import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/guidance/multi_floor_eta.dart';
import 'package:navigation_client/models/building/building_graph.dart';
import 'package:navigation_client/models/route/indoor_route.dart';

void main() {
  IndoorRoute route(double distanceM) =>
      IndoorRoute(points: const [], distanceMeters: distanceM);

  final multi = MultiFloorRoute(
    segments: [
      IndoorRouteSegment(
        floorId: 'b1',
        floorName: 'B1',
        route: route(20),
        transferDistanceMeters: 3,
        transferCostMeters: 12,
      ),
      IndoorRouteSegment(
        floorId: '1f',
        floorName: '1F',
        route: route(30),
        transferDistanceMeters: 2,
        transferCostMeters: 8,
      ),
      IndoorRouteSegment(floorId: '2f', floorName: '2F', route: route(40)),
    ],
    totalDistanceMeters: 95,
    totalCostMeters: 110,
  );

  test('현재 층 진행률이 아직 없어도 이미 지난 층을 다시 더하지 않는다', () {
    expect(remainingMultiFloorEta(route: multi, activeFloor: '1F'), (
      distanceM: 72.0,
      costM: 78.0,
    ));
  });

  test('현재 층의 진행률과 이후 층·수직 이동을 함께 반영한다', () {
    expect(
      remainingMultiFloorEta(
        route: multi,
        activeFloor: '1F',
        activeSegmentRemainingM: 11,
      ),
      (distanceM: 53.0, costM: 59.0),
    );
  });

  test('현재 층을 찾지 못하면 경로 전체를 보수적으로 유지한다', () {
    expect(remainingMultiFloorEta(route: multi, activeFloor: '3F'), (
      distanceM: 95.0,
      costM: 110.0,
    ));
  });
}
