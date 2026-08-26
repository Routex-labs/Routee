import 'dart:math' as math;

import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import '../../../domain/guidance/route_checkpoint.dart';
import '../../../domain/guidance/route_movement.dart';
import '../../../domain/guidance/route_progress.dart';
import '../../../models/building/building_graph.dart';
import '../../../models/building/floor_graph.dart';
import '../contract/altitude_sample.dart';
import '../contract/pdr_anchor.dart';
import '../contract/raw_motion_activity.dart';
import 'corridor_position_tracker.dart';
import 'corridor_tracking_session.dart';
import 'escalator_transition_detector.dart';
import '../../../models/route/indoor_route.dart';
import 'indoor_guidance_position.dart';
import 'indoor_guidance_progress.dart';
import 'indoor_location_estimate.dart';
import '../../../domain/guidance/corridor_tracking.dart';

/// 기압 샘플 한 건이 만들어 낸 층 이동 신호들.
///
/// 셋을 한 번에 돌려주는 이유는 셋이 **서로 다른 시점의 같은 이동**을 가리키기
/// 때문이다. 화면은 순서대로(시작 → 취소 → 확정) 처리해야 층·경로 복원이
/// 어긋나지 않는다.
class EscalatorAltitudeOutcome {
  const EscalatorAltitudeOutcome({
    this.started,
    this.cancelled,
    this.confirmed,
    this.events = const [],
  });

  /// 후보가 열려 목적 층 지도를 여는 시점.
  final EscalatorTransition? started;

  /// 열렸던 후보가 되돌아간 경우. 층·경로를 원래대로 복원해야 한다.
  final EscalatorTransition? cancelled;

  /// 하차가 확정된 시점. 새 앵커를 잡는다.
  final EscalatorTransition? confirmed;

  /// 판정 로그. 레코더가 없어도 세션은 비워서 넘긴다 — 안 그러면 다음 안내
  /// 세션 로그에 지난 판정이 섞인다.
  final List<EscalatorDetectionEvent> events;

  bool get isEmpty => started == null && cancelled == null && confirmed == null;
}

/// 탑승 판정이 가리키는 노드가 **안내가 지목한 탑승점**이면 그 좌표, 아니면 null.
///
/// 판정기는 경로와 무관한 근접만으로도 단계를 올린다. 그 근거로 마커를 고정하면
/// 에스컬레이터 옆을 스쳐 지나가는 사용자의 위치가 그 자리에 붙어 버린다 —
/// 그냥 걷고 있는 사람의 마커를 세우는 것이다. 그래서 세 가지가 모두 맞을
/// 때만 고정한다.
///
/// 1. 앵커가 지금 보고 있는 층에 있다(다른 층 노드에 고정하면 남의 층 좌표다).
/// 2. 이 층 세그먼트가 실제로 **에스컬레이터로** 갈아타는 구간이다.
/// 3. 길찾기가 고른 전이 노드가 판정기가 고른 탑승 노드와 **같다**.
PdrLocalPoint? routeBoardingHoldPoint({
  required String? boardingNodeId,
  required String? anchorFloorId,
  required String? displayedFloorId,
  required MultiFloorRoute? multiFloorRoute,
  required FloorGraph? graph,
}) {
  if (boardingNodeId == null ||
      anchorFloorId == null ||
      anchorFloorId != displayedFloorId) {
    return null;
  }
  final segment = multiFloorRoute?.segmentForFloor(anchorFloorId);
  if (segment == null ||
      segment.transferModeToNext != 'escalator' ||
      segment.transferFromNodeId != boardingNodeId) {
    return null;
  }
  final node = graph?.nodes.where((n) => n.id == boardingNodeId).firstOrNull;
  return node == null ? null : PdrLocalPoint(node.xM, node.yM);
}

/// 수직 이동이 잡힌 뒤, 고정 지점이 지금 위치에서 이만큼 넘게 떨어져 있으면
/// **그 자리에 세운다**.
///
/// 고정은 원래 "탑승점을 지나 앞 매장으로 흘러가는 것"을 막으려는 것이다.
/// 그런데 판정이 이르거나 틀렸을 때 먼 노드로 스냅하면 마커가 눈에 띄게 뒤로
/// 순간이동하고, 사용자는 그걸 "위치가 튄다"로 읽는다 — 막으려던 것보다 나쁜
/// 그림이다. 6m는 랜딩 폭과 보정 오차를 감안한 강한 단계의 보정 한계다. 접근
/// 중 화면 고정을 시작하는 문턱으로는 쓰지 않는다.
const boardingHoldSnapRadiusM = 6.0;

/// 탑승점 후보를 화면 고정으로 올릴 때의 반경.
///
/// 6m는 판정 허가 오차를 품는 범위라 그 경계에서 탑승점으로 당기면 눈에 띄는
/// 순간이동이 된다. 화면 고정은 마커가 실제로 노드에 붙어 보이는 범위만 쓴다.
const boardingApproachVisibleSnapRadiusM = 1.5;

/// 활성 경로가 지목한 탑승점의 가시 반경에 들어온 뒤 필요한 전진 peak 수.
///
/// 대상 일치는 이미 [routeBoardingHoldPoint]가 보장한다. 여기서 한 걸음을 더
/// 기다리면 marker가 실제 사용자보다 앞서 탑승점을 지나친 경우 다음 peak가
/// "멀어짐"으로 읽혀 후보가 사라졌다. 첫 신뢰 가능한 근접 걸음에서 붙든다.
const boardingApproachVisiblePeakCount = 1;

/// 고정 지점을 지금 위치 기준으로 다듬는다. 멀면 [currentM]을 그대로 쓴다.
PdrLocalPoint? clampBoardingHold({
  required PdrLocalPoint? holdPoint,
  required PdrLocalPoint? currentM,
  double radiusM = boardingHoldSnapRadiusM,
}) {
  if (holdPoint == null || currentM == null) return holdPoint ?? currentM;
  return (holdPoint - currentM).distance <= radiusM ? holdPoint : currentM;
}

/// 이 층에서 걸을 거리가 이보다 짧으면 **내리자마자 바로 다음 에스컬레이터**로
/// 본다.
///
/// 다층 경로에서 흔한 모양이다 — B2에서 내려 두어 걸음 옆의 상행을 바로 탄다.
/// 그 구간에서는 걸어갈 거리가 없으므로 탑승 판정을 늦출 이유가 없고, 늦추면
/// 환승마다 마커가 먼저 몇 걸음 흘러간다.
const consecutiveTransferRouteM = 6.0;

/// 교차점을 지나는 동안 이탈 증거를 새로 쌓지 않는 시간.
///
/// 교차점에서는 어느 간선에 있는지가 잠깐 흔들린다. 이 보호가 없으면 통과하는
/// 것만으로 재탐색이 돈다. 반대로 무한정 보호하면 교차점 옆 복도로 실제로 걸어
/// 나간 경우에 재탐색이 영영 걸리지 않는다.
const junctionRerouteHoldMs = 4000;

/// 실내 안내에서 **"지금 어디에 있는가"** 하나를 소유하는 headless 세션.
///
/// 같은 판단이 두 화면에 따로 구현돼 서로 다른 위치를 그리던 것을 하나로 모은
/// 것이다. 세션은 **위젯을 모른다** — 지도·카메라·도면은 화면 몫이고 여기서는
/// 위치 한 건과 그 출처만 내준다.
///
/// [attach]/[detach]가 필요한 이유는 오버레이가 꺼진 구간이다 — 예전에는 그때도
/// 복도 보정이 돌아, 야외를 걸은 거리가 실내 좌표계에 쌓였다.
class IndoorGuidanceSession {
  IndoorGuidanceSession({
    DateTime Function()? now,
    int Function()? nowMs,
    EscalatorTransitionDetector? escalator,
  }) : _now = now ?? DateTime.now,
       _nowMs = nowMs ?? _defaultNowMs,
       _escalator = escalator ?? EscalatorTransitionDetector();

  static int _defaultNowMs() => DateTime.now().millisecondsSinceEpoch;

  final DateTime Function() _now;
  final int Function() _nowMs;

  final CorridorTrackingSession _corridor = CorridorTrackingSession();
  final EscalatorTransitionDetector _escalator;

  bool _attached = false;
  String? _buildingId;
  String? _floorId;
  List<String> _floorLabels = const [];
  FloorGraph? _graph;
  PdrAnchor? _anchor;
  PdrSnapshot? _snapshot;
  IndoorLocationEstimate? _estimate;
  MultiFloorRoute? _multiFloorRoute;

