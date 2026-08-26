/// UX 규칙을 **순서대로 밟으며** 이음매마다 상태를 찍는 시나리오 하니스.
///
/// 규칙의 단일 출처는 `docs/client/indoor-leg-in-outdoor-journey.md`. 조각을 따로
/// 재는 테스트와 달리 **여정 하나를 처음부터 끝까지** 밟는다 — 이 브랜치의 버그가
/// 거의 다 조각이 아니라 **조각이 맞물리는 자리**에서 나왔기 때문이다.
///
/// 화면 상태는 private이라 [dump]가 **사용자가 보는 것**(카드 라벨·거리·분과 떠
/// 있는 버튼)만 찍는다. 값이 예상과 다르면 그 줄이 곧 어느 이음매가 어긋났는지다.
///
/// 기존 하니스(`outdoor_exit_to_outdoors_test.dart`)와 다른 점은 **건물 그래프를
/// 진짜로 물린다**는 것이다. 그쪽은 null을 돌려줘 문 고르기·진입 시 재계산처럼
/// 그래프에 기대는 갈래가 통째로 안 돌았다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/building/building.dart';
import 'package:navigation_client/models/building/building_graph.dart';
import 'package:navigation_client/models/building/category_count.dart';
import 'package:navigation_client/models/place/poi_search_result.dart';
import 'package:navigation_client/models/place/store_index_entry.dart';
import 'package:navigation_client/models/route/indoor_route.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/widgets/eta_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _metersPerDegreeLat = 111320.0;
const _metersPerDegreeLng = 88243.0;
const _originLat = 37.5663;
const _originLng = 126.9777;

LatLng _at(double xM, double yM) => LatLng(
  _originLat + yM / _metersPerDegreeLat,
  _originLng + xM / _metersPerDegreeLng,
);

/// 건물 안(외곽선 한가운데).
final _inside = _at(30, 30);

/// 건물 밖 북쪽 약 190 m — 바깥 목적지.
const _outsideDestination = LatLng(37.5680, 126.9790);

/// 문 둘. n-a는 남쪽, n-d는 북쪽이라 목적지 방향이 갈린다.
final _doorA = _at(18, 22);
final _doorD = _at(18, 58);

/// 건물 안 목적지 매장(n-b).
final _store = PoiSearchResult(
  name: '매장',
  floor: '1F',
  point: _at(48, 22),
  nodeId: 'n-b',
);

Map<String, dynamic> _node(String id, double xM, double yM) => {
  'id': id,
  'type': 'corridor',
  'x_m': xM,
  'y_m': yM,
  'lat': _originLat + yM / _metersPerDegreeLat,
  'lng': _originLng + xM / _metersPerDegreeLng,
  'floor_id': 'f1',
};

Map<String, dynamic> _edge(String id, String from, String to, double length) => {
  'id': id,
  'from': from,
  'to': to,
  'length_m': length,
  'bidirectional': true,
  'geometry_local_m': <Map<String, dynamic>>[],
};

/// n-b(매장) ── n-a(남문) ── n-c ── n-d(북문)
final _graphJson = <String, dynamic>{
  'nodes': [
    _node('n-a', 18, 22),
    _node('n-b', 48, 22),
    _node('n-c', 18, 40),
    _node('n-d', 18, 58),
  ],
  'edges': [
    _edge('e-ab', 'n-a', 'n-b', 30),
    _edge('e-ac', 'n-a', 'n-c', 18),
    _edge('e-cd', 'n-c', 'n-d', 18),
  ],
};

Map<String, dynamic> get _buildingGraphJson => {
  'building': {'id': 'thehyundai-seoul'},
  'vertical': 'auto',
  'floors': [
    {'id': 'f1', 'name': '1F'},
  ],
  'nodes': _graphJson['nodes'],
  'edges': _graphJson['edges'],
};

