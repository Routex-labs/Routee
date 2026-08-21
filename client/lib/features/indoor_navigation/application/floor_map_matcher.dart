import 'dart:math' as math;

import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import '../../../models/building/floor_graph.dart';

/// PDR의 floor-local 위치를 navigation graph의 통행 간선 위로 붙인다.
///
/// 단순히 매 순간 가장 가까운 선분에 투영하면 서로 떨어진 복도 사이를
/// 순간이동하거나, 렌더러가 두 스냅 점을 직선으로 이어 매장 내부를 가로지를 수
/// 있다. 이 matcher는 직전 매칭점에서 graph를 따라 도달 가능한 후보만 간선
/// 전환에 사용하고, [matchRoutedPath]는 전환 시 교차점까지의 실제 graph 경로를
/// 펼친다.
class FloorMapMatcher {
  FloorMapMatcher(
    FloorGraph graph, {
    this.edgeSwitchBiasM = 1.25,
    this.minimumNetworkTransitionM = 4,
    this.transitionDistanceMultiplier = 3,
    this.accessEdgePenaltyM = 4,
    this.directionMismatchPenaltyM = 2,
    this.recoveryTriggerDistanceM = 2,
    this.recoveryConsecutiveSamples = 3,
    this.recoverySearchRadiusM = 12,
    this.recoveryMinimumNetworkTransitionM = 14,
    this.recoveryTransitionDistanceMultiplier = 4,
  }) : _nodes = {for (final node in graph.nodes) node.id: node},
       _edges = _buildEdges(graph, accessEdgePenaltyM),
       _adjacency = _buildAdjacency(graph, accessEdgePenaltyM) {
    for (final edge in _edges) {
      _edgeById[edge.id] = edge;
    }
  }

  /// 다른 간선으로 바뀌기 위해 필요한 추가 근접도. 평행 복도에서 조금
  /// 흔들려도 간선이 번갈아 바뀌지 않게 한다.
  final double edgeSwitchBiasM;

  /// 한 PDR 점 사이에 graph를 따라 이동할 수 있는 최소 허용 거리다. 배치된
  /// pedometer 점이 교차점 전후를 건너뛰어도 자연스럽게 이어지게 한다.
  final double minimumNetworkTransitionM;

  /// raw PDR의 두 점 사이 거리 대비 허용하는 graph 이동 배수다. 이 범위를
  /// 넘는 후보는 센서 드리프트에 의한 다른 복도 스냅으로 보고 무시한다.
  final double transitionDistanceMultiplier;

  /// 매장 입구·POI로 끝나는 짧은 가지가 가까이 있어도 주 통행 복도를 우선하기
  /// 위한 거리 환산 페널티다. 실제 graph 거리에는 더하지 않고 후보 순위에만 쓴다.
  final double accessEdgePenaltyM;

  /// 최근 PDR 이동 방향과 후보 간선 방향이 직교할수록 후보 점수에 더하는 값이다.
  final double directionMismatchPenaltyM;

  /// 현재 간선에서 이 거리 이상 벗어나야 복구 증거를 누적한다.
  final double recoveryTriggerDistanceM;

  /// 같은 대체 복도가 연속해서 선택돼야 복구 전환을 허용한다.
  final int recoveryConsecutiveSamples;

  /// 복구 후보가 raw 위치에서 이 거리보다 멀면 잘못된 재부착으로 간주한다.
  final double recoverySearchRadiusM;

  /// 복구 모드에서 허용하는 최소 graph 이동거리다. 정상 모드의 4m 제한 때문에
  /// 한번 놓친 분기를 영원히 통과하지 못하는 문제를 완화한다.
  final double recoveryMinimumNetworkTransitionM;

  final double recoveryTransitionDistanceMultiplier;

  final Map<String, GraphNode> _nodes;
  final List<_NetworkEdge> _edges;
  final Map<String, _NetworkEdge> _edgeById = {};
  final Map<String, List<_GraphArc>> _adjacency;
  final Map<String, _NodeRoute?> _nodeRouteCache = {};

