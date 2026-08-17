import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/screens/outdoor_map/transition/indoor_transition_preview.dart';

/// 하네스가 **뜨는지**만 본다. 연출이 예쁜지는 눈으로 볼 일이고, 여기서 막고
/// 싶은 것은 "곡선을 고치러 열었더니 화면이 터져 있는" 경우다.
///
/// 두 폭에서 모두 띄운다 — 좁은 화면은 세로, 넓은 화면은 가로로 배치가 갈린다.
Future<void> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    const MaterialApp(home: IndoorTransitionPreview()),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('좁은 화면에서 두 무대가 모두 뜬다', (tester) async {
    await _pumpAt(tester, const Size(390, 1400));
    expect(find.text('야외 → 실내 진입'), findsOneWidget);
    expect(find.text('실내 → 야외 이탈'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('넓은 화면에서도 두 무대가 모두 뜬다', (tester) async {
    await _pumpAt(tester, const Size(1200, 1000));
    expect(find.text('야외 → 실내 진입'), findsOneWidget);
    expect(find.text('실내 → 야외 이탈'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('재생해도 중간 프레임에서 터지지 않는다', (tester) async {
    await _pumpAt(tester, const Size(390, 1400));
    await tester.tap(find.text('둘 다 재생'));
    // 연출 전체를 잘게 밟는다. 그리기 코드가 특정 진행률에서만 터지는 일이
    // 있어서(투명도 0 분기, 퇴화한 경로) 끝 상태만 봐서는 못 잡는다.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
  });
}
