import 'dart:math' as math;

import '../domain/events.dart';
import '../domain/heading_sample.dart';
import '../domain/pdr_local_point.dart';
import 'stride_estimator.dart';

/// accel peak만으로 누적하는 raw-ish preview path(주황).
///
/// confirmed path/distance/count에는 영향을 주지 않는 비교용 경로다.
///
/// 연구 앱 `accel_preview_track.dart`에서 옮겼다. `Offset`→`PdrLocalPoint`로 바꾸고
/// export 전용 stepEvents/peakEvents/recentRejects/pathPoints는 제거했다.
/// quality가 읽는 [rejectReasons] 히스토그램은 보존한다.
class AccelPreviewTrack {
  AccelPreviewTrack({this.maxPoints = 800});

  static const int maxStepLead = 12;
  static const double maxDistanceLeadMeters = 10.0;
  static const int maxInitialStepLead = 30;
  static const double maxInitialDistanceLeadMeters = 24.0;
  static const int minPeakIntervalMs = 300;
  static const int maxPeakIntervalMs = 1100;

  /// 확정이 이만큼 늦어질 때까지는 lead cap을 적용하지 않는다.
  ///
  /// 캡의 목적은 "센서가 폭주해도 주황이 무한히 달아나지 않게" 하는 것이지
  /// **확정 배치가 늦다는 이유로 마커를 세우는 것**이 아니다. 예전에는 둘을
  /// 구분하지 못해서, 첫 배치가 도착한 뒤로는 pedometer 지연이 곧바로 12걸음
  /// 캡에 닿아 걸음이 버려졌다 — 걷는데 화면이 멈췄다가 배치가 오면 한꺼번에
  /// 밀려가는 동작의 원인이다. 확정 시각과 지금 peak의 간격으로 둘을 가른다:
  /// 이 창 안이면 "정상적인 배치 지연"이라 캡을 재지 않고, 이보다 오래 확정이
  /// 없으면(heading 소실·pedometer 정지) 그때부터 캡이 걸린다.
  static const int confirmedLagGraceMs = 8000;

  /// 캡에 걸린 걸음을 보류해 두는 최대 개수.
  ///
  /// 버리지 않고 들고 있다가 확정이 따라오면 소비한다. 무한히 쌓으면 센서가
  /// 정말 폭주했을 때 나중에 그 걸음이 통째로 풀려 위치가 순간이동하므로
  /// 상한을 둔다. 넘치면 **가장 오래된 쪽**을 버린다 — 최근 걸음이 지금
  /// 위치에 더 가깝다.
  static const int maxDeferredPeaks = 40;

  static const String baseline = 'baseline';
  static const String tooDense = 'tooDense';
  static const String tooSparse = 'tooSparse';
  static const String cadenceMismatch = 'cadenceMismatch';
  static const String stepLeadCap = 'stepLeadCap';
  static const String distanceLeadCap = 'distanceLeadCap';
  static const String notTracking = 'notTracking';
  static const String noHeading = 'noHeading';
  static const String missingTimestamp = 'missingTimestamp';
  static const String batchedPeaksCapped = 'batchedPeaksCapped';

  /// 캡에 걸렸지만 버리지 않고 보류 중인 걸음. 확정이 따라오면 반영된다.
  static const String leadDeferred = 'leadDeferred';

  /// 보류 큐가 넘쳐 실제로 버린 걸음.
  static const String deferOverflow = 'deferOverflow';

  final int maxPoints;
  final List<PdrLocalPoint> path = [PdrLocalPoint.zero];

  /// [path]와 같은 길이·같은 인덱스로 유지되는, 실제 반영된 peak 시각.
  ///
  /// 거부된 peak는 path에 점을 만들지 않으므로 여기에도 남지 않는다. 원점은
  /// 대응 peak가 없어 null이다. 배치 peak(`delta > 1`)는 알고 있는 시각이
  /// `latestPeakMs` 하나뿐이라 같은 값을 delta번 넣어 인덱스를 맞춘다.
  final List<int?> acceptedPeakTimesMs = [null];

