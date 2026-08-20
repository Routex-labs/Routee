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
  Future<bool> foundInTopSearch(
    WidgetTester tester, {
    required String query,
    required String name,
  }) async {
    await resetShell(tester);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await drain(tester);
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
    // 밖에서도 우리 매장 줄이 목록에 남는다. 층·노드가 붙어 있어 문을 경유해
    // 매장 앞까지 데려다주는 줄이라, 겹치는 POI 줄을 빼고 이쪽을 남긴다.
    expect(
      await foundInTopSearch(tester, query: '강의실', name: '강의실 101'),
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
