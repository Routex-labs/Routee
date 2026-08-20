/// 점 하나로 그려지는 레이어들 — 현재 위치(GPS), 야외 목적지, 실내 도착 핀.
///
/// 셋 다 모양이 같다: 상태에서 좌표 하나(또는 없음)를 뽑아 그 소스에 밀어 넣는다.
/// **무엇을 그릴지는 화면이 정한다.** 목적지가 문을 경유하는 중인지, 다층 경로의
/// 도착 층을 보고 있는지 같은 판단은 화면 상태와 얽혀 있어 여기로 오면 안 된다.
/// 이 파일은 "받은 좌표를 그 소스에 쓴다"만 한다.
///
/// 소스를 셋으로 나눈 이유는 [kOutdoorIndoorDestSourceId]에 적어 뒀다.
library;

import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../map/geojson.dart';
import '../../../theme/app_theme.dart';
import '../../../map/icon/destination_pin.dart';
import '../../../map/icon/location_marker_icon.dart';
import 'indoor_overlay_layers.dart' show MapColorHex;

/// 현재 위치: 반투명 원(정확도 반경 시각화용, 픽셀 반경) + 진한 점.
const kOutdoorCurrentSourceId = 'outdoor-current';
const _accuracyLayerId = 'outdoor-accuracy';
const _currentDotLayerId = 'outdoor-current-dot';

/// 사용자가 고른 야외 목적지.
const kOutdoorDestSourceId = 'outdoor-destination';
const _destLayerId = 'outdoor-destination-pin';

/// 실내 경로의 도착 노드에 찍는 물방울 핀. 야외 GPS 목적지 원([_destLayerId])과
/// **소스를 나눈다** — 같은 소스에 넣으면 원 레이어 필터가 없어 실내 도착
/// 노드에도 빨간 원이 함께 그려져 핀 밑에 원이 비어져 나온다.
const kOutdoorIndoorDestSourceId = 'outdoor-indoor-destination';

/// 실내 도착 핀 레이어. hot reload로 다시 얹을 때 지울 대상이라 밖에서 쓴다
/// ([addIndoorDestinationPinLayer]).
const kOutdoorIndoorDestLayerId = 'outdoor-indoor-destination-pin';

/// 도착 핀 비트맵의 addImage 등록 키. 실내 지도와 같은 도형을
/// ([destination_pin.dart]) 공유하지만 등록 키는 화면마다 따로 둔다. 웹 addImage는
/// 같은 이름이 이미 있으면 새 비트맵을 버리므로 디자인을 바꿀 땐 이름의 버전도
/// 같이 올려야 살아 있는 지도에 반영된다.
/// v3: "도착" 글씨를 비트맵에 구워 넣었다(심볼 텍스트에서 이동).
const _destinationPinImageName = 'outdoor-destination-pin-v3';

/// 도착 핀 iconSize의 zoom 보간 구간(z16 → z20). 원본 비트맵이 128x172px이라
/// 화면 높이는 172 x iconSize다.
///
/// 기준은 현재 위치 마커다 — 그쪽은 zoom과 무관하게 42px 고정 도트인데
/// (kLocationMarkerIconRimRadius 21의 지름), 이전 값(0.115/0.25)에서는 실내
/// 오버레이를 실제로 보는 zoom 18에서 핀이 31px밖에 안 돼 "저기가 목적지"를
/// 가리키는 랜드마크가 사용자 위치 도트보다 작았다. 지금 값은 z18 ≈ 64px,
/// z20 ≈ 86px로 도트보다 확실히 크다. 위쪽(z20) 상한은 확대했을 때 핀이 도착
/// 매장 폴리곤을 통째로 덮지 않는 선에서 잡았다.
const kDestinationPinIconSizeZ16 = 0.24;
const kDestinationPinIconSizeZ20 = 0.50;

