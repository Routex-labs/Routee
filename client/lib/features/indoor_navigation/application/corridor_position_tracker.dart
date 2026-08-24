import 'dart:math' as math;

import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import '../../../domain/guidance/corridor_tracking.dart';
import '../../../models/building/floor_graph.dart';
import '../contract/pdr_anchor.dart';
import 'corridor/corridor_hypothesis.dart';
import 'corridor/corridor_network.dart';
import 'corridor/corridor_observation.dart';
import 'corridor/corridor_tracker_config.dart';

export 'corridor/corridor_observation.dart';
export 'corridor/corridor_tracker_config.dart';

/// 초록·주황 원본을 수정하지 않고 실제 위치만 graph 제약으로 보정한다.
///
/// **빔 서치**다 — 간선 하나를 잠그는 대신 가설 여럿을 동시에 들고 걸음마다 점수를
/// 매겨 언제든 1등이 바뀔 수 있게 둔다. 이전의 탐욕적 상태기는 회전을 한 번 놓치면
/// 되돌릴 수 없어 실측에서 교차점에 28초 멈춰 있었다.
///
/// 위치는 절대 멈추지 않는다 — 어떤 가설도 설명되지 않으면 벌점을 주되 진행시켜
/// 걸은 거리가 통째로 사라지지 않게 한다.
class CorridorPositionTracker {
  CorridorPositionTracker(
    FloorGraph graph, {
    this.config = const CorridorTrackerConfig(),
  }) : _network = CorridorNetwork(graph);

  final CorridorTrackerConfig config;
  final CorridorNetwork _network;

  /// 현재 안내 경로의 방향 있는 간선 열. 맵매칭을 강제로 고정하지는 않고, 실제
  /// 보행이 graph 꼭짓점을 잘라 지나갈 때도 정확한 다음 간선 가설을 열어 두는
  /// 약한 prior로만 쓴다.
  List<String> _preferredRouteEdgeIds = const [];
  List<String> _preferredRouteNodeIds = const [];
  bool _preferRouteContinuity = false;
  bool _lockPreferredRouteTerminal = false;
  int _lastRouteStraightEpochIndex = -1;

  final List<PdrLocalPoint> _correctedPath = [];
  final List<PdrLocalPoint> _previewPath = [];

  List<Hypothesis> _beam = const [];

  /// 화면 위치를 들고 있는 두 번째 빔. 확정 빔과 **따로** 산다.
  ///
  /// 매 snapshot마다 확정 1등에서 다시 만들지 않는다. 새 accel peak가 생긴
  /// 즉시 한 번 전진하고, 그 뒤 확정 배치가 같은 peak를 확인하더라도 다시
  /// 전진하거나 뒤로 가지 않는다.
  List<Hypothesis> _optimisticBeam = const [];

  /// optimistic beam에 이미 태운 preview peak 식별자(오래된 것부터).
  final List<int> _appliedPreviewPeakIds = [];
  final Set<int> _appliedPreviewPeakIdSet = {};

  /// optimistic·confirmed가 각각 태운 누적 보행 거리(m).
  double _optimisticTraveledM = 0;
  double _confirmedTraveledM = 0;
  bool _previewPeakIdsSynthetic = false;

  /// 직전 확정 배치의 마지막 걸음 방위(bias 적용 전). preview 없이 배치로만
  /// 들어온 걸음을 optimistic beam에 태울 때 쓴다.
  double? _lastConfirmedSegmentHeadingDeg;

  String? _junctionNodeId;
  double _junctionDistanceM = double.infinity;
  List<String> _junctionCandidateEdgeIds = const [];

  CorridorTrackingState _state = CorridorTrackingState.uncertain;
  PdrLocalPoint _correctedPosition = PdrLocalPoint.zero;
  PdrLocalPoint _previewPosition = PdrLocalPoint.zero;
  double _previewHeadingDeg = 0;
  List<String> _previewCandidateEdgeIds = const [];
  bool _previewIsAmbiguous = false;
  PdrLocalPoint _rawConfirmedPosition = PdrLocalPoint.zero;
  PdrLocalPoint _rawPreviewPosition = PdrLocalPoint.zero;
  double _sensorHeadingDeg = 0;
  double _headingBiasDeg = 0;
  int _lastConfirmedSteps = 0;
  double _lastConfirmedDistanceM = 0;
  int _lastPreviewSteps = 0;
  String? _pendingEdgeId;
  String? _lastConfirmedNodeId;
  String? _leaderEdgeId;
  int _leaderSign = 1;
  String? _optimisticLeaderEdgeId;
  int _optimisticLeaderSign = 1;

  /// 이번 갱신에서 확정 위치가 나아간 거리(m).
  double _confirmedAdvanceM = 0;
  bool _leaderRelocated = false;
  String? _routeStraightEpochNodeId;
  final List<OptimisticStepAdvance> _optimisticStepAdvances = [];

  bool get isInitialized => _beam.isNotEmpty;

  void setPreferredRoute({
    required List<String> edgeIds,
    required List<String> nodeIds,
    bool preferContinuity = false,
    bool lockTerminal = false,
  }) {
    final routeChanged =
        !_sameStrings(_preferredRouteEdgeIds, edgeIds) ||
        !_sameStrings(_preferredRouteNodeIds, nodeIds);
    if (nodeIds.length != edgeIds.length + 1) {
      _preferredRouteEdgeIds = const [];
      _preferredRouteNodeIds = const [];
      _preferRouteContinuity = false;
      _lockPreferredRouteTerminal = false;
      _lastRouteStraightEpochIndex = -1;
      return;
    }
    _preferredRouteEdgeIds = List.unmodifiable(edgeIds);
    _preferredRouteNodeIds = List.unmodifiable(nodeIds);
    _preferRouteContinuity = preferContinuity;
    _lockPreferredRouteTerminal = lockTerminal;
    if (routeChanged) _lastRouteStraightEpochIndex = -1;
  }

  Hypothesis? get _best => _beam.isEmpty ? null : _beam.first;

  Hypothesis? get _optimisticBest =>
      _optimisticBeam.isEmpty ? null : _optimisticBeam.first;

  double get _optimisticLeadM =>
      math.max(0.0, _optimisticTraveledM - _confirmedTraveledM);

