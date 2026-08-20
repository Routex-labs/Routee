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
import 'package:navigation_client/widgets/eta_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 상단 길찾기 바의 ⇅(출발↔도착 바꾸기)가 **실제로 반대 방향 경로를 다시 그리는지**
/// 에 대한 회귀 테스트.
///
/// 라벨만 뒤바뀌고 경로는 그대로면 사용자는 뒤집혔다고 믿은 채 원래 방향으로
/// 걷게 된다. 그래서 검증은 초안 바의 글자가 아니라 **ETA 카드가 가리키는
/// 도착지**로 한다 — 카드는 실제로 계산된 경로를 따라 그려지기 때문이다.
/// 판정 규칙 자체(무엇을 고르고 언제 못 고르는지)는
/// `test/domain/route_endpoint_swap_test.dart`가 경우별로 못 박는다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  final repository = MockBuildingRepository();

  /// 건물 **밖** 좌표(외곽선에서 약 185 m 동쪽).
  ///
  /// 예전에는 입구와 같은 좌표(37.5665, 126.9779)를 썼다. 그때는 진입 판정이
  /// "입구 앞 + 신호 저하"라 오차 10 m면 야외로 남았지만, 지금 판정은 "믿을 수
  /// 있는 좌표가 외곽선 안"이라(judgeBuildingFromGps) 그 좌표가 곧 실내 진입이
  /// 된다. 실내로 들어가면 출발지 기준이 PDR 앵커로 바뀌어 "도착"이 경로를
  /// 그리지 못하고, 이 테스트가 보려는 뒤집기까지 가지 못한다.
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
    buildingRepository = repository;
    destinationRepository = MockDestinationRepository(repository);
    requestStartupPermissions = () async => {};
    await repository.getAllBuildings();
  });

  tearDown(() {
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    requestStartupPermissions = defaultRequestStartupPermissions;
    watchPosition = defaultWatchPosition;
  });

  /// 플래너에서 고치는 위치만 입력창으로 열린다.
  Finder originField() => find.descendant(
    of: find.byKey(const Key('route-draft-origin')),
    matching: find.byType(TextField),
  );

  /// 출발지·도착지가 **둘 다 실제 지점**인 경로를 만든다. 뒤집기의 기본 경우다
  /// (현재 위치를 매장으로 굳히는 분기를 타지 않는다).
  Future<void> startRouteBetweenTwoPlaces(WidgetTester tester) async {
    final positions = StreamController<Position>.broadcast();
    addTearDown(positions.close);
    watchPosition = () => positions.stream;

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await drain(tester);
    positions.add(fix());
    await drain(tester);

    // 도착지 먼저 정해 초안 바를 띄운다.
    await tester.tap(find.byType(TextField).first);
    await drain(tester);
    await tester.enterText(find.byType(TextField).first, '강의실');
    await drain(tester);
    await tester.tap(find.text('강의실 101').first);
    await drain(tester);
    await tester.tap(find.text('도착'));
    await drain(tester);

    // 출발 칸에 그 자리에서 친다. 상단 바가 두 칸(진짜 입력창)이라 누르면
    // 커서가 그 칸에 잡히고 후보 목록이 그 칸 기준으로 열린다.
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('route-planner')),
        matching: find.text('현재 위치'),
      ),
    );
    await drain(tester);
    await tester.enterText(originField(), '데모');
    await drain(tester);
    await tester.tap(find.text('데모 건물').first);
    await drain(tester);
  }

  testWidgets('⇅를 누르면 출발지와 도착지가 뒤바뀌고 반대 방향 경로가 다시 그려진다', (
    WidgetTester tester,
  ) async {
    await startRouteBetweenTwoPlaces(tester);

    expect(
      find.descendant(of: find.byType(EtaCard), matching: find.text('강의실 101')),
      findsOneWidget,
      reason: '테스트 전제(뒤집기 전 도착지가 강의실 101)가 성립하지 않았다',
    );

    await tester.tap(find.byTooltip('목적지 더보기'));
    await drain(tester);

    expect(find.text('강의실 101'), findsWidgets);
    expect(find.text('데모 건물'), findsWidgets);

    // 그리고 **경로가 실제로 다시 계산됐다.** 라벨만 바뀌고 카드가 이전
    // 도착지를 가리키면 화면과 실제 안내가 어긋난 것이다.
    expect(
      find.descendant(of: find.byType(EtaCard), matching: find.text('데모 건물')),
      findsOneWidget,
      reason: '끝점을 뒤집었으면 경로를 끊지 말고 곧바로 반대 방향으로 다시 그려야 한다',
    );
  });

  testWidgets('출발지가 현재 위치이고 측위가 없으면 ⇅는 비활성이다', (WidgetTester tester) async {
    final positions = StreamController<Position>.broadcast();
    addTearDown(positions.close);
    watchPosition = () => positions.stream;

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await drain(tester);
    positions.add(fix());
    await drain(tester);

    await tester.tap(find.byType(TextField).first);
    await drain(tester);
    await tester.enterText(find.byType(TextField).first, '강의실');
    await drain(tester);
    await tester.tap(find.text('강의실 101').first);
    await drain(tester);
    await tester.tap(find.text('도착'));
    await drain(tester);

    // 출발지는 "현재 위치"(= _selectedOrigin이 null)이고, 이 테스트 환경에는
    // 실내 도달 거리 맵이 없다. 놓을 매장을 고를 근거가 없으므로 공용
    // 패턴은 누르지 못하는 장식 버튼 대신 동작 자체를 숨긴다.
    expect(
      find.byTooltip('목적지 더보기'),
      findsNothing,
      reason: '고를 근거가 없으면 활성처럼 보여서는 안 된다',
    );
  });
}
