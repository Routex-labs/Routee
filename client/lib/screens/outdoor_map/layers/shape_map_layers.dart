/// 건물 fill·dim scrim·층 외곽선(링)과 출구 핀(점)의 소스·레이어.
///
/// 전부 "링 또는 점 몇 개를 소스에 쓴다"가 전부이고, **무엇을 쓸지는 화면이
/// 정한다.**
///
/// 레이어 속성은 [indoor_overlay_layers.dart]가 소유한다(전체 교체 규칙이 거기 있다).
/// 출구 핀의 도형은 [place_pin.dart]가 굽는다.
library;

import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../map/geojson.dart';
import '../../../map/style/palette.dart';
import '../entry/indoor_entry_zoom.dart';
import 'indoor_overlay_layers.dart';

/// 건물 폴리곤. 탭 피드백으로 fill opacity가 오르내리므로 레이어 id를 밖에
/// 연다([buildingFillProps]와 함께 쓴다).
const kOutdoorBuildingSourceId = 'outdoor-building';
const kOutdoorBuildingFillLayerId = 'outdoor-building-fill';

/// 실내 진입 dim scrim. 진입/이탈에 따라 opacity 표현식을 갈아 끼우므로 레이어
/// id를 밖에 연다.
const kOutdoorDimScrimSourceId = 'outdoor-dim-scrim';
const kOutdoorDimScrimFillLayerId = 'outdoor-dim-scrim-fill';

/// 현재 층 외곽선.
const kOutdoorFloorOutlineSourceId = 'outdoor-floor-outline';
const kOutdoorFloorOutlineLayerId = 'outdoor-floor-outline-line';

/// 실내 오버레이에서 고른 매장 하나만 칠하고 테두리를 두르는 전용 소스·레이어.
/// 색은 [mapSelectionFill]·[mapSelectionLine] 하나씩만 쓴다.
const kOutdoorHighlightSourceId = 'outdoor-highlight';
const _highlightFillLayerId = 'outdoor-highlight-fill';
const _highlightLineLayerId = 'outdoor-highlight-line';

/// 출구 핀 소스·레이어. 매장 핀과 **소스를 나눈다** — 같은 소스에 넣으면
/// 아이콘을 고르는 표현식이 필요해지는데, 출구 핀은 방위마다 비트맵이 달라
/// 표현식이 8갈래로 늘어난다. 소스를 나누면 각자 자기 아이콘만 안다.
const kOutdoorGateSourceId = 'outdoor-gate';
const _gatePinLayerId = 'outdoor-gate-pin';

/// 출구 핀 비트맵 등록 키의 접두사. 뒤에 방위 글자가 붙는다.
const kGatePinImagePrefix = 'outdoor-gate-pin-v1-';

/// 출구 핀은 **한 층에 다섯이라** 작게 둔다. 크게 두면 1F 도면이
/// 핀 다섯 개로 덮인다.
const _gatePinIconSizeZ16 = 0.12;
const _gatePinIconSizeZ20 = 0.26;

/// 건물 fill과 dim scrim을 등록한다.
///
/// **가장 먼저 불러야 한다.** 건물 fill은 다른 레이어(경로선·위치 점)가 위에
/// 오도록 맨 아래고, scrim은 그 바로 위여서 이후 등록되는 route/실내 MVT
/// 오버레이보다 아래에 온다 — 실내 도면은 스크림 위에 그려져 밝게 남고 야외
/// base만 어두워진다.
///
/// 외곽선은 여기 붙이지 않는다 — 실내 진입 상태에서만, 층에 따라 다른 링을
/// 그리므로 전용 소스로 뺐다([registerFloorOutlineLayer]).
Future<void> registerBuildingAndScrimLayers(
  MapLibreMapController controller, {
  required double buildingFillOpacity,
}) async {
  await controller.addSource(
    kOutdoorBuildingSourceId,
    GeojsonSourceProperties(data: emptyGeoJsonCollection()),
  );
  await controller.addFillLayer(
    kOutdoorBuildingSourceId,
    kOutdoorBuildingFillLayerId,
    buildingFillProps(buildingFillOpacity),
  );

  // 초기 opacity=0. geometry는 footprint가 로드된 뒤 세계 outer + 건물 hole
  // 폴리곤으로 채워진다([syncDimScrimSource]).
  await controller.addSource(
    kOutdoorDimScrimSourceId,
    GeojsonSourceProperties(data: emptyGeoJsonCollection()),
  );
  await controller.addFillLayer(
    kOutdoorDimScrimSourceId,
    kOutdoorDimScrimFillLayerId,
    dimScrimProps(0),
    enableInteraction: false,
  );
}