  CorridorTrackingResult get result => CorridorTrackingResult(
    state: _state,
    correctedPosition: _correctedPosition,
    correctedHeadingDeg:
        _best?.edge.bearingForTravel(_best!.progressM, _best!.travelSign) ??
        normalizeBearing(_sensorHeadingDeg + _headingBiasDeg),
    headingBiasDeg: _headingBiasDeg,
    currentEdgeId: _best?.edge.id,
    currentEdgeProgressM: _best?.progressM ?? 0,
    travelDirectionSign: _best?.travelSign ?? 1,
    pendingEdgeId: _pendingEdgeId,
    lastConfirmedNodeId: _lastConfirmedNodeId,
    correctedPath: List.unmodifiable(_correctedPath),
    previewPosition: _previewPosition,
    previewHeadingDeg: _previewHeadingDeg,
    previewPath: List.unmodifiable(_previewPath),
    previewCandidateEdgeIds: List.unmodifiable(_previewCandidateEdgeIds),
    previewIsAmbiguous: _previewIsAmbiguous,
    rawConfirmedPosition: _rawConfirmedPosition,
    rawPreviewPosition: _rawPreviewPosition,
    confirmedDisplacementM: _confirmedAdvanceM,
    optimisticLeadM: _optimisticLeadM,
    optimisticEdgeId: _optimisticBest?.edge.id,
    optimisticEdgeProgressM: _optimisticBest?.progressM ?? 0,
    previewPeakIdsSynthetic: _previewPeakIdsSynthetic,
    junctionNodeId: _junctionNodeId,
    junctionDistanceM: _junctionDistanceM,
    junctionCandidateEdgeIds: List.unmodifiable(_junctionCandidateEdgeIds),
    leaderRelocated: _leaderRelocated,
    routeStraightEpochNodeId: _routeStraightEpochNodeId,
    optimisticStepAdvances: List.unmodifiable(_optimisticStepAdvances),
  );

  void reset({
    required PdrLocalPoint initialPosition,
    required double initialHeadingDeg,
    required int timestampMs,
    int initialConfirmedSteps = 0,
    double initialConfirmedDistanceM = 0,
    int initialPreviewSteps = 0,
  }) {
    _sensorHeadingDeg = normalizeBearing(initialHeadingDeg);
    _headingBiasDeg = 0;
    _lastConfirmedSteps = initialConfirmedSteps;
    _lastConfirmedDistanceM = initialConfirmedDistanceM;
    _lastPreviewSteps = initialPreviewSteps;
    _rawConfirmedPosition = initialPosition;
    _rawPreviewPosition = initialPosition;
    _lastConfirmedNodeId = null;
    _pendingEdgeId = null;
    _leaderEdgeId = null;
    _leaderSign = 1;
    _optimisticLeaderEdgeId = null;
    _optimisticLeaderSign = 1;
    _confirmedAdvanceM = 0;
    _leaderRelocated = false;
    _routeStraightEpochNodeId = null;
    _lastRouteStraightEpochIndex = -1;
    _optimisticStepAdvances.clear();
    _lastConfirmedSegmentHeadingDeg = null;
    // 두 beam과 식별자 상태를 함께 초기화한다. 하나만 남기면 새 세션의 첫
    // peak가 "이미 태운 걸음"으로 걸러진다.
    _appliedPreviewPeakIds.clear();
    _appliedPreviewPeakIdSet.clear();
    _optimisticBeam = const [];
    _confirmedTraveledM = initialConfirmedDistanceM;
    _optimisticTraveledM = initialConfirmedDistanceM;
    _previewPeakIdsSynthetic = false;

    // 시작 방향을 하나로 못 박지 않는다. 첫 걸음의 방위는 복도에 거의 수직인
    // 경우가 많고(실측에서 176.9°), 그것으로 진행 부호를 잠그면 6° 차이로
    // 역주행이 확정된다. 대신 근처 간선의 양방향을 모두 씨앗으로 깔고 걸음이
    // 쌓이면서 걸러지게 둔다.
    _beam = _seedHypotheses(initialPosition, initialHeadingDeg);
    _correctedPosition = _best == null
        ? initialPosition
        : _best!.edge.pointAt(_best!.progressM);
    _correctedPath
      ..clear()
      ..add(_correctedPosition);
    _state = _beam.isEmpty
        ? CorridorTrackingState.uncertain
        : CorridorTrackingState.straightTracking;
    _resetPreviewToConfirmed();
    _updateJunctionState();
  }

  CorridorTrackingResult update(CorridorObservation observation) {
    if (!isInitialized) {
      reset(
        initialPosition: observation.rawConfirmedPosition,
        initialHeadingDeg: observation.sensorHeadingDeg,
        timestampMs: observation.timestampMs,
      );
    }
    _optimisticStepAdvances.clear();
    final previousRawConfirmedPosition = _rawConfirmedPosition;
    _rawConfirmedPosition = observation.rawConfirmedPosition;
    _rawPreviewPosition = observation.rawPreviewPosition;
    if (observation.hasHeading && observation.sensorHeadingDeg.isFinite) {
      _sensorHeadingDeg = normalizeBearing(observation.sensorHeadingDeg);
    }

    final deltaSteps = math.max(
      0,
      observation.confirmedSteps - _lastConfirmedSteps,
    );
    final deltaDistanceM = math.max(
      0.0,
      observation.confirmedDistanceM - _lastConfirmedDistanceM,
    );
    final hasConfirmedAdvance = deltaSteps > 0 && deltaDistanceM > 0;

    final previousCorrected = _correctedPosition;
    _confirmedAdvanceM = 0;
    _leaderRelocated = false;
    _routeStraightEpochNodeId = null;
    if (hasConfirmedAdvance) {
      final segments = _rawSegments(
        deltaSteps: deltaSteps,
        deltaDistanceM: deltaDistanceM,
        previousRawConfirmedPosition: previousRawConfirmedPosition,
        rawConfirmedStepPositions: observation.rawConfirmedStepPositions,
      );
      final transitionsBefore = _best?.transitions ?? 0;
      for (final segment in segments) {
        _advanceBeam(segment);
        _lastConfirmedSegmentHeadingDeg = segment.headingDeg;
      }
      _updateHeadingBias();
      _publishConfirmed(transitionsBefore: transitionsBefore);
      _beginRouteStraightEpochIfReady();
      _confirmedAdvanceM = (_correctedPosition - previousCorrected).distance;
      // 그래프를 따라 실제로 걸었다면 두 끝점의 직선거리는 보행 경로 길이를
      // 넘을 수 없다. 0.5m 여유를 넘는 차이는 빔 1등 교체로 위치 해석이
      // 재배치된 것이다.
      _leaderRelocated = _confirmedAdvanceM > deltaDistanceM + 0.5;
    }

    _lastConfirmedSteps = math.max(
      _lastConfirmedSteps,
      observation.confirmedSteps,
    );
    _lastConfirmedDistanceM = math.max(
      _lastConfirmedDistanceM,
      observation.confirmedDistanceM,
    );
    _confirmedTraveledM = _lastConfirmedDistanceM;
    _lastPreviewSteps = math.max(_lastPreviewSteps, observation.previewSteps);

    // 확정 → optimistic 순서를 지킨다. 단, 새 확정 걸음이 없는 heading/
    // heartbeat snapshot은 optimistic cursor의 lineage를 바꿀 근거가 아니다.
    // 이때도 reconcile하면 같은 확정점으로 화면만 반복해서 되감긴다.
    if (hasConfirmedAdvance) {
      _reconcileOptimistic(
        observation.confirmedThroughPeakId ?? observation.confirmedThroughMs,
      );
    }
    _applyPreviewPeaks(observation);
    _catchUpOptimisticToConfirmed();
    _forgetAcknowledgedPeakIds(
      observation.confirmedThroughPeakId ?? observation.confirmedThroughMs,
    );
    _publishPreview();
    _updateJunctionState();
    return result;
  }

