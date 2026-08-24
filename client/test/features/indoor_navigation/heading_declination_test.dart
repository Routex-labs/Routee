/// 자편각 부호와 현장 보정 노브의 검증 기준.
///
/// 부호를 뒤집으면 오차가 두 배가 되므로 "진북 = 자북 + 편각"을 여기서 못 박는다.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/features/indoor_navigation/application/indoor_navigation_controller.dart';
import 'package:navigation_client/features/indoor_navigation/contract/indoor_navigation_contract.dart';
import 'package:navigation_client/features/indoor_navigation/platform/native_pdr_event.dart';
import 'package:navigation_client/features/indoor_navigation/platform/pdr_motion_source.dart';

class _FakeSource implements PdrMotionSource {
  final _controller = StreamController<NativePdrEvent>.broadcast();

  @override
  Stream<NativePdrEvent> get events => _controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<int?> resetPedometer() async => 1;

  @override
  Future<Map<String, Object?>?> finalizePedometer() async => null;

  @override
  Future<void> dispose() async => _controller.close();

  void emitMagneticHeading() {
    final event = NativePdrEvent.tryParse({
      'source': 'ios_core_motion',
      'kind': 'motion',
      'stepSessionId': 1,
      'fusedHeadingDeg': 0.0,
      'headingStable': true,
      'headingSource': 'device_motion/xMagneticNorthZVertical',
      'motionTimestamp': 1000.0,
    });
    if (event != null) _controller.add(event);
  }
}

PdrAnchor _anchor(double rotationDeg) => PdrAnchor(
  floorId: '1F',
  anchorLocalM: PdrLocalPoint.zero,
  rotationDeg: rotationDeg,
  headingReference: HeadingReference.magneticNorth,
  requiresManualRotationCalibration: false,
  source: AnchorSource.userPin,
  confidence: 1,
);

void main() {
  group('자편각 상수', () {
    test('서울은 자북이 진북보다 서쪽이라 음수다', () {
      expect(magneticDeclinationDeg, lessThan(0));
      // WMM-2025가 유효한 동안(2029말)에는 이 범위를 벗어날 수 없다.
      expect(magneticDeclinationDeg, inInclusiveRange(-10, -8));
    });

    test('진방위 = 자방위 + 편각', () {
      final transform = FloorCoordinateTransform(
        _anchor(magneticDeclinationDeg),
      );
      // 나침반이 "북쪽(0°)"이라 말할 때 실제로 향한 진방위는 편각만큼 어긋나 있다.
      expect(
        transform.toFloorBearing(0),
        closeTo(normalizePdrBearing(magneticDeclinationDeg), 1e-9),
      );
      expect(transform.toFloorBearing(0), greaterThan(340));
    });

    test('부호를 뒤집으면 오차가 두 배가 된다', () {
      final right = FloorCoordinateTransform(
        _anchor(magneticDeclinationDeg),
      ).toFloorBearing(90);
      final flipped = FloorCoordinateTransform(
        _anchor(-magneticDeclinationDeg),
      ).toFloorBearing(90);
      expect(
        normalizePdrRotation(flipped - right),
        closeTo(-2 * magneticDeclinationDeg, 1e-9),
      );
    });

    test('0/360을 넘겨도 정규화된 bearing이 나온다', () {
      final transform = FloorCoordinateTransform(
        _anchor(magneticDeclinationDeg),
      );
      for (final magnetic in [0.0, 5.0, 180.0, 355.0, 359.9]) {
        final floor = transform.toFloorBearing(magnetic);
        expect(floor, inInclusiveRange(0, 360));
        expect(
          normalizePdrRotation(floor - (magnetic + magneticDeclinationDeg)),
          closeTo(0, 1e-9),
          reason: '자방위 $magnetic°에서 편각만큼만 돌아야 한다',
        );
      }
    });

    test('normalizePdrRotation은 -180 이상 180 미만으로 접는다', () {
      expect(
        normalizePdrRotation(magneticDeclinationDeg + 360),
        closeTo(magneticDeclinationDeg, 1e-9),
      );
      expect(normalizePdrRotation(190), closeTo(-170, 1e-9));
      expect(normalizePdrRotation(-190), closeTo(170, 1e-9));
    });
  });

  group('현장 보정 노브', () {
    late _FakeSource source;
    late ValueNotifier<double> offset;
    late IndoorNavigationDriver driver;

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    setUp(() async {
      source = _FakeSource();
      offset = ValueNotifier<double>(0);
      driver = IndoorNavigationDriver(source: source, headingOffsetDeg: offset);
      await driver.startGuidance(floorId: '1F');
      source.emitMagneticHeading();
      await settle();
    });

    tearDown(() async {
      await driver.dispose();
      offset.dispose();
    });

    test('노브가 0이면 자편각만 적용된다', () async {
      await driver.confirmAnchorByPin(floorPointM: const PdrLocalPoint(10, 20));
      final anchor = driver.currentCalibration.anchor!;
      expect(anchor.rotationDeg, closeTo(magneticDeclinationDeg, 1e-9));
      expect(anchor.headingOffsetDeg, 0);
    });

    test('노브를 돌리면 자편각 위에 더해진다', () async {
      offset.value = 12;
      await driver.confirmAnchorByPin(floorPointM: const PdrLocalPoint(10, 20));
      final anchor = driver.currentCalibration.anchor!;
      expect(anchor.rotationDeg, closeTo(magneticDeclinationDeg + 12, 1e-9));
      expect(anchor.headingOffsetDeg, 12);
    });

    test('anchor를 다시 찍지 않아도 노브가 바로 반영된다', () async {
      await driver.confirmAnchorByPin(floorPointM: const PdrLocalPoint(10, 20));
      offset.value = -20;
      final anchor = driver.currentCalibration.anchor!;
      expect(anchor.rotationDeg, closeTo(magneticDeclinationDeg - 20, 1e-9));
      expect(anchor.headingOffsetDeg, -20);
      // 노브는 회전만 건드린다 — 찍어 둔 위치는 그대로여야 한다.
      expect(anchor.anchorLocalM.eastM, closeTo(10, 1e-9));
      expect(anchor.anchorLocalM.northM, closeTo(20, 1e-9));
    });

    test('노브를 여러 번 돌려도 누적되지 않는다', () async {
      await driver.confirmAnchorByPin(floorPointM: PdrLocalPoint.zero);
      offset.value = 10;
      offset.value = 30;
      offset.value = 5;
      expect(
        driver.currentCalibration.anchor!.rotationDeg,
        closeTo(magneticDeclinationDeg + 5, 1e-9),
      );
    });
  });
}
