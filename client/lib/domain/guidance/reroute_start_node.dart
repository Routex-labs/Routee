import '../../models/building/floor_graph.dart';

/// 재탐색 출발점이 될 수 없는 노드 타입.
///
/// 수직 전이 노드를 출발점으로 삼는 것은 "이미 그것을 타는 중"이라는 뜻이다.
/// 이탈 재탐색은 걷다가 경로를 벗어난 사람에게 도는 것이라 그 전제가 성립하지
/// 않는다.
const rerouteExcludedNodeTypes = {'escalator', 'elevator', 'stairs'};

/// 이탈 재탐색의 출발 노드를 고른다. 쓸 노드가 없으면 null — 호출부는 이번
/// 이탈에서 재탐색을 걸지 않는다.
///
/// 최근접만으로 고르면 안 되는 이유가 에스컬레이터에 있다. 실측 B2 그래프에서
/// 나란한 두 레인의 노드는 1.3~2.6m 떨어져 있고 서로 직접 연결돼 있어, heading이
/// 틀어져 보정 위치가 2m 밀리는 것만으로 최근접 노드가 반대 레인으로 넘어간다.
/// 그 노드에서 다시 뽑은 다층 경로는 반대 에스컬레이터를 타므로, 사용자에게는
/// 경로가 통째로 뒤집힌 것으로 보인다.
///
/// 그래프 거리로 거르는 방법은 여기서 통하지 않는다 — 두 레인이 직접 이어져
/// 있어 그래프 거리도 똑같이 1.3~2.6m다. 그래서 [rerouteExcludedNodeTypes]를
/// 후보에서 뺀다. 남는 최근접은 그 레인 쪽 junction(실측 2.7~6m)이고, 어느
/// 레인을 탈지는 그 자리에서 다시 길찾기가 정한다.
String? pickRerouteStartNodeId({
  required List<GraphNode> nodes,
  required double xM,
  required double yM,
  String? excludingNodeId,
}) {
  GraphNode? nearest;
  double? nearestDistanceSquared;
  for (final node in nodes) {
    if (node.id == excludingNodeId) continue;
    if (rerouteExcludedNodeTypes.contains(node.type.toLowerCase())) continue;
    final dx = node.xM - xM;
    final dy = node.yM - yM;
    final distanceSquared = dx * dx + dy * dy;
    if (nearestDistanceSquared == null ||
        distanceSquared < nearestDistanceSquared) {
      nearestDistanceSquared = distanceSquared;
      nearest = node;
    }
  }
  return nearest?.id;
}
