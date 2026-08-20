/// 야외 지도의 "GPS 기반 실내 진입/이탈" 판정 정책.
///
/// 좌표 한 건이 건물 외곽선 안인지만 본다 — 안·밖·모름 셋 중 하나. 히스테리시스는
/// 거리로 만들고([indoorEnterInsetMeters]·[outdoorExitMarginMeters]), 판정과 함께
/// 그 판정을 만든 숫자를 돌려준다([GpsBuildingJudgement]).
///
/// 임계값의 근거, 버린 규칙("신호가 무너짐"), 진단 칩의 각 항목이 왜 필요한지는
/// `docs/client/indoor-entry-rules.md`.
library;

import 'package:latlong2/latlong.dart' as ll;

import 'indoor_entry_proximity.dart';

/// **진입** 판정에 쓸 수 있는 좌표의 최대 오차(m). 넘으면 진입 근거로 안 쓴다.
const decisiveAccuracyMeters = 20.0;

/// **이탈** 판정에 쓸 수 있는 좌표의 최대 오차(m). 진입보다 느슨하다.
///
/// 건물에서 막 나온 순간이 정확히 오차가 큰 구간이라, 진입과 같은 20 m를
/// 요구하면 그 구간이 통째로 `unclear`가 돼 전환이 늦는다. 이탈은 부풀린
/// 외곽선 **밖으로 14 m**를 요구하므로(아래 두 상수의 합) 30 m 오차로도 그만큼
/// 나갔다면 근거로 쓸 만하다. 진입은 안쪽 5 m뿐이라 같이 풀면 안 된다.
const outdoorExitAccuracyMeters = 30.0;

/// 외곽선에서 이만큼 안쪽에 찍혀야 "들어왔다"고 본다(m).
const indoorEnterInsetMeters = 5.0;

/// 외곽선에서 이만큼 바깥에 찍혀야 "나왔다"고 본다(m).
///
/// [indoorEnterInsetMeters]보다 크다 — 잘못 들어가는 비용보다 잘못 나오는 비용
/// (안에 있는데 PDR 추적이 끊김)이 커서 나가는 쪽을 엄격하게 잡는다.
const outdoorExitMarginMeters = 8.0;

/// 우리 외곽선과 실제 건물 벽 사이의 알려진 어긋남(m).
///
/// 판정은 외곽선을 이만큼 **바깥으로 부풀려** 쓴다. 진입을 앞당기는 만큼
/// **이탈도 늦춰야** 벽 근처에서 화면이 깜빡이지 않는다([judgeBuildingFromGps]).
const footprintOutwardToleranceMeters = 6.0;

/// 한 건만으로 진입을 확정해도 되는 최대 오차. 이보다 큰 inside는 다음 표본을
/// 한 번 더 확인한다.
const immediateEntryAccuracyMeters = 10.0;

/// 판정에 쓰는 위치 한 건.
class GpsFix {
  const GpsFix({required this.point, required this.accuracyMeters});

  final ll.LatLng point;

  /// 오차 반경(m). **작을수록 정확하다.**
  final double accuracyMeters;
}

/// 좌표 한 건이 말하는 "건물 안팎".
enum GpsBuildingVerdict {
  /// 건물 안. 야외 상태였다면 실내로 들어갈 근거다.
  inside,

  /// 건물 밖. 실내 상태였다면 나갈 근거이고, 야외 상태라면 자동 진입을 다시
  /// 무장할 근거다.
  outside,

  /// 판단하지 않는다 — 오차가 크거나, 외곽선을 모르거나, 벽 주변 완충 구간.
  unclear,
}

/// 한 건의 건물 판정을 시간축 증거와 합친 결과.
enum GpsEntryConfirmation {
  /// 진입 증거가 아니거나 기존 후보가 취소됐다.
  none,

  /// 보통 inside 한 건을 받았고 다음 정상 표본을 기다린다.
  pending,

  /// 오차가 작은 강한 inside라 추가 대기 없이 확정했다.
  immediate,

