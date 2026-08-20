import 'dart:async';

import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import '../contract/indoor_navigation_contract.dart';
import '../platform/native_pdr_event.dart';
import '../platform/pdr_motion_source.dart';
import '../../../domain/geo/geo_transform.dart';

/// 앱 범위 실내 내비게이션 세션을 소유하는 headless 컨트롤러.
///
/// 계약([IndoorNavigationController])을 구현한다. 위젯을 만들지 않고, PdrSession(코어)과
/// [PdrMotionSource]를 소유하며 native 이벤트를 코어로 흘린다. UI는 스트림을 관찰만 한다.
///
/// lifecycle 원칙(설계 v4 Phase 2):
///   - anchor 확정 + startGuidance에서 세션 ON
///   - 화면 전환(IndoorMap↔RouteGuide↔calibration)에는 세션 유지
///   - 안내 종료·층 변경·명시 reset·background에서만 stop/pause
class IndoorNavigationDriver implements IndoorNavigationController {
  IndoorNavigationDriver({
    required PdrMotionSource source,
    PdrSessionConfig? config,
    int Function()? nowMs,
  }) : _source = source, // ignore: prefer_initializing_formals
       _nowMs = nowMs ?? _defaultNowMs {
    _session = PdrSession(config: config);
    _sessionSub = _session.snapshots.listen(_onSnapshot);
  }

  static int _defaultNowMs() => DateTime.now().millisecondsSinceEpoch;

  final PdrMotionSource _source;
  final int Function() _nowMs;

  late final PdrSession _session;
  late final StreamSubscription<PdrSnapshot> _sessionSub;
  StreamSubscription<NativePdrEvent>? _eventSub;

  final _snapshots = StreamController<PdrSnapshot>.broadcast();
  final _calibration = StreamController<CalibrationStatus>.broadcast();
  final _runtimeStatuses = StreamController<PdrRuntimeStatus>.broadcast();
  final _altitudes = StreamController<AltitudeSample>.broadcast();
  final _rawMotion = StreamController<RawMotionActivity>.broadcast();

  // 원시 누적 카운터. native는 pause 여부와 무관하게 계속 보내므로 여기서만
  // 차분을 낸다(PdrSession은 pause 중 이 값을 경로에 반영하지 않는다).
  int? _lastRawAccelPeakCount;
  int? _lastRawPedometerSteps;

  AltitudeSample? _currentAltitude;
  AltimeterStatus _altimeterStatus = const AltimeterStatus.unavailable();

  PdrSnapshot? _current;
  CalibrationStatus _calib = const CalibrationStatus.uncalibrated();
  PdrRuntimeStatus _runtimeStatus = const PdrRuntimeStatus.idle();
  Map<String, Object?>? _lastPedometerFinalizeInfo;
  bool _guiding = false;
  bool _backgrounded = false;
  Future<void> _lifecycleTransition = Future<void>.value();
  String? _floorId;

  // 캘리브레이션 진행 중 임시 상태.
  PdrLocalPoint? _pendingPinFloorM;
  PdrLocalPoint? _pendingPinPdrM;
  PdrToFloorAxes _pendingAxes = const PdrToFloorAxes.identity();

  // ── IndoorNavigationView ──

  @override
  Stream<PdrSnapshot> get snapshots => _snapshots.stream;

  @override
  PdrSnapshot? get currentSnapshot => _current;

  @override
  Stream<CalibrationStatus> get calibration => _calibration.stream;

  @override
  CalibrationStatus get currentCalibration => _calib;

  @override
  Stream<PdrRuntimeStatus> get runtimeStatuses => _runtimeStatuses.stream;

  @override
  PdrRuntimeStatus get currentRuntimeStatus => _runtimeStatus;

  @override
  String? get currentFloorId => _floorId;

  @override
  Stream<AltitudeSample> get altitudeSamples => _altitudes.stream;

  @override
  AltitudeSample? get currentAltitude => _currentAltitude;

  @override
  AltimeterStatus get altimeterStatus => _altimeterStatus;

