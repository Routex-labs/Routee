import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/route/directions_route.dart';
import 'package:navigation_client/repositories/routing/mock_directions_repository.dart';

void main() {
  test('returns a straight line with distance and duration', () async {
    final repository = MockDirectionsRepository();
    const origin = LatLng(37.5665, 126.9780);
    const destination = LatLng(37.5665, 126.9790);

    final route = await repository.getWalkingRoute(
      origin: origin,
      destination: destination,
    );

    expect(route, isNotNull);
    expect(route!.points, [origin, destination]);
    expect(route.distanceMeters, greaterThan(0));
    expect(route.durationSeconds, greaterThan(0));
  });

  test('자동차 후보 2개(추천/최단거리)를 돌려준다', () async {
    final repository = MockDirectionsRepository();

    final options = await repository.getDrivingRouteOptions(
      origin: const LatLng(37.5665, 126.9780),
      destination: const LatLng(37.5665, 126.9790),
    );

    expect(options.hasRoutes, isTrue);
    expect(options.options.length, 2);
    expect(
      options.options[0].kinds,
      [DirectionsRouteOptionKind.recommended],
    );
    expect(
      options.options[1].kinds,
      [DirectionsRouteOptionKind.shortestDistance],
    );
  });
}