  // ── 빔 ──

  List<Hypothesis> _seedHypotheses(PdrLocalPoint position, double headingDeg) {
    final seeds = <Hypothesis>[];
    for (final projection in _network.nearbyProjections(
      position,
      radiusM: config.seedRadiusM,
    )) {
      for (final sign in const [1, -1]) {
        if (sign < 0 && !projection.edge.bidirectional) continue;
        seeds.add(
          Hypothesis(
            edge: projection.edge,
            progressM: projection.distanceAlongM,
            travelSign: sign,
            path: [projection.point],
            cost: 0,
            matchedM: 0,
            // 잊히지 않는 벌점. 시작 지점에서 먼 씨앗일수록 끝까지 불리하다.
            seedPenaltyDegM: projection.distanceM * config.seedPenaltyDegM,
          ),
        );
      }
    }
    if (seeds.isEmpty) return const [];
    return _prune(seeds);
  }

  void _advanceBeam(
    ({double headingDeg, double distanceM, PdrLocalPoint rawPoint}) segment,
  ) {
    final observed = normalizeBearing(segment.headingDeg + _headingBiasDeg);
    final next = <Hypothesis>[];
    for (final hypothesis in _beam) {
      next.addAll(
        _advance(hypothesis, observed, segment.distanceM, segment.rawPoint),
      );
      // 복도 한가운데서 되돌아오는 경우, 노드를 거치지 않으므로 전이만으로는
      // 표현되지 않는다. 관측이 진행 방향과 크게 어긋날 때만 반대 부호 가설을
      // 함께 만들어 비용이 판정하게 한다.
      final currentBearing = hypothesis.edge.bearingForTravel(
        hypothesis.progressM,
        hypothesis.travelSign,
      );
      if (hypothesis.edge.bidirectional &&
          headingError(observed, currentBearing) >= config.reverseTriggerDeg) {
        next.addAll(
          _advance(
            hypothesis.reversed(),
            observed,
            segment.distanceM,
            segment.rawPoint,
          ),
        );
      }
    }
    if (next.isEmpty) return;
    _beam = _prune(next);
  }

  List<Hypothesis> _advance(
    Hypothesis hypothesis,
    double observedHeadingDeg,
    double remainingM,
    PdrLocalPoint rawPoint, {
    int depth = 0,
  }) {
    if (remainingM <= 1e-6) return [hypothesis];
    final edge = hypothesis.edge;
    final distanceToEnd = hypothesis.travelSign > 0
        ? edge.lengthM - hypothesis.progressM
        : hypothesis.progressM;
    final appliedM = math.min(remainingM, distanceToEnd);
    final graphHeading = edge.bearingForTravel(
      hypothesis.progressM,
      hypothesis.travelSign,
    );
    final advanced = hypothesis.advance(
      observedHeadingDeg: observedHeadingDeg,
      graphHeadingDeg: graphHeading,
      distanceM: appliedM,
      absoluteWeight: config.absoluteErrorWeight,
      maxSegmentErrorDeg: config.maxSegmentErrorDeg,
      rawPoint: rawPoint,
      positionalWeightDegPerM: config.positionalWeightDegPerM,
      positionalToleranceM: config.positionalToleranceM,
      positionalMaxOffsetM: config.positionalMaxOffsetM,
      maxPathPoints: config.maxPathPoints,
      costHorizonM: config.costHorizonM,
      offEdgeSlackLimitM: config.junctionZoneRadiusM,
    );
    if (remainingM <= distanceToEnd + 1e-6) {
      // 노드를 아직 넘지 않았다. 여기서 끝내면 회전 후보는 노드를 지난 뒤에야
      // 열리고, 그 사이 걸음이 전부 직진 가설에만 쌓인다. 전환 구간 안이면
      // **연결된** 간선 후보를 미리·아직 열어 둔다.
      final alternatives = depth == 0
          ? _junctionAlternatives(advanced, observedHeadingDeg, rawPoint)
          : const <Hypothesis>[];
      return alternatives.isEmpty ? [advanced] : [advanced, ...alternatives];
    }

    final leftoverM = remainingM - appliedM;
    final nodeId = edge.nodeAtTravelEnd(hypothesis.travelSign);
    if (_lockPreferredRouteTerminal &&
        _isPreferredRouteTerminalHypothesis(hypothesis) &&
        nodeId == _preferredRouteNodeIds.last) {
      // 정확한 탑승 종점에 도달한 뒤 들어오는 걸음은 다른 복도나 역방향
      // 간선으로 넘기지 않는다. 거리는 unmatched로 계속 소비하므로 preview
      // 적산을 잃지 않고, 세션의 탑승 고정/이탈 판정이 이어받을 수 있다.
      return [advanced.withDeadEnd(leftoverM, 0)];
    }
    final node = _network.nodes[nodeId];
    if (node == null || depth >= config.maxTransitionsPerSegment) {
      return [advanced.withDeadEnd(leftoverM, config.deadEndPenaltyDeg)];
    }
    // 같은 간선으로 되돌아가는 선택지도 남긴다. 막다른 복도 끝에서 유턴하는
    // 것은 정상적인 보행이고, 이걸 빼면 그 지점에서 가설이 전멸한다.
    final options = _network.recoveryOptionsFromNode(nodeId);
    if (options.isEmpty) {
      return [advanced.withDeadEnd(leftoverM, config.deadEndPenaltyDeg)];
    }
    final branched = <Hypothesis>[];
    for (final option in options) {
      branched.addAll(
        _advance(
          advanced.enter(
            option,
            nodeId: nodeId,
            nodePoint: node.point,
            rawPoint: rawPoint,
            penaltyDegM: config.transitionPenaltyDegM,
          ),
          observedHeadingDeg,
          leftoverM,
          rawPoint,
          depth: depth + 1,
        ),
      );
    }
    return branched;
  }

