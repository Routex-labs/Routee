# 층 JSON(다층)을 ORM 적재용 표준 dict로 변환한다.
# 입력은 scripts/transform/build_studio_from_dabeeo.py가 만든 층별 파일이다.
# 변환 규칙:
#   - floor(상단) → building 블록 합성. 건물명은 Studio 건물 ID의 정적 메타데이터로 보완한다.
#   - nodes  → local_m을 그대로 쓰고 wgs84만 다시 계산한다(아래 좌표계 항목 참고).
#   - edges  → 그대로 사용(seed_navigation.edge_geometry_and_length가 geometry.local_m 처리).
#   - stores → 폴리곤이 포함된 stores_{층}.json을 seed 스키마로 reshape.
#   - pois   → elevator/escalator 노드에서 자동 생성(지도 마커용).
#   - 층 간   → 엘리베이터/에스컬레이터를 이어 수직 전이 간선 생성(vertical_transfers).
# 좌표계(중요):
#   전 층이 하나의 local_m 프레임을 공유한다는 것이 이 어댑터의 전제다. 백엔드는
#   건물당 local_m->wgs84 변환을 하나만 피팅하므로(repositories/geo_transform.py),
#   층 프레임이 제각각이면 그 피팅이 무의미해진다. 다베오 변환기가 원본 좌표계를
#   전 층에 그대로 물려주므로(build_studio_from_dabeeo.py) 이 전제가 성립한다.
#   wgs84만 기준층의 local_m_to_wgs84 아핀으로 다시 계산한다 — 개별 층 익스포트에는
#   wgs84가 아예 없는 경우가 있기 때문이다.
# 실행 (backend/ 디렉토리에서):
#   python -m scripts.seed.studio_adapter

from __future__ import annotations

import json
from datetime import date
from math import hypot
from pathlib import Path

from app.core.config import settings
from app.core.database import SessionLocal
from app.graph import integrity as graph_integrity
from app.repositories import place_details, store_facets
from scripts.seed import seed_navigation
from scripts.transform import floor_alignment, vertical_transfers

API_ROOT = Path(__file__).resolve().parents[2]
# 다베오 공식 payload에서 만든 12개 층(scripts/transform/build_studio_from_dabeeo.py).
STUDIO_DIR = API_ROOT / "resources" / "studio" / "thehyundai-seoul-dabeeo"
BUILDING_NAMES = {"thehyundai-seoul": "더현대 서울"}

# 매장 id -> {category, subcategory} 오버라이드. Studio 원본은 리테일을 전부
# category="매장"으로 뭉개므로(build_studio가 dabeeo categoryCode를 버림), 실제
# 카테고리를 별도 매핑으로 주입한다. 현재는 category_code가 repo에 남아 있는
# 매장만 채워져 있고(navigation_map_parts/stores.json 기반), 나머지는 매핑에
# 없으므로 원본 category를 그대로 둔다. 파일이 없으면 오버라이드 없이 동작한다.
STORE_CATEGORIES_PATH = API_ROOT / "resources" / "store_categories.json"
# 매장명 -> {category, subcategory}. category_code가 없는 매장(대부분)을 브랜드명
# 기준으로 분류한 폴백 매핑. id 기반(STORE_CATEGORIES_PATH)이 우선한다.
STORE_CATEGORIES_BY_NAME_PATH = API_ROOT / "resources" / "store_category_by_name.json"
# 검색 전용 facet 오버레이 디렉터리. 파생 규칙(store_facets._SUBCATEGORY_TO_STYLES)과
# 합쳐 stores.search_facets 컬럼을 채운다. 디렉터리가 없으면 파생분만 적재된다.
STORE_SEARCH_FACETS_DIR = API_ROOT / "resources" / "store_search_facets"
# 매장 상세 표시용 수작업 오버레이 디렉터리. DB에 적재하지 않고 API가 조회 시점에
# 읽는다(app/repositories/place_details.py) — 재시드가 사람이 쓴 내용을 덮어쓰지
# 않게 하려는 것이다. 여기서는 적재 전에 내용이 원본과 어긋나지 않는지만 검증한다.
STORE_DETAILS_DIR = API_ROOT / "resources" / "store_details"


