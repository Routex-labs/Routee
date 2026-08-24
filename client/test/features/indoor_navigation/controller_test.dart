import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/features/indoor_navigation/application/indoor_navigation_controller.dart';
import 'package:navigation_client/features/indoor_navigation/contract/indoor_navigation_contract.dart';
import 'package:navigation_client/features/indoor_navigation/platform/native_pdr_event.dart';
import 'package:navigation_client/features/indoor_navigation/platform/pdr_motion_source.dart';
import 'package:navigation_client/domain/geo/geo_transform.dart';

/// 테스트/하니스용 fake 소스. raw native map을 파서에 태워 흘린다(파서+컨트롤러+코어
/// end-to-end = 헤드리스 하니스).
class FakePdrMotionSource implements PdrMotionSource {
  final _controller = StreamController<NativePdrEvent>.broadcast();
  int startCount = 0;
  int stopCount = 0;
  int resetCount = 0;
  int finalizeCount = 0;
  Map<String, Object?>? finalizeInfo;
  int _sessionId = 0;
  Object? startError;
  Object? stopError;
  Object? resetError;
  Completer<void>? stopGate;

  @override
  Stream<NativePdrEvent> get events => _controller.stream;

  @override
  Future<void> start() async {
    startCount++;
    if (startError case final error?) throw error;
  }

  @override
  Future<void> stop() async {
    stopCount++;
    if (stopError case final error?) throw error;
    await stopGate?.future;
  }

  @override
  Future<int?> resetPedometer() async {
    resetCount++;
    if (resetError case final error?) throw error;
    return ++_sessionId;
  }

  @override
  Future<Map<String, Object?>?> finalizePedometer() async {
    finalizeCount++;
    return finalizeInfo;
  }

  @override
  Future<void> dispose() async => _controller.close();

  void emitRaw(Map<String, Object?> raw) {
    final e = NativePdrEvent.tryParse(raw);
    if (e == null) return;
    _controller.add(e);
  }

  void emitError(Object error) => _controller.addError(error);
}

Map<String, Object?> motionEvent({
  required int tMs,
  double heading = 0,
  String source = 'device_motion/xMagneticNorthZVertical',
  int? stepPeakCount,
  int? latestStepPeakMs,
  double? headingErrorDeg,
}) => {
  'source': 'ios_core_motion',
  'kind': 'motion',
  'stepSessionId': 1,
  'fusedHeadingDeg': heading,
  'headingStable': true,
  'headingSource': source,
  'rotationHeadingAccuracyDeg': ?headingErrorDeg,
  'motionTimestamp': tMs.toDouble(),
  'stepPeakCount': ?stepPeakCount,
  'latestStepPeakMs': ?latestStepPeakMs?.toDouble(),
};

