/// 안내 중 카메라가 사용자를 따라갈 때의 **각도 산수**.
///
/// `zoom_math.dart`와 같은 성격이다 — 언제 따라갈지·어떤 값으로 따라갈지 같은
/// 판단은 여기 없고(`screens/outdoor_map/`), "이 각과 저 각을 섞으면 몇 도인가",
/// "이번엔 돌려도 되는가"만 있다. 조정 값의 자리는 `outdoor_map_tuning.dart`이고,
/// 왜 프레임마다 보간하는지는 `docs/client/location-marker-glide.md`.
library;

import 'package:indoor_pdr_core/indoor_pdr_core.dart'
    show normalizeDegrees, shortestDeltaDegrees;

import '../../domain/guidance/location_marker_glide.dart' show glideFollowFactor;

/// [from]에서 [to]로 **0/360을 넘어 최단 경로로** 보간한 각(도).
///
/// 359°에서 1°로 갈 때 단순 보간은 358°를 거꾸로 돈다 — 화면이 한 바퀴 돈다.
/// 두 각의 차를 (-180, 180]로 접은 뒤 그 몫만큼만 간다.
///
/// [t]는 0~1로 잘린다. 결과는 항상 [0, 360)이다.
double lerpBearingDeg(double from, double to, double t) => normalizeDegrees(
  from + shortestDeltaDegrees(to - from) * t.clamp(0.0, 1.0),
);

/// 나침반 각([orientationHeadingDeg])을 기준으로, 걷는 동안에는 진행 방향
/// ([walkingHeadingDeg])쪽으로 [walkingPullWeight]만큼 끌어당긴 bearing.
///
/// **실내 나침반은 철구조와 에스컬레이터 모터에 흔들린다.** 걸을 때만은 이동
/// 벡터라는 독립된 기준이 생기므로 그쪽으로 당긴다. 다만 **갈아치우지는 않는다**
/// — walking heading은 폰을 쥔 자세 보정(walkOffset)이 섞인 값이라, 그것만 믿으면
/// 자세 추정이 틀린 순간 화면이 통째로 돌아간다.
///
/// 멈춰 있거나([walking]이 false) 진행 방향을 모르면 나침반 각을 그대로 쓴다 —
/// 서 있는 사람의 "이동 방향"은 아무 값도 아니다.
double blendedFollowBearingDeg({
  required double orientationHeadingDeg,
  required double? walkingHeadingDeg,
  required bool walking,
  required double walkingPullWeight,
}) {
  if (!walking || walkingHeadingDeg == null) {
    return normalizeDegrees(orientationHeadingDeg);
  }
  return lerpBearingDeg(
    orientationHeadingDeg,
    walkingHeadingDeg,
    walkingPullWeight,
  );
}

/// 이번 스냅샷에 카메라를 명령할 bearing. **null이면 이번엔 움직이지 않는다.**
///
/// 거르는 이유는 둘이다. [notBeforeMs]는 걸음마다 애니메이션을 쏘아 지도가 떠는
/// 것을 막고(최소 간격), 동시에 다른 카메라 주인이 도는 동안의 유예로도 쓴다 —
/// 둘 다 "이 시각 전에는 손대지 않는다"라 값 하나면 된다. 데드밴드([deadbandDeg])
/// 는 몇 도짜리 나침반 흔들림으로 화면이 돌지 않게 한다. 데드밴드에 걸리면 각을
/// **이전 값 그대로** 두고 위치만 따라가므로 [targetMoved]가 필요하다.
///
/// [lastBearingDeg]가 null이면 아직 한 번도 안 돌린 것이라 데드밴드를 건너뛴다.
double? nextFollowCameraBearingDeg({
  required int nowMs,
  required int notBeforeMs,
  required double? lastBearingDeg,
  required bool targetMoved,
  required double desiredBearingDeg,
  required double deadbandDeg,
}) {
  if (nowMs < notBeforeMs) return null;
  final desired = normalizeDegrees(desiredBearingDeg);
  if (lastBearingDeg == null) return desired;
  final held =
      shortestDeltaDegrees(desired - lastBearingDeg).abs() < deadbandDeg
      ? normalizeDegrees(lastBearingDeg)
      : desired;
  // 각도 흔들림도 데드밴드에 먹히고 위치도 그대로면 명령할 것이 없다. 서 있는
  // 동안 초당 몇 번씩 같은 자리로 animateCamera를 쏘지 않기 위한 갈래다.
  if (!targetMoved && held == normalizeDegrees(lastBearingDeg)) return null;
  return held;
}

/// 화면이 지금 그리고 있는 각([shown])을 목표([target]) 쪽으로 [elapsed]만큼
/// 당긴 값. **명령을 띄엄띄엄 보내는 대신 매 프레임 이 값으로 카메라를 놓는다.**
///
/// 두 규칙을 겹친다.
///
/// 1. 남은 각에 비례해 다가간다(지수 평활, [timeConstant]). 작은 보정이
///    부드럽게 **멈추는** 것은 이쪽 몫이다.
/// 2. 각속도를 [maxRateDegPerSec]로 **자른다**. 목표각은 초당 두어 번, 한 번에
///    수십 도씩 뛰어서 오므로(PDR 스냅샷 주기) 1번만 두면 도착 직후 300°/s로
///    후려치고 다음 목표까지 멈춰 선다 — 그것이 "뚝뚝 끊겨 돈다"의 정체다.
///    잘라 두면 그 도약이 등속 램프가 되어 다음 목표가 올 때까지 이어진다.
///
/// 그래서 큰 도약은 등속으로, 마지막 몇 도는 지수로 잦아들며 멈춘다. 목표보다
/// 늦게 도착하는 것은 **의도한 교환**이다 — 근거는
/// `docs/client/location-marker-glide.md`.
double glidedFollowBearingDeg({
  required double shown,
  required double target,
  required Duration elapsed,
  required Duration timeConstant,
  required double maxRateDegPerSec,
}) {
  final eased = shortestDeltaDegrees(target - shown) *
      glideFollowFactor(elapsed, timeConstant);
  final cap = maxRateDegPerSec * elapsed.inMicroseconds / 1000000;
  final step = eased.abs() <= cap ? eased : (eased.isNegative ? -cap : cap);
  return normalizeDegrees(shown + step);
}

/// 두 각의 최단 차(도, 절댓값). 데드밴드와 수렴 판정이 **같은 산수**를 보게
/// 한다 — 한쪽만 360을 못 넘으면 경계에서 서로 다른 답을 낸다.
double bearingGapDeg(double a, double b) =>
    shortestDeltaDegrees(a - b).abs();
