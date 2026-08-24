import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/core/api_config.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/events_sheet.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/place_detail_sheet.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/sheet_drag_dismiss.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:routex_design_system/routex_design_system.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 이 검사가 지키는 것 — **본문 아무 데나 잡고 내려도 시트가 닫히는가.**
///
/// 예전에는 끌어내릴 바닥이 처음 높이와 같거나(상세) 문턱보다 높아서(이벤트)
/// 시트가 내려갈 자리가 없었다. 본문을 끌면 아무 일도 안 일어나고, 닫히는 곳은
/// 손잡이 언저리뿐인 것처럼 느껴졌다. 화면만 봐서는 "원래 이런가" 싶은 실패라
/// 여기서 못 박는다. 두 시트가 **같은 감각**이어야 한다는 것도 함께 지킨다
/// ([SheetDragDismiss]).
void main() {
  late BuildingRepository original;

  setUp(() {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    original = buildingRepository;
    buildingRepository = MockBuildingRepository();
  });

  tearDown(() => buildingRepository = original);

  Future<void> openSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => PlaceDetailSheet.show(
                context,
                // 상세를 부르지 않는 경로로 연다 — 여기서 보는 것은 제스처다.
                target: ValueNotifier(
                  const PlaceDetailTarget(
                    title: 'MLB',
                    subtitle: 'B2',
                    placeId: null,
                  ),
                ),
                buildingId: demoBuildingId,
                onCloseAll: () {},
              ),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(find.text('MLB'), findsOneWidget);
  }

  testWidgets('본문을 잡고 내리면 닫힌다 — 손잡이만이 아니다', (tester) async {
    await openSheet(tester);

    // 손잡이가 아니라 이름이 적힌 본문을 잡는다.
    await tester.drag(find.text('MLB'), const Offset(0, 400));
    await tester.pumpAndSettle();

    expect(find.text('MLB'), findsNothing);
  });

  testWidgets('손잡이로도 그대로 닫힌다', (tester) async {
    await openSheet(tester);

    await tester.drag(find.byType(RoutexSheetHandle), const Offset(0, 400));
    await tester.pumpAndSettle();

    expect(find.text('MLB'), findsNothing);
  });

  testWidgets('오늘의 이벤트 시트도 같은 감각으로 닫힌다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => EventsSheet.show(context, onCloseAll: () {}),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(find.text('오늘의 이벤트'), findsOneWidget);

    // 머리글이 아니라 본문 자리를 잡고 내린다.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
    await tester.pumpAndSettle();

    expect(find.text('오늘의 이벤트'), findsNothing);
  });

  testWidgets('조금 내렸다 놓으면 닫지 않고 제자리로 돌아온다', (tester) async {
    await openSheet(tester);
    final before = tester.getTopLeft(find.byType(RoutexBottomSheet)).dy;

    // 문턱(처음 높이의 18%)에 못 미치는 거리다. 스크롤하려던 손이 시트를
    // 닫아 버리면 본문을 읽을 수가 없다.
    await tester.drag(find.text('MLB'), const Offset(0, 12));
    await tester.pumpAndSettle();

    expect(find.text('MLB'), findsOneWidget);
    expect(tester.getTopLeft(find.byType(RoutexBottomSheet)).dy, before);
  });
}
