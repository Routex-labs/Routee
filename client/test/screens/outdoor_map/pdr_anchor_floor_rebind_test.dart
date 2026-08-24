import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/building/category_count.dart';
import 'package:navigation_client/models/place/store_index_entry.dart';
import 'package:navigation_client/core/api_config.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/features/indoor_navigation/contract/indoor_navigation_contract.dart';
import 'package:navigation_client/models/building/building.dart';
import 'package:navigation_client/models/building/building_graph.dart';
import 'package:navigation_client/models/route/indoor_route.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:navigation_client/screens/outdoor_map/widgets/floor_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 층을 옮긴 뒤 위치를 다시 지정할 수 있는지에 대한 회귀 테스트.
///
/// 지키려는 증상: 1층에서 한 번 위치를 지정하면, 2층으로 올라가 "위치 지정"을
/// 눌러 지도를 탭해도 아무 일도 일어나지 않았다. PDR 세션의 층은 세션을 처음
/// 시작할 때 한 번만 정해졌고, 화면은 세션이 이미 돌고 있으면 그대로 재사용했다.
/// 그래서 2층에서 찍은 앵커에도 층이 `1F`로 찍혔고, 위치 마커·경로는 모두
/// `anchor.floorId == 지금 보고 있는 층`을 요구하므로 2층 지도에는 아무것도
/// 그려지지 않았다. 오류도 안 뜨니 "위치 지정이 안 된다"로만 보였다.
///
/// 세션의 층([IndoorNavigationView.currentFloorId])이 앵커의 층이 되므로, 여기서
/// 고정하는 것은 그 값이다. 앵커에 그 값이 그대로 찍힌다는 계약은 컨트롤러
/// 테스트(`test/features/indoor_navigation/controller_test.dart`)가 지킨다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  const metersPerDegreeLat = 111320.0;
  const metersPerDegreeLng = 88243.0;
  const originLat = 37.5663;
  const originLng = 126.9777;

  Map<String, dynamic> node(String id, double xM, double yM) => {
    'id': id,
    'type': 'corridor',
    'x_m': xM,
    'y_m': yM,
    'lat': originLat + yM / metersPerDegreeLat,
    'lng': originLng + xM / metersPerDegreeLng,
  };

  // 세 노드가 한 직선 위에 있지 않아야 좌표 피팅이 유일하게 풀린다. 두 층이
  // 같은 도면을 쓰므로, 층 말고는 조건이 완전히 같다.
  final graphJson = <String, dynamic>{
    'nodes': [node('n-a', 18, 22), node('n-b', 48, 22), node('n-c', 18, 52)],
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

  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  // native PDR 채널. 핸들러가 없으면 startGuidance가 곧장 degraded로 빠져
  // 세션이 정상 경로를 타지 않는다.
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
    // 위치 지정은 권한 게이트를 지나야 세션을 시작한다. 실제 plugin을 부르면
    // 테스트에서 응답이 오지 않으므로 service_locator의 seam을 교체한다.
    isPedometerPermissionGranted = () async => true;
    messenger().setMockMethodCallHandler(commandChannel, (call) async => 1);
    messenger().setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(onListen: (arguments, sink) {}),
    );
    final repository = _TwoFloorGraphRepository(graphJson);
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

  Future<GlobalKey<OutdoorMapBodyState>> openIndoorMap(
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
    expect(
      key.currentState!.currentFloor,
      '1F',
      reason: '테스트 전제(1층 도면 로드)가 성립하지 않았다',
    );
    return key;
  }

  /// 층 chip으로 [floor] 도면을 연다. 층 선택기는 PDR 세션을 건드리지 않는다 —
  /// "다른 층 지도를 훑어보는" 동작이지 사용자가 이동했다는 신호가 아니다.
  ///
  /// chip을 좌표로 탭하지 않고 콜백을 직접 부른다. 층 선택기는 5칸만 보이는
  /// 세로 스크롤이라 원하는 층이 클립된 자리에 있으면 탭이 빗나가고, 그러면
  /// 검증하려는 것(층이 바뀐 뒤의 위치 지정)이 아니라 선택기의 스크롤 위치를
  /// 테스트하게 된다.
  Future<void> openFloor(
    WidgetTester tester,
    GlobalKey<OutdoorMapBodyState> key,
    String floor,
  ) async {
    tester
        .widget<FloorSelector>(find.byType(FloorSelector))
        .onSelectFloor(floor);
    await drain(tester);
    expect(key.currentState!.currentFloor, floor);
  }

  testWidgets('다른 층에서 위치 지정을 누르면 PDR 세션이 그 층으로 옮겨간다', (
    WidgetTester tester,
  ) async {
    final key = await openIndoorMap(tester);

    await key.currentState!.startLocationPlacement();
    await drain(tester);
    expect(indoorNavigationDriver.currentFloorId, '1F');

    await openFloor(tester, key, '2F');
    // 층만 바꾼 시점에는 세션이 그대로여야 한다. 지도를 훑어봤을 뿐이다.
    expect(indoorNavigationDriver.currentFloorId, '1F');

    await key.currentState!.startLocationPlacement();
    await drain(tester);

    // 여기가 1F로 남으면 이후 어디를 탭해도 앵커가 1층으로 기록돼, 2층 지도에는
    // 위치가 영영 나타나지 않는다.
    expect(indoorNavigationDriver.currentFloorId, '2F');
  });

  testWidgets('같은 층에서 다시 지정할 때는 세션을 그대로 둔다', (WidgetTester tester) async {
    // 층이 같은데도 세션을 갈아엎으면(changeFloor) 걸음 세션이 리셋되고 앵커도
    // 버려진다. 위치만 다시 찍으려던 사용자에게는 손해다.
    final key = await openIndoorMap(tester);

    await key.currentState!.startLocationPlacement();
    await drain(tester);
    final firstPhase = indoorNavigationDriver.currentCalibration.phase;

    await key.currentState!.startLocationPlacement();
    await drain(tester);

    expect(indoorNavigationDriver.currentFloorId, '1F');
    expect(indoorNavigationDriver.currentCalibration.phase, firstPhase);
  });

  testWidgets('층을 되돌아오면 세션도 그 층으로 다시 붙는다', (WidgetTester tester) async {
    // 계단을 오르내리며 여러 번 다시 잡는 경우. 한 방향(1F→2F)만 동작하고
    // 되돌아올 때 막히면 사용자는 같은 증상을 다시 겪는다.
    final key = await openIndoorMap(tester);

    await key.currentState!.startLocationPlacement();
    await drain(tester);
    await openFloor(tester, key, '2F');
    await key.currentState!.startLocationPlacement();
    await drain(tester);
    expect(indoorNavigationDriver.currentFloorId, '2F');

    await openFloor(tester, key, '1F');
    await key.currentState!.startLocationPlacement();
    await drain(tester);

    expect(indoorNavigationDriver.currentFloorId, '1F');
  });
}