/// 현재 위치 소스·레이어를 등록한다.
Future<void> registerCurrentLocationLayers(
  MapLibreMapController controller,
) async {
  await controller.addSource(
    kOutdoorCurrentSourceId,
    GeojsonSourceProperties(data: emptyGeoJsonCollection()),
  );
  await controller.addCircleLayer(
    kOutdoorCurrentSourceId,
    _accuracyLayerId,
    CircleLayerProperties(
      circleRadius: 22,
      circleColor: AppColors.primary.toHexString(),
      circleOpacity: 0.18,
      circleStrokeColor: AppColors.primary.toHexString(),
      circleStrokeWidth: 1,
    ),
  );
  await controller.addCircleLayer(
    kOutdoorCurrentSourceId,
    _currentDotLayerId,
    CircleLayerProperties(
      circleRadius: 7,
      circleColor: AppColors.primary.toHexString(),
      circleStrokeColor: '#FFFFFF',
      circleStrokeWidth: 2,
    ),
  );
}

/// 야외 목적지 핀(빨간 원) 소스·레이어를 등록한다.
Future<void> registerDestinationLayer(MapLibreMapController controller) async {
  await controller.addSource(
    kOutdoorDestSourceId,
    GeojsonSourceProperties(data: emptyGeoJsonCollection()),
  );
  await controller.addCircleLayer(
    kOutdoorDestSourceId,
    _destLayerId,
    CircleLayerProperties(
      circleRadius: 9,
      circleColor: AppColors.dest.toHexString(),
      circleStrokeColor: '#FFFFFF',
      circleStrokeWidth: 2,
    ),
  );
}

/// 실내 도착 핀의 비트맵·소스·레이어를 등록한다.
///
/// **현재 위치 마커보다 나중에** 불러야 도착 노드와 사용자 위치가 겹칠 때 도착
/// 핀이 위에 온다(실내 지도와 같은 순서).
Future<void> registerIndoorDestinationLayers(
  MapLibreMapController controller,
) async {
  await controller.addImage(
    _destinationPinImageName,
    await renderDestinationPinIcon(),
  );
  await controller.addSource(
    kOutdoorIndoorDestSourceId,
    GeojsonSourceProperties(data: emptyGeoJsonCollection()),
  );
  await addIndoorDestinationPinLayer(controller);
}

/// 실내 경로 도착 핀 레이어를 얹는다. 실내 화면과 **같은 함수**로 속성을
/// 만든다 — 두 화면이 각자 정의를 베껴 들고 있던 탓에 둘 다 `text-font`를
/// 빠뜨렸던 이력이 있다([destination_pin.dart] 주석).
///
/// 등록과 hot reload 재적용이 같은 함수를 쓴다. 핀 바닥(tip)이 도착 노드
/// 좌표에 오도록 iconAnchor는 bottom이고, 크기는 zoom 보간식으로 걸어 축소했을
/// 때 핀이 도면을 다 덮지 않게 한다. allowOverlap을 켜 매장 라벨과 겹쳐도 핀은
/// 항상 보인다.
Future<void> addIndoorDestinationPinLayer(
  MapLibreMapController controller,
) async {
  await controller.addSymbolLayer(
    kOutdoorIndoorDestSourceId,
    kOutdoorIndoorDestLayerId,
    destinationPinSymbolProps(
      imageName: _destinationPinImageName,
      iconSizeZ16: kDestinationPinIconSizeZ16,
      iconSizeZ20: kDestinationPinIconSizeZ20,
    ),
    enableInteraction: false,
  );
}

/// 실내 진입 상태에서 사용자의 PDR 위치(앵커 또는 실시간 확정 위치)를 그리는
/// 전용 소스. 야외 GPS 마커와 함께 그려질 수 있지만 색과 위치가 달라 겹쳐도
/// 서로 구분된다 — GPS는 건물 밖 신호, PDR은 건물 내 실측이라 두 표시가 동시에
/// 보이는 순간이 자연스러운 전환기다.
const kOutdoorPdrCurrentSourceId = 'outdoor-pdr-current';
const _pdrCurrentLayerId = 'outdoor-pdr-current-dot';

/// PDR 위치 심볼 아이콘 이름(addImage 등록 키). heading이 있으면 방향 원뿔이
/// 함께 그려진 이미지, 없으면 원형 도트만 있는 이미지로 자동 교체된다. 그림과
/// 크기 상수는 실내 지도와 공유한다([location_marker_icon.dart]) — 같은 지점을
/// 봤을 때 두 화면의 마커가 달라 보이면 안 된다.
///
/// 이름 끝에 코어 반지름을 박아 둔다 — 웹 addImage는 같은 이름이 이미 있으면
/// 새 비트맵을 버리고 건너뛰고, removeImage도 없어서 디자인을 바꿔도 살아 있는
/// 지도에는 예전 크기가 남는다.
const _pdrLocationImageName =
    'outdoor-pdr-location-r$kLocationMarkerIconCoreRadius';
