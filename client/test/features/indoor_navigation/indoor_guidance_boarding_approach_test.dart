import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_pdr_core/indoor_pdr_core.dart';
import 'package:navigation_client/features/indoor_navigation/application/escalator_transition_detector.dart';
import 'package:navigation_client/features/indoor_navigation/application/indoor_guidance_session.dart';
import 'package:navigation_client/features/indoor_navigation/contract/altitude_sample.dart';
import 'package:navigation_client/features/indoor_navigation/contract/pdr_anchor.dart';
import 'package:navigation_client/models/building/building_graph.dart';
import 'package:navigation_client/models/building/floor_graph.dart';
import 'package:navigation_client/models/route/indoor_route.dart';

/// 동서 복도(0,0)~(7,0) 끝에 하행 에스컬레이터가 붙어 있고, 그 자리에서 북쪽으로
/// **경로가 아닌** 복도가 갈라진다. 탑승점을 지나 북쪽으로 흘러가는 걸음이 곧
/// 실기기에서 재탐색을 돌리던 모양이다.
const _graph = FloorGraph(
  nodes: [
    GraphNode(id: 'a', type: 'corridor', xM: 0, yM: 0),
    GraphNode(id: 'es', type: 'escalator', name: 'ES1-DN(TOB1)', xM: 7, yM: 0),
    GraphNode(id: 'c', type: 'corridor', xM: 7, yM: 30),
  ],
  edges: [
    GraphEdge(
      id: 'ab',
      fromNodeId: 'a',
      toNodeId: 'es',
      lengthM: 7,
      bidirectional: true,
      geometryLocalM: [LocalPoint(0, 0), LocalPoint(7, 0)],
    ),
    GraphEdge(
      id: 'bc-off-route',
      fromNodeId: 'es',
      toNodeId: 'c',
      lengthM: 30,
      bidirectional: true,
      geometryLocalM: [LocalPoint(7, 0), LocalPoint(7, 30)],
    ),
  ],
);

const _route = IndoorRoute(
  points: [],
  pointsLocalM: [LocalPoint(0, 0), LocalPoint(7, 0)],
  nodeIds: ['a', 'es'],
  edgeIds: ['ab'],
  distanceMeters: 7,
);

/// 이 층 경로 끝에서 [transferMode]로 갈아타는 다층 경로.
MultiFloorRoute _routeVia({required String? transferMode}) => MultiFloorRoute(
  segments: [
    IndoorRouteSegment(
      floorId: '1F',
      floorName: '1F',
      route: _route,
      transferModeToNext: transferMode,
      transferFromNodeId: 'es',
      transferToNodeId: 'es-arrive',
    ),
  ],
  totalDistanceMeters: 7,
  totalCostMeters: 7,
);

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

/// 동쪽으로 10걸음(7m) 걸어 탑승점에 선 뒤, 그다음부터는 북쪽으로 흘러간다.
/// 걸음 0.7m 기준이다.
PdrSnapshot _walkedToBoardingThenNorth(int steps) {
  final path = [
    for (var index = 0; index <= steps; index += 1)
      index <= 10
          ? PdrLocalPoint(index * 0.7, 0)
          : PdrLocalPoint(7, (index - 10) * 0.7),
  ];
  final heading = steps <= 10 ? 90.0 : 0.0;
  return PdrSnapshot(
    position: path.last,
    path: path,
    steps: steps,
    distanceM: steps * 0.7,
    orientationHeadingDeg: heading,
    walkingHeadingDeg: heading,
    hasHeading: true,
    preview: PdrPreview(
      position: path.last,
      path: path,
      steps: steps,
      distanceM: steps * 0.7,
      acceptedPeakTimesMs: List<int?>.filled(path.length, null),
    ),
    quality: _quality,
  );
}

