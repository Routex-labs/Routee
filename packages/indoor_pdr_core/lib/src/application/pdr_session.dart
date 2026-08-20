import 'dart:async';
import 'dart:math' as math;

import '../domain/angle_utils.dart';
import '../domain/events.dart';
import '../domain/heading_reference.dart';
import '../domain/heading_sample.dart';
import '../domain/pdr_local_point.dart';
import '../domain/quality.dart';
import '../domain/snapshot.dart';
import 'accel_preview_track.dart';
import 'heading_trackers.dart';
import 'path_accumulator.dart';
import 'pedometer_batch_processor.dart';
import 'pdr_session_config.dart';
import 'quality_metrics.dart';
import 'ronin_stride_track.dart';
import 'stride_estimator.dart';

/// 적용된 confirmed 배치의 진단 정보. [PdrSession.onBatchApplied]로 전달된다.
class AppliedBatchInfo {
  const AppliedBatchInfo({
    required this.batchId,
    required this.deltaSteps,
    required this.appliedSteps,
    required this.stepDistanceMeters,
    required this.strideSource,
  });

  final int batchId;
  final int deltaSteps;
  final int appliedSteps;
  final double stepDistanceMeters;
  final String strideSource;
}

/// 위젯·플랫폼·지도·GPS·ML·export에 의존하지 않는 PDR 코어.
///
/// typed 센서 이벤트를 받아 confirmed(초록) 경로/거리와 preview(주황) 경로, 품질
/// 신호를 유지한다. 연구 앱 `PdrEngine`의 오케스트레이션을 재작성했다:
///   - `Offset`→`PdrLocalPoint`, `ValueNotifier`→`Stream<PdrSnapshot>`
///   - GPS reference / IMU v3 / ML preview / JSON export / relative-display baseline 제외
///
/// 위치 계산:
///   거리 = CMPedometer step delta × 추정 보폭
///   방향 = fused heading smoothing + walkOffset 보정
///
/// 이 결과는 초록 센서 원본이다. 제품 현재 위치의 복도 제약은 floor graph를
/// 소유한 Flutter 클라이언트가 별도 상태로 적용한다.
class PdrSession {
  /// heading 전용 스냅샷을 내보내기 전에 **다른 스냅샷이 없었어야 하는** 시간.
  ///
  /// 소비자는 스냅샷 하나마다 화면 전체를 다시 그리고 지도 소스를 다시 올린다.
  /// 그래서 이 신호는 "걸음이 없어 스냅샷이 끊긴 구간을 메우는" 용도로만 써야
  /// 한다. 걷는 동안에는 accel peak가 이미 초당 두어 번 스냅샷을 만들고 그
  /// 스냅샷에 최신 heading이 실려 있으므로, 여기서 더 보탤 이유가 없다.
  ///
  /// 처음에 이 조건 없이 150ms마다 내보냈더니 갱신 빈도가 3배가 되면서 지도
  /// 채널이 밀렸고, 도면 로딩과 위치 반영이 눈에 띄게 느려졌다.
  static const int _headingEmitQuietMs = 400;

  /// 이만큼도 안 움직였으면 방향이 바뀐 게 아니라 센서가 떠는 것이다.
  static const double _headingEmitMinDeltaDeg = 2.0;

  PdrSession({PdrSessionConfig? config})
    : config = config ?? const PdrSessionConfig() {
    _paths = PathAccumulator(maxPoints: this.config.maxPathPoints);
    _accelPreview = AccelPreviewTrack(maxPoints: this.config.maxPathPoints);
    _roninTrack = RoninStrideTrack(maxPoints: this.config.maxPathPoints);
    _stride.fallbackMeters = this.config.fallbackStrideMeters;
    _stride.effectiveMeters = this.config.fallbackStrideMeters;
    _stride.lastBatchMeters = this.config.fallbackStrideMeters;
  }

  final PdrSessionConfig config;

  late final PathAccumulator _paths;
  late final AccelPreviewTrack _accelPreview;
  late final RoninStrideTrack _roninTrack;
  final StrideEstimator _stride = StrideEstimator();
  final PedometerBatchProcessor _pedometer = PedometerBatchProcessor();
  final SwingDetector _swing = SwingDetector();
  final WalkOffsetEstimator _walkOffset = WalkOffsetEstimator();
  final HeadingConvergenceTracker _headingConvergence =
      HeadingConvergenceTracker();
  final HeadingHistory _headingHistory = HeadingHistory();

