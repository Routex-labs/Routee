import 'dart:math' as math;

import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import '../../../../models/building/floor_graph.dart';
import '../../contract/pdr_anchor.dart';

/// 노드에서 나가는 한 갈래. 어느 간선을 어느 부호로 탈 것인가.
class RecoveryOption {
  const RecoveryOption({
    required this.edge,
    required this.travelSign,
    required this.bearingDeg,
  });

  final CorridorEdge edge;
  final int travelSign;
  final double bearingDeg;
}

class CorridorNetwork {
  CorridorNetwork(FloorGraph graph)
    : nodes = {
        for (final node in graph.nodes)
          node.id: CorridorNode(
            id: node.id,
            point: PdrLocalPoint(node.xM, node.yM),
            type: node.type.toLowerCase(),
          ),
      } {
    for (final graphEdge in graph.edges) {
      final from = nodes[graphEdge.fromNodeId];
      final to = nodes[graphEdge.toNodeId];
      if (from == null || to == null || graphEdge.transferMode != null) {
        continue;
      }
      final geometry = graphEdge.geometryLocalM.length >= 2
          ? graphEdge.geometryLocalM
                .map((point) => PdrLocalPoint(point.x, point.y))
                .toList(growable: false)
          : [from.point, to.point];
      final edge = CorridorEdge(
        id: graphEdge.id,
        fromNodeId: from.id,
        toNodeId: to.id,
        bidirectional: graphEdge.bidirectional,
        points: geometry,
        accessEdge:
            graphEdge.id.startsWith('store_edge_') ||
            const {'store_entrance', 'poi'}.contains(from.type) ||
            const {'store_entrance', 'poi'}.contains(to.type),
      );
      if (edge.lengthM <= 1e-6) continue;
      edges.add(edge);
      _edgesById[edge.id] = edge;
      _incident.putIfAbsent(from.id, () => []).add(edge);
      _incident.putIfAbsent(to.id, () => []).add(edge);
    }
  }

  final Map<String, CorridorNode> nodes;
  final List<CorridorEdge> edges = [];
  final Map<String, CorridorEdge> _edgesById = {};
  final Map<String, List<CorridorEdge>> _incident = {};

  /// [radiusM] 안에 있는 모든 간선의 투영점. 빔의 시작 씨앗을 만든다.
  ///
  /// 가장 가까운 하나만 고르면 시작 위치가 평행 복도 사이에 있을 때 그 선택이
  /// 곧 최종 답이 된다. 후보를 다 깔고 걸음으로 걸러내는 편이 안전하다.
  List<EdgeProjection> nearbyProjections(
    PdrLocalPoint point, {
    required double radiusM,
  }) {
    final found = <EdgeProjection>[];
    for (final edge in edges) {
      if (edge.accessEdge) continue;
      final projection = edge.project(point);
      if (projection.distanceM <= radiusM) found.add(projection);
    }
    if (found.isEmpty) {
      final nearest = nearestProjection(point);
      if (nearest != null) found.add(nearest);
    }
    found.sort((left, right) => left.distanceM.compareTo(right.distanceM));
    return found;
  }

  EdgeProjection? nearestProjection(PdrLocalPoint point, {double? headingDeg}) {
    EdgeProjection? best;
    for (final edge in edges) {
      final projection = edge.project(point);
      final closer =
          best == null || projection.distanceM < best.distanceM - 0.1;
      final nearTie =
          best != null &&
          (projection.distanceM - best.distanceM).abs() <= 0.1 &&
          headingDeg != null;
      final headingBetter =
          nearTie &&
          headingError(
                headingDeg,
                edge.bearingForTravel(
                  projection.distanceAlongM,
                  edge.directionSignForHeading(headingDeg),
                ),
              ) <
              headingError(
                headingDeg,
                best.edge.bearingForTravel(
                  best.distanceAlongM,
                  best.edge.directionSignForHeading(headingDeg),
                ),
              );
      if (closer || headingBetter) {
        best = projection;
      }
    }
    return best;
  }

  JunctionDistance? nearestJunctionOn(
    CorridorEdge edge,
    PdrLocalPoint point, {
    required double maxDistanceM,
  }) => _nearestNodeOn(
    edge,
    point,
    maxDistanceM: maxDistanceM,
    accepts: (nodeId) => isDirectionDecisionNode(edge, nodeId),
  );

