import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/core/api_config.dart';
import 'package:navigation_client/domain/route/vertical_preference.dart';
import 'package:navigation_client/models/building/building.dart';
import 'package:navigation_client/models/building/building_graph.dart';
import 'package:navigation_client/models/building/category_count.dart';
import 'package:navigation_client/models/building/floor_graph.dart';
import 'package:navigation_client/models/place/poi_search_result.dart';
import 'package:navigation_client/models/place/store_index_entry.dart';
import 'package:navigation_client/models/route/indoor_route.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/state/vertical_preference_controller.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/widgets/vertical_preference_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 사용자가 고른 **수직 이동 선호가 서버 질의까지 실제로 닿는지** 고정한다.
///
/// 이 배관은 조용히 끊긴다. 값을 안 실어도 서버는 기본 정책(auto) 그래프를
/// 정상으로 돌려주므로 어디서도 예외가 나지 않고, 화면은 "고른 대로 됐다"고
/// 믿은 채 예전과 같은 경로를 그린다. 그래서 리포지토리가 받은 인자를 직접 본다.
///
/// 선호가 그 건물에서 불가능할 때의 규칙(자동으로 한 번 되돌리고 그 사실을
/// 알린다)도 여기서 함께 못 박는다 — 되돌림이 사라지면 사용자는 갈 수 있는
/// 길을 두고 "경로 없음"을 보게 된다.
void main() {
  late BuildingRepository originalRepository;
  late VerticalPreferenceController originalPreference;
  late _RecordingGraphRepository repository;

  const metersPerDegreeLat = 111320.0;
  const metersPerDegreeLng = 88243.0;
  const originLat = 37.5663;
  const originLng = 126.9777;

  LatLng wgs84(double xM, double yM) => LatLng(
    originLat + yM / metersPerDegreeLat,
    originLng + xM / metersPerDegreeLng,
  );

  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await debugModeController.reload();
    originalRepository = buildingRepository;
    originalPreference = verticalPreferenceController;
    repository = _RecordingGraphRepository(wgs84);
    buildingRepository = repository;
    verticalPreferenceController = VerticalPreferenceController(
      prefs: await SharedPreferences.getInstance(),
    );
    await verticalPreferenceController.ready;
  });

  tearDown(() {
    buildingRepository = originalRepository;
    verticalPreferenceController = originalPreference;
  });

  Future<OutdoorMapBodyState> openIndoorMap(WidgetTester tester) async {
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
    return key.currentState!;
  }

  /// 1F 매장에서 2F 매장까지 층 간 경로를 뽑는다.
  ///
  /// **`preview: true`다.** 그래야 출발지에 PDR 앵커를 찍는 흐름(진행 방향 모달·
  /// 센서 채널)을 통째로 건너뛰고 경로 계산만 남는다 — 여기서 재는 것은 앵커가
  /// 아니라 리포지토리가 받은 인자다.
  Future<void> routeAcrossFloors(
    WidgetTester tester,
    OutdoorMapBodyState state,
  ) async {
    await state.showIndoorRouteTo(
      PoiSearchResult(
        name: '올리브영',
        floor: '2F',
        point: wgs84(48, 22),
        nodeId: 'n-b2',
      ),
      origin: PoiSearchResult(
        name: 'MLB',
        floor: '1F',
        point: wgs84(18, 22),
        nodeId: 'n-a1',
      ),
      preview: true,
    );
    await drain(tester);
  }

  testWidgets('아무것도 안 고르면 auto로 묻는다 — 오늘 동작이 기본값이다', (
    WidgetTester tester,
  ) async {
    final state = await openIndoorMap(tester);
    await routeAcrossFloors(tester, state);

    expect(repository.verticals, isNotEmpty, reason: '그래프를 아예 안 받아 갔다');
    expect(repository.verticals, everyElement('auto'));
  });

  testWidgets('엘리베이터를 고르면 그 값이 서버 질의로 나간다', (WidgetTester tester) async {
    await verticalPreferenceController.set(VerticalPreference.elevator);
    final state = await openIndoorMap(tester);
    repository.verticals.clear();

    await routeAcrossFloors(tester, state);

    expect(repository.verticals, contains('elevator'));
    expect(repository.verticals, isNot(contains('auto')));
  });

  testWidgets('카드에서 선호를 바꾸면 그 값으로 경로를 다시 뽑는다', (WidgetTester tester) async {
    final state = await openIndoorMap(tester);
    await routeAcrossFloors(tester, state);
    expect(
      find.byType(VerticalPreferenceBar),
      findsOneWidget,
      reason: '층 간 경로가 그려졌는데 고르는 줄이 없다',
    );
    repository.verticals.clear();

    await tester.tap(find.text('에스컬레이터'));
    await drain(tester);

    // 값만 갈아 두고 화면의 선을 옛 정책 그대로 두면 안 된다. 다시 물어본
    // 것이 그 증거다.
    expect(verticalPreferenceController.value, VerticalPreference.escalator);
    expect(repository.verticals, contains('escalator'));
  });

  testWidgets('그 건물에 없는 수단을 고르면 자동으로 되돌리고 그 사실을 알린다', (
    WidgetTester tester,
  ) async {
    // 이 건물의 수직 연결은 에스컬레이터뿐이다. 엘리베이터로 물으면 서버가
    // 수직 간선이 하나도 없는 그래프를 내려준다.
    repository.hasElevator = false;
    await verticalPreferenceController.set(VerticalPreference.elevator);
    final state = await openIndoorMap(tester);
    repository.verticals.clear();

    await routeAcrossFloors(tester, state);

    expect(repository.verticals, ['elevator', 'auto']);
    expect(find.textContaining('엘리베이터 연결이 없어'), findsOneWidget);
    // 되돌림은 이번 계산 한 번짜리다 — 저장된 선택까지 잃으면 다음 건물에서
    // 다시 골라야 한다.
    expect(verticalPreferenceController.value, VerticalPreference.elevator);
  });
}

