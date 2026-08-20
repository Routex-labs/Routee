# 건물/층/매장/지도/그래프 단순 조회 Query 함수.
# - Session을 첫 인자로 받고 기존 API 응답과 동일한 dict를 조립한다.
# - None은 존재하지 않는 Building/Floor, 빈 list는 검색 결과 없음을 뜻한다.
# - HTTP 상태 코드 변환은 Router가 담당한다.

from __future__ import annotations

from collections.abc import Mapping
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.orm import Session, selectinload

from app.geo.georeference import GeoTransform
from app.geo.shared_polygon import split_shared_polygons
from app.geo.tiling import local_points_to_lnglat
from app.graph.revision import graph_revision
from app.models import Building, Edge, Floor, Node, Poi, Store
from app.repositories.geo_transform import fit_building_geo_transform
from app.repositories.place_detail_queries import classify_place_kind


# 전체 건물 요약 목록. selectinload로 층 목록 N+1을 제거한다.
def list_buildings(session: Session) -> list[dict[str, Any]]:
    buildings = session.scalars(select(Building).options(selectinload(Building.floors))).all()
    return [_to_building_summary(building) for building in buildings]


# 건물의 (층·대분류·소분류)별 매장 수. 없는 건물이면 None.
#
# 지도 위 카테고리 필터가 쓰는 목록이다. 이게 없을 때 클라이언트는 pill 목록과
# "이 층 N곳" 안내를 만들려고 **12개 층 GeoJSON을 통째로** 받았다(접근 로그 실측
# 130건). 정작 쓰는 건 세 문자열과 개수뿐인데 매장 폴리곤·좌표·navigation_graph가
# 전부 따라왔다.
#
# 개수를 서버가 세는 이유: 클라이언트가 세려면 결국 매장 목록을 받아야 한다.
# GROUP BY로 접으면 응답이 조합 수(실데이터 150행 안팎)로 고정된다.
def list_category_counts(session: Session, building_id: str) -> list[dict[str, Any]] | None:
    building = session.scalars(select(Building).where(Building.id == building_id)).one_or_none()
    if building is None:
        return None

    rows = session.execute(
        select(
            Floor.name,
            Store.category,
            Store.subcategory,
            func.count(Store.id),
        )
        .join(Store, Store.floor_id == Floor.id)
        .where(Floor.building_id == building_id)
        # 대분류가 없는 매장은 pill을 만들 수 없어 클라이언트가 어차피 버린다.
        # 여기서 걸러 응답을 더 줄인다.
        .where(Store.category.is_not(None))
        .group_by(Floor.name, Store.category, Store.subcategory)
        .order_by(Floor.name, Store.category, Store.subcategory)
    ).all()

    return [
        {
            "floor": floor_name,
            "category": category,
            "subcategory": subcategory,
            "count": count,
        }
        for floor_name, category, subcategory, count in rows
    ]


# 건물 상세(footprint 포함). 없으면 None.
def get_building(session: Session, building_id: str) -> dict[str, Any] | None:
    building = session.scalars(
        select(Building).where(Building.id == building_id).options(selectinload(Building.floors))
    ).one_or_none()
    if building is None:
        return None

    # 목록용 요약에 상세 전용 필드를 얹는다.
    summary = _to_building_summary(building)
    summary["area_m2"] = building.area_m2
    summary["perimeter_m"] = building.perimeter_m
    footprint_local = building.footprint_local_m or []
    summary["footprint_local_m"] = footprint_local
    # 야외 지도가 건물 폴리곤을 그리려면 wgs84 좌표가 필요하다. floor 응답과
    # 같은 아핀을 공유하도록 fit_building_geo_transform으로 매 요청 재피팅한다.
    transform = fit_building_geo_transform(session, building_id)
    summary["footprint_wgs84"] = _footprint_wgs84(footprint_local, transform)
    return summary


