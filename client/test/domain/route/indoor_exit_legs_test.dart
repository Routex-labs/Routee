/// 나가는 문 하나를 고르면서 **그 실내 구간의 거리·비용까지** 함께 집어 오는지.
///
/// 목적지가 여럿인 화면(대중교통 후보 목록)이 그래프를 한 번만 훑게 하는 것이
/// 이 타입의 존재 이유다 — `docs/client/indoor-leg-in-outdoor-journey.md`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/route/building_entrances.dart';
import 'package:navigation_client/domain/route/indoor_exit_legs.dart';

/// 더현대 서울 1층 출구 일부(라이브 API 값).
const _northWest = LatLng(37.526549, 126.927834);
const _southEast = LatLng(37.525538, 126.929258);

BuildingEntrance _entrance(String id, LatLng point) =>
    BuildingEntrance(id: id, name: '출구', nodeId: 'ND-$id', point: point);

void main() {
  test('총 이동거리가 작은 문을 고르고 그 문의 거리·비용을 함께 준다', () {
    final reach = IndoorExitReach([
      // 복도로는 북서쪽이 훨씬 가깝지만 목적지는 남동쪽이다.
      (entrance: _entrance('nw', _northWest), distanceM: 40, costM: 40),
      (entrance: _entrance('se', _southEast), distanceM: 116, costM: 160),
    ]);

    // 남동쪽 문 바로 바깥의 목적지.
    final leg = reach.towards(const LatLng(37.5250, 126.9300));

    expect(leg?.entrance.id, 'se');
    expect(leg?.distanceM, 116);
    // **비용은 거리와 다르다** — 엘리베이터 대기·탑승이 여기 들어 있다.
    expect(leg?.costM, 160);
  });

  test('목적지가 반대쪽이면 고르는 문도 바뀐다', () {
    final reach = IndoorExitReach([
      (entrance: _entrance('nw', _northWest), distanceM: 40, costM: 40),
      (entrance: _entrance('se', _southEast), distanceM: 116, costM: 160),
    ]);
    expect(reach.towards(const LatLng(37.5300, 126.9250))?.entrance.id, 'nw');
  });

  test('닿는 문이 없으면 null이다 — 호출부가 실내 구간 없이 진행한다', () {
    expect(const IndoorExitReach([]).isEmpty, isTrue);
    expect(const IndoorExitReach([]).towards(_northWest), isNull);
  });
}
