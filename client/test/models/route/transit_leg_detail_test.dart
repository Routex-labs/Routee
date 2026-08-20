import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/models/route/transit_route.dart';

// 상세 화면이 쓰는 두 목록(지나는 정류장·같은 구간 노선)이 파싱에서 살아남는지
// 본다. 픽스처 원문은 test/repositories/routing/kakao_transit_repository_test.dart.

Map<String, dynamic> _kakaoStep({
  required String type,
  List<Map<String, String>> stops = const [],
  List<Map<String, String>>? vehicles,
}) => {
  'properties': {
    'type': type,
    'distance': 900,
    'time': 103,
    'stops': stops,
    'vehicles': ?vehicles,
  },
  'path': {
    'points': [
      [126.9243, 37.5215],
      [127.0251, 37.5045],
    ],
  },
};

void main() {
  test('탈것 구간은 지나는 정류장을 순서대로 전부 남긴다', () {
    final leg = TransitLeg.fromKakaoJson(
      _kakaoStep(
        type: 'SUBWAY',
        stops: const [
          {'name': '여의도'},
          {'name': '노량진'},
          {'name': '동작'},
          {'name': '고속터미널'},
          {'name': '신논현'},
        ],
        vehicles: const [
          {'name': '9호선', 'type': '급행'},
        ],
      ),
    );

    expect(leg.stopNames, ['여의도', '노량진', '동작', '고속터미널', '신논현']);
    // 기존 필드는 새 목록에서 파생돼도 값이 그대로여야 한다.
    expect(leg.startName, '여의도');
    expect(leg.endName, '신논현');
    expect(leg.stationCount, 4);
    expect(leg.shortLabel, '9호선');
  });

  test('도보 구간의 stops는 지나는 정류장이 아니다', () {
    final leg = TransitLeg.fromKakaoJson(
      _kakaoStep(
        type: 'WALKING',
        stops: const [
          {'name': '신논현'},
          {'name': '신논현역'},
        ],
      ),
    );

    // 카카오는 도보에도 stops를 둘 붙여 준다. 그대로 내보내면 상세 화면이
    // 걷는 구간에 정류장 두 개를 찍는다.
    expect(leg.stopNames, isEmpty);
    expect(leg.vehicles, isEmpty);
    expect(leg.stationCount, 0);
    // 다만 구간 이름은 지금 화면들이 쓰고 있으므로 그대로 남는다.
    expect(leg.startName, '신논현');
    expect(leg.endName, '신논현역');
  });

  test('같은 구간을 지나는 노선을 번호·종류로 전부 남긴다', () {
    final leg = TransitLeg.fromKakaoJson(
      _kakaoStep(
        type: 'BUS',
        stops: const [
          {'name': '한국거래소'},
          {'name': '여의도역6번출구'},
        ],
        vehicles: const [
          {'name': '5623', 'type': '지선'},
          {'name': '461', 'type': '간선'},
          {'name': '7007-1', 'type': '지선'},
        ],
      ),
    );

    expect(leg.vehicles.map((v) => v.name), ['5623', '461', '7007-1']);
    expect(leg.vehicles.map((v) => v.type), ['지선', '간선', '지선']);
    // 목록 칩은 예전 그대로 첫 노선 + "외 N대"다.
    expect(leg.shortLabel, '5623외 2대');
  });

  test('노선 종류가 없어도 번호는 살린다', () {
    final leg = TransitLeg.fromKakaoJson(
      _kakaoStep(
        type: 'BUS',
        stops: const [
          {'name': '가'},
          {'name': '나'},
        ],
        vehicles: const [
          {'name': '272'},
        ],
      ),
    );

    expect(leg.vehicles.single.name, '272');
    expect(leg.vehicles.single.type, isNull);
    expect(leg.shortLabel, '272');
  });

  test('TMAP 구간은 두 목록이 비어 있다 — 응답에 오지 않는다', () {
    final leg = TransitLeg.fromTmapJson({
      'mode': 'SUBWAY',
      'route': '수도권5호선',
      'sectionTime': 900,
      'distance': 8000,
      'start': {'name': '여의도역', 'lon': 126.9245, 'lat': 37.5215},
      'end': {'name': '광화문역', 'lon': 126.9769, 'lat': 37.5710},
      'passStopList': {
        'stationList': [
          {'index': 0, 'stationName': '여의도'},
          {'index': 1, 'stationName': '마포'},
          {'index': 2, 'stationName': '광화문'},
        ],
      },
      'passShape': {'linestring': '126.9245,37.5215 126.9769,37.5710'},
    });

    expect(leg.stopNames, isEmpty);
    expect(leg.vehicles, isEmpty);
    // 정거장 수는 예전대로 passStopList에서 센다.
    expect(leg.stationCount, 2);
  });
}
