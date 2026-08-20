/// "내 주변 360°에서 가까운 것부터" 규칙.
///
/// 위치를 잡으려고 여는 목록이라 **방향을 가리면 안 된다** — 바로 뒤에 서 있는
/// 매장이 빠지면 정작 고르고 싶은 후보가 없다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/store/nearest_around_me.dart';

void main() {
  const points = [
    (id: 'east', x: 10.0, y: 0.0),
    (id: 'west', x: -3.0, y: 0.0),
    (id: 'north', x: 0.0, y: 5.0),
    (id: 'south', x: 0.0, y: -1.0),
  ];

  test('가까운 순으로 준다 — 방향은 가리지 않는다', () {
    final result = nearestAroundMe(fromX: 0, fromY: 0, points: points);
    expect(result.map((r) => r.id), ['south', 'west', 'north', 'east']);
    expect(result.first.distanceM, closeTo(1, 1e-9));
  });

  test('limit만큼만 자른다', () {
    final result = nearestAroundMe(
      fromX: 0,
      fromY: 0,
      points: points,
      limit: 2,
    );
    expect(result.map((r) => r.id), ['south', 'west']);
  });

  test('후보가 limit보다 적으면 있는 만큼', () {
    final result = nearestAroundMe(
      fromX: 0,
      fromY: 0,
      points: points,
      limit: 99,
    );
    expect(result, hasLength(4));
  });

  // 같은 화면을 두 번 열었을 때 순서가 뒤집히면 "방금 두 번째였던 줄"이 첫 줄에
  // 온다 — 사용자가 위치를 잘못 고르는 자리다.
  test('같은 거리는 id로 갈라 순서를 고정한다', () {
    const tied = [
      (id: 'b', x: 3.0, y: 0.0),
      (id: 'a', x: 0.0, y: 3.0),
      (id: 'c', x: -3.0, y: 0.0),
    ];
    expect(nearestAroundMe(fromX: 0, fromY: 0, points: tied).map((r) => r.id), [
      'a',
      'b',
      'c',
    ]);
  });

  test('기준점이 후보 위에 있으면 거리는 0이다', () {
    final result = nearestAroundMe(
      fromX: 10,
      fromY: 0,
      points: points,
      limit: 1,
    );
    expect(result.single.id, 'east');
    expect(result.single.distanceM, 0);
  });

  test('후보가 없거나 limit이 0이면 빈 목록', () {
    expect(nearestAroundMe(fromX: 0, fromY: 0, points: const []), isEmpty);
    expect(
      nearestAroundMe(fromX: 0, fromY: 0, points: points, limit: 0),
      isEmpty,
    );
  });
}