# 건물 내 매장 이름 검색. 건물이 없으면 None, 결과 없으면 빈 리스트.
def search_stores(
    session: Session,
    building_id: str,
    query: str,
) -> list[dict[str, Any]] | None:
    if session.get(Building, building_id) is None:
        return None

    stores = session.scalars(
        select(Store)
        .join(Floor, Store.floor_id == Floor.id)
        .where(Floor.building_id == building_id, Store.name.like(f"%{query}%"))
    ).all()

    transform = fit_building_geo_transform(session, building_id)
    return [_to_store_dict(store, transform) for store in stores]


# 자동완성 인덱스용 경량 매장 목록. 없는 건물이면 None, 매장이 없으면 빈 리스트.
#
# 클라이언트가 앱 시작 시 1회 받아 온디바이스 자동완성·초성 검색·오타 교정의 원본으로
# 쓴다(설계: docs/client/search-input-assist.md K절). 타이핑마다 서버를 왕복하지 않는
# 이유는 실내 매장 집합이 1640건으로 고정이라서다.
#
# search_stores()를 재사용하지 않는 이유: 그쪽은 폴리곤을 local_m·wgs84 두 벌로 실어
# 응답의 절반 이상이 자동완성에 안 쓰이는 좌표다. 여기서는 필요한 컬럼만 고른다.
#
# select(Store)가 아니라 컬럼을 나열하는 것도 같은 이유다. ORM 엔티티를 읽으면
# polygon(JSON 텍스트)까지 SQLite에서 꺼내 파싱한 뒤 버리게 된다 — 응답에는 안 나가도
# 조회 비용은 그대로 든다.
def list_store_index(session: Session, building_id: str) -> list[dict[str, Any]] | None:
    if session.get(Building, building_id) is None:
        return None

    rows = session.execute(
        select(
            Store.id,
            Store.name,
            Floor.id,
            Floor.name,
            Store.category,
            Store.subcategory,
            Store.entrance_node_id,
        )
        .join(Floor, Store.floor_id == Floor.id)
        .where(Floor.building_id == building_id)
        # 결정적 순서. 정렬을 명시하지 않으면 SQLite의 반환 순서에 의존하게 되고,
        # 같은 데이터에 대해 호출마다 순서가 달라지면 클라이언트가 인덱스를 캐시할 때
        # "내용은 같은데 다른 응답"으로 보인다. Floor.level 내림차순은 건물 요약
        # (_to_building_summary)의 층 순서(엘리베이터 버튼판, 위층이 앞)와 같고,
        # Store.id는 PK라 층 안에서 동점이 없다 — 두 키로 전순서가 정해진다.
        .order_by(Floor.level.desc(), Store.id)
    ).all()

    return [
        {
            "id": store_id,
            "name": name,
            # floor_id와 floor_name을 함께 준다. 라벨(B2)이 없으면 클라이언트가
            # 후보 한 줄을 그리려고 건물 응답의 층 목록과 다시 조인해야 하고, 반대로
            # id가 없으면 층 지도 응답(StoreResponse.floor_id)·현재 층 필터와 대조할
            # 키가 사라진다. 층은 12개뿐이라 두 벌을 실어도 반복 문자열 몇 KB다.
            # 자연어 질의 응답(dto/query.py QueryMatch)도 같은 이유로 둘 다 싣는다.
            "floor_id": floor_id,
            "floor_name": floor_name,
            "category": category,
            "subcategory": subcategory,
            # 상세와 **같은 분류**를 함께 준다. 이 색인에는 주차 787·에스컬레이터
            # 152·엘리베이터 68이 섞여 있어서(전체의 61%), "근처 매장"처럼 매장만
            # 골라야 하는 화면이 규칙을 다시 만들어야 한다. 클라이언트가 소분류
            # 목록을 들고 스스로 판정하면 그 목록이 서버와 갈라지는 날 "상세는 안
            # 열리는데 목록에는 있는" 상태가 조용히 생긴다.
            "kind": classify_place_kind(subcategory),
            # 후보를 고른 직후 길찾기로 넘어가는 도착 노드. 이게 없으면 이름을 다시
            # 질의해 매장을 찾아야 한다.
            "entrance_node_id": entrance_node_id,
        }
        for store_id, name, floor_id, floor_name, category, subcategory, entrance_node_id in rows
    ]


