import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/route/directions_route.dart';
import 'package:navigation_client/repositories/routing/tmap_directions_repository.dart';

// 실제 TMAP 보행자 경로 API(POST /routes/pedestrian) 응답을 그대로 캡처한 픽스처.
// (2026-07-06, 시청 근처 출발지/목적지 200m 남짓 도보 경로로 실제 검증함)
const _sampleResponseBody = '''
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "geometry": { "type": "Point", "coordinates": [126.97784881268932, 37.56814892738826] },
      "properties": { "totalDistance": 265, "totalTime": 228, "pointType": "SP" }
    },
    {
      "type": "Feature",
      "geometry": {
        "type": "LineString",
        "coordinates": [
          [126.97784881268932, 37.56814892738826],
          [126.97758217189669, 37.56809337350867],
          [126.97732664120262, 37.56803781982844]
        ]
      },
      "properties": { "distance": 48, "time": 36 }
    },
    {
      "type": "Feature",
      "geometry": { "type": "Point", "coordinates": [126.97732664120262, 37.56803781982844] },
      "properties": { "pointType": "GP" }
    },
    {
      "type": "Feature",
      "geometry": {
        "type": "LineString",
        "coordinates": [
          [126.97732664120262, 37.56803781982844],
          [126.97735166479588, 37.56712403764582],
          [126.97738499564204, 37.56710459606009]
        ]
      },
      "properties": { "distance": 105, "time": 105 }
    },
    {
      "type": "Feature",
      "geometry": { "type": "Point", "coordinates": [126.97738499564204, 37.56710459606009] },
      "properties": { "pointType": "GP" }
    },
    {
      "type": "Feature",
      "geometry": {
        "type": "LineString",
        "coordinates": [
          [126.97738499564204, 37.56710459606009],
          [126.97738499902333, 37.56698516550335]
        ]
      },
      "properties": { "distance": 13, "time": 9 }
    },
    {
      "type": "Feature",
      "geometry": { "type": "Point", "coordinates": [126.97738499902333, 37.56698516550335] },
      "properties": { "pointType": "GP" }
    },
    {
      "type": "Feature",
      "geometry": {
        "type": "LineString",
        "coordinates": [
          [126.97738499902333, 37.56698516550335],
          [126.97736001136667, 37.56662965083942]
        ]
      },
      "properties": { "distance": 41, "time": 30 }
    },
    {
      "type": "Feature",
      "geometry": { "type": "Point", "coordinates": [126.97736001136667, 37.56662965083942] },
      "properties": { "pointType": "GP" }
    },
    {
      "type": "Feature",
      "geometry": {
        "type": "LineString",
        "coordinates": [
          [126.97736001136667, 37.56662965083942],
          [126.97789607606079, 37.5665435593568]
        ]
      },
      "properties": { "distance": 58, "time": 48 }
    },
    {
      "type": "Feature",
      "geometry": { "type": "Point", "coordinates": [126.97789607606079, 37.5665435593568] },
      "properties": { "pointType": "EP" }
    }
  ]
}
''';

// 자동차 경로(POST /routes) 응답. 보행자와 같은 FeatureCollection이고,
// 첫 Feature의 properties에 요금 두 줄(totalFare·taxiFare)이 더 붙는다.
const _drivingResponseBody = '''
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "geometry": { "type": "Point", "coordinates": [126.7, 37.63] },
      "properties": {
        "totalDistance": 30400,
        "totalTime": 2100,
        "totalFare": 0,
        "taxiFare": 30000,
        "pointType": "S"
      }
    },
    {
      "type": "Feature",
      "geometry": {
        "type": "LineString",
        "coordinates": [[126.7, 37.63], [126.85, 37.56], [126.92, 37.53]]
      },
      "properties": { "distance": 30400, "time": 2100 }
    }
  ]
}
''';

// searchOption '10'(최단거리) 전용 응답. 좌표가 달라야 병합에서 따로 남는다.
const _shortestDistanceResponseBody = '''
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "geometry": { "type": "Point", "coordinates": [126.7, 37.63] },
      "properties": {
        "totalDistance": 28000,
        "totalTime": 1900,
        "totalFare": 0,
        "taxiFare": 28000,
        "pointType": "S"
      }
    },
    {
      "type": "Feature",
      "geometry": {
        "type": "LineString",
        "coordinates": [[126.7, 37.63], [126.80, 37.58], [126.92, 37.53]]
      },
      "properties": { "distance": 28000, "time": 1900 }
    }
  ]
}
''';

