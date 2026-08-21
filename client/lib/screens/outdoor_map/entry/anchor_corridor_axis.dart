/// 방위를 못 얻는 기기에서 **앵커 회전각을 복도에서 가져오는** 정책.
///
/// 지하에서는 나침반도 GPS도 없다. 남는 근거는 사용자가 서 있는 자리의 복도
/// 모양뿐이다. 왜 「층 그래프 중심 방향」을 버렸는지는
/// `docs/client/android-heading-drift.md` 7절.
library;

import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import '../../../features/indoor_navigation/application/floor_map_matcher.dart';
import '../../../models/building/floor_graph.dart';
import '../outdoor_map_tuning.dart';

/// 앵커 지점에 놓인 **복도의 축**을 floor local_m 방향 벡터로 돌려준다.
///
/// [anchorFloorPoint]에서 [anchorAxisSnapDistanceM]보다 먼 곳에 통행 간선이
/// 하나도 없으면 null이다 — 그때는 회전각을 지어내는 것보다 앵커를 포기하는
/// 편이 낫다.
///
/// [inwardHint]는 **앞뒤만** 고르는 데 쓴다(±90°만 맞으면 되고, 각도 자체는 쓰지
/// 않는다). 문으로 들어온 사람에게는 "건물 안쪽"이 곧 진행 방향이라 층 그래프
/// 중심을 넘기면 되고, 힌트가 없거나 축과 직교하면 간선의 from→to를 그대로 쓴다.
PdrLocalPoint? corridorAxisAtAnchor({
  required FloorGraph graph,
  required PdrLocalPoint anchorFloorPoint,
  PdrLocalPoint? inwardHint,
  double maxSnapDistanceM = anchorAxisSnapDistanceM,
}) {
  final snapped = FloorMapMatcher(graph).snapToWalkableNetwork(
    anchorFloorPoint,
  );
  if (snapped == null || snapped.distanceToGraphM > maxSnapDistanceM) {
    return null;
  }
  final axis = PdrLocalPoint(snapped.tangentEast, snapped.tangentNorth);
  if (axis.distance < 1e-9) return null;
  final hint = inwardHint;
  if (hint == null || hint.distance < 1e-6) return axis;
  final dot = axis.eastM * hint.eastM + axis.northM * hint.northM;
  return dot < 0 ? PdrLocalPoint(-axis.eastM, -axis.northM) : axis;
}

/// 층 그래프 노드의 무게중심 방향. [corridorAxisAtAnchor]의 앞뒤 힌트 전용이다.
///
/// **이 값을 회전각으로 쓰면 안 된다.** 층 한가운데를 찍은 사용자에게는 아무
/// 근거가 없는 각도이고, 실기기에서 궤적을 51° 비스듬히 돌려 놓은 것이 바로 이
/// 값이었다. 앞뒤 두 갈래 중 하나를 고르는 데까지만 쓴다.
PdrLocalPoint? inwardHintFromGraphCentroid(
  FloorGraph graph,
  PdrLocalPoint from,
) {
  if (graph.nodes.isEmpty) return null;
  var sumX = 0.0;
  var sumY = 0.0;
  for (final node in graph.nodes) {
    sumX += node.xM;
    sumY += node.yM;
  }
  final hint = PdrLocalPoint(
    sumX / graph.nodes.length - from.eastM,
    sumY / graph.nodes.length - from.northM,
  );
  return hint.distance < 1e-3 ? null : hint;
}

/// 복도 축으로 잡은 앵커의 **앞뒤가 거꾸로인지**를 걸어 본 궤적으로 판정한다.
///
/// 축은 앞뒤를 가르지 못한다 — 같은 복도를 두 방향으로 걸을 수 있기 때문이다.
/// 거꾸로 잡았다면 궤적 전체가 앵커를 중심으로 점대칭이고, 복도는 유한하므로
/// 그 궤적은 통행 그래프를 벗어난다. 두 가설을 같은 자(그래프까지의 평균 거리)로
/// 재서 뒤집은 쪽이 [marginM]만큼 **뚜렷하게** 나을 때만 참이다.
///
/// **null은 "아직 모른다"다** — [floorPath]의 누적 이동이 [minTravelM]에 못
/// 미치거나 붙일 간선이 없는 경우다. false(그대로 두라)와 반드시 갈라야 한다:
/// 호출자는 한 앵커를 한 번만 판정하는데, 둘을 합치면 걷기도 전에 "확인했다"로
/// 소진되어 앞뒤가 영영 안 갈린다.
bool? anchorAxisIsBackward({
  required FloorGraph graph,
  required PdrLocalPoint anchorLocalM,
  required List<PdrLocalPoint> floorPath,
  double minTravelM = anchorAxisProbeTravelM,
  double marginM = anchorAxisProbeMarginM,
}) {
  if (floorPath.length < 2 || graph.edges.isEmpty) return null;
  if (_traveledM(floorPath) < minTravelM) return null;
  final matcher = FloorMapMatcher(graph);
  final asIs = _meanOffGraphM(matcher, floorPath);
  final mirrored = _meanOffGraphM(matcher, [
    for (final point in floorPath) _mirror(point, anchorLocalM),
  ]);
  if (asIs == null || mirrored == null) return null;
  return mirrored + marginM < asIs;
}

/// 앵커를 중심으로 한 점대칭. 회전각에 180°를 더한 것과 **정확히 같다** —
/// `rotatePdrBearing`이 선형이고 `PdrToFloorAxes`도 선형이라, 두 변환을 지나도
/// 부호 반전이 그대로 살아남기 때문이다.
PdrLocalPoint _mirror(PdrLocalPoint point, PdrLocalPoint about) => PdrLocalPoint(
  2 * about.eastM - point.eastM,
  2 * about.northM - point.northM,
);

double _traveledM(List<PdrLocalPoint> path) {
  var total = 0.0;
  for (var index = 1; index < path.length; index++) {
    total += (path[index] - path[index - 1]).distance;
  }
  return total;
}

/// 궤적의 각 점에서 통행 그래프까지의 평균 거리. 붙일 간선이 없으면 null.
double? _meanOffGraphM(FloorMapMatcher matcher, List<PdrLocalPoint> path) {
  var total = 0.0;
  var counted = 0;
  for (final point in path) {
    final snapped = matcher.snapToWalkableNetwork(point);
    if (snapped == null) continue;
    total += snapped.distanceToGraphM;
    counted++;
  }
  return counted == 0 ? null : total / counted;
}
