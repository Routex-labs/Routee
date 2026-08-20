import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/widgets/eta_card.dart';

/// "안내 시작"은 이동수단과 무관하게 **계획 상태**로 그려 둔 동안만 뜬다.
///
/// 경로를 그리자마자 카메라를 현재 위치로 확대하면 사용자는 전체 경로를 한 번도
/// 못 보고 안내에 들어간다. 그래서 계획(경로 전체)과 안내(내 위치)를 버튼 하나로
/// 나눴고, 이 테스트가 그 버튼의 유무 규칙을 지킨다.
void main() {
  Widget host({
    bool guidanceStarted = false,
    VoidCallback? onStartGuidance,
    VoidCallback? onClose,
  }) {
    return MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: EtaCard(
          distanceMeters: 5200,
          minutes: 14,
          label: '강남역까지',
          guidanceStarted: guidanceStarted,
          onClose: onClose,
          onStartGuidance: onStartGuidance,
        ),
      ),
    );
  }

  testWidgets('계획 상태에서는 안내 시작만 뜬다', (tester) async {
    var started = false;
    await tester.pumpWidget(
      host(onStartGuidance: () => started = true, onClose: () {}),
    );
    await tester.pump();

    expect(find.text('안내 시작'), findsOneWidget);
    // 아직 출발도 안 했는데 "종료"가 함께 있으면, 무엇이 이미 시작됐는지부터
    // 헷갈린다. 계획을 접는 길은 상단 길찾기 바에 있다.
    expect(find.text('안내 종료'), findsNothing);

    await tester.tap(find.text('안내 시작'));
    await tester.pump();
    expect(started, isTrue);
  });

  testWidgets('시작 동작이 없는 자동 경로에는 버튼이 없다', (tester) async {
    await tester.pumpWidget(host(onClose: () {}));
    await tester.pump();

    expect(find.text('안내 시작'), findsNothing);
    expect(find.text('안내 종료'), findsNothing);
  });

  testWidgets('안내를 시작하면 종료만 남는다', (tester) async {
    await tester.pumpWidget(host(guidanceStarted: true, onClose: () {}));
    await tester.pump();

    expect(find.text('안내 시작'), findsNothing);
    expect(find.text('안내 종료'), findsOneWidget);
  });
}