  /// 서로 다른 보통 inside 두 건이 이어져 확정했다.
  confirmed,
}

/// 단일 GPS 튐은 막되 좋은 좌표에는 지연을 더하지 않는 진입 증거 누적기.
///
/// 좌표를 평활하거나 경로에 붙이지 않는다. 원본 표본이 만든 [GpsBuildingJudgement]
/// 만 시간순으로 읽으므로 화면용 위치 보정이 판정 사실을 바꾸지 않는다.
class GpsEntryEvidenceTracker {
  DateTime? _pendingAt;

  void reset() => _pendingAt = null;

  GpsEntryConfirmation observe(
    GpsBuildingJudgement judgement, {
    required DateTime observedAt,
  }) {
    if (judgement.verdict != GpsBuildingVerdict.inside) {
      reset();
      return GpsEntryConfirmation.none;
    }
    if (judgement.accuracyMeters <= immediateEntryAccuracyMeters) {
      reset();
      return GpsEntryConfirmation.immediate;
    }

    final previous = _pendingAt;
    if (previous == null) {
      _pendingAt = observedAt;
      return GpsEntryConfirmation.pending;
    }
    final gap = observedAt.difference(previous);
    if (gap == Duration.zero) {
      // 같은 OS fix를 스트림과 일회성 조회가 중복 배달해도 두 표본으로 세지 않는다.
      return GpsEntryConfirmation.pending;
    }
    if (gap.isNegative) {
      _pendingAt = observedAt;
      return GpsEntryConfirmation.pending;
    }
    reset();
    return GpsEntryConfirmation.confirmed;
  }
}

/// 판정 한 건과, 그 판정을 만든 숫자들.
///
/// 거리는 **판정이 실제로 쓴 값 그대로**다. 그래서 화면 진단(칩)과 동작이 어긋날
/// 수 없다.
class GpsBuildingJudgement {
  const GpsBuildingJudgement({
    required this.verdict,
    required this.accuracyMeters,
    required this.metersInside,
    required this.metersOutside,
    required this.hasFootprint,
  });

  /// 이 좌표가 말하는 건물 안팎.
  final GpsBuildingVerdict verdict;

  /// 이 좌표의 오차 반경(m). [decisiveAccuracyMeters]를 넘으면 나머지 거리가
  /// 어떻든 [GpsBuildingVerdict.unclear]다.
  final double accuracyMeters;

  /// 외곽선 **안쪽**으로 들어와 있는 거리(m). 밖이면 0.
  ///
  /// 오차가 커서 판정을 건너뛴 경우에도 채운다.
  final double metersInside;

  /// 외곽선 **바깥**으로 나가 있는 거리(m). 안이면 0.
  final double metersOutside;

  /// 건물 외곽선을 알고 있었는지. false면 두 거리는 0이고 의미가 없다.
  final bool hasFootprint;
}

/// [fix]가 [footprint] 안팎 중 어디를 가리키는지 판정한다.
///
/// 지금 실내 상태인지는 **묻지 않는다.** 좌표 하나를 읽을 뿐이고, 그 결과로
/// 무엇을 할지(진입·이탈·무장)는 화면이 정한다.
GpsBuildingJudgement judgeBuildingFromGps({
  required GpsFix fix,
  required List<ll.LatLng>? footprint,
}) {
  if (footprint == null || footprint.length < 3) {
    return GpsBuildingJudgement(
      verdict: GpsBuildingVerdict.unclear,
      accuracyMeters: fix.accuracyMeters,
      metersInside: 0,
      metersOutside: 0,
      hasFootprint: false,
    );
  }
  // unclear로 정해질 경우에도 거리는 끝까지 잰다 — 진단에는 이 값이 전부다.
  // 균일한 바깥 버퍼는 "안쪽 거리 + tolerance, 바깥 거리 − tolerance"와 같은
  // 뜻이라, 폴리곤을 다시 만들지 않고 거리를 옮기는 것으로 끝낸다. 음수로
  // 내려가지 않게 자른다("반대쪽은 0"이 두 값의 약속이다).
  final rawInside = metersInsidePolygon(fix.point, footprint);
  final rawOutside = metersToPolygon(fix.point, footprint);
  final metersInside = rawOutside > 0
      ? (footprintOutwardToleranceMeters - rawOutside).clamp(
          0.0,
          double.infinity,
        )
      : rawInside + footprintOutwardToleranceMeters;
  final metersOutside = (rawOutside - footprintOutwardToleranceMeters).clamp(
    0.0,
    double.infinity,
  );
  return GpsBuildingJudgement(
    verdict: _verdictFrom(
      accuracyMeters: fix.accuracyMeters,
      metersInside: metersInside,
      metersOutside: metersOutside,
    ),
    accuracyMeters: fix.accuracyMeters,
    metersInside: metersInside,
    metersOutside: metersOutside,
    hasFootprint: true,
  );
}

