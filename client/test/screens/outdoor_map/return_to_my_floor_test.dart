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
/// **그 문은 GPS 버튼 하나다.** 한동안 다른 층에서만 뜨는 화살표 버튼을 따로
/// 두었는데, 하는 일이 같은 버튼이 화면에 둘이 되어 어느 쪽을 눌러야 내 자리로
/// 가는지가 갈렸다. 지금은 하단 바의 "위치 보정"이 부르는 [OutdoorMapBodyState.recalibrate]
/// 가 층부터 되돌린다 — 여기서 재는 것이 그 경로다.
///
/// 카메라는 여기서 확인하지 않는다(MapLibre 플랫폼 뷰가 위젯 테스트에 없다).
/// 확인하는 것은 **층이 돌아오는가**와 **화면에 그 문이 하나뿐인가** 둘이다.
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

  /// 하단 바는 셸이 그린다(이 테스트는 지도만 띄운다). 그 버튼이 부르는 것이
  /// [OutdoorMapBodyState.recalibrate]라, 그 호출을 그대로 대신한다.
  Future<void> tapCalibrate(
    WidgetTester tester,
    GlobalKey<OutdoorMapBodyState> key,
  ) async {
    await key.currentState!.recalibrate();
    await drain(tester);
  }

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

  testWidgets('다른 층을 열고 위치 보정을 누르면 내 층으로 돌아온다', (WidgetTester tester) async {
    final key = await openIndoorMap(tester);
    await placeAnchorOnCurrentFloor(tester, key);

    await openFloor(tester, key, '2F');
    await tapCalibrate(tester, key);

    expect(key.currentState!.currentFloor, '1F');
  });

  testWidgets('돌아온 뒤의 위치 보정은 층을 다시 건드리지 않는다', (WidgetTester tester) async {
    // 같은 층에서는 평소의 보정(중앙 정렬·회전)으로 돌아가야 한다 — 층 복귀는
    // 다른 층을 보는 동안에만 앞에 끼어드는 갈래다.
    final key = await openIndoorMap(tester);
    await placeAnchorOnCurrentFloor(tester, key);

    await openFloor(tester, key, '2F');
    await tapCalibrate(tester, key);
    await tapCalibrate(tester, key);

    expect(key.currentState!.currentFloor, '1F');
  });

  testWidgets('내 자리로 돌아가는 버튼은 화면에 둘이 아니다', (WidgetTester tester) async {
    // 다른 층을 보는 동안 화살표 버튼을 따로 띄우던 시절의 회귀를 막는다.
    // 그 일은 하단 바의 GPS 버튼 하나가 한다.
    final key = await openIndoorMap(tester);
    await placeAnchorOnCurrentFloor(tester, key);
    await openFloor(tester, key, '2F');

    expect(find.byIcon(Icons.near_me), findsNothing);
    expect(find.byKey(const Key('return-to-my-floor')), findsNothing);
  });

  testWidgets('위치를 아직 안 잡았으면 층도 그대로다', (WidgetTester tester) async {
    // 돌아갈 자리가 없다. 그 상태의 출구는 하단 바 "위치 지정"이라, 보정은
    // 그 버튼을 깜빡이고 층은 사용자가 고른 그대로 둔다.
    final key = await openIndoorMap(tester);

    await openFloor(tester, key, '2F');
    await tapCalibrate(tester, key);

    expect(key.currentState!.currentFloor, '2F');
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
