import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/core/api_config.dart';
import 'package:navigation_client/map/picked_point.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/models/building/building.dart';
import 'package:navigation_client/models/building/building_graph.dart';
import 'package:navigation_client/models/building/category_count.dart';
import 'package:navigation_client/models/place/store_index_entry.dart';
import 'package:navigation_client/models/route/indoor_route.dart';
import 'package:navigation_client/models/place/poi_search_result.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 길찾기 위치 행을 편집하며 **복도를 눌러** 출발지/도착지를 정할 수 있는지.
///
/// 지키려는 증상: 지도 탭은 매장 폴리곤만 받았다. 그래서 지도에 보이는
/// 곳 중 매장이 아닌 자리(복도·광장·에스컬레이터 앞)는 아무리 눌러도 반응이
/// 없었고, 사용자는 기능이 고장 난 것으로 봤다. 정작 하단 바의 "위치 지정"은
/// 같은 자리를 눌러 위치를 잡아 주므로, 같은 지도에서 같은 손짓이 어떤 때는
/// 되고 어떤 때는 안 되는 상태였다.
///
/// 여기서 못 박는 계약은 셋이다.
///   1. 고르는 중일 때 복도를 누르면 **그래프 노드가 확정된 후보**가 나온다.
///      노드 id가 없으면 다익스트라가 시작·종료할 지점을 못 정해 후보로 쓸모가
///      없다(경로 계산이 "노드 정보가 없어 계산할 수 없습니다"로 끝난다).
///   2. 고르는 중이 아니면 복도 탭은 **아무 일도 하지 않는다.** 지도를 훑다
///      빈 곳을 누른 것이 목적지 지정으로 읽히면 시키지 않은 경로가 그려진다.
///   3. 통로에서 너무 먼 탭(건물 밖 등)은 후보가 되지 않는다. 스냅 상한은
///      "위치 지정"과 **같은 값**을 쓴다 — 두 곳이 다르면 같은 자리를 눌러도
///      한쪽만 된다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  const metersPerDegreeLat = 111320.0;
  const metersPerDegreeLng = 88243.0;
  const originLat = 37.5663;
  const originLng = 126.9777;

  /// local_m 좌표를 이 테스트 그래프가 쓰는 위경도로. 화면이 좌표 피팅으로
  /// 되돌리는 값과 같은 규칙이라, 탭 지점을 미터 단위로 설계할 수 있다.
  LatLng latLngAt(double xM, double yM) => LatLng(
    originLat + yM / metersPerDegreeLat,
    originLng + xM / metersPerDegreeLng,
  );

  Map<String, dynamic> node(String id, double xM, double yM) => {
    'id': id,
    'type': 'corridor',
    'x_m': xM,
    'y_m': yM,
    'lat': originLat + yM / metersPerDegreeLat,
    'lng': originLng + xM / metersPerDegreeLng,
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

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await debugModeController.reload();
    originalBuildingRepository = buildingRepository;
    originalDestinationRepository = destinationRepository;
    final repository = _GraphOnlyRepository(graphJson);
    buildingRepository = repository;
    destinationRepository = MockDestinationRepository(repository);
    await repository.getAllBuildings();
  });

  tearDown(() {
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
  });

  /// [picking]이 켜진 지도를 실내 진입 상태로 띄우고, 고른 후보를 담을 리스트를
  /// 함께 준다.
  Future<(GlobalKey<OutdoorMapBodyState>, List<PoiSearchResult>)> openIndoorMap(
    WidgetTester tester, {
    required bool picking,
  }) async {
    final key = GlobalKey<OutdoorMapBodyState>();
    final picked = <PoiSearchResult>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: OutdoorMapBody(
            key: key,
            pickingOnMap: picking,
            onMapPointPicked: picked.add,
          ),
        ),
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
    return (key, picked);
  }

  testWidgets('고르는 중에 복도를 누르면 그 지점이 노드까지 확정된 후보로 올라온다', (
    WidgetTester tester,
  ) async {
    final (key, picked) = await openIndoorMap(tester, picking: true);

    // n-a(18, 22)에서 3m 떨어진 복도 위. 스냅 상한(12m) 안이고, 가장 가까운
    // 노드가 n-a임이 명확한 자리다.
    // ignore: invalid_use_of_visible_for_testing_member
    await key.currentState!.handleMapClickForTest(latLngAt(21, 22));
    await drain(tester);

    expect(picked, hasLength(1), reason: '고르는 중인 탭은 이 경로가 소비해야 한다');
    expect(picked.single.nodeId, 'n-a');
    expect(picked.single.floor, '1F');
    // 매장 이름 자리에 들어가는 값이다. 장소 이름처럼 보이면 사용자가 실제로
    // 존재하는 매장을 고른 것으로 오해한다.
    expect(picked.single.name, kMapPickedPointLabel);
  });

  testWidgets('고르는 중이 아니면 복도 탭은 아무 일도 하지 않는다', (WidgetTester tester) async {
    final (key, picked) = await openIndoorMap(tester, picking: false);

    // ignore: invalid_use_of_visible_for_testing_member
    await key.currentState!.handleMapClickForTest(latLngAt(21, 22));
    await drain(tester);

    // 소비하지 않아야 뒤따르는 다른 지도 처리(있다면)가 그대로 흘러간다.
    expect(picked, isEmpty);
  });

  testWidgets('통로에서 멀리 떨어진 탭은 후보가 되지 않는다', (WidgetTester tester) async {
    final (key, picked) = await openIndoorMap(tester, picking: true);

    // 그래프에서 100m 넘게 떨어진 자리 — 사실상 건물 밖을 누른 경우다. 여기서
    // 후보를 만들어 주면 사용자가 누르지도 않은 복도가 출발지가 된다.
    // ignore: invalid_use_of_visible_for_testing_member
    await key.currentState!.handleMapClickForTest(latLngAt(180, 22));
    await drain(tester);

    expect(picked, isEmpty);
  });
}

/// 층 도면은 비우고 통행 그래프만 내려주는 가짜 저장소. 이 테스트가 보는 것은
/// 복도 스냅뿐이라 매장 폴리곤이 필요 없다.
class _GraphOnlyRepository implements BuildingRepository {
  _GraphOnlyRepository(this.graphJson);

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

  // 카테고리 pill은 이 테스트의 관심사가 아니다. 빈 목록이면 pill 줄이 아예
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
