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
import 'package:navigation_client/screens/outdoor_map/entry/indoor_entry_gps.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:navigation_client/screens/outdoor_map/transition/indoor_transition_overlay.dart';
import 'package:navigation_client/screens/outdoor_map/transition/indoor_transition_timeline.dart';
import 'package:navigation_client/screens/outdoor_map/widgets/floor_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "밖으로 나갔다"를 GPS로 알아채는 흐름에 대한 회귀 테스트.
///
/// 판정 근거는 좌표 하나다 — **믿을 수 있는 좌표가 건물 외곽선 밖으로 충분히
/// 나갔는가**([indoor_entry_gps.dart]). 그래서 실내에서도 구독을 끊지 않는다.
/// 끊으면 사용자가 아무 조작 없이 걸어 나갔을 때 알 방법이 없다.
///
/// 구독이 살아 있는지는 broadcast 스트림의 `hasListener`로 본다. 실내 여부는
/// 층 선택기([FloorSelector]) 노출로 판정한다 — 실내 오버레이가 켜졌을 때만
/// 뜨는 위젯이다.
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

  /// 건물 밖. 북쪽 변에서 약 33 m 떨어져 이탈 기준([outdoorExitMarginMeters])을
  /// 넉넉히 넘는다.
  const wellOutside = LatLng(37.5670, 126.9780);

  /// 벽 바로 밖 — 완충 구간 **한가운데**라 어느 쪽으로도 판정하지 않는다. 실내에서
  /// 켠 GPS가 흔히 주는, 조금 튄 좌표다. 숫자를 박지 않고 이탈 기준에서 잡는 이유는
  /// 그 상수를 조였을 때 이 좌표만 조용히 완충 밖으로 밀려나기 때문이다.
  const justOutside = LatLng(
    37.5667 + outdoorExitMarginMeters / 2 / metersPerDegreeLat,
    126.9780,
  );

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

  /// 건물 안 좌표 한 건으로 자동 진입시킨다. 진입 근거가 "믿을 수 있는 좌표가
  /// 건물 안"이므로 신호를 무너뜨릴 필요가 없다 — 예전 판정이 요구하던
  /// "입구 앞 + 신호 저하" 짝이 여기서 사라졌다.
  Future<void> enterIndoorByGps(
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
      findsOneWidget,
      reason: '테스트 전제(자동 실내 진입)가 성립하지 않았다',
    );
  }

  /// 앵커를 기다리는 센서 준비 타이머(2초)를 흘려보낸다. 남겨 두면 테스트가
  /// "타이머가 살아 있다"로 넘어진다.
  Future<void> settleSensorWarmup(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
    await drain(tester);
  }

  testWidgets('들어오자마자 돌아 나가도 앵커를 기다리지 않고 알아챈다', (WidgetTester tester) async {
    // 진입 직후에는 앵커가 아직 없어 PDR이 위치를 말하지 못한다. 예전에는 그동안
    // GPS가 꺼져 있어서, 문을 통과했다 바로 돌아 나가는 사용자를 놓쳤다 —
    // 정작 가장 확인이 필요한 순간이다.
    final positions = StreamController<Position>.broadcast();
    await enterIndoorByGps(tester, positions);
    expect(
      positions.hasListener,
      isTrue,
      reason: '실내에서도 구독은 끊기지 않아야 한다 — 이탈 판정의 유일한 입력이다',
    );

    positions.add(fix(wellOutside, 8));
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);
    expect(find.byType(FloorSelector), findsNothing);

    await settleSensorWarmup(tester);
  });

  testWidgets('건물 안이나 벽 바로 밖에서는 도면을 접지 않는다', (WidgetTester tester) async {
    final positions = StreamController<Position>.broadcast();
    await enterIndoorByGps(tester, positions);
    await settleSensorWarmup(tester);

    // 신호가 나쁜 좌표 — 실내에서 흔히 나오는 값이다. 이걸로 나갔다고 보면
    // 안에 있는 사용자의 도면이 제멋대로 닫힌다.
    positions.add(fix(wellOutside, 45));
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);
    expect(find.byType(FloorSelector), findsOneWidget);

    // 믿을 수 있지만 벽 바로 밖인 좌표 — 실내에서 조금 튄 값과 구분할 수 없다.
    positions.add(fix(justOutside, 8));
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);
    expect(find.byType(FloorSelector), findsOneWidget);

    // 건물에서 확실히 벗어나야 접는다.
    positions.add(fix(wellOutside, 8));
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);
    expect(find.byType(FloorSelector), findsNothing);
  });

  testWidgets('실내에서 들어온 GPS 좌표는 화면에 쓰지 않는다', (WidgetTester tester) async {
    // 이 좌표가 마커·배지 쪽으로 새면, 실내 도면 위에 건물 밖 GPS 점이 찍히던
    // 예전 문제가 그대로 돌아온다. MapLibre 레이어는 위젯 트리에 없으므로
    // 'GPS 신호 약함' 배지로 대신 본다 — 배지는 GPS 기반 표시가 살아 있을 때만
    // 뜬다.
    final positions = StreamController<Position>.broadcast();
    await enterIndoorByGps(tester, positions);
    await settleSensorWarmup(tester);

    positions.add(fix(entrance, 45));
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);

    expect(find.byType(FloorSelector), findsOneWidget);
    expect(find.text('GPS 신호 약함'), findsNothing);
  });

  testWidgets('밖으로 나가면 실내 위치 추정치를 버린다', (WidgetTester tester) async {
    // 이 추정치는 GPS를 층 그래프에 투영한 값이고 **30초 동안 살아 있다**
    // (IndoorLocationEstimate.isFresh). 앵커가 없을 때의 마지막 폴백이라,
    // 안 버리면 야외로 나간 뒤에도 30초간 실내 좌표가 유효한 채로 남는다.
    // 한때 clear()를 부르는 코드가 앱 전체에 하나도 없었다.
    final positions = StreamController<Position>.broadcast();
    await enterIndoorByGps(tester, positions);
    await settleSensorWarmup(tester);

    expect(
      indoorLocationEstimateController.current,
      isNotNull,
      reason: '테스트 전제(자동 진입이 추정치를 채움)가 성립하지 않았다',
    );

    positions.add(fix(wellOutside, 8));
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);

    expect(find.byType(FloorSelector), findsNothing);
    expect(
      indoorLocationEstimateController.current,
      isNull,
      reason: '야외에 선 사용자에게 30초짜리 실내 좌표가 남아 있으면 안 된다',
    );
  });

  group('전환 연출은 물리적인 진입·이탈에서만 뜬다', () {
    // **이 구분이 연출의 핵심 계약이다.** 건물 탭·홈 버튼처럼 사용자가 도면을
    // 여닫는 조작에까지 붙으면, 2 km 밖에서 건물을 눌러 본 사람에게 "들어가는
    // 중"이라고 말하게 된다.
    testWidgets('GPS 진입에서는 문과 문구가 뜬다', (WidgetTester tester) async {
      final positions = StreamController<Position>.broadcast();
      watchPosition = () => positions.stream;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: OutdoorMapBody()),
        ),
      );
      await drain(tester);

      // **밖 좌표를 먼저 흘린다.** 밖을 한 번도 안 본 진입은 "앱을 실내에서 켰다"로
      // 읽혀 층 시트가 뜨고 연출은 뜨지 않는다(entry_floor_prompt_test.dart).
      positions.add(fix(wellOutside, 8));
      await tester.pump(const Duration(milliseconds: 50));
      await drain(tester);

      positions.add(fix(entrance, 10));
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

    testWidgets('GPS 이탈에서는 나가는 문구가 뜬다', (WidgetTester tester) async {
      final positions = StreamController<Position>.broadcast();
      await enterIndoorByGps(tester, positions);
      await settleSensorWarmup(tester);

      positions.add(fix(wellOutside, 8));
      await tester.pump(const Duration(milliseconds: 50));
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
      await enterIndoorByGps(tester, positions);
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
      await enterIndoorByGps(tester, positions);
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

  testWidgets('건물 밖을 탭해 나오면 안에 서 있어도 다시 끌려 들어가지 않는다', (
    WidgetTester tester,
  ) async {
    // 진입 근거가 "좌표가 건물 안"으로 바뀐 뒤 생긴 가장 위험한 상태다. 무장을
    // 풀지 않으면 다음 위치 한 건이 곧바로 다시 끌고 들어가, 건물 안에서는
    // 야외 지도를 볼 수 없게 된다.
    final positions = StreamController<Position>.broadcast();
    await enterIndoorByGps(tester, positions);
    await settleSensorWarmup(tester);

    final state = tester.state<OutdoorMapBodyState>(
      find.byType(OutdoorMapBody),
    );
    // ignore: invalid_use_of_visible_for_testing_member
    await state.handleMapClickForTest(const LatLng(37.5680, 126.9800));
    await drain(tester);
    expect(find.byType(FloorSelector), findsNothing);

    positions.add(fix(entrance, 8));
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);
    expect(
      find.byType(FloorSelector),
      findsNothing,
      reason: '나가겠다고 누른 사용자를 GPS가 다시 끌고 들어가면 안 된다',
    );

    // 실제로 건물을 벗어나면 다시 무장되고, 그 뒤에 들어가면 정상 진입한다.
    positions.add(fix(wellOutside, 8));
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);
    positions.add(fix(entrance, 8));
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);
    expect(find.byType(FloorSelector), findsOneWidget);

    await settleSensorWarmup(tester);
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
