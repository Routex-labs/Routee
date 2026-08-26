import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_pdr_core/indoor_pdr_core.dart';
import 'package:navigation_client/models/building/floor_graph.dart';
import 'package:navigation_client/screens/outdoor_map/entry/anchor_corridor_axis.dart';

/// 동서로 뻗은 복도 하나(0,0)~(40,0)에, 한쪽 끝에서 북쪽으로 꺾이는 가지.
///
/// 가지가 있어서 **노드 무게중심이 복도 위에 있지 않다** — 중심 방향을 각도로
/// 쓰던 예전 폴백이 복도를 비스듬히 가로지르던 상황을 그대로 만든 그래프다.
FloorGraph _corridorWithBranch() => FloorGraph(
  nodes: const [
    GraphNode(id: 'a', type: 'corridor', xM: 0, yM: 0),
    GraphNode(id: 'b', type: 'corridor', xM: 40, yM: 0),
    GraphNode(id: 'c', type: 'corridor', xM: 40, yM: 30),
  ],
  edges: const [
    GraphEdge(
      id: 'ab',
      fromNodeId: 'a',
      toNodeId: 'b',
      lengthM: 40,
      bidirectional: true,
      geometryLocalM: [LocalPoint(0, 0), LocalPoint(40, 0)],
    ),
    GraphEdge(
      id: 'bc',
      fromNodeId: 'b',
      toNodeId: 'c',
      lengthM: 30,
      bidirectional: true,
      geometryLocalM: [LocalPoint(40, 0), LocalPoint(40, 30)],
    ),
  ],
);

/// 동서 복도 하나만. 뒤집힌 궤적이 갈 곳이 없어야 앞뒤 판정이 갈린다.
FloorGraph _singleCorridor() => FloorGraph(
  nodes: const [
    GraphNode(id: 'a', type: 'corridor', xM: 0, yM: 0),
    GraphNode(id: 'b', type: 'corridor', xM: 40, yM: 0),
  ],
  edges: const [
    GraphEdge(
      id: 'ab',
      fromNodeId: 'a',
      toNodeId: 'b',
      lengthM: 40,
      bidirectional: true,
      geometryLocalM: [LocalPoint(0, 0), LocalPoint(40, 0)],
    ),
  ],
);

void main() {
  group('corridorAxisAtAnchor', () {
    test('찍은 자리의 복도와 나란한 방향을 돌려준다', () {
      final axis = corridorAxisAtAnchor(
        graph: _corridorWithBranch(),
        anchorFloorPoint: const PdrLocalPoint(5, 0),
        inwardHint: const PdrLocalPoint(1, 0),
      );
      expect(axis, isNotNull);
      expect(axis!.northM, closeTo(0, 1e-9));
      expect(axis.eastM, greaterThan(0));
    });

    test('힌트가 반대쪽을 가리키면 앞뒤를 뒤집는다', () {
      final axis = corridorAxisAtAnchor(
        graph: _corridorWithBranch(),
        anchorFloorPoint: const PdrLocalPoint(5, 0),
        inwardHint: const PdrLocalPoint(-1, 0),
      );
      expect(axis!.eastM, lessThan(0));
      expect(axis.northM, closeTo(0, 1e-9));
    });

    test('힌트는 앞뒤만 고르고 **각도는 쓰지 않는다**', () {
      // 이 회귀가 실기기에서 궤적을 51° 비스듬히 돌려 놓았다. 중심 방향
      // (21.7, 10)을 그대로 각도로 쓰면 북쪽 성분이 남는다.
      final graph = _corridorWithBranch();
      const anchor = PdrLocalPoint(5, 0);
      final hint = inwardHintFromGraphCentroid(graph, anchor);
      expect(hint!.northM, greaterThan(5), reason: '중심은 복도 위에 있지 않다');

      final axis = corridorAxisAtAnchor(
        graph: graph,
        anchorFloorPoint: anchor,
        inwardHint: hint,
      );
      expect(axis!.northM, closeTo(0, 1e-9));
      expect(axis.eastM, greaterThan(0), reason: '앞뒤는 중심 쪽으로 잡힌다');
    });

    test('상한보다 먼 자리에서는 회전각을 지어내지 않는다', () {
      final axis = corridorAxisAtAnchor(
        graph: _corridorWithBranch(),
        anchorFloorPoint: const PdrLocalPoint(5, 60),
        inwardHint: const PdrLocalPoint(0, -1),
        maxSnapDistanceM: 20,
      );
      expect(axis, isNull);
    });
  });

  group('anchorAxisIsBackward', () {
    const anchor = PdrLocalPoint(5, 0);

    test('이동이 모자라면 판정하지 않는다(null)', () {
      // false와 갈라야 한다 — 호출자는 한 앵커를 한 번만 판정하므로, 여기서
      // false를 주면 걷기도 전에 판정이 소진되어 앞뒤가 영영 안 갈린다.
      final verdict = anchorAxisIsBackward(
        graph: _singleCorridor(),
        anchorLocalM: anchor,
        floorPath: const [PdrLocalPoint(5, 0), PdrLocalPoint(7, 0)],
      );
      expect(verdict, isNull);
    });

    test('복도를 따라 제대로 걸었으면 그대로 둔다', () {
      final verdict = anchorAxisIsBackward(
        graph: _singleCorridor(),
        anchorLocalM: anchor,
        floorPath: const [
          PdrLocalPoint(5, 0),
          PdrLocalPoint(8, 0),
          PdrLocalPoint(12, 0),
          PdrLocalPoint(15, 0),
        ],
      );
      expect(verdict, isFalse);
    });

    test('궤적이 복도 밖으로 나가면 앞뒤가 거꾸로다', () {
      // 앵커에서 서쪽으로 걸어 복도가 끝나는 x=0을 넘어갔다. 앵커를 중심으로
      // 점대칭한 궤적은 복도 위에 그대로 얹힌다.
      final verdict = anchorAxisIsBackward(
        graph: _singleCorridor(),
        anchorLocalM: anchor,
        floorPath: const [
          PdrLocalPoint(5, 0),
          PdrLocalPoint(2, 0),
          PdrLocalPoint(-2, 0),
          PdrLocalPoint(-5, 0),
        ],
      );
      expect(verdict, isTrue);
    });
  });
}
