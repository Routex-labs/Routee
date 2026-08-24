import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:navigation_client/screens/map_shell/widgets/chrome/category_chips_row.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/app_menu_sheet.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/building_info_sheet.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/category_stores_sheet.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/events_sheet.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/place_detail_sheet.dart';
import 'package:navigation_client/models/building/floor_plan.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:navigation_client/screens/outdoor_map/widgets/nearby_store_sheet.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/widgets/sheet_stack_guard.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/categorized_building_repository.dart';

/// 시트가 **겹쳐 쌓이지 않는지** 고정한다.
///
/// 지도 위 시트는 barrier가 없다([MapPassThroughSheetRoute]) — 시트를 놔둔 채
/// 지도를 움직이라고 일부러 뺐다. 그 대가로 시트가 떠 있는 동안에도 지도·상단
/// 바·칩 줄이 그대로 눌리고, 각 입구가 자기 시트만 막고 있어서 **다른 입구를
/// 누르면 시트가 두 겹**이 됐다.
///
/// **조합을 손으로 적지 않는다.** 입구가 열둘이라 순서쌍이 132개고 시트를 하나
/// 늘릴 때마다 스물넷이 붙는다. 대신 입구를 표에 두고 순서쌍을 돌리며, 불변식
/// 하나("살아 있는 시트 라우트는 한 장")를 [SheetStackGuard]가 잰다.
///
/// **상태마다 유효한 입구가 다르다.** 실내에서 다른 건물을 누를 수 없고 야외에는
/// 카테고리 칩 줄이 없다. 그래서 상태별로 표를 나눈다 — 조합만 늘리면 실제로는
/// 아무 일도 안 하고 통과하는 줄이 생기고, 그것이 가장 나쁜 초록이다.
void main() {
  late BuildingRepository originalBuilding;
  late DestinationRepository originalDestination;

  /// 목업 건물 외곽선(위도 37.5663~37.5667, 경도 126.9777~126.9783)의 한가운데.
  /// 매장 centroid도 같은 자리라 실내에서는 매장 탭이 된다.
  const insideBuilding = LatLng(37.5665, 126.9780);

  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await debugModeController.reload();
    originalBuilding = buildingRepository;
    originalDestination = destinationRepository;
    final repository = CategorizedBuildingRepository();
    buildingRepository = repository;
    destinationRepository = MockDestinationRepository(repository);
    requestStartupPermissions = () async => {};
    // asset 캐시를 미리 채운다. 위젯 테스트의 가짜 시계는 실제 파일 I/O를
    // 기다려 주지 않아, 캐시가 비어 있으면 칩 줄이 뜨지 않는다.
    await repository.getAllBuildings();
  });

  tearDown(() {
    buildingRepository = originalBuilding;
    destinationRepository = originalDestination;
    requestStartupPermissions = defaultRequestStartupPermissions;
    watchPosition = defaultWatchPosition;
  });

  Future<void> tapMap(WidgetTester tester) async {
    final state = tester.state<OutdoorMapBodyState>(find.byType(OutdoorMapBody));
    // 화면 좌표를 함께 준다. 기본값 (0,0)은 상단 바 아래라
    // [_isTapOnMapOverlay]가 먼저 삼켜, 검증하려는 분기까지 오지 않는다.
    // ignore: invalid_use_of_visible_for_testing_member
    await state.handleMapClickForTest(
      insideBuilding,
      screenPoint: const Offset(200, 400),
    );
    await drain(tester);
  }

  Future<void> pumpShell(WidgetTester tester, {required bool indoor}) async {
    // **앞 쌍의 트리를 확실히 헌다.** 같은 모양으로 다시 `pumpWidget`하면
    // Element가 재사용돼 NavigatorState가 살아남고, 앞 쌍에서 열어 둔 시트가
    // 그대로 얹혀 있는 채로 다음 쌍이 시작한다 — 그러면 재는 것이 이 쌍의
    // 결과가 아니라 앞 쌍의 잔해다.
    await tester.pumpWidget(const SizedBox.shrink());
    sheetStackGuard.resetForTest();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        // 앱과 **같은 배선**이다(`app.dart`). 관찰자를 빼고 재면 그물망이 무엇을
        // 받아냈는지 볼 수 없어, 정상 경로가 막은 것과 구별되지 않는다.
        navigatorObservers: [sheetStackGuard],
        home: const MapShellScreen(),
      ),
    );
    await drain(tester);
    if (!indoor) return;
    tester
        .state<OutdoorMapBodyState>(find.byType(OutdoorMapBody))
        // ignore: invalid_use_of_visible_for_testing_member
        .enterIndoorForTest();
    await drain(tester);
  }

  /// 입구 하나. 돌려주는 값은 "이 입구가 실제로 시트를 열었나"다 — 손가락이
  /// 빗나간 조합은 아무 일도 안 하고 통과해 **초록 거짓말**이 되기 때문이다.
  Future<bool> openMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('메뉴'), warnIfMissed: false);
    await drain(tester);
    return find.byType(AppMenuSheet).evaluate().isNotEmpty;
  }

  /// 실내에서 그 시트가 떠 있는 상태. 판의 쪽 카드를 누르면 열리는 것과 같은
  /// 시트를 직접 띄운다 — 판에 오늘 카드가 몇 장인지는 스냅샷 날짜에 달려 있어,
  /// 카드를 눌러 여는 길로 만들면 날짜가 지나는 순간 이 표가 통째로 헛돈다.
  Future<bool> openEventsSheet(WidgetTester tester) async {
    unawaited(
      EventsSheet.show(
        tester.element(find.byType(OutdoorMapBody)),
        onCloseAll: () {},
      ),
    );
    await drain(tester);
    return find.byType(EventsSheet).evaluate().isNotEmpty;
  }

  final outdoorEntries = <String, Future<bool> Function(WidgetTester)>{
    '건물 폴리곤 탭': (tester) async {
      await tapMap(tester);
      return find.byType(BuildingInfoSheet).evaluate().isNotEmpty;
    },
    '상단 바 메뉴': openMenu,
    // 이벤트는 여기에 없다. 탭 줄의 이벤트는 **건물 안에서만 서고**, 야외에서
    // 오늘 목록 시트를 여는 입구는 이제 하나도 없다([MapShellScreen] 탭 목록).
  };

  final indoorEntries = <String, Future<bool> Function(WidgetTester)>{
    // 지도 폴리곤 탭이 아니라 검색으로 연다 — 실내 매장 히트 판정은 지도
    // 컨트롤러가 있어야 서서, 위젯 테스트에서는 탭이 아무 데도 닿지 않는다.
    '검색 결과 탭': (tester) async {
      await tester.tap(find.byType(TextField).first, warnIfMissed: false);
      await drain(tester);
      await tester.enterText(find.byType(TextField).first, '우리은행');
      await drain(tester);
      final row = find.text('우리은행 ATM');
      if (row.evaluate().isEmpty) return false;
      await tester.tap(row.first, warnIfMissed: false);
      await drain(tester);
      return find.byType(PlaceDetailSheet).evaluate().isNotEmpty;
    },
    '카테고리 칩': (tester) async {
      // 칩 줄로 좁힌다 — 목록 시트가 뜨면 제목에도 같은 글자가 있다.
      final chip = find.descendant(
        of: find.byType(CategoryChipsRow),
        matching: find.text('서비스'),
      );
      await tester.tap(chip, warnIfMissed: false);
      await drain(tester);
      return find.byType(CategoryStoresSheet).evaluate().isNotEmpty;
    },
    '상단 바 메뉴': openMenu,
    // 하단 바 "가까운 매장으로 위치 지정" 버튼이 여는 시트. 그 버튼이 뜨려면
    // 실내 앵커·도면 상태가 갖춰져 있어야 해서, 여기서는 그 조건을 갖추는
    // 대신 띄우는 함수를 앱과 같은 것으로 직접 부른다.
    '근처 매장 위치 지정 시트': (tester) async {
      unawaited(
        showNearbyStoreSheet(
          tester.element(find.byType(OutdoorMapBody)),
          rows: [
            (
              store: const StorePolygon(
                id: '1F-0',
                name: '우리은행 ATM',
                polygon: [],
                centroid: LatLng(37.5665, 126.978),
              ),
              distanceM: 3,
            ),
          ],
        ),
      );
      await drain(tester);
      return find.text('근처 매장에서 골라주세요').evaluate().isNotEmpty;
    },
    '오늘의 이벤트 시트': openEventsSheet,
  };

  /// 지금 **화면에 실제로 보이는** 시트 수. 라우트를 세는 [SheetStackGuard]와
  /// 따로 재는 이유는, 라우트가 하나여도 위젯이 남아 있으면 사용자에게는 두 장
  /// 겹친 것으로 보이기 때문이다.
  List<String> visibleSheetNames() => {
    '건물 정보': find.byType(BuildingInfoSheet),
    '앱 메뉴': find.byType(AppMenuSheet),
    '카테고리 목록': find.byType(CategoryStoresSheet),
    '오늘의 이벤트': find.byType(EventsSheet),
    '매장 상세': find.byType(PlaceDetailSheet),
    '근처 매장': find.text('근처 매장에서 골라주세요'),
  }.entries.where((e) => e.value.evaluate().isNotEmpty).map((e) => e.key).toList();

  Future<void> sweep(
    WidgetTester tester,
    Map<String, Future<bool> Function(WidgetTester)> entries, {
    required bool indoor,
  }) async {
    final everOpened = <String>{};

    for (final first in entries.entries) {
      for (final second in entries.entries) {
        await pumpShell(tester, indoor: indoor);
        final pair = '${first.key} → ${second.key}';

        if (await first.value(tester)) everOpened.add(first.key);
        expect(
          sheetStackGuard.openCount,
          lessThanOrEqualTo(1),
          reason: '$pair: 첫 시트를 여는 것만으로 두 장이 됐다',
        );

        if (await second.value(tester)) everOpened.add(second.key);
        expect(sheetStackGuard.openCount, lessThanOrEqualTo(1), reason: pair);
        expect(
          visibleSheetNames(),
          hasLength(lessThanOrEqualTo(1)),
          reason: '$pair: 두 장이 화면에 함께 남았다',
        );
      }
    }

    // 손가락이 빗나가면 조합이 통째로 헛돈다. 한 번도 시트를 열지 못한 입구가
    // 있으면 그 줄들은 아무것도 재지 않은 것이므로 여기서 무너뜨린다.
    expect(
      entries.keys.toSet().difference(everOpened),
      isEmpty,
      reason: '이 입구는 한 번도 시트를 열지 못했다 — 그 조합은 헛돌았다',
    );
  }

  testWidgets('야외 — 어떤 순서로 열어도 시트는 한 장뿐이다', (tester) async {
    await sweep(tester, outdoorEntries, indoor: false);
  });

  testWidgets('실내 — 어떤 순서로 열어도 시트는 한 장뿐이다', (tester) async {
    await sweep(tester, indoorEntries, indoor: true);
  });

  testWidgets('건물을 두 번 누르면 정보 시트가 두 겹으로 쌓이지 않는다', (tester) async {
    await pumpShell(tester, indoor: false);

    await tapMap(tester);
    expect(find.byType(BuildingInfoSheet), findsOneWidget);

    await tapMap(tester);
    expect(find.byType(BuildingInfoSheet), findsOneWidget);
  });

  testWidgets('건물 정보 시트가 떠 있을 때 메뉴를 열면 시트가 두 겹이 되지 않는다', (tester) async {
    await pumpShell(tester, indoor: false);

    await tapMap(tester);
    expect(find.byType(BuildingInfoSheet), findsOneWidget);

    expect(await openMenu(tester), isTrue);
    expect(
      find.byType(BuildingInfoSheet),
      findsNothing,
      reason: '메뉴가 건물 시트 위에 얹히면 뒤로가기를 몇 번 눌러야 하는지 알 수 없다',
    );
  });
}