  /// 탑승 판정 중 위치를 고정할 지점. 안내가 지목한 탑승점일 때만 채워진다.
  PdrLocalPoint? _boardingHoldPointM;

  /// 실제 수직 이동이 확인된 뒤 마커를 묶어 두는 지점.
  ///
  /// [_boardingHoldPointM]과 나누는 이유는 **근거의 세기가 다르기** 때문이다. 접근
  /// 단계는 스쳐 지나가기만 해도 올라가므로 경로와 판정이 일치할 때만 고정한다.
  ///
  /// 수직 이동은 스쳐 지나감이 아니라, 여기서는 근거를 물러서며 **반드시** 어딘가에
  /// 고정한다(탑승점 → 판정기 노드 → 그 순간 보정 위치) — 안 그러면 발판 진동이
  /// 걸음으로 세어져 마커가 앞 매장으로 흘러갔다.
  PdrLocalPoint? _rideHoldPointM;

  /// 경로 탑승 후보에서 1차 수직 속도가 확인된 순간의 표시 위치.
  ///
  /// 아직 0.5m 강한 문턱 전이라 탑승점으로 스냅하거나 배너를 열지는 않는다.
  /// 다만 이때도 사람이 이미 발판 위일 수 있으므로, 이후 걸음과 재탐색이 반대
  /// 레인까지 마커를 밀지 못하게 그 순간 보이던 자리를 붙든다.
  PdrLocalPoint? _verticalObservationHoldPointM;

  /// 고도 근거가 오기 **전에** 탑승점 하나만으로 거는 고정 지점.
  ///
  /// 위 둘과 달리 단계 전이가 아니라 [_syncBoardingApproach]가 매 스냅샷 갱신한다.
  /// 탑승 직후 몇 초는 판정기가 idle이라 단계가 아예 안 나오기 때문이다.
  PdrLocalPoint? _approachHoldPointM;
  int? _approachHoldEnteredAtMs;

  /// 경로가 지목한 탑승점까지의 거리(m). 그런 탑승점이 없으면 null.
  double? _boardingApproachDistanceM;

  /// 넓은 반경 안에 처음 들어선 시각. 밖으로 나가야 다시 잡힌다(시간 탈출구).
  int? _boardingApproachSinceMs;

  /// 탑승점 근거만으로 재탐색을 막는 구간인지. [_syncBoardingApproach]가 정한다.
  bool _boardingApproachGateOpen = false;
  int? _boardingApproachLastActivityPeakId;
  int? _boardingApproachLastActivityConfirmedSteps;
  int _boardingApproachEvidencePeaks = 0;
  int? _boardingApproachLastPeakId;
  int? _boardingApproachLastConfirmedSteps;
  double? _boardingApproachLastDistanceM;
  int _boardingVestibuleEvidencePeaks = 0;
  double? _boardingVestibuleLastDistanceM;

  /// 마지막으로 신뢰한 graph 위치에서 원시 PDR의 **이동 벡터만** 이어 붙인
  /// 탑승 접근 그림자. 화면에는 그리지 않고, 열린 공간에서 경로 간선을 잘라
  /// 에스컬레이터로 곧장 가는 경우의 근접 근거로만 쓴다.
  PdrLocalPoint? _boardingApproachShadowM;
  PdrLocalPoint? _boardingApproachShadowLastRawM;
  String? _boardingApproachShadowNodeId;
  double? _boardingApproachShadowHeadingBiasDeg;
  int _boardingApproachShadowEvidencePeaks = 0;
  int? _boardingApproachShadowLastPeakId;
  int? _boardingApproachShadowLastConfirmedSteps;
  double? _boardingApproachShadowLastDistanceM;

  bool get isAttached => _attached;
  String? get buildingId => _buildingId;
  String? get floorId => _floorId;

  /// 층 판정기 진단값. 디버그 칩과 레코더가 읽는다.
  EscalatorTransitionDetector get escalator => _escalator;

  /// 탑승점에 고정 중인지. 화면은 이 구간에서 경로 진행률을 갱신하지 않는다.
  PdrLocalPoint? get boardingHoldPointM => _boardingHoldPointM;

  /// 걸음이 위치를 더 못 밀고 있는가(접근 고정이든 탑승 고정이든).
  ///
  /// 진행률 갱신을 멈출지 판단하는 자리가 이 값 하나를 보게 해서, 고정 지점이
  /// 늘어날 때마다 조건을 두 곳에서 맞추는 일이 없게 한다.
  bool get isPositionHeld =>
      _boardingHoldPointM != null ||
      _rideHoldPointM != null ||
      _verticalObservationHoldPointM != null ||
      _approachHoldPointM != null;

  /// 경로가 지목한 탑승점까지의 거리(m). 디버그 칩이 읽는다 — 게이트가 안 열렸을 때
  /// "거리가 멀어서"인지 "탑승점을 못 찾아서(null)"인지는 이 값으로만 갈린다.
  double? get boardingApproachDistanceM => _boardingApproachDistanceM;

  /// 탑승점 근거만으로 재탐색을 막는 구간인가.
  ///
  /// [isPositionHeld]보다 **넓은** 반경을 쓴다. 재탐색 차단은 틀려도 몇 초 늦을
  /// 뿐이지만, 위치 고정은 틀리면 걸어가는 사용자의 마커가 안 따라간다.
  bool get isNearRouteBoarding => _boardingApproachGateOpen;

  /// 복도 보정 결과 원본. 디버그 궤적과 경로 진행률이 함께 쓴다.
  CorridorTrackingResult? get trackingResult =>
      _attached ? _corridor.result : null;

  CorridorObservation? get lastObservation => _corridor.lastObservation;
  bool get lastWasReset => _corridor.lastWasReset;
  CorridorTrackingSession get corridor => _corridor;

  /// 실내 안내를 켠다. 이미 같은 건물에 붙어 있으면 아무것도 하지 않는다 —
  /// 여기서 무조건 초기화하면 층 오버레이를 다시 그릴 때마다 보정이 리셋된다.
  void attach({required String buildingId}) {
    if (_attached && _buildingId == buildingId) return;
    _attached = true;
    _buildingId = buildingId;
    _resetTracking();
  }

  /// 실내 안내를 끈다. 야외로 나갔거나 오버레이를 닫은 상태다.
  ///
  /// 보정 상태를 **버린다.** 남겨 두면 야외에서 걸은 거리가 다음 진입에
  /// 이월되고, 사용자는 건물에 들어서자마자 엉뚱한 자리에 서 있다.
  void detach() {
    if (!_attached) return;
    _attached = false;
    _buildingId = null;
    _resetTracking();
  }

  /// 탑승점 고정만 푼다.
  ///
  /// 단계 전이가 아니라 화면 쪽 출구(되돌리기·취소 정리)에서 탑승이 끝나는
  /// 경로가 있다. 그 경로가 고정을 안 풀면 마커가 탑승점에 붙은 채 남는다.
  void clearBoardingHold() {
    _boardingHoldPointM = null;
    _rideHoldPointM = null;
    _verticalObservationHoldPointM = null;
    _approachHoldPointM = null;
    _approachHoldEnteredAtMs = null;
  }

  /// 접근 근거 자체를 버린다. [clearBoardingHold]와 나눈 이유는 **시간 상한** 때문이다 —
  /// 고정을 푸는 자리마다 시각까지 지우면 탑승점 앞에 계속 서 있어도 상한이 매번
  /// 처음부터 다시 세어져 탈출구가 사라진다.
  void _clearBoardingApproach() {
    _boardingApproachDistanceM = null;
    _boardingApproachSinceMs = null;
    _boardingApproachGateOpen = false;
    _boardingApproachLastActivityPeakId = null;
    _boardingApproachLastActivityConfirmedSteps = null;
    _clearBoardingApproachEvidence();
    _clearBoardingApproachShadow();
  }

  void _clearBoardingApproachEvidence() {
    _boardingApproachEvidencePeaks = 0;
    _boardingApproachLastPeakId = null;
    _boardingApproachLastConfirmedSteps = null;
    _boardingApproachLastDistanceM = null;
    _boardingVestibuleEvidencePeaks = 0;
    _boardingVestibuleLastDistanceM = null;
    _boardingApproachShadowEvidencePeaks = 0;
    _boardingApproachShadowLastPeakId = null;
    _boardingApproachShadowLastConfirmedSteps = null;
    _boardingApproachShadowLastDistanceM = null;
  }

  void _clearBoardingApproachShadow() {
    _boardingApproachShadowM = null;
    _boardingApproachShadowLastRawM = null;
    _boardingApproachShadowNodeId = null;
    _boardingApproachShadowHeadingBiasDeg = null;
  }

