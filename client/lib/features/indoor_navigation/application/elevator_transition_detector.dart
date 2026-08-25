/// 기압 변화로 **엘리베이터 층 이동**을 판정한다. 화면·HTTP를 모르는 순수
/// 상태기계이고, 합성 기압 시계열로 전부 테스트된다.
///
/// 층별 고도 실측은 `docs/client/elevator-altitude-probe.md`가 단일 출처이고,
/// 임계값은 [ElevatorDetectorConfig]에 있다.
library;

import 'dart:math' as math;

import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import '../../../domain/floor/floor_altitude_table.dart';
import '../../../models/building/floor_graph.dart';
import '../contract/altitude_sample.dart';
import '../contract/raw_motion_activity.dart';
import 'elevator_arrival.dart';
import 'elevator_detector_config.dart';

export 'elevator_detector_config.dart';

/// 탑승 판정의 공개 단계.
///
/// 에스컬레이터와 단계 이름이 다른 이유는 **확정 근거가 다르기** 때문이다.
/// 에스컬레이터는 "반 층 지났다"에서 목적 층 도면을 열지만, 엘리베이터는 몇 층을
/// 갈지 미리 모르므로 중간에 열 도면이 없다. 대신 `settled`를 따로 두어
/// "섰다"와 "내렸다"를 가른다.
enum ElevatorPhase {
  idle,

  /// 엘리베이터 노드 근처이거나, 경로가 이 층에서 엘리베이터를 타라고 한다.
  armed,

  /// 수직으로 움직이는 중. **이 단계에서 걸음을 멈춘다.**
  riding,

  /// 수직 속도가 멎었다. 남의 층일 수 있으므로 **확정하지 않는다.**
  settled,

  /// 내려서 걷기 시작했다. 걸음을 재개하고, 층을 알아냈으면 함께 바꾼다.
  confirmed,

  /// 근거가 사라졌다. 걸음만 재개하고 층은 그대로 둔다.
  cancelled,
}

/// 확정된 층 이동. [toFloorLabel]을 못 정하면 이 값 자체가 안 만들어진다 —
/// 층을 모르는 채로 도면을 바꾸는 경로를 두지 않기 위해서다.
class ElevatorTransition {
  const ElevatorTransition({
    required this.fromFloorLabel,
    required this.toFloorLabel,
    required this.deltaM,
    required this.boardingNodeId,
    required this.carName,
    required this.durationMs,
    required this.arrivalSource,
  });

  final String fromFloorLabel;
  final String toFloorLabel;

  /// 탑승 직전 고도 대비 변화(m). 올라갔으면 양수.
  final double deltaM;

  final String? boardingNodeId;

  /// 호기 이름(`EV1`…). 같은 이름이 층을 가로질러 같은 샤프트를 가리킨다.
  final String? carName;

  final int durationMs;

  /// `route`(경로가 말한 층) · `table`(고도표로 푼 층).
  final String arrivalSource;
}

/// 단계 전이 한 건. 화면은 이 값만 보고 배너·걸음 정지를 결정한다.
class ElevatorPhaseChange {
  const ElevatorPhaseChange({
    required this.phase,
    required this.atMs,
    required this.reason,
    required this.fromFloorLabel,
    this.toFloorLabel,
    this.boardingNodeId,
    this.carName,
    this.deltaM = 0,
    this.transition,
  });

  final ElevatorPhase phase;
  final int atMs;

  /// 왜 이 단계로 왔나. 진단 로그와 디버그 칩이 그대로 쓴다.
  final String reason;

  final String? fromFloorLabel;
  final String? toFloorLabel;
  final String? boardingNodeId;
  final String? carName;
  final double deltaM;

  /// `confirmed`에서 **층까지 정해졌을 때만** 채워진다.
  final ElevatorTransition? transition;

  /// 이 단계에서 걸음을 위치에 반영하면 안 되는가. 화면은 이 값만 보고
  /// `pauseStepTracking`을 켜고 끈다 — 단계 이름을 다시 해석하지 않는다.
  bool get pausesStepTracking =>
      phase == ElevatorPhase.riding || phase == ElevatorPhase.settled;

  Map<String, Object?> toJson() => {
    'phase': phase.name,
    'at_ms': atMs,
    'reason': reason,
    'from_floor': fromFloorLabel,
    'to_floor': toFloorLabel,
    'boarding_node_id': boardingNodeId,
    'car_name': carName,
    'delta_m': deltaM,
  };
}

