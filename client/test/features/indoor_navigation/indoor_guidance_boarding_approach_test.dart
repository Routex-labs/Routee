import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_pdr_core/indoor_pdr_core.dart';
import 'package:navigation_client/features/indoor_navigation/application/escalator_transition_detector.dart';
import 'package:navigation_client/features/indoor_navigation/application/indoor_guidance_session.dart';
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

/// 탑승점까지 30m가 남은 긴 복도. 차단 반경(16m)과 고정 반경(6m) **사이**를 걷는
/// 구간이 여기서만 나온다 — 위 7m 복도는 들어서자마자 고정 반경 안이다.
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

  /// [steps]걸음까지 걸어 넣는다. 기압은 **한 건도 넣지 않는다** — 탑승 직후
  /// Δ가 0인 구간이 이 파일이 덮는 구간이다.
  ///
  /// 단계 전이도 꺼내지 않는다. 화면은 기압 샘플이 올 때 꺼내므로, 기압이 없는
  /// 이 구간에서는 단계 고정(`_boardingHoldPointM`)이 애초에 안 걸린다.
  void walkTo(IndoorGuidanceSession session, int steps, {int startMs = 1000}) {
    for (var step = 0; step <= steps; step += 1) {
      session.onSnapshot(
        _walkedToBoardingThenNorth(step),
        timestampMs: startMs + step * 500,
      );
    }
  }

  group('탑승점 접근 — 고도가 오기 전', () {
    test('Δ가 0이고 판정기가 idle이어도 탑승점에 서면 마커를 붙든다', () {
      // 실기기 증상: 타는 중인데 마커가 옆 복도에 있고 칩은 `Δ-0.0m · 무장O ·
      // 후보X · idle`이었다. 보정 위치가 탑승점 3.5m 앞에 멈춰 배너 반경(3m)
      // 밖이라 단계가 안 올라가는 상태 — 실측에서 위치가 12m까지 어긋났다.
      final session = sessionVia('escalator');

      walkTo(session, 5);

      expect(session.escalator.phase, EscalatorPhase.idle);
      expect(session.isPositionHeld, isTrue);
      expect(session.position!.localM.eastM, closeTo(7, 0.01));
      expect(session.position!.localM.northM, closeTo(0, 0.01));
    });

    test('발판 진동이 걸음으로 세어져도 마커는 그 자리다', () {
      // 증상 (2): 한 칸 옆으로 옮겨 섰을 뿐인데 마커가 크게 움직였다.
      final session = sessionVia('escalator');
      walkTo(session, 10);
      final held = session.position!.localM;

      // 탑승 뒤 진동 6걸음(4.2m). 고정 반경 6m 안이라 아직 안 풀린다.
      walkTo(session, 16);

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
    test('탑승점에서 멀어지면 고정이 먼저 풀린다', () {
      // 탑승점 앞에 섰다가 그냥 지나쳐 걸어가는 사람. 고정(8m)이 차단(16m)보다
      // 먼저 풀려야 걸어가는 마커가 따라간다.
      final session = sessionVia('escalator');

      walkTo(session, 10);
      expect(session.isPositionHeld, isTrue);

      // 북쪽으로 13걸음(9.1m) — 푸는 반경 8m 밖.
      walkTo(session, 23);

      expect(session.isPositionHeld, isFalse);
      expect(session.isNearRouteBoarding, isTrue, reason: '차단은 아직 살아 있다');
      final tracked = session.trackingResult!.previewPosition;
      expect(session.position!.localM.northM, closeTo(tracked.northM, 0.01));
    });

    test('더 멀어지면 재탐색 차단도 풀린다', () {
      final session = sessionVia('escalator');

      // 북쪽으로 25걸음(17.5m) — 허가 반경 16m 밖.
      walkTo(session, 35);

      expect(session.isNearRouteBoarding, isFalse);
      expect(session.isPositionHeld, isFalse);
    });

    test('탑승점 앞에 계속 서 있어도 40초가 지나면 둘 다 접는다', () {
      // 거리로는 영영 안 풀리는 경우의 상한. 줄을 서서 기다리는 동안이라
      // 게이트가 먼저 풀려도 잃는 것이 없다.
      final session = sessionVia('escalator');
      walkTo(session, 10);
      expect(session.isPositionHeld, isTrue);

      // 걸음이 안 늘어난 채 41초가 흐른다.
      final heldUntilMs = 1000 + 10 * 500;
      for (var second = 1; second <= 41; second += 1) {
        session.onSnapshot(
          _walkedToBoardingThenNorth(10),
          timestampMs: heldUntilMs + second * 1000,
        );
      }

      expect(session.isPositionHeld, isFalse);
      expect(session.isNearRouteBoarding, isFalse);
    });
  });

  group('탑승점 접근 — 남은거리는 계속 간다', () {
    test('차단 반경 안이어도 고정 전까지는 진행률이 갱신된다', () {
      // 차단(16m)과 고정(6m)을 같은 조건으로 묶으면 ETA가 탑승점 16m 전부터
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

      // 고정 반경(6m) 밖까지만 더 걷는다: 30걸음 = 21m, 남은 9m.
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
