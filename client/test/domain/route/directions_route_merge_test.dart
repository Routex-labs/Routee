import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/route/directions_route_merge.dart';
import 'package:navigation_client/models/route/directions_route.dart';

void main() {
  const routeA = DirectionsRoute(
    points: [LatLng(0, 0), LatLng(1, 1)],
    distanceMeters: 100,
    durationSeconds: 60,
  );
  const routeASameGeometry = DirectionsRoute(
    points: [LatLng(0, 0), LatLng(1, 1)],
    distanceMeters: 100,
    durationSeconds: 60,
  );
  const routeB = DirectionsRoute(
    points: [LatLng(0, 0), LatLng(2, 2)],
    distanceMeters: 200,
    durationSeconds: 90,
  );

  test('좌표열이 같으면 kinds를 합치고 한 줄로 남는다', () {
    final merged = mergeDirectionsRouteOptions([
      (DirectionsRouteOptionKind.recommended, routeA),
      (DirectionsRouteOptionKind.alternative, routeASameGeometry),
    ]);

    expect(merged.length, 1);
    expect(merged.single.kinds, [
      DirectionsRouteOptionKind.recommended,
      DirectionsRouteOptionKind.alternative,
    ]);
  });

  test('좌표열이 다르면 따로 두고 추천이 최단거리보다 먼저 온다', () {
    final merged = mergeDirectionsRouteOptions([
      (DirectionsRouteOptionKind.shortestDistance, routeB),
      (DirectionsRouteOptionKind.recommended, routeA),
    ]);

    expect(merged.length, 2);
    expect(merged[0].kinds, [DirectionsRouteOptionKind.recommended]);
    expect(merged[0].route, routeA);
    expect(merged[1].kinds, [DirectionsRouteOptionKind.shortestDistance]);
  });

  test('같은 kind가 두 번 들어와도 kinds에는 한 번만 남는다', () {
    final merged = mergeDirectionsRouteOptions([
      (DirectionsRouteOptionKind.recommended, routeA),
      (DirectionsRouteOptionKind.alternative, routeASameGeometry),
      (DirectionsRouteOptionKind.alternative, routeASameGeometry),
    ]);

    expect(merged.length, 1);
    expect(merged.single.kinds, [
      DirectionsRouteOptionKind.recommended,
      DirectionsRouteOptionKind.alternative,
    ]);
  });

  test('입력이 비면 빈 목록을 돌려준다', () {
    expect(mergeDirectionsRouteOptions([]), isEmpty);
  });
}