  @override
  Stream<RawMotionActivity> get rawMotion => _rawMotion.stream;

  @override
  Map<String, Object?>? get lastPedometerFinalizeInfo =>
      _lastPedometerFinalizeInfo;

  @override
  bool get isHeadingConverged => _session.headingConverged;

  // ── IndoorNavigationIntents ──

  @override
  Future<void> startGuidance({required String floorId}) async {
    if (_guiding && _floorId == floorId) {
      return;
    }
    _floorId = floorId;
    _guiding = true;
    _backgrounded = false;
    _session.reset();
    _updateRuntime(PdrRuntimeState.starting);
    _eventSub ??= _source.events.listen(
      _onNativeEvent,
      onError: _onSourceError,
    );
    try {
      await _source.start();
      // 새 guidance는 native step-session도 반드시 새로 연다. 그렇지 않으면
      // 직전 stop에서 동결한 Android counter가 재시작 뒤에도 finalized 상태로
      // 남아 이후 걸음을 모두 무시한다.
      final newSessionId = await _source.resetPedometer();
      _session.reset(newStepSessionId: newSessionId);
    } on Object {
      _updateRuntime(
        PdrRuntimeState.degraded,
        warnings: const ['sensorStartFailed'],
      );
    }
    _updateCalibration(CalibrationPhase.awaitingPin);
  }

  @override
  Future<void> stopGuidance() async {
    if (!_guiding) {
      return;
    }
    _guiding = false;
    _backgrounded = false;
    _updateRuntime(PdrRuntimeState.stopping);
    try {
      // stop 전에 native가 보유한 마지막 STEP_COUNTER/CMPedometer 상태를
      // 한 번만 flush한다. finalize 뒤 native는 추가 pedometer callback을
      // 경로로 보내지 않으므로 종료 지점이 흔들리지 않는다.
      _lastPedometerFinalizeInfo = await _source.finalizePedometer();
      await Future<void>.delayed(Duration.zero);
    } on Object {
      _updateRuntime(
        PdrRuntimeState.degraded,
        warnings: const ['pedometerFinalizeFailed'],
      );
    }
    await _source.stop();
    _pendingPinFloorM = null;
    _pendingPinPdrM = null;
    _pendingAxes = const PdrToFloorAxes.identity();
    _updateCalibration(CalibrationPhase.uncalibrated);
    _updateRuntime(PdrRuntimeState.idle);
  }

  @override
  Future<void> confirmAnchorByPin({
    required PdrLocalPoint floorPointM,
    PdrToFloorAxes axes = const PdrToFloorAxes.identity(),
    String? floorId,
  }) async {
    if (!_guiding) {
      return;
    }
    // 길찾기에서 다른 층의 출발지를 직접 고르면 좌표뿐 아니라 현재 층도 함께
    // 바뀌어야 한다. 좌표만 새 층 값으로 넣고 _floorId를 이전 층에 두면
    // calibration은 성공해도 화면의 floor gate가 마커·PDR을 전부 숨긴다.
    if (floorId != null) {
      _floorId = floorId;
    }
    // 위치 재지정은 새 경로의 시작이지만 센서를 다시 켜는 동작은 아니다.
    // native 누적 counter/heading은 유지하고 Dart 경로만 지금 시각으로 재기준화해,
    // iOS CMPedometer의 느린 첫 batch를 다시 기다리지 않게 한다.
    _rebasePathForNewOrigin();
    _pendingPinFloorM = floorPointM;
    _pendingPinPdrM = PdrLocalPoint.zero;
    _pendingAxes = axes;
    if (_session.headingReference == HeadingReference.magneticNorth) {
      // 자북 기준: 서버 north_alignment 오프셋을 Phase 3에서 주입한다. 지금은 0.
      _finalizeAnchor(rotationDeg: 0, source: AnchorSource.userPin);
    } else {
      // arbitrary corrected: 진행 방향 보정이 필수(§4).
      _updateCalibration(CalibrationPhase.awaitingHeading);
    }
  }

