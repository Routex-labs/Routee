import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/building/category_count.dart';
import 'package:navigation_client/models/place/store_index_entry.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/models/building/building.dart';
import 'package:navigation_client/models/building/building_graph.dart';
import 'package:navigation_client/models/route/indoor_route.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:navigation_client/screens/outdoor_map/transition/indoor_transition_overlay.dart';
import 'package:navigation_client/screens/outdoor_map/transition/indoor_transition_timeline.dart';
import 'package:navigation_client/screens/outdoor_map/widgets/floor_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "밖으로 나가기" 버튼이 실제로 야외로 되돌리는지에 대한 회귀 테스트.
///
/// GPS로 이탈을 알아채던 흐름은 걷어냈다 — 건물 안 좌표는 오차가 십수 m라
/// 벽 안팎을 가르지 못했고, 튄 좌표 한 건이 건물 안에 선 사용자의 도면과 위치를
/// 통째로 지웠다. 지금 나가는 것은 사용자가 누른 순간뿐이다.
///
/// 실내 여부는 층 선택기([FloorSelector]) 노출로 판정한다 — 실내 오버레이가
/// 켜졌을 때만 뜨는 위젯이다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  const metersPerDegreeLat = 111320.0;
  const metersPerDegreeLng = 88243.0;
  const originLat = 37.5663;
  const originLng = 126.9777;

  /// 건물 안. 외곽선(위도 37.5663~37.5667)의 한가운데라 어느 변에서도 17 m 넘게
  /// 들어와 있어, 진입 기준(안쪽 5 m)을 넉넉히 넘는다.
  const entrance = LatLng(37.5665, 126.9779);

  /// 건물 밖. 북쪽 변에서 약 33 m 떨어져 있다 — 나간 뒤 카메라가 따라갈 좌표다.
  const wellOutside = LatLng(37.5670, 126.9780);


  Map<String, dynamic> node(String id, double xM, double yM) => {
    'id': id,
    'type': 'corridor',
    'x_m': xM,
    'y_m': yM,
    'lat': originLat + yM / metersPerDegreeLat,
    'lng': originLng + xM / metersPerDegreeLng,
  };

  // 입구는 층 로컬로 약 (17.6, 22.3)이라 n-a 바로 옆이다. 자동 앵커가 여기에
  // 찍히므로 PDR 위치도 입구 앞이 되고, 그래서 이탈 감시가 켜진다.
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

  Position fix(LatLng point, double accuracy) => Position(
    latitude: point.latitude,
    longitude: point.longitude,
    timestamp: DateTime(2024, 1, 1),
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
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
    final repository = _GraphBuildingRepository(graphJson);
    buildingRepository = repository;
    destinationRepository = MockDestinationRepository(repository);
    requestStartupPermissions = () async => {};
    messenger().setMockMethodCallHandler(commandChannel, (call) async => 1);
    messenger().setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(onListen: (arguments, sink) {}),
    );
  });

  tearDown(() async {
    await indoorNavigationDriver.stopGuidance();
    messenger().setMockMethodCallHandler(commandChannel, null);
    messenger().setMockStreamHandler(eventChannel, null);
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    requestStartupPermissions = defaultRequestStartupPermissions;
    watchPosition = defaultWatchPosition;
  });

  /// 야외 지도를 띄우고, 문 앞 좌표를 흘린 뒤 **진입 버튼과 같은 함수**로
  /// 들어간다. 좌표만으로는 더 이상 들어가지지 않는다.
  Future<void> enterIndoorByButton(
    WidgetTester tester,
    StreamController<Position> positions,
  ) async {
    watchPosition = () => positions.stream;
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: Scaffold(body: OutdoorMapBody())),
    );
    await drain(tester);
    positions.add(fix(entrance, 10));
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);
    expect(
      find.byType(FloorSelector),
      findsNothing,
      reason: '좌표 한 건이 화면을 실내로 바꾸면 안 된다',
    );
    // **await하지 않는다.** 이 Future는 전환 연출이 끝나야 완료되는데 그 시계를
    // 미는 것이 아래 drain이다 — 기다리면 서로를 기다리며 테스트가 멈춘다.
    unawaited(
      tester
          .state<OutdoorMapBodyState>(find.byType(OutdoorMapBody))
          .enterIndoorFromGuidance(),
    );
    await drain(tester);
    expect(
      find.byType(FloorSelector),
      findsOneWidget,
      reason: '테스트 전제(진입 버튼으로 실내 진입)가 성립하지 않았다',
    );
  }

  /// 나가기 버튼과 같은 함수를 부른다.
  Future<void> leaveIndoorByButton(WidgetTester tester) async {
    tester
        .state<OutdoorMapBodyState>(find.byType(OutdoorMapBody))
        .exitIndoorFromGuidance();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// 앵커를 기다리는 센서 준비 타이머(2초)를 흘려보낸다. 남겨 두면 테스트가
  /// "타이머가 살아 있다"로 넘어진다.
  Future<void> settleSensorWarmup(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
    await drain(tester);
  }

  testWidgets('좌표가 건물 밖으로 나가도 스스로 접지 않는다', (WidgetTester tester) async {
    // **이 파일이 지키는 가장 중요한 계약이다.** 예전에는 이 좌표 한 건이 실내
    // 상태를 통째로 접었다. 건물 안에서 켠 GPS는 좌표가 밖으로 튀는 일이 흔한데,
    // 그때마다 사용자는 건물 한가운데에서 도면과 위치 아이콘을 잃었다.
    final positions = StreamController<Position>.broadcast();
    await enterIndoorByButton(tester, positions);
    await settleSensorWarmup(tester);
    expect(
      positions.hasListener,
      isTrue,
      reason: '실내에서도 구독은 끊기지 않는다 — 진입 게이트가 다시 열리려면 좌표가 필요하다',
    );

    positions.add(fix(wellOutside, 8));
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);
    expect(find.byType(FloorSelector), findsOneWidget);
  });

  testWidgets('나가기 버튼을 누르면 야외로 되돌아간다', (WidgetTester tester) async {
    final positions = StreamController<Position>.broadcast();
    await enterIndoorByButton(tester, positions);
    await settleSensorWarmup(tester);

    await leaveIndoorByButton(tester);
    await drain(tester);
    expect(find.byType(FloorSelector), findsNothing);
  });

  testWidgets('실내에서 들어온 GPS 좌표는 화면에 쓰지 않는다', (WidgetTester tester) async {
    // 이 좌표가 마커·배지 쪽으로 새면, 실내 도면 위에 건물 밖 GPS 점이 찍히던
    // 예전 문제가 그대로 돌아온다. MapLibre 레이어는 위젯 트리에 없으므로
    // 'GPS 신호 약함' 배지로 대신 본다 — 배지는 GPS 기반 표시가 살아 있을 때만
    // 뜬다.
    final positions = StreamController<Position>.broadcast();
    await enterIndoorByButton(tester, positions);
    await settleSensorWarmup(tester);

    positions.add(fix(entrance, 45));
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);

    expect(find.byType(FloorSelector), findsOneWidget);
    expect(find.text('GPS 신호 약함'), findsNothing);
  });

  testWidgets('나가기 버튼을 누르면 실내 위치 추정치를 버린다', (WidgetTester tester) async {
    // 이 추정치는 GPS를 층 그래프에 투영한 값이고 **30초 동안 살아 있다**
    // (IndoorLocationEstimate.isFresh). 앵커가 없을 때의 마지막 폴백이라,
    // 안 버리면 야외로 나간 뒤에도 30초간 실내 좌표가 유효한 채로 남는다.
    // 한때 clear()를 부르는 코드가 앱 전체에 하나도 없었다.
    final positions = StreamController<Position>.broadcast();
    await enterIndoorByButton(tester, positions);
    await settleSensorWarmup(tester);

    expect(
      indoorLocationEstimateController.current,
      isNotNull,
      reason: '테스트 전제(진입이 추정치를 채움)가 성립하지 않았다',
    );

    await leaveIndoorByButton(tester);
    await drain(tester);

    expect(find.byType(FloorSelector), findsNothing);
    expect(
      indoorLocationEstimateController.current,
      isNull,
      reason: '야외에 선 사용자에게 30초짜리 실내 좌표가 남아 있으면 안 된다',
    );
  });

  group('전환 연출은 실제 진입·이탈에서만 뜬다', () {
    // **이 구분이 연출의 핵심 계약이다.** 건물 탭·홈 버튼처럼 사용자가 도면을
    // 여닫는 조작에까지 붙으면, 2 km 밖에서 건물을 눌러 본 사람에게 "들어가는
    // 중"이라고 말하게 된다.
    testWidgets('진입 버튼에서는 문과 문구가 뜬다', (WidgetTester tester) async {
      final positions = StreamController<Position>.broadcast();
      watchPosition = () => positions.stream;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: OutdoorMapBody()),
        ),
      );
      await drain(tester);
      positions.add(fix(entrance, 10));
      await tester.pump(const Duration(milliseconds: 50));
      await drain(tester);

      unawaited(
        tester
            .state<OutdoorMapBodyState>(find.byType(OutdoorMapBody))
            .enterIndoorFromGuidance(),
      );
      // 덮개가 덮이는 중간을 잡는다. drain까지 돌리면 연출이 끝나 버려서 "떴다"를
      // 확인할 수 없다.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(
        indoorTransitionSwapDelay(IndoorTransitionDirection.enter),
      );
      expect(find.byType(IndoorTransitionOverlay), findsOneWidget);
      expect(find.textContaining('들어가는 중'), findsOneWidget);

      await drain(tester);
      await settleSensorWarmup(tester);
      // 연출이 끝나면 스스로 사라진다. 남으면 지도 위에 흰 막이 굳는다.
      expect(find.textContaining('들어가는 중'), findsNothing);
    });

    testWidgets('나가기 버튼에서는 나가는 문구가 뜬다', (WidgetTester tester) async {
      final positions = StreamController<Position>.broadcast();
      await enterIndoorByButton(tester, positions);
      await settleSensorWarmup(tester);

      await leaveIndoorByButton(tester);
      await tester.pump(
        indoorTransitionSwapDelay(IndoorTransitionDirection.exit),
      );
      expect(find.textContaining('나가는 중'), findsOneWidget);
      await drain(tester);
      await settleSensorWarmup(tester);
    });

    testWidgets('홈으로 도면을 접는 것은 이탈이 아니라 연출이 없다', (
      WidgetTester tester,
    ) async {
      // 도면만 접는 조작이다. 사용자는 여전히 건물 안에 서 있을 수 있으므로
      // "밖으로 나가는 중"은 거짓말이 된다.
      final positions = StreamController<Position>.broadcast();
      await enterIndoorByButton(tester, positions);
      await settleSensorWarmup(tester);

      final state = tester.state<OutdoorMapBodyState>(
        find.byType(OutdoorMapBody),
      );
      await state.returnToOutdoorView();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('나가는 중'), findsNothing);
      await drain(tester);
    });

    testWidgets('건물 밖 탭으로 나오는 것도 연출이 없다', (WidgetTester tester) async {
      final positions = StreamController<Position>.broadcast();
      await enterIndoorByButton(tester, positions);
      await settleSensorWarmup(tester);

      final state = tester.state<OutdoorMapBodyState>(
        find.byType(OutdoorMapBody),
      );
      // ignore: invalid_use_of_visible_for_testing_member
      await state.handleMapClickForTest(const LatLng(37.5680, 126.9800));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('나가는 중'), findsNothing);
      await drain(tester);
    });
  });
}

