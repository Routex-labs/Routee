import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/repositories/routing/transit_repository.dart';
import 'package:navigation_client/models/route/transit_route.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/transit_route_detail_sheet.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/transit_routes_sheet.dart';
import 'package:navigation_client/widgets/transit_itinerary_card.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/state/recent_route_points_controller.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:routex_design_system/routex_design_system.dart';
import 'package:navigation_client/widgets/eta_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 뒤로가기가 열려 있는 것을 한 겹씩 벗기는지에 대한 회귀 테스트.
///
/// 경로가 그려진 채 뒤로가기를 누르면 루트 라우트가 pop돼 앱이 통째로 꺼졌다.
/// 하네스(`fix()`·`drain()`·저장소 교체)는 `route_mode_test.dart`와 같다.
/// 목록이 뜨기만 하면 되므로 조회는 늘 같은 후보 둘을 돌려준다.
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

/// 첫·마지막 구간을 **도보로** 둔다. 그래야 앞뒤 도보를 채우는 보행자 조회가
/// 아예 안 나가, 이 테스트가 네트워크에 손대지 않는다.
TransitItinerary _itinerary(int seconds) => TransitItinerary(
  totalTimeSeconds: seconds,
  totalWalkTimeSeconds: 300,
  totalDistanceMeters: 3000,
  transferCount: 0,
  fare: 1500,
  legs: [
    // 첫 점이 아래 GPS 좌표다 — 안내 시작이 "경로 근처에 있는지"를 본다.
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
    originalTransitRepository = transitRepository;
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

  /// 길찾기 바로 들어가 강의실까지 도보 경로를 그린다.
  Future<void> planWalkRoute(WidgetTester tester) async {
    await tester.tap(find.byTooltip('길찾기'));
    await drain(tester);
    await tester.enterText(destinationField(), '강의실');
    await drain(tester);
    await tester.tap(find.text('강의실 101').first);
    await drain(tester);
  }

  /// 후보 목록에서 [index]번째 카드를 눌러 상세를 열고, 거기서 `안내 시작`으로
  /// 그 경로를 확정한다. **카드 탭만으로는 아무것도 그려지지 않는다** — 상세는
  /// 다른 후보와 견주라고 있는 한 겹이라, 지도는 이 버튼에서만 바뀐다.
  ///
  /// 이 버튼은 확정과 **안내 시작을 함께** 한다(`transit_preview_test.dart`).
  /// 그래서 이 함수를 부른 뒤 화면은 계획이 아니라 안내 중이다.
  Future<void> pickTransitCandidate(
    WidgetTester tester, [
    int index = 0,
  ]) async {
    await tester.tap(find.byType(TransitItineraryCard).at(index));
    await drain(tester);
    expect(
      find.byType(TransitRoutesSheet),
      findsOneWidget,
      reason: '카드를 눌렀다고 목록이 닫히면 다른 후보로 돌아올 길이 없다',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(TransitRouteDetailSheet),
        matching: find.text('안내 시작'),
      ),
    );
    await drain(tester);
    expect(find.byType(TransitRoutesSheet), findsNothing);
  }

  /// 길찾기 바가 지금 보여 주는 도착지. 경로만 지웠는지(칸은 살아 있는지)를 본다.
  /// 편집 중이 아닐 때 도착 칸은 TextField가 아니라 라벨이라 글자로 찾는다.
  Finder plannerDestination(String label) => find.descendant(
    of: find.byKey(const Key('route-planner')),
    matching: find.text(label),
  );

  /// 앱이 실제로 꺼졌는지를 세는 자리. `SystemNavigator.pop`은 플랫폼 채널로
  /// 나가므로 테스트에서는 가로채야 보인다.
  List<String> watchExit(WidgetTester tester) {
    final calls = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.pop') calls.add(call.method);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    return calls;
  }

  testWidgets('경로가 그려져 있으면 뒤로가기가 경로만 지우고 출발·도착은 남긴다', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);
    await planWalkRoute(tester);
    expect(find.byType(EtaCard), findsOneWidget);

    await tester.binding.handlePopRoute();
    await drain(tester);

    // 벗겨진 것은 지도의 경로 한 겹뿐이다. 길찾기 바와 그 안의 도착지가 남아야
    // 목적지를 다시 치지 않고 수단만 바꿔 볼 수 있다.
    expect(find.byType(MapShellScreen), findsOneWidget);
    expect(find.byType(EtaCard), findsNothing);
    expect(find.byKey(const Key('route-planner')), findsOneWidget);
    expect(plannerDestination('강의실 101'), findsOneWidget);
  });

  testWidgets('경로가 없는 길찾기 바에서 뒤로가기는 바를 닫아 검색창으로 되돌린다', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);
    await planWalkRoute(tester);

    await tester.binding.handlePopRoute(); // 경로 한 겹
    await drain(tester);
    await tester.binding.handlePopRoute(); // 길찾기 바 한 겹
    await drain(tester);

    expect(find.byKey(const Key('route-planner')), findsNothing);
    expect(find.byTooltip('길찾기'), findsOneWidget);
  });

  testWidgets('뒤로가기 세 번이 경로·길찾기 바·종료 확인을 한 겹씩 벗긴다', (
    WidgetTester tester,
  ) async {
    final exits = watchExit(tester);
    await pumpShell(tester);
    await planWalkRoute(tester);

    await tester.binding.handlePopRoute();
    await drain(tester);
    expect(find.byType(EtaCard), findsNothing);
    expect(find.byKey(const Key('route-planner')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await drain(tester);
    expect(find.byTooltip('길찾기'), findsOneWidget);
    expect(find.byType(RoutexDialog), findsNothing, reason: '두 겹을 한 번에 벗겼다');

    await tester.binding.handlePopRoute();
    await drain(tester);
    expect(find.byType(RoutexDialog), findsOneWidget);
    expect(exits, isEmpty, reason: '확인 전에 나가면 안전장치가 없는 것과 같다');
  });

  testWidgets('종료 확인에서 확인을 누르면 실제로 나간다', (WidgetTester tester) async {
    final exits = watchExit(tester);
    await pumpShell(tester);

    await tester.binding.handlePopRoute();
    await drain(tester);
    expect(find.byType(RoutexDialog), findsOneWidget);
    expect(exits, isEmpty);

    await tester.tap(find.text('종료'));
    await drain(tester);

    expect(exits, hasLength(1));
  });

  testWidgets('종료 확인 위에서 뒤로가기는 다이얼로그만 닫는다', (WidgetTester tester) async {
    final exits = watchExit(tester);
    await pumpShell(tester);

    await tester.binding.handlePopRoute();
    await drain(tester);
    expect(find.byType(RoutexDialog), findsOneWidget);

    await tester.binding.handlePopRoute();
    await drain(tester);

    expect(find.byType(RoutexDialog), findsNothing);
    expect(exits, isEmpty, reason: '확인창 위의 뒤로가기가 앱을 끄면 안전장치가 함정이 된다');
    expect(find.byType(MapShellScreen), findsOneWidget);
  });

  testWidgets('뒤로가기를 연타해도 종료 확인이 두 겹으로 쌓이지 않는다', (WidgetTester tester) async {
    final exits = watchExit(tester);
    await pumpShell(tester);

    // 한 프레임 간격의 연타. 둘째 누름이 방금 뜬 창을 도로 닫는 것까지는
    // 정상이라 개수는 상한만 본다 — 두 겹으로 쌓이면 한 번 확인해도 뒤에 남은
    // 창이 계속 길을 막는다.
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.binding.handlePopRoute();
    await drain(tester);

    expect(find.byType(RoutexDialog).evaluate(), hasLength(lessThan(2)));
    expect(exits, isEmpty, reason: '연타가 확인 없이 앱을 끄면 안전장치가 없는 것과 같다');
  });

  testWidgets('안내 중이면 뒤로가기가 안내만 끄고 경로는 남긴다', (WidgetTester tester) async {
    await pumpShell(tester);
    await tester.tap(find.byTooltip('길찾기'));
    await drain(tester);
    await tester.enterText(destinationField(), '강의실');
    await drain(tester);
    await tester.tap(find.text('강의실 101').first);
    await drain(tester);
    await tester.tap(find.text('안내 시작'));
    await drain(tester);
    expect(
      find.text('안내 종료'),
      findsOneWidget,
      reason: '테스트 전제(안내가 시작됨)가 성립하지 않았다',
    );

    await tester.binding.handlePopRoute();
    await drain(tester);

    // 벗겨진 것은 안내 한 겹뿐이다 — 경로도 길찾기 바도 그대로 있어야
    // 다른 후보를 다시 고를 수 있다.
    expect(find.byType(EtaCard), findsOneWidget);
    expect(find.text('안내 시작'), findsOneWidget);
    expect(
      find.byKey(const Key('route-planner')),
      findsOneWidget,
      reason: '길찾기 바까지 사라지면 다른 후보를 고를 문이 닫힌다',
    );
  });

  testWidgets('대중교통 안내 중 뒤로가기 뒤, 같은 칩을 다시 누르면 후보 목록이 돌아온다', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);
    await planWalkRoute(tester);
    await tester.tap(find.text('대중교통'));
    await drain(tester);
    expect(
      find.byType(TransitItineraryCard),
      findsWidgets,
      reason: '테스트 전제(후보 목록이 뜸)가 성립하지 않았다',
    );

    await pickTransitCandidate(tester);
    expect(
      find.text('안내 종료'),
      findsOneWidget,
      reason: '테스트 전제(안내가 시작됨)가 성립하지 않았다',
    );

    await tester.binding.handlePopRoute();
    await drain(tester);

    // 뒤로가기가 떨어뜨리는 곳은 **계획 화면**이다. 목록을 바로 띄우면 그
    // modal 시트가 방금 편 수단 줄을 덮어, 보이기만 하고 안 눌린다.
    expect(find.byType(TransitRoutesSheet), findsNothing);

    // 목록으로 가는 문은 그 수단 줄에 있다. 조회는 다시 나가지 않는다.
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('route-planner')),
        matching: find.text('대중교통'),
      ),
    );
    await drain(tester);

    expect(find.byType(TransitRoutesSheet), findsOneWidget);
  });

  testWidgets('길찾기를 끝내면 보관한 대중교통 조회도 함께 비워진다', (WidgetTester tester) async {
    await pumpShell(tester);
    await planWalkRoute(tester);
    await tester.tap(find.text('대중교통'));
    await drain(tester);
    await pickTransitCandidate(tester);

    // 안내 한 겹, 경로 한 겹, 길찾기 바 한 겹. 셋을 합치면 상단 X와 같은 정리다.
    // 첫 겹이 안내인 것은 상세의 `안내 시작`이 확정과 함께 안내를 걸기 때문이다.
    await tester.binding.handlePopRoute();
    await drain(tester);
    await tester.binding.handlePopRoute();
    await drain(tester);
    await tester.binding.handlePopRoute();
    await drain(tester);
    expect(
      find.byTooltip('길찾기'),
      findsOneWidget,
      reason: '테스트 전제(경로가 지워짐)가 성립하지 않았다',
    );

    // 이번엔 도보로 다시 안내를 건다. 옛 조회가 남아 있으면 아래에서 도보
    // 칩을 눌렀을 때 **예전 목적지의 후보 목록**이 튀어나온다.
    await planWalkRoute(tester);
    await tester.tap(find.text('안내 시작'));
    await drain(tester);
    await tester.binding.handlePopRoute();
    await drain(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('route-planner')),
        matching: find.text('도보'),
      ),
    );
    await drain(tester);

    expect(find.byType(TransitRoutesSheet), findsNothing);
  });

  testWidgets('수단을 바꾸면 보관한 대중교통 조회도 함께 버려진다', (WidgetTester tester) async {
    await pumpShell(tester);
    await planWalkRoute(tester);
    await tester.tap(find.text('대중교통'));
    await drain(tester);
    await pickTransitCandidate(tester);

    // 안내가 걸린 채로는 수단 줄이 접혀 있다. 뒤로 한 겹만 벗겨 계획 화면으로
    // 돌아온다 — 길찾기 자체는 끝내지 않는다.
    await tester.binding.handlePopRoute();
    await drain(tester);

    // 길찾기를 끝내지 않고 **수단만** 도보로 되돌린다. 여기서 옛 조회를 안
    // 버리면, 아래 도보 칩 재탭이 도보 화면 위에 대중교통 후보 시트를 띄운다.
    await tester.tap(find.text('도보'));
    await drain(tester);
    await tester.tap(find.text('안내 시작'));
    await drain(tester);

    await tester.binding.handlePopRoute();
    await drain(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('route-planner')),
        matching: find.text('도보'),
      ),
    );
    await drain(tester);

    expect(find.byType(TransitRoutesSheet), findsNothing);
  });
}
