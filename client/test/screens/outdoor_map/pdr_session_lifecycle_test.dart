import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/features/indoor_navigation/contract/indoor_navigation_contract.dart';
import 'package:navigation_client/screens/outdoor_map/pdr_session_lifecycle.dart';
import 'package:navigation_client/domain/geo/geo_transform.dart';

/// [PdrSessionLifecycle]을 화면 없이 직접 시험한다.
///
/// ## 왜 위젯 테스트가 아닌가
///
/// 여기서 지키려는 것은 "아직 끝나지 않은 정지를 시작이 기다리는가"다. 그런데
/// 위젯 테스트에서는 그 창을 만들 수가 없다 — 정지가 native 응답을 기다리는데,
/// 모의 채널 핸들러 안의 지연은 `tester.pump`가 앞당길 수 없는 **실제 시계**를
/// 쓴다. 실제로 이 동작을 위젯 테스트로 먼저 시도했다가, `awaitStop`을 통째로
/// 빼도 통과하는 무력한 테스트가 나왔다.
///
/// 여기서는 정지 Future를 테스트가 직접 쥐고 있으므로 창을 원하는 만큼 열어
/// 둘 수 있다. 세션 수명을 화면에서 떼어낸 값어치가 이것이다.
void main() {
  late _FakeDriver driver;

  PdrSessionLifecycle lifecycleFor({Future<bool> Function()? permission}) =>
      PdrSessionLifecycle(
        driver: driver,
        isPermissionGranted: permission ?? () async => true,
      );

  setUp(() => driver = _FakeDriver());

  Future<void> start(
    PdrSessionLifecycle lifecycle, {
    String? startable = '1F',
    String? Function()? activeFloor,
  }) => lifecycle.startIfIdle(
    readStartableFloor: () => startable,
    readActiveFloor: activeFloor ?? () => startable,
  );

  test('정지가 끝나기 전에는 시작하지 않고 기다린다', () async {
    // 이것이 이 클래스가 존재하는 이유다. 기다리지 않으면 `stopping`을 "이미
    // 돌고 있다"로 읽어, 세션 없이 앵커만 찍힌 채 위치가 굳는다.
    final lifecycle = lifecycleFor();
    driver.state = PdrRuntimeState.running;
    lifecycle.stopWithoutWaiting();
    expect(driver.log, ['stop']);

    final started = start(lifecycle);
    // 정지를 아직 풀지 않았다. 여기서 startGuidance가 찍히면 진 것이다.
    await pumpEventQueue();
    expect(driver.log, ['stop'], reason: '정지가 끝나기 전에 시작했다');

    driver.completeStop();
    await started;
    expect(driver.log, ['stop', 'start:1F']);
  });

  test('정지가 예외로 끝나도 시작은 진행한다', () async {
    // 정지 실패에서 멈추면 센서가 한 번 어긋난 뒤로 실내 위치가 영영 안 잡힌다.
    final lifecycle = lifecycleFor();
    driver.state = PdrRuntimeState.running;
    lifecycle.stopWithoutWaiting();

    final started = start(lifecycle);
    driver.failStop(StateError('native stop failed'));
    await started;

    expect(driver.log, ['stop', 'start:1F']);
  });

  test('같은 정지를 두 번 기다려도 두 번째는 곧바로 지나간다', () async {
    // 정지를 남겨 두는 자리가 한 칸뿐이라, 다 쓴 뒤 비우지 않으면 다음 시작이
    // 이미 끝난 Future를 계속 다시 기다린다.
    final lifecycle = lifecycleFor();
    driver.state = PdrRuntimeState.running;
    lifecycle.stopWithoutWaiting();
    driver.completeStop();
    await lifecycle.awaitStop();

    driver.state = PdrRuntimeState.idle;
    await start(lifecycle).timeout(const Duration(seconds: 1));
    expect(driver.log, ['stop', 'start:1F']);
  });

  test('이미 돌고 있으면 시작하지 않는다', () async {
    final lifecycle = lifecycleFor();
    driver.state = PdrRuntimeState.running;

    await start(lifecycle);

    expect(driver.log, isEmpty);
  });

  test('권한이 없으면 시작하지 않는다', () async {
    // 진입마다 재시도하면 degraded warning만 쌓인다.
    final lifecycle = lifecycleFor(permission: () async => false);

    await start(lifecycle);

    expect(driver.log, isEmpty);
  });

  test('시작할 층이 없으면(화면이 사라졌거나 그래프가 없으면) 시작하지 않는다', () async {
    final lifecycle = lifecycleFor();

    await start(lifecycle, startable: null);

    expect(driver.log, isEmpty);
  });

  test('권한을 기다리는 사이 층이 바뀌면 시작하지 않는다', () async {
    // 바뀐 뒤에 시작하면 앵커가 **옛 층**으로 기록돼, 지금 보고 있는 도면에는
    // 아무것도 그려지지 않는다.
    var active = '1F';
    // 층이 바뀌는 시점을 권한 대기 **안**에 둔다. 밖에서 뒤집으면 첫 읽기보다
    // 먼저 바뀌어, 재확인이 아니라 첫 게이트를 시험하게 된다.
    final lifecycle = lifecycleFor(
      permission: () async {
        active = '2F';
        await Future<void>.delayed(Duration.zero);
        return true;
      },
    );

    await lifecycle.startIfIdle(
      readStartableFloor: () => '1F',
      readActiveFloor: () => active,
    );

    expect(driver.log, isEmpty);
  });

  test('층은 그대로인데 그래프만 잠깐 비면 그래도 시작한다', () async {
    // 재확인이 그래프까지 보면 같은 층을 다시 로드하는 찰나에 시작이 취소된다.
    // 두 클로저가 보는 조건이 다른 것은 그래서 의도다.
    var graphLoaded = true;
    final lifecycle = lifecycleFor(
      permission: () async {
        graphLoaded = false;
        await Future<void>.delayed(Duration.zero);
        return true;
      },
    );

    await lifecycle.startIfIdle(
      readStartableFloor: () => graphLoaded ? '1F' : null,
      readActiveFloor: () => '1F',
    );

    expect(driver.log, ['start:1F']);
  });
}