  final StreamController<PdrSnapshot> _snapshots =
      StreamController<PdrSnapshot>.broadcast();

  bool _tracking = true;

  // fused heading 상태.
  bool hasFusedHeading = false;
  double fusedHeadingDeg = 0;
  bool headingStable = false;
  String headingSource = 'waiting';
  double deviceHeadingDeg = -1;
  double yawDeg = 0;
  double gyroHeadingDeg = 0;
  double pitchDeg = 0;
  double rollDeg = 0;
  String magneticAccuracy = 'unknown';
  double rotationHeadingAccuracyDeg = -1;
  double walkDirDeg = 0;
  double walkDirConfidence = 0;
  int? lastMotionAtMs;

  // 걸음 없이 방향만 바뀔 때 스냅샷을 흘려보내는 스로틀 상태.
  //
  // [_lastEmitAtMs]는 heading 전용이 아니라 **모든** 스냅샷의 시각이다. 걸음이
  // 만든 스냅샷도 같이 세야 "조용한 구간"을 판단할 수 있다.
  int? _lastEmitAtMs;
  double? _lastEmittedHeadingDeg;

  int iosTrackedSteps = 0;

  /// 마지막으로 confirmed 경로에 반영된 배치. snapshot이 그대로 실어 나른다.
  PdrAppliedBatch? _lastAppliedBatch;

  /// 적용된 confirmed 배치 진단 훅(telemetry/테스트용). appliedSteps>0일 때만 호출.
  void Function(AppliedBatchInfo info)? onBatchApplied;

  // ── 파생 상태 ──

  bool get tracking => _tracking;

  /// fused heading + walkOffset. confirmed path 방향의 기준.
  double get walkingHeadingDeg =>
      normalizeDegrees(fusedHeadingDeg + _walkOffset.offsetDeg);

  /// [walkingHeadingDeg]에 더해진 보정량(진단용). ±60°로 clamp된다.
  double get walkOffsetDeg => _walkOffset.offsetDeg;

  /// walkOffset이 지금 갱신 중인지(진단용).
  bool get walkOffsetActive => _walkOffset.active;

  /// heading이 자리를 잡았는지. 앵커를 확정하기 전에 이 값을 확인하면, 방향이
  /// 아직 흔들리는 동안 놓인 첫 걸음들이 틀어지는 것을 막을 수 있다.
  bool get headingConverged => _headingConvergence.converged;

  /// 수렴 판정 창의 최대 편차(도).
  double get headingSpreadDeg => _headingConvergence.spreadDeg;

  HeadingReference get headingReference =>
      headingReferenceFromSource(headingSource);

  PdrLocalPoint get position => _paths.correctedPosition;
  List<PdrLocalPoint> get path => List.unmodifiable(_paths.corrected);
  int get steps => iosTrackedSteps;

  /// confirmed 이동 거리(m). tracking 중 반영한 step distance 합.
  double get distanceM => _stride.trackedDistanceM;

  Stream<PdrSnapshot> get snapshots => _snapshots.stream;

  // ── 이벤트 입력 ──

  /// CoreMotion DeviceMotion 이벤트. heading smoothing/swing/walkOffset/history 갱신.
  void onHeading(HeadingEvent e) {
    headingSource = e.headingSource ?? headingSource;
    deviceHeadingDeg = e.deviceHeadingDeg ?? deviceHeadingDeg;
    magneticAccuracy = e.magneticAccuracy ?? magneticAccuracy;
    rotationHeadingAccuracyDeg =
        e.rotationHeadingAccuracyDeg ?? rotationHeadingAccuracyDeg;
    headingStable = e.headingStable ?? headingStable;
    yawDeg = e.yawDeg ?? yawDeg;
    gyroHeadingDeg = e.gyroHeadingDeg ?? gyroHeadingDeg;
    pitchDeg = e.pitchDeg ?? pitchDeg;
    rollDeg = e.rollDeg ?? rollDeg;
    walkDirDeg = e.walkDirDeg ?? walkDirDeg;
    walkDirConfidence = e.walkDirConfidence ?? walkDirConfidence;

    // motionTimestamp는 native step peak timestamp와 같은 시간축이다.
    final motionMs = e.motionTimestampMs;
    final dtSeconds = ((motionMs - (lastMotionAtMs ?? motionMs)) / 1000.0)
        .clamp(0.0, 0.5);
    lastMotionAtMs = motionMs;

    // 팔 흔들림은 smoothing 전 raw heading으로 판단한다.
    _swing.update(motionMs, e.fusedHeadingDeg);
    // smoothing 전 raw로 판정한다. 필터 tau가 0.1초라 smoothing된 값은 raw를
    // 거의 그대로 따라가지만, 수렴 판정만큼은 필터가 만든 매끄러움에 속으면
    // 안 된다.
    _headingConvergence.update(motionMs, e.fusedHeadingDeg);
    _updateFusedHeading(e.fusedHeadingDeg, dtSeconds);
    _walkOffset.update(
      nowMs: motionMs,
      dtSeconds: dtSeconds,
      swinging: _swing.swinging,
      swingNetDeg: _swing.netDeg,
      walkDirDeg: walkDirDeg,
      walkDirConfidence: walkDirConfidence,
      fusedHeadingDeg: fusedHeadingDeg,
    );
    _headingHistory.add(
      HeadingSample(
        ms: motionMs,
        walkDeg: walkingHeadingDeg,
        fusedDeg: fusedHeadingDeg,
        yawDeg: yawDeg,
        deviceHeadingDeg: deviceHeadingDeg,
      ),
    );
    _maybeEmitHeading(motionMs);
  }