// 합성 픽스처(실측 아님) — 방위각 계산을 검증하려고 손으로 만든 직각 경로.
// 북쪽(0,0)->(0,0.002)으로 가다 안내지점에서 동쪽(0.002,0.002)으로 90도
// 꺾인다. 손으로 방위각을 계산해 검증한 값이라 기대값이 정확하다.
const _turnSampleResponseBody = '''
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "geometry": { "type": "Point", "coordinates": [0, 0] },
      "properties": { "totalDistance": 380, "totalTime": 290, "pointType": "SP" }
    },
    {
      "type": "Feature",
      "geometry": { "type": "LineString", "coordinates": [[0, 0], [0, 0.002]] },
      "properties": { "distance": 200, "time": 150 }
    },
    {
      "type": "Feature",
      "geometry": { "type": "Point", "coordinates": [0, 0.002] },
      "properties": { "pointType": "GP" }
    },
    {
      "type": "Feature",
      "geometry": { "type": "LineString", "coordinates": [[0, 0.002], [0.002, 0.002]] },
      "properties": { "distance": 180, "time": 140 }
    },
    {
      "type": "Feature",
      "geometry": { "type": "Point", "coordinates": [0.002, 0.002] },
      "properties": { "pointType": "EP" }
    }
  ]
}
''';

// 안내지점 3개(SP·GP·EP)에 구간 2개가 있어 개수 검사는 통과하지만, 두 번째
// LineString이 좌표 1쌍뿐인 퇴화 도형이다 — 서버가 이런 응답을 보낸 적은
// 없지만 방위각 계산이 좌표 2개를 가정하므로 방어선을 검증한다.
const _degenerateLineResponseBody = '''
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "geometry": { "type": "Point", "coordinates": [0, 0] },
      "properties": { "totalDistance": 100, "totalTime": 80, "pointType": "SP" }
    },
    {
      "type": "Feature",
      "geometry": { "type": "LineString", "coordinates": [[0, 0], [0, 0.001]] },
      "properties": { "distance": 50, "time": 40 }
    },
    {
      "type": "Feature",
      "geometry": { "type": "Point", "coordinates": [0, 0.001] },
      "properties": { "pointType": "GP" }
    },
    {
      "type": "Feature",
      "geometry": { "type": "LineString", "coordinates": [[0, 0.001]] },
      "properties": { "distance": 50, "time": 40 }
    },
    {
      "type": "Feature",
      "geometry": { "type": "Point", "coordinates": [0, 0.002] },
      "properties": { "pointType": "EP" }
    }
  ]
}
''';

