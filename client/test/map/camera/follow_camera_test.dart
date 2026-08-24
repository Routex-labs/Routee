import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/map/camera/follow_camera.dart';

/// 팔로우 카메라 각도 산수의 검증 기준.
///
/// 화면 코드에 묻으면 확인할 방법이 없어 따로 뺀 계산이다. 여기서 지키는 것은
/// 다섯 — 0/360을 넘는 최단 경로, 나침반↔걷는 방향 혼합, 유예 시각, 데드밴드,
/// 프레임 보간.
void main() {
  group('lerpBearingDeg', () {
    test('359°에서 1°로 갈 때 한 바퀴 돌지 않는다', () {
      // 단순 보간이면 180이 나온다 — 화면이 통째로 뒤집힌다.
      expect(lerpBearingDeg(359, 1, 0.5), closeTo(0, 1e-9));
    });

    test('경계를 넘는 방향이 짧은 쪽으로 잡힌다', () {
      expect(lerpBearingDeg(10, 350, 0.5), closeTo(0, 1e-9));
      expect(lerpBearingDeg(350, 10, 0.25), closeTo(355, 1e-9));
    });

    test('t는 0~1로 잘리고 결과는 [0,360)에 든다', () {
      expect(lerpBearingDeg(10, 350, 0), closeTo(10, 1e-9));
      expect(lerpBearingDeg(10, 350, 5), closeTo(350, 1e-9));
      expect(lerpBearingDeg(350, 30, 1), closeTo(30, 1e-9));
    });
  });

  group('blendedFollowBearingDeg', () {
    double blend({
      required double orientation,
      double? walking,
      required bool isWalking,
      double weight = 0.6,
    }) => blendedFollowBearingDeg(
      orientationHeadingDeg: orientation,
      walkingHeadingDeg: walking,
      walking: isWalking,
      walkingPullWeight: weight,
    );

    test('멈춰 있으면 나침반 각을 그대로 쓴다', () {
      expect(blend(orientation: 30, walking: 120, isWalking: false), 30);
    });

    test('걷는 방향을 모르면 걷는 중이어도 나침반 각이다', () {
      expect(blend(orientation: 30, walking: null, isWalking: true), 30);
    });

    test('걷는 동안에는 걷는 방향 쪽으로 끌려간다 — 갈아치우지는 않는다', () {
      final blended = blend(orientation: 0, walking: 100, isWalking: true);
      expect(blended, closeTo(60, 1e-9));
      expect(blended, greaterThan(0));
      expect(blended, lessThan(100));
    });

    test('혼합도 0/360을 넘어 최단 경로로 간다', () {
      expect(
        blend(orientation: 350, walking: 10, isWalking: true, weight: 0.5),
        closeTo(0, 1e-9),
      );
    });
  });

  group('nextFollowCameraBearingDeg', () {
    double? next({
      required int nowMs,
      int notBeforeMs = 0,
      double? lastBearingDeg,
      bool targetMoved = true,
      required double desired,
      double deadbandDeg = 8,
    }) => nextFollowCameraBearingDeg(
      nowMs: nowMs,
      notBeforeMs: notBeforeMs,
      lastBearingDeg: lastBearingDeg,
      targetMoved: targetMoved,
      desiredBearingDeg: desired,
      deadbandDeg: deadbandDeg,
    );

    test('유예 시각 전에는 아무것도 명령하지 않는다', () {
      expect(next(nowMs: 1000, notBeforeMs: 1400, desired: 90), isNull);
      expect(next(nowMs: 1400, notBeforeMs: 1400, desired: 90), 90);
    });

    test('첫 명령에는 데드밴드를 적용하지 않는다', () {
      expect(next(nowMs: 0, lastBearingDeg: null, desired: 3), 3);
    });

    test('데드밴드 안의 흔들림으로는 각을 바꾸지 않는다', () {
      // 위치는 따라가되 각은 이전 값 그대로 — 서 있는 지도가 진동하지 않는다.
      expect(next(nowMs: 0, lastBearingDeg: 90, desired: 95), 90);
      expect(next(nowMs: 0, lastBearingDeg: 90, desired: 99), 99);
    });

    test('데드밴드도 0/360을 넘어 잰다', () {
      // 358°와 2°는 4° 차이다. 360을 그냥 빼면 356°로 읽혀 화면이 돈다.
      expect(next(nowMs: 0, lastBearingDeg: 358, desired: 2), 358);
    });

    test('각도 흔들림도 데드밴드에 먹히고 위치도 그대로면 건너뛴다', () {
      expect(
        next(nowMs: 0, lastBearingDeg: 90, desired: 93, targetMoved: false),
        isNull,
      );
    });

    test('각이 데드밴드를 넘으면 제자리에 서 있어도 돌린다', () {
      expect(
        next(nowMs: 0, lastBearingDeg: 90, desired: 130, targetMoved: false),
        130,
      );
    });
  });

  group('glidedFollowBearingDeg', () {
    const tau = Duration(milliseconds: 120);
    const maxRate = 90.0;
    const frame = Duration(milliseconds: 16);

    double glide(
      double shown,
      double target, {
      Duration elapsed = frame,
      double rate = maxRate,
    }) => glidedFollowBearingDeg(
      shown: shown,
      target: target,
      elapsed: elapsed,
      timeConstant: tau,
      maxRateDegPerSec: rate,
    );

    /// [target]까지 도는 동안의 프레임별 회전량(도).
    List<double> steps(double target, {int frames = 60}) {
      final out = <double>[];
      var shown = 0.0;
      for (var i = 0; i < frames; i++) {
        final next = glide(shown, target);
        out.add(bearingGapDeg(next, shown));
        shown = next;
      }
      return out;
    }

    test('한 프레임에 다 돌지 않는다', () {
      final next = glide(0, 90);
      expect(next, greaterThan(0));
      expect(next, lessThan(90));
    });

    test('프레임이 길수록 더 많이 돈다', () {
      expect(
        glide(0, 90, elapsed: frame * 2),
        greaterThan(glide(0, 90)),
      );
    });

    test('경계를 넘어도 짧은 쪽으로 돈다', () {
      // 350°에서 10°로 갈 때 거꾸로 돌면 340°를 지나며 화면이 한 바퀴 돈다.
      final next = glide(350, 10);
      expect(next, greaterThan(350));
      expect(next, lessThan(360));
    });

    test('목표에 서 있으면 그대로 있는다', () {
      expect(glide(90, 90), closeTo(90, 1e-9));
    });

    test('각속도가 상한을 넘지 않는다 — 도약이 램프가 되는 근거다', () {
      final perFrame = maxRate * frame.inMilliseconds / 1000;
      for (final step in steps(180)) {
        expect(step, lessThanOrEqualTo(perFrame + 1e-9));
      }
    });

    test('큰 도약은 한동안 **등속**으로 돈다', () {
      // 지수만 있으면 첫 프레임이 가장 크고 계속 줄어든다 — 그 모양이 화면에서
      // "확 돌고 멈춤"으로 보인다. 상한에 걸린 구간은 프레임마다 같아야 한다.
      final head = steps(90).take(10).toList();
      for (final step in head) {
        expect(step, closeTo(head.first, 1e-9));
      }
    });

    test('마지막 몇 도는 지수로 잦아들며 멈춘다', () {
      // 등속만 쓰면 도착 순간 속도가 뚝 끊겨 멈춤이 딱딱하다.
      final tail = steps(90, frames: 200).skip(120).toList();
      expect(tail.first, lessThan(maxRate * frame.inMilliseconds / 1000));
      expect(tail.last, lessThan(tail.first));
    });

    test('오래 쉬었다 와도 한 프레임에 상한 이상 돌지 않는다', () {
      // 상한이 시간에 비례하므로 5초가 밀리면 그만큼은 허용된다 — 다만 지수가
      // 계산한 값(=목표)보다 크게 돌지는 않는다.
      expect(glide(0, 90, elapsed: const Duration(seconds: 5)), closeTo(90, 1e-9));
    });

    test('상한을 낮추면 그 속도로만 돈다', () {
      expect(
        glide(0, 90, elapsed: frame, rate: 30),
        closeTo(30 * frame.inMilliseconds / 1000, 1e-9),
      );
    });
  });

  group('bearingGapDeg', () {
    test('0/360을 넘어 잰다 — 데드밴드와 같은 산수다', () {
      expect(bearingGapDeg(358, 2), closeTo(4, 1e-9));
      expect(bearingGapDeg(2, 358), closeTo(4, 1e-9));
    });

    test('반대편은 180이 상한이다', () {
      expect(bearingGapDeg(0, 190), closeTo(170, 1e-9));
    });
  });
}
