/// 실내↔야외 **수동 전환 버튼**을 언제 누를 수 있는지의 정책.
///
/// 예전에는 같은 거리 계산이 화면 상태를 직접 바꿨다([indoor_entry_gps.dart]의
/// 진입·이탈 갈래). 지금은 **버튼을 켜기만 한다** — 실제로 들어가고 나가는 것은
/// 사용자가 누른 순간뿐이다. 왜 자동을 버렸는지는
/// `docs/client/indoor-entry-rules.md` 6절.
///
/// 두 게이트가 서로 다른 좌표계를 본다. 진입은 **GPS 위경도**를 건물 외곽선에
/// 대고, 이탈은 **층 좌표(m)**를 출입구 노드에 댄다 — 나가려는 사람은 건물
/// 안이라 GPS로 문 앞인지 가릴 수 없기 때문이다.
library;

import 'package:latlong2/latlong.dart' as ll;

import '../../../features/indoor_navigation/contract/indoor_navigation_contract.dart';
import 'indoor_entry_proximity.dart';

/// GPS 좌표가 건물 외곽선에서 이 거리 안이면 "진입" 버튼을 켠다(m).
///
/// 실기기 GPS 오차가 11~15 m로 관측됐다(`docs/client/indoor-entry-rules.md`
/// 1절). 30 m는 그 오차를 한 번 더 얹고도 남는 폭이라 문 앞 인도에 선 사람은
/// 확실히 켜지고, 길 건너편(왕복 6차선이 30 m를 넘는다)은 안 켜진다.
///
/// **자동 진입의 5 m(`indoorEnterInsetMeters`)보다 훨씬 넉넉한 것이 의도다.**
/// 저 값은 앱이 제멋대로 들어가지 않게 막는 문턱이었지만, 여기서는 사람이 한 번
/// 더 확인하고 누른다 — 넉넉히 잡아 못 누르는 일을 없애는 쪽이 맞다.
const manualIndoorEntryRadiusMeters = 30.0;

/// PDR 위치가 지상 출입구 노드에서 이 거리 안이면 "밖으로 나가기" 버튼을 켠다(m).
///
/// **어느 문이든 센다.** 경로가 지정한 출구만 세면 다른 문 앞에 선 사용자가
/// 갇힌다 — 실내 재탐색은 목적지 노드를 바꾸지 않아
/// (`parts/guidance.dart`의 `_rerouteIndoorFromCurrentPosition`) 경로는 계속
/// 반대편 문으로 되돌리라고 말하고, 버튼은 영영 회색이다. 다른 문으로 나가도
/// 야외 구간은 나간 자리에서 다시 그려지므로(`_activatePendingOutdoorRoute`)
/// 잃는 것은 걷는 거리뿐이다.
///
/// 15 m는 PDR 누적 오차(수 m)와 문 앞 홀의 폭을 함께 덮는다.
const manualOutdoorExitRadiusMeters = 15.0;

/// 게이트 한 건과, 그 게이트를 만든 거리.
///
/// 거리를 함께 돌려주는 이유는 [describeManualTransitionGate]다 — 실기기에서
/// "왜 버튼이 회색인가"는 화면만 봐서는 알 수 없고, 판정이 쓴 값을 그대로
/// 보여줘야 임계값과 동작이 어긋날 수 없다.
class ManualTransitionGate {
  const ManualTransitionGate({required this.enabled, required this.distanceM});

  /// 버튼을 누를 수 있는지.
  final bool enabled;

  /// 판정이 실제로 쓴 거리(m). 잴 근거가 없으면 null이고 그때 [enabled]는 false다.
  final double? distanceM;

  static const unknown = ManualTransitionGate(enabled: false, distanceM: null);
}

/// "OO(으)로 진입" 버튼의 게이트. [fix]는 지금 GPS 좌표다.
///
/// **오차를 보지 않는다.** 자동 진입에서 오차 문턱을 버린 것과 같은 이유이고
/// (`docs/client/indoor-entry-rules.md`의 「버린 규칙: 진입 오차 문턱」), 여기서는
/// 근거가 하나 더 있다 — 틀린 판정이 화면을 바꾸지 못한다. 켜져 있어도 누르지
/// 않으면 아무 일도 없다.
ManualTransitionGate manualIndoorEntryGate({
  required ll.LatLng? fix,
  required List<ll.LatLng>? footprint,
  double radiusMeters = manualIndoorEntryRadiusMeters,
}) {
  if (fix == null || footprint == null || footprint.length < 3) {
    return ManualTransitionGate.unknown;
  }
  final distance = metersToPolygon(fix, footprint);
  return ManualTransitionGate(
    enabled: distance <= radiusMeters,
    distanceM: distance,
  );
}

/// "밖으로 나가기" 버튼의 게이트.
///
/// [positionM]과 [entranceNodesM]은 **같은 층의 층 좌표**여야 한다. 같은 숫자가
/// 층마다 다른 자리를 가리키므로, 사용자가 출입구 층이 아닌 곳에 있으면 부르는
/// 쪽이 빈 목록을 넘겨 게이트를 닫는다.
ManualTransitionGate manualOutdoorExitGate({
  required PdrLocalPoint? positionM,
  required List<PdrLocalPoint> entranceNodesM,
  double radiusMeters = manualOutdoorExitRadiusMeters,
}) {
  if (positionM == null || entranceNodesM.isEmpty) {
    return ManualTransitionGate.unknown;
  }
  var best = double.infinity;
  for (final node in entranceNodesM) {
    final distance = (node - positionM).distance;
    if (distance < best) best = distance;
  }
  return ManualTransitionGate(
    enabled: best <= radiusMeters,
    distanceM: best,
  );
}

/// 게이트 한 건을 실기기 진단 칩의 한 줄로 만든다.
///
/// 예) `진입 12.4m/30m · 켬`, `나가기 근거없음`
String describeManualTransitionGate(
  ManualTransitionGate gate, {
  required String label,
  required double radiusMeters,
}) {
  final distance = gate.distanceM;
  if (distance == null) return '$label 근거없음';
  return '$label ${distance.toStringAsFixed(1)}m/'
      '${radiusMeters.toStringAsFixed(0)}m · ${gate.enabled ? '켬' : '끔'}';
}