  /// 전환 구간 안에서 열어 둘 회전 가설.
  ///
  /// 두 방향 모두 같은 규칙이다.
  ///
  /// - **빠른 회전**: 진행 방향 끝 노드까지 반경 안이면, 아직 노드를 밟지
  ///   않았어도 연결된 outgoing 후보를 만든다.
  /// - **늦은 회전**: 방금 지나온 노드에서 반경 안이면, 그 노드의 다른 연결
  ///   간선 후보를 아직 살려 둔다.
  ///
  /// 두 경우 모두 위치가 노드까지 [건너뛴] 거리에 비례해 벌점을 물고, 관측
  /// 방향이 그쪽을 실제로 지지할 때만 만들어진다. 걸음이 없으면 이 함수 자체가
  /// 호출되지 않으므로(제자리 heading 회전은 [_advance]로 들어오지 않는다)
  /// 휴대폰만 돌려서 간선이 바뀌는 일은 없다.
  List<Hypothesis> _junctionAlternatives(
    Hypothesis advanced,
    double observedHeadingDeg,
    PdrLocalPoint rawPoint,
  ) {
    final edge = advanced.edge;
    final endNodeId = edge.nodeAtTravelEnd(advanced.travelSign);
    final startNodeId = edge.nodeAtTravelEnd(-advanced.travelSign);
    final distanceToEndM = advanced.travelSign > 0
        ? edge.lengthM - advanced.progressM
        : advanced.progressM;
    final distanceFromStartM = edge.lengthM - distanceToEndM;
    final currentBearing = edge.bearingForTravel(
      advanced.progressM,
      advanced.travelSign,
    );

    final alternatives = <Hypothesis>[];
    void openAt(String nodeId, double rawSkipM, {required bool ahead}) {
      // 회전 중에는 이 간선을 따라 걷고 있지 않다. 그 구간만큼 창을 되돌린다.
      final skipM = math.max(0.0, rawSkipM - advanced.offEdgeDistanceM);
      if (skipM <= 1e-6 || skipM > _junctionZoneRadiusM(edge)) return;
      if (!_network.isDirectionDecisionNode(edge, nodeId)) return;
      final node = _network.nodes[nodeId];
      if (node == null) return;
      for (final option in _network.recoveryOptionsFromNode(nodeId)) {
        if (option.edge.id == edge.id) continue;
        if (skipM > _junctionZoneRadiusM(option.edge)) continue;
        // 보통은 관측이 지금 간선보다 이쪽을 더 잘 설명할 때만 후보를 연다.
        // 다만 활성 경로의 **정확한 다음 간선**은 후보만 살린다. graph 꼭짓점을
        // 잘라 걷는 동안 센서 방향이 늦게 돌아도 경로 가설 자체를 잃지 않는다.
        final preferred = _isPreferredForwardTransition(
          edgeId: edge.id,
          nodeId: nodeId,
          optionEdgeId: option.edge.id,
        );
        if (!preferred &&
            headingError(observedHeadingDeg, option.bearingDeg) >=
                headingError(observedHeadingDeg, currentBearing)) {
          continue;
        }
        alternatives.add(
          advanced.enter(
            option,
            nodeId: nodeId,
            nodePoint: node.point,
            rawPoint: rawPoint,
            penaltyDegM:
                config.transitionPenaltyDegM +
                skipM * config.junctionShortcutPenaltyDegM,
            turnedGraphHeadingDeg: option.bearingDeg,
            approachPath: ahead
                ? edge.pointsBetween(
                    advanced.progressM,
                    advanced.travelSign > 0 ? edge.lengthM : 0,
                  )
                : const [],
            trimTailM: ahead ? 0 : rawSkipM,
          ),
        );
      }
    }

    openAt(endNodeId, distanceToEndM, ahead: true);
    // 지나온 쪽은 **방금 그 노드를 통해 들어온 가설**만 되돌린다. 그러지 않으면
    // 모든 간선의 시작 노드가 항상 후보를 열어 빔이 분기로 가득 찬다.
    if (advanced.lastNodeId == startNodeId) {
      openAt(startNodeId, distanceFromStartM, ahead: false);
    }
    return alternatives;
  }

  bool _isPreferredForwardTransition({
    required String edgeId,
    required String nodeId,
    required String optionEdgeId,
  }) {
    for (var index = 0; index < _preferredRouteEdgeIds.length - 1; index++) {
      if (_preferredRouteEdgeIds[index] == edgeId &&
          _preferredRouteNodeIds[index + 1] == nodeId &&
          _preferredRouteEdgeIds[index + 1] == optionEdgeId) {
        return true;
      }
    }
    return false;
  }

  /// 표시 중인 가설이 전환 구간 안이고 도전자가 그 node에 **연결된** 간선인가.
  ///
  /// 여기서만 1등 교체 관성을 줄인다. 연결되지 않은 평행 간선은 아무리 가까워도
  /// 이 조건을 통과하지 못한다.
  bool _isJunctionTurn(Hypothesis held, Hypothesis challenger) {
    if (held.edge.id == challenger.edge.id) return false;
    final junction = _network.nearestJunctionOn(
      held.edge,
      held.edge.pointAt(held.progressM),
      maxDistanceM: _junctionZoneRadiusM(held.edge) + held.offEdgeDistanceM,
    );
    if (junction == null) return false;
    return _network
        .recoveryOptionsFromNode(junction.node.id)
        .any((option) => option.edge.id == challenger.edge.id);
  }

  /// 이 간선에서 쓸 전환 구간 반경. 짧은 간선을 통째로 삼키지 않게 제한한다.
  double _junctionZoneRadiusM(CorridorEdge edge) => math.min(
    config.junctionZoneRadiusM,
    edge.lengthM * config.junctionZoneEdgeLengthRatio,
  );

  /// 지금 표시 위치가 어느 전환 구간 안인지 갱신한다. 재탐색 유예의 근거다.
  void _updateJunctionState() {
    final leader = _optimisticBest ?? _best;
    if (leader == null) {
      _junctionNodeId = null;
      _junctionDistanceM = double.infinity;
      _junctionCandidateEdgeIds = const [];
      return;
    }
    final junction = _network.nearestJunctionOn(
      leader.edge,
      leader.edge.pointAt(leader.progressM),
      // 회전 중 진행한 거리는 창에서 빼 준다. `_junctionAlternatives`가 후보를
      // 열어 두는 구간과 재탐색을 유예하는 구간이 어긋나면 안 된다.
      maxDistanceM: _junctionZoneRadiusM(leader.edge) + leader.offEdgeDistanceM,
    );
    if (junction == null) {
      _junctionNodeId = null;
      _junctionDistanceM = double.infinity;
      _junctionCandidateEdgeIds = const [];
      return;
    }
    _junctionNodeId = junction.node.id;
    _junctionDistanceM = junction.distanceM;
    _junctionCandidateEdgeIds = [
      for (final option in _network.recoveryOptionsFromNode(junction.node.id))
        option.edge.id,
    ];
  }

  /// 같은 자리에 몰린 가설을 합치고 상위 [CorridorTrackerConfig.beamWidth]만 남긴다.
  ///
  /// 합치지 않으면 빔이 "같은 간선 위 1cm 차이" 복제본으로 가득 차서, 정작
  /// 다른 복도에 있는 정답 가설이 밀려난다.
  List<Hypothesis> _prune(List<Hypothesis> candidates) {
    final best = <String, Hypothesis>{};
    for (final candidate in candidates) {
      final bucket = (candidate.progressM / config.progressBucketM).round();
      final key = '${candidate.edge.id}|${candidate.travelSign}|$bucket';
      final existing = best[key];
      if (existing == null || candidate.meanErrorDeg < existing.meanErrorDeg) {
        best[key] = candidate;
      }
    }
    final sorted = best.values.toList(growable: false)
      ..sort((left, right) => left.meanErrorDeg.compareTo(right.meanErrorDeg));
    return sorted.take(config.beamWidth).toList(growable: false);
  }