def _load_store_categories(path: Path = STORE_CATEGORIES_PATH) -> dict[str, dict]:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def _resolved_category(
    store: dict, overrides: dict[str, dict], by_name: dict[str, dict]
) -> tuple[str | None, str | None]:
    """카테고리 오버라이드 적용 순서를 한 곳에 모은다 — id 우선, 매장명 폴백, 원본 유지.

    `_reshape_stores`와 검증용 `_all_store_rows`가 같은 결과를 보게 하려고 함수로 뺐다.
    두 곳이 각자 오버라이드를 적용하면 규칙이 갈리는 순간 검증이 통과하는데 시드는
    다른 카테고리를 넣는 일이 생긴다.
    """
    override = overrides.get(store["id"]) or by_name.get((store.get("name") or "").strip())
    return (
        (override or {}).get("category") or store.get("category"),
        (override or {}).get("subcategory") or store.get("subcategory"),
    )


def _all_store_rows(directory: Path = STUDIO_DIR) -> list[dict]:
    """facet 검증용 전 매장 목록. `store_facets`가 기대하는 순수 dict 모양이다.

    DB를 거치지 않고 Studio JSON에서 직접 만든다 — 검증은 적재 **전에** 돌아야
    잘못된 태그가 DB에 들어가는 것을 막을 수 있다.
    """
    overrides = _load_store_categories()
    by_name = _load_store_categories(STORE_CATEGORIES_BY_NAME_PATH)
    # facet도 함께 실어 `_reshape_stores`가 규칙에 넘기는 것과 **같은 모양**으로
    # 만든다. intent 규칙이 `cuisines` 같은 축을 볼 수 있게 되면서, 검증이 보는
    # 행에 그 축이 없으면 "실데이터에 없는 값"으로 잘못 걸린다.
    facet_overlay = store_facets.load_overlay(STORE_SEARCH_FACETS_DIR)
    rows: list[dict] = []
    for path in sorted(directory.glob("stores_*.json")):
        payload = json.loads(path.read_text(encoding="utf-8"))
        for store in payload.get("stores", []):
            category, subcategory = _resolved_category(store, overrides, by_name)
            rows.append(
                {
                    "store_id": store["id"],
                    # name-null footprint는 id로 폴백 — _reshape_stores와 같은 규칙이라
                    # 오버레이의 name 대조가 실제 적재값과 어긋나지 않는다.
                    "name": store.get("name") or store["id"],
                    "category": category,
                    "subcategory": subcategory,
                    **store_facets.resolve_facets(store["id"], category, subcategory, facet_overlay),
                }
            )
    return rows


def validate_facet_resources(directory: Path = STUDIO_DIR) -> list[str]:
    """오버레이·intents 정의를 실데이터와 대조한다. 오류 메시지 목록(빈 목록이면 정상).

    설계 문서 5-2가 요구하는 "시드가 실패로 처리"의 실행 지점이다. 지금까지
    `store_facets.validate_*`는 단위 테스트만 불렀고 시드는 검증 없이 적재했다 —
    고아 store_id나 vocabulary 밖 값이 있어도 시드가 성공했다.

    태그가 없는 매장은 오류가 아니다(5-2 명시) — 커버리지 보고가 따로 다룬다.

    **실데이터(STUDIO_DIR)를 시드할 때만 검증한다.** 테스트는 합성 층 몇 개짜리 임시
    디렉터리로 시드하는데, 거기에는 오버레이가 가리키는 매장이 당연히 없어서 전부
    고아 store_id로 잡힌다. 오버레이는 실제 건물 데이터에 대해 정의된 것이므로
    다른 데이터셋으로 대조하는 것 자체가 의미가 없다.
    """
    if directory != STUDIO_DIR or not STORE_SEARCH_FACETS_DIR.exists():
        return []

    rows = _all_store_rows(directory)
    known_ids = {row["store_id"] for row in rows}
    names = {row["store_id"]: row["name"] for row in rows}

    vocabulary_path = STORE_SEARCH_FACETS_DIR / "_vocabulary.json"
    vocabulary = (
        json.loads(vocabulary_path.read_text(encoding="utf-8")).get("vocabulary", {})
        if vocabulary_path.exists()
        else {}
    )

    errors: list[str] = []
    for path in sorted(STORE_SEARCH_FACETS_DIR.glob("*.json")):
        if path.name.startswith("_"):
            continue
        payload = json.loads(path.read_text(encoding="utf-8"))
        errors += [
            f"{path.name}: {message}"
            for message in store_facets.validate_overlay(payload, vocabulary, known_ids, names)
        ]

    intents_path = STORE_SEARCH_FACETS_DIR / store_facets.INTENTS_FILENAME
    if intents_path.exists():
        payload = json.loads(intents_path.read_text(encoding="utf-8"))
        errors += [
            f"{store_facets.INTENTS_FILENAME}: {message}" for message in store_facets.validate_intents(payload, rows)
        ]
    return errors