# 층 지도 데이터(footprint + 벡터 지도 + 매장 폴리곤 + POI). 없으면 None.
def get_floor_map(
    session: Session,
    building_id: str,
    floor_name: str,
) -> dict[str, Any] | None:
    floor = _find_floor(session, building_id, floor_name)
    if floor is None:
        return None

    # 한 층을 그리는 데 필요한 재료를 모은다.
    building = session.get(Building, building_id)
    stores = session.scalars(select(Store).where(Store.floor_id == floor.id)).all()
    pois = session.scalars(select(Poi).where(Poi.floor_id == floor.id)).all()
    transform = fit_building_geo_transform(session, building_id)
    shared_polygons = split_shared_polygons(stores)

    return {
        "floor": {"id": floor.id, "name": floor.name, "level": floor.level},
        "navigation_coordinate_system": "local_m",
        "map_calibration_version": floor.map_calibration_version,
        # 층 외곽선이 있으면 그것을 쓴다. 건물 footprint는 기준층(1F) 것이라
        # 전 층에 돌려쓰면 지하 주차장에도 1F 윤곽이 그려진다.
        "footprint_local_m": _floor_footprint(floor, building),
        "footprint_wgs84": _footprint_wgs84(_floor_footprint(floor, building), transform),
        # Flutter는 최초 층 지도 응답에서 이 그래프를 캐시해 클라이언트 다익스트라를 실행한다.
        "navigation_graph": _to_floor_graph_dict(session, floor),
        # 나눠 쓰는 폴리곤은 타일과 **같은 함수**로 잘라 보낸다. 강조 오버레이가 이
        # 값을 쓰는데 타일만 자르면 바닥 fill 위에 통짜 사각형이 얹힌다. 매장 검색에
        # 같은 계산을 걸지 않는 이유는 그쪽이 이름으로 거른 부분 집합이라 짝을 못
        # 찾기 때문이다(docs/backend/shared-polygon-split.md).
        "stores": [_to_store_dict(store, transform, shared_polygons.get(store.id)) for store in stores],
        "pois": [_to_poi_dict(poi, transform) for poi in pois],
        # 못 걷는 면(Floor.non_walkable_polygons_local_m)은 여기에 싣지 않는다.
        # 화면은 MVT 타일의 non_walkable 레이어로 그리므로 이 응답에 넣어도 아무도
        # 읽지 않고, B4는 기둥만 209개라 층을 열 때마다 폴리곤 수백 개가 헛돈다.
    }


# 층 길찾기 그래프(nodes + edges). 없으면 None.
def get_floor_graph(
    session: Session,
    building_id: str,
    floor_name: str,
) -> dict[str, Any] | None:
    floor = _find_floor(session, building_id, floor_name)
    if floor is None:
        return None
    return _to_floor_graph_dict(session, floor)


# 수직 이동 정책. 층 간 전이 간선 중 무엇을 그래프에 실을지 고른다.
#   auto      — 엘리베이터·에스컬레이터 모두(비용 모델이 층수에 따라 자동으로 고름)
#   elevator  — 엘리베이터만 (에스컬레이터 회피)
#   escalator — 에스컬레이터만
VERTICAL_POLICIES = ("auto", "elevator", "escalator")


def _vertical_allows(policy: str, transfer_mode: str | None) -> bool:
    # 층 내부 간선(transfer_mode=None)은 정책과 무관하게 항상 포함한다.
    if transfer_mode is None:
        return True
    if policy == "elevator":
        return transfer_mode == "elevator"
    if policy == "escalator":
        return transfer_mode == "escalator"
    return True  # auto


