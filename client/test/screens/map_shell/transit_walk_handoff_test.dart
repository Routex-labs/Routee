/// 대중교통 → 도보 인계 규칙.
///
/// 실기기에서 하차 지점 **바로 옆에 문이 있는데 건물을 빙 돌아 반대편 문으로
/// 안내한** 화면을 봤다. 그 사고를 다시 내지 않기 위한 테스트다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/route/transit_route.dart';
import 'package:navigation_client/screens/map_shell/transit_walk_handoff.dart';

const _fallback = LatLng(37.0, 127.0);

TransitLeg leg(
  TransitMode mode,
  List<LatLng> points, {
  int seconds = 60,
  double meters = 100,
}) => TransitLeg(
  mode: mode,
  sectionTimeSeconds: seconds,
  distanceMeters: meters,
  points: points,
);

TransitItinerary plan(List<TransitLeg> legs) => TransitItinerary(
  totalTimeSeconds: 1200,
  totalWalkTimeSeconds: 300,
  totalDistanceMeters: 5000,
  transferCount: 1,
  legs: legs,
  fare: 1500,
);

void main() {
  group('내린 자리', () {
    test('마지막에 도보가 붙어 있어도 **탈것**이 끝난 곳을 쓴다', () {
      // 이것이 그 사고의 핵심이다. legs.last를 쓰면 카카오 도보의 끝점,
      // 즉 우리가 보낸 목적지 좌표가 잡혀 "목적지에서 가까운 문"이 된다.
      const busEnd = LatLng(37.5, 127.05);
      const walkEnd = LatLng(37.6, 127.20);
      final itinerary = plan([
        leg(TransitMode.walk, const [
          LatLng(37.4, 127.0),
          LatLng(37.45, 127.0),
        ]),
        leg(TransitMode.bus, const [LatLng(37.45, 127.0), busEnd]),
        leg(TransitMode.walk, const [busEnd, walkEnd]),
      ]);

      expect(transitDropPoint(itinerary, fallback: _fallback), busEnd);
    });

    test('탈것이 여럿이면 마지막 탈것이 끝난 곳이다', () {
      const subwayEnd = LatLng(37.55, 127.10);
      final itinerary = plan([
        leg(TransitMode.bus, const [LatLng(37.4, 127.0), LatLng(37.5, 127.05)]),
        leg(TransitMode.subway, const [LatLng(37.5, 127.05), subwayEnd]),
      ]);

      expect(transitDropPoint(itinerary, fallback: _fallback), subwayEnd);
    });

    test('처음부터 끝까지 걷는 안내면 마지막 구간의 끝이다', () {
      const walkEnd = LatLng(37.42, 127.01);
      final itinerary = plan([
        leg(TransitMode.walk, const [LatLng(37.4, 127.0), walkEnd]),
      ]);

      expect(transitDropPoint(itinerary, fallback: _fallback), walkEnd);
    });

    test('점이 하나도 없으면 fallback으로 떨어진다', () {
      expect(
        transitDropPoint(
          plan([leg(TransitMode.bus, const [])]),
          fallback: _fallback,
        ),
        _fallback,
      );
    });

    test('구간이 아예 없어도 터지지 않는다', () {
      expect(transitDropPoint(plan([]), fallback: _fallback), _fallback);
    });
  });

  group('마지막 도보 잘라내기', () {
    test('마지막이 도보면 잘라 낸다', () {
      final itinerary = plan([
        leg(TransitMode.walk, const [LatLng(37.4, 127.0)]),
        leg(TransitMode.bus, const [LatLng(37.45, 127.0)]),
        leg(TransitMode.walk, const [LatLng(37.5, 127.05)]),
      ]);

      final trimmed = trimTrailingWalkLeg(itinerary);
      expect(trimmed.legs.length, 2);
      expect(trimmed.legs.last.mode, TransitMode.bus);
      // 요약 값은 그대로 둔다 — 총 소요시간은 카카오가 준 값이 정답이고,
      // 우리가 붙일 도보도 결국 그 시간 안에 들어간다.
      expect(trimmed.totalTimeSeconds, itinerary.totalTimeSeconds);
      expect(trimmed.fare, itinerary.fare);
    });

    test('마지막이 탈것이면 그대로 둔다', () {
      final itinerary = plan([
        leg(TransitMode.walk, const [LatLng(37.4, 127.0)]),
        leg(TransitMode.bus, const [LatLng(37.45, 127.0)]),
      ]);

      expect(trimTrailingWalkLeg(itinerary).legs.length, 2);
    });

    test('구간이 도보 하나뿐이면 자르지 않는다', () {
      // 처음부터 끝까지 걷는 안내다. 자르면 아무것도 안 남는다.
      final itinerary = plan([
        leg(TransitMode.walk, const [LatLng(37.4, 127.0)]),
      ]);

      expect(trimTrailingWalkLeg(itinerary).legs.length, 1);
    });

    test('구간이 없으면 그대로 둔다', () {
      expect(trimTrailingWalkLeg(plan([])).legs, isEmpty);
    });
  });

  group('타는 자리', () {
    test('앞에 도보가 붙어 있어도 **탈것**이 시작한 곳을 쓴다', () {
      // 하차 쪽 사고의 거울상이다. legs.first를 쓰면 카카오 도보의 시작점,
      // 즉 우리가 보낸 출발 좌표가 잡혀 "방금 보낸 값을 되받는" 꼴이 된다.
      const walkStart = LatLng(37.40, 127.00);
      const busStart = LatLng(37.45, 127.02);
      final itinerary = plan([
        leg(TransitMode.walk, const [walkStart, busStart]),
        leg(TransitMode.bus, const [busStart, LatLng(37.5, 127.05)]),
      ]);

      expect(transitBoardPoint(itinerary, fallback: _fallback), busStart);
    });

    test('탈것이 여럿이면 **처음** 탈것이 시작한 곳이다', () {
      const busStart = LatLng(37.45, 127.02);
      final itinerary = plan([
        leg(TransitMode.bus, const [busStart, LatLng(37.5, 127.05)]),
        leg(TransitMode.subway, const [
          LatLng(37.5, 127.05),
          LatLng(37.55, 127.1),
        ]),
      ]);

      expect(transitBoardPoint(itinerary, fallback: _fallback), busStart);
    });

    test('처음부터 끝까지 걷는 안내면 첫 구간의 시작이다', () {
      const walkStart = LatLng(37.40, 127.00);
      final itinerary = plan([
        leg(TransitMode.walk, const [walkStart, LatLng(37.42, 127.01)]),
      ]);

      expect(transitBoardPoint(itinerary, fallback: _fallback), walkStart);
    });

    test('점이 하나도 없으면 fallback으로 떨어진다', () {
      expect(
        transitBoardPoint(
          plan([leg(TransitMode.bus, const [])]),
          fallback: _fallback,
        ),
        _fallback,
      );
    });

    test('구간이 아예 없어도 터지지 않는다', () {
      expect(transitBoardPoint(plan([]), fallback: _fallback), _fallback);
    });
  });

  group('첫 도보 잘라내기', () {
    test('처음이 도보면 잘라 낸다', () {
      final itinerary = plan([
        leg(TransitMode.walk, const [LatLng(37.4, 127.0)]),
        leg(TransitMode.bus, const [LatLng(37.45, 127.0)]),
        leg(TransitMode.walk, const [LatLng(37.5, 127.05)]),
      ]);

      final trimmed = trimLeadingWalkLeg(itinerary);
      expect(trimmed.legs.length, 2);
      expect(trimmed.legs.first.mode, TransitMode.bus);
      expect(trimmed.totalTimeSeconds, itinerary.totalTimeSeconds);
      expect(trimmed.fare, itinerary.fare);
    });

    test('처음이 탈것이면 그대로 둔다', () {
      final itinerary = plan([
        leg(TransitMode.bus, const [LatLng(37.45, 127.0)]),
        leg(TransitMode.walk, const [LatLng(37.5, 127.05)]),
      ]);

      expect(trimLeadingWalkLeg(itinerary).legs.length, 2);
    });

    test('구간이 도보 하나뿐이면 자르지 않는다', () {
      final itinerary = plan([
        leg(TransitMode.walk, const [LatLng(37.4, 127.0)]),
      ]);

      expect(trimLeadingWalkLeg(itinerary).legs.length, 1);
    });

    test('구간이 없으면 그대로 둔다', () {
      expect(trimLeadingWalkLeg(plan([])).legs, isEmpty);
    });
  });
}
