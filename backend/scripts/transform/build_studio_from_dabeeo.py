"""다베오 공식 payload를 Studio 층 JSON으로 변환한다(12개 층).

기존 파이프라인의 문제:
  - 1F만 다베오에서 받고 B2는 스크린샷을 40px 격자로 근사했다.
  - 층마다 좌표 변환을 따로 피팅해 층별 비등방 배율(1.39~2.77)이 생겼고,
    이를 6-DOF 아핀으로 이어붙이며 shear가 발생했다.
  - 기존 노드 wgs84는 그 비등방 변환의 산물이라 건물이 북향으로 눕는다
    (실측 회전 52.578°, 기존 데이터 0.04°).

이 변환기는 다베오 원본 좌표계를 **모든 층이 그대로 공유**하게 한다. 층 정렬이
필요 없으므로 shear도 이방성도 구조적으로 발생할 수 없다.

미해결:
  절대 배율. payload의 scaleCm=10/scalePx=1은 0.1m/unit을 뜻하지만, 그러면 1F
  LEVEL section이 167x98m(16182m²)로 VWorld 실측 7062m²와 맞지 않는다. 형상과
  층간 정합은 배율과 무관하므로 우선 0.1을 쓰고 SCALE_M_PER_UNIT 한 곳만 고치면
  전체가 따라오도록 둔다.
"""

from __future__ import annotations

import json
from math import hypot
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
OUT = REPO / "backend/resources/studio/thehyundai-seoul-dabeeo"

# payload.scaleCm=10.0, scalePx=1 → 1 unit = 10cm. 등방.
SCALE_M_PER_UNIT = 0.1

# 다베오 층 이름 -> 우리 층 코드. level은 위층일수록 커지는 단조 정수로 둔다
# (vertical_transfers가 level 정렬로 인접 층을 잇는다).
FLOOR_LEVELS = {
    "6F": 6,
    "5F": 5,
    "4F": 4,
    "3F": 3,
    "2F": 2,
    "1F": 1,
    "B1": -1,
    "B2": -2,
    "B3": -3,
    "B4": -4,
    "B5": -5,
    "B6": -6,
}

# node.transCode -> 우리 노드 타입. 나머지는 통로 교차점이다.
TRANS_CODE_TYPES = {
    "OB-ELEVATOR": "elevator",
    "OB-ESCALATOR_UP": "escalator",
    "OB-ESCALATOR_DOWN": "escalator",
    "OB-STAIRS": "stairs",
}

# object.attributeCode -> (category, subcategory). 다베오는 먹거리 매장도 "시설
# 속성"으로 태깅하므로(OB-CAFE/OB-RESTAURANT), 속성이 붙었다는 이유만으로 전부
# 편의시설로 넣으면 스타벅스 리저브·런던베이글 뮤지엄 같은 매장이 편의시설이 된다.
# 대분류를 속성별로 명시해 카페는 카페로, 식당은 음식점으로 떨어지게 한다.
#
# 값은 전부 사용자가 실제로 쓰는 말로 적는다. 유통업계 용어인 "식음료"를 대분류
# 하나로 두면 사용자가 그 말로 찾지 않고, 소분류를 영어 원본(escalator·restroom)
# 그대로 두면 화면·검색 라벨에 영어가 그대로 새어 나온다. OB-OTHER_FACILITIES는
# "생활편의"다 — "편의시설"로 쓰면 대분류와 같아져 "편의시설 > 편의시설"이 된다.
#
# 주의: OB-RESTAURANT는 거친 태그라 레스토랑/카페·베이커리/식품·그로서리를 구분하지
# 못한다. 여기서는 가장 흔한 값을 기본으로 주고, 매장별 세부 분류는 생성된
# resources/studio/.../stores_{층}.json에서 손으로 다듬는다(재생성 시 재적용 필요).
FACILITY_ATTRIBUTES = {
    "OB-ELEVATOR": ("편의시설", "엘리베이터"),
    "OB-ESCALATOR_UP": ("편의시설", "에스컬레이터"),
    "OB-ESCALATOR_DOWN": ("편의시설", "에스컬레이터"),
    "OB-TOILET": ("편의시설", "화장실"),
    "OB-CAFE": ("카페", "카페·베이커리"),
    "OB-RESTAURANT": ("음식점", "레스토랑"),
    "OB-OTHER_FACILITIES": ("편의시설", "생활편의"),
}


