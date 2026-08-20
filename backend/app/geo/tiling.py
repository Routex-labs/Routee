# 건물의 local_m 지오메트리를 MVT 타일용 WGS84 GeoJSON 레이어로 변환한다.
# MVT 바이트 인코딩(mapbox_vector_tile) 자체는 외부 포맷 라이브러리 의존이라
# Query 쪽에서 호출한다. 이 모듈은 순수하게 (1) 슬리피맵 z/x/y -> WGS84 경계
# 상자 계산, (2) local_m -> wgs84 좌표 변환, (3) 타일과 겹치는 feature만 골라
# GeoJSON 레이어를 만드는 역할만 한다. FastAPI, SQLAlchemy, mapbox_vector_tile을
# 알지 못하고 ORM 모델(app.models)의 필드에만 의존한다.
#
# SVG 도면으로 보정한 정밀 좌표(footprint_wgs84_svg, svg_polygon_wgs84,
# centroid_lat/lng)는 현재 ORM 스키마에 없어 이 모듈은 건물 전체 affine
# 변환(GeoTransform)으로 근사한 좌표만 사용한다.

from __future__ import annotations

from collections.abc import MutableMapping, Sequence
from dataclasses import dataclass
from math import atan, degrees, pi, sinh
from typing import TYPE_CHECKING

from app.geo.label_point import label_point
from app.geo.shared_polygon import (
    SharedSlab,
    aggregate_store_ids,
    clip_polygon_to_slab,
    group_axis_and_order,
    shared_slabs,
    shared_store_groups,
)

if TYPE_CHECKING:
    from app.geo.georeference import GeoTransform
    from app.models import Building, Poi, Store


# 슬리피맵 타일 하나가 덮는 WGS84 경계 상자.
@dataclass(frozen=True)
class TileBounds:
    west: float
    south: float
    east: float
    north: float

    # 이 경계 상자가 다른 경계 상자와 겹치는지(경계 포함) 확인한다.
    def intersects(self, other_west: float, other_south: float, other_east: float, other_north: float) -> bool:
        return (
            self.west <= other_east
            and other_west <= self.east
            and self.south <= other_north
            and other_south <= self.north
        )


# 표준 슬리피맵(z/x/y, Web Mercator) 타일 좌표를 WGS84 경계 상자로 바꾼다.
def tile_bounds(z: int, x: int, y: int) -> TileBounds:
    if z < 0 or not (0 <= x < 2**z) or not (0 <= y < 2**z):
        raise ValueError(f"타일 좌표 범위를 벗어났습니다: z={z}, x={x}, y={y}")

    tiles_per_axis = 2.0**z

    # 경도는 타일 격자에 선형 비례한다.
    west = x / tiles_per_axis * 360.0 - 180.0
    east = (x + 1) / tiles_per_axis * 360.0 - 180.0

    # 타일 y는 위쪽(북쪽)이 작은 값이라 north가 y, south가 y+1에 대응한다.
    north = _tile_edge_latitude(y, tiles_per_axis)
    south = _tile_edge_latitude(y + 1, tiles_per_axis)

    return TileBounds(west=west, south=south, east=east, north=north)


# Web Mercator 타일 y좌표 한쪽 변의 위도(도).
def _tile_edge_latitude(y: int, tiles_per_axis: float) -> float:
    lat_rad = atan(sinh(pi * (1 - 2 * y / tiles_per_axis)))
    return degrees(lat_rad)


def _polygon_bbox(ring: list[list[float]]) -> tuple[float, float, float, float]:
    lngs = [point[0] for point in ring]
    lats = [point[1] for point in ring]
    return min(lngs), min(lats), max(lngs), max(lats)


# local_m 점 목록을 [lng, lat] 목록으로 옮긴다(폴리곤을 닫지는 않음).
def local_points_to_lnglat(points: list[dict], transform: GeoTransform) -> list[list[float]]:
    return [list(reversed(transform.apply(p["x"], p["y"]))) for p in points]


