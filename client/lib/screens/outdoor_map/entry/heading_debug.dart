/// 위치 마커의 heading이 어디서 어긋나는지 한 줄로 가르는 진단 문구.
///
/// 마커가 도는 길은 네 토막(센서 → 코어 smoothing → 앵커 회전 → 지도 회전)이고,
/// 화면에서는 넷이 **똑같이 "돌아가 있다"로 보인다.** 어느 토막인지는 각 토막의
/// 값을 나란히 놓아야만 갈린다. 읽는 법은 `docs/client/android-heading-drift.md`.
library;

/// 마커 heading 한 줄.
/// 예) `기기 271° · 마커 271° · 카메라 180° · 화면 91° · rot 0° · rotation_vector · 자력계 high`
///
/// [deviceBearingDeg]는 센서가 준 나침반 방위, [markerBearingDeg]는 마커에 실제로
/// 넘긴 값, [cameraBearingDeg]는 지도가 돌아간 각도, [anchorRotationDeg]는 앵커가
/// 더하는 보정각이다.
///
/// **[headingSource]는 파생값이 아니라 센서 원문이어야 한다** —
/// `rotation_vector+gyro_hold`가 그냥 `rotation_vector`와 갈리는 것이 이 줄의 핵심
/// 정보다. 각 자리를 읽는 법은 `docs/client/android-heading-drift.md` 5절.
String describeMarkerHeading({
  required double? deviceBearingDeg,
  required double? markerBearingDeg,
  required double cameraBearingDeg,
  required double? anchorRotationDeg,
  required String? headingSource,
  String? magneticAccuracy,
}) {
  String deg(double? value) =>
      value == null ? '—' : '${_normalize(value).toStringAsFixed(0)}°';

  final screen = (deviceBearingDeg == null || markerBearingDeg == null)
      ? null
      : markerBearingDeg - cameraBearingDeg;
  return [
    '기기 ${deg(deviceBearingDeg)}',
    '마커 ${deg(markerBearingDeg)}',
    '카메라 ${deg(cameraBearingDeg)}',
    '화면 ${deg(screen)}',
    'rot ${deg(anchorRotationDeg)}',
    headingSource ?? '출처 없음',
    if (magneticAccuracy != null) '자력계 $magneticAccuracy',
  ].join(' · ');
}

double _normalize(double degrees) {
  final normalized = degrees % 360;
  return normalized < 0 ? normalized + 360 : normalized;
}