  _MatchedCandidate? _last;
  PdrLocalPoint? _lastRaw;
  String? _suspectEdgeId;
  int _suspectSamples = 0;
  double _suspectRawDistanceM = 0;

  /// 시작점처럼 아직 직전 PDR 상태가 없는 좌표를 통행 가능한 graph 위로
  /// 투영한다. 이 호출은 matcher의 시간 상태를 바꾸지 않으므로, 사용자가
  /// 찍은 anchor를 보정할 때 안전하게 쓸 수 있다.
  MapMatchedFloorPoint? snapToWalkableNetwork(PdrLocalPoint point) {
    if (_edges.isEmpty) return null;
    final nearest = _candidatesFor(point).firstOrNull;
    return nearest?.publicResult();
  }

  /// raw 한 점의 graph 위 매칭 결과다. 간선 전환은 현재 raw 점이 더 가깝다는
  /// 사실만으로 허용하지 않고, 직전 매칭점에서 graph를 따라 도달 가능한지도
  /// 함께 확인한다.
  MapMatchedFloorPoint? match(PdrLocalPoint raw) {
    if (_edges.isEmpty) return null;

    final movement = _lastRaw == null ? null : raw - _lastRaw!;
    final rawStepM = movement?.distance ?? 0;
    final candidates = _candidatesFor(raw, movement: movement);
    if (candidates.isEmpty) return null;

    final previous = _last;
    _MatchedCandidate selected;
    var state = MapMatchState.tracking;
    if (previous == null) {
      selected = candidates.first;
      _clearRecoveryEvidence();
    } else {
      final previousEdgeCandidate = previous.edge.project(raw);
      final maxTransitionM = math.max(
        minimumNetworkTransitionM,
        rawStepM * transitionDistanceMultiplier + edgeSwitchBiasM,
      );

      _MatchedCandidate? bestReachableSwitch;
      // 가장 가까운 후보부터 몇 개만 살핀다. 매칭 그래프는 작지만, PDR path는
      // 수백 점이 될 수 있어 무조건 모든 후보에 다익스트라를 돌리지 않는다.
      for (final candidate in candidates.take(8)) {
        if (candidate.edge.id == previous.edge.id) continue;
        final route = _routeBetween(previous, candidate);
        if (route == null || route.distanceM > maxTransitionM) continue;
        bestReachableSwitch = candidate;
        break;
      }

      // 다른 간선이 확실히 더 가까우면서, 실제 graph를 따라 갈 수 있을 때만
      // 바꾼다. 그렇지 않으면 직전 간선 위에서 계속 투영해 벽 너머 복도로
      // 점프하지 않는다.
      if (bestReachableSwitch != null &&
          _isClearlyBetter(
            bestReachableSwitch,
            previousEdgeCandidate,
            movement,
          )) {
        selected = bestReachableSwitch;
        _clearRecoveryEvidence();
      } else {
        final recoveryCandidate = _bestRecoveryCandidate(
          candidates,
          previous,
          previousEdgeCandidate,
          movement,
        );
        if (recoveryCandidate == null ||
            previousEdgeCandidate.distanceToGraphM < recoveryTriggerDistanceM) {
          selected = previousEdgeCandidate;
          _clearRecoveryEvidence();
        } else {
          _recordRecoveryEvidence(recoveryCandidate.edge.id, rawStepM);
          selected = previousEdgeCandidate;
          state = MapMatchState.suspect;

          if (_suspectSamples >= recoveryConsecutiveSamples) {
            final route = _routeBetween(previous, recoveryCandidate);
            final recoveryTransitionM = math.max(
              recoveryMinimumNetworkTransitionM,
              _suspectRawDistanceM * recoveryTransitionDistanceMultiplier +
                  edgeSwitchBiasM,
            );
            if (route != null && route.distanceM <= recoveryTransitionM) {
              selected = recoveryCandidate;
              state = MapMatchState.recovered;
              _clearRecoveryEvidence();
            }
          }
        }
      }
    }

    _last = selected;
    _lastRaw = raw;
    return selected.publicResult(state: state);
  }