  /// 부착·층·경로는 그대로 두고 **보정만** 처음부터 다시 본다.
  ///
  /// 새 PDR 세션을 시작했거나 앵커를 다시 찍은 경우다. [detach]와 달리 층·
  /// 그래프·경로를 버리지 않는다 — 그것까지 버리면 다음 스냅샷이 올 때까지
  /// 화면이 컨텍스트 없는 상태로 남는다.
  void resetTracking() {
    _corridor.reset();
    _snapshot = null;
    clearBoardingHold();
    _clearBoardingApproach();
  }

  void _resetTracking() {
    _corridor.reset();
    _snapshot = null;
    _anchor = null;
    _floorId = null;
    _graph = null;
    _multiFloorRoute = null;
    clearBoardingHold();
    _clearBoardingApproach();
  }

  /// 지금 보고 있는 층과 그 층의 그래프를 알려 준다.
  ///
  /// 층이 바뀌면 보정과 탑승점 고정을 버린다. 같은 local m 숫자가 층마다 다른
  /// 자리를 가리키므로, 이전 층 상태를 들고 가면 새 층 첫 프레임이 엉뚱한
  /// 복도에 붙는다.
  ///
  /// **층 판정기에는 탑승 중이 아닐 때만 알린다.** 조기 전환 뒤 화면은 목적
  /// 층을 먼저 보여주지만, 판정기는 탑승 층의 baseline과 노드 허가를 하차까지
  /// 유지해야 한다. 이 규칙이 깨지면 긴 에스컬레이터 중간에 0점이 다시 잡혀
  /// 남은 반 층이 또 하나의 층 이동으로 보인다.
  void setContext({
    required String? floorId,
    required FloorGraph? graph,
    List<String>? floorLabels,
  }) {
    if (!_attached) return;
    final floorChanged = floorId != _floorId;
    _floorId = floorId;
    _graph = graph;
    if (floorLabels != null) _floorLabels = floorLabels;
    if (floorChanged) {
      _corridor.reset();
      _snapshot = null;
      // 고정 지점은 **이전 층의 local m**이다. 같은 숫자가 새 층에서는 다른
      // 자리를 가리키므로 들고 가지 않는다. 조기 전환으로 목적 층 도면이 먼저
      // 열린 구간에서 마커가 사라지는 것은 화면이 따로 메운다(탑승 활강).
      clearBoardingHold();
    }
    if (_escalator.pendingTransition == null) {
      _escalator.updateContext(
        floorLabel: floorId,
        graph: graph,
        floorLabels: _floorLabels,
      );
    }
  }

  /// 지금 안내 중인 다층 경로. 탑승점 고정과 경로 접근 판정이 쓴다.
  void setRoute(MultiFloorRoute? multiFloorRoute) {
    _multiFloorRoute = multiFloorRoute;
    if (multiFloorRoute == null) _boardingHoldPointM = null;
  }

  /// 보정 기준점. 확정 전(`canRenderPosition`이 false)에는 null로 준다.
  void setAnchor(PdrAnchor? anchor) {
    if (!_attached) return;
    _anchor = anchor;
  }

  /// GPS·입구에서 온 절대 위치 추정. 앵커가 없을 때만 화면에 쓰인다.
  ///
  /// 앵커를 **덮지 않는다.** 오래된 GPS가 최신 PDR을 되돌리는 사고를 구조적으로
  /// 막으려면 둘이 다른 자리에 있어야 한다.
  void setEstimate(IndoorLocationEstimate? estimate) {
    _estimate = estimate;
  }

  /// 새 PDR 스냅샷을 보정에 넣는다. 부착 상태가 아니면 **버린다**.
  ///
  /// 앵커가 지금 보고 있는 층에 없으면 보정을 돌리지 않는다. 다른 층 기준점으로
  /// 이 층 복도에 스냅하면 마커가 남의 층 복도를 따라 걸어간다.
  CorridorTrackingResult? onSnapshot(
    PdrSnapshot? snapshot, {
    int? timestampMs,
  }) {
    if (!_attached) return null;
    _snapshot = snapshot;
    final anchor = _anchor;
    if (anchor == null || anchor.floorId != _floorId) return null;
    final atMs = timestampMs ?? _nowMs();
    final lockBoardingTerminal =
        _boardingApproachGateOpen &&
        (_approachHoldPointM != null ||
            (_boardingApproachDistanceM ?? double.infinity) <=
                _escalator.config.armRadiusM);
    final result = _corridor.update(
      graph: _graph,
      anchor: anchor,
      snapshot: snapshot,
      timestampMs: atMs,
      preferredRouteEdgeIds: _routeSegment?.edgeIds ?? const [],
      preferredRouteNodeIds: _routeSegment?.nodeIds ?? const [],
      preferRouteContinuity: _boardingApproachGateOpen,
      lockPreferredRouteTerminal: lockBoardingTerminal,
    );
    if (result == null) return null;
    _feedEscalator(result, snapshot, atMs);
    return result;
  }

  /// 보정 위치를 층 판정기에 먹인다.
  ///
  /// **원시 PDR 좌표가 아니라 보정된 위치를 준다.** 원시 좌표를 주면 앵커
  /// 오차만큼 에스컬레이터 노드 근접 판정이 어긋난다.
  void _feedEscalator(
    CorridorTrackingResult result,
    PdrSnapshot? snapshot,
    int atMs,
  ) {
    final steps = snapshot?.steps ?? 0;
    _escalator.onPosition(
      positionM: result.correctedPosition,
      steps: steps,
      timestampMs: atMs,
    );

    // 안내가 이 층에서 에스컬레이터로 갈아타라고 했으면, 경로가 지목한 탑승
    // 노드를 판정기에 함께 알린다. 붙어 있는 레인 중 어느 것을 타는지는 센서로
    // 가릴 수 없고 길찾기만 안다.
    final floor = _floorId;
    final segment = floor == null
        ? null
        : _multiFloorRoute?.segmentForFloor(floor);
    final route = segment?.route;
    PdrLocalPoint? routeApproachPositionM;
    if (segment != null &&
        segment.transferModeToNext == 'escalator' &&
        segment.transferFromNodeId != null &&
        route != null &&
        route.pointsLocalM.isNotEmpty) {
      final routeEnd = route.pointsLocalM.last;
      final routeEndM = PdrLocalPoint(routeEnd.x, routeEnd.y);
      routeApproachPositionM = _updateBoardingApproachShadow(
        boardingNodeId: segment.transferFromNodeId!,
        routeEndM: routeEndM,
        result: result,
      );
      _escalator.onEscalatorRouteApproach(
        positionM: routeApproachPositionM,
        routeEndM: routeEndM,
        expectedBoardingNodeId: segment.transferFromNodeId!,
        expectedArrivalNodeId: segment.transferToNodeId,
        steps: steps,
        timestampMs: atMs,
        immediateTransfer: route.distanceMeters <= consecutiveTransferRouteM,
      );
    } else {
      _clearBoardingApproachShadow();
    }
    _syncBoardingApproach(
      segment: segment,
      result: result,
      confirmedSteps: steps,
      atMs: atMs,
      routeApproachPositionM: routeApproachPositionM,
    );
  }

  /// graph에 고정된 표시 위치와 자유보행 그림자 중 탑승점에 가까운 쪽을 낸다.
  ///
  /// 원시 PDR 절대좌표를 그대로 믿지 않는다. 마지막 안정된 표시점에 그림자를
  /// 놓고, 이후 원시 이동 벡터를 tracker가 학습한 heading bias로 회전해 누적한다.
  /// 그래서 heading 오차는 보정하면서도 graph에 없는 대각선 지름길은 보존한다.
  PdrLocalPoint _updateBoardingApproachShadow({
    required String boardingNodeId,
    required PdrLocalPoint routeEndM,
    required CorridorTrackingResult result,
  }) {
    final matchedM = result.matchedPreviewPosition;
    final matchedDistanceM = (routeEndM - matchedM).distance;
    final config = _escalator.config;
    final sameTarget = _boardingApproachShadowNodeId == boardingNodeId;
    if (!sameTarget) _clearBoardingApproachShadow();

    if (_boardingApproachShadowM == null) {
      final canSeed =
          matchedDistanceM <= config.routeApproachArmRadiusM &&
          result.state != CorridorTrackingState.uncertain &&
          !result.leaderRelocated;
      if (!canSeed) return matchedM;
      _boardingApproachShadowM = matchedM;
      _boardingApproachShadowLastRawM = result.rawPreviewPosition;
      _boardingApproachShadowNodeId = boardingNodeId;
      _boardingApproachShadowHeadingBiasDeg = result.headingBiasDeg;
    } else {
      final previousRawM = _boardingApproachShadowLastRawM;
      if (previousRawM != null) {
        final rawDelta = result.rawPreviewPosition - previousRawM;
        _boardingApproachShadowM =
            _boardingApproachShadowM! +
            _rotateFloorVector(
              rawDelta,
              _boardingApproachShadowHeadingBiasDeg ?? result.headingBiasDeg,
            );
      }
      _boardingApproachShadowLastRawM = result.rawPreviewPosition;
    }

    final shadowM = _boardingApproachShadowM!;
    return (routeEndM - shadowM).distance < matchedDistanceM
        ? shadowM
        : matchedM;
  }