def validate_store_detail_resources(
    directory: Path = STUDIO_DIR,
    today: str | None = None,
) -> list[str]:
    """매장 상세 오버레이를 실데이터와 대조한다. 오류 메시지 목록(빈 목록이면 정상).

    facet 검증과 같은 이유로 **실데이터를 시드할 때만** 돈다 — 합성 픽스처에는
    오버레이가 가리키는 매장이 없어 전부 고아 id로 잡힌다.

    상세 오버레이가 아직 한 건도 없어도 정상이다(빈 목록). 데이터 작성이 API보다
    늦게 끝나는 순서를 전제로 하기 때문이다.
    """
    if directory != STUDIO_DIR or not STORE_DETAILS_DIR.exists():
        return []

    schema_path = STORE_DETAILS_DIR / place_details.SCHEMA_FILENAME
    schema = json.loads(schema_path.read_text(encoding="utf-8")) if schema_path.exists() else {}

    rows = _all_store_rows(directory)
    known_ids = {row["store_id"] for row in rows}
    names = {row["store_id"]: row["name"] for row in rows}
    reference_date = today or date.today().isoformat()

    errors: list[str] = []
    for path in sorted(STORE_DETAILS_DIR.glob("*.json")):
        if path.name.startswith("_"):
            continue
        payload = json.loads(path.read_text(encoding="utf-8"))
        errors += [
            f"{path.name}: {message}"
            for message in place_details.validate_overlay(payload, known_ids, names, schema, reference_date)
        ]
    return errors


# 기준층: 건물 공통 프레임의 wgs84 앵커를 가진 층. 좌표 자체는 전 층이 공유하므로
# 여기서 가져오는 것은 local_m -> wgs84 아핀뿐이다.
REFERENCE_FLOOR = "1f"

# 지도에 마커로 노출할 편의시설 노드 타입 → POI 로 승격(노드에서 자동 생성)
POI_NODE_TYPES = {"elevator", "escalator"}


# {층}.json이 있는 층 코드를 찾아 기준층을 맨 앞에 둔 순서로 돌려준다.
def discover_floor_codes(directory: Path = STUDIO_DIR) -> list[str]:
    codes = sorted(
        path.stem for path in directory.glob("*.json") if not path.stem.startswith(("stores_", "transfers_"))
    )
    if REFERENCE_FLOOR in codes:
        codes.remove(REFERENCE_FLOOR)
        codes.insert(0, REFERENCE_FLOOR)
    return codes


def _load(floor_code: str, directory: Path = STUDIO_DIR) -> dict:
    return json.loads((directory / f"{floor_code}.json").read_text(encoding="utf-8"))


# Studio 데이터에 없는 표시용 건물명을 ID 기반 메타데이터로 보완한다.
def _building_name(building_id: str) -> str:
    return BUILDING_NAMES.get(building_id, building_id)


# 노드/엣지 ID를 층 스코프로 네임스페이싱한다(층 간 ID 재사용 충돌 방지).
def _scoped(floor_id: str, raw_id: str | None) -> str | None:
    if raw_id is None:
        return None
    return f"{floor_id}:{raw_id}"


# 기준층의 local_m -> wgs84 아핀. 출력은 (lng, lat) 순서다.
def _wgs84_transform(reference: dict) -> floor_alignment.Affine | None:
    matrix = reference["coordinate_system"].get("affine_transforms", {}).get("local_m_to_wgs84", {}).get("matrix")
    if not matrix:
        return None
    return (
        (matrix[0][0], matrix[0][1], matrix[0][2]),
        (matrix[1][0], matrix[1][1], matrix[1][2]),
    )


