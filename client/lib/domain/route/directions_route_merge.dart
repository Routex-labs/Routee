/// 자동차 경로 후보(kind, DirectionsRoute) 묶음을 화면에 보일 목록으로
/// 합친다.
///
/// 좌표열이 같은 후보는 한 줄로 합치고, 순서는 추천 > 최단거리 > 대안이다.
/// 총거리·시간이 아니라 좌표열로 비교하는 이유: 길이가 같은 다른 도로를
/// 같은 경로로 묶거나, 같은 도로를 반올림 오차로 다른 경로로 가르는 것을
/// 막기 위해서다.
library;

import '../../models/route/directions_route.dart';

const _kindPriority = [
  DirectionsRouteOptionKind.recommended,
  DirectionsRouteOptionKind.shortestDistance,
  DirectionsRouteOptionKind.alternative,
];

/// [candidates]를 kind 우선순위로 정렬하고 좌표열이 같은 것을 합친다.
List<DirectionsRouteOption> mergeDirectionsRouteOptions(
  List<(DirectionsRouteOptionKind, DirectionsRoute)> candidates,
) {
  final sorted = [...candidates]..sort(
    (a, b) =>
        _kindPriority.indexOf(a.$1).compareTo(_kindPriority.indexOf(b.$1)),
  );
  final order = <String>[];
  final byKey = <String, DirectionsRouteOption>{};
  for (final (kind, route) in sorted) {
    final key = _geometryKey(route);
    final existing = byKey[key];
    if (existing == null) {
      order.add(key);
      byKey[key] = DirectionsRouteOption(kinds: [kind], route: route);
    } else if (!existing.kinds.contains(kind)) {
      // searchOption 2·3이 둘 다 alternative로 매핑돼, 좌표열까지 같으면 같은
      // kind가 두 번 들어온다. 그대로 두면 목록이 "추천 · 대안 · 대안"이 된다.
      byKey[key] = DirectionsRouteOption(
        kinds: [...existing.kinds, kind],
        route: existing.route,
      );
    }
  }
  return [for (final key in order) byKey[key]!];
}

String _geometryKey(DirectionsRoute route) =>
    route.points.map((p) => '${p.latitude},${p.longitude}').join(';');
