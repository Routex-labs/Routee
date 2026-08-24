import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/map/icon/location_marker_icon.dart';

/// 현재 위치 마커의 방향 삼각형이 지켜야 하는 것.
///
/// 픽셀을 비교하지 않는다 — 도형이 **어디에 있고 어디를 향하는가**만 잡는다.
/// 이 둘이 틀리면 화면에서 곧바로 드러나지만(rim 안에 묻히거나 반대를 가리킨다)
/// 색·두께는 눈으로 고르는 값이다.
void main() {
  const center = Offset(100, 100);
  const coreRadius = 16.0;
  const rimRadius =
      coreRadius * kLocationMarkerRimRadiusPx / kLocationMarkerCoreRadiusPx;

  List<Offset> triangle({double radius = coreRadius}) =>
      locationMarkerHeadingTriangle(center: center, coreRadius: radius);

  test('꼭짓점 셋이 모두 흰 rim 바깥에 있다', () {
    // rim 안에서 시작하면 도트에 파묻혀 방향이 안 보인다 — 원뿔을 버린 이유다.
    for (final vertex in triangle()) {
      expect((vertex - center).distance, greaterThan(rimRadius));
    }
  });

  test('캔버스 기준 위(-y)를 향한다', () {
    // MapLibre가 비트맵 전체를 heading만큼 돌리므로, 여기서 위를 향해야 회전
    // 뒤 진행 방향과 맞는다. 아래를 향하면 마커가 정확히 반대를 가리킨다.
    final [apex, left, right] = triangle();
    expect(apex.dy, lessThan(left.dy));
    expect(apex.dy, lessThan(right.dy));
    expect(apex.dy, lessThan(center.dy - rimRadius));
    // 꼭짓점은 밑변의 한가운데 — 좌우로 기울지 않는다.
    expect(apex.dx, closeTo(center.dx, 1e-9));
    expect(left.dx, lessThan(center.dx));
    expect(right.dx, greaterThan(center.dx));
    expect(left.dy, closeTo(right.dy, 1e-9));
  });

  test('코어 반지름을 키우면 삼각형도 같은 비율로 커진다', () {
    // 크기를 상수로 박아 두면 코어만 키웠을 때 삼각형이 도트에 삼켜진다.
    final small = triangle();
    final big = triangle(radius: coreRadius * 2);
    for (var i = 0; i < 3; i++) {
      expect((big[i] - center).dx, closeTo((small[i] - center).dx * 2, 1e-9));
      expect((big[i] - center).dy, closeTo((small[i] - center).dy * 2, 1e-9));
    }
  });
}
