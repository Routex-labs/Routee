import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/map/camera/follow_camera.dart';

/// 팔로우 카메라 각도 산수의 검증 기준.
///
/// 화면 코드에 묻으면 확인할 방법이 없어 따로 뺀 계산이다. 여기서 지키는 것은
/// 넷 — 0/360을 넘는 최단 경로, 나침반↔걷는 방향 혼합, 프레임 보간, 데드존.
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

  group('glidedFollowBearingDeg', () {
    const tau = Duration(milliseconds: 120);
    const maxRate = 360.0;
    const deadZone = 5.0;
    const frame = Duration(milliseconds: 16);

    double glide(
      double shown,
      double target, {
      Duration elapsed = frame,
      double rate = maxRate,
      double deadZoneDeg = 0,
    }) => glidedFollowBearingDeg(
      shown: shown,
      target: target,
      elapsed: elapsed,
      timeConstant: tau,
      maxRateDegPerSec: rate,
      deadZoneDeg: deadZoneDeg,
    );

    test('한 프레임에 다 돌지 않는다', () {
      final next = glide(0, 90);
      expect(next, greaterThan(0));
      expect(next, lessThan(90));
    });

    test('프레임이 길수록 더 많이 돈다', () {
      expect(glide(0, 90, elapsed: frame * 2), greaterThan(glide(0, 90)));
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

    test('데드존 안의 흔들림에는 화면이 꿈쩍도 안 한다', () {
      // 서 있어도 나침반은 몇 도씩 흔들린다. 그걸 따라가면 지도가 잘게 진동한다.
      expect(glide(90, 93, deadZoneDeg: deadZone), 90);
      expect(glide(90, 87, deadZoneDeg: deadZone), 90);
    });

    test('데드존을 벗어나면 이어서 따라간다 — 목표는 계단이 아니다', () {
      // 데드존을 목표각에 걸면 목표가 5°씩 뛰고 그 계단이 회전에 그대로 보인다.
      // 여기서는 목표가 연속이고, 화면이 따라갈지만 데드존이 가른다.
      var shown = 90.0;
      for (var target = 95.0; target < 120; target += 0.5) {
        final next = glide(shown, target, deadZoneDeg: deadZone);
        expect(next, greaterThanOrEqualTo(shown));
        shown = next;
      }
      expect(shown, greaterThan(100));
    });

    test('목표가 멈추면 화면도 멎는다 — 관성이 남지 않는다', () {
      // 상한으로 등속을 만들던 때는 몸이 멈춘 뒤에도 밀린 각만큼 계속 돌았다.
      var shown = 0.0;
      final steps = <double>[];
      for (var i = 0; i < 40; i++) {
        final next = glide(shown, 30);
        steps.add(bearingGapDeg(next, shown));
        shown = next;
      }
      // 프레임마다 회전량이 줄어든다 = 목표에 가까워질수록 느려진다.
      expect(steps.last, lessThan(steps.first));
      expect(steps.last, lessThan(0.05));
      expect(shown, closeTo(30, 1));
    });

    test('각이 통째로 벌어져도 상한을 넘지는 않는다', () {
      // 층 fit이나 하차 조준 뒤 팔로우가 돌아오는 경우의 안전판이다.
      final perFrame = maxRate * frame.inMilliseconds / 1000;
      expect(
        bearingGapDeg(glide(0, 180), 0),
        lessThanOrEqualTo(perFrame + 1e-9),
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
