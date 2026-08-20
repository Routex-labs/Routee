/// 지도에 회색으로 깔 "고르지 않은 자동차 후보"를 뽑는다.
///
/// 설계 근거는
/// docs/superpowers/specs/2026-08-19-route-alternatives-and-guidance-design.md
/// 「1단계」, 검증 기준은
/// test/domain/route/directions_route_alternatives_test.dart가 단일 출처다.
library;

import '../../models/route/directions_route.dart';

/// [options]에서 [selectedIndex]번째를 뺀 나머지 경로를 원래 순서로 준다.
///
/// [selectedIndex]가 범위 밖(음수·길이 이상)이어도 던지지 않고 **전부**
/// 돌려준다 — 목록이 줄어든 직후 한 틱 동안 그 상태가 실제로 생기고,
/// 그때는 파란 본선이 없으니 겹칠 대상도 없다.
///
/// 좌표가 2개 미만인 후보는 뺀다 — 빈 LineString은 MapLibre에서 조용히
/// 사라지거나 던진다.
List<DirectionsRoute> unselectedDirectionsRoutes(
  List<DirectionsRouteOption> options,
  int selectedIndex,
) => [
  for (var i = 0; i < options.length; i++)
    if (i != selectedIndex && options[i].route.points.length >= 2)
      options[i].route,
];
