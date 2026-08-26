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
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/state/recent_route_points_controller.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/widgets/transit_itinerary_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 후보 **목록**에 앞뒤 도보가 채워져 뜨는지에 대한 회귀 테스트.
///
/// 카카오는 첫 승차 전·마지막 하차 뒤 도보를 안 준다. 채우는 일이 고른 뒤에만
/// 돌던 시절에는 목록의 선이 정류장에서 시작해, 사용자가 "정문까지 걸어가야
/// 하는데 생략됐다"고 지적했다. 하네스는 `back_steps_out_of_route_test.dart`와 같다.
///
/// 후보는 **버스 한 구간뿐**이라 앞뒤가 모두 비어 있다 — 그래야 채우는 쪽이
/// 실제로 도는지 보인다. 도보 조회는 키가 없을 때 쓰는 직선 Mock이 답한다.
class _FakeTransitRepository implements TransitRepository {
  _FakeTransitRepository(this.candidates);

  final int candidates;

  @override
  bool get isAvailable => true;

  @override
  Future<TransitRoutes> getTransitRoutes({
    required LatLng origin,
    required LatLng destination,
    int count = 0,
  }) async => TransitRoutes.ok([
    for (var index = 0; index < candidates; index++) _itinerary(index),
  ]);
}

/// 후보마다 승·하차 정류장을 다르게 둔다 — 겹치면 중복 제거에 먹혀 상한
/// (기본 10건)에 걸리는 경우를 만들 수 없다.
LatLng _boarding(int index) => LatLng(37.5670 + index * 0.001, 126.9805);

LatLng _alighting(int index) => LatLng(37.5720 + index * 0.001, 126.9900);

/// 요금을 후보마다 다르게 둔다 — 헤더의 이 글자가 목록에서 그 후보를 찾는
/// 손잡이다. 소요 시간은 뒤에 있는 도보 안내 카드와 겹칠 수 있어 안 쓴다.
String _fareLabel(int index) => '${1500 + index * 100}원'.replaceAllMapped(
  RegExp(r'^(\d)(\d{3})'),
  (m) => '${m[1]},${m[2]}',
);

