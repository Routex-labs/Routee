/// 경로선(자동차 실선·도보 점선·실내 실선·완료 회색선·환승선) 레이어의 등록.
///
/// 색·굵기 값과 그 근거는 map/style/route_style.dart가 단일 출처다(실내 화면과
/// 공유). 여기는 야외 지도에서 그 스타일로 **어떤 소스·레이어를 어떤 순서로
/// 쌓는지**만 소유한다. 소스에 데이터를 밀어 넣는 일(어떤 경로를 그릴지)은
/// 화면 상태가 한다 — 그쪽은 층·재탐색·승격 판단과 얽혀 있어 상태 옆에 있어야
/// 한다.
library;

import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../map/geojson.dart';
import '../../../map/style/route_style.dart';

/// 화면 sync 코드가 데이터를 밀어 넣는 소스 id들.
///
/// 계획 경로([kOutdoorRouteSourceId])와 지나온 구간([kOutdoorWalkedRouteSourceId])
/// 을 나누는 이유: 계획 경로가 재탐색으로 바뀌어도 이전 경로의 완료 이력이
/// 남아 있어야 한다.
const kOutdoorRouteSourceId = 'outdoor-route';
const kOutdoorWalkedRouteSourceId = 'outdoor-walked-route';
const kOutdoorTransferRouteSourceId = 'outdoor-transfer-route';

/// 고르지 않은 자동차 후보 경로. 계획 경로와 **소스를 나눈다** — 같은 소스에
/// 두고 속성으로 가르면 후보를 바꿀 때마다 본선의 색·굵기 표현식이 다시
/// 계산돼 선 전체가 한 번 깜빡인다(대중교통 후보와 같은 이유).
const kOutdoorRouteAltSourceId = 'outdoor-route-alt';

/// 경로 묶음의 **맨 아래** 레이어. 실내 MVT 오버레이가 `belowLayerId:`로 이
/// 레이어 아래에 삽입되므로, 이 id가 곧 "도면은 경로선 아래"라는 z-순서 계약이다.
const kOutdoorRouteCasingLayerId = 'outdoor-route-casing';

const _routeAltLayerId = 'outdoor-route-alt-line';
const _routeLineLayerId = 'outdoor-route-line';
const _routeWalkLayerId = 'outdoor-route-walk';
const _routeIndoorLayerId = 'outdoor-route-indoor';
// 진행 방향 화살표. 본선 위에 얹혀 선을 따라 흐른다.
const _routeArrowLayerId = 'outdoor-route-arrow';
const _walkedRouteLayerId = 'outdoor-walked-route-line';
const _transferRouteLayerId = 'outdoor-transfer-route-line';

