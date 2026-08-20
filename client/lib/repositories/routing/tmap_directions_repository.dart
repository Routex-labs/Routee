import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../core/api_config.dart';
import '../../domain/route/directions_route_merge.dart';
import '../../models/route/directions_route.dart';
import 'directions_repository.dart';

/// TMAP(SK Open API) 경로 안내.
///
/// - 보행자: POST `/routes/pedestrian` — https://openapi.sk.com/products/detail?linkMenuSeq=45
/// - 자동차: POST `/routes` — 같은 appKey로 호출한다.
///
/// 두 응답이 **같은 모양**이라 파싱을 한 곳에 모았다(FeatureCollection이고,
/// 총 거리·시간은 첫 Feature의 properties에만 들어 있으며, 선은 LineString
/// Feature들에 쪼개져 있다). 다른 것은 자동차 응답에만 요금 필드가 붙는 정도다.
class TmapDirectionsRepository implements DirectionsRepository {
  TmapDirectionsRepository({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<DirectionsRoute?> getWalkingRoute({
    required LatLng origin,
    required LatLng destination,
  }) {
    return _request(
      Uri.parse('$tmapBaseUrl/routes/pedestrian?version=1'),
      origin: origin,
      destination: destination,
    );
  }

  @override
  Future<DirectionsRoute?> getDrivingRoute({
    required LatLng origin,
    required LatLng destination,
  }) {
    return _request(
      Uri.parse('$tmapBaseUrl/routes?version=1'),
      origin: origin,
      destination: destination,
      // 0 = 교통최적+추천. 화면에 "내비 추천"으로 적는 값이라 여기서 고정한다 —
      // 옵션을 사용자에게 열어 두려면 그때 인자로 올린다.
      extra: const {'searchOption': '0', 'trafficInfo': 'N'},
    );
  }

  /// 자동차 후보를 만들려고 물어보는 `searchOption` 값들. **순서가 곧
  /// kind 대응 순서다.** TMAP에는 대안 경로를 한 번에 주는 엔드포인트가
  /// 없어, 값을 바꿔 여러 번 묻고 우리가 비교해 후보를 만든다. 후보를 합칠
  /// 때 총거리·시간이 아니라 좌표열로 비교하는 이유: 길이가 같은 다른
  /// 도로를 같은 경로로 묶거나, 같은 도로를 반올림 오차로 다른 경로로
  /// 가르는 것을 막기 위해서다.
  static const _drivingSearchOptions = [
    ('0', DirectionsRouteOptionKind.recommended),
    ('2', DirectionsRouteOptionKind.alternative),
    ('3', DirectionsRouteOptionKind.alternative),
    ('10', DirectionsRouteOptionKind.shortestDistance),
  ];

  @override
  Future<DirectionsRouteOptions> getDrivingRouteOptions({
    required LatLng origin,
    required LatLng destination,
  }) async {
    // 동시에 보낸다 — 순서대로 기다리면 옵션 수만큼 왕복 시간이 곱해진다.
    final responses = await Future.wait([
      for (final (option, kind) in _drivingSearchOptions)
        _request(
          Uri.parse('$tmapBaseUrl/routes?version=1'),
          origin: origin,
          destination: destination,
          extra: {'searchOption': option, 'trafficInfo': 'N'},
        ).then((route) => (kind, route)),
    ]);

    final candidates = [
      for (final (kind, route) in responses)
        if (route != null) (kind, route),
    ];
    if (candidates.isEmpty) {
      return const DirectionsRouteOptions.failure();
    }
    return DirectionsRouteOptions.ok(mergeDirectionsRouteOptions(candidates));
  }

  Future<DirectionsRoute?> _request(
    Uri uri, {
    required LatLng origin,
    required LatLng destination,
    Map<String, String> extra = const {},
  }) async {
    final http.Response response;
    try {
      response = await _client.post(
        uri,
        headers: {'appKey': tmapAppKey},
        body: {
          'startX': origin.longitude.toString(),
          'startY': origin.latitude.toString(),
          'endX': destination.longitude.toString(),
          'endY': destination.latitude.toString(),
          'reqCoordType': 'WGS84GEO',
          'resCoordType': 'WGS84GEO',
          'startName': '출발지',
          'endName': '목적지',
          ...extra,
        },
      );
    } on Object {
      // 네트워크가 끊긴 경우다. 여기서 던지면 화면이 통째로 죽으므로, 다른
      // 실패(키 오류·경로 없음)와 같은 자리로 모아 호출부가 한 가지 안내만
      // 하게 한다.
      return null;
    }

    if (response.statusCode != 200) return null;

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } on Object {
      return null;
    }
    final features = (body['features'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    if (features.isEmpty) return null;

    // totalDistance/totalTime은 첫 Feature의 properties에만 들어있다.
    final summary = features.first['properties'];
    if (summary is! Map<String, dynamic>) return null;
    final distanceMeters = _number(summary['totalDistance']);
    final durationSeconds = _number(summary['totalTime']);
    if (distanceMeters == null || durationSeconds == null) return null;

    final points = <LatLng>[];
    for (final feature in features) {
      final geometry = feature['geometry'] as Map<String, dynamic>?;
      if (geometry?['type'] != 'LineString') continue;
      for (final coordinate in geometry!['coordinates'] as List<dynamic>) {
        final pair = coordinate as List<dynamic>;
        points.add(
          LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble()),
        );
      }
    }

    return DirectionsRoute(
      points: points,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds.round(),
      // 보행자 응답에는 없는 필드라 null로 남는다. 그 null이 곧 "이 수단엔
      // 요금 개념이 없다"는 뜻이다([DirectionsRoute.tollFareWon]).
      tollFareWon: _number(summary['totalFare'])?.round(),
      taxiFareWon: _number(summary['taxiFare'])?.round(),
      steps: _computeSteps(features),
    );
  }

  static List<DirectionsRouteStep> _computeSteps(
    List<Map<String, dynamic>> features,
  ) {
    final points = <Map<String, dynamic>>[];
    final lines = <Map<String, dynamic>>[];
    for (final feature in features) {
      final geometry = feature['geometry'] as Map<String, dynamic>?;
      switch (geometry?['type']) {
        case 'Point':
          points.add(feature);
        case 'LineString':
          lines.add(feature);
      }
    }
    // 안내지점 개수는 항상 구간 개수 + 1이어야 한다(SP, GP..., EP 사이사이에
    // 구간이 하나씩 낀다). 어긋나면 응답이 예상 모양이 아니라는 뜻이라, 억지로
    // 읽지 않고 빈 목록으로 물러난다 — `_request()`의 다른 실패(네트워크 오류,
    // 200이 아닌 응답, JSON 파싱 실패)가 전부 조용히 null/빈 값으로 떨어지는
    // 것과 같은 원칙이다. 여기서 예외를 던지면 이 메서드만 "절대 안 던진다"는
    // 계약을 깨고, Task 5의 `Future.wait` 안에서 다른 옵션 응답까지 끌고 죽는다.
    if (points.isEmpty || lines.length != points.length - 1) return const [];
    // 방위각 계산이 좌표 2개(첫/끝 또는 끝에서 둘째)를 가정한다. 좌표가
    // 0~1개뿐인 LineString이 섞여 있으면 위 개수 검사를 통과해도
    // `_lineBearing`이 RangeError를 던지므로 여기서 미리 걸러 빈 목록으로
    // 물러난다 — 같은 "예상 모양이 아니면 포기" 원칙이다.
    for (final line in lines) {
      final coordinates =
          (line['geometry'] as Map<String, dynamic>)['coordinates']
              as List<dynamic>;
      if (coordinates.length < 2) return const [];
    }

    final steps = <DirectionsRouteStep>[];
    for (var i = 0; i < points.length; i++) {
      final coordinate =
          (points[i]['geometry'] as Map<String, dynamic>)['coordinates']
              as List<dynamic>;
      final point = _toLatLng(coordinate);

      if (i == 0) {
        steps.add(
          DirectionsRouteStep(instruction: '출발', distanceMeters: 0, point: point),
        );
        continue;
      }

      final beforeLine = lines[i - 1];
      final beforeDistance =
          _number(beforeLine['properties']?['distance']) ?? 0;

      if (i == points.length - 1) {
        steps.add(
          DirectionsRouteStep(
            instruction: '도착',
            distanceMeters: beforeDistance,
            point: point,
          ),
        );
        continue;
      }

      final afterLine = lines[i];
      final bearingBefore = _lineBearing(beforeLine, atStart: false);
      final bearingAfter = _lineBearing(afterLine, atStart: true);
      final turn = classifyTurn(
        bearingBeforeDeg: bearingBefore,
        bearingAfterDeg: bearingAfter,
      );
      steps.add(
        DirectionsRouteStep(
          instruction: switch (turn) {
            DirectionsTurn.straight => '직진',
            DirectionsTurn.turnLeft => '좌회전',
            DirectionsTurn.turnRight => '우회전',
          },
          distanceMeters: beforeDistance,
          point: point,
        ),
      );
    }
    return steps;
  }

  /// [atStart]가 true면 선의 첫 두 점(진입 방위), false면 마지막 두 점
  /// (진출 방위)으로 방위각을 잰다.
  static double _lineBearing(
    Map<String, dynamic> lineFeature, {
    required bool atStart,
  }) {
    final coordinates =
        ((lineFeature['geometry'] as Map<String, dynamic>)['coordinates']
                as List<dynamic>)
            .cast<List<dynamic>>();
    final a = atStart
        ? coordinates.first
        : coordinates[coordinates.length - 2];
    final b = atStart ? coordinates[1] : coordinates.last;
    return _bearingDeg(_toLatLng(a), _toLatLng(b));
  }

  static LatLng _toLatLng(List<dynamic> pair) =>
      LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble());

  static double _bearingDeg(LatLng from, LatLng to) {
    final dLon = to.longitude - from.longitude;
    final dLat = to.latitude - from.latitude;
    final deg = math.atan2(dLon, dLat) * 180 / math.pi;
    return deg < 0 ? deg + 360 : deg;
  }

  static double? _number(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }
}