  PdrLocalPoint position = PdrLocalPoint.zero;
  int steps = 0;
  int acceptedPeaks = 0;
  int acknowledgedSteps = 0;
  int rejectedPeaks = 0;
  int? lastStepAtMs;
  String lastRejectReason = 'none';
  double distanceM = 0;
  final Map<String, int> rejectReasons = {
    baseline: 0,
    tooDense: 0,
    tooSparse: 0,
    cadenceMismatch: 0,
    stepLeadCap: 0,
    distanceLeadCap: 0,
    notTracking: 0,
    noHeading: 0,
    missingTimestamp: 0,
    batchedPeaksCapped: 0,
    leadDeferred: 0,
    deferOverflow: 0,
  };

  int? _lastPeakCount;
  int? _lastAcceptedPeakMs;
  int? _lastGatePeakMs;

  /// 캡 때문에 아직 경로에 반영하지 못한 걸음의 peak 시각(오래된 것부터).
  final List<int> _deferredPeakTimesMs = [];

  /// 보류 중인 걸음 수(진단용).
  int get deferredPeaks => _deferredPeakTimesMs.length;

  bool applyRealtimePeaks(
    AccelPeakEvent? signal, {
    required bool tracking,
    required bool hasHeading,
    required double effectiveStrideMeters,
    required double fallbackStrideMeters,
    required int confirmedSteps,
    required double confirmedDistanceM,
    int? confirmedThroughMs,
    required double? pedometerCadenceHz,
    required HeadingSample? Function(int ms) headingAt,
    required double fallbackHeadingDeg,
  }) {
    if (signal == null) {
      return false;
    }
    final count = signal.count;
    final peakMs = signal.latestPeakMs;

    final previousCount = _lastPeakCount;
    if (previousCount == null || count < previousCount) {
      _lastPeakCount = count;
      _resyncGate(peakMs);
      _recordReject(reason: baseline, deltaPeaks: 0, counted: false);
      return false;
    }

    final delta = count - previousCount;
    _lastPeakCount = count;
    if (delta <= 0) {
      return false;
    }

    if (peakMs == null) {
      _recordReject(reason: missingTimestamp, deltaPeaks: delta);
      return false;
    }
    if (!tracking || !hasHeading) {
      final reason = tracking ? noHeading : notTracking;
      _resyncGate(peakMs);
      // 추적이 꺼졌거나 방향을 모르는 구간의 걸음은 어느 방향으로 놓을지
      // 알 수 없다. 보류해 뒀다가 나중에 푸는 것이 더 나쁘므로 버린다.
      _deferredPeakTimesMs.clear();
      _recordReject(reason: reason, deltaPeaks: delta);
      return false;
    }

    if (delta > 1) {
      _recordReject(
        reason: batchedPeaksCapped,
        deltaPeaks: delta - 1,
        counted: false,
      );
    }
    final intervalCheck = _checkInterval(peakMs, pedometerCadenceHz);
    if (intervalCheck.reason != null) {
      _recordReject(
        reason: intervalCheck.reason!,
        deltaPeaks: 1,
        counted: false,
      );
      if (intervalCheck.resync) {
        _resyncGate(peakMs);
      }
    }

    final stride = _resolveStepDistance(
      effectiveStrideMeters: effectiveStrideMeters,
      fallbackStrideMeters: fallbackStrideMeters,
    );

    // 새 peak를 보류 큐 뒤에 붙이고, 캡이 허용하는 만큼 앞에서부터 소비한다.
    // 캡에 걸린 걸음을 그 자리에서 버리던 예전 구조는 "확정이 늦어서 못 넣은
    // 걸음"과 "센서 과검출이라 넣으면 안 되는 걸음"을 구분하지 못했다.
    _deferredPeakTimesMs.addAll(List<int>.filled(delta, peakMs));
    if (_deferredPeakTimesMs.length > maxDeferredPeaks) {
      final drop = _deferredPeakTimesMs.length - maxDeferredPeaks;
      _deferredPeakTimesMs.removeRange(0, drop);
      _recordReject(reason: deferOverflow, deltaPeaks: drop);
    }

    var applied = 0;
    String? blockedBy;
    // 한 센서 이벤트에서 새로 관측된 peak 수보다 많이 풀지 않는다. 확정 배치가
    // 도착해 cap이 갑자기 열려도 오래 묵은 큐 전체가 한 프레임에 쏟아져 마커가
    // 순간이동하지 않게 하는 화면 연속성 경계다.
    while (_deferredPeakTimesMs.isNotEmpty && applied < delta) {
      blockedBy = _leadCapReason(
        stride.meters,
        confirmedSteps: confirmedSteps,
        confirmedDistanceM: confirmedDistanceM,
        confirmedThroughMs: confirmedThroughMs,
        nowMs: peakMs,
      );
      if (blockedBy != null) break;
      final stepMs = _deferredPeakTimesMs.removeAt(0);
      // 보류됐던 걸음은 자기 시각의 heading으로 놓는다. 배치로 몰려 들어온
      // 걸음을 수신 시점 heading 하나로 그리면 회전 구간이 통째로 눕는다.
      final headingDeg = headingAt(stepMs)?.walkDeg ?? fallbackHeadingDeg;
      final headingRad = headingDeg * math.pi / 180;
      position += PdrLocalPoint(
        math.sin(headingRad) * stride.meters,
        math.cos(headingRad) * stride.meters,
      );
      path.add(position);
      acceptedPeakTimesMs.add(stepMs);
      steps += 1;
      acceptedPeaks += 1;
      distanceM += stride.meters;
      applied += 1;
    }
    _trim();

    if (_deferredPeakTimesMs.isNotEmpty) {
      // 버린 게 아니라 들고 있는 것이므로 rejectedPeaks에는 세지 않는다.
      _recordReject(
        reason: leadDeferred,
        deltaPeaks: _deferredPeakTimesMs.length,
        counted: false,
      );
      // 어느 캡에 걸렸는지는 튜닝에 필요하다.
      if (blockedBy != null) {
        rejectReasons[blockedBy] = (rejectReasons[blockedBy] ?? 0) + 1;
      }
    }
    _resyncGate(peakMs);
    if (applied == 0) {
      return false;
    }
    lastStepAtMs = peakMs;
    _lastAcceptedPeakMs = peakMs;
    lastRejectReason = _deferredPeakTimesMs.isEmpty
        ? 'none'
        : _label(leadDeferred);
    return true;
  }