/// 걷기/자동차/실내 경로선과 완료 회색선을 등록한다.
///
/// 대중교통 레이어(registerTransitLayers)는 이 함수 **다음**,
/// [registerTransferRouteLayer]는 그 다음에 불러야 한다 — 등록 순서가 곧
/// 쌓임 순서다.
Future<void> registerRouteLayers(MapLibreMapController controller) async {
  // 지나온 계획 구간은 계획 경로와 분리한다. 계획 경로가 재탐색으로 바뀌어도
  // 이전 경로의 완료 이력이 남아 있어야 하므로 전용 source를 둔다. 레이어는
  // 아래 source만 먼저 등록하고, 파란 경로 레이어가 등록된 뒤 위에 올린다.
  await controller.addSource(
    kOutdoorWalkedRouteSourceId,
    GeojsonSourceProperties(data: emptyGeoJsonCollection()),
  );

  // 경로선: 진한 파랑 casing + 파란 본선 + 흰 화살표. 값과 근거는
  // [map_route_style.dart]에 있다(실내 화면과 공유).
  await controller.addSource(
    kOutdoorRouteSourceId,
    GeojsonSourceProperties(data: emptyGeoJsonCollection()),
  );
  // 테두리는 **실선 구간에만** 깐다(자동차·실내). 점선 아래에 테두리를 깔면
  // 점 사이 빈틈이 테두리 색으로 채워져 점선이 실선처럼 보이기 때문인데, 그
  // 이유는 도보 점선에만 해당한다. 한때 자동차만 남겨 두는 바람에 실내 실선이
  // 테두리 없이 도면 위에 맨살로 떠 있었다 — 밝은 매장 바닥 위에서 경계가
  // 흐려 선이 얇고 초라해 보인다.
  await controller.addLineLayer(
    kOutdoorRouteSourceId,
    kOutdoorRouteCasingLayerId,
    const LineLayerProperties(
      lineColor: kRouteCasingColor,
      lineWidth: kRouteCasingWidthExpr,
      lineCap: 'round',
      lineJoin: 'round',
    ),
    filter: [
      'match',
      ['get', 'style'],
      ['drive', 'indoor'],
      true,
      false,
    ],
  );
  // 자동차 후보는 **casing 위, 본선 아래**다. casing보다 아래에 두면 실내
  // 도면(casing 아래로 삽입된다)이 후보를 덮고, 본선보다 위에 두면 겹치는
  // 구간에서 회색이 파란 선을 지운다.
  await controller.addSource(
    kOutdoorRouteAltSourceId,
    GeojsonSourceProperties(data: emptyGeoJsonCollection()),
  );
  await controller.addLineLayer(
    kOutdoorRouteAltSourceId,
    _routeAltLayerId,
    const LineLayerProperties(
      lineColor: kRouteCompletedColor,
      lineWidth: 3.5,
      lineOpacity: 0.75,
      lineCap: 'round',
      lineJoin: 'round',
    ),
    enableInteraction: false,
  );

  // 자동차만 실선이다. 운전 경로는 도로를 그대로 따라가므로 선이 곧 길이지만,
  // 걷는 구간은 횡단보도·건물 앞 광장처럼 "이 근처로 가라"에 가까워 점선이 맞다.
  await controller.addLineLayer(
    kOutdoorRouteSourceId,
    _routeLineLayerId,
    const LineLayerProperties(
      lineColor: kRouteLineColor,
      lineWidth: kRouteLineWidthExpr,
      lineCap: 'round',
      lineJoin: 'round',
    ),
    filter: [
      '==',
      ['get', 'style'],
      'drive',
    ],
  );
  await controller.addLineLayer(
    kOutdoorRouteSourceId,
    _routeWalkLayerId,
    const LineLayerProperties(
      lineColor: kRouteWalkColor,
      lineWidth: kRouteLineWidthExpr,
      lineDasharray: kRouteWalkDashArray,
      lineCap: 'round',
      lineJoin: 'round',
    ),
    filter: [
      '==',
      ['get', 'style'],
      'walk',
    ],
  );
  await controller.addLineLayer(
    kOutdoorRouteSourceId,
    // 실내 구간은 **실선**이다. 건물 안에서는 복도가 정해져 있어 "대략 이쪽"이
    // 아니라 실제로 그 길로 걷는다 — 점선으로 그리면 밖의 도보 구간과 같은
    // 성격으로 읽힌다. 색은 야외 본선과 같다([kRouteIndoorLineColor] 주석).
    _routeIndoorLayerId,
    const LineLayerProperties(
      lineColor: kRouteIndoorLineColor,
      lineWidth: kRouteLineWidthExpr,
      lineCap: 'round',
      lineJoin: 'round',
    ),
    filter: [
      '==',
      ['get', 'style'],
      'indoor',
    ],
  );
  await controller.addImage(
    kRouteArrowImageName,
    await renderRouteArrowIcon(),
  );
  await controller.addSymbolLayer(
    kOutdoorRouteSourceId,
    _routeArrowLayerId,
    routeArrowProps(),
    enableInteraction: false,
  );
  // 회색선은 이전 경로의 완료 이력을 보존해야 하므로 파란 잔여선보다 위에
  // 둔다. 현재 경로는 이미 완료/잔여로 분할되어 있어 두 선이 겹치지 않고,
  // 재탐색 전 이력이 새 파란 경로에 가려지지도 않는다.
  await controller.addLineLayer(
    kOutdoorWalkedRouteSourceId,
    _walkedRouteLayerId,
    const LineLayerProperties(
      lineColor: kRouteCompletedColor,
      lineWidth: kRouteLineWidthExpr,
      lineOpacity: 0.72,
      lineCap: 'round',
      lineJoin: 'round',
    ),
    enableInteraction: false,
  );
}

/// 층을 잇는 환승선(에스컬레이터·엘리베이터 구간). 대중교통 레이어까지 등록된
/// 뒤 불러, 겹칠 때 환승선이 맨 위에 온다.
Future<void> registerTransferRouteLayer(MapLibreMapController controller) async {
  await controller.addSource(
    kOutdoorTransferRouteSourceId,
    GeojsonSourceProperties(data: emptyGeoJsonCollection()),
  );
  await controller.addLineLayer(
    kOutdoorTransferRouteSourceId,
    _transferRouteLayerId,
    const LineLayerProperties(
      lineColor: kRouteLineColor,
      lineWidth: kRouteTransferWidthExpr,
      lineOpacity: 0.85,
      lineDasharray: [1.2, 1.1],
      lineCap: 'round',
      lineJoin: 'round',
    ),
    enableInteraction: false,
  );
}
