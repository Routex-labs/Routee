import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/route/route_endpoint_fill.dart';
import 'package:navigation_client/models/route/directions_route.dart';

/// 여의도 일대. 위도 1도 ≈ 111km라 소수 넷째 자리가 약 11m다.
const _roadEnd = LatLng(37.5259, 126.9290);

DirectionsRoute _route(List<LatLng> points) => DirectionsRoute(
  points: points,
  distanceMeters: 3448,
  durationSeconds: 2880,
);

void main() {
  test('도로에서 끝난 선을 출입구까지 이어 붙인다', () {
    // 도로 끝에서 약 30m 떨어진 출입구.
    const entrance = LatLng(37.52617, 126.9290);
    final filled = extendRouteToDestination(_route(const [
      LatLng(37.5280, 126.9290),
      _roadEnd,
    ]), entrance);

    expect(filled!.points, hasLength(3));
    expect(filled.points.last, entrance);
    // 거리·시간은 건드리지 않는다. 여기서 더하기 시작하면 화면에 적히는 숫자의
    // 출처가 둘로 갈린다.
    expect(filled.distanceMeters, 3448);
    expect(filled.durationSeconds, 2880);
  });

  test('사실상 같은 점이면 붙이지 않는다', () {
    final filled = extendRouteToDestination(
      _route(const [LatLng(37.5280, 126.9290), _roadEnd]),
      const LatLng(37.52590, 126.92901),
    );

    expect(filled!.points, hasLength(2));
  });

  test('너무 멀면 붙이지 않는다 — 직선이 건물·도로를 관통한다', () {
    // 약 1.1km 떨어진 점. 끊긴 선은 "여기부터 알아서"로 읽히지만, 그어진
    // 직선은 길이라고 읽힌다.
    final filled = extendRouteToDestination(
      _route(const [LatLng(37.5280, 126.9290), _roadEnd]),
      const LatLng(37.5359, 126.9290),
    );

    expect(filled!.points, hasLength(2));
  });

  group('TMAP이 도착점에 닿지 못한 경우', () {
    // 실측 재현(더현대 서울 남서쪽 출구). 정류장에서 문까지 직선 52m인데,
    // TMAP은 서쪽으로 돌아 69m를 안내하고 그 끝점은 문에서 35m 떨어진 지하철
    // 출입구 광장이다. 화면에는 "서쪽으로 돌았다가 벽을 따라 되돌아오는" 선이
    // 남는다.
    const door = LatLng(37.52520479, 126.92870807);
    const detour = [
      LatLng(37.524723, 126.928752), // 정류장(출발)
      LatLng(37.524720, 126.928591),
      LatLng(37.524809, 126.928402), // 서쪽으로 벗어남
      LatLng(37.524989, 126.928363),
      LatLng(37.525064, 126.928349), // 문에서 35m 떨어진 곳에서 끝남
    ];

    test('우회를 걷어내고 도착점까지 직선으로 잇는다', () {
      final fixed = extendRouteToDestination(
        DirectionsRoute(
          points: detour,
          distanceMeters: 69,
          durationSeconds: 50,
        ),
        door,
      );

      // 서쪽으로 벗어나기 **전**에서 끊는다 — 출발점 하나만 남고 도착점이 붙는다.
      expect(fixed!.points, hasLength(2));
      expect(fixed.points.first, detour.first);
      expect(fixed.points.last, door);
      // 기하가 달라졌으므로 거리·시간도 새 기하를 따른다(같은 보행 속도).
      expect(fixed.distanceMeters, closeTo(54, 4));
      expect(fixed.durationSeconds, lessThan(50));
    });

    test('직선이 길면 우회로를 그대로 둔다 — 관통선이 돌아가는 길보다 나쁘다', () {
      // 같은 모양이지만 출발점이 문에서 200m 남쪽이다. 이때 그어질 직선은
      // 건물·도로를 관통한다.
      final far = [const LatLng(37.52340, 126.928752), ...detour.skip(1)];
      final fixed = extendRouteToDestination(
        DirectionsRoute(points: far, distanceMeters: 250, durationSeconds: 190),
        door,
      );

      expect(fixed!.points, hasLength(far.length + 1));
      expect(fixed.distanceMeters, 250);
    });

    test('끝점이 도착점 코앞이어도 전체가 우회면 지름길로 자른다', () {
      // 실측 재현(더현대 서울 진입 경로). TMAP 끝점은 문에서 10m 안(스냅
      // 허용치 20m 이내)이라 예전 규칙은 "제대로 도착했다"로 보고 지름길을
      // 아예 찾지 않았다 — 그래서 경로 전체가 건물을 크게 도는 사각형 루프로
      // 남았다. 출발점부터 문까지 직선은 40m인데 실제로 걸은 길은 270m다.
      const start = LatLng(37.52556419, 126.92870807);
      const detourLoop = [
        start,
        LatLng(37.52556419, 126.92938757), // 동쪽으로 60m
        LatLng(37.52466589, 126.92938757), // 남쪽으로 100m
        LatLng(37.52466589, 126.92870807), // 서쪽으로 60m
        LatLng(37.52511499, 126.92870807), // 문 쪽으로 50m 접근, 10m 못 미쳐 끝남
      ];
      final fixed = extendRouteToDestination(
        DirectionsRoute(
          points: detourLoop,
          distanceMeters: 270,
          durationSeconds: 210,
        ),
        door,
      );

      expect(fixed!.points, hasLength(2));
      expect(fixed.points.first, start);
      expect(fixed.points.last, door);
      expect(fixed.distanceMeters, closeTo(40, 4));
    });

    test('곧장 다가오다 끝났으면 이어 붙이기만 한다 — 이득이 없다', () {
      // 문 남쪽 도로를 따라 문 쪽으로 곧게 다가오다 35m 앞에서 끝난 경로.
      final straight = [
        const LatLng(37.524600, 126.928708),
        const LatLng(37.524750, 126.928708),
        const LatLng(37.524890, 126.928708),
      ];
      final fixed = extendRouteToDestination(
        DirectionsRoute(
          points: straight,
          distanceMeters: 32,
          durationSeconds: 25,
        ),
        door,
      );

      expect(fixed!.points, hasLength(straight.length + 1));
      expect(fixed.distanceMeters, 32);
    });
  });

  test('경로나 도착점이 없으면 그대로 돌려준다', () {
    expect(extendRouteToDestination(null, _roadEnd), isNull);
    final route = _route(const [LatLng(37.5280, 126.9290), _roadEnd]);
    expect(extendRouteToDestination(route, null), same(route));
    // 좌표가 한 점뿐이면 이을 선 자체가 없다.
    final single = _route(const [_roadEnd]);
    expect(
      extendRouteToDestination(single, const LatLng(37.52617, 126.9290)),
      same(single),
    );
  });
}
