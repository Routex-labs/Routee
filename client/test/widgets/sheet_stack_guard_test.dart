import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/widgets/sheet_stack_guard.dart';

/// 그물망 자체를 잰다.
///
/// 셸을 지나는 시트는 [_withMapsLocked]가 먼저 막아서, 화면 테스트로는 이
/// 관찰자가 **한 번도 돌지 않는다**. 그런데 이것이 받아내야 하는 것은 바로 그
/// 셸을 지나지 않는 입구들(GPS 진입이 띄우는 근처 매장 시트, 겹친 매장 시트,
/// 안내 중 경로 단계 시트)이다 — 그쪽을 화면 테스트로 몰기 어려우므로 여기서
/// 관찰자만 떼어 직접 흔든다.
void main() {
  late SheetStackGuard guard;

  setUp(() {
    guard = SheetStackGuard();
  });

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [guard],
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
  }

  Future<void> openSheet(WidgetTester tester, String label) async {
    final context = tester.element(find.byType(Scaffold));
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        builder: (_) => Text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('시트 위에 시트를 열면 아래 것을 걷어낸다', (tester) async {
    await pumpHost(tester);

    await openSheet(tester, '첫째');
    expect(guard.openCount, 1);
    expect(guard.caughtStackings, 0);

    await openSheet(tester, '둘째');

    expect(find.text('첫째'), findsNothing, reason: '아래 시트가 남아 있으면 두 겹 그대로다');
    expect(find.text('둘째'), findsOneWidget);
    expect(guard.openCount, 1);
    expect(guard.caughtStackings, 1, reason: '걷어낸 것을 세지 않으면 테스트가 헛돈 것과 구별되지 않는다');
  });

  testWidgets('시트를 닫으면 다음 시트는 겹친 것으로 세지 않는다', (tester) async {
    await pumpHost(tester);

    await openSheet(tester, '첫째');
    Navigator.of(tester.element(find.text('첫째'))).pop();
    await tester.pumpAndSettle();
    expect(guard.openCount, 0);

    await openSheet(tester, '둘째');
    expect(guard.openCount, 1);
    expect(guard.caughtStackings, 0);
  });

  // 의도적으로 겹치는 것까지 걷어내면 대중교통 상세(목록 위에 얹히는
  // `PageRoute`)와 사진 뷰어(`DialogRoute`)가 열리자마자 사라진다. 세는 대상을
  // `ModalBottomSheetRoute`로 좁힌 것이 그 예외를 표시 없이 만든다.
  /// 지도 화면 아래에는 라우트가 아닌 표면(이슈 다이어리 판)도 있다. 그것은 이
  /// 관찰자가 세는 대상이 아니라, 시트가 떠도 그대로 남아 두 장이 겹친 것처럼
  /// 보였다. 같은 신호로 물러나게 하려면 값이 밖으로 나가야 한다.
  testWidgets('열린 시트 수를 밖에서 들을 수 있다', (tester) async {
    await pumpHost(tester);
    final seen = <int>[];
    guard.openSheets.addListener(() => seen.add(guard.openSheets.value));

    await openSheet(tester, '첫 장');
    expect(guard.openSheets.value, 1);

    // 두 장째가 떠도 앞의 것이 걷히므로 값은 1에 머문다.
    await openSheet(tester, '둘째 장');
    expect(guard.openSheets.value, 1);

    Navigator.of(tester.element(find.text('둘째 장'))).pop();
    await tester.pumpAndSettle();
    expect(guard.openSheets.value, 0);

    // 0에서 1로, 1에서 0으로 — 판이 물러나고 돌아오는 두 신호가 다 왔다.
    expect(seen.first, 1);
    expect(seen.last, 0);
  });

  testWidgets('시트가 아닌 라우트는 세지도 걷어내지도 않는다', (tester) async {
    await pumpHost(tester);

    await openSheet(tester, '첫째');
    unawaited(
      showDialog<void>(
        context: tester.element(find.text('첫째')),
        builder: (_) => const Text('사진'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('첫째'), findsOneWidget);
    expect(find.text('사진'), findsOneWidget);
    expect(guard.openCount, 1);
    expect(guard.caughtStackings, 0);
  });
}
