# 자연어 질의 매칭.
# 매장 이름·카테고리·동의어를 텍스트로 매칭해 최적 1건을 고른다(경량, 임베딩 없음).
# 질의는 꼬리 제거 + 형태소 정규화(query_morph)를 거쳐 조사·어미가 붙어도 매칭된다.
# - match_destination:    확정 가능한 1건 + 입구 노드(온디바이스 경로용).
#                         한 곳을 지목할 수 없으면 status="ambiguous"로 비워 보낸다 —
#                         클라이언트가 /query/ai 목록 계약으로 이어 간다.
# - match_info:           최적 1건 + 대상이 존재하는 층 목록.
# - match_ai_destination: 하이브리드 — 1차 경량 확정, 미스·모호한 부분 일치는 2차 의미 검색.
# Building이 없으면 None(→ Router가 404). 매칭 0건은 status="no_match"로 정상 응답.
# floor_name은 여기서 Floor를 조인해 얻는다(공유 _to_store_dict는 건드리지 않음).

from __future__ import annotations

import json
from functools import lru_cache
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session, defer

from app.core.config import API_ROOT
from app.geo.georeference import GeoTransform
from app.models import Building, Floor, Store
from app.repositories import query_morph
from app.repositories.geo_transform import fit_building_geo_transform

_SYNONYMS_PATH = API_ROOT / "resources" / "query_synonyms.json"
MAX_QUERY_LENGTH = 200

# Studio의 Store 레코드에는 원본 POI type(exit 등)이 보존되지 않는다. 현재
# 데모 데이터에서 같은 이름이어도 서로 다른 물리 선택지로 취급해야 하는 값은
# 이 정책 집합에만 명시해, 일반 매장명 중복을 목록으로 바꾸지 않는다.
_MULTI_PHYSICAL_POI_NAMES = frozenset({"출구"})

# 질의 꼬리(조사·의문형) — 정규화 때 최대 1개 제거. 긴 것부터 검사한다.
_TAILS = tuple(
    sorted(("몇 층이야", "몇층이야", "몇 층", "몇층", "어디야", "어디", "위치", "알려줘"), key=len, reverse=True)
)

# 문장 끝에서 후보로 벗겨 볼 구두점. 원문 후보도 항상 남기므로 "A.P.C."처럼
# 구두점이 실제 이름 일부인 매장은 정확 일치가 우선한다. 내부 구두점("We,pet")은 건드리지 않는다.
_SENTENCE_PUNCTUATION = frozenset("?!.,，。！？…")


def _norm(text: str) -> str:
    return text.strip().lower()


@lru_cache(maxsize=1)
def _synonyms() -> dict[str, str]:
    # 별칭 → 표준어 사전. 파일이 없어도 빈 사전으로 동작한다(장애 없이 매칭만 약해짐).
    try:
        raw = json.loads(_SYNONYMS_PATH.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}
    return {_norm(k): _norm(v) for k, v in raw.items()}


# 정규화. 꼬리 제거 → 형태소 정규화.
# 꼬리 제거를 먼저 하는 이유: "몇 층이야"의 "층"은 Kiwi가 일반명사(NNG)로 보기 때문에
# 형태소만으로는 "화장실 몇 층이야" → "화장실 층"이 되어 이름 일치가 깨진다.
# 형태소는 그다음 남은 조사·어미를 뗀다("화장실이" → "화장실"). Kiwi가 없으면 꼬리 제거
# 결과만 쓴다.
def _normalize_variant(text: str) -> str:
    t = _strip_tail(text)
    return query_morph.normalize(t) or t


def _query_candidates(text: str) -> tuple[str, ...]:
    """원문과 문장 끝 구두점을 한 글자씩 벗긴 정규화 후보를 만든다.

    원문 후보를 먼저 둬서 "A.P.C." 같은 실제 상호를 보존하고, 뒤 후보로
    "화장실이 어디야?" 같은 문장부호 입력을 받는다. 빈 후보는 category가 null인
    임의 매장과 일치할 수 있으므로 제외한다.
    """
    current = _norm(text)
    if len(current) > MAX_QUERY_LENGTH:
        return ()

    variants = [current]
    while current and current[-1] in _SENTENCE_PUNCTUATION:
        current = current[:-1].rstrip()
        variants.append(current)

    candidates: list[str] = []
    for variant in variants:
        normalized = _normalize_variant(variant)
        if normalized and normalized not in candidates:
            candidates.append(normalized)
    return tuple(candidates)


def _normalize_query(text: str) -> str:
    """단일 정규화 결과가 필요한 검사 호환용. 매칭은 모든 후보를 직접 평가한다."""
    candidates = _query_candidates(text)
    return candidates[-1] if candidates else ""


def _is_multi_physical_query(text: str) -> bool:
    return _normalize_query(text) in _MULTI_PHYSICAL_POI_NAMES


def _is_multi_physical_store(store: Store) -> bool:
    return _norm(store.name or "") in _MULTI_PHYSICAL_POI_NAMES


def _strip_tail(t: str) -> str:
    for tail in _TAILS:
        if t.endswith(tail):
            return t[: -len(tail)].strip()
    return t


# tier 2(이름 부분 일치) 안의 정밀도. 낮을수록 우선.
# 사용자는 이름 앞에서부터 친다 — "레이어드"는 "카페 레이어드"를 찾는 것이지 다른 이름의
# 중간 어딘가를 찾는 게 아니다. 이 순위가 없으면 둘 다 같은 tier 2라 층·ID순으로 갈려,
# 몇 글자를 친 순간 엉뚱한 시설이 먼저 뜬다(KIWI.md 9절이 예고한 한 글자 과매칭).
_NAME_PREFIX = 0  # 이름이 질의로 시작 — "이솝화" → "이솝 화장품"(2글자부터, 아래 참고)
_WORD_PREFIX = 1  # 이름 속 단어가 질의로 시작 — "레이어드" → "카페 레이어드"
_CONTAINS = 2  # 그 밖의 중간 포함 — "이솝" → "엘리베이터솝"(가상의 예)

