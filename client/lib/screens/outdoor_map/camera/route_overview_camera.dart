/// 카메라를 **야외 경로 전체로 물러서게** 할 때 실내 도면이 어떻게 되는지.
///
/// 개요를 그리는 자리(경로 확정·대중교통 그리기)와 그 축소를 받아 도면을 접을지
/// 정하는 자리(카메라 정지), 그리고 안내를 끄는 자리가 이 파일의 규칙을 쓴다.
/// 검증 기준은 `test/screens/outdoor_map/camera/route_overview_camera_test.dart`.
library;

/// 개요 때문에 축소한 카메라가 **실내 상태를 그대로 두어야** 하는가.
///
/// 경로 전체를 담는 맞추기([animateCameraToPoints])에는 줌 하한이 없어, 목적지가
/// 몇백 m만 떨어져도 배율이 실내 이탈 임계값 아래로 내려간다. 붙드는 것은 눈에
/// 보이는 도면이 아니라 실내 상태다 — 꺼지면 길찾기가 실내 갈래로 못 들어가
/// **실내 구간이 계산조차 되지 않는다.**
///
/// [overviewHold]는 이 축소를 개요가 만들었는가, [hasRouteToShow]는 붙들 이유가
/// 아직 있는가다. [indoorPositionLive]는 둘을 **웃돈다** — 실내 위치가 살아 있으면
/// 이 사람은 건물 안이고, 접는 순간 화면과 판정이 어긋난다.
///
/// 실측과 버린 규칙은 `docs/client/indoor-leg-in-outdoor-journey.md`의
/// 「축소해도 접지 않는다」.
bool zoomOutKeepsIndoor({
  required bool overviewHold,
  required bool hasRouteToShow,
  required bool indoorPositionLive,
}) => indoorPositionLive || (overviewHold && hasRouteToShow);

/// 안내를 끈 순간 카메라가 갈 곳.
enum GuidanceStopCameraTarget {
  /// 야외 경로(또는 대중교통 여정) 전체를 담는다.
  wholeRoute,

  /// 지금 층 실내 구간만 담는다.
  indoorSegment,

  /// 카메라를 건드리지 않는다.
  keep,
}

/// 안내를 끄고 계획 화면으로 돌아갈 때 어디에 맞출지 정한다.
///
/// **건물 안에서 껐으면 지금 층 실내 구간에 맞춘다.** 여기서 여정 전체로
/// 물러서면 방금까지 따라가던 실내 선이 배율에 지워져(도면 페이드), 되돌아온
/// 계획 화면이 정작 사용자가 서 있는 자리를 안 보여 준다. 개요를 그리는 자리와
/// 갈리는 것은 그 때문이다 — 그쪽은 아직 안 가 본 길을 보여 주는 화면이고,
/// 이쪽은 가던 길을 멈춘 화면이다. 바깥 구간은 나간 뒤 그 자리에서 다시
/// 그려지며 그때 카메라를 맞춘다.
///
/// 담을 실내 구간이 없으면 아무것도 하지 않는다: 맞출 대상 없이 배율만
/// 되돌리면 방금 보던 화면을 이유 없이 잃는다.
GuidanceStopCameraTarget guidanceStopCameraTarget({
  required bool indoorEntered,
  required bool hasIndoorSegment,
  required bool hasRouteToShow,
}) {
  if (indoorEntered) {
    return hasIndoorSegment
        ? GuidanceStopCameraTarget.indoorSegment
        : GuidanceStopCameraTarget.keep;
  }
  return hasRouteToShow
      ? GuidanceStopCameraTarget.wholeRoute
      : GuidanceStopCameraTarget.keep;
}
