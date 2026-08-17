import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/screens/outdoor_map/transition/indoor_transition_timeline.dart';

/// 연출이 예쁜지는 눈으로 볼 일이고(`lib/indoor_transition_preview_main.dart`),
/// **깨지면 안 되는 관계**는 여기서 끝난다.

/// 진행률을 촘촘히 훑는다. 덮개가 얇아지는 구간은 몇 프레임뿐이라 성긴 표본으로는
/// 못 잡는다.
Iterable<double> _sweep() sync* {
  for (var i = 0; i <= 200; i++) {
    yield i / 200;
  }
}

void main() {
  group('덮개가 화면 교체를 가린다', () {
    // 이 그룹이 이 연출의 존재 이유다. 교체가 보이는 구간이 남으면 연출을
    // 얹고도 깜빡임이 그대로 남는다.
    test('교체 시점에는 덮개가 완전히 덮여 있다', () {
      for (final direction in IndoorTransitionDirection.values) {
        final total = indoorTransitionDuration(direction);
        final delay = indoorTransitionSwapDelay(direction);
        final t = delay.inMicroseconds / total.inMicroseconds;
        final frame = indoorTransitionFrameAt(t);
        expect(
          frame.hidesSwap,
          isTrue,
          reason: '$direction: 교체 시점 t=$t에서 덮개가 얇다',
        );
      }
    });

    test('덮개가 걷히기 시작하는 시점은 교체보다 뒤다', () {
      // 순서가 뒤집히면 교체가 걷히는 덮개 사이로 보인다.
      expect(
        indoorTransitionVeilOut.begin,
        greaterThan(indoorTransitionVeilIn.end),
      );
    });

    test('문이 다 열린 뒤에 덮개가 걷힌다', () {
      // 열리는 중에 걷히면 문이 사라지면서 열리는 것으로 보인다.
      expect(
        indoorTransitionVeilOut.begin,
        greaterThanOrEqualTo(indoorTransitionDoor.end),
      );
    });
  });

  group('양 끝은 아무것도 덮지 않는다', () {
    test('t=0과 t=1에서 덮개가 없다', () {
      // 0에서 남아 있으면 연출 전에 화면이 하얗게 번쩍이고, 1에서 남아 있으면
      // 덮개가 걷히지 않은 채로 굳는다.
      for (final t in [0.0, 1.0]) {
        final frame = indoorTransitionFrameAt(t);
        expect(frame.veilOpacity, 0, reason: 't=$t');
        expect(frame.captionOpacity, 0, reason: 't=$t');
      }
    });

    test('문은 끝에서 활짝 열려 있다', () {
      expect(indoorTransitionFrameAt(1).doorOpen, 1);
      expect(indoorTransitionFrameAt(0).doorOpen, 0);
    });
  });

  group('값의 범위', () {
    test('세 값 모두 0~1을 벗어나지 않는다', () {
      // 덮개와 문구는 두 구간을 뺀 값이라, 구간이 겹치면 음수가 나온다.
      for (final t in _sweep()) {
        final frame = indoorTransitionFrameAt(t);
        expect(frame.veilOpacity, inInclusiveRange(0, 1), reason: 't=$t');
        expect(frame.doorOpen, inInclusiveRange(0, 1), reason: 't=$t');
        expect(frame.captionOpacity, inInclusiveRange(0, 1), reason: 't=$t');
      }
    });

    test('범위를 벗어난 진행률은 잘라 낸다', () {
      // 애니메이션 커브가 1을 아주 살짝 넘기는 일이 흔하다.
      expect(indoorTransitionFrameAt(1.02).doorOpen, 1);
      expect(indoorTransitionFrameAt(-0.02).doorOpen, 0);
      expect(indoorTransitionFrameAt(-0.02).veilOpacity, 0);
    });
  });

  group('두 방향의 길이', () {
    test('이탈이 진입보다 짧다', () {
      // 나가는 사람은 이미 문 밖이라, 같은 시간을 쓰면 화면이 굼떠 보인다.
      expect(
        indoorExitTransitionDuration,
        lessThan(indoorEnterTransitionDuration),
      );
    });

    test('교체 지연은 방향마다 전체 길이에 비례한다', () {
      for (final direction in IndoorTransitionDirection.values) {
        final total = indoorTransitionDuration(direction);
        expect(
          indoorTransitionSwapDelay(direction).inMicroseconds,
          closeTo(total.inMicroseconds * indoorTransitionVeilIn.end, 2),
          reason: '$direction',
        );
      }
    });
  });
}