# 건물 전체 길찾기 그래프(전 층 nodes + 층 내부 간선 + 수직 전이 간선). 없으면 None.
# 층별 /graph와 달리 수직 전이 간선을 포함해 클라이언트가 층 간 경로를 계산할 수 있다.
# 전이 간선은 floor_id가 None이라 층별 조회에서는 빠지므로 여기서만 합류한다.
def get_building_graph(
    session: Session,
    building_id: str,
    vertical: str = "auto",
) -> dict[str, Any] | None:
    building = session.get(Building, building_id)
    if building is None:
        return None

    floors = session.scalars(select(Floor).where(Floor.building_id == building_id)).all()
    floor_ids = [floor.id for floor in floors]
    nodes = session.scalars(select(Node).where(Node.floor_id.in_(floor_ids))).all()
    node_ids = {node.id for node in nodes}

    # 층 내부 간선 + 이 건물 노드를 잇는 전이 간선(floor_id=None). 전이 간선은
    # 건물 스코프가 없으므로 **양 끝 노드가 모두** 이 건물 소속인 것만 고른다.
    # from만 확인하면 to가 다른 건물 노드인 간선이 딸려 와, 그래프에 없는 노드를
    # 가리키는 dangling 간선(to_floor_id=None)이 응답에 실린다.
    intra_edges = session.scalars(select(Edge).where(Edge.floor_id.in_(floor_ids))).all()
    transfer_edges = session.scalars(
        select(Edge).where(
            Edge.floor_id.is_(None),
            Edge.from_node_id.in_(node_ids),
            Edge.to_node_id.in_(node_ids),
        )
    ).all()
    edges = list(intra_edges) + [edge for edge in transfer_edges if _vertical_allows(vertical, edge.transfer_mode)]

    # 전이 간선의 양 끝 층을 노드에서 되찾기 위한 맵. 이미 읽어 둔 nodes를 재사용해
    # 간선마다 노드를 다시 조회하지 않는다.
    node_floor_ids = {node.id: node.floor_id for node in nodes}

    node_dicts = [_to_graph_node_dict(node) for node in nodes]
    edge_dicts = [_to_edge_dict(edge, node_floor_ids) for edge in edges]

    return {
        "building": {"id": building.id, "name": building.name},
        "vertical": vertical,
        # 이 그래프 내용의 체크섬. 클라이언트·타일 캐시(06번)가 무효화 키로 쓴다.
        # vertical 정책에 따라 간선이 달라지면 리비전도 달라진다(payload가 실제로 다르므로).
        "revision": graph_revision(node_dicts, edge_dicts),
        "floors": [{"id": floor.id, "name": floor.name} for floor in floors],
        "nodes": node_dicts,
        "edges": edge_dicts,
    }


# 층 지도와 독립 그래프 API가 공유하는 길찾기 레이어 응답을 조립한다.
def _to_floor_graph_dict(session: Session, floor: Floor) -> dict[str, Any]:
    nodes = session.scalars(select(Node).where(Node.floor_id == floor.id)).all()
    edges = session.scalars(select(Edge).where(Edge.floor_id == floor.id)).all()

    return {
        "floor": {"id": floor.id, "name": floor.name},
        "nodes": [_to_node_dict(node) for node in nodes],
        "edges": [_to_edge_dict(edge) for edge in edges],
    }


def _find_floor(
    session: Session,
    building_id: str,
    floor_name: str,
) -> Floor | None:
    return session.scalars(
        select(Floor).where(
            Floor.building_id == building_id,
            Floor.name == floor_name,
        )
    ).one_or_none()


# --- ORM 객체 → API 응답 dict 변환 ---