/// 정지 시점을 테스트가 쥐는 가짜 드라이버. 계약 전체를 구현하지만 이 테스트가
/// 쓰는 것은 상태·시작·정지뿐이다.
class _FakeDriver implements IndoorNavigationController {
  final List<String> log = [];
  PdrRuntimeState state = PdrRuntimeState.idle;
  Completer<void>? _stopCompleter;
  String? _floorId;

  void completeStop() => _stopCompleter?.complete();
  void failStop(Object error) => _stopCompleter?.completeError(error);

  @override
  Future<void> startGuidance({required String floorId}) async {
    log.add('start:$floorId');
    _floorId = floorId;
    state = PdrRuntimeState.running;
  }

  @override
  Future<void> stopGuidance() {
    log.add('stop');
    state = PdrRuntimeState.stopping;
    final completer = Completer<void>();
    _stopCompleter = completer;
    return completer.future.whenComplete(() {
      state = PdrRuntimeState.idle;
    });
  }

  @override
  PdrRuntimeStatus get currentRuntimeStatus => PdrRuntimeStatus(state: state);

  @override
  String? get currentFloorId => _floorId;

  // ── 아래는 이 테스트가 쓰지 않는 계약 표면 ──

  @override
  Stream<PdrSnapshot> get snapshots => const Stream.empty();

  @override
  PdrSnapshot? get currentSnapshot => null;

  @override
  Stream<CalibrationStatus> get calibration => const Stream.empty();

  @override
  CalibrationStatus get currentCalibration =>
      const CalibrationStatus.uncalibrated();

  @override
  Stream<PdrRuntimeStatus> get runtimeStatuses => const Stream.empty();

  @override
  Stream<AltitudeSample> get altitudeSamples => const Stream.empty();

  @override
  AltitudeSample? get currentAltitude => null;

  @override
  AltimeterStatus get altimeterStatus => const AltimeterStatus.unavailable();

  @override
  Stream<RawMotionActivity> get rawMotion => const Stream.empty();

  @override
  bool get isHeadingConverged => true;

  @override
  Map<String, Object?>? get lastPedometerFinalizeInfo => null;

  @override
  Future<void> confirmAnchorByPin({
    required PdrLocalPoint floorPointM,
    PdrToFloorAxes axes = const PdrToFloorAxes.identity(),
    String? floorId,
  }) async {}

  @override
  Future<void> confirmAnchorByFloorDirection({
    required PdrLocalPoint floorDirection,
  }) async {}

  @override
  Future<void> changeFloor({required String floorId}) async {
    _floorId = floorId;
  }

  @override
  Future<void> applyVerticalTransfer({
    required String floorId,
    required PdrLocalPoint anchorLocalM,
    PdrToFloorAxes? axes,
  }) async {}

  @override
  Future<void> pauseStepTracking() async {}

  @override
  Future<void> resumeStepTracking() async {}

  @override
  Future<void> onAppBackgrounded() async {}

  @override
  Future<void> onAppForegrounded() async {}
}
