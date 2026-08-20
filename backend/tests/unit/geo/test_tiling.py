"""벡터 타일용 좌표 변환/레이어 구성 단위 테스트."""

import mapbox_vector_tile
import pytest

from app.geo.georeference import GeoTransform
from app.geo.tiling import TileBounds, build_floor_tile_layers, tile_bounds
from app.models import Building, Poi, Store

IDENTITY_TRANSFORM = GeoTransform(a=1.0, b=0.0, c=0.0, d=1.0, tx=126.0, ty=37.0)


# z=0에서는 타일 하나가 지구 전체를 덮으므로 서경/남위 끝은 -180/-85.05...(Web
# Mercator 위도 한계) 근처가 나와야 한다.
def test_z0_타일은_지구_전체를_덮는다():
    bounds = tile_bounds(0, 0, 0)

    assert bounds.west == pytest.approx(-180.0)
    assert bounds.east == pytest.approx(180.0)
    assert bounds.north == pytest.approx(85.0511, abs=1e-3)
    assert bounds.south == pytest.approx(-85.0511, abs=1e-3)


def test_범위를_벗어난_타일_좌표는_거부한다():
    with pytest.raises(ValueError):
        tile_bounds(2, 4, 0)  # z=2는 x/y가 0..3까지만 유효


def _building() -> Building:
    return Building(
        id="b1",
        name="테스트빌딩",
        area_m2=100.0,
        perimeter_m=40.0,
        footprint_local_m=[
            {"x": 0.0, "y": 0.0},
            {"x": 10.0, "y": 0.0},
            {"x": 10.0, "y": 10.0},
            {"x": 0.0, "y": 10.0},
        ],
    )


# transform이 없는 건물(실측 앵커가 전혀 없어 피팅이 불가능한 경우)은 타일을
# 만들 실좌표 근거가 없으므로 빈 레이어를 반환해야 한다.
def test_transform이_없으면_빈_레이어를_반환한다():
    layers = build_floor_tile_layers(
        _building(),
        stores=[],
        pois=[],
        transform=None,
        bounds=tile_bounds(0, 0, 0),
    )

    assert layers == []


# 항등 변환(스케일 1, 회전 없음)일 때 footprint 좌표가 lng=x+126, lat=y+37로
# 그대로 옮겨지는지 확인한다.
def test_footprint이_geo_transform으로_wgs84로_변환된다():
    layers = build_floor_tile_layers(
        _building(),
        stores=[],
        pois=[],
        transform=IDENTITY_TRANSFORM,
        bounds=tile_bounds(0, 0, 0),
    )

    footprint_layer = next(layer for layer in layers if layer["name"] == "footprint")
    ring = footprint_layer["features"][0]["geometry"]["coordinates"][0]

    assert ring[0] == [126.0, 37.0]
    assert ring[2] == [136.0, 47.0]
    # 폴리곤 링은 닫혀 있어야 한다(첫 점 == 마지막 점).
    assert ring[0] == ring[-1]


# 타일 경계와 겹치지 않는 매장은 걸러내는지 확인한다.
def test_타일_밖의_매장은_제외된다():
    far_store = Store(
        id="far",
        floor_id="f1",
        name="먼 매장",
        centroid_x_m=1000.0,
        centroid_y_m=1000.0,
        polygon=[
            {"x": 1000.0, "y": 1000.0},
            {"x": 1001.0, "y": 1000.0},
            {"x": 1001.0, "y": 1001.0},
        ],
    )
    near_store = Store(
        id="near",
        floor_id="f1",
        name="가까운 매장",
        centroid_x_m=0.1,
        centroid_y_m=0.1,
        polygon=[
            {"x": 0.1, "y": 0.1},
            {"x": 0.2, "y": 0.1},
            {"x": 0.2, "y": 0.2},
        ],
    )
    # 매장 전용 좁은 타일: IDENTITY_TRANSFORM 기준 lng/lat 126~126.5, 37~37.5
    # 범위만 덮도록 z=0 대신 직접 TileBounds를 만들어 검증한다.
    narrow_bounds = TileBounds(west=126.0, south=37.0, east=126.5, north=37.5)

    layers = build_floor_tile_layers(
        _building(),
        stores=[far_store, near_store],
        pois=[],
        transform=IDENTITY_TRANSFORM,
        bounds=narrow_bounds,
    )

    store_layer = next(layer for layer in layers if layer["name"] == "stores")
    ids = {feature["properties"]["id"] for feature in store_layer["features"]}

    assert ids == {"near"}


