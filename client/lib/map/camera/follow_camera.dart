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

/// 화면이 지금 그리고 있는 각([shown])을 목표([target]) 쪽으로 [elapsed]만큼
/// 당긴 값. **명령을 띄엄띄엄 보내는 대신 매 프레임 이 값으로 카메라를 놓는다.**
///
/// 규칙 셋이 겹친다.
///
/// 1. **데드존**([deadZoneDeg]) — 남은 각이 이보다 작으면 아예 안 돈다. 실내
///    나침반은 서 있어도 몇 도씩 흔들리는데, 그걸 따라가면 지도가 계속 잘게
///    진동해 읽을 수가 없다. 목표를 계단으로 만들지 않고 **화면이 안 따라가는**
///    쪽으로 거르는 것이 요점이다 — 목표를 계단으로 만들면 그 계단이 그대로
///    회전에 보인다.
/// 2. **지수 평활**([timeConstant]) — 남은 각에 비례해 다가간다. 몸이 멈추면
///    남은 각이 줄면서 화면도 같이 멎는다. 관성이 없다.
/// 3. **각속도 상한**([maxRateDegPerSec]) — 안전판이다. 층 fit이나 하차 조준
///    뒤 팔로우가 돌아올 때처럼 각이 통째로 벌어진 경우에만 걸린다.
///
/// 근거와 버린 대안은 `docs/client/location-marker-glide.md`.
double glidedFollowBearingDeg({
  required double shown,
  required double target,
  required Duration elapsed,
  required Duration timeConstant,
  required double maxRateDegPerSec,
  required double deadZoneDeg,
}) {
  final delta = shortestDeltaDegrees(target - shown);
  if (delta.abs() < deadZoneDeg) return normalizeDegrees(shown);
  final eased = delta * glideFollowFactor(elapsed, timeConstant);
  final cap = maxRateDegPerSec * elapsed.inMicroseconds / 1000000;
  final step = eased.abs() <= cap ? eased : (eased.isNegative ? -cap : cap);
  return normalizeDegrees(shown + step);
}

/// 두 각의 최단 차(도, 절댓값). 데드밴드와 수렴 판정이 **같은 산수**를 보게
/// 한다 — 한쪽만 360을 못 넘으면 경계에서 서로 다른 답을 낸다.
double bearingGapDeg(double a, double b) =>
    shortestDeltaDegrees(a - b).abs();