  /// 표시용 1등을 고른다. 근소한 점수 차로 화면이 복도 사이를 오가지 않게,
  /// 지금 보여 주고 있는 간선을 [CorridorTrackerConfig.leaderSwitchMarginDeg]
  /// 만큼 이겨야 넘겨준다.
  ///
  /// 1등이 노드를 넘어가면 이전 간선의 가설은 빔에서 사라지므로 자연히 새
  /// 간선으로 넘어간다 — 그 전환은 붙어 있는 간선이라 위치가 튀지 않는다.
  void _electLeader() {
    if (_beam.isEmpty) return;
    final observed = normalizeBearing(
      (_lastConfirmedSegmentHeadingDeg ?? _sensorHeadingDeg) + _headingBiasDeg,
    );
    final globalBest = _preferredLeader(_beam, observedHeadingDeg: observed);
    final heldId = _leaderEdgeId;
    if (heldId == null) {
      _leaderEdgeId = globalBest.edge.id;
      _leaderSign = globalBest.travelSign;
      _putLeaderFirst(globalBest);
      return;
    }
    Hypothesis? held;
    for (final hypothesis in _beam) {
      if (hypothesis.edge.id == heldId &&
          hypothesis.travelSign == _leaderSign) {
        held = hypothesis;
        break;
      }
    }
    final marginDeg = held != null && _isJunctionTurn(held, globalBest)
        ? config.junctionLeaderSwitchMarginDeg
        : config.leaderSwitchMarginDeg;
    if (held == null ||
        globalBest.meanErrorDeg < held.meanErrorDeg - marginDeg) {
      _leaderEdgeId = globalBest.edge.id;
      _leaderSign = globalBest.travelSign;
      _putLeaderFirst(globalBest);
      return;
    }
    _putLeaderFirst(held);
  }

  /// 경로 prior는 간선 ID만 보지 않고 저장 방향까지 맞아야 한다. 같은 복도를
  /// 반대로 걷는 가설까지 우대하면 실제 유턴을 경로 진행으로 오인한다.
  bool _isPreferredRouteHypothesis(Hypothesis hypothesis) {
    return _preferredRouteIndex(hypothesis) != null;
  }

  int? _preferredRouteIndex(Hypothesis hypothesis) {
    for (var index = 0; index < _preferredRouteEdgeIds.length; index++) {
      if (_preferredRouteEdgeIds[index] != hypothesis.edge.id) continue;
      final fromNodeId = _preferredRouteNodeIds[index];
      final toNodeId = _preferredRouteNodeIds[index + 1];
      final expectedSign =
          hypothesis.edge.fromNodeId == fromNodeId &&
              hypothesis.edge.toNodeId == toNodeId
          ? 1
          : hypothesis.edge.fromNodeId == toNodeId &&
                hypothesis.edge.toNodeId == fromNodeId
          ? -1
          : 0;
      if (expectedSign == hypothesis.travelSign) return index;
    }
    return null;
  }

  bool _isPreferredRouteTerminalHypothesis(Hypothesis hypothesis) {
    if (_preferredRouteEdgeIds.isEmpty) return false;
    final lastIndex = _preferredRouteEdgeIds.length - 1;
    if (_preferredRouteEdgeIds[lastIndex] != hypothesis.edge.id) return false;
    final fromNodeId = _preferredRouteNodeIds[lastIndex];
    final toNodeId = _preferredRouteNodeIds[lastIndex + 1];
    final expectedSign =
        hypothesis.edge.fromNodeId == fromNodeId &&
            hypothesis.edge.toNodeId == toNodeId
        ? 1
        : hypothesis.edge.fromNodeId == toNodeId &&
              hypothesis.edge.toNodeId == fromNodeId
        ? -1
        : 0;
    return expectedSign == hypothesis.travelSign;
  }

  /// 평소에는 작은 점수 여유 안에서만 경로 가설을 우대한다. 정확한 에스컬레이터
  /// 탑승 접근 중에는 raw 걸음 거리는 그대로 쓰면서 연결된 경로 간선 열을
  /// 유지한다. 단, 관측이 경로 진행 방향과 [CorridorTrackerConfig.reverseTriggerDeg]
  /// 이상 반대면 실제 유턴일 수 있으므로 강한 우대를 해제한다. 정확한 탑승점
  /// 근처에서 terminal lock이 열렸다면 몸을 발판 방향으로 돌리는 동작이므로 이
  /// 각도 탈출구보다 마지막 경로 간선을 우선한다.
  Hypothesis _preferredLeader(
    List<Hypothesis> beam, {
    required double observedHeadingDeg,
  }) {
    final globalBest = beam.first;
    if (_isPreferredRouteHypothesis(globalBest)) return globalBest;
    final routeBest = _lockPreferredRouteTerminal
        ? beam.where(_isPreferredRouteTerminalHypothesis).firstOrNull ??
              beam.where(_isPreferredRouteHypothesis).firstOrNull
        : beam.where(_isPreferredRouteHypothesis).firstOrNull;
    if (routeBest == null) return globalBest;
    if (_lockPreferredRouteTerminal) return routeBest;
    if (_preferRouteContinuity) {
      final routeBearing = routeBest.edge.bearingForTravel(
        routeBest.progressM,
        routeBest.travelSign,
      );
      if (headingError(observedHeadingDeg, routeBearing) <
          config.reverseTriggerDeg) {
        return routeBest;
      }
    }
    return routeBest.meanErrorDeg <=
            globalBest.meanErrorDeg + config.routePreferenceMarginDeg
        ? routeBest
        : globalBest;
  }

  void _putLeaderFirst(Hypothesis leader) {
    if (identical(_beam.first, leader)) return;
    _beam = [
      leader,
      ..._beam.where((hypothesis) => !identical(hypothesis, leader)),
    ];
  }

  void _publishConfirmed({required int transitionsBefore}) {
    _electLeader();
    final best = _best;
    if (best == null) return;
    _correctedPosition = best.edge.pointAt(best.progressM);
    // 1등 가설이 **자기 이력 전체**를 들고 있으므로 그대로 쓴다.
    //
    // 예전에는 윈도우 밖을 따로 커밋해 두고 `커밋분 + 현재 윈도우`로 이어
    // 붙였는데, 1등이 바뀌면 두 조각이 서로 다른 복도에 있어서 이음매가
    // 지도를 가로지르는 직선으로 그려졌다(실측에서 29점 중 21구간이 2m 초과
    // 점프, 합계 102.5m). 한 가설의 경로는 정의상 그래프를 따라가므로
    // 이음매가 없다. 서로 수렴한 가설은 _prune이 합치면서 옛 갈래를 지운다.
    _correctedPath
      ..clear()
      ..addAll(best.path);
    _lastConfirmedNodeId = best.lastNodeId;

    final runnerUp = _beam.length > 1 ? _beam[1] : null;
    final ambiguous =
        runnerUp != null &&
        runnerUp.edge.id != best.edge.id &&
        runnerUp.meanErrorDeg - best.meanErrorDeg < config.ambiguousMarginDeg;
    _pendingEdgeId = ambiguous ? runnerUp.edge.id : null;
    if (best.unmatchedM > 0.5) {
      _state = CorridorTrackingState.uncertain;
    } else if (best.transitions > transitionsBefore) {
      _state = CorridorTrackingState.nodeConfirmed;
    } else if (ambiguous) {
      _state = CorridorTrackingState.turnPending;
    } else {
      _state = CorridorTrackingState.straightTracking;
    }
  }

