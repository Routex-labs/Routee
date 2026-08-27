import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_pdr_core/indoor_pdr_core.dart';
import 'package:navigation_client/domain/guidance/route_approach_follower.dart';
import 'package:navigation_client/models/building/floor_graph.dart';

void main() {
  const route = [LocalPoint(0, 0), LocalPoint(0, 5), LocalPoint(-4, 5)];

  test('실제 걸음 거리만큼 ㄱ자 경로를 따라 진행한다', () {
    final follower = RouteApproachFollower.start(
      points: route,
      seed: const PdrLocalPoint(0, 2),
    )!;

    follower.advance(3.5);
    expect(follower.position.eastM, closeTo(-0.5, 0.001));
    expect(follower.position.northM, closeTo(5, 0.001));

    follower.advance(3.5);
    expect(follower.position.eastM, closeTo(-4, 0.001));
    expect(follower.position.northM, closeTo(5, 0.001));
    expect(follower.isAtTerminal, isTrue);
  });

  test('걸음이 없으면 시간과 무관하게 움직이지 않는다', () {
    final follower = RouteApproachFollower.start(
      points: route,
      seed: const PdrLocalPoint(0, 2),
    )!;

    final initial = follower.position;
    follower.advance(0);

    expect(follower.position, initial);
  });

  test('두 번 꺾이는 남은 경로도 순서대로 끝까지 따른다', () {
    final follower = RouteApproachFollower.start(
      points: const [
        LocalPoint(0, 0),
        LocalPoint(0, 4),
        LocalPoint(-3, 4),
        LocalPoint(-3, 7),
      ],
      seed: const PdrLocalPoint(0, 1),
    )!;

    follower.advance(8.5);

    expect(follower.position.eastM, closeTo(-3, 0.001));
    expect(follower.position.northM, closeTo(6.5, 0.001));
    expect(follower.isAtTerminal, isFalse);

    follower.advance(0.5);
    expect(follower.isAtTerminal, isTrue);
  });

  test('옆 복도처럼 경로에서 먼 시작점은 붙잡지 않는다', () {
    final follower = RouteApproachFollower.start(
      points: route,
      seed: const PdrLocalPoint(4, 2),
    );

    expect(follower, isNull);
  });
}