/// `vertical` 인자를 받아 적는 리포지토리. 두 층(1F·2F) 사이를 에스컬레이터와
/// 엘리베이터로 잇고, 요청받은 정책에 맞는 수직 간선만 남겨 서버 필터링을 흉내낸다.
class _RecordingGraphRepository implements BuildingRepository {
  _RecordingGraphRepository(this._wgs84);

  final LatLng Function(double, double) _wgs84;

  /// 호출된 순서대로 쌓인 `vertical` 인자.
  final verticals = <String>[];

  /// 이 건물에 엘리베이터 간선이 있는지. false면 `vertical=elevator` 질의가
  /// 수직 간선 없는 그래프를 돌려준다.
  bool hasElevator = true;

  static const _building = Building(
    id: demoBuildingId,
    name: '테스트몰',
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

  /// 한 층의 노드 셋. 좌표 피팅이 유일하게 풀리도록 셋이 한 직선 위에 있지 않다.
  List<GraphNode> _floorNodes(String floorId, String suffix) => [
    for (final spot in const [
      (18.0, 22.0, 'a'),
      (48.0, 22.0, 'b'),
      (18.0, 52.0, 'c'),
    ])
      GraphNode(
        id: 'n-${spot.$3}$suffix',
        type: 'corridor',
        xM: spot.$1,
        yM: spot.$2,
        lat: _wgs84(spot.$1, spot.$2).latitude,
        lng: _wgs84(spot.$1, spot.$2).longitude,
        floorId: floorId,
      ),
  ];

  GraphEdge _walk(String id, String from, String to, String floorId) =>
      GraphEdge(
        id: id,
        fromNodeId: from,
        toNodeId: to,
        lengthM: 30,
        bidirectional: true,
        geometryLocalM: const [],
        fromFloorId: floorId,
        toFloorId: floorId,
      );

  GraphEdge _transfer(String id, String from, String to, String mode) =>
      GraphEdge(
        id: id,
        fromNodeId: from,
        toNodeId: to,
        lengthM: 5,
        costM: 20,
        bidirectional: true,
        geometryLocalM: const [],
        transferMode: mode,
        fromFloorId: 'f1',
        toFloorId: 'f2',
      );

  @override
  Future<BuildingGraph?> getBuildingGraph(
    String buildingId, {
    String vertical = 'auto',
  }) async {
    verticals.add(vertical);
    if (buildingId != _building.id) return null;
    return BuildingGraph(
      buildingId: buildingId,
      vertical: vertical,
      floorNamesById: const {'f1': '1F', 'f2': '2F'},
      nodes: [..._floorNodes('f1', '1'), ..._floorNodes('f2', '2')],
      edges: [
        _walk('e-ab1', 'n-a1', 'n-b1', 'f1'),
        _walk('e-ac1', 'n-a1', 'n-c1', 'f1'),
        _walk('e-ab2', 'n-a2', 'n-b2', 'f2'),
        _walk('e-ac2', 'n-a2', 'n-c2', 'f2'),
        // 서버가 정책에 맞는 수직 간선만 남겨 내려주는 것을 흉내낸다.
        if (vertical != 'elevator')
          _transfer('e-esc', 'n-b1', 'n-b2', 'escalator'),
        if (vertical != 'escalator' && hasElevator)
          _transfer('e-elev', 'n-c1', 'n-c2', 'elevator'),
      ],
    );
  }

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
    final floorId = floor == '1F' ? 'f1' : 'f2';
    final suffix = floor == '1F' ? '1' : '2';
    return {
      'type': 'FeatureCollection',
      'features': <Map<String, dynamic>>[],
      'navigation_graph': {
        'nodes': [
          for (final node in _floorNodes(floorId, suffix))
            {
              'id': node.id,
              'type': node.type,
              'x_m': node.xM,
              'y_m': node.yM,
              'lat': node.lat,
              'lng': node.lng,
            },
        ],
        'edges': [
          {
            'id': 'e-ab\$suffix',
            'from': 'n-a\$suffix',
            'to': 'n-b\$suffix',
            'length_m': 30.0,
            'bidirectional': true,
            'geometry_local_m': <Map<String, dynamic>>[],
          },
          {
            'id': 'e-ac\$suffix',
            'from': 'n-a\$suffix',
            'to': 'n-c\$suffix',
            'length_m': 30.0,
            'bidirectional': true,
            'geometry_local_m': <Map<String, dynamic>>[],
          },
        ],
      },
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
  Future<List<StoreIndexEntry>?> getStoreIndex(String buildingId) async => null;

  @override
  Future<List<CategoryCount>?> getCategoryCounts(String buildingId) async =>
      null;

  @override
  Future<Map<String, dynamic>?> getBuildingEvents(String buildingId) async =>
      null;
}
