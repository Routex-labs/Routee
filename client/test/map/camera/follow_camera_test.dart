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
    double glide(double shown, double target, {int ms = 32}) =>
        glidedFollowBearingDeg(
          shown: shown,
          target: target,
          elapsed: Duration(milliseconds: ms),
          timeConstant: const Duration(milliseconds: 240),
        );

    test('한 프레임에 다 돌지 않는다 — 이 지연이 곧 부드러움이다', () {
      final next = glide(0, 90);
      expect(next, greaterThan(0));
      expect(next, lessThan(90));
    });

    test('프레임이 길수록 더 많이 돈다', () {
      expect(glide(0, 90, ms: 64), greaterThan(glide(0, 90, ms: 32)));
    });

    test('오래 쉬었다 오면 한 번에 목표까지 붙는다', () {
      expect(glide(0, 90, ms: 5000), closeTo(90, 0.1));
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

    test('시정수가 0이면 보간하지 않는다', () {
      expect(
        glidedFollowBearingDeg(
          shown: 0,
          target: 90,
          elapsed: const Duration(milliseconds: 32),
          timeConstant: Duration.zero,
        ),
        closeTo(90, 1e-9),
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
