import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/guidance/route_guidance.dart';
import 'package:navigation_client/widgets/route_steps_view.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../support/routex_test_host.dart';

/// 계획 카드의 단계 목록 계약은 **"기본은 접힘, 눌러야 펴진다"** 이다.
///
/// 펼친 채로 시작하면 카드가 화면 절반을 먹고, 그 높이를 재서 여백을 잡는
/// 카메라가 방금 그린 경로를 화면 밖으로 밀어낸다 — 대중교통 요약 카드가
/// 세부를 접어 두는 것과 같은 이유다([CollapsibleRouteSteps]).
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

  Future<void> pump(WidgetTester tester, List<RouteStep> given) async {
    await tester.pumpWidget(
      appThemedHost(
        CollapsibleRouteSteps(steps: given, destinationName: '스타벅스 리저브'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('처음에는 접혀 있고 목록 대신 개수만 말한다', (WidgetTester tester) async {
    await pump(tester, steps(8));

    expect(find.byType(RouteStepsView), findsNothing);
    // 접힌 상태에서도 규모는 알려 준다 — 펼칠지 말지를 그 숫자로 정한다.
    expect(find.textContaining('8'), findsOneWidget);
  });

  testWidgets('펼치면 그 자리에서 단계가 나오고 다시 접힌다', (WidgetTester tester) async {
    await pump(tester, steps(8));

    await tester.tap(find.byType(RoutexShowMore));
    await tester.pumpAndSettle();
    expect(find.byType(RouteStepsView), findsOneWidget);
    // 도착 행은 목적지 이름까지 적는다([RouteStepsView]).
    expect(find.text('스타벅스 리저브 도착'), findsOneWidget);

    await tester.tap(find.byType(RoutexShowMore));
    await tester.pumpAndSettle();
    expect(find.byType(RouteStepsView), findsNothing);
  });

  testWidgets('펼쳐도 화면을 다 덮지 않는다', (WidgetTester tester) async {
    // 층을 넘나드는 실내 경로는 단계가 쉽게 스무 개를 넘는다. 상한이 없으면
    // 카드가 지도를 통째로 가린다.
    await pump(tester, steps(40));
    await tester.tap(find.byType(RoutexShowMore));
    await tester.pumpAndSettle();

    final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(
      tester.getSize(find.byType(CollapsibleRouteSteps)).height,
      lessThan(screenHeight * 0.5),
    );
  });

  testWidgets('단계가 없으면 접이 줄 자체를 그리지 않는다', (WidgetTester tester) async {
    // 빈 줄을 남기면 그만큼 지도가 가려진다.
    await pump(tester, const []);

    expect(find.byType(RoutexShowMore), findsNothing);
  });
}
