import 'dart:math' as math;

import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import '../../../../domain/guidance/corridor_tracking.dart';
import 'corridor_network.dart';

/// 빔의 한 가설. 어느 간선 위 어디를, 어느 방향으로 걷고 있다는 한 가지 설명.
class Hypothesis {
  const Hypothesis({
    required this.edge,
    required this.progressM,
    required this.travelSign,
    required this.path,
    required this.cost,
    required this.matchedM,
    this.unmatchedM = 0,
    this.previousObservedHeadingDeg,
    this.previousGraphHeadingDeg,
    this.transitions = 0,
    this.lastNodeId,
    this.previousOffsetM = 0,
    this.seedPenaltyDegM = 0,
    this.offEdgeDistanceM = 0,
    this.stepParentHypothesisId,
    this.stepTraversals = const [],
    this.stepCrossedNodeIds = const [],
  });

  final CorridorEdge edge;
  final double progressM;
  final int travelSign;
  final List<PdrLocalPoint> path;

  /// 누적 가중 오차(도·m).
  final double cost;

  /// 비용을 매긴 총 이동 거리(m).
  final double matchedM;

  /// 그래프로 설명하지 못한 이동 거리(m).
  final double unmatchedM;

  final double? previousObservedHeadingDeg;
  final double? previousGraphHeadingDeg;
  final int transitions;
  final String? lastNodeId;

  /// 직전 걸음에서 원본 위치와 벌어져 있던 거리(m).
  final double previousOffsetM;

  /// 시작 위치에서 떨어져 있던 만큼의 영구 벌점(도·m). 감쇠하지 않는다.
  final double seedPenaltyDegM;

  /// 이 간선 방향과 **크게 어긋난 채** 진행한 거리(m).
  ///
  /// 회전 허용 구간을 그래프 진행거리만으로 재면, 사람이 코너에서 직각으로
  /// 꺾는 동안에도 가설의 progress는 원래 간선을 따라 계속 늘어난다. 그래서
  /// 정작 회전 중일 때 창이 닫힌다. 이 값만큼 창을 되돌려 주면, "지금 이
  /// 간선을 따라 걷고 있지 않다"는 구간에서는 창이 유지된다.
  final double offEdgeDistanceM;

  /// 현재 preview peak를 적용하기 직전 lineage와, 그 peak 안에서 지난 graph
  /// 조각. 다음 peak가 시작될 때 [beginStep]이 비운다.
  final String? stepParentHypothesisId;
  final List<OptimisticEdgeTraversal> stepTraversals;
  final List<String> stepCrossedNodeIds;

  String get diagnosticId =>
      '${edge.id}:$travelSign:${progressM.toStringAsFixed(3)}:$transitions';

  /// 가설끼리 비교하는 값. 같은 걸음을 먹었으므로 거리 정규화만으로 공평하다.
  double get meanErrorDeg => matchedM <= 1e-6
      ? cost + seedPenaltyDegM
      : (cost + seedPenaltyDegM) / matchedM;

  Hypothesis reversed() => _copy(travelSign: -travelSign);

  Hypothesis beginStep() => Hypothesis(
    edge: edge,
    progressM: progressM,
    travelSign: travelSign,
    path: path,
    cost: cost,
    matchedM: matchedM,
    unmatchedM: unmatchedM,
    previousObservedHeadingDeg: previousObservedHeadingDeg,
    previousGraphHeadingDeg: previousGraphHeadingDeg,
    transitions: transitions,
    lastNodeId: lastNodeId,
    previousOffsetM: previousOffsetM,
    seedPenaltyDegM: seedPenaltyDegM,
    offEdgeDistanceM: offEdgeDistanceM,
    stepParentHypothesisId: diagnosticId,
  );

  /// preview 분기용 사본. 경로를 **현재 위치 한 점으로 리셋**한다.
  ///
  /// 윈도우 이력(최대 30m)을 그대로 들고 가면 두 preview 후보의 공통 prefix가
  /// 그 이력 전체가 되어, 분기 대기 지점이 현재 위치보다 뒤로 잡힌다. 그러면
  /// 모호해질 때마다 preview가 꼬리 길이만큼 뒤로 튄다.
  Hypothesis forPreview() => _copy(path: [edge.pointAt(progressM)]);

