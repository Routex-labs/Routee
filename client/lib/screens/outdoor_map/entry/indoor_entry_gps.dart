/// 야외 지도의 "GPS 기반 실내 진입/이탈" 판정 정책.
///
/// 좌표 한 건이 건물 외곽선 안인지만 본다 — 안·밖·모름 셋 중 하나. 히스테리시스는
/// 거리로 만들고([indoorEnterInsetMeters]·[outdoorExitMarginMeters]), 판정과 함께
/// 그 판정을 만든 숫자를 돌려준다([GpsBuildingJudgement]).
///
/// 임계값의 근거, 버린 규칙("신호가 무너짐"·"진입 오차 문턱"), 진단 칩의 각 항목이
/// 왜 필요한지는 `docs/client/indoor-entry-rules.md`.
library;

import 'package:latlong2/latlong.dart' as ll;

import 'indoor_entry_proximity.dart';

/// **이탈** 판정에 쓸 수 있는 좌표의 최대 오차(m).
///
/// 이탈은 벽 **밖으로 8 m**를 요구하므로 30 m 오차로도 그만큼 나갔다면 근거로
/// 쓸 만하다. 이보다 나쁜 좌표는 건물 폭과 오차가 맞먹어 안팎을 못 가른다.
const outdoorExitAccuracyMeters = 30.0;

/// 외곽선에서 이만큼 안쪽에 찍혀야 "들어왔다"고 본다(m).
const indoorEnterInsetMeters = 5.0;

/// 외곽선에서 이만큼 바깥에 찍혀야 "나왔다"고 본다(m).
///
/// [indoorEnterInsetMeters]보다 크다 — 잘못 들어가는 비용보다 잘못 나오는 비용
/// (안에 있는데 PDR 추적이 끊김)이 커서 나가는 쪽을 엄격하게 잡는다.
const outdoorExitMarginMeters = 8.0;

/// 우리 외곽선과 배경 지도 타일의 건물 윤곽 사이에 **남아 있는** 어긋남(m).
///
/// 판정은 외곽선을 이만큼 바깥으로 부풀려 쓴다. 진입을 앞당기는 만큼 이탈도
/// 그만큼 늦춰야 벽 근처에서 화면이 깜빡이지 않는다([judgeBuildingFromGps]).
///
/// **지금은 0이다.** 한때 6 m였고 근거는 "백엔드 footprint가 타일 건물보다
/// 작다"였는데, 정합을 VWorld 건물 꼭지점으로 다시 잡아 그 차이가 0.11 m가 됐다
/// (`docs/client/indoor-entry-rules.md` 1절). 근거가 사라진 뒤에도 6 m를 두면
/// 벽 **바깥 1 m**에 선 사람이 "안"으로 읽힌다. 정합이 안 된 건물을 새로 넣을
/// 때 되살릴 손잡이라 상수 자체는 남긴다.
const footprintOutwardToleranceMeters = 0.0;

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

  /// 이 좌표의 오차 반경(m). **이탈 갈래만** 이 값을 본다
  /// ([outdoorExitAccuracyMeters]) — 진입도 재무장([shouldRearmGpsEntry])도
  /// 오차를 따지지 않는다.
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
      ? (footprintOutwardToleranceMeters - rawOutside).clamp(0.0, double.infinity)
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

/// 자동 진입 빗장을 풀 근거인가. **오차를 보지 않는다.**
///
/// 요구 거리는 이탈과 같은 [outdoorExitMarginMeters]지만 오차 문턱이 없다 —
/// 틀렸을 때의 비용이 다르기 때문이다. 이탈은 틀리면 건물 안에서 도면과 위치를
/// 잃지만, 재무장은 진입을 **허용할 뿐 발화시키지 않는다**(실제로 들어가려면
/// 안쪽 [indoorEnterInsetMeters]를 넘긴 좌표가 따로 와야 한다).
///
/// 오차 문턱을 여기 두면 오차가 30 m 아래로 안 내려오는 자리에서 빗장이
/// **영구히** 걸린다 — 걸어 나감 이탈이 끈 빗장을 아무도 못 푼다.
bool shouldRearmGpsEntry(GpsBuildingJudgement judgement) =>
    judgement.hasFootprint &&
    judgement.metersOutside >= outdoorExitMarginMeters;

/// 잰 거리로 결론을 내리는 사다리. 순서가 곧 정책이다.
///
/// **진입은 오차를 보지 않는다.** 좌표가 외곽선 안쪽 문턱을 넘었으면 그것으로
/// 끝이다 — 오차 문턱을 두면 실내에서 신호가 무너진 구간이 통째로 `unclear`가
/// 되어, 이미 건물 안인 사용자가 한참 뒤에야 들어간다. 대신 잘못 들어간 화면은
/// 건물 밖을 한 번 탭하면 닫힌다.
GpsBuildingVerdict _verdictFrom({
  required double accuracyMeters,
  required double metersInside,
  required double metersOutside,
}) {
  if (metersInside >= indoorEnterInsetMeters) {
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
  if (sinceLastFix != null) {
    final seconds = (sinceLastFix.inMilliseconds / 1000).toStringAsFixed(1);
    line = '$line · +${seconds}s';
  }
  if (fromStream != null) line = '$line · ${fromStream ? '스트림' : '직접'}';
  if (streamRestarts != null) line = '$line · 재시작$streamRestarts';
  return line;
}
