"""store_facets 순수 함수 단위 테스트.

이 모듈은 DB·시드를 모르는 순수 함수라서 db_session fixture가 필요 없다.
파일 I/O가 필요한 load_overlay 테스트만 tmp_path로 임시 디렉터리를 만든다.
"""

from __future__ import annotations

import json

import pytest

from app.repositories import store_facets

# ── derive_facets ────────────────────────────────────────────────────────


# wave1/README.md에 확정된 5줄 매핑이 그대로 구현됐는지 하나씩 확인한다.
def test_소분류_5개가_각각_맞는_styles로_파생된다():
    assert store_facets.derive_facets("패션", "스포츠·아웃도어") == {"styles": ["스포츠"]}
    assert store_facets.derive_facets("패션", "캐주얼·스트리트") == {"styles": ["캐주얼"]}
    assert store_facets.derive_facets("패션", "컨템포러리") == {"styles": ["컨템포러리"]}
    assert store_facets.derive_facets("패션", "명품") == {"styles": ["명품"]}
    assert store_facets.derive_facets("패션", "골프") == {"styles": ["골프"]}


# 매핑에 없는 소분류(품목 축)는 styles 키 자체가 생기면 안 된다 — 빈 배열도 금지.
def test_매핑에_없는_소분류는_키가_안_생긴다():
    assert store_facets.derive_facets("패션", "슈즈") == {}
    assert store_facets.derive_facets("패션", "잡화·액세서리") == {}
    assert store_facets.derive_facets("패션", "시계·주얼리") == {}
    assert store_facets.derive_facets(None, None) == {}


def test_derive_facets는_category를_쓰지_않고_subcategory만_본다():
    # category가 달라도 subcategory가 같으면 같은 결과 — 함수가 category를 무시한다는
    # 계약을 문서화하는 회귀 테스트.
    assert store_facets.derive_facets("아무거나", "골프") == {"styles": ["골프"]}


# ── resolve_facets ───────────────────────────────────────────────────────


def test_오버레이가_없으면_파생값만_돌아온다():
    result = store_facets.resolve_facets("PO-1", "패션", "명품", overlay={})
    assert result == {"styles": ["명품"]}


# 오버레이가 파생을 이긴다 — 축 단위 병합(다른 축은 파생값을 유지).
def test_오버레이가_같은_축의_파생값을_이긴다():
    overlay = {"PO-1": {"name": "탠디", "styles": ["스포츠", "캐주얼"]}}
    result = store_facets.resolve_facets("PO-1", "패션", "슈즈", overlay=overlay)
    # 슈즈는 파생이 없으므로 오버레이 값이 그대로 최종 결과다.
    assert result == {"styles": ["스포츠", "캐주얼"]}


def test_오버레이는_축_단위로만_덮고_다른_축의_파생값은_보존한다():
    # cuisines처럼 아직 derive_facets가 모르는 축이라도, 오버레이가 그 축만 추가하면
    # styles 파생값은 그대로 남아야 한다(통째로 갈아치우지 않는다는 설계 근거).
    overlay = {"PO-1": {"cuisines": ["일식"]}}
    result = store_facets.resolve_facets("PO-1", "패션", "명품", overlay=overlay)
    assert result == {"styles": ["명품"], "cuisines": ["일식"]}


def test_오버레이가_빈_배열을_주면_해당_축을_제거한다():
    overlay = {"PO-1": {"styles": []}}
    result = store_facets.resolve_facets("PO-1", "패션", "명품", overlay=overlay)
    assert result == {}


def test_name은_facet_축으로_취급하지_않는다():
    overlay = {"PO-1": {"name": "탠디"}}
    result = store_facets.resolve_facets("PO-1", "패션", "슈즈", overlay=overlay)
    assert result == {}


# ── load_overlay ─────────────────────────────────────────────────────────


def test_파일도_디렉터리도_없으면_빈_dict를_돌려준다(tmp_path):
    missing = tmp_path / "does-not-exist"
    assert store_facets.load_overlay(missing) == {}


