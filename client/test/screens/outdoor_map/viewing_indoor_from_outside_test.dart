import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:navigation_client/screens/outdoor_map/widgets/floor_selector.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **밖에 서서 도면만 폈을 때 위치 마커의 주인이 누구인지**에 대한 회귀 테스트.
///
/// 지키려는 증상: 건물 밖에서 매장을 찾아보려고 도면을 폈을 뿐인데, 화면에는
/// 도면 위 흐린 점이 떠서 "내가 건물 안에 있다"로 읽히는 것. 그 점의 근거는
/// 건물 밖에서 찍힌 GPS 좌표 하나뿐이라([_indoorGapGpsPoint]), 도면 위 자리는
/// 애초에 아무 뜻도 없다.
///
/// 규칙은 **어떻게 도면을 폈는가** 하나다([IndoorEntrySource.isViewingOnly]).
/// 확대·건물 탭은 화면 조작이라 위치의 주인이 GPS로 남고, 걸어 들어온 사람
/// (진입 버튼·실내 콜드스타트·직접 찍은 위치)만 실내 마커를 갖는다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  final testBuildingRepository = MockBuildingRepository();

  // 데모 건물 footprint는 위도 37.5663~37.5667, 경도 126.9777~126.9783 사각형이다.
  const insideBuilding = ll.LatLng(37.5665, 126.9780);

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
    buildingRepository = testBuildingRepository;
    destinationRepository = MockDestinationRepository(buildingRepository);
    requestStartupPermissions = () async => {};
    await testBuildingRepository.getAllBuildings();
  });

  tearDown(() {
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    requestStartupPermissions = defaultRequestStartupPermissions;
  });

  testWidgets('건물을 탭해 도면만 폈으면 위치의 주인은 그대로 GPS다', (
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

    final state = key.currentState!;
    // ignore: invalid_use_of_visible_for_testing_member
    await state.handleMapClickForTest(insideBuilding);
    await drain(tester);

    expect(
      find.byType(FloorSelector),
      findsOneWidget,
      reason: '테스트 전제: 건물 탭으로 도면이 펴져 있어야 한다',
    );
    expect(
      // ignore: invalid_use_of_visible_for_testing_member
      state.indoorMarkerOwnsLocationForTest,
      isFalse,
      reason: '도면을 편 것뿐이다 — 실내 마커가 그릴 근거는 건물 밖 GPS 좌표밖에 없다',
    );
    expect(
      // ignore: invalid_use_of_visible_for_testing_member
      state.outdoorGpsMarkerVisibleForTest,
      isTrue,
      reason: '그 자리는 야외 GPS 마커가 지킨다 — 안 그러면 화면에 내 자리가 하나도 없다',
    );
  });

  testWidgets('걸어 들어온 진입이면 실내 마커가 주인이 된다', (WidgetTester tester) async {
    final key = GlobalKey<OutdoorMapBodyState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: OutdoorMapBody(key: key)),
      ),
    );
    await drain(tester);

    final state = key.currentState!;
    // 화면 조작이 아닌 진입 — 실기기에서는 안내 카드의 "OO(으)로 진입"과 실내
    // 콜드스타트가 이 자리로 들어온다.
    // ignore: invalid_use_of_visible_for_testing_member
    state.enterIndoorForTest();
    await drain(tester);

    expect(
      // ignore: invalid_use_of_visible_for_testing_member
      state.indoorMarkerOwnsLocationForTest,
      isTrue,
      reason: '앵커가 아직 없어도 마커의 주인은 실내다 — 그 공백을 GPS 좌표가 흐리게 메운다',
    );
    expect(
      // ignore: invalid_use_of_visible_for_testing_member
      state.outdoorGpsMarkerVisibleForTest,
      isFalse,
      reason: '두 마커가 함께 뜨면 같은 사람 자리에 점이 둘이 된다',
    );
  });
}
