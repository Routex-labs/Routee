import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// GPS로 건물 안에 들어가는 테스트가 **거의 다** 부르게 되는 정리 한 줄.
///
/// 자동 진입은 "몇 층에 계신가요?"를 먼저 띄운다
/// (`lib/screens/outdoor_map/widgets/entry_floor_prompt.dart`). 그 화면은 지도를
/// 덮으므로, 진입 이후의 지도 조작을 시험하려면 먼저 걷어야 한다 — 안 걷으면
/// 탭이 전부 이 화면에 먹혀 "왜 버튼이 안 눌리지"로만 보인다.
///
/// 떠 있지 않으면 아무 일도 하지 않는다. 진입 경로가 여럿이라(건물 탭·줌·GPS)
/// 호출부가 매번 조건을 따지지 않아도 되게 한다.
Future<void> dismissEntryFloorPrompt(WidgetTester tester) async {
  final skip = find.byKey(const Key('entry-floor-skip'));
  if (skip.evaluate().isEmpty) return;
  await tester.tap(skip);
  await tester.pumpAndSettle();
}

/// 층을 골라 답한다. 없으면 아무 일도 하지 않는다.
Future<void> answerEntryFloorPrompt(WidgetTester tester, String floor) async {
  final option = find.byKey(ValueKey('entry-floor-$floor'));
  if (option.evaluate().isEmpty) return;
  await tester.tap(option);
  await tester.pumpAndSettle();
}