  /// 연결된 다음 **경로 간선** 위 전진이 충분히 확인된 뒤 새 직선 epoch를 연다.
  ///
  /// node에 닿자마자 열지 않는다. 코너를 안쪽으로 자른 후보와 한 번의 큰 배치가
  /// 잠깐 1등이 된 경우까지 확정해 버리기 때문이다. 반대로 이 시점을 통과하면
  /// 이전 간선의 회전·방위 비용은 더 이상 현재 직선의 순위를 눌러서는 안 된다.
  void _beginRouteStraightEpochIfReady() {
    final best = _best;
    if (best == null || best.unmatchedM > 0.5) return;
    final routeIndex = _preferredRouteIndex(best);
    if (routeIndex == null ||
        routeIndex <= 0 ||
        routeIndex <= _lastRouteStraightEpochIndex) {
      return;
    }
    final entryNodeId = _preferredRouteNodeIds[routeIndex];
    if (best.lastNodeId != entryNodeId) return;
    final progressFromEntryM = best.travelSign > 0
        ? best.progressM
        : best.edge.lengthM - best.progressM;
    if (progressFromEntryM + 1e-6 < config.routeStraightEpochMinProgressM) {
      return;
    }

    // 같은 간선의 반대 방향까지 포함해 근소한 경쟁자가 남아 있으면 아직 새
    // 기준으로 삼지 않는다. 경로 prior가 1등을 표시했다는 사실만으로는 부족하다.
    for (final candidate in _beam) {
      if (identical(candidate, best) ||
          _preferredRouteIndex(candidate) == routeIndex) {
        continue;
      }
      if (candidate.meanErrorDeg - best.meanErrorDeg <
          config.ambiguousMarginDeg) {
        return;
      }
    }

    final committed = [
      for (final candidate in _beam)
        if (_preferredRouteIndex(candidate) == routeIndex &&
            candidate.lastNodeId == entryNodeId)
          candidate.beginStraightEpoch(rawPoint: _rawConfirmedPosition),
    ];
    if (committed.isEmpty) return;
    _beam = _prune(committed);
    _leaderEdgeId = best.edge.id;
    _leaderSign = best.travelSign;
    _electLeader();

    // 화면 cursor는 되감지 않는다. optimistic 후보들의 현재 위치·path·누적
    // 선행 거리는 그대로 두고 같은 점수 epoch만 연다. 다음 확정 reconcile이
    // 연결성을 판정하므로 여기서 경로 후보만 남기는 강제 잠금은 하지 않는다.
    if (_optimisticBeam.isNotEmpty) {
      _optimisticBeam = _prune([
        for (final candidate in _optimisticBeam)
          candidate.beginStraightEpoch(rawPoint: _rawPreviewPosition),
      ]);
      _electOptimisticLeader(
        observedHeadingDeg: normalizeBearing(
          (_lastConfirmedSegmentHeadingDeg ?? _sensorHeadingDeg) +
              _headingBiasDeg,
        ),
      );
    }

    final committedBest = _best!;
    _correctedPosition = committedBest.edge.pointAt(committedBest.progressM);
    _correctedPath
      ..clear()
      ..addAll(committedBest.path);
    _lastConfirmedNodeId = committedBest.lastNodeId;
    _pendingEdgeId = null;
    _state = CorridorTrackingState.straightTracking;
    _lastRouteStraightEpochIndex = routeIndex;
    _routeStraightEpochNodeId = entryNodeId;
  }

  /// 1등 가설이 뚜렷할 때만 heading bias를 조금씩 복도 방향으로 당긴다.
  void _updateHeadingBias() {
    final best = _best;
    if (best == null || best.unmatchedM > 0.5) return;
    final target = best.edge.bearingForTravel(best.progressM, best.travelSign);
    final corrected = normalizeBearing(_sensorHeadingDeg + _headingBiasDeg);
    final requested = shortestDelta(target - corrected);
    if (requested.abs() > config.headingBiasMaxErrorDeg) return;
    final maxCorrection = config.maxHeadingCorrectionPerStepDeg;
    _headingBiasDeg = _clampSigned(
      _headingBiasDeg + requested.clamp(-maxCorrection, maxCorrection),
      config.headingBiasLimitDeg,
    );
  }

  List<({double headingDeg, double distanceM, PdrLocalPoint rawPoint})>
  _rawSegments({
    required int deltaSteps,
    required double deltaDistanceM,
    required PdrLocalPoint previousRawConfirmedPosition,
    required List<PdrLocalPoint> rawConfirmedStepPositions,
  }) {
    final rawSegments =
        <({double headingDeg, double distanceM, PdrLocalPoint rawPoint})>[];
    var rawCursor = previousRawConfirmedPosition;
    var rawTotalM = 0.0;
    for (final rawPoint in rawConfirmedStepPositions) {
      final movement = rawPoint - rawCursor;
      rawCursor = rawPoint;
      if (movement.distance <= 1e-6) continue;
      rawSegments.add((
        headingDeg: pdrBearingForDirection(movement),
        distanceM: movement.distance,
        rawPoint: rawPoint,
      ));
      rawTotalM += movement.distance;
    }
    if (rawSegments.isEmpty || rawTotalM <= 1e-6) {
      final fallbackSteps = math.max(1, deltaSteps);
      return [
        for (var index = 0; index < fallbackSteps; index += 1)
          (
            headingDeg: _sensorHeadingDeg,
            distanceM: deltaDistanceM / fallbackSteps,
            rawPoint: _rawConfirmedPosition,
          ),
      ];
    }
    final distanceScale = deltaDistanceM / rawTotalM;
    return [
      for (final segment in rawSegments)
        (
          headingDeg: segment.headingDeg,
          distanceM: segment.distanceM * distanceScale,
          rawPoint: segment.rawPoint,
        ),
    ];
  }

  // ── optimistic preview cursor ──

