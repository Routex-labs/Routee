import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/core/api_config.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/models/building/building.dart';
import 'package:navigation_client/models/building/building_graph.dart';
import 'package:navigation_client/models/building/category_count.dart';
import 'package:navigation_client/models/route/indoor_route.dart';
import 'package:navigation_client/models/place/store_index_entry.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:navigation_client/screens/outdoor_map/widgets/floor_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 층 전환 크로스페이드(95f9b13) 뒤 실기기에서 나온 회귀 두 갈래를 고정한다.
///
/// 1. **늦게 도착한 이전 층 도면이 지금 층을 덮어쓰지 않는다.** 층 도면 요청은
///    저장소가 층별 future를 캐시하므로 이미 가 본 층은 즉시, 처음 가는 층은
///    네트워크 시간 뒤에 도착한다. 층을 연달아 바꾸면 응답 순서가 뒤집히는데,
///    이때 이전 층 응답이 [_floorPlan]을 덮어쓰면 화면 층과 도면이 어긋난다 —
///    카메라 fit이 엉뚱한 외곽선에 맞고(지하층 정렬 이상), 매장 탭의 feature
///    id 조회가 다른 층 목록에서 실패해 건물 파란 반짝임만 남으며, 검색 포커스
///    도 매장을 못 찾는다.
///
/// 2. **검색 포커스는 한 번에 완결된다.** [resolveIndexEntry]가 층 도면 로드가
///    끝나기 전의 빈 [_floorPlan]을 읽으면 조용히 null을 돌려주고, 상위는 이름
///    재검색으로 떨어져 사용자가 같은 매장을 **두 번** 눌러야 했다.
///
/// MapLibre 플랫폼 뷰는 위젯 테스트에 없어 지도 레이어 경로는 돌지 않지만,
/// 층 상태·도면 로드는 실기기와 같은 코드를 지난다. 층 chip은 실기기처럼
/// [FloorSelector.onSelectFloor] 콜백으로 누른다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;
  late _RacingFloorRepository repository;

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
    repository = _RacingFloorRepository();
    buildingRepository = repository;
    destinationRepository = MockDestinationRepository(repository);
    await repository.getAllBuildings();
  });

  tearDown(() {
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
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
    expect(
      key.currentState!.currentFloor,
      '1F',
      reason: '테스트 전제(1층 도면 로드)가 성립하지 않았다',
    );
    return key;
  }

  /// 층 chip 콜백을 직접 부른다. 좌표 탭은 선택기 스크롤 위치까지 테스트하게
  /// 되므로 쓰지 않는다(pdr_anchor_floor_rebind_test와 같은 이유).
  void tapFloorChip(WidgetTester tester, String floor) {
    tester
        .widget<FloorSelector>(find.byType(FloorSelector))
        .onSelectFloor(floor);
  }

  testWidgets('늦게 도착한 이전 층 도면이 지금 층 도면을 덮어쓰지 않는다', (WidgetTester tester) async {
    final key = await openIndoorMap(tester);

    // B2는 처음 가는 층(응답 지연), B1은 곧바로 도착하는 층 — 연달아 누르면
    // 응답이 B1 → B2 순서로 뒤집혀 도착한다.
    tapFloorChip(tester, 'B2');
    await tester.pump();
    tapFloorChip(tester, 'B1');
    await tester.pump();
    repository.completeFloor('B1');
    await drain(tester);
    expect(key.currentState!.currentFloor, 'B1');

    // 추월당한 B2 응답이 이제서야 도착한다.
    repository.completeFloor('B2');
    await drain(tester);

    expect(key.currentState!.currentFloor, 'B1');
    // 같은 층 매장 해석은 [_floorPlan]을 그대로 읽는다. 늦은 B2 응답이 B1
    // 도면을 덮어썼다면 B1 매장을 찾지 못해 null이 나온다 — 실기기에서는 매장
    // 탭이 전부 실패하고 건물 fill 반짝임만 남는 증상이었다.
    final resolved = await key.currentState!.resolveIndexEntry(
      _entry(floor: 'B1'),
    );
    expect(resolved, isNotNull, reason: '늦게 도착한 이전 층 도면이 지금 층 도면을 덮어썼다');
    expect(resolved!.floor, 'B1');
  });

  testWidgets('검색으로 고른 타 층 매장은 한 번에 좌표까지 해석된다', (WidgetTester tester) async {
    final key = await openIndoorMap(tester);

    final pending = key.currentState!.resolveIndexEntry(_entry(floor: 'B2'));
    await tester.pump();
    repository.completeFloor('B2');
    await drain(tester);

    final resolved = await pending;
    expect(
      resolved,
      isNotNull,
      reason: '첫 탭이 null이면 상위가 이름 재검색으로 떨어져 두 번 눌러야 한다',
    );
    expect(resolved!.floor, 'B2');
    expect(key.currentState!.currentFloor, 'B2');
  });

  testWidgets('층을 막 바꾼 직후의 검색 탭도 도면 로드를 기다려 한 번에 해석된다', (
    WidgetTester tester,
  ) async {
    final key = await openIndoorMap(tester);

    // 층 chip으로 B2 전환을 시작만 해 두고(도면 응답은 아직) 곧바로 같은 층
    // 매장을 검색에서 고른다 — 층은 이미 B2라 전환은 건너뛰지만 도면은 아직
    // 비어 있는, 실기기의 "chip 직후 검색" 타이밍이다.
    tapFloorChip(tester, 'B2');
    await tester.pump();
    expect(key.currentState!.currentFloor, 'B2');

    final pending = key.currentState!.resolveIndexEntry(_entry(floor: 'B2'));
    await tester.pump();
    repository.completeFloor('B2');
    await drain(tester);

    final resolved = await pending;
    expect(
      resolved,
      isNotNull,
      reason: '진행 중인 도면 로드를 기다리지 않으면 빈 도면을 읽고 첫 탭이 실패한다',
    );
    expect(resolved!.floor, 'B2');
  });
}