/// 같은 호기의 엘리베이터 노드가 **실제로 서는 층** 집합. 키는
/// [elevatorCarName]이 정한 꼴이다 — 이름을 읽는 규칙이 도착 노드 찾기와
/// 갈리면 후보를 좁히는 쪽만 틀린다.
///
/// 건물 전체 그래프의 노드를 넣는다. 층 소속을 어떻게 읽을지는 호출부가 아는
/// 일이라 [floorLabelOf]로 받는다(층별 그래프는 `floorId`가 비어 있다).
///
/// **없는 호기는 키 자체가 없다.** 빈 집합을 남기면 부르는 쪽이 그대로
/// `contains`로 써서 모든 층을 걸러내고, 판정이 조용히 죽는다.
Map<String, Set<String>> elevatorServedFloorsByCar({
  required Iterable<GraphNode> nodes,
  required String? Function(GraphNode node) floorLabelOf,
}) {
  final result = <String, Set<String>>{};
  for (final node in nodes) {
    final name = elevatorCarName(node);
    final floor = floorLabelOf(node);
    if (name == null || floor == null) continue;
    (result[name] ??= <String>{}).add(floor);
  }
  return result;
}

/// 기압 시계열 + 엘리베이터 노드 근접으로 층 이동을 판정하는 상태기.
///
/// 입력은 두 갈래다. [updateContext]·[onPosition]·[onElevatorRouteApproach]가
/// "지금 어느 엘리베이터 앞인가"를 알려주고, [onAltitude]가 기압을 넣으며
/// 판정한다. [onRawMotion]은 걸음 정지 중에도 흐르는 움직임 신호다.
class ElevatorTransitionDetector {
  ElevatorTransitionDetector({this.config = const ElevatorDetectorConfig()});

  final ElevatorDetectorConfig config;

  // 컨텍스트.
  String? _floorLabel;
  String? _buildingId;
  FloorAltitudeTable? _table;
  FloorGraph? _graph;
  List<_ElevatorNode> _elevatorNodes = const [];
  Map<String, Set<String>> _servedFloorsByCar = const {};

  // 허가.
  String? _boardingNodeId;
  String? _carName;
  int? _armedUntilMs;
  String? _routeTargetFloorLabel;

  // 기압.
  final List<AltitudeSample> _window = [];
  final List<({int atMs, double valueM})> _smoothedHistory = [];
  double? _lastSmoothedM;
  int? _lastSampleAtMs;
  double? _fastAltitudeM;
  final List<({int atMs, double valueM})> _fastHistory = [];

  /// [_floorLabel]을 더 못 믿는다. 움직인 탑승이 층을 바꾸지 못한 채 끝나면 선다.
  bool _floorTrustLost = false;

  // 탑승.
  ElevatorPhase _phase = ElevatorPhase.idle;
  double? _baselineM;
  int? _rideStartMs;
  int? _verticalMotionSinceMs;
  int _verticalMotionSign = 0;
  int? _settleQuietSinceMs;
  int? _settledAtMs;

  /// 이번 탑승이 층을 옮길 만큼 움직였는가.
  ///
  /// 취소 시점에 다시 재지 않고 **미리** 세워 둔다 — `timelineGap` 취소는 고도
  /// 이력을 버린 뒤에 끝내므로([onAltitude]), 그때는 [deltaM]이 이미 null이다.
  bool _rideMovedFar = false;

  // 걸음.
  int _lastSteps = 0;
  int _rawStepCount = 0;

  /// `settled`에 들어간 순간의 걸음 수. 확정은 **그 뒤로 쌓인 걸음**이 정한다 —
  /// 샘플 간 증분으로 재면 Android(5Hz)에서는 문턱을 영영 못 넘는다.
  int? _settleStepsBaseline;
  int? _settleRawStepsBaseline;

  final List<ElevatorPhaseChange> _phaseChanges = [];

  ElevatorPhase get phase => _phase;

  /// 지금 걸음을 위치에 반영하면 안 되는가.
  bool get pausesStepTracking =>
      _phase == ElevatorPhase.riding || _phase == ElevatorPhase.settled;

  bool get isArmed => _boardingNodeId != null || _routeTargetFloorLabel != null;

