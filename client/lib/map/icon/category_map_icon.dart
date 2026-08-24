/// 지도 위 매장명 라벨에 붙는 **대분류 아이콘**과, 이름이 아이콘 좌/우 중 어느
/// 쪽에 놓일지 정하는 규칙.
///
/// 글리프와 색은 chip·목록 시트와 **같은 표**에서 가져온다.
///
/// 좌/우 뒤집기는 `text-variable-anchor`에 맡긴다 — **충돌 판정**으로 자리를 고르므로
/// `text-allow-overlap`을 켜면 앵커가 항상 첫 값이 되어 조용히 죽는다.
/// 그 밖의 근거는 `docs/client/map-style-rules.md` 7절.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'category_icon.dart';
import '../style/floor_facility_style.dart';

/// 대분류가 없는 매장에 쓰는 폴백 키.
///
/// 타일은 `category`가 null이면 **키 자체를 싣지 않아**(`tiling.py`의
/// `_store_properties`) `match`의 default로 떨어진다. 이 키는 [categoryIconFor]의
/// 표에도 없으므로 매장 목록 시트와 같은 storefront + primary로 폴백한다.
const kStoreCategoryFallbackKey = '__분류없음__';

/// [MapLibreMapController.addImage]에 등록할 이름. 카테고리마다 색이 달라
/// 글리프 codePoint만으로는 구분되지 않으므로 대분류 이름을 키로 삼는다
/// ([facilityIconImageName]과 같은 이유).
String storeCategoryIconImageName(String category) =>
    'store-category-icon-$category';

/// 고른 매장에 쓰는 같은 글리프의 포인트 색 버전.
String selectedStoreCategoryIconImageName(String category) =>
    'store-category-icon-selected-$category';

/// 지도에 등록해야 하는 대분류 아이콘 전체. 폴백까지 포함한다.
Iterable<String> get storeCategoryIconKeys => [
  ...categoryIconCategories,
  kStoreCategoryFallbackKey,
];

/// `stores` feature의 `category`로 아이콘 비트맵을 고르는 표현식.
///
/// `match`의 label 자리에 **문자열만** 들어간다. 배열을 label로 쓰는 형태는
/// MapLibre GL Native에서 조용히 매치 0건이 되는 경로가 있어 이 저장소가 이미
/// 한 번 데였다(`category_map_filter.dart` 주석). 이 형태는 POI·편의시설 아이콘이
/// 실기기에서 검증한 경로와 같다.
List<Object> _storeCategoryIconMatch({required bool selected}) => [
  'match',
  ['get', 'category'],
  for (final category in categoryIconCategories) ...[
    category,
    selected
        ? selectedStoreCategoryIconImageName(category)
        : storeCategoryIconImageName(category),
  ],
  selected
      ? selectedStoreCategoryIconImageName(kStoreCategoryFallbackKey)
      : storeCategoryIconImageName(kStoreCategoryFallbackKey),
];

/// 선택된 feature는 크기를 바꾸지 않고 같은 아이콘을 포인트 색으로 바꾼다.
List<Object> storeCategoryIconExpression({String? highlightedStoreId}) {
  final normal = _storeCategoryIconMatch(selected: false);
  if (highlightedStoreId == null) return normal;
  return [
    'case',
    [
      '==',
      ['get', 'id'],
      highlightedStoreId,
    ],
    _storeCategoryIconMatch(selected: true),
    normal,
  ];
}

/// 실내 화면의 대분류 배지 `icon-size`.
///
/// 화장실 아이콘과 **같은 값 하나**([kIndoorMarkerLogicalPx])를 쓰고 zoom 보간도
/// 걸지 않는다. 배지만 줌에 따라 커지면 같은 화면에서 시설 아이콘과 크기가 어긋난다.
///
/// **배율 환산은 그대로 필요하다.** `icon-size`는 비트맵의 **물리** 픽셀에 곱해지고
/// `text-size`는 논리 픽셀이라, 안 곱하면 고밀도 화면에서 아이콘만 배율만큼 작아진다
/// — Galaxy S23(배율 3.5)에서 글자 49 물리px 옆에 배지가 19 물리px으로 떴다. 환산은
/// [indoorMarkerIconSize]가 맡는다.
double storeCategoryIconSize(double devicePixelRatio) =>
    indoorMarkerIconSize(devicePixelRatio);

/// 대분류 아이콘 비트맵. 흰 테두리 + 카테고리 색 원 + 흰 글리프.
///
/// MapLibre 심볼 레이어는 사전 등록된 비트맵만 참조할 수 있어서 폰트 글리프를
/// 직접 캔버스에 그려 PNG로 바꾼다([renderPoiIconPng]와 같은 이유).
Future<Uint8List> renderStoreCategoryIconPng(
  String category, {
  bool selected = false,
}) async {
  const canvasSize = 96.0;
  const center = Offset(canvasSize / 2, canvasSize / 2);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    const Rect.fromLTWH(0, 0, canvasSize, canvasSize),
  );

  // 흰 테두리는 도면(연회색)·강조된 매장(연파랑) 어느 배경 위에서도 원의 윤곽이
  // 살아 있게 한다. 배경색만 칠하면 밝은 카테고리 색이 도면에 묻힌다.
  canvas.drawCircle(center, canvasSize / 2, Paint()..color = Colors.white);
  // 선택은 **다른 색이 아니라 같은 색의 진한 쪽**이다. 청록 하나로 칠하던
  // 시절에는 어느 매장을 골라도 배지가 같은 초록이 되어, 고른 순간 그 매장이
  // 무슨 대분류인지가 화면에서 사라졌다.
  canvas.drawCircle(
    center,
    canvasSize / 2 - 5,
    Paint()
      ..color = selected
          ? categoryColorDeepen(
              category,
              saturate: kCategorySelectedSaturate,
              darken: kCategorySelectedDarken,
            )
          : categoryColorFor(category),
  );

  paintIconGlyph(
    canvas,
    icon: categoryIconFor(category),
    color: Colors.white,
    fontSize: canvasSize * 0.55,
    center: center,
  );

  final image = await recorder.endRecording().toImage(
    canvasSize.toInt(),
    canvasSize.toInt(),
  );
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}
