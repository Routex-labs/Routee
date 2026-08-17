/// 기압 변화로 **에스컬레이터 층 이동**을 판정한다. HTTP·플러그인·UI를 모르는
/// 순수 로직이고, 합성 기압 시계열로 전부 테스트된다.
///
/// 설계 원칙 셋(오탐 > 미탐 · 노드는 허가 기압은 근거 · 절대 고도는 못 쓴다)과
/// 아래 모든 임계값의 실측 근거는 `docs/client/escalator-thresholds.md`가 단일 출처다.
library;

import 'dart:math' as math;

import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import '../../../domain/geo/floor_label.dart';
import '../../../models/building/floor_graph.dart';
import '../contract/altitude_sample.dart';
import '../contract/raw_motion_activity.dart';
import 'escalator_node_naming.dart';

/// 판정 임계값. 값마다의 실측 근거는 `docs/client/escalator-thresholds.md`에 있고,
/// 조정은 로그(schema v12 `altimeter_samples`·`floor_transition_events`)를 보고 한다.
class EscalatorDetectorConfig {
  const EscalatorDetectorConfig({
    this.armRadiusM = 6.0,
    this.routeApproachArmRadiusM = 16.0,
    this.altitudeArmRadiusM = 16.0,
    this.armHoldMs = 60000,
    this.smoothingWindowMs = 3000,
    this.minSmoothingSamples = 3,
    this.maxSampleAgeMs = 15000,
    this.minDeltaM = 1.2,
    this.mapSwapDeltaM = 2.4,
    this.minConfirmDeltaM = 2.2,
    this.rampConsistencyWindowMs = 5000,
    this.minDirectionalRampStrides = 3,
    this.directionalStrideMs = 1000,
    this.minDirectionalSampleDeltaM = 0.04,
    this.minRampMs = 2500,
    this.settleWindowMs = 2500,
    this.minRampRiseM = 0.45,
    this.settleSlopeM = 0.25,
    this.fastAltitudeTauMs = 300,
    this.fastSlopeBaseMs = 700,
    this.fastExitSlopeMps = 0.12,
    this.fastExitWithStepSlopeMps = 0.18,
    this.fastExitQuietMs = 1000,
    this.candidateTimeoutMs = 90000,
    this.multiFloorRejectM = 10.0,
    this.baselineTrackAlpha = 0.02,
    this.boardingApproachRadiusM = 3.0,
    this.boardingApproachUpdates = 2,
    this.boardingPhaseTimeoutMs = 40000,
    this.minVerticalSpeedMps = 0.12,
    this.verticalMotionMinMs = 1000,
    this.visibleVerticalDeltaM = 1.2,
    this.minVisibleRiseM = 0.5,
    this.earlyVerticalQuietMs = 1000,
  });

  /// 에스컬레이터 노드에 이만큼 다가오면 판정을 "허가"한다. 랜딩 폭과 보정
  /// 위치 오차를 감안한 값이다.
  final double armRadiusM;

  /// 경로가 탑승 노드를 정확히 가리킬 때만 쓰는 넓은 허가 반경(실측 위치 오차 12m).
  final double routeApproachArmRadiusM;

  /// **기압이 이미 층 이동을 말할 때** 쓰는 허가 반경. 근거는
  /// `docs/client/escalator-thresholds.md`의 「허가」절.
  final double altitudeArmRadiusM;

  /// 허가 유지 시간. 탑승 뒤에는 걸음이 멈춰 위치가 갱신되지 않으므로, 노드에서
  /// 멀어진 것으로 계산되는 동안에도 판정할 수 있어야 한다.
  final int armHoldMs;

  /// 중앙값 평활 창. **이 창이 곧 판정 지연이다**(중앙값은 창의 절반쯤 뒤처진다).
  /// 2000ms에서 iOS 판정이 한 번도 안 돌았던 사고가 여기 있다.
  final int smoothingWindowMs;

  /// 평활에 쓸 최소 샘플 수. iOS ~0.93Hz, Android 5Hz로 간격이 5배 다르므로
  /// 시간 창만으로는 개수가 보장되지 않는다. 창보다 오래된 샘플이라도 최근
  /// 이 개수는 남겨 두어, 센서 주기가 어떻든 판정이 돌게 한다.
  final int minSmoothingSamples;

  /// 이보다 오래된 샘플은 평활에 쓰지 않는다. 시계열이 끊긴 구간은 판정하지 않고
  /// 창을 다시 채운다.
  final int maxSampleAgeMs;

  /// 후보를 여는 최소 고도 변화(m). 도면 교체는 [mapSwapDeltaM]에서 따로 한다.
  ///
  /// **이 문턱 하나로 층이 바뀌지 않는다** — 노드 허가·방향 일관성
  /// ([minDirectionalRampStrides])·수직 속도([minRampRiseM])가 함께 성립해야 한다.
  final double minDeltaM;

  /// 목적 층 도면으로 갈아 끼우는 누적 변화량. [minConfirmDeltaM](2.2)보다 크므로
  /// 낮은 층고에서는 조기 신호 없이 `landed`에서 한 번에 전환된다.
  final double mapSwapDeltaM;

  /// 층 이동을 최종 확정할 최소 변화량. 고정된 층고를 맞히려 하지 않고, 같은 방향
  /// 등속 변화와 하차 시 속도 감소가 함께 확인될 때만 쓴다.
  final double minConfirmDeltaM;

  /// 후보 시작 전 상승·하강이 한 번의 압력 튐이 아니라 같은 방향으로 이어졌는지
  /// 확인하는 시간 창이다.
  final int rampConsistencyWindowMs;

  /// 그 창 안에서 같은 방향을 확인할 **구간(stride) 수**. 샘플 수로 세면 같은 5초가
  /// iOS 4~5개 · Android 27개가 되어 기기마다 다른 문턱이 된다.
  final int minDirectionalRampStrides;

  /// 한 구간의 최소 길이. 이 값이 곧 [minDirectionalSampleDeltaM]의 의미를 정한다 —
  /// 1초에 4cm와 0.18초에 4cm는 전혀 다른 속도다.
  final int directionalStrideMs;

  final double minDirectionalSampleDeltaM;

  /// 후보가 최소 이만큼 유지돼야 확정 판단으로 넘어간다. 중앙값 평활이 꺾이는
  /// 지점에 만드는 **평평한 구간**을 확정으로 오인하지 않기 위한 것이다.
  final int minRampMs;

  /// 상승/하강이 멈췄는지 보는 창. "움직이는 중"인지도 같은 창으로 본다.
  final int settleWindowMs;

  /// 후보를 열려면 [settleWindowMs] 동안 이만큼은 실제로 움직여야 한다.
  /// **누적 변화량만으로는 부족하다** — 기상 드리프트도 누적 [minDeltaM]을 넘는다.
  final double minRampRiseM;

  /// 이 창 동안 고도 변화가 이 값 이하면 "멈췄다"로 본다. 확정 시점을 하차
  /// 순간에 맞추려면 임계값 통과가 아니라 **정지**를 기다려야 한다. 임계값
  /// 통과에서 바로 확정하면 아직 탑승 중인데 지도가 바뀐다.
  final double settleSlopeM;

  /// 하차를 빠르게 잡는 저지연 EMA의 **시정수**(ms). 샘플당 고정 계수로 적으면
  /// 같은 α가 기기마다 다른 필터가 되므로 시정수로 적고, 계수는 매 샘플
  /// `1 - exp(-dt/tau)`로 만든다. 평활의 몫은 [fastSlopeBaseMs]가 맡는다.
  final int fastAltitudeTauMs;

  /// 수직 속도를 잴 **최소 시간 밑변**(ms). 직전 샘플과 비교하면 Android 180ms
  /// 밑변에서 진짜 변화(5cm)가 센서 분해능(0.01 hPa ≈ 8cm)보다 작아 속도가 0으로
  /// 읽힌다 — 타는 중에 "멈췄다"가 된다.
  final int fastSlopeBaseMs;

  /// 빠른 EMA의 수직 속도가 이 값 이하로 유지되면 하차로 본다.
  final double fastExitSlopeMps;

  /// 새 걸음이 함께 관측된 경우의 완화된 속도 상한. 사용자가 에스컬레이터에서
  /// 걷더라도 수직 속도가 계속 크면 통과하지 않고, 하차 뒤 첫 걸음과 수직 속도
  /// 감소가 겹치면 곧바로 재개한다.
  final double fastExitWithStepSlopeMps;

  /// 걸음 근거가 없을 때 저속이 **유지돼야 하는 시간**. 개수로 세면 Android에서
  /// 0.36초가 되어 노이즈 한 번이 하차로 읽혔다(= 한 층에 층이 두 번 바뀌는 증상).
  final int fastExitQuietMs;

  /// 후보가 이 시간 안에 안정되지 않으면 기상 변화·센서 드리프트로 보고 버린다.
  final int candidateTimeoutMs;

  /// 한 층으로 설명되지 않는 변화(엘리베이터·연속 탑승). v1은 ±1층만 지원해
  /// 확정하지 않고 거부하되, 빈도는 로그로 남긴다. 실측 한 층은 6.2m·두 층은 12m.
  final double multiFloorRejectM;

  /// 허가/후보가 없는 동안 baseline을 천천히 따라가는 비율. 기상 드리프트를
  /// 흡수한다. 허가 중에는 추적하지 않는다 — 상승분을 같이 먹어버린다.
  final double baselineTrackAlpha;

