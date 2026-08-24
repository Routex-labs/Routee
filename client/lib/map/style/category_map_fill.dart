/// 카테고리를 선택했을 때 **강조되는 매장**을 대분류 색으로 칠하는 규칙.
///
/// 평소에는 칠하지 않는다 — 항상 칠하면 도면이 색 밭이 되어 무엇이 선택됐는지가
/// 오히려 안 읽힌다. 색은 chip·시트와 **같은 표**를 쓴다.
///
/// 카테고리마다 레이어를 얹지 않고 **강조 레이어 하나**의 색만 바꾼다.
/// 그 밖의 근거는 `docs/client/map-style-rules.md` 4절.
library;

import 'package:flutter/painting.dart' show Color;

import 'palette.dart';
import '../icon/category_icon.dart';

/// 면에 섞는 대분류 색의 비율. 0이면 흰색, 1이면 대분류 색 원본이다.
///
/// **기준은 "면이 어두운가"가 아니라 "기본 매장 면(`mapStoreFill`)과 다른가"다.**
/// 0.18은 대분류가 진했던 시절 옛 파랑(`#D6E4FC`, 휘도 0.77)과 같은 대역을
/// 만들던 값인데, 아홉 색이 전부 파스텔로 바뀌자 같은 비율이 휘도 0.86~0.90을
/// 뱉었다 — 기본 매장 면(0.858)과 차이가 0.001~0.039뿐이라 강조를 걸어도 티가
/// 나지 않았고, 여섯 대분류는 오히려 기본보다 밝아져 "밝을수록 걷는 곳"이라는
/// 도면 규칙과 반대로 읽혔다. 0.35가 옛 파랑과 같은 대역(0.74~0.81)을 되돌린다.
///
/// 올릴 때 걸리는 상한은 매장명(`#444846`) 가독이고, 임계값은
/// `test/map/style/category_map_fill_test.dart`가 지킨다.
const _fillTintRatio = 0.35;

/// 강조 테두리를 진하게 만드는 정도([categoryColorDeepen]).
///
/// **채도가 먼저다.** 파스텔 아홉 색은 원본 그대로면 기본 매장 경계선
/// (`mapStoreOutline`)과 명도가 겹쳐 강조해도 테두리가 흐려 보인다. 그렇다고
/// 명도를 크게 내리면(한때 채널 ×0.7) 색 계열을 잃고 탁해진다 — 실기기 판정이
/// "너무 진하고 어둡다"였다. 채도를 1.25배 올리고 명도는 0.06만 내린다.
///
/// 기본 경계선과의 구분은 이제 명도가 아니라 **채도**가 만든다(그 표는 회색에
/// 가까운 s=0.10이다). 검증은 `test/map/style/category_map_fill_test.dart`.
const _outlineSaturate = 1.25;
const _outlineDarken = 0.06;

String _hex(int r, int g, int b) {
  final rgb = (r << 16) | (g << 8) | b;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

String _hexOf(Color color) => _hex(
  (color.r * 255).round(),
  (color.g * 255).round(),
  (color.b * 255).round(),
);

int _mixOverWhite(double channel) =>
    (channel * 255 * _fillTintRatio + 255 * (1 - _fillTintRatio)).round().clamp(
      0,
      255,
    );

/// 매장 면에 쓰는 옅은 대분류 색(`#RRGGBB`).
String categoryFillTintHex(String category) {
  final color = categoryColorFor(category);
  return _hex(
    _mixOverWhite(color.r),
    _mixOverWhite(color.g),
    _mixOverWhite(color.b),
  );
}

/// 매장 경계선에 쓰는 대분류 색을 [_outlineShade]만큼 낮춘 값(`#RRGGBB`).
String categoryOutlineHex(String category) => _hexOf(
  categoryColorDeepen(
    category,
    saturate: _outlineSaturate,
    darken: _outlineDarken,
  ),
);

/// 고른 매장 하나의 테두리·아이콘에 쓰는 **가장 진한** 대분류 색(`#RRGGBB`).
///
/// 같은 카테고리의 안 고른 매장이 [categoryOutlineHex]를 쓰므로 채도·명도
/// 양쪽에서 한 단계 더 간다 — "고른 하나"가 "같은 종류 여럿"보다 진해야
/// 골라진 것이 보인다. 도면 위 색이 아니라 **선과 점**의 색이라 매장명을
/// 가리지 않는다.
String categorySelectedHex(String category) => _hexOf(
  categoryColorDeepen(
    category,
    saturate: kCategorySelectedSaturate,
    darken: kCategorySelectedDarken,
  ),
);

/// `category` 속성으로 색을 고르는 `match` 표현식을 만든다.
///
/// label 자리에 **문자열만** 넣는다 — 배열을 label로 쓰는 형태는 MapLibre GL
/// Native에서 예외도 로그도 없이 매치 0건이 된다(`category_map_filter.dart`).
List<Object> _colorByCategoryExpression(
  String Function(String category) colorFor,
  String fallback,
) => [
  'match',
  ['get', 'category'],
  for (final category in categoryPaletteCategories) ...[
    category,
    colorFor(category),
  ],
  fallback,
];

/// `stores` feature의 `category`로 강조 면 색을 고르는 표현식.
///
/// default는 [mapStoreFill] — 표에 없는 대분류거나 타일에 `category` 키가 아예
/// 없는 매장(`tiling.py`의 `_store_properties`는 null이면 키를 싣지 않는다)은
/// 강조돼도 기본 매장 색 그대로다(= 눈에 띄는 변화가 없을 뿐 깨지지 않는다).
List<Object> storeCategoryHighlightFillColorExpression() =>
    _colorByCategoryExpression(categoryFillTintHex, mapStoreFill);

/// 같은 규칙의 경계선 색. default는 [mapStoreOutline].
List<Object> storeCategoryHighlightOutlineExpression() =>
    _colorByCategoryExpression(categoryOutlineHex, mapStoreOutline);

/// 고른 매장 한 곳을 칠하는 면·테두리 색.
///
/// **파랑 하나였다.** 어느 매장을 골라도 같은 파랑이면 "고름"은 보이지만 그
/// 매장이 무엇인지는 색이 말해 주지 않았고, 카테고리 강조를 켠 상태에서는
/// 파란 면이 그 위에 겹쳐 대분류 색을 지웠다. 이제 같은 표의 자기 색을 쓰되
/// 진하기로 위계를 만든다 — 안 고른 같은 카테고리 0.7, 고른 하나 0.55.
///
/// default는 [mapSelectionFallback]. 대분류가 없는 매장도 고르면 반드시 보여야
/// 하므로 기본 매장 색이 아니라 회색 잉크로 떨어진다.
List<Object> storeSelectionColorExpression() =>
    _colorByCategoryExpression(categorySelectedHex, mapSelectionFallback);