# 띄어쓰기를 양쪽에서 뗀 뒤의 일치. 위 세 단계보다 **항상 뒤에** 온다.
#
# 사람은 브랜드명을 띄어 치고("노스 페이스"), 데이터도 같은 시설을 제각각 띄어 적는다
# (`물품보관함`·`물품 보관함`·`물 품 보 관 함` 세 이름이 실제로 있다). 어느 쪽이든
# 공백은 뜻을 나르지 않는데 문자열 비교는 그걸 다른 이름으로 본다.
#
# 공백을 뗀 비교를 별도 단계로 두는 이유는 순위 때문이다. 원문 띄어쓰기 그대로 걸린
# 매장이 있으면 그쪽이 무조건 먼저여야 한다 — 공백을 떼면 후보가 늘기만 하므로,
# 같은 단계에 섞으면 정확히 친 사용자가 손해를 본다.
#
# 공백을 뗀 이름에는 단어 경계가 없어 _WORD_PREFIX에 해당하는 단계가 없다. 대신
# "이름 전체가 같음"을 맨 앞에 둔다 — "노스 페이스"가 `노스페이스`(전체 일치)와
# `노스페이스 화이트 라벨`(접두)을 같은 정밀도로 묶으면 둘 중 하나로 확정하지 못하고
# 되물음으로 새 버린다.
_SPACELESS_EXACT = 3  # 공백을 떼면 이름 전체와 같음 — "노스 페이스" → "노스페이스"
_SPACELESS_PREFIX = 4  # 공백을 떼면 이름이 질의로 시작 — "노스 페이스" → "노스페이스 화이트 라벨"
_SPACELESS_CONTAINS = 5  # 그 밖의 중간 포함

# tier 2(이름 부분 일치)에 들어가려면 질의가 최소 2글자여야 한다. query_morph.normalize가
# 형태소 분해로 오타·조사를 지우면서 질의가 1글자로 축소되는 경우가 있다("샤낼"→"샤",
# "물 사고싶어"→"물"). 그 1글자가 무관한 매장 이름 접두와 우연히 맞아 오탐이 난다.
# tier 0(정확 이름 일치)·tier 1(카테고리 일치)은 이 하한의 영향을 받지 않는다 — "송"·"온"
# 같은 한 글자 매장명은 정확 일치로 계속 잡혀야 한다.
_MIN_NAME_PARTIAL_MATCH_LEN = 2


def _intent_names(store: Store) -> tuple[str, ...]:
    """이 매장이 속한 intent 이름들(정규화). 태그가 없으면 빈 튜플.

    값의 출처는 `Store.search_facets["intents"]`이고, 시드가
    `store_facets.resolve_intents`로 규칙 + 예외에서 유도해 구워 둔 것이다. 매칭
    시점에 규칙을 다시 푸는 게 아니라 이미 구워진 결과만 읽는다 — 질의마다 1640건에
    규칙을 돌리면 경량 경로가 경량이 아니게 된다.
    """
    return tuple(_norm(value) for value in _facets(store).get("intents", ()))


def _squash_spaces(text: str) -> str:
    return "".join(text.split())


def _spaceless_match_rank(name: str, q: str) -> int | None:
    """공백을 뗀 뒤의 부분 일치 정밀도. 뗄 공백이 아예 없으면 검사하지 않는다."""
    squashed_name = _squash_spaces(name)
    squashed_q = _squash_spaces(q)
    # 양쪽 다 공백이 없으면 바로 위 검사와 완전히 같은 비교다 — 두 번 하지 않는다.
    if squashed_name == name and squashed_q == q:
        return None
    if len(squashed_q) < _MIN_NAME_PARTIAL_MATCH_LEN or squashed_q not in squashed_name:
        return None
    if squashed_name == squashed_q:
        return _SPACELESS_EXACT
    if squashed_name.startswith(squashed_q):
        return _SPACELESS_PREFIX
    return _SPACELESS_CONTAINS


def _name_match_rank(name: str, q: str) -> int | None:
    if not q:
        return None
    if len(q) >= _MIN_NAME_PARTIAL_MATCH_LEN and q in name:
        if name.startswith(q):
            return _NAME_PREFIX
        if any(token.startswith(q) for token in name.split()):
            return _WORD_PREFIX
        return _CONTAINS
    return _spaceless_match_rank(name, q)


# 질의를 **접두로 갖는** 별칭들의 표준형.
#
# 별칭 사전은 완전 일치 조회(`synonyms.get(q)`)라 `starbucks`를 끝까지 쳐야 걸렸다.
# 한글은 매장명 자체가 `스타벅스 리저브`라 `스타`만 쳐도 부분 일치로 잡히는데,
# 영어로 치는 사용자만 전부 입력해야 했다 — 같은 매장을 찾는 두 언어의 경험이
# 달랐다.
#
# 그래서 `starb`처럼 별칭의 앞부분만 쳐도 그 별칭의 표준형(`스타벅스`)을 함께
# 후보로 본다. 반대 방향(표준형이 질의의 접두)은 넣지 않는다 — `스`가 `스타벅스`
# 별칭 전부를 끌어와 무관한 매장이 쏟아진다.
#
# 질의당 한 번만 계산해 매장 루프 밖에서 넘긴다. 사전이 190개 남짓이라 순회가
# 싸고, 매장마다 다시 돌면 600곳 × 190개가 된다.
def _prefix_expansions(synonyms: dict[str, str], q: str) -> tuple[str, ...]:
    if len(q) < _MIN_NAME_PARTIAL_MATCH_LEN:
        return ()
    found: list[str] = []
    for alias, canon in synonyms.items():
        # 완전 일치는 호출부가 이미 canon으로 처리한다.
        if alias != q and alias.startswith(q) and canon not in found:
            found.append(canon)
    return tuple(found)


# 매칭 우선순위 (tier, tier 2 정밀도). 낮을수록 우선. 안 걸리면 None.
def _tier(store: Store, q: str, canon: str, expansions: tuple[str, ...] = ()) -> tuple[int, int] | None:
    name = _norm(store.name or "")
    cat = _norm(store.category or "")
    sub = _norm(store.subcategory or "")
    if name in (q, canon):
        return 0, 0  # 정확 이름 일치
    if q in (cat, sub) or canon in (cat, sub):
        return 1, 0  # 카테고리/서브카테고리 일치
    # intent 일치도 카테고리와 같은 tier 1이다.
    #
    # intent는 "사용자가 치는 말"이고(`신발`·`밥집`), 분류 라벨은 운영자가 쓰는 말이다
    # (`슈즈`·`레스토랑`). 둘이 어긋나는 게 정상이라 라벨만 보면 `신발`·`음식점`은
    # 영원히 no_match였다. 여기서 새 규칙을 쓰지 않는 게 핵심이다 — 어떤 매장이 신발을
    # 파는지는 사람이 검수한 `_intents.json`(규칙 + 예외 145건)에 데이터로 들어 있고,
    # 시드가 그걸 풀어 search_facets에 구워 둔다. 동의어를 하나씩 늘리는 방식과 달리
    # 예외가 늘어도 코드가 아니라 검수 대상 JSON이 늘어난다.
    if q in (intents := _intent_names(store)) or canon in intents:
        return 1, 0
    # 질의 원문과 동의어 표준형 중 더 정밀하게 걸린 쪽을 쓴다.
    ranks = [rank for rank in (_name_match_rank(name, q), _name_match_rank(name, canon)) if rank is not None]
    for expanded in expansions:
        rank = _name_match_rank(name, expanded)
        if rank is not None:
            ranks.append(rank)
    if ranks:
        return 2, min(ranks)  # 이름 부분 일치
    return None