def _store_with_category(
    store_id: str,
    category: str | None,
    subcategory: str | None,
) -> Store:
    return Store(
        id=store_id,
        floor_id="f1",
        name=f"매장 {store_id}",
        category=category,
        subcategory=subcategory,
        centroid_x_m=0.1,
        centroid_y_m=0.1,
        polygon=[
            {"x": 0.1, "y": 0.1},
            {"x": 0.2, "y": 0.1},
            {"x": 0.2, "y": 0.2},
        ],
    )


def _store_properties_by_id(stores: list[Store]) -> dict[str, dict]:
    layers = build_floor_tile_layers(
        _building(),
        stores=stores,
        pois=[],
        transform=IDENTITY_TRANSFORM,
        bounds=tile_bounds(0, 0, 0),
    )

    store_layer = next(layer for layer in layers if layer["name"] == "stores")
    return {feature["properties"]["id"]: feature["properties"] for feature in store_layer["features"]}


# 클라이언트가 MapLibre setFilter로 카테고리 필터를 걸려면 두 값이 타일에 실려야 한다.
def test_매장_feature에_category와_subcategory가_실린다():
    properties = _store_properties_by_id([_store_with_category("s1", "패션", "여성복")])["s1"]

    assert properties["category"] == "패션"
    assert properties["subcategory"] == "여성복"


# category/subcategory는 nullable이다. None이면 null을 싣는 게 아니라 키 자체를
# 빼는 것이 계약이다 — MapLibre 필터에서 ['has', 'category']로 판정할 수 있다.
@pytest.mark.parametrize(
    ("category", "subcategory", "expected_keys"),
    [
        (None, None, set()),
        ("패션", None, {"category"}),
        (None, "여성복", {"subcategory"}),
    ],
)
def test_category가_없으면_해당_키를_아예_넣지_않는다(category, subcategory, expected_keys):
    properties = _store_properties_by_id([_store_with_category("s1", category, subcategory)])["s1"]

    assert {"category", "subcategory"} & set(properties) == expected_keys
    # 값이 없어도 나머지 property는 그대로 있어야 한다.
    assert properties["kind"] == "store"


# 위 계약이 실제 MVT 바이트까지 살아남는지 확인한다. 인코더에 None을 넘겨도 지금은
# 조용히 키가 빠지지만, 그 동작에 기대지 않는다는 것이 이 테스트의 요지다.
def test_category가_없는_매장도_예외없이_MVT로_인코딩된다():
    bounds = tile_bounds(0, 0, 0)
    layers = build_floor_tile_layers(
        _building(),
        stores=[
            _store_with_category("s1", None, None),
            _store_with_category("s2", "패션", "여성복"),
        ],
        pois=[],
        transform=IDENTITY_TRANSFORM,
        bounds=bounds,
    )

    encoded = mapbox_vector_tile.encode(
        layers,
        default_options={"quantize_bounds": (bounds.west, bounds.south, bounds.east, bounds.north)},
    )
    decoded = mapbox_vector_tile.decode(encoded)

    properties = {feature["properties"]["id"]: feature["properties"] for feature in decoded["stores"]["features"]}
    assert "category" not in properties["s1"]
    assert "subcategory" not in properties["s1"]
    assert properties["s2"]["category"] == "패션"
    assert properties["s2"]["subcategory"] == "여성복"


def _void(shape_id: str, x: float, y: float, kind: str = "void") -> dict:
    return {
        "id": shape_id,
        "kind": kind,
        "polygon_local_m": [
            {"x": x, "y": y},
            {"x": x + 0.1, "y": y},
            {"x": x + 0.1, "y": y + 0.1},
            {"x": x, "y": y + 0.1},
        ],
    }


def _non_walkable_layer(shapes, bounds=None) -> dict:
    layers = build_floor_tile_layers(
        _building(),
        stores=[],
        pois=[],
        transform=IDENTITY_TRANSFORM,
        bounds=bounds or tile_bounds(0, 0, 0),
        non_walkable_local_m=shapes,
    )
    return next(layer for layer in layers if layer["name"] == "non_walkable")