  /// 초록에 실제 적용된 걸음 수만큼만 preview를 대응시킨다.
  ///
  /// `spanEndMs` 안의 accel peak를 전부 지우면 CMPedometer 1걸음/accel 2 peak인
  /// 첫 배치에서 주황 한 걸음이 초록에 들어가지도 않았는데 사라진다. 여기서는
  /// 오래된 accepted preview부터 최대 [appliedSteps]개만 소비하고, 남은 수만큼만
  /// deferred queue에서 버린다. 시간창은 미래 peak를 소비하지 않는 상한일 뿐이다.
  ({int accepted, int deferred}) acknowledgeConfirmedBatch({
    required int appliedSteps,
    required int? spanEndMs,
  }) {
    if (appliedSteps <= 0) return (accepted: 0, deferred: 0);
    var eligibleAccepted = 0;
    final firstPathStep = steps - (path.length - 1);
    for (var index = 0; index < acceptedPeakTimesMs.length; index++) {
      final stepId = firstPathStep + index;
      if (stepId <= acknowledgedSteps || stepId <= 0) continue;
      final peakMs = acceptedPeakTimesMs[index];
      if (spanEndMs != null && peakMs != null && peakMs > spanEndMs) break;
      eligibleAccepted += 1;
    }
    final accepted = math.min(appliedSteps, eligibleAccepted);
    acknowledgedSteps += accepted;

    var remaining = appliedSteps - accepted;
    var deferred = 0;
    while (remaining > 0 && _deferredPeakTimesMs.isNotEmpty) {
      final peakMs = _deferredPeakTimesMs.first;
      if (spanEndMs != null && peakMs > spanEndMs) break;
      _deferredPeakTimesMs.removeAt(0);
      remaining -= 1;
      deferred += 1;
    }
    return (accepted: accepted, deferred: deferred);
  }