  /// 활성 경로의 탑승점에 이만큼 다가오면 **배너만** 띄운다. 되돌리기 비용이 거의
  /// 없어 [minDeltaM]보다 훨씬 이른 근거로 띄운다.
  final double boardingApproachRadiusM;

  /// 탑승점까지 거리가 줄어드는 것을 확인할 **서로 다른 걸음 갱신** 횟수.
  /// 한 프레임의 근접만으로 띄우면 옆을 스쳐 지나가는 사람에게도 뜬다.
  final int boardingApproachUpdates;

  /// 배너를 띄운 뒤 수직 이동 근거 없이 기다리는 최대 시간. 넘으면 취소한다.
  final int boardingPhaseTimeoutMs;

  /// "지금 실제로 오르내리는 중"으로 보는 최소 수직 속도(m/s). 누적 고도가
  /// [minDeltaM]에 닿기 **전에** 걸음을 멈추기 위한 근거이고, 층은 안 바꾼다.
  final double minVerticalSpeedMps;

  /// 단일 기압 튐을 배제하려고 같은 방향이 이어져야 하는 시간(iOS 2샘플 길이).
  /// 개수로 적으면 Android 0.36초가 되어 걷는 중 노이즈로도 마커가 멈춘다.
  final int verticalMotionMinMs;

  /// 노드 근접 없이 **걸음을 멈추는** 갈래의 누적 고도 변화(m).
  ///
  /// [minDeltaM]과 값은 같지만 하는 일이 다르다 — 이쪽은 마커 정지까지고, 도면
  /// 교체는 그 위에 노드 허가와 램프 일관성을 더 요구한다.
  final double visibleVerticalDeltaM;

  /// 탑승점이 정해져 있어도 2차로 올리기 전에 요구하는 최소 수직 변화(m).
  /// 속도만 보면 노이즈 한 번에 단계가 올라간다(실기기: "걸을 때 위치가 계속 뒤로
  /// 순간이동").
  final double minVisibleRiseM;

  /// 노드를 못 고른 채 열린 2차 단계를 접는 "수직 속도 없음" 유지 시간.
  /// 없으면 [boardingPhaseTimeoutMs] 40초 동안 걸음이 멈춘 채 화면이 덮여 있다.
  final int earlyVerticalQuietMs;
}

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

/// 기압 시계열 + 에스컬레이터 노드 근접으로 층 이동을 판정하는 상태기.
///
/// 입력은 두 갈래다. [updateContext]·[onPosition]이 "지금 어느 층의 어느
/// 에스컬레이터 근처인가"를 알려주고, [onAltitude]가 기압을 넣으며 판정한다.
class EscalatorTransitionDetector {
  EscalatorTransitionDetector({
    this.config = const EscalatorDetectorConfig(),
    this.maxEvents = 200,
  });

  final EscalatorDetectorConfig config;

  /// 진단 이벤트 보관 상한. 넘으면 오래된 쪽을 버린다.
  final int maxEvents;

  // 컨텍스트.
  String? _floorLabel;
  FloorGraph? _graph;
  List<String> _floorLabels = const [];
  List<_EscalatorNode> _escalatorNodes = const [];

  // 기압 상태.
  final List<AltitudeSample> _window = [];
  final List<_Smoothed> _smoothedHistory = [];
  double? _baselineM;
  double? _lastSmoothedM;

  // 허가 상태. 도착 노드나 같은 그룹의 다른 레인이 대신 허가하지 못하도록
  // 탑승 노드 id별로 보관한다.
  final Map<String, _ArmedNode> _armedNodes = {};
  final Map<String, double> _observedBoardingDistances = {};

  /// 근접이 아니라 **기압 근거로** 허가한 탑승 노드 id([_armByAltitude]).
  ///
  /// [_observedBoardingDistances]와 섞지 않는다 — 그 값은 "실제로 그만큼 가까이
  /// 갔다"는 관측이고, 배너 단계(3 m)와 근거 문자열이 그것을 그대로 믿는다.
  final Set<String> _altitudeArmedNodeIds = {};
  String? _expectedBoardingNodeId;
  String? _expectedArrivalNodeId;
  String _boardingEvidence = 'observed';
  int? _armedUntilMs;
  int _lastSteps = 0;

  /// 마지막으로 받은 보정 위치(층 local m). 기압 근거로 뒤늦게 허가할 때
  /// 후보 노드를 고르는 기준점이다([_armByAltitude]).
  PdrLocalPoint? _lastPositionM;

  /// 방금 확정한 이동의 목적 층. 화면이 그 층을 알려 올 때 "설명되는 층 변경"
  /// 임을 알아보고 baseline·기압 창을 지키기 위한 표식이다. 한 번 쓰면 비운다.
  String? _confirmedToFloorLabel;

  // 후보 상태.
  int? _candidateStartMs;
  int _candidateSign = 0;
  int _candidateStartSteps = 0;
  _EscalatorNode? _candidateBoarding;
  String? _candidateToFloor;

  // 중앙값 평활보다 빠른 하차 판정 상태.
  double? _fastAltitudeM;
  int? _lastFastAltitudeAtMs;

  /// 빠른 EMA의 최근 이력. 수직 속도를 [EscalatorDetectorConfig.fastSlopeBaseMs]
  /// 이상 떨어진 값과 비교해 재기 위해 들고 있다.
  final List<_Smoothed> _fastHistory = [];

  /// 저속이 이어지기 시작한 시각. 저속이 끊기면 null.
  int? _fastExitQuietSinceMs;
  int _lastAltitudeSteps = 0;

  /// 위치 적용과 무관한 원시 움직임 누적. 걸음 pause 중에도 늘어난다.
  int _rawMotionCount = 0;
  int _lastAltitudeRawMotionCount = 0;

  /// 원시 움직임 중 **네이티브 걸음만** 센 것. 발판 진동(accel peak)은 여기
  /// 안 들어간다 — 진동은 "기기가 움직이는 중"의 근거는 되지만 "하차 후 첫
  /// 걸음"의 근거는 못 된다. 2026-08-13 Samsung 실측에서 진동이 걸음으로
  /// 인정돼 탑승 중간(층고의 65%)에 하차가 확정됐다.
  int _rawStepCount = 0;
  int _lastAltitudeRawStepCount = 0;

  /// 확정 직후 수직 이동이 멎을 때까지 새 후보를 열지 않는 잠금.
  /// 없으면 남은 이동분이 **유령 후보**로 다시 열린다(이중 층 전환의 정체).
  bool _awaitingPostConfirmQuiet = false;
  int? _postConfirmQuietSinceMs;

  // UI가 "층은 먼저 바꾸고 마커는 고정"하는 두 단계 전환을 적용할 수 있도록
  // 후보 시작/취소 신호를 한 번씩 보관한다. 최종 확정은 onAltitude 반환값이다.
  EscalatorTransition? _startedTransition;
  EscalatorTransition? _cancelledTransition;
  EscalatorTransition? _pendingTransition;

  // 공개 단계 상태.
  EscalatorPhase _phase = EscalatorPhase.idle;
  int? _phaseEnteredAtMs;
  final List<EscalatorPhaseChange> _phaseChanges = [];

  // 탑승점 접근 상태(배너 근거). 위치 갱신에서만 갱신한다.
  double? _lastApproachDistanceM;
  int _approachDecreaseUpdates = 0;
  int? _lastApproachSteps;
  _EscalatorNode? _approachBoarding;

  /// 내리자마자 다음 에스컬레이터를 타는 구간인지(안내가 알려 준다). 이때는 걸을
  /// 거리가 없어 오탐 여지도 없으므로 "얼마나 올랐는지"를 기다리지 않는다.
  bool _immediateTransfer = false;

  // 수직 이동 상태(걸음 pause 근거). 시각으로 들고 있다 — 개수로 세면 같은
  // 조건이 기기 주기에 따라 5배 다른 시간을 뜻하게 된다.
  int? _verticalMotionSinceMs;
  int _verticalMotionSign = 0;

  /// 지금 걸음을 멈춘 단계가 **노드 허가 없이** 열린 것인지. 하차를 확정할
  /// 수단이 없으므로, 수직 이동이 멎는 즉시 접어야 한다.
  bool _earlyVerticalMotion = false;
  int? _verticalMotionQuietSinceMs;

  /// 1차 감지 — 수직 속도가 잡혔다. **화면에는 알리지 않는다.** 디버그 칩이
  /// "왜 아직 탑승으로 안 넘어가는가"를 볼 수 있게만 내놓는다.
  bool _verticalMotionObserved = false;

  /// 같은 방향으로 이어지는 동안 빠른 EMA 속도를 적분한 변위(m). 중앙값 delta와
  /// 같은 것을 재지만 약 1초 덜 늦어, 걸음 정지를 그만큼 일찍 건다.
  ///
  /// 방향이 바뀌거나 속도가 문턱 아래면 0으로 되돌린다.
  /// **층을 바꾸는 판정에는 쓰지 않는다** — 되돌릴 수 없는 쪽은 중앙값을 쓴다.
  double _fastDisplacementM = 0;

  final List<EscalatorDetectionEvent> _events = [];

