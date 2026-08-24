/// 실외 이탈의 **약한 근거** — GPS 문턱을 못 넘는 구간에서 쓰는 판정.
///
/// 확정 이탈(앵커 폐기)은 `indoor_entry_gps.dart`의 `outside`가 그대로 맡는다.
/// 여기 있는 것은 되돌리기 쉬운 일(재무장·기본 층 리셋)만 시키는 갈래다.
///
/// 두 상수는 **실측 없이 정한 초안값**이다. 근거는 각 선언 위에, 검증 기준은
/// `test/screens/outdoor_map/entry/indoor_exit_evidence_test.dart`.
library;

import 'dart:math' as math;

import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import '../../../domain/geo/geo_transform.dart';
import '../../../domain/guidance/corridor_tracking.dart';
import '../../../domain/route/building_entrances.dart';
import '../../../models/building/floor_graph.dart';
import '../../../models/building/floor_plan.dart';
import 'indoor_entry_gps.dart';

/// 보정된 실내 위치가 **문 앞 좌표**에서 이 거리 안이면 문에 닿았다고 본다(m).
///
/// 문 두께가 아니라 **닿을 수 있는 최단 거리**로 정한 값이다. 화면이 든 층
/// 그래프에는 문 노드가 없고(`domain/route/entrance_door_nodes.dart` 머리 주석의
/// 이유), 복도 보정은 위치를 그 그래프 위에 붙인다. 그래서 통로에서 문 앞
/// 좌표에 가장 가까워질 수 있는 지점은 **문 안쪽 앵커 노드**이고, 둘의 실측
/// 간격이 7~12 m다(`domain/route/building_entrances.dart`의
/// `BuildingEntrance.point` 주석). 12 m보다 작게 잡으면 이 조건은 **영원히 안
/// 걸린다.**
///
/// 15 = 실측 간격 상한 12 + 보정 오차 3. 아래 3 m가 근거 없는 몫이므로 **실측으로
/// 조정해야 한다** — 문을 통과한 실기기 로그(디버그 JSON `indoor_exit_events`의
/// `door_distance_m`)에서 이 거리의 최솟값을 재고 그 값 + 여유로 다시 잡는다.
const kExitDoorReachRadiusMeters = 15.0;

/// unclear가 이어지는 동안 좌표가 계속 바깥에 찍히면, 이만큼 뒤 약한 이탈로 본다.
///
/// **실측 없이 정한 값이고, 아직도 그렇다.** 좌표가 1 Hz 안팎이라 20초는 연속
/// 20건쯤에 해당한다 — 벽 옆에서 한두 건이 튀는 것으로는 안 걸리고, 정말 걸어
/// 나갔다면 그 안에 채운다. 틀렸을 때의 비용이 층 하나뿐이라 짧은 쪽으로 잡았다.
///
/// **값을 안 고친 이유**: 이 갈래는 [nextUnclearOutsideSince]의 오차 문턱 때문에
/// 실측에서 한 번도 시계조차 안 섰다(그 함수 주석). 발화한 적이 없으니 20이 길다
/// 짧다를 말할 근거가 없고, 근거 없이 옮기면 지금과 똑같이 "왜 그 값인지 못 적는"
/// 상수가 하나 더 생긴다. 갈래를 살리고 값은 그대로 둔 채, 다음 실측에서
/// `gps_position_deltas`의 `meters_outside`·`gps_accuracy_m`로 **바깥이 실제로
/// 몇 초 이어졌는지**를 재서 정한다.
const kUnclearOutsideExitHold = Duration(seconds: 20);

/// 문 앞 도달 판정 **한 걸음**. 상태를 안 들고 있으니 호출자가 [leftDoorZone]을
/// 보관했다가 돌려받은 값으로 갱신한다.
///
/// [reached]는 **문에서 한 번 멀어졌다가 다시 닿았을 때만** true다. 들어오는
/// 사람도 문 앞을 지나므로, 그 구분이 없으면 진입 직후에 곧바로 이탈로 읽는다.
///
/// 다음 중 하나라도 아니면 판정하지 않는다:
/// - [onDefaultFloor]가 false — 지상 출구는 건물 기본 층에만 있다.
/// - [corridorState]가 null이거나 [CorridorTrackingState.uncertain] — 위치를
///   못 믿는 상태에서 "문에 닿았다"고 말하면 안 된다.
///
/// [missReason]은 **안 걸린 이유**다(걸렸으면 null). 위 조건 목록을 레코더 쪽에
/// 다시 적지 않으려고 여기서 함께 돌려준다 — 이유가 두 곳에 있으면 한쪽이 썩는다.
/// [doorDistanceM]은 잰 거리 그대로이고, 못 쟀으면 null이다.
({bool leftDoorZone, bool reached, String? missReason, double? doorDistanceM})
stepExitDoorEvidence({
  required bool leftDoorZone,
  required PdrLocalPoint? positionM,
  required bool onDefaultFloor,
  required CorridorTrackingState? corridorState,
  required List<PdrLocalPoint> doorPointsM,
}) {
  final nearestM = nearestExitDoorDistanceM(positionM, doorPointsM);
  if (!onDefaultFloor) {
    return (
      leftDoorZone: leftDoorZone,
      reached: false,
      missReason: 'offDefaultFloor',
      doorDistanceM: nearestM,
    );
  }
  if (corridorState == null ||
      corridorState == CorridorTrackingState.uncertain) {
    return (
      leftDoorZone: leftDoorZone,
      reached: false,
      missReason: corridorState == null ? 'noTracker' : 'trackerUncertain',
      doorDistanceM: nearestM,
    );
  }
  if (nearestM == null) {
    return (
      leftDoorZone: leftDoorZone,
      reached: false,
      missReason: 'noDoorDistance',
      doorDistanceM: null,
    );
  }
  if (nearestM > kExitDoorReachRadiusMeters) {
    return (
      leftDoorZone: true,
      reached: false,
      missReason: 'outsideReachRadius',
      doorDistanceM: nearestM,
    );
  }
  return (
    leftDoorZone: leftDoorZone,
    reached: leftDoorZone,
    missReason: leftDoorZone ? null : 'neverLeftDoorZone',
    doorDistanceM: nearestM,
  );
}

