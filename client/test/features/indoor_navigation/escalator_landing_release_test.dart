import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_pdr_core/indoor_pdr_core.dart';
import 'package:navigation_client/features/indoor_navigation/application/indoor_guidance_session.dart';
import 'package:navigation_client/features/indoor_navigation/contract/altitude_sample.dart';
import 'package:navigation_client/features/indoor_navigation/contract/pdr_anchor.dart';
import 'package:navigation_client/models/building/building_graph.dart';
import 'package:navigation_client/models/building/floor_graph.dart';
import 'package:navigation_client/models/route/indoor_route.dart';

/// **하차가 고정을 푼다**는 계약. 그리고 층을 갈아타도 학습한 heading 보정각이
/// 이어진다는 계약.
///
/// 두 증상이 실기기에서 함께 났다.
///
/// 1. 에스컬레이터에서 내렸는데 마커가 도착 노드에 붙어 안 따라온다.
/// 2. 타는 동안과 내리는 순간 삼각형이 사방으로 돈다.
///
/// (1)의 원인은 고정을 푸는 유일한 자리가 화면(`_endEscalatorRide`)이었던 것이다.
/// 확정이 도착 노드를 못 찾고 일찍 돌아가거나, 조기 전환 없이 `landed`에서 바로
/// 오거나, 전환이 겹쳐 막히거나, 화면이 이미 닫힌 경우 그 호출이 통째로 빠지고
/// **마커가 영영 붙은 채** 남는다. 고정을 소유하는 것은 이 세션이므로 푸는 것도
/// 세션이 한다.
///
/// (2)는 여기서 보지 않는다 — 활강 중 방향의 주인은 화면이고, 보정각 인계는
/// `corridor_heading_bias_carry_test.dart`가 검사한다.
///
/// 탑승점을 **지나서도** 복도가 이어진다. 고정이 풀렸는지 보려면 마커가 갈 수
/// 있는 자리가 탑승 노드 너머에 있어야 한다 — 복도가 노드에서 끝나면 풀려도
/// 그 자리에 멈춰 있어 두 상태를 구분할 수 없다.
const _f1Graph = FloorGraph(
  nodes: [
    GraphNode(id: 'a', type: 'corridor', xM: 0, yM: 0),
    GraphNode(id: 'es', type: 'escalator', name: 'ES1-DN(TOB1)', xM: 7, yM: 0),
    GraphNode(id: 'past', type: 'corridor', xM: 25, yM: 0),
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
      id: 'past-es',
      fromNodeId: 'es',
      toNodeId: 'past',
      lengthM: 18,
      bidirectional: true,
      geometryLocalM: [LocalPoint(7, 0), LocalPoint(25, 0)],
    ),
  ],
);

const _f1Route = IndoorRoute(
  points: [],
  pointsLocalM: [LocalPoint(0, 0), LocalPoint(7, 0)],
  nodeIds: ['a', 'es'],
  edgeIds: ['ab'],
  distanceMeters: 7,
);