METERS_PER_DEGREE_LAT = 111320.0
VWORLD_BUILDING = REPO / "thehyundai_indoor_navigation_dataset/navigation_map_parts/building.json"


def floor_code(name: str) -> str:
    return name.lower()


# local_m -> wgs84 아핀을 만든다.
#
# 회전은 payload의 georeferencingRotate(52.578°)를 쓴다. 기존 데이터는 이 값을
# 반영하지 않아 건물이 북향으로 누워 있었다. 위치는 VWorld 실측 건물 중심에
# 맞춘다 — georeferencing 4개 코너로 풀면 배율이 0.1024로 나와 공식 scaleCm과
# 2.4% 어긋나므로, 검증된 회전·배율은 쓰고 평행이동만 실측으로 정한다.
#
# status는 unverified로 남긴다. 절대 배율이 확정되기 전까지 이 변환은 표시용이다.
def georeference(payload: dict, reference_floor: dict) -> dict:
    import math

    rotate = math.radians(float(payload.get("georeferencingRotate") or 0.0))
    building = json.loads(VWORLD_BUILDING.read_text(encoding="utf-8"))["building"]
    ring = building["exterior_geojson"]["coordinates"][0]
    target_lng = sum(p[0] for p in ring) / len(ring)
    target_lat = sum(p[1] for p in ring) / len(ring)

    footprint = floor_footprint(reference_floor)
    source = centroid(footprint)

    cos_lat = math.cos(math.radians(target_lat))
    cos_r, sin_r = math.cos(rotate), math.sin(rotate)

    # local_m을 회전시켜 동/북 미터로, 다시 경위도로. y축은 화면 아래가 +이므로 북쪽은 -y다.
    a = cos_r / (METERS_PER_DEGREE_LAT * cos_lat)
    b = sin_r / (METERS_PER_DEGREE_LAT * cos_lat)
    c = sin_r / METERS_PER_DEGREE_LAT
    d = -cos_r / METERS_PER_DEGREE_LAT
    return {
        "type": "affine_2d",
        "matrix": [
            [a, b, target_lng - (a * source["x"] + b * source["y"])],
            [c, d, target_lat - (c * source["x"] + d * source["y"])],
            [0, 0, 1],
        ],
        "input_axes": ["x", "y"],
        "output_axes": ["lng", "lat"],
        "rotate_deg": payload.get("georeferencingRotate"),
        "anchor": "vworld_building_centroid",
        "status": "unverified",
    }


def text_ko(values: list[dict] | None) -> str | None:
    for value in values or []:
        if value.get("lang") == "ko" and value.get("text"):
            return " ".join(value["text"].split())
    return None


def to_local(point: dict) -> dict[str, float]:
    return {
        "x": round(float(point.get("x", 0.0)) * SCALE_M_PER_UNIT, 6),
        "y": round(float(point.get("y", 0.0)) * SCALE_M_PER_UNIT, 6),
    }


def source_point(point: dict) -> dict[str, float]:
    return {"x": round(float(point.get("x", 0.0)), 6), "y": round(float(point.get("y", 0.0)), 6)}


def polygon(points: list[dict] | None) -> list[dict[str, float]]:
    return [to_local(p) for p in points or [] if "x" in p and "y" in p]


