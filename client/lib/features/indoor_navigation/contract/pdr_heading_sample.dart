/// 화면 회전용 **방향 한 건**. native motion 주기(≈33Hz)로 흐른다.
///
/// 스냅샷과 따로 두는 이유는 [PdrHeadingSample] 주석에 있다. 위치·판정에는
/// 쓰지 않는다 — 그쪽의 단일 출처는 스냅샷이다.
library;

/// 카메라와 마커 삼각형이 도는 데만 쓰는 방향 두 개(도, 세션 좌표계).
///
/// **스냅샷([IndoorNavigationView.snapshots])과 나눠 둔 이유가 전부다.** 스냅샷은
/// 걸음·궤적·품질을 통째로 실어 나르므로 소비자가 화면을 다시 그리게 되고, 그래서
/// 초당 두어 번으로 눌러 놨다. 그 주기로 카메라를 돌리면 한 번에 수십 도가
/// 도착해 "확 돌고 멈춤"이 초당 두세 번 반복된다.
///
/// 이 신호는 double 둘뿐이라 그 비용 없이 촘촘하게 흐른다. 근거와 실측은
/// `docs/client/location-marker-glide.md`.
class PdrHeadingSample {
  const PdrHeadingSample({
    required this.orientationDeg,
    required this.walkingDeg,
    required this.converged,
  });

  /// 몸이 바라보는 방향(smoothing된 fused heading).
  final double orientationDeg;

  /// 걸어가고 있는 방향. 자세 보정(walkOffset)이 섞여 있어 카메라는 이쪽으로
  /// **끌어당기기만** 한다([blendedFollowBearingDeg]).
  final double walkingDeg;

  /// 방향이 아직 자리를 못 잡았으면 false. 그때는 삼각형도 카메라도 돌리지
  /// 않는다 — 모르는 것을 아는 척하게 된다.
  final bool converged;
}