  /// 디버그 오버레이·로그용 현재 관측값.
  double? get baselineM => _baselineM;
  double? get smoothedAltitudeM => _lastSmoothedM;
  double? get deltaM => (_baselineM == null || _lastSmoothedM == null)
      ? null
      : _lastSmoothedM! - _baselineM!;
  bool get isArmed => _armedNodes.isNotEmpty;

  /// 1차 감지가 서 있는지 — 수직 속도는 잡혔지만 아직 사용자에게 알리지 않은
  /// 상태. 진단용이다(왜 아직 탑승 단계로 안 넘어가는지 읽는다).
  bool get isVerticalMotionObserved => _verticalMotionObserved;
  bool get hasCandidate => _candidateStartMs != null;
  EscalatorTransition? get pendingTransition => _pendingTransition;

  EscalatorTransition? takeStartedTransition() {
    final transition = _startedTransition;
    _startedTransition = null;
    return transition;
  }

  EscalatorTransition? takeCancelledTransition() {
    final transition = _cancelledTransition;
    _cancelledTransition = null;
    return transition;
  }

  /// 지금 공개 단계.
  EscalatorPhase get phase => _phase;

  /// 기록된 단계 전이를 비우며 가져간다. UI는 이 순서대로 적용한다.
  List<EscalatorPhaseChange> takePhaseChanges() {
    final drained = List<EscalatorPhaseChange>.unmodifiable(_phaseChanges);
    _phaseChanges.clear();
    return drained;
  }

  /// 기록된 진단 이벤트를 비우며 가져간다.
  List<EscalatorDetectionEvent> takeEvents() {
    final drained = List<EscalatorDetectionEvent>.unmodifiable(_events);
    _events.clear();
    return drained;
  }

  /// 층·그래프·층 목록을 갱신한다.
  ///
  /// **설명되지 않는** 층 변경(층 선택기·계단·엘리베이터)이면 baseline과 허가·후보를
  /// 전부 버리고, **이 판정기가 방금 확정한 이동**이면 아무것도 버리지 않는다.
  ///
  /// 탑승 중(`pendingTransition != null`)에는 호출자가 이 함수를 부르지 않는다 —
  /// 부르면 남은 반 층이 **또 하나의 층 이동**으로 보인다(근거: 실측 함정 4).
  void updateContext({
    required String? floorLabel,
    required FloorGraph? graph,
    required List<String> floorLabels,
  }) {
    _floorLabels = floorLabels;
    final floorChanged = floorLabel != _floorLabel;
    final graphChanged = !identical(graph, _graph);
    _floorLabel = floorLabel;
    if (graphChanged) {
      _graph = graph;
      _escalatorNodes = _parseEscalatorNodes(graph);
    }
    if (!floorChanged) return;
    if (floorLabel != null && floorLabel == _confirmedToFloorLabel) {
      _confirmedToFloorLabel = null;
      return;
    }
    _resetForNewFloor();
  }

  /// 보정된 현재 위치를 넣어 허가 상태를 갱신한다.
  ///
  /// [positionM]은 층 `local_m` 좌표(복도 보정 결과)여야 한다. 원시 PDR 좌표를
  /// 넣으면 노드 근접 판정이 앵커 오차만큼 어긋난다.
  void onPosition({
    required PdrLocalPoint positionM,
    required int steps,
    required int timestampMs,
  }) {
    _lastSteps = steps;
    _lastPositionM = positionM;
    if (_escalatorNodes.isEmpty) return;

    var armedNow = false;
    for (final node in _escalatorNodes) {
      if (node.name.role != EscalatorNodeRole.boarding) continue;
      final distance = math.sqrt(
        math.pow(positionM.eastM - node.xM, 2) +
            math.pow(positionM.northM - node.yM, 2),
      );
      if (distance > config.armRadiusM) continue;
      armedNow = true;
      final existing = _armedNodes[node.id];
      if (existing == null || distance < existing.distanceM) {
        _armedNodes[node.id] = _ArmedNode(
          nodeId: node.id,
          distanceM: distance,
          atMs: timestampMs,
        );
      }
      final observedDistance = _observedBoardingDistances[node.id];
      if (observedDistance == null || distance < observedDistance) {
        _observedBoardingDistances[node.id] = distance;
      }
    }
    if (armedNow) {
      final wasArmed = _armedUntilMs != null && timestampMs <= _armedUntilMs!;
      _armedUntilMs = timestampMs + config.armHoldMs;
      if (!wasArmed) {
        _pushEvent(
          atMs: timestampMs,
          kind: 'armed',
          reason: _armedNodes.keys.join(','),
        );
      }
    }
  }

  /// 활성 다층 경로의 마지막 점이 탑승점일 때 쓰는 보조 허가. 경로에서 나온
  /// 탑승점이라는 근거가 강해 위치 보정이 늦어도 허가한다(수동 이동에는 안 쓴다).
  void onEscalatorRouteApproach({
    required PdrLocalPoint positionM,
    required PdrLocalPoint routeEndM,
    required String expectedBoardingNodeId,
    String? expectedArrivalNodeId,
    required int steps,
    required int timestampMs,
    bool immediateTransfer = false,
  }) {
    final approachDistance = (positionM - routeEndM).distance;
    if (approachDistance > config.routeApproachArmRadiusM) {
      _resetApproach();
      return;
    }
    _lastSteps = steps;
    final expected = _escalatorNodes
        .where(
          (node) =>
              node.id == expectedBoardingNodeId &&
              node.name.role == EscalatorNodeRole.boarding,
        )
        .firstOrNull;
    if (expected == null) return;
    _expectedBoardingNodeId = expectedBoardingNodeId;
    _expectedArrivalNodeId = expectedArrivalNodeId;
    _approachBoarding = expected;
    _immediateTransfer = immediateTransfer;
    _armedNodes[expected.id] = _ArmedNode(
      nodeId: expected.id,
      distanceM: approachDistance,
      atMs: timestampMs,
    );
    _armedUntilMs = timestampMs + config.armHoldMs;
    _updateBoardingApproach(
      approachDistanceM: approachDistance,
      steps: steps,
      timestampMs: timestampMs,
      expectedArrivalNodeId: expectedArrivalNodeId,
      boarding: expected,
    );
  }

  /// 탑승점까지 남은 거리가 실제로 **줄고 있을 때만** 배너 단계로 올린다.
  /// 거리 하나로 판정하면 옆을 지나가는 사람에게도 뜬다.
  void _updateBoardingApproach({
    required double approachDistanceM,
    required int steps,
    required int timestampMs,
    required String? expectedArrivalNodeId,
    required _EscalatorNode boarding,
  }) {
    if (_phase != EscalatorPhase.idle &&
        _phase != EscalatorPhase.boardingDetected) {
      return;
    }
    if (_lastApproachSteps != steps) {
      final previous = _lastApproachDistanceM;
      if (previous != null && approachDistanceM < previous - 0.2) {
        _approachDecreaseUpdates++;
      } else if (previous != null && approachDistanceM > previous + 0.5) {
        // 다시 멀어졌다. 근거를 처음부터 다시 모은다.
        _approachDecreaseUpdates = 0;
        if (_phase == EscalatorPhase.boardingDetected) {
          _setPhase(
            EscalatorPhase.cancelled,
            atMs: timestampMs,
            reason: 'movedAwayFromBoarding',
          );
        }
      }
      _lastApproachDistanceM = approachDistanceM;
      _lastApproachSteps = steps;
    }
    if (_phase == EscalatorPhase.boardingDetected) return;
    if (approachDistanceM > config.boardingApproachRadiusM) return;
    if (_approachDecreaseUpdates < config.boardingApproachUpdates) return;
    final toFloor = boarding.name.otherFloorLabel;
    if (_floorLabels.isNotEmpty && !_floorLabels.contains(toFloor)) return;
    _setPhase(
      EscalatorPhase.boardingDetected,
      atMs: timestampMs,
      reason: 'routeApproach',
      toFloorLabel: toFloor,
      group: boarding.name.group,
      direction: boarding.name.direction,
      boardingNodeId: boarding.id,
      expectedArrivalNodeId: expectedArrivalNodeId,
    );
  }

  void _resetApproach() {
    _lastApproachDistanceM = null;
    _lastApproachSteps = null;
    _approachDecreaseUpdates = 0;
    _approachBoarding = null;
    _immediateTransfer = false;
  }

  void _setPhase(
    EscalatorPhase phase, {
    required int atMs,
    required String reason,
    String? toFloorLabel,
    String? group,
    EscalatorDirection? direction,
    String? boardingNodeId,
    String? expectedArrivalNodeId,
    double deltaM = 0,
    EscalatorTransition? transition,
  }) {
    if (_phase == phase) return;
    _phase = phase;
    _phaseEnteredAtMs = atMs;
    if (phase == EscalatorPhase.cancelled ||
        phase == EscalatorPhase.failed ||
        phase == EscalatorPhase.landed) {
      _resetApproach();
      _verticalMotionSinceMs = null;
      _verticalMotionSign = 0;
      _verticalMotionObserved = false;
      _fastDisplacementM = 0;
      _earlyVerticalMotion = false;
      _verticalMotionQuietSinceMs = null;
      _phase = EscalatorPhase.idle;
    }
    _phaseChanges.add(
      EscalatorPhaseChange(
        phase: phase,
        atMs: atMs,
        fromFloorLabel: _floorLabel ?? '',
        reason: reason,
        toFloorLabel: toFloorLabel,
        group: group,
        direction: direction,
        boardingNodeId: boardingNodeId,
        expectedArrivalNodeId: expectedArrivalNodeId,
        deltaM: deltaM,
        transition: transition,
      ),
    );
  }

