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
import 'package:navigation_client/screens/map_shell/widgets/sheets/transit_routes_sheet.dart';
import 'package:navigation_client/screens/outdoor_map/widgets/transit_summary_card.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/state/recent_route_points_controller.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/widgets/eta_card.dart';
import 'package:navigation_client/widgets/transit_itinerary_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `대중교통` 칩이 자동차·도보와 **같은 그림**을 내는지에 대한 회귀 테스트.
///
/// 조회가 끝나면 목록을 열기 전에 첫 후보를 미리 그리고, 그 뒤에는 카드를 누른
/// 그 후보로 갈아친다(확정은 아니다). 그 미리보기는
/// **지도에만** 나타난다 — 목록이 떠 있는 동안 요약 카드까지 뜨면 시트가 두
/// 겹이다. 그리고 상세의 `안내 시작`은 확정과 안내를 한 번에 한다.
/// 하네스(`fix()`·`drain()`·저장소 교체)는 `back_steps_out_of_route_test.dart`와 같다.
class _FakeTransitRepository implements TransitRepository {
  _FakeTransitRepository(this.answer);

  final TransitRoutes answer;

  @override
  bool get isAvailable => true;

  @override
  Future<TransitRoutes> getTransitRoutes({
    required LatLng origin,
    required LatLng destination,
    int count = 0,
  }) async => answer;
}

