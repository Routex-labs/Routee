/// 야외 지도 위 실내 오버레이 레이어의 **완성된** 속성 묶음.
///
/// 규칙은 하나 — **`setLayerProperties`는 전체 교체다.** 그래서 최초 등록과 갱신이
/// 같은 함수를 쓴다(경위: `docs/client/map-style-rules.md` 0절).
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/painting.dart' show Color;
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../map/style/fonts.dart';
import '../../../map/style/label_style.dart';
import '../../../map/style/palette.dart';
import '../../../theme/app_theme.dart';
import '../../../map/style/category_map_fill.dart';
import '../../../map/style/category_map_filter.dart';
import '../../../map/icon/category_map_icon.dart';
import '../../../map/style/floor_facility_style.dart';
import '../entry/indoor_entry_zoom.dart'
    show indoorTilesMaxZoom, indoorTilesMinZoom;
import 'route_map_layers.dart' show kOutdoorRouteCasingLayerId;

/// `Color`를 MapLibre가 받는 `#RRGGBB` 문자열로. 알파는 별도 opacity 속성으로
/// 주므로 여기서는 RGB만 쓴다.
extension MapColorHex on Color {
  String toHexString() {
    final rgb =
        (r * 255).round() << 16 | (g * 255).round() << 8 | (b * 255).round();
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}

/// 야외 건물 폴리곤 fill. 탭 피드백으로 opacity만 오르내리지만, 그때도 색을
/// 반드시 함께 넘겨야 한다(파일 상단 규칙).
FillLayerProperties buildingFillProps(double opacity) => FillLayerProperties(
  fillColor: AppColors.primary.toHexString(),
  fillOpacity: opacity,
);

/// 실내 진입 상태에서만 그리는 현재 층 외곽선. 도면 **위에** 얹히는 선이라 얇게
/// (1px) 긋는다 — 굵으면 가장자리 매장을 덮고 선 자체가 도면처럼 읽힌다.
///
/// 링과 바닥은 **같은 층 footprint**에서 나와야 한다(다르면 경계가 어긋난다).
LineLayerProperties floorOutlineProps(List<Object> fadeExpr) =>
    LineLayerProperties(
      lineColor: AppColors.primary.toHexString(),
      lineWidth: 1,
      lineOpacity: fadeExpr,
      lineJoin: 'round',
    );

/// 실내 진입 dim scrim. 세계를 덮는 outer ring + 건물 hole 폴리곤을 칠한다.
FillLayerProperties dimScrimProps(Object fillOpacity) =>
    FillLayerProperties(fillColor: '#000000', fillOpacity: fillOpacity);

FillLayerProperties indoorFootprintProps(List<Object> fadeExpr) =>
    FillLayerProperties(
      fillColor: mapFootprintFill,
      fillOutlineColor: mapFootprintOutline,
      fillOpacity: fadeExpr,
    );

/// 걸을 수 없는 면(보이드·기둥·조경) fill. 타일의 `non_walkable` 소스 레이어를
/// 그린다.
///
/// **kind(void|pillar|feature)로 색을 가르지 않는다** — 카카오 실측에서 보이드와
/// 조경이 같은 회색 하나이고, 기둥만 다른 값을 주면 근거 없는 숫자가 된다.
FillLayerProperties indoorNonWalkableProps(List<Object> fadeExpr) =>
    FillLayerProperties(
      fillColor: mapNonWalkableFill,
      fillOutlineColor: mapNonWalkableOutline,
      fillOpacity: fadeExpr,
    );

/// 실내 오버레이의 매장 fill. 색은 [map_palette.dart]에서 온다 — 여기에 hex를
/// 직접 박으면 층 전환 사이에 같은 매장이 다른 색으로 보이던 옛 문제로 돌아간다.
FillLayerProperties indoorStoresFillProps(List<Object> fadeExpr) =>
    FillLayerProperties(
      fillColor: mapStoreFill,
      fillOutlineColor: mapStoreOutline,
      fillOpacity: fadeExpr,
    );

/// 카테고리 필터로 강조된 매장 fill. 색은 실내 화면과 **같은 표현식**을 쓰고
/// (같은 매장이 두 화면에서 다른 색이면 안 된다), 다른 점은 **opacity를 fadeExpr로
/// 묶는다**는 것뿐이다 — 안 묶으면 도면이 안 보이는 줌에서 강조만 공중에 뜬다.
FillLayerProperties indoorCategoryHighlightProps(List<Object> fadeExpr) =>
    FillLayerProperties(
      fillColor: storeCategoryHighlightFillColorExpression(),
      fillOutlineColor: storeCategoryHighlightOutlineExpression(),
      fillOpacity: fadeExpr,
    );

FillLayerProperties indoorVerticalTransportProps(List<Object> fadeExpr) =>
    FillLayerProperties(
      fillColor: '#DCEBD4',
      fillOutlineColor: '#6FA167',
      fillOpacity: fadeExpr,
    );

/// 매장명 라벨 + 대분류 아이콘(같은 심볼에 얹는 이유는 [category_map_icon.dart]).
///
/// **호출하는 쪽이 모두 [selection]을 넘겨야 한다** — 페이드 갱신에서도 불리는데
/// 거기서 빼먹으면 줌만 움직여도 가려 뒀던 이름이 되살아난다(상단 "전체 교체"
/// 규칙이 layout 속성에도 적용되는 경우다).
///
/// [alwaysVisible]은 **한 폴리곤을 여러 매장이 나눠 쓰는 자리** 전용이다. 충돌
/// 판정에 맡기면 하나가 지워져 보이는 이름과 열리는 매장이 어긋난다 — 1,640곳 중
/// 91곳뿐이라 조금 겹쳐도 번지지 않는다.
SymbolLayerProperties indoorStoresLabelProps(
  List<Object> fadeExpr,
  CategorySelection? selection,
  double devicePixelRatio, {
  bool alwaysVisible = false,
  Object? symbolSortKey,
  String? highlightedStoreId,
}) => SymbolLayerProperties(
  textField: categoryLabelTextField(selection),
  textFont: const [mapFontStackRegular],
  // 색·헤일로·크기 전부 [map_label_style.dart]가 단일 출처다. 크기가 고정인
  // 이유는 이 오버레이가 도면 전체를 훑는 축소 화면이라, 폴리곤 맞춤 크기를
  // 쓰면 작은 매장 이름이 읽을 수 없게 작아지기 때문이다. 선택 표시도 크기가 아니라
  // 아이콘 색만 바꾸어 라벨 밀도를 흔들지 않는다.
  textSize: mapLabelFixedTextSize,
  textColor: mapLabelStoreColor,
  textHaloColor: mapLabelHaloColor,
  textHaloWidth: mapLabelHaloWidth,
  textMaxWidth: mapLabelFixedMaxWidth,
  textOpacity: fadeExpr,
  iconImage: storeCategoryIconExpression(
    highlightedStoreId: highlightedStoreId,
  ),
  // 화장실·정수기 같은 시설 아이콘과 **같은 크기 하나**를 쓴다
  // ([kIndoorMarkerLogicalPx]). 실내 화면이 같은 피드백("대분류 아이콘을
  // 화장실만큼")으로 이미 내린 결론인데 이 오버레이만 따라오지 않았다.
  iconSize: indoorMarkerIconSize(devicePixelRatio),
  iconOpacity: fadeExpr,
  // 이름은 항상 아이콘 아래다 — 실내 도면·편의시설 라벨과 같은 규칙.
  textAnchor: 'top',
  textOffset: mapLabelBelowIconOffset,
  textJustify: 'center',
  textAllowOverlap: alwaysVisible,
  iconAllowOverlap: alwaysVisible,
  // 일반 매장은 아이콘과 이름을 **한 단위로** 배치한다. 둘 중 하나만 optional로
  // 두면 붐비는 축소 화면에서 이름은 사라지고 색 아이콘만 남아, 무엇을 뜻하는지
  // 알 수 없는 점들로 지도가 다시 복잡해진다. 둘 다 필수면 한쪽이 충돌할 때
  // 심볼 전체가 빠지고, 확대해 자리가 생기면 둘이 함께 돌아온다.
  // 공유 매장은 alwaysVisible이 충돌 판정을 끄므로 같은 값이 그대로 안전하다.
  textOptional: false,
  iconOptional: false,
  symbolSortKey: symbolSortKey,
);

/// 편의시설의 텍스트 전용 라벨. 아이콘은 [indoorFacilityIconProps]가 그린다.
///
/// [selection]은 매장명 라벨과 같은 규칙으로 쓴다 — 아이콘이 다른 레이어에 있을
/// 뿐 화면에서는 이름 달린 폴리곤 하나라, 여기만 예외로 두면 고른 카테고리
/// 이외의 시설 이름이 그대로 남는다. 호출하는 쪽이 모두 지금 선택을 넘겨야
/// 하는 이유도 [indoorStoresLabelProps]와 같다.
SymbolLayerProperties indoorFacilityLabelProps(
  List<Object> fadeExpr,
  CategorySelection? selection,
) => SymbolLayerProperties(
  textField: categoryLabelTextField(selection),
  textFont: const [mapFontStackRegular],
  textSize: mapLabelFixedTextSize,
  textColor: mapLabelFacilityColor,
  textHaloColor: mapLabelHaloColor,
  textHaloWidth: mapLabelHaloWidth,
  textMaxWidth: mapLabelFixedMaxWidth,
  textOpacity: fadeExpr,
  // 아이콘이 centroid를 차지하므로 이름은 아래로 내린다.
  textOffset: mapLabelBelowIconOffset,
  textAllowOverlap: false,
);

SymbolLayerProperties indoorPoiIconProps(
  List<Object> fadeExpr,
  double devicePixelRatio,
) => SymbolLayerProperties(
  iconImage: [
    'match',
    ['get', 'type'],
    for (final entry in kPoiIconByType.entries) ...[
      entry.key,
      poiIconImageName(entry.value),
    ],
    poiIconImageName(kDefaultPoiIcon),
  ],
  iconSize: indoorMarkerIconSize(devicePixelRatio),
  iconOpacity: fadeExpr,
  iconAllowOverlap: true,
);

SymbolLayerProperties indoorFacilityIconProps(
  List<Object> fadeExpr,
  double devicePixelRatio,
) => SymbolLayerProperties(
  iconImage: [
    'match',
    ['get', 'name'],
    for (final entry in kStoreFacilityStyleByName.entries) ...[
      entry.key,
      facilityIconImageName(entry.key),
    ],
    poiIconImageName(kDefaultPoiIcon),
  ],
  iconSize: indoorMarkerIconSize(devicePixelRatio),
  iconOpacity: fadeExpr,
  iconAllowOverlap: true,
  // iconOffset 없음 = 폴리곤 중심(centroid)에 그린다. 매장 라벨은 칸을 나눠
  // 배치하지만([store_label_anchor.dart]) 편의시설 아이콘은 하나뿐이라 중심이
  // 곧 정답이다.
);

/// 실내 오버레이 소스·레이어의 **한 세대**분 실제 ID 묶음.
///
/// 같은 ID로 removeSource → addSource를 반복하면 native가 정리를 스케줄만 한 채
/// 리턴해 다음 addSource가 "source already exists"로 조용히 실패한다(그 층만
/// 아무것도 안 그려지는 증상). 세대 카운터로 ID를 유일하게 만들어 경쟁을 없앤다.
///
/// 필드 12개를 값 하나로 묶은 이유는 하나라도 빠뜨리면 그 레이어만 이전 세대 ID로
/// 남아 remove 대상에서 새기 때문이다.
class IndoorOverlayIds {
  const IndoorOverlayIds([this.generation = 0]);

