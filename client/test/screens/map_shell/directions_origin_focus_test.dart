import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 상단 길찾기 바에서 어느 칸을 눌렀는지에 따라 후보 목록이 그 칸 기준으로
/// 열려야 한다는 테스트.
///
/// 지키려는 증상: **출발 칸을 눌렀는데 후보가 도착지 기준인 것.** 그러면 출발지를
/// 바꾸려던 사용자는 칸을 한 번 더 눌러야 하고, 방금 누른 곳과 후보 목록이 말하는
/// 곳이 다르다.
///
/// 활성 칸은 후보 목록으로 구분한다 — 출발지가 활성일 때만 맨 위에 "현재 위치"
/// 고정 행이 붙는다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  final repository = MockBuildingRepository();

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
  });

  /// 도착지를 정해 상단 초안 바가 뜬 상태를 만든다. 경로 계산까지 갈 필요는
  /// 없으므로(GPS 없음) 초안 바가 떴는지만 확인한다.
  Future<void> openRouteDraft(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const MapShellScreen()));
    await drain(tester);

    await tester.tap(find.byType(TextField).first);
    await drain(tester);
    await tester.enterText(find.byType(TextField).first, '강의실');
    await drain(tester);
    await tester.tap(find.text('강의실 101').first);
    await drain(tester);
    await tester.tap(find.text('도착'));
    await drain(tester);

    expect(
      find.byKey(const Key('route-planner')),
      findsOneWidget,
      reason: '테스트 전제(상단 초안 바가 뜸)가 성립하지 않았다',
    );
  }

  /// 후보 목록의 "현재 위치" 고정 행. 출발지 칸이 활성일 때만 붙는다. 상단 초안
  /// 바에도 같은 문구가 있으므로 후보 목록의 고정 키로 좁힌다.
  Finder currentLocationRow() =>
      find.byKey(const Key('route-field-current-location'));

  testWidgets('출발 칸을 누르면 후보가 출발지 기준으로 열린다', (WidgetTester tester) async {
    await openRouteDraft(tester);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('route-planner')),
        matching: find.text('현재 위치'),
      ),
    );
    await drain(tester);

    expect(
      currentLocationRow(),
      findsOneWidget,
      reason: '출발 행을 눌렀으면 후보 목록이 출발지 기준이어야 한다',
    );
    // 출발 칸의 "현재 위치"는 값이 아니라 **안내문**이다. 글자로 채워 두면
    // 사용자가 다른 곳을 치기 전에 먼저 지워야 하고, 그 글자가 검색어로도 쓰여
    // 결과가 비어 버린다.
    final originField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('route-draft-origin')),
        matching: find.byType(TextField),
      ),
    );
    expect(originField.controller?.text, isEmpty);
    expect(originField.decoration?.hintText, '출발지를 입력하세요');
  });

  testWidgets('도착 칸을 누르면 후보가 도착지 기준으로 열린다', (WidgetTester tester) async {
    // 기본 흐름이 뒤집히지 않는지 함께 고정한다.
    await openRouteDraft(tester);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('route-planner')),
        matching: find.text('강의실 101'),
      ),
    );
    await drain(tester);

    expect(
      currentLocationRow(),
      findsNothing,
      reason: '도착 행을 눌렀는데 출발지 후보 목록이 나왔다',
    );
  });
}