Map<String, Object?> pedometerEvent({
  required int steps,
  required int sessionStartMs,
  required int endMs,
  required double distanceM,
  List<double>? peaks,
}) => {
  'source': 'ios_core_motion',
  'kind': 'pedometer',
  'stepSessionId': 1,
  'steps': steps,
  'pedometerSessionStartMs': sessionStartMs,
  'pedometerTimestamp': endMs.toDouble(),
  'pedometerDistance': distanceM,
  'pedometerDistanceAvailable': true,
  'stepPeakTimes': peaks,
};

Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakePdrMotionSource source;
  late IndoorNavigationDriver driver;
  late int nowMs;

  setUp(() {
    source = FakePdrMotionSource();
    nowMs = 0;
    driver = IndoorNavigationDriver(source: source, nowMs: () => nowMs);
  });

  tearDown(() async {
    await driver.dispose();
  });

  test('Android RoNIN 자동보폭 필드를 typed event로 파싱한다', () {
    final event = NativePdrEvent.tryParse(const {
      'source': 'android_sensor_manager',
      'kind': 'pedometer',
      'stepSessionId': 3,
      'steps': 7,
      'roninSupported': true,
      'roninReady': true,
      'roninModel': 'ronin-tcn-200hz',
      'roninStatus': 'ready',
      'roninSpeedMps': 1.04,
      'roninSpeedStdMps': 0.09,
      'roninCadenceHz': 1.6,
      'roninStrideMeters': 0.65,
    });

    expect(event, isNotNull);
    expect(event!.pedometer!.isAndroid, isTrue);
    expect(event.pedometer!.roninSupported, isTrue);
    expect(event.pedometer!.roninReady, isTrue);
    expect(event.pedometer!.roninStrideMeters, 0.65);
  });

  test('startGuidance는 소스를 켜고 awaitingPin으로 간다', () async {
    await driver.startGuidance(floorId: 'F1');
    expect(source.startCount, 1);
    expect(source.resetCount, 1);
    expect(driver.currentCalibration.phase, CalibrationPhase.awaitingPin);
  });

  test('start는 starting이고 첫 native 이벤트 뒤 running이다', () async {
    await driver.startGuidance(floorId: 'F1');
    expect(driver.currentRuntimeStatus.state, PdrRuntimeState.starting);

    source.emitRaw(motionEvent(tMs: 1000));
    await settle();

    expect(driver.currentRuntimeStatus.state, PdrRuntimeState.running);
  });

  test('센서 시작 실패는 degraded warning으로 노출된다', () async {
    source.startError = StateError('denied');

    await driver.startGuidance(floorId: 'F1');

    expect(driver.currentRuntimeStatus.state, PdrRuntimeState.degraded);
    expect(driver.currentRuntimeStatus.warnings, contains('sensorStartFailed'));
  });

  test('센서 stream 오류는 처리되어 degraded가 된다', () async {
    await driver.startGuidance(floorId: 'F1');

    source.emitError(StateError('stream'));
    await settle();

    expect(driver.currentRuntimeStatus.state, PdrRuntimeState.degraded);
    expect(driver.currentRuntimeStatus.warnings, contains('sensorStreamError'));
  });

  test('heading+pedometer를 흘리면 confirmed 스냅샷이 방출된다', () async {
    await driver.startGuidance(floorId: 'F1');
    final seen = <PdrSnapshot>[];
    driver.snapshots.listen(seen.add);

    source.emitRaw(
      motionEvent(tMs: 1000, heading: 0, stepPeakCount: 0, latestStepPeakMs: 0),
    );
    source.emitRaw(
      pedometerEvent(
        steps: 10,
        sessionStartMs: 900,
        endMs: 2000,
        distanceM: 7.0,
        peaks: [1100, 1300, 1500, 1700, 1900],
      ),
    );
    await settle();

    expect(driver.currentSnapshot, isNotNull);
    expect(driver.currentSnapshot!.steps, 10);
    expect(driver.currentSnapshot!.distanceM, closeTo(7.0, 1e-9));
    expect(seen, isNotEmpty);
  });

  test('자북 기준: pin 확정으로 바로 calibrated', () async {
    await driver.startGuidance(floorId: 'F1');
    source.emitRaw(motionEvent(tMs: 1000, heading: 0));
    await settle();

    await driver.confirmAnchorByPin(
      floorPointM: const PdrLocalPoint(10, 20),
      axes: const PdrToFloorAxes(
        eastToX: 1,
        northToX: 0,
        eastToY: 0,
        northToY: -1,
      ),
    );
    expect(driver.currentCalibration.phase, CalibrationPhase.calibrated);
    expect(driver.currentCalibration.canRenderPosition, isTrue);
    expect(driver.currentCalibration.anchor, isNotNull);
    expect(driver.currentCalibration.anchor!.axes.northToY, -1);
  });

  test('시작 위치를 다시 찍으면 native는 유지하고 PDR 경로만 재기준화한다', () async {
    await driver.startGuidance(floorId: 'F1');
    source.emitRaw(
      motionEvent(tMs: 1000, heading: 0, stepPeakCount: 0, latestStepPeakMs: 0),
    );
    source.emitRaw(
      pedometerEvent(
        steps: 8,
        sessionStartMs: 900,
        endMs: 2000,
        distanceM: 5.6,
        peaks: [1100, 1300, 1500, 1700, 1900],
      ),
    );
    await settle();
    expect(driver.currentSnapshot!.steps, 8);

    nowMs = 2500;
    await driver.confirmAnchorByPin(floorPointM: const PdrLocalPoint(30, 40));
    await settle();

    expect(source.resetCount, 1);
    expect(driver.currentSnapshot!.steps, 0);
    expect(driver.currentSnapshot!.preview.steps, 0);
    expect(driver.currentSnapshot!.path, [PdrLocalPoint.zero]);
    expect(driver.currentSnapshot!.hasHeading, isTrue);
    expect(driver.currentCalibration.anchor!.anchorLocalM.eastM, 30);
    expect(driver.currentCalibration.anchor!.anchorLocalM.northM, 40);

    source.emitRaw(
      motionEvent(
        tMs: 3000,
        heading: 0,
        stepPeakCount: 1,
        latestStepPeakMs: 3000,
      ),
    );
    await settle();
    expect(driver.currentSnapshot!.preview.steps, 1);

    source.emitRaw(
      pedometerEvent(
        steps: 12,
        sessionStartMs: 900,
        endMs: 4000,
        distanceM: 8.4,
        peaks: [2200, 2800, 3400, 3900],
      ),
    );
    await settle();
    expect(driver.currentSnapshot!.steps, 3);
  });

  test('다른 층 출발지를 지정하면 새 anchor의 층도 함께 바뀐다', () async {
    await driver.startGuidance(floorId: '1F');
    source.emitRaw(motionEvent(tMs: 1000, heading: 0));
    await settle();

    await driver.confirmAnchorByPin(
      floorId: 'B2',
      floorPointM: const PdrLocalPoint(12, 34),
    );

    expect(driver.currentCalibration.phase, CalibrationPhase.calibrated);
    expect(driver.currentCalibration.anchor!.floorId, 'B2');
    expect(driver.currentCalibration.anchor!.anchorLocalM.eastM, 12);
    expect(driver.currentCalibration.anchor!.anchorLocalM.northM, 34);
  });

  group('자북 frame이어도 센서가 오차를 크게 신고하면 그 방위를 안 쓴다', () {
    // 안드로이드는 gyro hold 중에도 frame을 자북으로 신고한다. frame만 보면
    // 철골 건물 안에서 통째로 돌아간 방위가 보정 없이 앵커에 박힌다
    // (docs/client/android-heading-drift.md 6절).
    Future<void> pinWith(double? errorDeg) async {
      await driver.startGuidance(floorId: 'F1');
      source.emitRaw(
        motionEvent(
          tMs: 1000,
          heading: 0,
          source: 'fused_orientation_provider+gyro_hold',
          headingErrorDeg: errorDeg,
        ),
      );
      await settle();
      await driver.confirmAnchorByPin(floorPointM: const PdrLocalPoint(0, 0));
    }

    test('오차가 문턱을 넘으면 진행 방향 보정으로 넘어간다', () async {
      await pinWith(60);
      expect(driver.currentCalibration.phase, CalibrationPhase.awaitingHeading);
      expect(driver.currentCalibration.requiresManualRotationCalibration, isTrue);
    });

    test('오차가 작으면 자편각만 얹고 바로 확정한다', () async {
      await pinWith(8);
      expect(driver.currentCalibration.phase, CalibrationPhase.calibrated);
      // 센서를 믿었다는 뜻이지 회전이 0이라는 뜻이 아니다 — floor 축은 진북
      // 기준이라 자편각이 남는다(`heading_declination_test.dart`).
      expect(
        driver.currentCalibration.anchor!.rotationDeg,
        closeTo(magneticDeclinationDeg, 1e-9),
      );
      expect(
        driver.currentCalibration.anchor!.rotationBasis,
        AnchorRotationBasis.trustedHeading,
      );
    });

    test('기기가 오차를 안 주면(-1) 막지 않는다', () async {
      // SM-G996N은 rotation vector의 values[4]를 -1로 준다. 여기서 막으면 그
      // 기기의 앵커가 통째로 죽는다.
      await pinWith(-1);
      expect(driver.currentCalibration.phase, CalibrationPhase.calibrated);
    });
  });

  group('복도 축으로 잡은 회전각의 앞뒤 뒤집기', () {
    Future<void> anchorOnCorridorAxis() async {
      await driver.startGuidance(floorId: 'F1');
      source.emitRaw(
        motionEvent(
          tMs: 1000,
          heading: 0,
          source: 'fused_orientation_provider',
          headingErrorDeg: 180,
        ),
      );
      await settle();
      await driver.confirmAnchorByPin(floorPointM: const PdrLocalPoint(5, 7));
      await driver.confirmAnchorByFloorDirection(
        floorDirection: const PdrLocalPoint(1, 0),
        basis: AnchorRotationBasis.corridorAxis,
      );
    }

    test('회전각만 180° 돌고 찍은 자리는 안 움직인다', () async {
      await anchorOnCorridorAxis();
      final before = driver.currentCalibration.anchor!;
      await driver.flipAnchorRotation();
      final after = driver.currentCalibration.anchor!;

      expect(
        normalizePdrRotation(after.rotationDeg - before.rotationDeg).abs(),
        closeTo(180, 1e-9),
      );
      // 앵커 원점이 움직이면 사용자가 찍은 자리가 사라진다. 뒤집기는 그 점을
      // 중심으로 한 점대칭이어야 한다.
      expect(after.anchorLocalM.eastM, before.anchorLocalM.eastM);
      expect(after.anchorLocalM.northM, before.anchorLocalM.northM);
    });

    test('근거가 뒤집힘으로 바뀌어 두 번 판정되지 않는다', () async {
      await anchorOnCorridorAxis();
      expect(
        driver.currentCalibration.anchor!.rotationBasis,
        AnchorRotationBasis.corridorAxis,
      );
      await driver.flipAnchorRotation();
      expect(
        driver.currentCalibration.anchor!.rotationBasis,
        AnchorRotationBasis.corridorAxisFlipped,
      );
    });

    test('앵커가 없으면 아무 일도 하지 않는다', () async {
      await driver.startGuidance(floorId: 'F1');
      await driver.flipAnchorRotation();
      expect(driver.currentCalibration.anchor, isNull);
    });
  });

  test('arbitrary 기준: pin 후 heading 보정까지 요구한다', () async {
    await driver.startGuidance(floorId: 'F1');
    source.emitRaw(
      motionEvent(
        tMs: 1000,
        heading: 0,
        source: 'device_motion/xArbitraryCorrectedZVertical',
      ),
    );
    await settle();

    const rotatedAxes = PdrToFloorAxes(
      // 실제 동쪽은 floor 위쪽(+y), 실제 북쪽은 floor 왼쪽(-x)인 회전층.
      eastToX: 0,
      northToX: -1,
      eastToY: 1,
      northToY: 0,
    );
    await driver.confirmAnchorByPin(
      floorPointM: const PdrLocalPoint(0, 0),
      axes: rotatedAxes,
    );
    expect(driver.currentCalibration.phase, CalibrationPhase.awaitingHeading);
    expect(driver.currentCalibration.requiresManualRotationCalibration, isTrue);

    await driver.confirmAnchorByFloorDirection(
      floorDirection: const PdrLocalPoint(0, 1),
      basis: AnchorRotationBasis.corridorAxis,
    );
    expect(driver.currentCalibration.phase, CalibrationPhase.calibrated);
    expect(driver.currentCalibration.anchor!.rotationDeg, closeTo(90, 1e-9));
    final mappedNorth = FloorCoordinateTransform(
      driver.currentCalibration.anchor!,
    ).toFloor(const PdrLocalPoint(0, 1));
    expect(mappedNorth.eastM, closeTo(0, 1e-9));
    expect(mappedNorth.northM, closeTo(1, 1e-9));
  });

  test('background는 tracking을 pause해 이후 배치를 반영하지 않는다', () async {
    await driver.startGuidance(floorId: 'F1');
    source.emitRaw(motionEvent(tMs: 1000, heading: 0));
    await settle();

    await driver.onAppBackgrounded();
    source.emitRaw(
      pedometerEvent(
        steps: 8,
        sessionStartMs: 900,
        endMs: 2000,
        distanceM: 5.6,
        peaks: [1200, 1600],
      ),
    );
    await settle();

    expect(
      driver.currentSnapshot?.steps ?? 0,
      0,
      reason: 'pause 중에는 confirmed가 늘지 않아야 한다',
    );
  });

  test('안내 중 background는 tracking과 native source를 한 번 멈춘다', () async {
    await driver.startGuidance(floorId: 'F1');
    source.emitRaw(motionEvent(tMs: 1000));
    await settle();

    await driver.onAppBackgrounded();
    await driver.onAppBackgrounded();

    expect(source.stopCount, 1);
    expect(driver.currentRuntimeStatus.state, PdrRuntimeState.paused);
  });

  test('background 뒤 foreground는 source와 tracking을 한 번 재개한다', () async {
    await driver.startGuidance(floorId: 'F1');
    await driver.onAppBackgrounded();

    await driver.onAppForegrounded();
    await driver.onAppForegrounded();

    expect(source.startCount, 2);
    expect(driver.currentRuntimeStatus.state, PdrRuntimeState.starting);
  });

  test('빠른 background와 foreground 전환도 stop 뒤 start 순서로 직렬화한다', () async {
    await driver.startGuidance(floorId: 'F1');
    source.stopGate = Completer<void>();

    final background = driver.onAppBackgrounded();
    await settle();
    final foreground = driver.onAppForegrounded();
    await settle();

    expect(source.stopCount, 1);
    expect(source.startCount, 1, reason: 'stop 완료 전 start가 실행되면 안 된다');

    source.stopGate!.complete();
    await Future.wait([background, foreground]);

    expect(source.startCount, 2);
    expect(driver.currentRuntimeStatus.state, PdrRuntimeState.starting);
  });

  test('안내 중이 아니면 lifecycle이 source를 호출하지 않는다', () async {
    await driver.onAppBackgrounded();
    await driver.onAppForegrounded();

    expect(source.startCount, 0);
    expect(source.stopCount, 0);
  });

  test('background 센서 정지 실패는 degraded warning으로 노출된다', () async {
    await driver.startGuidance(floorId: 'F1');
    source.stopError = StateError('stop');

    await driver.onAppBackgrounded();

    expect(driver.currentRuntimeStatus.state, PdrRuntimeState.degraded);
    expect(driver.currentRuntimeStatus.warnings, contains('sensorStopFailed'));
  });

  test('foreground 센서 재시작 실패는 degraded warning으로 노출된다', () async {
    await driver.startGuidance(floorId: 'F1');
    await driver.onAppBackgrounded();
    source.startError = StateError('resume');

    await driver.onAppForegrounded();

    expect(driver.currentRuntimeStatus.state, PdrRuntimeState.degraded);
    expect(
      driver.currentRuntimeStatus.warnings,
      contains('sensorResumeFailed'),
    );
  });

  test('runtime 오류 뒤 snapshot quality와 warning도 degraded로 합성된다', () async {
    await driver.startGuidance(floorId: 'F1');
    source.emitError(StateError('stream'));
    source.emitRaw(motionEvent(tMs: 1000));
    source.emitRaw(
      pedometerEvent(
        steps: 4,
        sessionStartMs: 900,
        endMs: 2000,
        distanceM: 2.8,
        peaks: [1200, 1600],
      ),
    );
    await settle();

    expect(driver.currentSnapshot, isNotNull);
    expect(driver.currentSnapshot!.quality.state, PdrQualityState.degraded);
    expect(
      driver.currentSnapshot!.quality.warnings,
      contains('sensorStreamError'),
    );
  });

  test('stopGuidance는 소스를 끄고 uncalibrated로 되돌린다', () async {
    await driver.startGuidance(floorId: 'F1');
    await driver.stopGuidance();
    expect(source.stopCount, 1);
    expect(source.finalizeCount, 1);
    expect(driver.currentCalibration.phase, CalibrationPhase.uncalibrated);
  });

  test('changeFloor는 native sensor를 유지하고 awaitingPin으로 간다', () async {
    await driver.startGuidance(floorId: 'F1');
    await driver.changeFloor(floorId: 'F2');
    expect(source.resetCount, 1);
    expect(driver.currentCalibration.phase, CalibrationPhase.awaitingPin);
  });

  test('anchor에는 지금 세션의 층이 찍힌다', () async {
    // 화면 쪽 규칙의 근거. 위치 마커·경로는 `anchor.floorId == 보고 있는 층`일
    // 때만 그려지므로, 세션의 층이 옛 층에 묶여 있으면 새로 찍은 anchor가
    // 통째로 무시된다("다른 층에서는 위치 지정이 안 된다"의 정체).
    await driver.startGuidance(floorId: 'F1');
    source.emitRaw(motionEvent(tMs: 1000, heading: 0));
    await settle();
    await driver.confirmAnchorByPin(floorPointM: const PdrLocalPoint(1, 2));

    expect(driver.currentFloorId, 'F1');
    expect(driver.currentCalibration.anchor?.floorId, 'F1');
  });

  test('changeFloor 뒤 확정한 anchor는 새 층으로 기록된다', () async {
    await driver.startGuidance(floorId: 'F1');
    source.emitRaw(motionEvent(tMs: 1000, heading: 0));
    await settle();
    await driver.confirmAnchorByPin(floorPointM: const PdrLocalPoint(1, 2));

    await driver.changeFloor(floorId: 'F2');
    // 층을 바꾸면 이전 anchor는 버려진다. 그래서 화면은 층이 **실제로 다를 때만**
    // 이걸 불러야 한다 — 같은 층에서 위치만 다시 찍는 사용자의 anchor까지 날린다.
    expect(driver.currentCalibration.anchor, isNull);

    source.emitRaw(motionEvent(tMs: 2000, heading: 0));
    await settle();
    await driver.confirmAnchorByPin(floorPointM: const PdrLocalPoint(3, 4));

    expect(driver.currentFloorId, 'F2');
    expect(driver.currentCalibration.anchor?.floorId, 'F2');
  });
}
