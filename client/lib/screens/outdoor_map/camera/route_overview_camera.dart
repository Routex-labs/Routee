/// 카메라를 **야외 경로 전체로 물러서게 해도 되는지**, 안 되면 어디로 갈지.
///
/// 경로를 확정할 때·대중교통을 그릴 때·안내를 끌 때 세 자리가 같은 규칙을 쓴다.
/// 검증 기준은 `test/screens/outdoor_map/camera/route_overview_camera_test.dart`.
library;

/// 지금 야외 경로 전체를 담아도 되는가.
///
/// **도면을 편 상태에서는 안 된다.** 경로 전체를 담는 맞추기
/// ([animateCameraToPoints])에는 줌 하한이 없어서, 목적지가 몇백 m만 떨어져도
/// 배율이 실내 이탈 임계값(15.6) 아래로 내려간다. 대중교통이면 여정이 수 km라
/// 아예 확실하게 내려간다. 그러면 다음 카메라 정지에서 실내 오버레이가 접히고
/// ([indoorEntryTransitionForZoom]), 접힌 뒤로는 길찾기가 실내 갈래로 들어가지
/// 못해 **그 다음 길찾기부터 실내 구간이 통째로 안 그려진다.**
///
/// 지금 사용자는 건물 안이고, 봐야 할 것은 출구까지의 실내 구간이다. 바깥 구간은
/// 나간 뒤 그 자리에서 다시 그려지며 그때 카메라를 맞춘다.
bool canFitWholeRouteOverIndoor({required bool indoorEntered}) => !indoorEntered;

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
/// 전체를 담을 수 없으면([canFitWholeRouteOverIndoor]) 지금 층 실내 구간에
/// 맞춘다 — 그쪽 맞추기는 줌 하한이 걸려 있어 도면이 접히지 않는다. 담을 실내
/// 구간이 없으면 아무것도 하지 않는다: 맞출 대상 없이 배율만 되돌리면 방금
/// 보던 화면을 이유 없이 잃는다.
GuidanceStopCameraTarget guidanceStopCameraTarget({
  required bool indoorEntered,
  required bool hasIndoorSegment,
  required bool hasRouteToShow,
}) {
  if (!canFitWholeRouteOverIndoor(indoorEntered: indoorEntered)) {
    return hasIndoorSegment
        ? GuidanceStopCameraTarget.indoorSegment
        : GuidanceStopCameraTarget.keep;
  }
  return hasRouteToShow
      ? GuidanceStopCameraTarget.wholeRoute
      : GuidanceStopCameraTarget.keep;
}
