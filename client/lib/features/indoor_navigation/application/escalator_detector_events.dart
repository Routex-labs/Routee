/// 판정기가 바깥으로 내보내는 값 — 공개 단계, 단계 전이, 확정된 층 이동,
/// 진단 이벤트. 판정 알고리즘은 `escalator_transition_detector.dart`에 있다.
library;

import 'escalator_node_naming.dart';

/// 층 이동의 공개 진행 단계. 배너·걸음 pause·도면 교체·하차 재개가 **서로 다른
/// 근거와 시점**을 쓰도록 나눈 것이다(단계표: escalator-thresholds.md).
enum EscalatorPhase {
  idle,

  /// 활성 경로의 탑승점에 접근했다. 배너만 띄운다.
  boardingDetected,

  /// 실제로 오르내리는 중이다. 위치에 반영하는 걸음만 멈춘다.
  verticalMotionDetected,

  /// 반 층을 지났다. 이 단계에서만 목적 층 지도를 연다.
  midpointReached,

  /// 하차했다. 새 anchor를 잡고 걸음 적용을 재개한다.
  landed,

  cancelled,
  failed,
}

/// 단계 전이 한 건. UI는 이 값만 보고 문구·pause·층 전환을 결정한다.
class EscalatorPhaseChange {
  const EscalatorPhaseChange({
    required this.phase,
    required this.atMs,
    required this.fromFloorLabel,
    required this.reason,
    this.toFloorLabel,
    this.group,
    this.direction,
    this.boardingNodeId,
    this.expectedArrivalNodeId,
    this.deltaM = 0,
    this.transition,
  });

  final EscalatorPhase phase;
  final int atMs;
  final String fromFloorLabel;
  final String reason;
  final String? toFloorLabel;
  final String? group;
  final EscalatorDirection? direction;
  final String? boardingNodeId;
  final String? expectedArrivalNodeId;
  final double deltaM;

  /// `midpointReached`·`landed`·`cancelled`에서만 채워진다.
  final EscalatorTransition? transition;

  Map<String, Object?> toJson() => {
    'phase': phase.name,
    'at_ms': atMs,
    'reason': reason,
    'from_floor': fromFloorLabel,
    'to_floor': toFloorLabel,
    'group': group,
    'direction': direction?.name,
    'boarding_node_id': boardingNodeId,
    'expected_arrival_node_id': expectedArrivalNodeId,
    'delta_m': deltaM,
  };
}

/// 확정된 층 이동.
class EscalatorTransition {
  const EscalatorTransition({
    required this.group,
    required this.direction,
    required this.fromFloorLabel,
    required this.toFloorLabel,
    required this.deltaM,
    required this.durationMs,
    required this.stepsDuring,
    required this.boardingNodeId,
    required this.boardingNodeName,
    required this.boardingDistanceM,
    required this.boardingEvidence,
    this.expectedArrivalNodeId,
  });

  /// 에스컬레이터 뱅크 식별자(`ES1`…). 도착 노드를 새 층에서 찾을 때 쓴다.
  final String group;

  final EscalatorDirection direction;
  final String fromFloorLabel;
  final String toFloorLabel;

  /// baseline 대비 고도 변화(m). 상행이면 양수.
  final double deltaM;

  /// 후보가 열린 시점부터 확정까지 걸린 시간.
  final int durationMs;

  /// 그 사이 늘어난 걸음 수. 에스컬레이터는 거의 0, 계단은 크다 — 사후 분석에서
  /// 두 경우를 가르는 값이다.
  final int stepsDuring;

  final String boardingNodeId;
  final String? boardingNodeName;

  /// 허가 시점에 관측한 탑승 노드까지의 거리(m).
  final double boardingDistanceM;

  /// `observed`(위치로 단일 후보), `routeAndObserved`(예정 노드도 근접 관측),
  /// `routeExpected`(위치 오차 때문에 활성 경로의 예정 노드만 사용).
  final String boardingEvidence;

  /// 활성 경로가 선택한 정확한 도착 노드. 붙어 있는 레인은 센서로 억지
  /// 재구분하지 않고 길찾기가 고른 전이를 따라 새 층 앵커를 복원한다.
  final String? expectedArrivalNodeId;
}

/// 판정 과정 진단 이벤트. 확정뿐 아니라 **거부도 남긴다** — 임계값 튜닝은
/// 거부 이유가 있어야 가능하다.
class EscalatorDetectionEvent {
  const EscalatorDetectionEvent({
    required this.atMs,
    required this.kind,
    required this.reason,
    required this.deltaM,
    required this.fromFloorLabel,
    this.toFloorLabel,
    this.group,
    this.durationMs,
    this.stepsDuring,
    this.boardingEvidence,
  });

  final int atMs;

  /// `armed` · `candidate` · `confirmed` · `rejected`.
  final String kind;

  /// 거부 이유(`reverted`·`noSettle`·`multiFloorUnsupported`·`noBoardingNode`·
  /// `unknownTargetFloor`) 또는 진행 사유.
  final String reason;

  final double deltaM;
  final String fromFloorLabel;
  final String? toFloorLabel;
  final String? group;
  final int? durationMs;
  final int? stepsDuring;
  final String? boardingEvidence;

  Map<String, Object?> toJson() => {
    'at_ms': atMs,
    'kind': kind,
    'reason': reason,
    'delta_m': deltaM,
    'from_floor': fromFloorLabel,
    'to_floor': toFloorLabel,
    'group': group,
    'duration_ms': durationMs,
    'steps_during': stepsDuring,
    'boarding_evidence': boardingEvidence,
  };
}