  /// 탑승 직전 고도 대비 현재 변화(m). 탑승 전에는 null.
  double? get deltaM => (_baselineM == null || _lastSmoothedM == null)
      ? null
      : _lastSmoothedM! - _baselineM!;

  double? get smoothedAltitudeM => _lastSmoothedM;

  /// 걸음 정지 중에도 쌓인 원시 걸음 누적([onRawMotion]이 넣는다).
  ///
  /// **배선을 재는 값이다.** 이 값이 안 늘면 `onRawMotion`을 부르는 사람이
  /// 없다는 뜻이고, 그러면 `walkedOut` 확정이 영영 안 나서 하차가 20초 폴백으로만
  /// 끝난다 — 그동안 마커가 활강 끝점에 붙어 있다.
  int get rawStepCount => _rawStepCount;

  /// 기록된 단계 전이를 비우며 가져간다. 화면은 이 순서대로 적용한다.
  List<ElevatorPhaseChange> takePhaseChanges() {
    final out = List<ElevatorPhaseChange>.unmodifiable(_phaseChanges);
    _phaseChanges.clear();
    return out;
  }

  /// 층·그래프·건물을 갱신한다. 층이 실제로 바뀌면 판정 상태를 전부 버린다 —
  /// 이 판정기가 만든 층 변경이든 사람이 고른 것이든, 새 층에서는 새로 잰다.
  void updateContext({
    required String? floorLabel,
    required FloorGraph? graph,
    String? buildingId,
    Map<String, Set<String>>? servedFloorsByCar,
  }) {
    if (servedFloorsByCar != null) _servedFloorsByCar = servedFloorsByCar;
    if (buildingId != _buildingId) {
      _buildingId = buildingId;
      _table = floorAltitudeTableFor(buildingId);
    }
    if (!identical(graph, _graph)) {
      _graph = graph;
      _elevatorNodes = _parseElevatorNodes(graph);
    }
    if (floorLabel == _floorLabel) return;
    // 층이 바뀌었는데 아직 타는 중으로 보고 있으면 걸음이 멈춘 채로 남는다.
    // 확정으로 바뀐 층이든 사람이 고른 층이든, 여기서 반드시 푼다.
    if (pausesStepTracking) {
      _finish(
        ElevatorPhase.cancelled,
        atMs: _lastSampleAtMs ?? 0,
        reason: 'floorChanged',
      );
    }
    _floorLabel = floorLabel;
    // 층이 새로 정해졌다 — 앵커를 다시 찍었거나 확정이 층을 옮겼다는 뜻이라,
    // 여기서부터는 [_floorLabel]을 다시 믿을 수 있다([_floorTrustLost]).
    _floorTrustLost = false;
    _phase = ElevatorPhase.idle;
    _resetRide();
    _resetArm();
    _resetAltitude();
  }

  /// 보정된 현재 위치를 넣어 허가 상태를 갱신한다. [positionM]은 층 `local_m`
  /// 좌표(복도 보정 결과)여야 한다.
  void onPosition({
    required PdrLocalPoint positionM,
    required int steps,
    required int timestampMs,
  }) {
    _lastSteps = steps;
    if (_elevatorNodes.isEmpty) return;
    if (_phase == ElevatorPhase.riding || _phase == ElevatorPhase.settled) {
      return;
    }

    _ElevatorNode? nearest;
    var nearestDistanceM = double.infinity;
    final namesInRange = <String>{};
    for (final node in _elevatorNodes) {
      final distanceM = math.sqrt(
        math.pow(positionM.eastM - node.xM, 2) +
            math.pow(positionM.northM - node.yM, 2),
      );
      if (distanceM > config.armRadiusM) continue;
      if (node.name != null) namesInRange.add(node.name!);
      if (distanceM < nearestDistanceM) {
        nearest = node;
        nearestDistanceM = distanceM;
      }
    }
    if (nearest == null) return;

    _boardingNodeId = nearest.id;
    // 승강장에 호기가 여럿 겹쳐 보이면 어느 것을 탈지 못 가른다. 그때 호기를
    // 단정하면 정차 층 후보를 **틀리게 좁혀** 도착 층을 놓친다.
    _carName = namesInRange.length > 1 ? null : nearest.name;
    _armedUntilMs = timestampMs + config.armHoldMs;
    if (_phase == ElevatorPhase.idle) {
      _setPhase(ElevatorPhase.armed, atMs: timestampMs, reason: 'nearNode');
    }
  }