const _pdrLocationDotImageName =
    'outdoor-pdr-location-dot-r$kLocationMarkerIconCoreRadius';

/// PDR 위치 마커를 등록한다 — 실내 지도와 같은 파란 도트 + heading 원뿔.
///
/// heading 유무에 따라 다른 아이콘을 자동 선택하고, heading이 있을 때만
/// iconRotate로 지도 위에서 실제 방향을 가리키게 한다. `iconRotationAlignment:
/// 'map'`을 넣어야 사용자가 지도를 돌려도 원뿔이 실좌표 방향을 유지한다.
///
/// **PDR 진단 레이어보다 나중에** 불러야 마커가 항상 진단 선 위에 온다. 진단
/// 선이 현재 위치를 덮으면 정작 어디에 서 있는지가 안 보인다.
Future<void> registerPdrLocationLayer(MapLibreMapController controller) async {
  await controller.addSource(
    kOutdoorPdrCurrentSourceId,
    GeojsonSourceProperties(data: emptyGeoJsonCollection()),
  );
  await controller.addSymbolLayer(
    kOutdoorPdrCurrentSourceId,
    _pdrCurrentLayerId,
    SymbolLayerProperties(
      iconImage: [
        'case',
        ['has', 'heading'],
        _pdrLocationImageName,
        _pdrLocationDotImageName,
      ],
      // 야외 GPS 마커(CircleLayer 상수 반지름)가 zoom과 무관하게 고정이므로
      // 이쪽도 고정으로 둔다 — 디자인 1px = 화면 1px.
      iconSize: kLocationMarkerIconSize,
      iconRotate: [
        'coalesce',
        ['get', 'heading'],
        0,
      ],
      iconRotationAlignment: 'map',
      iconPitchAlignment: 'viewport',
      iconAllowOverlap: true,
      iconIgnorePlacement: true,
    ),
    enableInteraction: false,
  );
}

/// PDR 마커 비트맵 두 벌을 등록한다. 소스·레이어보다 **먼저** 불러야 한다.
Future<void> registerPdrLocationImages(MapLibreMapController controller) async {
  await controller.addImage(
    _pdrLocationImageName,
    await renderLocationMarkerIcon(showHeading: true),
  );
  await controller.addImage(
    _pdrLocationDotImageName,
    await renderLocationMarkerIcon(showHeading: false),
  );
}

/// PDR 마커 소스에 넣을 데이터. [point]가 null이면 빈 컬렉션이라 마커가 사라진다.
///
/// 쓰기 자체는 화면이 한다 — 센서 갱신마다 들어오는 호출을 큐로 직렬화하고 더
/// 최신 스냅샷이 오면 버리는 판단이 화면 상태(revision)에 있기 때문이다.
Map<String, dynamic> pdrLocationData(ll.LatLng? point, {double? headingDeg}) {
  if (point == null) return emptyGeoJsonCollection();
  return geoJsonCollection([
    {
      'type': 'Feature',
      'properties': <String, dynamic>{'heading': ?headingDeg},
      'geometry': {
        'type': 'Point',
        'coordinates': [point.longitude, point.latitude],
      },
    },
  ]);
}

/// 점 하나짜리 소스를 갱신한다. [point]가 null이면 비운다 — 레이어를 지웠다
/// 다시 만들지 않고 데이터만 비우는 편이 층 전환·스타일 재로드와 경쟁하지 않아
/// 안전하다([emptyGeoJsonCollection] 주석).
Future<void> syncPointSource(
  MapLibreMapController controller,
  String sourceId,
  ll.LatLng? point,
) async {
  await controller.setGeoJsonSource(
    sourceId,
    point == null
        ? emptyGeoJsonCollection()
        : geoJsonCollection([pointFeature(point)]),
  );
}

Map<String, dynamic> pointFeature(ll.LatLng point) {
  return {
    'type': 'Feature',
    'properties': const <String, dynamic>{},
    'geometry': {
      'type': 'Point',
      'coordinates': [point.longitude, point.latitude],
    },
  };
}