  /// 걸음이 끊긴 구간에서만 방향 갱신을 흘려보낸다.
  ///
  /// 스냅샷은 원래 걸음에서만 나갔다(accel peak 채택 · pedometer 배치). 그래서
  /// 제자리에 서서 몸만 돌리면 소비자가 받는 heading이 **마지막 걸음 시점에
  /// 얼어붙었다** — 코너에서 방향을 트는 순간이 정작 방향이 가장 필요한 때다.
  ///
  /// 그렇다고 native motion 주기(30ms)로 흘리면 안 된다. 소비자는 스냅샷마다
  /// 화면을 다시 그리므로 갱신 빈도가 그대로 비용이다. 걷는 동안에는 이미
  /// 스냅샷이 충분히 나가고 거기에 최신 heading이 실려 있으니, 여기서는
  /// **[_headingEmitQuietMs] 동안 아무 스냅샷도 없었을 때만** 보탠다.
  void _maybeEmitHeading(int motionMs) {
    final lastEmit = _lastEmitAtMs;
    if (lastEmit != null && motionMs - lastEmit < _headingEmitQuietMs) {
      return;
    }
    final previous = _lastEmittedHeadingDeg;
    final current = walkingHeadingDeg;
    if (previous != null &&
        shortestDeltaDegrees(current - previous).abs() <
            _headingEmitMinDeltaDeg) {
      return;
    }
    _lastEmittedHeadingDeg = current;
    _emitAt(motionMs);
  }

  /// native accel step-peak 신호. 주황 preview 경로에만 반영.
  void onAccelPeak(AccelPeakEvent e) {
    final changed = _accelPreview.applyRealtimePeaks(
      e,
      tracking: _tracking,
      hasHeading: hasFusedHeading,
      effectiveStrideMeters: _stride.effectiveMeters,
      fallbackStrideMeters: _stride.fallbackMeters,
      confirmedSteps: iosTrackedSteps,
      confirmedDistanceM: _stride.trackedDistanceM,
      // 총 주황/초록 걸음 수의 차이가 아니라, 마지막 초록 배치 뒤 아직
      // 확정되지 않은 주황 꼬리만 제한한다. 배치가 올 때마다 그 시간창 안의
      // peak가 자연스럽게 소비돼 새 초록 끝점에서 preview 여유가 다시 열린다.
      confirmedThroughMs: _lastAppliedBatch?.spanEndMs,
      pedometerCadenceHz: _stride.cadenceAvailable ? _stride.cadenceHz : null,
      headingAt: _headingHistory.at,
      fallbackHeadingDeg: walkingHeadingDeg,
    );
    if (changed) {
      _emit();
    }
  }