  List<_MatchedCandidate> _candidatesFor(
    PdrLocalPoint point, {
    PdrLocalPoint? movement,
  }) => <_MatchedCandidate>[for (final edge in _edges) edge.project(point)]
    ..sort(
      (a, b) =>
          _candidateScore(a, movement).compareTo(_candidateScore(b, movement)),
    );

  double _candidateScore(_MatchedCandidate candidate, PdrLocalPoint? movement) {
    var score = candidate.distanceToGraphM + candidate.edge.matchingPenaltyM;
    final movementDistance = movement?.distance ?? 0;
    if (movement == null || movementDistance < 0.2) return score;

    final dot =
        (movement.eastM * candidate.tangentEast +
            movement.northM * candidate.tangentNorth) /
        movementDistance;
    final alignment = candidate.edge.bidirectional
        ? dot.abs().clamp(0.0, 1.0)
        : dot.clamp(0.0, 1.0);
    score += (1 - alignment) * directionMismatchPenaltyM;
    return score;
  }

  bool _isClearlyBetter(
    _MatchedCandidate candidate,
    _MatchedCandidate current,
    PdrLocalPoint? movement,
  ) =>
      _candidateScore(candidate, movement) + edgeSwitchBiasM <
      _candidateScore(current, movement);

  _MatchedCandidate? _bestRecoveryCandidate(
    List<_MatchedCandidate> candidates,
    _MatchedCandidate previous,
    _MatchedCandidate current,
    PdrLocalPoint? movement,
  ) {
    for (final candidate in candidates) {
      if (candidate.edge.id == previous.edge.id ||
          candidate.distanceToGraphM > recoverySearchRadiusM ||
          !_isClearlyBetter(candidate, current, movement)) {
        continue;
      }
      // 끊어진 graph 사이를 순간이동시키지 않는다. 연결되지 않은 후보는 복구
      // 증거로도 쓰지 않아 기존 경로와 새 점을 직선으로 잇는 일을 막는다.
      if (_routeBetween(previous, candidate) != null) return candidate;
    }
    return null;
  }

  void _recordRecoveryEvidence(String edgeId, double rawStepM) {
    if (_suspectEdgeId == edgeId) {
      _suspectSamples += 1;
      _suspectRawDistanceM += rawStepM;
      return;
    }
    _suspectEdgeId = edgeId;
    _suspectSamples = 1;
    _suspectRawDistanceM = rawStepM;
  }

  void _clearRecoveryEvidence() {
    _suspectEdgeId = null;
    _suspectSamples = 0;
    _suspectRawDistanceM = 0;
  }

  /// raw 점마다 선택된 간선만 돌려준다. 진단이나 간선 전환 테스트에 쓴다.
  List<MapMatchedFloorPoint> matchPath(Iterable<PdrLocalPoint> rawPath) => [
    for (final point in rawPath) ?match(point),
  ];

  /// 지도에 그릴 graph-constrained polyline이다.
  ///
  /// 간선이 바뀌면 직전 투영점 → 교차 노드들 → 새 투영점 순서로 추가한다.
  /// 따라서 렌더러가 간선 사이를 직선으로 연결해 매장이나 벽을 뚫는 일이 없다.
  List<PdrLocalPoint> matchRoutedPath(Iterable<PdrLocalPoint> rawPath) {
    final routed = <PdrLocalPoint>[];
    for (final raw in rawPath) {
      final previous = _last;
      final result = match(raw);
      final selected = _last;
      if (result == null || selected == null) continue;

      if (previous == null) {
        _appendDistinct(routed, selected.point);
        continue;
      }

      final route = _routeBetween(previous, selected);
      if (route == null) {
        // match()가 전환을 거절했을 때 같은 간선 후보를 선택하므로 보통 이
        // 분기는 닿지 않는다. 그래도 graph가 불완전한 경우 새 직선을 만들지
        // 않고 마지막 안전 점을 유지한다.
        continue;
      }
      for (final point in route.points) {
        _appendDistinct(routed, point);
      }
    }
    return routed;
  }

