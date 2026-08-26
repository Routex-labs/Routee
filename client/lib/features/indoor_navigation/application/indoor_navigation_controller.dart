import 'dart:async';

import 'package:flutter/foundation.dart';
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
    ValueListenable<double>? headingOffsetDeg,
  }) : _source = source, // ignore: prefer_initializing_formals
       _nowMs = nowMs ?? _defaultNowMs,
       // ignore: prefer_initializing_formals
       _headingOffsetDeg = headingOffsetDeg {
    _session = PdrSession(config: config);
    _sessionSub = _session.snapshots.listen(_onSnapshot);
    _headingOffsetDeg?.addListener(_onHeadingOffsetChanged);
  }

  static int _defaultNowMs() => DateTime.now().millisecondsSinceEpoch;

  final PdrMotionSource _source;
  final int Function() _nowMs;

  /// 디버그 전용 현장 보정 노브. null이면(=일반 사용자) 언제나 0도다.
  final ValueListenable<double>? _headingOffsetDeg;

  /// 노브를 뺀 회전각. 노브를 돌릴 때마다 이 값 위에 다시 얹는다.
  double _baseRotationDeg = 0;

  late final PdrSession _session;
  late final StreamSubscription<PdrSnapshot> _sessionSub;
  StreamSubscription<NativePdrEvent>? _eventSub;

  final _snapshots = StreamController<PdrSnapshot>.broadcast();
  final _calibration = StreamController<CalibrationStatus>.broadcast();
  final _runtimeStatuses = StreamController<PdrRuntimeStatus>.broadcast();
  final _altitudes = StreamController<AltitudeSample>.broadcast();
  final _rawMotion = StreamController<RawMotionActivity>.broadcast();

  /// 화면 회전용 방향. native motion 주기(≈33Hz)로 흐른다 — 스냅샷과 나눈
  /// 이유는 [PdrHeadingSample]에 있다.
  final _headings = StreamController<PdrHeadingSample>.broadcast();

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
  Stream<PdrHeadingSample> get headings => _headings.stream;

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
    double? trueCourseDeg,
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
    // **frame이 자북인 것만으로는 부족하다.** 안드로이드는 gyro hold 중에도
    // frame을 자북으로 신고하므로, 그것만 보면 철골 건물 안에서 통째로 돌아간
    // 방위를 보정 없이 앵커에 구워 넣는다([PdrSession.headingTrustworthy]).
    if (_session.headingTrustworthy &&
        !_courseContradictsHeading(trueCourseDeg)) {
      // 믿을 수 있는 자북 기준이어도 회전각은 0이 아니다. floor 축은 진북
      // 기준이라 자편각을 더해야 한다 — 여기를 0으로 두면 실내 heading 전체가
      // 그만큼 통째로 돌아간다.
      _finalizeAnchor(
        rotationDeg: magneticDeclinationDeg,
        source: AnchorSource.userPin,
        basis: AnchorRotationBasis.trustedHeading,
      );
    } else {
      // frame이 arbitrary이거나, 자북이어도 센서가 스스로 오차가 크다고 보고한
      // 경우다. 둘 다 진행 방향으로 보정해야 한다(§4). 방금 밖에서 걷던 방향과
      // 어긋난 나침반도 여기로 온다 — 문 앞 철제 구조물이 흔한 원인이고, 그
      // 왜곡은 세기·신고 오차로는 안 잡힌다([entryCourseDisagreementDeg]).
      _updateCalibration(CalibrationPhase.awaitingHeading);
    }
  }

  /// 방금 밖에서 걷던 진행 방향이 지금 나침반과 어긋나는가.
  ///
  /// 나침반이 말하는 진행 방향은 `걸음 방위 + 자편각`이다 — [_finalizeAnchor]가
  /// 자북 갈래에서 쓰는 회전각과 **같은 식**이라, 여기서 통과한 값이 곧 그
  /// 회전각의 근거가 된다. 잴 값이 없으면 어긋난다고 하지 않는다 — 나쁘다는
  /// 증거가 있을 때만 거부한다는 규칙은 여기서도 같다.
  bool _courseContradictsHeading(double? trueCourseDeg) {
    if (trueCourseDeg == null) return false;
    final compassCourseDeg = normalizePdrBearing(
      _session.walkingHeadingDeg + magneticDeclinationDeg,
    );
    final gapDeg = normalizePdrRotation(compassCourseDeg - trueCourseDeg).abs();
    return gapDeg > entryCourseDisagreementDeg;
  }

  @override
  Future<void> confirmAnchorByFloorDirection({
    required PdrLocalPoint floorDirection,
    required AnchorRotationBasis basis,
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
      basis: basis,
    );
  }

  @override
  Future<void> flipAnchorRotation() async {
    final previous = _calib.anchor;
    if (!_guiding || previous == null) return;
    // anchor 원점은 pin 그 자리다(`_finalizeAnchor`에서 pinPdr이 0). 회전각만
    // 180° 돌리면 궤적이 그 점을 중심으로 점대칭이 되고 찍은 자리는 안 움직인다.
    _updateCalibration(
      CalibrationPhase.calibrated,
      anchor: PdrAnchor(
        floorId: previous.floorId,
        anchorLocalM: previous.anchorLocalM,
        rotationDeg: normalizePdrRotation(previous.rotationDeg + 180),
        rotationBasis: AnchorRotationBasis.corridorAxisFlipped,
        headingReference: previous.headingReference,
        requiresManualRotationCalibration:
            previous.requiresManualRotationCalibration,
        source: previous.source,
        confidence: previous.confidence,
        axes: previous.axes,
      ),
    );
  }

  @override
  Future<void> resetHeadingTrust() async {
    if (!_guiding) return;
    // startGuidance가 세션을 여는 순간 부르는 것과 같은 호출이다 — native
    // 소스는 건드리지 않으므로 걸음 세션은 끊기지 않는다.
    _session.reset();
    _updateCalibration(CalibrationPhase.awaitingPin);
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
        rotationDeg: _rotationWithOffset(),
        rotationBasis: AnchorRotationBasis.inherited,
        headingOffsetDeg: _headingOffset,
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
    _headingOffsetDeg?.removeListener(_onHeadingOffsetChanged);
    await _eventSub?.cancel();
    await _sessionSub.cancel();
    _session.dispose();
    await _source.dispose();
    await _snapshots.close();
    await _calibration.close();
    await _runtimeStatuses.close();
    await _altitudes.close();
    await _rawMotion.close();
    await _headings.close();
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
      _emitHeading();
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

  /// 방향만 실어 내보낸다. **스냅샷을 만들지 않는다** — 스냅샷은 궤적 목록을
  /// 복사하고 소비자가 화면을 다시 그리므로, 이 주기(≈33Hz)로 낼 수 없다.
  void _emitHeading() {
    if (_headings.isClosed) return;
    _headings.add(
      PdrHeadingSample(
        orientationDeg: _session.fusedHeadingDeg,
        walkingDeg: _session.walkingHeadingDeg,
        converged: _session.hasFusedHeading,
      ),
    );
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

  /// 지금 적용할 현장 보정 노브 값. 디버그가 꺼져 있으면 0이다.
  double get _headingOffset => _headingOffsetDeg?.value ?? 0;

  /// 노브를 돌리면 이미 선 anchor의 회전각도 바로 따라간다.
  ///
  /// 실기기 앞에서 몇 도인지 맞춰 보려면 값을 바꿀 때마다 화면이 돌아야 한다.
  /// 다시 pin을 찍게 하면 노브가 아니라 재보정 절차가 된다. pin은 언제나 PDR
  /// 원점(0,0)에서 찍으므로 anchorLocalM은 회전과 무관하다 — 회전각만 갈아
  /// 끼우면 된다.
  void _onHeadingOffsetChanged() {
    final anchor = _calib.anchor;
    if (anchor == null) return;
    _updateCalibration(
      _calib.phase,
      anchor: PdrAnchor(
        floorId: anchor.floorId,
        anchorLocalM: anchor.anchorLocalM,
        rotationDeg: _rotationWithOffset(),
        headingReference: anchor.headingReference,
        requiresManualRotationCalibration:
            anchor.requiresManualRotationCalibration,
        source: anchor.source,
        confidence: anchor.confidence,
        axes: anchor.axes,
        rotationBasis: anchor.rotationBasis,
        headingOffsetDeg: _headingOffset,
      ),
    );
  }

  double _rotationWithOffset() =>
      normalizePdrRotation(_baseRotationDeg + _headingOffset);

  void _finalizeAnchor({
    required double rotationDeg,
    required AnchorSource source,
    required AnchorRotationBasis basis,
  }) {
    final pinFloor = _pendingPinFloorM;
    final pinPdr = _pendingPinPdrM;
    if (pinFloor == null || pinPdr == null) {
      return;
    }
    _baseRotationDeg = rotationDeg;
    final rotation = _rotationWithOffset();
    // anchorLocalM = pinFloor - axes·R(rotationDeg)·pinPdr.
    // PDR는 +east/+north지만 floor local_m은 +y가 남쪽일 수 있으므로, anchor
    // 확정에도 렌더링과 같은 축 변환을 적용해야 한다.
    final mappedPinPdr = _pendingAxes.apply(rotatePdrBearing(pinPdr, rotation));
    final anchorLocalM = PdrLocalPoint(
      pinFloor.eastM - mappedPinPdr.eastM,
      pinFloor.northM - mappedPinPdr.northM,
    );

    final reference = _session.headingReference;
    final anchor = PdrAnchor(
      floorId: _floorId ?? '',
      anchorLocalM: anchorLocalM,
      rotationDeg: rotation,
      rotationBasis: basis,
      headingOffsetDeg: _headingOffset,
      headingReference: reference,
      // **frame이 아니라 신뢰를 기록한다.** 이 값은 진단 로그로만 나가는데,
      // frame만 적으면 "자북인데 왜 회전값이 0이 아닌가"를 사후에 되짚을 수 없다.
      requiresManualRotationCalibration: !_session.headingTrustworthy,
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
    _calib = CalibrationStatus(
      phase: phase,
      headingReference: _session.headingReference,
      requiresManualRotationCalibration: !_session.headingTrustworthy,
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
