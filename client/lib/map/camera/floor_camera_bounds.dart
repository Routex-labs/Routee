import 'dart:math';

import 'package:latlong2/latlong.dart' as ll;

/// 이 값보다 작게 움직이는 되돌림은 없던 일로 친다(약 1cm). 되돌림이 다시
/// `onCameraIdle`을 불러 왕복이 멈추지 않는 것을 막는다.
const _epsilonDeg = 1e-7;

/// 화면에서 이 거리보다 작은 경계 보정은 실행하지 않는다.
///
/// 위경도 차이만으로는 같은 오차가 줌 단계에 따라 0.1px일 수도 수십 px일 수도
/// 있다. 사용자가 느끼는 것은 좌표 오차가 아니라 **화면의 2차 이동**이라 픽셀로
/// 판단한다 — 10px는 도면을 읽는 데 영향이 없지만 "손을 뗐는데 한 번 더 움직였다"
/// 는 느낌은 충분히 만든다.
const kCameraCorrectionDeadbandPx = 10.0;

/// [corrected]로 옮길 때 화면에서 보이는 거리가 데드밴드를 넘는지 판정한다.
///
/// [halfSpanLat]·[halfSpanLng]는 화면이 덮는 위경도 범위의 절반이라, 좌표 차이를
/// 전체 범위로 나눈 뒤 뷰포트 크기를 곱하면 회전된 지도에서도 보수적인 근사가 된다.
///
/// 화면 범위를 모르면 **보정한다** — 계산 실패를 이유로 도면이 사라질 만큼 밀린
/// 카메라를 방치하는 쪽이 더 큰 실패다.
bool shouldApplyCameraCorrection({
  required ll.LatLng current,
  required ll.LatLng corrected,
  required double halfSpanLat,
  required double halfSpanLng,
  required double viewportWidthPx,
  required double viewportHeightPx,
  double deadbandPx = kCameraCorrectionDeadbandPx,
}) {
  if (halfSpanLat <= 0 ||
      halfSpanLng <= 0 ||
      viewportWidthPx <= 0 ||
      viewportHeightPx <= 0 ||
      !halfSpanLat.isFinite ||
      !halfSpanLng.isFinite ||
      !viewportWidthPx.isFinite ||
      !viewportHeightPx.isFinite) {
    return true;
  }

  final dx =
      (corrected.longitude - current.longitude).abs() /
      (halfSpanLng * 2) *
      viewportWidthPx;
  final dy =
      (corrected.latitude - current.latitude).abs() /
      (halfSpanLat * 2) *
      viewportHeightPx;
  return sqrt(dx * dx + dy * dy) >= deadbandPx;
}

/// 카메라 중심이 허용 영역 밖이면 안으로 당긴 좌표를, 안이면 null을 돌려준다.
///
/// **허용 영역은 bbox가 아니라 bbox를 화면 크기의 일부만큼 깎은 것이다**
/// ([kFootprintDeflateRatio]). [userLocation]이 있으면 한 번 더 좁히고, 교집합이
/// 비면 **위치 쪽을 남긴다.** 기준이 없는 건물에서는 **항상 null**이다.
///
/// 각 판단의 근거는 `docs/client/camera-choreography-plan.md` 4.12.
ll.LatLng? clampToFootprint(
  ll.LatLng center,
  List<ll.LatLng> footprint, {
  double halfSpanLat = 0,
  double halfSpanLng = 0,
  ll.LatLng? userLocation,
}) {
  if (footprint.length < 2) return null;

  var minLat = footprint.first.latitude;
  var maxLat = footprint.first.latitude;
  var minLng = footprint.first.longitude;
  var maxLng = footprint.first.longitude;
  for (final point in footprint) {
    minLat = min(minLat, point.latitude);
    maxLat = max(maxLat, point.latitude);
    minLng = min(minLng, point.longitude);
    maxLng = max(maxLng, point.longitude);
  }
  if (maxLat <= minLat || maxLng <= minLng) return null;

  var latRange = _deflate(minLat, maxLat, halfSpanLat * kFootprintDeflateRatio);
  var lngRange = _deflate(minLng, maxLng, halfSpanLng * kFootprintDeflateRatio);
  if (userLocation != null) {
    latRange = _intersectAround(latRange, userLocation.latitude, halfSpanLat);
    lngRange = _intersectAround(lngRange, userLocation.longitude, halfSpanLng);
  }

  final lat = center.latitude.clamp(latRange.lo, latRange.hi);
  final lng = center.longitude.clamp(lngRange.lo, lngRange.hi);
  // 이미 안에 있으면 카메라를 건드리지 않는다. 매번 animateCamera를 부르면
  // 가만히 둔 지도가 미세하게 떨린다.
  if ((lat - center.latitude).abs() < _epsilonDeg &&
      (lng - center.longitude).abs() < _epsilonDeg) {
    return null;
  }
  return ll.LatLng(lat, lng);
}

