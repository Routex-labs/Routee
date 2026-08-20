import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/route/directions_route_alternatives.dart';
import 'package:navigation_client/models/route/directions_route.dart';

DirectionsRouteOption _option(List<LatLng> points) => DirectionsRouteOption(
  kinds: const [DirectionsRouteOptionKind.recommended],
  route: DirectionsRoute(
    points: points,
    distanceMeters: 100,
    durationSeconds: 60,
  ),
);

final _a = _option([const LatLng(37.0, 127.0), const LatLng(37.1, 127.1)]);
final _b = _option([const LatLng(37.2, 127.2), const LatLng(37.3, 127.3)]);
final _c = _option([const LatLng(37.4, 127.4), const LatLng(37.5, 127.5)]);

void main() {
  test('선택한 후보만 빼고 원래 순서를 유지한다', () {
    final result = unselectedDirectionsRoutes([_a, _b, _c], 1);
    expect(result, [_a.route, _c.route]);
  });

  test('빈 목록은 빈 목록이다', () {
    expect(unselectedDirectionsRoutes([], 0), isEmpty);
    expect(unselectedDirectionsRoutes([], -1), isEmpty);
  });

  test('선택 인덱스가 음수면 던지지 않고 전부 준다', () {
    expect(unselectedDirectionsRoutes([_a, _b], -1), [_a.route, _b.route]);
  });

  test('선택 인덱스가 길이 이상이면 던지지 않고 전부 준다', () {
    expect(unselectedDirectionsRoutes([_a, _b], 2), [_a.route, _b.route]);
    expect(unselectedDirectionsRoutes([_a, _b], 99), [_a.route, _b.route]);
  });

  test('좌표가 2개 미만인 후보는 뺀다', () {
    final empty = _option(const []);
    final single = _option([const LatLng(37.9, 127.9)]);
    expect(unselectedDirectionsRoutes([_a, empty, single, _b], 0), [_b.route]);
  });

  test('후보가 하나뿐이고 그것이 선택이면 빈 목록이다', () {
    expect(unselectedDirectionsRoutes([_a], 0), isEmpty);
  });
}