  PdrLocalPoint _rotateFloorVector(PdrLocalPoint vector, double degrees) {
    final radians = degrees * math.pi / 180;
    final cosine = math.cos(radians);
    final sine = math.sin(radians);
    return PdrLocalPoint(
      vector.eastM * cosine + vector.northM * sine,
      -vector.eastM * sine + vector.northM * cosine,
    );
  }

  /// 고도가 오기 **전** 구간을 탑승점 하나로 표현한다.
  ///
  /// 탑승 직후 Δ가 0인 몇 초 동안 걸음이 옆 복도로 스냅되지 않게 한다. 임계값과
  /// 실측 근거의 단일 출처는 `docs/client/escalator-thresholds.md`다.
  /// - **재탐색 차단**: `routeApproachArmRadiusM`(16m). 틀려도 몇 초 늦을 뿐이다.
  /// - **가시 고정 후보**: 판정기의 `boardingApproachRadiusM`(3m) 안에서 활성
  ///   경로를 따라 전진하는 서로 다른 peak를 센다.
  /// - **위치 고정**: 후보가 [boardingApproachVisiblePeakCount]번 이어지거나 탑승
  ///   노드를 실제 통과하면 건다. 노드에서 [boardingApproachVisibleSnapRadiusM]
  ///   안일 때만 노드에 붙이고, 아니면 그 순간 보이던 위치를 붙든다.
  ///
  /// 짧은 기압 인계 유예 뒤 `boardingAbandonRadiusM`에서 풀리고,
  /// 반경 안에서도 새 걸음 없이 `boardingPhaseTimeoutMs`(40초)가 지나면 접는다.
  /// 천천히 계속 걷는 접근은 걸음마다 이 무동작 시간을 갱신한다.
  void _syncBoardingApproach({
    required IndoorRouteSegment? segment,
    required CorridorTrackingResult result,
    required int confirmedSteps,
    required int atMs,
    required PdrLocalPoint? routeApproachPositionM,
  }) {
    final boardingNodeId = segment?.transferFromNodeId;
    final holdPoint = routeBoardingHoldPoint(
      boardingNodeId: boardingNodeId,
      anchorFloorId: _anchor?.floorId,
      displayedFloorId: _floorId,
      multiFloorRoute: _multiFloorRoute,
      graph: _graph,
    );
    final config = _escalator.config;
    // terminal lock이 표시 matcher를 탑승 노드에 세운 뒤에는 "가까운 쪽"을
    // 이탈 거리로 쓰면 항상 0m가 된다. 접근할 때는 matched/shadow 중 가까운
    // 쪽을 쓰되, 이미 붙든 뒤의 실제 통과 여부는 계속 흐르는 shadow로 잰다.
    final distanceProbeM = _approachHoldPointM == null
        ? routeApproachPositionM
        : _boardingApproachShadowM ?? routeApproachPositionM;
    final distanceM = holdPoint == null || distanceProbeM == null
        ? null
        : (holdPoint - distanceProbeM).distance;
    final holdGraceActive =
        _approachHoldPointM != null &&
        _approachHoldEnteredAtMs != null &&
        atMs - _approachHoldEnteredAtMs! < config.boardingAbandonGraceMs;
    if (distanceM != null && holdGraceActive) {
      _boardingApproachDistanceM = distanceM;
      _boardingApproachGateOpen = true;
      return;
    }
    if (distanceM == null || distanceM > config.routeApproachArmRadiusM) {
      _approachHoldPointM = null;
      _approachHoldEnteredAtMs = null;
      _clearBoardingApproach();
      _boardingApproachDistanceM = distanceM;
      return;
    }
    _boardingApproachDistanceM = distanceM;
    var hadMovement = false;
    for (final step in result.optimisticStepAdvances) {
      if (_boardingApproachLastActivityPeakId == step.peakId) continue;
      _boardingApproachLastActivityPeakId = step.peakId;
      hadMovement = true;
    }
    final lastConfirmed = _boardingApproachLastActivityConfirmedSteps;
    if (lastConfirmed == null || confirmedSteps > lastConfirmed) {
      _boardingApproachLastActivityConfirmedSteps = confirmedSteps;
      hadMovement = lastConfirmed != null;
    }
    if (_boardingApproachSinceMs == null || hadMovement) {
      _boardingApproachSinceMs = atMs;
    }
    final since = _boardingApproachSinceMs!;
    if (atMs - since >= config.boardingPhaseTimeoutMs) {
      // 움직임 없는 상태의 시간 상한. 천천히 접근하는 실제 걸음은 위에서 lease를
      // 갱신하지만, 탑승점 앞에 놓인 기기는 결국 풀려야 한다.
      _boardingApproachGateOpen = false;
      _approachHoldPointM = null;
      _approachHoldEnteredAtMs = null;
      _clearBoardingApproachEvidence();
      return;
    }
    _boardingApproachGateOpen = true;
    if (_approachHoldPointM != null) {
      if (distanceM > config.boardingAbandonRadiusM) {
        _approachHoldPointM = null;
        _approachHoldEnteredAtMs = null;
        _clearBoardingApproachEvidence();
      }
      return;
    }
    _updateBoardingApproachEvidence(
      segment: segment,
      result: result,
      confirmedSteps: confirmedSteps,
      boardingNodeId: boardingNodeId!,
      holdPoint: holdPoint!,
      atMs: atMs,
    );
  }

  void _updateBoardingApproachEvidence({
    required IndoorRouteSegment? segment,
    required CorridorTrackingResult result,
    required int confirmedSteps,
    required String boardingNodeId,
    required PdrLocalPoint holdPoint,
    required int atMs,
  }) {
    final graph = _graph;
    final route = segment?.route;
    if (graph == null || route == null) {
      _clearBoardingApproachEvidence();
      return;
    }
    final previousConfirmedSteps = _boardingApproachLastConfirmedSteps;
    _boardingApproachLastConfirmedSteps = confirmedSteps;
    final vestibule = _boardingVestibule(
      route: route,
      graph: graph,
      boardingNodeId: boardingNodeId,
    );
    var sawNewOptimisticStep = false;
    int? latestPeakId;
    for (final optimisticStep in result.optimisticStepAdvances) {
      if (_boardingApproachLastPeakId == optimisticStep.peakId) continue;
      sawNewOptimisticStep = true;
      latestPeakId = optimisticStep.peakId;
      _boardingApproachLastPeakId = optimisticStep.peakId;
      if (vestibule != null &&
          _optimisticStepReachedBoardingVestibule(
            step: optimisticStep,
            route: route,
            graph: graph,
            vestibuleNodeId: vestibule.nodeId,
          )) {
        _holdBoardingApproach(
          holdPoint: holdPoint,
          currentM: optimisticStep.position,
          atMs: atMs,
        );
        return;
      }
      final routeStep = adaptOptimisticStepToRoute(
        step: optimisticStep,
        graph: graph,
        routeEdgeIds: route.edgeIds,
        routeNodeIds: route.nodeIds,
      );
      final marker = routeStep.actualMarkerPosition;
      final trustedForward =
          routeStep.relation == RouteStepRelation.forward &&
          !routeStep.previewIsAmbiguous &&
          marker != null;
      if (!trustedForward) {
        _rejectBoardingApproachEvidence();
        continue;
      }
      if (vestibule != null &&
          _acceptBoardingVestibuleEvidence(
            markerDistanceM: (vestibule.pointM - marker).distance,
            crossedVestibule: routeStep.crossedRouteWaypointIds.contains(
              vestibule.nodeId,
            ),
          )) {
        _holdBoardingApproach(
          holdPoint: holdPoint,
          currentM: marker,
          atMs: atMs,
        );
        return;
      }
      final markerDistanceM = (holdPoint - marker).distance;
      final crossedBoarding = routeStep.crossedRouteWaypointIds.contains(
        boardingNodeId,
      );
      if (_acceptBoardingApproachEvidence(
        markerDistanceM: markerDistanceM,
        crossedBoarding: crossedBoarding,
      )) {
        _holdBoardingApproach(
          holdPoint: holdPoint,
          currentM: marker,
          atMs: atMs,
        );
        return;
      }
    }
    if (_acceptBoardingApproachShadowEvidence(
      result: result,
      confirmedSteps: confirmedSteps,
      latestPeakId: latestPeakId,
      holdPoint: holdPoint,
    )) {
      _holdBoardingApproach(
        holdPoint: holdPoint,
        currentM: result.previewPosition,
        atMs: atMs,
      );
      return;
    }
    final hasNewConfirmedStep =
        previousConfirmedSteps != null &&
        confirmedSteps > previousConfirmedSteps;
    if (!sawNewOptimisticStep &&
        hasNewConfirmedStep &&
        vestibule != null &&
        _isConfirmedForwardOnRouteEdge(
          route: route,
          graph: graph,
          result: result,
          edgeIndex: route.edgeIds.length - 2,
          allowJunctionAmbiguity: true,
        ) &&
        _acceptBoardingVestibuleEvidence(
          markerDistanceM:
              (vestibule.pointM - result.correctedPosition).distance,
          crossedVestibule: false,
        )) {
      _holdBoardingApproach(
        holdPoint: holdPoint,
        currentM: result.correctedPosition,
        atMs: atMs,
      );
      return;
    }
    if (sawNewOptimisticStep || !hasNewConfirmedStep) {
      return;
    }
    if (!_isConfirmedForwardOnFinalRouteEdge(
      route: route,
      graph: graph,
      result: result,
    )) {
      _rejectBoardingNodeApproachEvidence();
      return;
    }
    final crossedBoarding = result.lastConfirmedNodeId == boardingNodeId;
    if (_acceptBoardingApproachEvidence(
      markerDistanceM: (holdPoint - result.correctedPosition).distance,
      crossedBoarding: crossedBoarding,
    )) {
      _holdBoardingApproach(
        holdPoint: holdPoint,
        currentM: result.correctedPosition,
        atMs: atMs,
      );
    }
  }

