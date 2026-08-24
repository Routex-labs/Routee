import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 카테고리 대분류 이름에 대응하는 아이콘·색상·표시 라벨. chip과 시트 헤더가
/// 같은 시각 정체성을 갖도록 여러 곳에서 공유한다. 예상치 못한 카테고리는
/// 상점 기본 아이콘과 앱 primary 색으로 폴백한다.
/// 대분류 아이콘.
///
/// `식음료`는 **유통업계 용어라 사용자가 쓰는 말이 아니어서** 음식점·카페·식품관
/// 셋으로 나눴고, `서비스`는 **편의시설과의 경계가 정의된 적이 없어** 리테일이
/// 섞여 들던 자리라 없앴다(`docs/store-category-resurvey.md`). 둘 다 옛
/// 이름을 지우지 않고 남겨 두는 이유는 배포 시차다 — 클라이언트가 먼저 올라가고
/// 백엔드 시드가 아직 옛 어휘를 주는 동안, 지우면 그 매장들이 회색 storefront로
/// 떨어진다.
const _iconByCategory = <String, IconData>{
  '패션': Icons.checkroom,
  '편의시설': Icons.info_outline,
  '음식점': Icons.restaurant,
  '카페': Icons.local_cafe_outlined,
  '식품관': Icons.local_grocery_store_outlined,
  '식음료': Icons.restaurant, // 구 어휘 — 위 주석 참고
  '리빙': Icons.weekend_outlined,
  '서비스': Icons.support_agent,
  '키즈': Icons.child_care,
  '뷰티': Icons.brush,
};

/// 대분류 색.
///
/// 패션·음식점·카페·뷰티·식품관 다섯 갈래는 **지정된 Pantone 값**이다. 임의로
/// 밝기를 올리거나 내리면 지정색이 아니게 되므로, 조정이 필요하면 색상값이 아니라
/// 이 표를 쓰는 쪽(원 배경·면 채우기)의 대비를 손본다.
///
/// 나머지 셋(리빙·편의시설·키즈)과 옛 어휘 `서비스`는 지정색이 없어 그 다섯의 톤
/// 대역에 맞춘 파스텔로 눌렀다. 흰 글리프가 올라가므로 지정색보다 밝게 잡지 않는다.
///
/// 각 색의 Pantone 번호와 색상각 선택 근거는 `docs/client/map-style-rules.md`.
const _colorByCategory = <String, Color>{
  '패션': Color(0xFFA2B2C8),
  '편의시설': Color(0xFFAEBDC3),
  '음식점': Color(0xFFCA9A8E),
  '카페': Color(0xFFE1B87F),
  '식품관': Color(0xFF85B09A),
  '식음료': Color(0xFFCA9A8E), // 구 어휘 — 음식점과 같은 값을 유지한다
  '리빙': Color(0xFF87BEB8),
  '서비스': Color(0xFF9BA3D6),
  '키즈': Color(0xFFC5A8D0),
  '뷰티': Color(0xFFF2ACB9),
};

/// 아이콘·색이 정의된 대분류 목록.
///
/// 지도 심볼 레이어가 카테고리별 아이콘 비트맵을 **미리** 등록할 때 쓴다 —
/// MapLibre는 사전 등록된 이미지만 참조할 수 있어서, 어떤 카테고리가 올지
/// 런타임에 알아내는 방식이 통하지 않는다([category_map_icon.dart]).
///
/// 구 어휘(`식음료`)도 그대로 들어 있다. 등록 비용이 비트맵 한 장이라, 빼서
/// 배포 시차 동안 그 매장들이 폴백 아이콘으로 떨어지는 쪽이 손해다.
Iterable<String> get categoryIconCategories => _iconByCategory.keys;

/// 색이 정의된 대분류 목록. 매장 폴리곤을 대분류 색으로 칠하는 표현식이
/// 쓴다([category_map_fill.dart]).
///
/// [categoryIconCategories]와 **같은 키 집합이어야 한다** — 한쪽에만 있는
/// 대분류가 생기면 지도에서 아이콘은 붙는데 면은 회색이거나(또는 그 반대)
/// 그 카테고리만 반쯤 칠해진 것처럼 보인다. 테스트가 이 일치를 지킨다.
Iterable<String> get categoryPaletteCategories => _colorByCategory.keys;

IconData categoryIconFor(String category) =>
    _iconByCategory[category] ?? Icons.storefront;

Color categoryColorFor(String category) =>
    _colorByCategory[category] ?? AppColors.primary;

