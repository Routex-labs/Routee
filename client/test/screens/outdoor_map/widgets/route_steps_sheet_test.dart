import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/guidance/route_guidance.dart';
import 'package:navigation_client/screens/outdoor_map/widgets/route_steps_sheet.dart';

import '../../../support/routex_test_host.dart';

/// 경로 단계 목록 시트의 계약은 **"화면 절반까지만 차지하고 안에서 스크롤한다"** 이다
/// (`showRouteStepsSheet`의 주석). 시트가 지도를 다 덮으면 사용자가 "어디를 말하는지"를
/// 대조할 수 없다.
///
/// 실내 경로는 층을 넘나들면 단계가 쉽게 스무 개를 넘는다. 그때 목록이 뷰포트를 얻지
/// 못하면 스크롤이 아니라 **넘침**이 되어 마지막 단계들이 잘린다.
void main() {
  List<RouteStep> steps(int count) => [
    for (var i = 0; i < count - 1; i++)
      RouteStep(
        action: i.isEven
            ? RouteGuidanceAction.straight
            : RouteGuidanceAction.turnLeft,
        distanceM: 10 + i * 3,
      ),
    const RouteStep(action: RouteGuidanceAction.arrived),
  ];

  Future<void> openSheet(WidgetTester tester, int stepCount) async {
    await tester.pumpWidget(
      appThemedHost(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showRouteStepsSheet(
              context,
              steps: steps(stepCount),
              destinationName: '스타벅스 리저브',
            ),
            child: const Text('열기'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  testWidgets('단계가 많아도 넘치지 않는다', (tester) async {
    // 층을 넘나드는 실내 경로의 현실적인 길이. 한 줄 48dp면 화면 절반을 훌쩍 넘는다.
    await openSheet(tester, 24);

    // 넘치면 RenderFlex overflow가 예외로 올라온다. 여기서 잡히면 목록이 뷰포트를
    // 얻지 못했다는 뜻이고, 사용자는 마지막 단계들을 볼 방법이 없다.
    expect(tester.takeException(), isNull);
  });

  testWidgets('넘치는 목록은 시트 안에서 스크롤된다', (tester) async {
    await openSheet(tester, 24);

    final scrollable = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(Scrollable),
    );
    expect(scrollable, findsWidgets);

    // 실제로 굴러야 한다. 스크롤 위젯이 있어도 뷰포트가 콘텐츠와 같은 크기면
    // extent가 0이라 한 줄도 못 내려간다.
    final position = tester.widget<Scrollable>(scrollable.first).controller;
    await tester.drag(scrollable.first, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(position?.offset ?? _offsetOf(tester, scrollable.first), isNonZero);
  });

  testWidgets('짧은 목록은 시트를 화면 절반까지 늘리지 않는다', (tester) async {
    await openSheet(tester, 3);

    final sheetHeight = tester.getSize(find.byType(BottomSheet)).height;
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;

    // 세 단계짜리 경로에 화면 절반을 내주면 지도가 그만큼 가려진다.
    expect(sheetHeight, lessThan(screenHeight * 0.5));
  });
}

double _offsetOf(WidgetTester tester, Finder scrollable) =>
    Scrollable.of(tester.element(scrollable)).position.pixels;