def _close_ring(ring: list[list[float]]) -> list[list[float]]:
    if ring and ring[0] != ring[-1]:
        return [*ring, ring[0]]
    return ring


def _local_polygon_ring(points: list[dict], transform: GeoTransform) -> list[list[float]]:
    return _close_ring(local_points_to_lnglat(points, transform))


# `_close_ring`이 붙인 마지막 중복점을 떼고 (lng, lat) 튜플 목록으로 바꾼다.
# [label_point]는 링이 닫혀 있지 않다고 보고 마지막-첫 변을 스스로 잇기 때문에,
# 닫힌 링을 그대로 넘기면 길이 0짜리 변이 하나 끼어든다.
def _closed_ring_to_points(ring: list[list[float]]) -> list[tuple[float, float]]:
    points = [(point[0], point[1]) for point in ring]
    if len(points) > 1 and points[0] == points[-1]:
        points.pop()
    return points


# 매장 feature의 properties. category/subcategory는 클라이언트가 MapLibre
# setFilter로 카테고리 필터를 걸 때 쓴다.
#
# 두 컬럼 모두 nullable이라 값이 없는 매장이 실제로 있다. None일 때 **키 자체를
# 넣지 않는다.** 이유:
#
#   mapbox_vector_tile 2.2.0의 인코더는 값 타입을 _can_handle_val로 거르는데
#   (`isinstance(v, (str, bool, int, float))`), None은 여기에 걸려 예외도 null
#   인코딩도 아니고 **그 키를 조용히 통째로 버린다**. 즉 None을 그대로 넘겨도
#   지금은 "키 없음"으로 나온다 — 확인한 실제 동작이다.
#
#   그래도 여기서 명시적으로 빼는 건, 그 동작이 우리가 의존해도 되는 계약이
#   아니기 때문이다. 라이브러리가 판올림하며 null 인코딩으로 바뀌면 타일 계약이
#   조용히 달라지고(클라이언트 필터가 어긋난다), 무엇보다 "None이면 키가 없다"는
#   결정이 코드에 안 남아 리뷰에서 보이지 않는다. 호출부에서 빼면 인코더 버전과
#   무관하게 계약이 고정된다.
#
#   키 없음이 안전한 이유: MapLibre 필터에서 `['has', 'category']`로 값 유무를
#   판정할 수 있다. 반대로 null이 실리면 `has`는 참이 되면서 비교는 어긋나
#   "값이 없다"를 표현할 깔끔한 방법이 사라진다.
def _store_properties(store: Store) -> dict:
    properties: dict = {"id": store.id, "name": store.name, "kind": "store"}
    if store.category is not None:
        properties["category"] = store.category
    if store.subcategory is not None:
        properties["subcategory"] = store.subcategory
    return properties


# 못 걷는 면 도형을 wgs84 feature로 옮긴다. 좌표 경로는 매장 폴리곤과 완전히
# 같다(_local_polygon_ring → 같은 GeoTransform) — 다른 경로를 타면 같은 층에서
# 도형만 몇 m 밀린다. 거르는 기준도 매장과 같은 bbox 교차다.
def _non_walkable_features(
    shapes: Sequence[dict],
    transform: GeoTransform,
    bounds: TileBounds,
) -> list[dict]:
    features: list[dict] = []
    for shape in shapes:
        ring = _local_polygon_ring(shape.get("polygon_local_m") or [], transform)
        if len(ring) < 4 or not bounds.intersects(*_polygon_bbox(ring)):
            continue
        features.append(
            {
                "geometry": {"type": "Polygon", "coordinates": [ring]},
                "properties": {"kind": shape.get("kind", "non_walkable")},
            }
        )
    return features


# 나눠 쓰는 자리의 라벨 점. 칸 계산은 app/geo/shared_polygon.py가 갖고, 여기서는 그
# 칸의 가운데를 wgs84로 옮기기만 한다. 라벨 feature에 붙는 `shared`는 클라이언트가
# 충돌 판정을 끈 전용 레이어로 그리라는 표시다(docs/backend/shared-polygon-split.md).
@dataclass(frozen=True)
class _SharedSlot:
    label_lnglat: tuple[float, float]
    slab: SharedSlab