  /// CMPedometer 배치. confirmed(초록) 경로/거리에 반영.
  void onPedometerBatch(PedometerBatchEvent e) {
    final roninObservationChanged = _roninTrack.observe(e);
    final application = _pedometer.process(
      e,
      receivedAtMs: config.nowMs(),
      tracking: _tracking,
      hasHeading: hasFusedHeading,
      trackedSteps: iosTrackedSteps,
      stride: _stride,
    );
    if (application == null) {
      if (roninObservationChanged) _emit();
      return;
    }
    final applied = _paths.applyPedometerBatch(
      count: application.appliedSteps,
      stepDistanceMeters: application.stepDistanceMeters,
      currentWalkDeg: walkingHeadingDeg,
      currentFusedDeg: fusedHeadingDeg,
      headingAt: _headingHistory.at,
      spanStartMs: application.spanStartMs,
      spanEndMs: application.spanEndMs,
      peakTimes: application.peakTimes,
    );
    iosTrackedSteps += applied;
    _stride.addTrackedDistance(application.stepDistanceMeters * applied);
    _lastAppliedBatch = PdrAppliedBatch(
      batchId: application.batchId,
      spanStartMs: application.spanStartMs,
      spanEndMs: application.spanEndMs,
      appliedSteps: applied,
      appliedDistanceM: application.stepDistanceMeters * applied,
    );
    _roninTrack.apply(
      application,
      currentWalkDeg: walkingHeadingDeg,
      currentFusedDeg: fusedHeadingDeg,
      headingAt: _headingHistory.at,
    );
    onBatchApplied?.call(
      AppliedBatchInfo(
        batchId: application.batchId,
        deltaSteps: application.deltaSteps,
        appliedSteps: applied,
        stepDistanceMeters: application.stepDistanceMeters,
        strideSource: application.strideSource,
      ),
    );
    _emit();
  }

  // ── 외부 command ──

  /// pause. 전이 시각을 motion 시간축으로 기록해 늦은 batch를 시간축으로 분할한다.
  void pause({required int atMs}) => _setTracking(false, atMs);

  void resume({required int atMs}) => _setTracking(true, atMs);

  /// 경로·추정 상태 초기화. [newStepSessionId] 이후 pedometer event만 받는다.
  void reset({int? newStepSessionId}) {
    _paths.reset();
    _accelPreview.reset();
    _roninTrack.reset();
    iosTrackedSteps = 0;
    // _pedometer.reset()이 batchId를 1로 되돌리므로 이전 배치 식별자를 남기면
    // 소비자가 새 세션의 batchId=1을 "이미 소비함"으로 오판한다.
    _lastAppliedBatch = null;
    _pedometer.reset(
      initialTrackingOn: _tracking,
      newSessionId: newStepSessionId,
    );
    _headingHistory.clear();
    _stride.reset();
    _swing.reset();
    walkDirConfidence = 0;
    _walkOffset.reset();
    _headingConvergence.reset();
    _emit();
  }

  /// 네이티브 센서 스트림과 heading 수렴 상태를 유지한 채 경로 원점만 다시 잡는다.
  ///
  /// 위치 재지정·층 전환 때 `CMPedometer.stop/start`를 호출하지 않기 위한 경로다.
  /// 누적 counter baseline은 보존하고 [atMs] 이전 걸음은 tracking timeline에서
  /// 제외하므로 다음 늦은 batch가 이전 이동을 새 원점 뒤에 다시 붙이지 않는다.
  void rebasePath({required int atMs}) {
    _paths.reset();
    _accelPreview.reset(preserveNativePeakBaseline: true);
    _roninTrack.rebasePath();
    iosTrackedSteps = 0;
    _lastAppliedBatch = null;
    _pedometer.rebasePath(atMs: atMs, initialTrackingOn: _tracking);
    _stride.rebaseTrackedDistance();
    _emit();
  }

  /// 현재 스냅샷을 즉시 만든다.
  PdrSnapshot get snapshot => _buildSnapshot();

  void dispose() {
    _snapshots.close();
  }

  // ── 내부 ──

  void _setTracking(bool value, int atMs) {
    if (value == _tracking) {
      return;
    }
    _tracking = value;
    _pedometer.addTrackingTransition(atMs: atMs, on: value);
  }

  /// heading smoothing 시간상수. 안정적이면 빠르게, 팔 흔들림 중이면 느리게.
  double get _headingTauSeconds {
    if (!headingStable) {
      return 0.60;
    }
    if (_swing.swinging) {
      return 1.00;
    }
    return 0.10;
  }

  /// fused heading을 최단각 exponential filter로 smoothing한다.
  void _updateFusedHeading(double targetDeg, double dtSeconds) {
    if (!hasFusedHeading) {
      hasFusedHeading = true;
      fusedHeadingDeg = normalizeDegrees(targetDeg);
      return;
    }
    final alpha = 1 - math.exp(-dtSeconds / _headingTauSeconds);
    final delta = shortestDeltaDegrees(targetDeg - fusedHeadingDeg);
    fusedHeadingDeg = normalizeDegrees(fusedHeadingDeg + delta * alpha);
  }

