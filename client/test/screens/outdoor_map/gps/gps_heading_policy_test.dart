import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/screens/outdoor_map/gps/gps_heading_policy.dart';

/// 야외 마커의 방향 삼각형을 GPS 좌표에서 뽑는 규칙.
///
/// 지키려는 증상 둘.
///   - **서 있는데 삼각형이 돈다** — 멈춰 있을 때의 `heading`은 진행 방향이
///     아니라 좌표 잡음이 만든 각이다.
///   - **걸음을 멈출 때마다 삼각형이 깜빡인다** — 방향을 잠깐 들고 있지 않으면
///     신호등마다 사라졌다 나타난다.
void main() {
  final t0 = DateTime.utc(2026, 8, 26, 12);

  group('usableGpsHeadingDeg', () {
    test('걷는 속도로 움직이면 그 방향을 그대로 쓴다', () {
      expect(
        usableGpsHeadingDeg(
          headingDeg: 137,
          headingAccuracyDeg: 20,
          speedMps: 1.3,
        ),
        137,
      );
    });

    test('서 있으면 방향이 없다', () {
      // 값이 실려 와도 버린다 — 움직이지 않으면 "진행 방향"이라는 것이 없다.
      expect(
        usableGpsHeadingDeg(
          headingDeg: 137,
          headingAccuracyDeg: 5,
          speedMps: 0.1,
        ),
        isNull,
      );
    });

    test('기기가 방향을 못 주면(iOS는 -1) 버린다', () {
      expect(
        usableGpsHeadingDeg(
          headingDeg: -1,
          headingAccuracyDeg: -1,
          speedMps: 1.3,
        ),
        isNull,
      );
    });

    test('정확도가 실려 왔고 그 값이 나쁘면 버린다', () {
      expect(
        usableGpsHeadingDeg(
          headingDeg: 137,
          headingAccuracyDeg: outdoorHeadingMaxAccuracyDeg + 1,
          speedMps: 1.3,
        ),
        isNull,
      );
    });

    test('정확도 0은 "모른다"라, 그것 때문에 버리지는 않는다', () {
      // Android는 못 구했을 때 0을 준다. 0을 "오차 0도"로 읽으면 가장 못 믿을
      // 값이 가장 정확한 값이 된다.
      expect(
        usableGpsHeadingDeg(
          headingDeg: 137,
          headingAccuracyDeg: 0,
          speedMps: 1.3,
        ),
        137,
      );
    });
  });

  group('OutdoorHeadingTracker', () {
    test('걸음을 잠깐 멈춰도 방금까지 알던 방향을 들고 있는다', () {
      final tracker = OutdoorHeadingTracker();
      tracker.track(
        headingDeg: 90,
        headingAccuracyDeg: 10,
        speedMps: 1.4,
        at: t0,
      );
      final held = tracker.track(
        headingDeg: 0,
        headingAccuracyDeg: 10,
        speedMps: 0,
        at: t0.add(const Duration(seconds: 2)),
      );
      expect(held, 90);
    });

    test('오래 서 있으면 잊는다', () {
      final tracker = OutdoorHeadingTracker();
      tracker.track(
        headingDeg: 90,
        headingAccuracyDeg: 10,
        speedMps: 1.4,
        at: t0,
      );
      final forgotten = tracker.track(
        headingDeg: 0,
        headingAccuracyDeg: 10,
        speedMps: 0,
        at: t0.add(outdoorHeadingMemory + const Duration(seconds: 1)),
      );
      expect(forgotten, isNull, reason: '그동안 몸이 돌아갔을 수 있다 — 없는 편이 틀린 것보다 낫다');
    });

    test('reset은 마지막으로 알던 방향까지 버린다', () {
      final tracker = OutdoorHeadingTracker();
      tracker.track(
        headingDeg: 90,
        headingAccuracyDeg: 10,
        speedMps: 1.4,
        at: t0,
      );
      tracker.reset();
      expect(tracker.headingDeg, isNull);
    });
  });
}
