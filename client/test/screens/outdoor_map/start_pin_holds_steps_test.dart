import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/building/category_count.dart';
import 'package:navigation_client/models/place/store_index_entry.dart';
import 'package:navigation_client/core/api_config.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/features/indoor_navigation/application/indoor_navigation_controller.dart';
import 'package:navigation_client/models/building/building.dart';
import 'package:navigation_client/models/building/building_graph.dart';
import 'package:navigation_client/models/route/indoor_route.dart';
import 'package:navigation_client/models/place/poi_search_result.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 출발 위치를 지정한 뒤 `안내 시작`을 누르기 전까지 위치 아이콘이 혼자
/// 움직이지 않는지에 대한 회귀 테스트.
///
/// 지키려는 증상: 지도를 탭해 "나는 여기 있다"고 지정해 두고 목적지를 고르는
/// 동안, 제자리에 서 있는데도 아이콘이 지정한 자리에서 흘러가 있었다. 걸음
/// 판정은 제자리 흔들림도 걸음으로 세기 때문이다.
///
/// 지도 레이어는 위젯 트리에 없어 아이콘 픽셀을 볼 수 없다. 대신 그 멈춤의
/// 유일한 근거인 드라이버의 보류 상태를 본다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  const metersPerDegreeLat = 111320.0;
  const metersPerDegreeLng = 88243.0;
  const originLat = 37.5663;
  const originLng = 126.9777;

  LatLng wgs84(double xM, double yM) => LatLng(
    originLat + yM / metersPerDegreeLat,
    originLng + xM / metersPerDegreeLng,
  );

  Map<String, dynamic> node(String id, double xM, double yM) => {
    'id': id,
    'type': 'corridor',
    'x_m': xM,
    'y_m': yM,
    'lat': wgs84(xM, yM).latitude,
    'lng': wgs84(xM, yM).longitude,
  };

  // 세 노드가 한 직선 위에 있지 않아야 좌표 피팅이 유일하게 풀린다.
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

  bool stepsHeld() =>
      (indoorNavigationDriver as IndoorNavigationDriver).stepsHeldBeforeStart;

  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// 진행 방향 모달이 떠 있으면 눌러 닫는다. 자북 heading을 못 얻는 기기(테스트
  /// 환경이 그렇다)는 앵커 확정 도중 이 모달로 진행 방향을 물어본다.
  Future<void> answerHeadingPromptIfShown(WidgetTester tester) async {
    if (find.text('위쪽').evaluate().isEmpty) return;
    await tester.tap(find.text('위쪽'));
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// [condition]이 참이 될 때까지 프레임을 진행시킨다. 앵커 확정은 heading
  /// 수렴을 실제 시계로 기다리므로 고정 횟수 pump로는 앞서 나간다.
  Future<void> pumpUntil(WidgetTester tester, bool Function() condition) async {
    final giveUpAt = DateTime.now().add(const Duration(seconds: 30));
    while (!condition() && DateTime.now().isBefore(giveUpAt)) {
      await tester.pump(const Duration(milliseconds: 100));
      await answerHeadingPromptIfShown(tester);
    }
    await drain(tester);
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
    // 위치 지정은 권한 게이트를 지나야 세션을 시작한다.
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
    return key;
  }

  /// 하단 바 "위치 지정" → 복도 탭. 사용자가 출발점을 직접 찍는 그 순서다.
  Future<void> pinStart(
    WidgetTester tester,
    OutdoorMapBodyState state,
    LatLng point,
  ) async {
    await state.startLocationPlacement();
    await drain(tester);
    // ignore: invalid_use_of_visible_for_testing_member
    unawaited(state.handleMapClickForTest(point));
    await pumpUntil(
      tester,
      () => indoorNavigationDriver.currentCalibration.anchor != null,
    );
  }

  PoiSearchResult storeOn(String floor, {String nodeId = 'n-a'}) =>
      PoiSearchResult(
        name: 'MLB',
        floor: floor,
        point: wgs84(18, 22),
        nodeId: nodeId,
      );

  testWidgets('출발 위치를 지정하면 안내 시작 전까지 걸음을 붙든다', (WidgetTester tester) async {
    final key = await openIndoorMap(tester);

    await pinStart(tester, key.currentState!, wgs84(18, 52));

    expect(stepsHeld(), isTrue, reason: '지정한 자리에 세워 두지 않으면 아이콘이 혼자 흘러간다');
  });

  testWidgets('안내 시작을 누르면 그때부터 걸음이 위치를 민다', (WidgetTester tester) async {
    final key = await openIndoorMap(tester);
    final state = key.currentState!;

    await pinStart(tester, state, wgs84(18, 52));
    expect(stepsHeld(), isTrue);

    // 목적지를 고르면 계획 카드까지만 뜬다 — 거기서도 아직 붙들고 있어야 한다.
    await state.showIndoorRouteTo(
      PoiSearchResult(
        name: '올리브영',
        floor: '1F',
        point: wgs84(48, 22),
        nodeId: 'n-b',
      ),
      origin: storeOn('1F'),
      preview: true,
    );
    await drain(tester);
    expect(stepsHeld(), isTrue);

    await state.startGuidanceForPickedRoute();
    await drain(tester);

    expect(
      stepsHeld(),
      isFalse,
      reason: '시작을 눌렀는데도 붙들고 있으면 걸어도 아이콘이 안 움직인다',
    );
  });
}
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

  /// **여기가 원본 픽스처와 다른 점이다.** null을 돌려주면 계획 화면이 경로를
  /// 못 그려, `안내 시작`이 누를 것도 없이 되돌아간다.
  @override
  Future<IndoorRoute?> getShortestRoute(
    String buildingId,
    String floor,
    String startNodeId,
    String endNodeId,
  ) async {
    final start = _nodePoint(startNodeId);
    final end = _nodePoint(endNodeId);
    if (start == null || end == null) return null;
    return IndoorRoute(
      points: [start, end],
      distanceMeters: const Distance().as(LengthUnit.Meter, start, end),
      nodeIds: [startNodeId, endNodeId],
    );
  }

  LatLng? _nodePoint(String nodeId) {
    for (final node in graphJson['nodes'] as List<dynamic>) {
      final row = node as Map<String, dynamic>;
      if (row['id'] != nodeId) continue;
      return LatLng(row['lat'] as double, row['lng'] as double);
    }
    return null;
  }

  @override
  Future<BuildingGraph?> getBuildingGraph(
    String buildingId, {
    String vertical = 'auto',
  }) async => null;
}