  /// 확정 1등이 optimistic cursor와 더 이상 같은 길 위에 있지 않을 때만
  /// 화면 cursor를 재배치한다.
  ///
  /// 배치 수신 자체는 marker 이동 이벤트가 아니다. 확정 빔이 optimistic cursor를
  /// 그래프로 따라잡을 수 있는 한(같은 간선이거나 앞으로 연결된 간선), cursor는
  /// 그대로 둔다 — 그게 "배치가 와도 뒤로 가지 않는다"의 구현이다.
  void _reconcileOptimistic(int? confirmedThroughMs) {
    final best = _best;
    if (best == null) {
      _optimisticBeam = const [];
      return;
    }
    final leader = _optimisticBest;
    if (leader == null) {
      _rebaseOptimistic(best);
      return;
    }
    if (leader.edge.id == best.edge.id &&
        leader.travelSign == best.travelSign) {
      return;
    }
    if (_network.isForwardReachable(
      fromEdge: best.edge,
      travelSign: best.travelSign,
      progressM: best.progressM,
      targetEdgeId: leader.edge.id,
      maxDistanceM: _optimisticLeadM + config.optimisticReconcileMarginM,
    )) {
      return;
    }
    // preview가 아직 몇 걸음 앞서 있는데 배치가 일부 peak만
    // 확정했다고 그 선행분을 한번에 폐기하지 않는다. 확정 cursor가
    // 따라잡은 뒤 재배치하면 보정은 유지하면서 뒤점프만 제한된다.
    if (_optimisticLeadM > config.optimisticRelocationMaxLeadM) {
      return;
    }
    // 그래프로 설명되지 않는 1등 교체. 화면을 옛 복도에 남겨 두면 그때부터
    // 모든 갱신이 틀린 자리에서 시작한다. 확정 lineage로 바꾸되,
    // 아직 확정되지 않은 주황 peak는 새 lineage 위에 다시 올려 선행
    // 거리를 버리지 않는다. 그냥 rebase만 하면 배치가 올 때마다
    // marker가 확정점으로 몇 m씩 뒤로 튀었다.
    _leaderRelocated = true;
    _rebaseOptimistic(best);
    _releasePendingPeakIds(confirmedThroughMs);
  }

  void _rebaseOptimistic(Hypothesis confirmedLeader) {
    _optimisticBeam = [confirmedLeader.forPreview()];
    _optimisticLeaderEdgeId = confirmedLeader.edge.id;
    _optimisticLeaderSign = confirmedLeader.travelSign;
    _optimisticTraveledM = _confirmedTraveledM;
  }

  /// 아직 태우지 않은 preview peak만 시간순으로 한 번 적용한다.
  void _applyPreviewPeaks(CorridorObservation observation) {
    if (observation.hasSyntheticPreviewPeakIds) {
      _previewPeakIdsSynthetic = true;
    }
    var origin = observation.previewTailOriginM;
    if (origin == null) return;
    for (final step in observation.timedPreviewSteps) {
      final previous = origin!;
      origin = step.rawPoint;
      if (!_rememberPreviewPeak(step.peakId)) continue;
      final movement = step.rawPoint - previous;
      if (movement.distance <= 1e-6) continue;
      _advanceOptimistic(
        headingDeg: pdrBearingForDirection(movement),
        distanceM: movement.distance,
        rawPoint: step.rawPoint,
        peakId: step.peakId,
        occurredAtMs: step.occurredAtMs ?? observation.timestampMs,
      );
      _optimisticTraveledM += movement.distance;
    }
  }

  /// preview로 한 번도 보이지 않고 배치로만 들어온 걸음을 태운다.
  ///
  /// 두 beam이 같은 걸음을 두 번 먹지 않으면서도, optimistic cursor가 확정보다
  /// 뒤에 남는 일은 없어야 한다. 차이는 항상 "preview가 놓친 걸음"이다.
  void _catchUpOptimisticToConfirmed() {
    final deficitM = _confirmedTraveledM - _optimisticTraveledM;
    if (deficitM <= 1e-6) return;
    final best = _best;
    if (best == null) return;
    if (_optimisticBeam.isEmpty) _rebaseOptimistic(best);
    // 확정 간선의 방위가 아니라 **관측 방향**을 쓴다. 간선 방위를 넣으면
    // optimistic beam이 확정 1등의 선택을 그대로 베끼게 되어, 회전을 스스로
    // 발견할 수 없다(관측이 항상 지금 간선과 일치하는 것처럼 보인다).
    _advanceOptimistic(
      headingDeg: _lastConfirmedSegmentHeadingDeg ?? _sensorHeadingDeg,
      distanceM: deficitM,
      rawPoint: _rawConfirmedPosition,
    );
    _optimisticTraveledM = _confirmedTraveledM;
  }

  void _advanceOptimistic({
    required double headingDeg,
    required double distanceM,
    required PdrLocalPoint rawPoint,
    int? peakId,
    int? occurredAtMs,
  }) {
    if (_optimisticBeam.isEmpty) return;
    final previousLeaderId = _optimisticBest!.diagnosticId;
    final observed = normalizeBearing(headingDeg + _headingBiasDeg);
    final next = <Hypothesis>[];
    for (final original in _optimisticBeam) {
      final hypothesis = original.beginStep();
      next.addAll(_advance(hypothesis, observed, distanceM, rawPoint));
      // 실제 유턴은 반영한다. 반대 부호 가설을 함께 만들어 두면 비용이
      // 판정하고, 이길 경우 cursor가 뒤로 가는 것도 허용된다.
      final currentBearing = hypothesis.edge.bearingForTravel(
        hypothesis.progressM,
        hypothesis.travelSign,
      );
      if (hypothesis.edge.bidirectional &&
          headingError(observed, currentBearing) >= config.reverseTriggerDeg) {
        next.addAll(
          _advance(hypothesis.reversed(), observed, distanceM, rawPoint),
        );
      }
    }
    if (next.isEmpty) return;
    _optimisticBeam = _prune(next);
    _electOptimisticLeader(observedHeadingDeg: observed);
    final leader = _optimisticBest!;
    if (peakId != null && occurredAtMs != null) {
      final runnerUp = _optimisticBeam.length > 1 ? _optimisticBeam[1] : null;
      final previewIsAmbiguous =
          runnerUp != null &&
          runnerUp.edge.id != leader.edge.id &&
          runnerUp.meanErrorDeg - leader.meanErrorDeg <
              config.ambiguousMarginDeg;
      final traversals = List<OptimisticEdgeTraversal>.unmodifiable(
        leader.stepTraversals,
      );
      _optimisticStepAdvances.add(
        OptimisticStepAdvance(
          peakId: peakId,
          occurredAtMs: occurredAtMs,
          hypothesisId: leader.diagnosticId,
          parentHypothesisId: leader.stepParentHypothesisId ?? previousLeaderId,
          distanceM: traversals.fold(0, (sum, item) => sum + item.distanceM),
          edgeId: leader.edge.id,
          mapMatchedHeadingDeg: leader.edge.bearingForTravel(
            leader.progressM,
            leader.travelSign,
          ),
          previewIsAmbiguous: previewIsAmbiguous,
          position: leader.edge.pointAt(leader.progressM),
          traversals: traversals,
          crossedNodeIds: List<String>.unmodifiable(leader.stepCrossedNodeIds),
          leaderRelocated:
              _leaderRelocated ||
              leader.stepParentHypothesisId != previousLeaderId,
        ),
      );
    }
  }

