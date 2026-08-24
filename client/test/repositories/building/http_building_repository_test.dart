import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navigation_client/repositories/building/http_building_repository.dart';

void main() {
  group('getBuildingEvents', () {
    /// 서버가 주는 것은 **기간이라는 규칙뿐**이다. 오늘 열리는지는 화면이 기기
    /// 로컬 날짜로 판정하므로, 저장소는 날짜로 좁히지 않은 통짜를 받아야 한다.
    test('행사 경로를 그대로 부르고 응답을 통짜로 돌려준다', () async {
      String? path;
      final client = MockClient((request) async {
        path = request.url.path;
        return http.Response(
          jsonEncode({
            'captured_on': '2026-08-21',
            'diaries': [
              {'key': 'popup', 'title': 'WEEKLY POP-UP'},
            ],
            'events': [
              {
                'title': '이번 주 팝업',
                'start': '2026-08-20',
                'end': '2026-08-26',
                'store_id': 'PO-icon',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final repository = HttpBuildingRepository(client: client);

      final events = await repository.getBuildingEvents('thehyundai-seoul');

      expect(path, endsWith('/buildings/thehyundai-seoul/events'));
      expect(events?['captured_on'], '2026-08-21');
      expect((events?['events'] as List).single['store_id'], 'PO-icon');
    });

    /// 빈 목록으로 떨어뜨리면 "행사가 없는 건물"과 "아직 안 모은 건물"이 같은
    /// 화면이 된다. 그 구분은 null이 진다.
    test('모아 둔 것이 없는 건물은 빈 목록이 아니라 null이다', () async {
      final client = MockClient((request) async => http.Response('', 404));
      final repository = HttpBuildingRepository(client: client);

      expect(await repository.getBuildingEvents('no-such-building'), isNull);
    });
  });

  group('getBuilding', () {
    test('caches the response so a second call skips the network', () async {
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        return http.Response(
          jsonEncode({
            'id': 'bldg-001',
            'name': '데모 건물',
            'floors': ['1F', '2F'],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final repository = HttpBuildingRepository(client: client);

      final first = await repository.getBuilding('bldg-001');
      final second = await repository.getBuilding('bldg-001');

      expect(first?.name, '데모 건물');
      expect(second?.name, '데모 건물');
      expect(requestCount, 1);
    });

    // 야외 지도·실내 지도·카테고리 목록이 같은 프레임에 같은 건물을 부른다.
    // 값만 캐시하면 await가 끝나기 전이라 셋 다 캐시 미스가 되어 각자 네트워크를
    // 탄다 — 실측 로그에서 /buildings/{id}가 같은 초에 12건까지 나갔다.
    test('동시에 부르면 요청 하나를 함께 기다린다', () async {
      var requestCount = 0;
      final gate = Completer<void>();
      final client = MockClient((request) async {
        requestCount++;
        await gate.future; // 첫 요청을 일부러 붙잡아 "진행 중" 창을 만든다
        return http.Response(
          jsonEncode({
            'id': 'bldg-001',
            'name': '데모 건물',
            'floors': ['1F'],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final repository = HttpBuildingRepository(client: client);

      final pending = Future.wait([
        repository.getBuilding('bldg-001'),
        repository.getBuilding('bldg-001'),
        repository.getBuilding('bldg-001'),
      ]);
      gate.complete();
      final results = await pending;

      expect(results.map((b) => b?.name), everyElement('데모 건물'));
      expect(requestCount, 1);
    });

    test('동시에 부른 층도 요청 하나로 합쳐진다', () async {
      var requestCount = 0;
      final gate = Completer<void>();
      final client = MockClient((request) async {
        requestCount++;
        await gate.future;
        return http.Response(
          jsonEncode({'type': 'FeatureCollection', 'features': []}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final repository = HttpBuildingRepository(client: client);

      final pending = Future.wait([
        repository.getFloorGeoJson('bldg-001', '1F'),
        repository.getFloorGeoJson('bldg-001', '1F'),
      ]);
      gate.complete();
      await pending;

      expect(requestCount, 1);
    });

    // 잠깐 끊긴 네트워크가 영구 실패로 굳으면 재시도 경로(건물 로드 실패 배지)가
    // 죽는다. 실패한 Future는 캐시에서 빠져야 한다.
    test('실패는 캐시에 남지 않아 재시도가 다시 네트워크를 탄다', () async {
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        if (requestCount == 1) throw const SocketException('연결 실패');
        return http.Response(
          jsonEncode({
            'id': 'bldg-001',
            'name': '데모 건물',
            'floors': ['1F'],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final repository = HttpBuildingRepository(client: client);

      await expectLater(repository.getBuilding('bldg-001'), throwsA(anything));
      final retried = await repository.getBuilding('bldg-001');

      expect(retried?.name, '데모 건물');
      expect(requestCount, 2);
    });

    test('does not cache a 404 response', () async {
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        return http.Response('', 404);
      });
      final repository = HttpBuildingRepository(client: client);

      final first = await repository.getBuilding('unknown');
      final second = await repository.getBuilding('unknown');

      expect(first, isNull);
      expect(second, isNull);
      expect(requestCount, 2);
    });
  });

  group('getFloorGeoJson', () {
    test('caches per building+floor combination', () async {
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        return http.Response(
          jsonEncode({'type': 'FeatureCollection', 'features': []}),
          200,
        );
      });
      final repository = HttpBuildingRepository(client: client);

      await repository.getFloorGeoJson('bldg-001', '1F');
      await repository.getFloorGeoJson('bldg-001', '1F'); // 같은 조합 → 캐시 재사용
      await repository.getFloorGeoJson('bldg-001', '2F'); // 다른 층 → 새 요청

      // 층마다 /floors/{floor} 요청 1번씩만, 캐시된 재호출은 요청 없음.
      expect(requestCount, 2);
    });

    test('does not call the separate /graph endpoint', () async {
      final requestPaths = <String>[];
      final client = MockClient((request) async {
        requestPaths.add(request.url.path);
        return http.Response(
          jsonEncode({'type': 'FeatureCollection', 'features': []}),
          200,
        );
      });
      final repository = HttpBuildingRepository(client: client);

      await repository.getFloorGeoJson('bldg-001', '1F');

      expect(requestPaths, ['/buildings/bldg-001/floors/1F']);
      expect(requestPaths.any((path) => path.endsWith('/graph')), isFalse);
    });

    test('maps navigation_graph edges into corridors_local_m', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'floor': '1F',
            'footprint_local_m': [],
            'stores': [],
            'pois': [],
            'navigation_graph': {
              'floor': {'id': '1F', 'name': '1층'},
              'nodes': [
                {'id': 'A', 'type': 'corridor', 'x_m': 0.0, 'y_m': 0.0},
                {'id': 'B', 'type': 'corridor', 'x_m': 1.0, 'y_m': 1.0},
              ],
              'edges': [
                {
                  'id': 'e1',
                  'from': 'A',
                  'to': 'B',
                  'length_m': 1.4142,
                  'bidirectional': true,
                  'geometry_local_m': [
                    {'x': 0.0, 'y': 0.0},
                    {'x': 1.0, 'y': 1.0},
                  ],
                },
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final repository = HttpBuildingRepository(client: client);

      final geojson = await repository.getFloorGeoJson('bldg-001', '1F');

      expect(geojson!['corridors_local_m'], [
        [
          {'x': 0.0, 'y': 0.0},
          {'x': 1.0, 'y': 1.0},
        ],
      ]);
    });

    test(
      'reuses the floor response graph for the following route request',
      () async {
        final requestPaths = <String>[];
        final client = MockClient((request) async {
          requestPaths.add(request.url.path);
          return http.Response(
            jsonEncode({
              'floor': {'id': 'floor-1f', 'name': '1F'},
              'footprint_local_m': [],
              'stores': [],
              'pois': [],
              'navigation_graph': {
                'floor': {'id': 'floor-1f', 'name': '1F'},
                'nodes': [
                  {
                    'id': 'A',
                    'type': 'corridor',
                    'name': null,
                    'x_m': 0.0,
                    'y_m': 0.0,
                    'lat': 37.0,
                    'lng': 127.0,
                  },
                  {
                    'id': 'B',
                    'type': 'corridor',
                    'name': null,
                    'x_m': 2.0,
                    'y_m': 0.0,
                    'lat': 37.0,
                    'lng': 127.0,
                  },
                ],
                'edges': [
                  {
                    'id': 'AB',
                    'from': 'A',
                    'to': 'B',
                    'length_m': 2.0,
                    'bidirectional': true,
                    'geometry_local_m': [],
                  },
                ],
              },
            }),
            200,
          );
        });
        final repository = HttpBuildingRepository(client: client);

        await repository.getFloorGeoJson('bldg-001', '1F');
        final route = await repository.getShortestRoute(
          'bldg-001',
          '1F',
          'A',
          'B',
        );

        expect(route?.distanceMeters, 2.0);
        expect(requestPaths, ['/buildings/bldg-001/floors/1F']);
      },
    );
  });

  group('getShortestRoute', () {
    // 그래프(nodes+edges)는 이제 별도 /graph 엔드포인트가 아니라
    // GET /buildings/{id}/floors/{floor} 응답에 함께 내려오는 navigation_graph
    // 하나에서만 얻는다. api/app/schemas/floor_map.py::FloorMapResponse와 동일한
    // 모양(최소 navigation_graph만 채움).
    //
    // N1 -> N3 직행 간선(10.0)보다 N1 -> N2 -> N3 우회 경로(2.0 + 3.0 = 5.0)가
    // 더 짧으므로, 다익스트라가 실제로 우회 경로를 골랐는지(노드 순서)까지
    // 검증할 수 있다.
    Map<String, dynamic> floorResponse() => {
      'floor': {'id': '1F', 'name': '1층', 'level': 1},
      'navigation_coordinate_system': 'local_m',
      'footprint_local_m': <Map<String, double>>[],
      'vector_map': null,
      'navigation_graph': {
        'floor': {'id': '1F', 'name': '1층'},
        'nodes': [
          {
            'id': 'N1',
            'type': 'corridor',
            'name': null,
            'x_m': 0.0,
            'y_m': 0.0,
            'lat': 37.5260,
            'lng': 126.9280,
          },
          {
            'id': 'N2',
            'type': 'corridor',
            'name': null,
            'x_m': 2.0,
            'y_m': 1.0,
            'lat': 37.5261,
            'lng': 126.9281,
          },
          {
            'id': 'N3',
            'type': 'corridor',
            'name': null,
            'x_m': 5.0,
            'y_m': 0.0,
            'lat': 37.5262,
            'lng': 126.9282,
          },
        ],
        'edges': [
          {
            'id': 'E_DIRECT',
            'from': 'N1',
            'to': 'N3',
            'length_m': 10.0,
            'bidirectional': true,
            'geometry_local_m': <Map<String, double>>[],
          },
          {
            'id': 'E1',
            'from': 'N1',
            'to': 'N2',
            'length_m': 2.0,
            'bidirectional': true,
            'geometry_local_m': <Map<String, double>>[],
          },
          {
            'id': 'E2',
            'from': 'N2',
            'to': 'N3',
            'length_m': 3.0,
            'bidirectional': true,
            'geometry_local_m': <Map<String, double>>[],
          },
        ],
      },
      'stores': <Map<String, dynamic>>[],
      'pois': <Map<String, dynamic>>[],
    };

    test('GET /floors/{floor} 응답 하나로 최단 경로를 계산한다(별도 /graph 요청 없음)', () async {
      final requestPaths = <String>[];
      final client = MockClient((request) async {
        requestPaths.add(request.url.path);
        return http.Response(
          jsonEncode(floorResponse()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final repository = HttpBuildingRepository(client: client);

      final route = await repository.getShortestRoute(
        'thehyundai-seoul',
        '1F',
        'N1',
        'N3',
      );

      // 요청 경로가 /buildings/thehyundai-seoul/floors/1F 하나뿐이어야 한다.
      expect(requestPaths, ['/buildings/thehyundai-seoul/floors/1F']);

      // 거리: 직행(10.0)이 아니라 N1->N2->N3 우회(2.0+3.0=5.0)를 골라야 한다.
      expect(route?.distanceMeters, 5.0);

      // 노드 순서: 세 노드의 lat/lng을 N1, N2, N3 순서로 그대로 지난다
      // (간선 geometry가 비어 있어 노드 좌표 사이를 직선으로 잇기 때문).
      expect(route?.points.length, 3);
      expect(route!.points[0].latitude, closeTo(37.5260, 1e-9));
      expect(route.points[0].longitude, closeTo(126.9280, 1e-9));
      expect(route.points[1].latitude, closeTo(37.5261, 1e-9));
      expect(route.points[1].longitude, closeTo(126.9281, 1e-9));
      expect(route.points[2].latitude, closeTo(37.5262, 1e-9));
      expect(route.points[2].longitude, closeTo(126.9282, 1e-9));
    });

    test(
      'reuses the cached floor response for a second node pair on the same floor',
      () async {
        var requestCount = 0;
        final client = MockClient((request) async {
          requestCount++;
          return http.Response(
            jsonEncode(floorResponse()),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });
        final repository = HttpBuildingRepository(client: client);

        final first = await repository.getShortestRoute(
          'thehyundai-seoul',
          '1F',
          'N1',
          'N2',
        );
        final second = await repository.getShortestRoute(
          'thehyundai-seoul',
          '1F',
          'N1',
          'N3',
        );

        expect(first?.distanceMeters, 2.0);
        expect(second?.distanceMeters, 5.0);
        // 층 응답은 한 번만 요청하고(캐시), 두 경로 계산 모두 로컬에서 수행한다.
        expect(requestCount, 1);
      },
    );

    test('returns null when the floor is not found (404)', () async {
      final client = MockClient((request) async {
        return http.Response('', 404);
      });
      final repository = HttpBuildingRepository(client: client);

      final result = await repository.getShortestRoute(
        'thehyundai-seoul',
        '1F',
        'N1',
        'N2',
      );

      expect(result, isNull);
    });

    test('returns null for a node ID that is not in the graph', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode(floorResponse()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final repository = HttpBuildingRepository(client: client);

      final result = await repository.getShortestRoute(
        'thehyundai-seoul',
        '1F',
        'N1',
        'unknown',
      );

      expect(result, isNull);
    });
  });

  group('getAllBuildings', () {
    test('does not let the slim list response satisfy getBuilding', () async {
      // 목록에는 tile_revision이 없다(단건 응답에만 있다). 목록으로 개별 캐시를
      // 채우면 그 뒤 실내 타일 URL에 `?v=`가 안 붙어 서버 캐시가 1년 immutable
      // 대신 60초로 떨어지고, 층을 바꿀 때마다 타일을 다시 받게 된다.
      var listCount = 0;
      var singleCount = 0;
      final client = MockClient((request) async {
        final isList = request.url.path.endsWith('/buildings');
        if (isList) {
          listCount++;
          return http.Response(
            jsonEncode([
              {
                'id': 'bldg-001',
                'name': '데모 건물',
                'floors': ['1F', '2F'],
              },
            ]),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        singleCount++;
        return http.Response(
          jsonEncode({
            'id': 'bldg-001',
            'name': '데모 건물',
            'floors': ['1F', '2F'],
            'tile_revision': 'rev-1',
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final repository = HttpBuildingRepository(client: client);

      await repository.getAllBuildings();
      await repository.getAllBuildings();
      final building = await repository.getBuilding('bldg-001');

      // 목록 자체는 여전히 한 번만 받는다.
      expect(listCount, 1);
      // 개별 조회는 단건 엔드포인트를 타야 tile_revision이 채워진다.
      expect(singleCount, 1);
      expect(building?.name, '데모 건물');
      expect(building?.tileRevision, 'rev-1');
    });
  });
}