void main() {
  test(
    'parses distance/time from the first feature and flattens the path',
    () async {
      final client = MockClient((request) async {
        return http.Response(
          _sampleResponseBody,
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final repository = TmapDirectionsRepository(client: client);

      final route = await repository.getWalkingRoute(
        origin: const LatLng(37.56814892738826, 126.97784881268932),
        destination: const LatLng(37.5665435593568, 126.97789607606079),
      );

      expect(route, isNotNull);
      expect(route!.distanceMeters, 265);
      expect(route.durationSeconds, 228);
      // 시작점과 끝점이 실제 경로 좌표와 일치하는지 확인
      expect(
        route.points.first,
        const LatLng(37.56814892738826, 126.97784881268932),
      );
      expect(
        route.points.last,
        const LatLng(37.5665435593568, 126.97789607606079),
      );
      expect(route.points, isNotEmpty);
    },
  );

  test('자동차 경로는 /routes를 부르고 요금까지 읽는다', () async {
    Uri? calledUri;
    Map<String, String>? sentFields;
    final client = MockClient((request) async {
      calledUri = request.url;
      sentFields = request.bodyFields;
      return http.Response(
        _drivingResponseBody,
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final repository = TmapDirectionsRepository(client: client);

    final route = await repository.getDrivingRoute(
      origin: const LatLng(37.63, 126.7),
      destination: const LatLng(37.53, 126.92),
    );

    // 보행자 경로와 **다른 엔드포인트**를 불러야 한다. 같은 주소로 보내면
    // 자동차 탭에 사람이 걸어가는 길이 그려지고, 35분짜리 거리가 8시간으로 뜬다.
    expect(calledUri?.path, endsWith('/tmap/routes'));
    expect(sentFields?['startY'], '37.63');
    expect(route, isNotNull);
    expect(route!.distanceMeters, 30400);
    expect(route.durationSeconds, 2100);
    // 통행료 0은 "무료"이지 "정보 없음"이 아니다. null로 뭉개면 화면이
    // "통행료 없음"을 말하지 못한다.
    expect(route.tollFareWon, 0);
    expect(route.taxiFareWon, 30000);
    expect(route.points.length, 3);
  });

  test('보행자 경로에는 요금 필드가 없어 null로 남는다', () async {
    final client = MockClient((request) async {
      return http.Response(
        _sampleResponseBody,
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final repository = TmapDirectionsRepository(client: client);

    final route = await repository.getWalkingRoute(
      origin: const LatLng(37.56814892738826, 126.97784881268932),
      destination: const LatLng(37.5665435593568, 126.97789607606079),
    );

    expect(route!.tollFareWon, isNull);
    expect(route.taxiFareWon, isNull);
  });

  test('returns null on a non-200 response', () async {
    final client = MockClient((request) async {
      return http.Response('{"error": {"code": "INVALID_API_KEY"}}', 403);
    });
    final repository = TmapDirectionsRepository(client: client);

    final route = await repository.getWalkingRoute(
      origin: const LatLng(37.5665, 126.9780),
      destination: const LatLng(37.5670, 126.9790),
    );

    expect(route, isNull);
  });

  test('안내 지점을 좌회전/우회전/직진으로 계산해 스텝을 만든다', () async {
    final client = MockClient((request) async {
      return http.Response(
        _turnSampleResponseBody,
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final repository = TmapDirectionsRepository(client: client);

    final route = await repository.getWalkingRoute(
      origin: const LatLng(0, 0),
      destination: const LatLng(0.002, 0.002),
    );

    expect(route!.steps.length, 3);
    expect(route.steps[0].instruction, '출발');
    expect(route.steps[0].distanceMeters, 0);
    expect(route.steps[1].instruction, '우회전');
    expect(route.steps[1].distanceMeters, 200);
    expect(route.steps[2].instruction, '도착');
    expect(route.steps[2].distanceMeters, 180);
  });

  test('기존 자동차 응답(1 Point/1 LineString)은 스텝을 생성하지 않는다', () async {
    final client = MockClient((request) async {
      return http.Response(
        _drivingResponseBody,
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final repository = TmapDirectionsRepository(client: client);

    final route = await repository.getDrivingRoute(
      origin: const LatLng(37.63, 126.7),
      destination: const LatLng(37.53, 126.92),
    );

    // 이 응답은 Feature 구조가 SP(Point) + 선분(LineString) 하나로
    // 이루어져 있다(SP-[LineString]-EP 구조가 아님). 안내지점 개수(1)가
    // 구간 개수(1)와 다르므로, _computeSteps는 예상 구조 불일치를
    // 감지해 빈 목록으로 돌아온다.
    expect(route!.steps, isEmpty);
  });

  test('자동차 후보 4개를 조회해 좌표로 중복 제거한다', () async {
    final client = MockClient((request) async {
      final option = request.bodyFields['searchOption'];
      final body = option == '10'
          ? _shortestDistanceResponseBody
          : _drivingResponseBody; // '0','2','3'은 같은 응답 -> 하나로 합쳐짐
      return http.Response(
        body,
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final repository = TmapDirectionsRepository(client: client);

    final options = await repository.getDrivingRouteOptions(
      origin: const LatLng(37.63, 126.7),
      destination: const LatLng(37.53, 126.92),
    );

    expect(options.status, DirectionsRouteOptionsStatus.ok);
    expect(options.options.length, 2);
    // searchOption 2·3이 둘 다 alternative로 매핑되지만 kinds에는 한 번만
    // 남는다. 같은 kind가 두 번 있는 것은 목록의 사실이 아니라 요청 방식의
    // 부산물이다(domain/route/directions_route_merge.dart).
    expect(options.options[0].kinds, [
      DirectionsRouteOptionKind.recommended,
      DirectionsRouteOptionKind.alternative,
    ]);
    expect(options.options[1].kinds, [DirectionsRouteOptionKind.shortestDistance]);
  });

  test('좌표 1개뿐인 퇴화 LineString이 있어도 던지지 않고 스텝을 비운다', () async {
    final client = MockClient((request) async {
      return http.Response(
        _degenerateLineResponseBody,
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final repository = TmapDirectionsRepository(client: client);

    final route = await repository.getWalkingRoute(
      origin: const LatLng(0, 0),
      destination: const LatLng(0.002, 0),
    );

    expect(route, isNotNull);
    expect(route!.steps, isEmpty);
  });

  test('전부 실패하면 failed 상태를 돌려준다', () async {
    final client = MockClient((request) async => http.Response('', 500));
    final repository = TmapDirectionsRepository(client: client);

    final options = await repository.getDrivingRouteOptions(
      origin: const LatLng(37.63, 126.7),
      destination: const LatLng(37.53, 126.92),
    );

    expect(options.status, DirectionsRouteOptionsStatus.failed);
    expect(options.options, isEmpty);
  });
}
