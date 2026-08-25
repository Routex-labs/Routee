import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/route/directions_candidate.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:navigation_client/screens/map_shell/widgets/chrome/map_tab_bar.dart';
import 'package:navigation_client/screens/map_shell/widgets/search/route_field_results.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/state/recent_route_points_controller.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/widgets/eta_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 화면 아래로 뻗는 것들이 **탭 줄에 덮이지 않는지** 고정한다.
///
/// 탭 줄은 늘 바닥에 있고([MapTabBar]) 셸 Stack의 위층이라, 아래로 자라는 표면은
/// 무엇이든 그 줄만큼 자리를 비켜야 한다. 안 비키면 잘린 쪽은 조용히 사라진다 —
/// 실기기에서 ETA 카드의 지표 줄("1.2km · 거리")이 통째로 없어졌고 `안내 시작`
/// 버튼의 아래 모서리가 잘렸다. 지금 그 구간이 남은 자리는 **길찾기 후보
/// 목록**이다 — 경로 요약 카드는 선이 그려지는 순간 줄이 접혀 둘이 같은 화면에
/// 서지 않는다(`tab_bar_folds_when_route_drawn_test.dart`).
///
/// 카드 쪽은 반대 방향으로 남긴다: 비켜설 줄이 없어졌으면 띄워 둔 자리도
/// 반납해야 한다. 접는 조건과 높이를 더하는 조건의 단일 출처는 셸의
/// `_tabBarVisible`이다.
///
/// 재는 것은 높이도 리프트 값도 아니라 **두 상자가 겹치지 않는가** 하나다. 값으로
/// 재면 카드가 한 줄 늘어나는 날 테스트만 통과한다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;
  late RecentRoutePointsController originalRecents;

  final repository = MockBuildingRepository();

  /// 건물 **밖** 좌표. 안이면 출발지가 PDR 앵커로 바뀌어 경로가 그려지지 않는다
  /// (`guidance_chrome_folds_test.dart`가 같은 이유로 같은 좌표를 쓴다).
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

  /// 지도만 떠 있는 첫 화면.
  Future<void> pumpShell(WidgetTester tester) async {
    // broadcast여야 한다 — 화면이 위치를 다시 구독하는 자리가 있다.
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

  /// 경로가 그려지고 `안내 시작` 카드가 뜬 상태까지 띄운다.
  Future<void> pumpPlannedRoute(WidgetTester tester) async {
    await pumpShell(tester);
    // **상단 검색창이 아니라 길찾기 도착지 칸이다.** 이 화면은 건물 밖에 서
    // 있고, 실외 상단 검색은 우리 도면 매장을 돌려주지 않는다
    // (`search-result-list-ux.md` Y절). 후보를 고르면 그 자리에서 경로가
    // 그려지므로 "도착"을 따로 누르지 않는다.
    await tester.tap(find.byTooltip('길찾기'));
    await drain(tester);
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

  testWidgets('안내 중에도 카드가 바닥까지 내려와 있다', (WidgetTester tester) async {
    await pumpPlannedRoute(tester);
    await tester.tap(find.text('안내 시작'));
    await drain(tester);

    expect(
      find.byType(MapTabBar),
      findsNothing,
      reason: '테스트 전제(안내 중에는 탭 줄이 접힘)가 성립하지 않았다',
    );
    // 비켜설 것이 없어졌으면 띄워 둔 자리도 반납해야 한다. 안 그러면 안내
    // 화면에서 카드 밑에 빈 띠가 남는다.
    expect(
      tester.getBottomLeft(find.byType(EtaCard)).dy,
      tester.getSize(find.byType(Scaffold).first).height,
      reason: '탭 줄이 없는데도 카드가 떠 있으면 그만큼이 빈 자리로 남는다',
    );
  });

  testWidgets('길찾기 후보 목록의 마지막 줄이 탭 줄 뒤로 들어가지 않는다', (
    WidgetTester tester,
  ) async {
    // **목록을 화면보다 길게 만든다.** 목업 건물의 후보는 두 줄뿐이라 그대로
    // 재면 목록이 바닥에 닿지도 않는다 — 늘 통과하는 줄이 된다. 최근 지점은
    // 상한이 10이고([RecentRoutePointsController.maxEntries]) 도착 칸을 비워
    // 두면 그 목록이 그대로 뜨므로, 채워 두는 것만으로 넘친다.
    for (var i = 0; i < RecentRoutePointsController.maxEntries; i++) {
      await recentRoutePointsController.add(
        DirectionsCandidate(
          title: '최근 지점 $i',
          subtitle: '1F',
          point: LatLng(37.5665 + i * 0.0001, 126.9780),
        ),
      );
    }

    await pumpShell(tester);
    await tester.tap(find.byTooltip('길찾기'));
    await drain(tester);

    expect(
      find.byType(RouteFieldResults),
      findsOneWidget,
      reason: '테스트 전제(길찾기를 열면 최근 지점 목록이 뜸)가 성립하지 않았다',
    );
    final scroller = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(RouteFieldResults),
        matching: find.byType(Scrollable),
      ),
    );
    expect(
      scroller.position.maxScrollExtent,
      greaterThan(0),
      reason: '목록이 자리 안에 다 들어갔다 — 이 줄은 아무것도 재지 않았다',
    );

    expect(
      tester.getBottomLeft(find.byType(RouteFieldResults)).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byType(MapTabBar)).dy),
      reason: '목록이 탭 줄 밑까지 자라면 마지막 줄을 영영 못 본다',
    );
  });
}
