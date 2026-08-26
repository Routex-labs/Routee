import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/event/building_events.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/event_poster_view.dart';
import 'package:navigation_client/theme/app_theme.dart';

void main() {
  const events = [
    BuildingEvent(
      title: '첫 번째 행사',
      start: '2026-08-20',
      end: '2026-08-26',
      place: '1F',
      details: [EventBlock(kind: 'p', text: '첫 번째 행사 본문')],
    ),
    BuildingEvent(
      title: '두 번째 행사',
      start: '2026-08-20',
      end: '2026-08-26',
      place: '2F',
      details: [EventBlock(kind: 'p', text: '두 번째 행사 본문')],
    ),
  ];

  Future<void> pumpPoster(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: const EventPosterView(
        events: events,
        initialIndex: 0,
        navigable: [false, false],
      ),
    ),
  );

  testWidgets('밝은 화면에서 현재 행사 본문만 보인다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpPoster(tester);
    await tester.pumpAndSettle();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppColors.background);
    expect(find.text('첫 번째 행사'), findsOneWidget);
    expect(find.text('두 번째 행사'), findsNothing);

    await tester.drag(find.byType(PageView), const Offset(-320, 0));
    await tester.pumpAndSettle();

    expect(find.text('첫 번째 행사'), findsNothing);
    expect(find.text('두 번째 행사'), findsOneWidget);
  });
}