/// 현재 층 외곽선을 등록한다.
///
/// **경로선 다음에** 불러야 한다 — 실내 MVT 오버레이는 나중에
/// `belowLayerId: kOutdoorRouteCasingLayerId`로 삽입되므로, 경로선 앞(=건물
/// fill·dim scrim 옆)에 두면 불투명한 흰색 footprint fill 밑으로 깔려 선이
/// 반쯤 먹힌다. 도면 위에 얹혀야 경계가 그대로 보인다.
///
/// 페이드 표현식은 **진입 상태 램프로 고정**한다. 이 레이어는 진입했을 때만
/// 지오메트리를 갖고(그 외에는 빈 소스), 진입 상태에서만 보이므로 진입 전
/// 램프가 쓰일 일이 없다. 덕분에 상태가 바뀔 때 setLayerProperties를 다시
/// 부를 필요가 없다(전체 교체 규칙에 걸릴 여지도 사라진다).
Future<void> registerFloorOutlineLayer(MapLibreMapController controller) async {
  await controller.addSource(
    kOutdoorFloorOutlineSourceId,
    GeojsonSourceProperties(data: emptyGeoJsonCollection()),
  );
  await controller.addLineLayer(
    kOutdoorFloorOutlineSourceId,
    kOutdoorFloorOutlineLayerId,
    floorOutlineProps(indoorOverlayFadeExpr(entered: true, maxOpacity: 0.9)),
    enableInteraction: false,
  );
}

/// 출구 핀 소스·레이어를 등록한다. 비트맵은 방위를 알아야 구울 수 있으므로
/// 여기서 굽지 않는다 — 층 도면이 로드된 뒤 화면이 [kGatePinImagePrefix]로
/// 등록한다.
///
Future<void> registerGateLayers(MapLibreMapController controller) async {
  await controller.addSource(
    kOutdoorGateSourceId,
    GeojsonSourceProperties(data: emptyGeoJsonCollection()),
  );
  await controller.addSymbolLayer(
    kOutdoorGateSourceId,
    _gatePinLayerId,
    // 아이콘 이름을 feature 속성에서 읽는다. 방위마다 비트맵이 다르다.
    _placePinProps(
      ['get', 'icon'],
      sizeZ16: _gatePinIconSizeZ16,
      sizeZ20: _gatePinIconSizeZ20,
    ),
    enableInteraction: false,
  );
}

/// 고른 매장 하나만 칠하는 소스·레이어를 등록한다.
///
/// **PDR 마커보다 아래·경로선보다 위다.** 실내 오버레이의 매장 fill은 나중에
/// `belowLayerId`로 이 아래에 삽입되므로, 칠이 도면 위에 확실히 덮인다.
///
/// 라벨 아이콘의 선택 색과 **둘 다 쓴다.** 아이콘은 "이거 하나"를, 이 면은
/// "여기까지"를 말한다 — 색을 나눈 이유는 [mapSelectionFill].
Future<void> registerHighlightLayers(MapLibreMapController controller) async {
  await controller.addSource(
    kOutdoorHighlightSourceId,
    GeojsonSourceProperties(data: emptyGeoJsonCollection()),
  );
  await controller.addFillLayer(
    kOutdoorHighlightSourceId,
    _highlightFillLayerId,
    const FillLayerProperties(
      fillColor: mapSelectionFill,
      fillOpacity: mapSelectionFillOpacity,
    ),
    enableInteraction: false,
  );
  await controller.addLineLayer(
    kOutdoorHighlightSourceId,
    _highlightLineLayerId,
    const LineLayerProperties(
      lineColor: mapSelectionLine,
      // 면을 옅게 둔 만큼 경계는 이 선이 만든다. 1.2px는 옅은 칠 위에서
      // 있는지 없는지 알 수 없던 굵기다.
      lineWidth: 2,
      lineJoin: 'round',
    ),
    enableInteraction: false,
  );
}