/// 탑승점 2.8m 앞에서 센서 보행 방향이 순간적으로 정반대로 해석되는 경로.
/// 실제로는 발판을 향해 몸을 크게 돌릴 때도 이 모양이 나올 수 있다.
PdrSnapshot _walkedNearBoardingThenReverse(int steps) {
  final path = [
    for (var index = 0; index <= steps; index += 1)
      index <= 6
          ? PdrLocalPoint(index * 0.7, 0)
          : PdrLocalPoint(4.2 - (index - 6) * 0.7, 0),
  ];
  final heading = steps <= 6 ? 90.0 : 270.0;
  return PdrSnapshot(
    position: path.last,
    path: path,
    steps: steps,
    distanceM: steps * 0.7,
    orientationHeadingDeg: heading,
    walkingHeadingDeg: heading,
    hasHeading: true,
    preview: PdrPreview(
      position: path.last,
      path: path,
      steps: steps,
      distanceM: steps * 0.7,
      acceptedPeakTimesMs: List<int?>.filled(path.length, null),
    ),
    quality: _quality,
  );
}

/// 탑승점까지 30m가 남은 긴 복도. 차단 반경(16m)과 가시 고정 반경(1.5m) **사이**를 걷는
/// 구간이 여기서만 나온다 — 위 7m 복도는 들어서자마자 차단 반경 안이다.
const _longGraph = FloorGraph(
  nodes: [
    GraphNode(id: 'a', type: 'corridor', xM: 0, yM: 0),
    GraphNode(id: 'es', type: 'escalator', name: 'ES1-DN(TOB1)', xM: 30, yM: 0),
  ],
  edges: [
    GraphEdge(
      id: 'ab',
      fromNodeId: 'a',
      toNodeId: 'es',
      lengthM: 30,
      bidirectional: true,
      geometryLocalM: [LocalPoint(0, 0), LocalPoint(30, 0)],
    ),
  ],
);

const _longRoute = IndoorRoute(
  points: [],
  pointsLocalM: [LocalPoint(0, 0), LocalPoint(30, 0)],
  nodeIds: ['a', 'es'],
  edgeIds: ['ab'],
  distanceMeters: 30,
);

/// graph 경로는 세 변을 도는 U자지만 실제 보행 공간은 열려 있어 사용자는
/// 시작점에서 눈앞의 에스컬레이터로 곧장 갈 수 있다. 특정 코너 판정이 아니라
/// "graph 경로와 자유보행이 다르다"는 계약을 재현한다.
const _shortcutGraph = FloorGraph(
  nodes: [
    GraphNode(id: 'a', type: 'corridor', xM: 0, yM: 0),
    GraphNode(id: 'b', type: 'corridor', xM: 0, yM: 10),
    GraphNode(id: 'c', type: 'corridor', xM: 10, yM: 10),
    GraphNode(id: 'es', type: 'escalator', name: 'ES1-DN(TOB1)', xM: 10, yM: 0),
  ],
  edges: [
    GraphEdge(
      id: 'ab',
      fromNodeId: 'a',
      toNodeId: 'b',
      lengthM: 10,
      bidirectional: true,
      geometryLocalM: [LocalPoint(0, 0), LocalPoint(0, 10)],
    ),
    GraphEdge(
      id: 'bc',
      fromNodeId: 'b',
      toNodeId: 'c',
      lengthM: 10,
      bidirectional: true,
      geometryLocalM: [LocalPoint(0, 10), LocalPoint(10, 10)],
    ),
    GraphEdge(
      id: 'ce',
      fromNodeId: 'c',
      toNodeId: 'es',
      lengthM: 10,
      bidirectional: true,
      geometryLocalM: [LocalPoint(10, 10), LocalPoint(10, 0)],
    ),
  ],
);

const _shortcutRoute = IndoorRoute(
  points: [],
  pointsLocalM: [
    LocalPoint(0, 0),
    LocalPoint(0, 10),
    LocalPoint(10, 10),
    LocalPoint(10, 0),
  ],
  nodeIds: ['a', 'b', 'c', 'es'],
  edgeIds: ['ab', 'bc', 'ce'],
  distanceMeters: 30,
);

