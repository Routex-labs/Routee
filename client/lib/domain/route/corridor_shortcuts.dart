/// 복도 그래프에 지름길 간선을 얹는다. **노드는 하나도 만들지 않는다.**
///
/// **[entranceDoorNodes]와 정반대로 두 그래프 모두에 얹는다.** 문 노드는 건물
/// 밖 가짜 복도라 지도 매칭에서 뺐지만, 지름길은 사용자가 실제로 걷는 자리다 —
/// 라우팅에만 넣으면 경로와 마커가 서로 다른 길을 가리킨다.
///
/// 왜 그 간선을 골랐는지와 **새 노드 0개 규칙을 못 푸는 이유**는
/// `docs/client/corridor-graph-detour.md`. 검증은 corridor_shortcuts_test.dart.
library;


import '../../models/building/floor_graph.dart';

/// 이미 있는 두 노드를 잇는 지름길 하나.
class CorridorShortcut {
  const CorridorShortcut({
    required this.fromNodeId,
    required this.toNodeId,
    required this.lengthM,
  });

  final String fromNodeId;
  final String toNodeId;

  /// 두 노드의 직선 거리(m). 층 내부 간선은 cost_m == length_m이 정의이므로
  /// (GraphEdge.routingCostM 주석) 이 값 하나가 표시 거리이자 탐색 비용이다.
  final double lengthM;
}

/// 건물 하나의 층별 지름길 표.
class CorridorShortcutTable {
  const CorridorShortcutTable({
    required this.buildingId,
    required this.byFloorName,
  });

  /// 이 표가 유효한 건물. **다른 건물에 조용히 적용되면 안 된다** — 노드 id는
  /// 건물마다 다른 체계이고, 우연히 겹치면 벽을 관통하는 간선이 생긴다.
  final String buildingId;

  /// 층 이름(`1F`·`B1`) -> 그 층의 지름길.
  final Map<String, List<CorridorShortcut>> byFloorName;

  List<CorridorShortcut> forFloor(String buildingId, String floorName) =>
      buildingId == this.buildingId
      ? (byFloorName[floorName] ?? const [])
      : const [];
}

/// 지름길 간선 id. 만드는 쪽과 알아보는 쪽이 이 규칙 하나를 공유한다.
/// 멱등성이 여기 걸려 있다 — 같은 지름길은 언제나 같은 id다.
String corridorShortcutEdgeId(CorridorShortcut shortcut) =>
    'corridor-shortcut:${shortcut.fromNodeId}|${shortcut.toNodeId}';

/// [graph]에 [table]의 지름길을 얹은 새 그래프. 얹을 것이 없으면 [graph] 그대로.
///
/// 다음은 **조용히 건너뛴다**(예외를 던지지 않는다). 지름길 하나가 안 맞는 것은
/// 길찾기를 통째로 죽일 만한 일이 아니고, 이 표는 서버 데이터보다 늦게 낡는다.
///
/// - [buildingId]가 표의 건물과 다르다 → 아무것도 안 얹는다
/// - 노드 id가 그래프에 없다(데이터 재생성으로 id가 바뀐 경우)
/// - 그 두 노드를 잇는 간선이 이미 있다 → 중복 간선을 만들지 않는다(멱등)
FloorGraph floorGraphWithCorridorShortcuts(
  FloorGraph graph,
  CorridorShortcutTable table, {
  required String buildingId,
  required String floorName,
}) {
  final shortcuts = table.forFloor(buildingId, floorName);
  if (shortcuts.isEmpty) return graph;

  final nodeIds = {for (final node in graph.nodes) node.id};
  final linked = {
    for (final edge in graph.edges) _pairKey(edge.fromNodeId, edge.toNodeId),
  };

  final added = <GraphEdge>[];
  for (final shortcut in shortcuts) {
    if (!nodeIds.contains(shortcut.fromNodeId)) continue;
    if (!nodeIds.contains(shortcut.toNodeId)) continue;
    final key = _pairKey(shortcut.fromNodeId, shortcut.toNodeId);
    if (!linked.add(key)) continue;
    added.add(
      GraphEdge(
        id: corridorShortcutEdgeId(shortcut),
        fromNodeId: shortcut.fromNodeId,
        toNodeId: shortcut.toNodeId,
        lengthM: shortcut.lengthM,
        bidirectional: true,
        // 비워 두면 두 노드를 직선으로 잇는다는 것이 규칙이고, 지름길은 정의상
        // 직선이다(그래서 여유폭을 그 직선 위에서 쟀다).
        geometryLocalM: const [],
      ),
    );
  }
  if (added.isEmpty) return graph;
  return FloorGraph(nodes: graph.nodes, edges: [...graph.edges, ...added]);
}

String _pairKey(String left, String right) =>
    left.compareTo(right) <= 0 ? '$left|$right' : '$right|$left';