/// 허용 영역을 깎는 정도(화면 절반에 대한 비율). 0.75 = 화면의 1/8까지 도면 밖
/// 여백을 허용한다.
///
/// ⚠️ **0.5로 잡았다가 되돌렸다** — 도면이 통째로 사라지는 자리까지 밀렸다.
/// 이 값은 넉넉함만이 아니라 **bbox와 실제 도면의 차이를 흡수할 여유**까지 함께
/// 쓴다(근거: camera-choreography-plan.md 4.12).
const kFootprintDeflateRatio = 0.75;

/// 추적 중 카메라를 다시 옮기기 전에 허용하는 **어긋남**(화면 절반에 대한 비율).
/// 없으면 PDR이 한 걸음마다 값을 내놓아 걷는 내내 지도가 끌려다닌다
/// (근거: camera-choreography-plan.md 4.12).
const kFollowDeadbandRatio = 0.35;

/// 추적 중인 카메라를 [user] 자리로 다시 옮겨야 하는지. 화면 크기를 모르면
/// **항상 옮긴다** — 안 옮기면 마커가 화면 밖으로 나가도 영영 안 따라간다.
///
/// [halfSpan]은 회전된 뷰포트의 축정렬 bbox라 넉넉한데, "덜 따라간다" 쪽 오차다.
bool shouldRecenterFollow({
  required ll.LatLng camera,
  required ll.LatLng user,
  double halfSpanLat = 0,
  double halfSpanLng = 0,
}) {
  if (halfSpanLat <= 0 ||
      halfSpanLng <= 0 ||
      !halfSpanLat.isFinite ||
      !halfSpanLng.isFinite) {
    return true;
  }
  return (user.latitude - camera.latitude).abs() >
          halfSpanLat * kFollowDeadbandRatio ||
      (user.longitude - camera.longitude).abs() >
          halfSpanLng * kFollowDeadbandRatio;
}

/// [lo]~[hi] 구간을 양쪽에서 [halfSpan]만큼 깎는다. 다 깎여 뒤집히면 중점
/// 하나로 붕괴시킨다.
({double lo, double hi}) _deflate(double lo, double hi, double halfSpan) {
  if (!halfSpan.isFinite || halfSpan <= 0) return (lo: lo, hi: hi);
  final deflatedLo = lo + halfSpan;
  final deflatedHi = hi - halfSpan;
  if (deflatedLo > deflatedHi) {
    final mid = (lo + hi) / 2;
    return (lo: mid, hi: mid);
  }
  return (lo: deflatedLo, hi: deflatedHi);
}

/// [range]를 [user] ± [halfSpan]과 교차시킨다. 교집합이 비면 위치 쪽을 남긴다.
({double lo, double hi}) _intersectAround(
  ({double lo, double hi}) range,
  double user,
  double halfSpan,
) {
  if (!user.isFinite || !halfSpan.isFinite || halfSpan <= 0) return range;
  final nearLo = user - halfSpan;
  final nearHi = user + halfSpan;
  final lo = max(range.lo, nearLo);
  final hi = min(range.hi, nearHi);
  if (lo > hi) return (lo: nearLo, hi: nearHi);
  return (lo: lo, hi: hi);
}

/// 매장으로 카메라를 옮길 때 쓸 배율. 두 화면이 **같은 규칙을 써야** 같은 조작에
/// 같은 화면이 나온다.
///
/// [keepZoom]이면 배율을 그대로 둔다(훑는 행동이라 당기면 층 배치를 잃는다).
/// 아니면 [storeFocusZoom]까지 당기되 **이미 더 가까우면 그대로 둔다.**
///
/// [storeFitsViewport]는 [storeFocusZoom]이 **그 매장의 폴리곤을 재서 나온
/// 값**이라는 뜻이다. 그때는 더 가까이 있어도 그 배율까지 **물러선다** — 크게
/// 당겨 놓고 앵커 매장을 누르면 한 귀퉁이만 보이던 것이 이 조건에서 났다.
/// 폴리곤을 못 재 상수로 떨어진 값이면 물러서지 않는다. 매장 크기를 모르는
/// 채 배율을 낮추면 훑던 화면만 잃는다.
double focusZoomFor({
  required double currentZoom,
  required bool keepZoom,
  double storeFocusZoom = 19.0,
  bool storeFitsViewport = false,
}) {
  if (keepZoom) return currentZoom;
  if (storeFitsViewport) return storeFocusZoom;
  return currentZoom > storeFocusZoom ? currentZoom : storeFocusZoom;
}