const _multi = MultiFloorRoute(
  segments: [
    IndoorRouteSegment(
      floorId: '1F',
      floorName: '1F',
      route: _f1Route,
      transferModeToNext: 'escalator',
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

/// [bearingDeg] 방향으로 곧게 걷는 원시 PDR 경로. 복도 방위와 다르게 주면 그
/// 차이가 곧 tracker가 학습해야 할 보정각이다.
PdrSnapshot _walk(int steps, {double bearingDeg = 90}) {
  final radians = bearingDeg * math.pi / 180;
  final east = math.sin(radians);
  final north = math.cos(radians);
  final path = [
    for (var index = 0; index <= steps; index += 1)
      PdrLocalPoint(index * 0.7 * east, index * 0.7 * north),
  ];
  return PdrSnapshot(
    position: path.last,
    path: path,
    steps: steps,
    distanceM: steps * 0.7,
    orientationHeadingDeg: bearingDeg,
    walkingHeadingDeg: bearingDeg,
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

const _f1Anchor = PdrAnchor(
  floorId: '1F',
  anchorLocalM: PdrLocalPoint(0, 0),
  rotationDeg: 0,
  headingReference: HeadingReference.magneticNorth,
  requiresManualRotationCalibration: false,
  source: AnchorSource.userPin,
  confidence: 1,
);

double _pressureAt(double altitudeM) =>
    1013.25 * math.pow(1.0 - altitudeM / 44330.0, 1 / 0.190295);

void main() {
  final now = DateTime(2026, 8, 27, 12);

  IndoorGuidanceSession boardedSession() {
    final session = IndoorGuidanceSession(now: () => now)
      ..attach(buildingId: 'b1')
      ..setContext(floorId: '1F', graph: _f1Graph, floorLabels: ['1F', 'B1'])
      ..setAnchor(_f1Anchor)
      ..setRoute(_multi)
      ..setRouteSegment(_f1Route);
    for (var steps = 1; steps <= 10; steps += 1) {
      session.onSnapshot(_walk(steps), timestampMs: steps * 700);
    }
    return session;
  }

  /// [session]에 기압 시계열을 흘려 하차까지 태운다. 확정 사건을 돌려준다.
  EscalatorAltitudeOutcome rideDown(
    IndoorGuidanceSession session, {
    required bool revert,
  }) {
    var atMs = 7000;
    var last = const EscalatorAltitudeOutcome();
    void altitude(double altitudeM) {
      atMs += 1069;
      final outcome = session.onAltitude(
        AltitudeSample(
          timestampMs: atMs,
          pressureHpa: _pressureAt(altitudeM),
          source: 'test',
        ),
      );
      if (!outcome.isEmpty) last = outcome;
      session.takePhaseChanges();
    }

    for (var index = 0; index < 5; index++) {
      altitude(0);
    }
    for (var index = 1; index <= 20; index++) {
      altitude(-5.0 * index / 20);
    }
    if (revert) {
      // 내려갔다 그대로 되돌아온다 — 판정기가 취소를 낸다.
      for (var index = 20; index >= 0; index--) {
        altitude(-5.0 * index / 20);
      }
      for (var index = 0; index < 8; index++) {
        altitude(0);
      }
    } else {
      for (var index = 0; index < 8; index++) {
        altitude(-5.0);
      }
    }
    return last;
  }

  group('하차가 고정을 푼다', () {
    test('확정이 나면 화면이 손대지 않아도 세션이 고정을 푼다', () {
      final session = boardedSession();
      expect(
        session.isPositionHeld,
        isTrue,
        reason: '탑승점에 서 있으면 붙들려 있어야 한다',
      );

      final outcome = rideDown(session, revert: false);

      expect(outcome.confirmed, isNotNull, reason: '하차가 확정돼야 하는 시계열이다');
      // 화면의 `clearBoardingHold()`를 **부르지 않는다.** 그 호출이 빠지는 길이
      // 실제로 여럿이라, 세션 혼자서 풀려야 한다.
      expect(session.isPositionHeld, isFalse);
      expect(session.boardingHoldPointM, isNull);
      expect(session.isNearRouteBoarding, isFalse);
    });

    test('확정 뒤 걸으면 마커가 탑승 노드를 떠난다', () {
      // 화면의 층 교체·리셋을 **일부러 넣지 않는다.** 그것들도 고정을 풀기
      // 때문에, 넣으면 이 테스트가 확정 해제를 검사하지 못한다. 실기기에서
      // 마커가 노드에 붙어 있던 것이 정확히 그 호출들이 빠진 상태였다.
      final session = boardedSession();
      rideDown(session, revert: false);
      final pinned = session.position!.localM;

      var atMs = 60000;
      for (var steps = 11; steps <= 16; steps += 1) {
        atMs += 700;
        session.onSnapshot(_walk(steps), timestampMs: atMs);
      }

      expect(session.position!.localM.eastM, greaterThan(pinned.eastM + 1.0));
    });

    test('취소도 같은 자리에서 푼다', () {
      final session = boardedSession();
      final outcome = rideDown(session, revert: true);

      expect(outcome.cancelled, isNotNull);
      expect(session.isPositionHeld, isFalse);
    });
  });
}