/// 첫·마지막 구간을 **도보로** 둔다. 그래야 목록 단계의 보행자 조회가 아예
/// 안 나가, 미리보기가 새 호출을 부르는지 여부가 로그에서 바로 보인다.
/// [fare]로 후보를 구분한다 — 미리보기가 첫 후보인지 보는 손잡이다.
TransitItinerary _itinerary(int fare) => TransitItinerary(
  totalTimeSeconds: 1200,
  totalWalkTimeSeconds: 300,
  totalDistanceMeters: 3000,
  transferCount: 0,
  fare: fare,
  legs: [
    // 첫 점이 아래 GPS 좌표다.
    TransitLeg(
      mode: TransitMode.walk,
      sectionTimeSeconds: 300,
      distanceMeters: 200,
      points: const [LatLng(37.5665, 126.9800), LatLng(37.5670, 126.9805)],
    ),
    TransitLeg(
      mode: TransitMode.bus,
      sectionTimeSeconds: 600,
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

/// 좌표가 하나도 없는 후보. 그릴 선이 없다.
TransitItinerary _pointlessItinerary() => TransitItinerary(
  totalTimeSeconds: 1200,
  totalWalkTimeSeconds: 300,
  totalDistanceMeters: 3000,
  transferCount: 0,
  fare: 1500,
  legs: [
    TransitLeg(
      mode: TransitMode.bus,
      sectionTimeSeconds: 600,
      distanceMeters: 2600,
      points: const [],
      startName: '앞 정류장',
      endName: '뒤 정류장',
      stationCount: 3,
    ),
  ],
);

void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;
  late RecentRoutePointsController originalRecents;
  late TransitRepository originalTransitRepository;

  final repository = MockBuildingRepository();

  // 건물 밖 좌표. 건물 안이면 GPS가 실내 진입을 발동시켜 야외 흐름이 갈라진다.
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

  /// 경로에서 5 km 넘게 떨어진 위치. 안내 시작 가드(150 m)에 확실히 걸린다.
  Position far() => Position(
    latitude: 37.6100,
    longitude: 127.0500,
    timestamp: DateTime(2024, 1, 1, 0, 1),
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

  /// GPS 스트림을 돌려준다 — 안내 시작 가드를 보려면 경로를 그린 **뒤에** 멀리
  /// 떨어진 위치를 한 번 더 밀어 넣어야 한다.
  Future<StreamController<Position>> pumpShell(WidgetTester tester) async {
    final positions = StreamController<Position>.broadcast();
    addTearDown(positions.close);
    watchPosition = () => positions.stream;

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await drain(tester);
    positions.add(fix());
    await drain(tester);
    return positions;
  }

  Finder destinationField() => find.descendant(
    of: find.byKey(const Key('route-draft-destination')),
    matching: find.byType(TextField),
  );

  /// 강의실까지 도보 경로를 그린 뒤 `대중교통`으로 갈아탄다. 갈아타기 전의
  /// 도보 경로가 있어야 "앞 수단이 남는가"를 볼 수 있다.
  Future<StreamController<Position>> tapTransit(
    WidgetTester tester,
    TransitRoutes answer,
  ) async {
    transitRepository = _FakeTransitRepository(answer);
    final positions = await pumpShell(tester);
    await tester.tap(find.byTooltip('길찾기'));
    await drain(tester);
    await tester.enterText(destinationField(), '강의실');
    await drain(tester);
    await tester.tap(find.text('강의실 101').first);
    await drain(tester);
    expect(
      find.byType(EtaCard),
      findsOneWidget,
      reason: '테스트 전제(앞 수단인 도보 경로가 그려짐)가 성립하지 않았다',
    );
    await tester.tap(find.text('대중교통'));
    await drain(tester);
    return positions;
  }

  TransitItinerary previewed(WidgetTester tester) => tester
      .widget<TransitSummaryCard>(find.byType(TransitSummaryCard))
      .itinerary;

  /// 첫 후보의 상세를 열어 `안내 시작`으로 확정한다. 같은 글자가 하단 카드에도
  /// 있을 수 있어 상세 안으로 좁혀 찾는다.
  Future<void> pickFirstCandidate(WidgetTester tester) async {
    await tester.tap(find.byType(TransitItineraryCard).first);
    await drain(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(TransitRouteDetailSheet),
        matching: find.text('안내 시작'),
      ),
    );
    await drain(tester);
  }

  testWidgets('목록이 떠 있는 동안에는 요약 카드를 감춘다', (WidgetTester tester) async {
    await tapTransit(
      tester,
      TransitRoutes.ok([_itinerary(1500), _itinerary(1600)]),
    );

    expect(find.byType(TransitRoutesSheet), findsOneWidget);
    expect(
      find.byType(TransitSummaryCard),
      findsNothing,
      reason: '목록 위에 요약 카드까지 뜨면 시트가 두 겹이다',
    );
    // 미리보기가 실제로 돌았다는 증거. 앞 수단(도보) 카드는 `showTransitRoute`가
    // 경로를 갈아치울 때만 사라진다 — 아래 "좌표가 없으면"과 정확히 반대다.
    expect(
      find.byType(EtaCard),
      findsNothing,
      reason: '대중교통을 눌렀는데 앞 수단 경로가 남아 있으면 안 된다',
    );
  });

  testWidgets('목록을 아무것도 안 고르고 닫으면 그때 미리보기 카드가 뜬다', (WidgetTester tester) async {
    await tapTransit(
      tester,
      TransitRoutes.ok([_itinerary(1500), _itinerary(1600)]),
    );
    await tester.binding.handlePopRoute();
    await drain(tester);

    expect(find.byType(TransitRoutesSheet), findsNothing);
    expect(find.byType(TransitSummaryCard), findsOneWidget);
    expect(previewed(tester).fare, 1500, reason: '미리 그리는 것은 첫(최적) 후보다');
  });

  testWidgets('다른 카드를 누르면 지도 경로가 그 후보로 갈아탄다', (WidgetTester tester) async {
    await tapTransit(
      tester,
      TransitRoutes.ok([_itinerary(1500), _itinerary(1600)]),
    );

    // 두 번째 후보의 상세를 열었다가 아무것도 안 고르고 나온다.
    await tester.tap(find.byType(TransitItineraryCard).at(1));
    await drain(tester);
    await tester.binding.handlePopRoute();
    await drain(tester);
    // 목록도 닫는다 — 요약 카드는 목록이 덮는 동안 감춰져 있어 이때만 읽힌다.
    await tester.binding.handlePopRoute();
    await drain(tester);

    expect(
      previewed(tester).fare,
      1600,
      reason: '고르지 않고 닫아도 마지막에 본 후보가 지도에 남아야 한다',
    );
  });

  testWidgets('상세를 열었다 뒤로 닫으면 목록만 남고 카드는 계속 감춰져 있다', (
    WidgetTester tester,
  ) async {
    await tapTransit(
      tester,
      TransitRoutes.ok([_itinerary(1500), _itinerary(1600)]),
    );
    await tester.tap(find.byType(TransitItineraryCard).first);
    await drain(tester);
    expect(find.byType(TransitRouteDetailSheet), findsOneWidget);

    await tester.binding.handlePopRoute();
    await drain(tester);

    expect(find.byType(TransitRouteDetailSheet), findsNothing);
    expect(
      find.byType(TransitRoutesSheet),
      findsOneWidget,
      reason: '견주던 목록이 남아야 한다',
    );
    expect(find.byType(TransitSummaryCard), findsNothing);
  });

  testWidgets('상세의 안내 시작이 안내까지 건다', (WidgetTester tester) async {
    await tapTransit(
      tester,
      TransitRoutes.ok([_itinerary(1500), _itinerary(1600)]),
    );
    await pickFirstCandidate(tester);

    expect(find.byType(TransitRoutesSheet), findsNothing);
    expect(
      find.byType(TransitSummaryCard),
      findsOneWidget,
      reason: '목록이 닫혔으니 카드가 돌아온다',
    );
    expect(
      find.text('안내 시작'),
      findsNothing,
      reason: '확정만 하고 멈추면 사용자가 같은 버튼을 두 번 누른다',
    );
    expect(find.text('안내 종료'), findsOneWidget);
  });

  testWidgets('경로에서 멀면 안내는 안 걸리고 카드에 안내 시작이 남는다', (WidgetTester tester) async {
    final positions = await tapTransit(
      tester,
      TransitRoutes.ok([_itinerary(1500), _itinerary(1600)]),
    );
    // 미리보기가 끝난 **뒤에** 경로에서 멀리 떨어진 위치를 밀어 넣는다. 처음부터
    // 멀면 앞 도보 구간이 그 자리까지 채워져 경로가 사용자를 지나간다.
    positions.add(far());
    await drain(tester);
    await pickFirstCandidate(tester);

    expect(find.byType(TransitSummaryCard), findsOneWidget);
    expect(
      find.text('안내 시작'),
      findsOneWidget,
      reason: '가드에 걸려 안내가 안 걸렸으면 버튼이 남는 것이 맞다',
    );
    expect(find.text('경로 근처에 있을 때 안내를 시작할 수 있습니다.'), findsOneWidget);
  });

  testWidgets('안내 중 뒤로 나와 목록을 다시 열어도 카드가 감춰졌다 돌아온다', (
    WidgetTester tester,
  ) async {
    await tapTransit(
      tester,
      TransitRoutes.ok([_itinerary(1500), _itinerary(1600)]),
    );
    await pickFirstCandidate(tester);
    await tester.binding.handlePopRoute();
    await drain(tester);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('route-planner')),
        matching: find.text('대중교통'),
      ),
    );
    await drain(tester);
    expect(find.byType(TransitRoutesSheet), findsOneWidget);
    expect(
      find.byType(TransitSummaryCard),
      findsNothing,
      reason: '다시 연 목록도 카드를 덮는다',
    );

    await tester.binding.handlePopRoute();
    await drain(tester);
    expect(find.byType(TransitSummaryCard), findsOneWidget);
  });

  testWidgets('조회가 실패하면 앞 수단 경로를 그대로 둔다', (WidgetTester tester) async {
    await tapTransit(
      tester,
      const TransitRoutes.failure(TransitRoutesStatus.noRoute),
    );

    expect(find.byType(TransitRoutesSheet), findsNothing);
    expect(find.byType(TransitSummaryCard), findsNothing);
    // 지우고 조회했으면 여기가 빈 화면이다. 새 경로가 없을 때 남길 것은 앞 경로다.
    expect(find.byType(EtaCard), findsOneWidget);
  });

  // 후보 0개는 여기까지 오지 않는다 — 두 저장소 모두 빈 목록을 `noRoute`로
  // 바꿔 답한다(`kakao_transit_repository.dart`·`tmap_transit_repository.dart`).
  // 억지로 만들면 미리보기가 아니라 후보 시트가 먼저 터진다(탭이 2개 미만).

  testWidgets('첫 후보에 좌표가 없으면 미리 그리지 않는다', (WidgetTester tester) async {
    await tapTransit(tester, TransitRoutes.ok([_pointlessItinerary()]));

    // 목록은 뜬다 — 그릴 선이 없다는 것과 후보가 없다는 것은 다르다.
    expect(find.byType(TransitRoutesSheet), findsOneWidget);
    // 목록이 떠 있는 동안은 카드가 어차피 감춰지므로, 미리보기가 안 돈 증거는
    // **앞 수단 카드가 살아 있는 것**이다.
    expect(
      find.byType(EtaCard),
      findsOneWidget,
      reason: '빈 선을 그리면 앞 경로만 지워지고 지도는 빈 화면이 된다',
    );

    // 목록을 닫아도 그릴 것이 없으니 대중교통 카드는 끝까지 안 뜬다.
    await tester.binding.handlePopRoute();
    await drain(tester);
    expect(find.byType(TransitSummaryCard), findsNothing);
  });
}
