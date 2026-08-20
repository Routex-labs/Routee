import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:geolocator/geolocator.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:navigation_client/screens/map_shell/widgets/chrome/map_bottom_bar.dart';
import 'package:navigation_client/screens/map_shell/widgets/chrome/map_overlay_scroll_row.dart';
import 'package:navigation_client/widgets/eta_card.dart';
import 'package:navigation_client/widgets/directions_route_options_panel.dart';
import 'package:navigation_client/screens/map_shell/widgets/search/route_field_results.dart';
import 'package:navigation_client/state/recent_route_points_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 길찾기가 **상단 바 안에서** 끝나는지에 대한 회귀 테스트.
///
/// 한동안 길찾기는 전체 화면(`screens/route_planner/`)이었다. 지도를 새로 만들지
/// 않으려고 오버레이로 얹었지만 화면이 통째로 바뀌는 것은 마찬가지라, 목적지를
/// 고치려면 지도를 잃고 그 화면을 다시 열어야 했다. 지금은 상단 바가 출발/도착
/// 두 위치가 되고 그 아래에 이동 수단 줄이 붙는다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;
  late RecentRoutePointsController originalRecents;

  final repository = MockBuildingRepository();

  // 건물 밖 좌표(외곽선에서 약 185 m 동쪽). 건물 안이면 GPS가 실내 진입을
  // 발동시켜 야외 흐름이 아니라 실내 안내로 갈라진다.
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

  /// 지도만 떠 있는 첫 화면을 만든다.
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

  testWidgets('길찾기를 누르면 플래너가 뜨고 끝점 확정 뒤 이동 수단이 나타난다', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);
    // 전체 화면이 아니라는 것부터 고정한다 — 지도가 그대로 보여야 한다.
    expect(find.byKey(const Key('route-draft-origin')), findsNothing);

    await tester.tap(find.byTooltip('길찾기'));
    await drain(tester);

    expect(find.byKey(const Key('route-planner')), findsOneWidget);
    expect(find.text('현재 위치'), findsOneWidget);
    expect(find.byKey(const Key('route-draft-destination')), findsOneWidget);
    expect(find.text('자동차'), findsNothing);
    expect(find.text('도보'), findsNothing);

    await tester.enterText(destinationField(), '강의실');
    await drain(tester);
    await tester.tap(find.text('강의실 101').first);
    await drain(tester);

    // 테스트 환경에는 카카오 키가 없어 대중교통은 빠진다. 두 끝점이 확정된
    // 뒤에만 나머지 수단이 나타난다.
    expect(find.text('자동차'), findsOneWidget);
    expect(find.text('도보'), findsOneWidget);
    expect(
      tester.getRect(find.text('도보')).top,
      greaterThan(tester.getRect(find.text('현재 위치')).bottom),
    );
  });

  testWidgets('야외에서 아직 아무것도 안 쳤으면 빈 후보 카드를 남기지 않는다', (
    WidgetTester tester,
  ) async {
    // 야외 + 빈 도착 칸에는 별도 지름길이나 빈 검색 후보가 없다. 그런데도
    // 카드를 그리면 위치 행 아래에 아무
    // 내용 없는 흰 막대가 떠 있게 된다.
    await pumpShell(tester);
    await tester.tap(find.byTooltip('길찾기'));
    await drain(tester);

    // 위젯은 트리에 있어도 그리는 높이가 0이어야 한다 — 흰 막대의 정체가
    // "내용 없는 카드"였으므로 높이로 확인한다.
    expect(tester.getSize(find.byType(RouteFieldResults)).height, 0);
  });

  testWidgets('도착지를 그 자리에서 쳐서 고르면 경로가 그려진다', (WidgetTester tester) async {
    await pumpShell(tester);
    await tester.tap(find.byTooltip('길찾기'));
    await drain(tester);

    // 열자마자 도착 칸이 활성이라 바로 칠 수 있다.
    await tester.enterText(destinationField(), '강의실');
    await drain(tester);
    await tester.tap(find.text('강의실 101').first);
    await drain(tester);

    expect(find.byType(EtaCard), findsOneWidget);
    expect(find.byType(MapBottomBar), findsNothing);
    expect(find.byType(MapOverlayScrollRow), findsNothing);
    expect(
      tester.getBottomLeft(find.byType(EtaCard)).dy,
      tester.getSize(find.byType(Scaffold).first).height,
      reason: '안내 시작 전 경로 요약도 화면 하단에 붙어야 한다',
    );
    // 고른 값이 그 칸에 그대로 남아, 다시 눌러 고칠 수 있다.
    expect(find.byKey(const Key('route-draft-destination')), findsNothing);
    expect(find.text('강의실 101'), findsWidgets);
  });

  testWidgets('X를 누르면 길찾기 바와 경로가 함께 사라진다', (WidgetTester tester) async {
    await pumpShell(tester);
    await tester.tap(find.byTooltip('길찾기'));
    await drain(tester);
    await tester.enterText(destinationField(), '강의실');
    await drain(tester);
    await tester.tap(find.text('강의실 101').first);
    await drain(tester);
    expect(find.byType(EtaCard), findsOneWidget);

    await tester.tap(find.byTooltip('경로 계획 닫기'));
    await drain(tester);

    expect(find.byKey(const Key('route-draft-origin')), findsNothing);
    expect(find.byType(EtaCard), findsNothing);
    // 검색창이 돌아온다 — 길찾기가 끝났으니 상단 바는 원래 얼굴이어야 한다.
    expect(find.byTooltip('길찾기'), findsOneWidget);
  });

  testWidgets('자동차 모드에서 후보가 여러 개면 목록에서 고를 수 있다', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);
    await tester.tap(find.byTooltip('길찾기'));
    await drain(tester);
    await tester.enterText(destinationField(), '강의실');
    await drain(tester);
    await tester.tap(find.text('강의실 101').first);
    await drain(tester);

    await tester.tap(find.text('자동차'));
    await drain(tester);

    expect(find.byType(EtaCard), findsOneWidget);
    expect(find.text('추천'), findsOneWidget);
    expect(find.text('최단거리'), findsOneWidget);

    await tester.tap(find.text('최단거리'));
    await drain(tester);

    expect(find.byType(EtaCard), findsOneWidget);
    expect(find.text('최단거리'), findsOneWidget);
  });

  testWidgets('도보로 바꾸면 자동차 후보 목록이 남지 않는다', (WidgetTester tester) async {
    await pumpShell(tester);
    await tester.tap(find.byTooltip('길찾기'));
    await drain(tester);
    await tester.enterText(destinationField(), '강의실');
    await drain(tester);
    await tester.tap(find.text('강의실 101').first);
    await drain(tester);

    await tester.tap(find.text('자동차'));
    await drain(tester);

    // 자동차 후보가 여러 개 뜬 상태에서 시작한다(기존 테스트와 같은 전제).
    expect(find.text('추천'), findsOneWidget);
    expect(find.text('최단거리'), findsOneWidget);
    expect(find.byType(DirectionsRouteOptionsPanel), findsOneWidget);

    await tester.tap(find.text('도보'));
    await drain(tester);

    // 도보로 바뀌면 방금 본 자동차 후보 패널이 그대로 남아 있으면 안 된다.
    expect(find.byType(DirectionsRouteOptionsPanel), findsNothing);
    expect(find.text('최단거리'), findsNothing);
  });

  testWidgets('출발 칸을 누르면 "현재 위치"로 되돌릴 길이 목록에 있다', (WidgetTester tester) async {
    await pumpShell(tester);
    await tester.tap(find.byTooltip('길찾기'));
    await drain(tester);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('route-planner')),
        matching: find.text('현재 위치'),
      ),
    );
    await drain(tester);

    // 따로 고르지 않으면 현재 위치가 출발지이므로, 되돌아올 길이 목록 안에
    // 있어야 한다. 도착 칸에서는 뜨지 않는다.
    expect(
      find.byKey(const Key('route-field-current-location')),
      findsOneWidget,
    );
    // 지도 탭은 위치 행 편집 자체에 연결되므로 별도 지름길을 만들지 않는다.
    expect(find.byKey(const Key('route-field-pick-on-map')), findsNothing);
  });
}
