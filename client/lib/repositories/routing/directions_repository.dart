import 'package:latlong2/latlong.dart';

import '../../models/route/directions_route.dart';

abstract class DirectionsRepository {
  /// origin에서 destination까지의 도보 경로를 반환한다. 실패하면 null.
  Future<DirectionsRoute?> getWalkingRoute({
    required LatLng origin,
    required LatLng destination,
  });

  /// origin에서 destination까지의 **자동차** 경로를 반환한다. 실패하면 null.
  ///
  /// 도보와 메서드를 나눈 이유는 부르는 API가 다르기 때문이다(보행자 경로는
  /// `/routes/pedestrian`, 자동차는 `/routes`). 한 메서드에 수단 플래그를 두면
  /// 호출부가 "실패했다"와 "그 수단은 지원 안 한다"를 구분할 수 없다 — 둘 다
  /// null로 돌아오는데, 사용자에게 해야 할 말은 서로 다르다.
  Future<DirectionsRoute?> getDrivingRoute({
    required LatLng origin,
    required LatLng destination,
  });

  /// 자동차 경로 후보 여러 개. `feature-car-route-alternatives` 브랜치의
  /// `getDrivingRoutes()`를 반환 타입만 [DirectionsRouteOptions](라벨 있는
  /// 목록 봉투)로 바꿔 옮긴 것이다.
  Future<DirectionsRouteOptions> getDrivingRouteOptions({
    required LatLng origin,
    required LatLng destination,
  });
}