  /// 짧은 마지막 간선으로 에스컬레이터에 직접 붙는 직전 노드.
  ///
  /// 이 노드에서는 사람이 graph의 마지막 직각을 정확히 밟지 않고 눈앞의 발판을
  /// 탈 수 있다. 마지막 간선이 기존 물리 허가 반경(6m) 안일 때만 전실로 인정해,
  /// 긴 일반 복도 초입에서 마커가 멈추는 실패를 막는다.
  ({String nodeId, PdrLocalPoint pointM})? _boardingVestibule({
    required IndoorRoute route,
    required FloorGraph graph,
    required String boardingNodeId,
  }) {
    if (route.nodeIds.length < 3 || route.edgeIds.length < 2) return null;
    if (route.nodeIds.last != boardingNodeId) return null;
    final vestibuleNodeId = route.nodeIds[route.nodeIds.length - 2];
    final edge = graph.edges
        .where((item) => item.id == route.edgeIds.last)
        .firstOrNull;
    if (edge == null || edge.lengthM > _escalator.config.armRadiusM) {
      return null;
    }
    final directlyConnected =
        (edge.fromNodeId == vestibuleNodeId &&
            edge.toNodeId == boardingNodeId) ||
        (edge.toNodeId == vestibuleNodeId && edge.fromNodeId == boardingNodeId);
    if (!directlyConnected) return null;
    final node = graph.nodes
        .where((item) => item.id == vestibuleNodeId)
        .firstOrNull;
    if (node == null) return null;
    return (nodeId: node.id, pointM: PdrLocalPoint(node.xM, node.yM));
  }

  bool _optimisticStepReachedBoardingVestibule({
    required OptimisticStepAdvance step,
    required IndoorRoute route,
    required FloorGraph graph,
    required String vestibuleNodeId,
  }) {
    if (step.leaderRelocated ||
        step.previewIsAmbiguous ||
        !step.crossedNodeIds.contains(vestibuleNodeId)) {
      return false;
    }
    final incomingIndex = route.edgeIds.length - 2;
    final edgeId = route.edgeIds[incomingIndex];
    final edge = graph.edges.where((item) => item.id == edgeId).firstOrNull;
    if (edge == null) return false;
    final routeFrom = route.nodeIds[incomingIndex];
    final expectedSign =
        edge.fromNodeId == routeFrom && edge.toNodeId == vestibuleNodeId
        ? 1
        : edge.toNodeId == routeFrom && edge.fromNodeId == vestibuleNodeId
        ? -1
        : 0;
    if (expectedSign == 0) return false;
    return step.traversals.any(
      (item) => item.edgeId == edgeId && item.edgeDirectionSign == expectedSign,
    );
  }

  bool _acceptBoardingVestibuleEvidence({
    required double markerDistanceM,
    required bool crossedVestibule,
  }) {
    final wasApproaching =
        _boardingVestibuleLastDistanceM == null ||
        markerDistanceM <= _boardingVestibuleLastDistanceM! + 0.1;
    _boardingVestibuleLastDistanceM = markerDistanceM;
    if (!crossedVestibule &&
        (markerDistanceM > boardingApproachVisibleSnapRadiusM ||
            !wasApproaching)) {
      _boardingVestibuleEvidencePeaks = 0;
      return false;
    }
    _boardingVestibuleEvidencePeaks++;
    return crossedVestibule ||
        _boardingVestibuleEvidencePeaks >= boardingApproachVisiblePeakCount;
  }

  bool _acceptBoardingApproachShadowEvidence({
    required CorridorTrackingResult result,
    required int confirmedSteps,
    required int? latestPeakId,
    required PdrLocalPoint holdPoint,
  }) {
    final shadowM = _boardingApproachShadowM;
    if (shadowM == null) return false;
    var hasNewStep = false;
    if (latestPeakId != null &&
        latestPeakId != _boardingApproachShadowLastPeakId) {
      _boardingApproachShadowLastPeakId = latestPeakId;
      hasNewStep = true;
    } else if (latestPeakId == null) {
      final previousConfirmed = _boardingApproachShadowLastConfirmedSteps;
      _boardingApproachShadowLastConfirmedSteps = confirmedSteps;
      hasNewStep =
          previousConfirmed != null && confirmedSteps > previousConfirmed;
    }
    if (!hasNewStep) return false;

    final distanceM = (holdPoint - shadowM).distance;
    final wasApproaching =
        _boardingApproachShadowLastDistanceM == null ||
        distanceM <= _boardingApproachShadowLastDistanceM! + 0.1;
    _boardingApproachShadowLastDistanceM = distanceM;
    if (distanceM > _escalator.config.boardingApproachRadiusM ||
        !wasApproaching) {
      _boardingApproachShadowEvidencePeaks = 0;
      return false;
    }
    _boardingApproachShadowEvidencePeaks++;
    return _boardingApproachShadowEvidencePeaks >=
        boardingApproachVisiblePeakCount;
  }

  void _holdBoardingApproach({
    required PdrLocalPoint holdPoint,
    required PdrLocalPoint currentM,
    required int atMs,
  }) {
    _approachHoldPointM =
        (holdPoint - currentM).distance <= boardingApproachVisibleSnapRadiusM
        ? holdPoint
        : currentM;
    _approachHoldEnteredAtMs = atMs;
  }

  bool _isConfirmedForwardOnFinalRouteEdge({
    required IndoorRoute route,
    required FloorGraph graph,
    required CorridorTrackingResult result,
  }) {
    return _isConfirmedForwardOnRouteEdge(
      route: route,
      graph: graph,
      result: result,
      edgeIndex: route.edgeIds.length - 1,
    );
  }

  bool _isConfirmedForwardOnRouteEdge({
    required IndoorRoute route,
    required FloorGraph graph,
    required CorridorTrackingResult result,
    required int edgeIndex,
    bool allowJunctionAmbiguity = false,
  }) {
    if (edgeIndex < 0 ||
        edgeIndex >= route.edgeIds.length ||
        route.nodeIds.length != route.edgeIds.length + 1 ||
        result.state == CorridorTrackingState.uncertain ||
        (!allowJunctionAmbiguity && result.previewIsAmbiguous) ||
        result.leaderRelocated) {
      return false;
    }
    final edgeId = route.edgeIds[edgeIndex];
    final edge = graph.edges.where((item) => item.id == edgeId).firstOrNull;
    if (edge == null || result.currentEdgeId != edgeId) return false;
    final routeFrom = route.nodeIds[edgeIndex];
    final routeTo = route.nodeIds[edgeIndex + 1];
    final expectedSign =
        edge.fromNodeId == routeFrom && edge.toNodeId == routeTo
        ? 1
        : edge.fromNodeId == routeTo && edge.toNodeId == routeFrom
        ? -1
        : 0;
    return expectedSign != 0 && result.travelDirectionSign == expectedSign;
  }

