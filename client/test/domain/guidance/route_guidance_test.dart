import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/guidance/route_guidance.dart';
import 'package:navigation_client/domain/guidance/route_movement.dart';
import 'package:navigation_client/domain/guidance/route_progress.dart';
import 'package:navigation_client/models/building/floor_graph.dart';

void main() {
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

  test('탑승구 5m 안에서도 그 사이에 남은 회전을 먼저 안내한다', () {
    // 지하 2층 구호플러스 옆 엘리베이터: 진행점이 회전 꼭짓점(2번째 점)에
    // 서 있고, 거기서 탑승구까지 3m뿐이라 도착 임계값(5m) 안이다. 회전을
    // 먼저 찾지 않으면 "엘리베이터를 탑승하세요"가 곧장 뜨고 사용자는 아직
    // 돌지 않은 모퉁이 앞에 남는다.
    const progress = RouteProgress(
      traveledM: 10,
      remainingM: 3,
      offsetM: 0,
      onRouteEdge: true,
      reacquired: false,
      segmentIndex: 0,
      projectedPoint: LocalPoint(0, 10),
    );

    final instruction = buildRouteGuidance(
      localPoints: const [
        LocalPoint(0, 0),
        LocalPoint(0, 10),
        LocalPoint(3, 10),
      ],
      wgs84Points: const [
        LatLng(37, 127),
        LatLng(37.00009, 127),
        LatLng(37.00009, 127.000113),
      ],
      progress: progress,
      transferMode: 'elevator',
    );

    expect(instruction.action, RouteGuidanceAction.turnRight);
  });

  // 위 엘리베이터 테스트와 **좌표가 완전히 같고 [transferMode]만 다르다.** 두
  // 개를 나란히 두는 것이 이 수정의 경계다 — 탑승구는 회전이 이기고, 목적지는
  // 도착이 이긴다.
  test('목적지 직전 모퉁이에서는 회전 대신 도착을 안내한다', () {
    // 복도 P0→P1를 걸어와 매장 문 앞(모퉁이 P1)에 섰다. 매장 노드 P2는 거기서
    // 3m 안이라 도착 임계값(5m) 안이지만, 진행률은 아직 앞 세그먼트에 있다 —
    // `computeRouteProgress`가 offset 동률에서 앞 세그먼트를 고르기 때문에,
    // 문 앞에 선 사람은 여기서 벗어나지 못한다. 회전을 먼저 내면 도착 카드도
    // 경로 자동 종료도 영영 안 온다.
    const progress = RouteProgress(
      traveledM: 10,
      remainingM: 3,
      offsetM: 0,
      onRouteEdge: true,
      reacquired: false,
      segmentIndex: 0,
      projectedPoint: LocalPoint(0, 10),
    );

    final instruction = buildRouteGuidance(
      localPoints: const [
        LocalPoint(0, 0),
        LocalPoint(0, 10),
        LocalPoint(3, 10),
      ],
      wgs84Points: const [
        LatLng(37, 127),
        LatLng(37.00009, 127),
        LatLng(37.00009, 127.000113),
      ],
      progress: progress,
    );

    expect(instruction.action, RouteGuidanceAction.arrived);
    expect(instruction.primaryText, '목적지에 도착했습니다');
  });

  test('같은 모퉁이라도 아직 멀면 도착이 아니라 회전을 안내한다', () {
    // 도착 임계값 밖(남은 13m)에서는 목적지 직전 모퉁이도 예전처럼 회전으로
    // 나간다. 위 테스트가 회전 탐색 자체를 지우는 방향으로 새는 것을 막는다.
    const progress = RouteProgress(
      traveledM: 0,
      remainingM: 13,
      offsetM: 0,
      onRouteEdge: true,
      reacquired: false,
      segmentIndex: 0,
      projectedPoint: LocalPoint(0, 0),
    );

    final instruction = buildRouteGuidance(
      localPoints: const [
        LocalPoint(0, 0),
        LocalPoint(0, 10),
        LocalPoint(3, 10),
      ],
      wgs84Points: const [
        LatLng(37, 127),
        LatLng(37.00009, 127),
        LatLng(37.00009, 127.000113),
      ],
      progress: progress,
    );

    expect(instruction.action, RouteGuidanceAction.turnRight);
  });
}