def polygon_area(points: list[dict]) -> float:
    n = len(points)
    if n < 3:
        return 0.0
    total = sum(points[i]["x"] * points[(i + 1) % n]["y"] - points[(i + 1) % n]["x"] * points[i]["y"] for i in range(n))
    return abs(total) / 2


def centroid(points: list[dict]) -> dict[str, float]:
    if not points:
        return {"x": 0.0, "y": 0.0}
    return {
        "x": round(sum(p["x"] for p in points) / len(points), 6),
        "y": round(sum(p["y"] for p in points) / len(points), 6),
    }


# 층 외곽선: LEVEL section이 층 전체 윤곽이다. OB-OUTLINE은 1F에서 10~12m²짜리
# 장식 객체라 외곽선으로 쓸 수 없다.
def floor_footprint(floor: dict) -> list[dict[str, float]]:
    levels = [s for s in floor.get("sections") or [] if s.get("title") == "LEVEL"]
    pool = levels or (floor.get("sections") or [])
    if not pool:
        return []
    best = max(pool, key=lambda s: polygon_area(polygon(s.get("coordinates"))))
    return polygon(best.get("coordinates"))


# POI가 안 붙은 도형 중 "걸어다닐 수 없는 면"으로 그릴 것들.
#
# 원본은 매장·시설을 POI로 표시하는데, 아트리움 구멍·기둥·조경처럼 **이름이 없는
# 것**에는 POI를 달지 않는다. 그래서 POI만 훑던 임포터가 이 도형들을 통째로
# 버리고 있었다 — 실측: 보이드 2~6F 33개(6F 737m², 2~5F 각 1,700~1,810m²),
# 기둥 B3~B6 763개, 1F 폭포정원 곡선 2개.
#
# `kind`는 화면이 색을 가르는 데 쓴다. 자세한 것은
# `docs/client/kakao-map-indoor-observation.md` V·W절.
NON_WALKABLE_ATTRIBUTES = {
    "OB-VOID_AREA": "void",  # 아트리움 구멍. 2F부터 뚫린다(1F·지하는 0개다)
    "OB-PILLAR": "pillar",  # 지하 주차장 기둥
    "OB-OTHER_FACILITY": "feature",  # 조경·설치물. 1F WATERFALL GARDEN이 여기다
    # **에스컬레이터 도형은 POI가 떨어져 나갔다.** v180.4에서는 층마다 16개가
    # POI를 달고 매장으로 들어왔는데 v182.8에서는 4개만 남았다 — 도형은 그대로
    # 있고 연결만 끊겼다. 여기서 줍지 않으면 초록 에스컬레이터 그림이 층마다
    # 12개씩 사라진다(노드는 안 바뀌어 길찾기는 무관하다).
    "OB-ESCALATOR_UP": "escalator",
    "OB-ESCALATOR_DOWN": "escalator",
    "OB-ESCALATOR": "escalator",  # 접미사 없는 코드. 4F에 2개뿐이라 놓치기 쉽다
}

# 전체 재생성 때만 줍는 속성. `--non-walkable-only`는 매장·노드를 v180.4로 두는데,
# 그 버전 stores_*.json에는 이미 에스컬레이터 매장이 층당 6~16개 폴리곤과 함께
# 있다. 실측: v182.8 도형 121개 중 109개가 그 매장 중심점 위에 그대로 겹치고,
# 남는 12개(5F·4F·B2 각 2, B6 6)도 기존 도형 바로 옆(최근접 0.00m)에 붙는다.
# 즉 얹으면 초록 에스컬레이터가 회색 조각에 덮인다 — 모드 단위로 통째로 뺀다.
REGENERATION_ONLY_KINDS = frozenset({"escalator"})


