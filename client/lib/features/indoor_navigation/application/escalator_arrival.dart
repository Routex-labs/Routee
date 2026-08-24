import '../../../models/building/floor_graph.dart';
import '../contract/floor_transition_ui_state.dart';
import 'escalator_node_naming.dart';
import 'escalator_transition_detector.dart';

/// 확정된 층 이동의 **도착 노드**를 새 층 그래프에서 찾는다.
///
/// 이 값이 새 층의 앵커가 된다. 못 찾으면 사용자는 하차한 자리를 앱이 모르는
/// 상태가 되므로, 세 단계로 물러서며 찾는다.
///
/// 1. **길찾기가 지목한 노드**([EscalatorTransition.expectedArrivalNodeId]).
///    붙어 있는 레인 중 어느 것을 탔는지는 센서로 못 가르고 경로만 안다.
/// 2. **이름이 맞는 도착 노드** — `{그룹}-UP(FR2F)`처럼 출발 층까지 일치.
/// 3. **같은 뱅크·같은 방향의 아무 노드** — 이름 규칙이 깨진 데이터에서도
///    같은 에스컬레이터 근처에는 세워 준다. 정확하진 않아도 반대편 건물에
///    떨어뜨리는 것보다 낫다.
GraphNode? findEscalatorArrivalNode(
  FloorGraph? graph,
  EscalatorTransition transition,
) {
  if (graph == null) return null;
  final expectedArrivalNodeId = transition.expectedArrivalNodeId;
  if (expectedArrivalNodeId != null) {
    for (final node in graph.nodes) {
      if (node.id == expectedArrivalNodeId && node.type == 'escalator') {
        return node;
      }
    }
  }
  GraphNode? sameGroupFallback;
  for (final node in graph.nodes) {
    if (node.type != 'escalator') continue;
    final parsed = EscalatorNodeName.tryParse(node.name);
    if (parsed == null) continue;
    if (parsed.isArrivalOf(
      group: transition.group,
      direction: transition.direction,
      fromFloorLabel: transition.fromFloorLabel,
    )) {
      return node;
    }
    if (sameGroupFallback == null &&
        parsed.group == transition.group &&
        parsed.direction == transition.direction) {
      sameGroupFallback = node;
    }
  }
  return sameGroupFallback;
}

/// 이 층에서 [direction]으로 **실제로 데려다주는** 탑승 노드. 없으면 null.
///
/// 디버그 강제 전환이 "위층/아래층"을 정할 때 쓴다. **층 순위로 ±1을 계산하지
/// 않는다** — 노드 이름이 갈 층을 직접 적고(`ES1-UP(TO3F)`), 한 번에 두 층을
/// 건너뛰는 에스컬레이터가 실제로 있다(2026-08-13 실측). 순위로 이웃 층을 잡으면
/// 그런 에스컬레이터는 강제 전환으로 영영 재현할 수 없다.
///
/// [knownFloorLabels]에 없는 층으로는 태우지 않는다. 도착 층 도면을 못 열면
/// 시퀀스가 중간에 되돌아가서, 보려던 연출 대신 실패 경로를 보게 된다.
({GraphNode node, EscalatorNodeName name})? findEscalatorBoardingNode({
  required FloorGraph? graph,
  required EscalatorDirection direction,
  required List<String> knownFloorLabels,
}) {
  if (graph == null) return null;
  for (final node in graph.nodes) {
    if (node.type != 'escalator') continue;
    final name = EscalatorNodeName.tryParse(node.name);
    if (name == null) continue;
    if (name.role != EscalatorNodeRole.boarding) continue;
    if (name.direction != direction) continue;
    if (!knownFloorLabels.contains(name.otherFloorLabel)) continue;
    return (node: node, name: name);
  }
  return null;
}

/// 지금 화면이 그려야 하는 층 전환 배너 상태. 없으면 null.
///
/// 판정 단계를 UI 문구로 **한 번만** 옮긴다. 화면은 여기서
/// 나온 값만 보고 그린다 — 임계값이나 노드 근접을 다시 계산하지 않는다.
///
/// 우선순위가 이 함수의 전부다. 탑승 중 → 접근 순으로 보며, 앞의 것이 있으면
/// 뒤는 보지 않는다. 뒤집으면 도면을 갈아 끼우는 동안 "접근 중"이 떠 있다.
///
/// **하차 뒤 단계는 없다.** 확정되는 순간 [ride]가 비고 배너도 사라진다
/// ([FloorTransitionStage]).
FloorTransitionUiState? floorTransitionUiState({
  required EscalatorTransition? ride,
  required EscalatorPhaseChange? stage,
}) {
  if (ride != null) {
    return FloorTransitionUiState(
      stage: FloorTransitionStage.swapping,
      fromFloorLabel: ride.fromFloorLabel,
      toFloorLabel: ride.toFloorLabel,
      goingUp: ride.direction == EscalatorDirection.up,
    );
  }
  // 도착 층을 모르면 배너에 쓸 문장이 없다. `{출발}→{도착}`이 문구의 뼈대다.
  if (stage == null || stage.toFloorLabel == null) return null;
  return FloorTransitionUiState(
    stage: stage.phase == EscalatorPhase.verticalMotionDetected
        ? FloorTransitionStage.moving
        : FloorTransitionStage.boarding,
    fromFloorLabel: stage.fromFloorLabel,
    toFloorLabel: stage.toFloorLabel!,
    goingUp: stage.direction == EscalatorDirection.up,
  );
}