Position _fix(LatLng point, double accuracy) => Position(
  latitude: point.latitude,
  longitude: point.longitude,
  timestamp: DateTime.now(),
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

void main() {
  late BuildingRepository originalBuildingRepository;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    originalBuildingRepository = buildingRepository;
    buildingRepository = _ScenarioBuildingRepository();
  });

  tearDown(() {
    buildingRepository = originalBuildingRepository;
    watchPosition = Geolocator.getPositionStream;
  });

  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  /// 이음매마다 **화면에서 읽히는 값**을 찍는다. 상태가 private이라 여기서
  /// 보이는 것이 곧 사용자가 보는 것이다.
  void dump(WidgetTester tester, String step) {
    final cards = find.byType(EtaCard).evaluate();
    final card = cards.isEmpty
        ? null
        : tester.widget<EtaCard>(find.byType(EtaCard));
    final buttons = <String>[
      for (final label in ['안내 시작', '밖으로 나가기', '남은 시간'])
        if (find.text(label).evaluate().isNotEmpty) label,
      // 진입 버튼은 건물 이름이 붙어 라벨이 고정이 아니다.
      if (find.textContaining('진입').evaluate().isNotEmpty) '진입',
    ];
    debugPrint(
      '[$step] 카드=${card == null ? '없음' : '"${card.label}" '
                '${card.distanceMeters.round()}m/${card.minutes}분'}'
      ' · 버튼=$buttons',
    );
  }

  testWidgets('실내 → 야외 도보: 이음매마다 값을 찍는다', (WidgetTester tester) async {
    final positions = StreamController<Position>.broadcast();
    watchPosition = () => positions.stream;
    addTearDown(positions.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        // 스낵바가 [ScaffoldMessenger]를 찾는다 — 실기기에서는 셸이 준다.
        home: const Scaffold(body: OutdoorMapBody()),
      ),
    );
    await drain(tester);
    positions.add(_fix(_inside, 8));
    await drain(tester);

    final state = tester.state<OutdoorMapBodyState>(find.byType(OutdoorMapBody));
    // ignore: invalid_use_of_visible_for_testing_member
    state.enterIndoorForTest();
    await drain(tester);
    dump(tester, '1. 실내 진입');

    // 매장(n-b)에서 바깥 목적지로. 문은 **총 이동거리**로 갈린다 — n-a는
    // 실내 30 m + 야외 193 m = 223 m, n-d는 66 m + 163 m = 229 m라 n-a가 이긴다
    // (목적지가 북쪽이라 직선거리만 보면 n-d가 이긴다).
    await state.showIndoorToOutdoorRouteTo(
      _outsideDestination,
      label: '계양도서관',
      origin: _store,
    );
    await drain(tester);
    dump(tester, '2. 실내→야외 계획');
    final planned = tester.widget<EtaCard>(find.byType(EtaCard));
    expect(planned.label, contains('계양도서관'));
    expect(planned.label, contains('경유'));
    // 실내 30 m가 야외 193 m 위에 더해졌다.
    expect(planned.distanceMeters.round(), 223);

    await tester.tap(find.text('안내 시작'));
    await drain(tester);
    dump(tester, '3. 안내 시작');
    expect(find.text('안내 시작'), findsNothing);
    // 나가는 여정이므로 하단 카드가 전환 버튼을 함께 든다.
    expect(find.text('밖으로 나가기'), findsOneWidget);

    tester.widget<EtaCard>(find.byType(EtaCard)).onClose!();
    await drain(tester);
    dump(tester, '4. 안내 종료');
    expect(find.byType(EtaCard), findsNothing);
  });

  testWidgets('야외 → 실내 도보: 진입하면 실내 카드가 자리를 받는다', (
    WidgetTester tester,
  ) async {
    final positions = StreamController<Position>.broadcast();
    watchPosition = () => positions.stream;
    addTearDown(positions.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: OutdoorMapBody()),
      ),
    );
    await drain(tester);
    // 건물 밖에서 시작한다 — 실내 위치가 없으므로 야외→실내 갈래다.
    positions.add(_fix(_outsideDestination, 8));
    await drain(tester);

    final state = tester.state<OutdoorMapBodyState>(find.byType(OutdoorMapBody));
    await state.showOutdoorToIndoorRouteTo(_store);
    await drain(tester);
    dump(tester, 'A. 야외→실내 계획');

    // **안내를 누르고 걸어 들어간다** — 실기기에서 전제로 둔 순서다.
    await tester.tap(find.text('안내 시작'));
    await drain(tester);
    dump(tester, 'B. 안내 시작(야외)');
    // 걸어 들어가려면 이 버튼이 있어야 한다. 게이트가 멀어 회색이어도 **보이기는
    // 해야 한다** — 조건을 채웠을 때만 나타나면 그런 버튼이 있는 줄도 모른다.
    expect(find.textContaining('진입'), findsOneWidget);

    // 진입. 실내 구간이 승격되면서 카드가 실내 것으로 바뀌어야 한다 —
    // 앞 구간 판정이 직전 여정에서 새면 여기서 바깥 카드가 자리를 쥔다.
    // ignore: invalid_use_of_visible_for_testing_member
    state.enterIndoorForTest();
    await drain(tester);
    dump(tester, 'C. 진입 후');
    expect(find.textContaining('진입'), findsNothing, reason: '이미 들어왔다');
    expect(
      find.text('안내 시작'),
      findsNothing,
      reason: '걸어 들어온 사람에게 다시 시작하라고 하면 같은 여정이 두 번 시작된다',
    );
    final indoorCard = tester.widget<EtaCard>(find.byType(EtaCard));
    expect(indoorCard.label, contains('매장'));
    // 야외 163 m는 이미 걸었다 — 남은 것은 실내 66 m뿐이다.
    expect(indoorCard.distanceMeters.round(), 66);
  });
}

