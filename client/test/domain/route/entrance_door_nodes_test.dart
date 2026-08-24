import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/route/building_entrances.dart';
import 'package:navigation_client/domain/route/entrance_door_nodes.dart';
import 'package:navigation_client/models/building/building_graph.dart';
import 'package:navigation_client/models/building/floor_graph.dart';
import 'package:navigation_client/models/building/floor_plan.dart';

/// 손으로 만든 층 좌표계. x=동쪽 m, y=북쪽 m이고 이 규칙으로 만든 노드 세 개가
/// 한 직선 위에 있지 않아 [fitFloorGeoTransform]이 실측 앵커로 정확히 풀린다.
const _lat0 = 37.5;
const _lng0 = 127.0;
const _metersPerDegreeLat = 111320.0;

LatLng _wgs84(double xM, double yM) => LatLng(
  _lat0 + yM / _metersPerDegreeLat,
  _lng0 +
      xM / (_metersPerDegreeLat * math.cos(_lat0 * math.pi / 180)),
);

GraphNode _node(String id, double xM, double yM, {String? floorId}) {
  final point = _wgs84(xM, yM);
  return GraphNode(
    id: id,
    type: 'corridor',
    xM: xM,
    yM: yM,
    lat: point.latitude,
    lng: point.longitude,
    floorId: floorId,
  );
}

/// 앵커 노드 셋을 가진 층 그래프. 문 안쪽 노드는 원점(`n-inside`)이다.
FloorGraph _floorGraph({List<GraphNode> extra = const []}) => FloorGraph(
  nodes: [
    _node('n-inside', 0, 0),
    _node('n-east', 20, 0),
    _node('n-north', 0, 20),
    ...extra,
  ],
  edges: const [],
);

/// 문 앞 좌표가 [doorX], [doorY]인 출구 하나짜리 도면.
FloorPlan _plan({
  required double doorX,
  required double doorY,
  String nodeId = 'n-inside',
}) => FloorPlan(
  stores: [
    StorePolygon(
      id: 'exit-1',
      name: '출구',
      polygon: const [],
      centroid: _wgs84(doorX, doorY),
      entranceNodeId: nodeId,
      subcategory: kGroundEntranceSubcategory,
    ),
  ],
  pois: const [],
);

void main() {
  group('floorGraphWithEntranceDoors', () {
    test('문 앞 좌표에 노드를 만들고 안쪽 노드와 양방향 간선으로 잇는다', () {
      final stitched = floorGraphWithEntranceDoors(
        _floorGraph(),
        _plan(doorX: 0, doorY: -10),
      );

      final door = stitched.nodes.singleWhere(
        (node) => node.id == entranceDoorNodeId('exit-1'),
      );
      expect(door.xM, closeTo(0, 0.01));
      expect(door.yM, closeTo(-10, 0.01));
      // 좌표를 채우면 다음 변환 피팅의 대응점으로 세어진다. 그리기는 local m을
      // 쓰므로 비워 둔다.
      expect(door.lat, isNull);
      expect(door.lng, isNull);

      final edge = stitched.edges.single;
      expect(edge.fromNodeId, door.id);
      expect(edge.toNodeId, 'n-inside');
      expect(edge.lengthM, closeTo(10, 0.01));
      expect(edge.bidirectional, isTrue);
      // 비어 있으면 두 노드를 직선으로 잇는다는 것이 이 코드베이스의 약속이다.
      expect(edge.geometryLocalM, isEmpty);
      expect(edge.transferMode, isNull);
    });

    test('$kEntranceDoorMinGapMeters m 미만이면 꿰매지 않는다', () {
      final stitched = floorGraphWithEntranceDoors(
        _floorGraph(),
        _plan(doorX: 0, doorY: -2),
      );

      expect(stitched.nodes.length, 3);
      expect(stitched.edges, isEmpty);
    });

    test('$kEntranceDoorMaxGapMeters m를 넘으면 꿰매지 않는다', () {
      final stitched = floorGraphWithEntranceDoors(
        _floorGraph(),
        _plan(doorX: 0, doorY: -30),
      );

      expect(stitched.nodes.length, 3);
      expect(stitched.edges, isEmpty);
    });

    test('앵커 노드가 그래프에 없으면 건너뛴다', () {
      final stitched = floorGraphWithEntranceDoors(
        _floorGraph(),
        _plan(doorX: 0, doorY: -10, nodeId: 'n-missing'),
      );

      expect(stitched.nodes.length, 3);
      expect(stitched.edges, isEmpty);
    });

    test('이미 그 자리에 노드가 있으면 중복으로 만들지 않는다', () {
      final graph = _floorGraph(extra: [_node('n-door-already', 0, -10)]);

      final stitched = floorGraphWithEntranceDoors(
        graph,
        _plan(doorX: 0, doorY: -10),
      );

      expect(stitched.nodes.length, 4);
      expect(stitched.edges, isEmpty);
    });

    test('두 번 꿰매도 노드가 늘지 않는다', () {
      final plan = _plan(doorX: 0, doorY: -10);
      final once = floorGraphWithEntranceDoors(_floorGraph(), plan);
      final twice = floorGraphWithEntranceDoors(once, plan);

      expect(twice.nodes.length, once.nodes.length);
      expect(twice.edges.length, once.edges.length);
    });
  });

  group('buildingGraphWithEntranceDoors', () {
    BuildingGraph buildingGraph() => BuildingGraph(
      buildingId: 'bldg-1',
      vertical: 'auto',
      floorNamesById: const {'floor-1': '1F', 'floor-2': '2F'},
      nodes: [
        _node('n-inside', 0, 0, floorId: 'floor-1'),
        _node('n-east', 20, 0, floorId: 'floor-1'),
        _node('n-north', 0, 20, floorId: 'floor-1'),
        // 다른 층 노드는 문 노드의 층 피팅에 섞이면 안 된다.
        _node('n-2f', 0, 0, floorId: 'floor-2'),
      ],
      edges: const [],
    );

    test('문 노드는 앵커와 같은 층에 붙는다', () {
      final stitched = buildingGraphWithEntranceDoors(
        buildingGraph(),
        _plan(doorX: 0, doorY: -10),
      );

      final door = stitched.nodes.singleWhere(
        (node) => node.id == entranceDoorNodeId('exit-1'),
      );
      expect(door.floorId, 'floor-1');
      expect(door.yM, closeTo(-10, 0.01));

      final edge = stitched.edges.single;
      expect(edge.fromFloorId, 'floor-1');
      expect(edge.toFloorId, 'floor-1');
    });
  });

  group('entranceRouteNodeId', () {
    const entrance = BuildingEntrance(
      id: 'exit-1',
      name: '출구',
      nodeId: 'n-inside',
      point: LatLng(_lat0, _lng0),
    );

    test('문 노드가 있으면 그 id를 쓴다', () {
      final stitched = floorGraphWithEntranceDoors(
        _floorGraph(),
        _plan(doorX: 0, doorY: -10),
      );

      expect(
        entranceRouteNodeId(stitched.nodes, entrance),
        entranceDoorNodeId('exit-1'),
      );
    });

    test('꿰매지 못한 출구는 예전 안쪽 노드로 폴백한다', () {
      expect(entranceRouteNodeId(_floorGraph().nodes, entrance), 'n-inside');
    });

    test('그래프를 못 받았으면 예전 안쪽 노드로 폴백한다', () {
      expect(entranceRouteNodeId(null, entrance), 'n-inside');
    });
  });
}