# 점이 폴리곤 안에 있나(짝수-홀수 ray casting). 경계 위는 결과가 갈릴 수 있으나
# 여기 쓰임(매장 중심점)에서는 경계에 정확히 걸리는 사례가 없다.
def point_in_polygon(ring: list[dict[str, float]], px: float, py: float) -> bool:
    inside = False
    n = len(ring)
    for i in range(n):
        ax, ay = ring[i]["x"], ring[i]["y"]
        bx, by = ring[(i + 1) % n]["x"], ring[(i + 1) % n]["y"]
        if (ay > py) != (by > py) and px < ax + (py - ay) / (by - ay) * (bx - ax):
            inside = not inside
    return inside


def non_walkable_shapes(
    floor: dict,
    blocked_points: list[dict[str, float]],
    *,
    skip_kinds: frozenset[str] = frozenset(),
) -> list[dict]:
    """POI가 가리키지 않는 도형 중 [NON_WALKABLE_ATTRIBUTES]에 해당하는 것.

    POI가 달린 도형은 이미 매장·시설로 들어가므로 제외한다 — 안 빼면 같은 칸이
    매장과 "못 걷는 면" 두 벌로 그려진다.

    [blocked_points]는 "가려지면 안 되는 점" 목록이다. 매장 마커·라벨이 찍히는
    자리(폴리곤이 있는 매장의 centroid_local_m)를 넘기면 그 점을 품는 도형이
    빠진다 — 임계값 없는 기하 판정이고, 검산 결과는
    `docs/client/kakao-map-indoor-observation.md`에 있다.
    """
    linked = {poi.get("objectId") for poi in (floor.get("pois") or []) if poi.get("objectId")}
    shapes: list[dict] = []
    for obj in floor.get("objects") or []:
        if obj.get("id") in linked:
            continue
        kind = NON_WALKABLE_ATTRIBUTES.get(obj.get("attributeCode") or "")
        if kind is None or kind in skip_kinds:
            continue
        shape = polygon(obj.get("coordinates"))
        # 면이 되려면 점이 셋은 있어야 한다. 원본에 선분만 있는 항목이 섞인다.
        if len(shape) < 3:
            continue
        if any(point_in_polygon(shape, p["x"], p["y"]) for p in blocked_points):
            continue
        shapes.append({"id": obj["id"], "kind": kind, "polygon_local_m": shape})
    return shapes


