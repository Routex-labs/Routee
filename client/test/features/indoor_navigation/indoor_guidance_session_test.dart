import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_pdr_core/indoor_pdr_core.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/features/indoor_navigation/application/indoor_guidance_position.dart';
import 'package:navigation_client/features/indoor_navigation/application/indoor_guidance_session.dart';
import 'package:navigation_client/features/indoor_navigation/application/indoor_location_estimate.dart';
import 'package:navigation_client/features/indoor_navigation/application/escalator_transition_detector.dart';
import 'package:navigation_client/features/indoor_navigation/contract/altitude_sample.dart';
import 'package:navigation_client/models/building/building_graph.dart';
import 'package:navigation_client/domain/guidance/route_movement.dart';
import 'package:navigation_client/models/route/indoor_route.dart';
import 'package:navigation_client/features/indoor_navigation/contract/pdr_anchor.dart';
import 'package:navigation_client/models/building/floor_graph.dart';

/// 동서로 뻗은 복도 하나. 걸음이 이 선 위로 보정된다.
const _corridorGraph = FloorGraph(
  nodes: [
    GraphNode(id: 'w', type: 'corridor', xM: 0, yM: 0),
    GraphNode(id: 'e', type: 'corridor', xM: 50, yM: 0),
  ],
  edges: [
    GraphEdge(
      id: 'we',
      fromNodeId: 'w',
      toNodeId: 'e',
      lengthM: 50,
      bidirectional: true,
      geometryLocalM: [LocalPoint(0, 0), LocalPoint(50, 0)],
    ),
  ],
);

const _turnRouteGraph = FloorGraph(
  nodes: [
    GraphNode(id: 'a', type: 'corridor', xM: 0, yM: 0),
    GraphNode(id: 'b', type: 'junction', xM: 7, yM: 0),
    GraphNode(id: 'c', type: 'corridor', xM: 7, yM: 7),
  ],
  edges: [
    GraphEdge(
      id: 'ab',
      fromNodeId: 'a',
      toNodeId: 'b',
      lengthM: 7,
      bidirectional: true,
      geometryLocalM: [LocalPoint(0, 0), LocalPoint(7, 0)],
    ),
    GraphEdge(
      id: 'bc',
      fromNodeId: 'b',
      toNodeId: 'c',
      lengthM: 7,
      bidirectional: true,
      geometryLocalM: [LocalPoint(7, 0), LocalPoint(7, 7)],
    ),
  ],
);

const _turnRoute = IndoorRoute(
  points: [],
  pointsLocalM: [LocalPoint(0, 0), LocalPoint(7, 0), LocalPoint(7, 7)],
  nodeIds: ['a', 'b', 'c'],
  edgeIds: ['ab', 'bc'],
  distanceMeters: 14,
);

const _branchGraph = FloorGraph(
  nodes: [
    GraphNode(id: 'a', type: 'corridor', xM: 0, yM: 0),
    GraphNode(id: 'b', type: 'junction', xM: 7, yM: 0),
    GraphNode(id: 'c', type: 'corridor', xM: 7, yM: 20),
  ],
  edges: [
    GraphEdge(
      id: 'ab',
      fromNodeId: 'a',
      toNodeId: 'b',
      lengthM: 7,
      bidirectional: true,
      geometryLocalM: [LocalPoint(0, 0), LocalPoint(7, 0)],
    ),
    GraphEdge(
      id: 'bc-off-route',
      fromNodeId: 'b',
      toNodeId: 'c',
      lengthM: 20,
      bidirectional: true,
      geometryLocalM: [LocalPoint(7, 0), LocalPoint(7, 20)],
    ),
  ],
);

const _branchRoute = IndoorRoute(
  points: [],
  pointsLocalM: [LocalPoint(0, 0), LocalPoint(7, 0)],
  nodeIds: ['a', 'b'],
  edgeIds: ['ab'],
  distanceMeters: 7,
);