  JunctionDistance? _nearestNodeOn(
    CorridorEdge edge,
    PdrLocalPoint point, {
    required double maxDistanceM,
    required bool Function(String nodeId) accepts,
  }) {
    JunctionDistance? best;
    final projection = edge.project(point);
    for (final nodeId in [edge.fromNodeId, edge.toNodeId]) {
      if (!accepts(nodeId)) continue;
      final node = nodes[nodeId]!;
      final distance = nodeId == edge.fromNodeId
          ? projection.distanceAlongM
          : edge.lengthM - projection.distanceAlongM;
      if (distance > maxDistanceM ||
          best != null && distance >= best.distanceM) {
        continue;
      }
      best = JunctionDistance(node: node, distanceM: distance);
    }
    return best;
  }

  bool isDirectionDecisionNode(CorridorEdge current, String nodeId) {
    final incomingBearing = current.bearingTowardNode(nodeId);
    for (final edge in _incident[nodeId] ?? const []) {
      if (edge.id == current.id || edge.accessEdge) continue;
      if (!edge.bidirectional && edge.fromNodeId != nodeId) continue;
      final outgoingBearing = edge.bearingAwayFromNode(nodeId);
      if (headingError(incomingBearing, outgoingBearing) > 20) return true;
    }
    return false;
  }

  /// [fromEdge] 위 [progressM]에서 진행 방향으로 [maxDistanceM] 안에
  /// [targetEdgeId]에 닿을 수 있는지.
  ///
  /// optimistic cursor를 그대로 둘지 확정 쪽으로 되돌릴지 가르는 판정이다.
  /// "가까운 간선"이 아니라 **연결된 간선**만 본다 — 나란한 평행 복도는 거리가
  /// 아무리 가까워도 여기서 통과하지 못한다.
  bool isForwardReachable({
    required CorridorEdge fromEdge,
    required int travelSign,
    required double progressM,
    required String targetEdgeId,
    required double maxDistanceM,
  }) {
    if (fromEdge.id == targetEdgeId) return true;
    final remainingM = travelSign > 0
        ? fromEdge.lengthM - progressM
        : progressM;
    if (remainingM > maxDistanceM) return false;
    final visited = <String>{fromEdge.id};
    final queue = <({String nodeId, double distanceM})>[
      (nodeId: fromEdge.nodeAtTravelEnd(travelSign), distanceM: remainingM),
    ];
    while (queue.isNotEmpty) {
      final head = queue.removeAt(0);
      for (final option in recoveryOptionsFromNode(head.nodeId)) {
        if (option.edge.id == targetEdgeId) return true;
        if (!visited.add(option.edge.id)) continue;
        final nextM = head.distanceM + option.edge.lengthM;
        if (nextM > maxDistanceM) continue;
        queue.add((
          nodeId: option.edge.nodeAtTravelEnd(option.travelSign),
          distanceM: nextM,
        ));
      }
    }
    return false;
  }

  List<RecoveryOption> recoveryOptionsFromNode(String nodeId) => [
    for (final edge in _incident[nodeId] ?? const [])
      if (!edge.accessEdge && (edge.bidirectional || edge.fromNodeId == nodeId))
        RecoveryOption(
          edge: edge,
          travelSign: edge.travelSignAwayFromNode(nodeId),
          bearingDeg: edge.bearingAwayFromNode(nodeId),
        ),
  ];
}

class CorridorNode {
  const CorridorNode({
    required this.id,
    required this.point,
    required this.type,
  });

  final String id;
  final PdrLocalPoint point;
  final String type;
}

class CorridorEdge {
  CorridorEdge({
    required this.id,
    required this.fromNodeId,
    required this.toNodeId,
    required this.bidirectional,
    required this.points,
    required this.accessEdge,
  }) : _lengths = _cumulativeLengths(points);

  final String id;
  final String fromNodeId;
  final String toNodeId;
  final bool bidirectional;
  final List<PdrLocalPoint> points;
  final bool accessEdge;
  final List<double> _lengths;

  double get lengthM => _lengths.last;

  EdgeProjection project(PdrLocalPoint point) {
    EdgeProjection? best;
    for (var index = 1; index < points.length; index += 1) {
      final from = points[index - 1];
      final to = points[index];
      final delta = to - from;
      final squared = delta.eastM * delta.eastM + delta.northM * delta.northM;
      if (squared <= 1e-12) continue;
      final rawT =
          ((point.eastM - from.eastM) * delta.eastM +
              (point.northM - from.northM) * delta.northM) /
          squared;
      final t = rawT.clamp(0.0, 1.0).toDouble();
      final projected = PdrLocalPoint(
        from.eastM + delta.eastM * t,
        from.northM + delta.northM * t,
      );
      final segmentLength = math.sqrt(squared);
      final candidate = EdgeProjection(
        edge: this,
        point: projected,
        distanceM: (point - projected).distance,
        distanceAlongM: _lengths[index - 1] + segmentLength * t,
      );
      if (best == null || candidate.distanceM < best.distanceM) {
        best = candidate;
      }
    }
    return best!;
  }

