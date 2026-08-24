import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_pdr_core/indoor_pdr_core.dart';
import 'package:navigation_client/features/indoor_navigation/contract/calibration_state.dart';
import 'package:navigation_client/features/indoor_navigation/contract/pdr_anchor.dart';
import 'package:navigation_client/features/indoor_navigation/debug/pdr_debug_session_recorder.dart';

/// 품질은 이 검증에 안 쓰인다. 스냅샷을 만들려면 필요할 뿐이라 최소값 한 벌.
const _quality = PdrQuality(
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
    cadenceHz: 1.6,
    pitchDeg: 0,
    rollDeg: 0,
    headingReferenceIsMagneticNorth: true,
    peakRejectHistogram: {},
    fusedHeadingDeg: 90,
    walkOffsetDeg: 0,
    walkOffsetActive: false,
    deviceHeadingDeg: 90,
    gyroHeadingDeg: 90,
    walkDirDeg: 90,
    walkDirConfidence: 1,
    headingConverged: true,
    headingSpreadDeg: 1,
  ),
);

PdrSnapshot _walkedEast(int steps) {
  final path = [for (var i = 0; i <= steps; i += 1) PdrLocalPoint(i * 1.0, 0)];
  return PdrSnapshot(
    position: path.last,
    path: path,
    steps: steps,
    distanceM: steps * 1.0,
    orientationHeadingDeg: 90,
    walkingHeadingDeg: 90,
    hasHeading: true,
    preview: PdrPreview(
      position: path.last,
      path: path,
      steps: steps,
      distanceM: steps * 1.0,
      acceptedPeakTimesMs: List<int?>.filled(path.length, null),
    ),
    quality: _quality,
  );
}

CalibrationStatus _anchoredAt(String floorId) => CalibrationStatus(
  phase: CalibrationPhase.calibrated,
  headingReference: HeadingReference.magneticNorth,
  requiresManualRotationCalibration: false,
  anchor: PdrAnchor(
    floorId: floorId,
    anchorLocalM: PdrLocalPoint.zero,
    rotationDeg: 0,
    headingReference: HeadingReference.magneticNorth,
    requiresManualRotationCalibration: false,
    source: AnchorSource.userPin,
    confidence: 1,
  ),
);

List<Object?> _pathsByFloor(Map<String, Object?> json) =>
    json['paths_by_floor']! as List<Object?>;

Map<String, Object?> _floorEntry(Map<String, Object?> json, String floorId) =>
    _pathsByFloor(json)
        .cast<Map<String, Object?>>()
        .firstWhere((entry) => entry['floor_id'] == floorId);

void main() {
  test('층이 바뀌어도 이전 층 궤적이 남는다', () {
    final recorder = PdrDebugSessionRecorder(
      startedAt: DateTime.utc(2026, 7, 18, 9),
    );
    recorder.recordCalibration(_anchoredAt('1F'));
    recorder.recordSnapshot(_walkedEast(4), at: DateTime.utc(2026, 7, 18, 9, 1));
    recorder.recordCalibration(_anchoredAt('B2'));
    recorder.recordSnapshot(_walkedEast(2), at: DateTime.utc(2026, 7, 18, 9, 2));

    final json = recorder.buildJson(
      buildingId: 'thehyundai-seoul',
      selectedFloor: 'B2',
      mapCalibrationVersion: 'v1',
      graph: null,
      device: const {'device_name': 'Test device'},
      exportedAt: DateTime.utc(2026, 7, 18, 9, 3),
    );

    expect(_pathsByFloor(json), hasLength(2));
    expect(
      _floorEntry(json, '1F')['floor_local_m_before_matching'],
      hasLength(5),
    );
    expect(
      _floorEntry(json, 'B2')['floor_local_m_before_matching'],
      hasLength(3),
    );
  });

  test('앵커가 없으면 층별 궤적도 없다', () {
    final recorder = PdrDebugSessionRecorder(
      startedAt: DateTime.utc(2026, 7, 18, 9),
    );
    recorder.recordSnapshot(_walkedEast(3), at: DateTime.utc(2026, 7, 18, 9, 1));

    final json = recorder.buildJson(
      buildingId: 'thehyundai-seoul',
      selectedFloor: '1F',
      mapCalibrationVersion: 'v1',
      graph: null,
      device: const {},
      exportedAt: DateTime.utc(2026, 7, 18, 9, 2),
    );
    expect(_pathsByFloor(json), isEmpty);
  });
}
