/// 다층 안내에서 현재 층부터 목적지까지 남은 거리와 ETA 비용을 계산한다.
///
/// 층을 바꿀 때 PDR 보정 세션은 새로 시작하므로 현재 세그먼트의 진행률은 잠시
/// 비어 있다. 이때 경로 전체 합계를 그대로 쓰면 이미 지난 층의 거리까지 다시
/// 나타난다. 현재 층보다 앞선 세그먼트는 제외하고, 현재·이후 세그먼트만 합산해
/// 한 여정의 남은 값이 끊기지 않게 한다.
library;

import '../../models/building/building_graph.dart';

typedef MultiFloorEta = ({double distanceM, double costM});

MultiFloorEta remainingMultiFloorEta({
  required MultiFloorRoute route,
  required String? activeFloor,
  double? activeSegmentRemainingM,
}) {
  final activeIndex = activeFloor == null
      ? -1
      : route.segments.indexWhere(
          (segment) => segment.floorName == activeFloor,
        );
  // 수동으로 다른 층을 보고 있거나 경로 갱신 중에는 추측해서 빼지 않는다.
  if (activeIndex < 0) {
    return (distanceM: route.totalDistanceMeters, costM: route.totalCostMeters);
  }

  var distanceM = 0.0;
  var costM = 0.0;
  for (var index = activeIndex; index < route.segments.length; index++) {
    final segment = route.segments[index];
    final walkingM = index == activeIndex
        ? (activeSegmentRemainingM ?? segment.route.distanceMeters).clamp(
            0.0,
            segment.route.distanceMeters,
          )
        : segment.route.distanceMeters;
    // 층 내부 보행은 거리와 보행 등가 비용이 같다. 수직 이동은 두 값을 분리해
    // 거리 카드에는 실제 이동 거리, 시간에는 대기·탑승 비용을 반영한다.
    distanceM += walkingM + segment.transferDistanceMeters;
    costM += walkingM + segment.transferCostMeters;
  }
  return (distanceM: distanceM, costM: costM);
}