def build_floor(payload: dict, floor: dict, geo: dict) -> tuple[dict, dict]:
    name = text_ko(floor.get("name")) or floor["id"]
    code = floor_code(name)
    floor_id = floor["id"]
    level = FLOOR_LEVELS.get(name, 0)

    objects = {o["id"]: o for o in floor.get("objects") or []}

    nodes: list[dict] = []
    for node in floor.get("nodes") or []:
        trans = node.get("transCode")
        node_type = TRANS_CODE_TYPES.get(trans or "", "junction")
        title = node.get("title")
        record = {
            "id": node["id"],
            "type": node_type,
            "position": {
                "source": source_point(node.get("position") or {}),
                "local_m": to_local(node.get("position") or {}),
            },
            "source": {"kind": "dabeeo_node", "trans_code": trans, "object_ids": node.get("objectIds") or []},
        }
        if title and title != "NODE":
            record["name"] = title
        nodes.append(record)

    node_ids = {n["id"] for n in nodes}
    edges: list[dict] = []
    transfers: list[dict] = []
    seen: set[tuple[str, str]] = set()
    for node in floor.get("nodes") or []:
        for edge in node.get("edges") or []:
            target = edge.get("nodeId")
            if not target:
                continue
            key = tuple(sorted((node["id"], target)))
            if key in seen:
                continue
            seen.add(key)
            linked = edge.get("linkedFloorId")
            # distance가 없는 간선이 있다. 두 노드 좌표로 직접 잰다.
            raw_distance = edge.get("distance")
            if raw_distance is None:
                other = next((n for n in floor.get("nodes") or [] if n["id"] == target), None)
                here = node.get("position") or {}
                there = (other or {}).get("position") or {}
                raw_distance = hypot(
                    float(there.get("x", here.get("x", 0.0))) - float(here.get("x", 0.0)),
                    float(there.get("y", here.get("y", 0.0))) - float(here.get("y", 0.0)),
                )
            length = round(float(raw_distance) * SCALE_M_PER_UNIT, 6)
            payload_edge = {
                "id": edge.get("id") or f"{node['id']}__{target}",
                "from": node["id"],
                "to": target,
                "bidirectional": True,
                "length_m": length,
                "passable": bool(edge.get("passable", True)),
                "source": {"kind": "dabeeo_edge"},
            }
            if linked and linked != floor_id:
                payload_edge["linked_floor_id"] = linked
                transfers.append(payload_edge)
            elif target in node_ids:
                edges.append(payload_edge)

    # POI를 매장/시설로, 연결된 object 폴리곤을 도형으로 쓴다.
    stores: list[dict] = []
    polygons: list[list[dict]] = []
    metadata: list[dict] = []
    for poi in floor.get("pois") or []:
        title = text_ko(poi.get("titleByLanguages")) or poi.get("title")
        if not title:
            continue
        obj = objects.get(poi.get("objectId") or "")
        shape = polygon((obj or {}).get("coordinates")) if obj else []
        attribute = (obj or {}).get("attributeCode")
        # 속성이 없는 일반 리테일은 대분류를 알 수 없어 "매장"으로 두고,
        # 실제 카테고리는 시드 단계의 store_categories*.json 오버라이드가 채운다.
        category, subcategory = FACILITY_ATTRIBUTES.get(attribute or "", ("매장", "매장"))
        store_id = poi["id"]
        record = {
            "id": store_id,
            "name": title,
            "category": category,
            "subcategory": subcategory,
            "floor_id": floor_id,
            "entrance_node_id": None,
            "entrance_local_m": to_local(poi.get("position") or {}),
            "entrance_wgs84": None,
            "centroid_local_m": centroid(shape) if shape else to_local(poi.get("position") or {}),
            "polygon_local_m": shape,
            "match": {"method": "dabeeo_official_poi", "object_id": poi.get("objectId"), "review_required": False},
        }
        stores.append(record)
        if shape:
            polygons.append(shape)
            metadata.append(
                {
                    "id": store_id,
                    "name": title,
                    "category": record["category"],
                    "subcategory": record["subcategory"],
                    "entrance_node_id": None,
                    "centroid_local_m": record["centroid_local_m"],
                }
            )

    # 폴리곤 없는 매장은 앵커에서 뺀다. centroid가 POI 위치로 폴백하는데,
    # 2~4F `박선기 작품`·`서혜영 작품`이 아트리움 한가운데 떠 있는 라벨이라
    # 넣으면 멀쩡한 보이드 4개(241~297m²)가 억울하게 잘려 나간다.
    anchors = [s["centroid_local_m"] for s in stores if s["polygon_local_m"]]
    non_walkable = non_walkable_shapes(floor, anchors)
    footprint = floor_footprint(floor)
    graph = {
        "schema_version": "0.1.0",
        "building_id": "thehyundai-seoul",
        "floor": {"id": floor_id, "name": name, "level": level, "order": floor.get("order", level)},
        "generated_from": {
            "provider": "dabeeo_official_map",
            "map_id": payload.get("id"),
            "map_version": payload.get("versionString"),
            "credentials_persisted": False,
        },
        "coordinate_system": {
            "type": "dabeeo_map_units_scaled",
            "calibration_version": f"dabeeo-official-v{payload.get('versionString')}",
            "source_map_size": payload.get("size"),
            "scale": {"x_m_per_source_unit": SCALE_M_PER_UNIT, "y_m_per_source_unit": SCALE_M_PER_UNIT},
            "affine_transforms": {
                "source_to_local_m": {
                    "type": "affine_2d",
                    "matrix": [[SCALE_M_PER_UNIT, 0, 0], [0, SCALE_M_PER_UNIT, 0], [0, 0, 1]],
                    "input_axes": ["x", "y"],
                    "output_axes": ["x", "y"],
                },
                "local_m_to_wgs84": geo,
            },
            "georeferencing": {
                "west": payload.get("georeferencingWest"),
                "south": payload.get("georeferencingSouth"),
                "east": payload.get("georeferencingEast"),
                "north": payload.get("georeferencingNorth"),
                "rotate_deg": payload.get("georeferencingRotate"),
                "status": "unverified",
            },
            "notes": [
                "모든 층이 다베오 원본 좌표계를 공유한다. 층 정렬이 필요 없으므로 shear/이방성이 생기지 않는다.",
                "절대 배율 미검증: scaleCm=10 기준 1F LEVEL이 167x98m인데 VWorld 실측은 126x68m다.",
            ],
        },
        "nodes": nodes,
        "edges": edges,
        "vertical_transfer_edges": transfers,
        "store_polygons_local_m": polygons,
        "store_polygons_imported": True,
        "store_polygon_metadata": metadata,
        "non_walkable_polygons_local_m": non_walkable,
        "manual_review_candidates": [],
        "counts": {
            "nodes": len(nodes),
            "edges": len(edges),
            "transfers": len(transfers),
            "stores": len(stores),
            "polygons": len(polygons),
            "non_walkable": len(non_walkable),
        },
        "building_footprint_local_m": footprint,
    }
    store_payload = {
        "building_id": "thehyundai-seoul",
        "floor": graph["floor"],
        "coordinate_frame": "dabeeo_local_m",
        "stores": stores,
        "unmatched": [],
        "summary": {
            "source": "dabeeo official map",
            "store_count": len(stores),
            "polygon_count": len(polygons),
            "review_required": False,
        },
    }
    return code, {"graph": graph, "stores": store_payload}