# 못 걷는 면은 매장(stores)이 아니라 전용 레이어로 나가야 한다. 같은 레이어에
# 실으면 카테고리 강조 필터·탭 판정이 회색 도형까지 집어간다.
def test_못_걷는_면은_전용_레이어로_나간다():
    layer = _non_walkable_layer([_void("OB-1", 0.1, 0.1)])

    feature = layer["features"][0]
    assert feature["geometry"]["type"] == "Polygon"
    # 매장 폴리곤과 같은 변환을 타야 도형이 안 밀린다(lng=x+126, lat=y+37).
    assert feature["geometry"]["coordinates"][0][0] == [126.1, 37.1]
    # 링은 닫혀 있어야 한다.
    assert feature["geometry"]["coordinates"][0][0] == feature["geometry"]["coordinates"][0][-1]


# 클라이언트가 색을 가를 수 있게 kind를 싣는다. 반대로 매장 식별자(id/name/
# category)는 실으면 안 된다 — 탭 판정이 properties["id"]로 매장을 되찾는다.
def test_못_걷는_면_feature에는_kind만_실린다():
    layer = _non_walkable_layer([_void("OB-1", 0.1, 0.1, kind="pillar")])

    assert layer["features"][0]["properties"] == {"kind": "pillar"}


# 도형이 하나도 없는 층(B2)에서도 레이어 자체는 나가야 한다. 층마다 레이어
# 유무가 갈리면 클라이언트 sourceLayer 배선이 그 층에서만 달라진다.
@pytest.mark.parametrize("shapes", [None, []])
def test_도형이_없는_층에도_빈_레이어를_낸다(shapes):
    assert _non_walkable_layer(shapes)["features"] == []


# 거르는 기준은 매장 폴리곤과 같은 bbox 교차다.
def test_타일_밖의_못_걷는_면은_제외된다():
    narrow_bounds = TileBounds(west=126.0, south=37.0, east=126.5, north=37.5)

    layer = _non_walkable_layer([_void("near", 0.1, 0.1), _void("far", 1000.0, 1000.0)], bounds=narrow_bounds)

    assert len(layer["features"]) == 1


# 못 걷는 면은 **stores 위, store_labels 아래**여야 한다. 목록 순서가 곧
# 클라이언트 쌓임 순서라, stores 아래로 내려가면 지하 주차칸 폴리곤이 기둥
# 면적의 40%를 가린다(실측: docs/client/kakao-map-indoor-observation.md 3절).
# 매장이 덮일 걱정은 임포터의 중심점 규칙이 받는다.
def test_레이어_순서가_stores_위_store_labels_아래다():
    layers = build_floor_tile_layers(
        _building(),
        stores=[_store_with_category("s1", "패션", "여성복")],
        pois=[],
        transform=IDENTITY_TRANSFORM,
        bounds=tile_bounds(0, 0, 0),
        non_walkable_local_m=[_void("OB-1", 0.1, 0.1)],
    )

    names = [layer["name"] for layer in layers]
    assert names == ["footprint", "stores", "non_walkable", "store_labels", "pois"]


# 지난 실패가 "데이터는 갔는데 화면 픽셀이 0"이었으므로, MVT 바이트 왕복까지
# 살아남는지 단언한다.
def test_못_걷는_면이_MVT_바이트까지_살아남는다():
    bounds = tile_bounds(0, 0, 0)
    layers = build_floor_tile_layers(
        _building(),
        stores=[],
        pois=[],
        transform=IDENTITY_TRANSFORM,
        bounds=bounds,
        non_walkable_local_m=[_void("OB-1", 0.1, 0.1), _void("OB-2", 0.3, 0.3, kind="pillar")],
    )

    decoded = mapbox_vector_tile.decode(
        mapbox_vector_tile.encode(
            layers,
            default_options={"quantize_bounds": (bounds.west, bounds.south, bounds.east, bounds.north)},
        )
    )

    features = decoded["non_walkable"]["features"]
    assert len(features) == 2
    assert {feature["properties"]["kind"] for feature in features} == {"void", "pillar"}