  /// 위치에 반영되지 않은 원시 움직임을 넣는다. 탑승 중에는 [onPosition]의
  /// `steps`가 안 늘어 하차 빠른 확정이 안 돌기 때문이고, 이 신호는 pause와
  /// 무관하게 흐른다. 수직 속도가 낮을 때만 쓰여 진동 peak로는 재개되지 않는다.
  void onRawMotion(RawMotionActivity activity) {
    if (!activity.hasMotion) return;
    _rawMotionCount +=
        activity.accelPeakDelta + (activity.nativeStepDelta ?? 0);
    _rawStepCount += activity.nativeStepDelta ?? 0;
  }

  /// 기압 샘플을 넣고 판정한다. 층 이동이 확정된 순간에만 non-null.
  ///
  /// 아래 단계 여섯이 순서대로 흐르고 **순서가 곧 의미다.** 1이 3보다 먼저인 이유는
  /// 2가 EMA 상태를 지우기 때문이다 — 직전 EMA 값은 맨 처음에 붙잡아 3으로 넘긴다.
  EscalatorTransition? onAltitude(AltitudeSample sample) {
    final previousFast = (
      altitudeM: _fastAltitudeM,
      atMs: _lastFastAltitudeAtMs,
    );
    final motion = _takeMotionEvidence();
    final timelineGap = _clearOnTimelineGap(sample);
    final fast = _updateFastAltitude(
      sample,
      previous: previousFast,
      timelineGap: timelineGap,
    );

    final smoothed = _pushAndSmooth(sample);
    if (smoothed == null) return null;

    _baselineM ??= smoothed;
    final armed = _refreshArm(sample.timestampMs);
    final delta = smoothed - _baselineM!;

    if (_candidateStartMs == null && _awaitingPostConfirmQuiet) {
      return _absorbPostConfirmDrift(sample, smoothed: smoothed, fast: fast);
    }
    if (_candidateStartMs == null) {
      return _openCandidate(
        sample,
        smoothed: smoothed,
        delta: delta,
        armed: armed,
        fast: fast,
        motion: motion,
      );
    }
    return _advanceCandidate(
      sample,
      smoothed: smoothed,
      delta: delta,
      fast: fast,
      motion: motion,
    );
  }

  // ── onAltitude의 단계들 ──
  //
  // 전부 onAltitude에서만 부른다. 재사용이 아니라 한 함수 331줄을 읽을 수 없어서
  // 뗀 것이고, 상태 필드는 그대로 공유한다(축자 이동이라야 무회귀를 증명한다).

  /// 1) 직전 샘플 이후 걸음·진동이 새로 들어왔는지 읽고, 카운터를 갱신한다.
  ({bool hadNewSteps, bool hadMotionEvidence}) _takeMotionEvidence() {
    // "하차 후 첫 걸음"은 위치에 적용된 걸음 **또는 네이티브 걸음**만 인정한다.
    // 발판 진동을 걸음으로 치면 탑승 중간에 확정된다(실측 함정 2).
    final hadNewSteps =
        _lastSteps > _lastAltitudeSteps ||
        _rawStepCount > _lastAltitudeRawStepCount;
    // 진동까지 포함한 "기기가 실제로 움직이는 중" 근거. 걸음 pause 갈래에서만
    // 쓴다 — 그쪽은 책상 위 기압 드리프트를 거르는 용도라 진동도 근거가 된다.
    final hadMotionEvidence =
        hadNewSteps || _rawMotionCount > _lastAltitudeRawMotionCount;
    _lastAltitudeSteps = _lastSteps;
    _lastAltitudeRawMotionCount = _rawMotionCount;
    _lastAltitudeRawStepCount = _rawStepCount;
    return (hadNewSteps: hadNewSteps, hadMotionEvidence: hadMotionEvidence);
  }

  /// 2) 시계열이 끊겼으면(background 복귀 등) 이전 관측을 통째로 버린다.
  ///
  /// 공백 동안 층이 바뀌었을 수 있어 baseline과 후보도 함께 무효다.
  bool _clearOnTimelineGap(AltitudeSample sample) {
    final previous = _window.isEmpty ? null : _window.last;
    final timelineGap =
        previous != null &&
        sample.timestampMs - previous.timestampMs > config.maxSampleAgeMs;
    if (timelineGap) {
      _window.clear();
      _smoothedHistory.clear();
      _baselineM = null;
      _lastSmoothedM = null;
      _candidateStartMs = null;
      _candidateSign = 0;
      _candidateBoarding = null;
      _candidateToFloor = null;
      _pendingTransition = null;
      _fastAltitudeM = null;
      _lastFastAltitudeAtMs = null;
      _fastHistory.clear();
      _fastExitQuietSinceMs = null;
      _awaitingPostConfirmQuiet = false;
      _postConfirmQuietSinceMs = null;
    }
    return timelineGap;
  }

  /// 3) 저지연 EMA를 갱신하고, 이 샘플의 이동량과 수직 속도를 낸다.
  ({double stepM, double? speedMps}) _updateFastAltitude(
    AltitudeSample sample, {
    required ({double? altitudeM, int? atMs}) previous,
    required bool timelineGap,
  }) {
    final rawAltitude = sample.altitudeM;
    // EMA 계수를 **경과 시간에서 만든다.** 샘플당 고정 계수를 쓰면 같은 숫자가
    // iOS(1069ms)에서는 시정수 1초, Android(180ms)에서는 0.2초짜리 필터가 된다.
    final fastDeltaSeconds = timelineGap || previous.atMs == null
        ? null
        : (sample.timestampMs - previous.atMs!) / 1000.0;
    final alpha = fastDeltaSeconds == null || fastDeltaSeconds <= 0
        ? 1.0
        : 1 - math.exp(-fastDeltaSeconds * 1000 / config.fastAltitudeTauMs);
    _fastAltitudeM = _fastAltitudeM == null
        ? rawAltitude
        : _fastAltitudeM! + alpha * (rawAltitude - _fastAltitudeM!);
    _lastFastAltitudeAtMs = sample.timestampMs;
    // 이 샘플에서 실제로 움직인 양. 적분(_fastDisplacementM)은 이 값을 그대로
    // 더해 망원합이 되므로, 아래 속도가 어떤 밑변으로 재지든 영향받지 않는다.
    final fastStepM = previous.altitudeM == null || fastDeltaSeconds == null
        ? 0.0
        : _fastAltitudeM! - previous.altitudeM!;
    _fastHistory.add(_Smoothed(sample.timestampMs, _fastAltitudeM!));
    return (stepM: fastStepM, speedMps: _fastSpeedOver(sample.timestampMs));
  }

  /// 4) 샘플을 창에 넣고 중앙값으로 평활한다. 근거가 모자라면 null.
  double? _pushAndSmooth(AltitudeSample sample) {
    _window.add(sample);
    // 시간 창으로 자르되 최근 minSmoothingSamples개는 항상 남긴다. 센서
    // 주기가 창 대비 크면(iOS 1069ms) 창만으로는 개수를 못 채운다.
    final windowStart = sample.timestampMs - config.smoothingWindowMs;
    while (_window.length > config.minSmoothingSamples &&
        _window.first.timestampMs < windowStart) {
      _window.removeAt(0);
    }
    if (_window.length < config.minSmoothingSamples) {
      // 아직 평활할 근거가 없다. 디버그 표시가 지난 값을 "지금 관측"으로
      // 보이지 않도록 비워 둔다.
      _lastSmoothedM = null;
      return null;
    }

    final smoothed = _median(
      _window.map((item) => item.altitudeM).toList(growable: false),
    );
    _lastSmoothedM = smoothed;
    _smoothedHistory.add(_Smoothed(sample.timestampMs, smoothed));
    // 안정 판단은 settleWindow만 보면 되지만, 타임아웃 구간까지 넉넉히 남긴다.
    final historyStart =
        sample.timestampMs - config.candidateTimeoutMs - config.settleWindowMs;
    _smoothedHistory.removeWhere((item) => item.atMs < historyStart);
    return smoothed;
  }

  /// 허가가 살아 있는지 보고, 만료됐으면 근접 관측을 비운다.
  bool _refreshArm(int atMs) {
    final armed = _armedUntilMs != null && atMs <= _armedUntilMs!;
    if (!armed) {
      _armedNodes.clear();
      _observedBoardingDistances.clear();
      _altitudeArmedNodeIds.clear();
    }
    return armed;
  }

  /// 5) 확정 직후 잠금 구간. 하차가 실제로 끝나면 그 자리 고도로 0점을 다시 잡는다.
  EscalatorTransition? _absorbPostConfirmDrift(
    AltitudeSample sample, {
    required double smoothed,
    required ({double stepM, double? speedMps}) fast,
  }) {
    final speed = fast.speedMps;
    // 확정이 하차보다 일렀다면 지금도 오르내리는 중이고, 그 잔여 이동분으로
    // 후보를 열면 한 층이 두 층이 된다. 저속이 이어져 "멎었다"가 확인되는
    // 순간, 그 자리 고도로 0점을 다시 잡아 잔여분을 통째로 흡수한다.
    final quietNow = speed != null && speed.abs() < config.minVerticalSpeedMps;
    if (quietNow) {
      final since = _postConfirmQuietSinceMs ??= sample.timestampMs;
      if (sample.timestampMs - since >= config.earlyVerticalQuietMs) {
        _baselineM = smoothed;
        _awaitingPostConfirmQuiet = false;
        _postConfirmQuietSinceMs = null;
      }
    } else {
      _postConfirmQuietSinceMs = null;
    }
    return null;
  }

