import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:navigation_client/models/route/directions_route.dart';
import 'package:navigation_client/models/route/transit_route.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 자동차를 보고 나서 대중교통으로 갈아탄 뒤 안내를 시작하면, **카메라가
/// 자동차 따라가기로 들어가는지**에 대한 회귀 테스트.
///
/// 증상: 대중교통 상세의 `안내 시작` 직후 지도가 사용자 위치로 끌려가
/// 경로가 화면 귀퉁이로 밀렸다. 원인은 `_routeIsDriving`가 자동차 화면에서
/// 켜진 채 `showTransitRoute`를 지나 살아남은 것이다 —
/// `_startCurrentGuidance`는 그 값만 보고 `startFollowingCurrentLocation()`을
/// 부른다.
///
/// 따라가기가 켜졌는지는 **`_position`이 없을 때만 화면에 드러난다** —
/// 그때 `startFollowingCurrentLocation`이 자기 안내 문구를 띄운다. 그래서
/// 좌표를 한 번도 주지 않고, 좌표가 없어도 안내 시작 가드에 안 걸리도록
/// 좌표가 1개뿐인 여정을 쓴다(가드는 2개 이상일 때만 위치를 본다).
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;
  final repository = MockBuildingRepository();

  const somewhere = ll.LatLng(37.5665, 126.9780);

  /// 좌표가 1개뿐인 여정. 안내 시작 가드가 위치를 묻지 않고 지나간다.
  const itinerary = TransitItinerary(
    totalTimeSeconds: 1200,
    totalWalkTimeSeconds: 300,
    totalDistanceMeters: 3000,
    transferCount: 0,
    fare: 1500,
    legs: [
      TransitLeg(
        mode: TransitMode.bus,
        sectionTimeSeconds: 1200,
        distanceMeters: 3000,
        points: [somewhere],
        startName: '앞 정류장',
        endName: '뒤 정류장',
        stationCount: 3,
      ),
    ],
  );

  final drivingRoute = DirectionsRoute(
    points: const [somewhere, ll.LatLng(37.5700, 126.9800)],
    distanceMeters: 1200,
    durationSeconds: 300,
  );

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await debugModeController.reload();
    originalBuildingRepository = buildingRepository;
    originalDestinationRepository = destinationRepository;
    buildingRepository = repository;
    destinationRepository = MockDestinationRepository(repository);
    requestStartupPermissions = () async => {};
    await repository.getAllBuildings();
  });

  tearDown(() {
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    requestStartupPermissions = defaultRequestStartupPermissions;
  });

  testWidgets('자동차를 보고 온 대중교통 안내는 따라가기로 들어가지 않는다', (WidgetTester tester) async {
    final key = GlobalKey<OutdoorMapBodyState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: OutdoorMapBody(key: key)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await key.currentState!.showPlannedRoadRoute(
      drivingRoute,
      origin: somewhere,
      destination: const ll.LatLng(37.5700, 126.9800),
      label: '어딘가',
      driving: true,
    );
    await tester.pump();

    await key.currentState!.showTransitRoute(
      itinerary,
      destination: const ll.LatLng(37.5700, 126.9800),
      label: '어딘가',
      origin: somewhere,
    );
    await tester.pump();

    await key.currentState!.startGuidanceForPickedRoute();
    await tester.pump();

    expect(
      find.text('현재 위치를 아직 못 잡았습니다. 신호가 잡히면 그 자리로 지도를 옮깁니다.'),
      findsNothing,
      reason: '대중교통 안내가 자동차 따라가기(startFollowingCurrentLocation)를 켰다',
    );
  });
}