  Hypothesis advance({
    required double observedHeadingDeg,
    required double graphHeadingDeg,
    required double distanceM,
    required double absoluteWeight,
    required double maxSegmentErrorDeg,
    required PdrLocalPoint rawPoint,
    required double positionalWeightDegPerM,
    required double positionalToleranceM,
    required double positionalMaxOffsetM,
    required int maxPathPoints,
    required double costHorizonM,
    required double offEdgeSlackLimitM,
  }) {
    if (distanceM <= 1e-6) return this;
    final absoluteError = headingError(observedHeadingDeg, graphHeadingDeg);
    final previousObserved = previousObservedHeadingDeg;
    final previousGraph = previousGraphHeadingDeg;
    // 형태 오차: 관측의 방위 변화와 그래프의 방위 변화가 얼마나 다른가.
    // heading에 상수 bias가 껴 있어도 이 값은 살아남는다.
    final shapeError = previousObserved == null || previousGraph == null
        ? absoluteError
        : headingError(
            shortestDelta(observedHeadingDeg - previousObserved),
            shortestDelta(graphHeadingDeg - previousGraph),
          );
    final combined = math.min(
      maxSegmentErrorDeg,
      absoluteError * absoluteWeight + shapeError * (1 - absoluteWeight),
    );
    final nextProgress = (progressM + travelSign * distanceM)
        .clamp(0.0, edge.lengthM)
        .toDouble();
    final nextPoint = edge.pointAt(nextProgress);
    final nextTraversals = nextProgress == progressM
        ? stepTraversals
        : [
            ...stepTraversals,
            OptimisticEdgeTraversal(
              edgeId: edge.id,
              fromProgressM: progressM,
              toProgressM: nextProgress,
            ),
          ];
    // 나란한 복도를 가르는 신호. 다만 **절대 어긋남**을 벌하면 안 된다 —
    // PDR 원본은 heading 오차로 옆으로 밀리고(실측 안드로이드 87m 보행에서
    // north 방향 13m), 그러면 원본이 밀려간 쪽의 엉뚱한 평행 복도가 오히려
    // 가까워져서 그리로 붙는다. 실제로 남쪽 매장 앞을 걸었는데 10m 북쪽
    // 복도로 올라가 버렸다.
    //
    // 그래서 어긋남의 **증가분**만 벌한다. 서서히 밀리는 드리프트는 걸음당
    // 증가가 미미해 거의 공짜이고, 갈림길에서 엉뚱한 쪽으로 꺾는 순간에는
    // 급격히 벌어져 크게 물린다.
    final offsetNowM = (nextPoint - rawPoint).distance;
    final grownM = (offsetNowM - previousOffsetM)
        .clamp(0.0, positionalMaxOffsetM)
        .toDouble();
    final offsetM =
        grownM * 10 +
        (offsetNowM - positionalToleranceM).clamp(0.0, positionalMaxOffsetM) *
            0.15;
    final nextPath = path.length >= maxPathPoints
        ? [...path.skip(path.length - maxPathPoints + 1), nextPoint]
        : [...path, nextPoint];
    // 오래된 증거를 지수적으로 잊는다. 그래야 후반에도 최근 구간이 순위를
    // 바꿀 수 있다.
    final decay = math.exp(-distanceM / costHorizonM);
    // 이 간선을 따라 걷고 있지 않은 구간만 센다. 다시 정렬되면 같은 지평선으로
    // 잊어 창이 영구히 열려 있지 않게 한다.
    final nextOffEdgeM = absoluteError > 60
        ? math.min(offEdgeSlackLimitM, offEdgeDistanceM + distanceM)
        : offEdgeDistanceM * decay;
    return _copy(
      progressM: nextProgress,
      path: nextPath,
      offEdgeDistanceM: nextOffEdgeM,
      cost:
          cost * decay +
          combined * distanceM +
          offsetM * positionalWeightDegPerM * distanceM,
      matchedM: matchedM * decay + distanceM,
      unmatchedM: unmatchedM * decay,
      previousOffsetM: offsetNowM,
      previousObservedHeadingDeg: observedHeadingDeg,
      previousGraphHeadingDeg: graphHeadingDeg,
      stepTraversals: nextTraversals,
    );
  }