# 못 걷는 면을 넣어도 기존 레이어의 feature는 하나도 달라지면 안 된다.
def test_못_걷는_면은_기존_레이어를_바꾸지_않는다():
    stores = [_store_with_category("s1", "패션", "여성복")]
    poi = Poi(id="poi-1", floor_id="f1", type="elevator", name="EV1", x_m=5.0, y_m=5.0)
    without = build_floor_tile_layers(
        _building(),
        stores=stores,
        pois=[poi],
        transform=IDENTITY_TRANSFORM,
        bounds=tile_bounds(0, 0, 0),
    )
    with_shapes = build_floor_tile_layers(
        _building(),
        stores=stores,
        pois=[poi],
        transform=IDENTITY_TRANSFORM,
        bounds=tile_bounds(0, 0, 0),
        non_walkable_local_m=[_void("OB-1", 0.1, 0.1)],
    )

    def others(layers: list[dict]) -> dict:
        return {layer["name"]: layer["features"] for layer in layers if layer["name"] != "non_walkable"}

    assert others(with_shapes) == others(without)


# POI 좌표도 동일한 변환을 거치는지 확인한다.
def test_poi도_wgs84로_변환된다():
    poi = Poi(
        id="poi-1",
        floor_id="f1",
        type="elevator",
        name="EV1",
        x_m=5.0,
        y_m=5.0,
    )

    layers = build_floor_tile_layers(
        _building(),
        stores=[],
        pois=[poi],
        transform=IDENTITY_TRANSFORM,
        bounds=tile_bounds(0, 0, 0),
    )

    poi_layer = next(layer for layer in layers if layer["name"] == "pois")
    coordinates = poi_layer["features"][0]["geometry"]["coordinates"]

    assert coordinates == [131.0, 42.0]


# 라벨(아이콘+이름)은 매장 폴리곤이 아니라 전용 점 레이어에 실린다. MapLibre가
# 폴리곤 심볼을 면적 무게중심에 찍는데, ㄱ자 매장에서는 그 점이 매장 밖이다
# ([label_point.py] 주석). 클라이언트 라벨 레이어가 이 레이어를 본다.
def test_매장_라벨은_전용_점_레이어로_나간다():
    layers = build_floor_tile_layers(
        _building(),
        stores=[_store_with_category("s1", "패션", "여성복")],
        pois=[],
        transform=IDENTITY_TRANSFORM,
        bounds=tile_bounds(0, 0, 0),
    )

    label_layer = next(layer for layer in layers if layer["name"] == "store_labels")
    feature = label_layer["features"][0]

    assert feature["geometry"]["type"] == "Point"
    # 필터 표현식이 폴리곤 레이어와 같은 키를 보므로 properties도 같아야 한다.
    assert feature["properties"]["id"] == "s1"
    assert feature["properties"]["category"] == "패션"
    assert feature["properties"]["subcategory"] == "여성복"


# ㄱ자 매장에서 라벨 점이 폴리곤 안에 들어와야 한다. 무게중심을 그대로 쓰면
# 두 팔 사이 빈 곳(=복도)에 아이콘이 뜬다.
def test_ㄱ자_매장_라벨_점이_폴리곤_안에_있다():
    l_shaped = Store(
        id="l1",
        floor_id="f1",
        name="ㄱ자 매장",
        centroid_x_m=0.0,
        centroid_y_m=0.0,
        polygon=[
            {"x": 0.0, "y": 0.0},
            {"x": 0.30, "y": 0.0},
            {"x": 0.30, "y": 0.06},
            {"x": 0.06, "y": 0.06},
            {"x": 0.06, "y": 0.30},
            {"x": 0.0, "y": 0.30},
        ],
    )

    layers = build_floor_tile_layers(
        _building(),
        stores=[l_shaped],
        pois=[],
        transform=IDENTITY_TRANSFORM,
        bounds=tile_bounds(0, 0, 0),
    )

    ring = next(layer for layer in layers if layer["name"] == "stores")["features"][0]
    polygon = [(point[0], point[1]) for point in ring["geometry"]["coordinates"][0]]
    label = next(layer for layer in layers if layer["name"] == "store_labels")["features"][0]
    x, y = label["geometry"]["coordinates"]

    inside = False
    for index in range(len(polygon)):
        x0, y0 = polygon[index]
        x1, y1 = polygon[(index + 1) % len(polygon)]
        if (y0 > y) != (y1 > y) and x < (x1 - x0) * (y - y0) / (y1 - y0) + x0:
            inside = not inside

    assert inside