  bool _acceptBoardingApproachEvidence({
    required double markerDistanceM,
    required bool crossedBoarding,
  }) {
    final wasApproaching =
        _boardingApproachLastDistanceM == null ||
        markerDistanceM <= _boardingApproachLastDistanceM! + 0.1;
    _boardingApproachLastDistanceM = markerDistanceM;
    if (!crossedBoarding &&
        (markerDistanceM > _escalator.config.boardingApproachRadiusM ||
            !wasApproaching)) {
      _boardingApproachEvidencePeaks = 0;
      return false;
    }
    _boardingApproachEvidencePeaks++;
    return crossedBoarding ||
        _boardingApproachEvidencePeaks >= boardingApproachVisiblePeakCount;
  }

  void _rejectBoardingApproachEvidence() {
    _rejectBoardingNodeApproachEvidence();
    _boardingVestibuleEvidencePeaks = 0;
    _boardingVestibuleLastDistanceM = null;
  }

  void _rejectBoardingNodeApproachEvidence() {
    _boardingApproachEvidencePeaks = 0;
    _boardingApproachLastDistanceM = null;
  }

  /// 기압 샘플 한 건을 판정기에 넣는다.
  ///
  /// 부착 상태가 아니면 **넣지 않는다.** 야외에서 오르내린 고도가 실내 판정의
  /// 0점을 흔들면, 건물에 들어서자마자 있지도 않은 층 이동이 잡힌다.
  EscalatorAltitudeOutcome onAltitude(AltitudeSample sample) {
    if (!_attached) return const EscalatorAltitudeOutcome();
    final confirmed = _escalator.onAltitude(sample);
    if (_escalator.hasRouteVerticalMotionLock) {
      _verticalObservationHoldPointM ??= _corridor.result?.previewPosition;
    } else {
      _verticalObservationHoldPointM = null;
    }
    return EscalatorAltitudeOutcome(
      started: _escalator.takeStartedTransition(),
      cancelled: _escalator.takeCancelledTransition(),
      confirmed: confirmed,
      events: _escalator.takeEvents(),
    );
  }

  void onRawMotion(RawMotionActivity activity) {
    if (!_attached) return;
    _escalator.onRawMotion(activity);
  }

  /// 쌓인 단계 전이를 꺼내면서 탑승점 고정을 함께 갱신한다.
  ///
  /// 고정을 **여기 한 곳에서만** 걸고 푼다. 화면이 따로 조건을 세면 판정기가
  /// 멀어짐·타임아웃으로 단계를 취소했을 때 한쪽에 고정이 남는다.
  List<EscalatorPhaseChange> takePhaseChanges() {
    if (!_attached) return const [];
    final changes = _escalator.takePhaseChanges();
    for (final change in changes) {
      final currentM = _corridor.result?.previewPosition;
      switch (change.phase) {
        case EscalatorPhase.boardingDetected:
          _boardingHoldPointM =
              _approachHoldPointM ??
              _visibleBoardingHold(
                holdPoint: _routeBoardingHoldPoint(change),
                currentM: currentM,
              );
        case EscalatorPhase.verticalMotionDetected:
          _boardingHoldPointM = clampBoardingHold(
            holdPoint: _routeBoardingHoldPoint(change),
            currentM: currentM,
          );
          _rideHoldPointM = clampBoardingHold(
            holdPoint:
                _routeBoardingHoldPoint(change) ??
                _detectorBoardingNodePoint(change),
            currentM: currentM,
          );
        case EscalatorPhase.cancelled:
        case EscalatorPhase.failed:
        case EscalatorPhase.idle:
          clearBoardingHold();
        case EscalatorPhase.midpointReached:
        case EscalatorPhase.landed:
          break;
      }
    }
    return changes;
  }

  PdrLocalPoint? _visibleBoardingHold({
    required PdrLocalPoint? holdPoint,
    required PdrLocalPoint? currentM,
  }) {
    if (holdPoint == null) return currentM;
    if (currentM == null) return holdPoint;
    return (holdPoint - currentM).distance <= boardingApproachVisibleSnapRadiusM
        ? holdPoint
        : currentM;
  }

  /// 판정기가 고른 탑승 노드의 좌표. 경로가 지목한 노드가 아니어도 쓴다 —
  /// 수직 이동이 확인된 뒤라 "에스컬레이터 위"라는 사실 자체는 이미 근거가 있다.
  ///
  /// 앵커가 다른 층에 있으면 null이다. 그때의 local m은 남의 층 좌표라, 고정할
  /// 자리로 쓰면 마커를 엉뚱한 곳에 못 박는다.
  PdrLocalPoint? _detectorBoardingNodePoint(EscalatorPhaseChange change) {
    final nodeId = change.boardingNodeId;
    if (nodeId == null || _anchor?.floorId != _floorId) return null;
    final node = _graph?.nodes.where((n) => n.id == nodeId).firstOrNull;
    return node == null ? null : PdrLocalPoint(node.xM, node.yM);
  }

  PdrLocalPoint? _routeBoardingHoldPoint(EscalatorPhaseChange change) =>
      routeBoardingHoldPoint(
        boardingNodeId: change.boardingNodeId,
        anchorFloorId: _anchor?.floorId,
        displayedFloorId: _floorId,
        multiFloorRoute: _multiFloorRoute,
        graph: _graph,
      );

  /// 지금 화면이 그려야 하는 위치와 그 출처.
  ///
  /// 우선순위가 이 함수의 전부다.
  ///
  /// 1. **보정된 걸음 위치**(tracked) — 앵커가 이 층에 있고 보정 결과가 있다.
  /// 2. **앵커 자리**(anchorOnly) — 앵커는 이 층에 있는데 아직 걸음이 없다.
  /// 3. **추정점**(estimate) — 앵커가 없거나 다른 층이다. 신선한 값만.
  ///
  /// 순서가 뒤집히면 안 되는 이유는 3번이 30초까지 살아 있기 때문이다. 추정을
  /// 먼저 보면, 걸어서 이미 20m를 이동한 사용자를 30초 전 GPS 자리로 되돌린다.
  GuidancePosition? get position {
    if (!_attached) return null;

    final anchor = _anchor;
    final onThisFloor = anchor != null && anchor.floorId == _floorId;

    if (onThisFloor) {
      final result = _corridor.result;
      if (result != null) {
        // 수평 보행의 실제 마커는 항상 optimistic tracker 위치다. 파란선 진행률
        // 보호가 이 값을 붙들면 첫 역방향 걸음과 실제 이탈이 화면에서 사라진다.
        // 에스컬레이터 근거가 만든 명시적 고정만 tracker보다 우선한다.
        return GuidancePosition(
          localM:
              _rideHoldPointM ??
              _boardingHoldPointM ??
              _verticalObservationHoldPointM ??
              _approachHoldPointM ??
              result.previewPosition,
          source: GuidancePositionSource.tracked,
          headingDeg: _floorHeadingDeg(anchor),
        );
      }
      return GuidancePosition(
        localM: anchor.anchorLocalM,
        source: GuidancePositionSource.anchorOnly,
      );
    }

    final estimate = _estimate;
    if (estimate == null ||
        estimate.buildingId != _buildingId ||
        estimate.floorId != _floorId ||
        !estimate.isFresh(_now())) {
      return null;
    }
    return GuidancePosition(
      localM: estimate.localM,
      source: GuidancePositionSource.estimate,
      accuracyM: estimate.accuracyMeters,
    );
  }

  // --- 경로 진행률 ---
  //
  // 진행률에 얽힌 상태를 **여기 한 곳에** 모은다. 예전에는 화면이
  // `_routeProgress`·`_lastRouteTraveledM`·`_lastRouteProgressAcceptedSteps`·
  // `_lastRouteEvaluatedSteps`와 이탈 증거 카운터를 직접 들고, 경로를 새로 뽑을
  // 때마다 열 군데 가까이에서 같은 묶음을 손으로 맞췄다. 한 곳만 빠뜨려도 새
  // 경로의 남은거리가 이전 경로 기준으로 계산된다.

  final TravelDirectionTracker _travelDirection = TravelDirectionTracker();
  final RouteCheckpointShadowTracker _checkpoints =
      RouteCheckpointShadowTracker();