  /// 활성 경로가 이 층에서 엘리베이터를 타라고 할 때의 허가. 경로에서 나온
  /// 근거라 위치 보정이 늦어도 허가하고, **도착 층을 함께 받는다** — 그 값이
  /// 확정 시 1순위다.
  void onElevatorRouteApproach({
    required PdrLocalPoint positionM,
    required PdrLocalPoint routeEndM,
    required String expectedBoardingNodeId,
    required String? targetFloorLabel,
    required int steps,
    required int timestampMs,
    String? carName,
  }) {
    _lastSteps = steps;
    if (_phase == ElevatorPhase.riding || _phase == ElevatorPhase.settled) {
      return;
    }
    final approachDistanceM = (positionM - routeEndM).distance;
    if (approachDistanceM > config.routeApproachArmRadiusM) return;

    _boardingNodeId = expectedBoardingNodeId;
    _carName =
        normalizedCarName(carName) ??
        _elevatorNodes
            .where((node) => node.id == expectedBoardingNodeId)
            .map((node) => node.name)
            .firstOrNull;
    _routeTargetFloorLabel = targetFloorLabel;
    _armedUntilMs = timestampMs + config.armHoldMs;
    if (_phase == ElevatorPhase.idle) {
      _setPhase(ElevatorPhase.armed, atMs: timestampMs, reason: 'routeSegment');
    }
  }

  /// 위치에 반영되지 않은 원시 움직임을 넣는다. 탑승 중에는 [onPosition]의
  /// `steps`가 안 늘어, 이 신호가 없으면 "내려서 걷기 시작했다"를 볼 수 없다.
  ///
  /// **네이티브 걸음만** 센다. 발판 진동(accel peak)은 "기기가 움직인다"의 근거는
  /// 되지만 "내려서 걷는다"의 근거는 못 된다.
  void onRawMotion(RawMotionActivity activity) {
    _rawStepCount += activity.nativeStepDelta ?? 0;
  }

  /// 기압 샘플을 넣고 판정한다. **층까지 확정된 순간에만** non-null이다 —
  /// 층을 못 정한 채 탑승이 끝나는 경우도 있으므로(고도표도 경로도 없을 때),
  /// 걸음 정지·재개는 반환값이 아니라 [takePhaseChanges]로 배선해야 한다.
  ElevatorTransition? onAltitude(AltitudeSample sample) {
    final atMs = sample.timestampMs;
    final lastAtMs = _lastSampleAtMs;
    if (lastAtMs != null &&
        (atMs < lastAtMs || atMs - lastAtMs > config.maxSampleAgeMs)) {
      final wasRiding = pausesStepTracking;
      _resetAltitude();
      if (wasRiding) {
        _finish(ElevatorPhase.cancelled, atMs: atMs, reason: 'timelineGap');
      }
    }
    _lastSampleAtMs = atMs;

    final speedMps = _updateFastAltitude(sample);
    final smoothed = _pushAndSmooth(sample);
    if (smoothed == null) return null;
    _lastSmoothedM = smoothed;
    if ((deltaM ?? 0).abs() >= config.minRideDeltaM) _rideMovedFar = true;
    _smoothedHistory.add((atMs: atMs, valueM: smoothed));
    while (_smoothedHistory.length > 2 &&
        atMs - _smoothedHistory.first.atMs > 30000) {
      _smoothedHistory.removeAt(0);
    }
    _trackVerticalMotion(atMs, speedMps);

    switch (_phase) {
      case ElevatorPhase.idle:
        return null;
      case ElevatorPhase.armed:
        return _advanceArmed(atMs);
      case ElevatorPhase.riding:
        return _advanceRiding(atMs);
      case ElevatorPhase.settled:
        return _advanceSettled(atMs);
      case ElevatorPhase.confirmed:
      case ElevatorPhase.cancelled:
        return null;
    }
  }

  /// 판정 상태를 전부 비운다. 걸음 정지 중이었다면 재개 신호를 낸다.
  void reset({int atMs = 0}) {
    if (pausesStepTracking) {
      _finish(ElevatorPhase.cancelled, atMs: atMs, reason: 'reset');
    }
    _phase = ElevatorPhase.idle;
    _floorTrustLost = false;
    _resetRide();
    _resetArm();
    _resetAltitude();
  }

