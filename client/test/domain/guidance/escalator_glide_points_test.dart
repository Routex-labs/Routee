import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/guidance/escalator_ride.dart';

/// 위도 37.5 기준 동쪽 [m]미터. 경도 1도 ≈ 88.4km.
LatLng _east(double m) => LatLng(37.5, 127.0 + m / 88400.0);

/// 위도 37.5 기준 북쪽 [m]미터.
LatLng _north(double m) => LatLng(37.5 + m / 111320.0, 127.0);

void main() {
  const distance = Distance();

  group('활강 시작점', () {
    // 폴리곤 축은 0m~20m 동쪽에 누워 있고, 하차 노드는 그 끝(20m)에 붙어 있다.
    // 그래프 탑승 노드는 축에서 8m 북쪽으로 벗어나 있다 — 실기기에서 마커가
    // 폴리곤 밖에서 안으로 끌려오던 그 거리다.
    final axis = (_east(0), _east(20));
    final to = _east(20);
    final strayBoarding = _north(8);

    test('축을 알면 탑승 노드는 폴리라인에 안 들어간다', () {
      final points = escalatorGlidePoints(
        from: strayBoarding,
        to: to,
        axis: axis,
      );

      expect(points.any((p) => distance(p, strayBoarding) < 0.5), isFalse);
    });

    test('축의 하차에서 먼 끝에서 시작한다', () {
      final points = escalatorGlidePoints(
        from: strayBoarding,
        to: to,
        axis: axis,
      );

      expect(distance(points.first, _east(0)), lessThan(0.5));
    });

    test('축 방향이 뒤집혀 들어와도 같은 점에서 시작한다', () {
      final points = escalatorGlidePoints(
        from: strayBoarding,
        to: to,
        axis: (axis.$2, axis.$1),
      );

      expect(distance(points.first, _east(0)), lessThan(0.5));
    });

    test('하차 노드와 1m 안으로 겹치는 축 끝은 버린다', () {
      // 안 버리면 그 구간 길이가 0에 가까워 진행률이 0으로 나뉜다.
      final points = escalatorGlidePoints(
        from: strayBoarding,
        to: to,
        axis: axis,
      );

      expect(points, hasLength(2));
      expect(distance(points.last, to), lessThan(0.01));
    });

    test('하차 노드가 축 끝에서 떨어져 있으면 축 끝을 경유한다', () {
      final offAxisArrival = _east(24);

      final points = escalatorGlidePoints(
        from: strayBoarding,
        to: offAxisArrival,
        axis: axis,
      );

      expect(points, hasLength(3));
      expect(distance(points[1], _east(20)), lessThan(0.5));
    });

    test('축을 모르면 예전대로 두 노드를 직선으로 잇는다', () {
      final points = escalatorGlidePoints(
        from: strayBoarding,
        to: to,
        axis: null,
      );

      expect(points, [strayBoarding, to]);
    });

    test('축 전체가 하차 노드에 뭉개져 있으면 옮기지 않는다', () {
      final squashed = (_east(20), _east(20.2));

      final points = escalatorGlidePoints(
        from: strayBoarding,
        to: to,
        axis: squashed,
      );

      expect(points, [strayBoarding, to]);
    });
  });

  group('활강 폴리라인에서 뽑는 하차 방향', () {
    test('마지막 구간 방향을 낸다', () {
      final bearing = escalatorGlideExitBearingDeg([
        _east(0),
        _east(20),
        LatLng(_north(6).latitude, _east(20).longitude),
      ]);

      expect(bearing, closeTo(0, 1));
    });

    test('마지막 구간이 너무 짧으면 축 전체를 본다', () {
      // 도면이 하차 노드를 축 끝에 1~3m로 찍어 둔 층. 그 짧은 구간만 보면
      // 좌표 오차가 방향이 되므로 축까지 거슬러 올라간다.
      final bearing = escalatorGlideExitBearingDeg([
        _east(0),
        _east(20),
        _east(21.5),
      ]);

      expect(bearing, closeTo(90, 1));
    });

    test('폴리라인 전체가 겹쳐 있으면 방향을 단정하지 않는다', () {
      final bearing = escalatorGlideExitBearingDeg([_east(0), _east(1)]);

      expect(bearing, isNull);
    });
  });
}