  final int generation;

  /// 다음 세대. 반드시 이전 세대의 remove **이후**, 다음 세대의 add **전에**
  /// 갈아 끼운다.
  IndoorOverlayIds next() => IndoorOverlayIds(generation + 1);

  String _idFor(String base) => '$base-g$generation';

  String get source => _idFor('outdoor-indoor-tiles');
  String get footprint => _idFor('outdoor-indoor-footprint');
  String get storesFill => _idFor('outdoor-indoor-stores-fill');

  /// 걸을 수 없는 면 fill. **[storesFill] 바로 위 한 자리뿐이다** — 아래로
  /// 내리면 주차칸·흰 바닥에 가려 픽셀이 사라지고(2026-08-15 되돌림 2번),
  /// [categoryHighlightFill] 위로 올리면 강조·수직이동 색이 회색에 덮인다.
  /// 매장을 덮을 걱정은 임포터의 중심점 규칙이 받는다.
  String get nonWalkableFill => _idFor('outdoor-indoor-non-walkable-fill');

  /// 카테고리 필터로 고른 매장만 파란톤으로 덧칠하는 fill. 일반 매장 fill 위,
  /// 수직이동 오버레이 아래에 넣어 실내 화면과 레이어 순서를 맞춘다 — 순서가
  /// 어긋나면 같은 선택인데 두 화면에서 강조가 다른 것에 가려진다.
  String get categoryHighlightFill =>
      _idFor('outdoor-indoor-category-highlight-fill');

