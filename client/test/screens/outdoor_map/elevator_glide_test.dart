import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/core/api_config.dart';
import 'package:navigation_client/domain/guidance/elevator_ride.dart';
import 'package:navigation_client/features/indoor_navigation/application/elevator_transition_detector.dart';
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

/// 엘리베이터 활강이 **화면에 배선된 방식**에 대한 회귀 테스트.
///
/// 활강을 걸지 말지 고르는 규칙 자체는 순수 함수로 검증한다
/// (`test/domain/guidance/elevator_ride_test.dart`). 여기서 보는 것은 그 규칙이
/// 실제로 이 화면을 지나는지와, 활강이 **타이머를 도는 코드**라는 사실이다 —
/// 탑승이 끝나거나 화면이 닫혔는데 틱이 남으면 전역 PDR 세션 위에서 계속 돈다.
///
/// 기압 시계열은 플랫폼 이벤트 채널로만 들어와 가짜 시계로 흘릴 수 없으므로,
/// 판정기가 `riding`을 낸 **뒤의** 자리를 직접 태운다.
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
      node('n-c', 18, 52),
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
      {
        'id': 'e-ac',
        'from': 'n-a',
        'to': 'n-c',
        'length_m': 30.0,
        'bidirectional': true,
        'geometry_local_m': <Map<String, dynamic>>[],
      },
    ],
  };

  final graphs = {'1F': graphFor(20, 24), '2F': graphFor(40, 45)};

  const boarding = LatLng(originLat, originLng);
  const arrival = LatLng(originLat + 0.0002, originLng + 0.0004);

  /// 1F(12.94) → 2F(18.50). 더현대 실측표의 실제 간격이다.
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

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await debugModeController.reload();
    originalBuildingRepository = buildingRepository;
    originalDestinationRepository = destinationRepository;
    isPedometerPermissionGranted = () async => true;
    messenger().setMockMethodCallHandler(commandChannel, (call) async => 1);
    messenger().setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(onListen: (arguments, sink) {}),
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

  Future<GlobalKey<OutdoorMapBodyState>> indoorScreen(
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
    return key;
  }

  testWidgets('경로가 도착 층을 안 말하면 활강을 안 건다', (WidgetTester tester) async {
    final key = await indoorScreen(tester);

    // 자유 보행이라 판정기도 도착 층을 모른다. 이 상태에서 활강을 걸면 분모를
    // 지어내야 하고, 그러면 진행률이 거짓이 된다.
    // ignore: invalid_use_of_visible_for_testing_member
    key.currentState!.beginElevatorGlideForTest(
      const ElevatorPhaseChange(
        phase: ElevatorPhase.riding,
        atMs: 0,
        reason: 'verticalMotion',
        fromFloorLabel: '1F',
        boardingNodeId: 'ev1',
        carName: 'EV1',
      ),
    );
    await drain(tester);

    // ignore: invalid_use_of_visible_for_testing_member
    expect(key.currentState!.elevatorGlideActive, isFalse);
  });

  testWidgets('도착 층을 알아도 경로의 수직 이동선이 없으면 활강을 안 건다', (
    WidgetTester tester,
  ) async {
    final key = await indoorScreen(tester);

    // 판정기는 도착 층을 받았지만 화면에 다층 경로가 없다. 양 끝을 모르는 활강은
    // 아무 방향으로나 흐르는 점일 뿐이다.
    // ignore: invalid_use_of_visible_for_testing_member
    key.currentState!.beginElevatorGlideForTest(
      const ElevatorPhaseChange(
        phase: ElevatorPhase.riding,
        atMs: 0,
        reason: 'verticalMotion',
        fromFloorLabel: '1F',
        toFloorLabel: '2F',
        boardingNodeId: 'ev1',
        carName: 'EV1',
      ),
    );
    await drain(tester);

    // ignore: invalid_use_of_visible_for_testing_member
    expect(key.currentState!.elevatorGlideActive, isFalse);
  });

  testWidgets('하차 확정이 활강과 그 타이머를 끝낸다', (WidgetTester tester) async {
    final key = await indoorScreen(tester);

    // ignore: invalid_use_of_visible_for_testing_member
    key.currentState!.startElevatorGlideForTest(plan);
    await drain(tester);
    // ignore: invalid_use_of_visible_for_testing_member
    expect(key.currentState!.elevatorGlideActive, isTrue);

    // **await로 붙잡지 않는다.** 도면 교체는 덮개가 올라오기를 기다리는데
    // (`Future.delayed`), 위젯 테스트의 시계는 pump로만 흐른다.
    // ignore: invalid_use_of_visible_for_testing_member
    final applied = key.currentState!.applyElevatorTransitionForTest(
      const ElevatorTransition(
        fromFloorLabel: '1F',
        toFloorLabel: '2F',
        deltaM: 5.56,
        boardingNodeId: 'ev1',
        carName: 'EV1',
        durationMs: 12000,
        arrivalSource: 'route',
      ),
    );
    await drain(tester);
    await drain(tester);
    await applied;
    await drain(tester);

    // ignore: invalid_use_of_visible_for_testing_member
    expect(key.currentState!.elevatorGlideActive, isFalse);
    expect(key.currentState!.currentFloor, '2F');
    // 틱이 남아 있으면 이 테스트가 "Timer is still pending"으로 깨진다.
  });

  testWidgets('활강 중 화면이 닫혀도 틱이 남지 않는다', (WidgetTester tester) async {
    final key = await indoorScreen(tester);

    // ignore: invalid_use_of_visible_for_testing_member
    key.currentState!.startElevatorGlideForTest(plan);
    await drain(tester);
    // ignore: invalid_use_of_visible_for_testing_member
    expect(key.currentState!.elevatorGlideActive, isTrue);

    // 탑승 중 화면을 떠난다. **그 뒤로 시계를 안 돌린다** — 틱이 한 번이라도
    // 돌면 콜백이 `mounted`를 보고 스스로 접어, dispose가 접었는지 알 수 없다.
    // dispose가 안 접으면 이 테스트는 "Timer is still pending"으로 깨진다.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  });
}

/// 층마다 엘리베이터 노드가 다른 자리에 있는 가짜 저장소. 다층 경로는 주지
/// 않는다 — 경로 없이는 활강이 안 걸린다는 것 자체가 여기서 볼 것이다.
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