TransitItinerary _itinerary(int index) => TransitItinerary(
  totalTimeSeconds: 1200,
  totalWalkTimeSeconds: 300,
  totalDistanceMeters: 3000,
  transferCount: 0,
  fare: 1500 + index * 100,
  legs: [
    TransitLeg(
      mode: TransitMode.bus,
      sectionTimeSeconds: 600,
      distanceMeters: 2600,
      points: [_boarding(index), _alighting(index)],
      startName: '승차$index',
      endName: '하차$index',
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

  /// 강의실까지 도보 경로를 그린 뒤 대중교통으로 갈아탄다.
  Future<void> openTransitList(WidgetTester tester, int candidates) async {
    transitRepository = _FakeTransitRepository(candidates);
    await pumpShell(tester);
    await tester.tap(find.byTooltip('길찾기'));
    await drain(tester);
    await tester.enterText(destinationField(), '강의실');
    await drain(tester);
    await tester.tap(find.text('강의실 101').first);
    await drain(tester);
    await tester.tap(find.text('대중교통'));
    await drain(tester);
  }

  /// 첫 후보의 상세를 열어 `안내 시작`으로 확정한다. 카드 탭은 지도만 갈아치울
  /// 뿐 확정이 아니고, 이 버튼 하나로 **안내까지 시작된다**(`transit_preview_test.dart`).
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

  TransitItinerary cardAt(WidgetTester tester, int index) => tester
      .widget<TransitItineraryCard>(find.byType(TransitItineraryCard).at(index))
      .itinerary;

  testWidgets('후보 목록이 뜨기 전에 앞뒤 도보가 채워진다', (WidgetTester tester) async {
    await openTransitList(tester, 2);
    expect(
      find.byType(TransitItineraryCard),
      findsNWidgets(2),
      reason: '테스트 전제(후보 목록이 뜸)가 성립하지 않았다',
    );

    for (final index in [0, 1]) {
      final legs = cardAt(tester, index).legs;
      expect(legs.length, 3, reason: '앞뒤 도보가 붙어 세 구간이어야 한다');
      expect(legs.first.mode.isWalk, isTrue);
      expect(legs.first.endName, '승차$index');
      expect(legs.last.mode.isWalk, isTrue);
      expect(legs.last.startName, '하차$index');
      // 조회가 실제로 나갔다는 증거. 직선으로 떨어진 구간은 0초다.
      expect(legs.first.sectionTimeSeconds, greaterThan(0));
      expect(legs.last.sectionTimeSeconds, greaterThan(0));
    }

    // 총 소요는 그대로다 — 카카오 totalTime에 이 도보가 이미 들어 있다.
    expect(cardAt(tester, 0).totalTimeSeconds, 1200);
  });

  testWidgets('상한을 넘은 후보는 직선으로 떨어지고 목록은 그대로 뜬다', (WidgetTester tester) async {
    // 후보 6개 × (앞·뒤) = 12건이라 기본 상한 10건을 넘는다. 잘리는 것은
    // 여섯 번째 후보 몫이다.
    await openTransitList(tester, 6);
    await tester.scrollUntilVisible(
      find.text(_fareLabel(5)),
      200,
      scrollable: find
          .descendant(
            of: find.byType(TransitRoutesSheet),
            matching: find.byType(Scrollable),
          )
          .last,
    );
    await drain(tester);

    final legs = tester
        .widget<TransitItineraryCard>(
          find.ancestor(
            of: find.text(_fareLabel(5)),
            matching: find.byType(TransitItineraryCard),
          ),
        )
        .itinerary
        .legs;
    expect(legs.length, 3, reason: '상한을 넘어도 도보 구간 자체는 붙어야 한다');
    expect(legs.first.sectionTimeSeconds, 0, reason: '조회를 안 했으니 직선이다');
    expect(legs.first.points.length, 2);
    expect(legs.last.sectionTimeSeconds, 0);
    expect(legs.last.points.length, 2);
  });

  /// [body]를 도는 동안 나온 도보 채우기 로그만 골라 담는다.
  ///
  /// `directionsRepository`는 바꿔 끼울 수 없어(service_locator의 final) 실호출
  /// 건수를 세는 자리가 이 로그밖에 없다. `debugPrint`는 **테스트 본문 안에서**
  /// 되돌린다 — addTearDown은 프레임워크의 전역 변수 검사보다 늦게 돈다.
  Future<List<String>> walkFillLog(Future<void> Function() body) async {
    final lines = <String>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null && message.contains('도보 채우기')) lines.add(message);
    };
    try {
      await body();
    } finally {
      debugPrint = original;
    }
    return lines;
  }

  testWidgets('목록에서 부른 도보를 후보 선택이 다시 부르지 않는다', (WidgetTester tester) async {
    final lines = await walkFillLog(() async {
      await openTransitList(tester, 2);
      await pickFirstCandidate(tester);
    });

    // 후보 2개 × (앞·뒤) = 4건, 상한 10에 안 걸린다. 그리고 마지막 하차 →
    // 목적지는 목록에서 이미 부른 그 구간이라 고를 때는 한 건도 안 나간다 —
    // 여기가 1건이면 후보를 고를 때마다 TMAP 할당량을 그만큼 버리는 것이다.
    expect(lines, [
      '[transit] 목록 도보 채우기: 필요 4건 실호출 4건 잘림 0건',
      '[transit] 고른 경로 도보 채우기: 실호출 0건',
    ]);
  });

  testWidgets('안내를 끄고 다시 연 목록에도 도보가 남아 있다', (WidgetTester tester) async {
    await openTransitList(tester, 2);
    await pickFirstCandidate(tester);
    expect(
      find.text('안내 종료'),
      findsOneWidget,
      reason: '테스트 전제(안내가 시작됨)가 성립하지 않았다',
    );

    // 뒤로가기는 계획 화면까지만 벗긴다. 목록은 수단 줄의 `대중교통`을 다시
    // 눌러 연다(`back_steps_out_of_route_test.dart`).
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

    final legs = cardAt(tester, 0).legs;
    expect(legs.length, 3, reason: '보관한 목록이 채우기 전 원본이면 여기서 한 구간으로 돌아온다');
    expect(legs.first.sectionTimeSeconds, greaterThan(0));
  });
}