# 노드의 wgs84를 건물 아핀으로 다시 계산한다(ID도 층 스코프).
def _normalized_nodes(
    floor_id: str,
    nodes: list[dict],
    to_wgs84: floor_alignment.Affine | None,
) -> list[dict]:
    out: list[dict] = []
    for node in nodes:
        local = node["position"]["local_m"]
        position = {**node["position"], "local_m": local}
        if to_wgs84 is not None:
            lng, lat = floor_alignment.apply(to_wgs84, local["x"], local["y"])
            position["wgs84"] = {"lat": round(lat, 9), "lng": round(lng, 9)}
        out.append({**node, "id": _scoped(floor_id, node["id"]), "position": position})
    return out


# 간선 ID를 층 스코프로 바꾼다. geometry는 양 끝점만 남기면 향후 곡선/꺾인 복도의
# 실제 경로와 길이가 유실되므로 모든 점을 보존한다.
def _scope_edges(floor_id: str, edges: list[dict]) -> list[dict]:
    scoped = []
    for edge in edges:
        geometry = edge.get("geometry_local_m")
        if geometry is None and isinstance(edge.get("geometry"), dict):
            geometry = edge["geometry"].get("local_m")
        item = {k: v for k, v in edge.items() if k not in ("geometry", "geometry_local_m", "length_m")}
        item.update(
            {
                "id": _scoped(floor_id, edge["id"]),
                "from": _scoped(floor_id, edge["from"]),
                "to": _scoped(floor_id, edge["to"]),
            }
        )
        if geometry:
            item["geometry_local_m"] = geometry
            item["length_m"] = sum(
                hypot(current["x"] - previous["x"], current["y"] - previous["y"])
                for previous, current in zip(geometry, geometry[1:])
            )
        scoped.append(item)
    return scoped


# 입구 좌표(local_m)에서 가장 가까운 통행 노드 ID와 그 거리를 찾는다. Studio 원본은 매장에
# entrance_local_m(좌표)만 주고 entrance_node_id(그래프 연결)는 비워두므로, 이걸
# 채워주지 않으면 클라이언트가 도착 노드를 못 찾아 다익스트라가 아예 돌지 않는다.
# 교차점(junction) 우선으로 스냅해 엘리베이터/에스컬레이터 노드에 잘못 붙는 걸 막고,
# junction이 하나도 없으면 아무 노드로나 폴백한다.
# 반환: (노드 id, 거리). 노드가 하나도 없으면 (None, inf).
def _nearest_node_id(
    nodes: list[dict],
    x: float,
    y: float,
) -> tuple[str | None, float]:
    candidates = [n for n in nodes if n.get("type") == "junction"] or nodes
    best_id: str | None = None
    best_distance = float("inf")
    for node in candidates:
        local = node["position"]["local_m"]
        distance = hypot(local["x"] - x, local["y"] - y)
        if distance < best_distance:
            best_distance = distance
            best_id = node["id"]
    return best_id, best_distance