/// 마지막 graph 노드에서 3.4m 서쪽의 에스컬레이터로 꺾어야 하지만, 부드럽게
/// 돌면 matcher가 북쪽 연장 간선을 계속 타는 실측 모양.
const _vestibuleGraph = FloorGraph(
  nodes: [
    GraphNode(id: 'a', type: 'corridor', xM: 0, yM: 0),
    GraphNode(id: 'v', type: 'junction', xM: 0, yM: 7),
    GraphNode(
      id: 'es',
      type: 'escalator',
      name: 'ES1-DN(TOB1)',
      xM: -3.4,
      yM: 7,
    ),
    GraphNode(id: 'wrong', type: 'corridor', xM: 0, yM: 20),
  ],
  edges: [
    GraphEdge(
      id: 'av',
      fromNodeId: 'a',
      toNodeId: 'v',
      lengthM: 7,
      bidirectional: true,
      geometryLocalM: [LocalPoint(0, 0), LocalPoint(0, 7)],
    ),
    GraphEdge(
      id: 've',
      fromNodeId: 'v',
      toNodeId: 'es',
      lengthM: 3.4,
      bidirectional: true,
      geometryLocalM: [LocalPoint(0, 7), LocalPoint(-3.4, 7)],
    ),
    GraphEdge(
      id: 'vw-wrong',
      fromNodeId: 'v',
      toNodeId: 'wrong',
      lengthM: 13,
      bidirectional: true,
      geometryLocalM: [LocalPoint(0, 7), LocalPoint(0, 20)],
    ),
  ],
);

const _vestibuleRoute = IndoorRoute(
  points: [],
  pointsLocalM: [LocalPoint(0, 0), LocalPoint(0, 7), LocalPoint(-3.4, 7)],
  nodeIds: ['a', 'v', 'es'],
  edgeIds: ['av', 've'],
  distanceMeters: 10.4,
);

/// 동쪽으로 [steps]걸음(0.7m).
PdrSnapshot _walkedEast(int steps) {
  final path = [for (var i = 0; i <= steps; i += 1) PdrLocalPoint(i * 0.7, 0)];
  return PdrSnapshot(
    position: path.last,
    path: path,
    steps: steps,
    distanceM: steps * 0.7,
    orientationHeadingDeg: 90,
    walkingHeadingDeg: 90,
    hasHeading: true,
    preview: PdrPreview(
      position: path.last,
      path: path,
      steps: steps,
      distanceM: steps * 0.7,
      acceptedPeakTimesMs: List<int?>.filled(path.length, null),
    ),
    quality: _quality,
  );
}

PdrSnapshot _walkedNorth(int steps) {
  final path = [for (var i = 0; i <= steps; i++) PdrLocalPoint(0, i * 0.7)];
  return PdrSnapshot(
    position: path.last,
    path: path,
    steps: steps,
    distanceM: steps * 0.7,
    orientationHeadingDeg: 0,
    walkingHeadingDeg: 0,
    hasHeading: true,
    preview: PdrPreview(
      position: path.last,
      path: path,
      steps: steps,
      distanceM: steps * 0.7,
      acceptedPeakTimesMs: List<int?>.filled(path.length, null),
    ),
    quality: _quality,
  );
}

/// 마지막 가로 에스컬레이터 연결 간선에 들어섰지만, 나침반은 아직 세로 복도
/// 방향을 보고 있는 실측 모양. 위치 polyline은 실제 ㄱ자로 꺾였고 heading만
/// 늦는다.
PdrSnapshot _walkedVestibuleWithLateHeading(int steps) {
  final path = [
    for (var index = 0; index <= steps; index += 1)
      index <= 10
          ? PdrLocalPoint(0, index * 0.7)
          : PdrLocalPoint(-(index - 10) * 0.7, 7),
  ];
  return PdrSnapshot(
    position: path.last,
    path: path,
    steps: steps,
    distanceM: steps * 0.7,
    orientationHeadingDeg: 0,
    walkingHeadingDeg: 0,
    hasHeading: true,
    preview: PdrPreview(
      position: path.last,
      path: path,
      steps: steps,
      distanceM: steps * 0.7,
      acceptedPeakTimesMs: List<int?>.filled(path.length, null),
    ),
    quality: _quality,
  );
}