def _to_building_summary(building: Building) -> dict[str, Any]:
    # level은 실제 층 높이다 — 위로 갈수록 크고 지하는 음수다(6F=6 … 1F=1 … B6=-6).
    # 내림차순 정렬은 엘리베이터 버튼판과 같은 순서(6F→B6)를 만든다.
    #
    # 기본 층은 정렬 순서와 분리해 default_floor로 따로 내려준다. 예전에는
    # 클라이언트가 floors.first를 초기 층으로 썼는데, 지하층이 생기자 목록 첫
    # 항목이 최상층(6F)이 되어 앱이 6F로 열렸다.
    floors = sorted(building.floors, key=lambda floor: floor.level, reverse=True)

    return {
        "id": building.id,
        "name": building.name,
        "floors": [floor.name for floor in floors],
        "default_floor": _default_floor(floors),
    }


# 앱이 처음 열 층. 출입구가 있는 지상 1층이 기준이고, 지상층이 없으면 가장 위층으로
# 폴백한다(지하 전용 건물도 빈 값 없이 열리도록).
def _default_floor(floors: list[Floor]) -> str | None:
    if not floors:
        return None

    # 지상층이 있으면 그중 가장 낮은 층(=1F), 없으면 최상층으로 폴백.
    above_ground = [floor for floor in floors if floor.level >= 1]
    if above_ground:
        return min(above_ground, key=lambda floor: floor.level).name
    return max(floors, key=lambda floor: floor.level).name


def _to_node_dict(node: Node) -> dict[str, Any]:
    return {
        "id": node.id,
        "type": node.type,
        "name": node.name,
        "x_m": node.x_m,
        "y_m": node.y_m,
        "lat": node.lat,
        "lng": node.lng,
    }


# 건물 전체 그래프용 노드 dict. 층별 그래프와 달리 어느 층 노드인지 floor_id를 함께 준다
# (전 층 노드가 한 그래프에 섞이므로 클라이언트가 층별로 다시 나눌 수 있어야 한다).
def _to_graph_node_dict(node: Node) -> dict[str, Any]:
    return {**_to_node_dict(node), "floor_id": node.floor_id}


# node_floor_ids: 노드 id → 소속 층 id. 전이 간선은 edge.floor_id가 None이라
# 양 끝 층을 노드에서만 알 수 있다. 넘기지 않으면(단일 층 그래프) 간선의 층을 쓴다.
def _to_edge_dict(edge: Edge, node_floor_ids: Mapping[str, str] | None = None) -> dict[str, Any]:
    # 내부 from_node_id/to_node_id를 API에서는 짧은 from/to 키로 노출한다.
    if node_floor_ids is None:
        from_floor_id = to_floor_id = edge.floor_id
    else:
        from_floor_id = node_floor_ids.get(edge.from_node_id)
        to_floor_id = node_floor_ids.get(edge.to_node_id)

    return {
        "id": edge.id,
        "from": edge.from_node_id,
        "to": edge.to_node_id,
        # 실제 이동 거리(표시용)와 라우팅 비용(Dijkstra 가중치)은 다르다.
        # 전이 간선에서만 갈라지며, 층 내부 간선은 두 값이 같다.
        "length_m": edge.length_m,
        "cost_m": edge.cost_m,
        "bidirectional": edge.bidirectional,
        "geometry_local_m": edge.geometry or [],
        # 층 내부 간선은 None, 수직 전이 간선은 elevator/escalator. 클라이언트가
        # 경로 안내에서 "엘리베이터 이용" 같은 문구·아이콘을 고르는 근거.
        "transfer_mode": edge.transfer_mode,
        # 전이가 어느 층에서 어느 층으로 가는지. 클라이언트는 이 값과 to 노드를
        # 그대로 써야 하며, 이름으로 도착 노드를 다시 찾지 않는다.
        "from_floor_id": from_floor_id,
        "to_floor_id": to_floor_id,
    }


