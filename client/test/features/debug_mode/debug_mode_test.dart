import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:indoor_pdr_core/indoor_pdr_core.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/features/debug_mode/debug_mode.dart';
import 'package:navigation_client/features/indoor_navigation/contract/calibration_state.dart';
import 'package:navigation_client/features/indoor_navigation/contract/pdr_anchor.dart';
import 'package:navigation_client/models/building/floor_graph.dart';
import 'package:navigation_client/models/building/floor_plan.dart';
import 'package:shared_preferences/shared_preferences.dart';

PdrSnapshot _snapshot() => const PdrSnapshot(
  position: PdrLocalPoint(2, 0),
  path: [PdrLocalPoint.zero, PdrLocalPoint(1, 0), PdrLocalPoint(2, 0)],
  steps: 2,
  distanceM: 2,
  orientationHeadingDeg: 90,
  walkingHeadingDeg: 90,
  hasHeading: true,
  preview: PdrPreview(
    position: PdrLocalPoint(2.2, 0),
    path: [PdrLocalPoint.zero, PdrLocalPoint(1.1, 0), PdrLocalPoint(2.2, 0)],
    steps: 2,
    distanceM: 2.2,
  ),
  quality: PdrQuality(
    state: PdrQualityState.healthy,
    warnings: [],
    features: PdrQualityFeatures(
      greenOrangeDistanceDivergencePct: 10,
      orangeStepRatio: 1,
      orangeOvercountLikely: false,
      pedometerUndercountSuspected: false,
      pedometerFlaggedSpanS: 0,
      headingStable: true,
      headingSource: 'test',
      magneticAccuracy: 'high',
      rotationHeadingAccuracyDeg: 1,
      cadenceHz: 1.5,
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
      walkDirConfidence: 0.8,
      headingConverged: true,
      headingSpreadDeg: 1.0,
    ),
  ),
);