# 폴리곤을 포함한 stores_{층}.json을 seed용 store dict로 변환한다.
# 반환: (store dict 목록, 스냅 거리 초과로 입구를 못 이은 unresolved 목록).
def _reshape_stores(
    floor_code: str,
    floor_id: str,
    nodes: list[dict],
    directory: Path = STUDIO_DIR,
) -> tuple[list[dict], list[dict]]:
    stores_path = directory / f"stores_{floor_code}.json"
    if not stores_path.exists():
        return [], []
    payload = json.loads(stores_path.read_text(encoding="utf-8"))
    category_overrides = _load_store_categories()
    category_by_name = _load_store_categories(STORE_CATEGORIES_BY_NAME_PATH)
    # 검색 facet은 카테고리가 확정된 뒤에 계산한다 — 파생 규칙이 소분류를 보기 때문에
    # 오버라이드 적용 전 원본 소분류로 계산하면 태그가 통째로 어긋난다.
    facet_overlay = store_facets.load_overlay(STORE_SEARCH_FACETS_DIR)
    # intent 정의(`_intents.json`)는 지금까지 validate_facet_resources가 **검증만** 하고
    # 아무도 적재하지 않았다. 그래서 사람이 검수한 "나이키 라이즈는 신발을 판다" 145건이
    # DB에도 검색에도 존재하지 않았고, `신발` 질의는 소분류 슈즈 8건조차 라벨이 안 맞아
    # 못 잡았다. 여기서 매장별 intent를 풀어 search_facets에 함께 굽는다.
    intent_definitions = store_facets.load_intents(STORE_SEARCH_FACETS_DIR)
    max_snap_m = settings.store_entrance_snap_max_m
    reshaped: list[dict] = []
    unresolved: list[dict] = []
    for store in payload.get("stores", []):
        entrance = store.get("entrance_local_m")
        centroid = store.get("centroid_local_m") or entrance
        if centroid is None:
            continue  # 좌표가 없으면 지도에 놓을 자리가 없다
        polygon = store.get("polygon_local_m")
        # entrance_node_id는 Node FK → 네임스페이싱한 노드 ID와 일치시켜야 한다.
        # 원본이 이미 노드를 지정했으면 그대로 스코프하고, 비어 있으면(현 Studio
        # 데이터는 전부 null) 입구 좌표를 가장 가까운 통행 노드에 스냅해 채운다.
        entrance_node_id = _scoped(floor_id, store.get("entrance_node_id"))
        if entrance_node_id is None and entrance is not None:
            snapped_id, snap_distance = _nearest_node_id(nodes, entrance["x"], entrance["y"])
            if snapped_id is not None and snap_distance <= max_snap_m:
                entrance_node_id = snapped_id
            else:
                # 최대 거리 초과 → 자동 연결 금지. 잘못된 원본 좌표를 벽 반대편·건물 반대편
                # 노드에 강제로 이어 매장을 가로지르는 경로가 생기는 것을 막는다. 매장 자체는
                # 그대로 시드하되(지도에는 보임) 경로 도착점만 비운 채 unresolved로 보고한다.
                unresolved.append(
                    {
                        "store_id": store["id"],
                        "name": store.get("name") or store["id"],
                        "floor_code": floor_code,
                        "floor_id": floor_id,
                        "distance_m": round(snap_distance, 3) if snapped_id is not None else None,
                        "max_m": max_snap_m,
                        "reason": (
                            f"가장 가까운 노드가 {snap_distance:.1f}m로 최대 {max_snap_m:.0f}m를 초과"
                            if snapped_id is not None
                            else "스냅할 노드가 없음"
                        ),
                    }
                )
        # 실제 카테고리 오버라이드. id 기반(category_code 근거)이 최우선, 없으면
        # 매장명 기반 폴백, 둘 다 없으면 원본 값을 유지한다.
        category, subcategory = _resolved_category(store, category_overrides, category_by_name)
        # 파생(소분류) + 수작업 오버레이. 빈 dict는 저장하지 않는다 — 컬럼을 None으로 둬야
        # "태그 없음"과 "빈 태그"가 DB에서 구분 없이 하나로 남는다(설계 5-1 빈 배열 금지).
        facets = store_facets.resolve_facets(store["id"], category, subcategory, facet_overlay)
        # intents는 오버레이가 아니라 규칙+예외에서 유도한다 — 매장별로 손으로 적게
        # 하면 소분류가 Studio에서 바뀔 때 JSON이 조용히 낡은 후보를 들고 있게 된다
        # (store_facets 모듈 docstring "왜 intents는 규칙 + 예외 파일인가").
        # `_all_store_rows`와 같은 순수 dict 모양으로 넘긴다.
        # facets를 함께 넘긴다 — 규칙이 `cuisines` 같은 축도 볼 수 있어서다
        # (store_facets._FACET_RULE_FIELDS). 바로 위에서 이미 푼 값이라 추가
        # 비용이 없고, `_all_store_rows`가 검증에 쓰는 모양과도 같다.
        intents = store_facets.resolve_intents(
            {
                "store_id": store["id"],
                "category": category,
                "subcategory": subcategory,
                **facets,
            },
            intent_definitions,
        )
        if intents:
            facets = {**facets, "intents": intents}
        reshaped.append(
            {
                "id": store["id"],  # store id는 층별로 이미 유일(네임스페이싱 불필요)
                # 매칭 안 된 구조물 footprint는 name이 null → store id로 폴백(stores.name NOT NULL)
                "name": store.get("name") or store["id"],
                # 한글 대분류/소분류 카테고리(없으면 None). name-null footprint는 둘 다 null.
                "category": category,
                "subcategory": subcategory,
                # seed_navigation는 store["centroid"]["local_m"] 구조를 기대한다.
                "centroid": {"local_m": centroid},
                "entrance_local_m": entrance,
                "entrance_node_id": entrance_node_id,
                "polygon_local_m": polygon or None,
                "search_facets": facets or None,
            }
        )
    return reshaped, unresolved