class _GraphBuildingRepository implements BuildingRepository {
  // 카테고리 pill은 이 테스트들의 관심사가 아니다. 빈 목록이면 pill 줄이 아예
  // 뜨지 않아 검증 대상 화면이 그대로 유지된다.
  @override
  Future<List<CategoryCount>?> getCategoryCounts(String buildingId) async =>
      const [];

  // 자동완성 원본. 이 테스트들은 후보를 보지 않으므로 빈 목록으로 둔다 —
  // 패널은 목록이 비면 후보를 그리지 않고 서버 검색만 돈다.
  @override
  Future<List<StoreIndexEntry>?> getStoreIndex(String buildingId) async =>
      const [];
  _GraphBuildingRepository(this.graphJson);

  final Map<String, dynamic> graphJson;

  static const _building = Building(
    id: 'thehyundai-seoul',
    name: '데모 건물',
    floors: ['1F'],
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
    if (buildingId != _building.id || floor != '1F') return null;
    // API 응답 모양(footprint_wgs84 + stores)으로 준다. GeoJSON 모양에는 지상
    // 출입구를 심을 자리가 없는데, 진입·나가기 버튼은 그 문 목록이 있어야 한다.
    return {
      'footprint_wgs84': [
        for (final point in _building.footprintWgs84!)
          {'lat': point.latitude, 'lng': point.longitude},
      ],
      'stores': [
        // 소분류 '교통' + entrance_node_id가 있어야 지상 출입구로 추려진다
        // (`domain/route/building_entrances.dart`의 groundEntrancesFrom).
        {
          'id': 'door-a',
          'name': '출구',
          'subcategory': '교통',
          'entrance_node_id': 'n-a',
          'centroid_wgs84': {'lat': 37.5665, 'lng': 126.9779},
        },
      ],
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