  /// 수직이동(에스컬레이터/엘리베이터) 구조물 폴리곤을 초록톤으로 덧칠하는 fill.
  /// [storesFill] 위, 라벨/아이콘보다 아래에 삽입해 초록 배경 + 라벨/아이콘이 한
  /// 덩어리로 읽히게 한다.
  String get verticalTransportFill =>
      _idFor('outdoor-indoor-vertical-transport-fill');

  String get storesLabel => _idFor('outdoor-indoor-stores-label');

  /// 한 폴리곤을 여러 매장이 나눠 쓰는 자리의 라벨 전용 레이어. 타일 라벨의
  /// `shared` 속성으로 갈라내고, 충돌 판정을 꺼서 이름이 지워지지 않게 한다
  /// ([indoorStoresLabelProps]의 alwaysVisible).
  String get sharedStoresLabel => _idFor('outdoor-indoor-stores-label-shared');

  /// 편의시설(화장실·정수기 등)의 텍스트 전용 라벨. 매장명 라벨에는 대분류
  /// 아이콘이 붙는데, 시설은 이미 전용 아이콘 레이어가 있어 두 아이콘이 겹친다.
  /// 그래서 이름만 따로 그린다.
  String get facilityLabel => _idFor('outdoor-indoor-store-facility-label');

