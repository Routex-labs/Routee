"""벡터 타일(MVT) HTTP API 통합 테스트."""

import math

import mapbox_vector_tile
from sqlalchemy import select

from app.models import Building, Floor
from app.repositories.geo_transform import fit_building_geo_transform
from tests.conftest import BUILDING_ID, FLOOR_NAME, REAL_BUILDING_ID, REAL_FLOOR_NAME

# 도형 개수를 세는 테스트가 쓰는 줌.
#
# z=0 타일은 지구 전체를 4096칸으로 양자화하므로 미터 단위 폴리곤이 한 점으로
# 뭉개져 인코더가 통째로 버린다(실측: 실데이터 3F의 z0 타일은 stores도
# non_walkable도 feature 0개다). z=15면 한 칸이 ~0.3m라 형태가 살아남고,
# 타일 하나가 이 건물을 통째로 덮는다(실측: stores 109개 = 층 전체).
_SHAPE_ZOOM = 15


# 건물 전체를 덮는 _SHAPE_ZOOM 타일의 z/x/y. 좌표를 상수로 박으면 지오레퍼런스가
# 바뀔 때 조용히 빈 타일을 보게 되므로, 시드된 변환에서 매번 구한다.
def _building_tile(session, building_id: str) -> tuple[int, int, int]:
    building = session.get(Building, building_id)
    transform = fit_building_geo_transform(session, building_id)
    points = [transform.apply(point["x"], point["y"]) for point in building.footprint_local_m]
    lat = sum(point[0] for point in points) / len(points)
    lng = sum(point[1] for point in points) / len(points)
    tiles = 2**_SHAPE_ZOOM
    x = int((lng + 180.0) / 360.0 * tiles)
    lat_rad = math.radians(lat)
    y = int((1.0 - math.log(math.tan(lat_rad) + 1 / math.cos(lat_rad)) / math.pi) / 2.0 * tiles)
    return _SHAPE_ZOOM, x, y