  /// 6a) 후보가 없는 구간. baseline을 드리프트에 맞추고, 근거가 다 모이면 후보를 연다.
  EscalatorTransition? _openCandidate(
    AltitudeSample sample, {
    required double smoothed,
    required double delta,
    required bool armed,
    required ({double stepM, double? speedMps}) fast,
    required ({bool hadNewSteps, bool hadMotionEvidence}) motion,
  }) {
    final speed = fast.speedMps;
    // 허가도 후보도 없는 구간에서만 baseline이 기상 드리프트를 따라간다.
    if (!armed) _trackBaselineDrift(delta, speed: speed);
    // **허가가 없어도 걸음은 멈춘다.** 노드 근접이 안 잡히는 랜딩이 실측에서 흔했고,
    // 그때 사용자는 이미 에스컬레이터 위인데 마커만 계속 걸어갔다.
    _updateVerticalMotion(
      sample.timestampMs,
      speed,
      fastStepM: fast.stepM,
      deltaM: delta,
      hasMotionEvidence: motion.hadMotionEvidence,
    );
    _expireStalledPhase(
      sample.timestampMs,
      reason: armed ? 'noVerticalMotion' : 'armExpired',
    );
    if (!armed) return null;

    if (delta.abs() < config.minDeltaM) return null;
    // 누적 변화량 + 지금도 그 방향으로 움직이는 중일 때만 후보를 연다.
    final rise = _riseOver(sample.timestampMs, smoothed);
    if (rise == null) return null;
    final sign = delta > 0 ? 1 : -1;
    if (rise * sign < config.minRampRiseM) return null;
    if (!_hasConsistentRamp(sample.timestampMs, sign)) return null;
    _candidateStartMs = sample.timestampMs;
    _candidateSign = sign;
    _candidateStartSteps = _lastSteps;
    _fastExitQuietSinceMs = null;
    _pushEvent(
      atMs: sample.timestampMs,
      kind: 'candidate',
      reason: _candidateSign > 0 ? 'rising' : 'falling',
      deltaM: delta,
    );

    final direction = sign > 0
        ? EscalatorDirection.up
        : EscalatorDirection.down;
    final boarding = _pickBoardingNode(direction);
    final fromFloor = _floorLabel;
    if (fromFloor == null || boarding == null) {
      _closeCandidate(
        atMs: sample.timestampMs,
        reason: 'noBoardingNode',
        deltaM: delta,
        elapsedMs: 0,
      );
      return null;
    }
    final toFloor = boarding.name.otherFloorLabel;
    if (_floorLabels.isNotEmpty && !_floorLabels.contains(toFloor)) {
      _closeCandidate(
        atMs: sample.timestampMs,
        reason: 'unknownTargetFloor',
        deltaM: delta,
        elapsedMs: 0,
        toFloorLabel: toFloor,
        group: boarding.name.group,
      );
      return null;
    }
    _candidateBoarding = boarding;
    _candidateToFloor = toFloor;
    // 후보는 여기서 열리지만 조기 층 전환(도면 교체) 신호는 아직 내지 않는다.
    // 그 신호는 [_advanceCandidate]에서 [mapSwapDeltaM]에 닿을 때 나간다.
    return null;
  }

  /// 6b) 후보가 열려 있는 구간. 기각하거나, 반 층에서 도면을 갈거나, 확정한다.
  EscalatorTransition? _advanceCandidate(
    AltitudeSample sample, {
    required double smoothed,
    required double delta,
    required ({double stepM, double? speedMps}) fast,
    required ({bool hadNewSteps, bool hadMotionEvidence}) motion,
  }) {
    final elapsedMs = sample.timestampMs - _candidateStartMs!;
    if (_rejectCandidate(
      sample,
      delta: delta,
      smoothed: smoothed,
      elapsedMs: elapsedMs,
    )) {
      return null;
    }
    _emitMidpointIfReached(sample, delta: delta, elapsedMs: elapsedMs);
    return _confirmIfSettled(
      sample,
      smoothed: smoothed,
      delta: delta,
      elapsedMs: elapsedMs,
      fast: fast,
      motion: motion,
    );
  }

  /// baseline이 기상 드리프트를 천천히 따라가게 한다.
  ///
  /// **지금 실제로 오르내리는 중이면 따라가지 않는다** — 허가 전 구간의 변화가
  /// 흡수되면 이미 반쯤 내려온 사용자가 문턱을 처음부터 다시 채운다(실측 함정 3).
  void _trackBaselineDrift(double delta, {required double? speed}) {
    final movingVertically =
        speed != null && speed.abs() >= config.minVerticalSpeedMps;
    if (movingVertically) return;
    _baselineM = _baselineM! + config.baselineTrackAlpha * delta;
  }

  /// 후보를 접어야 하는 세 경우. 접었으면 true.
  ///
  /// 셋 다 **거부가 안전한 쪽**이라는 같은 판단에서 나온다 — 이 파일 맨 위
  /// 설계 원칙 1번(오탐 비용 > 미탐 비용)이 여기서 세 번 적용된다.
  bool _rejectCandidate(
    AltitudeSample sample, {
    required double delta,
    required double smoothed,
    required int elapsedMs,
  }) {
    // 부호가 뒤집혔거나 baseline 근처로 돌아왔다 = 층을 옮긴 게 아니다.
    if (delta * _candidateSign < config.minDeltaM * 0.5) {
      _closeCandidate(
        atMs: sample.timestampMs,
        reason: 'reverted',
        deltaM: delta,
        elapsedMs: elapsedMs,
      );
      return true;
    }

    if (delta.abs() >= config.multiFloorRejectM) {
      // 여러 층을 한 번에 이동했다. 몇 층인지 추정하려면 층고 가정이 필요하고,
      // 그 가정이 틀리면 2층 어긋난 위치를 조용히 보여준다. 거부가 안전하다.
      _closeCandidate(
        atMs: sample.timestampMs,
        reason: 'multiFloorUnsupported',
        deltaM: delta,
        elapsedMs: elapsedMs,
        rebaselineTo: smoothed,
      );
      return true;
    }

    if (elapsedMs > config.candidateTimeoutMs) {
      _closeCandidate(
        atMs: sample.timestampMs,
        reason: 'noSettle',
        deltaM: delta,
        elapsedMs: elapsedMs,
        rebaselineTo: smoothed,
      );
      return true;
    }
    return false;
  }

  /// 반 층 부근에서 조기 층 전환 신호(도면 교체)를 낸다.
  ///
  /// 후보 열림과 분리한 근거는 [EscalatorDetectorConfig.mapSwapDeltaM]에 적었다.
  void _emitMidpointIfReached(
    AltitudeSample sample, {
    required double delta,
    required int elapsedMs,
  }) {
    if (_pendingTransition != null) return;
    if (delta.abs() < config.mapSwapDeltaM) return;
    if (delta * _candidateSign <= 0) return;

    final boarding = _candidateBoarding;
    final fromFloor = _floorLabel;
    final toFloor = _candidateToFloor;
    if (boarding == null || fromFloor == null || toFloor == null) return;

    final direction = _candidateSign > 0
        ? EscalatorDirection.up
        : EscalatorDirection.down;
    final started = _buildTransition(
      boarding: boarding,
      direction: direction,
      fromFloor: fromFloor,
      toFloor: toFloor,
      deltaM: delta,
      elapsedMs: elapsedMs,
    );
    _pendingTransition = started;
    _startedTransition = started;
    _setPhase(
      EscalatorPhase.midpointReached,
      atMs: sample.timestampMs,
      reason: _candidateSign > 0 ? 'rising' : 'falling',
      toFloorLabel: toFloor,
      group: boarding.name.group,
      direction: direction,
      boardingNodeId: boarding.id,
      expectedArrivalNodeId: started.expectedArrivalNodeId,
      deltaM: delta,
      transition: started,
    );
  }

