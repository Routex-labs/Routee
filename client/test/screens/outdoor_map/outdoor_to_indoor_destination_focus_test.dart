import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:navigation_client/models/building/building.dart';
import 'package:navigation_client/models/building/building_graph.dart';
import 'package:navigation_client/models/building/category_count.dart';
import 'package:navigation_client/models/place/poi_search_result.dart';
import 'package:navigation_client/models/place/store_index_entry.dart';
import 'package:navigation_client/models/building/floor_graph.dart';
import 'package:navigation_client/models/route/indoor_route.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:navigation_client/screens/outdoor_map/widgets/floor_selector.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **밖에서 건물 안 매장으로 길을 찾았을 때 화면이 무엇을 보여주는지**에 대한
/// 회귀 테스트.
///
/// 지키려는 증상 둘.
///   1. 목적지를 확정했는데 **화면이 건물 앞에 선다.** 이 여정의 야외 구간은
///      지상 출입구까지라, 경로 전체에 카메라를 맞추면 정작 사용자가 고른 매장은
///      화면에 없다 — 검색에서 그 매장을 보던 그림과도 어긋난다.
///   2. 매장을 보여 주려고 확대한 것을 **"건물에 들어왔다"로 읽는 것.** 그러면
///      실내 구간이 밖에 선 사용자에게 먼저 승격되고(`_activatePendingIndoorRoute`),
///      야외 구간은 그려져 있는데 안내는 이미 건물 안에서 시작한 화면이 된다.
///
/// 그리고 그 짝: 안내를 시작하면 도면 층이 **출입구 층으로 돌아와야** 한다.
/// 도면은 진입 상태가 아니라 배율만으로 페이드인하므로, 계획 화면이 켜 둔 목적지
/// 층이 남으면 걸어가는 야외선 밑에 그 층 도면이 깔린다.
///
/// 층은 [OutdoorMapBodyState.currentFloor]로 읽는다 — 도면·그래프·경로 레이어가
/// 전부 그 값을 본다. 실내 진입 여부는 층 선택기 노출로 읽는다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  final testBuildingRepository = _DoorJourneyRepository();

  const outsideBuilding = ll.LatLng(37.5655, 126.9780);

  // 2F 매장. 노드는 건물 그래프의 도착 노드와 같은 값이어야 실내 구간이 풀린다.
  const storeOn2F = PoiSearchResult(
    name: '올리브영',
    floor: '2F',
    point: ll.LatLng(37.56657, 126.97804),
    nodeId: 'FL-2:shop',
  );

  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await debugModeController.reload();
    originalBuildingRepository = buildingRepository;
    originalDestinationRepository = destinationRepository;
    buildingRepository = testBuildingRepository;
    destinationRepository = MockDestinationRepository(buildingRepository);
    requestStartupPermissions = () async => {};
  });

  tearDown(() {
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    requestStartupPermissions = defaultRequestStartupPermissions;
    watchPosition = defaultWatchPosition;
  });

  Future<OutdoorMapBodyState> pumpMap(WidgetTester tester) async {
    final key = GlobalKey<OutdoorMapBodyState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: OutdoorMapBody(key: key)),
      ),
    );
    await drain(tester);
    return key.currentState!;
  }

  testWidgets('실내 구간이 풀리면 화면은 목적지 매장 층에 선다', (WidgetTester tester) async {
    final state = await pumpMap(tester);
    expect(state.currentFloor, '1F', reason: '테스트 전제: 처음에는 기본 층이다');

    await state.showOutdoorToIndoorRouteTo(storeOn2F, origin: outsideBuilding);
    await drain(tester);

    expect(
      state.currentFloor,
      '2F',
      reason: '사용자가 고른 것은 2F 매장이다 — 그 매장을 보여 주려면 그 층 도면이 깔려야 한다',
    );
    expect(
      find.byType(FloorSelector),
      findsNothing,
      reason: '도면을 보여 줄 뿐 건물에 들어간 것이 아니다 — 들어가면 실내 구간이 먼저 승격된다',
    );
  });

  testWidgets('안내를 시작하면 도면 층이 출입구 층으로 돌아온다', (WidgetTester tester) async {
    // 안내 시작은 **경로 근처에 있는지**를 좌표로 확인한다. 좌표가 없으면 "현재
    // 위치를 확인하는 중입니다"에서 끝나 이 테스트가 보려는 자리에 닿지 못한다.
    final positions = StreamController<Position>.broadcast();
    addTearDown(positions.close);
    watchPosition = () => positions.stream;

    final state = await pumpMap(tester);
    positions.add(
      Position(
        latitude: outsideBuilding.latitude,
        longitude: outsideBuilding.longitude,
        timestamp: DateTime(2026, 8, 26),
        accuracy: 5,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      ),
    );
    await drain(tester);
    await state.showOutdoorToIndoorRouteTo(storeOn2F, origin: outsideBuilding);
    await drain(tester);
    expect(state.currentFloor, '2F', reason: '테스트 전제가 성립하지 않았다');

    await state.startGuidanceForPickedRoute();
    await drain(tester);

    expect(
      state.currentFloor,
      '1F',
      reason: '지금부터 걸을 구간은 지상 출입구까지다. 2F 도면이 남으면 야외선 밑에 그 층이 깔린다',
    );
  });
}

