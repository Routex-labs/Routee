import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navigation_client/domain/route/entrance_door_nodes.dart';
import 'package:navigation_client/models/building/floor_graph.dart';
import 'package:navigation_client/repositories/building/http_building_repository.dart';

/// 손으로 만든 층 좌표계(domain 테스트와 같은 규칙).
const _lat0 = 37.5;
const _lng0 = 127.0;
const _metersPerDegreeLat = 111320.0;

Map<String, double> _wgs84(double xM, double yM) => {
  'lat': _lat0 + yM / _metersPerDegreeLat,
  'lng':
      _lng0 + xM / (_metersPerDegreeLat * math.cos(_lat0 * math.pi / 180)),
};

Map<String, dynamic> _node(String id, double xM, double yM, {String? floorId}) {
  final point = _wgs84(xM, yM);
  return {
    'id': id,
    'type': 'corridor',
    'x_m': xM,
    'y_m': yM,
    'lat': point['lat'],
    'lng': point['lng'],
    'floor_id': ?floorId,
  };
}

final _navigationGraph = {
  'nodes': [_node('n-inside', 0, 0), _node('n-east', 20, 0), _node('n-north', 0, 20)],
  'edges': [
    {
      'id': 'e1',
      'from': 'n-inside',
      'to': 'n-east',
      'length_m': 20.0,
      'bidirectional': true,
      'geometry_local_m': const [],
    },
  ],
};

final _floorResponse = {
  'footprint_wgs84': const [],
  'stores': [
    {
      'id': 'exit-1',
      'name': '출구',
      'subcategory': '교통',
      'entrance_node_id': 'n-inside',
      // 문 앞은 안쪽 노드에서 10 m 남쪽이다.
      'centroid_wgs84': _wgs84(0, -10),
    },
  ],
  'navigation_graph': _navigationGraph,
};

final _buildingGraphResponse = {
  'building': {'id': 'bldg-001'},
  'vertical': 'auto',
  'floors': [
    {'id': 'floor-1', 'name': '1F'},
  ],
  'nodes': [
    _node('n-inside', 0, 0, floorId: 'floor-1'),
    _node('n-east', 20, 0, floorId: 'floor-1'),
    _node('n-north', 0, 20, floorId: 'floor-1'),
  ],
  'edges': _navigationGraph['edges'],
};

HttpBuildingRepository _repository({bool floorFound = true}) {
  final client = MockClient((request) async {
    final path = request.url.path;
    Map<String, dynamic> body;
    if (path.endsWith('/graph')) {
      body = _buildingGraphResponse;
    } else if (path.contains('/floors/')) {
      if (!floorFound) return http.Response('{}', 404);
      body = _floorResponse;
    } else {
      body = {
        'id': 'bldg-001',
        'name': '데모 건물',
        'floors': ['1F'],
        'default_floor': '1F',
      };
    }
    return http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
  return HttpBuildingRepository(client: client);
}

void main() {
  // 이 갈라짐이 설계 전체가 서 있는 자리다. 리포지토리가 경로 탐색용으로 들고
  // 있는 FloorGraph에는 문 노드가 있고, 화면이 같은 응답에서 따로 파싱하는
  // FloorGraph(지도 매칭·복도 추적용)에는 없다. 하나로 합치면 사용자가 문
  // 밖으로 스냅되고 복도 네트워크가 건물 밖으로 나간다.
  test('경로 탐색용 층 그래프에는 문 노드가 있다', () async {
    final repository = _repository();

    final route = await repository.getShortestRoute(
      'bldg-001',
      '1F',
      entranceDoorNodeId('exit-1'),
      'n-east',
    );

    expect(route, isNotNull);
    // 문 → 안쪽 노드 10 m + 안쪽 → 동쪽 20 m.
    expect(route!.distanceMeters, closeTo(30, 0.01));
  });

  test('화면이 파싱하는 층 응답에는 문 노드가 없다', () async {
    final repository = _repository();

    final geojson = await repository.getFloorGeoJson('bldg-001', '1F');
    final screenGraph = FloorGraph.fromJson(
      geojson!['navigation_graph'] as Map<String, dynamic>,
    );

    expect(screenGraph.nodes.length, 3);
    expect(
      screenGraph.nodes.map((node) => node.id),
      isNot(contains(entranceDoorNodeId('exit-1'))),
    );
  });

  test('건물 전체 그래프에도 문 노드가 꿰매진다', () async {
    final repository = _repository();

    final graph = await repository.getBuildingGraph('bldg-001');

    final door = graph!.nodes.singleWhere(
      (node) => node.id == entranceDoorNodeId('exit-1'),
    );
    expect(door.floorId, 'floor-1');
  });

  // 출구 데이터를 못 받았다고 층 간 길찾기까지 죽으면 안 된다.
  test('층 도면을 못 받으면 꿰매지 않고 원본 그래프를 돌려준다', () async {
    final repository = _repository(floorFound: false);

    final graph = await repository.getBuildingGraph('bldg-001');

    expect(graph!.nodes.length, 3);
  });
}