  void _emit() => _emitAt(lastMotionAtMs);

  void _emitAt(int? atMs) {
    if (_snapshots.isClosed) return;
    // motion 시간축이 아직 없으면(센서 시작 전 reset 등) 조용한 구간 판정만
    // 건너뛰고 스냅샷은 그대로 내보낸다.
    if (atMs != null) _lastEmitAtMs = atMs;
    _snapshots.add(_buildSnapshot());
  }

  PdrSnapshot _buildSnapshot() {
    final quality = _buildQuality();
    return PdrSnapshot(
      position: _paths.correctedPosition,
      path: List.unmodifiable(_paths.corrected),
      steps: iosTrackedSteps,
      distanceM: _stride.trackedDistanceM,
      orientationHeadingDeg: fusedHeadingDeg,
      walkingHeadingDeg: walkingHeadingDeg,
      hasHeading: hasFusedHeading,
      preview: PdrPreview(
        position: _accelPreview.position,
        path: List.unmodifiable(_accelPreview.path),
        steps: _accelPreview.steps,
        distanceM: _accelPreview.distanceM,
        acceptedPeakTimesMs: List.unmodifiable(
          _accelPreview.acceptedPeakTimesMs,
        ),
      ),
      ronin: _roninTrack.snapshot,
      quality: quality,
      lastAppliedBatch: _lastAppliedBatch,
    );
  }

  PdrQuality _buildQuality() {
    final undercount = QualityMetrics.undercountScan(_pedometer.batches);
    final undercountSuspected = QualityMetrics.pedometerUndercountSuspected(
      _pedometer.batches,
    );
    final overcountLikely = QualityMetrics.accelOvercountLikely(
      nativeSessionSteps: _pedometer.nativeSessionSteps,
      accelPreviewSteps: _accelPreview.steps,
      pedometerUndercountSuspected: undercountSuspected,
    );
    final green = _stride.trackedDistanceM;
    final orange = _accelPreview.distanceM;
    final divergencePct = green > 0
        ? (orange - green).abs() / green * 100.0
        : 0.0;
    final ratio = _pedometer.nativeSessionSteps > 0
        ? _accelPreview.steps / _pedometer.nativeSessionSteps
        : 0.0;

    // 판정(잠정, §5): undercount는 진단 전용이라 자동 전환에 쓰지 않지만 degraded
    // 신호로는 쓴다. divergence 단독으로 degraded를 만들지 않는다(주황 과검출일 수 있음).
    final PdrQualityState state;
    if (undercountSuspected) {
      state = PdrQualityState.degraded;
    } else if (divergencePct > config.cautionDivergencePct || overcountLikely) {
      state = PdrQualityState.caution;
    } else {
      state = PdrQualityState.healthy;
    }

    final warnings = QualityMetrics.warnings(
      nativeSessionSteps: _pedometer.nativeSessionSteps,
      accelPreviewSteps: _accelPreview.steps,
      accelPreviewRejectReasons: _accelPreview.rejectReasons,
      pedometerUndercountSuspected: undercountSuspected,
    );

    return PdrQuality(
      state: state,
      warnings: warnings,
      features: PdrQualityFeatures(
        greenOrangeDistanceDivergencePct: divergencePct,
        orangeStepRatio: ratio,
        orangeOvercountLikely: overcountLikely,
        pedometerUndercountSuspected: undercountSuspected,
        pedometerFlaggedSpanS: undercount.flaggedSpanMs / 1000.0,
        headingStable: headingStable,
        headingSource: headingSource,
        magneticAccuracy: magneticAccuracy,
        rotationHeadingAccuracyDeg: rotationHeadingAccuracyDeg,
        cadenceHz: _stride.cadenceHz,
        pitchDeg: pitchDeg,
        rollDeg: rollDeg,
        headingReferenceIsMagneticNorth:
            headingReference == HeadingReference.magneticNorth,
        peakRejectHistogram: Map.unmodifiable(_accelPreview.rejectReasons),
        fusedHeadingDeg: fusedHeadingDeg,
        walkOffsetDeg: walkOffsetDeg,
        walkOffsetActive: walkOffsetActive,
        deviceHeadingDeg: deviceHeadingDeg,
        gyroHeadingDeg: gyroHeadingDeg,
        walkDirDeg: walkDirDeg,
        walkDirConfidence: walkDirConfidence,
        headingConverged: headingConverged,
        headingSpreadDeg: headingSpreadDeg,
      ),
    );
  }
}