# (tier, 구두점 후보 순서, tier 2 정밀도, floor.level, store.id) 오름차순 정렬 — 결정적.
# 정밀도를 후보 순서 뒤에 두는 이유: 후보 순서는 "원문에 가까운 정규화"를 뜻하고,
# 정밀도는 그 후보가 이름 어디에 걸렸는지를 뜻한다. 원문 우선을 먼저 지킨 뒤
# 같은 후보 안에서 접두를 앞세워야 "A.P.C." 같은 기존 동작이 그대로 남는다.
def _rank_with_candidate(
    rows: list[tuple[Store, Floor]],
    text: str,
) -> list[tuple[int, int, int, int, str, Store, Floor]]:
    # 매장명을 형태소 사전에 먼저 등록한다 — 안 하면 미등록 브랜드명이 조사로 오해돼
    # 잘려 나간다("리모와" → "리모"). 이미 등록된 단어는 건너뛰므로 두 번째 요청부터는 사실상 무료.
    query_morph.register_words(store.name for store, _floor in rows)

    candidates = _query_candidates(text)
    synonyms = _synonyms()

    # 후보마다 표준형과 접두 확장을 **매장 루프 밖에서** 한 번만 만든다.
    expanded_candidates = [(synonyms.get(q, q), _prefix_expansions(synonyms, q)) for q in candidates]

    # 걸리는 매장마다 최선의 (tier, 후보 순서, 정밀도)를 고른다. tier가 같으면 원문에
    # 가까운 후보가 먼저라 "A.P.C."가 "A.P.C 골프"의 부분 일치보다 우선한다.
    scored_with_candidate = []
    for store, floor in rows:
        best: tuple[int, int, int] | None = None
        for candidate_order, q in enumerate(candidates):
            canon, expansions = expanded_candidates[candidate_order]
            matched = _tier(store, q, canon, expansions)
            if matched is None:
                continue
            tier, precision = matched
            key = (tier, candidate_order, precision)
            if best is None or key < best:
                best = key
        if best is not None:
            tier, candidate_order, precision = best
            scored_with_candidate.append((tier, candidate_order, precision, floor.level, store.id, store, floor))

    scored_with_candidate.sort(key=lambda row: (row[0], row[1], row[2], row[3], row[4]))
    return scored_with_candidate


def _rank(
    rows: list[tuple[Store, Floor]],
    text: str,
) -> list[tuple[int, int, str, Store, Floor]]:
    """외부 매칭용 순위. 내부 후보 순서·정밀도는 정렬에만 쓰고 반환에서는 감춘다."""
    return [
        (tier, level, store_id, store, floor)
        for (
            tier,
            _candidate_order,
            _precision,
            level,
            store_id,
            store,
            floor,
        ) in _rank_with_candidate(rows, text)
    ]


def _is_confident_light_match(
    scored: list[tuple[int, int, int, int, str, Store, Floor]],
) -> bool:
    """경량 결과를 바로 한 건으로 확정해도 되는지 판단한다.

    **두 경로가 이 함수 하나를 공유한다** — `match_destination`(단일 목적지)과
    `discover`(탐색)가 같은 질의에 다른 결론을 내면, 어느 경로로 들어왔는지에 따라
    사용자가 보는 결과가 달라진다. 실제로 그랬다: destination만 이 판정을 건너뛰어
    "명품"을 42건 중 첫 매장으로 고정했다.

    tier 0(정확 이름)·tier 1(카테고리·소분류 정확 일치)·tier 2(이름 부분 일치) 모두
    같은 기준으로 판단한다 — 최상위 (tier, 후보 순서, 정밀도) 그룹 안에서 서로 다른
    매장명이 하나일 때만 확정한다. 같은 시설이 여러 층에 있는 경우는 이름이 같으므로
    하나의 대상으로 본다.

    tier 0은 정의상(질의 원문과 이름이 정확히 같음) 그룹 안 이름이 항상 하나뿐이라
    이 통합으로 기존 동작(무조건 확정)이 그대로 유지된다. tier 1은 "명품"(43건)·
    "레스토랑"(65건)처럼 서로 다른 매장 이름이 여럿이면 확정하지 않고 2차 의미 검색으로
    넘긴다(docs/backend/native/conversational-discovery.md 7-2절).

    같은 tier 2라도 정밀도가 다르면 다른 그룹으로 본다 — "이"의 접두 일치("이솝")가
    유일하면, 중간 포함이 수십 건 있어도 그 하나로 확정한다.
    """
    if not scored:
        return False
    best_group = scored[0][:3]  # (tier, 후보 순서, 정밀도)
    best_rows = [
        (store, floor)
        for tier, order, precision, _level, _store_id, store, floor in scored
        if (tier, order, precision) == best_group
    ]
    best_names = {_norm(store.name or "") for store, _floor in best_rows}
    if len(best_names) != 1:
        return False

    # 출구처럼 이름은 같아도 좌표가 다른 POI들은 사용자가 고를 목록이어야
    # 한다. 일반 매장명이 여러 층에 반복되는 기존 direct 동작은 그대로 둔다.
    return not (len(best_rows) > 1 and all(_is_multi_physical_store(store) for store, _floor in best_rows))


def _floor_names_for_match(
    scored: list[tuple[int, int, str, Store, Floor]],
    selected_name: str,
) -> list[str]:
    """대표 매장과 이름이 같은 후보가 존재하는 층만 level 순으로 돌려준다."""
    normalized_name = _norm(selected_name)
    by_level: dict[str, int] = {}
    for _, level, _store_id, store, floor in scored:
        if _norm(store.name or "") == normalized_name:
            by_level.setdefault(floor.name, level)
    return [name for name, _ in sorted(by_level.items(), key=lambda item: item[1])]


def _to_match(
    store: Store,
    floor: Floor,
    transform: GeoTransform | None,
) -> dict[str, Any]:
    # wgs84는 지도 표시용. 건물에 실좌표 앵커가 없으면 transform이 없어 null이 된다.
    centroid_wgs84 = None
    if transform is not None:
        lat, lng = transform.apply(store.centroid_x_m, store.centroid_y_m)
        centroid_wgs84 = {"lat": lat, "lng": lng}

    return {
        "store_id": store.id,
        "name": store.name,
        "category": store.category,
        "subcategory": store.subcategory,
        "floor_id": store.floor_id,
        "floor_name": floor.name,
        "entrance_node_id": store.entrance_node_id,
        "centroid_local_m": {"x": store.centroid_x_m, "y": store.centroid_y_m},
        "centroid_wgs84": centroid_wgs84,
    }


# 입구 노드가 없으면 클라이언트가 경로를 못 만든다 — ok와 구분해 알린다.
def _status(store: Store) -> str:
    return "ok" if store.entrance_node_id else "ok_no_route"


