import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/category_stores_sheet.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/place_detail_sheet.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/widgets/sheet_stack_guard.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/categorized_building_repository.dart';

/// 상단 패널이 켜지면 **떠 있는 시트가 걷히는지** 고정한다.
///
/// 검색 결과·길찾기 후보는 라우트가 아니라 화면 위쪽 표면이라
/// [SheetStackGuard]가 세지 못한다. 그래서 시트가 아래쪽에 그대로 남아 두 장이
/// 한 화면에 겹쳤다 — 매장 상세를 열어 둔 채 검색창을 눌러 치면 결과 목록과
/// 상세가 함께 떴다(실기기 확인).
///
/// **반대 방향은 이미 지켜지고 있었다** — 시트를 여는 입구는 전부
/// `_closeSearch`를 지난다. 빠져 있던 것은 이쪽 한 방향이다.
void main() {
  late BuildingRepository originalBuilding;
  late DestinationRepository originalDestination;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    originalBuilding = buildingRepository;
    originalDestination = destinationRepository;
    final repository = CategorizedBuildingRepository();
    buildingRepository = repository;
    destinationRepository = MockDestinationRepository(repository);
    // asset 캐시를 미리 채운다. 위젯 테스트의 가짜 시계는 실제 파일 I/O를
    // 기다려 주지 않아, 캐시가 비어 있으면 칩 줄이 뜨지 않는다.
    await repository.getAllBuildings();
  });

  tearDown(() {
    buildingRepository = originalBuilding;
    destinationRepository = originalDestination;
  });

  /// 실내 도면을 보는 상태에서 카테고리 목록 시트를 띄운다.
  ///
  /// 매장 상세가 아니라 이 시트를 쓰는 이유는 **여는 데 지도 컨트롤러가 필요
  /// 없어서**다. 재는 것은 시트의 종류가 아니라 "라우트로 뜬 시트가 남는가"다.
  Future<void> pumpShellWithSheet(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    sheetStackGuard.resetForTest();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        // 앱과 **같은 배선**이다(`app.dart`). 관찰자를 빼면 걷는 쪽이 아예 안 돈다.
        navigatorObservers: [sheetStackGuard],
        home: const MapShellScreen(),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .state<OutdoorMapBodyState>(find.byType(OutdoorMapBody))
        // ignore: invalid_use_of_visible_for_testing_member
        .enterIndoorForTest();
    await tester.pumpAndSettle();

    await tester.tap(find.text('서비스'));
    await tester.pumpAndSettle();
    expect(
      find.byType(CategoryStoresSheet),
      findsOneWidget,
      reason: '테스트 전제(칩을 누르면 목록 시트가 뜸)가 성립하지 않았다',
    );
  }

  testWidgets('검색을 시작하면 떠 있던 시트가 걷힌다', (tester) async {
    await pumpShellWithSheet(tester);

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '우리은행');
    // 결과는 색인 조회를 한 번 지나 온다. `pumpAndSettle`은 예약된 프레임이
    // 없으면 곧바로 끝나므로, 그 사이 도착하는 응답을 못 기다린다.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
      sheetStackGuard.openCount,
      0,
      reason: '검색 결과가 뜨는데 시트가 남으면 두 표면이 한 화면에 겹친다',
    );
    expect(find.byType(CategoryStoresSheet), findsNothing);
    expect(find.byType(PlaceDetailSheet), findsNothing);
    // 걷어낸 자리에 검색 결과가 실제로 있어야 한다 — 시트만 사라지고 아무것도
    // 안 뜨면 이 줄은 "그냥 닫았다"와 구별되지 않는다.
    expect(find.text('우리은행 ATM'), findsWidgets);
  });

  testWidgets('길찾기 칸을 치기 시작해도 떠 있던 시트가 걷힌다', (tester) async {
    await pumpShellWithSheet(tester);

    await tester.tap(find.byTooltip('길찾기'));
    await tester.pumpAndSettle();

    expect(
      sheetStackGuard.openCount,
      0,
      reason: '후보 목록도 검색 결과와 같은 자리를 쓴다 — 시트가 남으면 똑같이 겹친다',
    );
    expect(find.byType(CategoryStoresSheet), findsNothing);
    expect(find.byKey(const Key('route-draft-destination')), findsOneWidget);
  });
}