  /// POI(엘리베이터·에스컬레이터·화장실 등 `pois` 소스 레이어) 위 아이콘 심볼.
  String get poiIcon => _idFor('outdoor-indoor-pois-icon');

  /// `stores` 소스 레이어에 이름으로 매칭되는 편의시설 위 아이콘 심볼.
  String get storeFacilityIcon => _idFor('outdoor-indoor-store-facility-icons');

  /// 현재 세대의 레이어 ID 목록(위→아래 순). removeLayer 순서로 그대로 쓸 수
  /// 있다 — 레이어는 반드시 소스보다 먼저 제거해야 한다.
  List<String> get layersTopFirst => [
    storeFacilityIcon,
    poiIcon,
    facilityLabel,
    sharedStoresLabel,
    storesLabel,
    verticalTransportFill,
    categoryHighlightFill,
    nonWalkableFill,
    storesFill,
    footprint,
  ];
}

/// 세대 접미사가 붙은 실내 오버레이 id인지 가려낸다. `outdoor-indoor-destination`
/// 처럼 세대가 없는 이웃 id를 쓸어 담지 않으려고 끝의 `-g<숫자>`까지 요구한다.
final _indoorOverlayIdPattern = RegExp(r'^outdoor-indoor-.+-g(\d+)$');

/// 지도에 **실제로 붙어 있는** 레이어·소스를 훑어 [keepGeneration]이 아닌 실내
/// 오버레이를 전부 지운다.
///
/// 층 전환은 이전 층 블록을 바로 지우지 않고 은퇴 목록에 넘긴 뒤, 크로스페이드
/// 마무리가 지우기로 **위임**한다. 그 마무리가 예약되지 않거나(등록 실패·비
/// 크로스페이드 전환) 중간에 물러나면 블록이 그대로 남고, 남은 블록은 새 층
/// 도면보다 아래에 깔려 **새 층이 덮지 못하는 바깥쪽만 밝게 보인다.** 지하는
/// 지상보다 외곽선이 최대 30 m 넓어서 그 차이가 띠로 남는다.
///
/// 그래서 장부를 믿지 않고 지도에 직접 묻는다. 우리가 놓친 블록도 여기서 잡힌다.
Future<void> purgeStaleIndoorOverlay(
  MapLibreMapController controller, {
  required int keepGeneration,
}) async {
  bool stale(String id) {
    final match = _indoorOverlayIdPattern.firstMatch(id);
    return match != null && match.group(1) != '$keepGeneration';
  }

  // 레이어를 먼저 지운다 — 소스에 레이어가 붙어 있으면 removeSource가 실패한다.
  try {
    for (final raw in await controller.getLayerIds()) {
      final id = raw?.toString() ?? '';
      if (!stale(id)) continue;
      try {
        await controller.removeLayer(id);
      } catch (_) {}
    }
  } catch (_) {
    return;
  }
  try {
    for (final id in await controller.getSourceIds()) {
      if (!stale(id)) continue;
      try {
        await controller.removeSource(id);
      } catch (_) {}
    }
  } catch (_) {}
}

/// 실내 오버레이 소스와 레이어 10장을 한 번에 등록한다. 성공하면 true.
///
/// 등록 **순서가 곧 쌓임 순서**다(footprint → 매장 fill → 못 걷는 면 → 강조 →
/// 수직이동 → 라벨 → 아이콘, 전부 route casing 아래). 바꾸면 경로선·마커가 fill
/// 밑으로 깔린다.
///
/// [ensureIconImages]를 콜백으로 받는 이유는 "스타일당 한 번" 게이팅을 호출자가
/// 들고 있어서다. 실패하면 **부분 등록된 것을 스스로 정리한다** — 안 그러면 다음
/// 호출이 "source already exists"로 폭발한다.
Future<bool> registerIndoorOverlayLayers(
  MapLibreMapController controller, {
  required IndoorOverlayIds ids,
  required String tileUrl,
  required List<Object> fadeExpr,
  required List<Object> categoryFilter,
  required CategorySelection? categorySelection,
  required double devicePixelRatio,
  Object? symbolSortKey,
  required Future<void> Function(MapLibreMapController) ensureIconImages,
}) async {
  try {
    await controller.addSource(
      ids.source,
      VectorSourceProperties(
        tiles: [tileUrl],
        // minzoom 미만에서는 타일 요청·캐시 자체를 막아, 저-zoom 부모 타일이
        // over-scale된 채 잠깐 보이면서 도면이 회전한 것처럼 보이는 문제를
        // 예방한다. 근거는 indoorTilesMinZoom 정의 위 주석 참고.
        minzoom: indoorTilesMinZoom,
        // z=18 상한. 더 높이면 tile 경계가 좁아져(z=21은 20m 남짓) 4096 유닛
        // quantize 오차가 커지고, 극한 확대에서 도면이 뒤틀려 보인다. 18이면
        // 경계 ~150m라 0.04m/유닛으로 어떤 배율에서도 sub-pixel이다.
        maxzoom: indoorTilesMaxZoom,
      ),
    );
    // POI/시설 아이콘 비트맵을 스타일당 한 번만 addImage로 등록한다. 층을
    // 바꿔도 이미지는 그대로 재사용되므로 반복 렌더를 피한다.
    await ensureIconImages(controller);
    // route casing 바로 아래에 삽입한다 — 안 그러면 먼저 그린 경로선·마커가
    // stores fill 밑으로 깔려 사라진다.
    // **전 레이어 인터랙션을 끈다** — 탭 검출은 [_handleMapClick]의
    // queryRenderedFeatures가 하고, 남겨 두면 크로스페이드 동안 은퇴 목록에 있는
    // 이전 층 폴리곤까지 탭 대상이 된다.
    await controller.addFillLayer(
      ids.source,
      ids.footprint,
      indoorFootprintProps(fadeExpr),
      sourceLayer: 'footprint',
      belowLayerId: kOutdoorRouteCasingLayerId,
      enableInteraction: false,
    );
    await controller.addFillLayer(
      ids.source,
      ids.storesFill,
      indoorStoresFillProps(fadeExpr),
      sourceLayer: 'stores',
      belowLayerId: kOutdoorRouteCasingLayerId,
      enableInteraction: false,
    );
    // 걸을 수 없는 면. **매장 fill 바로 위·카테고리 강조 바로 아래** — 지하
    // 주차 구획이 전부 매장이라 매장 아래에 깔면 기둥 면적의 40%가 주차칸에
    // 가린다(실측 근거는 docs/client/kakao-map-indoor-observation.md 3절).
    // 위로 올려도 매장은 안 사라진다 — 중심점을 품는 도형은 임포터가 이미
    // 뺐고, 남은 최대 겹침은 매장 하나의 28%다.
    await controller.addFillLayer(
      ids.source,
      ids.nonWalkableFill,
      indoorNonWalkableProps(fadeExpr),
      sourceLayer: 'non_walkable',
      belowLayerId: kOutdoorRouteCasingLayerId,
      // 탭 대상이 아니다 — 이름도 id도 없는 배경 도형이라 누를 것이 없다.
      // [store_tap.dart]의 레이어 목록에도 넣지 않는다.
      enableInteraction: false,
    );
    // 카테고리 강조. 일반 매장 fill 바로 위에 얹어 선택한 매장만 파랗게
    // 덮는다. 선택이 없을 때도 레이어는 남겨 두고 아무것도 맞지 않는 필터를
    // 걸어 둔다 — 이유는 kCategoryHighlightNoneFilter 주석.
    await controller.addFillLayer(
      ids.source,
      ids.categoryHighlightFill,
      indoorCategoryHighlightProps(fadeExpr),
      sourceLayer: 'stores',
      belowLayerId: kOutdoorRouteCasingLayerId,
      filter: categoryFilter,
      // 탭은 아래 일반 매장 fill이 받는다. 여기서도 받으면 같은 폴리곤에
      // 두 번 반응한다(실내 화면과 같은 이유).
      enableInteraction: false,
    );
    // 수직이동 구조물(에스컬레이터/엘리베이터) 전용 오버레이. 일반 매장 fill
    // 바로 위, 라벨/POI 아이콘보다 아래에 깔아서 초록 아이콘과 한 덩어리로
    // 읽히게 한다. 필터가 어긋나면(백엔드 name 변경 등) 이 레이어만 비고
    // 아래 일반 매장 스타일로 자연스럽게 폴백된다. 필터는 실내 화면과 같은
    // 형식(any + 개별 ==)을 유지한다.
    await controller.addFillLayer(
      ids.source,
      ids.verticalTransportFill,
      indoorVerticalTransportProps(fadeExpr),
      sourceLayer: 'stores',
      belowLayerId: kOutdoorRouteCasingLayerId,
      filter: [
        'any',
        for (final name in kVerticalTransportStoreNames)
          [
            '==',
            ['get', 'name'],
            name,
          ],
      ],
      enableInteraction: false,
    );
    await controller.addSymbolLayer(
      ids.source,
      ids.storesLabel,
      indoorStoresLabelProps(
        fadeExpr,
        categorySelection,
        devicePixelRatio,
        symbolSortKey: symbolSortKey,
      ),
      // **폴리곤이 아니라 라벨 전용 점 레이어를 본다.** MapLibre는 폴리곤
      // 심볼을 면적 무게중심에 찍는데, ㄱ자·길쭉한 매장에서 그 점이 눈에
      // 보이는 가운데가 아니다(백엔드 `label_point.py` 주석에 실측을 적었다).
      // 백엔드가 폴리곤마다 "라벨 놓을 자리"를 계산해 이 레이어로 내려준다.
      sourceLayer: 'store_labels',
      // 한 폴리곤을 나눠 쓰는 자리(`shared`)는 아래 전용 레이어가 그린다.
      // 두 레이어가 같은 feature를 그리면 이름이 두 번 찍힌다.
      filter: [
        'all',
        storeLabelWithCategoryIconFilter(),
        [
          '!',
          ['has', 'shared'],
        ],
      ],
      belowLayerId: kOutdoorRouteCasingLayerId,
      enableInteraction: false,
    );
    // 한 폴리곤을 여러 매장이 나눠 쓰는 자리 전용. 백엔드가 라벨 점을 흩어
    // 놓았지만(`tiling._shared_label_points`) 간격이 글자 폭보다 좁을 수
    // 있어, 충돌 판정에 맡기면 결국 하나가 지워진다 — 오설록만 보이는데
    // 일상다완이 열리던 증상. 충돌 판정을 끄고 전부 그린다.
    await controller.addSymbolLayer(
      ids.source,
      ids.sharedStoresLabel,
      indoorStoresLabelProps(
        fadeExpr,
        categorySelection,
        devicePixelRatio,
        alwaysVisible: true,
        symbolSortKey: symbolSortKey,
      ),
      sourceLayer: 'store_labels',
      filter: [
        'all',
        storeLabelWithCategoryIconFilter(),
        ['has', 'shared'],
      ],
      belowLayerId: kOutdoorRouteCasingLayerId,
      enableInteraction: false,
    );
    // 편의시설은 이름만 — 아이콘은 아래 ids.storeFacilityIcon가
    // 그린다. 위 레이어에 섞으면 아이콘이 두 개 뜬다.
    await controller.addSymbolLayer(
      ids.source,
      ids.facilityLabel,
      indoorFacilityLabelProps(fadeExpr, categorySelection),
      // 매장명 라벨과 같은 이유로 라벨 점 레이어를 본다.
      sourceLayer: 'store_labels',
      filter: facilityStoreLabelFilter(),
      belowLayerId: kOutdoorRouteCasingLayerId,
      enableInteraction: false,
    );
    // POI(엘리베이터·에스컬레이터·화장실 등) 심볼 레이어. `pois` 소스 레이어에
    // 있는 feature의 type 속성으로 아이콘을 골라 얹는다. iconOpacity를 fadeExpr
    // 로 묶어 오버레이와 같은 줌 구간에서 함께 페이드인된다.
    await controller.addSymbolLayer(
      ids.source,
      ids.poiIcon,
      indoorPoiIconProps(fadeExpr, devicePixelRatio),
      sourceLayer: 'pois',
      belowLayerId: kOutdoorRouteCasingLayerId,
      enableInteraction: false,
    );
    // 편의시설 아이콘: 화장실·정수기 같은 시설물은 백엔드에서 `pois`가 아니라
    // 매장으로 들어오므로 POI 아이콘 레이어를 타지 않는다. 이름을 기준으로
    // 심볼을 하나 더 얹어 아이콘이 붙게 한다. 이름은 위 편의시설 라벨
    // 레이어가 같은 점에 아래로 그린다.
    await controller.addSymbolLayer(
      ids.source,
      ids.storeFacilityIcon,
      indoorFacilityIconProps(fadeExpr, devicePixelRatio),
      // 이름과 아이콘이 **같은 점**에 놓여야 한다. 하나만 라벨 점 레이어로
      // 옮기면 아이콘과 이름이 매장 안 서로 다른 자리에 뜬다.
      sourceLayer: 'store_labels',
      belowLayerId: kOutdoorRouteCasingLayerId,
      filter: [
        'any',
        for (final name in kStoreFacilityStyleByName.keys)
          [
            '==',
            ['get', 'name'],
            name,
          ],
      ],
      enableInteraction: false,
    );
    return true;
  } catch (error, stack) {
    debugPrint('[outdoor overlay] MVT register FAILED: $error\n$stack');
    // 부분 추가된 소스/레이어를 정리해 다음 호출이 깨끗한 상태에서 다시
    // 시도할 수 있게 한다. 각 remove가 실패해도(안 붙어있어서) 조용히 넘긴다.
    for (final id in ids.layersTopFirst) {
      try {
        await controller.removeLayer(id);
      } catch (_) {}
    }
    try {
      await controller.removeSource(ids.source);
    } catch (_) {}
    return false;
  }
}

/// [syncIndoorOverlayProps]가 어떤 레이어까지 다시 밀지.
enum IndoorOverlaySyncScope {
  /// 등록된 오버레이 레이어 전부.
  all,

