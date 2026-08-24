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
import 'package:navigation_client/models/building/building.dart';
import 'package:navigation_client/models/building/building_graph.dart';
import 'package:navigation_client/models/route/indoor_route.dart';
import 'package:navigation_client/models/place/poi_search_result.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 매장을 출발지로 골라 길 안내를 시작하면 현재 위치 아이콘도 그 매장으로
/// 옮겨가는지에 대한 회귀 테스트.
///
/// 지키려는 증상: 경로는 고른 매장에서 뻗어 나가는데 위치 아이콘만 예전 자리에
/// (또는 아무 데도 없이) 남아, 사용자는 "내가 여기 있다는 표시"와 "경로가
/// 시작하는 자리"가 어긋난 화면을 보게 된다.
///
/// 지도 레이어는 위젯 트리에 없어 아이콘 픽셀을 볼 수 없다. 대신 그 아이콘의
/// 유일한 근거인 PDR 앵커(층·좌표·렌더 가능 여부)를 직접 본다.
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

  /// [condition]이 참이 될 때까지 프레임을 진행시킨다.
  ///
  /// 앵커 확정은 heading이 수렴할 때까지 몇 초를 기다리는데(실내 화면의
  /// `_waitForHeadingToSettle`), 그 대기는 **실제 시계**를 보면서 100ms 타이머로
  /// 잰다. 타이머는 프레임을 진행시켜야 깨어나므로 고정 횟수 pump로는 대기가
  /// 끝나기 전에 테스트가 앞서 나간다. 그래서 실제 시간을 한도로 두고 돈다.
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
    expect(key.currentState!.currentFloor, '1F');
    return key;
  }

  /// 길 안내를 시작하고, 도중에 뜨는 진행 방향 다이얼로그까지 처리한다.
  ///
  /// **future를 바로 await하면 안 된다.** 자북 heading을 못 얻는 기기(테스트
  /// 환경이 그렇다)는 앵커 확정 도중 모달로 진행 방향을 물어보는데, 그 모달은
  /// 프레임을 진행시켜야 뜨고 탭해야 닫힌다. 앵커 확정 전 heading 수렴 대기도
  /// 100ms 타이머로 돌아 프레임이 멈추면 깨어나지 않는다. 테스트 본문이 future를
  /// 붙잡고 있으면 둘 다 못 해 그대로 멈춘다.
  Future<void> startRoute(
    WidgetTester tester,
    OutdoorMapBodyState state,
    PoiSearchResult destination, {
    PoiSearchResult? origin,
  }) async {
    var done = false;
    final tracked = state
        .showIndoorRouteTo(destination, origin: origin)
        .whenComplete(() => done = true);
    await pumpUntil(tester, () => done);
    await tracked;
    await drain(tester);
  }

  PoiSearchResult storeOn(String floor, {String nodeId = 'n-a'}) =>
      PoiSearchResult(
        name: 'MLB',
        floor: floor,
        point: wgs84(18, 22),
        nodeId: nodeId,
      );

  testWidgets('매장을 출발지로 고르면 현재 위치가 그 매장 자리로 잡힌다', (WidgetTester tester) async {
    final key = await openIndoorMap(tester);

    await startRoute(
      tester,
      key.currentState!,
      PoiSearchResult(
        name: '올리브영',
        floor: '1F',
        point: wgs84(48, 22),
        nodeId: 'n-b',
      ),
      origin: storeOn('1F'),
    );

    final calibration = indoorNavigationDriver.currentCalibration;
    expect(
      calibration.canRenderPosition,
      isTrue,
      reason: '앵커가 확정되지 않으면 위치 아이콘이 그려지지 않는다',
    );
    final anchor = calibration.anchor!;
    expect(anchor.floorId, '1F');
    // 출발지 매장의 입구 노드 n-a(18, 22) 자리여야 한다. 여기가 어긋나면
    // 아이콘도 같은 만큼 엉뚱한 곳에 찍힌다.
    expect(anchor.anchorLocalM.eastM, closeTo(18, 0.5));
    expect(anchor.anchorLocalM.northM, closeTo(22, 0.5));
  });

  testWidgets('다른 층 매장을 출발지로 고르면 그 층에 위치가 잡힌다', (WidgetTester tester) async {
    // 2층 매장에서 출발한다고 했는데 앵커가 1층으로 찍히면, 위치 아이콘은
    // `anchor.floorId == 보고 있는 층` 게이팅에 걸려 어느 층에서도 안 보인다.
    final key = await openIndoorMap(tester);

    await startRoute(
      tester,
      key.currentState!,
      PoiSearchResult(
        name: '올리브영',
        floor: '2F',
        point: wgs84(48, 22),
        nodeId: 'n-b',
      ),
      origin: storeOn('2F'),
    );

    final anchor = indoorNavigationDriver.currentCalibration.anchor;
    expect(anchor, isNotNull);
    expect(anchor!.floorId, '2F');
    expect(indoorNavigationDriver.currentFloorId, '2F');
  });

  testWidgets('출발지를 고르지 않으면 기존 앵커를 건드리지 않는다', (WidgetTester tester) async {
    // "현재 위치에서 출발"은 사용자가 이미 잡아둔 위치를 그대로 쓰겠다는 뜻이다.
    // 여기서 앵커를 다시 찍으면 방금 걸어온 궤적이 통째로 리셋된다.
    final key = await openIndoorMap(tester);

    await key.currentState!.startLocationPlacement();
    await drain(tester);
    // 사용자가 직접 찍은 것과 같은 경로로 앵커를 만든다.
    await startRoute(
      tester,
      key.currentState!,
      PoiSearchResult(
        name: '올리브영',
        floor: '1F',
        point: wgs84(48, 22),
        nodeId: 'n-b',
      ),
      origin: storeOn('1F'),
    );
    final before = indoorNavigationDriver.currentCalibration.anchor!;

    await startRoute(
      tester,
      key.currentState!,
      PoiSearchResult(
        name: '올리브영',
        floor: '1F',
        point: wgs84(18, 52),
        nodeId: 'n-c',
      ),
    );

    final after = indoorNavigationDriver.currentCalibration.anchor;
    expect(after, isNotNull);
    expect(after!.anchorLocalM.eastM, closeTo(before.anchorLocalM.eastM, 1e-9));
    expect(
      after.anchorLocalM.northM,
      closeTo(before.anchorLocalM.northM, 1e-9),
    );
  });

  testWidgets('수동으로 위치를 잡으면 "위치가 갱신됐다"고 상위에 알린다', (WidgetTester tester) async {
    // 사용자가 보고한 순서: 매장 A를 출발지로 길을 찾은 뒤, 지도를 탭해 지금
    // 서 있는 곳을 다시 찍고 다시 길을 찾으면 경로가 방금 찍은 자리에서
    // 출발해야 한다. 상위(MapShellScreen)는 이 신호로 기억해둔 매장 A를 버린다.
    // 신호가 안 오면 새 위치 아이콘과 경로 시작점이 따로 논다.
    var anchored = 0;
    final key = GlobalKey<OutdoorMapBodyState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: OutdoorMapBody(key: key, onLocationAnchored: () => anchored++),
        ),
      ),
    );
    await drain(tester);

    await key.currentState!.startLocationPlacement();
    await drain(tester);
    // ignore: invalid_use_of_visible_for_testing_member
    unawaited(key.currentState!.handleMapClickForTest(wgs84(18, 52)));
    // 앵커 확정은 지도 탭 처리와 분리돼 돌아간다(unawaited). 확정될 때까지
    // 프레임을 진행시켜야 heading 대기와 진행 방향 모달이 흐른다.
    await pumpUntil(
      tester,
      () => indoorNavigationDriver.currentCalibration.anchor != null,
    );

    expect(anchored, 1);
    // 새로 찍은 자리(n-c: 18, 52)가 반영돼야 한다.
    final anchor = indoorNavigationDriver.currentCalibration.anchor!;
    expect(anchor.anchorLocalM.eastM, closeTo(18, 0.5));
    expect(anchor.anchorLocalM.northM, closeTo(52, 0.5));
  });

  testWidgets('출발지 매장을 따라 찍는 앵커는 갱신 신호를 보내지 않는다', (WidgetTester tester) async {
    // 이때의 앵커는 상위가 방금 정한 출발지를 되짚어 찍는 것이다. 여기서도
    // 신호를 보내면 상위가 그 출발지를 스스로 버려, 매장을 골라도 다음 길찾기가
    // "현재 위치"에서 출발하게 된다.
    var anchored = 0;
    final key = GlobalKey<OutdoorMapBodyState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: OutdoorMapBody(key: key, onLocationAnchored: () => anchored++),
        ),
      ),
    );
    await drain(tester);

    await startRoute(
      tester,
      key.currentState!,
      PoiSearchResult(
        name: '올리브영',
        floor: '1F',
        point: wgs84(48, 22),
        nodeId: 'n-b',
      ),
      origin: storeOn('1F'),
    );

    expect(indoorNavigationDriver.currentCalibration.canRenderPosition, isTrue);
    expect(anchored, 0);
  });
}

/// 두 층 모두 같은 navigation_graph를 내려주는 가짜 저장소.
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
