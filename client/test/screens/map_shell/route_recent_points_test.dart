import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:geolocator/geolocator.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/state/recent_route_points_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 최근 출발지·목적지가 **길찾기 두 칸에 실제로 배선됐는지** 보는 테스트.
///
/// 저장소 자체의 규칙(상한·중복·복원)은
/// `test/state/recent_route_points_controller_test.dart`가 따로 못 박는다.
/// 여기서는 "길을 찾으면 남고, 다음에 열면 보이고, 누르면 그 칸이 찬다"만 본다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;
  late RecentRoutePointsController originalRecents;

  final repository = MockBuildingRepository();

  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// 건물 **밖** 좌표. 출발지를 따로 고르지 않아도 "현재 위치"로 길을 찾을 수
  /// 있어야 `_startRoute`까지 간다 — 그 앞에서 멈추면 저장 훅도 안 돈다.
  /// 건물 안 좌표를 쓰면 자동 실내 진입이 걸려 출발지 규칙이 PDR 앵커로 바뀐다.
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

  /// 화면을 띄우고 좌표 한 건을 흘려 넣는다.
  Future<void> pumpShell(WidgetTester tester) async {
    // broadcast여야 한다. 화면이 상황에 따라 위치를 다시 구독하는데, 단일 구독
    // 스트림은 취소 뒤 재구독하면 'already been listened to'로 터진다.
    final positions = StreamController<Position>.broadcast();
    addTearDown(positions.close);
    watchPosition = () => positions.stream;

    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const MapShellScreen()));
    await drain(tester);
    positions.add(fix());
    await drain(tester);
  }

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await debugModeController.reload();
    originalBuildingRepository = buildingRepository;
    originalDestinationRepository = destinationRepository;
    originalRecents = recentRoutePointsController;
    buildingRepository = repository;
    destinationRepository = MockDestinationRepository(repository);
    // 전역이라 테스트끼리 목록이 샌다. 매번 새로 만든다.
    recentRoutePointsController = RecentRoutePointsController();
    await recentRoutePointsController.ready;
    requestStartupPermissions = () async => {};
    await repository.getAllBuildings();
  });

  tearDown(() {
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    recentRoutePointsController = originalRecents;
    requestStartupPermissions = defaultRequestStartupPermissions;
    watchPosition = defaultWatchPosition;
  });

  /// 검색으로 매장을 골라 "도착"까지 눌러 한 번 길을 찾는다.
  Future<void> routeOnce(WidgetTester tester) async {
    await tester.tap(find.byType(TextField).first);
    await drain(tester);
    await tester.enterText(find.byType(TextField).first, '강의실');
    await drain(tester);
    await tester.tap(find.text('강의실 101').first);
    await drain(tester);
    await tester.tap(find.text('도착'));
    await drain(tester);
  }

  testWidgets('길을 찾으면 그 목적지가 최근 목록에 남는다', (WidgetTester tester) async {
    await pumpShell(tester);
    expect(
      recentRoutePointsController.points,
      isEmpty,
      reason: '테스트 전제(시작은 빈 목록)가 성립하지 않았다',
    );

    await routeOnce(tester);

    expect(
      recentRoutePointsController.points.map((p) => p.title),
      contains('강의실 101'),
      reason: '_startRoute를 지났는데 아무것도 안 남으면 다음 실행에서 보여 줄 것이 없다',
    );
  });

  testWidgets('길찾기 칸을 열면 최근 목록이 뜨고, 누르면 그 칸이 찬다', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);
    await routeOnce(tester);

    // 길찾기를 끝내고 새로 연다. 도착 칸을 눌러 아직 아무것도 안 친 상태를 만든다.
    await tester.tap(find.byTooltip('경로 계획 닫기'));
    await drain(tester);
    await tester.tap(find.byTooltip('길찾기'));
    await drain(tester);

    expect(
      find.text('최근 출발지 · 목적지'),
      findsOneWidget,
      reason: '남겨 둔 기록을 꺼내 볼 자리가 없으면 저장한 의미가 없다',
    );

    await tester.tap(find.text('강의실 101').last);
    await drain(tester);

    expect(find.text('강의실 101'), findsWidgets);
  });

  testWidgets('전체 삭제를 누르면 최근 목록이 사라진다', (WidgetTester tester) async {
    await pumpShell(tester);
    await routeOnce(tester);

    await tester.tap(find.byTooltip('경로 계획 닫기'));
    await drain(tester);
    await tester.tap(find.byTooltip('길찾기'));
    await drain(tester);
    expect(find.text('최근 출발지 · 목적지'), findsOneWidget);

    await tester.tap(find.text('전체 삭제'));
    await drain(tester);

    expect(recentRoutePointsController.points, isEmpty);
    expect(find.text('최근 출발지 · 목적지'), findsNothing);
  });
}
