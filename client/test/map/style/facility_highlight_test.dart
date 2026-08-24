/// 시설 필터가 파랗게 칠할 폴리곤을 고르는 규칙.
///
/// 조용히 깨지는 자리라 테스트로 못 박는다 — 소분류가 안 맞으면 예외 없이 0건이
/// 되고, 반대로 대분류만 보고 칠하면 도면이 통째로 파래진다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/map/style/category_map_filter.dart';
import 'package:navigation_client/map/style/facility_highlight.dart';
import 'package:navigation_client/models/building/floor_plan.dart';

void main() {
  StorePolygon store({
    required String id,
    required String category,
    String? subcategory,
  }) => StorePolygon(
    id: id,
    name: id,
    polygon: const [
      LatLng(37.5, 126.9),
      LatLng(37.5, 126.901),
      LatLng(37.501, 126.901),
    ],
    centroid: const LatLng(37.5, 126.9),
    category: category,
    subcategory: subcategory,
  );

  final stores = [
    store(id: 'toilet-1', category: '편의시설', subcategory: '화장실'),
    store(id: 'toilet-2', category: '편의시설', subcategory: '화장실'),
    store(id: 'lift', category: '편의시설', subcategory: '엘리베이터'),
    store(id: 'parking', category: '편의시설', subcategory: '주차'),
    store(id: 'cafe', category: '카페', subcategory: '카페·베이커리'),
  ];

  test('고른 소분류만 칠한다', () {
    final polygons = facilityHighlightPolygons(
      stores: stores,
      selection: const CategorySelection(
        category: '편의시설',
        subcategory: '화장실',
      ),
    );

    expect(polygons.length, 2);
  });

  test('대분류만 고른 상태는 칠하지 않는다 — 주차까지 덮여 도면이 파래진다', () {
    expect(
      facilityHighlightPolygons(
        stores: stores,
        selection: const CategorySelection(category: '편의시설'),
      ),
      isEmpty,
    );
  });

  test('시설이 아닌 대분류는 이 강조를 쓰지 않는다 — 타일 fill이 칠한다', () {
    expect(
      facilityHighlightPolygons(
        stores: stores,
        selection: const CategorySelection(
          category: '카페',
          subcategory: '카페·베이커리',
        ),
      ),
      isEmpty,
    );
  });

  test('선택이 없으면 빈 목록', () {
    expect(
      facilityHighlightPolygons(stores: stores, selection: null),
      isEmpty,
    );
  });

  test('이 층에 그 시설이 없으면 빈 목록 — 층을 바꿔도 옛 층 도형이 남지 않는다', () {
    expect(
      facilityHighlightPolygons(
        stores: [store(id: 'cafe', category: '카페', subcategory: '카페·베이커리')],
        selection: const CategorySelection(
          category: '편의시설',
          subcategory: '에스컬레이터',
        ),
      ),
      isEmpty,
    );
  });
}