const _anchor = PdrAnchor(
  floorId: '1F',
  anchorLocalM: PdrLocalPoint(10, 20),
  rotationDeg: 0,
  headingReference: HeadingReference.magneticNorth,
  requiresManualRotationCalibration: false,
  source: AnchorSource.userPin,
  confidence: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
  });

  test('heading 보정 노브는 디버그 모드가 켜져 있을 때만 흘러나온다', () async {
    final preferences = await SharedPreferences.getInstance();
    final controller = DebugModeController(preferences: preferences);
    await controller.ready;

    await controller.setHeadingOffsetDeg(12);
    // 디버그가 꺼져 있으면 일반 사용자와 같아야 한다 — 자편각 상수만 적용된다.
    expect(controller.headingOffsetDeg.value, 0);

    await controller.setEnabled(true);
    expect(controller.headingOffsetDeg.value, 12);

    // 상한 밖은 잘린다. 노브를 끝까지 밀어도 anchor가 뒤집히지 않는다.
    await controller.setHeadingOffsetDeg(1000);
    expect(
      controller.headingOffsetDeg.value,
      DebugModeController.headingOffsetLimitDeg,
    );

    // 현장에서 맞춘 값은 앱을 다시 켜도 남아야 한다 — 그게 다음 상수의 근거다.
    final restored = DebugModeController(preferences: preferences);
    await restored.ready;
    expect(
      restored.headingOffsetDeg.value,
      DebugModeController.headingOffsetLimitDeg,
    );

    controller.dispose();
    restored.dispose();
  });

  test(
    'debug settings load defaults and persist every display toggle',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final controller = DebugModeController(preferences: preferences);
      await controller.ready;

      expect(controller.enabled, isFalse);
      expect(controller.showGraphNodes, isTrue);
      expect(controller.showGraphEdges, isTrue);
      expect(controller.showRawPdrPath, isTrue);
      expect(controller.showConfirmedPdrPath, isTrue);
      expect(controller.showMapMatchedPdrPath, isTrue);
      expect(controller.showRoninPdrPath, isTrue);
      expect(controller.showCardinalCross, isTrue);

      await controller.setEnabled(true);
      await controller.setShowGraphNodes(false);
      await controller.setShowGraphEdges(false);
      await controller.setShowRawPdrPath(false);
      await controller.setShowConfirmedPdrPath(false);
      await controller.setShowMapMatchedPdrPath(false);
      await controller.setShowRoninPdrPath(false);
      await controller.setShowCardinalCross(false);

      final restored = DebugModeController(preferences: preferences);
      await restored.ready;
      expect(restored.enabled, isTrue);
      expect(restored.showGraphNodes, isFalse);
      expect(restored.showGraphEdges, isFalse);
      expect(restored.showRawPdrPath, isFalse);
      expect(restored.showConfirmedPdrPath, isFalse);
      expect(restored.showMapMatchedPdrPath, isFalse);
      expect(restored.showRoninPdrPath, isFalse);
      expect(restored.showCardinalCross, isFalse);

      controller.dispose();
      restored.dispose();
    },
  );

  test('더현대 정북은 다섯 랜드마크 대응으로 회전과 반전을 함께 결정한다', () {
    final calibration = cardinalCalibrationForBuilding('thehyundai-seoul');

    expect(calibration, isNotNull);
    expect(calibration!.landmarkCount, 5);
    expect(calibration.reflected, isTrue);
    expect(calibration.rmsErrorPx, lessThan(12));
    expect(calibration.northMapBearingDeg, closeTo(308.9, 0.2));
    expect(cardinalCalibrationForBuilding('unknown'), isNull);
  });

  test('현재 도면의 WGS84 랜드마크가 있으면 그 좌표로 정북을 다시 맞춘다', () {
    StorePolygon store(String name, double latitude, double longitude) =>
        StorePolygon(
          id: name,
          name: name,
          polygon: const [],
          centroid: LatLng(latitude, longitude),
        );

    final calibration = cardinalCalibrationForBuilding(
      'thehyundai-seoul',
      floorPlan: FloorPlan(
        pois: const [],
        stores: [
          store('보테가 베네타', 37.52539279890545, 126.92820599451144),
          store('불가리', 37.525378771370065, 126.92839318128878),
          store('티파니앤코', 37.5259072870112, 126.92861936102356),
          store('루이비통', 37.525630957187424, 126.9289095728308),
          store('프라다', 37.5253297978992, 126.92882557288411),
        ],
      ),
    );

    expect(calibration, isNotNull);
    expect(calibration!.landmarkCount, 5);
    expect(calibration.northMapBearingDeg, closeTo(305.2, 0.2));
  });

  testWidgets('방위 격자는 지도와 별개인 전체 화면 painter로 표시된다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SizedBox.expand(
          child: CardinalGridOverlay(
            northMapBearingDeg: 305,
            cameraBearingDeg: 90,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('cardinal-grid-overlay')), findsOneWidget);
    expect(
      cardinalScreenAngleDeg(northMapBearingDeg: 305, cameraBearingDeg: 90),
      215,
    );
  });

  test(
    'graph overlay marks the matched edge and its endpoint nodes active',
    () {
      final graph = FloorGraph(
        nodes: const [
          GraphNode(id: 'A', type: 'corridor', xM: 0, yM: 0),
          GraphNode(id: 'B', type: 'corridor', xM: 10, yM: 0),
          GraphNode(id: 'C', type: 'corridor', xM: 20, yM: 0),
        ],
        edges: const [
          GraphEdge(
            id: 'AB',
            fromNodeId: 'A',
            toNodeId: 'B',
            lengthM: 10,
            bidirectional: true,
            geometryLocalM: [],
          ),
          GraphEdge(
            id: 'BC',
            fromNodeId: 'B',
            toNodeId: 'C',
            lengthM: 10,
            bidirectional: true,
            geometryLocalM: [],
          ),
        ],
      );

      final overlay = buildDebugMapOverlay(graph, activeEdgeIds: {'AB'});

      expect(overlay.nodes, hasLength(3));
      expect(overlay.edges, hasLength(2));
      expect(
        overlay.nodes.where((node) => node.active).map((node) => node.id),
        containsAll(<String>['A', 'B']),
      );
      expect(
        overlay.nodes.singleWhere((node) => node.id == 'C').active,
        isFalse,
      );
      expect(
        overlay.edges.singleWhere((edge) => edge.id == 'AB').active,
        isTrue,
      );
      expect(
        overlay.edges.singleWhere((edge) => edge.id == 'BC').active,
        isFalse,
      );
    },
  );

  test('PDR trail survives stop calibration and clears on the next start', () {
    final snapshot = _snapshot();
    final state = DebugPdrTrailState()
      ..recordSnapshot(snapshot)
      ..recordCalibration(
        const CalibrationStatus(
          phase: CalibrationPhase.calibrated,
          headingReference: HeadingReference.magneticNorth,
          requiresManualRotationCalibration: false,
          anchor: _anchor,
        ),
      );

    // stopGuidance가 보내는 uncalibrated 상태는 마지막 선을 지우지 않는다.
    state.recordCalibration(const CalibrationStatus.uncalibrated());
    expect(state.snapshot, same(snapshot));
    expect(state.anchor, same(_anchor));

    // 다음 PDR 시작 시점에만 이전 세션 표시를 초기화한다.
    state.beginNewSession();
    expect(state.snapshot, isNull);
    expect(state.anchor, isNull);
  });

  testWidgets('debug toast floats compactly above the map controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDebugToast(
                context,
                message: 'PDR 세션이 종료됐습니다.',
                bottomOffset: 124,
              ),
              child: const Text('show'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pump();

    final toast = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(toast.behavior, SnackBarBehavior.floating);
    expect((toast.margin! as EdgeInsets).bottom, 124);
    expect(find.text('PDR 세션이 종료됐습니다.'), findsOneWidget);
  });

  testWidgets('advanced options appear only after debug mode is enabled', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final controller = DebugModeController(preferences: preferences);
    await controller.ready;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDebugModeSettingsSheet(context, controller),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(find.text('고급 표시 옵션'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('debug-mode-enabled')));
    await tester.pumpAndSettle();
    expect(find.text('고급 표시 옵션'), findsOneWidget);
    expect(find.text('전체 화면 방위 격자'), findsOneWidget);
    expect(find.text('노드 이름'), findsNothing);
    expect(find.text('간선 이름'), findsNothing);
    expect(find.text('Raw 근접 경로'), findsOneWidget);
    expect(find.text('확정 PDR 경로'), findsOneWidget);
    expect(find.text('RoNIN 보폭 경로'), findsOneWidget);
    expect(find.text('지도 부착 경로'), findsOneWidget);

    controller.dispose();
  });
}