# current_floor_id는 층 라벨("B2")과 내부 id("FL-...")를 모두 받는다. 클라이언트는
# 사용자가 보는 라벨만 들고 있고, building_id로 스코프가 잡혀 있어 uq_floors_building_name이
# 건물 안에서 라벨의 유일성을 보장한다. id도 받는 건 기존 호출부 호환용.
def _load_stores(
    session: Session,
    building_id: str,
    *,
    current_floor_id: str | None = None,
) -> list[tuple[Store, Floor]]:
    # 도형 JSON 셋을 미룬다. 질의 경로는 이름·카테고리·search_facets만 보는데,
    # 이 셋은 매장 외곽선·층 외곽선이라 행마다 가장 큰 JSON이다.
    #
    # 실측(동의어 321건 전수, 매장 1,640건): 이 셋을 함께 읽으면 `json.loads`가
    # 210만 번 돌아 235초 중 **180초**를 쓴다. 랭킹 로직 자체는 5.7초다.
    # 미루면 남는 JSON은 search_facets 하나뿐이라 역직렬화가 1/4로 준다.
    #
    # `defer`라 접근하면 그때 한 번 더 읽는다 — 이 모듈은 세 컬럼을 쓰지 않고,
    # 다른 경로가 같은 Store를 쓰더라도 필요한 시점에 lazy로 채워진다.
    statement = (
        select(Store, Floor)
        .join(Floor, Store.floor_id == Floor.id)
        .where(Floor.building_id == building_id)
        .options(
            defer(Store.polygon),
            defer(Floor.footprint_local_m),
            defer(Floor.non_walkable_polygons_local_m),
        )
    )

    if current_floor_id is not None:
        statement = statement.where((Floor.name == current_floor_id) | (Floor.id == current_floor_id))
    # .tuples()는 Row가 아니라 (Store, Floor) 튜플로 받게 해 반환 타입과 실제가 일치한다.
    return list(session.execute(statement).tuples().all())


# 목적지 질의. Building 없으면 None(→404). 매칭 최적 1건을 입구 노드와 함께 반환.
def match_destination(
    session: Session,
    building_id: str,
    text: str,
    *,
    current_floor_id: str | None = None,
) -> dict[str, Any] | None:
    if session.get(Building, building_id) is None:
        return None

    scored = _rank_with_candidate(
        _load_stores(session, building_id, current_floor_id=current_floor_id),
        text,
    )
    if not scored:
        return {"status": "no_match", "query": text, "match": None}

    # 확정할 수 없는 매칭은 1건으로 좁히지 않는다.
    #
    # 이 판정을 AI 경로(discover)와 **같은 함수로** 한다. 예전에는 여기만 확정 판정
    # 없이 scored[0]을 무조건 돌려줬고, 그래서 "명품"(서로 다른 이름 42건)·
    # "레스토랑"(57건)이 몽클레르·데이릿 한 건으로 고정됐다. 클라이언트는
    # /query/destination이 성공하면 /query/ai를 부르지 않으므로(search_panel.dart),
    # 카테고리성 질의는 사용자가 목록을 볼 기회 자체가 없었다.
    #
    # 여기서 "목록을 원하는 질의"를 따로 분류하지 않는 게 핵심이다. 카테고리 단어
    # 사전을 만들면 `제일`은 되는데 `가장`은 안 되는 식으로 예외가 계속 늘어난다.
    # 이미 있는 기준 — 최상위 (tier, 후보 순서, 정밀도) 그룹 안에 서로 다른 매장명이
    # 둘 이상인가 — 하나로 충분하다. 그 기준은 tier와 무관하게 "이 질의로는 한 곳을
    # 지목할 수 없다"는 뜻이고, 그게 곧 목록을 보여줄 조건이다.
    #
    # 출구처럼 이름은 같아도 물리적으로 다른 POI들도 이 함수가 이미 걸러낸다
    # (_is_confident_light_match 마지막 줄). 그래서 여기 있던 _is_multi_physical_query
    # 특수 분기를 지웠다 — 같은 판정을 두 곳에서 따로 하고 있었다.
    #
    # DestinationResponse는 단일 목적지 계약이라 후보를 담을 자리가 없다. match=null로
    # 돌려주면 클라이언트가 빈 결과로 파싱해(http_destination_repository.dart)
    # /query/ai 목록 계약으로 자연스럽게 이어진다 — 클라이언트 변경이 필요 없다.
    if not _is_confident_light_match(scored):
        return {"status": "ambiguous", "query": text, "match": None}

    # 정렬이 결정적이라 [0]이 곧 최적 1건.
    *_, store, floor = scored[0]
    transform = fit_building_geo_transform(session, building_id)

    return {"status": _status(store), "query": text, "match": _to_match(store, floor, transform)}


# AI 자연어 질의(하이브리드) — 단일 목적지 1건 계약.
# **/query/ai는 더 이상 이 함수를 쓰지 않는다**(Wave 6에서 discover()의 탐색 계약으로
# 전환). 남겨 둔 이유는 "질의 하나 → 최적 1건"이 그대로 필요한 곳이 있기 때문이다:
# scripts/evaluate_query_hybrid.py의 기준선 측정(23/29)과 의미 검색 스모크 테스트.
# 1차 경량 확정 → 미스·모호한 부분 일치 시 2차 의미 검색.
# 검색 범위가 단계별로 다르다: 1차는 현재 층 한정(가까운 시설 우선), 2차는 건물 전체
# (사용자가 층을 모르는 자연어 질의). destination과 같은 응답 계약(status/query/match)을 쓴다.
# 설계: docs/backend/native/FAISS.md
def match_ai_destination(
    session: Session,
    building_id: str,
    text: str,
    *,
    current_floor_id: str | None = None,
) -> dict[str, Any] | None:
    if session.get(Building, building_id) is None:
        return None

    # 1차: 정확 이름·동의어와 단일 대상 부분 일치. 서로 다른 이름이 여럿 걸린 부분
    # 일치는 ID순으로 임의 확정하지 않고 2차가 의미로 판별하게 한다.
    scored = _rank_with_candidate(
        _load_stores(session, building_id, current_floor_id=current_floor_id),
        text,
    )
    if _is_confident_light_match(scored):
        *_, store, floor = scored[0]
        transform = fit_building_geo_transform(session, building_id)
        return {"status": _status(store), "query": text, "match": _to_match(store, floor, transform)}

    # 2차: 경량이 놓쳤거나 모호한 자연어를 임베딩 의미 검색으로.
    # import는 여기서 지연 — AI 경로가 2차를 쓸 때만 torch를 로드한다.
    #
    # current_floor_id를 넘기지 않는다 — 2차는 건물 전체를 본다.
    # 1차(현재 층 한정)가 이미 실패한 뒤라 층을 또 좁히면 남는 게 없다. 실제로 1F에서
    # "밥집"은 1F에 식당이 0개라 무조건 no_match였다. 현재 층 시설("화장실")은 1차가
    # 층 스코프로 잡아 확정하므로, 층 우선순위는 여기서가 아니라 1차에서 지켜진다.
    from app.repositories import query_semantic

    hit = query_semantic.semantic_search(session, building_id, text)
    if hit is None:
        return {"status": "no_match", "query": text, "match": None}

    _score, store, floor = hit
    transform = fit_building_geo_transform(session, building_id)

    return {"status": _status(store), "query": text, "match": _to_match(store, floor, transform)}


