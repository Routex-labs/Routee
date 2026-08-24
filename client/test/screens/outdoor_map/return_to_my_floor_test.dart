import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/building/category_count.dart';
import 'package:navigation_client/models/place/store_index_entry.dart';
import 'package:navigation_client/core/api_config.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/models/building/building.dart';
import 'package:navigation_client/models/building/building_graph.dart';
import 'package:navigation_client/models/route/indoor_route.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:navigation_client/screens/outdoor_map/widgets/floor_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **다른 층을 훑다가 내 자리로 돌아오는 문**의 검증 기준.
///
/// 증상: 1층에 서서 2층 도면을 열면 위치 마커가 흐린 점으로 물러나고, 그때
/// 하단 바 "위치 보정"은 아무 일도 하지 않은 채 "위치 지정" 버튼만 깜빡였다 —
/// 위치는 이미 잡혀 있는데 다시 잡으라고 말하는 셈이라, 층을 훑어본 사용자에게
/// 돌아올 문이 없었다.
///
/// 카메라는 여기서 확인하지 않는다(MapLibre 플랫폼 뷰가 위젯 테스트에 없다).
/// 확인하는 것은 **층이 돌아오는가**와 **그 문이 필요할 때만 보이는가** 둘이다.
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

  // 세 노드가 한 직선 위에 있지 않아야 좌표 피팅이 유일하게 풀린다
  // (pdr_anchor_floor_rebind_test와 같은 도면).
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

  final returnButton = find.byKey(const Key('return-to-my-floor'));

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

  /// 1층 복도 한 점에 앵커를 찍는다. 실기기와 같은 두 걸음("위치 지정"을 누르고
  /// 지도를 탭한다)을 그대로 지난다.
  Future<void> placeAnchorOnCurrentFloor(
    WidgetTester tester,
    GlobalKey<OutdoorMapBodyState> key,
  ) async {
    await key.currentState!.startLocationPlacement();
    await drain(tester);
    // ignore: invalid_use_of_visible_for_testing_member
    final placing = key.currentState!.handleMapClickForTest(
      const LatLng(
        originLat + 22 / metersPerDegreeLat,
        originLng + 18 / metersPerDegreeLng,
      ),
    );
    await drain(tester);
    // 절대 heading을 못 얻는 기기는 진행 방향을 되묻는다(가짜 센서가 그렇다).
    // 실기기에서 사용자가 누르는 그 한 번을 대신 누른다 — 안 누르면 앵커가
    // 확정되지 않아 이 테스트의 전제가 성립하지 않는다.
    final upward = find.widgetWithText(TextButton, '위쪽');
    if (upward.evaluate().isNotEmpty) {
      await tester.tap(upward);
      await drain(tester);
    }
    await placing;
  }

  /// 층 선택기 콜백을 직접 부른다. 좌표 탭은 선택기의 스크롤 위치까지 테스트하게
  /// 된다(pdr_anchor_floor_rebind_test와 같은 이유).
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

  testWidgets('내 층에 있는 동안에는 돌아오는 문을 띄우지 않는다', (WidgetTester tester) async {
    // 같은 층에서는 하단 바 "위치 보정"이 이미 그 일을 한다. 늘 띄우면 비슷하게
    // 생긴 두 조작이 화면에 남는다.
    final key = await openIndoorMap(tester);
    await placeAnchorOnCurrentFloor(tester, key);

    expect(returnButton, findsNothing);
  });

  testWidgets('다른 층을 열면 문이 뜨고, 누르면 내 층으로 돌아온다', (WidgetTester tester) async {
    final key = await openIndoorMap(tester);
    await placeAnchorOnCurrentFloor(tester, key);

    await openFloor(tester, key, '2F');
    expect(returnButton, findsOneWidget, reason: '흐린 점만 남은 화면에 돌아올 문이 없다');

    await tester.tap(returnButton);
    await drain(tester);

    expect(key.currentState!.currentFloor, '1F');
    // 돌아왔으면 문도 함께 사라진다 — 남으면 아무 일도 안 하는 버튼이 된다.
    expect(returnButton, findsNothing);
  });

  testWidgets('위치를 아직 안 잡았으면 다른 층에서도 문이 없다', (WidgetTester tester) async {
    // 돌아갈 자리가 없는데 문을 띄우면 눌러도 아무 일이 없다. 그 상태의 출구는
    // 하단 바 "위치 지정"이다.
    final key = await openIndoorMap(tester);

    await openFloor(tester, key, '2F');

    expect(returnButton, findsNothing);
  });
}

/// 두 층 모두 같은 navigation_graph를 내려주는 가짜 저장소.
class _TwoFloorGraphRepository implements BuildingRepository {
  _TwoFloorGraphRepository(this.graphJson);

  final Map<String, dynamic> graphJson;

  // 카테고리 pill·자동완성은 이 테스트의 관심사가 아니다. 비워 두면 그 줄이
  // 아예 뜨지 않아 검증 대상 화면이 그대로 유지된다.
  @override
  Future<List<CategoryCount>?> getCategoryCounts(String buildingId) async =>
      const [];

  @override
  Future<Map<String, dynamic>?> getBuildingEvents(String buildingId) async =>
      null;

  @override
  Future<List<StoreIndexEntry>?> getStoreIndex(String buildingId) async =>
      const [];

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
