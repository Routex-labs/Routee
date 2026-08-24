import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_pdr_core/indoor_pdr_core.dart';
import 'package:navigation_client/features/indoor_navigation/contract/altitude_sample.dart';
import 'package:navigation_client/features/indoor_navigation/debug/pdr_debug_session_recorder.dart';

/// **15~20분짜리 실측이 중간에서 잘리지 않는다.**
///
/// 예전 상한(품질 900 · tracker 입력 4000 · 경로진행 900 · 기압 3000 · 층 전이
/// 200 · GPS 차이 900)은 초과분을 **앞에서부터** 버렸다. 그러면 B2 매장에서
/// 출발한 구간, 즉 분석하려는 바로 그 앞부분이 파일에서 사라진다.
///
/// 여기서 미는 표본 수는 전부 옛 상한보다 크게 잡았다 — 상한이 되살아나면
/// 반드시 이 테스트가 먼저 깨진다.
PdrSnapshot _snapshot(int steps) => PdrSnapshot(
  position: const PdrLocalPoint(0, 0),
  path: const [PdrLocalPoint(0, 0)],
  steps: steps,
  distanceM: steps * 0.7,
  orientationHeadingDeg: 0,
  walkingHeadingDeg: 0,
  hasHeading: true,
  preview: PdrPreview(
    position: const PdrLocalPoint(0, 0),
    path: const [PdrLocalPoint(0, 0)],
    steps: steps,
    distanceM: steps * 0.7,
  ),
  quality: const PdrQuality(
    state: PdrQualityState.healthy,
    warnings: [],
    features: PdrQualityFeatures(
      greenOrangeDistanceDivergencePct: 0,
      orangeStepRatio: 1,
      orangeOvercountLikely: false,
      pedometerUndercountSuspected: false,
      pedometerFlaggedSpanS: 0,
      headingStable: true,
      headingSource: 'test',
      magneticAccuracy: 'high',
      rotationHeadingAccuracyDeg: 5,
      cadenceHz: 1.5,
      pitchDeg: 0,
      rollDeg: 0,
      headingReferenceIsMagneticNorth: false,
      peakRejectHistogram: {},
      fusedHeadingDeg: 0,
      walkOffsetDeg: 0,
      walkOffsetActive: false,
      deviceHeadingDeg: 0,
      gyroHeadingDeg: 0,
      walkDirDeg: 0,
      walkDirConfidence: 1,
      headingConverged: true,
      headingSpreadDeg: 1,
    ),
  ),
);

void main() {
  test('품질·기압 표본이 옛 상한을 넘어도 앞부분이 남는다', () {
    final start = DateTime.utc(2026, 8, 20, 9);
    final recorder = PdrDebugSessionRecorder(startedAt: start);

    // 1 Hz로 20분 = 1,200건(옛 상한 900).
    for (var i = 0; i < 1200; i++) {
      recorder.recordSnapshot(
        _snapshot(i),
        at: start.add(Duration(seconds: i)),
      );
    }
    // Android 5 Hz로 20분 = 6,000건(옛 상한 3,000).
    for (var i = 0; i < 6000; i++) {
      recorder.recordAltitudeSample(
        AltitudeSample(
          pressureHpa: 1013 + i * 0.0001,
          timestampMs: i * 200,
          source: 'test',
        ),
        at: start.add(Duration(milliseconds: i * 200)),
      );
    }

    final json = recorder.buildJson(
      buildingId: 'b',
      selectedFloor: '1F',
      mapCalibrationVersion: 'v1',
      graph: null,
      device: const {},
      exportedAt: start.add(const Duration(minutes: 20)),
    );

    final quality = json['quality_samples_1hz']! as List<Object?>;
    final altimeter = json['altimeter_samples']! as List<Object?>;
    expect(quality, hasLength(1200));
    expect(altimeter, hasLength(6000));
    // 앞에서부터 버리던 시절에는 첫 샘플이 300번째 걸음이었다.
    expect((quality.first! as Map<String, Object?>)['steps'], 0);
    expect((altimeter.first! as Map<String, Object?>)['timestamp_ms'], 0);
    // 상한이 없으니 언제나 0이다. **키는 남아 있어야 한다** — 분석 도구가 읽는다.
    expect(json['tracker_input_dropped'], 0);
    expect((json['altimeter']! as Map<String, Object?>)['dropped_samples'], 0);
  });

  group('실내→실외→실내 한 세션(v16)', () {
    test('경계는 마지막 값뿐 아니라 시계열로도 남는다', () {
      final start = DateTime.utc(2026, 8, 20, 9);
      final recorder = PdrDebugSessionRecorder(startedAt: start);

      expect(recorder.spansBuildingExit, isFalse);
      recorder.recordBuildingExit(at: start.add(const Duration(minutes: 8)));
      expect(recorder.spansBuildingExit, isTrue);
      recorder.recordSessionBoundary(
        'reEntered',
        at: start.add(const Duration(minutes: 11)),
      );

      final json = recorder.buildJson(
        buildingId: 'b',
        selectedFloor: '1F',
        mapCalibrationVersion: 'v1',
        graph: null,
        device: const {},
        exportedAt: start.add(const Duration(minutes: 20)),
      );

      final boundaries = (json['session_boundaries']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(boundaries.map((b) => b['boundary']), [
        'leftBuilding',
        'reEntered',
      ]);
      // 실외 구간을 자를 수 있어야 한다 — 그게 이 배열의 존재 이유다.
      expect(boundaries.first['at_utc'], '2026-08-20T09:08:00.000Z');
      expect(boundaries.last['at_utc'], '2026-08-20T09:11:00.000Z');
      expect(json['session_boundary'], 'reEntered');
      expect(json['spans_building_exit'], isTrue);
    });

    test('실내 상태의 출처를 남긴다 — 확대와 GPS 판정을 가른다', () {
      final start = DateTime.utc(2026, 8, 20, 9);
      final recorder = PdrDebugSessionRecorder(startedAt: start);

      recorder.recordIndoorStateChange(
        entered: true,
        source: 'cameraZoom',
        floorId: '1F',
        at: start,
      );
      recorder.recordIndoorStateChange(
        entered: false,
        source: 'gps',
        floorId: '1F',
        at: start.add(const Duration(minutes: 8)),
      );

      final changes =
          (recorder.buildJson(
                    buildingId: 'b',
                    selectedFloor: '1F',
                    mapCalibrationVersion: 'v1',
                    graph: null,
                    device: const {},
                  )['indoor_state_changes']!
                  as List<Object?>)
              .cast<Map<String, Object?>>();

      expect(changes.map((c) => c['source']), ['cameraZoom', 'gps']);
      expect(changes.first['entered'], isTrue);
      expect(changes.last['entered'], isFalse);
    });
  });
}
