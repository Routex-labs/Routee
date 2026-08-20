"""못 걷는 면 추출 규칙과 `--non-walkable-only`가 만든 층 JSON의 불변식."""

import json
from pathlib import Path

from scripts.transform.build_studio_from_dabeeo import (
    OUT,
    REGENERATION_ONLY_KINDS,
    non_walkable_shapes,
)

FLOOR_CODES = ["1f", "2f", "3f", "4f", "5f", "6f", "b1", "b2", "b3", "b4", "b5", "b6"]

# 되돌림(2026-08-15)을 부른 두 도형과, 그때 같이 빠져 버린 1F 폭포정원 곡선 둘.
# 규칙이 이 넷을 정확히 갈라야 같은 사고가 재발하지 않는다.
COVERING_SHAPE_IDS = ["OB-aGdAGsrQZB9337", "OB-q9sDeJsxE3558"]  # 1F 694m²·4F 2,483m²
WATERFALL_SHAPE_IDS = ["OB-PSPmym6Pk8548", "OB-bNYWWgirG78553"]  # 1F 46.8m²·56.3m²


def _square(x0: float, y0: float, size: float) -> list[dict[str, float]]:
    return [
        {"x": x0, "y": y0},
        {"x": x0 + size, "y": y0},
        {"x": x0 + size, "y": y0 + size},
        {"x": x0, "y": y0 + size},
    ]


# to_local이 0.1을 곱하므로 원본 좌표는 미터의 10배로 넣는다.
def _floor(*objects: dict) -> dict:
    return {"pois": [], "objects": list(objects)}


def _object(object_id: str, attribute: str, x0: float, y0: float, size: float) -> dict:
    return {"id": object_id, "attributeCode": attribute, "coordinates": _square(x0, y0, size)}


# 매장 마커가 찍히는 점을 품는 도형은 뺀다. 안 빼면 그 매장이 화면에서 사라진다.
def test_매장_중심점을_품는_도형은_제외된다():
    floor = _floor(_object("OB-BIG", "OB-OTHER_FACILITY", 0, 0, 1000))

    shapes = non_walkable_shapes(floor, [{"x": 50.0, "y": 50.0}])

    assert shapes == []


# 같은 도형이라도 중심점을 안 품으면 남는다 — 크기 임계값이 아니라 포함 판정이다.
def test_중심점을_안_품으면_크기와_무관하게_남는다():
    floor = _floor(_object("OB-BIG", "OB-OTHER_FACILITY", 0, 0, 1000))

    shapes = non_walkable_shapes(floor, [{"x": 500.0, "y": 500.0}])

    assert [s["id"] for s in shapes] == ["OB-BIG"]
    assert shapes[0]["kind"] == "feature"


# POI가 달린 도형은 이미 매장으로 들어가 있다. 안 빼면 같은 칸이 두 벌로 그려진다.
def test_POI가_달린_도형은_제외된다():
    floor = _floor(_object("OB-A", "OB-VOID_AREA", 0, 0, 100))
    floor["pois"] = [{"id": "PO-1", "objectId": "OB-A"}]

    assert non_walkable_shapes(floor, []) == []


# skip_kinds는 --non-walkable-only가 에스컬레이터를 통째로 빼는 데 쓴다.
def test_skip_kinds에_든_종류는_뽑지_않는다():
    floor = _floor(
        _object("OB-E", "OB-ESCALATOR_UP", 0, 0, 100),
        _object("OB-V", "OB-VOID_AREA", 2000, 2000, 100),
    )

    shapes = non_walkable_shapes(floor, [], skip_kinds=REGENERATION_ONLY_KINDS)

    assert [s["id"] for s in shapes] == ["OB-V"]


def _graph(code: str) -> dict:
    return json.loads((Path(OUT) / f"{code}.json").read_text(encoding="utf-8"))


# 층 JSON이 v180.4 매장과 v182.8 도형이 섞여 있다는 사실을 스스로 말하는지 본다.
def test_모든_층이_출처_버전을_적고_있다():
    for code in FLOOR_CODES:
        source = _graph(code)["non_walkable_source"]
        assert source["mode"] == "non_walkable_only"
        assert source["map_version"]


# 저장소 매장은 v180.4라 에스컬레이터 폴리곤을 이미 갖고 있다. 도형이 하나라도
# 섞이면 초록 에스컬레이터가 회색 조각에 덮인다.
def test_에스컬레이터_도형은_한_개도_들어오지_않는다():
    kinds = {shape["kind"] for code in FLOOR_CODES for shape in _graph(code)["non_walkable_polygons_local_m"]}

    assert kinds <= {"void", "pillar", "feature"}


# 되돌림의 원인과 그때 같이 잃은 것을 id로 못 박는다.
def test_매장을_덮던_도형만_빠지고_폭포정원은_남는다():
    ids = {shape["id"] for code in FLOOR_CODES for shape in _graph(code)["non_walkable_polygons_local_m"]}

    assert ids.isdisjoint(COVERING_SHAPE_IDS)
    assert ids.issuperset(WATERFALL_SHAPE_IDS)


# counts는 임포터가 무엇을 실었는지 파일이 스스로 말하는 자리다.
def test_counts가_실제_개수와_일치한다():
    for code in FLOOR_CODES:
        graph = _graph(code)
        assert graph["counts"]["non_walkable"] == len(graph["non_walkable_polygons_local_m"])
