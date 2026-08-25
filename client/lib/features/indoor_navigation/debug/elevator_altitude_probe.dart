/// 건물의 **층별 고도표**를 실측으로 채우는 도구.
///
/// 왜 시간이 아니라 고도인지, 왜 상수 하나로는 안 되는지, 어떻게 재는지는
/// `docs/client/elevator-altitude-probe.md`가 단일 출처다.
library;

import 'dart:math' as math;

import '../application/escalator_detector_config.dart';
import '../contract/altitude_sample.dart';

/// 사용자가 "지금 이 층에 서 있다"고 찍은 한 점.
class ElevatorAltitudeMark {
  const ElevatorAltitudeMark({
    required this.floorLabel,
    required this.atMs,
    required this.elapsedMs,
    required this.pressureHpa,
    required this.rawAltitudeM,
    required this.smoothedAltitudeM,
    required this.verticalSpeedMps,
    required this.settled,
  });

  final String floorLabel;

  /// 센서 시각(unix ms). 드리프트를 시간으로 회귀할 때 이 값을 쓴다.
  final int atMs;

  /// 측정 시작부터의 경과(ms). 화면에 적는 값이다.
  final int elapsedMs;

  final double pressureHpa;

  /// 그 순간의 원시 기압고도.
  final double rawAltitudeM;

  /// 중앙값 평활을 거친 고도. 판정기가 보는 것과 같은 창을 쓴다.
  final double smoothedAltitudeM;

  final double verticalSpeedMps;

  /// 찍은 순간 실제로 멈춰 있었는지. false로 찍힌 점은 사후 분석에서 버린다 —
  /// 움직이는 중에 찍은 값은 그 층의 고도가 아니다.
  final bool settled;

  Map<String, Object?> toJson() => {
    'floor': floorLabel,
    'at_ms': atMs,
    'elapsed_ms': elapsedMs,
    'pressure_hpa': pressureHpa,
    'raw_altitude_m': rawAltitudeM,
    'smoothed_altitude_m': smoothedAltitudeM,
    'vertical_speed_mps': verticalSpeedMps,
    'settled': settled,
  };
}

/// 층별 고도표를 모으는 세션. 화면은 `debug_mode/elevator_altitude_sheet.dart`다.
///
/// **표를 여기서 계산하지 않는다.** 마크와 원시 샘플만 들고, 층별 평균이나 인접
/// 층 Δ는 읽는 쪽이 [floorSummary]로 만든다 — 드리프트 보정 방식이 아직 안 정해져
/// 있어, 지금 고른 방식을 저장값에 굳혀 두면 나중에 다시 재야 한다.
class ElevatorAltitudeProbe {
  ElevatorAltitudeProbe({EscalatorDetectorConfig? config})
    : _config = config ?? const EscalatorDetectorConfig();

  final EscalatorDetectorConfig _config;

  /// 원시 샘플 상한. 5Hz Android 기준 약 66분치다. 넘으면 앞에서부터 버리되
  /// 마크는 그대로 둔다 — 표의 근거는 마크이고 샘플은 프로파일 참고용이다.
  static const _maxSamples = 20000;

  final List<AltitudeSample> _samples = [];
  final List<ElevatorAltitudeMark> _marks = [];

  int? _startedAtMs;
  bool _recording = false;

  bool get isRecording => _recording;
  List<ElevatorAltitudeMark> get marks => List.unmodifiable(_marks);
  int get sampleCount => _samples.length;
  int? get startedAtMs => _startedAtMs;

  /// 마지막 샘플의 원시 값들. 아직 하나도 안 왔으면 null.
  AltitudeSample? get latest => _samples.isEmpty ? null : _samples.last;

  void start() {
    if (_recording) return;
    _recording = true;
    _startedAtMs ??= DateTime.now().millisecondsSinceEpoch;
  }

  void stop() => _recording = false;

  /// 세션을 통째로 비운다. 새 건물에서 다시 잴 때 쓴다.
  void reset() {
    _samples.clear();
    _marks.clear();
    _startedAtMs = null;
    _recording = false;
  }

  void onSample(AltitudeSample sample) {
    if (!_recording) return;
    _startedAtMs ??= sample.timestampMs;
    _samples.add(sample);
    if (_samples.length > _maxSamples) {
      _samples.removeRange(0, _samples.length - _maxSamples);
    }
  }

  int get elapsedMs {
    final started = _startedAtMs;
    final last = _samples.isEmpty ? null : _samples.last.timestampMs;
    if (started == null || last == null) return 0;
    return math.max(0, last - started);
  }

  /// 판정기와 **같은 창**의 중앙값. 화면에 뜨는 값이 판정기가 보는 값과 다르면
  /// 현장에서 임계값을 맞출 수 없다.
  double? get smoothedAltitudeM {
    final window = _windowSamples(_config.smoothingWindowMs);
    if (window.isEmpty) return null;
    final values = [for (final sample in window) sample.altitudeM]..sort();
    final mid = values.length ~/ 2;
    return values.length.isOdd
        ? values[mid]
        : (values[mid - 1] + values[mid]) / 2;
  }