  // ── 단계 진행 ──

  ElevatorTransition? _advanceArmed(int atMs) {
    final armedUntilMs = _armedUntilMs;
    if (armedUntilMs != null && atMs > armedUntilMs) {
      _finish(ElevatorPhase.cancelled, atMs: atMs, reason: 'armTimeout');
      return null;
    }
    if (!_verticalMotionSustained(atMs)) return null;

    // baseline은 **수직 이동이 시작된 시각의** 평활값이다. 중앙값은 창의 절반쯤
    // 뒤처지므로 그 시점 값이 곧 탑승 직전 고도다.
    _baselineM = _smoothedAt(_verticalMotionSinceMs!) ?? _lastSmoothedM;
    _rideStartMs = atMs;
    _settleQuietSinceMs = null;
    _settledAtMs = null;
    _setPhase(ElevatorPhase.riding, atMs: atMs, reason: 'verticalMotion');
    return null;
  }

  ElevatorTransition? _advanceRiding(int atMs) {
    final startedAtMs = _rideStartMs;
    if (startedAtMs != null && atMs - startedAtMs > config.rideTimeoutMs) {
      _finish(ElevatorPhase.cancelled, atMs: atMs, reason: 'rideTimeout');
      return null;
    }
    final quietSinceMs = _settleQuietSinceMs;
    if (quietSinceMs == null || atMs - quietSinceMs < config.settleQuietMs) {
      return null;
    }
    // 출발 고도로 되돌아왔으면 타려다 만 것이다. 층은 그대로 두고 걸음만 푼다.
    if ((deltaM ?? 0).abs() < config.revertM) {
      _finish(ElevatorPhase.cancelled, atMs: atMs, reason: 'reverted');
      return null;
    }
    _settledAtMs = atMs;
    _markSettleStepBaseline();
    _setPhase(ElevatorPhase.settled, atMs: atMs, reason: 'stopped');
    return null;
  }

  /// `settled`에서 확정을 **걸음에 건다.**
  ///
  /// "멈췄다"로 확정하면 남이 눌러서 선 층에서 확정된다 — 문 열림이 보통
  /// 5~10초라 정지만으로는 내 층과 남의 층이 안 갈린다. 중간 정차 실측 표본이
  /// 아직 없으므로(`docs/client/elevator-altitude-probe.md`), 표본 없이도 안전한
  /// "내려서 걷기 시작했을 때"를 확정 근거로 쓴다.
  ///
  /// 걸음이 끝내 안 잡히면 [ElevatorDetectorConfig.settleFallbackConfirmMs]에서
  /// 반드시 푼다 — 걸음 정지가 영영 안 풀리는 것이 이 기능의 최악 실패다. 그때
  /// 층까지 바꾸는 것은 **경로가 말한 층과 측정 Δ가 맞을 때만**이다.
  ElevatorTransition? _advanceSettled(int atMs) {
    if (_verticalMotionSustained(atMs)) {
      // 남의 층에 섰다가 다시 간다. 확정하지 않고 riding으로 되돌린다 —
      // 고도 baseline은 그대로 둬야 여러 층을 한 번에 센다. 걸음 기준만 버린다:
      // 이 정차에서 뒤척인 한두 개가 다음 정차의 확정으로 넘어가면 안 된다.
      _settledAtMs = null;
      _settleStepsBaseline = null;
      _settleRawStepsBaseline = null;
      _setPhase(ElevatorPhase.riding, atMs: atMs, reason: 'resumedRiding');
      return null;
    }
    if (_stepsSinceSettled >= config.confirmMinSteps) {
      return _confirm(atMs, reason: 'walkedOut', requireRouteAgreement: false);
    }
    final settledAtMs = _settledAtMs;
    if (settledAtMs != null &&
        atMs - settledAtMs >= config.settleFallbackConfirmMs) {
      return _confirm(atMs, reason: 'noWalk', requireRouteAgreement: true);
    }
    final startedAtMs = _rideStartMs;
    if (startedAtMs != null && atMs - startedAtMs > config.rideTimeoutMs) {
      _finish(ElevatorPhase.cancelled, atMs: atMs, reason: 'rideTimeout');
    }
    return null;
  }

