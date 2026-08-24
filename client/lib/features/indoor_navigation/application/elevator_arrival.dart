/// 엘리베이터 층 이동의 **도착 노드**를 그래프에서 찾고, 호기 이름을 비교할
/// 때 쓰는 규칙을 정한다. 근거는 하나다 — 같은 `name`(호기 `EV1`…)이 층을
/// 가로질러 같은 샤프트를 가리킨다. 에스컬레이터 대응물은
/// `escalator_arrival.dart`.
library;

import '../../../models/building/floor_graph.dart';

/// 호기 이름을 비교할 수 있는 꼴로 만든다. 이름이 없으면 null.
///
/// **호기 이름을 다루는 단일 규칙이다.** 판정기
/// (`elevator_transition_detector.dart`)도 이 함수를 거쳐 이름을 읽는다 —
/// 한쪽만 정규화하면 정차 층 후보는 `EV1`과 `ev1 `을 두 호기로 쪼개는데
/// 도착 노드 찾기는 하나로 보아, 둘 중 한쪽만 맞는 상태가 된다.
///
/// 배포 데이터(더현대 서울, 2026-08-24)에는 `EV1`~`EV4`·`EV6`과 이름 없는
/// 노드뿐이라 **지금은 흡수할 변형이 없다.** 규칙을 한 곳에 둔 것은 데이터가
/// 흔들릴 때 두 곳이 같이 움직이게 하기 위해서다.
String? normalizedCarName(String? raw) {
  final trimmed = raw?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed.toUpperCase();
}

/// 노드가 엘리베이터면 비교에 쓸 **호기 이름**, 아니면 null.
///
/// null의 뜻이 둘이다: 엘리베이터가 아니거나, **호기를 모르는 엘리베이터**다.
/// 후자는 실제로 있다 — 더현대 서울 B3·B4에 이름 없는 노드가 4개 있고, 그
/// 노드로는 샤프트를 이을 수 없다([findElevatorArrivalNode]).
String? elevatorCarName(GraphNode node) =>
    node.type != 'elevator' ? null : normalizedCarName(node.name);

/// [carName] 호기가 [graph] 층에 서는 지점. 안 서면 null.
///
/// 층을 옮긴 뒤 **새 층의 앵커**가 되는 값이다. 좌표로 찾지 않는다 — 층 도면의
/// 등록 오차 때문에 같은 샤프트가 층마다 어긋나 있다(실측 EV1: 1F 97.5/120.8 ↔
/// B5 113.2/119.1, 약 16m). 이름이 유일하게 정확한 근거다.
///
/// **null을 억지로 메우지 않는다.** 두 경우 모두 null이고, 부르는 쪽은 "그
/// 층에서는 못 내린다"로 읽어야 한다.
/// - [carName]이 null·빈 값(호기를 모르는 노드에서 출발했다)
/// - 그 호기가 이 층에 안 선다(EV6은 5F·B3~B6에 안 선다)
///
/// 가장 가까운 **다른** 호기를 대신 돌려주면 사용자를 건물 반대편에 세운다.
GraphNode? findElevatorArrivalNode({
  required FloorGraph? graph,
  required String? carName,
}) {
  if (graph == null) return null;
  final wanted = normalizedCarName(carName);
  if (wanted == null) return null;
  for (final node in graph.nodes) {
    if (elevatorCarName(node) == wanted) return node;
  }
  return null;
}
