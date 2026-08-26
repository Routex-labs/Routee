/// 건물 안에서 출발하는 대중교통 여정의 **맨 앞 실내 구간**을 후보에 붙인다.
///
/// 왜 여기서는 총계를 함께 올리는지(`transit_walk_fill.dart`는 안 올린다)와 그때
/// 남는 근사는 `docs/client/indoor-leg-in-outdoor-journey.md`.
library;

import '../../models/route/transit_route.dart';

/// [itinerary] 앞에 실내 도보 한 구간을 붙이고 총계를 그만큼 올린다.
///
/// [seconds]가 0 이하면 붙일 것이 없으므로 원본을 그대로 돌려준다.
///
/// **총계를 올리는 것이 `fillTransitWalkLegs`와 다른 점이다.** 그쪽이 채우는
/// 야외 도보는 카카오 `totalTime`에 이미 들어 있어 더하면 이중 계산이지만,
/// 카카오는 우리 건물의 복도도 엘리베이터도 몰라 실내 구간은 총계에 **없다.**
///
/// **좌표는 담지 않는다.** 실내 선은 실내 경로 레이어가 층별로 그리므로
/// (`outdoor_map/parts/route_layers.dart`), 여기에 좌표를 넣으면 같은 복도에 선이
/// 두 겹 깔리고 카메라도 경로 전체를 잡을 때 그 점들을 한 번 더 센다.
TransitItinerary prependIndoorWalkLeg(
  TransitItinerary itinerary, {
  required int seconds,
  required double meters,
  required String exitName,
}) {
  if (seconds <= 0) return itinerary;
  final leg = TransitLeg(
    mode: TransitMode.walk,
    sectionTimeSeconds: seconds,
    distanceMeters: meters,
    points: const [],
    endName: exitName,
  );
  return TransitItinerary(
    totalTimeSeconds: itinerary.totalTimeSeconds + seconds,
    totalWalkTimeSeconds: itinerary.totalWalkTimeSeconds + seconds,
    totalDistanceMeters: itinerary.totalDistanceMeters + meters,
    transferCount: itinerary.transferCount,
    legs: [leg, ...itinerary.legs],
    fare: itinerary.fare,
  );
}

/// 앞에 붙여 둔 실내 구간을 **다시 떼어 낸다.** [prependIndoorWalkLeg]의 역이라
/// 총계도 함께 되돌린다 — 떼었다 붙이면 숫자가 정확히 제자리로 온다.
///
/// 고른 뒤 바깥 도보를 문 기준으로 다시 그릴 때 쓴다. 그때 `trimLeadingWalkLeg`가
/// 잘라야 하는 것은 **카카오가 준 첫 도보**인데, 실내 구간이 앞에 붙어 있으면
/// 그것이 대신 잘린다.
///
/// **좌표가 없는 도보 구간이 곧 우리 실내 구간이다.** 다른 도보는 전부 좌표를
/// 갖는다 — `fillTransitWalkLegs`는 실패해도 직선 두 점을 넣고, 카카오·TMAP은
/// 선을 준다. 좌표를 비우는 곳은 [prependIndoorWalkLeg] 하나뿐이다.
({({int seconds, double meters, String exitName})? lead, TransitItinerary rest})
takeIndoorWalkLead(TransitItinerary itinerary) {
  final legs = itinerary.legs;
  if (legs.isEmpty) return (lead: null, rest: itinerary);
  final first = legs.first;
  if (!first.mode.isWalk || first.points.isNotEmpty) {
    return (lead: null, rest: itinerary);
  }
  return (
    lead: (
      seconds: first.sectionTimeSeconds,
      meters: first.distanceMeters,
      exitName: first.endName ?? '',
    ),
    rest: TransitItinerary(
      totalTimeSeconds: itinerary.totalTimeSeconds - first.sectionTimeSeconds,
      totalWalkTimeSeconds:
          itinerary.totalWalkTimeSeconds - first.sectionTimeSeconds,
      totalDistanceMeters:
          itinerary.totalDistanceMeters - first.distanceMeters,
      transferCount: itinerary.transferCount,
      legs: legs.sublist(1),
      fare: itinerary.fare,
    ),
  );
}