  _NetworkRoute? _routeBetween(_MatchedCandidate from, _MatchedCandidate to) {
    if (from.edge.id == to.edge.id) {
      return _NetworkRoute(
        distanceM: (to.distanceAlongEdgeM - from.distanceAlongEdgeM).abs(),
        points: from.edge.pathBetween(
          from.distanceAlongEdgeM,
          to.distanceAlongEdgeM,
        ),
      );
    }

    _NetworkRoute? best;
    for (final fromEndpoint in _EdgeEndpoint.values) {
      final fromNode = from.edge.nodeIdAt(fromEndpoint);
      final fromDistance = from.edge.distanceToEndpoint(
        from.distanceAlongEdgeM,
        fromEndpoint,
      );
      final fromPoints = from.edge.pathBetween(
        from.distanceAlongEdgeM,
        from.edge.distanceAt(fromEndpoint),
      );

      for (final toEndpoint in _EdgeEndpoint.values) {
        final toNode = to.edge.nodeIdAt(toEndpoint);
        final middle = _shortestNodeRoute(fromNode, toNode);
        if (middle == null) continue;

        final toDistance = to.edge.distanceToEndpoint(
          to.distanceAlongEdgeM,
          toEndpoint,
        );
        final distanceM = fromDistance + middle.distanceM + toDistance;
        if (best != null && distanceM >= best.distanceM) continue;

        final points = <PdrLocalPoint>[];
        _appendAllDistinct(points, fromPoints);
        _appendAllDistinct(points, middle.points);
        _appendAllDistinct(
          points,
          to.edge.pathBetween(
            to.edge.distanceAt(toEndpoint),
            to.distanceAlongEdgeM,
          ),
        );
        best = _NetworkRoute(distanceM: distanceM, points: points);
      }
    }
    return best;
  }

  _NodeRoute? _shortestNodeRoute(String fromNodeId, String toNodeId) {
    final cacheKey = '$fromNodeId>$toNodeId';
    if (_nodeRouteCache.containsKey(cacheKey)) return _nodeRouteCache[cacheKey];
    if (!_nodes.containsKey(fromNodeId) || !_nodes.containsKey(toNodeId)) {
      return _nodeRouteCache[cacheKey] = null;
    }
    if (fromNodeId == toNodeId) {
      final node = _nodes[fromNodeId]!;
      return _nodeRouteCache[cacheKey] = _NodeRoute(
        distanceM: 0,
        points: [PdrLocalPoint(node.xM, node.yM)],
      );
    }

    final distances = <String, double>{fromNodeId: 0};
    final previous = <String, _PreviousNode>{};
    final frontier = <_NodeQueueEntry>[
      _NodeQueueEntry(nodeId: fromNodeId, distanceM: 0),
    ];

    while (frontier.isNotEmpty) {
      frontier.sort((a, b) => a.distanceM.compareTo(b.distanceM));
      final current = frontier.removeAt(0);
      if (current.distanceM != distances[current.nodeId]) continue;
      if (current.nodeId == toNodeId) break;

      for (final arc in _adjacency[current.nodeId] ?? const []) {
        final nextDistance = current.distanceM + arc.edge.lengthM;
        final known = distances[arc.toNodeId];
        if (known != null && known <= nextDistance) continue;
        distances[arc.toNodeId] = nextDistance;
        previous[arc.toNodeId] = _PreviousNode(current.nodeId, arc);
        frontier.add(
          _NodeQueueEntry(nodeId: arc.toNodeId, distanceM: nextDistance),
        );
      }
    }

    final totalDistance = distances[toNodeId];
    if (totalDistance == null) return _nodeRouteCache[cacheKey] = null;

    final arcs = <_GraphArc>[];
    var cursor = toNodeId;
    while (cursor != fromNodeId) {
      final step = previous[cursor];
      if (step == null) return _nodeRouteCache[cacheKey] = null;
      arcs.add(step.arc);
      cursor = step.fromNodeId;
    }

    final startNode = _nodes[fromNodeId]!;
    final points = <PdrLocalPoint>[PdrLocalPoint(startNode.xM, startNode.yM)];
    for (final arc in arcs.reversed) {
      _appendAllDistinct(
        points,
        arc.edge.pathBetween(
          arc.forward ? 0 : arc.edge.lengthM,
          arc.forward ? arc.edge.lengthM : 0,
        ),
      );
    }
    return _nodeRouteCache[cacheKey] = _NodeRoute(
      distanceM: totalDistance,
      points: points,
    );
  }