# elevator/escalator 노드를 POI(지도 마커)로 승격한다. nodes는 정규화·스코프 후.
def _generate_pois(floor_id: str, nodes: list[dict]) -> list[dict]:
    return [
        {
            "id": f"poi_{node['id']}",
            "type": node["type"],
            "name": node.get("name"),
            "position": {"local_m": node["position"]["local_m"]},
            "linked_node_id": node["id"],
        }
        for node in nodes
        if node.get("type") in POI_NODE_TYPES
    ]


# 한 층의 Studio JSON + stores JSON을 표준 seed dict로 조립한다.
def build_seed_dict(
    floor_code: str,
    reference: dict | None = None,
    directory: Path = STUDIO_DIR,
) -> dict:
    studio = _load(floor_code, directory)
    reference = reference or _load(REFERENCE_FLOOR, directory)
    to_wgs84 = _wgs84_transform(reference)

    building_id = studio["building_id"]
    floor = studio["floor"]
    floor_id = floor["id"]
    nodes = _normalized_nodes(floor_id, studio["nodes"], to_wgs84)
    footprint = studio.get("building_footprint_local_m") or None
    stores, unresolved_entrances = _reshape_stores(floor_code, floor_id, nodes, directory)

    return {
        "building": {
            "id": building_id,
            "name": _building_name(building_id),
            # 절대 배율이 미검증이라(build_studio_from_dabeeo.SCALE_M_PER_UNIT)
            # 면적·둘레는 신뢰할 수 없다. 배율이 확정되면 채운다.
            "area_m2": None,
            "perimeter_m": None,
            # 건물 대표 외곽(기준층). 층별 윤곽은 floor.footprint_local_m에 따로 넣는다.
            "footprint_local_m": footprint,
            "floor": {
                "id": floor_id,
                "name": floor["name"],
                "level": floor["level"],
                "footprint_local_m": footprint,
                # 못 걷는 면(구멍·기둥·조경·에스컬레이터 도형). 표시 전용이라
                # 비어 있어도 길찾기는 정상이다.
                "non_walkable_polygons_local_m": studio.get("non_walkable_polygons_local_m") or None,
            },
            "map_calibration_version": studio.get("coordinate_system", {}).get("calibration_version", "unversioned"),
        },
        "nodes": nodes,
        "edges": _scope_edges(floor_id, studio["edges"]),
        "stores": stores,
        "pois": _generate_pois(floor_id, nodes),
        # 스냅 거리 초과로 입구를 못 이은 매장들(add_dataset은 무시, 시드 리포트가 소비).
        "unresolved_store_entrances": unresolved_entrances,
    }


# 전 층의 "입구 스냅 거리 초과" 매장을 모은다. DB를 거치지 않고 build_seed_dict를 다시 태워,
# 시드가 실제로 내린 것과 같은 판정을 얻는다(같은 임계값·같은 스냅 로직). 시드 리포트가 쓴다.
def collect_unresolved_store_entrances(directory: Path = STUDIO_DIR) -> list[dict]:
    codes = discover_floor_codes(directory)
    reference = _load(REFERENCE_FLOOR, directory)
    unresolved: list[dict] = []
    for code in codes:
        data = build_seed_dict(code, reference, directory)
        unresolved.extend(data.get("unresolved_store_entrances", []))
    return unresolved


