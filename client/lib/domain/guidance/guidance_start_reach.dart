import 'package:latlong2/latlong.dart';

import 'geo_route_progress.dart';

/// 지금 위치에서 안내를 시작해도 되는지.
///
/// [position]이 null이거나 [routePoints]가 선을 이루지 못하면 false다. 위치를
/// 모르는 채 카메라만 옮기면 사용자는 자기가 어디 있는지 모르는 화면을 본다.
///
/// [computeGeoRouteProgress]에 `previousTraveledM`을 넘기지 않는 것이 핵심이다.
/// 넘기면 검색 창이 걸려 멀리 있는 위치에서 엉뚱한 구간에 붙는다.
bool canStartGuidanceFrom({
  required List<LatLng> routePoints,
  required LatLng? position,
  required double maxOffsetM,
}) {
  if (position == null) return false;
  final progress = computeGeoRouteProgress(
    routePoints: routePoints,
    position: position,
  );
  if (progress == null) return false;
  return progress.offsetM <= maxOffsetM;
}
