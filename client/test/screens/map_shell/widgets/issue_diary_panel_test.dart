import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/event/building_events.dart';
import 'package:navigation_client/screens/map_shell/widgets/chrome/issue_diary_panel.dart';
import 'package:routex_design_system/routex_design_system.dart';

/// 이 검사가 지키는 것 둘.
///
/// 하나 — **손잡이가 실제로 끈다.** 이 저장소는 손잡이를 "끌 수 있다"는 약속으로
/// 보고 끌 수 없는 시트에는 달지 않는다(`test/widgets/sheet_handle_test.dart`).
/// 판에 손잡이만 그려 놓고 접힌 채로 두면 그 약속이 거짓이 된다.
///
/// 둘 — **카드가 쪽 하나를 가리킨다.** 자막은 평소 숨어 있다가 손이 닿을 때만
/// 올라온다. 늘 켜 두면 대표 사진에 이미 그려진 이름과 두 벌로 겹친다.
void main() {
  const popup = EventDiaryPage(
    diary: EventDiary.popup,
    title: 'WEEKLY POP-UP',
    image: 'assets/events/diary_popup.png',
  );
  const tasty = EventDiaryPage(
    diary: EventDiary.tasty,
    title: 'TASTY SEOUL',
    image: 'assets/events/diary_tasty.png',
  );
  const pages = [(page: popup, count: 1), (page: tasty, count: 1)];
  const events = [
    BuildingEvent(
      title: '이번 주 팝업',
      start: '2026-08-20',
      end: '2026-08-26',
      place: '지하2층 POP-UP@ICONIC',
      diary: EventDiary.popup,
      floorName: 'B2',
      storeId: 'PO-i',
    ),
    BuildingEvent(
      title: '식품 행사장',
      start: '2026-08-21',
      end: '2026-08-27',
      place: '지하1층 식품행사장',
      diary: EventDiary.tasty,
      floorName: 'B1',
      storeId: 'PO-f',
    ),
  ];

  Widget host({
    List<({EventDiaryPage page, int count})> list = pages,
    ValueChanged<EventDiaryPage>? onPickPage,
    ValueChanged<int>? onPickEvent,
    VoidCallback? onDismissed,
  }) => MaterialApp(
    // 판이 디자인 시스템 표면을 쓰므로 그 토큰이 Theme에 있어야 한다.
    theme: RoutexTheme.light,
    home: Scaffold(
      body: Column(
        children: [
          const Spacer(),
          IssueDiaryPanel(
            pages: list,
            events: events,
            onPickPage: onPickPage ?? (_) {},
            onPickEvent: onPickEvent ?? (_) {},
            onDismissed: onDismissed ?? () {},
            onPointerOverChanged: (_) {},
            onPointerDownChanged: (_) {},
          ),
        ],
      ),
    ),
  );

  double panelHeight(WidgetTester tester) =>
      tester.getSize(find.byType(IssueDiaryPanel)).height;

  testWidgets('접힌 판에는 이름과 쪽 카드만 있다', (tester) async {
    await tester.pumpWidget(host());

    expect(find.text('Issue Diary'), findsOneWidget);
    expect(find.byKey(const Key('issue-diary-popup')), findsOneWidget);
    expect(find.byKey(const Key('issue-diary-tasty')), findsOneWidget);
    expect(panelHeight(tester), IssueDiaryPanel.peekHeight);
    // 접힌 채로는 목록이 없다 — 카드만 보이는 것이 접힘의 뜻이다.
    expect(find.byKey(const Key('issue-diary-row-이번 주 팝업')), findsNothing);
  });

  testWidgets('손잡이를 끌어올리면 오늘 전체가 갈래별로 펼쳐진다', (tester) async {
    await tester.pumpWidget(host());

    await tester.drag(
      find.byKey(RoutexBottomSheet.handleKey),
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();

    expect(panelHeight(tester), greaterThan(IssueDiaryPanel.peekHeight));
    expect(find.text('팝업'), findsOneWidget);
    expect(find.text('다이닝'), findsOneWidget);
    expect(find.byKey(const Key('issue-diary-row-이번 주 팝업')), findsOneWidget);
    expect(find.byKey(const Key('issue-diary-row-식품 행사장')), findsOneWidget);
  });

  testWidgets('끌어내리면 다시 접힌다', (tester) async {
    await tester.pumpWidget(host());
    final handle = find.byKey(RoutexBottomSheet.handleKey);

    await tester.drag(handle, const Offset(0, -260));
    await tester.pumpAndSettle();
    await tester.drag(handle, const Offset(0, 260));
    await tester.pumpAndSettle();

    expect(panelHeight(tester), IssueDiaryPanel.peekHeight);
  });

  testWidgets('접힘 아래로 더 끌어내리면 끝까지 미끄러진 뒤 치운다', (tester) async {
    var dismissed = 0;
    await tester.pumpWidget(host(onDismissed: () => dismissed++));

    // 손을 떼기 전에는 사라지지 않는다 — 중간에 툭 없어지면 사용자는 자기가
    // 무엇을 눌러 없앤 줄 안다. 판은 손가락을 끝까지 따라간다.
    final drag = await tester.startGesture(
      tester.getCenter(find.byKey(RoutexBottomSheet.handleKey)),
    );
    await drag.moveBy(const Offset(0, 180));
    await tester.pump();
    expect(dismissed, 0);
    expect(panelHeight(tester), lessThan(IssueDiaryPanel.peekHeight));

    await drag.up();
    await tester.pumpAndSettle();
    expect(dismissed, 1);
  });

  testWidgets('펼친 목록 맨 위에서 더 내리면 판이 따라 내려온다', (tester) async {
    var dismissed = 0;
    await tester.pumpWidget(host(onDismissed: () => dismissed++));
    await tester.drag(
      find.byKey(RoutexBottomSheet.handleKey),
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();
    expect(panelHeight(tester), greaterThan(IssueDiaryPanel.peekHeight));

    // 목록을 잡고 내린다. 맨 위라 스크롤이 소화하지 못하고 판으로 넘어간다.
    await tester.drag(
      find.byKey(const Key('issue-diary-row-이번 주 팝업')),
      const Offset(0, 600),
    );
    await tester.pumpAndSettle();

    expect(dismissed, 1);
  });

  testWidgets('조금 내렸다 놓으면 치우지 않고 접힘으로 돌아온다', (tester) async {
    var dismissed = 0;
    await tester.pumpWidget(host(onDismissed: () => dismissed++));

    await tester.drag(
      find.byKey(RoutexBottomSheet.handleKey),
      const Offset(0, 40),
    );
    await tester.pumpAndSettle();

    expect(dismissed, 0);
    expect(panelHeight(tester), IssueDiaryPanel.peekHeight);
  });

  testWidgets('목록 줄을 누르면 그 줄의 자리를 넘긴다', (tester) async {
    final picked = <int>[];
    await tester.pumpWidget(host(onPickEvent: picked.add));

    await tester.drag(
      find.byKey(RoutexBottomSheet.handleKey),
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('issue-diary-row-식품 행사장')));

    expect(picked, [1]);
  });

  testWidgets('이름은 원본과 같은 폰트로 붙는다', (tester) async {
    await tester.pumpWidget(host());

    final title = tester.widget<Text>(find.text('Issue Diary'));
    // pubspec의 family 이름과 어긋나면 조용히 기본 글꼴로 떨어진다 — 화면만
    // 봐서는 "원래 저 모양인가" 싶어 지나친다.
    expect(title.style?.fontFamily, 'PlayfairDisplay');
    // 가변 폰트라 굵기는 축으로 고른다. 축을 빼먹으면 400으로 그려진다.
    expect(title.style?.fontVariations, const [FontVariation('wght', 700)]);
  });

  testWidgets('자막은 평소 숨어 있다가 손이 닿으면 올라온다', (tester) async {
    await tester.pumpWidget(host());

    // AnimatedOpacity가 안에서 만드는 것이 [FadeTransition]이다.
    double captionOpacity(String key) => tester
        .widget<FadeTransition>(
          find
              .descendant(
                of: find.byKey(Key('issue-diary-$key')),
                matching: find.byType(FadeTransition),
              )
              .first,
        )
        .opacity
        .value;

    expect(captionOpacity('popup'), 0);

    // 손가락을 대고 있는 동안(누름)은 hover와 같은 상태다.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('issue-diary-popup'))),
    );
    await tester.pumpAndSettle();
    expect(captionOpacity('popup'), 1);
    expect(find.text('WEEKLY POP-UP'), findsOneWidget);
    // 갈래와 건수가 함께 온다 — 눌러서 무엇이 몇 개 나오는지가 요점이다.
    expect(find.text('팝업 · 1건'), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(captionOpacity('popup'), 0);
  });

  testWidgets('카드를 누르면 그 쪽을 넘긴다', (tester) async {
    final picked = <EventDiaryPage>[];
    await tester.pumpWidget(host(onPickPage: picked.add));

    await tester.tap(find.byKey(const Key('issue-diary-tasty')));
    expect(picked.single.diary, EventDiary.tasty);
  });

  testWidgets('오늘 열리는 쪽이 없으면 판을 통째로 뺀다', (tester) async {
    await tester.pumpWidget(host(list: const []));

    // 이름만 남은 판은 빈 칸을 가리키는 손잡이가 된다.
    expect(find.text('Issue Diary'), findsNothing);
    expect(find.byKey(RoutexBottomSheet.handleKey), findsNothing);
    expect(panelHeight(tester), 0);
  });
}
