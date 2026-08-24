import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/core/api_config.dart';
import 'package:navigation_client/features/indoor_navigation/application/elevator_transition_detector.dart';
import 'package:navigation_client/features/indoor_navigation/contract/floor_transition_ui_state.dart';
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

/// 엘리베이터 탑승 배너가 **언제 뜨고 언제 사라지는지**에 대한 회귀 테스트.
///
/// 문구·우선순위 자체는 순수 값으로 검증한다
/// (`test/features/indoor_navigation/elevator_banner_test.dart`). 여기서 보는
/// 것은 그 값이 이 화면을 실제로 지나는지와, **모든 출구에서 사라지는지**다 —
/// 하나라도 빠지면 배너가 화면에 눌어붙는다.
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

  /// 판정기가 `riding`을 낼 때 내보내는 값. [toFloorLabel]이 null인 것이
  /// 자유 보행(경로 없이 탄 경우)이다.
  ElevatorPhaseChange riding({String? toFloorLabel}) => ElevatorPhaseChange(
    phase: ElevatorPhase.riding,
    atMs: 0,
    reason: 'verticalMotion',
    fromFloorLabel: '1F',
    toFloorLabel: toFloorLabel,
    boardingNodeId: 'ev1',
    carName: 'EV1',
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
    WidgetTester tester, {
    FloorTransitionUiChanged? onFloorTransitionChanged,
  }) async {
    final key = GlobalKey<OutdoorMapBodyState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: OutdoorMapBody(
            key: key,
            onFloorTransitionChanged: onFloorTransitionChanged,
          ),
        ),
      ),
    );
    await drain(tester);
    // ignore: invalid_use_of_visible_for_testing_member
    key.currentState!.enterIndoorForTest();
    await drain(tester);
    expect(key.currentState!.currentFloor, '1F');
    return key;
  }

  // ignore: invalid_use_of_visible_for_testing_member
  FloorTransitionUiState? banner(GlobalKey<OutdoorMapBodyState> key) =>
      // ignore: invalid_use_of_visible_for_testing_member
      key.currentState!.floorTransitionUiStateForTest;

  testWidgets('경로가 도착 층을 말하면 배너가 그 층까지 적는다', (WidgetTester tester) async {
    final key = await indoorScreen(tester);

    // ignore: invalid_use_of_visible_for_testing_member
    key.currentState!.beginElevatorBannerForTest(riding(toFloorLabel: '2F'));
    await drain(tester);

    final state = banner(key);
    expect(state?.vehicle, FloorTransitionVehicle.elevator);
    expect(state?.headline, '1F → 2F');
    expect(state?.detail, '엘리베이터로 올라가는 중');
  });

  testWidgets('방향을 못 정하면 배너를 안 띄운다', (WidgetTester tester) async {
    final key = await indoorScreen(tester);

    // 경로 없이 탄 경우다. 도착 층은 하차 확정 뒤에야 나오고, 기압을 흘릴 수
    // 없는 이 테스트에서는 Δ도 없다 — 방향을 반반으로 찍느니 안 띄운다.
    // (Δ가 임계를 넘은 뒤 무엇을 적는지는 순수 값 테스트가 본다.)
    // ignore: invalid_use_of_visible_for_testing_member
    key.currentState!.beginElevatorBannerForTest(riding());
    await drain(tester);

    expect(banner(key), isNull);
  });

  testWidgets('내려가는 이동은 문구가 갈린다', (WidgetTester tester) async {
    final key = await indoorScreen(tester);

    // 층 순위가 방향을 말한다(2F → 1F). Δ를 못 넣는 자리에서의 폴백이다.
    // ignore: invalid_use_of_visible_for_testing_member
    key.currentState!.beginElevatorBannerForTest(
      const ElevatorPhaseChange(
        phase: ElevatorPhase.riding,
        atMs: 0,
        reason: 'verticalMotion',
        fromFloorLabel: '2F',
        toFloorLabel: '1F',
        boardingNodeId: 'ev1',
        carName: 'EV1',
      ),
    );
    await drain(tester);

    expect(banner(key)?.detail, '엘리베이터로 내려가는 중');
    expect(banner(key)?.headline, '2F → 1F');
  });

  testWidgets('탑승이 끝나면 배너가 사라진다 — 공통 출구 하나', (WidgetTester tester) async {
    final key = await indoorScreen(tester);

    // ignore: invalid_use_of_visible_for_testing_member
    key.currentState!.beginElevatorBannerForTest(riding(toFloorLabel: '2F'));
    await drain(tester);
    expect(banner(key), isNotNull);

    // 확정도 취소도 이 문을 지난다([_endElevatorRide]). 하나라도 안 지나면
    // 배너가 화면에 눌어붙는다.
    // ignore: invalid_use_of_visible_for_testing_member
    final ended = key.currentState!.endElevatorRideForTest();
    await drain(tester);
    await ended;
    await drain(tester);

    expect(banner(key), isNull);
  });

  testWidgets('하차 확정이 배너를 지운다', (WidgetTester tester) async {
    final key = await indoorScreen(tester);

    // ignore: invalid_use_of_visible_for_testing_member
    key.currentState!.beginElevatorBannerForTest(riding(toFloorLabel: '2F'));
    await drain(tester);
    expect(banner(key), isNotNull);

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

    expect(key.currentState!.currentFloor, '2F');
    expect(banner(key), isNull);
  });

  testWidgets('값이 안 바뀌면 셸에 다시 안 알린다', (WidgetTester tester) async {
    final reports = <FloorTransitionUiState?>[];
    final key = await indoorScreen(
      tester,
      onFloorTransitionChanged: (banner, scrim) => reports.add(banner),
    );
    reports.clear();

    // ignore: invalid_use_of_visible_for_testing_member
    key.currentState!.beginElevatorBannerForTest(riding(toFloorLabel: '2F'));
    await drain(tester);
    expect(reports.length, 1);

    // 같은 단계가 한 번 더 들어와도(중간 정차 뒤 `resumedRiding`) 값이 같으면
    // 알리지 않는다. 막지 않으면 매 스냅샷마다 부모 setState가 돌아 지도가
    // 초당 몇 번씩 다시 그려진다.
    // ignore: invalid_use_of_visible_for_testing_member
    key.currentState!.beginElevatorBannerForTest(riding(toFloorLabel: '2F'));
    await drain(tester);

    expect(reports.length, 1);
  });
}

/// 층마다 엘리베이터 노드가 다른 자리에 있는 가짜 저장소. 다층 경로는 주지
/// 않는다 — 배너는 경로가 없어도 떠야 하는 것이 이 파일에서 볼 것이다.
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