/// 두 층 모두 같은 navigation_graph를 내려주는 가짜 저장소. mock asset의 층에는
/// 그래프가 없어 "위치 지정"이 시작 조건에서 걸린다.
class _TwoFloorGraphRepository implements BuildingRepository {
  // 카테고리 pill은 이 테스트들의 관심사가 아니다. 빈 목록이면 pill 줄이 아예
  // 뜨지 않아 검증 대상 화면이 그대로 유지된다.
  @override
  Future<List<CategoryCount>?> getCategoryCounts(String buildingId) async =>
      const [];

  // 자동완성 원본. 이 테스트들은 후보를 보지 않으므로 빈 목록으로 둔다 —
  // 패널은 목록이 비면 후보를 그리지 않고 서버 검색만 돈다.
  @override
  Future<Map<String, dynamic>?> getBuildingEvents(String buildingId) async =>
      null;

  @override
  Future<List<StoreIndexEntry>?> getStoreIndex(String buildingId) async =>
      const [];
  _TwoFloorGraphRepository(this.graphJson);

  final Map<String, dynamic> graphJson;

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
  Future<List<Building>> getAllBuildings() async => const [_building];

  @override
  Future<Building?> getBuilding(String buildingId) async =>
      buildingId == _building.id ? _building : null;

  @override
  Future<Map<String, dynamic>?> getFloorGeoJson(
    String buildingId,
    String floor,
  ) async {
    if (buildingId != _building.id || !_building.floors.contains(floor)) {
      return null;
    }
    return {
      'type': 'FeatureCollection',
      'features': <Map<String, dynamic>>[],
      'navigation_graph': graphJson,
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
