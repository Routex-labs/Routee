import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_pdr_core/indoor_pdr_core.dart';
import 'package:navigation_client/domain/guidance/route_progress.dart';
import 'package:navigation_client/domain/guidance/route_checkpoint.dart';
import 'package:navigation_client/domain/guidance/route_movement.dart';
import 'package:navigation_client/features/indoor_navigation/application/corridor_position_tracker.dart';
import 'package:navigation_client/features/indoor_navigation/application/escalator_transition_detector.dart';
import 'package:navigation_client/features/indoor_navigation/contract/altitude_sample.dart';
import 'package:navigation_client/features/indoor_navigation/contract/calibration_state.dart';
import 'package:navigation_client/features/indoor_navigation/contract/pdr_anchor.dart';
import 'package:navigation_client/features/indoor_navigation/debug/pdr_debug_session_recorder.dart';
import 'package:navigation_client/models/building/floor_graph.dart';
import 'package:navigation_client/domain/guidance/corridor_tracking.dart';

PdrSnapshot _snapshot({
  required int steps,
  required double distanceM,
  required List<PdrLocalPoint> path,
  PdrAppliedBatch? lastAppliedBatch,
  List<int?>? previewPeakTimesMs,
  int? previewSteps,
}) => PdrSnapshot(
  position: path.last,
  path: path,
  steps: steps,
  distanceM: distanceM,
  orientationHeadingDeg: 80,
  walkingHeadingDeg: 90,
  hasHeading: true,
  lastAppliedBatch: lastAppliedBatch,
  preview: PdrPreview(
    position: path.last,
    path: path,
    steps: previewSteps ?? steps + 1,
    distanceM: distanceM + 0.5,
    acceptedPeakTimesMs:
        previewPeakTimesMs ?? List<int?>.filled(path.length, null),
  ),
  ronin: PdrRoninTrack(
    supported: true,
    modelReady: true,
    position: path.last,
    path: path,
    steps: steps,
    distanceM: distanceM - 0.2,
    effectiveStrideM: 0.65,
    model: 'ronin-tcn-200hz',
    status: 'ready',
    rawStrideM: 0.63,
    speedMps: 1.01,
    speedStdMps: 0.08,
    cadenceHz: 1.6,
  ),
  quality: const PdrQuality(
    state: PdrQualityState.caution,
    warnings: ['headingUnstable'],
    features: PdrQualityFeatures(
      greenOrangeDistanceDivergencePct: 10,
      orangeStepRatio: 1.1,
      orangeOvercountLikely: false,
      pedometerUndercountSuspected: false,
      pedometerFlaggedSpanS: 0,
      headingStable: false,
      headingSource: 'sensor_manager/rotation_vector+gyro_hold',
      magneticAccuracy: 'low',
      rotationHeadingAccuracyDeg: -1,
      cadenceHz: 1.5,
      pitchDeg: 4,
      rollDeg: -2,
      headingReferenceIsMagneticNorth: true,
      peakRejectHistogram: {},
      fusedHeadingDeg: 80,
      walkOffsetDeg: 10,
      walkOffsetActive: true,
      deviceHeadingDeg: 82,
      gyroHeadingDeg: 78,
      walkDirDeg: 88,
      walkDirConfidence: 0.6,
      headingConverged: true,
      headingSpreadDeg: 3.5,
    ),
  ),
);

FloorGraph _graph() => const FloorGraph(
  nodes: [
    GraphNode(id: 'a', type: 'path', xM: 0, yM: 0),
    GraphNode(id: 'b', type: 'path', xM: 10, yM: 0),
  ],
  edges: [
    GraphEdge(
      id: 'ab',
      fromNodeId: 'a',
      toNodeId: 'b',
      lengthM: 10,
      bidirectional: true,
      geometryLocalM: [LocalPoint(0, 0), LocalPoint(10, 0)],
    ),
  ],
);