def _shared_layouts(
    groups: Sequence[list[Store]],
    transform: GeoTransform,
) -> dict[str, _SharedSlot]:
    by_id = {store.id: store for group in groups for store in group}
    out: dict[str, _SharedSlot] = {}
    for store_id, slab in shared_slabs(groups).items():
        store = by_id[store_id]
        along = slab.middle
        x_m, y_m = (along, store.centroid_y_m) if slab.axis_is_x else (store.centroid_x_m, along)
        lat, lng = transform.apply(x_m, y_m)
        out[store_id] = _SharedSlot(label_lnglat=(lng, lat), slab=slab)
    return out


# 세 곳 이상이 한 폴리곤을 나눠 쓰는 자리의 **묶음 라벨 하나**.
#
# 칸으로 나누면 도면이 줄무늬 표처럼 보인다(실기기 확인). 대신 「첫 매장
# 외 N」 라벨 하나를 centroid에 놓고, 클라이언트가 누르면 매장 목록 시트를
# 띄운다 — 라벨 feature의 `cluster`(매장 수)가 그 신호이고, `id`는 대표(첫)
# 매장이라 클라이언트가 같은 centroid의 매장들을 되찾는 열쇠가 된다.
# `shared`도 함께 붙어 충돌 판정을 끈 레이어가 그린다 — 이 라벨 하나가 그
# 자리 전체의 유일한 입구라, 밀려서 사라지면 매장 N곳이 통째로 숨는다.
def _cluster_labels(
    groups: Sequence[list[Store]],
    transform: GeoTransform,
) -> list[dict]:
    features: list[dict] = []
    for group in groups:
        if len(group) < 3:
            continue
        _, _, _, ordered = group_axis_and_order(group)
        first = ordered[0]
        lat, lng = transform.apply(first.centroid_x_m, first.centroid_y_m)
        properties: dict = {
            "id": first.id,
            "name": f"{first.name} 외 {len(ordered) - 1}",
            "kind": "store",
            "cluster": len(ordered),
            "shared": True,
        }
        if first.category is not None:
            properties["category"] = first.category
        if first.subcategory is not None:
            properties["subcategory"] = first.subcategory
        features.append(
            {
                "geometry": {"type": "Point", "coordinates": [lng, lat]},
                "properties": properties,
            }
        )
    return features


