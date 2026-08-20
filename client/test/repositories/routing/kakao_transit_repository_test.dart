import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/route/transit_route.dart';
import 'package:navigation_client/repositories/routing/kakao_transit_repository.dart';

// 카카오맵 대중교통 경로 조회(GET /v2/routing/publictraffic) 실제 응답을 옮긴
// 픽스처다. 좌표 배열만 줄였고 시간·거리·구조는 더현대 서울 → 강남역 호출에서
// 받은 값 그대로다.
//
// 확인 지점 네 가지:
//  1. 첫 step이 SUBWAY다 — 출발지에서 역까지 걸어가는 구간이 응답에 없다.
//  2. 그런데 totalTime(2022)은 steps 시간 합(915+218+103=1236)보다 786초 크다.
//     그 786초가 빠진 앞뒤 도보이며, totalWalkTime을 여기서 복원한다.
//  3. WALKING step에도 stops가 둘 붙어 온다 — 도보에 "1정거장"이 찍히면 안 된다.
//  4. 노선 색상 필드가 없다.
const _sampleResponseBody = '''
{
  "status": "OK",
  "properties": {
    "total": 2,
    "bus": 1,
    "subway": 1,
    "busAndSubway": 0
  },
  "routes": [
    {
      "properties": {
        "type": "SUBWAY",
        "totalDistance": 11948,
        "totalTime": 2022,
        "transfers": 1,
        "fare": { "value": 2350 }
      },
      "steps": [
        {
          "properties": {
            "guidance": "9호선 (여의도 > 신논현)",
            "type": "SUBWAY",
            "distance": 10100,
            "time": 915,
            "stops": [
              { "name": "여의도" },
              { "name": "노량진" },
              { "name": "동작" },
              { "name": "고속터미널" },
              { "name": "신논현" }
            ],
            "vehicles": [ { "name": "9호선", "type": "급행" } ]
          },
          "path": {
            "points": [
              [126.92430000, 37.52150000],
              [127.02510000, 37.50450000]
            ]
          }
        },
        {
          "properties": {
            "guidance": "신논현 신논현역 하차",
            "type": "WALKING",
            "distance": 141,
            "time": 218,
            "stops": [
              { "name": "신논현" },
              { "name": "신논현역" }
            ]
          },
          "path": {
            "points": [
              [127.02510000, 37.50450000],
              [127.02480000, 37.50410000]
            ]
          }
        },
        {
          "properties": {
            "guidance": "신분당선 (신논현 > 강남)",
            "type": "SUBWAY",
            "distance": 900,
            "time": 103,
            "stops": [
              { "name": "신논현" },
              { "name": "강남" }
            ],
            "vehicles": [ { "name": "신분당선", "type": "일반" } ]
          },
          "path": {
            "points": [
              [127.02480000, 37.50410000],
              [127.02760000, 37.49790000]
            ]
          }
        }
      ]
    },
    {
      "properties": {
        "type": "BUS",
        "totalDistance": 9800,
        "totalTime": 1500,
        "transfers": 0
      },
      "steps": [
        {
          "properties": {
            "guidance": "지선 5623외 6대 (한국거래소 > 여의도역6번출구)",
            "type": "BUS",
            "distance": 9400,
            "time": 1200,
            "stops": [
              { "name": "한국거래소" },
              { "name": "여의도역6번출구" }
            ],
            "vehicles": [
              { "name": "5623", "type": "지선" },
              { "name": "461", "type": "간선" },
              { "name": "753", "type": "간선" },
              { "name": "5012", "type": "지선" },
              { "name": "8561", "type": "지선" },
              { "name": "5618", "type": "지선" },
              { "name": "7007-1", "type": "지선" }
            ]
          },
          "path": {
            "points": [
              [126.92800000, 37.52590000],
              [127.02760000, 37.49790000]
            ]
          }
        }
      ]
    }
  ]
}
''';

/// 더현대 서울(여의도)과 강남역. 700m 자체 차단에 걸리지 않을 만큼 멀다.
const _origin = LatLng(37.5259, 126.9280);
const _destination = LatLng(37.4979, 127.0276);