  int directionSignForHeading(double headingDeg) {
    if (!bidirectional) return 1;
    final forward = bearingForTravel(0, 1);
    final reverse = normalizeBearing(forward + 180);
    return headingError(headingDeg, forward) <=
            headingError(headingDeg, reverse)
        ? 1
        : -1;
  }

  int travelSignAwayFromNode(String nodeId) => nodeId == fromNodeId ? 1 : -1;

  String nodeAtTravelEnd(int travelSign) =>
      travelSign > 0 ? toNodeId : fromNodeId;

  double bearingForTravel(double distanceAlongM, int travelSign) {
    final tangent = tangentBearingAt(distanceAlongM);
    return travelSign > 0 ? tangent : normalizeBearing(tangent + 180);
  }

  double tangentBearingAt(double distanceAlongM) {
    final target = distanceAlongM.clamp(0.0, lengthM).toDouble();
    for (var index = 1; index < _lengths.length; index += 1) {
      if (target > _lengths[index] && index < _lengths.length - 1) continue;
      return pdrBearingForDirection(points[index] - points[index - 1]);
    }
    return pdrBearingForDirection(points.last - points[points.length - 2]);
  }

  double bearingTowardNode(String nodeId) {
    if (nodeId == toNodeId) {
      return pdrBearingForDirection(points.last - points[points.length - 2]);
    }
    return pdrBearingForDirection(points.first - points[1]);
  }

  double bearingAwayFromNode(String nodeId) =>
      normalizeBearing(bearingTowardNode(nodeId) + 180);

  /// [fromM]에서 [toM]까지 간선을 따라 촘촘히 샘플한 중간 점들(양 끝 제외).
  ///
  /// 회전 전환 구간에서 node로 옮겨 앉을 때, 그 사이를 직선 하나로 이으면
  /// 궤적이 3m 넘게 건너뛴 것처럼 보인다. 간선 형상을 따라 나눠 두면 실제
  /// 복도를 걸어간 모양으로 남는다.
  List<PdrLocalPoint> pointsBetween(
    double fromM,
    double toM, {
    double stepM = 0.8,
  }) {
    final spanM = (toM - fromM).abs();
    if (spanM <= stepM) return const [];
    final count = (spanM / stepM).ceil() - 1;
    final sign = toM >= fromM ? 1 : -1;
    return [
      for (var index = 1; index <= count; index += 1)
        pointAt(fromM + sign * spanM * index / (count + 1)),
    ];
  }

  PdrLocalPoint pointAt(double distanceM) {
    final target = distanceM.clamp(0.0, lengthM).toDouble();
    for (var index = 1; index < _lengths.length; index += 1) {
      if (target > _lengths[index]) continue;
      final span = _lengths[index] - _lengths[index - 1];
      final t = span <= 1e-12 ? 0.0 : (target - _lengths[index - 1]) / span;
      final from = points[index - 1];
      final to = points[index];
      return PdrLocalPoint(
        from.eastM + (to.eastM - from.eastM) * t,
        from.northM + (to.northM - from.northM) * t,
      );
    }
    return points.last;
  }
}

class EdgeProjection {
  const EdgeProjection({
    required this.edge,
    required this.point,
    required this.distanceM,
    required this.distanceAlongM,
  });

  final CorridorEdge edge;
  final PdrLocalPoint point;
  final double distanceM;
  final double distanceAlongM;
}

class JunctionDistance {
  const JunctionDistance({required this.node, required this.distanceM});

  final CorridorNode node;
  final double distanceM;
}

List<double> _cumulativeLengths(List<PdrLocalPoint> points) {
  final result = <double>[0];
  for (var index = 1; index < points.length; index += 1) {
    result.add(result.last + (points[index] - points[index - 1]).distance);
  }
  return result;
}

double normalizeBearing(double value) {
  final normalized = value % 360;
  return normalized < 0 ? normalized + 360 : normalized;
}

double shortestDelta(double value) {
  final normalized = (value + 180) % 360;
  return (normalized < 0 ? normalized + 360 : normalized) - 180;
}

double headingError(double left, double right) =>
    shortestDelta(left - right).abs();
