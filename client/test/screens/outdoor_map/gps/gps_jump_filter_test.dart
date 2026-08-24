import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:navigation_client/screens/outdoor_map/gps/gps_jump_filter.dart';

/// 위도 1도 ≈ 111.32 km. 북쪽으로 [meters]만큼 옮긴 좌표.
ll.LatLng north(ll.LatLng from, double meters) =>
    ll.LatLng(from.latitude + meters / 111320.0, from.longitude);

void main() {
  const door = ll.LatLng(37.5665, 126.9780);
  final t0 = DateTime.utc(2026, 8, 20, 9);

  test('첫 좌표는 비교할 기준이 없어 그대로 통과한다', () {
    final step = stepGpsJumpFilter(
      state: const GpsJumpFilterState(),
      point: door,
      at: t0,
      walking: true,
    );
    expect(step.accepted, isTrue);
    expect(step.jumpM, isNull);
    expect(step.state.acceptedPoint, door);
  });

  test('걸어서 갈 수 있는 이동은 통과한다', () {
    final first = stepGpsJumpFilter(
      state: const GpsJumpFilterState(),
      point: door,
      at: t0,
      walking: true,
    );
    // 5초에 10 m = 2 m/s. 상한(3.5) 아래다.
    final step = stepGpsJumpFilter(
      state: first.state,
      point: north(door, 10),
      at: t0.add(const Duration(seconds: 5)),
      walking: true,
    );
    expect(step.accepted, isTrue);
    expect(step.surrendered, isFalse);
    expect(step.jumpM, closeTo(10, 0.5));
    expect(step.state.rejectedInARow, 0);
  });

  test('실측 도약(5초에 51.7 m)은 거르고 기준점을 안 옮긴다', () {
    final first = stepGpsJumpFilter(
      state: const GpsJumpFilterState(),
      point: door,
      at: t0,
      walking: true,
    );
    final step = stepGpsJumpFilter(
      state: first.state,
      point: north(door, 51.7),
      at: t0.add(const Duration(seconds: 5)),
      walking: true,
    );
    expect(step.accepted, isFalse);
    expect(step.jumpM, closeTo(51.7, 0.5));
    // 15 + 3.5*5 = 32.5
    expect(step.allowanceM, closeTo(32.5, 0.01));
    expect(step.state.acceptedPoint, door);
    expect(step.state.rejectedInARow, 1);
  });

  test('자동차 안내 중에는 보행 상한을 대지 않는다', () {
    final first = stepGpsJumpFilter(
      state: const GpsJumpFilterState(),
      point: door,
      at: t0,
      walking: true,
    );
    final step = stepGpsJumpFilter(
      state: first.state,
      point: north(door, 300),
      at: t0.add(const Duration(seconds: 5)),
      walking: false,
    );
    expect(step.accepted, isTrue);
    expect(step.state.acceptedPoint, isNot(door));
  });

  test('연속 5건을 거르면 항복하고 받아들인다', () {
    var state = stepGpsJumpFilter(
      state: const GpsJumpFilterState(),
      point: door,
      at: t0,
      walking: true,
    ).state;
    final accepted = <bool>[];
    final surrendered = <bool>[];
    for (var i = 1; i <= kJumpFilterSurrenderCount; i++) {
      final step = stepGpsJumpFilter(
        state: state,
        // 항복이 **건수**로 걸리게 시간은 짧게 둔다(5건 × 1초 < 10초).
        point: north(door, 500.0 * i),
        at: t0.add(Duration(seconds: i)),
        walking: true,
      );
      state = step.state;
      accepted.add(step.accepted);
      surrendered.add(step.surrendered);
    }
    expect(accepted, [false, false, false, false, true]);
    expect(surrendered.last, isTrue);
    // 항복한 좌표가 새 기준이 된다 — 안 그러면 다음 건도 전부 걸린다.
    expect(state.acceptedPoint!.latitude, greaterThan(door.latitude));
    expect(state.rejectedInARow, 0);
  });

  test('건수를 못 채워도 10초가 지나면 항복한다', () {
    final first = stepGpsJumpFilter(
      state: const GpsJumpFilterState(),
      point: door,
      at: t0,
      walking: true,
    );
    // 스트림이 20초에 한 건을 주는 기기. 두 번째 건에서 시간으로 항복한다.
    final one = stepGpsJumpFilter(
      state: first.state,
      point: north(door, 400),
      at: t0.add(const Duration(seconds: 1)),
      walking: true,
    );
    expect(one.accepted, isFalse);
    final two = stepGpsJumpFilter(
      state: one.state,
      point: north(door, 800),
      at: t0.add(const Duration(seconds: 21)),
      walking: true,
    );
    expect(two.accepted, isTrue);
    expect(two.surrendered, isTrue);
  });

  test('경과 시간이 0이거나 거꾸로 가도 0으로 나누지 않는다', () {
    final first = stepGpsJumpFilter(
      state: const GpsJumpFilterState(),
      point: door,
      at: t0,
      walking: true,
    );
    // 같은 시각 — 허용치는 유예분만 남는다.
    final same = stepGpsJumpFilter(
      state: first.state,
      point: north(door, 51.7),
      at: t0,
      walking: true,
    );
    expect(same.accepted, isFalse);
    expect(same.allowanceM, kJumpFilterGraceMeters);
    expect(same.elapsedSeconds, 0);
    // 시계가 거꾸로 간 경우도 같은 자리다. 유예분 안이면 통과한다.
    final backwards = stepGpsJumpFilter(
      state: first.state,
      point: north(door, 3),
      at: t0.subtract(const Duration(seconds: 30)),
      walking: true,
    );
    expect(backwards.accepted, isTrue);
    expect(backwards.allowanceM, kJumpFilterGraceMeters);
  });
}
