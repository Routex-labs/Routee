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
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';


/// 안내 카드의 **"OO(으)로 진입"**을 누른 뒤, 그 문을 기준으로 실내 위치를 잡고
/// 센서 추적까지 시작하는지에 대한 회귀 테스트.
///
/// 예전에는 이 일을 GPS 자동 진입이 했고, 앵커를 **GPS 좌표를 통로에 붙여** 찍었다.
/// 건물 안 GPS는 오차가 십수 m라 복도 하나쯤은 예사로 틀렸다 — 지금은 사용자가
/// 문 앞에서 누르므로 그 문의 그래프 노드가 곧 위치다.
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

  /// 건물에서 한참 떨어진 인도(약 185 m 동쪽). 외곽선 밖이라 "밖을 봤다"의
  /// 근거가 된다.
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


  /// 문 앞. 오차가 나빠도 상관없다 — 진입 게이트는 오차를 보지 않고, 앵커도
  /// 이 좌표가 아니라 여기서 가장 가까운 문의 **노드**에 찍힌다.
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


  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// 야외 지도를 띄우고, 문 앞에 선 좌표를 흘린 뒤 **진입을 직접 부른다.**
  ///
  /// 버튼을 탭하지 않고 같은 함수를 부르는 이유는 이 파일의 관심사가 앵커이기
  /// 때문이다. 버튼이 언제 켜지는지는 게이트 테스트
  /// (`screens/outdoor_map/entry/manual_transition_gate_test.dart`)와 카드
  /// 위젯 테스트(`widgets/guidance_action_row_test.dart`)가 나눠 맡는다.
  Future<void> enterByButton(WidgetTester tester) async {
    // broadcast여야 한다. 앵커가 찍히면 화면이 GPS를 **다시 구독**하는데, 단일
    // 구독 스트림은 취소된 뒤 재구독하면 'already been listened to'로 터진다.
    // 실제 앱의 watchPosition은 호출마다 새 스트림을 준다.
    final positions = StreamController<Position>.broadcast();
    watchPosition = () => positions.stream;
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    // 위치를 흘리기 전에 건물(문 목록·층 그래프) 로드가 끝날 때까지 진행한다.
    await drain(tester);
    // **밖 좌표를 먼저 흘린다.** 밖을 한 번도 안 본 채 안 좌표가 오면 "앱을
    // 실내에서 켰다"로 읽혀, 화면이 스스로 실내로 들어가고 GPS 스냅으로 앵커를
    // 찍는다 — 이 파일이 확인하려는 문 노드 앵커가 아니게 된다.
    positions.add(farAway());
    await tester.pump(const Duration(milliseconds: 50));
    positions.add(atEntrance());
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);
    // **await하지 않는다.** 이 Future는 전환 연출(AnimationController)이 끝나야
    // 완료되는데, 그 시계를 미는 것이 아래 drain이다 — 여기서 기다리면 서로를
    // 기다리며 테스트가 멈춘다.
    unawaited(
      tester
          .state<OutdoorMapBodyState>(find.byType(OutdoorMapBody))
          .enterIndoorFromGuidance(),
    );
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

  Future<void> useGraphRepository({bool withGraph = true}) async {
    final repository = _GraphBuildingRepository(withGraph ? graphJson : null);
    buildingRepository = repository;
    destinationRepository = MockDestinationRepository(repository);
    await repository.getAllBuildings();
  }

  testWidgets('진입 버튼을 누르면 그 문의 노드에 실내 위치를 잡고 센서 추적을 시작한다', (
    WidgetTester tester,
  ) async {
    await useGraphRepository();
    await enterByButton(tester);
    // 센서 준비 대기가 끝날 때까지(_sensorWarmupTimeout) 시계를 밀어 준다.
    await tester.pump(const Duration(seconds: 3));
    await drain(tester);

    final calibration = indoorNavigationDriver.currentCalibration;
    expect(calibration.canRenderPosition, isTrue);

    // 앵커는 문의 그래프 노드 n-a(18, 22) **그 점**이다. 스냅도 좌표 변환도
    // 거치지 않으므로 오차가 끼어들 자리가 없다 — 여기가 어긋나면 지도의 위치
    // 아이콘도 같은 만큼 엉뚱한 곳에 찍힌다.
    final anchor = calibration.anchor!;
    expect(anchor.floorId, '1F');
    expect(anchor.anchorLocalM.eastM, closeTo(18, 0.01));
    expect(anchor.anchorLocalM.northM, closeTo(22, 0.01));

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
    await enterByButton(tester);

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

  testWidgets('층 그래프가 없으면 앵커를 포기하고 수동 지정을 안내한다', (
    WidgetTester tester,
  ) async {
    // 문 목록은 있는데 그 문의 노드를 찾을 그래프가 없는 건물이다(같은 층
    // 응답에서 stores는 오고 navigation_graph만 비었다). 억지로 찍지 않고
    // 사용자에게 수동 경로를 알려 준다.
    await useGraphRepository(withGraph: false);

    await enterByButton(tester);

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

  testWidgets('출입구 데이터가 없으면 들어가지 않고 이유를 말한다', (WidgetTester tester) async {
    // mock asset에는 지상 출입구('교통' 소분류 + entrance_node_id)가 없다. 문을
    // 모르면 앵커를 찍을 자리도, 실내 구간이 시작할 노드도 없다 — 도면만 펴 봐야
    // 위치 없는 화면이 되므로 진입 자체를 하지 않는다.
    final repository = MockBuildingRepository();
    buildingRepository = repository;
    destinationRepository = MockDestinationRepository(repository);
    await repository.getAllBuildings();

    await enterByButton(tester);

    expect(find.textContaining('건물 출입구 정보가 없어'), findsOneWidget);
    expect(
      indoorNavigationDriver.currentCalibration.canRenderPosition,
      isFalse,
    );
  });

}

/// 지상 출입구 하나와 (선택적으로) navigation_graph를 가진 층을 내려주는 가짜
/// 저장소. mock asset에는 둘 다 없어 앵커 경로를 끝까지 태울 수 없다.
class _GraphBuildingRepository implements BuildingRepository {
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
  _GraphBuildingRepository(this.graphJson);

  /// null이면 그 층에 navigation_graph를 넣지 않는다.
  final Map<String, dynamic>? graphJson;

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
    // 출입구를 심을 자리가 없는데, 진입 버튼은 그 문 목록이 있어야 동작한다.
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
      'navigation_graph': ?graphJson,
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