/// 문 앞 좌표까지의 최단 거리(m). 잴 수 없으면 null.
double? nearestExitDoorDistanceM(
  PdrLocalPoint? positionM,
  List<PdrLocalPoint> doorPointsM,
) {
  if (positionM == null || doorPointsM.isEmpty) return null;
  var nearestSquared = double.infinity;
  for (final door in doorPointsM) {
    final dx = positionM.eastM - door.eastM;
    final dy = positionM.northM - door.northM;
    final squared = dx * dx + dy * dy;
    if (squared < nearestSquared) nearestSquared = squared;
  }
  return math.sqrt(nearestSquared);
}

/// 지상 출구들의 **문 앞 좌표**를 층 로컬 m로 옮긴 목록. 못 옮기면 빈 목록.
///
/// 그래프에 노드로 넣지 않는다 — 필요한 것은 거리를 잴 좌표뿐이고, 넣으면 지도
/// 매칭이 사용자를 문 밖으로 스냅한다.
List<PdrLocalPoint> exitDoorPointsFloorLocalM(
  FloorPlan? plan,
  FloorGraph? graph,
) {
  if (plan == null || graph == null || graph.nodes.isEmpty) return const [];
  final entrances = groundEntrancesFrom(plan);
  if (entrances.isEmpty) return const [];
  final transform = fitFloorGeoTransform(graph.nodes);
  final points = <PdrLocalPoint>[];
  for (final entrance in entrances) {
    final local = transform.invert(
      entrance.point.latitude,
      entrance.point.longitude,
    );
    if (local == null) continue;
    points.add(PdrLocalPoint(local.$1, local.$2));
  }
  return points;
}

/// "바깥에 찍히기 시작한 시각"을 좌표 한 건으로 갱신한다.
///
/// 좌표를 **세 띠로 나눈다. 오차는 안 본다** — 지속 시간이 그 자리를 대신한다.
/// - 바깥 [outdoorExitMarginMeters] 이상: 시작 시각을 세우고, 있으면 유지한다.
/// - 외곽선 안쪽([GpsBuildingJudgement.metersInside] > 0): null로 되돌린다.
/// - 그 사이 완충 띠: 그대로 둔다. 시계를 세울 만큼도, 지울 만큼도 아니다.
///
/// **예전에는 오차 30 m 초과를 통째로 건너뛰었다**(`return since`). 못 믿는 좌표가
/// 시계를 **되돌리지** 않게 하려던 것인데, 같은 줄이 시계를 **세우는 것까지**
/// 막았다. 건물에서 막 나온 구간이 정확히 오차가 큰 구간이라, 나가는 내내 오차가
/// 30 m를 넘으면 시계는 끝까지 null이고 [unclearOutsideExitDue]는 영영 false다 —
/// 이 갈래가 실측에서 한 번도 발화하지 않은 이유다.
///
/// 오차 문턱을 버린 대신 **거리 문턱을 0 m에서 확정 이탈과 같은
/// [outdoorExitMarginMeters]로 올렸다.** 좌표 한 건을 믿으려면 오차가 작아야 하고
/// (확정 이탈), 오차를 안 볼 거면 같은 거리가 [kUnclearOutsideExitHold]만큼
/// 이어져야 한다(여기). 문턱을 낮춘 게 아니라 맞바꾼 것이다.
DateTime? nextUnclearOutsideSince({
  required GpsBuildingJudgement judgement,
  required DateTime? since,
  required DateTime now,
}) {
  if (!judgement.hasFootprint) return since;
  if (judgement.metersOutside >= outdoorExitMarginMeters) return since ?? now;
  if (judgement.metersInside > 0) return null;
  return since;
}

/// 바깥 지속이 [kUnclearOutsideExitHold]를 채웠는지.
bool unclearOutsideExitDue(DateTime? since, DateTime now) =>
    since != null && now.difference(since) >= kUnclearOutsideExitHold;