  Hypothesis enter(
    RecoveryOption option, {
    required String nodeId,
    required PdrLocalPoint nodePoint,
    required PdrLocalPoint rawPoint,
    required double penaltyDegM,
    double? turnedGraphHeadingDeg,
    List<PdrLocalPoint> approachPath = const [],
    double trimTailM = 0,
  }) => Hypothesis(
    edge: option.edge,
    progressM: option.travelSign > 0 ? 0 : option.edge.lengthM,
    travelSign: option.travelSign,
    // 전환 구간 가설의 경로는 **복도를 따라** node까지 간 뒤 새 간선으로
    // 넘어간다. 지금 위치에서 node로 직선을 그으면 그 선이 매장을 가로지르고,
    // 걸은 궤적이 지도 위에서 순간이동한 것처럼 보인다.
    //
    // 지나쳐 놓고 되돌아오는 경우(늦은 회전)에는 그 사이 그려 둔 꼬리를
    // 지운다. 남겨 두면 실제로 걷지 않은 왕복이 궤적에 남는다.
    path: [..._dropLastLength(path, trimTailM), ...approachPath, nodePoint],
    cost: cost + penaltyDegM,
    matchedM: matchedM,
    unmatchedM: unmatchedM,
    previousObservedHeadingDeg: previousObservedHeadingDeg,
    // 전환 구간 가설은 "회전이 방금 여기서 일어났다"고 주장한다. 그런데 관측
    // 쪽 회전은 직전 걸음에 이미 기록됐으므로, 그래프 쪽 기준을 이전 간선에
    // 두면 **다음 걸음**에서 있지도 않은 방위 변화가 형태 오차로 잡힌다.
    // 회전 비용은 이미 전이 벌점으로 물었으니 두 번 물리지 않는다.
    previousGraphHeadingDeg: turnedGraphHeadingDeg ?? previousGraphHeadingDeg,
    transitions: transitions + 1,
    lastNodeId: nodeId,
    // 노드로 옮겨 앉은 그 순간의 어긋남을 새 기준으로 삼는다.
    //
    // 위치 항은 "갈림길에서 엉뚱한 쪽으로 꺾는 순간 급격히 벌어지는" 것을
    // 벌하려고 어긋남의 **증가분**을 본다. 그런데 노드 전이 자체가 위치를
    // 옮기므로, 직전 간선 기준 어긋남을 그대로 물려주면 전이 첫 걸음이 항상
    // 큰 증가분을 문다. 코너를 잘라 도는 정상 보행이 그 벌점 때문에 여섯
    // 걸음 뒤에야 이겼다.
    previousOffsetM: (nodePoint - rawPoint).distance,
    seedPenaltyDegM: seedPenaltyDegM,
    stepParentHypothesisId: stepParentHypothesisId,
    stepTraversals: stepTraversals,
    stepCrossedNodeIds: [...stepCrossedNodeIds, nodeId],
  );

  /// 그래프로 더 갈 수 없는 이동. 가설을 죽이지 않고 벌점만 준다.
  Hypothesis withDeadEnd(double distanceM, double penaltyDeg) => _copy(
    cost: cost + penaltyDeg * distanceM,
    matchedM: matchedM + distanceM,
    unmatchedM: unmatchedM + distanceM,
  );

  /// 노드 전이 비용도 같은 지평선으로 잊는다.

  Hypothesis _copy({
    double? progressM,
    int? travelSign,
    List<PdrLocalPoint>? path,
    double? cost,
    double? matchedM,
    double? unmatchedM,
    double? previousObservedHeadingDeg,
    double? previousGraphHeadingDeg,
    double? previousOffsetM,
    double? offEdgeDistanceM,
    List<OptimisticEdgeTraversal>? stepTraversals,
  }) => Hypothesis(
    seedPenaltyDegM: seedPenaltyDegM,
    offEdgeDistanceM: offEdgeDistanceM ?? this.offEdgeDistanceM,
    edge: edge,
    progressM: progressM ?? this.progressM,
    travelSign: travelSign ?? this.travelSign,
    path: path ?? this.path,
    cost: cost ?? this.cost,
    matchedM: matchedM ?? this.matchedM,
    unmatchedM: unmatchedM ?? this.unmatchedM,
    previousObservedHeadingDeg:
        previousObservedHeadingDeg ?? this.previousObservedHeadingDeg,
    previousGraphHeadingDeg:
        previousGraphHeadingDeg ?? this.previousGraphHeadingDeg,
    transitions: transitions,
    lastNodeId: lastNodeId,
    previousOffsetM: previousOffsetM ?? this.previousOffsetM,
    stepParentHypothesisId: stepParentHypothesisId,
    stepTraversals: stepTraversals ?? this.stepTraversals,
    stepCrossedNodeIds: stepCrossedNodeIds,
  );
}

/// 경로 **끝에서** [lengthM]만큼 지운다. 첫 점은 항상 남긴다.
List<PdrLocalPoint> _dropLastLength(List<PdrLocalPoint> path, double lengthM) {
  if (lengthM <= 1e-9 || path.length < 2) return path;
  var remaining = lengthM;
  var index = path.length - 1;
  while (index >= 1) {
    final step = (path[index] - path[index - 1]).distance;
    if (step > remaining) break;
    remaining -= step;
    index -= 1;
  }
  if (index <= 0) return [path.first];
  final kept = path.sublist(0, index);
  if (remaining > 1e-6) {
    final step = (path[index] - path[index - 1]).distance;
    final t = step <= 1e-9 ? 0.0 : (step - remaining) / step;
    kept.add(
      PdrLocalPoint(
        path[index - 1].eastM + (path[index].eastM - path[index - 1].eastM) * t,
        path[index - 1].northM +
            (path[index].northM - path[index - 1].northM) * t,
      ),
    );
  }
  return kept;
}
