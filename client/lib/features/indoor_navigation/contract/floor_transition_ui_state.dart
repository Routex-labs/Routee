/// 층 전환 UI가 그리는 것 전부.
///
/// 판정기의 단계를 화면이 다시 해석하지 않게 하는 계약이다 — UI는 이 값을 문구와
/// 애니메이션으로만 바꾸고 임계값을 다시 계산하지 않는다.
///
/// 스크림은 **앱 셸의 최상위 Stack**이, 배너는 지도의 **안내 한 자리**가 그린다
/// (`GuidanceBanner`). 배너를 따로 띄우면 안내 위에 알약이 한 겹 더 겹친다.
library;

import 'dart:math' as math;

/// 스크림이 짙어지는/걷히는 시간.
///
/// **일부러 느리다.** 층 전환은 사용자가 알아채야 하는 사건이다. 빠른 페이드는
/// 지도가 "깜빡"한 것처럼 보여서, 화면이 바뀐 줄도 모르고 다른 층 도면을 읽는
/// 일이 생긴다. 천천히 덮였다가 천천히 걷히면 그 사이에 뭔가 일어났다는 것이
/// 눈에 남는다. 걷히는 쪽을 더 길게 둔 이유는, 그때 사용자가 이미 새 도면을
/// 보고 있어서 서두를 이유가 없기 때문이다.
const floorTransitionScrimFadeIn = Duration(milliseconds: _scrimFadeInMs);
const _scrimFadeInMs = 520;
const floorTransitionScrimFadeOut = Duration(milliseconds: 700);

/// 도착 층 사진이 미끄러져 들어오는 데 걸리는 시간. 시작은 덮개가 다 짙어진
/// 뒤([floorTransitionScrimFadeIn])다.
///
/// **자동 넘김이 이만큼 늦게 시작해야 한다.** 안 그러면 첫 장만 등장에 먹힌
/// 시간을 빼고 세어져 다른 장보다 짧게 지나간다 — 실기기에서 "첫 장을 아예 안
/// 보여 준다"로 보였다(2026-08-22).
const floorPhotoEntrance = Duration(milliseconds: _photoEntranceMs);
const _photoEntranceMs = 360;

/// 사진이 완전히 자리 잡는 시각(덮개가 짙어지기 시작한 순간 기준).
/// `Duration`끼리 더하는 식은 const가 안 돼서 밀리초로 더한다.
const floorPhotoSettled = Duration(
  milliseconds: _scrimFadeInMs + _photoEntranceMs,
);

/// 도착 층 사진 한 장이 머무는 시간.
///
/// 덮개를 붙잡는 시간과 사진이 넘어가는 주기가 **같은 값에서 나와야 한다** —
/// 따로 두면 마지막 장이 뜨자마자 덮개가 걷히거나, 다 넘긴 뒤로 빈 시간이 남는다.
const floorPhotoDwell = Duration(milliseconds: 2200);

/// 사진 [photoCount]장을 덮개가 떠 있는 동안 **모두** 보여 주려면 한 장이
/// 머무는 시간.
///
/// [floorTransitionScrimHold]가 상한에 걸리는 층(다섯 장)에서 [floorPhotoDwell]을
/// 그대로 쓰면 마지막 장이 뜨기 전에 덮개가 걷힌다 — 실기기에서 "마지막 사진이
/// 안 뜬다"로 보였다(2026-08-22). 남은 시간을 장수로 나눠 **모든 장이 같은
/// 시간**을 받게 한다. 마지막 장의 몫이 끝나는 순간이 곧 덮개가 걷히기 시작하는
/// 순간이다.
Duration floorPhotoDwellFor(int photoCount) {
  if (photoCount <= 1) return floorPhotoDwell;
  final showing =
      floorTransitionScrimHold(photoCount).inMilliseconds -
      floorPhotoSettled.inMilliseconds;
  return Duration(milliseconds: showing ~/ photoCount);
}