  static List<_NetworkEdge> _buildEdges(
    FloorGraph graph,
    double accessEdgePenaltyM,
  ) {
    final nodes = {for (final node in graph.nodes) node.id: node};
    final edges = <_NetworkEdge>[];
    for (final edge in graph.edges) {
      final networkEdge = _NetworkEdge.fromGraphEdge(
        edge,
        nodes,
        accessEdgePenaltyM,
      );
      if (networkEdge != null) edges.add(networkEdge);
    }
    return edges;
  }

  static Map<String, List<_GraphArc>> _buildAdjacency(
    FloorGraph graph,
    double accessEdgePenaltyM,
  ) {
    final nodes = {for (final node in graph.nodes) node.id: node};
    final adjacency = <String, List<_GraphArc>>{};
    for (final edge in graph.edges) {
      final networkEdge = _NetworkEdge.fromGraphEdge(
        edge,
        nodes,
        accessEdgePenaltyM,
      );
      if (networkEdge == null) continue;
      adjacency
          .putIfAbsent(networkEdge.fromNodeId, () => [])
          .add(_GraphArc(networkEdge.toNodeId, networkEdge, true));
      if (networkEdge.bidirectional) {
        adjacency
            .putIfAbsent(networkEdge.toNodeId, () => [])
            .add(_GraphArc(networkEdge.fromNodeId, networkEdge, false));
      }
    }
    return adjacency;
  }
}

/// 지도 렌더링·진단에 쓸 graph 위 좌표와 매칭값.
class MapMatchedFloorPoint {
  const MapMatchedFloorPoint({
    required this.point,
    required this.edgeId,
    required this.distanceToGraphM,
    required this.tangentEast,
    required this.tangentNorth,
    this.state = MapMatchState.tracking,
  });

  final PdrLocalPoint point;
  final String edgeId;
  final double distanceToGraphM;

  /// 붙은 선분의 진행 방향 단위 벡터(floor local_m). 부호는 간선의 from→to다.
  ///
  /// 방위를 모르는 기기가 앵커 회전각을 이 축에서 가져간다
  /// (`entry/anchor_corridor_axis.dart`). 후보 점수를 매길 때 이미 계산해 둔
  /// 값이라 여기서 다시 재지 않는다 — 다시 재면 "가장 가까운 선분"의 정의가
  /// 두 곳으로 갈린다.
  final double tangentEast;
  final double tangentNorth;

  final MapMatchState state;
}

enum MapMatchState { tracking, suspect, recovered }

class _NetworkEdge {
  _NetworkEdge({
    required this.id,
    required this.fromNodeId,
    required this.toNodeId,
    required this.bidirectional,
    required this.points,
    required this.matchingPenaltyM,
  }) : _cumulativeLengths = _buildCumulativeLengths(points);

  final String id;
  final String fromNodeId;
  final String toNodeId;
  final bool bidirectional;
  final List<PdrLocalPoint> points;
  final double matchingPenaltyM;
  final List<double> _cumulativeLengths;

  double get lengthM => _cumulativeLengths.last;

