/// 같은 이름으로 묶인 매장 여럿 중 **현재 위치에서 가장 가까운 하나**를 고른다.
///
/// **여기서 경로를 새로 계산하지 않는다.** 화면은 이미 `reachableFrom`을 한 번 돌려
/// 전 노드 결과를 들고 있고(`SearchPanel.reachByNodeId`), 이 함수는 그 맵을 조회만
/// 한다. 결과 목록의 거리순 정렬(`search_result_order.dart`)과 같은 근거다.
///
/// 설계 근거와 검증 기준은 `docs/client/search-result-list-ux.md` O절이 단일 출처다.
library;

import '../../models/place/store_index_entry.dart';
import '../route/dijkstra.dart';
import '../search/store_suggestions.dart';

/// 고른 대표와 그 매장까지의 도달 정보.
///
/// [reach]가 null이면 **거리를 모른다**는 뜻이고, 그때 [store]는 입력 순서 첫 번째다
/// — 지금까지의 동작 그대로다. 화면은 이 null을 보고 거리 줄을 생략한다.
typedef NearestStore = ({StoreIndexEntry store, NodeReach? reach});

/// [stores] 중 보행 거리가 가장 짧은 매장을 고른다. 빈 목록은 호출부의 버그다.
///
/// **거리를 모를 때** — 거리 정보 자체가 없으면 [currentFloorId]와 같은 층을,
/// 그마저 없으면 입력 첫 번째를 대표로 세운다. [currentFloorId]는 내부 id와 화면
/// 라벨(`B2`) 둘 다 받는다. 일부만 도달 가능하면 **그중
/// 최근접**을 고른다(도달 못 하는 곳을 "가장 가깝다"고 적지 않는다).
///
/// **묶인 개수는 손대지 않는다** — 19곳 중 3곳만 거리를 안다고 `등 3곳`이 되면
/// 없는 사실을 만드는 것이다.
///
/// 동점은 **엄격한 부등호로만 갱신**해 입력 순서로 깬다(정렬을 쓰지 않는다).
NearestStore nearestByWalkingDistance({
  required List<StoreIndexEntry> stores,
  required Map<String, NodeReach>? reachByNodeId,
  String? currentFloorId,
}) {
  assert(stores.isNotEmpty, '후보 한 줄은 최소 한 매장에서 나온다');
  // 거리를 모를 때 쓸 대표. 지금 보고 있는 층에 있으면 그것, 없으면 입력 첫 번째다.
  final fallback = _onCurrentFloor(stores, currentFloorId) ?? stores.first;
  final reach = reachByNodeId;
  if (reach == null || reach.isEmpty) return (store: fallback, reach: null);

  StoreIndexEntry? best;
  NodeReach? bestReach;
  for (final store in stores) {
    final nodeId = store.entranceNodeId;
    if (nodeId == null) continue;
    final found = reach[nodeId];
    if (found == null) continue;
    // 엄격한 `<`라서 동점이면 갱신하지 않는다 — 위 「결정성」 참고.
    if (bestReach == null || found.distanceM < bestReach.distanceM) {
      best = store;
      bestReach = found;
    }
  }

  if (best == null) return (store: fallback, reach: null);
  return (store: best, reach: bestReach);
}


/// [currentFloorId] 층에 있는 첫 매장. 없으면 null.
///
/// **내부 id(`FL-…`)와 화면 라벨(`B2`)을 모두 받는다.** 부르는 쪽이 둘 다 넘긴다 —
/// 저장소도 같은 규칙이다([DestinationRepository]). 한쪽만 대조하던 동안 화면이
/// 넘긴 라벨이 한 번도 안 맞아서, 거리를 모르는 자리(위치 미지정)의 `화장실`이
/// 늘 색인 첫 줄인 B6로 떨어졌다 — B2에 서 있어도 그랬다.
///
/// 같은 층이 여럿이어도 첫 번째로 족하다 — 어느 쪽이 더 가까운지는 거리를 알아야
/// 정할 수 있는 값이고, 이 함수가 불리는 자리는 그 거리를 모르는 자리다.
StoreIndexEntry? _onCurrentFloor(
  List<StoreIndexEntry> stores,
  String? currentFloorId,
) {
  if (currentFloorId == null) return null;
  for (final store in stores) {
    if (store.floorId == currentFloorId || store.floorName == currentFloorId) {
      return store;
    }
  }
  return null;
}


/// 이 질의가 **같은 이름이 층마다 있는 시설**을 가리키면, 가장 가까운 곳의 층을
/// 돌려준다. 아니면 null.
///
/// 시설인지는 **사전 없이 데이터에서 유도한다** — 온디바이스 후보의 최상위 그룹에
/// 같은 이름 매장이 둘 이상이면 그게 곧 "층마다 있는 시설"이다. 추가 요청은 없다.
///
/// null을 돌려주는 경우 넷: 후보가 없을 때, 최상위 후보가 교정일 때, 그룹이 아닐
/// 때(=매장이라 건물 전체를 본다), 거리를 모를 때.
///
/// 설계 근거와 검증 기준은 `docs/client/search-result-list-ux.md` U절이 단일 출처다.
String? nearestFloorForGroupedFacility({
  required List<StoreSuggestion> suggestions,
  required Map<String, NodeReach>? reachByNodeId,
}) {
  if (suggestions.isEmpty) return null;
  final top = suggestions.first;
  if (top.kind.isCorrection) return null;
  if (top.stores.length <= 1) return null;

  final nearest = nearestByWalkingDistance(
    stores: top.stores,
    reachByNodeId: reachByNodeId,
  );
  if (nearest.reach == null) return null;
  return nearest.store.floorId;
}
