import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/guidance/route_progress.dart';
import 'package:navigation_client/domain/guidance/route_movement.dart';
import 'package:navigation_client/models/building/floor_graph.dart';

/// (0,0) → (20,0) 직선 복도.
const _straightRoute = [LocalPoint(0, 0), LocalPoint(20, 0)];

/// (0,0) → (20,0) → (20,4) → (0,4) 로 돌아오는 ㄷ자 경로.
/// 시작 구간과 마지막 구간이 4m 간격으로 마주본다.
const _uTurnRoute = [
  LocalPoint(0, 0),
  LocalPoint(20, 0),
  LocalPoint(20, 4),
  LocalPoint(0, 4),
];

void main() {
  group('새 경로 시작 진행률', () {
    test('현재점과 뒷 구간이 겹쳐도 반드시 0m에서 시작한다', () {
      final progress = seedRouteProgressAtRouteStart(
        routePointsLocalM: const [
          LocalPoint(0, 0),
          LocalPoint(10, 0),
          LocalPoint(0, 0),
        ],
        routeEdgeIds: const {'ab', 'ba'},
        currentEdgeId: 'ab',
        headingDeg: 90,
      );

      expect(progress, isNotNull);
      expect(progress!.traveledM, 0);
      expect(progress.remainingM, 20);
      expect(progress.projectedPoint, const LocalPoint(0, 0));
      expect(progress.reacquired, isFalse);
    });
  });

  group('진행 표시 안정화', () {
    const previous = RouteProgress(
      traveledM: 10,
      remainingM: 30,
      offsetM: 0.4,
      onRouteEdge: true,
      reacquired: false,
      segmentIndex: 0,
    );

    test('걸음 없이 멀리 튄 진행점은 안내에 반영하지 않는다', () {
      const jumped = RouteProgress(
        traveledM: 28,
        remainingM: 12,
        offsetM: 0.3,
        onRouteEdge: true,
        reacquired: false,
        segmentIndex: 2,
      );

      expect(
        shouldHoldImplausibleRouteJump(
          previous: previous,
          candidate: jumped,
          acceptedAtSteps: 100,
          currentSteps: 100,
        ),
        isTrue,
      );
    });

    test('재배치된 후보는 이번 걸음 거리만큼만 경로 위에서 따라잡는다', () {
      const jumped = RouteProgress(
        traveledM: 19,
        remainingM: 1,
        offsetM: 0,
        onRouteEdge: true,
        reacquired: true,
        segmentIndex: 0,
        projectedPoint: LocalPoint(19, 0),
      );

      final bounded = moveRouteProgressToward(
        previous: const RouteProgress(
          traveledM: 7,
          remainingM: 13,
          offsetM: 0,
          onRouteEdge: true,
          reacquired: false,
          segmentIndex: 0,
          projectedPoint: LocalPoint(7, 0),
        ),
        candidate: jumped,
        routePointsLocalM: _straightRoute,
        maxDistanceM: 0.75,
      );

      expect(bounded.traveledM, closeTo(7.75, 1e-9));
      expect(bounded.remainingM, closeTo(12.25, 1e-9));
      expect(bounded.projectedPoint!.x, closeTo(7.75, 1e-9));
      expect(bounded.projectedPoint!.y, closeTo(0, 1e-9));
      expect(bounded.reacquired, isFalse);
    });

    test('실제 유턴 후보도 승인된 거리만큼 역방향으로 움직인다', () {
      const from = RouteProgress(
        traveledM: 10,
        remainingM: 10,
        offsetM: 0,
        onRouteEdge: true,
        reacquired: false,
        segmentIndex: 0,
        projectedPoint: LocalPoint(10, 0),
      );
      const candidate = RouteProgress(
        traveledM: 2,
        remainingM: 18,
        offsetM: 0,
        onRouteEdge: true,
        reacquired: false,
        segmentIndex: 0,
        projectedPoint: LocalPoint(2, 0),
      );

      final bounded = moveRouteProgressToward(
        previous: from,
        candidate: candidate,
        routePointsLocalM: _straightRoute,
        maxDistanceM: 1.4,
      );

      expect(bounded.traveledM, closeTo(8.6, 1e-9));
      expect(bounded.projectedPoint!.x, closeTo(8.6, 1e-9));
      expect(bounded.projectedPoint!.y, closeTo(0, 1e-9));
    });

    test('늘어난 걸음으로 설명되는 진행은 정상 반영한다', () {
      const walked = RouteProgress(
        traveledM: 20,
        remainingM: 20,
        offsetM: 0.3,
        onRouteEdge: true,
        reacquired: false,
        segmentIndex: 1,
      );

      expect(
        shouldHoldImplausibleRouteJump(
          previous: previous,
          candidate: walked,
          acceptedAtSteps: 100,
          currentSteps: 107,
        ),
        isFalse,
      );
    });

    test('앞을 보고 있는데 뒤로 밀린 진행점은 보류한다', () {
      // 빔 1등 재배치나 보폭 차이로 생기는 후퇴다. 사용자에게는 마커가 뒤로
      // 튄 것으로 보인다.
      const pushedBack = RouteProgress(
        traveledM: 6,
        remainingM: 34,
        offsetM: 0.4,
        onRouteEdge: true,
        reacquired: false,
        segmentIndex: 0,
        headingErrorDeg: 12,
      );

      expect(
        shouldHoldDisplayRouteRegression(
          previous: previous,
          candidate: pushedBack,
          travelDirectionState: TravelDirectionState.forward,
        ),
        isTrue,
      );
    });

    test('앞으로 걸은 걸음이 뒤로 갈 여유를 만들지 않는다', () {
      // pedometer는 방향을 모른다. 걸음 수를 근거로 쓰면 앞으로 걸을수록
      // 뒤로 튀는 것이 더 허용된다 — 실제로 그렇게 동작했다.
      const pushedBack = RouteProgress(
        traveledM: 4,
        remainingM: 36,
        offsetM: 0.4,
        onRouteEdge: true,
        reacquired: false,
        segmentIndex: 0,
        headingErrorDeg: 5,
      );

      expect(
        shouldHoldDisplayRouteRegression(
          previous: previous,
          candidate: pushedBack,
          travelDirectionState: TravelDirectionState.forward,
        ),
        isTrue,
      );
    });

    test('작은 후퇴는 그대로 통과시킨다', () {
      // 투영 오차 수준의 흔들림까지 막으면 마커가 계단식으로 움직인다.
      const jitter = RouteProgress(
        traveledM: 8.5,
        remainingM: 31.5,
        offsetM: 0.4,
        onRouteEdge: true,
        reacquired: false,
        segmentIndex: 0,
      );

      expect(
        shouldHoldDisplayRouteRegression(
          previous: previous,
          candidate: jitter,
          travelDirectionState: TravelDirectionState.forward,
        ),
        isFalse,
      );
    });

    test('실제 역방향 걸음이 확정된 후퇴는 그대로 받아들인다', () {
      const walkedBack = RouteProgress(
        traveledM: 3,
        remainingM: 37,
        offsetM: 0.4,
        onRouteEdge: true,
        reacquired: false,
        segmentIndex: 0,
        headingErrorDeg: 168,
      );

      expect(
        shouldHoldDisplayRouteRegression(
          previous: previous,
          candidate: walkedBack,
          travelDirectionState: TravelDirectionState.reverseConfirmed,
        ),
        isFalse,
      );
    });

    test('heading이 없어도 실제 방향 상태가 forward면 후퇴를 보류한다', () {
      const pushedBack = RouteProgress(
        traveledM: 3,
        remainingM: 37,
        offsetM: 0.4,
        onRouteEdge: true,
        reacquired: false,
        segmentIndex: 0,
      );

      expect(
        shouldHoldDisplayRouteRegression(
          previous: previous,
          candidate: pushedBack,
          travelDirectionState: TravelDirectionState.forward,
        ),
        isTrue,
      );
    });
  });

  group('직선 경로 진행', () {
    test('걸어 나갈수록 진행거리는 늘고 남은거리는 줄어든다', () {
      double? previous;
      final traveled = <double>[];
      final remaining = <double>[];

      for (final eastM in [0.0, 4.0, 8.0, 12.0, 16.0, 20.0]) {
        final progress = computeRouteProgress(
          routePointsLocalM: _straightRoute,
          routeEdgeIds: const {'ab'},
          position: LocalPoint(eastM, 0.2),
          currentEdgeId: 'ab',
          previousTraveledM: previous,
        )!;
        traveled.add(progress.traveledM);
        remaining.add(progress.remainingM);
        previous = progress.traveledM;

        expect(progress.onRouteEdge, isTrue);
        expect(progress.reacquired, isFalse);
        expect(progress.offsetM, closeTo(0.2, 1e-9));
        // 진행거리와 남은거리의 합은 항상 폴리라인 전체 길이다.
        expect(progress.traveledM + progress.remainingM, closeTo(20.0, 1e-9));
      }

      expect(traveled, orderedEquals(<double>[0, 4, 8, 12, 16, 20]));
      expect(remaining, orderedEquals(<double>[20, 16, 12, 8, 4, 0]));
    });

    test('120도 이상 heading 차이는 진단값일 뿐 제품 역주행을 만들지 않는다', () {
      final progress = computeRouteProgress(
        routePointsLocalM: _straightRoute,
        routeEdgeIds: const {'ab'},
        position: const LocalPoint(10, 0),
        currentEdgeId: 'ab',
        // (0,0) → (20,0)은 동쪽 90°, 270°는 정확한 반대 방향.
        headingDeg: 270,
      )!;

      expect(progress.headingErrorDeg, closeTo(180, 1e-9));
      expect(progress.routeHeadingDeg, closeTo(90, 1e-9));
    });

    test('코너와 경로 밖에서도 heading 오차는 진단값으로만 남는다', () {
      final corner = computeRouteProgress(
        routePointsLocalM: _straightRoute,
        routeEdgeIds: const {'ab'},
        position: const LocalPoint(10, 0),
        currentEdgeId: 'ab',
        headingDeg: 190,
      )!;
      final offRoute = computeRouteProgress(
        routePointsLocalM: _straightRoute,
        routeEdgeIds: const {'ab'},
        position: const LocalPoint(10, 1),
        currentEdgeId: 'other',
        headingDeg: 270,
      )!;

      expect(corner.headingErrorDeg, closeTo(100, 1e-9));
      expect(offRoute.headingErrorDeg, closeTo(180, 1e-9));
      expect(offRoute.onRouteEdge, isFalse);
    });

    test('경로 시작 이전·끝 이후로 나가도 진행거리가 경로 범위를 벗어나지 않는다', () {
      final before = computeRouteProgress(
        routePointsLocalM: _straightRoute,
        routeEdgeIds: const {'ab'},
        position: const LocalPoint(-5, 0),
        currentEdgeId: 'ab',
      )!;
      final after = computeRouteProgress(
        routePointsLocalM: _straightRoute,
        routeEdgeIds: const {'ab'},
        position: const LocalPoint(25, 0),
        currentEdgeId: 'ab',
      )!;

      expect(before.traveledM, 0.0);
      expect(before.remainingM, 20.0);
      expect(after.traveledM, 20.0);
      expect(after.remainingM, 0.0);
    });
  });

  group('평행 복도 오매칭', () {
    // 이 그룹이 1단계의 존재 이유다. 수직 거리만 보면 "잘 붙었다"로 보이는
    // 상태를 경로 기준으로는 이탈로 판정해야 한다.
    test('이탈거리가 작아도 간선이 경로에 없으면 경로 위가 아니다', () {
      final progress = computeRouteProgress(
        routePointsLocalM: _straightRoute,
        routeEdgeIds: const {'ab'},
        // 경로에서 1.5m 떨어진 나란한 옆 복도 간선에 붙은 상태.
        position: const LocalPoint(10, 1.5),
        currentEdgeId: 'parallel-corridor',
      )!;

      expect(progress.offsetM, closeTo(1.5, 1e-9));
      expect(progress.onRouteEdge, isFalse);
    });

    test('현재 간선이 확정되지 않았으면 경로 위로 보지 않는다', () {
      final progress = computeRouteProgress(
        routePointsLocalM: _straightRoute,
        routeEdgeIds: const {'ab'},
        position: const LocalPoint(10, 0),
        currentEdgeId: null,
      )!;

      expect(progress.offsetM, closeTo(0.0, 1e-9));
      expect(progress.onRouteEdge, isFalse);
    });
  });

  group('ㄷ자 경로', () {
    test('마주보는 구간이 가까워도 진행거리가 시작으로 되돌아가지 않는다', () {
      // 마지막 구간 위 (10,4). 첫 구간 (10,0)과 4m밖에 떨어져 있지 않지만,
      // 이전 진행거리(34m)를 기준으로 보면 마지막 구간이 맞다.
      final progress = computeRouteProgress(
        routePointsLocalM: _uTurnRoute,
        routeEdgeIds: const {'ab', 'bc', 'cd'},
        position: const LocalPoint(10, 4),
        currentEdgeId: 'cd',
        previousTraveledM: 34.0,
      )!;

      // 전체 44m 중 마지막 구간 중간 = 24 + 10 = 34m.
      expect(progress.traveledM, closeTo(34.0, 1e-9));
      expect(progress.segmentIndex, 2);
      expect(progress.reacquired, isFalse);
    });

    test('이전 진행거리가 없으면 같은 위치를 첫 구간으로 오인할 수 있다', () {
      // 지역 탐색 창이 왜 필요한지 고정해 두는 테스트다. 전역 최소만 쓰면
      // 마지막 구간 위 점이 offset 동률인 첫 구간으로 잡힐 수 있다.
      final progress = computeRouteProgress(
        routePointsLocalM: _uTurnRoute,
        routeEdgeIds: const {'ab', 'bc', 'cd'},
        position: const LocalPoint(10, 2),
        currentEdgeId: 'cd',
      )!;

      expect(progress.segmentIndex, 0);
      expect(progress.traveledM, closeTo(10.0, 1e-9));
    });
  });

  group('전역 재획득', () {
    test('탐색 창 밖으로 벗어나면 재획득하고 그 사실을 표시한다', () {
      final progress = computeRouteProgress(
        routePointsLocalM: _straightRoute,
        routeEdgeIds: const {'ab'},
        position: const LocalPoint(2, 0),
        currentEdgeId: 'ab',
        // 직전에는 경로 끝(20m)에 있었는데 위치가 2m로 튀었다 → 창(±15m) 밖.
        previousTraveledM: 20.0,
      )!;

      expect(progress.reacquired, isTrue);
      expect(progress.traveledM, closeTo(2.0, 1e-9));
    });

    test('경로에서 멀리 떨어져도 창 안이면 재획득 없이 이탈거리로만 나타난다', () {
      final progress = computeRouteProgress(
        routePointsLocalM: _straightRoute,
        routeEdgeIds: const {'ab'},
        position: const LocalPoint(10, 20),
        currentEdgeId: 'other',
        previousTraveledM: 10.0,
      )!;

      expect(progress.reacquired, isFalse);
      expect(progress.offsetM, closeTo(20.0, 1e-9));
      expect(progress.onRouteEdge, isFalse);
    });
  });

  group('경계값', () {
    test('점이 2개 미만인 경로는 계산하지 않는다', () {
      expect(
        computeRouteProgress(
          routePointsLocalM: const [],
          routeEdgeIds: const {},
          position: const LocalPoint(0, 0),
          currentEdgeId: null,
        ),
        isNull,
      );
      expect(
        computeRouteProgress(
          routePointsLocalM: const [LocalPoint(1, 1)],
          routeEdgeIds: const {},
          position: const LocalPoint(0, 0),
          currentEdgeId: null,
        ),
        isNull,
      );
    });

    test('같은 좌표만 반복되는 경로는 투영할 구간이 없어 계산하지 않는다', () {
      expect(
        computeRouteProgress(
          routePointsLocalM: const [LocalPoint(3, 3), LocalPoint(3, 3)],
          routeEdgeIds: const {'ab'},
          position: const LocalPoint(0, 0),
          currentEdgeId: 'ab',
        ),
        isNull,
      );
    });

    test('중복 좌표가 섞여 있어도 누적 거리는 실제 이동 거리만 센다', () {
      final progress = computeRouteProgress(
        routePointsLocalM: const [
          LocalPoint(0, 0),
          LocalPoint(10, 0),
          LocalPoint(10, 0),
          LocalPoint(20, 0),
        ],
        routeEdgeIds: const {'ab'},
        position: const LocalPoint(15, 0),
        currentEdgeId: 'ab',
      )!;

      expect(progress.traveledM, closeTo(15.0, 1e-9));
      expect(progress.remainingM, closeTo(5.0, 1e-9));
    });
  });
}
