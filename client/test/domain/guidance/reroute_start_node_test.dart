import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/guidance/reroute_start_node.dart';
import 'package:navigation_client/models/building/floor_graph.dart';

/// 실측 B2 그래프. 나란한 에스컬레이터 레인 간격의 단일 출처다.
const _fixture = 'test/features/indoor_navigation/fixtures/b2_graph.json';

/// 한 뱅크의 두 레인과 그 앞 junction. 값은 위 fixture에서 가져왔다.
const _upLaneId = 'FL-1ibh3iudjt4ro0414:ND-o_EVU0DMb5335';
const _downLaneId = 'FL-1ibh3iudjt4ro0414:ND-ZJ3WJKM999822';
const _landingJunctionId = 'FL-1ibh3iudjt4ro0414:ND-FTPGZa0Nh1478';

List<GraphNode> _b2Nodes() {
  final json =
      jsonDecode(File(_fixture).readAsStringSync()) as Map<String, dynamic>;
  return [
    for (final node in json['nodes'] as List)
      GraphNode.fromJson(node as Map<String, dynamic>),
  ];
}

GraphNode _node(List<GraphNode> nodes, String id) =>
    nodes.firstWhere((node) => node.id == id);

void main() {
  group('pickRerouteStartNodeId', () {
    test('나란한 레인은 1.3m 안에 있다 — 이 함수가 존재하는 이유', () {
      final nodes = _b2Nodes();
      final up = _node(nodes, _upLaneId);
      final down = _node(nodes, _downLaneId);
      final gapM = (up.xM - down.xM).abs();

      // 이 간격이 벌어지면(도면 개정 등) 전제가 바뀐 것이다. 그때는 타입 제외
      // 대신 다른 근거를 찾아야 한다.
      expect(gapM, lessThan(2.0));
    });

    test('보정 위치가 0.8m만 밀려도 최근접 노드는 반대 레인으로 넘어간다', () {
      final nodes = _b2Nodes();
      final up = _node(nodes, _upLaneId);
      final down = _node(nodes, _downLaneId);

      String? nearestAnyType(double xM, double yM) {
        GraphNode? best;
        double? bestDistanceSquared;
        for (final node in nodes) {
          final distanceSquared =
              (node.xM - xM) * (node.xM - xM) + (node.yM - yM) * (node.yM - yM);
          if (bestDistanceSquared == null ||
              distanceSquared < bestDistanceSquared) {
            bestDistanceSquared = distanceSquared;
            best = node;
          }
        }
        return best?.id;
      }

      final driftedX = up.xM + (down.xM - up.xM) * 0.6;
      expect(nearestAnyType(up.xM, up.yM), _upLaneId);
      expect(nearestAnyType(driftedX, up.yM), _downLaneId);
    });

    test('수직 전이 노드를 빼면 밀려도 같은 junction을 고른다', () {
      final nodes = _b2Nodes();
      final up = _node(nodes, _upLaneId);
      final down = _node(nodes, _downLaneId);

      for (final fraction in [0.0, 0.4, 0.6, 0.8, 1.0]) {
        final xM = up.xM + (down.xM - up.xM) * fraction;
        expect(
          pickRerouteStartNodeId(nodes: nodes, xM: xM, yM: up.yM),
          _landingJunctionId,
          reason: '레인 사이 $fraction 지점',
        );
      }
    });

    test('목적지 노드는 출발점이 되지 않는다', () {
      final nodes = _b2Nodes();
      final landing = _node(nodes, _landingJunctionId);

      expect(
        pickRerouteStartNodeId(
          nodes: nodes,
          xM: landing.xM,
          yM: landing.yM,
          excludingNodeId: _landingJunctionId,
        ),
        isNot(_landingJunctionId),
      );
    });

    test('쓸 노드가 하나도 없으면 null — 호출부가 재탐색을 걸지 않는다', () {
      const nodes = [
        GraphNode(id: 'e1', type: 'escalator', xM: 0, yM: 0),
        GraphNode(id: 'v1', type: 'elevator', xM: 1, yM: 0),
      ];

      expect(pickRerouteStartNodeId(nodes: nodes, xM: 0, yM: 0), isNull);
    });
  });
}