/// 두 핀이 공유하는 심볼 속성. **한 곳에 두는 이유는 [destination_pin.dart]와
/// 같다** — 두 레이어가 각자 정의를 들고 있으면 조용히 어긋난다. 다른 것은
/// 아이콘과 크기뿐이다.
SymbolLayerProperties _placePinProps(
  Object iconImage, {
  required double sizeZ16,
  required double sizeZ20,
}) => SymbolLayerProperties(
  iconImage: iconImage,
  iconSize: [
    'interpolate',
    ['linear'],
    ['zoom'],
    16,
    sizeZ16,
    20,
    sizeZ20,
  ],
  // 핀 바닥(tip)이 실제 좌표에 오도록.
  iconAnchor: 'bottom',
  // 매장 라벨과 충돌한다고 숨으면 정작 고른 것이 화면에서 사라진다.
  iconAllowOverlap: true,
  iconIgnorePlacement: true,
);

/// 점 여러 개를 **속성과 함께** 넣는다. 빈 목록이면 소스를 비운다.
///
/// 점 하나짜리는 `marker_map_layers.dart`의 `syncPointSource`가 이미 있다.
/// 여기가 따로 있는 이유는 **속성**이다 — 출구 핀은 방위마다 비트맵이 달라
/// feature가 자기 아이콘 이름을 들고 있어야 한다.
Future<void> syncPointsSource(
  MapLibreMapController controller,
  String sourceId,
  List<(ll.LatLng, Map<String, dynamic>)> points,
) async {
  await controller.setGeoJsonSource(
    sourceId,
    points.isEmpty
        ? emptyGeoJsonCollection()
        : geoJsonCollection([
            for (final (point, props) in points)
              {
                'type': 'Feature',
                'properties': props,
                'geometry': {
                  'type': 'Point',
                  // GeoJSON 좌표 순서는 [longitude, latitude]다.
                  'coordinates': [point.longitude, point.latitude],
                },
              },
          ]),
  );
}

/// 링 하나짜리 폴리곤 소스를 갱신한다. [ring]이 null이거나 점이 3개 미만이면
/// 비운다(폴리곤이 성립하지 않는다).
Future<void> syncPolygonSource(
  MapLibreMapController controller,
  String sourceId,
  List<ll.LatLng>? ring,
) async {
  if (ring == null || ring.length < 3) {
    await controller.setGeoJsonSource(sourceId, emptyGeoJsonCollection());
    return;
  }
  await controller.setGeoJsonSource(
    sourceId,
    geoJsonCollection([
      _polygonFeature([closedRing(ring)]),
    ]),
  );
}

/// 세계를 덮고 [hole] 만큼을 뚫은 스크림 폴리곤을 쓴다. [hole]이 없으면 비운다.
Future<void> syncDimScrimSource(
  MapLibreMapController controller,
  List<ll.LatLng>? hole,
) async {
  if (hole == null || hole.length < 3) {
    await controller.setGeoJsonSource(
      kOutdoorDimScrimSourceId,
      emptyGeoJsonCollection(),
    );
    return;
  }
  // 세계 전체를 덮는 outer ring(웹 메르카토르 상하한). 어떤 위치·줌에서도
  // 화면 밖까지 확실히 덮어 가장자리가 새어나오지 않는다.
  const worldRing = [
    [-180.0, -85.05112878],
    [180.0, -85.05112878],
    [180.0, 85.05112878],
    [-180.0, 85.05112878],
    [-180.0, -85.05112878],
  ];
  // GeoJSON 폴리곤 hole은 outer와 반대 방향(CW)이 표준. 백엔드 순회 방향에
  // 상관없이 안전하게 hole로 처리되도록 reversed로 뒤집는다.
  await controller.setGeoJsonSource(
    kOutdoorDimScrimSourceId,
    geoJsonCollection([
      _polygonFeature([worldRing, closedRing(hole.reversed.toList())]),
    ]),
  );
}

Map<String, dynamic> _polygonFeature(List<List<List<double>>> rings) => {
  'type': 'Feature',
  'properties': const <String, dynamic>{},
  'geometry': {'type': 'Polygon', 'coordinates': rings},
};

/// GeoJSON Polygon linear ring은 첫 점과 마지막 점이 같아야 한다. 백엔드가
/// 이미 닫아 보내주면 중복 추가하지 않는다.
List<List<double>> closedRing(List<ll.LatLng> points) {
  final ring = <List<double>>[
    for (final p in points) [p.longitude, p.latitude],
  ];
  if (ring.length > 1) {
    final first = ring.first;
    final last = ring.last;
    if (first[0] != last[0] || first[1] != last[1]) ring.add(first);
  }
  return ring;
}