  @override
  Future<void> confirmAnchorByFloorDirection({
    required PdrLocalPoint floorDirection,
  }) async {
    if (!_guiding || _pendingPinFloorM == null) {
      return;
    }
    // 화면/floor 좌표의 방향을 자북 기준 PDR 동·북 frame으로 되돌린 뒤 비교한다.
    // axes가 반전되거나 회전된 층에서 floor 각도를 바로 빼면 90°/180° 오차가 난다.
    final pdrDirection = _pendingAxes.inverseApply(floorDirection);
    if (pdrDirection == null || pdrDirection.distance < 1e-12) return;
    final targetPdrHeadingDeg = pdrBearingForDirection(pdrDirection);
    final rotationDeg = normalizePdrRotation(
      targetPdrHeadingDeg - _session.walkingHeadingDeg,
    );
    _finalizeAnchor(
      rotationDeg: rotationDeg,
      source: AnchorSource.manualHeadingCal,
    );
  }

  @override
  Future<void> changeFloor({required String floorId}) async {
    _floorId = floorId;
    _pendingPinFloorM = null;
    _pendingPinPdrM = null;
    _pendingAxes = const PdrToFloorAxes.identity();
    _rebasePathForNewOrigin();
    _updateCalibration(CalibrationPhase.awaitingPin);
  }

  @override
  Future<void> applyVerticalTransfer({
    required String floorId,
    required PdrLocalPoint anchorLocalM,
    PdrToFloorAxes? axes,
  }) async {
    final previous = _calib.anchor;
    // 직전 anchor가 없으면 물려받을 회전값이 없다. 이때는 층만 바꾸는
    // changeFloor 경로로 사용자 pin을 받는 게 맞다(조용히 틀린 위치보다 낫다).
    if (!_guiding || previous == null) {
      return;
    }
    _floorId = floorId;
    _pendingPinFloorM = null;
    _pendingPinPdrM = null;
    _pendingAxes = const PdrToFloorAxes.identity();
    // 센서 세션은 이어가되 경로 원점만 지금으로 옮긴다. 이전 층의 늦은 batch는
    // 시간 경계로 잘라 새 층 경로에 붙지 않게 한다.
    _rebasePathForNewOrigin();
    final reference = _session.headingReference;
    _updateCalibration(
      CalibrationPhase.calibrated,
      anchor: PdrAnchor(
        floorId: floorId,
        anchorLocalM: anchorLocalM,
        // 같은 센서 세션이므로 heading frame이 끊기지 않는다. 회전값을 물려받아
        // 사용자가 새 층에서 방향 보정을 다시 하지 않게 한다.
        rotationDeg: previous.rotationDeg,
        headingReference: reference,
        requiresManualRotationCalibration:
            reference != HeadingReference.magneticNorth,
        source: AnchorSource.verticalTransfer,
        // 사용자 pin(1.0)보다 낮다. 도착 노드 좌표만큼만 정확하고, 에스컬레이터를
        // 내린 직후 실제 위치는 노드에서 몇 미터 벗어나 있을 수 있다.
        confidence: 0.7,
        axes: axes ?? previous.axes,
      ),
    );
  }

  @override
  Future<void> pauseStepTracking() async {
    // background pause와 달리 native source는 건드리지 않는다. 하차 판정의
    // 근거인 기압과 방향이 계속 들어와야 한다.
    if (!_guiding || _backgrounded) return;
    _session.pause(atMs: _session.lastMotionAtMs ?? _nowMs());
  }

  @override
  Future<void> resumeStepTracking() async {
    if (!_guiding || _backgrounded) return;
    _session.resume(atMs: _session.lastMotionAtMs ?? _nowMs());
  }

  // ── 앱 lifecycle (앱 셸이 호출) ──

  /// 앱이 background로 가면 tracking pause.
  @override
  Future<void> onAppBackgrounded() =>
      _enqueueLifecycleTransition(_applyAppBackgrounded);

