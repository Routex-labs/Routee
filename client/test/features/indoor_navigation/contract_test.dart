import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/features/indoor_navigation/contract/indoor_navigation_contract.dart';
import 'package:navigation_client/domain/geo/geo_transform.dart';

/// 계약만 보고 만든 fake 구현. UI팀이 로직 완성을 기다리지 않고 이 계약으로
/// 병렬 작업할 수 있음을 보인다(Phase 1.5).
class FakeIndoorNavigation implements IndoorNavigationController {
  final _snapshots = StreamController<PdrSnapshot>.broadcast();
  final _calibration = StreamController<CalibrationStatus>.broadcast();
  final _runtimeStatuses = StreamController<PdrRuntimeStatus>.broadcast();
  final _altitudes = StreamController<AltitudeSample>.broadcast();
  final _rawMotion = StreamController<RawMotionActivity>.broadcast();

  PdrSnapshot? _current;
  CalibrationStatus _calib = const CalibrationStatus.uncalibrated();
  final PdrRuntimeStatus _runtimeStatus = const PdrRuntimeStatus.idle();
  final List<String> log = [];

  @override
  Stream<PdrSnapshot> get snapshots => _snapshots.stream;

  @override
  PdrSnapshot? get currentSnapshot => _current;

  @override
  Stream<CalibrationStatus> get calibration => _calibration.stream;

  @override
  CalibrationStatus get currentCalibration => _calib;

  @override
  Stream<PdrRuntimeStatus> get runtimeStatuses => _runtimeStatuses.stream;

  @override
  Stream<RawMotionActivity> get rawMotion => _rawMotion.stream;

  @override
  PdrRuntimeStatus get currentRuntimeStatus => _runtimeStatus;

  @override
  String? get currentFloorId => _floorId;

  String? _floorId;

  @override
  Stream<AltitudeSample> get altitudeSamples => _altitudes.stream;

  @override
  AltitudeSample? get currentAltitude => null;

  @override
  AltimeterStatus get altimeterStatus => const AltimeterStatus.unavailable();

  @override
  bool get isHeadingConverged => true;

  @override
  Map<String, Object?>? get lastPedometerFinalizeInfo => null;

  @override
  Future<void> startGuidance({required String floorId}) async {
    _floorId = floorId;
    log.add('start:$floorId');
  }

  @override
  Future<void> stopGuidance() async => log.add('stop');

  @override
  Future<void> confirmAnchorByPin({
    required PdrLocalPoint floorPointM,
    PdrToFloorAxes axes = const PdrToFloorAxes.identity(),
    String? floorId,
  }) async {
    log.add('pin:${floorPointM.eastM},${floorPointM.northM}');
  }

  @override
  Future<void> confirmAnchorByFloorDirection({
    required PdrLocalPoint floorDirection,
  }) async {
    log.add('heading:${floorDirection.eastM},${floorDirection.northM}');
  }

  @override
  Future<void> changeFloor({required String floorId}) async {
    _floorId = floorId;
    log.add('floor:$floorId');
  }

  @override
  Future<void> applyVerticalTransfer({
    required String floorId,
    required PdrLocalPoint anchorLocalM,
    PdrToFloorAxes? axes,
  }) async {
    log.add('transfer:$floorId@${anchorLocalM.eastM},${anchorLocalM.northM}');
  }

  @override
  Future<void> pauseStepTracking() async => log.add('pauseSteps');

  @override
  Future<void> resumeStepTracking() async => log.add('resumeSteps');

  @override
  Future<void> onAppBackgrounded() async => log.add('backgrounded');

  @override
  Future<void> onAppForegrounded() async => log.add('foregrounded');

  // 테스트 구동용.
  void pushCalibration(CalibrationStatus s) {
    _calib = s;
    _calibration.add(s);
  }

  void dispose() {
    _snapshots.close();
    _calibration.close();
    _runtimeStatuses.close();
    _altitudes.close();
  }
}

