import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/screens/outdoor_map/transition/indoor_transition_overlay.dart';
import 'package:navigation_client/screens/outdoor_map/transition/indoor_transition_timeline.dart';

/// 문이 예쁘게 열리는지는 눈으로 볼 일이고, 여기서는 **문구와 존재 여부**를 본다.
/// 그 둘이 데이터에 따라 갈리는 부분이라 화면만 보고는 다 밟아 볼 수 없다.
Future<void> _pump(
  WidgetTester tester, {
  required double progress,
  required IndoorTransitionDirection direction,
  String? buildingName,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Colors.black)),
          Positioned.fill(
            child: IndoorTransitionOverlay(
              progress: progress,
              direction: direction,
              buildingName: buildingName,
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('연출 전에는 아무것도 그리지 않는다', (tester) async {
    // 오버레이는 지도 위에 늘 트리에 있다. 진행률 0에서 뭔가 그리면 평상시
    // 화면에 흰 막이 덮여 있게 된다.
    await _pump(
      tester,
      progress: 0,
      direction: IndoorTransitionDirection.enter,
      buildingName: '더현대 서울',
    );
    expect(
      find.descendant(
        of: find.byType(IndoorTransitionOverlay),
        matching: find.byType(ColoredBox),
      ),
      findsNothing,
    );
    expect(find.textContaining('들어가는 중'), findsNothing);
  });

  testWidgets('진입 문구에 건물명과 조사가 붙는다', (tester) async {
    await _pump(
      tester,
      progress: 0.5,
      direction: IndoorTransitionDirection.enter,
      buildingName: '더현대 서울',
    );
    // 「서울」은 ㄹ 받침이라 `서울로`다 — `서울으로`가 아니다.
    expect(find.text('더현대 서울로 들어가는 중...'), findsOneWidget);
  });

  testWidgets('건물명을 모르면 이름 없이 띄운다', (tester) async {
    // 건물 로드가 실패했거나 아직 안 온 경우다. 조사만 남은 문구
    // (`로 들어가는 중...`)를 띄우면 안 된다.
    await _pump(
      tester,
      progress: 0.5,
      direction: IndoorTransitionDirection.enter,
    );
    expect(find.text('들어가는 중...'), findsOneWidget);
  });

  testWidgets('이탈 문구는 건물명을 쓰지 않는다', (tester) async {
    await _pump(
      tester,
      progress: 0.5,
      direction: IndoorTransitionDirection.exit,
      buildingName: '더현대 서울',
    );
    expect(find.text('밖으로 나가는 중...'), findsOneWidget);
    expect(find.textContaining('더현대'), findsNothing);
  });

  testWidgets('지도 조작을 막지 않는다', (tester) async {
    // 덮개가 떠 있는 1초 남짓 동안 탭이 안 먹으면 사용자는 앱이 멈춘 줄 안다.
    await _pump(
      tester,
      progress: 0.5,
      direction: IndoorTransitionDirection.enter,
      buildingName: '더현대 서울',
    );
    final overlay = tester.widget<IgnorePointer>(
      find.descendant(
        of: find.byType(IndoorTransitionOverlay),
        matching: find.byType(IgnorePointer),
      ),
    );
    expect(overlay.ignoring, isTrue);
  });

  testWidgets('연출 도중 어느 진행률에서도 터지지 않는다', (tester) async {
    // 그리기 코드가 특정 진행률에서만 터지는 일이 있다(투명도 0 분기, 퇴화한 변환).
    for (final direction in IndoorTransitionDirection.values) {
      for (var i = 0; i <= 20; i++) {
        await _pump(
          tester,
          progress: i / 20,
          direction: direction,
          buildingName: '스타필드 하남',
        );
        expect(tester.takeException(), isNull, reason: '$direction i=$i');
      }
    }
  });

  testWidgets('좁은 화면에서 긴 건물명이 넘치지 않는다', (tester) async {
    // 한때 `Row` 안의 `Text`에 폭 제한이 없어 `overflow: ellipsis`가 안 걸렸고,
    // 긴 이름이 말줄임 대신 **오버플로로 터졌다.** 프레임 추출기가 잡아 준
    // 버그인데 그 도구를 지웠으므로, 좁은 화면을 여기서 직접 만든다.
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(
      tester,
      progress: 0.5,
      direction: IndoorTransitionDirection.enter,
      buildingName: '스타필드 코엑스몰 서관 지하 아케이드',
    );
    expect(tester.takeException(), isNull);
  });
}