const _anchor = PdrAnchor(
  floorId: '1F',
  anchorLocalM: PdrLocalPoint(0, 0),
  rotationDeg: 0,
  headingReference: HeadingReference.magneticNorth,
  requiresManualRotationCalibration: false,
  source: AnchorSource.userPin,
  confidence: 1,
);

void main() {
  final now = DateTime(2026, 8, 20, 12);

  IndoorGuidanceSession sessionVia(String? transferMode) =>
      IndoorGuidanceSession(now: () => now)
        ..attach(buildingId: 'b1')
        ..setContext(floorId: '1F', graph: _graph, floorLabels: ['1F', 'B1'])
        ..setAnchor(_anchor)
        ..setRoute(_routeVia(transferMode: transferMode))
        ..setRouteSegment(_route);

  IndoorGuidanceSession longEscalatorSession() =>
      IndoorGuidanceSession(now: () => now)
        ..attach(buildingId: 'b1')
        ..setContext(floorId: '1F', graph: _longGraph, floorLabels: ['1F'])
        ..setAnchor(_anchor)
        ..setRoute(
          MultiFloorRoute(
            segments: [
              const IndoorRouteSegment(
                floorId: '1F',
                floorName: '1F',
                route: _longRoute,
                transferModeToNext: 'escalator',
                transferFromNodeId: 'es',
              ),
            ],
            totalDistanceMeters: 30,
            totalCostMeters: 30,
          ),
        )
        ..setRouteSegment(_longRoute);

  IndoorGuidanceSession shortcutEscalatorSession() =>
      IndoorGuidanceSession(now: () => now)
        ..attach(buildingId: 'b1')
        ..setContext(
          floorId: '1F',
          graph: _shortcutGraph,
          floorLabels: ['1F', 'B1'],
        )
        ..setAnchor(_anchor)
        ..setRoute(
          MultiFloorRoute(
            segments: [
              const IndoorRouteSegment(
                floorId: '1F',
                floorName: '1F',
                route: _shortcutRoute,
                transferModeToNext: 'escalator',
                transferFromNodeId: 'es',
              ),
            ],
            totalDistanceMeters: 30,
            totalCostMeters: 30,
          ),
        )
        ..setRouteSegment(_shortcutRoute);

  IndoorGuidanceSession vestibuleEscalatorSession({
    String? transferMode = 'escalator',
  }) => IndoorGuidanceSession(now: () => now)
    ..attach(buildingId: 'b1')
    ..setContext(
      floorId: '1F',
      graph: _vestibuleGraph,
      floorLabels: ['1F', 'B1'],
    )
    ..setAnchor(_anchor)
    ..setRoute(
      MultiFloorRoute(
        segments: [
          IndoorRouteSegment(
            floorId: '1F',
            floorName: '1F',
            route: _vestibuleRoute,
            transferModeToNext: transferMode,
            transferFromNodeId: 'es',
          ),
        ],
        totalDistanceMeters: 10.4,
        totalCostMeters: 10.4,
      ),
    )
    ..setRouteSegment(_vestibuleRoute);

  /// [steps]걸음까지 걸어 넣는다. 기압은 **한 건도 넣지 않는다** — 탑승 직후
  /// Δ가 0인 구간이 이 파일이 덮는 구간이다.
  ///
  /// 단계 전이도 꺼내지 않는다. 화면은 기압 샘플이 올 때 꺼내므로, 기압이 없는
  /// 이 구간에서는 단계 고정(`_boardingHoldPointM`)이 애초에 안 걸린다.
  void walkRange(
    IndoorGuidanceSession session, {
    required int fromStep,
    required int toStep,
    int startMs = 1000,
  }) {
    for (var step = fromStep; step <= toStep; step += 1) {
      final atMs = startMs + step * 500;
      final result = session.onSnapshot(
        _walkedToBoardingThenNorth(step),
        timestampMs: atMs,
      );
      session.updateProgress(result, previewSteps: step, nowMs: atMs);
    }
  }

  void walkTo(IndoorGuidanceSession session, int steps, {int startMs = 1000}) {
    walkRange(session, fromStep: 0, toStep: steps, startMs: startMs);
  }

  group('탑승점 접근 — 고도가 오기 전', () {
    test('6m 안에 들어와도 실제 마커가 탑승점에 붙기 전에는 후보로만 둔다', () {
      final session = sessionVia('escalator');

      walkTo(session, 5);

      expect(session.escalator.phase, EscalatorPhase.idle);
      expect(session.isNearRouteBoarding, isTrue);
      expect(session.isPositionHeld, isFalse);
      expect(session.position!.localM.eastM, closeTo(3.5, 0.01));
      expect(session.position!.localM.northM, closeTo(0, 0.01));
    });

    test('탑승 감지 전에는 3m 안이어도 출발점을 미리 고정하지 않는다', () {
      final onePeak = sessionVia('escalator');
      walkTo(onePeak, 6);
      expect(onePeak.boardingApproachDistanceM, closeTo(2.8, 0.01));
      expect(onePeak.isPositionHeld, isFalse);
      final shown = onePeak.position!.localM;
      final unchanged = onePeak.onSnapshot(
        _walkedToBoardingThenNorth(6),
        timestampMs: 6000,
      );
      onePeak.updateProgress(unchanged, previewSteps: 6, nowMs: 6000);
      expect(
        onePeak.position!.localM,
        shown,
        reason: '같은 peak 반복은 위치를 바꾸지 않는다',
      );
    });

    test('탑승 감지 뒤 반대 방향으로 돌아도 시작점은 유지한다', () {
      final session = sessionVia('escalator');
      for (var step = 0; step <= 12; step++) {
        final atMs = 1000 + step * 500;
        final result = session.onSnapshot(
          _walkedNearBoardingThenReverse(step),
          timestampMs: atMs,
        );
        session.updateProgress(result, previewSteps: step, nowMs: atMs);
      }

      expect(session.isPositionHeld, isTrue);
      expect(session.position!.localM.eastM, closeTo(4.9, 0.01));
      expect(session.trackingResult!.optimisticEdgeId, 'ab');
      expect(
        session.trackingResult!.previewPosition,
        const PdrLocalPoint(7, 0),
      );
    });

    test('탑승 감지 전에는 긴 마지막 간선도 계속 진행한다', () {
      final session = longEscalatorSession();
      for (var step = 0; step <= 40; step += 1) {
        final atMs = 1000 + step * 500;
        final snapshot = _walkedEast(step);
        session.updateProgress(
          session.onSnapshot(snapshot, timestampMs: atMs),
          previewSteps: step,
          nowMs: atMs,
        );
      }

      expect(session.isPositionHeld, isFalse);
      expect(session.position!.localM.eastM, isNot(closeTo(30, 0.01)));
    });

    test('느린 접근은 최초 16m 진입 후 40초가 지나도 탑승 후보를 유지한다', () {
      final session = longEscalatorSession();
      for (var step = 0; step <= 42; step += 1) {
        final atMs = step <= 20
            ? 1000 + step * 500
            : 11000 + (step - 20) * 2500;
        final snapshot = _walkedEast(step);
        session.updateProgress(
          session.onSnapshot(snapshot, timestampMs: atMs),
          previewSteps: step,
          nowMs: atMs,
        );
      }

      expect(session.isNearRouteBoarding, isTrue);
      expect(session.isPositionHeld, isFalse);
    });

    test('열린 공간을 가로질러도 탑승 감지 전에는 자유보행을 계속 표시한다', () {
      final session = shortcutEscalatorSession();
      for (var step = 0; step <= 14; step += 1) {
        final atMs = 1000 + step * 500;
        final snapshot = _walkedEast(step);
        session.updateProgress(
          session.onSnapshot(snapshot, timestampMs: atMs),
          previewSteps: step,
          nowMs: atMs,
        );
      }

      final result = session.trackingResult!;
      const boarding = PdrLocalPoint(10, 0);
      expect(
        (boarding - result.previewPosition).distance,
        greaterThan(3),
        reason: '고정 뒤 내부 tracker는 경로 종점에 잠기지만 화면은 이미 별도 hold다',
      );
      expect(
        (boarding - result.rawPreviewPosition).distance,
        lessThan(1),
        reason: '원시 절대좌표를 표시하지는 않지만 실제 자유보행은 탑승점에 닿았다',
      );
      expect(session.boardingApproachDistanceM, lessThan(1));
      expect(session.isPositionHeld, isFalse);
      expect(
        (session.position!.localM - result.rawPreviewPosition).distance,
        greaterThan(3),
        reason: '탑승 접근 그림자는 자유보행을 판정에만 쓰고 표시 위치는 억지로 고정하지 않는다',
      );
    });

    test('짧은 마지막 연결 간선에서 감지되면 내부 시작점을 보존한다', () {
      final session = vestibuleEscalatorSession();
      for (var step = 0; step <= 16; step++) {
        final atMs = 1000 + step * 500;
        final result = session.onSnapshot(
          _walkedNorth(step),
          timestampMs: atMs,
        );
        session.updateProgress(result, previewSteps: step, nowMs: atMs);
      }

      expect(session.isPositionHeld, isTrue);
      expect(
        session.trackingResult!.optimisticEdgeId,
        isNot('vw-wrong'),
        reason: '탑승 접근 중에는 걸음 거리를 버리지 않고 활성 경로 간선에 남는다',
      );
      expect(
        session.trackingResult!.matchedPreviewPosition.northM,
        closeTo(7, 0.1),
      );
      expect(session.position!.localM.eastM, closeTo(-3.4, 0.1));
      expect(session.position!.localM.northM, closeTo(7, 0.1));
    });

    test('마지막 ㄱ자에서 heading이 늦어도 걸음 속도로 탑승 노드까지 따른다', () {
      final session = vestibuleEscalatorSession();
      for (var step = 0; step <= 15; step++) {
        final atMs = 1000 + step * 500;
        final result = session.onSnapshot(
          _walkedVestibuleWithLateHeading(step),
          timestampMs: atMs,
        );
        session.updateProgress(result, previewSteps: step, nowMs: atMs);
      }

      expect(session.isFollowingRouteBoarding, isTrue);
      expect(session.position!.localM.eastM, closeTo(-3.4, 0.15));
      expect(session.position!.localM.northM, closeTo(7, 0.15));
    });

    test('같은 전실을 지나도 경로가 에스컬레이터 탑승을 지목하지 않으면 붙들지 않는다', () {
      final session = vestibuleEscalatorSession(transferMode: null);
      for (var step = 0; step <= 16; step++) {
        final atMs = 1000 + step * 500;
        final result = session.onSnapshot(
          _walkedNorth(step),
          timestampMs: atMs,
        );
        session.updateProgress(result, previewSteps: step, nowMs: atMs);
      }

      expect(session.isNearRouteBoarding, isFalse);
      expect(session.isPositionHeld, isFalse);
      expect(session.position!.localM.northM, greaterThan(9));
    });

    test('경로 후보에서 1차 수직 이동이 잡히면 강한 문턱 전에도 현재 위치를 붙든다', () {
      final session = sessionVia('escalator');
      walkTo(session, 5);
      expect(session.isPositionHeld, isFalse);
      final beforeRise = session.position!.localM;

      double pressureAt(double altitudeM) =>
          1013.25 * math.pow(1.0 - altitudeM / 44330.0, 1 / 0.190295);
      var atMs = 5000;
      final phases = <EscalatorPhase>[];
      void altitude(double altitudeM) {
        atMs += 1069;
        session.onAltitude(
          AltitudeSample(
            timestampMs: atMs,
            pressureHpa: pressureAt(altitudeM),
            source: 'test',
          ),
        );
        phases.addAll(session.takePhaseChanges().map((item) => item.phase));
      }

      for (var index = 0; index < 5; index++) {
        altitude(0);
      }
      for (var index = 1; index <= 3; index++) {
        altitude(-0.45 * index / 3);
      }

      expect(session.escalator.isVerticalMotionObserved, isTrue);
      expect(phases, isNot(contains(EscalatorPhase.verticalMotionDetected)));
      expect(session.isPositionHeld, isTrue);

      final moved = session.onSnapshot(
        _walkedToBoardingThenNorth(6),
        timestampMs: atMs + 500,
      );
      session.updateProgress(moved, previewSteps: 6, nowMs: atMs + 500);
      expect(session.position!.localM.eastM, closeTo(beforeRise.eastM, 0.01));
      expect(session.position!.localM.northM, closeTo(beforeRise.northM, 0.01));
    });

    test('발판 진동이 걸음으로 세어져도 마커는 그 자리다', () {
      // 증상 (2): 한 칸 옆으로 옮겨 섰을 뿐인데 마커가 크게 움직였다.
      final session = sessionVia('escalator');
      walkTo(session, 10);
      final held = session.position!.localM;

      // 탑승 뒤 진동 6걸음(4.2m). 풀기 반경 안이라 아직 안 풀린다.
      walkRange(session, fromStep: 11, toStep: 16);

      expect(session.position!.localM.eastM, held.eastM);
      expect(session.position!.localM.northM, held.northM);
    });

    test('경로가 지목한 탑승점이 아니면 아무것도 안 건다', () {
      // 엘리베이터 환승 구간. 그냥 걷고 있는 사람의 마커를 세우면 안 된다.
      final session = sessionVia('elevator');

      walkTo(session, 10);

      expect(session.isPositionHeld, isFalse);
      expect(session.isNearRouteBoarding, isFalse);
      expect(session.boardingApproachDistanceM, isNull);
    });
  });

  group('탑승점 접근 — 재탐색 차단', () {
    /// 탑승점을 지나 북쪽 복도로 흘러가는 동안 재탐색을 물어봤는지.
    bool askedWhileDriftingNorth(String? transferMode, {int toSteps = 30}) {
      final session = sessionVia(transferMode);
      var asked = false;
      for (var step = 0; step <= toSteps; step += 1) {
        final atMs = 1000 + step * 500;
        final result = session.onSnapshot(
          _walkedToBoardingThenNorth(step),
          timestampMs: atMs,
        );
        final update = session.updateProgress(
          result,
          previewSteps: step,
          nowMs: atMs,
        );
        asked = asked || update.shouldReroute;
      }
      return asked;
    }

    test('탑승점 근처에서는 이탈 증거가 쌓여도 재탐색을 걸지 않는다', () {
      // "경로를 벗어났습니다 / 새 경로를 자동으로 찾고 있습니다"가 타는 도중에
      // 뜨던 구간이다. 차단은 틀려도 재탐색이 몇 초 늦을 뿐이다.
      expect(askedWhileDriftingNorth('escalator'), isFalse);
    });

    test('같은 걸음이라도 에스컬레이터 환승이 아니면 재탐색이 나간다', () {
      expect(
        askedWhileDriftingNorth('elevator'),
        isTrue,
        reason: '차단이 탑승점 근거에서만 걸린다는 것을 이 대비가 보인다',
      );
    });
  });

  group('탑승점 접근 — 탈출구', () {
    test('탑승 직후에는 8m 밖 가짜 걸음도 잠시 붙들고 이후 실제 통과는 푼다', () {
      // 탑승점 앞에 섰다가 그냥 지나쳐 걸어가는 사람. 고정 해제(8m)가 차단(16m)보다
      // 먼저 풀려야 걸어가는 마커가 따라간다.
      final session = sessionVia('escalator');

      walkTo(session, 10);
      expect(session.isPositionHeld, isTrue);

      // 북쪽으로 13걸음(9.1m) — 푸는 반경 밖이어도 기압이 이어받을 유예 안이다.
      walkRange(session, fromStep: 11, toStep: 22);

      expect(session.isPositionHeld, isTrue);

      // 수직 근거 없이 계속 걸으면 실제 통과다. 유예 뒤에는 기존 탈출구가 산다.
      final afterGrace = session.onSnapshot(
        _walkedToBoardingThenNorth(22),
        timestampMs: 20000,
      );
      session.updateProgress(afterGrace, previewSteps: 22, nowMs: 20000);

      expect(session.isPositionHeld, isFalse);
      expect(session.isNearRouteBoarding, isTrue, reason: '차단은 아직 살아 있다');
      final tracked = session.trackingResult!.previewPosition;
      expect(session.position!.localM.northM, closeTo(tracked.northM, 0.01));
    });

    test('더 멀어지면 재탐색 차단도 풀린다', () {
      final session = sessionVia('escalator');

      // 북쪽으로 25걸음(17.5m) — 허가 반경 16m 밖.
      walkTo(session, 35);
      final afterGrace = session.onSnapshot(
        _walkedToBoardingThenNorth(35),
        timestampMs: 20000,
      );
      session.updateProgress(afterGrace, previewSteps: 35, nowMs: 20000);

      expect(session.isNearRouteBoarding, isFalse);
      expect(session.isPositionHeld, isFalse);
    });

    test('탑승점 앞에 계속 서 있어도 40초간 움직임이 없으면 둘 다 접는다', () {
      // 거리로는 영영 안 풀리는 경우의 상한. 줄을 서서 기다리는 동안이라
      // 게이트가 먼저 풀려도 잃는 것이 없다.
      final session = sessionVia('escalator');
      walkTo(session, 10);
      expect(session.isPositionHeld, isTrue);

      // 15초 탑승 보호 뒤 걸음이 안 늘어난 채 40초 이상 흐른다.
      final heldUntilMs = 1000 + 10 * 500;
      for (var second = 1; second <= 70; second += 1) {
        final result = session.onSnapshot(
          _walkedToBoardingThenNorth(10),
          timestampMs: heldUntilMs + second * 1000,
        );
        session.updateProgress(
          result,
          previewSteps: 10,
          nowMs: heldUntilMs + second * 1000,
        );
      }

      expect(session.isPositionHeld, isFalse);
      expect(session.isNearRouteBoarding, isFalse);
    });
  });

  group('탑승점 접근 — 남은거리는 계속 간다', () {
    test('차단 반경 안이어도 고정 전까지는 진행률이 갱신된다', () {
      // 차단(16m)과 위치 고정을 같은 조건으로 묶으면 ETA가 탑승점 16m 전부터
      // 멈춘다. 차단은 재탐색만 막고 진행률은 그대로 흘러야 한다.
      final session = IndoorGuidanceSession(now: () => now)
        ..attach(buildingId: 'b1')
        ..setContext(floorId: '1F', graph: _longGraph, floorLabels: ['1F'])
        ..setAnchor(_anchor)
        ..setRoute(
          MultiFloorRoute(
            segments: [
              IndoorRouteSegment(
                floorId: '1F',
                floorName: '1F',
                route: _longRoute,
                transferModeToNext: 'escalator',
                transferFromNodeId: 'es',
              ),
            ],
            totalDistanceMeters: 30,
            totalCostMeters: 30,
          ),
        )
        ..setRouteSegment(_longRoute);

      double? remainingAt(int steps) {
        final atMs = 1000 + steps * 500;
        session.updateProgress(
          session.onSnapshot(_walkedEast(steps), timestampMs: atMs),
          previewSteps: steps,
          nowMs: atMs,
        );
        return session.displayProgress?.remainingM;
      }

      for (var steps = 0; steps <= 20; steps += 1) {
        remainingAt(steps);
      }
      // 20걸음 = 14m, 탑승점까지 16m — 차단은 이미 열렸고 고정은 아직 아니다.
      expect(session.isNearRouteBoarding, isTrue);
      expect(session.isPositionHeld, isFalse);
      final atGateOpen = session.displayProgress!.remainingM;

      // 가시 고정 반경(1.5m) 밖까지만 더 걷는다: 30걸음 = 21m, 남은 9m.
      for (var steps = 21; steps <= 30; steps += 1) {
        remainingAt(steps);
      }

      expect(session.isPositionHeld, isFalse);
      expect(
        session.displayProgress!.remainingM,
        lessThan(atGateOpen),
        reason: '차단 구간에서도 남은거리는 계속 줄어야 한다',
      );
    });
  });
}