/// 대분류 색을 **같은 색 계열에서 더 진하게** 만든다. 색상각은 그대로 두고
/// 채도를 [saturate]배 올린 뒤 명도를 [darken]만큼만 내린다.
///
/// **채널을 통째로 곱하지 않는다.** 곱셈은 명도와 함께 절대 채도까지 끌어내려
/// 같은 색의 진한 쪽이 아니라 **탁하고 어두운 색**이 된다(실기기에서 되돌린
/// 방식이다). 파스텔의 문제는 어두움이 아니라 옅음이므로, 대비는 채도에서
/// 먼저 얻고 명도는 거들기만 한다.
///
/// 두 단계로 쓴다 — 카테고리 강조 테두리(약하게)와 고른 매장 하나
/// ([kCategorySelectedSaturate]·[kCategorySelectedDarken], 진하게).
/// 실제 값과 근거는 `docs/client/map-style-rules.md` 1절.
Color categoryColorDeepen(
  String category, {
  required double saturate,
  required double darken,
}) {
  final hsl = HSLColor.fromColor(categoryColorFor(category));
  return hsl
      .withSaturation((hsl.saturation * saturate).clamp(0.0, 1.0))
      .withLightness((hsl.lightness - darken).clamp(0.0, 1.0))
      .toColor();
}

/// 고른 매장 하나를 가리키는 잉크. 폴리곤 테두리이자 아이콘 원 배경이다.
///
/// 같은 카테고리의 **안 고른** 매장 테두리(1.25·0.06)보다 한 단계 진하다.
/// 위에 흰 글리프가 올라가지만 도면 아이콘은 원래 그 대비로 그려 왔다 — 여기서
/// 4.5:1을 맞추려고 명도를 더 내리면 다시 "어둡다"로 돌아간다. 대신 안 고른
/// 배지보다 **반드시 대비가 높다**는 것만 테스트가 지킨다.
const kCategorySelectedSaturate = 1.4;
const kCategorySelectedDarken = 0.14;

/// 매장 리스트에서 단일 아이템 왼쪽에 붙는 아이콘. 편의시설처럼 이질적인
/// 하위 항목이 섞이는 카테고리에서 어떤 종류인지 한 눈에 알 수 있게 한다.
/// subcategory가 있으면 그것으로 먼저 판정하고, 없으면 매장 이름의 부분
/// 문자열(정수기·ATM·수유실 등)로 판정한다. 어느 규칙에도 걸리지 않는
/// 일반 매장은 상점 아이콘([Icons.storefront])으로 폴백한다.
///
/// subcategory 표기가 두 갈래라 양쪽을 모두 받는다. 층 원본(studio JSON)에서
/// 온 시설물은 `restroom`·`elevator` 같은 영어 소문자이고, 카테고리 오버라이드
/// (store_categories*.json)를 거친 매장은 `레스토랑`·`카페·베이커리` 같은 한글이다.
///
/// [category]를 주면 어느 세부 규칙에도 걸리지 않았을 때 상점 아이콘 대신 대분류
/// 아이콘으로 떨어진다. 매장의 78%가 Studio 원본에서 `매장`이라는 무의미한
/// subcategory를 갖고 있어, 세부 규칙만으로는 대부분이 같은 글리프가 된다.
IconData storeIconFor({String? name, String? subcategory, String? category}) {
  final sub = subcategory?.toLowerCase();
  switch (sub) {
    // 영어 원본값은 이제 시드에서 한글로 들어오지만, 배포 시차 동안 옛 타일·
    // 옛 응답이 영어를 줄 수 있어 양쪽을 모두 받는다.
    case 'restroom':
    case '화장실':
      return Icons.wc;
    case 'elevator':
    case '엘리베이터':
      return Icons.elevator;
    case 'escalator':
    case '에스컬레이터':
      return Icons.escalator;
    case 'cafe':
    case '카페·베이커리':
      return Icons.local_cafe_outlined;
    case 'restaurant':
    case '레스토랑':
      return Icons.restaurant;
    case '식품·그로서리':
      return Icons.local_grocery_store_outlined;
    case '와인·주류':
      return Icons.wine_bar_outlined;
  }
  final n = name ?? '';
  if (n.contains('화장실') || n.contains('세면대')) return Icons.wc;
  if (n.contains('정수기')) return Icons.water_drop_outlined;
  if (n.contains('ATM') || n.contains('은행')) return Icons.local_atm;
  if (n.contains('수유실')) return Icons.child_friendly;
  if (n.contains('흡연')) return Icons.smoking_rooms;
  if (n.contains('취식')) return Icons.dining_outlined;
  if (n.contains('엘리베이터')) return Icons.elevator;
  if (n.contains('에스컬레이터')) return Icons.escalator;
  if (n.contains('물품보관') || n.contains('락커')) return Icons.lock_outline;
  if (category != null && _iconByCategory.containsKey(category)) {
    return _iconByCategory[category]!;
  }
  return Icons.storefront;
}