def test_밑줄로_시작하는_파일은_무시하고_나머지_json을_병합한다(tmp_path):
    (tmp_path / "_vocabulary.json").write_text(
        json.dumps({"version": 1, "vocabulary": {"styles": ["스포츠"]}}, ensure_ascii=False),
        encoding="utf-8",
    )
    (tmp_path / "fashion.json").write_text(
        json.dumps(
            {"version": 1, "stores": {"PO-1": {"name": "탠디", "styles": ["캐주얼"]}}},
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    (tmp_path / "food.json").write_text(
        json.dumps(
            {"version": 1, "stores": {"PO-2": {"name": "본가 스시", "cuisines": ["일식"]}}},
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )

    result = store_facets.load_overlay(tmp_path)

    assert result == {
        "PO-1": {"name": "탠디", "styles": ["캐주얼"]},
        "PO-2": {"name": "본가 스시", "cuisines": ["일식"]},
    }


def test_같은_store_id가_두_파일에_있으면_오류다(tmp_path):
    (tmp_path / "a.json").write_text(
        json.dumps({"version": 1, "stores": {"PO-1": {"styles": ["캐주얼"]}}}, ensure_ascii=False),
        encoding="utf-8",
    )
    (tmp_path / "b.json").write_text(
        json.dumps({"version": 1, "stores": {"PO-1": {"styles": ["명품"]}}}, ensure_ascii=False),
        encoding="utf-8",
    )

    # 중복 store_id는 예외를 던져야 한다.
    with pytest.raises(ValueError, match="PO-1"):
        store_facets.load_overlay(tmp_path)


# ── validate_overlay ─────────────────────────────────────────────────────


VOCAB = {"styles": ["스포츠", "캐주얼", "컨템포러리", "명품", "골프"]}
KNOWN_IDS = {"PO-1", "PO-2"}
NAMES = {"PO-1": "탠디", "PO-2": "본가 스시"}


def _overlay(stores: dict) -> dict:
    return {"version": 1, "stores": stores}


def test_정상_오버레이는_오류가_없다():
    overlay = _overlay({"PO-1": {"name": "탠디", "styles": ["캐주얼"]}})
    assert store_facets.validate_overlay(overlay, VOCAB, KNOWN_IDS, NAMES) == []


def test_version_미지원을_잡는다():
    overlay = {"version": 2, "stores": {}}
    errors = store_facets.validate_overlay(overlay, VOCAB, KNOWN_IDS, NAMES)
    assert len(errors) == 1
    assert "version" in errors[0]


def test_고아_store_id를_잡는다():
    overlay = _overlay({"PO-999": {"styles": ["캐주얼"]}})
    errors = store_facets.validate_overlay(overlay, VOCAB, KNOWN_IDS, NAMES)
    assert any("PO-999" in e and "존재하지 않는" in e for e in errors)


def test_name_불일치를_잡는다():
    overlay = _overlay({"PO-1": {"name": "완전 다른 이름", "styles": ["캐주얼"]}})
    errors = store_facets.validate_overlay(overlay, VOCAB, KNOWN_IDS, NAMES)
    assert any("name" in e for e in errors)


def test_vocabulary_밖의_값을_잡는다():
    overlay = _overlay({"PO-1": {"styles": ["구두·정장"]}})
    errors = store_facets.validate_overlay(overlay, VOCAB, KNOWN_IDS, NAMES)
    assert any("구두·정장" in e for e in errors)


def test_배열_내_중복_태그를_잡는다():
    overlay = _overlay({"PO-1": {"styles": ["캐주얼", "캐주얼"]}})
    errors = store_facets.validate_overlay(overlay, VOCAB, KNOWN_IDS, NAMES)
    assert any("중복" in e for e in errors)


def test_문자열이_아닌_태그_값을_잡는다():
    overlay = _overlay({"PO-1": {"styles": ["캐주얼", 123]}})
    errors = store_facets.validate_overlay(overlay, VOCAB, KNOWN_IDS, NAMES)
    assert any("문자열이 아닌" in e for e in errors)


def test_vocabulary에_없는_축_자체도_잡는다():
    overlay = _overlay({"PO-1": {"cuisines": ["일식"]}})
    errors = store_facets.validate_overlay(overlay, VOCAB, KNOWN_IDS, NAMES)
    assert any("cuisines" in e for e in errors)


def test_한_매장에_여러_오류가_있으면_전부_모은다():
    overlay = _overlay(
        {
            "PO-999": {"styles": ["캐주얼"]},  # 고아
            "PO-1": {"styles": ["구두·정장", "구두·정장"]},  # vocab 밖 + 중복
        }
    )
    errors = store_facets.validate_overlay(overlay, VOCAB, KNOWN_IDS, NAMES)
    assert len(errors) >= 2


# ── facet_coverage_report ────────────────────────────────────────────────


def test_커버리지_보고서는_건물별_대분류별_적용률을_센다():
    stores = [
        {
            "store_id": "PO-1",
            "building_id": "thehyundai-seoul",
            "category": "패션",
            "subcategory": "명품",
        },
        {
            "store_id": "PO-2",
            "building_id": "thehyundai-seoul",
            "category": "패션",
            "subcategory": "슈즈",  # 파생도 오버레이도 없음 → 태그 없음
        },
    ]
    report = store_facets.facet_coverage_report(stores, overlay={})

    assert report["by_building"]["thehyundai-seoul"] == {"total": 2, "tagged": 1}
    assert report["by_category"]["패션"] == {"total": 2, "tagged": 1}


def test_태그_없는_매장은_실패가_아니라_커버리지_분모에만_잡힌다():
    stores = [
        {"store_id": "PO-2", "building_id": "b1", "category": "패션", "subcategory": "슈즈"},
    ]
    report = store_facets.facet_coverage_report(stores, overlay={})
    assert report["by_building"]["b1"]["total"] == 1
    assert report["by_building"]["b1"]["tagged"] == 0


# ── intents (load_intents / resolve_intent_store_ids / validate_intents) ──


# 규칙·extra·제외를 한 번에 확인할 수 있는 최소 매장 목록.
# 슈즈 2건 + 레스토랑 2건 + 규칙에 안 잡히는 캐주얼·스트리트 1건(= extra 대상) 구성.
INTENT_STORES = [
    {"store_id": "PO-슈즈1", "name": "탠디", "category": "패션", "subcategory": "슈즈"},
    {"store_id": "PO-슈즈2", "name": "크록스", "category": "패션", "subcategory": "슈즈"},
    {
        "store_id": "PO-나이키",
        "name": "나이키 라이즈",
        "category": "패션",
        "subcategory": "캐주얼·스트리트",
    },
    {"store_id": "PO-식당1", "name": "본가 스시", "category": "음식점", "subcategory": "레스토랑"},
    {"store_id": "PO-식당2", "name": "공탕", "category": "음식점", "subcategory": "레스토랑"},
    # 먹거리지만 밥집이 아닌 것 — "식사"를 먹거리 대분류 기준으로 잡으면 여기가 섞인다.
    {"store_id": "PO-정육", "name": "정육 코너", "category": "식품관", "subcategory": "정육"},
]

INTENTS = {
    "신발": {
        "rules": {"subcategory": ["슈즈"]},
        "extra_store_ids": {"PO-나이키": "나이키 라이즈"},
    },
    "식사": {"rules": {"subcategory": ["레스토랑"]}},
}


def test_규칙이_소분류로_후보를_유도한다():
    assert store_facets.resolve_intent_store_ids("식사", INTENT_STORES, INTENTS) == {
        "PO-식당1",
        "PO-식당2",
    }


def test_extra_store_ids가_규칙_결과에_합쳐진다():
    assert store_facets.resolve_intent_store_ids("신발", INTENT_STORES, INTENTS) == {
        "PO-슈즈1",
        "PO-슈즈2",
        "PO-나이키",
    }


# "식사"는 먹거리 대분류가 아니라 subcategory=레스토랑 기준이다(설계 문서 결정).
# 대분류 기준이면 정육·야채·수산이 "밥집" 질의에 섞여 들어온다.
def test_식사는_category가_아니라_subcategory_기준이다():
    result = store_facets.resolve_intent_store_ids("식사", INTENT_STORES, INTENTS)
    assert "PO-정육" not in result
    # 대조군: 같은 스키마로 먹거리 대분류(음식점·식품관)를 규칙에 적으면 정육이 실제로
    # 섞인다 — 왜 subcategory를 골랐는지 코드로 남겨 두는 회귀 테스트다.
    category_based = {"식사": {"rules": {"category": ["음식점", "식품관"]}}}
    assert "PO-정육" in store_facets.resolve_intent_store_ids("식사", INTENT_STORES, category_based)


def test_excluded_store_ids는_규칙_결과에서_빠진다():
    intents = {
        "신발": {
            "rules": {"subcategory": ["슈즈"]},
            "excluded_store_ids": {"PO-슈즈2": "크록스"},
        }
    }
    assert store_facets.resolve_intent_store_ids("신발", INTENT_STORES, intents) == {"PO-슈즈1"}


# ── resolve_intents — 같은 규칙을 매장 관점에서 본다 ─────────────────────────
# 시드가 매장을 한 건씩 조립하므로 매장별 함수가 필요하다. 집합 함수와 결과가
# 갈리면 "시드가 붙인 태그"와 "검색이 세는 후보"가 어긋나므로 함께 검증한다.


def test_resolve_intents는_규칙과_extra를_모두_돌려준다():
    by_id = {store["store_id"]: store for store in INTENT_STORES}

    assert store_facets.resolve_intents(by_id["PO-슈즈1"], INTENTS) == ["신발"]
    assert store_facets.resolve_intents(by_id["PO-나이키"], INTENTS) == ["신발"]
    assert store_facets.resolve_intents(by_id["PO-식당1"], INTENTS) == ["식사"]
    assert store_facets.resolve_intents(by_id["PO-정육"], INTENTS) == []


def test_resolve_intents는_excluded를_뺀다():
    intents = {
        "신발": {
            "rules": {"subcategory": ["슈즈"]},
            # 규칙으로 들어왔든 손으로 넣었든 결국 제외 — 두 경우를 모두 확인한다.
            "excluded_store_ids": {"PO-슈즈2": "크록스", "PO-나이키": "나이키 라이즈"},
            "extra_store_ids": {"PO-나이키": "나이키 라이즈"},
        }
    }
    by_id = {store["store_id"]: store for store in INTENT_STORES}

    assert store_facets.resolve_intents(by_id["PO-슈즈1"], intents) == ["신발"]
    assert store_facets.resolve_intents(by_id["PO-슈즈2"], intents) == []
    assert store_facets.resolve_intents(by_id["PO-나이키"], intents) == []


# 순서가 흔들리면 같은 매장이 실행마다 다른 임베딩 문서 텍스트를 만든다
# (query_semantic._document_text가 이 값을 그대로 쓴다).
def test_resolve_intents는_정의_파일_순서를_지킨다():
    store = {"store_id": "PO-슈즈1", "category": "패션", "subcategory": "슈즈"}
    forward = {"신발": {"rules": {"subcategory": ["슈즈"]}}, "선물": {"rules": {"subcategory": ["슈즈"]}}}
    backward = {"선물": {"rules": {"subcategory": ["슈즈"]}}, "신발": {"rules": {"subcategory": ["슈즈"]}}}

    assert store_facets.resolve_intents(store, forward) == ["신발", "선물"]
    assert store_facets.resolve_intents(store, backward) == ["선물", "신발"]


# 두 함수가 같은 규칙을 본다는 것을 실제 데이터 모양으로 못 박는다.
def test_resolve_intents와_집합_함수의_결과가_일치한다():
    for intent in INTENTS:
        by_set = store_facets.resolve_intent_store_ids(intent, INTENT_STORES, INTENTS)
        by_store = {
            store["store_id"] for store in INTENT_STORES if intent in store_facets.resolve_intents(store, INTENTS)
        }
        assert by_set == by_store, intent


def test_모르는_intent는_빈_집합이다():
    assert store_facets.resolve_intent_store_ids("카페", INTENT_STORES, INTENTS) == set()


# 규칙 필드 오타를 조용히 무시하면 조건이 사라져 후보가 넓어지는 방향으로 틀린다.
# ── facet 축 규칙(cuisines 등) ────────────────────────────────────────────

# 소분류가 같아도 요리가 갈리는 경우. 실데이터의 음식점 소분류는 `레스토랑`
# 하나뿐이라 이 모양이 곧 현실이다.
CUISINE_STORES = [
    {
        "store_id": "PO-양식1",
        "name": "이탈리 마켓",
        "category": "음식점",
        "subcategory": "레스토랑",
        "cuisines": ["양식"],
    },
    {
        "store_id": "PO-일식1",
        "name": "본가 스시",
        "category": "음식점",
        "subcategory": "레스토랑",
        "cuisines": ["일식"],
    },
    # 요리 축이 아예 없는 매장. 규칙에 걸리면 안 된다.
    {"store_id": "PO-옷1", "name": "펜디", "category": "패션", "subcategory": "명품"},
]

CUISINE_INTENTS = {"양식": {"rules": {"cuisines": ["양식"]}}}


def test_facet_축_규칙이_배열_교집합으로_매칭된다():
    # 소분류로는 PO-양식1과 PO-일식1이 구분되지 않는다. 축이 그걸 가른다.
    assert store_facets.resolve_intent_store_ids("양식", CUISINE_STORES, CUISINE_INTENTS) == {"PO-양식1"}


def test_facet_축이_없는_매장은_규칙에_걸리지_않는다():
    assert store_facets.resolve_intents(CUISINE_STORES[2], CUISINE_INTENTS) == []


def test_facet_축_규칙은_값이_하나라도_겹치면_잡는다():
    store = {
        "store_id": "PO-복합",
        "name": "퓨전",
        "category": "음식점",
        "subcategory": "레스토랑",
        "cuisines": ["한식", "양식"],
    }
    assert store_facets.resolve_intents(store, CUISINE_INTENTS) == ["양식"]


def test_facet_축도_실데이터에_없는_값을_검증에서_잡는다():
    # 스칼라 필드와 같은 방어다 — 오버레이에서 요리 값이 빠지면 규칙이 조용히
    # 0건이 되는 것을 시드 전에 잡아야 한다.
    payload = {"version": 1, "intents": {"태국": {"rules": {"cuisines": ["태국"]}}}}
    errors = store_facets.validate_intents(payload, CUISINE_STORES)
    assert any("실데이터에 없는 값" in e and "태국" in e for e in errors)


def test_규칙에_쓸_수_없는_필드는_예외다():
    intents = {"신발": {"rules": {"subcategory_kr": ["슈즈"]}}}
    # 지원하지 않는 규칙 필드는 예외를 던져야 한다.
    with pytest.raises(ValueError, match="subcategory_kr"):
        store_facets.resolve_intent_store_ids("신발", INTENT_STORES, intents)


def test_intents_파일이_없으면_빈_dict다(tmp_path):
    # 디렉터리는 있지만 _intents.json이 없는 경우와, 경로 자체가 없는 경우 모두.
    assert store_facets.load_intents(tmp_path) == {}
    assert store_facets.load_intents(tmp_path / "없는파일.json") == {}


def test_load_intents는_디렉터리와_파일_경로를_모두_받는다(tmp_path):
    payload = {"version": 1, "intents": {"신발": {"rules": {"subcategory": ["슈즈"]}}}}
    file = tmp_path / store_facets.INTENTS_FILENAME
    file.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")

    assert store_facets.load_intents(tmp_path) == payload["intents"]
    assert store_facets.load_intents(file) == payload["intents"]


# _로 시작하므로 오버레이 로더는 이 파일을 매장 태그로 읽어선 안 된다.
def test_intents_파일은_오버레이로_읽히지_않는다(tmp_path):
    (tmp_path / store_facets.INTENTS_FILENAME).write_text(
        json.dumps({"version": 1, "intents": {"신발": {"rules": {"subcategory": ["슈즈"]}}}}),
        encoding="utf-8",
    )
    assert store_facets.load_overlay(tmp_path) == {}


def _intents_payload(intents: dict) -> dict:
    return {"version": 1, "intents": intents}


def test_정상_intents는_오류가_없다():
    assert store_facets.validate_intents(_intents_payload(INTENTS), INTENT_STORES) == []


def test_intents_version_미지원을_잡는다():
    errors = store_facets.validate_intents({"version": 2, "intents": {}}, INTENT_STORES)
    assert len(errors) == 1
    assert "version" in errors[0]


def test_extra의_고아_id를_잡는다():
    payload = _intents_payload(
        {"신발": {"rules": {"subcategory": ["슈즈"]}}, "선물": {"extra_store_ids": {"PO-없음": "유령"}}}
    )
    errors = store_facets.validate_intents(payload, INTENT_STORES)
    assert any("PO-없음" in e and "존재하지 않는" in e for e in errors)


# 규칙이 이미 잡는 매장을 extra에 또 적으면 같은 정보를 두 벌로 들게 된다(드리프트의 씨앗).
def test_규칙이_이미_잡는_매장이_extra에_있으면_중복으로_잡는다():
    payload = _intents_payload({"신발": {"rules": {"subcategory": ["슈즈"]}, "extra_store_ids": {"PO-슈즈1": "탠디"}}})
    errors = store_facets.validate_intents(payload, INTENT_STORES)
    assert any("PO-슈즈1" in e and "중복" in e for e in errors)


# 소분류가 Studio에서 바뀌면 규칙이 조용히 0건이 된다 — 그걸 잡는 검사.
def test_실데이터에_없는_규칙_값을_잡는다():
    payload = _intents_payload({"식사": {"rules": {"subcategory": ["레스토랑 "]}}})
    errors = store_facets.validate_intents(payload, INTENT_STORES)
    assert any("레스토랑 " in e and "실데이터에 없는" in e for e in errors)


def test_규칙에_쓸_수_없는_필드를_검증에서도_잡는다():
    payload = _intents_payload({"신발": {"rules": {"floor": ["4F"]}}})
    errors = store_facets.validate_intents(payload, INTENT_STORES)
    assert any("floor" in e for e in errors)


def test_extra의_name_불일치를_잡는다():
    payload = _intents_payload(
        {"신발": {"rules": {"subcategory": ["슈즈"]}, "extra_store_ids": {"PO-나이키": "다른 이름"}}}
    )
    errors = store_facets.validate_intents(payload, INTENT_STORES)
    assert any("PO-나이키" in e and "name" in e for e in errors)


def test_규칙도_extra도_없는_intent를_잡는다():
    errors = store_facets.validate_intents(_intents_payload({"카페": {}}), INTENT_STORES)
    assert any("카페" in e for e in errors)


def test_빈_규칙_배열을_잡는다():
    payload = _intents_payload({"신발": {"rules": {"subcategory": []}}})
    errors = store_facets.validate_intents(payload, INTENT_STORES)
    assert any("subcategory" in e for e in errors)


# 규칙이 바뀌어 후보가 아니게 된 매장이 excluded에 남아 있으면 찌꺼기다.
def test_후보가_아닌_매장을_excluded에_적으면_잡는다():
    payload = _intents_payload(
        {"신발": {"rules": {"subcategory": ["슈즈"]}, "excluded_store_ids": {"PO-식당1": "본가 스시"}}}
    )
    errors = store_facets.validate_intents(payload, INTENT_STORES)
    assert any("PO-식당1" in e for e in errors)


# ── 실제 배포 파일 회귀 검사 ──────────────────────────────────────────────


# W12에서 소분류 규칙으로 메운 intent들. 소분류 하나 → 그 소분류로 결정적으로 유도되는
# intent 이름이며, 사람이 매장별로 판단해야 하는 값(`선물` 등)은 여기 없다.
_W12_BY_SUBCATEGORY = {
    "시계·주얼리": ("시계", "주얼리"),
    "잡화·액세서리": ("잡화", "액세서리", "가방"),
    "가구·인테리어": ("가구", "인테리어"),
    "가전·디지털": ("가전", "디지털"),
    "리빙·주방": ("리빙", "주방", "그릇"),
    "침구·매트리스": ("침구", "매트리스", "침대"),
    "문구·팬시": ("문구", "팬시"),
    "플라워": ("꽃",),
    "토이·완구": ("토이", "완구", "장난감"),
    "유아·아동": ("유아", "아동", "아동복"),
    "식품·그로서리": ("식품", "그로서리", "장보기"),
    "와인·주류": ("와인", "주류"),
    "문화·예술": ("문화", "예술", "전시"),
    "의료·약국": ("의료", "약국", "병원"),
    "고객서비스": ("고객센터",),
    "뷰티살롱": ("미용실",),
}
_W12_INTENTS = tuple(name for names in _W12_BY_SUBCATEGORY.values() for name in names)


# 실데이터 대조(고아 id·소분류 일치)는 시드 경로에서 validate_intents가 하고, 여기서는
# 파일이 파싱되고 사람이 검수한 범위(P3 판정 예 145건)가 그대로인지만 지킨다.
def test_배포된_intents_파일이_검수_범위를_유지한다():
    from pathlib import Path

    # 이 파일 위치(tests/unit/query) 기준 backend 루트는 3단계 위다.
    path = Path(__file__).resolve().parents[3] / "resources" / "store_search_facets"
    intents = store_facets.load_intents(path)

    assert set(intents) == {
        "신발",
        "식사",
        "카페",
        "화장품",
        "향수",
        "의류",
        "출구",
        # 요리 분류. 「양식」이 intent에 없어서 의미검색으로 떨어졌고, 임베딩이
        # 洋食이 아니라 養殖으로 읽어 「수산」을 물어 왔다. 소분류로는 못 잡는다 —
        # 음식점 소분류는 `레스토랑` 하나뿐이라 한식·일식·중식·양식이 전부 같은
        # 칸에 있고, 그 구분은 `cuisines` 오버레이에만 있다.
        "양식",
        "한식",
        "일식",
        "중식",
        # W12. intent가 0건이던 대분류(리빙·서비스·식품관·키즈)를 소분류 규칙으로 메웠다.
        # 복합 라벨(`A·B`)은 양쪽 단어를 모두 선언한다 — 한쪽만 넣으면 그 단어가 문서
        # 텍스트에 두 번 들어가 나머지를 밀어낸다(FAISS.md 11-4의 화장품/향수 회귀).
        *_W12_INTENTS,
    }
    assert intents["신발"]["rules"] == {"subcategory": ["슈즈"]}
    # 먹거리 intent는 소분류가 아니라 **대분류**를 본다. 대분류 재편으로
    # category=음식점이 subcategory=레스토랑과 같은 집합이 됐고, 지도 필터 pill과
    # 같은 축을 봐야 나중에 음식점 밑에 소분류가 늘어도 함께 따라온다.
    # 근거는 store_facets.py 모듈 주석.
    assert intents["식사"]["rules"] == {"category": ["음식점"]}
    assert intents["카페"]["rules"] == {"category": ["카페"]}
    # P3 검수 결과 = 예 145건. 규칙이 잡는 슈즈 소분류는 extra에 없어야 한다.
    #
    # 148이 아니라 142인 이유: 공식 층별안내로 카테고리를 다시 매기면서 버윅·
    # 아떼바네사브루노·쿠에른 셋이 3F `슈즈&백 갤러리` 소속으로 잡혀 규칙이 직접
    # 가져간다. 검수 결과가 줄어든 게 아니라 **손으로 적을 필요가 없어진 것**이라,
    # 셋을 남겨 두면 오히려 중복으로 리소스 검증이 죽는다.
    # (docs/backend/store-category-resurvey.md 「소분류는 검색이 붙잡고 있다」)
    assert len(intents["신발"]["extra_store_ids"]) == 142
    assert "extra_store_ids" not in intents["식사"]

    # 확장분(W9)은 소분류에서 결정적으로 유도되는 규칙만 쓴다. 매장별 판단이 필요한
    # extra 목록을 사람 검수 없이 늘리지 않는다는 게 이 단언의 요지다 — 유일한 예외는
    # 소분류가 생활편의로 잘못 붙은 지하철 출입구 2건이다.
    for intent in ("카페", "화장품", "향수", "의류"):
        assert "extra_store_ids" not in intents[intent], intent
    assert len(intents["출구"]["extra_store_ids"]) == 2

    # 요리 intent도 같은 원칙이다 — 매장 id를 손으로 나열하지 않고 facet 축
    # 규칙만 쓴다. extra로 굽기 시작하면 요리 분류가 바뀔 때 오버레이와 intent
    # 목록이 따로 논다(store_facets._FACET_RULE_FIELDS 주석).
    for intent in ("양식", "한식", "일식", "중식"):
        assert intents[intent]["rules"] == {"cuisines": [intent]}, intent
        assert "extra_store_ids" not in intents[intent], intent

    # W12도 같은 원칙이다 — 소분류 규칙만 쓰고 extra로 매장을 손으로 굽지 않는다.
    # 규칙이 **잘못 끌어오는** 것을 빼는 excluded만 예외이고, 지금은 `가방` 하나뿐이다
    # (`잡화·액세서리` 18건 중 우산·폰케이스·모자 3건).
    for subcategory, names in _W12_BY_SUBCATEGORY.items():
        for intent in names:
            assert intents[intent]["rules"] == {"subcategory": [subcategory]}, intent
            assert "extra_store_ids" not in intents[intent], intent
            if intent != "가방":
                assert "excluded_store_ids" not in intents[intent], intent
    assert len(intents["가방"]["excluded_store_ids"]) == 3