  static _NetworkEdge? fromGraphEdge(
    GraphEdge edge,
    Map<String, GraphNode> nodes,
    double accessEdgePenaltyM,
  ) {
    final geometry = edge.geometryLocalM.length >= 2
        ? edge.geometryLocalM
        : _edgeEndpoints(edge, nodes);
    if (geometry.length < 2) return null;
    final points = geometry
        .map((point) => PdrLocalPoint(point.x, point.y))
        .toList(growable: false);
    if (_buildCumulativeLengths(points).last <= 1e-8) return null;
    return _NetworkEdge(
      id: edge.id,
      fromNodeId: edge.fromNodeId,
      toNodeId: edge.toNodeId,
      bidirectional: edge.bidirectional,
      points: points,
      matchingPenaltyM: _matchingPenalty(edge, nodes, accessEdgePenaltyM),
    );
  }

  static double _matchingPenalty(
    GraphEdge edge,
    Map<String, GraphNode> nodes,
    double accessEdgePenaltyM,
  ) {
    final fromType = nodes[edge.fromNodeId]?.type.toLowerCase();
    final toType = nodes[edge.toNodeId]?.type.toLowerCase();
    const backboneTypes = {'corridor', 'junction', 'path', 'dead_end'};
    const accessTypes = {'store_entrance', 'poi'};

    if (edge.id.startsWith('store_edge_') ||
        accessTypes.contains(fromType) ||
        accessTypes.contains(toType)) {
      return accessEdgePenaltyM;
    }
    if (backboneTypes.contains(fromType) && backboneTypes.contains(toType)) {
      return 0;
    }
    // 승강기·에스컬레이터·출구 연결선은 필요할 때 선택할 수 있게 완전히
    // 제외하지 않되, 같은 거리라면 주 복도를 먼저 고른다.
    return accessEdgePenaltyM * 0.5;
  }

  _MatchedCandidate project(PdrLocalPoint raw) {
    _MatchedCandidate? best;
    for (var index = 1; index < points.length; index++) {
      final from = points[index - 1];
      final to = points[index];
      final dx = to.eastM - from.eastM;
      final dy = to.northM - from.northM;
      final segmentLengthSquared = dx * dx + dy * dy;
      if (segmentLengthSquared < 1e-8) continue;
      final rawT =
          ((raw.eastM - from.eastM) * dx + (raw.northM - from.northM) * dy) /
          segmentLengthSquared;
      final t = rawT.clamp(0.0, 1.0).toDouble();
      final point = PdrLocalPoint(from.eastM + dx * t, from.northM + dy * t);
      final distance = (raw - point).distance;
      final candidate = _MatchedCandidate(
        edge: this,
        point: point,
        distanceToGraphM: distance,
        distanceAlongEdgeM:
            _cumulativeLengths[index - 1] + math.sqrt(segmentLengthSquared) * t,
        tangentEast: dx / math.sqrt(segmentLengthSquared),
        tangentNorth: dy / math.sqrt(segmentLengthSquared),
      );
      if (best == null || candidate.distanceToGraphM < best.distanceToGraphM) {
        best = candidate;
      }
    }
    return best!;
  }

  String nodeIdAt(_EdgeEndpoint endpoint) => switch (endpoint) {
    _EdgeEndpoint.from => fromNodeId,
    _EdgeEndpoint.to => toNodeId,
  };

  double distanceAt(_EdgeEndpoint endpoint) => switch (endpoint) {
    _EdgeEndpoint.from => 0,
    _EdgeEndpoint.to => lengthM,
  };

  double distanceToEndpoint(
    double distanceAlongEdgeM,
    _EdgeEndpoint endpoint,
  ) => (distanceAlongEdgeM - distanceAt(endpoint)).abs();

  /// 동일 edge 위 두 점 사이의 실제 polyline. 역방향도 지원한다.
  List<PdrLocalPoint> pathBetween(double fromDistanceM, double toDistanceM) {
    final start = fromDistanceM.clamp(0.0, lengthM).toDouble();
    final end = toDistanceM.clamp(0.0, lengthM).toDouble();
    if (start <= end) return _forwardPath(start, end);
    return _forwardPath(end, start).reversed.toList(growable: false);
  }

