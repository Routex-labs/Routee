import 'package:latlong2/latlong.dart';

import '../../models/route/directions_route.dart';
import 'directions_repository.dart';

const _walkingSpeedMetersPerSecond = 1.2;

/// 도심 자동차 평균 속도(m/s). 시속 22 km쯤으로, 신호·정체를 포함한 값이다.
/// 직선 거리에 곱하는 값이라 정확도를 논할 수준은 아니고, "도보보다 몇 배
/// 빠르다"는 감만 맞추면 된다.
const _drivingSpeedMetersPerSecond = 6.0;

/// 실제 경로 API(TMAP 등) 없이 출발지-목적지 직선을 경로로 취급한다.
/// 실제 라우팅이 준비되면 [TmapDirectionsRepository]로 교체한다.
class MockDirectionsRepository implements DirectionsRepository {
  @override
  Future<DirectionsRoute?> getWalkingRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final distance = const Distance().as(LengthUnit.Meter, origin, destination);
    return DirectionsRoute(
      points: [origin, destination],
      distanceMeters: distance,
      durationSeconds: (distance / _walkingSpeedMetersPerSecond).round(),
    );
  }

  @override
  Future<DirectionsRoute?> getDrivingRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final distance = const Distance().as(LengthUnit.Meter, origin, destination);
    return DirectionsRoute(
      points: [origin, destination],
      distanceMeters: distance,
      durationSeconds: (distance / _drivingSpeedMetersPerSecond).round(),
      // 요금은 **지어내지 않는다.** 거리로 곱해 만든 숫자를 "통행료 3,200원"
      // 처럼 적으면 사용자는 그것을 조회된 값으로 읽는다. 없으면 카드가 그
      // 줄을 아예 안 그린다.
    );
  }

  @override
  Future<DirectionsRouteOptions> getDrivingRouteOptions({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final direct = await getDrivingRoute(origin: origin, destination: destination);
    if (direct == null) {
      return const DirectionsRouteOptions.failure();
    }
    // 대안 후보: 중점을 살짝 밀어 올린 경유점을 하나 끼운 두 번째 선. 실제
    // API처럼 값이 달라야 목록이 둘로 보인다 — 완전히 같으면
    // mergeDirectionsRouteOptions가 하나로 합쳐 버린다.
    final midpoint = LatLng(
      (origin.latitude + destination.latitude) / 2 + 0.002,
      (origin.longitude + destination.longitude) / 2,
    );
    final viaDistance =
        const Distance().as(LengthUnit.Meter, origin, midpoint) +
        const Distance().as(LengthUnit.Meter, midpoint, destination);
    final alternative = DirectionsRoute(
      points: [origin, midpoint, destination],
      distanceMeters: viaDistance,
      durationSeconds: (viaDistance / _drivingSpeedMetersPerSecond).round(),
    );
    return DirectionsRouteOptions.ok([
      DirectionsRouteOption(
        kinds: const [DirectionsRouteOptionKind.recommended],
        route: direct,
      ),
      DirectionsRouteOption(
        kinds: const [DirectionsRouteOptionKind.shortestDistance],
        route: alternative,
      ),
    ]);
  }
}