  /// 매장명·공유 매장명·편의시설 라벨 세 장.
  labels,

  /// footprint·매장·못 걷는 면·카테고리 강조·수직이동 fill 다섯 장.
  fills,
}

/// 이미 등록된 오버레이 레이어의 속성을 지금 상태로 갈아 끼운다.
/// **각 레이어의 전체 속성을 매번 다시 넘긴다**(상단 주석).
///
/// [scope]로 범위를 좁힌다 — `labels`는 카테고리 선택만 바뀐 경우, `fills`는 층
/// 전환 크로스페이드 단계(매 프레임 라벨까지 밀면 native 왕복이 두 배다).
///
/// 이미 제거된 레이어에 대한 호출이 native에서 예외를 던져 각각 감싼다.
Future<void> syncIndoorOverlayProps(
  MapLibreMapController controller, {
  required IndoorOverlayIds ids,
  required List<Object> fadeExpr,
  required CategorySelection? categorySelection,
  required double devicePixelRatio,
  Object? symbolSortKey,
  String? highlightedStoreId,
  IndoorOverlaySyncScope scope = IndoorOverlaySyncScope.all,
}) async {
  // 선택을 반드시 함께 넘긴다. 빼면 줌을 움직일 때마다 가려 뒀던 매장 이름이
  // 되살아난다([indoorStoresLabelProps] 주석).
  final labels = <(String, LayerProperties)>[
    (
      ids.storesLabel,
      indoorStoresLabelProps(
        fadeExpr,
        categorySelection,
        devicePixelRatio,
        symbolSortKey: symbolSortKey,
        highlightedStoreId: highlightedStoreId,
      ),
    ),
    (
      ids.sharedStoresLabel,
      indoorStoresLabelProps(
        fadeExpr,
        categorySelection,
        devicePixelRatio,
        alwaysVisible: true,
        symbolSortKey: symbolSortKey,
        highlightedStoreId: highlightedStoreId,
      ),
    ),
    (ids.facilityLabel, indoorFacilityLabelProps(fadeExpr, categorySelection)),
  ];
  final fills = <(String, LayerProperties)>[
    (ids.footprint, indoorFootprintProps(fadeExpr)),
    (ids.storesFill, indoorStoresFillProps(fadeExpr)),
    // 빠뜨리면 층 전환 크로스페이드 동안 이 한 장만 계수를 못 따라가, 이전 층
    // 위에 못 걷는 면만 불투명하게 남는다.
    (ids.nonWalkableFill, indoorNonWalkableProps(fadeExpr)),
    (ids.categoryHighlightFill, indoorCategoryHighlightProps(fadeExpr)),
    (ids.verticalTransportFill, indoorVerticalTransportProps(fadeExpr)),
  ];
  final targets = switch (scope) {
    IndoorOverlaySyncScope.labels => labels,
    IndoorOverlaySyncScope.fills => fills,
    IndoorOverlaySyncScope.all => <(String, LayerProperties)>[
      ...fills,
      ...labels,
      (ids.poiIcon, indoorPoiIconProps(fadeExpr, devicePixelRatio)),
      (
        ids.storeFacilityIcon,
        indoorFacilityIconProps(fadeExpr, devicePixelRatio),
      ),
    ],
  };
  for (final (id, props) in targets) {
    try {
      await controller.setLayerProperties(id, props);
    } catch (_) {}
  }
}