/// 도면을 갈아 끼운 뒤 덮개를 그대로 두는 시간. [photoCount]는 도착 층 사진 장수.
///
/// **장수가 시간을 정한다.** 덮개가 하는 일이 둘이라 그렇다 — 도면이 갈리는 것을
/// 가리는 일(3.5초면 충분하다)과 도착 층을 보여 주는 일. 한 장뿐인 층에서 여러
/// 장 기준으로 붙잡으면 볼 것이 없는데 화면만 잡혀 있고, 반대로 여러 장인 층을
/// 3.5초로 두면 첫 장을 겨우 보고 걷힌다.
///
/// 상한이 있다. 실제 탑승은 20~35초라 시간 자체는 남지만, **하차까지 덮으면 안
/// 된다** — 내리기 전에 새 층 도면과 다음 경로를 볼 시간이 있어야 한다. 상한에
/// 걸린 층(사진 다섯 장)은 마지막 장이 넘겨야 보이는 덤이 된다.
Duration floorTransitionScrimHold(int photoCount) {
  final extra = (photoCount - 1).clamp(0, 10);
  final ms =
      _scrimHoldBase.inMilliseconds + extra * floorPhotoDwell.inMilliseconds;
  return Duration(milliseconds: math.min(ms, _scrimHoldCap.inMilliseconds));
}

/// 사진이 없거나 한 장일 때. 도면 교체를 가리는 데 필요한 최소치다.
const _scrimHoldBase = Duration(milliseconds: 3500);

/// 사진이 아무리 많아도 여기서 멈춘다.
const _scrimHoldCap = Duration(milliseconds: 9000);

/// 층 전환 UI 상태가 바뀔 때 상위 셸에 알리는 계약.
///
/// [banner]가 null이면 배너를 감춘다. [scrimOpacity]는 도면을 갈아 끼우는
/// 구간에서 1이 되며, 그동안 뒤쪽 입력을 막는다.
///
/// 탑승 진행률은 넘기지 않는다. 실제 진행(기압 구동)은 지도 마커가 보여 주고,
/// 덮개 카드의 점은 자체 시계로 한 번의 전체 스위프를 재생한다 — 실측에서
/// 실제 진행률을 카드에 그대로 얹으니 덮개가 보이는 몇 초 동안 점이 거의
/// 움직이지 않아 멈춘 것으로 읽혔다(2026-08-13).
typedef FloorTransitionUiChanged =
    void Function(FloorTransitionUiState? banner, double scrimOpacity);

/// 사용자에게 보이는 층 전환 진행 단계.
///
/// **완료 단계가 없다.** 예전에는 하차 확정 뒤 "N층으로 이동했습니다"를 몇 초 더
/// 띄웠는데, 그때 화면은 이미 새 층 도면과 새 경로를 그리고 있어서 배너가 방금
/// 끝난 일을 한 번 더 말할 뿐이었다. 끝난 일은 화면이 이미 말한다.
enum FloorTransitionStage {
  /// 탑승점에 접근했다. 배너만 뜨고 지도·걸음은 그대로다.
  boarding,

  /// 실제로 오르내리는 중이다. 걸음 적용은 멈췄고 지도는 아직 출발 층이다.
  moving,

  /// 목적 층 도면으로 바뀌었고 하차를 기다린다.
  swapping,
}

class FloorTransitionUiState {
  const FloorTransitionUiState({
    required this.stage,
    required this.fromFloorLabel,
    required this.toFloorLabel,
    required this.goingUp,
  });

  final FloorTransitionStage stage;
  final String fromFloorLabel;
  final String toFloorLabel;
  final bool goingUp;

  /// 안내 배너의 큰 줄. 남은거리가 서는 자리라 **가는 곳**을 적는다.
  String get headline => '$fromFloorLabel → $toFloorLabel';

  /// 지금 사용자에게 일어나는 일. 안내 배너의 작은 줄과 스크림 캡션이 **같은
  /// 문장**을 쓴다 — 한 사건을 두 표면이 다르게 부르면 화면 안에서 말이 갈린다.
  ///
  /// 도면을 갈아 끼우는 구간(`swapping`)도 "에스컬레이터로 이동 중"이다. 지도가
  /// 전환된다는 것은 앱의 사정이고, 그 사람에게 일어나는 일은 층 이동 하나다.
  ///
  /// 층 라벨은 넣지 않는다 — 배너는 [headline]이, 스크림은 큰 글씨가 따로 그려서
  /// 넣으면 같은 글자가 한 카드에 두 번 나온다.
  String get detail => switch (stage) {
    FloorTransitionStage.boarding => '에스컬레이터 탑승을 감지했습니다',
    FloorTransitionStage.moving ||
    FloorTransitionStage.swapping => '에스컬레이터로 이동 중',
  };

  @override
  bool operator ==(Object other) =>
      other is FloorTransitionUiState &&
      other.stage == stage &&
      other.fromFloorLabel == fromFloorLabel &&
      other.toFloorLabel == toFloorLabel &&
      other.goingUp == goingUp;

  @override
  int get hashCode => Object.hash(stage, fromFloorLabel, toFloorLabel, goingUp);
}