  ElevatorTransition? _confirm(
    int atMs, {
    required String reason,
    required bool requireRouteAgreement,
  }) {
    final measuredDeltaM = deltaM ?? 0;
    final fromFloorLabel = _floorLabel;
    if (measuredDeltaM.abs() < config.minRideDeltaM || fromFloorLabel == null) {
      _finish(ElevatorPhase.cancelled, atMs: atMs, reason: 'tooSmall');
      return null;
    }
    final arrival = _resolveArrival(
      fromFloorLabel: fromFloorLabel,
      measuredDeltaM: measuredDeltaM,
    );
    if (arrival == null ||
        (requireRouteAgreement && arrival.source != 'route')) {
      _finish(
        ElevatorPhase.confirmed,
        atMs: atMs,
        reason: arrival == null
            ? 'unknownTargetFloor'
            : 'unverifiedTargetFloor',
        deltaM: measuredDeltaM,
      );
      return null;
    }
    final transition = ElevatorTransition(
      fromFloorLabel: fromFloorLabel,
      toFloorLabel: arrival.floorLabel,
      deltaM: measuredDeltaM,
      boardingNodeId: _boardingNodeId,
      carName: _carName,
      durationMs: atMs - (_rideStartMs ?? atMs),
      arrivalSource: arrival.source,
    );
    _finish(
      ElevatorPhase.confirmed,
      atMs: atMs,
      reason: reason,
      deltaM: measuredDeltaM,
      transition: transition,
    );
    return transition;
  }

  /// 도착 층을 고르는 **순서가 이 함수의 전부다.**
  ///
  /// 1. 경로가 목표 층을 알면 그것이 1순위다.
  /// 2. 고도표가 있으면 검증한다 — 기대 Δ에서 반 층 넘게 벗어나면 그 층이 아니다.
  /// 3. 경로가 없거나 2에서 걸리면 고도표로 직접 푼다. 호기를 알면 그 호기가
  ///    서는 층만 후보로 넘긴다. 2에서 떨어졌다는 건 **다른 층에서 내렸다**는
  ///    뜻이고, 그 층이 어디인지는 표가 안다.
  /// 4. 표도 경로도 없으면 **층을 바꾸지 않는다**(null). 층고 상수로 ±1층을 찍는
  ///    폴백은 두지 않는다 — 엘리베이터는 여러 층을 한 번에 가므로 그 폴백은
  ///    맞을 때보다 틀릴 때가 많다.
  ({String floorLabel, String source})? _resolveArrival({
    required String fromFloorLabel,
    required double measuredDeltaM,
  }) {
    // 시작 층을 못 믿으면 도착 층도 못 푼다. [fromFloorLabel]과 baseline이
    // 서로 다른 층을 가리키는 상태라, 표를 봐도 경로를 봐도 답이 틀린다.
    if (_floorTrustLost) return null;
    final table = _table;
    final routeFloorLabel = _routeTargetFloorLabel;
    if (routeFloorLabel != null && routeFloorLabel != fromFloorLabel) {
      final agrees =
          table == null ||
          _routeFloorAgrees(
            table: table,
            fromFloorLabel: fromFloorLabel,
            routeFloorLabel: routeFloorLabel,
            measuredDeltaM: measuredDeltaM,
          );
      if (agrees) return (floorLabel: routeFloorLabel, source: 'route');
    }
    if (table == null) return null;
    final servedFloors = _carName == null ? null : _servedFloorsByCar[_carName];
    final resolved = floorAtDelta(
      table: table,
      fromFloor: fromFloorLabel,
      deltaM: measuredDeltaM,
      // 후보가 하나로 좁혀지면 2등이 없어 여유 규칙이 못 돈다. 그때는 좁히지
      // 않고 [floorAtDelta]의 절대 오차 상한에 맡긴다.
      servedFloors: (servedFloors != null && servedFloors.length > 1)
          ? servedFloors
          : null,
      minMarginM: config.floorMatchMarginM,
      maxErrorM: config.floorMatchMaxErrorM,
    );
    if (resolved == null || resolved == fromFloorLabel) return null;
    return (floorLabel: resolved, source: 'table');
  }