  /// 하차가 끝났다고 볼 근거가 모이면 확정한다. 아니면 null.
  EscalatorTransition? _confirmIfSettled(
    AltitudeSample sample, {
    required double smoothed,
    required double delta,
    required int elapsedMs,
    required ({double stepM, double? speedMps}) fast,
    required ({bool hadNewSteps, bool hadMotionEvidence}) motion,
  }) {
    if (elapsedMs < config.minRampMs) return null;
    if (delta.abs() < config.minConfirmDeltaM) return null;

    // 중앙값 settle 창보다 먼저, 저지연 EMA 속도가 잦아드는 순간을 잡는다. 하차 뒤
    // 첫 걸음이 오면 즉시, 없으면 [fastExitQuietMs] 동안 저속이 유지될 때 확정한다.
    // 속도 자체가 이미 시간 밑변 위의 값이라([_fastSpeedOver]) 센서 주기와 무관하다.
    final speed = fast.speedMps;
    if (speed != null) {
      final slopeLimit = motion.hadNewSteps
          ? config.fastExitWithStepSlopeMps
          : config.fastExitSlopeMps;
      if (speed.abs() <= slopeLimit) {
        _fastExitQuietSinceMs ??= sample.timestampMs;
      } else {
        _fastExitQuietSinceMs = null;
      }
      final quietSince = _fastExitQuietSinceMs;
      final fastSettled =
          quietSince != null &&
          (motion.hadNewSteps ||
              sample.timestampMs - quietSince >= config.fastExitQuietMs);
      if (fastSettled) {
        return _confirm(
          atMs: sample.timestampMs,
          smoothed: smoothed,
          deltaM: delta,
          elapsedMs: elapsedMs,
        );
      }
    }

    // fast EMA가 준비된 뒤에는 중앙값 창의 꼭대기를 정지로 오인하지 않는다.
    // 실제 하차는 저속 샘플이 연속되지만, 올라갔다 바로 내려오는 삼각형
    // 움직임은 방향 전환 지점의 한 샘플만 평평해질 수 있다.
    if (speed == null && _hasSettled(sample.timestampMs, smoothed)) {
      return _confirm(
        atMs: sample.timestampMs,
        smoothed: smoothed,
        deltaM: delta,
        elapsedMs: elapsedMs,
      );
    }
    return null;
  }

  // ── 내부 ──

  EscalatorTransition? _confirm({
    required int atMs,
    required double smoothed,
    required double deltaM,
    required int elapsedMs,
  }) {
    final direction = _candidateSign > 0
        ? EscalatorDirection.up
        : EscalatorDirection.down;
    final fromFloor = _floorLabel;
    final boarding = _candidateBoarding;

    if (fromFloor == null || boarding == null || _candidateToFloor == null) {
      // 기압은 층 이동이라 말하는데 그 방향의 탑승 노드가 허가된 그룹에 없다.
      // 반대 방향 에스컬레이터 옆을 지나간 경우이거나 이름 규칙이 없는 데이터다.
      _closeCandidate(
        atMs: atMs,
        reason: 'noBoardingNode',
        deltaM: deltaM,
        elapsedMs: elapsedMs,
        rebaselineTo: smoothed,
      );
      return null;
    }

    final toFloor = _candidateToFloor!;
    if (_floorLabels.isNotEmpty && !_floorLabels.contains(toFloor)) {
      // 이름이 가리키는 층이 건물 층 목록에 없다 = 데이터가 어긋났다.
      _closeCandidate(
        atMs: atMs,
        reason: 'unknownTargetFloor',
        deltaM: deltaM,
        elapsedMs: elapsedMs,
        rebaselineTo: smoothed,
        toFloorLabel: toFloor,
        group: boarding.name.group,
      );
      return null;
    }

    final stepsDuring = _lastSteps - _candidateStartSteps;
    _pushEvent(
      atMs: atMs,
      kind: 'confirmed',
      reason: direction == EscalatorDirection.up ? 'up' : 'down',
      deltaM: deltaM,
      toFloorLabel: toFloor,
      group: boarding.name.group,
      durationMs: elapsedMs,
      stepsDuring: stepsDuring,
      boardingEvidence: _boardingEvidence,
    );

    final transition = _buildTransition(
      boarding: boarding,
      direction: direction,
      fromFloor: fromFloor,
      toFloor: toFloor,
      deltaM: deltaM,
      elapsedMs: elapsedMs,
      stepsDuring: stepsDuring,
    );

    // 확정했으면 새 층 기준으로 처음부터 다시 본다. **상대 고도 0점을 다시
    // 잡는 곳은 여기 하나뿐이다** — 하차가 확정된 순간이고, 그 값은 지금
    // 서 있는 층의 고도다. 이후 호출자가 updateContext로 이 층을 알려 와도
    // 초기화가 한 번 더 돌지 않도록 목적 층을 표식으로 남긴다.
    _confirmedToFloorLabel = toFloor;
    _candidateStartMs = null;
    _candidateSign = 0;
    _candidateBoarding = null;
    _candidateToFloor = null;
    _pendingTransition = null;
    _fastExitQuietSinceMs = null;
    _baselineM = smoothed;
    // 확정이 하차보다 일렀을 수 있다. 수직 이동이 실제로 멎을 때까지 새 후보를
    // 잠그고, 멎는 순간 잔여 이동분을 baseline에 흡수한다(필드 근거는 선언부).
    _awaitingPostConfirmQuiet = true;
    _postConfirmQuietSinceMs = null;
    _armedNodes.clear();
    _observedBoardingDistances.clear();
    _altitudeArmedNodeIds.clear();
    _armedUntilMs = null;
    _setPhase(
      EscalatorPhase.landed,
      atMs: atMs,
      reason: direction == EscalatorDirection.up ? 'up' : 'down',
      toFloorLabel: toFloor,
      group: boarding.name.group,
      direction: direction,
      boardingNodeId: boarding.id,
      expectedArrivalNodeId: transition.expectedArrivalNodeId,
      deltaM: deltaM,
      transition: transition,
    );
    return transition;
  }

  /// 지금 실제로 오르내리는 중인지 갱신한다. **두 겹**이다 — 1차는 조용히
  /// [isVerticalMotionObserved]만 세우고, 2차에서 비로소 걸음이 멈추고 화면이 덮인다.
  /// 어느 쪽이든 층은 바꾸지 않는다.
  void _updateVerticalMotion(
    int atMs,
    double? fastSpeedMps, {
    required double fastStepM,
    required double deltaM,
    required bool hasMotionEvidence,
  }) {
    if (fastSpeedMps == null ||
        fastSpeedMps.abs() < config.minVerticalSpeedMps) {
      _verticalMotionSinceMs = null;
      _verticalMotionSign = 0;
      _verticalMotionObserved = false;
      _fastDisplacementM = 0;
      _expireEarlyVerticalMotion(atMs);
      return;
    }
    _verticalMotionQuietSinceMs = null;
    final sign = fastSpeedMps > 0 ? 1 : -1;
    if (sign != _verticalMotionSign) {
      _verticalMotionSign = sign;
      _verticalMotionSinceMs = atMs;
      _fastDisplacementM = fastStepM;
    } else {
      _fastDisplacementM += fastStepM;
    }
    final since = _verticalMotionSinceMs;
    if (since == null || atMs - since < config.verticalMotionMinMs) {
      return;
    }
    final direction = sign > 0
        ? EscalatorDirection.up
        : EscalatorDirection.down;
    // 여기까지가 **1차 감지**다. 화면에는 아무것도 알리지 않고, 걸음도 그대로
    // 흐른다. 아래 두 갈래 중 하나가 성립해야 2차로 올라간다.
    _verticalMotionObserved = true;
    // 중앙값 delta와 빠른 EMA 적분 중 **먼저 문턱을 넘는 쪽**을 쓴다. 둘은 같은
    // 것을 재지만 중앙값이 1초 넘게 늦고, 그 1초가 곧 발판 진동이 위치에 쌓이는
    // 시간이다.
    final risenM = math.max(deltaM.abs(), _fastDisplacementM.abs());

    // 허가가 아직 없으면 **여기서** 기압 근거로 한 번 더 시도한다. 근접만으로
    // 거는 허가(6 m)는 랜딩에서 보정 위치가 어긋나면 영영 안 걸리는데, 그러면
    // 배너는 "이동 중"이라 말하면서 층은 끝까지 안 바뀐다(2026-08-17 현장).
    final boarding =
        _approachBoarding ??
        _pickBoardingNode(direction) ??
        _armByAltitude(
          direction,
          atMs: atMs,
          risenM: risenM,
          hasMotionEvidence: hasMotionEvidence,
        );
    if (_promoteAtBoardingPoint(
      boarding,
      atMs: atMs,
      sign: sign,
      direction: direction,
      risenM: risenM,
    )) {
      return;
    }
    _promoteByAltitude(
      boarding,
      atMs: atMs,
      sign: sign,
      direction: direction,
      risenM: risenM,
      deltaM: deltaM,
      hasMotionEvidence: hasMotionEvidence,
    );
  }

  /// 갈래 1 — **탑승점이 정해져 있다.** 올렸으면 true. 그래도 속도만으로는 올리지
  /// 않고 [EscalatorDetectorConfig.minVisibleRiseM]만큼 실제로 움직였는지 본다.
  bool _promoteAtBoardingPoint(
    _EscalatorNode? boarding, {
    required int atMs,
    required int sign,
    required EscalatorDirection direction,
    required double risenM,
  }) {
    if (boarding == null || boarding.name.direction != direction) return false;
    final distanceM =
        _observedBoardingDistances[boarding.id] ??
        _armedNodes[boarding.id]?.distanceM;
    final atBoardingPoint =
        _approachBoarding != null ||
        (distanceM != null && distanceM <= config.boardingApproachRadiusM);
    // 연속 환승(내리자마자 바로 다음 에스컬레이터)에서는 최소 변화를 요구하지
    // 않는다. 걸어갈 거리가 없어 오탐 여지도 없고, 기다리면 환승마다 마커가
    // 먼저 몇 걸음 흘러간다.
    final requiredRiseM = _immediateTransfer && _approachBoarding != null
        ? 0.0
        : config.minVisibleRiseM;
    if (!atBoardingPoint || risenM < requiredRiseM) return false;

    _earlyVerticalMotion = false;
    _setPhase(
      EscalatorPhase.verticalMotionDetected,
      atMs: atMs,
      reason: sign > 0 ? 'rising' : 'falling',
      toFloorLabel: boarding.name.otherFloorLabel,
      group: boarding.name.group,
      direction: direction,
      boardingNodeId: boarding.id,
      expectedArrivalNodeId: boarding.id == _expectedBoardingNodeId
          ? _expectedArrivalNodeId
          : null,
    );
    return true;
  }