# --------------------------------------------------------------------------
# 탐색(Discovery) — POST /query/ai
# 설계: docs/backend/native/conversational-discovery.md 7·8절.
# 단일 목적지(match_destination)와 달리 "여러 후보 + 되물음"을 만든다.
# --------------------------------------------------------------------------

MAX_DISCOVERY_MATCHES = 5  # 되물을 수 없는 제한 상태(degraded)의 추천 상한
CLARIFY_PREVIEW_MATCHES = 3  # 질문과 함께 보여줄 초기 후보 수(12절 확정)

# 후보를 무엇으로 잡았는지. 응답의 `source`로 나가며, 클라이언트가 온디바이스 이름
# 후보와 이 응답 중 무엇을 화면에 둘지 판단하는 근거다.
#
# 왜 mode만으로는 부족한가: `results`·`clarify`는 어휘로 잡았을 때도 임베딩으로
# 잡았을 때도 나온다. 클라이언트가 구분해야 하는 축은 "얼마나 좁혀졌나"(mode)가
# 아니라 **"무엇을 근거로 잡았나"** 다. 이름을 정확히 아는 온디바이스 후보는 추측인
# 임베딩에는 이겨야 하고, 동의어·intent 같은 결정적 어휘에는 져야 한다.
SOURCE_LIGHT = "light"  # 이름·카테고리·동의어·intent — 결정적 어휘 매칭
SOURCE_SEMANTIC = "semantic"  # FAISS 임베딩 — 유사도 추측

# 목록(results) 상한.
#
# 12절이 정한 "추천 최대 5건"은 **질문이 아직 서 있는 화면**의 규칙이다. 되물을 축이
# 있으면 clarify가 미리보기 3건만 보여주고 사용자가 좁혀 나간다. 그런데 되물을 축이
# 없는 질의("커피" — 후보 53건이 전부 카페·베이커리라 나눌 축이 없다)는 그 5건이
# 곧 최종 답이 되고, 그 화면에는 "전체 보기" 버튼도 없다. 53곳 중 5곳만 보여주고
# 나머지 48곳으로 갈 길이 아예 없는 막다른 화면이었다.
#
# 그래서 "이게 최종 목록"인 자리는 전부 이 상한 하나를 쓴다 — 선택으로 좁힌 결과,
# 전체 보기, 되물을 축이 없는 결과. 100은 실제 데이터의 한 카테고리를 통째로
# 담는 크기다(카페 53, 컨템포러리 61). 상한 자체를 없애지는 않는다 — 이름이 제각각인
# 787건짜리 축이 걸리면 응답이 통째로 커진다.
MAX_RESULT_MATCHES = 100

# 되물을 축의 우선순위. 한 번에 한 축만 묻는다(2절). 앞에 있는 축부터 구분력을 본다.
_QUESTION_AXIS_ORDER = ("intents", "cuisines", "styles", "menus", "occasions", "audiences")

# 7-3절 질문 템플릿. 문장을 생성하지 않고 축별로 고정한다.
_QUESTION_TEMPLATES = {
    "intents": "무엇을 찾으세요?",
    "cuisines": "어떤 종류가 좋으세요?",
    "styles": "어떤 스타일을 찾으세요?",
    "menus": "무엇을 드시고 싶으세요?",
    "occasions": "어떤 상황에 맞는 곳을 찾으세요?",
    "audiences": "누구를 위한 곳인가요?",
}

# 추천 이유 템플릿. 검증된 태그(matched_facets)에서만 조립한다 — 이름·카테고리로
# 음식 종류나 취급 품목을 추측하지 않는다(2절 실패 조건).
_REASON_TEMPLATES = {
    "intents": "{values} 관련 매장이에요.",
    "cuisines": "{values} 음식점이에요.",
    "styles": "{values} 스타일 매장이에요.",
    "menus": "{values} 메뉴가 있어요.",
    "occasions": "{values}에 어울려요.",
    "audiences": "{values}를 위한 곳이에요.",
}


def _facets(store: Store) -> dict[str, list[str]]:
    """Store.search_facets를 방어적으로 읽는다. 미태깅 매장이 대다수라 빈 dict가 정상."""
    raw = store.search_facets
    if not isinstance(raw, dict):
        return {}
    return {
        axis: [value for value in values if isinstance(value, str)]
        for axis, values in raw.items()
        if isinstance(values, list) and values
    }


def _query_matched_intents(
    candidates: list[tuple[Store, Floor]],
    text: str,
) -> list[str]:
    """질의어 자체가 가리킨 intent 값들. 후보에 실제로 있는 값만 남긴다.

    `_tier`가 tier 1을 주는 조건(`q in intents or canon in intents`)을 질의 관점에서
    되짚은 것이다 — 후보 집합이 왜 이렇게 모였는지를 매장이 아니라 **질의**가 알고
    있으므로, 그 근거를 `basis`로 흘려보내야 `reason`이 사용자가 친 말과 이어진다.

    이게 없으면 `신발` 질의의 추천 이유가 "명품 스타일 매장이에요"로만 나온다.
    질문 축(styles)만 basis에 담기기 때문인데, 사용자 입장에서는 신발을 물었는데
    신발 이야기가 한 마디도 없는 문장이 된다(2절 "근거를 말한다"의 실패).

    후보에 없는 값을 지우는 이유: `_matched_facets`가 어차피 매장 태그와 교집합을
    내므로 결과는 같지만, 여기서 걸러 두면 `basis`가 곧 "이 화면에서 쓰인 근거"라는
    뜻을 유지한다.
    """
    synonyms = _synonyms()
    wanted: set[str] = set()
    for q in _query_candidates(text):
        wanted.add(q)
        wanted.add(synonyms.get(q, q))

    matched: list[str] = []
    for store, _floor in candidates:
        for value in _facets(store).get("intents", ()):
            if _norm(value) in wanted and value not in matched:
                matched.append(value)
    return matched


def _intent_basis(intents: list[str]) -> dict[str, list[str]]:
    """intent 근거를 basis 모양으로. 없으면 빈 dict — 빈 축을 만들지 않는다(5-1절)."""
    return {"intents": intents} if intents else {}


