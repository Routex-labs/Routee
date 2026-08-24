/// 출구의 **문 앞 좌표**(BuildingEntrance.point)에 그래프 노드를 하나 만들고 문
/// 안쪽 노드([BuildingEntrance.nodeId])와 간선으로 잇는다. 실내 선이 문까지 닿아
/// 야외 선과 같은 점에서 맞물리게 하는 것이 목적이다.
///
/// **화면이 들고 있는 FloorGraph에는 적용하지 않는다** — 그것은 지도 매칭·복도
/// 추적이 쓰는 그래프라, 꿰매면 사용자가 문 밖으로 스냅되고 복도 네트워크에
/// 건물 밖으로 나가는 복도가 생긴다. 검증 기준은
/// test/domain/route/entrance_door_nodes_test.dart.
library;

import 'dart:math' as math;

import '../../models/building/building_graph.dart';
import '../../models/building/floor_graph.dart';
import '../../models/building/floor_plan.dart';
import '../geo/geo_transform.dart';
import 'building_entrances.dart';

/// 문과 앵커가 이보다 가까우면 꿰매지 않는다(m). 사실상 같은 점이라 노드만 는다.
const kEntranceDoorMinGapMeters = 3.0;

/// 문과 앵커가 이보다 멀면 꿰매지 않는다(m).
///
/// 문 두께로 설명되는 거리가 아니다. 실측 간격은 7~12 m이고(building_entrances.dart의
/// `BuildingEntrance.point` 주석), 그 두 배를 넘었다면 문 좌표와 노드가 서로 다른
/// 문을 가리키고 있다고 보는 편이 맞다. 그 자리에 직선 간선을 지어내면 벽을
/// 관통하는 안내가 되므로, 꿰매지 않고 호출자가 예전 안쪽 노드로 폴백한다.
const kEntranceDoorMaxGapMeters = 25.0;

/// 그 자리에 이미 노드가 있다고 보는 반경(m). 데이터가 나중에 고쳐져 문 앞에
/// 진짜 노드가 생겼을 때 중복 노드를 만들지 않기 위한 방어다. 이미 꿰맨 그래프를
/// 한 번 더 꿰매도 같은 이유로 그대로다.
const _existingNodeRadiusMeters = 1.0;

/// [entranceId] 출구의 문 노드 id. 만드는 쪽과 쓰는 쪽이 이 규칙 하나를 공유한다.
String entranceDoorNodeId(String entranceId) => 'entrance-door:$entranceId';

/// 경로 탐색에 쓸 [entrance]의 노드 id.
///
/// [nodes]에 문 노드가 있으면 그 id를, 없으면 예전 [BuildingEntrance.nodeId]로
/// **폴백한다** — 꿰매기가 건너뛴 출구(위 상수들의 조건)와 그래프를 못 받은
/// 경우([nodes]가 null)가 그렇고, 폴백이 없으면 출구 하나가 어긋난 것만으로
/// 길찾기가 통째로 죽는다.
String entranceRouteNodeId(
  Iterable<GraphNode>? nodes,
  BuildingEntrance entrance,
) {
  if (nodes == null) return entrance.nodeId;
  final doorNodeId = entranceDoorNodeId(entrance.id);
  for (final node in nodes) {
    if (node.id == doorNodeId) return doorNodeId;
  }
  return entrance.nodeId;
}

/// 층 그래프에 문 노드를 꿰맨 새 그래프. 꿰맬 것이 없으면 [graph] 그대로.
FloorGraph floorGraphWithEntranceDoors(FloorGraph graph, FloorPlan plan) {
  final patch = _entranceDoorPatch(graph.nodes, plan);
  if (patch == null) return graph;
  return FloorGraph(
    nodes: [...graph.nodes, ...patch.nodes],
    edges: [...graph.edges, ...patch.edges],
  );
}