  Future<void> _applyAppBackgrounded() async {
    if (!_guiding || _backgrounded) {
      return;
    }
    _backgrounded = true;
    _session.pause(atMs: _session.lastMotionAtMs ?? _nowMs());
    try {
      await _source.stop();
      _updateRuntime(PdrRuntimeState.paused);
    } on Object {
      _updateRuntime(
        PdrRuntimeState.degraded,
        warnings: const ['sensorStopFailed'],
      );
    }
  }

  /// 앱이 foreground로 돌아오면 tracking resume.
  @override
  Future<void> onAppForegrounded() =>
      _enqueueLifecycleTransition(_applyAppForegrounded);

  Future<void> _applyAppForegrounded() async {
    if (!_guiding || !_backgrounded) {
      return;
    }
    try {
      await _source.start();
      _session.resume(atMs: _session.lastMotionAtMs ?? _nowMs());
      _backgrounded = false;
      _updateRuntime(PdrRuntimeState.starting);
    } on Object {
      _updateRuntime(
        PdrRuntimeState.degraded,
        warnings: const ['sensorResumeFailed'],
      );
    }
  }

  Future<void> _enqueueLifecycleTransition(Future<void> Function() operation) {
    // paused/resumed callback은 UI에서 기다리지 않으므로 빠르게 연달아 들어올 수
    // 있다. stop이 끝나기 전에 start가 `_rawSub != null`을 보고 no-op이 되는
    // 경합을 막기 위해 실제 센서 전환은 반드시 순서대로 실행한다.
    _lifecycleTransition = _lifecycleTransition
        .catchError((Object _) {})
        .then((_) => operation());
    return _lifecycleTransition;
  }

  Future<void> dispose() async {
    await _eventSub?.cancel();
    await _sessionSub.cancel();
    _session.dispose();
    await _source.dispose();
    await _snapshots.close();
    await _calibration.close();
    await _runtimeStatuses.close();
    await _altitudes.close();
    await _rawMotion.close();
  }

  // ── 내부 ──

  void _onNativeEvent(NativePdrEvent e) {
    if (_runtimeStatus.state == PdrRuntimeState.starting) {
      _updateRuntime(PdrRuntimeState.running);
    }
    // 기압은 PdrSession에 넣지 않는다. 층 전이 판정기만 보는 별도 스트림이다.
    final altimeter = e.altimeter;
    if (altimeter != null) {
      _altimeterStatus = altimeter;
    }
    final altitude = e.altitude;
    if (altitude != null) {
      _currentAltitude = altitude;
      if (!_altitudes.isClosed) {
        _altitudes.add(altitude);
      }
    }
    // 순서 유지: heading → accel peak → pedometer (연구 엔진과 동일).
    final heading = e.heading;
    if (heading != null) {
      _session.onHeading(heading);
    }
    final accelPeak = e.accelPeak;
    if (accelPeak != null) {
      _session.onAccelPeak(accelPeak);
    }
    final pedometer = e.pedometer;
    if (pedometer != null) {
      _session.onPedometerBatch(pedometer);
    }
    _emitRawMotion(accelPeak, pedometer);
  }

  /// pause 중에도 흐르는 원시 움직임. 위치·경로에는 반영하지 않는다.
  void _emitRawMotion(
    AccelPeakEvent? accelPeak,
    PedometerBatchEvent? pedometer,
  ) {
    if (accelPeak == null && pedometer == null) return;
    final peakDelta = _delta(accelPeak?.count, () => _lastRawAccelPeakCount, (
      value,
    ) {
      _lastRawAccelPeakCount = value;
    });
    final stepDelta = _delta(pedometer?.steps, () => _lastRawPedometerSteps, (
      value,
    ) {
      _lastRawPedometerSteps = value;
    });
    if (peakDelta == null && stepDelta == null) return;
    if (_rawMotion.isClosed) return;
    _rawMotion.add(
      RawMotionActivity(
        timestampMs: _session.lastMotionAtMs ?? _nowMs(),
        accelPeakDelta: peakDelta ?? 0,
        nativeStepDelta: stepDelta,
      ),
    );
  }

