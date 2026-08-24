import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_pdr_core/indoor_pdr_core.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/core/api_config.dart';
import 'package:navigation_client/domain/guidance/elevator_ride.dart';
import 'package:navigation_client/models/building/building.dart';
import 'package:navigation_client/models/building/building_graph.dart';
import 'package:navigation_client/models/building/category_count.dart';
import 'package:navigation_client/models/place/store_index_entry.dart';
import 'package:navigation_client/models/route/indoor_route.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 엘리베이터 판정기가 **화면에 실제로 연결돼 있는지**에 대한 회귀 테스트.
///
/// 판정기 단위 테스트(`elevator_transition_detector_test.dart`)는 메서드를 직접
/// 부르므로, "그 메서드를 실기기에서 부르는 사람이 없다"를 못 본다 — 원시 걸음
/// 배선이 초록 속에 숨어 있던 이유가 그것이다. 여기서는 **native 채널에 이벤트를
/// 흘려** 판정기까지 닿는지를 잰다.
///
/// 정리 출구와 층 훑기도 같은 성격이다. 상태가 남았는지는 판정기가 아니라
/// 화면이 들고 있어서, 화면을 세워 놓고만 볼 수 있다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  const metersPerDegreeLat = 111320.0;
  const metersPerDegreeLng = 88243.0;
  const originLat = 37.5663;
  const originLng = 126.9777;

  Map<String, dynamic> node(
    String id,
    double xM,
    double yM, {
    String type = 'corridor',
    String? name,
  }) => {
    'id': id,
    'type': type,
    'name': ?name,
    'x_m': xM,
    'y_m': yM,
    'lat': originLat + yM / metersPerDegreeLat,
    'lng': originLng + xM / metersPerDegreeLng,
  };

  Map<String, dynamic> graphFor(double evX, double evY) => {
    'nodes': [
      node('n-a', 18, 22),
      node('n-b', 48, 22),
      node('ev1', evX, evY, type: 'elevator', name: 'EV1'),
    ],
    'edges': [
      {
        'id': 'e-ab',
        'from': 'n-a',
        'to': 'n-b',
        'length_m': 30.0,
        'bidirectional': true,
        'geometry_local_m': <Map<String, dynamic>>[],
      },
    ],
  };

  final graphs = {'1F': graphFor(20, 24), '2F': graphFor(40, 45)};

  const boarding = LatLng(originLat, originLng);
  const arrival = LatLng(originLat + 0.0002, originLng + 0.0004);
  const plan = ElevatorGlidePlan(
    fromFloor: '1F',
    toFloor: '2F',
    totalGapM: 5.56,
    glide: ElevatorGlide(from: boarding, to: arrival),
  );

  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  const commandChannel = MethodChannel('navigation_client/pdr_motion_cmd');
  const eventChannel = EventChannel('navigation_client/pdr_motion');
  TestDefaultBinaryMessenger messenger() =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// native 이벤트를 흘려 넣는 손잡이. 드라이버가 채널을 구독할 때 잡힌다.
  MockStreamHandlerEventSink? sensorSink;

  setUp(() async {
    sensorSink = null;
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await debugModeController.reload();
    originalBuildingRepository = buildingRepository;
    originalDestinationRepository = destinationRepository;
    isPedometerPermissionGranted = () async => true;
    messenger().setMockMethodCallHandler(commandChannel, (call) async => 1);
    messenger().setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(
        onListen: (arguments, sink) {
          sensorSink = sink;
        },
      ),
    );
    final repository = _ElevatorGraphRepository(graphs);
    buildingRepository = repository;
    destinationRepository = MockDestinationRepository(repository);
    await repository.getAllBuildings();
  });

  tearDown(() async {
    // PDR 드라이버는 앱 전역 싱글턴이라 세션이 다음 테스트로 샌다.
    await indoorNavigationDriver.stopGuidance();
    messenger().setMockMethodCallHandler(commandChannel, null);
    messenger().setMockStreamHandler(eventChannel, null);
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    isPedometerPermissionGranted = defaultIsPedometerPermissionGranted;
  });

  /// 1층 도면을 열고 통로에 앵커를 찍는다. 여기까지 와야 드라이버가 native
  /// 채널을 구독해([sensorSink]) 이벤트를 흘려 넣을 수 있다.
  Future<GlobalKey<OutdoorMapBodyState>> anchoredOnFirstFloor(
    WidgetTester tester,
  ) async {
    final key = GlobalKey<OutdoorMapBodyState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: OutdoorMapBody(key: key)),
      ),
    );
    await drain(tester);
    // ignore: invalid_use_of_visible_for_testing_member
    key.currentState!.enterIndoorForTest();
    await drain(tester);
    expect(key.currentState!.currentFloor, '1F');

    await key.currentState!.startLocationPlacement();
    await drain(tester);
    // ignore: invalid_use_of_visible_for_testing_member
    final tapped = key.currentState!.handleMapClickForTest(
      const LatLng(
        originLat + 22 / metersPerDegreeLat,
        originLng + 18 / metersPerDegreeLng,
      ),
    );
    await drain(tester);
    // 가짜 센서 채널은 heading을 끝내 안 보내므로 방향 보정 다이얼로그가 뜬다.
    // 답을 안 주면 이 await가 영영 안 돌아온다.
    if (find.text('위쪽').evaluate().isNotEmpty) {
      await tester.tap(find.text('위쪽'));
      await drain(tester);
    }
    await tapped;
    await tester.pump(const Duration(seconds: 3));
    await drain(tester);
    expect(
      indoorNavigationDriver.currentCalibration.anchor?.floorId,
      '1F',
      reason: '테스트 전제(1층 앵커)가 성립하지 않았다',
    );
    return key;
  }

  /// native 만보계 이벤트 한 건. 첫 건은 기준점이라 증분이 0이다.
  ///
  /// **`runAsync` 안에서 흘린다.** EventChannel 왕복은 플랫폼 메시지라 가짜 시계
  /// 위에서는 배달되지 않는다 — `pump`만 돌리면 이벤트가 영영 안 도착한다.
  Future<void> emitPedometer(WidgetTester tester, int steps) async {
    await tester.runAsync(() async {
      sensorSink!.success(<String, Object?>{
        'source': 'android_sensor_manager',
        'kind': 'pedometer',
        'steps': steps,
        'pedometerTimestamp': steps.toDouble(),
      });
      await Future<void>.delayed(Duration.zero);
    });
    await drain(tester);
  }

  testWidgets('원시 걸음이 엘리베이터 판정기까지 닿는다', (WidgetTester tester) async {
    final key = await anchoredOnFirstFloor(tester);
    expect(sensorSink, isNotNull, reason: '드라이버가 native 채널을 안 열었다');
    // ignore: invalid_use_of_visible_for_testing_member
    final detector = key.currentState!.elevatorDetectorForTest;
    expect(detector.rawStepCount, 0);
    // 드라이버가 이벤트를 내보내는 것과 판정기가 그걸 받는 것은 다른 일이다.
    // 앞이 깨지면 이 하네스가 잘못된 것이고, 뒤만 깨지면 배선이 없는 것이다.
    final emitted = <int?>[];
    final probe = indoorNavigationDriver.rawMotion.listen(
      (activity) => emitted.add(activity.nativeStepDelta),
    );
    addTearDown(probe.cancel);

    await emitPedometer(tester, 0);
    await emitPedometer(tester, 3);

    // 이 값이 0에 머물면 `onRawMotion`을 부르는 사람이 없다는 뜻이고, 그러면
    // 하차 확정이 20초 폴백으로만 나서 그동안 마커가 활강 끝점에 붙어 있다.
    expect(emitted, [0, 3], reason: '하네스가 native 이벤트를 못 흘렸다');
    expect(
      detector.rawStepCount,
      greaterThanOrEqualTo(3),
      reason: 'rawMotion 구독이 엘리베이터 판정기에 안 물려 있다',
    );
  });

  testWidgets('층 전환 실패 복구가 엘리베이터 활강도 끝낸다', (WidgetTester tester) async {
    final key = await anchoredOnFirstFloor(tester);
    // ignore: invalid_use_of_visible_for_testing_member
    key.currentState!.startElevatorGlideForTest(plan);
    await drain(tester);
    // ignore: invalid_use_of_visible_for_testing_member
    expect(key.currentState!.elevatorGlideActive, isTrue);

    // 큐에 들어간 액션이 던졌다. 어느 탈것이 던졌는지는 이 해치가 모른다.
    // ignore: invalid_use_of_visible_for_testing_member
    final recovered = key.currentState!.recoverFloorTransitionFailureForTest();
    await drain(tester);
    await recovered;
    await drain(tester);

    // 남으면 `_pdrCurrentWgs84()`가 영영 활강 점을 돌려준다 = 마커 영구 고정.
    // ignore: invalid_use_of_visible_for_testing_member
    expect(key.currentState!.elevatorGlideActive, isFalse);
  });

  testWidgets('야외로 나가면 엘리베이터 활강도 끝난다', (WidgetTester tester) async {
    final key = await anchoredOnFirstFloor(tester);
    // ignore: invalid_use_of_visible_for_testing_member
    key.currentState!.startElevatorGlideForTest(plan);
    await drain(tester);
    // ignore: invalid_use_of_visible_for_testing_member
    expect(key.currentState!.elevatorGlideActive, isTrue);

    // 책상 테스트에서 GPS가 실내 상태를 지우는 일이 실제로 있다.
    // ignore: invalid_use_of_visible_for_testing_member
    key.currentState!.exitIndoorByZoomOutForTest();
    await drain(tester);
    await drain(tester);

    // ignore: invalid_use_of_visible_for_testing_member
    expect(key.currentState!.elevatorGlideActive, isFalse);
  });

  testWidgets('다른 층을 펴 놓아도 판정기 무장이 살아 있다', (WidgetTester tester) async {
    final key = await anchoredOnFirstFloor(tester);
    // ignore: invalid_use_of_visible_for_testing_member
    key.currentState!.syncElevatorContextForTest();
    // ignore: invalid_use_of_visible_for_testing_member
    final detector = key.currentState!.elevatorDetectorForTest;
    // 승강장 앞에 섰다(1F EV1은 20/24에 있다).
    detector.onPosition(
      positionM: const PdrLocalPoint(21, 24),
      steps: 0,
      timestampMs: 1000,
    );
    expect(detector.isArmed, isTrue, reason: '테스트 전제(무장)가 성립하지 않았다');

    // 층 선택기로 2F를 펴 본다. 몸은 여전히 1F 승강장 앞이다.
    // ignore: invalid_use_of_visible_for_testing_member
    await key.currentState!.selectFloorChipForTest('2F');
    await drain(tester);
    expect(key.currentState!.currentFloor, '2F');
    // ignore: invalid_use_of_visible_for_testing_member
    key.currentState!.syncElevatorContextForTest();

    // 판정기가 읽는 층은 **몸이 서 있는 층**이다. 표시 층을 넘기면 여기서
    // "층이 바뀌었다"로 읽고 무장을 버려, 그대로 타도 아무것도 안 잡힌다.
    expect(
      // ignore: invalid_use_of_visible_for_testing_member
      key.currentState!.elevatorJudgementFloorForTest,
      '1F',
    );
    expect(detector.isArmed, isTrue);
  });
}