/// 층 이름이 곧 매장 id가 되도록 층마다 매장 하나를 내려주는 검색 후보.
StoreIndexEntry _entry({required String floor}) => StoreIndexEntry(
  id: 'store-$floor',
  name: '매장 $floor',
  floorId: 'floor-$floor',
  floorName: floor,
);

/// 층별 도면 응답 시점을 테스트가 쥐고 있는 가짜 저장소.
///
/// 1F는 초기 로드가 막히지 않게 즉시 응답하고, 나머지 층은
/// [completeFloor]를 부를 때까지 pending이다 — 실기기의 "이미 가 본 층은
/// 캐시 즉시, 처음 가는 층은 네트워크 지연" 순서 뒤집힘을 재현한다.
class _RacingFloorRepository implements BuildingRepository {
  final _completers = <String, Completer<Map<String, dynamic>?>>{};

  void completeFloor(String floor) =>
      _completers[floor]!.complete(_floorGeoJson(floor));

  static const _building = Building(
    id: demoBuildingId,
    name: '데모 건물',
    floors: ['1F', 'B1', 'B2'],
    defaultFloor: '1F',
    entrance: LatLng(37.5665, 126.9779),
    footprintWgs84: [
      LatLng(37.5663, 126.9777),
      LatLng(37.5667, 126.9777),
      LatLng(37.5667, 126.9783),
      LatLng(37.5663, 126.9783),
    ],
  );

  static Map<String, dynamic> _floorGeoJson(String floor) => {
    'footprint_wgs84': [
      {'lat': 37.5663, 'lng': 126.9777},
      {'lat': 37.5667, 'lng': 126.9777},
      {'lat': 37.5667, 'lng': 126.9783},
      {'lat': 37.5663, 'lng': 126.9783},
    ],
    'stores': [
      {
        'id': 'store-$floor',
        'name': '매장 $floor',
        'centroid_wgs84': {'lat': 37.5665, 'lng': 126.9780},
      },
    ],
    // 간선 없는 그래프 — PDR 자동 시작 조건(간선 필요)에 걸리지 않아 native
    // 채널 mock 없이도 실내 진입이 안전하다.
    'navigation_graph': {
      'nodes': [
        {
          'id': 'n-a',
          'type': 'corridor',
          'x_m': 10.0,
          'y_m': 10.0,
          'lat': 37.5664,
          'lng': 126.9778,
        },
      ],
      'edges': <Map<String, dynamic>>[],
    },
  };

  @override
  Future<List<Building>> getAllBuildings() async => const [_building];

  @override
  Future<Building?> getBuilding(String buildingId) async =>
      buildingId == _building.id ? _building : null;

  @override
  Future<Map<String, dynamic>?> getFloorGeoJson(
    String buildingId,
    String floor,
  ) {
    final completer = _completers.putIfAbsent(floor, () {
      final completer = Completer<Map<String, dynamic>?>();
      // 초기 층은 화면이 뜨는 setUp 경로라 즉시 채운다.
      if (floor == '1F') completer.complete(_floorGeoJson(floor));
      return completer;
    });
    return completer.future;
  }

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
