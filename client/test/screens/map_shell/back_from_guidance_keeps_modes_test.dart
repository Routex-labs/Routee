import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/route/transit_route.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/repositories/routing/transit_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/transit_route_detail_sheet.dart';
import 'package:navigation_client/screens/outdoor_map/widgets/transit_summary_card.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/transit_routes_sheet.dart';
import 'package:navigation_client/state/recent_route_points_controller.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/widgets/transit_itinerary_card.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 안내를 시작한 뒤 뒤로가기를 누르면 **이동 수단을 다시 고를 수 있는 계획
/// 화면**으로 돌아오는지에 대한 회귀 테스트. 세 수단이 각자 다른 길을 타므로
/// 셋을 모두 같은 단언으로 확인한다.
class _FakeTransitRepository implements TransitRepository {
  @override
  bool get isAvailable => true;

  @override
  Future<TransitRoutes> getTransitRoutes({
    required LatLng origin,
    required LatLng destination,
    int count = 0,
  }) async => TransitRoutes.ok([_itinerary(1200), _itinerary(1800)]);
}

/// 첫·마지막 구간을 도보로 둬 앞뒤 도보 채우기 조회가 안 나가게 한다.
TransitItinerary _itinerary(int seconds) => TransitItinerary(
  totalTimeSeconds: seconds,
  totalWalkTimeSeconds: 300,
  totalDistanceMeters: 3000,
  transferCount: 0,
  fare: 1500,
  legs: [
    TransitLeg(
      mode: TransitMode.walk,
      sectionTimeSeconds: 300,
      distanceMeters: 200,
      points: const [LatLng(37.5665, 126.9800), LatLng(37.5670, 126.9805)],
    ),
    TransitLeg(
      mode: TransitMode.bus,
      sectionTimeSeconds: seconds - 600,
      distanceMeters: 2600,
      points: const [LatLng(37.5670, 126.9805), LatLng(37.5720, 126.9900)],
      startName: '앞 정류장',
      endName: '뒤 정류장',
      stationCount: 3,
    ),
    TransitLeg(
      mode: TransitMode.walk,
      sectionTimeSeconds: 300,
      distanceMeters: 200,
      points: const [LatLng(37.5720, 126.9900), LatLng(37.5725, 126.9905)],
    ),
  ],
);