void main() {
  group('계약 conformance', () {
    test('fake는 View와 Intents를 모두 만족한다', () {
      final nav = FakeIndoorNavigation();
      expect(nav, isA<IndoorNavigationView>());
      expect(nav, isA<IndoorNavigationIntents>());
      nav.dispose();
    });

    test('UI intents가 로직으로 전달된다', () async {
      final nav = FakeIndoorNavigation();
      await nav.startGuidance(floorId: 'F1');
      await nav.confirmAnchorByPin(floorPointM: const PdrLocalPoint(3, 4));
      await nav.changeFloor(floorId: 'F2');
      await nav.stopGuidance();
      expect(nav.log, ['start:F1', 'pin:3.0,4.0', 'floor:F2', 'stop']);
      nav.dispose();
    });

    test('runtime 초기 상태는 idle이고 warning이 없다', () {
      final nav = FakeIndoorNavigation();
      expect(nav.currentRuntimeStatus.state, PdrRuntimeState.idle);
      expect(nav.currentRuntimeStatus.warnings, isEmpty);
      nav.dispose();
    });

    test('미보정 상태에서는 위치를 렌더하지 않는다', () {
      const status = CalibrationStatus.uncalibrated();
      expect(status.canRenderPosition, isFalse);
      expect(status.phase, CalibrationPhase.uncalibrated);
    });
  });

  group('FloorCoordinateTransform', () {
    PdrAnchor anchor({
      PdrLocalPoint origin = PdrLocalPoint.zero,
      double rotationDeg = 0,
    }) => PdrAnchor(
      floorId: 'F1',
      anchorLocalM: origin,
      rotationDeg: rotationDeg,
      headingReference: HeadingReference.magneticNorth,
      requiresManualRotationCalibration: false,
      source: AnchorSource.userPin,
      confidence: 1,
    );

    test('회전·평행이동이 없으면 항등이다', () {
      final t = FloorCoordinateTransform(anchor());
      final p = t.toFloor(const PdrLocalPoint(2, 5));
      expect(p.eastM, closeTo(2, 1e-9));
      expect(p.northM, closeTo(5, 1e-9));
    });

    test('평행이동만 적용한다', () {
      final t = FloorCoordinateTransform(
        anchor(origin: const PdrLocalPoint(10, -3)),
      );
      final p = t.toFloor(const PdrLocalPoint(1, 2));
      expect(p.eastM, closeTo(11, 1e-9));
      expect(p.northM, closeTo(-1, 1e-9));
    });

    test('나침반 90도 보정은 북쪽 벡터를 동쪽으로 돌린다', () {
      final t = FloorCoordinateTransform(anchor(rotationDeg: 90));
      final p = t.toFloor(const PdrLocalPoint(0, 1));
      expect(p.eastM, closeTo(1, 1e-9));
      expect(p.northM, closeTo(0, 1e-9));
    });

    test('회전된 floor 방향을 axes 역변환해 PDR bearing으로 복원한다', () {
      const axes = PdrToFloorAxes(
        eastToX: 0,
        northToX: -1,
        eastToY: 1,
        northToY: 0,
      );

      final pdrDirection = axes.inverseApply(const PdrLocalPoint(0, 1));

      expect(pdrDirection, isNotNull);
      expect(pdrBearingForDirection(pdrDirection!), closeTo(90, 1e-9));
    });

    test('화면 방향은 camera bearing을 반영해 floor 방향으로 바뀐다', () {
      const axes = PdrToFloorAxes(
        eastToX: 1,
        northToX: 0,
        eastToY: 0,
        northToY: -1,
      );

      final floorDirection = floorDirectionForScreenDirection(
        cameraBearingDeg: 30,
        screenClockwiseOffsetDeg: 90,
        axes: axes,
      );
      final pdrDirection = axes.inverseApply(floorDirection)!;

      expect(pdrBearingForDirection(pdrDirection), closeTo(120, 1e-9));
    });

    test('heading 회전 차이는 360도 경계에서 최단각으로 정규화한다', () {
      expect(normalizePdrRotation(1 - 359), closeTo(2, 1e-9));
      expect(normalizePdrRotation(359 - 1), closeTo(-2, 1e-9));
    });

    test('남쪽으로 증가하는 floor y축으로 자북 PDR를 바꾼다', () {
      final t = FloorCoordinateTransform(
        anchor(),
        axes: const PdrToFloorAxes(
          eastToX: 1,
          northToX: 0,
          eastToY: 0,
          northToY: -1,
        ),
      );

      // PDR의 북쪽 +5m는 이 평면도에서는 y=-5m여야 한다.
      final p = t.toFloor(const PdrLocalPoint(2, 5));
      expect(p.eastM, closeTo(2, 1e-9));
      expect(p.northM, closeTo(-5, 1e-9));
    });

    test('회전 후 평행이동 순서로 왕복이 성립한다', () {
      final t = FloorCoordinateTransform(
        anchor(origin: const PdrLocalPoint(5, 5), rotationDeg: 90),
      );
      final p = t.toFloor(const PdrLocalPoint(2, 0));
      // east 2m → bearing +90° 보정 → south 2m → +anchor(5,5)
      expect(p.eastM, closeTo(5, 1e-9));
      expect(p.northM, closeTo(3, 1e-9));
    });
  });
}
