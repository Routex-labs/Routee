import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/route/corridor_shortcuts.dart';
import 'package:navigation_client/domain/route/corridor_shortcuts_data.dart';
import 'package:navigation_client/models/building/floor_graph.dart';

GraphNode _node(String id, double x, double y) =>
    GraphNode(id: id, type: 'junction', xM: x, yM: y);

GraphEdge _edge(String id, String from, String to, double lengthM) => GraphEdge(
  id: id,
  fromNodeId: from,
  toNodeId: to,
  lengthM: lengthM,
  bidirectional: true,
  geometryLocalM: const [],
);

/// ㄱ자로 도는 세 노드. a-b-c로 20m를 걷지만 a-c는 14.14m다.
FloorGraph _corner() => FloorGraph(
  nodes: [_node('a', 0, 0), _node('b', 10, 0), _node('c', 10, 10)],
  edges: [_edge('ab', 'a', 'b', 10), _edge('bc', 'b', 'c', 10)],
);

const _table = CorridorShortcutTable(
  buildingId: 'test-building',
  byFloorName: {
    '1F': [
      CorridorShortcut(fromNodeId: 'a', toNodeId: 'c', lengthM: 14.142136),
    ],
  },
);

void main() {
  group('floorGraphWithCorridorShortcuts', () {
    test('지름길을 얹고 노드는 하나도 만들지 않는다', () {
      final graph = _corner();
      final result = floorGraphWithCorridorShortcuts(
        graph,
        _table,
        buildingId: 'test-building',
        floorName: '1F',
      );

      // 새 노드 0개. PDR 무해성의 근거가 통째로 여기 걸려 있다.
      expect(result.nodes.length, graph.nodes.length);
      expect(result.edges.length, graph.edges.length + 1);

      final added = result.edges.last;
      expect(added.fromNodeId, 'a');
      expect(added.toNodeId, 'c');
      expect(added.lengthM, closeTo(14.142136, 1e-6));
      expect(added.bidirectional, isTrue);
      // 비어 있으면 두 노드를 직선으로 잇는 것이 규칙이고, 지름길은 정의상 직선이다.
      expect(added.geometryLocalM, isEmpty);
      // 층 내부 간선은 cost_m == length_m이 정의라 폴백이 곧 정답이다.
      expect(added.routingCostM, closeTo(14.142136, 1e-6));
    });

    test('건물 id가 다르면 원본 그대로 돌려준다', () {
      final graph = _corner();
      final result = floorGraphWithCorridorShortcuts(
        graph,
        _table,
        buildingId: 'other-building',
        floorName: '1F',
      );
      expect(identical(result, graph), isTrue);
    });

    test('표에 없는 층이면 원본 그대로 돌려준다', () {
      final graph = _corner();
      final result = floorGraphWithCorridorShortcuts(
        graph,
        _table,
        buildingId: 'test-building',
        floorName: 'B1',
      );
      expect(identical(result, graph), isTrue);
    });

    test('없는 노드 id를 가리키는 항목은 건너뛴다', () {
      final graph = _corner();
      final result = floorGraphWithCorridorShortcuts(
        graph,
        const CorridorShortcutTable(
          buildingId: 'test-building',
          byFloorName: {
            '1F': [
              CorridorShortcut(fromNodeId: 'a', toNodeId: 'zzz', lengthM: 5),
              CorridorShortcut(fromNodeId: 'yyy', toNodeId: 'c', lengthM: 5),
            ],
          },
        ),
        buildingId: 'test-building',
        floorName: '1F',
      );
      // 데이터가 재생성돼 노드 id가 바뀌어도 길찾기가 죽지 않아야 한다.
      expect(identical(result, graph), isTrue);
    });

    test('두 번 얹어도 결과가 같다(멱등)', () {
      final once = floorGraphWithCorridorShortcuts(
        _corner(),
        _table,
        buildingId: 'test-building',
        floorName: '1F',
      );
      final twice = floorGraphWithCorridorShortcuts(
        once,
        _table,
        buildingId: 'test-building',
        floorName: '1F',
      );
      expect(twice.edges.length, once.edges.length);
      expect(identical(twice, once), isTrue);
    });

    test('이미 이어진 두 노드에는 간선을 더 만들지 않는다', () {
      final graph = _corner();
      final result = floorGraphWithCorridorShortcuts(
        graph,
        const CorridorShortcutTable(
          buildingId: 'test-building',
          byFloorName: {
            // ab 간선이 이미 있다. 방향이 반대여도 같은 쌍으로 본다.
            '1F': [
              CorridorShortcut(fromNodeId: 'b', toNodeId: 'a', lengthM: 10),
            ],
          },
        ),
        buildingId: 'test-building',
        floorName: '1F',
      );
      expect(identical(result, graph), isTrue);
    });
  });

  group('생성된 표', () {
    test('검수 대기분은 켜져 있지 않다', () {
      // 수직 링크는 평행 복도 방어를 무너뜨릴 수 있다. 사람이 도면에서 확인하고
      // 옮기기 전까지 두 표는 겹치면 안 된다.
      final enabled = <String>{
        for (final entry in kCorridorShortcuts.byFloorName.entries)
          for (final shortcut in entry.value)
            corridorShortcutEdgeId(shortcut),
      };
      final pending = <String>{
        for (final entry in kCorridorShortcutsNeedingReview.byFloorName.entries)
          for (final shortcut in entry.value)
            corridorShortcutEdgeId(shortcut),
      };
      expect(enabled.intersection(pending), isEmpty);
      expect(pending, isNotEmpty);
    });

    test('노드 id가 층 스코프를 달고 있고 길이가 양수다', () {
      for (final entry in kCorridorShortcuts.byFloorName.entries) {
        expect(entry.value, isNotEmpty, reason: '${entry.key}에 빈 목록');
        for (final shortcut in entry.value) {
          // 클라이언트가 보는 id는 studio_adapter._scoped가 붙인 `{floorId}:{rawId}`다.
          expect(shortcut.fromNodeId, contains(':'));
          expect(shortcut.toNodeId, contains(':'));
          expect(shortcut.fromNodeId, isNot(shortcut.toNodeId));
          expect(shortcut.lengthM, greaterThan(0));
          // 생성 규칙 2: 2m <= 직선거리 <= 20m.
          expect(shortcut.lengthM, inInclusiveRange(2.0, 20.0));
        }
      }
    });
  });
}
