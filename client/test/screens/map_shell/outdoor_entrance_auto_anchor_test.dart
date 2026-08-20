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
import 'package:navigation_client/features/indoor_navigation/contract/indoor_navigation_contract.dart';
import 'package:navigation_client/models/building/building.dart';
import 'package:navigation_client/models/building/building_graph.dart';
import 'package:navigation_client/models/route/indoor_route.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/entry_floor_prompt_helper.dart';

/// 자동 실내 진입이 "진입한 입구"를 기준으로 실내 위치를 잡고 센서 추적까지
/// 시작하는지에 대한 회귀 테스트.
///
/// 예전에는 트리거가 층 오버레이만 켜고 끝나서, 건물에 들어와도 지도에 내 위치가
/// 없었다 — 사용자가 "위치 지정"으로 복도를 직접 탭해야 비로소 걸음 추적이 시작됐다.
///
/// MapLibre 레이어는 위젯 트리에 없어 위치 아이콘 픽셀을 볼 수 없다. 대신 그
/// 아이콘의 **유일한 근거**인 PDR 앵커(`canRenderPosition`과 anchorLocalM)와 센서
/// 세션 상태를 직접 본다. 앵커가 입구에 찍혔다면 야외 화면의 `_pdrCurrentWgs84()`가
/// 그 좌표를 돌려주므로 마커도 같은 자리에 그려진다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  // 층 로컬 좌표 → WGS84 대응점을 만들 때 쓰는 상수. 데모 건물 위도에서의 값이며,
  // 클라이언트의 좌표 변환(domain/geo_transform.dart)과 같은 근사다.
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

  // 입구(37.5665, 126.9779)는 층 로컬로 약 (17.6, 22.3)이라 n-a 바로 옆이다.
  // 세 노드는 한 직선 위에 있지 않아 affine 피팅이 유일하게 풀린다.
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

  // 자동 진입은 "신호가 멀쩡했을 때 입구 앞에 있었다"는 근거를 요구한다.
  // 저하 표본만 흘리면 판정이 서지 않으므로 접근 표본을 먼저 보낸다.
  Position approachingEntrance() => Position(
    latitude: 37.5665,
    longitude: 126.9779,
    timestamp: DateTime(2024, 1, 1),
    accuracy: 10,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  Position atEntrance() => Position(
    latitude: 37.5665,
    longitude: 126.9779,
    timestamp: DateTime(2024, 1, 1),
    accuracy: 60,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  Position farAway() => Position(
    latitude: 37.5665,
    longitude: 126.9800,
    timestamp: DateTime(2024, 1, 1),
    accuracy: 40,
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

  /// 야외 지도를 띄우고 "입구 20m 이내 + 신호 저하"로 자동 실내 진입을 발화시킨다.
  /// 멀리서 접근 → 입구 앞(양호) → 신호 저하 순서를 지켜야 한다 — 판정이 "신호가
  /// 멀쩡했을 때 입구 앞에 있었다"는 근거를 창에서 찾기 때문이다.
  Future<void> walkIntoBuilding(WidgetTester tester) async {
    // broadcast여야 한다. 앵커가 입구에 찍히면 PDR 위치도 입구 앞이라 화면이
    // 이탈 확인용 GPS를 **다시 구독**하는데, 단일 구독 스트림은 취소된 뒤
    // 재구독하면 'already been listened to'로 터진다. 실제 앱의 watchPosition은
    // 호출마다 새 스트림을 준다.
    final positions = StreamController<Position>.broadcast();
    watchPosition = () => positions.stream;
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const MapShellScreen()));
    // 위치를 흘리기 전에 건물(입구 좌표·층 그래프) 로드가 끝날 때까지 진행한다.
    await drain(tester);
    positions.add(farAway());
    await tester.pump(const Duration(milliseconds: 50));
    positions.add(approachingEntrance());
    await tester.pump(const Duration(milliseconds: 50));
    positions.add(atEntrance());
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);
    // 자동 진입은 "몇 층에 계신가요?"를 먼저 띄우고, **답을 받은 뒤에** 앵커를
    // 찍는다. 걷지 않으면 아래 검증이 기다리는 안내가 영영 안 온다.
    await dismissEntryFloorPrompt(tester);
    await drain(tester);
  }

  // native PDR 채널. 핸들러를 달지 않으면 startGuidance가 MissingPluginException
  // 으로 곧장 degraded에 빠져 센서 준비 대기(_awaitSensorWarmup)를 건너뛰고,
  // "heading을 기다리는 동안에는 앵커를 찍지 않는다"는 분기를 검증할 수 없다.
  //
  // 반대로 mock으로 heading 이벤트를 흘려 "자북 기기" 분기까지 태우지는 않는다.
  // 플랫폼 채널 이벤트는 위젯 테스트의 가짜 시계가 아니라 실제 이벤트 루프로
  // 배달돼서, 그걸 기다리려면 tester.runAsync가 필요하고 그 순간 MapLibre
  // PlatformView 생성까지 함께 깨어나 테스트가 무관한 예외로 넘어진다.
  // 자북 분기(회전 0으로 즉시 확정)는 드라이버 계약 테스트가 담당한다.
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
    requestStartupPermissions = () async => {};
    messenger().setMockMethodCallHandler(commandChannel, (call) async => 1);
    messenger().setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(onListen: (arguments, sink) {}),
    );
  });

  tearDown(() async {
    // PDR 드라이버는 앱 전역 싱글턴이라 세션이 다음 테스트로 샌다.
    await indoorNavigationDriver.stopGuidance();
    messenger().setMockMethodCallHandler(commandChannel, null);
    messenger().setMockStreamHandler(eventChannel, null);
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    requestStartupPermissions = defaultRequestStartupPermissions;
    watchPosition = defaultWatchPosition;
  });

  Future<void> useGraphRepository() async {
    final repository = _GraphBuildingRepository(graphJson);
    buildingRepository = repository;
    destinationRepository = MockDestinationRepository(repository);
    await repository.getAllBuildings();
  }

  testWidgets('자동 진입 후 입구 좌표에 실내 위치를 잡고 센서 추적을 시작한다', (
    WidgetTester tester,
  ) async {
    await useGraphRepository();
    await walkIntoBuilding(tester);
    // 센서 준비 대기가 끝날 때까지(_sensorWarmupTimeout) 시계를 밀어 준다.
    await tester.pump(const Duration(seconds: 3));
    await drain(tester);

    final calibration = indoorNavigationDriver.currentCalibration;
    expect(calibration.canRenderPosition, isTrue);

    // 앵커는 입구를 통로에 스냅한 지점이다. 입구의 층 로컬 좌표 (17.6, 22.3)에서
    // 가장 가까운 통로 점은 n-a(18, 22)라 1m 안에 들어와야 한다. 여기가 어긋나면
    // 지도의 위치 아이콘도 같은 만큼 엉뚱한 곳에 찍힌다.
    final anchor = calibration.anchor!;
    expect(anchor.floorId, '1F');
    expect(anchor.anchorLocalM.eastM, closeTo(18, 1));
    expect(anchor.anchorLocalM.northM, closeTo(22, 1));

    // 센서 세션이 실제로 돌고 있어야 한다 — 위치만 찍고 추적이 없으면 사용자는
    // 걸어도 마커가 그대로인 화면을 보게 된다.
    expect(
      indoorNavigationDriver.currentRuntimeStatus.state,
      isNot(PdrRuntimeState.idle),
    );
    expect(find.textContaining('입구를 기준으로 실내 위치를 잡았습니다'), findsOneWidget);
  });

  testWidgets('센서가 heading을 보고하기 전에는 앵커를 확정하지 않는다', (
    WidgetTester tester,
  ) async {
    await useGraphRepository();
    await walkIntoBuilding(tester);

    // 이 유예가 없으면 나침반이 멀쩡한 기기까지 "heading 없음"으로 보여, 추정한
    // 진입 방향이 회전각으로 박히고 이후 궤적 전체가 그만큼 돌아간다.
    expect(
      indoorNavigationDriver.currentCalibration.canRenderPosition,
      isFalse,
    );
    // 다만 센서 세션 자체는 이미 시작돼 있어야 한다.
    expect(
      indoorNavigationDriver.currentRuntimeStatus.state,
      isNot(PdrRuntimeState.idle),
    );

    // 유예가 끝나면 heading을 끝내 못 받았더라도 추정 방향으로 확정한다 —
    // 방향을 모른다고 멈춰 서면 위치 아이콘도 걸음 추적도 아예 없다.
    await tester.pump(const Duration(seconds: 3));
    await drain(tester);
    expect(indoorNavigationDriver.currentCalibration.canRenderPosition, isTrue);
  });

  testWidgets('층 그래프가 없으면 자동 앵커를 포기하고 수동 지정을 안내한다', (
    WidgetTester tester,
  ) async {
    // mock asset의 층에는 navigation_graph가 없다 — 입구 좌표를 층 좌표로 옮길
    // 근거가 없으므로 억지로 찍지 않고, 사용자에게 수동 경로를 알려 준다.
    final repository = MockBuildingRepository();
    buildingRepository = repository;
    destinationRepository = MockDestinationRepository(repository);
    await repository.getAllBuildings();

    await walkIntoBuilding(tester);

    // 안내는 스낵바라 기본 4초 뒤 사라진다. 먼저 확인하고 시계를 민다.
    expect(find.textContaining('위치 지정으로 직접 지정해주세요'), findsOneWidget);

    // 센서 준비 대기 시간을 넘겨도 앵커는 생기지 않고, 센서 세션도 아예 시작하지
    // 않는다 — 좌표를 옮길 근거가 없는데 배터리만 쓰는 세션이 남으면 안 된다.
    await tester.pump(const Duration(seconds: 3));
    await drain(tester);
    expect(
      indoorNavigationDriver.currentCalibration.canRenderPosition,
      isFalse,
    );
    expect(
      indoorNavigationDriver.currentRuntimeStatus.state,
      PdrRuntimeState.idle,
    );
  });
}

/// navigation_graph가 들어 있는 층을 하나 가진 가짜 저장소. mock asset은 그래프가
/// 없어 자동 앵커 경로를 끝까지 태울 수 없다.
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
