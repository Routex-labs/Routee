import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/guidance/route_guidance.dart';
import 'package:navigation_client/domain/guidance/route_movement.dart';
import 'package:navigation_client/domain/guidance/route_progress.dart';
import 'package:navigation_client/models/building/floor_graph.dart';

void main() {
  group('실내 안내 표시 근거', () {
    test('첫 걸음 전이어도 출발 앵커가 있으면 바로 옆 환승 안내를 보인다', () {
      expect(
        canShowIndoorRouteGuidance(hasProgress: false, hasIndoorPosition: true),
        isTrue,
      );
    });

    test('진행률과 실내 위치가 모두 없으면 건물 밖 실내 안내를 숨긴다', () {
      expect(
        canShowIndoorRouteGuidance(
          hasProgress: false,
          hasIndoorPosition: false,
        ),
        isFalse,
      );
    });
  });

  test('역주행이면 다음 회전보다 먼저 되돌아가라는 안내를 만든다', () {
    const progress = RouteProgress(
      traveledM: 5,
      remainingM: 15,
      offsetM: 0,
      onRouteEdge: true,
      reacquired: false,
      segmentIndex: 0,
      headingErrorDeg: 180,
    );

    final instruction = buildRouteGuidance(
      localPoints: const [LocalPoint(0, 0), LocalPoint(20, 0)],
      wgs84Points: const [LatLng(37, 127), LatLng(37, 127.001)],
      progress: progress,
      travelDirectionState: TravelDirectionState.reverseConfirmed,
    );

    expect(instruction.action, RouteGuidanceAction.wrongWay);
    expect(instruction.primaryText, contains('반대 방향'));
  });

  const points = [LocalPoint(0, 0), LocalPoint(0, 10), LocalPoint(10, 10)];
  const wgs84 = [
    LatLng(37, 127),
    LatLng(37.00009, 127),
    LatLng(37.00009, 127.000113),
  ];

  test('현재 위치에서 첫 의미 있는 회전 거리와 방향을 안내한다', () {
    const progress = RouteProgress(
      traveledM: 4,
      remainingM: 16,
      offsetM: 0,
      onRouteEdge: true,
      reacquired: false,
      segmentIndex: 0,
      projectedPoint: LocalPoint(0, 4),
    );

    final instruction = buildRouteGuidance(
      localPoints: points,
      wgs84Points: wgs84,
      progress: progress,
    );

    expect(instruction.action, RouteGuidanceAction.turnRight);
    expect(instruction.primaryText, '잠시 후 우회전');
  });

  test('회전이 없고 다음 층 이동이 있으면 에스컬레이터를 우선 안내한다', () {
    const progress = RouteProgress(
      traveledM: 0,
      remainingM: 10,
      offsetM: 0,
      onRouteEdge: true,
      reacquired: false,
      segmentIndex: 0,
      projectedPoint: LocalPoint(0, 0),
    );

    final instruction = buildRouteGuidance(
      localPoints: const [LocalPoint(0, 0), LocalPoint(0, 10)],
      wgs84Points: const [LatLng(37, 127), LatLng(37.00009, 127)],
      progress: progress,
      transferMode: 'escalator',
    );

    expect(instruction.action, RouteGuidanceAction.escalator);
    expect(instruction.primaryText, '10미터 후 에스컬레이터 탑승');
  });

  test('행동 거리는 실제 신뢰도에 맞게 5m 단위로 반올림한다', () {
    const progress = RouteProgress(
      traveledM: 0,
      remainingM: 18,
      offsetM: 0,
      onRouteEdge: true,
      reacquired: false,
      segmentIndex: 0,
      projectedPoint: LocalPoint(0, 0),
    );

    final instruction = buildRouteGuidance(
      localPoints: const [LocalPoint(0, 0), LocalPoint(0, 18)],
      wgs84Points: const [LatLng(37, 127), LatLng(37.00016, 127)],
      progress: progress,
      transferMode: 'escalator',
    );

    expect(instruction.primaryText, '20미터 후 에스컬레이터 탑승');
  });

  test('현재 간선 확정이 흔들려도 진행점을 기준으로 회색·파란선을 나눈다', () {
    const progress = RouteProgress(
      traveledM: 4,
      remainingM: 16,
      offsetM: 0,
      onRouteEdge: false,
      reacquired: false,
      segmentIndex: 0,
      projectedPoint: LocalPoint(0, 4),
    );

    final split = splitRouteAtProgress(points, progress)!;

    expect(split.completed, const [LocalPoint(0, 0), LocalPoint(0, 4)]);
    expect(split.remaining, const [
      LocalPoint(0, 4),
      LocalPoint(0, 10),
      LocalPoint(10, 10),
    ]);
  });

  test('다층 중간 세그먼트 끝은 목적지 도착으로 안내하지 않는다', () {
    const progress = RouteProgress(
      traveledM: 10,
      remainingM: 0,
      offsetM: 0,
      onRouteEdge: true,
      reacquired: false,
      segmentIndex: 0,
      projectedPoint: LocalPoint(0, 10),
    );

    final instruction = buildRouteGuidance(
      localPoints: const [LocalPoint(0, 0), LocalPoint(0, 10)],
      wgs84Points: const [LatLng(37, 127), LatLng(37.00009, 127)],
      progress: progress,
      allowArrival: false,
    );

    expect(instruction.action, isNot(RouteGuidanceAction.arrived));
    expect(instruction.primaryText, '다음 층 이동 지점입니다');
  });

  test('최종 목적지는 5m 안에서 도착으로 안내한다', () {
    const progress = RouteProgress(
      traveledM: 15.5,
      remainingM: 4.5,
      offsetM: 0,
      onRouteEdge: true,
      reacquired: false,
      segmentIndex: 0,
    );

    final instruction = buildRouteGuidance(
      localPoints: const [LocalPoint(0, 0), LocalPoint(20, 0)],
      wgs84Points: const [LatLng(37, 127), LatLng(37, 127.001)],
      progress: progress,
      allowArrival: true,
    );

    expect(instruction.action, RouteGuidanceAction.arrived);
  });

  test('다층 중간 지점은 5m 안이어도 도착으로 안내하지 않는다', () {
    const progress = RouteProgress(
      traveledM: 15.5,
      remainingM: 4.5,
      offsetM: 0,
      onRouteEdge: true,
      reacquired: false,
      segmentIndex: 0,
    );

    final instruction = buildRouteGuidance(
      localPoints: const [LocalPoint(0, 0), LocalPoint(20, 0)],
      wgs84Points: const [LatLng(37, 127), LatLng(37, 127.001)],
      progress: progress,
      transferMode: 'escalator',
      allowArrival: false,
    );

    expect(instruction.action, RouteGuidanceAction.escalator);
  });
}