class _ScenarioBuildingRepository implements BuildingRepository {
  static const _building = Building(
    id: 'thehyundai-seoul',
    name: '데모 건물',
    floors: ['1F'],
    defaultFloor: '1F',
    entrance: LatLng(37.5665, 126.9779),
    footprintWgs84: [
      LatLng(37.5663, 126.9777),
      LatLng(37.5668, 126.9777),
      LatLng(37.5668, 126.9783),
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
    if (buildingId != _building.id || floor != '1F') return null;
    return {
      'footprint_wgs84': [
        for (final point in _building.footprintWgs84!)
          {'lat': point.latitude, 'lng': point.longitude},
      ],
      'stores': [
        {
          'id': 'door-a',
          'name': '출구',
          'subcategory': '교통',
          'entrance_node_id': 'n-a',
          'centroid_wgs84': {
            'lat': _doorA.latitude,
            'lng': _doorA.longitude,
          },
        },
        {
          'id': 'door-d',
          'name': '출구',
          'subcategory': '교통',
          'entrance_node_id': 'n-d',
          'centroid_wgs84': {
            'lat': _doorD.latitude,
            'lng': _doorD.longitude,
          },
        },
      ],
      'navigation_graph': _graphJson,
    };
  }

  @override
  Future<IndoorRoute?> getShortestRoute(
    String buildingId,
    String floor,
    String startNodeId,
    String endNodeId,
  ) async {
    final start = _nodePoint(startNodeId);
    final end = _nodePoint(endNodeId);
    if (start == null || end == null) return null;
    return IndoorRoute(
      points: [start, end],
      distanceMeters: const Distance().as(LengthUnit.Meter, start, end),
      nodeIds: [startNodeId, endNodeId],
    );
  }

  LatLng? _nodePoint(String nodeId) {
    for (final node in _graphJson['nodes'] as List<dynamic>) {
      final row = node as Map<String, dynamic>;
      if (row['id'] != nodeId) continue;
      return LatLng(row['lat'] as double, row['lng'] as double);
    }
    return null;
  }

  /// **여기가 기존 하니스와 다른 점이다.** 예전 픽스처는 null을 돌려줘 그래프에
  /// 기대는 갈래(문 고르기·실내 선행 구간·진입 시 재계산)가 통째로 안 돌았다.
  @override
  Future<BuildingGraph?> getBuildingGraph(
    String buildingId, {
    String vertical = 'auto',
  }) async => BuildingGraph.fromJson(_buildingGraphJson);
}