  /// 누적 카운터의 증가분. 첫 관측과 세션 재시작(감소)은 0으로 본다.
  static int? _delta(
    int? current,
    int? Function() read,
    void Function(int) write,
  ) {
    if (current == null) return null;
    final previous = read();
    write(current);
    if (previous == null || current < previous) return 0;
    return current - previous;
  }

  void _onSourceError(Object error, [StackTrace? stackTrace]) {
    _updateRuntime(
      PdrRuntimeState.degraded,
      warnings: const ['sensorStreamError'],
    );
  }

  void _onSnapshot(PdrSnapshot snapshot) {
    final output = _withRuntimeQuality(snapshot);
    _current = output;
    if (!_snapshots.isClosed) {
      _snapshots.add(output);
    }
  }

  PdrSnapshot _withRuntimeQuality(PdrSnapshot snapshot) {
    if (_runtimeStatus.state != PdrRuntimeState.degraded) {
      return snapshot;
    }
    final warnings = <String>{
      ...snapshot.quality.warnings,
      ..._runtimeStatus.warnings,
    }.toList(growable: false);
    return PdrSnapshot(
      position: snapshot.position,
      path: snapshot.path,
      steps: snapshot.steps,
      distanceM: snapshot.distanceM,
      orientationHeadingDeg: snapshot.orientationHeadingDeg,
      walkingHeadingDeg: snapshot.walkingHeadingDeg,
      hasHeading: snapshot.hasHeading,
      preview: snapshot.preview,
      ronin: snapshot.ronin,
      lastAppliedBatch: snapshot.lastAppliedBatch,
      quality: PdrQuality(
        state: PdrQualityState.degraded,
        warnings: warnings,
        features: snapshot.quality.features,
      ),
    );
  }

  void _rebasePathForNewOrigin() {
    _session.rebasePath(atMs: _nowMs());
  }

  void _finalizeAnchor({
    required double rotationDeg,
    required AnchorSource source,
  }) {
    final pinFloor = _pendingPinFloorM;
    final pinPdr = _pendingPinPdrM;
    if (pinFloor == null || pinPdr == null) {
      return;
    }
    // anchorLocalM = pinFloor - axes·R(rotationDeg)·pinPdr.
    // PDR는 +east/+north지만 floor local_m은 +y가 남쪽일 수 있으므로, anchor
    // 확정에도 렌더링과 같은 축 변환을 적용해야 한다.
    final mappedPinPdr = _pendingAxes.apply(
      rotatePdrBearing(pinPdr, rotationDeg),
    );
    final anchorLocalM = PdrLocalPoint(
      pinFloor.eastM - mappedPinPdr.eastM,
      pinFloor.northM - mappedPinPdr.northM,
    );

    final reference = _session.headingReference;
    final anchor = PdrAnchor(
      floorId: _floorId ?? '',
      anchorLocalM: anchorLocalM,
      rotationDeg: rotationDeg,
      headingReference: reference,
      requiresManualRotationCalibration:
          reference != HeadingReference.magneticNorth,
      source: source,
      confidence: 1,
      axes: _pendingAxes,
    );
    _pendingPinFloorM = null;
    _pendingPinPdrM = null;
    _pendingAxes = const PdrToFloorAxes.identity();
    _updateCalibration(CalibrationPhase.calibrated, anchor: anchor);
  }

  void _updateCalibration(CalibrationPhase phase, {PdrAnchor? anchor}) {
    final reference = _session.headingReference;
    _calib = CalibrationStatus(
      phase: phase,
      headingReference: reference,
      requiresManualRotationCalibration:
          reference != HeadingReference.magneticNorth,
      anchor: anchor,
    );
    if (!_calibration.isClosed) {
      _calibration.add(_calib);
    }
  }

  void _updateRuntime(
    PdrRuntimeState state, {
    List<String> warnings = const [],
  }) {
    _runtimeStatus = PdrRuntimeStatus(
      state: state,
      warnings: List.unmodifiable(warnings),
    );
    if (!_runtimeStatuses.isClosed) {
      _runtimeStatuses.add(_runtimeStatus);
    }
  }
}