# 건물 하나의 layers(footprint/stores/pois)를 wgs84 GeoJSON feature로 만든다.
# 타일 경계 상자와 겹치지 않는 feature는 걸러낸다(정밀 클리핑 없이 bbox 교차만
# 확인 — 실내 지도는 feature 수가 적어 이 정도로도 타일이 과도하게 커지지 않는다).
# transform이 None이면 빈 레이어만 담은 유효한 빈 타일을 돌려준다 — 404 대신
# "표시할 게 없다"로 처리해 MapLibre가 에러 없이 조용히 아무것도 안 그리게 한다.
def build_floor_tile_layers(
    building: Building,
    # 호출부가 session.scalars(...).all()의 Sequence를 그대로 넘긴다 — list로 좁히지 않는다.
    stores: Sequence[Store],
    pois: Sequence[Poi],
    transform: GeoTransform | None,
    bounds: TileBounds,
    footprint_local_m: list[dict] | None = None,
    # 못 걷는 면 도형 목록(Floor.non_walkable_polygons_local_m). 항목은
    # {"id", "kind", "polygon_local_m"}이고, 없는 층은 None이다.
    non_walkable_local_m: list[dict] | None = None,
    # 매장 id → 라벨 좌표(lng, lat) memo. 호출자가 소유·무효화하는 저장소를
    # 넘기면 이미 계산된 매장의 label_point를 건너뛰고, 새로 계산한 값을 채운다.
    #
    # 타일 간 재사용이 안전한 근거: 라벨 좌표의 입력은 매장 폴리곤(local_m)과
    # 건물 단위 affine 변환(GeoTransform) 둘뿐이다. 변환은 건물 전체에 하나로
    # 피팅되고(z/x/y와 무관), bounds는 라벨을 실을지 말지만 거르지 좌표 계산에는
    # 끼지 않는다. 타일 격자 양자화는 이후 MVT 인코딩 단계에서 일어난다. 따라서
    # 같은 DB 상태(=같은 revision)에서는 어느 타일에서 계산하든 같은 좌표가
    # 나온다. 무효화(재시드 시점) 책임은 호출자(tile_queries)에 있다.
    store_label_memo: MutableMapping[str, tuple[float, float]] | None = None,
) -> list[dict]:
    if transform is None:
        return []

    layers: list[dict] = []

    # 층 외곽선을 받으면 그것을 그린다. 건물 footprint는 기준층 것이라 지하층
    # 타일에도 1F 윤곽이 찍힌다.
    footprint = footprint_local_m or building.footprint_local_m or []
    footprint_ring = _local_polygon_ring(footprint, transform)
    if footprint_ring and bounds.intersects(*_polygon_bbox(footprint_ring)):
        layers.append(
            {
                "name": "footprint",
                "features": [
                    {
                        "geometry": {"type": "Polygon", "coordinates": [footprint_ring]},
                        "properties": {"kind": "footprint", "building_id": building.id},
                    }
                ],
            }
        )

    # 매장 폴리곤 — 타일에 걸치지 않는 것은 버린다.
    #
    # 라벨(아이콘+이름)은 같은 폴리곤에 얹지 않고 아래 store_labels 점 레이어로
    # 따로 내려보낸다. 이유는 [label_point.py] 상단에 적었다 — MapLibre가 폴리곤
    # 심볼을 면적 무게중심에 찍는데, ㄱ자·길쭉한 매장에서 그 점이 눈에 보이는
    # 가운데가 아니다.
    store_features = []
    label_features = []
    # 묶음 매장(다른 매장 이름을 이어 붙인 항목)은 라벨을 달지 않고 칸 배치
    # 그룹에서도 뺀다 — 구성 매장들이 이미 각자 폴리곤·라벨을 갖고 있다.
    aggregate_ids = aggregate_store_ids(stores)
    shared_groups = shared_store_groups(stores, aggregate_ids)
    # 두 곳 그룹의 칸 배치. label_point 격자 탐색이 아니라 산술 계산뿐이라
    # memo를 거치지 않는다.
    shared_layouts = _shared_layouts(shared_groups, transform)
    # 세 곳 이상 그룹의 구성 매장 — 개별 라벨 대신 묶음 라벨 하나로 접는다.
    clustered_ids = {store.id for group in shared_groups if len(group) >= 3 for store in group}
    for store in stores:
        if not store.polygon:
            continue
        layout = shared_layouts.get(store.id)
        polygon_local = store.polygon
        if layout is not None:
            # 나눠 쓰는 자리는 fill도 자기 칸으로 잘라 내보낸다. 화면에서 실제로
            # 나뉜 구역으로 보이고, 탭 판정이 폴리곤만으로 정확해진다.
            clipped = clip_polygon_to_slab(store.polygon, layout.slab.axis_is_x, layout.slab.low, layout.slab.high)
            if clipped:
                polygon_local = clipped
        ring = _local_polygon_ring(polygon_local, transform)
        if not ring or not bounds.intersects(*_polygon_bbox(ring)):
            continue
        store_features.append(
            {
                "geometry": {"type": "Polygon", "coordinates": [ring]},
                "properties": _store_properties(store),
            }
        )
        # **라벨 점은 그 점이 들어 있는 타일에만 싣는다.** 폴리곤과 같은 기준
        # (bbox 교차)으로 실으면 타일 경계에 걸친 매장이 양쪽 타일에 라벨을
        # 하나씩 갖게 되고, 두 타일이 함께 떠 있는 순간 같은 이름이 두 번
        # 찍힌다. 대신 화면 가장자리에서 폴리곤 타일만 로드된 상태면 그 매장
        # 라벨이 잠깐 안 보이는데, POI 레이어가 이미 같은 규칙으로 동작한다.
        # 묶음 매장은 라벨을 달지 않는다 — 구성 매장들의 이름이 이미 화면에
        # 있다. 세 곳 이상 그룹의 구성 매장도 개별 라벨 대신 아래에서 묶음
        # 라벨 하나로 접는다.
        if store.id in aggregate_ids or store.id in clustered_ids:
            continue
        if layout is not None:
            label_xy = layout.label_lnglat
        else:
            memoized = store_label_memo.get(store.id) if store_label_memo is not None else None
            if memoized is None:
                label_xy = label_point(_closed_ring_to_points(ring))
                if store_label_memo is not None:
                    store_label_memo[store.id] = label_xy
            else:
                label_xy = memoized
        label_x, label_y = label_xy
        if bounds.intersects(label_x, label_y, label_x, label_y):
            label_properties = _store_properties(store)
            if layout is not None:
                # 클라이언트가 이 표시로 충돌 판정을 끈 전용 레이어를 갈라낸다.
                # 칸으로 나눠도 라벨 간격이 글자 폭보다 좁을 수 있어, 일반
                # 레이어에 두면 충돌 처리가 결국 하나를 지운다.
                label_properties["shared"] = True
            label_features.append(
                {
                    "geometry": {"type": "Point", "coordinates": [label_x, label_y]},
                    "properties": label_properties,
                }
            )
    # 세 곳 이상 그룹의 묶음 라벨. 점이라 bbox 교차가 곧 포함 여부다.
    for feature in _cluster_labels(shared_groups, transform):
        lng, lat = feature["geometry"]["coordinates"]
        if bounds.intersects(lng, lat, lng, lat):
            label_features.append(feature)
    layers.append({"name": "stores", "features": store_features})

    # 못 걷는 면(아트리움 보이드·기둥·조경) — **stores 바로 위, store_labels 아래.**
    #
    # 이 목록 순서가 클라이언트가 레이어를 꽂는 순서와 같다(뒤에 올수록 위).
    # stores 아래에 두면 지하 주차 구획이 전부 매장이라 기둥 면적의 40%가
    # 주차칸에 가린다(실측: docs/client/kakao-map-indoor-observation.md 3절).
    # 위로 올려도 매장은 안 사라진다 — 매장 중심점을 품는 도형은 임포터가
    # 이미 뺐고(build_studio_from_dabeeo.py), 라벨·아이콘은 더 위에 있다.
    #
    # 도형이 없는 층(B2)에서도 **빈 레이어를 반드시 낸다.** 층마다 레이어 유무가
    # 갈리면 클라이언트 sourceLayer 배선이 그 층에서만 달라진다.
    #
    # properties는 kind만 싣는다 — 매장 id·name·category를 실으면 카테고리 강조
    # 필터(`['get','category']`)나 탭 판정(`properties['id']`)에 새어 들어간다.
    layers.append(
        {
            "name": "non_walkable",
            "features": _non_walkable_features(non_walkable_local_m or [], transform, bounds),
        }
    )

    layers.append({"name": "store_labels", "features": label_features})

    # POI는 점이라 bbox 교차가 곧 포함 여부다.
    poi_features = []
    for poi in pois:
        lat, lng = transform.apply(poi.x_m, poi.y_m)
        if not bounds.intersects(lng, lat, lng, lat):
            continue
        poi_features.append(
            {
                "geometry": {"type": "Point", "coordinates": [lng, lat]},
                "properties": {"id": poi.id, "name": poi.name, "type": poi.type},
            }
        )
    layers.append({"name": "pois", "features": poi_features})

    return layers