PdrAnchor _anchor({
  String floorId = '1F',
  double eastM = 1,
  double northM = 0,
}) => PdrAnchor(
  floorId: floorId,
  anchorLocalM: PdrLocalPoint(eastM, northM),
  rotationDeg: 0,
  headingReference: HeadingReference.magneticNorth,
  requiresManualRotationCalibration: false,
  source: AnchorSource.userPin,
  confidence: 1,
);

/// 품질은 이 세션의 판단에 쓰이지 않는다. 스냅샷을 만들려면 필요할 뿐이라
/// 최소값 한 벌을 재사용한다.
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

/// 동쪽으로 [steps]걸음(0.7m) 걸은 스냅샷.
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

PdrSnapshot _walkedNorthTurn(int steps) {
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

IndoorLocationEstimate _estimate({
  String buildingId = 'b1',
  String floorId = '1F',
  double eastM = 40,
  required DateTime observedAt,
}) => IndoorLocationEstimate(
  buildingId: buildingId,
  floorId: floorId,
  localM: PdrLocalPoint(eastM, 0),
  wgs84: const LatLng(37, 127),
  accuracyMeters: 8,
  observedAt: observedAt,
  source: 'gps',
);

void main() {
  // 시간을 고정한다. 추정점 신선도(30초)가 판단에 들어가므로 벽시계를 쓰면
  // 느린 CI에서 간헐적으로 갈린다.
  final now = DateTime(2026, 8, 10, 12);
  IndoorGuidanceSession newSession() => IndoorGuidanceSession(now: () => now);

  /// 붙이고 층·그래프·앵커까지 세워 둔 세션. 대부분의 테스트가 여기서 시작한다.
  IndoorGuidanceSession attachedSession() => newSession()
    ..attach(buildingId: 'b1')
    ..setContext(floorId: '1F', graph: _corridorGraph)
    ..setAnchor(_anchor());

  group('부착 상태', () {
    test('붙이지 않으면 스냅샷을 버리고 위치도 내지 않는다', () {
      final session = newSession()
        ..setContext(floorId: '1F', graph: _corridorGraph)
        ..setAnchor(_anchor());

      expect(session.onSnapshot(_walkedEast(10), timestampMs: 1000), isNull);
      expect(session.position, isNull);
      expect(session.trackingResult, isNull);
    });

    test('떼어내면 그때까지의 보정을 버린다', () {
      // 야외로 나간 동안 걸은 거리가 실내 좌표계에 남아 있으면, 다시 들어올 때
      // 사용자는 걸어 본 적 없는 자리에서 시작한다.
      final session = attachedSession()
        ..onSnapshot(_walkedEast(10), timestampMs: 1000);
      expect(session.position?.source, GuidancePositionSource.tracked);

      session.detach();

      expect(session.isAttached, isFalse);
      expect(session.position, isNull);
      expect(session.trackingResult, isNull);
    });

    test('떼었다 다시 붙이면 이전 세션의 걸음이 이월되지 않는다', () {
      final session = attachedSession()
        ..onSnapshot(_walkedEast(20), timestampMs: 1000);
      final walkedEastM = session.position!.localM.eastM;
      expect(walkedEastM, greaterThan(10));

      session
        ..detach()
        ..attach(buildingId: 'b1')
        ..setContext(floorId: '1F', graph: _corridorGraph)
        ..setAnchor(_anchor());

      // 걸음 없이 앵커만 있는 상태로 돌아와야 한다.
      expect(session.position?.source, GuidancePositionSource.anchorOnly);
      expect(session.position?.localM.eastM, 1);
    });

    test('같은 건물에 다시 붙이는 것은 보정을 리셋하지 않는다', () {
      // 층 오버레이를 다시 그릴 때마다 attach가 불릴 수 있다. 그때마다 리셋하면
      // 사용자는 걷는 도중 위치가 앵커로 되돌아가는 것을 본다.
      final session = attachedSession()
        ..onSnapshot(_walkedEast(20), timestampMs: 1000);
      final before = session.position!.localM.eastM;

      session.attach(buildingId: 'b1');

      expect(session.position?.localM.eastM, before);
      expect(session.position?.source, GuidancePositionSource.tracked);
    });
  });

  group('위치 출처 우선순위', () {
    test('앵커 + 걸음이면 보정된 위치를 tracked로 낸다', () {
      final session = attachedSession()
        ..onSnapshot(_walkedEast(10), timestampMs: 1000);

      final position = session.position!;
      expect(position.source, GuidancePositionSource.tracked);
      // 복도 위로 보정되므로 north는 0에 붙어 있고, 동쪽으로 이동해 있다.
      expect(position.localM.northM, closeTo(0, 0.5));
      expect(position.localM.eastM, greaterThan(1));
      expect(position.headingDeg, isNotNull);
    });

    test('앵커만 있고 걸음이 없으면 anchorOnly이고 방향은 비운다', () {
      // 서 있는 사람에게 방향 원뿔을 그리면 아무 근거 없는 방향을 가리킨다.
      final session = attachedSession();

      final position = session.position!;
      expect(position.source, GuidancePositionSource.anchorOnly);
      expect(position.localM.eastM, 1);
      expect(position.headingDeg, isNull);
    });

    test('앵커가 없으면 신선한 추정점을 estimate로 낸다', () {
      final session = newSession()
        ..attach(buildingId: 'b1')
        ..setContext(floorId: '1F', graph: _corridorGraph)
        ..setEstimate(
          _estimate(observedAt: now.subtract(const Duration(seconds: 5))),
        );

      final position = session.position!;
      expect(position.source, GuidancePositionSource.estimate);
      expect(position.isConfirmed, isFalse);
      expect(position.accuracyM, 8);
      expect(position.headingDeg, isNull);
    });

    test('추정점은 걸어서 이동한 위치를 되돌리지 않는다', () {
      // 추정점은 30초까지 살아 있다. 우선순위가 뒤집히면 이미 20m 걸어간
      // 사용자를 30초 전 GPS 자리로 끌어다 놓는다.
      final session = attachedSession()
        ..setEstimate(_estimate(eastM: 40, observedAt: now))
        ..onSnapshot(_walkedEast(10), timestampMs: 1000);

      final position = session.position!;
      expect(position.source, GuidancePositionSource.tracked);
      expect(position.localM.eastM, lessThan(40));
    });

    test('오래된 추정점은 쓰지 않는다', () {
      final session = newSession()
        ..attach(buildingId: 'b1')
        ..setContext(floorId: '1F', graph: _corridorGraph)
        ..setEstimate(
          _estimate(observedAt: now.subtract(const Duration(seconds: 31))),
        );

      expect(session.position, isNull);
    });

    test('다른 건물·다른 층의 추정점은 쓰지 않는다', () {
      final session = newSession()
        ..attach(buildingId: 'b1')
        ..setContext(floorId: '1F', graph: _corridorGraph);

      session.setEstimate(_estimate(buildingId: 'b2', observedAt: now));
      expect(session.position, isNull, reason: '다른 건물 추정점');

      session.setEstimate(_estimate(floorId: '2F', observedAt: now));
      expect(session.position, isNull, reason: '다른 층 추정점');
    });
  });

  group('탑승점 고정 판정', () {
    // 에스컬레이터 노드 하나가 붙은 층. 고정은 이 노드 좌표로 걸린다.
    const escalatorGraph = FloorGraph(
      nodes: [
        GraphNode(id: 'w', type: 'corridor', xM: 0, yM: 0),
        GraphNode(
          id: 'es-up',
          type: 'escalator',
          name: 'ES1-UP(TO2F)',
          xM: 30,
          yM: 0,
        ),
      ],
      edges: [
        GraphEdge(
          id: 'we',
          fromNodeId: 'w',
          toNodeId: 'es-up',
          lengthM: 30,
          bidirectional: true,
          geometryLocalM: [LocalPoint(0, 0), LocalPoint(30, 0)],
        ),
      ],
    );

    MultiFloorRoute routeVia({
      required String? transferMode,
      required String? transferFromNodeId,
      String floorName = '1F',
    }) => MultiFloorRoute(
      segments: [
        IndoorRouteSegment(
          floorId: floorName,
          floorName: floorName,
          route: const IndoorRoute(
            points: [],
            pointsLocalM: [LocalPoint(0, 0), LocalPoint(30, 0)],
            nodeIds: ['w', 'es-up'],
            edgeIds: ['we'],
            distanceMeters: 30,
          ),
          transferModeToNext: transferMode,
          transferFromNodeId: transferFromNodeId,
        ),
      ],
      totalDistanceMeters: 30,
      totalCostMeters: 30,
    );

    test('안내가 지목한 탑승점이면 그 노드 좌표로 고정한다', () {
      final held = routeBoardingHoldPoint(
        boardingNodeId: 'es-up',
        anchorFloorId: '1F',
        displayedFloorId: '1F',
        multiFloorRoute: routeVia(
          transferMode: 'escalator',
          transferFromNodeId: 'es-up',
        ),
        graph: escalatorGraph,
      );

      expect(held, isNotNull);
      expect(held!.eastM, 30);
      expect(held.northM, 0);
    });

    test('경로가 지목하지 않은 에스컬레이터 옆을 지나가는 것으로는 고정하지 않는다', () {
      // 그냥 걷고 있는 사용자의 마커를 세우면 안 된다.
      final held = routeBoardingHoldPoint(
        boardingNodeId: 'es-up',
        anchorFloorId: '1F',
        displayedFloorId: '1F',
        multiFloorRoute: routeVia(
          transferMode: 'escalator',
          transferFromNodeId: 'es-other',
        ),
        graph: escalatorGraph,
      );

      expect(held, isNull);
    });

    test('엘리베이터로 갈아타는 구간에서는 고정하지 않는다', () {
      final held = routeBoardingHoldPoint(
        boardingNodeId: 'es-up',
        anchorFloorId: '1F',
        displayedFloorId: '1F',
        multiFloorRoute: routeVia(
          transferMode: 'elevator',
          transferFromNodeId: 'es-up',
        ),
        graph: escalatorGraph,
      );

      expect(held, isNull);
    });

    test('안내 중이 아니면 고정하지 않는다', () {
      final held = routeBoardingHoldPoint(
        boardingNodeId: 'es-up',
        anchorFloorId: '1F',
        displayedFloorId: '1F',
        multiFloorRoute: null,
        graph: escalatorGraph,
      );

      expect(held, isNull);
    });

    test('앵커가 보고 있는 층과 다르면 고정하지 않는다', () {
      // 다른 층 노드 좌표에 고정하면 남의 층 자리를 가리킨다.
      final held = routeBoardingHoldPoint(
        boardingNodeId: 'es-up',
        anchorFloorId: '2F',
        displayedFloorId: '1F',
        multiFloorRoute: routeVia(
          transferMode: 'escalator',
          transferFromNodeId: 'es-up',
        ),
        graph: escalatorGraph,
      );

      expect(held, isNull);
    });
  });

  group('부착 게이트 — 층 판정기', () {
    final sample = AltitudeSample(
      timestampMs: 1000,
      pressureHpa: 1013.25,
      source: 'test',
    );

    test('붙이기 전 기압 샘플은 판정기에 들어가지 않는다', () {
      // 야외에서 오르내린 고도가 실내 판정의 0점을 흔들면, 건물에 들어서자마자
      // 있지도 않은 층 이동이 잡힌다.
      final session = newSession();

      final outcome = session.onAltitude(sample);

      expect(outcome.isEmpty, isTrue);
      expect(outcome.events, isEmpty);
      expect(session.escalator.smoothedAltitudeM, isNull);
    });

    test('떼어낸 뒤 기압 샘플도 무시한다', () {
      final session = attachedSession()..detach();

      final outcome = session.onAltitude(sample);

      expect(outcome.isEmpty, isTrue);
      expect(session.escalator.smoothedAltitudeM, isNull);
    });

    test('떼어낸 상태에서는 단계 전이를 내지 않는다', () {
      final session = attachedSession()..detach();

      expect(session.takePhaseChanges(), isEmpty);
      expect(session.boardingHoldPointM, isNull);
    });
  });

  group('고정 지점 다듬기', () {
    // 먼 노드로 스냅하면 마커가 눈에 띄게 뒤로 순간이동한다. 막으려던 것보다
    // 나쁜 그림이다.

    test('가까우면 그 노드로 고정한다', () {
      final held = clampBoardingHold(
        holdPoint: const PdrLocalPoint(20, 0),
        currentM: const PdrLocalPoint(17, 0),
      );

      expect(held?.eastM, 20);
    });

    test('멀면 지금 자리에 세운다', () {
      final held = clampBoardingHold(
        holdPoint: const PdrLocalPoint(20, 0),
        currentM: const PdrLocalPoint(5, 0),
      );

      expect(held?.eastM, 5, reason: '15m 뒤로 끌려가면 위치가 튄 것으로 읽힌다');
    });

    test('지금 위치를 모르면 노드를 그대로 쓴다', () {
      final held = clampBoardingHold(
        holdPoint: const PdrLocalPoint(20, 0),
        currentM: null,
      );

      expect(held?.eastM, 20);
    });
  });

  group('탑승 고정 — 수직 이동이 확인된 뒤', () {
    // 복도 끝에 하행 에스컬레이터가 붙어 있는 층. **경로는 주지 않는다** —
    // 경로가 지목한 탑승점과 일치할 때만 고정하던 시절에 마커가 흘러가던
    // 상황이 바로 이 배치다.
    const graph = FloorGraph(
      nodes: [
        GraphNode(id: 'w', type: 'corridor', xM: 0, yM: 0),
        GraphNode(
          id: 'es-dn',
          type: 'escalator',
          name: 'ES1-DN(TOB1)',
          xM: 20,
          yM: 0,
        ),
      ],
      edges: [
        GraphEdge(
          id: 'we',
          fromNodeId: 'w',
          toNodeId: 'es-dn',
          lengthM: 20,
          bidirectional: true,
          geometryLocalM: [LocalPoint(0, 0), LocalPoint(20, 0)],
        ),
      ],
    );

    /// 표준대기 고도 → 기압. 판정기 테스트와 같은 역함수를 쓴다.
    double pressureAt(double altitudeM) =>
        1013.25 * math.pow(1.0 - altitudeM / 44330.0, 1 / 0.190295);

    /// 에스컬레이터 앞까지 걸어간 뒤, 기압이 [toM]까지 내려가는 시계열을 넣는다.
    /// 반환값은 그동안 세션이 낸 단계들.
    List<EscalatorPhase> rideDown(
      IndoorGuidanceSession session, {
      required double toM,
      int seconds = 12,
    }) {
      var nowMs = 1000;
      // 탑승점 앞까지 걸어간다. 접근은 **여러 번** 알려야 한다 — 판정기는 한
      // 프레임 근접만으로는 단계를 올리지 않는다(스쳐 지나감 방어).
      for (final steps in [20, 23, 25, 27]) {
        nowMs += 1500;
        session.onSnapshot(_walkedEast(steps), timestampMs: nowMs);
      }
      final phases = <EscalatorPhase>[];

      void feed(double altitudeM) {
        nowMs += 1069;
        session.onAltitude(
          AltitudeSample(
            timestampMs: nowMs,
            pressureHpa: pressureAt(altitudeM),
            source: 'test',
          ),
        );
        // 화면과 같은 순서다 — 샘플을 넣은 뒤 단계를 꺼내 고정을 갱신한다.
        phases.addAll(session.takePhaseChanges().map((c) => c.phase));
      }

      // 기준선을 잡는 정지 구간.
      for (var i = 0; i < 5; i++) {
        feed(0);
      }
      final sampleCount = (seconds * 1000 / 1069).round();
      for (var i = 1; i <= sampleCount; i++) {
        feed(toM * i / sampleCount);
      }
      return phases;
    }

    IndoorGuidanceSession ridingSession() => newSession()
      ..attach(buildingId: 'b1')
      ..setContext(floorId: '1F', graph: graph, floorLabels: ['1F', 'B1'])
      ..setAnchor(_anchor());

    test('경로가 없어도 수직 이동이 잡히면 마커를 그 자리에 세운다', () {
      // 에스컬레이터 발판 위 진동이 걸음으로 세어져 마커가 앞 매장으로
      // 흘러가던 버그. 경로 조건이 어긋나도 고정은 걸려야 한다.
      final session = ridingSession();

      final phases = rideDown(session, toM: -2.0, seconds: 8);
      expect(phases, contains(EscalatorPhase.verticalMotionDetected));

      final held = session.position!.localM;
      expect(session.isPositionHeld, isTrue);

      // 탑승 뒤에도 걸음이 20걸음(14m) 더 들어온다.
      session.onSnapshot(_walkedEast(47), timestampMs: 40000);

      expect(session.position!.localM.eastM, held.eastM);
      expect(session.position!.localM.northM, held.northM);
    });

    test('고정 지점은 판정기가 고른 탑승 노드다', () {
      final session = ridingSession();

      rideDown(session, toM: -2.0, seconds: 8);

      expect(session.position!.localM.eastM, 20);
      expect(session.position!.localM.northM, 0);
    });

    test('판정이 취소되면 고정을 풀고 걸음을 다시 따라간다', () {
      final session = ridingSession();
      rideDown(session, toM: -2.0, seconds: 8);
      expect(session.isPositionHeld, isTrue);

      // 화면 쪽 출구(취소·되돌리기 정리)가 부르는 경로.
      session.clearBoardingHold();
      session.onSnapshot(_walkedEast(30), timestampMs: 40000);

      expect(session.isPositionHeld, isFalse);
      // 다시 보정 결과를 그대로 따라간다 — 고정된 노드 좌표가 아니다.
      final tracked = session.trackingResult!.previewPosition;
      expect(session.position!.localM.eastM, tracked.eastM);
      expect(session.position!.localM.northM, tracked.northM);
    });
  });

  group('경로 진행률', () {
    /// 복도(0,0)~(50,0)을 그대로 따라가는 경로.
    const route = IndoorRoute(
      points: [],
      pointsLocalM: [LocalPoint(0, 0), LocalPoint(50, 0)],
      nodeIds: ['w', 'e'],
      edgeIds: ['we'],
      distanceMeters: 50,
    );

    IndoorGuidanceSession routedSession() =>
        attachedSession()..setRouteSegment(route);

    test('코너를 돈 뒤에도 마커가 코너 직전 표시 진행률에 붙들리지 않는다', () {
      final session = newSession()
        ..attach(buildingId: 'b1')
        ..setContext(floorId: '1F', graph: _turnRouteGraph)
        ..setAnchor(_anchor(eastM: 0))
        ..setRouteSegment(_turnRoute);

      session.onSnapshot(_walkedNorthTurn(0), timestampMs: 0);
      session.updateProgress(
        session.trackingResult,
        previewSteps: 0,
        nowMs: 0,
      );

      for (var steps = 1; steps <= 14; steps += 1) {
        final result = session.onSnapshot(
          _walkedNorthTurn(steps),
          timestampMs: steps * 500,
        );
        session.updateProgress(
          result,
          previewSteps: steps,
          nowMs: steps * 500,
        );
      }

      final trackerPosition = session.trackingResult!.previewPosition;
      final markerPosition = session.position!.localM;
      expect(trackerPosition.northM, greaterThan(1));
      expect(markerPosition.northM, greaterThan(1));
    });

    test('교차점 통과 중에도 회색선 기준과 마커 위치를 분리한다', () {
      final session = newSession()
        ..attach(buildingId: 'b1')
        ..setContext(floorId: '1F', graph: _branchGraph)
        ..setAnchor(_anchor(eastM: 0))
        ..setRouteSegment(_branchRoute);

      var sawPendingDeviation = false;
      for (var steps = 0; steps <= 30; steps += 1) {
        final result = session.onSnapshot(
          _walkedNorthTurn(steps),
          timestampMs: steps * 500,
        );
        final update = session.updateProgress(
          result,
          previewSteps: steps,
          nowMs: steps * 500,
        );
        if (update.holdReason == 'pendingDeviation') {
          sawPendingDeviation = true;
          expect(session.position!.localM.northM, greaterThan(0));
        }
      }

      final trackerPosition = session.trackingResult!.previewPosition;
      final markerPosition = session.position!.localM;
      expect(sawPendingDeviation, isTrue);
      expect(session.displayProgress!.traveledM, closeTo(7, 0.8));
      expect(trackerPosition.northM, greaterThan(0));
      expect(markerPosition.northM, greaterThan(0));
    });

    test('길안내 중에는 후퇴 방지된 경로 투영점을 마커에 우선 표시한다', () {
      // 센서 보정 위치는 복도 중심선(y=0)에 있지만, 안내 경로의 표시선은
      // 같은 간선 위에서 y=2로 보정돼 있다고 가정한다. 예전 홈 통합처럼
      // previewPosition을 그대로 그리면 마커가 파란 안내선에서 벗어난다.
      const shiftedRoute = IndoorRoute(
        points: [],
        pointsLocalM: [LocalPoint(0, 2), LocalPoint(50, 2)],
        nodeIds: ['w', 'e'],
        edgeIds: ['we'],
        distanceMeters: 50,
      );
      final session = attachedSession()..setRouteSegment(shiftedRoute);

      final result = session.onSnapshot(_walkedEast(10), timestampMs: 1000);
      session.updateProgress(result, previewSteps: 10);

      final preview = session.trackingResult!.previewPosition;
      final marker = session.position!;
      expect(preview.northM, closeTo(0, 1e-9));
      expect(session.displayProgress!.projectedPoint, isNotNull);
      expect(marker.localM.northM, closeTo(2, 1e-9));
    });

    test('걸을수록 남은거리가 줄어든다', () {
      final session = routedSession();

      session.updateProgress(
        session.onSnapshot(_walkedEast(5), timestampMs: 1000),
        previewSteps: 5,
      );
      final after5 = session.displayProgress!.remainingM;

      session.updateProgress(
        session.onSnapshot(_walkedEast(20), timestampMs: 2000),
        previewSteps: 20,
      );
      final after20 = session.displayProgress!.remainingM;

      expect(after5, lessThan(50));
      expect(after20, lessThan(after5));
    });

    test('경로가 없으면 진행률을 내지 않는다', () {
      final session = attachedSession();

      final update = session.updateProgress(
        session.onSnapshot(_walkedEast(5), timestampMs: 1000),
        previewSteps: 5,
      );

      expect(update.hasProgress, isFalse);
      expect(session.displayProgress, isNull);
    });

    test('세그먼트를 갈아타면 진행거리 기준점을 새로 잡는다', () {
      // 남겨 두면 새 세그먼트에서는 창 밖 값이 되어 매 걸음 재획득이 켜진다.
      final session = routedSession();
      session.updateProgress(
        session.onSnapshot(_walkedEast(20), timestampMs: 1000),
        previewSteps: 20,
      );
      expect(session.displayProgress, isNotNull);

      session
        ..setRouteSegment(route)
        ..seedProgress(null);

      expect(session.displayProgress, isNull);
      expect(session.measuredProgress, isNull);
    });

    test('안내를 끝내면 진행률과 방향 상태를 모두 버린다', () {
      final session = routedSession();
      session.updateProgress(
        session.onSnapshot(_walkedEast(20), timestampMs: 1000),
        previewSteps: 20,
      );
      expect(session.displayProgress, isNotNull);

      session.clearProgress();

      expect(session.displayProgress, isNull);
      expect(session.travelDirectionState, TravelDirectionState.forward);
    });

    test('에스컬레이터 위에서는 진행률을 갱신하지 않는다', () {
      // 위치가 한 지점에 묶여 있어 그 투영은 "경로를 벗어났다"는 오판만 만들고,
      // 곧 층이 바뀔 자리에서 재탐색을 돌린다.
      final session = routedSession();
      session.updateProgress(
        session.onSnapshot(_walkedEast(5), timestampMs: 1000),
        previewSteps: 5,
      );
      final frozen = session.displayProgress!.remainingM;

      session.updateProgress(
        session.onSnapshot(_walkedEast(30), timestampMs: 2000),
        previewSteps: 30,
        onEscalator: true,
      );

      expect(session.displayProgress!.remainingM, frozen);
    });

    test('층이 바뀌어 고정이 풀려도 탑승 중이면 재탐색을 걸지 않는다', () {
      // 조기 층 전환이 `setContext`의 floorChanged 갈래에서 clearBoardingHold를
      // 부르면 `isPositionHeld`가 먼저 false가 된다. 그 뒤 리셋된 트래커의
      // 위치로 이탈 증거가 쌓여도, 탑승 중이면 재탐색이 나가면 안 된다.
      bool askedWhileWalkingOffRoute({required bool onEscalator}) {
        final session = newSession()
          ..attach(buildingId: 'b1')
          ..setContext(floorId: '1F', graph: _branchGraph)
          ..setAnchor(_anchor(eastM: 0))
          ..setRouteSegment(_branchRoute)
          // 층 전환이 부르는 것과 같은 경로다.
          ..clearBoardingHold();
        expect(session.isPositionHeld, isFalse);

        var asked = false;
        for (var steps = 0; steps <= 30; steps += 1) {
          final result = session.onSnapshot(
            _walkedNorthTurn(steps),
            timestampMs: steps * 500,
          );
          final update = session.updateProgress(
            result,
            previewSteps: steps,
            nowMs: steps * 500,
            onEscalator: onEscalator,
          );
          asked = asked || update.shouldReroute;
        }
        return asked;
      }

      expect(
        askedWhileWalkingOffRoute(onEscalator: false),
        isTrue,
        reason: '탑승 중이 아니면 같은 걸음이 재탐색을 건다',
      );
      expect(askedWhileWalkingOffRoute(onEscalator: true), isFalse);
    });

    test('경로 위를 정상적으로 걸으면 재탐색을 걸지 않는다', () {
      final session = routedSession();

      var asked = false;
      for (var steps = 1; steps <= 20; steps += 1) {
        final update = session.updateProgress(
          session.onSnapshot(
            _walkedEast(steps),
            timestampMs: 1000 + steps * 500,
          ),
          previewSteps: steps,
        );
        asked = asked || update.shouldReroute;
      }

      expect(asked, isFalse);
    });
  });

  group('층 경계', () {
    test('앵커가 다른 층에 있으면 보정을 돌리지 않는다', () {
      // 다른 층 기준점으로 이 층 복도에 스냅하면 마커가 남의 층을 걸어간다.
      final session = newSession()
        ..attach(buildingId: 'b1')
        ..setContext(floorId: '1F', graph: _corridorGraph)
        ..setAnchor(_anchor(floorId: '2F'));

      expect(session.onSnapshot(_walkedEast(10), timestampMs: 1000), isNull);
      expect(session.trackingResult, isNull);
    });

    test('층이 바뀌면 보정을 버린다', () {
      // 같은 local m 숫자가 층마다 다른 자리를 가리킨다.
      final session = attachedSession()
        ..onSnapshot(_walkedEast(20), timestampMs: 1000);
      expect(session.trackingResult, isNotNull);

      session.setContext(floorId: '2F', graph: _corridorGraph);

      expect(session.trackingResult, isNull);
      expect(session.position, isNull, reason: '앵커는 아직 1F에 있다');
    });

    test('같은 층을 다시 알려주는 것은 보정을 버리지 않는다', () {
      final session = attachedSession()
        ..onSnapshot(_walkedEast(20), timestampMs: 1000);
      final before = session.position!.localM.eastM;

      session.setContext(floorId: '1F', graph: _corridorGraph);

      expect(session.position?.localM.eastM, before);
    });
  });
}