/// 건물 전체 그래프에 문 노드를 꿰맨 새 그래프. 꿰맬 것이 없으면 [graph] 그대로.
BuildingGraph buildingGraphWithEntranceDoors(
  BuildingGraph graph,
  FloorPlan plan,
) {
  final patch = _entranceDoorPatch(graph.nodes, plan);
  if (patch == null) return graph;
  return BuildingGraph(
    buildingId: graph.buildingId,
    vertical: graph.vertical,
    floorNamesById: graph.floorNamesById,
    nodes: [...graph.nodes, ...patch.nodes],
    edges: [...graph.edges, ...patch.edges],
  );
}

class _DoorPatch {
  const _DoorPatch(this.nodes, this.edges);
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
}

/// [plan]의 지상 출구마다 문 노드와 간선을 하나씩 만든다. 만든 것이 없으면 null.
///
/// 좌표 변환은 **앵커 노드가 있는 층의 노드만으로** 피팅한다. 건물 전체 그래프는
/// 전 층 노드가 섞여 있어 통째로 피팅하면 층마다 다른 보정이 하나로 뭉개진다
/// (multi_floor_router가 층별로 나눠 피팅하는 것과 같은 이유). 층 그래프는
/// floorId가 전부 null이라 그 한 덩어리가 그대로 한 층이 된다.
_DoorPatch? _entranceDoorPatch(List<GraphNode> nodes, FloorPlan plan) {
  final entrances = groundEntrancesFrom(plan);
  if (entrances.isEmpty) return null;

  final nodesById = {for (final node in nodes) node.id: node};
  final nodesByFloor = <String, List<GraphNode>>{};
  for (final node in nodes) {
    nodesByFloor.putIfAbsent(node.floorId ?? '', () => <GraphNode>[]).add(node);
  }
  final transformByFloor = <String, AffineTransform>{};

  final doorNodes = <GraphNode>[];
  final doorEdges = <GraphEdge>[];
  for (final entrance in entrances) {
    final anchor = nodesById[entrance.nodeId];
    if (anchor == null) continue;

    final floorKey = anchor.floorId ?? '';
    final floorNodes = nodesByFloor[floorKey]!;
    final transform = transformByFloor.putIfAbsent(
      floorKey,
      () => fitFloorGeoTransform(floorNodes),
    );
    final local = transform.invert(
      entrance.point.latitude,
      entrance.point.longitude,
    );
    if (local == null) continue;
    final (xM, yM) = local;

    final gapM = _distanceM(xM, yM, anchor.xM, anchor.yM);
    if (gapM < kEntranceDoorMinGapMeters) continue;
    if (gapM > kEntranceDoorMaxGapMeters) continue;
    if (floorNodes.any(
      (node) =>
          _distanceM(xM, yM, node.xM, node.yM) <= _existingNodeRadiusMeters,
    )) {
      continue;
    }

    final doorNodeId = entranceDoorNodeId(entrance.id);
    doorNodes.add(
      GraphNode(
        id: doorNodeId,
        type: 'entrance',
        name: entrance.name,
        xM: xM,
        yM: yM,
        // lat/lng는 일부러 비운다. 채우면 다음 fitFloorGeoTransform이 이
        // 노드까지 대응점으로 세어, 실측 앵커가 2개뿐이라 합성 변환을 쓰던
        // 층이 조용히 다른 변환으로 넘어간다. 그릴 때 쓰는 값은 local m이다.
        floorId: anchor.floorId,
      ),
    );
    doorEdges.add(
      GraphEdge(
        id: 'entrance-door-edge:${entrance.id}',
        fromNodeId: doorNodeId,
        toNodeId: anchor.id,
        lengthM: gapM,
        bidirectional: true,
        // 비우면 두 노드를 직선으로 잇는다(GraphEdge.geometryLocalM 주석).
        geometryLocalM: const [],
        fromFloorId: anchor.floorId,
        toFloorId: anchor.floorId,
      ),
    );
  }

  if (doorNodes.isEmpty) return null;
  return _DoorPatch(doorNodes, doorEdges);
}

double _distanceM(double x1, double y1, double x2, double y2) =>
    math.sqrt(math.pow(x1 - x2, 2) + math.pow(y1 - y2, 2));
