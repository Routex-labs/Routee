import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/models/route/route_plan_mode.dart';

import 'package:navigation_client/screens/map_shell/widgets/chrome/map_top_bar.dart';

/// 상단 바의 **두 얼굴**을 고정하는 테스트.
///
/// 평소에는 검색창 한 줄이고, 길찾기 중에는 Runtime Kit 플래너다. 플래너의 한
/// 위치를 고칠 때만 그 아래에 실제 입력 줄이 열리고, 확정 뒤에는 다시 플래너의
/// 출발·도착 요약으로 돌아간다.
void main() {
  ({
    TextEditingController search,
    TextEditingController origin,
    TextEditingController destination,
    FocusNode focus,
  })
  makeControllers(WidgetTester tester) {
    final search = TextEditingController();
    final origin = TextEditingController();
    final destination = TextEditingController();
    final focus = FocusNode();
    addTearDown(search.dispose);
    addTearDown(origin.dispose);
    addTearDown(destination.dispose);
    addTearDown(focus.dispose);
    return (
      search: search,
      origin: origin,
      destination: destination,
      focus: focus,
    );
  }

  testWidgets('길찾기 중에는 기존 플래너와 활성 입력 한 줄을 쓴다', (tester) async {
    final c = makeControllers(tester);
    c.destination.text = '다이슨';
    final events = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MapTopBar(
            onMenuTap: () {},
            controller: c.search,
            focusNode: c.focus,
            onChanged: (_) {},
            onSubmitted: (_) {},
            searchActive: false,
            onCancelSearch: () {},
            onDirectionsTap: () => events.add('directions'),
            routeMode: true,
            routeEditingField: RoutePlanField.destination,
            originController: c.origin,
            destinationController: c.destination,
            onOriginChanged: (value) => events.add('origin:$value'),
            onDestinationChanged: (value) => events.add('destination:$value'),
            onClearRouteDraft: () => events.add('clear'),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('route-planner')), findsOneWidget);
    // 플래너를 복제하지 않고, 지금 고치는 위치만 실제 입력 줄로 연다.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('다이슨'), findsOneWidget);
    // 출발지가 비어 있으면 "현재 위치"가 안내문으로만 뜬다 — 글자로 채우면
    // 사용자가 다른 곳을 치기 전에 먼저 지워야 한다.
    expect(find.text('현재 위치'), findsOneWidget);
    expect(c.origin.text, isEmpty);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('route-draft-destination')),
        matching: find.byType(TextField),
      ),
      '이솝',
    );
    await tester.tap(find.byTooltip('경로 계획 닫기'));

    expect(events, ['destination:이솝', 'clear']);
  });

  testWidgets('길찾기 중이 아니면 검색창 한 줄이다', (tester) async {
    final c = makeControllers(tester);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MapTopBar(
            onMenuTap: () {},
            controller: c.search,
            focusNode: c.focus,
            onChanged: (_) {},
            onSubmitted: (_) {},
            searchActive: true,
            onCancelSearch: () {},
            onDirectionsTap: () {},
            originController: c.origin,
            destinationController: c.destination,
          ),
        ),
      ),
    );

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byKey(const Key('route-draft-origin')), findsNothing);
  });

  // 이 자리가 앱 안 모든 검색창 지우기 X의 기준 패턴이다. 여기서 규칙이
  // 흔들리면 길찾기 시트·카테고리 매장 목록도 따라 어긋나므로 함께 고정한다.
  testWidgets('검색창 X는 글자가 있을 때만 나타나고 결과 상태까지 되돌린다', (tester) async {
    final changes = <String>[];
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MapTopBar(
            onMenuTap: () {},
            controller: controller,
            focusNode: focusNode,
            onChanged: changes.add,
            onSubmitted: (_) {},
            searchActive: true,
            onCancelSearch: () {},
            onDirectionsTap: () {},
          ),
        ),
      ),
    );

    // 글자가 없을 때 그 자리는 길찾기 버튼이 쓴다 — X가 빈자리를 차지하지 않는다.
    expect(find.byTooltip('검색어 지우기'), findsNothing);
    expect(find.byTooltip('길찾기'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '다이슨');
    await tester.pump();
    expect(find.byTooltip('검색어 지우기'), findsOneWidget);
    expect(find.byTooltip('길찾기'), findsOneWidget);

    await tester.tap(find.byTooltip('검색어 지우기'));
    await tester.pump();

    expect(controller.text, '');
    // 글자만 지우면 상위의 검색 결과가 그대로 남는다. 빈 문자열을 흘려 그
    // 입력이 걸어 둔 결과까지 되돌리는 것이 이 X의 계약이다.
    expect(changes.last, '');
    expect(find.byTooltip('검색어 지우기'), findsNothing);
  });
}