/// 지상 출입구가 있는 1F와 목적지 매장이 있는 2F, 그리고 **둘을 잇는 건물 그래프**를
/// 주는 저장소.
///
/// 목업 저장소([MockBuildingRepository])는 건물 그래프를 주지 않아 문 경유 안내가
/// 항상 "출입구까지만" 갈래로 떨어진다 — 실내 구간이 풀린 정상 흐름을 시험하려면
/// 이 그래프가 필요하다.
class _DoorJourneyRepository implements BuildingRepository {
  static const _originLat = 37.5663;
  static const _originLng = 126.9777;
  static const _metersPerDegreeLat = 111320.0;
  static const _metersPerDegreeLng = 88243.0;

  static Map<String, double> _wgs84(double xM, double yM) => {
    'lat': _originLat + yM / _metersPerDegreeLat,
    'lng': _originLng + xM / _metersPerDegreeLng,
  };

  static Map<String, dynamic> _node(String id, double xM, double yM) => {
    'id': id,
    'type': 'corridor',
    'x_m': xM,
    'y_m': yM,
    ..._wgs84(xM, yM),
  };

  static GraphNode _graphNode(String id, String floorId, double x, double y) =>
      GraphNode(id: id, type: 'corridor', xM: x, yM: y, floorId: floorId);

  static const _building = Building(
    id: 'thehyundai-seoul',
    name: '데모 건물',
    floors: ['2F', '1F'],
    defaultFloor: '1F',
    entrance: ll.LatLng(37.5665, 126.9779),
    footprintWgs84: [
      ll.LatLng(37.5663, 126.9777),
      ll.LatLng(37.5667, 126.9777),
      ll.LatLng(37.5667, 126.9783),
      ll.LatLng(37.5663, 126.9783),
    ],
  );

  @override
  Future<List<Building>> getAllBuildings() async => const [_building];

  @override
  Future<Building?> getBuilding(String buildingId) async =>
      buildingId == _building.id ? _building : null;

  @override
  Future<List<CategoryCount>?> getCategoryCounts(String buildingId) async =>
      const [];

  @override
  Future<Map<String, dynamic>?> getBuildingEvents(String buildingId) async =>
      null;

  @override
  Future<List<StoreIndexEntry>?> getStoreIndex(String buildingId) async =>
      const [];

  @override
  Future<Map<String, dynamic>?> getFloorGeoJson(
    String buildingId,
    String floor,
  ) async {
    if (buildingId != _building.id) return null;
    // 지상 출입구는 소분류가 '교통'이고 노드가 있어야 문으로 잡힌다
    // ([groundEntrancesFrom]).
    final stores = switch (floor) {
      '1F' => [
        {
          'id': 'exit-west',
          'name': '출구',
          'subcategory': '교통',
          'entrance_node_id': 'FL-1:door',
          'entrance_wgs84': _wgs84(10, 4),
          'centroid_wgs84': _wgs84(10, 4),
          'polygon_wgs84': <Map<String, double>>[],
        },
      ],
      '2F' => [
        {
          'id': 'store-olive',
          'name': '올리브영',
          'entrance_node_id': 'FL-2:shop',
          'entrance_wgs84': _wgs84(30, 40),
          'centroid_wgs84': _wgs84(30, 40),
          // 폴리곤이 있어야 포커스가 매장 크기로 배율을 잰다
          // ([_focusZoomForStore]). 없어도 상수 배율로 떨어질 뿐이지만, 실기기와
          // 같은 갈래를 지나게 둔다.
          'polygon_wgs84': [
            _wgs84(26, 36),
            _wgs84(34, 36),
            _wgs84(34, 44),
            _wgs84(26, 44),
          ],
        },
      ],
      _ => null,
    };
    if (stores == null) return null;
    return {
      'footprint_wgs84': [
        _wgs84(0, 0),
        _wgs84(60, 0),
        _wgs84(60, 60),
        _wgs84(0, 60),
      ],
      'stores': stores,
      'navigation_graph': {
        'nodes': floor == '1F'
            ? [_node('FL-1:door', 10, 4), _node('FL-1:hall', 30, 20)]
            : [_node('FL-2:hall', 30, 20), _node('FL-2:shop', 30, 40)],
        'edges': [
          {
            'id': 'e-$floor',
            'from': floor == '1F' ? 'FL-1:door' : 'FL-2:hall',
            'to': floor == '1F' ? 'FL-1:hall' : 'FL-2:shop',
            'length_m': 20.0,
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
  Future<BuildingGraph?> getBuildingGraph(
    String buildingId, {
    String vertical = 'auto',
  }) async {
    if (buildingId != _building.id) return null;
    return BuildingGraph(
      buildingId: buildingId,
      vertical: vertical,
      floorNamesById: const {'FL-1': '1F', 'FL-2': '2F'},
      nodes: [
        _graphNode('FL-1:door', 'FL-1', 10, 4),
        _graphNode('FL-1:hall', 'FL-1', 30, 20),
        _graphNode('FL-2:hall', 'FL-2', 30, 20),
        _graphNode('FL-2:shop', 'FL-2', 30, 40),
      ],
      edges: [
        const GraphEdge(
          id: 'e-1f',
          fromNodeId: 'FL-1:door',
          toNodeId: 'FL-1:hall',
          lengthM: 20,
          bidirectional: true,
          geometryLocalM: [],
        ),
        const GraphEdge(
          id: 'e-up',
          fromNodeId: 'FL-1:hall',
          toNodeId: 'FL-2:hall',
          lengthM: 4,
          costM: 25,
          bidirectional: true,
          geometryLocalM: [],
          transferMode: 'elevator',
        ),
        const GraphEdge(
          id: 'e-2f',
          fromNodeId: 'FL-2:hall',
          toNodeId: 'FL-2:shop',
          lengthM: 20,
          bidirectional: true,
          geometryLocalM: [],
        ),
      ],
    );
  }
}
