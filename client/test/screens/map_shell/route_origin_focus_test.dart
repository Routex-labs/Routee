import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/building/building.dart';
import 'package:navigation_client/models/building/building_graph.dart';
import 'package:navigation_client/models/building/category_count.dart';
import 'package:navigation_client/models/place/store_index_entry.dart';
import 'package:navigation_client/models/route/indoor_route.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 출발지로 고른 매장을 **실내 지도가 따라가는지**에 대한 회귀 테스트.
///
/// 도착지가 아직 없으면 경로를 그리지 않고, 그래서 카메라를 잡아 줄 경로 개요도
/// 없다. 예전에는 이 갈래가 상태만 바꾸고 지도를 그대로 둬서, B2 매장을
/// 출발지로 잡아도 화면은 보고 있던 층 그대로였다.
///
/// **기본 목업(assets/mock)으로는 이 흐름을 시험할 수 없다** — 그쪽 매장에는
/// `entrance_node_id`가 없어 후보가 실내 지점으로 취급되지 않는다. 그래서 노드를
/// 가진 매장을 층마다 하나씩 두는 리포지토리를 여기서 따로 만든다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await debugModeController.reload();
    originalBuildingRepository = buildingRepository;
    originalDestinationRepository = destinationRepository;
    final repository = _TwoFloorStoreRepository();
    buildingRepository = repository;
    destinationRepository = MockDestinationRepository(repository);
    requestStartupPermissions = () async => {};
    await repository.getAllBuildings();
  });

  tearDown(() {
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    requestStartupPermissions = defaultRequestStartupPermissions;
    watchPosition = defaultWatchPosition;
  });

  testWidgets('다른 층 매장을 출발지로 잡으면 실내 지도도 그 층으로 옮긴다', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await drain(tester);

    final map = tester.state<OutdoorMapBodyState>(find.byType(OutdoorMapBody));
    // ignore: invalid_use_of_visible_for_testing_member
    map.enterIndoorForTest();
    await drain(tester);
    expect(map.currentFloor, '1F', reason: '테스트 전제(진입 직후에는 기본 층)가 성립하지 않았다');

    // 길찾기 출발 칸으로 고른다. 상단 검색과 달리 이쪽은 층으로 좁히지 않아
    // ("길찾기는 항상 건물 전체") 1층을 보는 중에도 2층 매장을 고를 수 있다.
    await tester.tap(find.byTooltip('길찾기'));
    await drain(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('route-planner')),
        matching: find.text('현재 위치'),
      ),
    );
    await drain(tester);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('route-draft-origin')),
        matching: find.byType(TextField),
      ),
      // 검색어는 **결과 이름과 다른 글자**여야 한다. 같으면 find.text가 결과
      // 행이 아니라 방금 글자를 넣은 입력창을 먼저 잡아, 아무것도 안 눌린 채
      // 통과한다.
      '올리브',
    );
    await drain(tester);

    final result = find.text('올리브영');
    expect(result, findsWidgets, reason: '테스트 전제(길찾기 후보에 2층 매장이 나옴)가 성립하지 않았다');
    await tester.tap(result.first);
    await drain(tester);

    expect(
      map.currentFloor,
      '2F',
      reason: '출발지로 잡은 매장이 있는 층을 보여 주지 않으면 화면과 계산이 어긋난다',
    );
  });
}

/// 층마다 노드를 가진 매장 하나씩. 1F는 `MLB`, 2F는 `올리브영`이다.
class _TwoFloorStoreRepository implements BuildingRepository {
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

  static const _building = Building(
    id: 'thehyundai-seoul',
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
    final name = switch (floor) {
      '1F' => 'MLB',
      '2F' => '올리브영',
      _ => null,
    };
    if (name == null) return null;
    return {
      // `footprint_wgs84`가 있어야 FloorPlan이 API 응답 갈래로 파싱해
      // `stores`를 읽는다([FloorPlan.fromJson]). 없으면 GeoJSON 갈래로 가서
      // 매장이 하나도 안 잡히고, 검색 후보가 통째로 비어 버린다.
      'footprint_wgs84': [
        _wgs84(0, 0),
        _wgs84(60, 0),
        _wgs84(60, 60),
        _wgs84(0, 60),
      ],
      'stores': [
        {
          'id': '$floor-store',
          'name': name,
          'entrance_node_id': 'n-a',
          'entrance_wgs84': _wgs84(18, 22),
          'centroid_wgs84': _wgs84(18, 22),
          'polygon_wgs84': <Map<String, double>>[],
        },
      ],
      'navigation_graph': {
        'nodes': [_node('n-a', 18, 22), _node('n-b', 48, 22)],
        'edges': [
          {
            'id': 'e-ab',
            'from': 'n-a',
            'to': 'n-b',
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
  Future<BuildingGraph?> getBuildingGraph(
    String buildingId, {
    String vertical = 'auto',
  }) async => null;
}
