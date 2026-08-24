import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/route/route_endpoint_fill.dart';
import 'package:navigation_client/models/route/directions_route.dart';

/// 경로의 **시작**을 실제 출발점에 맞추는 규칙([extendRouteFromOrigin]).
///
/// 끝을 맞추는 쪽(`route_endpoint_fill_test.dart`)과 같은 문턱을 쓰는 것이
/// 이 파일이 지키려는 것이다 — 한쪽만 고치면 같은 여정의 두 끝이 다른 규칙으로
/// 이어진다.
void main() {
  /// 더현대 서울 남서쪽 문. 실측 좌표는 끝 맞추기 테스트와 같은 점을 쓴다.
  const door = LatLng(37.52520479, 126.92870807);

  DirectionsRoute route(
    List<LatLng> points, {
    double distanceMeters = 120,
    int durationSeconds = 90,
  }) => DirectionsRoute(
    points: points,
    distanceMeters: distanceMeters,
    durationSeconds: durationSeconds,
  );

  test('도로에서 시작한 선을 나온 문까지 앞으로 이어 붙인다', () {
    // TMAP이 문에서 약 24m 북쪽 도로에 스냅해 시작한 경로.
    final filled = extendRouteFromOrigin(
      route(const [
        LatLng(37.525420, 126.928708),
        LatLng(37.526000, 126.928708),
      ]),
      door,
    );

    expect(filled!.points, hasLength(3));
    expect(filled.points.first, door);
    // 뒤쪽은 손대지 않는다 — 이 함수가 맡은 것은 머리 하나다.
    expect(filled.points.last, const LatLng(37.526000, 126.928708));
    // 잇기만 할 때는 거리·시간을 건드리지 않는다(끝 맞추기와 같은 규칙).
    expect(filled.distanceMeters, 120);
    expect(filled.durationSeconds, 90);
  });

  test('사실상 같은 점이면 붙이지 않는다', () {
    final same = route(const [
      LatLng(37.525206, 126.928709),
      LatLng(37.526000, 126.928708),
    ]);

    expect(extendRouteFromOrigin(same, door)!.points, hasLength(2));
  });

  test('너무 멀면 붙이지 않는다 — 직선이 건물·도로를 관통한다', () {
    // 문에서 약 1.1km 떨어진 곳에서 시작한 경로.
    final far = route(const [
      LatLng(37.535200, 126.928708),
      LatLng(37.536000, 126.928708),
    ]);

    expect(extendRouteFromOrigin(far, door)!.points, hasLength(2));
  });

  test('출발 쪽 우회를 걷어내고 문에서 직선으로 잇는다', () {
    // 끝 맞추기 테스트의 실측을 그대로 뒤집었다 — 문에서 나가는데 TMAP이
    // 서쪽 지하철 광장에서 시작해 벽을 따라 되돌아오는 선을 준 경우다.
    final detour = [
      const LatLng(37.525064, 126.928349), // 문에서 35m 떨어진 곳에서 시작
      const LatLng(37.524989, 126.928363),
      const LatLng(37.524809, 126.928402),
      const LatLng(37.524720, 126.928591),
      const LatLng(37.524723, 126.928752), // 정류장(도착)
    ];
    final fixed = extendRouteFromOrigin(
      route(detour, distanceMeters: 69, durationSeconds: 50),
      door,
    );

    // 서쪽으로 벗어난 구간이 통째로 빠지고 문 → 정류장 두 점만 남는다.
    expect(fixed!.points, hasLength(2));
    expect(fixed.points.first, door);
    expect(fixed.points.last, detour.last);
    expect(fixed.distanceMeters, closeTo(54, 4));
    expect(fixed.durationSeconds, lessThan(50));
  });

  test('손댈 것이 없으면 원본 그대로다 — 턴바이턴을 잃지 않는다', () {
    final withSteps = DirectionsRoute(
      points: const [
        LatLng(37.525206, 126.928709),
        LatLng(37.526000, 126.928708),
      ],
      distanceMeters: 88,
      durationSeconds: 70,
      steps: const [
        DirectionsRouteStep(
          instruction: '출발',
          distanceMeters: 0,
          point: LatLng(37.525206, 126.928709),
        ),
      ],
    );

    final result = extendRouteFromOrigin(withSteps, door);
    // 같은 객체를 그대로 돌려준다. 뒤집었다 되돌리면 좌표는 같아도 `steps`가
    // 사라져, 아무 일도 없었던 경로가 안내 문구만 잃는다.
    expect(result, same(withSteps));
  });

  test('경로나 출발점이 없으면 그대로 돌려준다', () {
    expect(extendRouteFromOrigin(null, door), isNull);
    final plain = route(const [
      LatLng(37.525420, 126.928708),
      LatLng(37.526000, 126.928708),
    ]);
    expect(extendRouteFromOrigin(plain, null), same(plain));
    // 좌표가 한 점뿐이면 이을 선 자체가 없다.
    final single = route(const [LatLng(37.525420, 126.928708)]);
    expect(extendRouteFromOrigin(single, door), same(single));
  });
}