  IndoorRoute? _routeSegment;
  IndoorRoute? _progressRoute;
  int _routeGeneration = 0;
  RouteProgress? _displayProgress;
  RouteProgress? _measuredProgress;
  double? _lastTraveledM;
  int? _lastAcceptedSteps;
  int? _lastEvaluatedSteps;

  int _offRouteEvidenceUpdates = 0;
  int? _offRouteFirstEvidenceAtMs;
  int? _junctionZoneEnteredAtMs;

  /// 이미 재탐색을 요청한 경로 밖 간선. 같은 간선 위에 계속 있는 동안에는
  /// 경로가 새로 계산돼도 또 이탈한 것으로 취급하지 않는다. 새 간선으로 실제
  /// 이동하거나 경로 위로 돌아오면 비워 다음 이탈은 다시 잡는다.
  String? _rerouteRequestedForEdgeId;

  /// 지금 이 층에 그려진 경로 세그먼트. 화면도 이 값을 읽어 폴리라인을 그린다.
  IndoorRoute? get routeSegment => _routeSegment;

  /// 화면이 그리는 진행률. 튐·후퇴를 보류한 결과다.
  RouteProgress? get displayProgress => _displayProgress;

  /// 보류 전 원본. 진단 로그와 도착 판정이 쓴다.
  RouteProgress? get measuredProgress => _measuredProgress;

  TravelDirectionState get travelDirectionState => _travelDirection.state;
  int get routeGeneration => _routeGeneration;

  /// 이 층에 그릴 세그먼트를 바꾼다. 진행률 기준점은 [seedProgress]가 정한다.
  void setRouteSegment(IndoorRoute? route) {
    _routeSegment = route;
    // 사용자가 새 목적지를 고르는 흐름은 먼저 세그먼트를 비운다. 이전 여정의
    // 이탈 잠금이 새 길찾기에 남으면 같은 복도에서 재탐색을 못 하게 된다.
    if (route == null) _rerouteRequestedForEdgeId = null;
  }

  /// 진행률 기준점을 통째로 다시 잡는다.
  ///
  /// 경로를 새로 뽑았거나 층 세그먼트를 갈아탄 직후다. [progress]가 null이면
  /// "아직 아무것도 모른다"는 상태이고, 다음 걸음이 시작점 근처면
  /// [updateProgress]가 알아서 seed한다.
  void seedProgress(RouteProgress? progress, {int? atSteps}) {
    _displayProgress = progress;
    _measuredProgress = progress;
    _lastTraveledM = progress?.traveledM;
    _lastAcceptedSteps = progress == null ? null : atSteps;
    _lastEvaluatedSteps = null;
    _offRouteEvidenceUpdates = 0;
    _offRouteFirstEvidenceAtMs = null;
  }

  /// 안내가 끝났다. 진행률과 이탈 증거를 모두 버린다.
  void clearProgress() {
    _progressRoute = null;
    _travelDirection.reset();
    _rerouteRequestedForEdgeId = null;
    seedProgress(null);
  }

  /// 보정 위치를 이 층 경로에 투영해 진행 상태를 낸다.
  ///
  /// 경로는 이 계산의 **입력이 아니라 출력 쪽**에만 있다 — tracker에는 아무것도
  /// 되돌려주지 않으므로, 경로가 위치 추정을 끌어당기는 일이 구조적으로
  /// 불가능하다.
  GuidanceProgressUpdate updateProgress(
    CorridorTrackingResult? result, {
    int? previewSteps,
    int? confirmedSteps,
    double? orientationHeadingDeg,
    double? walkingHeadingDeg,
    bool rerouteInFlight = false,
    bool onEscalator = false,
    int? nowMs,
  }) {
    final route = _routeSegment;
    if (route == null || result == null) {
      if (route == null) {
        _progressRoute = null;
        _travelDirection.reset();
      }
      final hadProgress = _displayProgress != null || _lastTraveledM != null;
      if (hadProgress) seedProgress(null);
      return GuidanceProgressUpdate(cleared: hadProgress);
    }

    final routeChanged = !identical(_progressRoute, route);
    if (routeChanged) {
      _progressRoute = route;
      _routeGeneration += 1;
      _travelDirection.reset();
      final graph = _graph;
      if (graph != null) {
        _checkpoints.configure(
          routeGeneration: _routeGeneration,
          route: route,
          graph: graph,
        );
      }
    }

    final advances = <GuidanceStepAdvance>[];
    final events = <RouteCheckpointEvent>[];
    var trustedForwardDistanceM = 0.0;
    var trustedReverseDistanceM = 0.0;
    final graph = _graph;
    if (graph != null) {
      for (final optimisticStep in result.optimisticStepAdvances) {
        final routeStep = adaptOptimisticStepToRoute(
          step: optimisticStep,
          graph: graph,
          routeEdgeIds: route.edgeIds,
          routeNodeIds: route.nodeIds,
          orientationHeadingDeg: orientationHeadingDeg,
          walkingHeadingDeg: walkingHeadingDeg,
        );
        final transition = _travelDirection.apply(routeStep);
        if (!routeStep.previewIsAmbiguous) {
          switch (routeStep.relation) {
            case RouteStepRelation.forward:
              trustedForwardDistanceM += routeStep.signedRouteDistanceM;
            case RouteStepRelation.reverse:
              trustedReverseDistanceM += routeStep.signedRouteDistanceM.abs();
            case RouteStepRelation.offRoute:
            case RouteStepRelation.ambiguous:
            case RouteStepRelation.relocated:
              break;
          }
        }
        advances.add(
          GuidanceStepAdvance(step: routeStep, transition: transition),
        );
        events.addAll(
          _checkpoints.apply(
            step: routeStep,
            travelDirectionState: _travelDirection.state,
            trackerPreviewPosition: result.previewPosition,
            trackerState: result.state,
            graph: graph,
            rerouteInFlight: rerouteInFlight,
          ),
        );
      }
    }

    // 에스컬레이터 위나 탑승점 고정 구간에서는 진행 상태를 갱신하지 않는다.
    // 위치가 한 지점에 묶여 있어 그 투영은 "경로를 벗어났다"는 오판만 만들고,
    // 곧 층이 바뀔 자리에서 재탐색을 돌린다.
    //
    // 탑승점 **접근**은 여기서 막지 않는다 — 그 반경(16m)은 아직 걸어가는 중인
    // 거리라 남은거리까지 얼려 버리면 ETA가 16m 전부터 멈춘다. 접근은 아래에서
    // 재탐색만 막는다.
    if (onEscalator || isPositionHeld) {
      return GuidanceProgressUpdate(
        displayProgress: _displayProgress,
        measuredProgress: _measuredProgress,
        stepAdvances: advances,
        checkpointEvents: events,
        travelDirectionState: _travelDirection.state,
        routeChanged: routeChanged,
      );
    }

    final localPosition = LocalPoint(
      result.previewPosition.eastM,
      result.previewPosition.northM,
    );
    final first = route.pointsLocalM.isEmpty ? null : route.pointsLocalM.first;
    final atNewRouteStart =
        _displayProgress == null &&
        first != null &&
        math.sqrt(
              math.pow(localPosition.x - first.x, 2) +
                  math.pow(localPosition.y - first.y, 2),
            ) <=
            0.5;
    final progress = atNewRouteStart
        ? seedRouteProgressAtRouteStart(
            routePointsLocalM: route.pointsLocalM,
            routeEdgeIds: route.edgeIds.toSet(),
            currentEdgeId: result.optimisticEdgeId,
            headingDeg: orientationHeadingDeg,
          )
        : computeRouteProgress(
            routePointsLocalM: route.pointsLocalM,
            routeEdgeIds: route.edgeIds.toSet(),
            // 표시 위치와 같은 값을 쓴다. 확정 위치로 계산하면 화면의 마커와
            // 남은거리가 서로 다른 시점을 가리킨다.
            position: localPosition,
            currentEdgeId: result.optimisticEdgeId,
            // orientation은 경로 접선과의 오차를 진단하는 데만 쓴다. 역방향
            // 안내와 display 후퇴 허용은 peak traversal 상태기가 결정한다.
            headingDeg: orientationHeadingDeg,
            previousTraveledM: _lastTraveledM,
          );
    if (progress == null) {
      return GuidanceProgressUpdate(
        displayProgress: _displayProgress,
        measuredProgress: _measuredProgress,
        stepAdvances: advances,
        checkpointEvents: events,
        travelDirectionState: _travelDirection.state,
        routeChanged: routeChanged,
      );
    }

    final previous = _displayProgress;
    final responsiveSteps = previewSteps ?? confirmedSteps;
    // **순서가 중요하다.** 이탈 증거를 이번 프레임 값으로 올린 **뒤에** hold를
    // 판단해야 한다. 뒤집으면 이탈 첫 프레임의 표시값이 한 박자 늦게 붙들려,
    // 재탐색 직전에 마커가 경로 밖으로 한 번 튀었다 돌아온다.
    // 증거는 그대로 쌓되 **걸지만 않는다**(`rerouteInFlight`와 같은 모양이다).
    // 탑승점을 정말 지나쳐 걸어간 사람은 게이트가 닫히는 즉시 쌓인 증거로 재탐색이
    // 나가고, 타고 있는 사람은 그 전에 수직 이동 근거가 이어받는다.
    final shouldReroute =
        _updateDeviationEvidence(
          progress: progress,
          result: result,
          confirmedOffRoute: _hasConfirmedOffRouteEdge(result, route),
          steps: responsiveSteps,
          rerouteInFlight: rerouteInFlight,
          nowMs: nowMs ?? _nowMs(),
        ) &&
        !isNearRouteBoarding;
    if (shouldReroute) {
      // 이탈이 확정됐는데도 옛 경로의 continuity shadow를 계속 쓰면 새 경로의
      // 출발점이 뒤에 남고, 화면 마커도 복도 밖을 떠다닌다. 재탐색 요청과 같은
      // 틱에 현재 map-matched preview로 붙인다.
      _corridor.snapMarkerToMatchedPreview();
    }
    var holdReason = _holdReason(previous, progress, responsiveSteps);
    var display = holdReason == null ? progress : previous!;
    if (holdReason == 'implausibleJump' && previous != null) {
      final movingForward = progress.traveledM > previous.traveledM;
      final movementBudgetM = movingForward
          ? trustedForwardDistanceM
          : _travelDirection.state == TravelDirectionState.reverseConfirmed
          ? trustedReverseDistanceM
          : 0.0;
      if (movementBudgetM > 1e-6) {
        display = moveRouteProgressToward(
          previous: previous,
          candidate: progress,
          routePointsLocalM: route.pointsLocalM,
          maxDistanceM: movementBudgetM,
        );
        holdReason = 'boundedReconcile';
      }
    }

    _displayProgress = display;
    _measuredProgress = progress;
    _lastTraveledM = progress.traveledM;
    if (holdReason == null || holdReason == 'boundedReconcile') {
      _lastAcceptedSteps = responsiveSteps;
    }

    return GuidanceProgressUpdate(
      displayProgress: display,
      measuredProgress: progress,
      holdReason: holdReason,
      stepAdvances: advances,
      checkpointEvents: events,
      travelDirectionState: _travelDirection.state,
      routeChanged: routeChanged,
      shouldReroute: shouldReroute,
    );
  }

