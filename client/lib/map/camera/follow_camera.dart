/// 안내 중 카메라가 사용자를 따라갈 때의 **각도 산수**.
///
/// `zoom_math.dart`와 같은 성격이다 — 언제 따라갈지·어떤 값으로 따라갈지 같은
/// 판단은 여기 없고(`screens/outdoor_map/`), "이 각과 저 각을 섞으면 몇 도인가",
/// "이번엔 돌려도 되는가"만 있다. 조정 값의 자리는 `outdoor_map_tuning.dart`.
library;

import 'package:indoor_pdr_core/indoor_pdr_core.dart'
    show normalizeDegrees, shortestDeltaDegrees;

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
