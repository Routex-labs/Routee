/// 코어에 들어오는 typed 센서 이벤트.
///
/// 연구 앱은 native EventChannel의 raw `Map`을 `PdrNativeEvent.tryParse`로 파싱했다.
/// 코어는 플랫폼을 모르므로, adapter(플랫폼 계층)가 raw map을 아래 타입으로 변환해
/// 넣는다. 코어에는 `Map<dynamic,dynamic>`이 진입하지 않는다.
library;

/// CoreMotion DeviceMotion 묶음에서 코어가 쓰는 필드.
class HeadingEvent {
  const HeadingEvent({
    required this.motionTimestampMs,
    required this.fusedHeadingDeg,
    this.headingStable,
    this.deviceHeadingDeg,
    this.yawDeg,
    this.gyroHeadingDeg,
    this.pitchDeg,
    this.rollDeg,
    this.walkDirDeg,
    this.walkDirConfidence,
    this.magneticAccuracy,
    this.magneticField,
    this.magneticInclinationDeg,
    this.rotationHeadingAccuracyDeg,
    this.headingSource,
  });

  /// native step peak timestamp와 같은 시간축. heading history/step 시각 정렬의 기준.
  final int motionTimestampMs;
  final double fusedHeadingDeg;
  final bool? headingStable;
  final double? deviceHeadingDeg;
  final double? yawDeg;
  final double? gyroHeadingDeg;
  final double? pitchDeg;
  final double? rollDeg;
  final double? walkDirDeg;
  final double? walkDirConfidence;
  final String? magneticAccuracy;
  final double? magneticField;

  /// 자기 벡터가 수평면에서 기운 각(도). 위도로 정해지며 서울은 약 53°다.
  /// 값을 못 받았으면 null, 기기가 못 냈으면 음수다.
  final double? magneticInclinationDeg;
  final double? rotationHeadingAccuracyDeg;
  final String? headingSource;
}

/// CMPedometer 배치. iOS가 1~2.5초 단위로 늦게 flush한다.
class PedometerBatchEvent {
  const PedometerBatchEvent({
    required this.steps,
    this.stepSessionId,
    this.sessionStartMs,
    this.timestampMs,
    this.deltaMs,
    this.distanceM,
    this.distanceAvailable,
    this.cadenceHz,
    this.paceSecPerM,
    this.cadenceAvailable,
    this.paceAvailable,
    this.stepPeakTimes,
    this.isAndroid = false,
    this.stepCountSource,
    this.authoritativeSteps,
    this.stepCounterSteps,
    this.stepCounterDelta,
    this.counterLastEventAtMs,
    this.stepAccelAmplitudeMps2,
    this.roninSupported = false,
    this.roninReady = false,
    this.roninModel,
    this.roninStatus,
    this.roninSpeedMps,
    this.roninSpeedStdMps,
    this.roninCadenceHz,
    this.roninStrideMeters,
  });

  final int steps;
  final int? stepSessionId;
  final int? sessionStartMs;
  final double? timestampMs;
  final double? deltaMs;
  final double? distanceM;
  final bool? distanceAvailable;
  final double? cadenceHz;
  final double? paceSecPerM;
  final bool? cadenceAvailable;
  final bool? paceAvailable;
  final List<double>? stepPeakTimes;

  /// Android는 CMPedometer distance가 없으므로 stride 후보를 shadow 진단으로만
  /// 계산한다. 확정 거리에는 fallback/calibration만 사용한다.
  final bool isAndroid;
  final String? stepCountSource;
  final int? authoritativeSteps;
  final int? stepCounterSteps;
  final int? stepCounterDelta;
  final double? counterLastEventAtMs;
  final double? stepAccelAmplitudeMps2;

  /// Android 전용 RoNIN shadow 추론값. confirmed(초록) 거리에는 반영하지 않고
  /// 동일 step/heading으로 누적하는 별도 비교 경로에서만 사용한다.
  final bool roninSupported;
  final bool roninReady;
  final String? roninModel;
  final String? roninStatus;
  final double? roninSpeedMps;
  final double? roninSpeedStdMps;
  final double? roninCadenceHz;
  final double? roninStrideMeters;
}

/// native accel step-peak 카운터 신호. 주황(preview) 경로 전용.
class AccelPeakEvent {
  const AccelPeakEvent({
    required this.count,
    this.latestPeakMs,
    this.motionTimestampMs,
  });

  final int count;
  final int? latestPeakMs;
  final num? motionTimestampMs;
}
