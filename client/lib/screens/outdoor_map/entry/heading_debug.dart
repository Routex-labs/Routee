/// 위치 마커의 heading이 어디서 어긋나는지 한 줄로 가르는 진단 문구.
///
/// 마커가 도는 길은 네 토막(센서 → 코어 smoothing → 앵커 회전 → 지도 회전)이고,
/// 화면에서는 넷이 **똑같이 "돌아가 있다"로 보인다.** 어느 토막인지는 각 토막의
/// 값을 나란히 놓아야만 갈린다. 읽는 법은 `docs/client/android-heading-drift.md`.
library;

/// 마커 heading 한 줄. 예) `기기 271° · 마커 271° · 카메라 180° · 화면 91° · rot 0° · rotation_vector`
///
/// [deviceBearingDeg]는 센서가 준 나침반 방위, [markerBearingDeg]는 마커에 실제로
/// 넘긴 값, [cameraBearingDeg]는 지도가 돌아간 각도다. [anchorRotationDeg]는 앵커가
/// 더하는 보정각이고, [headingSource]는 그 방위의 출처다.
///
/// **화면 각도(`markerBearing − cameraBearing`)를 함께 적는 것이 핵심이다.** 지도가
/// 돌아가 있으면 마커가 화면에서 어디를 가리켜야 하는지는 이 뺄셈의 결과이고,
/// 눈으로 보이는 것도 그 값이다. 둘이 다르면 회전 규약이, 같은데도 실제와 다르면
/// 방위 자체가 틀린 것이다.
String describeMarkerHeading({
  required double? deviceBearingDeg,
  required double? markerBearingDeg,
  required double cameraBearingDeg,
  required double? anchorRotationDeg,
  required String? headingSource,
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
  ].join(' · ');
}

double _normalize(double degrees) {
  final normalized = degrees % 360;
  return normalized < 0 ? normalized + 360 : normalized;
}
