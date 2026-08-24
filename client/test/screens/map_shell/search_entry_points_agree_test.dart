import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/models/place/outdoor_poi.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/repositories/place/outdoor_poi_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **상단 검색창과 길찾기 시트가 같은 것을 찾는지**에 대한 회귀 테스트.
///
/// 지키려는 증상: 같은 검색어를 어디에 치느냐에 따라 나오는 곳이 다른 것.
///
/// 두 진입점이 각자 검색을 구현하면 반드시 갈린다. 실제로 반복해서 갈렸다 —
/// 한쪽에는 건물 밖 장소(TMAP)가 있고 다른 쪽에는 없어서, 상단 검색에서는
/// 찾아지던 곳이 길찾기에서는 없는 곳이 됐다. 사용자에게는 "될 때도 있고 안
/// 될 때도 있는 검색"으로 보인다.
///
/// 그래서 후보를 정하는 자리를 하나로 모았고(`_searchDirectionsCandidates`),
/// 이 테스트가 그 하나를 지킨다. 새 출처를 붙일 때 한쪽에만 붙이면 여기서
/// 걸린다.
///
/// ## 갈리는 축은 **딱 하나**, 그리고 그건 의도한 것이다
///
/// 상단 검색은 서 있는 쪽만 보여준다 — 실외면 TMAP, 실내면 우리 도면
/// (`search-result-list-ux.md` Y절). 길찾기 도착지 칸은 안 가른다: 그 칸의
/// 본업이 **밖에 서서 안을 고르는 것**이라, 같이 가르면 야외에서 건물 안 매장으로
/// 가는 길을 아예 못 찍는다(`walk_route_kind.dart`의 「야외 → 실내」).
///
/// 그래서 아래 테스트들은 **같은 컨텍스트에서** 두 진입점을 맞춰 본다. 실내
/// 매장은 실내에서, 바깥 장소는 실외에서. 컨텍스트를 넘나드는 비교는 이제
/// 규칙 위반이 아니라 규칙 그 자체다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;
  late OutdoorPoiRepository originalPoiRepository;

  final repository = MockBuildingRepository();

  // 바깥 검색은 기준점(GPS)이 있어야 돈다. 없으면 두 진입점 모두 조용히
  // 건너뛰어, 갈렸는지 아닌지를 볼 수 없다.
  Position fix() => Position(
    latitude: 37.5665,
    longitude: 126.9800,
    timestamp: DateTime(2024, 1, 1),
    accuracy: 10,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  /// 앞 단계에서 열어 둔 화면 상태(검색 활성 등)를 지운다. 같은 타입 위젯을
  /// 다시 pump하면 State가 재사용돼, 검색창이 열린 채로 다음 진입점을 열게
  /// 된다 — 그러면 상단 바에 길찾기 버튼이 없다.
  Future<void> resetShell(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const SizedBox()),
    );
    await tester.pump();
  }

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
    originalPoiRepository = outdoorPoiRepository;
    buildingRepository = repository;
    destinationRepository = MockDestinationRepository(repository);
    outdoorPoiRepository = _FixedPoiRepository();
    requestStartupPermissions = () async => {};
    watchPosition = () => Stream.value(fix());
    await repository.getAllBuildings();
  });

  tearDown(() {
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    outdoorPoiRepository = originalPoiRepository;
    requestStartupPermissions = defaultRequestStartupPermissions;
    watchPosition = defaultWatchPosition;
  });

  /// 상단 검색창에 [query]를 치고 목록에 [name]이 있는지 본다.
  ///
  /// 이름은 검색어 강조 때문에 `Text.rich`로 그려지므로 findRichText가 필요하다.
  /// [indoor]면 먼저 도면 안으로 들어간다 — 상단 검색은 서 있는 쪽만 보여주므로,
  /// 실내 매장을 실외에서 찾는 것은 이제 실패가 아니라 규칙이다.
  Future<bool> foundInTopSearch(
    WidgetTester tester, {
    required String query,
    required String name,
    bool indoor = false,
  }) async {
    await resetShell(tester);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await drain(tester);
    if (indoor) {
      tester
          .state<OutdoorMapBodyState>(find.byType(OutdoorMapBody))
          // ignore: invalid_use_of_visible_for_testing_member
          .enterIndoorForTest();
      await drain(tester);
    }
    await tester.enterText(find.byType(TextField).first, query);
    await tester.pump();
    await drain(tester);
    return find.text(name, findRichText: true).evaluate().isNotEmpty;
  }

  /// 길찾기 시트의 도착지 칸에 [query]를 치고 후보에 [name]이 있는지 본다.
  ///
  /// 도착지 칸은 화면의 **마지막** TextField다 — 인덱스로 집으면 상단 바에
  /// 검색창이 있느냐에 따라 한 칸씩 밀린다.
  Future<bool> foundInDirections(
    WidgetTester tester, {
    required String query,
    required String name,
  }) async {
    await resetShell(tester);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await drain(tester);
    await tester.tap(find.byTooltip('길찾기'));
    await drain(tester);
    await tester.enterText(find.byType(TextField).last, query);
    await drain(tester);
    return find.text(name, findRichText: true).evaluate().isNotEmpty;
  }

  testWidgets('건물 안 매장은 두 진입점 모두에서 찾아진다', (WidgetTester tester) async {
    // 상단 검색은 **도면 안에서** 물어본다. 길찾기 칸은 밖에서 물어도 답한다 —
    // 그 비대칭이 의도한 것이고, 그 이유는 이 파일 머리말에 있다.
    expect(
      await foundInTopSearch(
        tester,
        query: '강의실',
        name: '강의실 101',
        indoor: true,
      ),
      isTrue,
      reason: '상단 검색에서 매장이 안 나왔다',
    );
    expect(
      await foundInDirections(tester, query: '강의실', name: '강의실 101'),
      isTrue,
      reason: '길찾기에서만 매장이 빠졌다 — 두 진입점이 갈렸다',
    );
  });

  testWidgets('건물 밖 장소(TMAP)는 두 진입점 모두에서 찾아진다', (WidgetTester tester) async {
    expect(
      await foundInTopSearch(tester, query: '카페', name: '건너편카페'),
      isTrue,
      reason: '상단 검색에서 건물 밖 장소가 안 나왔다',
    );
    expect(
      await foundInDirections(tester, query: '카페', name: '건너편카페'),
      isTrue,
      reason: '길찾기에서만 건물 밖 장소가 빠졌다 — 실제로 반복됐던 증상이다',
    );
  });

  testWidgets('건물은 두 진입점 모두에서 찾아진다', (WidgetTester tester) async {
    expect(
      await foundInTopSearch(tester, query: '데모', name: '데모 건물'),
      isTrue,
      reason: '상단 검색에서 건물이 안 나왔다',
    );
    expect(
      await foundInDirections(tester, query: '데모', name: '데모 건물'),
      isTrue,
      reason: '길찾기에서만 건물이 빠졌다 — 두 진입점이 갈렸다',
    );
  });
}

/// 검색어와 무관하게 건물 밖 장소 한 건을 돌려준다. TMAP 없이 "바깥에도 답이
/// 있다"는 상황만 만든다.
class _FixedPoiRepository implements OutdoorPoiRepository {
  @override
  bool get isAvailable => true;

  @override
  Future<List<OutdoorPoi>> searchNearby(
    String keyword, {
    required LatLng center,
    int radiusMeters = 0,
    int limit = 10,
  }) async => const [
    OutdoorPoi(
      id: 'cafe-1',
      name: '건너편카페',
      point: LatLng(37.5670, 126.9782),
      category: '커피전문점',
    ),
  ];
}