  /// 다음 초록 걸음과 1:1로 대응할, 아직 소비되지 않은 preview peak 시각.
  ///
  /// 초록 경로도 이 시각의 heading을 쓰면 배치 끝 시각 하나로 코너가 눌리지
  /// 않는다. 미래 peak는 반환하지 않고, 필요한 수를 다 못 채우면 호출자가
  /// 기존 pedometer 시간 복원으로 폴백한다.
  List<int> pendingAcceptedPeakTimes({
    required int maxCount,
    required int? throughMs,
  }) {
    if (maxCount <= 0) return const [];
    final output = <int>[];
    final firstPathStep = steps - (path.length - 1);
    for (var index = 0; index < acceptedPeakTimesMs.length; index++) {
      final stepId = firstPathStep + index;
      if (stepId <= acknowledgedSteps || stepId <= 0) continue;
      final peakMs = acceptedPeakTimesMs[index];
      if (peakMs == null) continue;
      if (throughMs != null && peakMs > throughMs) break;
      output.add(peakMs);
      if (output.length == maxCount) break;
    }
    return output;
  }

  void reset({bool preserveNativePeakBaseline = false}) {
    final nativePeakBaseline = _lastPeakCount;
    path
      ..clear()
      ..add(PdrLocalPoint.zero);
    acceptedPeakTimesMs
      ..clear()
      ..add(null);
    position = PdrLocalPoint.zero;
    steps = 0;
    acceptedPeaks = 0;
    acknowledgedSteps = 0;
    rejectedPeaks = 0;
    lastStepAtMs = null;
    lastRejectReason = 'none';
    distanceM = 0;
    for (final key in rejectReasons.keys.toList()) {
      rejectReasons[key] = 0;
    }
    // 위치 재지정은 센서를 재시작하는 동작이 아니다. 네이티브 누적 peak count를
    // 기억해야 다음 count가 이전 전체 누적이 아니라 정확히 한 걸음 delta가 된다.
    _lastPeakCount = preserveNativePeakBaseline ? nativePeakBaseline : null;
    _lastAcceptedPeakMs = null;
    _lastGatePeakMs = null;
    _deferredPeakTimesMs.clear();
  }

  void _trim() {
    if (path.length > maxPoints) {
      final drop = path.length - maxPoints;
      path.removeRange(0, drop);
      // 인덱스 정렬이 깨지면 확정 소비가 엉뚱한 걸음을 지우므로 반드시 함께 자른다.
      acceptedPeakTimesMs.removeRange(0, drop);
    }
  }

  ({String? reason, bool resync, int? intervalMs, double? expectedIntervalMs})
  _checkInterval(int peakMs, double? pedometerCadenceHz) {
    final previous = _lastGatePeakMs ?? _lastAcceptedPeakMs;
    if (previous == null) {
      return (
        reason: null,
        resync: false,
        intervalMs: null,
        expectedIntervalMs: null,
      );
    }
    final intervalMs = peakMs - previous;
    if (intervalMs < minPeakIntervalMs) {
      return (
        reason: tooDense,
        resync: false,
        intervalMs: intervalMs,
        expectedIntervalMs: null,
      );
    }
    if (intervalMs > maxPeakIntervalMs) {
      return (
        reason: tooSparse,
        resync: true,
        intervalMs: intervalMs,
        expectedIntervalMs: null,
      );
    }

    if (pedometerCadenceHz != null && pedometerCadenceHz > 0.2) {
      final expectedMs = 1000.0 / pedometerCadenceHz;
      // CMPedometer cadence는 배치/평균값이라 realtime accel peak와 정확히 같은
      // cadence를 보장하지 않는다. 특히 peak detector가 한쪽 발/강한 peak만 잡으면
      // 실제 interval이 Apple cadence의 2배 근처로 보일 수 있다.
      if (intervalMs < expectedMs * 0.45 || intervalMs > expectedMs * 2.60) {
        return (
          reason: cadenceMismatch,
          resync: true,
          intervalMs: intervalMs,
          expectedIntervalMs: expectedMs,
        );
      }
    }
    return (
      reason: null,
      resync: false,
      intervalMs: intervalMs,
      expectedIntervalMs: pedometerCadenceHz != null && pedometerCadenceHz > 0.2
          ? 1000.0 / pedometerCadenceHz
          : null,
    );
  }