# 라벨 좌표는 타일(z/x/y)과 무관하게 매장 폴리곤 + 건물 변환만으로 정해지므로,
# 호출자가 memo를 넘기면 계산 결과가 채워져 다음 타일에서 재사용할 수 있어야 한다.
def test_라벨_memo에_계산된_좌표가_채워진다():
    memo: dict[str, tuple[float, float]] = {}

    layers = build_floor_tile_layers(
        _building(),
        stores=[_store_with_category("s1", "패션", "여성복")],
        pois=[],
        transform=IDENTITY_TRANSFORM,
        bounds=tile_bounds(0, 0, 0),
        store_label_memo=memo,
    )

    label = next(layer for layer in layers if layer["name"] == "store_labels")["features"][0]
    assert memo["s1"] == tuple(label["geometry"]["coordinates"])


# memo에 이미 있는 매장은 다시 계산하지 않고 그 좌표를 그대로 쓴다. 재계산이
# 일어나면 memo 값과 다른(진짜 계산된) 좌표가 실리므로, 일부러 다른 좌표를
# 심어 재사용 여부를 판별한다.
def test_라벨_memo의_좌표를_재계산_없이_그대로_쓴다():
    planted = (126.15, 37.15)
    memo = {"s1": planted}

    layers = build_floor_tile_layers(
        _building(),
        stores=[_store_with_category("s1", "패션", "여성복")],
        pois=[],
        transform=IDENTITY_TRANSFORM,
        bounds=tile_bounds(0, 0, 0),
        store_label_memo=memo,
    )

    label = next(layer for layer in layers if layer["name"] == "store_labels")["features"][0]
    assert tuple(label["geometry"]["coordinates"]) == planted


# 타일 경계에 걸친 매장은 폴리곤이 양쪽 타일에 실리지만 **라벨은 한 번만**
# 실려야 한다. 둘 다 실으면 두 타일이 함께 떠 있을 때 같은 이름이 두 번 찍힌다.
def test_라벨_점이_없는_타일에는_라벨을_싣지_않는다():
    store = _store_with_category("s1", "패션", "여성복")
    # 매장 폴리곤(lng 126.1~126.2)과 겹치지만 라벨 점(lng≈126.171)은 담지 못하는
    # 좁은 띠. 화면 가장자리에서 매장의 오른쪽 끝만 걸친 타일이 이 모양이다.
    sliver = TileBounds(west=126.18, south=37.0, east=126.5, north=37.5)

    layers = build_floor_tile_layers(
        _building(),
        stores=[store],
        pois=[],
        transform=IDENTITY_TRANSFORM,
        bounds=sliver,
    )

    assert next(layer for layer in layers if layer["name"] == "stores")["features"]
    assert next(layer for layer in layers if layer["name"] == "store_labels")["features"] == []


# 한 폴리곤을 여러 매장이 나눠 쓰면(더현대 서울 31곳·91매장) label_point가
# 폴리곤당 한 점이라 라벨이 정확히 포개지고, MapLibre 충돌 처리가 하나만
# 남긴다 — 나머지 매장은 지도에서 보이지도, 눌리지도 않는다. 그래서 이런
# 매장의 라벨은 (1) 서로 다른 점에 놓이고 (2) `shared` 표시를 달아야 한다.
def _shared_polygon_store(store_id: str, entrance_x: float) -> Store:
    # 오설록·일상다완의 실제 모양을 축소한 것: 같은 폴리곤·같은 centroid,
    # 입구 핀만 다르다. 긴 축은 x(가로 9.6m > 세로 6.2m 비율).
    return Store(
        id=store_id,
        floor_id="f1",
        name=store_id,
        centroid_x_m=4.8,
        centroid_y_m=3.0,
        entrance_x_m=entrance_x,
        entrance_y_m=3.0,
        polygon=[
            {"x": 0.0, "y": 0.0},
            {"x": 9.6, "y": 0.0},
            {"x": 9.6, "y": 6.0},
            {"x": 0.0, "y": 6.0},
        ],
    )