  /// 갈래 2 — **이미 사람이 오를 수 없는 만큼 올라왔다.** 노드가 없거나 멀어도
  /// 누적 고도가 [EscalatorDetectorConfig.visibleVerticalDeltaM]을 넘으면 올린다.
  /// 기기가 움직이는 중이라는 신호를 함께 요구한다 — 없으면 책상 위 폰도 덮인다.
  void _promoteByAltitude(
    _EscalatorNode? boarding, {
    required int atMs,
    required int sign,
    required EscalatorDirection direction,
    required double risenM,
    required double deltaM,
    required bool hasMotionEvidence,
  }) {
    if (risenM < config.visibleVerticalDeltaM) return;
    if (!hasMotionEvidence) return;
    final toFloor = (boarding != null && boarding.name.direction == direction)
        ? boarding.name.otherFloorLabel
        : _adjacentFloorLabel(direction);
    if (toFloor == null) return;
    // 노드를 못 고른 경우에는 하차를 확정할 수단이 없다 — 수직 이동이 멎으면
    // 스스로 접어야 한다([_expireEarlyVerticalMotion]).
    _earlyVerticalMotion = boarding == null;
    _verticalMotionQuietSinceMs = null;
    _setPhase(
      EscalatorPhase.verticalMotionDetected,
      atMs: atMs,
      reason: sign > 0 ? 'risingByAltitude' : 'fallingByAltitude',
      toFloorLabel: toFloor,
      group: boarding?.name.group,
      direction: direction,
      boardingNodeId: boarding?.id,
      deltaM: deltaM,
    );
  }

  /// 노드 없이 열린 단계를 수직 이동이 멎으면 접는다. 하차를 확정할 수단이 없어
  /// 그대로 두면 40초 동안 걸음이 멈춘 채 화면이 덮여 있다.
  void _expireEarlyVerticalMotion(int atMs) {
    if (!_earlyVerticalMotion) return;
    if (_phase != EscalatorPhase.verticalMotionDetected) return;
    final quietSince = _verticalMotionQuietSinceMs ??= atMs;
    if (atMs - quietSince < config.earlyVerticalQuietMs) return;
    _earlyVerticalMotion = false;
    _verticalMotionQuietSinceMs = null;
    _setPhase(
      EscalatorPhase.cancelled,
      atMs: atMs,
      reason: 'verticalMotionEnded',
    );
  }

  /// [direction] 쪽으로 한 칸 붙어 있는 층 라벨. 알 수 없으면 null.
  /// 나열 순서가 아니라 라벨 자체를 순위로 읽는다 — 서버 응답 순서는 위아래를
  /// 약속하지 않는다.
  String? _adjacentFloorLabel(EscalatorDirection direction) {
    final from = _floorLabel;
    if (from == null || _floorLabels.isEmpty) return null;
    final fromRank = floorLabelRank(from);
    if (fromRank == 0) return null;
    final step = direction == EscalatorDirection.up ? 1 : -1;
    // 지상 1층과 지하 1층 사이에는 0층이 없다.
    final targetRank = fromRank + step == 0
        ? fromRank + step * 2
        : fromRank + step;
    for (final label in _floorLabels) {
      if (floorLabelRank(label) == targetRank) return label;
    }
    return null;
  }

  /// 배너·pause 단계가 근거 없이 오래 머물면 되돌린다.
  ///
  /// 이 경로가 없으면 탑승점에 다가갔다가 그냥 지나친 사용자에게 배너가 영영
  /// 남고, `verticalMotionDetected`로 멈춘 걸음이 다시 켜지지 않는다.
  void _expireStalledPhase(int atMs, {required String reason}) {
    if (_phase != EscalatorPhase.boardingDetected &&
        _phase != EscalatorPhase.verticalMotionDetected) {
      return;
    }
    final since = _phaseEnteredAtMs;
    if (since == null || atMs - since < config.boardingPhaseTimeoutMs) return;
    _setPhase(EscalatorPhase.cancelled, atMs: atMs, reason: reason);
  }

  EscalatorTransition _buildTransition({
    required _EscalatorNode boarding,
    required EscalatorDirection direction,
    required String fromFloor,
    required String toFloor,
    required double deltaM,
    required int elapsedMs,
    int stepsDuring = 0,
  }) => EscalatorTransition(
    group: boarding.name.group,
    direction: direction,
    fromFloorLabel: fromFloor,
    toFloorLabel: toFloor,
    deltaM: deltaM,
    durationMs: elapsedMs,
    stepsDuring: stepsDuring,
    boardingNodeId: boarding.id,
    boardingNodeName: boarding.rawName,
    boardingDistanceM: _armedNodes[boarding.id]?.distanceM ?? double.nan,
    boardingEvidence: _boardingEvidence,
    expectedArrivalNodeId: boarding.id == _expectedBoardingNodeId
        ? _expectedArrivalNodeId
        : null,
  );

  /// 허가된 탑승 노드 중 방향이 맞는 가장 가까운 노드를 고른다. 활성 경로의
  /// 정확한 id가 있으면 그것을 우선한다. 경로가 없으면 같은 방향 후보 중
  /// 가장 가까운 것을 쓴다. 기압 방향으로 상·하행을 먼저 거르므로 붙어 있는
  /// 반대 방향 레인을 선택하지 않는다.
  _EscalatorNode? _pickBoardingNode(EscalatorDirection direction) {
    _boardingEvidence = 'observed';
    final candidates = <(_EscalatorNode, double)>[];
    for (final armed in _armedNodes.values) {
      final node = _escalatorNodes
          .where((candidate) => candidate.id == armed.nodeId)
          .firstOrNull;
      if (node == null || node.name.direction != direction) continue;
      candidates.add((node, armed.distanceM));
    }
    final expected = candidates
        .where((candidate) => candidate.$1.id == _expectedBoardingNodeId)
        .firstOrNull;
    if (expected != null) {
      _boardingEvidence = _observedBoardingDistances.containsKey(expected.$1.id)
          ? 'routeAndObserved'
          : 'routeExpected';
      return expected.$1;
    }

    final observedCandidates = candidates
        .where(
          (candidate) =>
              _observedBoardingDistances.containsKey(candidate.$1.id),
        )
        .map(
          (candidate) =>
              (candidate.$1, _observedBoardingDistances[candidate.$1.id]!),
        )
        .toList();
    observedCandidates.sort((a, b) => a.$2.compareTo(b.$2));
    if (observedCandidates.isNotEmpty) return observedCandidates.first.$1;

    // 관측 근거가 없으면 기압 근거로 허가한 노드를 쓴다. **관측보다 뒤에 둔다** —
    // 실제로 가까이 간 노드가 있으면 그쪽이 언제나 더 강한 근거다.
    final byAltitude =
        candidates
            .where((c) => _altitudeArmedNodeIds.contains(c.$1.id))
            .toList()
          ..sort((a, b) => a.$2.compareTo(b.$2));
    if (byAltitude.isNotEmpty) {
      _boardingEvidence = 'altitudeArmed';
      return byAltitude.first.$1;
    }
    return null;
  }

  /// 기압이 이미 층 이동을 말하는데 허가가 없을 때, 마지막 보정 위치 주변에서
  /// 탑승 노드를 골라 뒤늦게 허가한다. 못 고르면 null.
  ///
  /// 근접(6 m)만으로 거는 허가는 랜딩에서 보정 위치가 어긋나면 영영 안 걸리고,
  /// 그러면 배너는 "이동 중"인데 층은 끝까지 안 바뀐다. 조건과 오탐 방어는
  /// `docs/client/escalator-thresholds.md`의 「허가」절.
  _EscalatorNode? _armByAltitude(
    EscalatorDirection direction, {
    required int atMs,
    required double risenM,
    required bool hasMotionEvidence,
  }) {
    if (!hasMotionEvidence) return null;
    if (risenM < config.visibleVerticalDeltaM) return null;
    final position = _lastPositionM;
    if (position == null) return null;

    _EscalatorNode? nearest;
    var nearestM = double.infinity;
    final groups = <String>{};
    for (final node in _escalatorNodes) {
      if (node.name.role != EscalatorNodeRole.boarding) continue;
      if (node.name.direction != direction) continue;
      final distance = math.sqrt(
        math.pow(position.eastM - node.xM, 2) +
            math.pow(position.northM - node.yM, 2),
      );
      if (distance > config.altitudeArmRadiusM) continue;
      groups.add(node.name.group);
      if (distance < nearestM) {
        nearestM = distance;
        nearest = node;
      }
    }
    // 두 뱅크가 함께 잡히면 어느 것을 탔는지 가릴 근거가 없다. 층을 잘못 바꾸는
    // 비용이 못 바꾸는 비용보다 크므로 여기서는 아무것도 고르지 않는다.
    if (nearest == null || groups.length > 1) return null;

    // 허가는 매 샘플 갱신하되 이벤트는 처음 걸릴 때만 남긴다 — 안 그러면 진단
    // 로그가 초당 몇 줄씩 같은 사실로 찬다.
    final first = !_armedNodes.containsKey(nearest.id);
    _armedNodes[nearest.id] = _ArmedNode(
      nodeId: nearest.id,
      distanceM: nearestM,
      atMs: atMs,
    );
    _altitudeArmedNodeIds.add(nearest.id);
    _armedUntilMs = atMs + config.armHoldMs;
    _boardingEvidence = 'altitudeArmed';
    if (first) {
      _pushEvent(
        atMs: atMs,
        kind: 'armed',
        reason: 'altitude:${nearest.id}',
        deltaM: risenM,
        group: nearest.name.group,
        toFloorLabel: nearest.name.otherFloorLabel,
      );
    }
    return nearest;
  }