  String? _leadCapReason(
    double stepDistance, {
    required int confirmedSteps,
    required double confirmedDistanceM,
    int? confirmedThroughMs,
    int? nowMs,
  }) {
    if (confirmedThroughMs != null) {
      // 확정이 아직 "정상적인 지연" 범위면 캡을 재지 않는다. 배치가 늦다고
      // 마커를 세우는 것이 이 캡의 목적이 아니다.
      if (nowMs != null && nowMs - confirmedThroughMs <= confirmedLagGraceMs) {
        return null;
      }
      final pendingSteps = math.max(0, steps - acknowledgedSteps);
      var pendingDistanceM = 0.0;
      final firstPathStep = steps - (path.length - 1);
      for (var index = 1; index < path.length; index++) {
        final stepId = firstPathStep + index;
        if (stepId <= acknowledgedSteps) continue;
        pendingDistanceM += (path[index] - path[index - 1]).distance;
      }
      if (pendingSteps + 1 > maxStepLead) return stepLeadCap;
      if (pendingDistanceM + stepDistance > maxDistanceLeadMeters) {
        return distanceLeadCap;
      }
      return null;
    }
    // 첫 CMPedometer batch는 실제 기기에서 7~10초 늦게 올 수 있다.
    // confirmed가 아직 0이면 일반 lead cap보다 넓게 허용해서 preview가 초반에
    // 12 step에서 멈추지 않게 한다. confirmed가 한 번이라도 들어오면 기존 cap으로
    // 돌아가서 raw-ish 경로가 무한히 앞서가는 것을 막는다.
    final stepLead = confirmedSteps == 0 ? maxInitialStepLead : maxStepLead;
    final distanceLead = confirmedDistanceM <= 0
        ? maxInitialDistanceLeadMeters
        : maxDistanceLeadMeters;
    if (steps + 1 > confirmedSteps + stepLead) {
      return stepLeadCap;
    }
    if (distanceM + stepDistance > confirmedDistanceM + distanceLead) {
      return distanceLeadCap;
    }
    return null;
  }

  ({double meters, String source}) _resolveStepDistance({
    required double effectiveStrideMeters,
    required double fallbackStrideMeters,
  }) {
    if (StrideEstimator.valid(effectiveStrideMeters)) {
      return (meters: effectiveStrideMeters, source: 'effective');
    }
    if (StrideEstimator.valid(fallbackStrideMeters)) {
      return (meters: fallbackStrideMeters, source: 'fallback');
    }
    return (meters: 0.70, source: 'default');
  }

  void _resyncGate(int? peakMs) {
    if (peakMs != null) {
      _lastGatePeakMs = peakMs;
    }
  }

  void _recordReject({
    required String reason,
    required int deltaPeaks,
    bool counted = true,
  }) {
    final count = math.max(0, deltaPeaks);
    if (counted) {
      rejectedPeaks += count;
    }
    rejectReasons[reason] = (rejectReasons[reason] ?? 0) + count;
    lastRejectReason = _label(reason);
  }

  String _label(String reason) {
    switch (reason) {
      case tooDense:
        return 'too dense';
      case tooSparse:
        return 'too sparse';
      case cadenceMismatch:
        return 'cadence mismatch';
      case stepLeadCap:
        return 'step lead cap';
      case distanceLeadCap:
        return 'distance lead cap';
      case notTracking:
        return 'not tracking';
      case noHeading:
        return 'no heading';
      case missingTimestamp:
        return 'missing timestamp';
      case batchedPeaksCapped:
        return 'batched peaks capped';
      case leadDeferred:
        return 'lead deferred';
      case deferOverflow:
        return 'defer overflow';
      case baseline:
        return 'baseline';
      default:
        return reason;
    }
  }
}
