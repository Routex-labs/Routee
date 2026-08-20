"""공식 층별안내에서 만든 카테고리 매핑이 실데이터와 어긋나지 않는지 검증한다.

여기서 지키는 것은 값 하나하나가 아니라 **재조사가 뒤집히지 않는 조건**이다.
판단 근거는 docs/backend/store-category-resurvey.md.
"""

import json

import pytest

from scripts.transform.build_store_categories import (
    ID_MAP_PATH,
    OFFICIAL_PATH,
    OUTPUT_PATH,
    SECTION_MAP_PATH,
    build,
    normalize,
)

# 재조사로 확정한 대분류. `서비스`는 여기 없다 — 경계가 정의된 적이 없어
# 리테일·식당이 섞여 들어오던 자리라 없앴다.
EXPECTED_CATEGORIES = {
    "패션",
    "뷰티",
    "리빙",
    "식품관",
    "카페",
    "음식점",
    "키즈",
    "편의시설",
}


@pytest.fixture(scope="module")
def section_map() -> dict:
    return json.loads(SECTION_MAP_PATH.read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def name_map() -> dict:
    return json.loads(OUTPUT_PATH.read_text(encoding="utf-8"))


def test_매핑표가_공식_섹션을_전부_덮는다(section_map):
    # 섹션이 하나라도 빠지면 그 섹션 매장이 통째로 Studio 원본 카테고리로 떨어진다.
    official = json.loads(OFFICIAL_PATH.read_text(encoding="utf-8"))
    titles = {section["title"] for floor in official["floors"] for section in floor["sections"]}

    assert titles - set(section_map["sections"]) == set()


def test_서비스_대분류는_남아_있지_않다(name_map):
    categories = {entry["category"] for entry in name_map.values()}

    assert "서비스" not in categories
    assert categories <= EXPECTED_CATEGORIES


def test_id_맵이_이름_맵과_같은_값을_준다(name_map):
    # id 맵은 시드에서 **먼저** 적용되므로(studio_adapter._resolved_category)
    # 여기 옛 값이 남으면 새 매핑을 조용히 이긴다. 실제로 `생로랑`이 뷰티로,
    # `페어몬트 호텔`이 서비스로 남아 있었다.
    id_map = json.loads(ID_MAP_PATH.read_text(encoding="utf-8"))

    conflicts = [
        f"{entry['name']}: id={entry['category']}/{entry['subcategory']}"
        f" name={name_map[entry['name']]['category']}/{name_map[entry['name']]['subcategory']}"
        for entry in id_map.values()
        if entry["name"] in name_map
        and (entry["category"], entry["subcategory"])
        != (name_map[entry["name"]]["category"], name_map[entry["name"]]["subcategory"])
    ]

    assert conflicts == []


def test_alias가_가리키는_도면_이름이_실제로_있다():
    # 오타를 내면 조용히 매칭 실패로 흡수되어 "공식에만 있음"으로 잘못 보고된다.
    _, report = build()

    assert report["aliasMissing"] == []
    assert report["localOnlyMissing"] == []


def test_alias는_이름이_같아지도록_이어_붙이지_않는다(section_map):
    # 문자열 유사도만 보고 이으면 공식 `보스`(Bose 음향)가 도면 `보스 골프`(BOSS)에
    # 붙는다. alias는 정규화해도 서로 다른 이름을 잇는 장치이므로, 정규화 결과가
    # 같아지는 항목은 alias가 필요 없다는 뜻이다.
    aliases = {k: v for k, v in section_map["aliases"].items() if not k.startswith("_")}

    redundant = [k for k, v in aliases.items() if normalize(k) == normalize(v)]

    assert redundant == []


def test_생성_결과가_저장된_파일과_같다(name_map):
    # 매핑표만 고치고 스크립트를 안 돌리면 시드가 옛 값을 넣는다.
    mapping, _ = build()

    assert mapping == name_map