  /// 측정 Δ가 경로가 말한 층의 기대 Δ에서 **반 층 이내**인가. 층고가
  /// 3.23~7.11 m로 다르므로 상수가 아니라 그 층의 한 층을 기준으로 잰다.
  bool _routeFloorAgrees({
    required FloorAltitudeTable table,
    required String fromFloorLabel,
    required String routeFloorLabel,
    required double measuredDeltaM,
  }) {
    final expectedDeltaM = floorGapM(
      table: table,
      from: fromFloorLabel,
      to: routeFloorLabel,
    );
    if (expectedDeltaM == null) return true;
    final oneFloorM = nearestFloorGapM(table: table, floor: routeFloorLabel);
    if (oneFloorM == null) return true;
    return (measuredDeltaM - expectedDeltaM).abs() <=
        oneFloorM * config.routeFloorToleranceRatio;
  }

  // ── 기압 처리 ──

  /// 저지연 EMA를 갱신하고 수직 속도(m/s)를 돌려준다. 밑변이 아직 안 모이면 null.
  double? _updateFastAltitude(AltitudeSample sample) {
    final altitudeM = sample.altitudeM;
    final atMs = sample.timestampMs;
    final previousM = _fastAltitudeM;
    final previousAtMs = _fastHistory.isEmpty ? null : _fastHistory.last.atMs;
    if (previousM == null || previousAtMs == null) {
      _fastAltitudeM = altitudeM;
    } else {
      final dtMs = (atMs - previousAtMs).clamp(1, config.maxSampleAgeMs);
      final alpha = 1 - math.exp(-dtMs / config.fastAltitudeTauMs);
      _fastAltitudeM = previousM + alpha * (altitudeM - previousM);
    }
    _fastHistory.add((atMs: atMs, valueM: _fastAltitudeM!));
    while (_fastHistory.length > 2 && atMs - _fastHistory.first.atMs > 5000) {
      _fastHistory.removeAt(0);
    }

    ({int atMs, double valueM})? base;
    for (final entry in _fastHistory) {
      if (atMs - entry.atMs < config.fastSlopeBaseMs) break;
      base = entry;
    }
    if (base == null) return null;
    return (_fastAltitudeM! - base.valueM) / ((atMs - base.atMs) / 1000);
  }

  double? _pushAndSmooth(AltitudeSample sample) {
    _window.add(sample);
    while (_window.length > config.minSmoothingSamples &&
        sample.timestampMs - _window.first.timestampMs >
            config.smoothingWindowMs) {
      _window.removeAt(0);
    }
    if (_window.length < config.minSmoothingSamples) return null;
    final values = _window.map((sample) => sample.altitudeM).toList()..sort();
    final middle = values.length ~/ 2;
    return values.length.isOdd
        ? values[middle]
        : (values[middle - 1] + values[middle]) / 2;
  }

  void _trackVerticalMotion(int atMs, double? speedMps) {
    if (speedMps == null) return;
    if (speedMps.abs() >= config.minVerticalSpeedMps) {
      final sign = speedMps > 0 ? 1 : -1;
      if (sign != _verticalMotionSign) {
        _verticalMotionSign = sign;
        _verticalMotionSinceMs = atMs;
      }
    } else {
      _verticalMotionSign = 0;
      _verticalMotionSinceMs = null;
    }
    if (speedMps.abs() <= config.settleSpeedMps) {
      _settleQuietSinceMs ??= atMs;
    } else {
      _settleQuietSinceMs = null;
    }
  }

  bool _verticalMotionSustained(int atMs) {
    final sinceMs = _verticalMotionSinceMs;
    return sinceMs != null && atMs - sinceMs >= config.verticalMotionMinMs;
  }

  double? _smoothedAt(int atMs) {
    if (_smoothedHistory.isEmpty) return null;
    var valueM = _smoothedHistory.first.valueM;
    for (final entry in _smoothedHistory) {
      if (entry.atMs > atMs) break;
      valueM = entry.valueM;
    }
    return valueM;
  }

  // ── 상태 갈무리 ──

  void _setPhase(
    ElevatorPhase phase, {
    required int atMs,
    required String reason,
    double deltaM = 0,
    ElevatorTransition? transition,
  }) {
    _phase = phase;
    _phaseChanges.add(
      ElevatorPhaseChange(
        phase: phase,
        atMs: atMs,
        reason: reason,
        fromFloorLabel: _floorLabel,
        toFloorLabel: transition?.toFloorLabel ?? _routeTargetFloorLabel,
        boardingNodeId: _boardingNodeId,
        carName: _carName,
        deltaM: deltaM,
        transition: transition,
      ),
    );
  }

