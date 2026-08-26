import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
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

  /// 건물을 나선 직후를 지킨다. 수신기가 아직 위성을 다시 못 잡은 동안 course는
  /// "모른다"가 아니라 **틀린 값이 자신 있게** 온다 — 그 값과 우리가 잰 이동
  /// 방향을 맞춰 봐야 가려낼 수 있다.
  ///
  /// 사용자가 보는 것은 **점이 간 쪽과 삼각형이 가리키는 쪽의 관계**뿐이라,
  /// 그 둘이 어긋나면 수신기가 뭐라고 하든 화면에서는 오류로 읽힌다.
  group('OutdoorHeadingTracker — 이동 방향과 대조', () {
    /// [northM]만큼 북쪽으로 옮긴 좌표. 위도 1도 ≈ 111,320m.
    ll.LatLng north(ll.LatLng from, double northM) =>
        ll.LatLng(from.latitude + northM / 111320, from.longitude);

    final door = ll.LatLng(37.5259, 126.9285);

    test('실제로 북쪽으로 걸었는데 course가 남쪽이면 걸어온 쪽을 쓴다', () {
      final tracker = OutdoorHeadingTracker();
      tracker.track(
        headingDeg: 180,
        headingAccuracyDeg: 0,
        speedMps: 1.4,
        at: t0,
        point: door,
      );
      final drawn = tracker.track(
        headingDeg: 180,
        headingAccuracyDeg: 0,
        speedMps: 1.4,
        at: t0.add(const Duration(seconds: 6)),
        point: north(door, 8),
      );
      expect(
        drawn,
        closeTo(0, 0.5),
        reason: '반사 신호가 만든 course는 등을 진다 — 점이 실제로 간 쪽을 그린다',
      );
    });

    test('수신기가 방향을 아예 못 줘도 걸어온 쪽으로 삼각형을 그린다', () {
      final tracker = OutdoorHeadingTracker();
      tracker.track(
        headingDeg: -1,
        headingAccuracyDeg: -1,
        speedMps: 0,
        at: t0,
        point: door,
      );
      final drawn = tracker.track(
        headingDeg: -1,
        headingAccuracyDeg: -1,
        speedMps: 0,
        at: t0.add(const Duration(seconds: 6)),
        point: north(door, 8),
      );
      expect(
        drawn,
        closeTo(0, 0.5),
        reason: '기기가 못 주는 값이지 우리가 모르는 방향이 아니다',
      );
    });

    test('걸어온 방향과 맞으면 그대로 쓴다', () {
      final tracker = OutdoorHeadingTracker();
      tracker.track(
        headingDeg: 0,
        headingAccuracyDeg: 0,
        speedMps: 1.4,
        at: t0,
        point: door,
      );
      final drawn = tracker.track(
        headingDeg: 0,
        headingAccuracyDeg: 0,
        speedMps: 1.4,
        at: t0.add(const Duration(seconds: 6)),
        point: north(door, 8),
      );
      expect(drawn, 0);
    });

    test('움직임이 짧으면 대조하지 않는다 — 그 방향은 오차가 만든 것이다', () {
      final tracker = OutdoorHeadingTracker();
      tracker.track(
        headingDeg: 180,
        headingAccuracyDeg: 0,
        speedMps: 1.4,
        at: t0,
        point: door,
      );
      final drawn = tracker.track(
        headingDeg: 180,
        headingAccuracyDeg: 0,
        speedMps: 1.4,
        at: t0.add(const Duration(seconds: 2)),
        point: north(door, outdoorHeadingCrossCheckMinTravelM - 1),
      );
      expect(drawn, 180, reason: '틀렸다는 증거가 없으면 거부하지 않는다');
    });

    test('좌표 사이가 오래 끊겼으면 대조하지 않는다', () {
      final tracker = OutdoorHeadingTracker();
      tracker.track(
        headingDeg: 180,
        headingAccuracyDeg: 0,
        speedMps: 1.4,
        at: t0,
        point: door,
      );
      final drawn = tracker.track(
        headingDeg: 180,
        headingAccuracyDeg: 0,
        speedMps: 1.4,
        at: t0.add(outdoorHeadingCrossCheckMaxGap + const Duration(seconds: 1)),
        point: north(door, 30),
      );
      expect(drawn, 180, reason: '그사이 어디를 돌아 왔는지 모른다');
    });

    test('reset 뒤 첫 좌표는 대조할 기준이 없어 그대로 통과한다', () {
      final tracker = OutdoorHeadingTracker();
      tracker.track(
        headingDeg: 0,
        headingAccuracyDeg: 0,
        speedMps: 1.4,
        at: t0,
        point: door,
      );
      tracker.reset();
      final drawn = tracker.track(
        headingDeg: 180,
        headingAccuracyDeg: 0,
        speedMps: 1.4,
        at: t0.add(const Duration(seconds: 6)),
        point: north(door, 8),
      );
      expect(
        drawn,
        180,
        reason: '건물을 가로질러 나온 직선을 진행 방향으로 삼지 않는다',
      );
    });
  });
}
