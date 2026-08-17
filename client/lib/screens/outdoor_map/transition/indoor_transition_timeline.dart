/// 실내 진입·이탈 **전환 연출**의 타임라인 — 진행률 하나를 각 요소의 값으로 옮긴다.
///
/// 위젯도 지도도 모른다. 그래서 미리보기 하네스와 실제 화면이 **같은 곡선**을 쓰고,
/// 곡선을 고치면 양쪽이 함께 바뀐다.
///
/// 구간의 근거, 흰 덮개의 위험, 진입과 이탈이 왜 대칭이 아닌지는
/// `docs/client/indoor-transition-choreography.md`.
library;

import 'dart:math' as math;

/// 진입 연출 길이.
const indoorEnterTransitionDuration = Duration(milliseconds: 1200);

/// 이탈 연출 길이. **진입보다 짧다** — 나가는 사람은 이미 문 밖으로 걸어 나간
/// 뒤라, 같은 시간을 쓰면 화면이 자기를 못 따라온다고 느낀다.
const indoorExitTransitionDuration = Duration(milliseconds: 900);

/// 전환의 방향.
enum IndoorTransitionDirection {
  /// 야외 → 실내. 문을 **당겨서** 연다.
  enter,

  /// 실내 → 야외. 문을 **바깥쪽으로 밀어서** 연다.
  exit,
}

/// 한 요소가 움직이는 구간. 두 값 모두 **전체 진행률**(0~1) 위의 위치다.
class TransitionSpan {
  const TransitionSpan(this.begin, this.end);

  final double begin;
  final double end;

  double rawAt(double t) {
    if (t <= begin) return 0;
    if (t >= end) return 1;
    return (t - begin) / (end - begin);
  }

  /// easeOutCubic을 먹인 값. 카메라 이징과 같은 곡선이라 요소들이 따로 놀지 않는다.
  double easedAt(double t) => 1 - math.pow(1 - rawAt(t), 3).toDouble();
}

/// 덮개가 덮이는 구간. **여기가 끝나는 순간이 화면을 갈아 끼우는 시점이다**
/// ([indoorTransitionSwapDelay]).
const indoorTransitionVeilIn = TransitionSpan(0.0, 0.14);

/// 문이 열리는 구간.
const indoorTransitionDoor = TransitionSpan(0.16, 0.62);

/// 문구가 보이는 구간(등장 → 유지 → 퇴장).
const indoorTransitionCaptionIn = TransitionSpan(0.20, 0.34);
const indoorTransitionCaptionOut = TransitionSpan(0.72, 0.94);

/// 덮개가 걷히는 구간. 시작점이 [indoorTransitionVeilIn]의 끝보다 한참 뒤라,
/// 그 사이에 일어난 화면 교체는 사용자에게 보이지 않는다.
const indoorTransitionVeilOut = TransitionSpan(0.80, 1.0);

/// 전환 한 프레임의 모든 값. 화면은 이걸 그대로 그리기만 한다.
class IndoorTransitionFrame {
  const IndoorTransitionFrame({
    required this.veilOpacity,
    required this.doorOpen,
    required this.captionOpacity,
  });

  /// 흰 덮개의 불투명도. 0이면 지도가 그대로 보인다.
  final double veilOpacity;

  /// 문이 열린 정도(0=닫힘, 1=활짝).
  final double doorOpen;

  /// 문구의 불투명도.
  final double captionOpacity;

  /// 지금 프레임에서 화면 교체가 사용자에게 보이는지. 덮개가 충분히 두껍지 않은
  /// 구간에서 지도를 갈아 끼우면 그 자체가 이 연출이 없애려는 깜빡임이 된다.
  bool get hidesSwap => veilOpacity >= 0.99;
}

/// [direction]에서 **덮개가 다 덮이기까지** 걸리는 시간.
///
/// 화면 상태를 바꾸는 쪽은 이만큼 기다린 뒤에 바꿔야 한다. 곧바로 바꾸면 덮개가
/// 아직 얇은 동안 도면과 마커가 갈리는 것이 보인다.
Duration indoorTransitionSwapDelay(IndoorTransitionDirection direction) {
  final total = indoorTransitionDuration(direction);
  return Duration(
    microseconds:
        (total.inMicroseconds * indoorTransitionVeilIn.end).round(),
  );
}

/// [direction]의 전체 연출 길이.
Duration indoorTransitionDuration(IndoorTransitionDirection direction) =>
    switch (direction) {
      IndoorTransitionDirection.enter => indoorEnterTransitionDuration,
      IndoorTransitionDirection.exit => indoorExitTransitionDuration,
    };

/// 진행률 [t](0~1)에서 그려야 할 한 프레임. 범위 밖 값은 잘라 낸다 —
/// 애니메이션 컨트롤러가 커브 때문에 아주 살짝 넘기는 일이 흔하다.
IndoorTransitionFrame indoorTransitionFrameAt(double t) {
  final p = t.clamp(0.0, 1.0).toDouble();
  final veil = (indoorTransitionVeilIn.rawAt(p) -
          indoorTransitionVeilOut.rawAt(p))
      .clamp(0.0, 1.0)
      .toDouble();
  final caption = (indoorTransitionCaptionIn.rawAt(p) -
          indoorTransitionCaptionOut.rawAt(p))
      .clamp(0.0, 1.0)
      .toDouble();
  return IndoorTransitionFrame(
    veilOpacity: veil,
    doorOpen: indoorTransitionDoor.easedAt(p),
    captionOpacity: caption,
  );
}
