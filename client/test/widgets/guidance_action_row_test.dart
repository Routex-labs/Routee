import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/route/transit_route.dart';
import 'package:navigation_client/screens/outdoor_map/widgets/transit_summary_card.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/widgets/eta_card.dart';
import 'package:navigation_client/widgets/guidance_action_row.dart';

const _point = LatLng(37.5253, 126.9250);

const _walkOnly = TransitItinerary(
  totalTimeSeconds: 600,
  totalWalkTimeSeconds: 600,
  totalDistanceMeters: 500,
  transferCount: 0,
  legs: [
    TransitLeg(
      mode: TransitMode.walk,
      sectionTimeSeconds: 600,
      distanceMeters: 500,
      points: [_point, _point],
    ),
  ],
);

/// 안내 중 하단 카드의 **버튼 줄**에 대한 검증 기준.
///
/// 지키는 계약 셋:
///   - 전환 버튼이 없으면 지금까지와 똑같이 `안내 종료` 하나다.
///   - 전환 버튼은 조건을 못 채워도 **자리를 지키되 눌리지 않는다.**
///   - 도보 카드와 대중교통 카드가 **같은 줄**을 쓴다. 실내→야외 여정은 두 카드
///     어느 쪽으로도 시작되므로, 한쪽에만 붙으면 대중교통으로 나가려는 사용자는
///     나갈 방법이 없다.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: child)),
    ),
  );

  /// 버튼 하나가 실제로 눌리는 상태인지. `RoutexButton`은 비활성일 때 내부
  /// TextButton의 onPressed를 null로 내린다.
  bool enabled(WidgetTester tester, String label) {
    final button = tester.widget<TextButton>(
      find.ancestor(of: find.text(label), matching: find.byType(TextButton)),
    );
    return button.onPressed != null;
  }

  group('GuidanceActionRow', () {
    testWidgets('전환이 없으면 안내 종료 하나만 남는다', (WidgetTester tester) async {
      await pump(tester, GuidanceActionRow(onStop: () {}));
      expect(find.text('안내 종료'), findsOneWidget);
      expect(find.byKey(GuidanceActionRow.transitionButtonKey), findsNothing);
    });

    testWidgets('조건을 못 채운 전환 버튼도 자리를 지킨다', (WidgetTester tester) async {
      // **숨기지 않는 것이 요점이다.** 문 앞에서야 처음 나타나면 사용자는 그런
      // 조작이 있는 줄도 모르고 걷다가, 정작 눌러야 할 때 처음 보게 된다.
      await pump(
        tester,
        GuidanceActionRow(
          onStop: () {},
          transition: const GuidanceTransitionAction(
            label: '더현대 서울로 진입',
            onPressed: null,
          ),
        ),
      );
      expect(find.text('더현대 서울로 진입'), findsOneWidget);
      expect(enabled(tester, '더현대 서울로 진입'), isFalse);
      expect(
        enabled(tester, '안내 종료'),
        isTrue,
        reason: '전환이 잠겨도 안내를 끝낼 길은 늘 열려 있어야 한다',
      );
    });

    testWidgets('조건을 채우면 눌린다', (WidgetTester tester) async {
      var pressed = 0;
      await pump(
        tester,
        GuidanceActionRow(
          onStop: () {},
          transition: GuidanceTransitionAction(
            label: '밖으로 나가기',
            onPressed: () => pressed++,
          ),
        ),
      );
      expect(enabled(tester, '밖으로 나가기'), isTrue);
      await tester.tap(find.byKey(GuidanceActionRow.transitionButtonKey));
      await tester.pump();
      expect(pressed, 1);
    });

    testWidgets('전환이 왼쪽, 안내 종료가 오른쪽이다', (WidgetTester tester) async {
      // 오른쪽 끝은 엄지가 가장 먼저 닿는 자리이고 거기엔 이미 되돌릴 수 없는
      // 조작(안내 종료)이 있었다. 새 버튼을 그리로 옮기면 익숙해진 손이 종료
      // 대신 진입을 누른다.
      await pump(
        tester,
        GuidanceActionRow(
          onStop: () {},
          transition: GuidanceTransitionAction(
            label: '밖으로 나가기',
            onPressed: () {},
          ),
        ),
      );
      expect(
        tester.getCenter(find.text('밖으로 나가기')).dx,
        lessThan(tester.getCenter(find.text('안내 종료')).dx),
      );
    });
  });

  group('카드에 붙는 자리', () {
    testWidgets('걷는 안내 카드가 전환 버튼을 함께 띄운다', (WidgetTester tester) async {
      await pump(
        tester,
        EtaCard(
          distanceMeters: 120,
          minutes: 3,
          guidanceStarted: true,
          onClose: () {},
          transition: GuidanceTransitionAction(
            label: '밖으로 나가기',
            onPressed: () {},
          ),
        ),
      );
      // 남은 시간·거리를 잃지 않는다. 버튼 한 개를 더 넣느라 진행 정보가
      // 사라지면 안내 중 화면이 무엇을 말하는지가 통째로 바뀐다.
      expect(find.text('남은 거리'), findsOneWidget);
      expect(find.text('남은 시간'), findsOneWidget);
      expect(find.text('밖으로 나가기'), findsOneWidget);
      expect(find.text('안내 종료'), findsOneWidget);
    });

    testWidgets('전환이 없는 걷는 안내는 예전 카드 그대로다', (WidgetTester tester) async {
      await pump(
        tester,
        EtaCard(
          distanceMeters: 120,
          minutes: 3,
          guidanceStarted: true,
          onClose: () {},
        ),
      );
      expect(find.byKey(GuidanceActionRow.transitionButtonKey), findsNothing);
      expect(find.text('남은 거리'), findsOneWidget);
      expect(find.text('안내 종료'), findsOneWidget);
    });

    testWidgets('대중교통 안내 카드도 같은 줄을 쓴다', (WidgetTester tester) async {
      // 실내에서 타러 나가는 여정이 이 카드로 안내된다. 여기에 안 붙으면
      // 대중교통으로 나가려는 사용자는 건물에서 나갈 방법이 없다.
      await pump(
        tester,
        TransitSummaryCard(
          itinerary: _walkOnly,
          label: '목적지까지',
          onClose: () {},
          transition: const GuidanceTransitionAction(
            label: '밖으로 나가기',
            onPressed: null,
          ),
        ),
      );
      expect(find.text('밖으로 나가기'), findsOneWidget);
      expect(enabled(tester, '밖으로 나가기'), isFalse);
      expect(find.text('안내 종료'), findsOneWidget);
    });
  });
}