  /// 끝난 단계(`confirmed`·`cancelled`)를 내보내고 idle로 돌아간다. 어느 쪽이든
  /// **걸음은 반드시 재개된다** — 그것이 이 함수를 하나로 둔 이유다.
  void _finish(
    ElevatorPhase phase, {
    required int atMs,
    required String reason,
    double deltaM = 0,
    ElevatorTransition? transition,
  }) {
    _noteFloorTrust(phase, transition: transition);
    _setPhase(
      phase,
      atMs: atMs,
      reason: reason,
      deltaM: deltaM,
      transition: transition,
    );
    _phase = ElevatorPhase.idle;
    _resetRide();
    _resetArm();
  }

  /// 움직인 탑승이 **층을 못 바꾼 채** 끝났으면 층 라벨의 신뢰를 잃는다.
  ///
  /// 취소가 나도 사람은 아직 차 안이다. 앵커가 탄 층 승강장에 그대로라 곧바로
  /// 다시 무장하는데, 그때 baseline은 **중간 층 고도**로 잡히고 [_floorLabel]은
  /// 탄 층 그대로다. 그 둘로 푼 도착 층은 반드시 틀린다 — 1F→8F를 4F에서
  /// 끊고 남은 구간만 재면 "1F에서 23 m"가 되어 4F로 확정된다.
  ///
  /// 회복은 실제 층 변경이나 [reset]뿐이다. 틀린 층 하나보다 놓친 층 하나가 싸다.
  void _noteFloorTrust(
    ElevatorPhase phase, {
    required ElevatorTransition? transition,
  }) {
    if (transition != null) return;
    if (phase != ElevatorPhase.cancelled && phase != ElevatorPhase.confirmed) {
      return;
    }
    if (!_rideMovedFar) return;
    _floorTrustLost = true;
  }

  /// `settled` 진입 시각의 걸음 수를 뜬다.
  void _markSettleStepBaseline() {
    _settleStepsBaseline = _lastSteps;
    _settleRawStepsBaseline = _rawStepCount;
  }

  /// `settled`에 들어간 뒤 쌓인 걸음. 기준을 못 떴으면 0.
  ///
  /// 두 출처를 더한다. 걸음 정지 중에는 스냅샷 걸음([_lastSteps])이 안 늘고
  /// 원시 걸음([_rawStepCount])만 흐르는데, 어느 쪽이 흐르는지는 이 판정기가
  /// 알 일이 아니다 — 둘 다 "발을 뗐다"의 근거다.
  int get _stepsSinceSettled {
    final steps = _settleStepsBaseline;
    final raw = _settleRawStepsBaseline;
    if (steps == null || raw == null) return 0;
    return (_lastSteps - steps) + (_rawStepCount - raw);
  }

  void _resetRide() {
    _baselineM = null;
    _rideMovedFar = false;
    _rideStartMs = null;
    _verticalMotionSinceMs = null;
    _verticalMotionSign = 0;
    _settleQuietSinceMs = null;
    _settledAtMs = null;
    _settleStepsBaseline = null;
    _settleRawStepsBaseline = null;
  }

  void _resetArm() {
    _boardingNodeId = null;
    _carName = null;
    _armedUntilMs = null;
    _routeTargetFloorLabel = null;
  }

  void _resetAltitude() {
    _window.clear();
    _smoothedHistory.clear();
    _fastHistory.clear();
    _fastAltitudeM = null;
    _lastSmoothedM = null;
  }

  static List<_ElevatorNode> _parseElevatorNodes(FloorGraph? graph) {
    if (graph == null) return const [];
    return [
      for (final node in graph.nodes)
        if (node.type == 'elevator')
          _ElevatorNode(
            id: node.id,
            // 이름은 **여기 한 번만** 읽는다. 이 값이 곧 정차 층 후보를 찾는
            // 키이자 [ElevatorTransition.carName]이라, 도착 노드 찾기와 같은
            // 규칙([elevatorCarName])을 써야 둘이 같은 호기를 가리킨다.
            name: elevatorCarName(node),
            xM: node.xM,
            yM: node.yM,
          ),
    ];
  }
}

class _ElevatorNode {
  const _ElevatorNode({
    required this.id,
    required this.name,
    required this.xM,
    required this.yM,
  });

  final String id;
  final String? name;
  final double xM;
  final double yM;
}