def test_한_폴리곤을_나눠_쓰는_매장들의_라벨이_갈라진다():
    layers = build_floor_tile_layers(
        _building(),
        # 입구 핀 순서(2.0 < 7.0)가 라벨 배치 순서가 되는지도 함께 본다.
        stores=[_shared_polygon_store("ilsang", 7.0), _shared_polygon_store("osulloc", 2.0)],
        pois=[],
        transform=IDENTITY_TRANSFORM,
        bounds=tile_bounds(0, 0, 0),
    )

    labels = {
        feature["properties"]["id"]: feature
        for feature in next(layer for layer in layers if layer["name"] == "store_labels")["features"]
    }

    assert set(labels) == {"osulloc", "ilsang"}
    osulloc_xy = labels["osulloc"]["geometry"]["coordinates"]
    ilsang_xy = labels["ilsang"]["geometry"]["coordinates"]
    # 긴 축(x)을 반으로 나눈 칸의 중심: 2.4m / 7.2m 지점 (+126 오프셋).
    assert osulloc_xy[0] == pytest.approx(126.0 + 2.4)
    assert ilsang_xy[0] == pytest.approx(126.0 + 7.2)
    # 짧은 축은 centroid 그대로.
    assert osulloc_xy[1] == pytest.approx(37.0 + 3.0)
    # 클라이언트가 충돌 판정을 끈 전용 레이어로 갈라낼 표시.
    assert labels["osulloc"]["properties"]["shared"] is True
    assert labels["ilsang"]["properties"]["shared"] is True


def test_혼자_쓰는_폴리곤에는_shared_표시가_없다():
    layers = build_floor_tile_layers(
        _building(),
        stores=[_shared_polygon_store("alone", 2.0)],
        pois=[],
        transform=IDENTITY_TRANSFORM,
        bounds=tile_bounds(0, 0, 0),
    )

    feature = next(layer for layer in layers if layer["name"] == "store_labels")["features"][0]
    assert "shared" not in feature["properties"]


# 묶음 매장 — 이름이 같은 층 다른 매장 이름 2개 이상을 이어 붙인 항목
# (「마사비스 리치몬드 과자점 은비스브레드 니드쿠키앤베이커리」류). 구성
# 매장들이 각자 폴리곤·라벨을 갖고 있으므로 묶음에는 라벨을 달지 않는다.
def _named_store(store_id: str, name: str, cx: float, cy: float) -> Store:
    return Store(
        id=store_id,
        floor_id="f1",
        name=name,
        centroid_x_m=cx,
        centroid_y_m=cy,
        polygon=[
            {"x": cx - 1.0, "y": cy - 1.0},
            {"x": cx + 1.0, "y": cy - 1.0},
            {"x": cx + 1.0, "y": cy + 1.0},
            {"x": cx - 1.0, "y": cy + 1.0},
        ],
    )


def test_묶음_매장에는_라벨을_달지_않는다():
    layers = build_floor_tile_layers(
        _building(),
        stores=[
            # 표기 흔들림까지 재현: 묶음은 「세띠엠므」, 구성 매장은 「세띠 엠므」.
            _named_store("agg", "포동 푸딩 우나하우스 세띠엠므 멜로드도산", 5.0, 5.0),
            _named_store("podong", "포동 푸딩", 3.0, 3.0),
            _named_store("setti", "세띠 엠므", 7.0, 3.0),
            _named_store("melrod", "멜로드도산", 7.0, 7.0),
        ],
        pois=[],
        transform=IDENTITY_TRANSFORM,
        bounds=tile_bounds(0, 0, 0),
    )

    label_ids = {
        feature["properties"]["id"]
        for feature in next(layer for layer in layers if layer["name"] == "store_labels")["features"]
    }
    fill_ids = {
        feature["properties"]["id"]
        for feature in next(layer for layer in layers if layer["name"] == "stores")["features"]
    }

    assert label_ids == {"podong", "setti", "melrod"}
    # 폴리곤 fill은 남는다 — 구역 배경으로는 유효한 도형이다.
    assert "agg" in fill_ids


def test_이름_하나만_품는_매장은_묶음이_아니다():
    layers = build_floor_tile_layers(
        _building(),
        stores=[
            _named_store("nb", "뉴발란스", 3.0, 3.0),
            _named_store("nbkids", "뉴발란스 키즈", 7.0, 7.0),
        ],
        pois=[],
        transform=IDENTITY_TRANSFORM,
        bounds=tile_bounds(0, 0, 0),
    )

    label_ids = {
        feature["properties"]["id"]
        for feature in next(layer for layer in layers if layer["name"] == "store_labels")["features"]
    }
    assert label_ids == {"nb", "nbkids"}


