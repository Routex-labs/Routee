/// 실기기에서 heading이 어긋나는 자리를 찾는 로그 한 줄.
///
/// 칩([describeMarkerHeading])과 **같은 자리에서, 같은 값으로** 찍는다. 칩은
/// 화면에 다 못 담아 네 자리만 보여주고, 이 줄은 그 판정의 근거가 된 원본까지
/// 싣는다. 둘을 다른 곳에서 만들면 "칩은 맞는데 로그는 다르다"에서 더 못
/// 나아간다.
///
/// 읽는 법은 `docs/client/android-heading-drift.md` 5절의 네 토막 표와 같다.
library;

import 'package:indoor_pdr_core/indoor_pdr_core.dart';

/// heading 진단 한 줄. 앞에 `HEADING`이 붙어 있어 logcat에서 바로 걸린다.
///
/// 예)
/// ```
/// HEADING 센서 rv=161.8 gyro=161.8 자기장=108.3µT(2.2배·의심) 오차=모름 자력계=unknown src=sensor_manager/rotation_vector
///   · 코어 orient=161.8 walk=163.0 woff=1.2 수렴=y
///   · 앵커 rot=0 phase=calibrated 신뢰=y · 지도 마커=161.8 카메라=325 화면=197
/// ```
///
/// **[magneticFieldUt]가 이 줄의 핵심이다.** 나머지 품질 값은 기기가 스스로
/// 신고하는 것이라 안 주는 기기에서는 전부 비어 있는데, 이 값만은 관측이라
/// 언제나 있다.
String describeHeadingLog({
  required double? deviceBearingDeg,
  required double? gyroBearingDeg,
  required double? orientationBearingDeg,
  required double? walkingBearingDeg,
  required double? walkOffsetDeg,
  required bool? headingConverged,
  required double? magneticFieldUt,
  required double? magneticInclinationDeg,
  required double? headingErrorDeg,
  required String? magneticAccuracy,
  required String? headingSource,
  required double? anchorRotationDeg,
  required String? calibrationPhase,
  required bool? headingTrustworthy,
  required double? markerBearingDeg,
  required double cameraBearingDeg,
}) {
  String d(double? value) => value == null ? '—' : value.toStringAsFixed(1);
  String b(bool? value) => value == null ? '—' : (value ? 'y' : 'n');

  final screen = (markerBearingDeg == null)
      ? null
      : _normalize(markerBearingDeg - cameraBearingDeg);

  return [
    'HEADING 센서',
    'rv=${d(deviceBearingDeg)}',
    'gyro=${d(gyroBearingDeg)}',
    '자기장=${describeMagneticField(magneticFieldUt)}',
    '복각=${_describeInclination(magneticInclinationDeg)}',
    '오차=${_describeError(headingErrorDeg)}',
    '자력계=${magneticAccuracy ?? '—'}',
    'src=${headingSource ?? '—'}',
    '· 코어',
    'orient=${d(orientationBearingDeg)}',
    'walk=${d(walkingBearingDeg)}',
    'woff=${d(walkOffsetDeg)}',
    '수렴=${b(headingConverged)}',
    '· 앵커',
    'rot=${d(anchorRotationDeg)}',
    'phase=${calibrationPhase ?? '—'}',
    '신뢰=${b(headingTrustworthy)}',
    '· 지도',
    '마커=${d(markerBearingDeg)}',
    '카메라=${d(cameraBearingDeg)}',
    '화면=${d(screen)}',
  ].join(' ');
}

/// 지표 자기장 세기의 대표값(µT). 위도에 따라 25~65 사이를 오간다.
///
/// 배수를 적을 기준으로만 쓴다. 판정은 [isMagneticFieldPlausible]이 범위로
/// 하므로 이 값이 정확할 필요는 없다.
const nominalEarthFieldUt = 50.0;

/// 세기와 그 세기로 내린 결론을 붙여 쓴다. 숫자만 있으면 지구 자기장이 얼마인지
/// 외우고 있어야 읽힌다.
String describeMagneticField(double? fieldUt) {
  if (fieldUt == null || fieldUt <= 0) return '모름';
  final ratio = (fieldUt / nominalEarthFieldUt).toStringAsFixed(1);
  final verdict = isMagneticFieldPlausible(fieldUt) ? '정상' : '의심';
  return '${fieldUt.toStringAsFixed(1)}µT($ratio배·$verdict)';
}

/// 서울의 자기 복각(도). 위도로 정해지므로 이 앱이 도는 범위에서는 상수로 둔다.
const seoulMagneticInclinationDeg = 53.0;

/// 복각이 서울 값에서 이만큼 넘게 벗어나면 그 자리 자기장은 지구 것이 아니다.
///
/// 넉넉하다. 기기 자세와 센서 잡음으로 몇 도는 흔들리고, 이 판정으로 잡으려는
/// 것은 왜곡된 자리에서 나타나는 수십 도짜리 어긋남이다.
const inclinationToleranceDeg = 15.0;

/// 복각과 그 값으로 내린 결론. 음수·null은 기기가 값을 안 준 것이다.
String _describeInclination(double? inclinationDeg) {
  if (inclinationDeg == null || inclinationDeg < -90) return '모름';
  final off = (inclinationDeg - seoulMagneticInclinationDeg).abs();
  final verdict = off <= inclinationToleranceDeg ? '정상' : '의심';
  return '${inclinationDeg.toStringAsFixed(0)}°($verdict)';
}

String _describeError(double? errorDeg) {
  if (errorDeg == null) return '—';
  return errorDeg < 0 ? '모름' : '${errorDeg.toStringAsFixed(0)}°';
}

double _normalize(double degrees) {
  final normalized = degrees % 360;
  return normalized < 0 ? normalized + 360 : normalized;
}
