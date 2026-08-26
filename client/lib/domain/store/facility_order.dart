/// 편의시설을 **지금 선 자리에서 가까운 순**으로 세운다.
///
/// 계약과 그렇게 정한 이유는 [facilitiesByWalkingDistance] 위에 있다.
library;

import '../../models/place/store_index_entry.dart';
import '../route/dijkstra.dart';

/// 시설 한 줄과 거기까지의 도달 정보.
///
/// [reach]가 null이면 **거리를 모른다**는 뜻이다(입구 노드가 없거나 그래프에서
/// 닿지 못한다). 화면은 이 null을 보고 거리 줄을 생략한다 — 0도 무한대도 거짓이다.
typedef FacilityReach = ({StoreIndexEntry facility, NodeReach? reach});

/// [facilities]를 보행 거리 오름차순으로 세운 **새 목록**을 만든다.
///
/// 호출부는 **건물 전체**를 넘긴다(층으로 거르지 않는다). 급할 때 찾는 시설의
/// 질문은 "이 층에 무엇이 있나"가 아니라 "가장 가까운 것이 어디냐"라서다.
///
/// [reachByNodeId]는 사용자의 현재 위치에서 돌린 `reachableFrom` 결과다. 경로를
/// 그릴 때와 **같은 시작 노드**여야 한다 — 다른 규칙으로 고르면 목록에 적힌
/// 거리와 실제로 그 줄을 눌렀을 때 나오는 거리가 어긋난다. 직선거리를 안 쓰는
/// 이유와 새로 계산하지 않는 이유는 `search_result_order.dart`와 같다.
///
/// **거리를 모르면 순서를 바꾸지 않는다.** 전부 세우거나 전혀 안 세운다 — 아는
/// 몇 건만 올리면 "가까운 순"이라 적힌 목록이 실제로는 아니게 된다. 닿지 못하는
/// 시설은 **끝**에 입력 순서로 붙인다(있다는 사실은 참이지만 가깝지는 않다).
List<FacilityReach> facilitiesByWalkingDistance({
  required List<StoreIndexEntry> facilities,
  required Map<String, NodeReach>? reachByNodeId,
}) {
  final reach = reachByNodeId;
  if (reach == null || reach.isEmpty) {
    return [for (final f in facilities) (facility: f, reach: null)];
  }

  // 거리를 아는 것만 정렬 대상으로 뽑는다. index는 아래 동점 처리에 쓴다.
  final ranked = <({int index, StoreIndexEntry facility, NodeReach reach})>[];
  // 거리를 모르는 것은 여기 모았다가 뒤에 그대로 붙인다. 훑는 순서가 곧 입력
  // 순서라, 따로 정렬하지 않는 것만으로 상대 순서가 보존된다.
  final unknown = <StoreIndexEntry>[];

  for (var index = 0; index < facilities.length; index++) {
    final facility = facilities[index];
    final nodeId = facility.entranceNodeId;
    final found = nodeId == null ? null : reach[nodeId];
    if (found == null) {
      unknown.add(facility);
      continue;
    }
    ranked.add((index: index, facility: facility, reach: found));
  }

  // **Dart의 `List.sort`는 안정 정렬이 아니다** — 같은 노드를 공유하는 시설은
  // (한 자리에 남녀 화장실이 붙어 있는 경우가 그렇다) 거리가 같아 호출마다 순서가
  // 뒤바뀐다. 원래 인덱스로 동점을 깬다.
  //
  // 기준이 `costM`이 아니라 `distanceM`인 이유는 화면에 적히는 값이 그것이라서다.
  ranked.sort((a, b) {
    final byDistance = a.reach.distanceM.compareTo(b.reach.distanceM);
    if (byDistance != 0) return byDistance;
    return a.index.compareTo(b.index);
  });

  return [
    for (final e in ranked) (facility: e.facility, reach: e.reach),
    for (final f in unknown) (facility: f, reach: null),
  ];
}