# 묶음이 구성 매장과 centroid를 공유하는 자리(니드쿠키앤베이커리 실사례):
# 묶음을 그룹에서 빼므로 구성 매장은 혼자가 되어 칸도 shared 표시도 없어야 한다.
def test_묶음과_centroid를_공유하는_매장은_혼자로_취급한다():
    aggregate = _named_store("agg", "마사비스 은비스브레드 니드쿠키앤베이커리", 5.0, 5.0)
    member = _named_store("need", "니드쿠키앤베이커리", 5.0, 5.0)
    others = [_named_store("masa", "마사비스", 2.0, 2.0), _named_store("eunbi", "은비스브레드", 8.0, 2.0)]

    layers = build_floor_tile_layers(
        _building(),
        stores=[aggregate, member, *others],
        pois=[],
        transform=IDENTITY_TRANSFORM,
        bounds=tile_bounds(0, 0, 0),
    )

    labels = {
        feature["properties"]["id"]: feature
        for feature in next(layer for layer in layers if layer["name"] == "store_labels")["features"]
    }
    assert "agg" not in labels
    assert "shared" not in labels["need"]["properties"]


# 같은 폴리곤을 나눠 쓰는 매장은 fill도 자기 칸으로 잘려 나가야 화면에서
# 나뉜 구역으로 보이고 탭 판정이 폴리곤만으로 정확해진다.
def test_나눠_쓰는_매장의_fill이_칸으로_잘린다():
    layers = build_floor_tile_layers(
        _building(),
        stores=[_shared_polygon_store("ilsang", 7.0), _shared_polygon_store("osulloc", 2.0)],
        pois=[],
        transform=IDENTITY_TRANSFORM,
        bounds=tile_bounds(0, 0, 0),
    )

    fills = {
        feature["properties"]["id"]: feature["geometry"]["coordinates"][0]
        for feature in next(layer for layer in layers if layer["name"] == "stores")["features"]
    }

    osulloc_lngs = [point[0] for point in fills["osulloc"]]
    ilsang_lngs = [point[0] for point in fills["ilsang"]]
    # 긴 축(x, 0~9.6m)을 반으로: 오설록(입구 2.0) 왼쪽 칸, 일상다완(입구 7.0) 오른쪽 칸.
    assert max(osulloc_lngs) == pytest.approx(126.0 + 4.8)
    assert min(ilsang_lngs) == pytest.approx(126.0 + 4.8)
    # 각 라벨이 자기 칸 안에 있다.
    labels = {
        feature["properties"]["id"]: feature["geometry"]["coordinates"]
        for feature in next(layer for layer in layers if layer["name"] == "store_labels")["features"]
    }
    assert min(osulloc_lngs) <= labels["osulloc"][0] <= max(osulloc_lngs)
    assert min(ilsang_lngs) <= labels["ilsang"][0] <= max(ilsang_lngs)


# 세 곳 이상이 한 폴리곤을 나눠 쓰면 칸이 줄무늬처럼 잘게 갈라진다(실기기
# 확인). 개별 라벨·fill 분할 대신 「첫 매장 외 N」 라벨 하나로 접고,
# 클라이언트가 누르면 목록 시트를 띄운다.
def test_세_곳_이상은_묶음_라벨_하나로_접는다():
    layers = build_floor_tile_layers(
        _building(),
        stores=[
            _shared_polygon_store("bao", 7.0),
            _shared_polygon_store("paris", 2.0),
            _shared_polygon_store("saru", 5.0),
        ],
        pois=[],
        transform=IDENTITY_TRANSFORM,
        bounds=tile_bounds(0, 0, 0),
    )

    labels = next(layer for layer in layers if layer["name"] == "store_labels")["features"]
    assert len(labels) == 1
    cluster = labels[0]
    # 입구 핀 순서(2.0 < 5.0 < 7.0)로 첫 매장은 paris다.
    assert cluster["properties"]["name"] == "paris 외 2"
    assert cluster["properties"]["id"] == "paris"
    assert cluster["properties"]["cluster"] == 3
    # 이 라벨 하나가 그 자리의 유일한 입구다 — 충돌로 사라지면 안 된다.
    assert cluster["properties"]["shared"] is True

    # fill은 자르지 않는다 — 세 조각 전부 원본 폭(0~9.6m) 그대로다.
    fills = next(layer for layer in layers if layer["name"] == "stores")["features"]
    for feature in fills:
        lngs = [point[0] for point in feature["geometry"]["coordinates"][0]]
        assert max(lngs) - min(lngs) == pytest.approx(9.6)
