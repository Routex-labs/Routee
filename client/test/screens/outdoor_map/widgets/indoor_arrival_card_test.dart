import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/screens/outdoor_map/widgets/indoor_arrival_card.dart';

Widget _host(Widget child, {double textScale = 1.0}) => MediaQuery(
  data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
  child: MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  testWidgets('목적지 이름이 제목이고 층은 그 아래에 붙는다', (tester) async {
    // 어디에 도착했는지가 먼저다. "도착했습니다"를 크게 쓰면 정작 매장 이름이
    // 두 번째 줄로 밀린다.
    await tester.pumpWidget(
      _host(
        IndoorArrivalCard(
          destinationName: '스타벅스 리저브',
          destinationFloor: 'B2',
          onConfirm: () {},
        ),
      ),
    );

    expect(find.text('도착했습니다'), findsOneWidget);
    expect(find.text('스타벅스 리저브 · B2'), findsOneWidget);
  });

  testWidgets('층을 모르면 층 없이 도착만 말한다', (tester) async {
    await tester.pumpWidget(
      _host(IndoorArrivalCard(destinationName: '레페토', onConfirm: () {})),
    );

    expect(find.text('레페토'), findsOneWidget);
    expect(find.text('도착했습니다'), findsOneWidget);
  });

  // 도착은 다음 조작이 없는 유일한 상태다. 남은 거리도 0이라, 걷는 중 배너와
  // 같은 모양으로 그리면 `0 m`만 붙은 이상한 줄이 된다. 예전에는 하단 배너가
  // 도착도 함께 말했고, 그 규칙을 이 카드가 물려받는다.
  testWidgets('남은 거리를 적지 않는다', (tester) async {
    await tester.pumpWidget(
      _host(
        IndoorArrivalCard(
          destinationName: '스타벅스 리저브',
          destinationFloor: 'B2',
          onConfirm: () {},
        ),
      ),
    );

    expect(find.textContaining(' m'), findsNothing);
    expect(find.textContaining('0m'), findsNothing);
  });

  testWidgets('안내 종료를 누르면 상위에 알린다', (tester) async {
    var confirmed = false;
    await tester.pumpWidget(
      _host(
        IndoorArrivalCard(
          destinationName: '레페토',
          onConfirm: () => confirmed = true,
        ),
      ),
    );

    await tester.tap(find.text('안내 종료'));

    expect(confirmed, isTrue);
  });

  testWidgets('큰 글자 배율에서도 넘치지 않는다', (tester) async {
    await tester.pumpWidget(
      _host(
        const SizedBox(
          width: 280,
          child: IndoorArrivalCard(
            destinationName: '포인트 오브 뷰 성수 플래그십 스토어',
            destinationFloor: 'B2',
            onConfirm: _noop,
          ),
        ),
        textScale: 2,
      ),
    );

    expect(tester.takeException(), isNull);
  });
}

void _noop() {}
