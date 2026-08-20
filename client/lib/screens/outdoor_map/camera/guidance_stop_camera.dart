/// 안내를 끄고 **계획 화면으로 되돌아갈 때** 카메라를 무엇에 맞출지 정하는 정책.
///
/// 판정만 뗀 이유는 이 결정이 지도 컨트롤러 없이는 한 줄도 시험할 수 없어서다.
/// 검증 기준은 `test/screens/outdoor_map/camera/guidance_stop_camera_test.dart`.
library;

/// 안내를 끈 순간 카메라가 갈 곳.
enum GuidanceStopCameraTarget {
  /// 야외 경로(또는 대중교통 여정) 전체를 담는다.
  wholeRoute,

  /// 지금 층 실내 구간만 담는다.
  indoorSegment,

  /// 카메라를 건드리지 않는다.
  keep,
}

/// 어디에 맞출지 정한다.
///
/// **도면을 편 상태에서는 야외 경로 전체로 물러서지 않는다.** 경로 전체를 담는
/// 맞추기([animateCameraToPoints])에는 줌 하한이 없어서, 목적지가 몇백 m만 떨어져도
/// 배율이 이탈 임계값(15.6) 아래로 내려간다. 그러면 다음 카메라 정지에서 실내
/// 오버레이가 접히고([indoorEntryTransitionForZoom]), 접힌 뒤로는 길찾기가 실내
/// 갈래로 가지 못해 **그 다음 길찾기부터 실내 구간이 통째로 안 그려진다.**
/// 같은 이유로 새 야외 구간을 확정하는 자리도 이미 도면 유무로 갈린다
/// (`parts/route.dart`의 `_applyRoute`).
///
/// 대신 지금 층 실내 구간에 맞춘다 — 그쪽 맞추기는 하한이 걸려 있어 도면이
/// 접히지 않고, 건물 안에 선 사람이 봐야 하는 것도 출구까지의 실내 구간이다.
/// 담을 실내 구간이 없으면 아무것도 하지 않는다: 맞출 대상 없이 배율만 되돌리면
/// 방금 보던 화면을 이유 없이 잃는다.
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
