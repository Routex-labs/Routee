import 'dart:math' as math;

import '../domain/heading_sample.dart';
import '../domain/pdr_local_point.dart';

/// confirmed step을 green corrected path와 blue device-heading path에 누적한다.
///
/// CMPedometer batch 안의 step 시각 재구성도 여기서 처리한다.
///
/// 연구 앱 `path_accumulator.dart`에서 옮겼다. `Offset`→`PdrLocalPoint`로 바꾸고,
/// export 전용 `confirmedSteps` 맵/pathPoints 메서드는 제거했다(기하 계산은 보존).
class PathAccumulator {
  PathAccumulator({this.maxPoints = 800});

  final int maxPoints;
  final List<PdrLocalPoint> corrected = [PdrLocalPoint.zero];
  final List<PdrLocalPoint> legacy = [PdrLocalPoint.zero];
  PdrLocalPoint correctedPosition = PdrLocalPoint.zero;
  PdrLocalPoint legacyPosition = PdrLocalPoint.zero;

  double get divergenceMeters => (correctedPosition - legacyPosition).distance;

  void add({
    required double walkDeg,
    required double fusedDeg,
    required double distanceMeters,
  }) {
    final walkRad = walkDeg * math.pi / 180;
    correctedPosition += PdrLocalPoint(
      math.sin(walkRad) * distanceMeters,
      math.cos(walkRad) * distanceMeters,
    );
    final fusedRad = fusedDeg * math.pi / 180;
    legacyPosition += PdrLocalPoint(
      math.sin(fusedRad) * distanceMeters,
      math.cos(fusedRad) * distanceMeters,
    );
    corrected.add(correctedPosition);
    legacy.add(legacyPosition);
    trim();
  }

  /// batch 안의 [count] step을 각 step 시각의 heading으로 배치하며 누적한다.
  /// 반영한 step 수를 반환한다.
  int applyPedometerBatch({
    required int count,
    required double stepDistanceMeters,
    required double currentWalkDeg,
    required double currentFusedDeg,
    required HeadingSample? Function(int ms) headingAt,
    int? spanStartMs,
    int? spanEndMs,
    List<double>? peakTimes,
    List<int>? exactStepTimesMs,
  }) {
    List<double>? peaksInSpan;
    if (peakTimes != null && spanStartMs != null && spanEndMs != null) {
      peaksInSpan =
          peakTimes.where((t) => t > spanStartMs && t <= spanEndMs).toList()
            ..sort();
      if (peaksInSpan.length < 2) {
        peaksInSpan = null;
      }
    }

    for (var i = 1; i <= count; i += 1) {
      var walkDeg = currentWalkDeg;
      var fusedDeg = currentFusedDeg;
      final stepTiming = _stepTiming(
        index: i,
        count: count,
        exactStepTimesMs: exactStepTimesMs,
        spanStartMs: spanStartMs,
        spanEndMs: spanEndMs,
        peaksInSpan: peaksInSpan,
      );
      if (stepTiming != null) {
        final sample = headingAt(stepTiming);
        if (sample != null) {
          walkDeg = sample.walkDeg;
          fusedDeg = sample.fusedDeg;
        }
      }
      add(
        walkDeg: walkDeg,
        fusedDeg: fusedDeg,
        distanceMeters: stepDistanceMeters,
      );
    }
    return count;
  }

  void reset() {
    corrected
      ..clear()
      ..add(PdrLocalPoint.zero);
    legacy
      ..clear()
      ..add(PdrLocalPoint.zero);
    correctedPosition = PdrLocalPoint.zero;
    legacyPosition = PdrLocalPoint.zero;
  }

  void trim() {
    if (corrected.length > maxPoints) {
      corrected.removeRange(0, corrected.length - maxPoints);
    }
    if (legacy.length > maxPoints) {
      legacy.removeRange(0, legacy.length - maxPoints);
    }
  }

  static int? _stepTiming({
    required int index,
    required int count,
    required List<int>? exactStepTimesMs,
    required int? spanStartMs,
    required int? spanEndMs,
    required List<double>? peaksInSpan,
  }) {
    if (exactStepTimesMs != null && exactStepTimesMs.length == count) {
      return exactStepTimesMs[index - 1];
    }
    if (peaksInSpan != null) {
      // count개의 step을 peak 시각들 사이에 선형 보간해 배치한다.
      // round()로 최근접 peak에 스냅하면 count가 peak 수보다 많을 때 여러 step이
      // 같은 시각에 뭉쳐(turn 구간에서 heading이 계단처럼 튐) 궤적이 꺾인다.
      // 보간하면 단조·분산 배치가 되어 heading 샘플링이 매끄러워진다.
      final pos =
          (peaksInSpan.length - 1) * (index - 1) / math.max(1, count - 1);
      final lo = pos.floor().clamp(0, peaksInSpan.length - 1);
      final hi = pos.ceil().clamp(0, peaksInSpan.length - 1);
      final ms =
          peaksInSpan[lo] + (pos - lo) * (peaksInSpan[hi] - peaksInSpan[lo]);
      return ms.round();
    }
    if (spanStartMs != null && spanEndMs != null && spanEndMs > spanStartMs) {
      return spanStartMs + ((spanEndMs - spanStartMs) * index) ~/ count;
    }
    return null;
  }
}
