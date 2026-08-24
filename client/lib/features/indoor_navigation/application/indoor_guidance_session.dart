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

/// 고정 지점이 지금 위치에서 이만큼 넘게 떨어져 있으면 **그 자리에 세운다**.
///
/// 고정은 원래 "탑승점을 지나 앞 매장으로 흘러가는 것"을 막으려는 것이다.
/// 그런데 판정이 이르거나 틀렸을 때 먼 노드로 스냅하면 마커가 눈에 띄게 뒤로
/// 순간이동하고, 사용자는 그걸 "위치가 튄다"로 읽는다 — 막으려던 것보다 나쁜
/// 그림이다. 6m는 랜딩 폭과 보정 오차를 감안한 값으로, 실제로 탑승점에 서
/// 있으면 이 안에 든다.
const boardingHoldSnapRadiusM = 6.0;

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

  /// 고도 근거가 오기 **전에** 탑승점 하나만으로 거는 고정 지점.
  ///
  /// 위 둘과 달리 단계 전이가 아니라 [_syncBoardingApproach]가 매 스냅샷 갱신한다.
  /// 탑승 직후 몇 초는 판정기가 idle이라 단계가 아예 안 나오기 때문이다.
  PdrLocalPoint? _approachHoldPointM;

  /// 경로가 지목한 탑승점까지의 거리(m). 그런 탑승점이 없으면 null.
  double? _boardingApproachDistanceM;

  /// 넓은 반경 안에 처음 들어선 시각. 밖으로 나가야 다시 잡힌다(시간 탈출구).
  int? _boardingApproachSinceMs;

  /// 탑승점 근거만으로 재탐색을 막는 구간인지. [_syncBoardingApproach]가 정한다.
  bool _boardingApproachGateOpen = false;

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
    _approachHoldPointM = null;
  }

  /// 접근 근거 자체를 버린다. [clearBoardingHold]와 나눈 이유는 **시간 상한** 때문이다 —
  /// 고정을 푸는 자리마다 시각까지 지우면 탑승점 앞에 계속 서 있어도 상한이 매번
  /// 처음부터 다시 세어져 탈출구가 사라진다.
  void _clearBoardingApproach() {
    _boardingApproachDistanceM = null;
    _boardingApproachSinceMs = null;
    _boardingApproachGateOpen = false;
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
    final result = _corridor.update(
      graph: _graph,
      anchor: anchor,
      snapshot: snapshot,
      timestampMs: atMs,
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
    if (segment != null &&
        segment.transferModeToNext == 'escalator' &&
        segment.transferFromNodeId != null &&
        route != null &&
        route.pointsLocalM.isNotEmpty) {
      final routeEnd = route.pointsLocalM.last;
      _escalator.onEscalatorRouteApproach(
        positionM: result.previewPosition,
        routeEndM: PdrLocalPoint(routeEnd.x, routeEnd.y),
        expectedBoardingNodeId: segment.transferFromNodeId!,
        expectedArrivalNodeId: segment.transferToNodeId,
        steps: steps,
        timestampMs: atMs,
        immediateTransfer: route.distanceMeters <= consecutiveTransferRouteM,
      );
    }
    _syncBoardingApproach(
      boardingNodeId: segment?.transferFromNodeId,
      currentM: result.previewPosition,
      atMs: atMs,
    );
  }

  /// 고도가 오기 **전** 구간을 탑승점 하나로 표현한다.
  ///
  /// 판정기는 Δ가 `minDeltaM`(1.2m)만큼 변해야 후보를 여는데, 탑승 직후 몇 초는
  /// 계단이 아직 사람을 안 올려 Δ가 0이다. 그 사이 걸음이 계속 옆 복도로 스냅되고
  /// 이탈 증거가 쌓여 재탐색이 돌았다(2026-08-20 실기기).
  ///
  /// 근거의 세기가 달라 문턱을 둘로 나눈다. 표는
  /// `docs/client/escalator-thresholds.md`가 단일 출처다.
  /// - **재탐색 차단**: `routeApproachArmRadiusM`(16m). 틀려도 몇 초 늦을 뿐이다.
  /// - **위치 고정**: [boardingHoldSnapRadiusM](6m)에서 걸고
  ///   `boardingAbandonRadiusM`(8m)에서 푼다. 탑승점을 지나 발판에 올라서는 동안
  ///   거리가 늘어나는 것은 이탈이 아니라 탑승의 모양이라 넓게 푼다.
  ///
  /// 탈출구가 둘이다 — 탑승점에서 멀어지면 그 자리에서 풀리고, 반경 안에 머물러도
  /// `boardingPhaseTimeoutMs`(40초)가 지나면 접는다. 판정기가 배너를 접는 규칙과
  /// 같은 거리·시간을 쓴다.
  void _syncBoardingApproach({
    required String? boardingNodeId,
    required PdrLocalPoint currentM,
    required int atMs,
  }) {
    final holdPoint = routeBoardingHoldPoint(
      boardingNodeId: boardingNodeId,
      anchorFloorId: _anchor?.floorId,
      displayedFloorId: _floorId,
      multiFloorRoute: _multiFloorRoute,
      graph: _graph,
    );
    final config = _escalator.config;
    final distanceM = holdPoint == null
        ? null
        : (holdPoint - currentM).distance;
    if (distanceM == null || distanceM > config.routeApproachArmRadiusM) {
      _approachHoldPointM = null;
      _clearBoardingApproach();
      _boardingApproachDistanceM = distanceM;
      return;
    }
    _boardingApproachDistanceM = distanceM;
    final since = _boardingApproachSinceMs ??= atMs;
    if (atMs - since >= config.boardingPhaseTimeoutMs) {
      // 시간 상한. 거리로 한 번 나갔다 들어와야 다시 열린다 — 그래야 탑승점 앞에
      // 계속 서 있는 사람에게 무한히 걸리지 않는다.
      _boardingApproachGateOpen = false;
      _approachHoldPointM = null;
      return;
    }
    _boardingApproachGateOpen = true;
    if (_approachHoldPointM == null) {
      if (distanceM <= boardingHoldSnapRadiusM) _approachHoldPointM = holdPoint;
    } else if (distanceM > config.boardingAbandonRadiusM) {
      _approachHoldPointM = null;
    }
  }

  /// 기압 샘플 한 건을 판정기에 넣는다.
  ///
  /// 부착 상태가 아니면 **넣지 않는다.** 야외에서 오르내린 고도가 실내 판정의
  /// 0점을 흔들면, 건물에 들어서자마자 있지도 않은 층 이동이 잡힌다.
  EscalatorAltitudeOutcome onAltitude(AltitudeSample sample) {
    if (!_attached) return const EscalatorAltitudeOutcome();
    final confirmed = _escalator.onAltitude(sample);
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
          _boardingHoldPointM = clampBoardingHold(
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
        // 고정 중이면 걸음이 더 세어져도 그 자리다. 에스컬레이터 앞에 선 뒤의
        // 걸음은 발판 위 진동이거나 대기 중 제자리 움직임이라, 그대로 두면
        // 마커가 탑승점을 지나 앞 매장으로 흘러간다. 탑승 고정이 접근 고정을
        // 이긴다 — 늦게 잡힌 쪽이 더 강한 근거다.
        return GuidancePosition(
          localM:
              _rideHoldPointM ??
              _boardingHoldPointM ??
              _approachHoldPointM ??
              _displayTrackedPosition(result),
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

  /// 길안내 중에는 화면용으로 채택한 경로 투영점을 우선한다.
  ///
  /// tracker의 위치를 경로에 끌어당기는 것이 아니다. tracker 결과와 경로 진행률
  /// 계산은 그대로 두고, **표시할 때만** 예전 실내 화면과 같은 규칙을 적용한다.
  /// 정상적으로 경로 위에 있거나 아직 이탈 증거가 충분히 쌓이지 않았으면
  /// `projectedPoint`를 사용해 대표 간선 교체가 마커를 뒤로 밀지 않게 한다.
  /// 다만 재탐색 대기 중에는 회색선 기준인 `displayProgress`만 멈추고, 마커는
  /// tracker의 optimistic 위치를 계속 따라가야 한다. 둘을 같이 멈추면 사람이
  /// 이미 코너를 돌아 걸어가도 코너 직전에서 마커가 고정된다.
  /// 이탈이 확정됐거나 재획득한 경우에도 raw preview로 돌아가 실제 이탈을
  /// 숨기지 않는다.
  PdrLocalPoint _displayTrackedPosition(CorridorTrackingResult result) {
    // 이탈 대기(pendingDeviation)는 회색선이 센서 흔들림을 따라 늘어나지 않게
    // 하는 상태다. 위치 표시까지 이전 투영점에 붙들 이유는 없다. tracker가
    // 이미 다음 연결 간선으로 이동한 optimistic cursor를 공개하고 있으므로
    // 마커는 그 값을 쓴다. 실제 재탐색이 확정되면 다음 progress 갱신에서 새
    // 경로의 displayProgress가 다시 시작된다.
    if (_displayProgressHoldReason == 'pendingDeviation') {
      return result.previewPosition;
    }

    final progress = _displayProgress;
    final projected = progress?.projectedPoint;
    final junctionPreviewHasMoved =
        projected != null &&
        result.isInJunctionZone &&
        result.state != CorridorTrackingState.uncertain &&
        (result.previewPosition - PdrLocalPoint(projected.x, projected.y))
                .distance >
            0.75;
    if (junctionPreviewHasMoved) {
      // 교차점에서는 `currentEdgeId`·route edge 일치가 한두 peak 늦을 수 있다.
      // 이때 경로 투영점만 쓰면 outgoing 간선으로 이미 코너를 돈 preview가
      // incoming 간선 끝점에 눌린다. tracker가 연결 간선 후보를 그래프로
      // 제한하고 있으므로, 불확실 상태가 아닌 동안은 실제 preview를 쓴다.
      return result.previewPosition;
    }

    final canFollowGuidance =
        _routeSegment != null &&
        progress != null &&
        projected != null &&
        result.state != CorridorTrackingState.uncertain &&
        (progress.onRouteEdge ||
            (!progress.reacquired &&
                progress.offsetM < 4 &&
                _offRouteEvidenceUpdates < 3));
    if (!canFollowGuidance) return result.previewPosition;
    return PdrLocalPoint(projected.x, projected.y);
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
  String? _displayProgressHoldReason;

  int _offRouteEvidenceUpdates = 0;
  int? _offRouteFirstEvidenceAtMs;
  int? _junctionZoneEnteredAtMs;

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
    _displayProgressHoldReason = null;
    _offRouteEvidenceUpdates = 0;
    _offRouteFirstEvidenceAtMs = null;
  }

  /// 안내가 끝났다. 진행률과 이탈 증거를 모두 버린다.
  void clearProgress() {
    _progressRoute = null;
    _travelDirection.reset();
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
          steps: responsiveSteps,
          rerouteInFlight: rerouteInFlight,
          nowMs: nowMs ?? _nowMs(),
        ) &&
        !isNearRouteBoarding;
    final holdReason = _holdReason(previous, progress, responsiveSteps);
    final display = holdReason == null ? progress : previous!;

    _displayProgress = display;
    _measuredProgress = progress;
    _displayProgressHoldReason = holdReason;
    _lastTraveledM = progress.traveledM;
    if (holdReason == null) _lastAcceptedSteps = responsiveSteps;

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
    required int? steps,
    required bool rerouteInFlight,
    required int nowMs,
  }) {
    if (result.isInJunctionZone) {
      _junctionZoneEnteredAtMs ??= nowMs;
    } else {
      _junctionZoneEnteredAtMs = null;
    }

    final strongDeviation = progress.offsetM >= 4 || progress.reacquired;
    final deviated = !progress.onRouteEdge || strongDeviation;
    if (!deviated ||
        result.optimisticEdgeId == null ||
        result.state == CorridorTrackingState.uncertain) {
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
    return _offRouteEvidenceUpdates >= requiredUpdates &&
        evidenceDurationMs >= requiredDurationMs &&
        !rerouteInFlight;
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
    return FloorCoordinateTransform(
      anchor,
    ).toFloorBearing(snapshot.orientationHeadingDeg);
  }
}