  /// 빠른 EMA의 수직 속도(m/s). 직전 샘플이 아니라
  /// [EscalatorDetectorConfig.fastSlopeBaseMs] 이상 떨어진 값과 비교한다.
  /// 이력이 모자라면 null — "안 움직였다"와 섞으면 세션 시작이 곧 하차가 된다.
  double? _fastSpeedOver(int atMs) {
    if (_fastHistory.length < 2) return null;
    final baseLimit = atMs - config.fastSlopeBaseMs;
    // 밑변보다 오래된 값은 하나만 남기면 된다(그 하나가 기준점이다).
    while (_fastHistory.length > 2 && _fastHistory[1].atMs <= baseLimit) {
      _fastHistory.removeAt(0);
    }
    final reference = _fastHistory.first;
    if (reference.atMs > baseLimit) return null;
    final seconds = (atMs - reference.atMs) / 1000.0;
    if (seconds <= 0) return null;
    return (_fastHistory.last.value - reference.value) / seconds;
  }

  bool _hasSettled(int atMs, double smoothed) {
    final rise = _riseOver(atMs, smoothed);
    if (rise == null) return false;
    return rise.abs() <= config.settleSlopeM;
  }

  /// 최근 [EscalatorDetectorConfig.settleWindowMs] 동안의 평활 고도 변화량.
  ///
  /// 창을 채울 이력이 없으면 null — "안 움직였다"와 "아직 모른다"를 섞으면
  /// 세션 시작 직후 첫 샘플들이 곧바로 확정으로 넘어간다.
  double? _riseOver(int atMs, double smoothed) {
    final windowStart = atMs - config.settleWindowMs;
    _Smoothed? reference;
    for (final item in _smoothedHistory) {
      if (item.atMs <= windowStart) {
        reference = item;
      } else {
        break;
      }
    }
    if (reference == null) return null;
    return smoothed - reference.value;
  }

  /// 창 안의 평활 이력을 [EscalatorDetectorConfig.directionalStrideMs] 이상 떨어진
  /// 구간으로 잘라, 같은 방향 구간이 충분히 이어졌는지 본다(샘플 쌍이 아니라 구간).
  bool _hasConsistentRamp(int atMs, int sign) {
    final windowStart = atMs - config.rampConsistencyWindowMs;
    _Smoothed? strideStart;
    var directionalStrides = 0;
    var opposingStrides = 0;
    int? firstAtMs;
    int? lastAtMs;
    for (final item in _smoothedHistory) {
      if (item.atMs < windowStart) continue;
      firstAtMs ??= item.atMs;
      lastAtMs = item.atMs;
      final before = strideStart;
      if (before == null) {
        strideStart = item;
        continue;
      }
      if (item.atMs - before.atMs < config.directionalStrideMs) continue;
      strideStart = item;
      final directionalDelta = (item.value - before.value) * sign;
      if (directionalDelta >= config.minDirectionalSampleDeltaM) {
        directionalStrides++;
      } else if (directionalDelta <= -config.minDirectionalSampleDeltaM) {
        opposingStrides++;
      }
    }
    final durationMs = firstAtMs == null || lastAtMs == null
        ? 0
        : lastAtMs - firstAtMs;
    return durationMs >= config.settleWindowMs &&
        directionalStrides >= config.minDirectionalRampStrides &&
        opposingStrides == 0;
  }

  void _closeCandidate({
    required int atMs,
    required String reason,
    required double deltaM,
    required int elapsedMs,
    double? rebaselineTo,
    String? toFloorLabel,
    String? group,
  }) {
    if (_pendingTransition != null) {
      _cancelledTransition = _pendingTransition;
    }
    _setPhase(
      EscalatorPhase.cancelled,
      atMs: atMs,
      reason: reason,
      toFloorLabel: toFloorLabel,
      group: group,
      deltaM: deltaM,
      transition: _pendingTransition,
    );
    _candidateStartMs = null;
    _candidateSign = 0;
    _candidateBoarding = null;
    _candidateToFloor = null;
    _pendingTransition = null;
    _fastExitQuietSinceMs = null;
    if (rebaselineTo != null) {
      _baselineM = rebaselineTo;
    }
    _pushEvent(
      atMs: atMs,
      kind: 'rejected',
      reason: reason,
      deltaM: deltaM,
      toFloorLabel: toFloorLabel,
      group: group,
      durationMs: elapsedMs,
      stepsDuring: _lastSteps - _candidateStartSteps,
    );
  }

  void _resetForNewFloor() {
    _confirmedToFloorLabel = null;
    _window.clear();
    _smoothedHistory.clear();
    _baselineM = null;
    _lastSmoothedM = null;
    // 같은 local m 숫자가 층마다 다른 자리를 가리킨다. 들고 가면 새 층의 엉뚱한
    // 에스컬레이터가 기압 근거로 허가된다([_armByAltitude]).
    _lastPositionM = null;
    _armedNodes.clear();
    _observedBoardingDistances.clear();
    _altitudeArmedNodeIds.clear();
    _expectedBoardingNodeId = null;
    _expectedArrivalNodeId = null;
    _armedUntilMs = null;
    _candidateStartMs = null;
    _candidateSign = 0;
    _candidateBoarding = null;
    _candidateToFloor = null;
    _pendingTransition = null;
    _startedTransition = null;
    _cancelledTransition = null;
    _fastAltitudeM = null;
    _lastFastAltitudeAtMs = null;
    _fastExitQuietSinceMs = null;
    _lastAltitudeSteps = _lastSteps;
    _lastAltitudeRawMotionCount = _rawMotionCount;
    _lastAltitudeRawStepCount = _rawStepCount;
    _awaitingPostConfirmQuiet = false;
    _postConfirmQuietSinceMs = null;
    // 층이 바뀌었으면 진행 중인 단계도 끝난 것이다. 남겨 두면 새 층에서 옛
    // 배너와 pause가 그대로 이어진다.
    if (_phase == EscalatorPhase.boardingDetected ||
        _phase == EscalatorPhase.verticalMotionDetected ||
        _phase == EscalatorPhase.midpointReached) {
      _setPhase(
        EscalatorPhase.cancelled,
        atMs: _phaseEnteredAtMs ?? 0,
        reason: 'floorChanged',
      );
    }
    _phase = EscalatorPhase.idle;
    _phaseEnteredAtMs = null;
    _resetApproach();
    _verticalMotionSinceMs = null;
    _verticalMotionSign = 0;
    _verticalMotionObserved = false;
    _fastDisplacementM = 0;
    _earlyVerticalMotion = false;
    _verticalMotionQuietSinceMs = null;
  }

  void _pushEvent({
    required int atMs,
    required String kind,
    required String reason,
    double deltaM = 0,
    String? toFloorLabel,
    String? group,
    int? durationMs,
    int? stepsDuring,
    String? boardingEvidence,
  }) {
    if (_events.length >= maxEvents) {
      _events.removeAt(0);
    }
    _events.add(
      EscalatorDetectionEvent(
        atMs: atMs,
        kind: kind,
        reason: reason,
        deltaM: deltaM,
        fromFloorLabel: _floorLabel ?? '',
        toFloorLabel: toFloorLabel,
        group: group,
        durationMs: durationMs,
        stepsDuring: stepsDuring,
        boardingEvidence: boardingEvidence,
      ),
    );
  }

  static List<_EscalatorNode> _parseEscalatorNodes(FloorGraph? graph) {
    if (graph == null) return const [];
    final nodes = <_EscalatorNode>[];
    for (final node in graph.nodes) {
      if (node.type != 'escalator') continue;
      final parsed = EscalatorNodeName.tryParse(node.name);
      // 이름 규칙이 없는 노드는 방향·목표 층을 알 수 없어 판정에 쓸 수 없다.
      if (parsed == null) continue;
      nodes.add(
        _EscalatorNode(
          id: node.id,
          rawName: node.name,
          name: parsed,
          xM: node.xM,
          yM: node.yM,
        ),
      );
    }
    return List.unmodifiable(nodes);
  }

  static double _median(List<double> values) {
    final sorted = List<double>.from(values)..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }
}

class _EscalatorNode {
  const _EscalatorNode({
    required this.id,
    required this.rawName,
    required this.name,
    required this.xM,
    required this.yM,
  });

  final String id;
  final String? rawName;
  final EscalatorNodeName name;
  final double xM;
  final double yM;
}

class _ArmedNode {
  const _ArmedNode({
    required this.nodeId,
    required this.distanceM,
    required this.atMs,
  });

  final String nodeId;
  final double distanceM;
  final int atMs;
}

class _Smoothed {
  const _Smoothed(this.atMs, this.value);

  final int atMs;
  final double value;
}