/// 잰 거리로 결론을 내리는 사다리. 순서가 곧 정책이다.
///
/// **오차 문턱을 두 갈래가 각자 본다.** 예전에는 맨 위에서 한 번만 걸렀는데,
/// 그 값이 진입 기준(엄격)이라 이탈까지 같이 막혔다 — 건물에서 막 나온 순간이
/// 정확히 오차가 큰 구간이라 그 구간이 통째로 `unclear`가 됐다.
GpsBuildingVerdict _verdictFrom({
  required double accuracyMeters,
  required double metersInside,
  required double metersOutside,
}) {
  if (accuracyMeters <= decisiveAccuracyMeters &&
      metersInside >= indoorEnterInsetMeters) {
    return GpsBuildingVerdict.inside;
  }
  if (accuracyMeters <= outdoorExitAccuracyMeters &&
      metersOutside >= outdoorExitMarginMeters) {
    return GpsBuildingVerdict.outside;
  }
  return GpsBuildingVerdict.unclear;
}

/// 판정 한 건을 실기기 화면에 띄울 한 줄로 만든다.
///
/// 예) `정확도 12m · 안쪽 3.1m · unclear · 무장O · +1.0s`
///
/// [armed]는 자동 진입 무장 여부(화면 상태라 판정에는 안 들어간다), [sinceLastFix]
/// 는 직전 좌표와의 간격, [fromStream]·[streamRestarts]는 그 간격의 원인을 가르는
/// 값이다. 각 항목이 왜 필요한지는 `docs/client/indoor-entry-rules.md`.
String describeGpsBuildingJudgement(
  GpsBuildingJudgement judgement, {
  required bool armed,
  GpsEntryConfirmation? entryConfirmation,
  Duration? sinceLastFix,
  bool? fromStream,
  int? streamRestarts,
}) {
  final accuracy = '정확도 ${judgement.accuracyMeters.toStringAsFixed(0)}m';
  final place = !judgement.hasFootprint
      ? '외곽선 없음'
      : judgement.metersInside > 0
      ? '안쪽 ${judgement.metersInside.toStringAsFixed(1)}m'
      : '바깥 ${judgement.metersOutside.toStringAsFixed(1)}m';
  final verdict = judgement.verdict.name;
  var line = '$accuracy · $place · $verdict · 무장${armed ? 'O' : 'X'}';
  if (entryConfirmation == GpsEntryConfirmation.pending) {
    line = '$line · 확인1/2';
  } else if (entryConfirmation == GpsEntryConfirmation.immediate) {
    line = '$line · 즉시확정';
  } else if (entryConfirmation == GpsEntryConfirmation.confirmed) {
    line = '$line · 확인2/2';
  }
  if (sinceLastFix != null) {
    final seconds = (sinceLastFix.inMilliseconds / 1000).toStringAsFixed(1);
    line = '$line · +${seconds}s';
  }
  if (fromStream != null) line = '$line · ${fromStream ? '스트림' : '직접'}';
  if (streamRestarts != null) line = '$line · 재시작$streamRestarts';
  return line;
}