void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;
  late RecentRoutePointsController originalRecents;
  late TransitRepository originalTransitRepository;

  final repository = MockBuildingRepository();

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
    originalRecents = recentRoutePointsController;
    originalTransitRepository = transitRepository;
    buildingRepository = repository;
    destinationRepository = MockDestinationRepository(repository);
    transitRepository = _FakeTransitRepository();
    recentRoutePointsController = RecentRoutePointsController();
    await recentRoutePointsController.ready;
    requestStartupPermissions = () async => {};
    await repository.getAllBuildings();
  });

  tearDown(() {
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    recentRoutePointsController = originalRecents;
    transitRepository = originalTransitRepository;
    requestStartupPermissions = defaultRequestStartupPermissions;
    watchPosition = defaultWatchPosition;
  });

  Future<void> pumpShell(WidgetTester tester) async {
    final positions = StreamController<Position>.broadcast();
    addTearDown(positions.close);
    watchPosition = () => positions.stream;

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await drain(tester);
    positions.add(fix());
    await drain(tester);
  }

  Finder destinationField() => find.descendant(
    of: find.byKey(const Key('route-draft-destination')),
    matching: find.byType(TextField),
  );

  Future<void> planRoute(WidgetTester tester) async {
    await tester.tap(find.byTooltip('길찾기'));
    await drain(tester);
    await tester.enterText(destinationField(), '강의실');
    await drain(tester);
    await tester.tap(find.text('강의실 101').first);
    await drain(tester);
  }

  /// 뒤로가기 뒤에 남아야 하는 것 — 계획 화면과 **고를 수 있는 세 수단**,
  /// 그리고 방금 보던 경로. 경로가 지워지면 한 겹을 잘못 벗긴 것이다.
  void expectPlannerWithModes(WidgetTester tester) {
    expect(
      find.text('안내 시작'),
      findsWidgets,
      reason: '경로 카드까지 사라지면 안내가 통째로 끝난 것이다',
    );
    expect(
      find.byKey(const Key('route-planner')),
      findsOneWidget,
      reason: '길찾기 바가 사라지면 수단을 다시 고를 문이 닫힌다',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('route-planner')),
        matching: find.text('강의실 101'),
      ),
      findsOneWidget,
      reason: '도착지까지 지워지면 처음부터 다시 쳐야 한다',
    );
    for (final label in ['자동차', '대중교통', '도보']) {
      expect(
        find.descendant(
          of: find.byKey(const Key('route-planner')),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: '$label 버튼이 없으면 수단을 다시 고를 수 없다',
      );
    }
  }

  testWidgets('도보 안내 시작 뒤 뒤로가기는 수단을 고를 수 있는 계획 화면으로 돌아온다', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);
    await planRoute(tester);
    await tester.tap(find.text('안내 시작'));
    await drain(tester);
    expect(find.text('안내 종료'), findsOneWidget, reason: '테스트 전제(안내 시작)가 안 섰다');

    await tester.binding.handlePopRoute();
    await drain(tester);

    expectPlannerWithModes(tester);
  });

  testWidgets('자동차 안내 시작 뒤 뒤로가기는 수단을 고를 수 있는 계획 화면으로 돌아온다', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);
    await planRoute(tester);
    await tester.tap(find.text('자동차'));
    await drain(tester);
    await tester.tap(find.text('안내 시작'));
    await drain(tester);
    expect(find.text('안내 종료'), findsOneWidget, reason: '테스트 전제(안내 시작)가 안 섰다');

    await tester.binding.handlePopRoute();
    await drain(tester);

    expectPlannerWithModes(tester);
  });

  testWidgets('검색 → 매장 시트 → 도착으로 시작한 안내도 뒤로가기로 수단 줄까지 돌아온다', (
    WidgetTester tester,
  ) async {
    // 길찾기 바를 거치지 않고 들어오는 길이다. 실기기에서 제일 흔한 조작이고,
    // 이 길에서는 도착지가 `_routeDraftDestination`에 안 실릴 수 있다.
    await pumpShell(tester);
    await tester.tap(find.byType(TextField).first);
    await drain(tester);
    await tester.enterText(find.byType(TextField).first, '강의실');
    await drain(tester);
    await tester.tap(find.text('강의실 101').first);
    await drain(tester);
    await tester.tap(find.text('도착'));
    await drain(tester);
    await tester.tap(find.text('안내 시작'));
    await drain(tester);
    expect(find.text('안내 종료'), findsOneWidget, reason: '테스트 전제(안내 시작)가 안 섰다');

    await tester.binding.handlePopRoute();
    await drain(tester);

    expectPlannerWithModes(tester);
  });

  testWidgets('대중교통 안내 시작 뒤 뒤로가기는 수단을 고를 수 있는 계획 화면으로 돌아온다', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);
    await planRoute(tester);
    await tester.tap(find.text('대중교통'));
    await drain(tester);
    expect(
      find.byType(TransitItineraryCard),
      findsWidgets,
      reason: '후보 목록이 안 떴다',
    );

    await tester.tap(find.byType(TransitItineraryCard).first);
    await drain(tester);
    // 상세의 이 버튼 하나가 확정과 안내를 함께 한다 — 하단 카드에서 한 번 더
    // 누를 필요가 없다(`transit_preview_test.dart`).
    await tester.tap(
      find.descendant(
        of: find.byType(TransitRouteDetailSheet),
        matching: find.text('안내 시작'),
      ),
    );
    await drain(tester);
    expect(find.text('안내 종료'), findsOneWidget, reason: '테스트 전제(안내 시작)가 안 섰다');

    await tester.binding.handlePopRoute();
    await drain(tester);

    expect(
      find.byType(TransitRoutesSheet),
      findsNothing,
      reason: '목록 시트가 덮으면 뒤에 펴진 수단 줄이 보이기만 하고 안 눌린다',
    );
    expectPlannerWithModes(tester);

    // 수단 줄이 **실제로 눌리는지**까지 본다. 여기가 사용자가 말한
    // "다시 자동차·대중교통·걷기로 돌아온다"의 마지막 한 걸음이다.
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('route-planner')),
        matching: find.text('도보'),
      ),
    );
    await drain(tester);

    expect(
      find.byType(TransitSummaryCard),
      findsNothing,
      reason: '도보로 바꿨는데 대중교통 요약 카드가 남으면 수단 전환이 안 먹은 것이다',
    );
  });
}
