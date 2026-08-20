/// 걷는 안내 중 **언제 카메라를 마커 쪽으로 다시 부를지** 정하는 정책.
///
/// 화면 좌표로 판단한다 — 같은 위경도 차이가 배율에 따라 0.1px일 수도 수백
/// px일 수도 있고, 사용자가 느끼는 것은 좌표 오차가 아니라 화면의 이동이다.
///
/// 근거는 `docs/client/camera-choreography-plan.md` 4.3.
library;

import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:latlong2/latlong.dart' as ll;

import '../../../map/camera/zoom_math.dart';

/// 화면 **절반**의 이 비율만큼 벗어나면 다시 가운데로 부른다.
///
/// 0.35는 화면 폭의 약 17.5%다. 마커는 여전히 가운데 언저리에 있고, 걸음마다
/// 오던 미세한 끌림은 사라진다. 키우면 조용해지지만 마커가 구석으로 밀리고,
/// 줄이면 PDR이 한 걸음마다 값을 내놓는 만큼 지도가 끌려다녀 도면을 읽을 수 없다.
const guidanceFollowDeadbandRatio = 0.35;

/// 마커가 화면 중심에서 데드밴드를 넘어갔는지.
///
/// 화면 크기나 배율을 모르면 **참이다** — 계산 실패를 이유로 마커가 화면 밖으로
/// 나간 것을 방치하는 쪽이 더 큰 실패다.
bool isBeyondFollowDeadband({
  required ll.LatLng camera,
  required ll.LatLng marker,
  required double zoom,
  required Size viewport,
  double ratio = guidanceFollowDeadbandRatio,
}) {
  if (!zoom.isFinite || viewport.width <= 0 || viewport.height <= 0) {
    return true;
  }
  // 짧은 변이 먼저 차므로 그쪽으로 잰다 — 세로로 긴 화면에서 가로 기준으로
  // 재면 마커가 좌우로는 이미 화면을 벗어난 뒤에야 따라간다.
  final shortSidePx = math.min(viewport.width, viewport.height);
  final visibleM = visibleWidthMeters(
    zoom: zoom,
    availablePx: shortSidePx,
    latitude: marker.latitude,
  );
  if (!visibleM.isFinite || visibleM <= 0) return true;

  return _metersBetween(camera, marker) >= visibleM / 2 * ratio;
}

const _metersPerDegreeLat = 111320.0;

double _metersBetween(ll.LatLng a, ll.LatLng b) {
  final mPerDegLng =
      _metersPerDegreeLat * math.cos(a.latitude * math.pi / 180);
  final dx = (b.longitude - a.longitude) * mPerDegLng;
  final dy = (b.latitude - a.latitude) * _metersPerDegreeLat;
  return math.sqrt(dx * dx + dy * dy);
}