def _matches_selection(store: Store, selection: dict[str, list[str]]) -> bool:
    """축 사이는 AND, 축 안의 값들은 OR. 태그가 없는 매장은 선택된 축에서 탈락한다."""
    facets = _facets(store)
    for axis, wanted in selection.items():
        if not set(facets.get(axis, ())) & set(wanted):
            return False
    return True


def _facet_options(
    candidates: list[tuple[Store, Floor]],
    axis: str,
) -> list[dict[str, Any]]:
    """축의 값별 후보 수. 실제 후보가 있는 값만 만든다(빈 chip 금지, 4-3절)."""
    counts: dict[str, int] = {}
    for store, _floor in candidates:
        for value in _facets(store).get(axis, ()):
            counts[value] = counts.get(value, 0) + 1
    return [
        {"facet": axis, "value": value, "label": value, "count": count}
        for value, count in sorted(counts.items(), key=lambda item: (-item[1], item[0]))
    ]


def _drop_indistinguishable(
    candidates: list[tuple[Store, Floor]],
    axis: str,
    options: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    """가리키는 후보가 똑같은 선택지를 하나로 접는다.

    같은 매장 집합을 가리키는 값이 둘이면 화면에는 chip이 둘 뜨지만 어느 쪽을 눌러도
    결과가 같다. 고르는 행동이 아무것도 바꾸지 못하므로 선택지가 아니다. 근거와 실제
    사례는 [_pick_question] docstring 2번에 있다.

    남길 값은 [_facet_options]가 정한 순서(후보 수 내림차순 → 값 오름차순)의 첫 번째다.
    같은 입력에 항상 같은 chip이 나와야 하므로 순서에 기대는 선택이며, 그 순서 자체가
    이미 결정적이다.
    """
    kept: dict[frozenset[str], dict[str, Any]] = {}
    for option in options:
        members = frozenset(store.id for store, _floor in candidates if option["value"] in _facets(store).get(axis, ()))
        # 후보가 하나도 없는 값은 애초에 _facet_options가 만들지 않는다. 방어적으로만 둔다.
        if not members:
            continue
        kept.setdefault(members, option)
    return list(kept.values())


def _pick_question(
    candidates: list[tuple[Store, Floor]],
    asked_intents: list[str] | None = None,
) -> tuple[str | None, list[dict[str, Any]]]:
    """현재 후보를 실제로 둘 이상으로 나누는 축을 고른다. 없으면 (None, []).

    세 가지를 모두 만족해야 질문이 된다(7-3절 "현재 후보를 실제로 나누지 못하는
    facet은 질문으로 선택하지 않는다").

    1. 서로 다른 값이 둘 이상 — "명품" 질의의 후보 43건은 전부 styles=["명품"]이라
       스타일을 다시 물어도 후보가 그대로다.
    2. **그 값들이 서로 다른 후보를 가리킨다** — 값 개수만 세면 라벨만 다르고 가리키는
       매장이 똑같은 쌍을 걸러내지 못한다. `_intents.json`의 `화장품`과 `향수`가 바로
       그런 쌍이다(둘 다 `subcategory: ["화장품·향수"]`). 실기기에서 `샤낼 뷰티`를
       치면 `향수 (10)` `화장품 (10)` 두 chip이 떴는데 **어느 쪽을 눌러도 같은 10건**
       이었다. 고르는 행동이 아무것도 바꾸지 못하는 질문이라 사용자는 "둘 중 뭘 고르라는
       거지"만 남는다.

       이 쌍은 **임베딩 쪽에서는 의도된 것**이다 — 소분류가 복합 라벨(`화장품·향수`)
       이라 `화장품`만 선언하면 문서 텍스트의 단어 빈도가 한쪽으로 쏠려 `향수` 질의가
       회귀했다(FAISS.md 11-4). 그래서 데이터를 고치지 않고 **질문 축으로 쓸 때만**
       걸러낸다. 한 데이터가 임베딩 가중치와 질문 선택지라는 두 용도를 겸하고 있고,
       두 번째 용도에서만 무효인 경우다.
    3. 그 축을 가진 후보가 절반 이상 — 태깅이 아직 얇은 지금 데이터에서는, 상위 10건 중
       2건만 태그가 있어도 "값이 2개"라는 조건은 통과해 버린다. 그 질문에 답하면
       태그 없는 8건이 통째로 사라진다(2절 "미표기 매장이 통째로 사라진다").

    `asked_intents`(질의가 이미 가리킨 intent 값)는 intents 축의 선택지에서 뺀다.
    사용자가 방금 친 말을 선택지로 되돌려주는 건 질문이 아니라 메아리다 — 한 매장이
    여러 intent를 갖게 되면(`신발`과 `의류`를 함께 파는 매장) "신발"에 대고
    "신발/의류 중 무엇을 찾으세요?"를 묻게 된다. 뺀 뒤 선택지가 2개 미만이면 이 축은
    구분력이 없는 것이므로 다음 축(styles 등)으로 넘어간다.
    """
    excluded = set(asked_intents or ())
    for axis in _QUESTION_AXIS_ORDER:
        options = _facet_options(candidates, axis)
        if axis == "intents" and excluded:
            options = [option for option in options if option["value"] not in excluded]
        options = _drop_indistinguishable(candidates, axis, options)
        if len(options) < 2:
            continue
        covered = sum(1 for store, _floor in candidates if _facets(store).get(axis))
        if covered * 2 >= len(candidates):
            return axis, options
    return None, []


def _matched_facets(
    store: Store,
    basis: dict[str, list[str]],
) -> dict[str, list[str]]:
    """이번 질문·선택(basis)과 실제로 겹친 태그만 남긴다. 원본 facet 전체를 내보내지 않는다."""
    facets = _facets(store)
    matched: dict[str, list[str]] = {}
    for axis, wanted in basis.items():
        allowed = set(wanted)
        hit = [value for value in facets.get(axis, ()) if value in allowed]
        if hit:
            matched[axis] = hit
    return matched


def _reason(matched: dict[str, list[str]]) -> str | None:
    """검증된 태그에서만 문장을 조립한다. 태그가 없으면 이유를 생략한다(2절)."""
    parts = [
        _REASON_TEMPLATES[axis].format(values="·".join(matched[axis]))
        for axis in _QUESTION_AXIS_ORDER
        if matched.get(axis) and axis in _REASON_TEMPLATES
    ]
    return " ".join(parts) or None


def _is_current_floor(floor: Floor, current_floor_id: str | None) -> bool:
    return current_floor_id is not None and current_floor_id in (floor.name, floor.id)


def _dedupe_by_name(
    rows: list[tuple[Store, Floor]],
    current_floor_id: str | None,
) -> list[tuple[Store, Floor]]:
    """같은 이름은 한 건만 남긴다 — 다양성 보정의 1순위(1-6절).

    코퍼스의 67%가 편의시설이고 엘리베이터·에스컬레이터는 12개 층에 같은 이름으로
    존재한다. 이름 축을 빼면 상위 N이 같은 시설의 층 목록으로 채워진다.

    대표로 남길 층은 관련도 1순위를 쓰되, 같은 이름이 현재 층에도 있으면 그쪽을
    고른다 — `current_floor_id`를 후보 제거가 아니라 정렬 보조로 쓰는 지점이다(8-2절 A안).
    """
    order: list[str] = []
    picked: dict[str, tuple[Store, Floor]] = {}
    for store, floor in rows:
        # 일반 매장·전 층 공용 시설은 이름으로 묶되, 출구는 같은 층에서도
        # 서로 다른 물리 선택지라 store id를 유지한다.
        key = store.id if _is_multi_physical_store(store) else (_norm(store.name or "") or store.id)
        if key not in picked:
            picked[key] = (store, floor)
            order.append(key)
        elif _is_current_floor(floor, current_floor_id) and not _is_current_floor(picked[key][1], current_floor_id):
            picked[key] = (store, floor)
    return [picked[key] for key in order]


def _diversify(
    rows: list[tuple[Store, Floor]],
    limit: int,
    *,
    axis: str | None = None,
) -> list[tuple[Store, Floor]]:
    """같은 소분류·같은 층 쏠림을 라운드로빈으로 완화한다(7-2절 7단계).

    이름 중복 제거(_dedupe_by_name)를 먼저 거친 목록을 받는다. 버킷 순서는 관련도
    순서(각 버킷의 첫 등장 순)를 그대로 따르므로, 1순위 후보는 항상 1순위로 남는다.

    `axis`를 주면 소분류 대신 그 축의 값으로 버킷을 나눈다. clarify의 초기 후보를
    "서로 다른 성격"으로 보여주기 위해서다(4-2절) — 스타일을 되묻는 화면의 미리보기가
    전부 같은 스타일이면 질문의 근거가 보이지 않는다.
    """
    buckets: dict[tuple[str, str], list[tuple[Store, Floor]]] = {}
    for store, floor in rows:
        if axis is None:
            group = _norm(store.subcategory or "")
        else:
            values = _facets(store).get(axis, ())
            group = values[0] if values else ""
        buckets.setdefault((group, floor.name), []).append((store, floor))

    picked: list[tuple[Store, Floor]] = []
    while len(picked) < limit:
        progressed = False
        for bucket in buckets.values():
            if not bucket:
                continue
            picked.append(bucket.pop(0))
            progressed = True
            if len(picked) >= limit:
                break
        if not progressed:
            break
    return picked


def _to_discovery_match(
    store: Store,
    floor: Floor,
    transform: GeoTransform | None,
    basis: dict[str, list[str]],
) -> dict[str, Any]:
    matched = _matched_facets(store, basis) if basis else {}
    return {**_to_match(store, floor, transform), "matched_facets": matched, "reason": _reason(matched)}


def _discovery_matches(
    candidates: list[tuple[Store, Floor]],
    limit: int,
    basis: dict[str, list[str]],
    transform: GeoTransform | None,
    axis: str | None = None,
) -> list[dict[str, Any]]:
    return [
        _to_discovery_match(store, floor, transform, basis) for store, floor in _diversify(candidates, limit, axis=axis)
    ]


def _discovery(
    text: str,
    mode: str,
    *,
    source: str,
    question: str | None = None,
    options: list[dict[str, Any]] | None = None,
    matches: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    return {
        "mode": mode,
        "query": text,
        "source": source,
        "question": question,
        "options": options or [],
        "matches": matches or [],
    }


def discover(
    session: Session,
    building_id: str,
    text: str,
    *,
    current_floor_id: str | None = None,
    selected_facets: dict[str, list[str]] | None = None,
    show_all: bool = False,
) -> dict[str, Any] | None:
    """탐색 질의. 명확하면 바로 안내하고, 넓으면 되묻거나 여러 후보를 추천한다.

    stateless다 — 서버 세션이 없고, 클라이언트가 매 요청에 원문과 현재 선택을 다시 보낸다.

    판정 순서(7-2절):
      1. 경량 1차가 단일 대상으로 확정되면 `direct`. 선택(facet)이 이미 있으면 건너뛴다.
      2. 확정 실패면 후보 집합을 만든다. 경량 후보가 있으면 그것을, 없으면 2차 의미 검색 상위 N을.
      3. `selected_facets`로 좁힌다. 좁힌 결과가 0건이면 선택을 해제하고 전체 후보 판정으로
         되돌아간다(→ 대개 clarify로 복귀) — 막다른 흐름을 만들지 않기 위해서다
         (2절 "결과가 없는데 계속 세분화 질문"). option은 항상 실제 후보가 있는 값만
         만들므로, 이 되돌림은 화면에 없던 축을 클라이언트가 보냈을 때만 일어난다.
      4. 이름 중복 제거 → 후보가 넓고 구분력 있는 축이 있으면 `clarify`, 아니면 `results`.
         `show_all=True`이면 후보·선택 계산은 그대로 두고 clarify만 건너뛰어 `results`를 준다.

    `current_floor_id`는 8-2절 A안이다. 1차 경량(tier 0·1 시설 질의)은 층 스코프를 유지해
    "화장실"이 현재 층에서 확정되게 하고, 탐색 후보 집합은 건물 전체를 보되 같은 이름이
    현재 층에도 있으면 그 층을 대표로 고르는 정렬 보조로만 쓴다.

    응답의 `source`는 **이 후보가 어휘로 잡힌 것인지 임베딩으로 잡힌 것인지**를 알린다.
    클라이언트가 온디바이스 이름 후보와 이 응답 중 무엇을 보여줄지 판단하는 근거다 —
    이름 후보는 임베딩(`semantic`)에는 이기지만 어휘(`light`)에는 진다. 근거는
    docs/client/search-input-assist.md 「실기기 검증」 2번.
    """
    if session.get(Building, building_id) is None:
        return None

    selection = {axis: list(values) for axis, values in (selected_facets or {}).items() if values}
    transform = fit_building_geo_transform(session, building_id)

    building_rows = _load_stores(session, building_id)
    building_scored = _rank_with_candidate(building_rows, text)
    floor_scoped = (
        _rank_with_candidate(
            _load_stores(session, building_id, current_floor_id=current_floor_id),
            text,
        )
        if current_floor_id is not None
        else building_scored
    )

    if not selection:
        # 층 스코프 1차가 우선 — 현재 층에 있는 시설을 그 층에서 확정한다.
        for scored in (floor_scoped, building_scored):
            if _is_confident_light_match(scored):
                *_, store, floor = scored[0]
                # 한 건으로 확정돼도 intent로 걸린 것이면 그 근거를 남긴다 —
                # 확정 여부와 "왜 이게 답인지"는 별개다.
                basis = _intent_basis(_query_matched_intents([(store, floor)], text))
                return _discovery(
                    text,
                    "direct",
                    source=SOURCE_LIGHT,
                    matches=[_to_discovery_match(store, floor, transform, basis)],
                )

    # 탐색 후보 집합. 경량이 잡은 게 있으면(카테고리·소분류 정확 일치 등) 그것이
    # 의미 검색보다 정밀하므로 먼저 쓴다.
    # 현재 층에서 여러 출구가 맞으면 다른 층의 동명 출구를 섞지 않는다. 이
    # 정책은 Store에 시설 kind가 없는 데모 데이터의 명시적 보완이다.
    if current_floor_id is not None and _is_multi_physical_query(text):
        current_floor_physical = [
            (store, floor) for *_rank, store, floor in floor_scoped if _is_multi_physical_store(store)
        ]
        pool = current_floor_physical or [(store, floor) for *_rank, store, floor in building_scored]
    else:
        pool = [(store, floor) for *_rank, store, floor in building_scored]

    degraded = False
    # 후보가 어디서 왔는지. 아래 모든 반환이 이 값을 그대로 싣는다 — 경로마다 따로
    # 판단하면 한 갈래만 고쳐도 계약이 갈라진다.
    source = SOURCE_LIGHT
    if not pool:
        # import는 여기서 지연 — 2차를 실제로 쓸 때만 torch를 로드한다.
        from app.repositories import query_semantic

        source = SOURCE_SEMANTIC
        results = query_semantic.search_many(session, building_id, text)
        degraded = results.is_degraded
        pool = [(store, floor) for _score, store, floor in results.hits]

    if selection:
        narrowed = [row for row in pool if _matches_selection(row[0], selection)]
        if narrowed:
            pool = narrowed
        else:
            selection = {}  # 선택을 해제하고 전체 후보를 보여준다(막다른 흐름 방지)

    candidates = _dedupe_by_name(pool, current_floor_id)

    if not candidates:
        return _discovery(text, "degraded" if degraded else "no_match", source=source)

    if degraded:
        # 의미 검색 기능 자체를 못 쓰는 상태. 경량·태그로 얻은 결과라도 담아 준다(8-3절).
        # 지금 구조에서는 경량 후보가 하나라도 있으면 2차를 아예 부르지 않으므로
        # (degraded 판정 자체가 서지 않는다) 이 가지의 matches는 사실상 비어 있다.
        # 계약을 맞춰 두는 이유는 나중에 경량 후보를 2차로 넓히게 되면 이 자리가
        # 그대로 "경량 결과 + 제한 안내"가 되기 때문이다.
        return _discovery(
            text,
            "degraded",
            source=source,
            matches=_discovery_matches(candidates, MAX_DISCOVERY_MATCHES, {}, transform),
        )

    # 후보 집합이 왜 모였는지의 근거. 질문 축과 별개로 모든 mode에 실린다.
    intent_basis = _intent_basis(_query_matched_intents(candidates, text))

    if selection or show_all:
        # 선택으로 좁힌 결과도 목록 상한을 쓴다. chip에는 `컨템포러리 (61)`처럼
        # **후보 수가 적혀 있다.** 61이라고 적힌 것을 눌렀는데 5건이 오면 나머지 56건은
        # 어디로 갔는지 알 방법이 없다. 숫자를 보여 준 이상 그만큼 도달할 수 있어야 한다.
        return _discovery(
            text,
            "results",
            source=source,
            matches=_discovery_matches(candidates, MAX_RESULT_MATCHES, {**intent_basis, **selection}, transform),
        )

    if len(candidates) > MAX_DISCOVERY_MATCHES:
        axis, options = _pick_question(candidates, intent_basis.get("intents"))
        if axis is not None:
            # 질문 축이 intents여도 **질의가 가리킨 intent를 덮지 않는다.** 덮으면
            # 사용자가 친 말이 reason에서 사라진다 — `신발` 질의에 "의류 관련
            # 매장이에요"만 남는 식이다([_query_matched_intents] 주석의 실패 조건).
            #
            # 오래 안 드러났던 이유는 intents가 질문 축이 되는 일이 드물어서다.
            # `신발`의 후보는 전부 `의류`도 함께 갖고 있어 구분력이 없었고 축은
            # styles로 떨어졌다. 신발 브랜드를 `슈즈` 소분류로 모으자 `의류`가
            # 전 후보를 덮지 않게 되면서 이 자리가 처음 밟혔다.
            option_values = [option["value"] for option in options]
            basis = {
                **intent_basis,
                axis: [*intent_basis.get(axis, ()), *option_values],
            }
            # 초기 후보는 그 축의 태그가 있는 매장에서 고른다 — 미태깅 매장이 섞이면
            # 질문의 근거(reason)가 비어 보인다. 태그된 후보가 없으면 전체에서 고른다.
            preview = [row for row in candidates if _facets(row[0]).get(axis)]
            return _discovery(
                text,
                "clarify",
                source=source,
                question=_QUESTION_TEMPLATES[axis],
                options=options,
                matches=_discovery_matches(
                    preview or candidates,
                    CLARIFY_PREVIEW_MATCHES,
                    basis,
                    transform,
                    axis=axis,
                ),
            )

    # 구분력 있는 축이 없으면 억지로 되묻지 않는다 — 다양성 보정된 목록을 그대로 준다.
    #
    # 이 자리가 곧 최종 답이라 목록 상한을 쓴다. 추천 상한(5)을 쓰던 시절 "커피"는
    # 카페 53곳 중 5곳만 보여줬고, 되물음이 없으니 화면에 "전체 보기"도 없어서
    # 나머지로 갈 길이 아예 없었다.
    return _discovery(
        text,
        "results",
        source=source,
        matches=_discovery_matches(candidates, MAX_RESULT_MATCHES, intent_basis, transform),
    )


# 정보 질의. 최적 1건 + 대상이 존재하는 층 목록(level 오름차순)을 반환.
def match_info(
    session: Session,
    building_id: str,
    text: str,
    *,
    current_floor_id: str | None = None,
) -> dict[str, Any] | None:
    if session.get(Building, building_id) is None:
        return None

    scored = _rank(
        _load_stores(session, building_id, current_floor_id=current_floor_id),
        text,
    )
    if not scored:
        return {"status": "no_match", "query": text, "match": None, "floors": []}

    _, _, _, store, floor = scored[0]
    transform = fit_building_geo_transform(session, building_id)

    # 같은 이름이 여러 층에 있으면 그 이름의 층만 모은다. 낮은 tier의 다른 부분
    # 일치 매장까지 섞으면 "A.P.C." 응답에 "A.P.C 골프" 층이 붙을 수 있다.
    floors = _floor_names_for_match(scored, store.name or "")

    return {
        "status": "ok",
        "query": text,
        "match": _to_match(store, floor, transform),
        "floors": floors,
    }