  List<PdrLocalPoint> _forwardPath(double start, double end) {
    final output = <PdrLocalPoint>[pointAt(start)];
    for (var index = 1; index < points.length - 1; index++) {
      final distance = _cumulativeLengths[index];
      if (distance > start + 1e-8 && distance < end - 1e-8) {
        _appendDistinct(output, points[index]);
      }
    }
    _appendDistinct(output, pointAt(end));
    return output;
  }

  PdrLocalPoint pointAt(double distanceAlongEdgeM) {
    final distance = distanceAlongEdgeM.clamp(0.0, lengthM).toDouble();
    for (var index = 1; index < points.length; index++) {
      final end = _cumulativeLengths[index];
      if (distance > end && index < points.length - 1) continue;
      final start = _cumulativeLengths[index - 1];
      final segmentLength = end - start;
      if (segmentLength <= 1e-8) return points[index];
      final t = ((distance - start) / segmentLength).clamp(0.0, 1.0);
      final from = points[index - 1];
      final to = points[index];
      return PdrLocalPoint(
        from.eastM + (to.eastM - from.eastM) * t,
        from.northM + (to.northM - from.northM) * t,
      );
    }
    return points.last;
  }

  static List<double> _buildCumulativeLengths(List<PdrLocalPoint> points) {
    final lengths = <double>[0];
    for (var index = 1; index < points.length; index++) {
      lengths.add(lengths.last + (points[index] - points[index - 1]).distance);
    }
    return lengths;
  }

  static List<LocalPoint> _edgeEndpoints(
    GraphEdge edge,
    Map<String, GraphNode> nodes,
  ) {
    final from = nodes[edge.fromNodeId];
    final to = nodes[edge.toNodeId];
    if (from == null || to == null) return const [];
    return [LocalPoint(from.xM, from.yM), LocalPoint(to.xM, to.yM)];
  }
}

class _MatchedCandidate {
  const _MatchedCandidate({
    required this.edge,
    required this.point,
    required this.distanceToGraphM,
    required this.distanceAlongEdgeM,
    required this.tangentEast,
    required this.tangentNorth,
  });

  final _NetworkEdge edge;
  final PdrLocalPoint point;
  final double distanceToGraphM;
  final double distanceAlongEdgeM;
  final double tangentEast;
  final double tangentNorth;

  MapMatchedFloorPoint publicResult({
    MapMatchState state = MapMatchState.tracking,
  }) => MapMatchedFloorPoint(
    point: point,
    edgeId: edge.id,
    distanceToGraphM: distanceToGraphM,
    tangentEast: tangentEast,
    tangentNorth: tangentNorth,
    state: state,
  );
}

class _GraphArc {
  const _GraphArc(this.toNodeId, this.edge, this.forward);

  final String toNodeId;
  final _NetworkEdge edge;
  final bool forward;
}

class _PreviousNode {
  const _PreviousNode(this.fromNodeId, this.arc);

  final String fromNodeId;
  final _GraphArc arc;
}

class _NodeQueueEntry {
  const _NodeQueueEntry({required this.nodeId, required this.distanceM});

  final String nodeId;
  final double distanceM;
}

class _NodeRoute {
  const _NodeRoute({required this.distanceM, required this.points});

  final double distanceM;
  final List<PdrLocalPoint> points;
}

class _NetworkRoute {
  const _NetworkRoute({required this.distanceM, required this.points});

  final double distanceM;
  final List<PdrLocalPoint> points;
}

enum _EdgeEndpoint { from, to }

void _appendAllDistinct(
  List<PdrLocalPoint> destination,
  Iterable<PdrLocalPoint> source,
) {
  for (final point in source) {
    _appendDistinct(destination, point);
  }
}

void _appendDistinct(List<PdrLocalPoint> destination, PdrLocalPoint point) {
  if (destination.isEmpty || (destination.last - point).distance > 1e-6) {
    destination.add(point);
  }
}
