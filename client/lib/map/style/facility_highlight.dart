/// 시설을 종류로 골랐을 때 **파랗게 칠할 폴리곤**을 고른다.
///
/// 다른 대분류는 타일 fill이 옅은 대분류 색으로 칠하지만
/// ([storeCategoryHighlightFillColorExpression]) 편의시설 색(`#AEBDC3`)은 18%로
/// 희석하면 거의 흰색이라 화면에서 아무 일도 일어나지 않고, 엘리베이터·
/// 에스컬레이터는 그 위에 상시 초록 오버레이까지 덮인다. 그래서 시설만 매장 탭과
/// 같은 강조 소스를 쓴다.
library;

import 'package:latlong2/latlong.dart';

import '../../domain/category/category_taxonomy.dart';
import '../../models/building/floor_plan.dart';
import 'category_map_filter.dart';

/// [selection]이 시설 소분류를 가리키면 이 층의 그 시설 폴리곤 전부, 아니면 빈 목록.
///
/// 대분류만 고른 상태(소분류 null)는 빈 목록이다 — 편의시설 전체를 파랗게 칠하면
/// 주차칸까지 덮여 도면이 통째로 파래진다(1F 기준 시설 30여 곳).
List<List<LatLng>> facilityHighlightPolygons({
  required List<StorePolygon> stores,
  required CategorySelection? selection,
}) {
  final subcategory = selection?.subcategory;
  if (selection?.category != kFacilityCategory || subcategory == null) {
    return const [];
  }
  return [
    for (final store in stores)
      if (store.subcategory == subcategory) store.polygon,
  ];
}
