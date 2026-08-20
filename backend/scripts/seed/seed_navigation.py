# Studio 어댑터가 만든 표준 dict를 ORM 객체로 변환한다.
# DDL과 트랜잭션 경계는 각각 reset_database와 studio_adapter가 담당한다.
# 이 모듈은 파일을 직접 읽지 않고 한 건물/층 데이터를 Session에 추가하기만 한다.

from __future__ import annotations

from math import hypot

from sqlalchemy.orm import Session

from app.models import (
    Building,
    Edge,
    Floor,
    Node,
    Poi,
    Store,
)


# geometry 또는 length가 누락된 입력을 양 끝 노드 좌표로 보완한다.
# Studio의 geometry.local_m을 우선 사용하고, 없으면 양 끝 노드 좌표로 직선을
# 만든다. geometry_local_m은 테스트용 표준 dict도 허용한다.
def edge_geometry_and_length(
    edge: dict,
    node_points: dict[str, dict[str, float]],
) -> tuple[list[dict], float]:
    geometry = edge.get("geometry_local_m")
    if geometry is None:
        raw = edge.get("geometry")
        if isinstance(raw, dict):
            geometry = raw.get("local_m")
        elif isinstance(raw, list):
            geometry = raw
    if not geometry:
        geometry = [
            dict(node_points[edge["from"]]),
            dict(node_points[edge["to"]]),
        ]
    length_m = edge.get("length_m")
    if length_m is None:
        length_m = sum(
            hypot(current["x"] - previous["x"], current["y"] - previous["y"])
            for previous, current in zip(geometry, geometry[1:])
        )
    return geometry, length_m


# Studio 표준 dict 한 건물/층을 Session에 추가한다(commit은 호출자).
def add_dataset(session: Session, data: dict) -> None:
    building_data = data["building"]
    floor_data = building_data["floor"]
    building_id = building_data["id"]
    floor_id = floor_data["id"]
    node_points = {node["id"]: node["position"]["local_m"] for node in data["nodes"]}

    # 같은 건물의 여러 층을 이어서 시드할 때 Building은 한 번만 생성한다.
    # autoflush=False이므로 직후 flush로 identity map에 올려 다음 층 조회가 찾도록 한다.
    if session.get(Building, building_id) is None:
        session.add(
            Building(
                id=building_id,
                name=building_data["name"],
                area_m2=building_data.get("area_m2"),
                perimeter_m=building_data.get("perimeter_m"),
                footprint_local_m=building_data.get("footprint_local_m"),
            )
        )
        session.flush()
    session.add(
        Floor(
            id=floor_id,
            building_id=building_id,
            name=floor_data["name"],
            level=floor_data["level"],
            map_calibration_version=building_data.get("map_calibration_version", "unversioned"),
            footprint_local_m=floor_data.get("footprint_local_m"),
            non_walkable_polygons_local_m=floor_data.get("non_walkable_polygons_local_m"),
        )
    )

    session.add_all(
        Node(
            id=node["id"],
            floor_id=floor_id,
            type=node["type"],
            name=node.get("name"),
            x_m=node["position"]["local_m"]["x"],
            y_m=node["position"]["local_m"]["y"],
            lat=(node["position"].get("wgs84") or {}).get("lat"),
            lng=(node["position"].get("wgs84") or {}).get("lng"),
            source_x=(node["position"].get("source") or {}).get("x"),
            source_y=(node["position"].get("source") or {}).get("y"),
        )
        for node in data["nodes"]
    )

    edges: list[Edge] = []
    for edge in data["edges"]:
        geometry, length_m = edge_geometry_and_length(edge, node_points)
        edges.append(
            Edge(
                id=edge["id"],
                floor_id=floor_id,
                from_node_id=edge["from"],
                to_node_id=edge["to"],
                length_m=length_m,
                # 층 내부 간선은 실제 거리가 곧 라우팅 비용이다. 둘이 갈라지는 것은
                # 수직 전이 간선뿐이다(add_transfer_edges 참고).
                cost_m=length_m,
                bidirectional=edge.get("bidirectional", True),
                geometry=geometry,
            )
        )
    session.add_all(edges)

    session.add_all(
        Store(
            id=store["id"],
            floor_id=floor_id,
            name=store["name"],
            category=store.get("category"),
            subcategory=store.get("subcategory"),
            centroid_x_m=store["centroid"]["local_m"]["x"],
            centroid_y_m=store["centroid"]["local_m"]["y"],
            entrance_x_m=(store.get("entrance_local_m") or {}).get("x"),
            entrance_y_m=(store.get("entrance_local_m") or {}).get("y"),
            entrance_node_id=store.get("entrance_node_id"),
            polygon=store.get("polygon_local_m"),
            # 파생·오버레이 계산은 이 모듈 밖(Wave 2)에서 하고, 여기서는 dict에
            # 이미 실려 온 값을 컬럼에 그대로 옮기기만 한다. 키가 없으면 None.
            search_facets=store.get("search_facets"),
        )
        for store in data.get("stores", [])
    )
    session.add_all(
        Poi(
            id=poi["id"],
            floor_id=floor_id,
            type=poi["type"],
            name=poi.get("name"),
            x_m=poi["position"]["local_m"]["x"],
            y_m=poi["position"]["local_m"]["y"],
            linked_node_id=poi.get("linked_node_id"),
        )
        for poi in data.get("pois", [])
    )


# 층을 잇는 수직 전이 간선을 Session에 추가한다(commit은 호출자).
# 층 내부 간선과 달리 floor_id는 None이다. 단일 층 조회는 floor_id로 필터되므로
# 전이 간선은 자연히 제외되고, 건물 전체 경로 탐색에서만 쓰인다.
def add_transfer_edges(session: Session, transfers: list[dict]) -> None:
    session.add_all(
        Edge(
            id=transfer["id"],
            floor_id=None,
            from_node_id=transfer["from"],
            to_node_id=transfer["to"],
            # 전이 간선은 실제 이동 거리(length_m)와 라우팅 비용(cost_m)이 다르다.
            # 비용은 수단 선호를 인코딩한 튜닝값이라 표시 거리로 쓰면 안 된다.
            length_m=transfer["length_m"],
            cost_m=transfer["cost_m"],
            bidirectional=transfer.get("bidirectional", True),
            geometry=None,
            transfer_mode=transfer["mode"],
        )
        for transfer in transfers
    )