# 시드 데이터 지역(서울)을 덮는 낮은 줌 타일 하나면 항상 존재/디코딩 가능해야 한다.
def test_유효한_타일을_MVT로_디코딩할_수_있다(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/floors/{FLOOR_NAME}/tiles/0/0/0.mvt")

    assert response.status_code == 200
    assert response.headers["content-type"] == "application/vnd.mapbox-vector-tile"
    decoded = mapbox_vector_tile.decode(response.content)
    assert set(decoded) <= {"footprint", "non_walkable", "stores", "store_labels", "pois"}


# 못 걷는 면(보이드·기둥·조경)이 DB에서 타일 **바이트**까지 가는지 본다. 지난
# 시도는 DB·HTTP 응답까지는 갔는데 화면 픽셀이 0이었다 — 그 사이 구간을 여기서
# 못 박는다. 값은 합성 픽스처(test-tower 1F의 OB-TEST-VOID 하나)라 그대로 단언한다.
def test_못_걷는_면이_전용_레이어로_타일에_실린다(api_client, db_session):
    z, x, y = _building_tile(db_session, BUILDING_ID)

    response = api_client.get(f"/buildings/{BUILDING_ID}/floors/{FLOOR_NAME}/tiles/{z}/{x}/{y}.mvt")

    assert response.status_code == 200
    layer = mapbox_vector_tile.decode(response.content)["non_walkable"]
    assert len(layer["features"]) == 1
    feature = layer["features"][0]
    assert feature["geometry"]["type"] == "Polygon"
    # 클라이언트가 색을 가르는 열쇠는 kind뿐이다. 매장 식별자가 실리면 카테고리
    # 강조 필터·탭 판정이 회색 도형까지 집어간다.
    assert feature["properties"] == {"kind": "void"}


# 도형이 없는 층(실데이터 B2가 그렇다)에서도 레이어 자체는 나가야 한다.
# 층마다 레이어 유무가 갈리면 클라이언트 sourceLayer가 그 층에서만 비어 버린다.
def test_도형이_없는_층에도_빈_레이어가_나간다(api_client, db_session):
    z, x, y = _building_tile(db_session, BUILDING_ID)

    response = api_client.get(f"/buildings/{BUILDING_ID}/floors/2F/tiles/{z}/{x}/{y}.mvt")

    assert mapbox_vector_tile.decode(response.content)["non_walkable"]["features"] == []


# 실데이터 스모크 — 개수는 데이터 갱신으로 바뀌므로 상수로 박지 않고, 시드된
# 층 행과 타일이 일치하는지(=하나도 안 흘렸는지)를 본다.
def test_실데이터_층_타일이_시드된_못_걷는_면을_모두_싣는다(real_api_client, real_db_session):
    floor = real_db_session.scalars(
        select(Floor).where(Floor.building_id == REAL_BUILDING_ID, Floor.name == "3F")
    ).one()
    shapes = floor.non_walkable_polygons_local_m
    # 3F는 아트리움 보이드가 있는 층이라 비어 있으면 파이프라인이 끊긴 것이다.
    assert shapes

    z, x, y = _building_tile(real_db_session, REAL_BUILDING_ID)
    response = real_api_client.get(f"/buildings/{REAL_BUILDING_ID}/floors/3F/tiles/{z}/{x}/{y}.mvt")

    features = mapbox_vector_tile.decode(response.content)["non_walkable"]["features"]
    assert len(features) == len(shapes)
    assert {feature["properties"]["kind"] for feature in features} == {shape["kind"] for shape in shapes}


def test_존재하지_않는_건물의_타일은_찾을수없음_응답을_반환한다(api_client):
    response = api_client.get(f"/buildings/nonexistent/floors/{FLOOR_NAME}/tiles/0/0/0.mvt")

    assert response.status_code == 404
    assert response.json()["detail"] == "Floor not found"


def test_존재하지_않는_층의_타일은_찾을수없음_응답을_반환한다(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/floors/99F/tiles/0/0/0.mvt")

    assert response.status_code == 404
    assert response.json()["detail"] == "Floor not found"


def test_범위를_벗어난_타일_좌표는_잘못된요청_응답을_반환한다(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/floors/{FLOOR_NAME}/tiles/-1/0/0.mvt")

    assert response.status_code == 400


# 헤더가 없으면 MapLibre가 같은 타일을 줌 전환·층 재방문마다 다시 받아 간다.
def test_타일_응답에_캐시_헤더가_붙는다(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/floors/{FLOOR_NAME}/tiles/0/0/0.mvt")

    assert response.status_code == 200
    assert response.headers["cache-control"] == "public, max-age=60"
    assert response.headers["etag"]


def test_같은_타일은_같은_ETag를_돌려준다(api_client):
    url = f"/buildings/{BUILDING_ID}/floors/{FLOOR_NAME}/tiles/0/0/0.mvt"

    first = api_client.get(url)
    second = api_client.get(url)

    assert first.headers["etag"] == second.headers["etag"]


def test_ETag가_같으면_본문없는_304를_돌려준다(api_client):
    url = f"/buildings/{BUILDING_ID}/floors/{FLOOR_NAME}/tiles/0/0/0.mvt"
    etag = api_client.get(url).headers["etag"]

    response = api_client.get(url, headers={"If-None-Match": etag})

    assert response.status_code == 304
    assert response.content == b""
    # 304에도 헤더를 붙여야 브라우저가 만료 시각을 갱신한다.
    assert response.headers["cache-control"] == "public, max-age=60"


def test_ETag가_다르면_본문을_다시_내려준다(api_client):
    url = f"/buildings/{BUILDING_ID}/floors/{FLOOR_NAME}/tiles/0/0/0.mvt"

    response = api_client.get(url, headers={"If-None-Match": '"stale"'})

    assert response.status_code == 200
    assert response.content


# 타일은 gzip이 평균 48% 줄이는 응답이다(app/main.py 미들웨어 주석의 실측 참고).
# 미들웨어가 빠지면 전송량이 조용히 두 배가 되므로 계약으로 고정한다.
#
# **합성 픽스처(test-tower)가 아니라 실데이터 클라이언트를 쓰는 이유**: GZipMiddleware는
# `minimum_size`(500바이트) 미만을 압축하지 않는데, test-tower의 z0 타일은 매장이
# 몇 개뿐이라 그 아래다. 픽스처로 테스트하면 미들웨어가 붙어 있어도 실패한다.
def test_타일_응답은_gzip으로_압축된다(real_api_client):
    response = real_api_client.get(
        f"/buildings/{REAL_BUILDING_ID}/floors/{REAL_FLOOR_NAME}/tiles/0/0/0.mvt",
        headers={"Accept-Encoding": "gzip"},
    )

    assert response.status_code == 200
    assert response.headers["content-encoding"] == "gzip"
    # 중간 캐시가 압축본을 비압축 요청에 주지 않도록 Vary가 반드시 붙어야 한다.
    assert "accept-encoding" in response.headers["vary"].lower()
    # httpx가 자동으로 풀어 주므로 본문은 그대로 MVT로 디코딩된다.
    assert mapbox_vector_tile.decode(response.content)


# URL에 버전이 붙으면 재검증조차 필요 없다고 선언한다. 이게 빠지면 층을 오갈
# 때마다 304 왕복이 다시 살아난다(실측 콜드 재시작 1회에 22건).
def test_버전이_붙은_타일은_immutable로_길게_캐시된다(api_client):
    revision = api_client.get(f"/buildings/{BUILDING_ID}").json()["tile_revision"]
    assert revision

    response = api_client.get(f"/buildings/{BUILDING_ID}/floors/{FLOOR_NAME}/tiles/0/0/0.mvt?v={revision}")

    assert response.status_code == 200
    cache_control = response.headers["cache-control"]
    assert "immutable" in cache_control
    # 60초짜리 기본값이 아니라 길게 잡혔는지 확인한다.
    assert "max-age=31536000" in cache_control


# 버전 없이 오는 요청(옛 클라이언트)은 지금까지와 똑같이 짧은 캐시 + 재검증이다.
def test_버전이_없으면_기존_짧은_캐시를_유지한다(api_client):
    response = api_client.get(f"/buildings/{BUILDING_ID}/floors/{FLOOR_NAME}/tiles/0/0/0.mvt")

    assert response.headers["cache-control"] == "public, max-age=60"


# 버전은 시드가 바뀌면 달라져야 한다. 안 바뀌면 낡은 타일이 1년간 눌러앉는다.
def test_같은_DB에서는_버전이_안정적이다(api_client):
    first = api_client.get(f"/buildings/{BUILDING_ID}").json()["tile_revision"]
    second = api_client.get(f"/buildings/{BUILDING_ID}").json()["tile_revision"]

    assert first == second


# gzip을 못 받는 클라이언트에게는 그대로 원본을 준다. 미들웨어가 Accept-Encoding을
# 무시하고 압축하면 MapLibre 네이티브가 타일을 못 읽는다.
def test_gzip을_받지_않는_클라이언트에는_원본을_준다(real_api_client):
    response = real_api_client.get(
        f"/buildings/{REAL_BUILDING_ID}/floors/{REAL_FLOOR_NAME}/tiles/0/0/0.mvt",
        headers={"Accept-Encoding": "identity"},
    )

    assert response.status_code == 200
    assert "content-encoding" not in response.headers
    assert mapbox_vector_tile.decode(response.content)