  /// 이탈 증거를 갱신하고, 재탐색을 걸 때가 됐으면 true.
  ///
  /// 걸음 개수를 임계값으로 쓰면 네이티브 이벤트 한 번에 여러 걸음이 묶여 들어올
  /// 때 한 프레임만으로 이탈이 확정될 수 있다. 시간과 독립 갱신 횟수를 함께
  /// 요구해 교차점 흔들림은 흡수하되 실제 이탈은 1~2초 안에 잡는다.
  bool _updateDeviationEvidence({
    required RouteProgress progress,
    required CorridorTrackingResult result,
    required bool confirmedOffRoute,
    required int? steps,
    required bool rerouteInFlight,
    required int nowMs,
  }) {
    if (result.isInJunctionZone) {
      _junctionZoneEnteredAtMs ??= nowMs;
    } else {
      _junctionZoneEnteredAtMs = null;
    }

    final headingStillFollowsRoute =
        progress.headingErrorDeg == null || progress.headingErrorDeg! <= 65;
    // 그래프에는 모든 실제 보행선을 넣을 수 없다. 가까운 평행 통로를 따라
    // 가면서 방향도 경로와 같으면, 간선 id가 달라도 안내 경로의 오차로 본다.
    final routeLikeMovement =
        progress.offsetM <= 2.5 && headingStillFollowsRoute;
    final strongDeviation =
        (progress.offsetM >= 5.5 && !headingStillFollowsRoute) ||
        (progress.reacquired && !headingStillFollowsRoute);
    final deviated =
        confirmedOffRoute || !progress.onRouteEdge || strongDeviation;
    if (!deviated ||
        (!confirmedOffRoute && routeLikeMovement) ||
        result.optimisticEdgeId == null ||
        result.state == CorridorTrackingState.uncertain) {
      if (!deviated) _rerouteRequestedForEdgeId = null;
      _offRouteEvidenceUpdates = 0;
      _offRouteFirstEvidenceAtMs = null;
      _lastEvaluatedSteps = steps;
      return false;
    }
    // 교차점을 통과하는 동안에는 증거를 **새로 쌓지 않는다**. 기존 증거는
    // 지우지 않는다 — 구간을 빠져나온 뒤 실제 이탈이면 그 자리에서 이어 간다.
    final junctionSinceMs = _junctionZoneEnteredAtMs;
    if (junctionSinceMs != null &&
        nowMs - junctionSinceMs < junctionRerouteHoldMs) {
      return false;
    }
    if (steps == null || steps == _lastEvaluatedSteps) return false;
    _lastEvaluatedSteps = steps;
    _offRouteFirstEvidenceAtMs ??= nowMs;
    _offRouteEvidenceUpdates++;
    final evidenceDurationMs = nowMs - _offRouteFirstEvidenceAtMs!;
    final requiredUpdates = strongDeviation ? 2 : 3;
    final requiredDurationMs = strongDeviation ? 700 : 1200;
    final offRouteEdgeId = result.currentEdgeId ?? result.optimisticEdgeId;
    final ready =
        _offRouteEvidenceUpdates >= requiredUpdates &&
        evidenceDurationMs >= requiredDurationMs &&
        !rerouteInFlight;
    if (!ready || offRouteEdgeId == _rerouteRequestedForEdgeId) return false;
    _rerouteRequestedForEdgeId = offRouteEdgeId;
    return true;
  }

  /// 표시 마커는 continuity shadow 때문에 잠시 옛 경로에 남을 수 있다. 이탈
  /// 판정은 그 그림이 아니라 확정 beam의 간선으로도 확인해야 한다.
  bool _hasConfirmedOffRouteEdge(
    CorridorTrackingResult result,
    IndoorRoute route,
  ) {
    final edgeId = result.currentEdgeId;
    return edgeId != null &&
        !route.edgeIds.contains(edgeId) &&
        !result.previewIsAmbiguous &&
        result.state != CorridorTrackingState.uncertain;
  }

  /// 표시값을 이전 것으로 붙들 이유가 있으면 그 이름, 없으면 null.
  ///
  /// 이름을 돌려주는 이유는 로그 때문이다. "붙들었다"만 알면 실측에서 어느
  /// 조건이 걸렸는지 되짚을 수 없다.
  String? _holdReason(
    RouteProgress? previous,
    RouteProgress candidate,
    int? responsiveSteps,
  ) {
    if (previous == null) return null;
    if (!candidate.onRouteEdge && _offRouteEvidenceUpdates > 0) {
      return 'pendingDeviation';
    }
    if (shouldHoldImplausibleRouteJump(
      previous: previous,
      candidate: candidate,
      acceptedAtSteps: _lastAcceptedSteps,
      currentSteps: responsiveSteps,
    )) {
      return 'implausibleJump';
    }
    if (shouldHoldDisplayRouteRegression(
      previous: previous,
      candidate: candidate,
      travelDirectionState: _travelDirection.state,
    )) {
      return 'regression';
    }
    return null;
  }

  /// 마커 원뿔이 쓰는 층 기준 방향.
  ///
  /// 간선 방위(`previewHeadingDeg`)가 아니라 orientation heading을 쓴다. 간선
  /// 방위는 걸음이 있어야 갱신되고 직선 복도에서는 제자리 회전에 반응하지
  /// 않아서, 서서 몸을 돌리면 화면 방향이 얼어붙는다.
  double? _floorHeadingDeg(PdrAnchor anchor) {
    final snapshot = _snapshot;
    if (snapshot == null) return null;
    final floorHeading = FloorCoordinateTransform(
      anchor,
    ).toFloorBearing(snapshot.orientationHeadingDeg);
    // tracker의 correction은 floor frame에서 배웠다. PDR 헤딩에 먼저 더하면
    // y축이 반전된 도면에서 부호가 뒤집히므로 변환이 끝난 뒤 정확히 한 번만 더한다.
    return normalizePdrBearing(
      floorHeading + (_corridor.result?.headingBiasDeg ?? 0),
    );
  }
}