# 기존 층 JSON에 "못 걷는 면"만 얹는다. 매장·노드·간선은 한 바이트도 안 건드린다.
#
# 왜 전체 재생성을 안 하나: 캐시본은 v182.8이고 저장소는 v180.4다. 전부 갈면
# 손으로 단 검색 facet 8건이 무효가 되고(B1 매장이 실제로 바뀌었다) 에스컬레이터
# POI가 떨어져 나가 층당 16개→4개가 된다. 자세한 것은
# `docs/client/kakao-map-indoor-observation.md` 4절.
def rewrite_non_walkable(payload: dict) -> None:
    version = payload.get("versionString")
    print(f"{'층':5s}{'보이드':>7s}{'기둥':>6s}{'조경':>6s}{'제외':>6s}  합계")
    for floor in payload.get("floors") or []:
        name = text_ko(floor.get("name")) or floor["id"]
        code = floor_code(name)
        graph_path = OUT / f"{code}.json"
        stores_path = OUT / f"stores_{code}.json"
        if not graph_path.exists() or not stores_path.exists():
            raise SystemExit(f"{code}: 기존 층 JSON이 없다 — 전체 재생성이 먼저다")

        graph = json.loads(graph_path.read_text(encoding="utf-8"))
        # 층 id가 어긋나면 다른 건물이거나 재편성된 payload다. 조용히 덮어쓰면
        # 엉뚱한 층에 도형이 얹힌다.
        if graph["floor"]["id"] != floor["id"]:
            raise SystemExit(f"{code}: 층 id 불일치 {graph['floor']['id']} != {floor['id']}")

        # 앵커는 stores_{층}.json이 단일 출처다. 같은 파일의 store_polygon_metadata는
        # 시드가 읽지 않고 실제로 어긋나 있다(3F 기준 97개 vs 109개).
        stores = json.loads(stores_path.read_text(encoding="utf-8"))["stores"]
        anchors = [s["centroid_local_m"] for s in stores if s.get("polygon_local_m")]
        shapes = non_walkable_shapes(floor, anchors, skip_kinds=REGENERATION_ONLY_KINDS)

        graph["non_walkable_polygons_local_m"] = shapes
        graph["counts"] = {**graph.get("counts", {}), "non_walkable": len(shapes)}
        # 두 버전이 섞여 있다는 사실을 파일이 스스로 말하게 한다.
        graph["non_walkable_source"] = {
            "provider": "dabeeo_official_map",
            "map_id": payload.get("id"),
            "map_version": version,
            "mode": "non_walkable_only",
        }
        graph_path.write_text(json.dumps(_ordered(graph), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

        tally = {"void": 0, "pillar": 0, "feature": 0}
        for shape in shapes:
            tally[shape["kind"]] = tally.get(shape["kind"], 0) + 1
        skipped = len(non_walkable_shapes(floor, [], skip_kinds=REGENERATION_ONLY_KINDS)) - len(shapes)
        print(f"{code:5s}{tally['void']:7d}{tally['pillar']:6d}{tally['feature']:6d}{skipped:6d}  {len(shapes)}")
    print(f"\n갱신 위치: {OUT} (매장·노드·간선 무변경, non_walkable_source=v{version})")


# 전체 재생성이 쓰는 키 순서로 되돌린다. 그냥 대입하면 새 키가 파일 끝에 붙어
# 나중에 전체 재생성했을 때 통째로 diff가 난다.
def _ordered(graph: dict) -> dict:
    order = [
        "schema_version",
        "building_id",
        "floor",
        "generated_from",
        "non_walkable_source",
        "coordinate_system",
        "nodes",
        "edges",
        "vertical_transfer_edges",
        "store_polygons_local_m",
        "store_polygons_imported",
        "store_polygon_metadata",
        "non_walkable_polygons_local_m",
        "manual_review_candidates",
        "counts",
        "building_footprint_local_m",
    ]
    ranked = {key: index for index, key in enumerate(order)}
    return {key: graph[key] for key in sorted(graph, key=lambda k: (ranked.get(k, len(order)), k))}


def main(payload_path: Path) -> None:
    payload = json.loads(payload_path.read_text(encoding="utf-8"))
    OUT.mkdir(parents=True, exist_ok=True)
    reference = next(f for f in payload["floors"] if text_ko(f.get("name")) == "1F")
    geo = georeference(payload, reference)
    print(f"{'층':5s}{'노드':>6s}{'간선':>7s}{'층간':>6s}{'매장':>6s}{'폴리곤':>7s}  외곽선")
    for floor in payload.get("floors") or []:
        code, built = build_floor(payload, floor, geo)
        (OUT / f"{code}.json").write_text(
            json.dumps(built["graph"], ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        (OUT / f"stores_{code}.json").write_text(
            json.dumps(built["stores"], ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        c = built["graph"]["counts"]
        fp = built["graph"]["building_footprint_local_m"]
        xs = [p["x"] for p in fp] or [0]
        ys = [p["y"] for p in fp] or [0]
        print(
            f"{code:5s}{c['nodes']:6d}{c['edges']:7d}{c['transfers']:6d}"
            f"{c['stores']:6d}{c['polygons']:7d}  {len(fp)}각형 "
            f"{max(xs) - min(xs):.1f}x{max(ys) - min(ys):.1f}m"
        )
    print(f"\n생성 위치: {OUT}")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="다베오 payload를 Studio 층 JSON으로 변환한다")
    parser.add_argument("payload", type=Path, help="다베오 /v2/map 응답 JSON")
    parser.add_argument(
        "--non-walkable-only",
        action="store_true",
        help="기존 층 JSON에 못 걷는 면만 얹는다(매장·노드·간선 무변경)",
    )
    args = parser.parse_args()
    if args.non_walkable_only:
        rewrite_non_walkable(json.loads(args.payload.read_text(encoding="utf-8")))
    else:
        main(args.payload)
