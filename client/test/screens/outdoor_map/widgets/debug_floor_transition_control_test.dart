import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/screens/outdoor_map/widgets/debug_floor_transition_control.dart';
import 'package:navigation_client/theme/app_theme.dart';

/// [RoutexMapControl]은 그림을 **하나만** 받는다(icon·glyphBuilder·text 중 정확히
/// 하나). 호출부가 화살표와 층 라벨을 함께 넘겨 그 assert가 터졌고, 실기기에서
/// 화면 절반이 빨간 오류 상자로 덮여 탭이 통째로 막혔다.
///
/// **분석기도 나머지 테스트도 못 잡았다.** assert는 런타임이고, 이 버튼은 디버그
/// 모드 + 실내 + 그 층에 탑승 노드가 있을 때만 뜬다. 그래서 두 상태를 여기서 직접
/// 빌드해 본다 — 재는 것은 글자가 아니라 **터지지 않는다**는 것이다.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool up,
    required String? label,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: DebugFloorTransitionControl(
            up: up,
            targetFloorLabel: label,
            onPressed: label == null ? null : () {},
          ),
        ),
      ),
    );
  }

  testWidgets('탑승 노드를 알면 층 라벨만 그린다', (tester) async {
    await pump(tester, up: true, label: '2F');

    expect(tester.takeException(), isNull);
    expect(find.text('2F'), findsOneWidget);
    // 화살표까지 함께 넘기면 그 순간 assert가 터진다.
    expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
  });

  testWidgets('탑승 노드가 없으면 방향 화살표만 그린다', (tester) async {
    await pump(tester, up: false, label: null);

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
  });

  testWidgets('방향은 라벨이 있어도 낭독기와 툴팁에 남는다', (tester) async {
    // 화살표를 뺀 대가를 여기서 갚는다. 이 문구까지 사라지면 두 버튼이 "2F"와
    // "B1"로만 보여, 어느 쪽이 위인지 화면 순서에만 의존하게 된다.
    await pump(tester, up: true, label: '2F');

    expect(
      find.byTooltip('위층으로 층 전환'),
      findsOneWidget,
      reason: '방향을 말하는 것이 화면에 하나도 없으면 안 된다',
    );
  });

  testWidgets('탑승 노드가 없으면 회색이다', (tester) async {
    await pump(tester, up: true, label: null);

    expect(tester.takeException(), isNull);
    // 눌러도 할 일이 없는 버튼이다. 켜 두면 눌렀는데 아무 일도 안 일어난다.
    final gesture = tester.widget<GestureDetector>(
      find.byType(GestureDetector).first,
    );
    expect(gesture.onTap, isNull);
  });
}
