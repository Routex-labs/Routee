import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/guidance/guidance_start_reach.dart';

/// 안내를 시작해도 되는 위치인지 판정한다. 경계값은
/// `docs/superpowers/specs/2026-08-19-transit-screen-redesign-design.md` 3절.
void main() {
  // 서울시청 앞에서 동쪽으로 뻗은 짧은 선. 위도 1도 ≈ 111 km라
  // 경도 0.001도 ≈ 88 m(위도 37.5에서)다.
  const route = [LatLng(37.5665, 126.9780), LatLng(37.5665, 126.9880)];

  test('경로 위에 서 있으면 시작할 수 있다', () {
    expect(
      canStartGuidanceFrom(
        routePoints: route,
        position: const LatLng(37.5665, 126.9800),
        maxOffsetM: 150,
      ),
      isTrue,
    );
  });

  test('경로에서 한참 떨어져 있으면 시작할 수 없다', () {
    // 위도 +0.01도 ≈ 1.1 km 북쪽.
    expect(
      canStartGuidanceFrom(
        routePoints: route,
        position: const LatLng(37.5765, 126.9800),
        maxOffsetM: 150,
      ),
      isFalse,
    );
  });

  test('위치를 모르면 시작할 수 없다', () {
    expect(
      canStartGuidanceFrom(routePoints: route, position: null, maxOffsetM: 150),
      isFalse,
    );
  });

  test('경로가 선을 이루지 못하면 시작할 수 없다', () {
    expect(
      canStartGuidanceFrom(
        routePoints: const [LatLng(37.5665, 126.9780)],
        position: const LatLng(37.5665, 126.9780),
        maxOffsetM: 150,
      ),
      isFalse,
    );
  });
}