def _to_store_dict(
    store: Store,
    transform: GeoTransform | None,
    polygon_local_m: list[dict[str, float]] | None = None,
) -> dict[str, Any]:
    # 한 폴리곤을 둘이 나눠 쓰는 자리는 [polygon_local_m]으로 자기 칸을 받는다. 넘어오지
    # 않으면 원본이다(docs/backend/shared-polygon-split.md).
    polygon = polygon_local_m if polygon_local_m is not None else store.polygon
    # 실좌표 앵커가 없는 건물이면 transform이 없어 wgs84 필드는 null로 나간다.
    centroid_wgs84 = None
    entrance_wgs84 = None
    polygon_wgs84 = None
    if transform is not None:
        lat, lng = transform.apply(store.centroid_x_m, store.centroid_y_m)
        centroid_wgs84 = {"lat": lat, "lng": lng}
        # 입구 좌표는 원본에서 **다비오 공식 POI 핀 위치**다
        # (scripts/transform/build_studio_from_dabeeo.py의 `poi["position"]`).
        # 한 폴리곤에 여러 매장이 붙은 자리에서 centroid는 전부 같은 값이지만
        # 이 핀은 매장마다 다르므로, 화면이 라벨을 흩을 때 쓰는 유일한 근거다
        # (client/lib/domain/store_label_anchor.dart). 클라이언트는 이 키를
        # 예전부터 읽고 있었는데 서버가 보내지 않아 죽은 폴백이었다.
        if store.entrance_x_m is not None and store.entrance_y_m is not None:
            entrance_lat, entrance_lng = transform.apply(store.entrance_x_m, store.entrance_y_m)
            entrance_wgs84 = {"lat": entrance_lat, "lng": entrance_lng}
        if polygon:
            polygon_wgs84 = [{"lng": lng, "lat": lat} for lng, lat in local_points_to_lnglat(polygon, transform)]

    return {
        "id": store.id,
        "floor_id": store.floor_id,
        "name": store.name,
        "category": store.category,
        "subcategory": store.subcategory,
        "centroid_local_m": {"x": store.centroid_x_m, "y": store.centroid_y_m},
        "centroid_wgs84": centroid_wgs84,
        "polygon_wgs84": polygon_wgs84,
        "entrance_local_m": _optional_point(
            store.entrance_x_m,
            store.entrance_y_m,
            label=f"매장 {store.id} 입구",
        ),
        "entrance_wgs84": entrance_wgs84,
        "entrance_node_id": store.entrance_node_id,
        "polygon_local_m": polygon,
    }


def _to_poi_dict(poi: Poi, transform: GeoTransform | None) -> dict[str, Any]:
    position_wgs84 = None
    if transform is not None:
        lat, lng = transform.apply(poi.x_m, poi.y_m)
        position_wgs84 = {"lat": lat, "lng": lng}

    return {
        "id": poi.id,
        "type": poi.type,
        "name": poi.name,
        "position_local_m": {"x": poi.x_m, "y": poi.y_m},
        "position_wgs84": position_wgs84,
        "linked_node_id": poi.linked_node_id,
    }


# 층 자체 외곽선 우선, 없으면 건물 대표 외곽으로 폴백한다.
def _floor_footprint(floor: Floor, building: Building | None) -> list[dict]:
    if floor.footprint_local_m:
        return floor.footprint_local_m
    return (building.footprint_local_m or []) if building else []


def _footprint_wgs84(
    footprint: list[dict],
    transform: GeoTransform | None,
) -> list[dict[str, float]] | None:
    if transform is None or not footprint:
        return None

    points = local_points_to_lnglat(footprint, transform)
    return [{"lng": lng, "lat": lat} for lng, lat in points]


# 선택 좌표는 x/y 모두 NULL일 때만 없음으로 처리하고, 한쪽만 있으면 오류다.
def _optional_point(
    x: float | None,
    y: float | None,
    *,
    label: str,
) -> dict[str, float] | None:
    if x is None and y is None:
        return None
    if x is None or y is None:
        raise ValueError(f"{label} 좌표 값이 불완전합니다.")
    return {"x": x, "y": y}