  /// 주황 preview도 확정 빔과 같은 1등 교체 관성을 가진다.
  ///
  /// 예전에는 `_prune(next).first`를 바로 화면에 내보내서 코너의 1·2등 점수가
  /// 근소하게 바뀔 때마다 진입 간선과 진출 간선을 왕복했다. 연결된 코너에서는
  /// 작은 관성만, 떨어진 간선·반대 방향에는 평시 관성을 써 실제 회전과 이탈은
  /// 계속 허용한다.
  void _electOptimisticLeader({required double observedHeadingDeg}) {
    if (_optimisticBeam.isEmpty) return;
    final globalBest = _preferredLeader(
      _optimisticBeam,
      observedHeadingDeg: observedHeadingDeg,
    );

    final heldEdgeId = _optimisticLeaderEdgeId;
    if (heldEdgeId == null) {
      _optimisticLeaderEdgeId = globalBest.edge.id;
      _optimisticLeaderSign = globalBest.travelSign;
      _putOptimisticLeaderFirst(globalBest);
      return;
    }
    final held = _optimisticBeam
        .where(
          (hypothesis) =>
              hypothesis.edge.id == heldEdgeId &&
              hypothesis.travelSign == _optimisticLeaderSign,
        )
        .firstOrNull;
    final marginDeg = held != null && _isJunctionTurn(held, globalBest)
        ? config.junctionLeaderSwitchMarginDeg
        : config.leaderSwitchMarginDeg;
    if (held == null ||
        globalBest.meanErrorDeg < held.meanErrorDeg - marginDeg) {
      _optimisticLeaderEdgeId = globalBest.edge.id;
      _optimisticLeaderSign = globalBest.travelSign;
      _putOptimisticLeaderFirst(globalBest);
      return;
    }
    _putOptimisticLeaderFirst(held);
  }

  void _putOptimisticLeaderFirst(Hypothesis leader) {
    if (identical(_optimisticBeam.first, leader)) return;
    _optimisticBeam = [
      leader,
      ..._optimisticBeam.where((hypothesis) => !identical(hypothesis, leader)),
    ];
  }

  /// 처음 보는 peak면 기억하고 true. 이미 태운 peak면 false.
  bool _rememberPreviewPeak(int peakId) {
    if (!_appliedPreviewPeakIdSet.add(peakId)) return false;
    _appliedPreviewPeakIds.add(peakId);
    while (_appliedPreviewPeakIds.length > config.maxTrackedPreviewPeaks) {
      _appliedPreviewPeakIdSet.remove(_appliedPreviewPeakIds.removeAt(0));
    }
    return true;
  }

  /// 확정 시간창을 지난 식별자는 다시 tail에 나타나지 않으므로 잊는다.
  void _forgetAcknowledgedPeakIds(int? confirmedThroughMs) {
    if (confirmedThroughMs == null) return;
    while (_appliedPreviewPeakIds.isNotEmpty) {
      final oldest = _appliedPreviewPeakIds.first;
      // 합성 식별자(음수)는 시각 축이 아니므로 개수 상한으로만 관리한다.
      if (oldest < 0 || oldest > confirmedThroughMs) break;
      _appliedPreviewPeakIdSet.remove(_appliedPreviewPeakIds.removeAt(0));
    }
  }

  /// lineage 재해석 후 현재 tail에 남은 preview peak를 다시 태운다.
  ///
  /// 실제 시각 ID는 확정 배치 끝 이후분만 풀고, 시각이 없는 예전
  /// snapshot의 합성 ID는 tail 자체가 pending 범위이므로 모두 풀어 준다.
  void _releasePendingPeakIds(int? confirmedThroughMs) {
    _appliedPreviewPeakIds.removeWhere((peakId) {
      final pending =
          peakId < 0 ||
          confirmedThroughMs == null ||
          peakId > confirmedThroughMs;
      if (pending) _appliedPreviewPeakIdSet.remove(peakId);
      return pending;
    });
  }

  void _publishPreview() {
    final leader = _optimisticBest;
    if (leader == null) {
      _resetPreviewToConfirmed();
      return;
    }
    final runnerUp = _optimisticBeam.length > 1 ? _optimisticBeam[1] : null;
    // 모호 판정에 히스테리시스를 준다. 단일 임계값을 쓰면 점수가 그 근처에서
    // 오갈 때마다 후보 목록이 프레임마다 뒤집힌다.
    final gapDeg = runnerUp == null || runnerUp.edge.id == leader.edge.id
        ? double.infinity
        : runnerUp.meanErrorDeg - leader.meanErrorDeg;
    final exitThreshold = config.ambiguousMarginDeg * 2;
    _previewIsAmbiguous = _previewIsAmbiguous
        ? gapDeg < exitThreshold
        : gapDeg < config.ambiguousMarginDeg;

    _previewPosition = leader.edge.pointAt(leader.progressM);
    _previewHeadingDeg = leader.edge.bearingForTravel(
      leader.progressM,
      leader.travelSign,
    );
    // 표시 경로는 확정 위치에서 optimistic cursor까지의 **선행분**이다.
    // 선행분을 별도 scalar로 안정화하지 않고 두 누적 거리의 차이로 정의하므로,
    // 배치가 확인만 하고 지나가는 프레임에서는 값이 그대로 유지된다.
    final tail = _takeLastLength(leader.path, _optimisticLeadM);
    _previewPath
      ..clear()
      ..addAll(tail.isEmpty ? [_previewPosition] : tail);
    final seen = <String>{};
    _previewCandidateEdgeIds = [
      for (final candidate in _optimisticBeam)
        if (seen.add(candidate.edge.id)) candidate.edge.id,
    ];
  }

  /// 경로 **끝에서부터** [lengthM]만큼만 남긴다. 첫 점은 정확히 그 지점이다.
  static List<PdrLocalPoint> _takeLastLength(
    List<PdrLocalPoint> path,
    double lengthM,
  ) {
    if (path.isEmpty) return const [];
    if (lengthM <= 1e-9) return [path.last];
    final tail = <PdrLocalPoint>[path.last];
    var remaining = lengthM;
    for (var index = path.length - 1; index >= 1; index -= 1) {
      final step = (path[index] - path[index - 1]).distance;
      if (step <= 1e-9) continue;
      if (remaining >= step) {
        tail.add(path[index - 1]);
        remaining -= step;
        continue;
      }
      if (remaining > 1e-6) {
        final t = remaining / step;
        tail.add(
          PdrLocalPoint(
            path[index].eastM + (path[index - 1].eastM - path[index].eastM) * t,
            path[index].northM +
                (path[index - 1].northM - path[index].northM) * t,
          ),
        );
      }
      break;
    }
    return tail.reversed.toList(growable: false);
  }

  void _resetPreviewToConfirmed() {
    _previewPosition = _correctedPosition;
    _previewHeadingDeg = result.correctedHeadingDeg;
    _previewPath
      ..clear()
      ..add(_correctedPosition);
    _previewCandidateEdgeIds = const [];
    _previewIsAmbiguous = false;
    final best = _best;
    if (best != null) {
      _rebaseOptimistic(best);
    } else {
      _optimisticBeam = const [];
      _optimisticTraveledM = _confirmedTraveledM;
    }
  }
}

double _clampSigned(double value, double limit) =>
    value.clamp(-limit, limit).toDouble();

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
