/// 건물 **안에서 밖으로 나가는 구간**의 거리·비용을 한 번에 재 둔다.
///
/// 나가는 문은 목적지마다 다른데([nearestEntranceByTotalJourney]) 목적지가 여럿인
/// 화면이 있다 — 근거와 설계는 `docs/client/indoor-leg-in-outdoor-journey.md`.
library;

import 'package:latlong2/latlong.dart';

import 'building_entrances.dart';

/// 지금 서 있는 곳에서 문 하나까지의 실내 구간.
///
/// 거리와 비용을 함께 든다. 화면에 적는 "몇 m"는 실제 이동 거리이고, "몇 분"은
/// 엘리베이터 대기·탑승까지 담은 비용이다 — 한 값으로 겸하면 남은거리가 대기
/// 시간만큼 부풀어 보인다(`multi_floor_eta.dart`와 같은 규칙).
typedef IndoorExitLeg = ({
  BuildingEntrance entrance,
  double distanceM,
  double costM,
});

/// 실내 그래프로 **실제 닿는** 문들과 그 구간. 못 닿는 문은 애초에 안 담는다.
///
/// 대중교통 후보 목록은 후보마다 처음 타는 정류장이 달라 나가는 문도 갈릴 수
/// 있다. 후보마다 그래프를 다시 훑으면 같은 다익스트라를 후보 수만큼 돌리게
/// 되므로, **도달성은 한 번만 재고 문 고르기만 되풀이한다** — `dijkstra.dart`의
/// [reachableFrom]이 목록 화면을 위해 조기 종료를 뺀 것과 같은 이유다.
class IndoorExitReach {
  const IndoorExitReach(this.legs);

  final List<IndoorExitLeg> legs;

  bool get isEmpty => legs.isEmpty;

  /// [target]으로 나갈 때 고르는 문과 그 실내 구간. 닿는 문이 없으면 null.
  ///
  /// 문을 고르는 규칙은 [nearestEntranceByTotalJourney] **하나뿐이다.** 여기서
  /// 다시 구현하면 목록에 적힌 시간과 실제로 그려지는 실내 선이 서로 다른 문을
  /// 향하게 된다.
  IndoorExitLeg? towards(LatLng target) {
    final entrance = nearestEntranceByTotalJourney([
      for (final leg in legs)
        (entrance: leg.entrance, indoorDistanceM: leg.distanceM),
    ], target);
    if (entrance == null) return null;
    for (final leg in legs) {
      if (leg.entrance.id == entrance.id) return leg;
    }
    return null;
  }
}