  /// 수직 속도(m/s). 밑변은 [EscalatorDetectorConfig.fastSlopeBaseMs]다 — 직전
  /// 샘플과 비교하면 Android 180ms 밑변에서 진짜 변화가 센서 분해능보다 작아
  /// 0으로 읽힌다.
  double? get verticalSpeedMps {
    if (_samples.length < 2) return null;
    final last = _samples.last;
    final baseMs = _config.fastSlopeBaseMs;
    AltitudeSample? base;
    for (var i = _samples.length - 2; i >= 0; i--) {
      base = _samples[i];
      if (last.timestampMs - base.timestampMs >= baseMs) break;
    }
    if (base == null) return null;
    final dtMs = last.timestampMs - base.timestampMs;
    if (dtMs <= 0) return null;
    return (last.altitudeM - base.altitudeM) / (dtMs / 1000.0);
  }

  /// 지금 멈춰 있는가. 판정기가 하차로 보는 속도 문턱과 같은 값을 쓴다.
  bool get isSettled {
    final speed = verticalSpeedMps;
    return speed != null && speed.abs() <= _config.fastExitSlopeMps;
  }

  /// 지금 값을 이 층의 점으로 찍는다. 샘플이 아직 없으면 null.
  ElevatorAltitudeMark? mark(String floorLabel) {
    final last = _samples.isEmpty ? null : _samples.last;
    final smoothed = smoothedAltitudeM;
    if (last == null || smoothed == null) return null;
    final mark = ElevatorAltitudeMark(
      floorLabel: floorLabel,
      atMs: last.timestampMs,
      elapsedMs: elapsedMs,
      pressureHpa: last.pressureHpa,
      rawAltitudeM: last.altitudeM,
      smoothedAltitudeM: smoothed,
      verticalSpeedMps: verticalSpeedMps ?? 0,
      settled: isSettled,
    );
    _marks.add(mark);
    return mark;
  }

  void removeMarkAt(int index) {
    if (index < 0 || index >= _marks.length) return;
    _marks.removeAt(index);
  }

  /// 층별 요약 — 찍은 횟수, 평균 고도, **같은 층 재방문 사이의 벌어짐**.
  ///
  /// 마지막 값이 곧 드리프트의 하한이다. 같은 층인데 두 번 찍은 값이 3m 벌어져
  /// 있으면 그 세션의 표는 층 하나만큼 못 믿는다는 뜻이다. 움직이는 중에 찍힌
  /// 점([ElevatorAltitudeMark.settled]가 false)은 빼고 센다.
  List<ElevatorFloorSummary> get floorSummary {
    final byFloor = <String, List<ElevatorAltitudeMark>>{};
    for (final mark in _marks) {
      if (!mark.settled) continue;
      byFloor.putIfAbsent(mark.floorLabel, () => []).add(mark);
    }
    final rows = <ElevatorFloorSummary>[];
    for (final entry in byFloor.entries) {
      final values = [for (final m in entry.value) m.smoothedAltitudeM];
      final mean = values.reduce((a, b) => a + b) / values.length;
      final spread = values.length < 2
          ? 0.0
          : values.reduce(math.max) - values.reduce(math.min);
      rows.add(
        ElevatorFloorSummary(
          floorLabel: entry.key,
          count: values.length,
          meanAltitudeM: mean,
          spreadM: spread,
        ),
      );
    }
    // 고도 순으로 세운다 — 층 이름은 B2·1F처럼 정렬 규칙이 없고, 표를 읽는
    // 목적이 "인접 층 사이가 몇 미터인가"라 높이 순이 곧 읽는 순서다.
    rows.sort((a, b) => a.meanAltitudeM.compareTo(b.meanAltitudeM));
    return rows;
  }

  /// 내보낼 세션. 원시 샘플을 통째로 싣는다 — 이 도구의 목적이 판단이 아니라
  /// **자료 확보**라, 지금 고른 평활·문턱이 나중에 틀린 것으로 밝혀져도 다시
  /// 재지 않아도 되게 한다.
  Map<String, Object?> buildJson({
    required String? buildingId,
    required AltimeterStatus altimeter,
    Map<String, Object?>? device,
  }) {
    final started = _startedAtMs;
    return {
      'schema': 'elevator_altitude_probe_v1',
      'started_at_utc': started == null
          ? ''
          : DateTime.fromMillisecondsSinceEpoch(
              started,
              isUtc: true,
            ).toIso8601String(),
      'building_id': buildingId,
      'altimeter': {
        'available': altimeter.available,
        'source': altimeter.source,
        'sensor_name': altimeter.sensorName,
      },
      'device': ?device,
      'marks': [for (final mark in _marks) mark.toJson()],
      'samples': [
        for (final sample in _samples)
          {
            't': sample.timestampMs,
            'hpa': sample.pressureHpa,
            'alt_m': sample.altitudeM,
            if (sample.relativeAltitudeM != null)
              'rel_m': sample.relativeAltitudeM,
          },
      ],
    };
  }

  List<AltitudeSample> _windowSamples(int windowMs) {
    if (_samples.isEmpty) return const [];
    final lastMs = _samples.last.timestampMs;
    final window = <AltitudeSample>[];
    for (var i = _samples.length - 1; i >= 0; i--) {
      final sample = _samples[i];
      if (lastMs - sample.timestampMs > windowMs &&
          window.length >= _config.minSmoothingSamples) {
        break;
      }
      window.add(sample);
    }
    return window;
  }
}

/// 한 층에 대한 요약 한 줄.
class ElevatorFloorSummary {
  const ElevatorFloorSummary({
    required this.floorLabel,
    required this.count,
    required this.meanAltitudeM,
    required this.spreadM,
  });

  final String floorLabel;
  final int count;
  final double meanAltitudeM;

  /// 같은 층을 여러 번 찍었을 때 값이 벌어진 폭(m). 드리프트의 하한이다.
  final double spreadM;
}
