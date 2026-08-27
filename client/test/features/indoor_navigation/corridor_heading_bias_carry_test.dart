import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_pdr_core/indoor_pdr_core.dart';
import 'package:navigation_client/features/indoor_navigation/application/indoor_guidance_session.dart';
import 'package:navigation_client/features/indoor_navigation/contract/pdr_anchor.dart';
import 'package:navigation_client/models/building/floor_graph.dart';
import 'package:navigation_client/models/route/indoor_route.dart';

/// **학습한 heading 보정각은 층을 갈아타도 이어진다**는 계약.
///
/// 보정각은 층이 아니라 **기기와 건물**의 성질이다 — 철골이 나침반을 얼마나 틀어
/// 놓는가. 그래서 층 이동에서 앵커의 회전값을 물려받는 것과 같은 이유로 이 값도
/// 물려받아야 한다.
///
/// 안 물려받으면 실기기에서 이렇게 보였다. 에스컬레이터에서 내리는 순간 tracker가
/// 새로 서면서 학습해 둔 각(최대 `headingBiasLimitDeg` 60°)이 한 프레임에 0으로
/// 사라지고, 그 뒤 `headingCorrectionMinEvidenceM` 7m를 걷는 동안 다시 차오른다.
/// 그동안 마커의 삼각형이 계속 돌아간다.
///
/// 다만 **frame이 같을 때만** 옮긴다. 보정각은 floor bearing에서 잰 값이라 앵커의
/// 회전값이나 축이 바뀌면 같은 숫자가 다른 각을 뜻한다.
const _eastCorridor = FloorGraph(
  nodes: [
    GraphNode(id: 'a', type: 'corridor', xM: 0, yM: 0),
    GraphNode(id: 'b', type: 'corridor', xM: 30, yM: 0),
  ],
  edges: [
    GraphEdge(
      id: 'ab',
      fromNodeId: 'a',
      toNodeId: 'b',
      lengthM: 30,
      bidirectional: true,
      geometryLocalM: [LocalPoint(0, 0), LocalPoint(30, 0)],
    ),
  ],
);

const _eastRoute = IndoorRoute(
  points: [],
  pointsLocalM: [LocalPoint(0, 0), LocalPoint(30, 0)],
  nodeIds: ['a', 'b'],
  edgeIds: ['ab'],
  distanceMeters: 30,
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
PdrSnapshot _walk(int steps, {required double bearingDeg}) {
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

const _anchor = PdrAnchor(
  floorId: '1F',
  anchorLocalM: PdrLocalPoint(0, 0),
  rotationDeg: 0,
  headingReference: HeadingReference.magneticNorth,
  requiresManualRotationCalibration: false,
  source: AnchorSource.userPin,
  confidence: 1,
);

/// 하차 앵커. 회전값을 **물려받으므로**(`applyVerticalTransfer`) frame이 같다.
const _transferredAnchor = PdrAnchor(
  floorId: 'B1',
  anchorLocalM: PdrLocalPoint(0, 0),
  rotationDeg: 0,
  headingReference: HeadingReference.magneticNorth,
  requiresManualRotationCalibration: false,
  source: AnchorSource.verticalTransfer,
  confidence: 0.7,
);

/// frame이 다른 앵커. 회전값이 달라 같은 숫자가 다른 각을 뜻한다.
const _rotatedAnchor = PdrAnchor(
  floorId: 'B1',
  anchorLocalM: PdrLocalPoint(0, 0),
  rotationDeg: 35,
  headingReference: HeadingReference.magneticNorth,
  requiresManualRotationCalibration: false,
  source: AnchorSource.verticalTransfer,
  confidence: 0.7,
);

void main() {
  final now = DateTime(2026, 8, 27, 12);

  /// 복도는 동쪽(90°)인데 원시 PDR은 80°로 걷는다. 그 10°가 학습할 보정각이다.
  IndoorGuidanceSession learnedBiasSession() {
    final session = IndoorGuidanceSession(now: () => now)
      ..attach(buildingId: 'b1')
      ..setContext(
        floorId: '1F',
        graph: _eastCorridor,
        floorLabels: ['1F', 'B1'],
      )
      ..setAnchor(_anchor)
      ..setRouteSegment(_eastRoute);
    for (var steps = 1; steps <= 30; steps += 1) {
      session.onSnapshot(
        _walk(steps, bearingDeg: 80),
        timestampMs: steps * 700,
      );
    }
    return session;
  }

  test('먼저 복도 방위와의 차이만큼 보정각을 학습한다', () {
    final session = learnedBiasSession();
    expect(session.trackingResult!.headingBiasDeg, closeTo(10, 0.5));
  });

  test('층 이동으로 tracker가 새로 서도 보정각이 0으로 사라지지 않는다', () {
    final session = learnedBiasSession();
    final learned = session.trackingResult!.headingBiasDeg;

    // 화면이 하차에서 하는 일 그대로 — 층 컨텍스트를 갈고 보정을 리셋한 뒤
    // 도착 노드로 앵커를 옮긴다.
    session
      ..setContext(floorId: 'B1', graph: _eastCorridor, floorLabels: [
        '1F',
        'B1',
      ])
      ..resetTracking()
      ..setAnchor(_transferredAnchor)
      ..setRouteSegment(_eastRoute);
    session.onSnapshot(_walk(0, bearingDeg: 80), timestampMs: 40000);

    expect(session.trackingResult!.headingBiasDeg, closeTo(learned, 0.01));
  });

  test('frame이 다르면 물려받지 않는다', () {
    final session = learnedBiasSession();

    // 위 테스트와 **앵커 하나만** 다르다. 회전값이 달라 같은 숫자가 다른 각을
    // 뜻하므로, 그대로 옮기면 삼각형이 그 차이만큼 틀어진 채 고정된다.
    session
      ..setContext(floorId: 'B1', graph: _eastCorridor, floorLabels: [
        '1F',
        'B1',
      ])
      ..resetTracking()
      ..setAnchor(_rotatedAnchor)
      ..setRouteSegment(_eastRoute);
    session.onSnapshot(_walk(0, bearingDeg: 80), timestampMs: 40000);

    expect(session.trackingResult!.headingBiasDeg, 0);
  });
}
