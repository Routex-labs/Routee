import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:navigation_client/screens/map_shell/widgets/chrome/map_tab_bar.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/state/recent_route_points_controller.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/widgets/eta_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 하단 탭 줄(지도·길찾기·이벤트·저장)이 **경로선과 함께 접히는지** 고정한다.
///
/// 선이 그려지면 화면의 일이 "이 경로를 본다" 하나로 좁혀지므로, 다른 데로
/// 가는 줄을 바닥에 남겨 둘 이유가 없다. 접는 조건의 단일 출처는 셸의
/// `_tabBarVisible`이다.
///
/// **두 가지를 한 번에 잰다** — 줄이 트리에서 빠지는 것과, 그 높이를 더하던
/// 쪽이 함께 자리를 반납하는 것. 하나만 고치면 카드가 빈 띠 위에 뜬다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;
  late RecentRoutePointsController originalRecents;

  final repository = MockBuildingRepository();

  /// 건물 **밖** 좌표. 안이면 출발지가 PDR 앵커로 바뀌어 경로가 그려지지 않는다
  /// (`nothing_covers_tab_bar_test.dart`가 같은 이유로 같은 좌표를 쓴다).
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
    buildingRepository = repository;
    destinationRepository = MockDestinationRepository(repository);
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

  Future<void> openRouteMode(WidgetTester tester) async {
    await tester.tap(find.byTooltip('길찾기'));
    await drain(tester);
  }

  Future<void> pickDestination(WidgetTester tester) async {
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('route-draft-destination')),
        matching: find.byType(TextField),
      ),
      '강의실',
    );
    await drain(tester);
    await tester.tap(find.text('강의실 101').first);
    await drain(tester);
  }

  testWidgets('도착지를 고르는 동안에는 탭 줄이 남아 있다', (WidgetTester tester) async {
    // 접는 기준이 `_routeMode`가 아니라 **그려진 선**이라는 것을 못 박는다.
    // 아직 어디로 갈지 고르는 중이면 지도를 둘러보는 것이고, 그때는 다른
    // 데로 빠질 문이 있어야 한다.
    await pumpShell(tester);
    await openRouteMode(tester);

    expect(find.byType(EtaCard), findsNothing);
    expect(find.byType(MapTabBar), findsOneWidget);
  });

  testWidgets('경로가 그려지면 탭 줄이 접히고 카드가 바닥까지 내려온다', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);
    await openRouteMode(tester);
    await pickDestination(tester);

    expect(
      find.byType(EtaCard),
      findsOneWidget,
      reason: '테스트 전제(도착지를 고르면 경로가 그려짐)가 성립하지 않았다',
    );
    expect(find.byType(MapTabBar), findsNothing);
    // 그리는 조건과 높이를 더하는 조건이 갈리면 여기서 잡힌다 — 줄은 없는데
    // 카드만 그만큼 떠서 바닥에 빈 띠가 남는다.
    expect(
      tester.getBottomLeft(find.byType(EtaCard)).dy,
      tester.getSize(find.byType(Scaffold).first).height,
      reason: '탭 줄이 없는데도 카드가 떠 있으면 그만큼이 빈 자리로 남는다',
    );
  });

  testWidgets('길찾기 바의 X가 탭 줄로 돌아가는 문이다', (WidgetTester tester) async {
    // 줄이 사라지면 '지도' 탭으로 빠져나가는 문이 닫힌다. 그 대신이 되는 것이
    // 상단 X 하나뿐이므로, 그것이 정말 줄을 되돌리는지 함께 고정한다.
    await pumpShell(tester);
    await openRouteMode(tester);
    await pickDestination(tester);
    expect(find.byType(MapTabBar), findsNothing);

    await tester.tap(find.byTooltip('경로 계획 닫기'));
    await drain(tester);

    expect(find.byType(MapTabBar), findsOneWidget);
  });
}
