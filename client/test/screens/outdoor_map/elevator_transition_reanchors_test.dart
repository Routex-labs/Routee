import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/core/api_config.dart';
import 'package:navigation_client/features/indoor_navigation/application/elevator_transition_detector.dart';
import 'package:navigation_client/features/indoor_navigation/contract/indoor_navigation_contract.dart';
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

/// 엘리베이터 확정이 났을 때 **도면과 앵커가 함께** 목표 층으로 옮겨가는지에
/// 대한 회귀 테스트.
///
/// 지키려는 증상 둘: 엘리베이터를 타도 층이 안 바뀌고, 층 선택기로 직접 바꿔도
/// 앵커가 옛 층이라 흐린 마커만 남았다. 층만 바꾸고 앵커를 안 옮기면 두 번째
/// 증상이 그대로 남으므로, 여기서는 **앵커 좌표가 도착 층 엘리베이터 노드**인지
/// 까지 본다.
///
/// 도착 노드를 좌표가 아니라 호기 이름으로 찾는다는 계약이 이 테스트의 핵심이다.
/// 두 층의 EV1을 일부러 멀리 떨어뜨려 둬서, 좌표로 이어 붙이면 앵커가 1F 자리에
/// 남고 검증이 깨진다.
///
/// MapLibre 레이어는 위젯 트리에 없어 마커 픽셀을 볼 수 없다. 대신 그 마커의
/// 유일한 근거인 PDR 앵커를 직접 본다(`outdoor_entrance_auto_anchor_test.dart`와
/// 같은 방식).
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

  List<Map<String, dynamic>> edges() => [
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
  ];

  // 통로 노드 셋은 두 층이 같다(한 직선 위에 없어야 좌표 피팅이 유일하게 풀린다).
  // 다른 것은 EV1의 자리뿐이다 — 도면 등록 오차로 같은 샤프트가 층마다 어긋나
  // 있는 실측 상황을 그대로 만든 것이다.
  Map<String, dynamic> graphFor(double evX, double evY) => {
    'nodes': [
      node('n-a', 18, 22),
      node('n-b', 48, 22),
      node('n-c', 18, 52),
      node('ev1', evX, evY, type: 'elevator', name: 'EV1'),
    ],
    'edges': edges(),
  };

  final graphs = {'1F': graphFor(20, 24), '2F': graphFor(40, 45)};

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

  /// 1층 도면을 열고 통로에 앵커를 찍는다. `applyVerticalTransfer`는 물려받을
  /// 회전값이 있어야 하므로(직전 앵커가 없으면 아무것도 안 한다), 확정을 태우기
  /// 전에 반드시 이 상태를 만들어 둬야 한다.
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

  testWidgets('엘리베이터 확정이 오면 도면이 목표 층으로 바뀌고 앵커가 그 층 엘리베이터에 선다', (
    WidgetTester tester,
  ) async {
    final key = await anchoredOnFirstFloor(tester);

    // **await로 붙잡지 않는다.** 도면 교체는 덮개가 올라오기를 기다리는데
    // (`Future.delayed`), 위젯 테스트의 시계는 pump로만 흐른다. 먼저 기다리면
    // 아무도 pump하지 않아 그대로 멈춘다.
    // ignore: invalid_use_of_visible_for_testing_member
    final applied = key.currentState!.applyElevatorTransitionForTest(
      const ElevatorTransition(
        fromFloorLabel: '1F',
        toFloorLabel: '2F',
        deltaM: 5.56,
        boardingNodeId: 'ev1',
        carName: 'EV1',
        durationMs: 12000,
        arrivalSource: 'table',
      ),
    );
    await drain(tester);
    await applied;
    await drain(tester);

    expect(key.currentState!.currentFloor, '2F');

    final anchor = indoorNavigationDriver.currentCalibration.anchor!;
    expect(anchor.floorId, '2F');
    // 2F의 EV1은 (40,45)다. 여기가 1F의 (20,24)로 남으면 마커는 건물 반대편에
    // 서고, 층만 바뀐 채 위치는 틀린 예전 증상이 그대로다.
    expect(anchor.anchorLocalM.eastM, closeTo(40, 0.5));
    expect(anchor.anchorLocalM.northM, closeTo(45, 0.5));
    expect(anchor.source, AnchorSource.verticalTransfer);
  });

  testWidgets('도착 호기를 못 찾으면 층만 바꾸고 위치 지정을 안내한다', (WidgetTester tester) async {
    // 호기를 모르는 노드에서 탔다(더현대 B3·B4에 이름 없는 엘리베이터 노드가
    // 실제로 있다). 억지로 가까운 호기에 세우면 사용자를 건물 반대편에 놓는다.
    final key = await anchoredOnFirstFloor(tester);
    final before = indoorNavigationDriver.currentCalibration.anchor!;

    // ignore: invalid_use_of_visible_for_testing_member
    final applied = key.currentState!.applyElevatorTransitionForTest(
      const ElevatorTransition(
        fromFloorLabel: '1F',
        toFloorLabel: '2F',
        deltaM: 5.56,
        boardingNodeId: 'ev1',
        carName: null,
        durationMs: 12000,
        arrivalSource: 'table',
      ),
    );
    await drain(tester);
    await applied;
    await drain(tester);

    // 조용히 넘어가면 사용자는 "고장"으로 읽는다. 할 일을 한 줄로 알린다.
    expect(find.textContaining('도착 지점을 찾지 못했습니다'), findsOneWidget);
    expect(key.currentState!.currentFloor, '2F');
    // 앵커는 옛 층에 그대로다 — 모르는 자리를 지어내지 않는다.
    expect(
      indoorNavigationDriver.currentCalibration.anchor?.floorId,
      before.floorId,
    );
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