void main() {
  test('확정 PDR 경로·품질·맵매칭 결과만 JSON으로 내보낸다', () {
    final recorder = PdrDebugSessionRecorder(
      startedAt: DateTime.utc(2026, 7, 18, 9),
    );
    recorder.recordCalibration(
      CalibrationStatus(
        phase: CalibrationPhase.calibrated,
        headingReference: HeadingReference.magneticNorth,
        requiresManualRotationCalibration: false,
        anchor: const PdrAnchor(
          floorId: '1F',
          anchorLocalM: PdrLocalPoint.zero,
          rotationDeg: 0,
          headingReference: HeadingReference.magneticNorth,
          requiresManualRotationCalibration: false,
          source: AnchorSource.userPin,
          confidence: 1,
        ),
      ),
    );
    recorder.recordSnapshot(
      _snapshot(
        steps: 4,
        distanceM: 3.1,
        path: const [PdrLocalPoint(0, 0), PdrLocalPoint(4, 1)],
      ),
      at: DateTime.utc(2026, 7, 18, 9, 0, 2),
    );

    final json = recorder.buildJson(
      buildingId: 'thehyundai-seoul',
      selectedFloor: '1F',
      mapCalibrationVersion: 'thehyundai-seoul-1f-svg-v1',
      graph: _graph(),
      device: const {'device_name': 'Test device'},
      exportedAt: DateTime.utc(2026, 7, 18, 9, 1),
    );

    final summary = json['summary']! as Map<String, Object?>;
    final paths = json['paths']! as Map<String, Object?>;
    final matched = paths['map_matched_floor_local_m']! as List<Object?>;
    final finalMatched = matched.last! as Map<String, double>;

    expect(json['schema_version'], 20);
    expect(
      (json['map_context']! as Map<String, Object?>)['map_calibration_version'],
      'thehyundai-seoul-1f-svg-v1',
    );
    expect(summary['confirmed_steps'], 4);
    expect(summary['confirmed_distance_m'], 3.1);
    expect(summary['orientation_heading_deg'], 80);
    expect(summary['walking_heading_deg'], 90);
    expect(
      (summary['ronin']! as Map<String, Object?>)['distance_m'],
      closeTo(2.9, 1e-9),
    );
    expect(summary['map_matched_path_distance_m'], closeTo(4, 1e-9));
    expect(
      (summary['quality']! as Map<String, Object?>)['magnetic_accuracy'],
      'low',
    );
    expect(finalMatched['east_m'], closeTo(4, 1e-9));
    expect(finalMatched['north_m'], closeTo(0, 1e-9));
    expect((json['quality_samples_1hz']! as List<Object?>), hasLength(1));
    // 길찾기 없이 걸은 세션에는 경로 계측이 없다 — null이어야 "이 파일로는
    // 경로 기준 판단을 할 수 없다"가 분명해진다.
    expect(json['route_context'], isNull);
    expect(json['route_progress_summary'], isNull);
  });

  group('경로 기준 계측(v11)', () {
    test('경로 컨텍스트와 진행률 시계열·요약을 남긴다', () {
      final recorder = PdrDebugSessionRecorder(
        startedAt: DateTime.utc(2026, 7, 18, 9),
      );
      recorder.recordSnapshot(
        _snapshot(
          steps: 4,
          distanceM: 3.1,
          path: const [PdrLocalPoint(0, 0), PdrLocalPoint(4, 1)],
        ),
        at: DateTime.utc(2026, 7, 18, 9, 0, 1),
      );
      recorder.recordRouteContext(
        destinationName: '테스트 매장',
        destinationNodeId: 'c',
        floorId: '1F',
        edgeIds: const ['ab', 'bc'],
        routeDistanceM: 20,
        isMultiFloor: false,
      );
      recorder.recordRouteProgress(
        const RouteProgress(
          traveledM: 4,
          remainingM: 16,
          offsetM: 0.3,
          onRouteEdge: true,
          reacquired: false,
          segmentIndex: 0,
        ),
        at: DateTime.utc(2026, 7, 18, 9, 0, 1),
      );
      // 이탈로 바뀐 순간은 1초 간격을 기다리지 않고 즉시 남아야 한다.
      recorder.recordRouteProgress(
        const RouteProgress(
          traveledM: 6,
          remainingM: 14,
          offsetM: 1.6,
          onRouteEdge: false,
          reacquired: false,
          segmentIndex: 0,
        ),
        at: DateTime.utc(2026, 7, 18, 9, 0, 1, 200),
      );

      final json = recorder.buildJson(
        buildingId: 'thehyundai-seoul',
        selectedFloor: '1F',
        mapCalibrationVersion: 'thehyundai-seoul-1f-svg-v1',
        graph: _graph(),
        device: const {'device_name': 'Test device'},
        exportedAt: DateTime.utc(2026, 7, 18, 9, 1),
      );

      final context = json['route_context']! as Map<String, Object?>;
      expect(context['destination_node_id'], 'c');
      expect(context['edge_ids'], ['ab', 'bc']);

      final samples = json['route_progress_samples']! as List<Object?>;
      expect(samples, hasLength(2));

      final summary = json['route_progress_summary']! as Map<String, Object?>;
      expect(summary['sample_count'], 2);
      expect(summary['on_route_ratio'], closeTo(0.5, 1e-9));
      expect(summary['reacquired_count'], 0);
      expect(summary['max_offset_m'], closeTo(1.6, 1e-9));
      expect(summary['last_remaining_m'], closeTo(14, 1e-9));
    });

    test('상태 변화가 없으면 1초에 한 건으로 줄인다', () {
      final recorder = PdrDebugSessionRecorder(
        startedAt: DateTime.utc(2026, 7, 18, 9),
      );
      for (var index = 0; index < 5; index++) {
        recorder.recordRouteProgress(
          RouteProgress(
            traveledM: index.toDouble(),
            remainingM: 20 - index.toDouble(),
            offsetM: 0.2,
            onRouteEdge: true,
            reacquired: false,
            segmentIndex: 0,
          ),
          at: DateTime.utc(2026, 7, 18, 9, 0, 0, index * 200),
        );
      }

      final json = recorder.buildJson(
        buildingId: 'thehyundai-seoul',
        selectedFloor: '1F',
        mapCalibrationVersion: 'thehyundai-seoul-1f-svg-v1',
        graph: _graph(),
        device: const {'device_name': 'Test device'},
        exportedAt: DateTime.utc(2026, 7, 18, 9, 1),
      );

      expect((json['route_progress_samples']! as List<Object?>), hasLength(1));
    });

    test('재획득이 켜지는 순간도 간격과 무관하게 남긴다', () {
      final recorder = PdrDebugSessionRecorder(
        startedAt: DateTime.utc(2026, 7, 18, 9),
      );
      recorder.recordRouteProgress(
        const RouteProgress(
          traveledM: 10,
          remainingM: 10,
          offsetM: 0.2,
          onRouteEdge: true,
          reacquired: false,
          segmentIndex: 0,
        ),
        at: DateTime.utc(2026, 7, 18, 9, 0, 0),
      );
      recorder.recordRouteProgress(
        const RouteProgress(
          traveledM: 2,
          remainingM: 18,
          offsetM: 0.4,
          onRouteEdge: true,
          reacquired: true,
          segmentIndex: 0,
        ),
        at: DateTime.utc(2026, 7, 18, 9, 0, 0, 100),
      );

      final json = recorder.buildJson(
        buildingId: 'thehyundai-seoul',
        selectedFloor: '1F',
        mapCalibrationVersion: 'thehyundai-seoul-1f-svg-v1',
        graph: _graph(),
        device: const {'device_name': 'Test device'},
        exportedAt: DateTime.utc(2026, 7, 18, 9, 1),
      );

      final summary = json['route_progress_summary']! as Map<String, Object?>;
      expect(summary['sample_count'], 2);
      expect(summary['reacquired_count'], 1);
    });
  });

  test('peak 이동·방향 전이·shadow checkpoint를 한 JSON에서 재생할 수 있다', () {
    final recorder = PdrDebugSessionRecorder();
    const step = RouteStepAdvance(
      peakId: 1000,
      occurredAtMs: 1000,
      signedRouteDistanceM: -0.7,
      relation: RouteStepRelation.reverse,
      crossedRouteWaypointIds: [],
      optimisticEdgeId: 'ab',
      walkingHeadingDeg: 260,
      mapMatchedHeadingDeg: 270,
      orientationHeadingDeg: 270,
      routeHeadingDeg: 90,
      headingErrorDeg: 180,
    );
    recorder.recordRouteStepAdvance(
      step,
      transition: const TravelDirectionTransition(
        from: TravelDirectionState.forward,
        to: TravelDirectionState.reverseCandidate,
        peakId: 1000,
        occurredAtMs: 1000,
        evidencePeakCount: 1,
        evidenceDistanceM: 0.7,
      ),
    );
    recorder.recordCheckpointEvent(
      const RouteCheckpointEvent(
        routeGeneration: 2,
        waypoint: RouteCheckpointWaypoint(
          nodeId: 'b',
          kind: RouteCheckpointKind.weakStraight,
          routeDistanceM: 10,
          incomingEdgeId: 'ab',
          outgoingEdgeId: 'bc',
        ),
        decision: RouteCheckpointDecision.reject,
        reason: 'travelDirectionNotForward',
        peakId: 1000,
        occurredAtMs: 1000,
        waypointDistanceM: 0.4,
      ),
    );

    final json = recorder.buildJson(
      buildingId: 'test',
      selectedFloor: '1F',
      mapCalibrationVersion: 'v1',
      graph: _graph(),
      device: const {},
    );

    expect(json['route_step_advances'], hasLength(1));
    final routeStep = (json['route_step_advances']! as List).single as Map;
    expect(routeStep['optimistic_edge_id'], 'ab');
    expect(routeStep['walking_heading_deg'], 260);
    expect(routeStep['map_matched_heading_deg'], 270);
    expect(json['travel_direction_transitions'], hasLength(1));
    final checkpoint = (json['checkpoint_events']! as List).single as Map;
    expect(checkpoint['decision'], 'reject');
    expect(checkpoint['shadow'], isTrue);
  });

  test('1Hz 샘플에 주황(preview)도 같이 남긴다', () {
    // 초록만 남기면 둘이 언제 벌어졌는지를 파일에서 못 읽는다.
    final recorder = PdrDebugSessionRecorder(
      startedAt: DateTime.utc(2026, 7, 18, 9),
    );
    recorder.recordSnapshot(
      _snapshot(
        steps: 4,
        distanceM: 3.1,
        path: const [PdrLocalPoint(0, 0), PdrLocalPoint(4, 1)],
      ),
      at: DateTime.utc(2026, 7, 18, 9),
    );

    final json = recorder.buildJson(
      buildingId: 'thehyundai-seoul',
      selectedFloor: '1F',
      mapCalibrationVersion: 'v1',
      graph: _graph(),
      device: const {},
    );

    final sample =
        (json['quality_samples_1hz']! as List<Object?>).single!
            as Map<String, Object?>;
    expect(sample['steps'], 4);
    expect(sample['distance_m'], 3.1);
    expect(sample['preview_steps'], 5);
    expect(sample['preview_distance_m'], 3.6);
    expect(sample['ronin'], isA<Map<String, Object?>>());
    expect(
      (sample['ronin']! as Map<String, Object?>)['effective_stride_m'],
      0.65,
    );
    // heading 분해도 매 샘플에 들어간다 — 초반 수렴 구간을 보려면 시계열이어야 한다.
    expect(sample['fused_heading_deg'], 80);
    expect(sample['walk_offset_deg'], 10);
    expect(sample['device_heading_deg'], 82);
    expect(sample['heading_converged'], true);
  });

  group('기압계·층 전이 판정(v12)', () {
    test('기압 원본 시계열과 판정 상태를 남긴다', () {
      final recorder = PdrDebugSessionRecorder(
        startedAt: DateTime.utc(2026, 7, 18, 9),
      );
      recorder.recordAltimeterStatus(
        const AltimeterStatus(
          available: true,
          source: 'android_pressure',
          sensorName: 'LPS22HH Pressure Sensor',
        ),
      );
      recorder.recordAltitudeSample(
        const AltitudeSample(
          timestampMs: 1770000000000,
          pressureHpa: 1008.2,
          source: 'android_pressure',
        ),
        smoothedM: 42.1,
        baselineM: 38.0,
        deltaM: 4.1,
        armed: true,
        candidate: true,
        at: DateTime.utc(2026, 7, 18, 9, 0, 20),
      );
      recorder.recordSnapshot(
        _snapshot(
          steps: 4,
          distanceM: 3.1,
          path: const [PdrLocalPoint(0, 0), PdrLocalPoint(4, 1)],
        ),
        at: DateTime.utc(2026, 7, 18, 9, 0, 21),
      );
      recorder.recordFloorTransitionEvents([
        const EscalatorDetectionEvent(
          atMs: 1770000000000,
          kind: 'confirmed',
          reason: 'up',
          deltaM: 4.4,
          fromFloorLabel: '2F',
          toFloorLabel: '3F',
          group: 'ES1',
          durationMs: 21000,
          stepsDuring: 0,
        ),
        // 거부도 남는다 — 임계값 조정은 거부 이유가 있어야 가능하다.
        const EscalatorDetectionEvent(
          atMs: 1770000030000,
          kind: 'rejected',
          reason: 'multiFloorUnsupported',
          deltaM: 9.8,
          fromFloorLabel: '3F',
        ),
      ], at: DateTime.utc(2026, 7, 18, 9, 0, 22));

      final json = recorder.buildJson(
        buildingId: 'thehyundai-seoul',
        selectedFloor: '3F',
        mapCalibrationVersion: 'v1',
        graph: _graph(),
        device: const {},
      );

      final altimeter = json['altimeter']! as Map<String, Object?>;
      expect(altimeter['available'], true);
      expect(altimeter['source'], 'android_pressure');
      expect(altimeter['sensor_name'], 'LPS22HH Pressure Sensor');
      expect(altimeter['sample_count'], 1);
      expect(altimeter['dropped_samples'], 0);

      final sample =
          (json['altimeter_samples']! as List<Object?>).single!
              as Map<String, Object?>;
      expect(sample['pressure_hpa'], 1008.2);
      expect(sample['altitude_m'], isA<double>());
      expect(sample['smoothed_m'], 42.1);
      expect(sample['baseline_m'], 38.0);
      expect(sample['delta_m'], 4.1);
      expect(sample['armed'], true);
      expect(sample['candidate'], true);

      // 걸음 시계열과 같은 줄에서 고도를 볼 수 있어야 에스컬레이터와 계단을 가른다.
      final qualitySample =
          (json['quality_samples_1hz']! as List<Object?>).single!
              as Map<String, Object?>;
      final inlineAltimeter =
          qualitySample['altimeter']! as Map<String, Object?>;
      expect(inlineAltimeter['delta_m'], 4.1);

      final events = json['floor_transition_events']! as List<Object?>;
      expect(events, hasLength(2));
      expect((events.first! as Map<String, Object?>)['kind'], 'confirmed');
      expect((events.first! as Map<String, Object?>)['to_floor'], '3F');
      expect(
        (events.last! as Map<String, Object?>)['reason'],
        'multiFloorUnsupported',
      );
    });

    test('기압계 없는 기기는 available=false로 남고 시계열이 비어 있다', () {
      final recorder = PdrDebugSessionRecorder(
        startedAt: DateTime.utc(2026, 7, 18, 9),
      );
      recorder.recordSnapshot(
        _snapshot(
          steps: 1,
          distanceM: 0.7,
          path: const [PdrLocalPoint(0, 0), PdrLocalPoint(0.7, 0)],
        ),
        at: DateTime.utc(2026, 7, 18, 9),
      );

      final json = recorder.buildJson(
        buildingId: 'thehyundai-seoul',
        selectedFloor: '1F',
        mapCalibrationVersion: 'v1',
        graph: _graph(),
        device: const {},
      );

      expect((json['altimeter']! as Map<String, Object?>)['available'], false);
      expect(json['altimeter_samples'], isEmpty);
      expect(json['floor_transition_events'], isEmpty);
      final qualitySample =
          (json['quality_samples_1hz']! as List<Object?>).single!
              as Map<String, Object?>;
      expect(qualitySample['altimeter'], isNull);
    });
  });

  test('pedometer live/재조회 대조를 남기고, 없으면 null이다', () {
    final recorder = PdrDebugSessionRecorder(
      startedAt: DateTime.utc(2026, 7, 18, 9),
    );
    recorder.recordSnapshot(
      _snapshot(
        steps: 4,
        distanceM: 3.1,
        path: const [PdrLocalPoint(0, 0), PdrLocalPoint(4, 1)],
      ),
      at: DateTime.utc(2026, 7, 18, 9),
    );

    Map<String, Object?> build() => recorder.buildJson(
      buildingId: 'thehyundai-seoul',
      selectedFloor: '1F',
      mapCalibrationVersion: 'v1',
      graph: _graph(),
      device: const {},
    );

    expect(build()['pedometer_finalize'], isNull);

    recorder.recordPedometerFinalize(const {
      'steps': 112,
      'queriedSteps': 140,
      'queriedDistanceM': 107.4,
      'queryAvailable': true,
      'sessionStartMs': 1000.0,
      'stoppedAtMs': 77000.0,
    });

    final finalize = build()['pedometer_finalize']! as Map<String, Object?>;
    expect(finalize['live_steps'], 112);
    expect(finalize['queried_steps'], 140);
    // 이 차이가 0인지 아닌지가 초반 부족분의 성격을 가른다.
    expect(finalize['queried_minus_live'], 28);
  });

  test('복도 보정 상태와 heading bias를 원본 경로와 별도로 기록한다', () {
    final recorder = PdrDebugSessionRecorder(
      startedAt: DateTime.utc(2026, 7, 18, 9),
    );
    recorder.recordSnapshot(
      _snapshot(
        steps: 4,
        distanceM: 3.1,
        path: const [PdrLocalPoint.zero, PdrLocalPoint(4, 1)],
      ),
    );
    recorder.recordCorridorCorrection(
      const CorridorTrackingResult(
        state: CorridorTrackingState.turnPending,
        correctedPosition: PdrLocalPoint(4, 0),
        correctedHeadingDeg: 90,
        headingBiasDeg: 7,
        currentEdgeId: 'ab',
        currentEdgeProgressM: 4,
        travelDirectionSign: 1,
        pendingEdgeId: 'bc',
        lastConfirmedNodeId: null,
        correctedPath: [PdrLocalPoint.zero, PdrLocalPoint(4, 0)],
        previewPosition: PdrLocalPoint(4.5, 0),
        previewHeadingDeg: 90,
        previewPath: [PdrLocalPoint(4, 0), PdrLocalPoint(4.5, 0)],
        previewCandidateEdgeIds: ['bc'],
        previewIsAmbiguous: false,
        rawConfirmedPosition: PdrLocalPoint(4, 1),
        rawPreviewPosition: PdrLocalPoint(4.5, 1.2),
        confirmedDisplacementM: 4,
        optimisticLeadM: 0.5,
        optimisticEdgeId: 'ab',
        optimisticEdgeProgressM: 4.5,
        previewPeakIdsSynthetic: false,
        junctionNodeId: null,
        junctionDistanceM: double.infinity,
        junctionCandidateEdgeIds: [],
        leaderRelocated: false,
      ),
      at: DateTime.utc(2026, 7, 18, 9, 0, 3),
    );

    final json = recorder.buildJson(
      buildingId: 'thehyundai-seoul',
      selectedFloor: '1F',
      mapCalibrationVersion: 'v1',
      graph: _graph(),
      device: const {},
    );
    final summary = json['summary']! as Map<String, Object?>;
    final correction = summary['corridor_correction']! as Map<String, Object?>;
    final paths = json['paths']! as Map<String, Object?>;

    expect(correction['state'], 'turnPending');
    expect(correction['edge_progress_m'], 4);
    expect(correction['travel_direction_sign'], 1);
    expect(correction['heading_bias_deg'], 7);
    expect(correction['pending_edge_id'], 'bc');
    expect(paths['confirmed_pdr_local_m'], hasLength(2));
    expect(paths['corridor_corrected_floor_local_m'], hasLength(2));
    expect(paths['corridor_preview_floor_local_m'], hasLength(2));
    expect(json['corridor_correction_samples'], hasLength(1));
  });

  group('tracker 입력 이벤트(v10)', () {
    const result = CorridorTrackingResult(
      state: CorridorTrackingState.straightTracking,
      correctedPosition: PdrLocalPoint(4, 0),
      correctedHeadingDeg: 90,
      headingBiasDeg: 0,
      currentEdgeId: 'ab',
      currentEdgeProgressM: 4,
      travelDirectionSign: 1,
      pendingEdgeId: null,
      lastConfirmedNodeId: null,
      correctedPath: [PdrLocalPoint.zero, PdrLocalPoint(4, 0)],
      previewPosition: PdrLocalPoint(4.5, 0),
      previewHeadingDeg: 90,
      previewPath: [PdrLocalPoint(4, 0), PdrLocalPoint(4.5, 0)],
      previewCandidateEdgeIds: ['ab'],
      previewIsAmbiguous: false,
      rawConfirmedPosition: PdrLocalPoint(4, 1),
      rawPreviewPosition: PdrLocalPoint(4.5, 1.2),
      confirmedDisplacementM: 4,
      optimisticLeadM: 0.5,
      optimisticEdgeId: 'ab',
      optimisticEdgeProgressM: 4.5,
      previewPeakIdsSynthetic: false,
      junctionNodeId: null,
      junctionDistanceM: double.infinity,
      junctionCandidateEdgeIds: [],
      leaderRelocated: false,
    );

    CorridorObservation observation({
      required int timestampMs,
      required int confirmedSteps,
      int previewSteps = 6,
    }) => CorridorObservation(
      timestampMs: timestampMs,
      rawConfirmedPosition: const PdrLocalPoint(4, 1),
      confirmedSteps: confirmedSteps,
      confirmedDistanceM: confirmedSteps * 0.7,
      rawPreviewPosition: const PdrLocalPoint(4.5, 1.2),
      previewSteps: previewSteps,
      sensorHeadingDeg: 91.5,
      hasHeading: true,
      rawConfirmedStepPositions: const [PdrLocalPoint(3.3, 1)],
      rawPreviewTailPositions: const [
        PdrLocalPoint(4, 1),
        PdrLocalPoint(4.5, 1.2),
      ],
    );

    List<Object?> eventsOf(PdrDebugSessionRecorder recorder) =>
        recorder.buildJson(
              buildingId: 'b',
              selectedFloor: '1F',
              mapCalibrationVersion: 'v1',
              graph: _graph(),
              device: const {},
            )['tracker_input_events']!
            as List<Object?>;

    test('재초기화 지점과 관측을 순서대로 남긴다', () {
      final recorder = PdrDebugSessionRecorder(
        startedAt: DateTime.utc(2026, 7, 27, 9),
      );
      final snapshot = _snapshot(
        steps: 3,
        distanceM: 2.1,
        path: const [PdrLocalPoint.zero, PdrLocalPoint(4, 1)],
      );

      recorder.recordTrackerInput(
        observation: null,
        wasReset: true,
        result: result,
        snapshot: snapshot,
        previewTailPeakTimesMs: const [],
        at: DateTime.utc(2026, 7, 27, 9, 0, 1),
      );
      recorder.recordTrackerInput(
        observation: observation(timestampMs: 1000, confirmedSteps: 3),
        wasReset: false,
        result: result,
        snapshot: snapshot,
        previewTailPeakTimesMs: const [900, 1100],
        at: DateTime.utc(2026, 7, 27, 9, 0, 2),
      );

      final events = eventsOf(recorder);
      expect(events, hasLength(2));
      final reset = events.first! as Map<String, Object?>;
      expect(reset['kind'], 'reset');
      // reset 지점에는 관측이 없다. 재생은 여기서 상태를 다시 세운다.
      expect(reset.containsKey('confirmed_steps'), isFalse);

      final update = events.last! as Map<String, Object?>;
      expect(update['kind'], 'update');
      expect(update['timestamp_ms'], 1000);
      expect(update['confirmed_steps'], 3);
      expect(update['sensor_heading_deg'], 91.5);
      expect(update['raw_confirmed_step_positions'], hasLength(1));
      // 꼬리 좌표와 peak 시각의 인덱스가 맞아야 확정 시간창과 대조할 수 있다.
      expect(update['raw_preview_tail_positions'], hasLength(2));
      expect(update['raw_preview_tail_peak_times_ms'], [900, 1100]);
      expect((update['result']! as Map<String, Object?>)['edge_id'], 'ab');
    });

    test('같은 batchId는 한 번만 applied_batch로 남긴다', () {
      final recorder = PdrDebugSessionRecorder(
        startedAt: DateTime.utc(2026, 7, 27, 9),
      );
      final snapshot = _snapshot(
        steps: 3,
        distanceM: 2.1,
        path: const [PdrLocalPoint.zero, PdrLocalPoint(4, 1)],
        lastAppliedBatch: const PdrAppliedBatch(
          batchId: 7,
          spanStartMs: 500,
          spanEndMs: 1500,
          appliedSteps: 3,
          appliedDistanceM: 2.1,
        ),
        previewPeakTimesMs: const [null, 1200],
      );

      for (var i = 0; i < 3; i += 1) {
        recorder.recordTrackerInput(
          observation: observation(
            timestampMs: 1000 + i * 500,
            confirmedSteps: 3,
          ),
          wasReset: false,
          result: result,
          snapshot: snapshot,
          previewTailPeakTimesMs: const [1200],
          at: DateTime.utc(2026, 7, 27, 9, 0, i),
        );
      }

      final events = eventsOf(recorder);
      final withBatch = events
          .cast<Map<String, Object?>>()
          .where((event) => event.containsKey('applied_batch'))
          .toList();
      // snapshot은 motion마다 재방출되므로 batchId로 막지 않으면 3번 찍힌다.
      expect(withBatch, hasLength(1));
      final batch = withBatch.single['applied_batch']! as Map<String, Object?>;
      expect(batch['batch_id'], 7);
      expect(batch['span_end_ms'], 1500);
      expect(batch['applied_steps'], 3);
      expect(batch['consumed_preview_peak_times_ms'], [1200]);
    });

    test('걸음·배치 변화가 없으면 heartbeat 간격으로만 남긴다', () {
      final recorder = PdrDebugSessionRecorder(
        startedAt: DateTime.utc(2026, 7, 27, 9),
      );
      final snapshot = _snapshot(
        steps: 3,
        distanceM: 2.1,
        path: const [PdrLocalPoint.zero, PdrLocalPoint(4, 1)],
      );

      // 50ms 간격 20건 = 950ms. heartbeat(250ms)로 첫 건 + 3건만 남아야 한다.
      for (var i = 0; i < 20; i += 1) {
        recorder.recordTrackerInput(
          observation: observation(
            timestampMs: 1000 + i * 50,
            confirmedSteps: 3,
          ),
          wasReset: false,
          result: result,
          snapshot: snapshot,
          previewTailPeakTimesMs: const [],
          at: DateTime.utc(2026, 7, 27, 9, 0, 0, i * 50),
        );
      }

      final events = eventsOf(recorder);
      expect(events, hasLength(4));
      expect(
        events.cast<Map<String, Object?>>().map(
          (event) => event['timestamp_ms'],
        ),
        [1000, 1250, 1500, 1750],
      );
    });

    test('걸음이 바뀌면 heartbeat 전이라도 남긴다', () {
      final recorder = PdrDebugSessionRecorder(
        startedAt: DateTime.utc(2026, 7, 27, 9),
      );
      PdrSnapshot snapshotWith(int steps) => _snapshot(
        steps: steps,
        distanceM: steps * 0.7,
        path: const [PdrLocalPoint.zero, PdrLocalPoint(4, 1)],
      );

      recorder.recordTrackerInput(
        observation: observation(timestampMs: 1000, confirmedSteps: 3),
        wasReset: false,
        result: result,
        snapshot: snapshotWith(3),
        previewTailPeakTimesMs: const [],
        at: DateTime.utc(2026, 7, 27, 9, 0, 0),
      );
      recorder.recordTrackerInput(
        observation: observation(timestampMs: 1050, confirmedSteps: 4),
        wasReset: false,
        result: result,
        snapshot: snapshotWith(4),
        previewTailPeakTimesMs: const [],
        at: DateTime.utc(2026, 7, 27, 9, 0, 0, 50),
      );

      expect(eventsOf(recorder), hasLength(2));
    });
  });

  group('recordExitDoorMiss', () {
    Map<String, Object?>? missOf(PdrDebugSessionRecorder recorder) =>
        recorder.buildJson(
              buildingId: 'b',
              selectedFloor: '1F',
              mapCalibrationVersion: 'v1',
              graph: null,
              device: const {},
              exportedAt: DateTime.utc(2026, 8, 20),
            )['exit_door_closest_miss']
            as Map<String, Object?>?;

    test('가장 가까웠던 한 건만 남고 나머지는 세어진다', () {
      final recorder = PdrDebugSessionRecorder(
        startedAt: DateTime.utc(2026, 8, 20),
      );
      expect(missOf(recorder), isNull);

      recorder.recordExitDoorMiss(reason: 'outsideReachRadius', doorDistanceM: 40);
      recorder.recordExitDoorMiss(reason: 'trackerUncertain', doorDistanceM: 18);
      recorder.recordExitDoorMiss(reason: 'outsideReachRadius', doorDistanceM: 25);

      final miss = missOf(recorder)!;
      expect(miss['door_distance_m'], 18);
      expect(miss['reason'], 'trackerUncertain');
      expect(miss['sample_count'], 3);
    });

    // 거리를 못 잰 건이 잰 건을 밀어내면, 문턱을 다시 잡을 값이 사라진다.
    test('거리를 못 잰 건은 잰 건을 못 밀어낸다', () {
      final recorder = PdrDebugSessionRecorder(
        startedAt: DateTime.utc(2026, 8, 20),
      );
      recorder.recordExitDoorMiss(reason: 'noDoorDistance');
      expect(missOf(recorder)!['reason'], 'noDoorDistance');

      recorder.recordExitDoorMiss(reason: 'outsideReachRadius', doorDistanceM: 30);
      expect(missOf(recorder)!['door_distance_m'], 30);

      recorder.recordExitDoorMiss(reason: 'noDoorDistance');
      expect(missOf(recorder)!['door_distance_m'], 30);
    });
  });
}