/// 층마다 엘리베이터 노드가 다른 자리에 있는 가짜 저장소.
class _ElevatorGraphRepository implements BuildingRepository {
  _ElevatorGraphRepository(this.graphs);

  final Map<String, Map<String, dynamic>> graphs;

  static const _building = Building(
    id: demoBuildingId,
    name: '데모 건물',
    floors: ['2F', '1F'],
    defaultFloor: '1F',
    entrance: LatLng(37.5665, 126.9779),
    footprintWgs84: [
      LatLng(37.5663, 126.9777),
      LatLng(37.5667, 126.9777),
      LatLng(37.5667, 126.9783),
      LatLng(37.5663, 126.9783),
    ],
  );

  @override
  Future<List<CategoryCount>?> getCategoryCounts(String buildingId) async =>
      const [];

  @override
  Future<Map<String, dynamic>?> getBuildingEvents(String buildingId) async =>
      null;

  @override
  Future<List<StoreIndexEntry>?> getStoreIndex(String buildingId) async =>
      const [];

  @override
  Future<List<Building>> getAllBuildings() async => const [_building];

  @override
  Future<Building?> getBuilding(String buildingId) async =>
      buildingId == _building.id ? _building : null;

  @override
  Future<Map<String, dynamic>?> getFloorGeoJson(
    String buildingId,
    String floor,
  ) async {
    final graph = graphs[floor];
    if (buildingId != _building.id || graph == null) return null;
    return {
      'type': 'FeatureCollection',
      'features': <Map<String, dynamic>>[],
      'navigation_graph': graph,
    };
  }

  @override
  Future<IndoorRoute?> getShortestRoute(
    String buildingId,
    String floor,
    String startNodeId,
    String endNodeId,
  ) async => null;

  @override
  Future<BuildingGraph?> getBuildingGraph(
    String buildingId, {
    String vertical = 'auto',
  }) async => null;
}