MockClient _respondWith(String body, {int statusCode = 200}) {
  return MockClient((request) async {
    return http.Response.bytes(
      utf8.encode(body),
      statusCode,
      headers: {'content-type': 'application/json'},
    );
  });
}

void main() {
  test('구간·요금을 파싱하고 빠른 순으로 정렬한다', () async {
    late Uri requestUri;
    late Map<String, String> requestHeaders;
    final client = MockClient((request) async {
      requestUri = request.url;
      requestHeaders = request.headers;
      return http.Response.bytes(
        utf8.encode(_sampleResponseBody),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final repository = KakaoTransitRepository(
      client: client,
      restApiKey: 'test-key',
    );

    final routes = await repository.getTransitRoutes(
      origin: _origin,
      destination: _destination,
    );

    expect(routes.status, TransitRoutesStatus.ok);
    expect(routes.itineraries, hasLength(2));

    // 응답 순서(2022초 → 1500초)가 아니라 소요 시간 오름차순이어야 한다.
    expect(routes.itineraries.first.totalTimeSeconds, 1500);

    // 좌표는 (x=경도, y=위도)로 나가야 한다. 뒤집히면 STARTNODES_NULL이 온다.
    expect(requestUri.queryParameters['start_x'], '126.928');
    expect(requestUri.queryParameters['start_y'], '37.5259');
    expect(requestUri.queryParameters['end_x'], '127.0276');
    expect(requestUri.path, '/v2/routing/publictraffic');
    expect(requestHeaders['Authorization'], 'KakaoAK test-key');
  });

  test('빠진 앞뒤 도보 시간을 총계에서 복원한다', () async {
    final repository = KakaoTransitRepository(
      client: _respondWith(_sampleResponseBody),
      restApiKey: 'test-key',
    );

    final routes = await repository.getTransitRoutes(
      origin: _origin,
      destination: _destination,
    );
    final subwayRoute = routes.itineraries.firstWhere(
      (itinerary) => itinerary.totalTimeSeconds == 2022,
    );

    // 응답에 온 도보는 환승 218초뿐이지만, totalTime(2022)이 steps 합(1236)보다
    // 786초 크다. 그 차이가 응답에 없는 출발·도착 도보다.
    expect(subwayRoute.totalWalkTimeSeconds, 218 + 786);
    expect(subwayRoute.transferCount, 1);
    expect(subwayRoute.fare, 2350);
  });

  test('도보 구간의 stops는 정거장으로 세지 않는다', () async {
    final repository = KakaoTransitRepository(
      client: _respondWith(_sampleResponseBody),
      restApiKey: 'test-key',
    );

    final routes = await repository.getTransitRoutes(
      origin: _origin,
      destination: _destination,
    );
    final subwayRoute = routes.itineraries.firstWhere(
      (itinerary) => itinerary.totalTimeSeconds == 2022,
    );

    // 첫 step이 도보가 아니다 — 카카오는 첫 승차지점까지의 도보를 주지 않는다.
    expect(subwayRoute.legs.first.mode, TransitMode.subway);
    expect(subwayRoute.legs.first.stationCount, 4); // 정류장 5건 - 1
    // 중간 정류장은 버리지 않는다 — 상세 화면이 순서대로 늘어놓는다.
    expect(subwayRoute.legs.first.stopNames, [
      '여의도',
      '노량진',
      '동작',
      '고속터미널',
      '신논현',
    ]);
    expect(subwayRoute.legs.first.shortLabel, '9호선'); // "급행:" 접두사를 뗀다
    expect(subwayRoute.legs.first.routeColorHex, isNull); // 카카오는 색을 안 준다

    // 환승 도보에도 stops가 둘 붙어 오지만 "1정거장"이 되면 안 된다.
    final walk = subwayRoute.legs[1];
    expect(walk.mode, TransitMode.walk);
    expect(walk.stationCount, 0);
    expect(walk.stopNames, isEmpty); // 걷는 구간에 정류장을 찍으면 안 된다
    expect(walk.points, hasLength(2));
    expect(walk.points.first, const LatLng(37.5045, 127.0251));
  });

  test('같은 구간을 지나는 버스 여러 대는 "외 N대"로 접는다', () async {
    final repository = KakaoTransitRepository(
      client: _respondWith(_sampleResponseBody),
      restApiKey: 'test-key',
    );

    final routes = await repository.getTransitRoutes(
      origin: _origin,
      destination: _destination,
    );
    final busRoute = routes.itineraries.firstWhere(
      (itinerary) => itinerary.totalTimeSeconds == 1500,
    );

    expect(busRoute.legs.single.shortLabel, '5623외 6대');
    // 접었어도 원본 7대는 남아 있어야 한다 — 상세 화면이 번호 칩으로 쓴다.
    expect(busRoute.legs.single.vehicles, hasLength(7));
    expect(busRoute.legs.single.vehicles.last, (name: '7007-1', type: '지선'));
    // 요금 필드가 통째로 없는 경로가 실제로 온다. 0으로 채우면 "공짜"가 된다.
    expect(busRoute.fare, isNull);
  });

  test('count로 후보를 자른다 — 카카오는 요청으로 개수를 못 줄인다', () async {
    final repository = KakaoTransitRepository(
      client: _respondWith(_sampleResponseBody),
      restApiKey: 'test-key',
    );

    final routes = await repository.getTransitRoutes(
      origin: _origin,
      destination: _destination,
      count: 1,
    );

    expect(routes.itineraries, hasLength(1));
    expect(routes.itineraries.single.totalTimeSeconds, 1500);
  });

  test('700m 이내면 호출하지 않고 tooClose로 답한다', () async {
    // 카카오는 600m 거리에도 12분짜리 버스 경로를 OK로 준다. 걸어가면 되는
    // 상황이라는 신호가 응답에 없으므로 부르기 전에 우리가 자른다.
    final client = MockClient((request) async {
      fail('700m 이내인데 카카오를 호출했다');
    });
    final repository = KakaoTransitRepository(
      client: client,
      restApiKey: 'test-key',
    );

    final routes = await repository.getTransitRoutes(
      origin: const LatLng(37.5259, 126.9280),
      destination: const LatLng(37.5215, 126.9243),
    );

    expect(routes.status, TransitRoutesStatus.tooClose);
    expect(routes.itineraries, isEmpty);
  });

  test('EQUAL_POINTS는 tooClose로 구분한다', () async {
    final repository = KakaoTransitRepository(
      client: _respondWith(
        '{"status": "EQUAL_POINTS", "properties": {"total": 0}}',
      ),
      restApiKey: 'test-key',
    );

    expect(
      (await repository.getTransitRoutes(
        origin: _origin,
        destination: _destination,
      )).status,
      TransitRoutesStatus.tooClose,
    );
  });

  test('STARTNODES_NULL은 경로 없음이다 — 주변에 정류장이 없는 지역', () async {
    final repository = KakaoTransitRepository(
      client: _respondWith(
        '{"status": "STARTNODES_NULL", "properties": {"total": 0}}',
      ),
      restApiKey: 'test-key',
    );

    expect(
      (await repository.getTransitRoutes(
        origin: const LatLng(37.5000, 130.8600),
        destination: const LatLng(37.4800, 130.9000),
      )).status,
      TransitRoutesStatus.noRoute,
    );
  });

  test('HTTP 오류는 failed로 구분한다 — 재시도가 의미 있는 유일한 상태다', () async {
    // 401은 키가 틀렸거나 [제품 설정] > [카카오맵] 사용 설정이 꺼진 경우다.
    final repository = KakaoTransitRepository(
      client: _respondWith(
        '{"code": -10, "msg": "API limit has been exceeded."}',
        statusCode: 401,
      ),
      restApiKey: 'test-key',
    );

    expect(
      (await repository.getTransitRoutes(
        origin: _origin,
        destination: _destination,
      )).status,
      TransitRoutesStatus.failed,
    );
  });

  test('키가 없으면 isAvailable이 false다', () {
    expect(KakaoTransitRepository(restApiKey: '').isAvailable, isFalse);
    expect(KakaoTransitRepository(restApiKey: 'k').isAvailable, isTrue);
  });
}