# 원본 층간 간선의 노드 ID를 층 스코프 ID로 바꾼다.
#
# 층 내부 간선(_scope_edges)과 달리 양 끝점이 서로 다른 층에 있어 "이 간선의 층"으로는
# 스코프를 정할 수 없다. 그래서 전 층 노드에서 raw ID -> 스코프 ID 표를 먼저 만든다.
# 다베오 원본 노드 ID는 건물 전체에서 유일하므로(전 층 1931개, 중복 0) 표가 성립한다.
# 양 끝 중 하나라도 표에 없으면(원본에 노드가 빠진 간선) 버린다.
def _scope_transfer_edges(
    floors_for_transfer: list[dict],
    raw_edges: list[dict],
) -> list[dict]:
    scoped_by_raw: dict[str, str] = {}
    for floor in floors_for_transfer:
        for node in floor["nodes"]:
            raw_id = node["id"].split(":", 1)[-1]
            scoped_by_raw[raw_id] = node["id"]

    out: list[dict] = []
    for edge in raw_edges:
        from_id = scoped_by_raw.get(edge.get("from"))
        to_id = scoped_by_raw.get(edge.get("to"))
        if from_id is None or to_id is None:
            continue
        out.append({**edge, "from": from_id, "to": to_id})
    return out


# Studio 전 층 + 층 간 전이 간선을 하나의 트랜잭션으로 적재한다.
def seed_studio(
    *,
    session=None,
    floor_codes: list[str] | None = None,
    directory: Path = STUDIO_DIR,
) -> list[dict]:
    codes = floor_codes or discover_floor_codes(directory)
    if REFERENCE_FLOOR not in codes:
        raise ValueError(f"기준층 {REFERENCE_FLOOR}.json이 있어야 wgs84를 계산할 수 있습니다.")
    reference = _load(REFERENCE_FLOOR, directory)

    # 적재 전에 검증한다 — 잘못된 태그가 DB에 들어간 뒤 실패하면 반쯤 시드된 DB가 남는다.
    facet_errors = validate_facet_resources(directory)
    if facet_errors:
        raise ValueError(f"검색 facet 리소스 검증 실패 ({len(facet_errors)}건):\n  - " + "\n  - ".join(facet_errors))

    detail_errors = validate_store_detail_resources(directory)
    if detail_errors:
        raise ValueError(f"매장 상세 오버레이 검증 실패 ({len(detail_errors)}건):\n  - " + "\n  - ".join(detail_errors))

    own_session = session or SessionLocal()
    try:
        summaries: list[dict] = []
        floors_for_transfer: list[dict] = []
        raw_transfer_edges: list[dict] = []
        for code in codes:
            data = build_seed_dict(code, reference, directory)
            seed_navigation.add_dataset(own_session, data)
            floor = data["building"]["floor"]
            raw_transfer_edges.extend(_load(code, directory).get("vertical_transfer_edges") or [])
            floors_for_transfer.append(
                {
                    "code": code,
                    "floor_id": floor["id"],
                    "name": floor["name"],
                    "level": floor["level"],
                    "nodes": data["nodes"],
                }
            )
            summaries.append(
                {
                    "code": code,
                    "name": floor["name"],
                    "nodes": len(data["nodes"]),
                    "edges": len(data["edges"]),
                    "stores": len(data["stores"]),
                    "pois": len(data["pois"]),
                    "unresolved_entrances": len(data["unresolved_store_entrances"]),
                }
            )

        built = vertical_transfers.build_transfers(
            floors_for_transfer,
            _scope_transfer_edges(floors_for_transfer, raw_transfer_edges),
        )
        seed_navigation.add_transfer_edges(own_session, built.edges)
        summaries.append(
            {
                "code": "-",
                "transfers": len(built.edges),
                "unresolved": len(built.unresolved),
                "warnings": len(built.warnings),
            }
        )

        # 커밋 전 그래프 무결성 게이트. 타 건물 연결·동일 층 전이·NaN 같은 에러가 있으면
        # 여기서 GraphIntegrityError로 중단되어 아래 except가 롤백한다(반쯤 시드된 DB 방지).
        # facet 검증과 같은 위치·같은 철학이다.
        graph_integrity.validate_seeded_graph(own_session)

        if session is None:
            own_session.commit()
        return summaries
    except Exception:
        if session is None:
            own_session.rollback()
        raise
    finally:
        if session is None:
            own_session.close()


def main() -> None:
    for row in seed_studio():
        if "transfers" in row:
            print(f"[전이] 간선={row['transfers']} 미해결={row['unresolved']} 경고={row['warnings']}")
            continue
        print(f"[{row['name']}] nodes={row['nodes']} edges={row['edges']} stores={row['stores']} pois={row['pois']}")
    print("Studio 데이터 적재 완료")


if __name__ == "__main__":
    main()
