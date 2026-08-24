import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/guidance/route_guidance.dart';
import 'package:navigation_client/features/indoor_navigation/contract/floor_transition_ui_state.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/widgets/eta_card.dart';
import 'package:routex_design_system/routex_design_system.dart';

/// Runtime Kit의 계획 카드·안내 배너에 앱 경로 값이 올바르게 연결되는지 확인한다.
void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: Center(child: child)),
  );

  RouteGuidanceInstruction turn({double toAction = 92}) =>
      RouteGuidanceInstruction(
        action: RouteGuidanceAction.turnRight,
        primaryText: '오른쪽 통로로 이동',
        distanceToActionM: toAction,
      );

  group('안내 중 상단 배너', () {
    testWidgets('다음 행동과 그 행동까지의 거리를 적는다', (tester) async {
      await tester.pumpWidget(wrap(GuidanceBanner(instruction: turn())));

      expect(find.text('오른쪽 통로로 이동'), findsOneWidget);
      expect(find.text('92m'), findsOneWidget);
    });

    testWidgets('도착 직전에는 소수점 한 자리까지 보여 준다', (tester) async {
      await tester.pumpWidget(
        wrap(GuidanceBanner(instruction: turn(toAction: 3.4))),
      );

      expect(find.text('3.4m'), findsOneWidget);
    });

    testWidgets('1 km가 넘으면 km로 적는다', (tester) async {
      await tester.pumpWidget(
        wrap(GuidanceBanner(instruction: turn(toAction: 1200))),
      );

      expect(find.text('1.2km'), findsOneWidget);
    });

    testWidgets('경로 이탈은 조작 지시 대신 재탐색 상태를 말한다', (tester) async {
      await tester.pumpWidget(
        wrap(
          const GuidanceBanner(
            instruction: RouteGuidanceInstruction(
              action: RouteGuidanceAction.wrongWay,
              primaryText: '반대 방향',
              distanceToActionM: 0,
            ),
          ),
        ),
      );

      expect(find.text('경로를 벗어났습니다'), findsOneWidget);
      expect(find.text('새 경로를 자동으로 찾고 있습니다'), findsOneWidget);
    });
  });

  group('상단 배너는 한 자리다 — 무엇이 그 자리를 쓰는가', () {
    // 예전에는 층 전환만 셸이 흰 알약으로 따로 띄워, 초록 배너 위에 알약이
    // 겹쳤다. 이제 네 상태가 같은 자리를 나눠 쓰고 우선순위가 하나뿐이다.

    FloorTransitionUiState riding() => const FloorTransitionUiState(
      stage: FloorTransitionStage.swapping,
      fromFloorLabel: 'B2',
      toFloorLabel: 'B1',
      goingUp: true,
    );

    testWidgets('층 전환이 다음 행동을 밀어낸다', (tester) async {
      // 타는 동안 걸음이 멈춰 있어 남은거리가 갱신되지 않는다. 그대로 두면
      // "92m 뒤 오른쪽"이 에스컬레이터를 타는 내내 붙어 있다.
      await tester.pumpWidget(
        wrap(GuidanceBanner(instruction: turn(), floorTransition: riding())),
      );

      expect(find.text('B2 → B1'), findsOneWidget);
      expect(find.text('에스컬레이터로 이동 중'), findsOneWidget);
      expect(find.text('오른쪽 통로로 이동'), findsNothing);
    });

    testWidgets('도착은 다음 행동보다 앞서고 층 전환보다 뒤다', (tester) async {
      await tester.pumpWidget(
        wrap(GuidanceBanner(instruction: turn(), arrivalAt: '오설록 · B1')),
      );

      expect(find.text('목적지에 도착했습니다'), findsOneWidget);
      expect(find.text('오설록 · B1'), findsOneWidget);
      expect(find.text('오른쪽 통로로 이동'), findsNothing);

      await tester.pumpWidget(
        wrap(
          GuidanceBanner(
            instruction: turn(),
            floorTransition: riding(),
            arrivalAt: '오설록 · B1',
          ),
        ),
      );

      expect(find.text('에스컬레이터로 이동 중'), findsOneWidget);
      expect(find.text('목적지에 도착했습니다'), findsNothing);
    });

    testWidgets('그릴 것이 없으면 호출부가 자리를 비울 수 있다', (tester) async {
      expect(const GuidanceBanner().isEmpty, isTrue);
      expect(GuidanceBanner(instruction: turn()).isEmpty, isFalse);
      expect(const GuidanceBanner(arrivalAt: '오설록 · B1').isEmpty, isFalse);
    });
  });

  group('안내 전 계획 카드', () {
    testWidgets('무엇을 향하는지와 소요·거리를 함께 적는다', (tester) async {
      await tester.pumpWidget(
        wrap(const EtaCard(distanceMeters: 480, minutes: 7, label: '건물 입구까지')),
      );

      expect(find.text('건물 입구까지'), findsOneWidget);
      expect(find.textContaining('7분', findRichText: true), findsOneWidget);
      expect(find.textContaining('480m', findRichText: true), findsOneWidget);
      expect(find.text('안내 종료'), findsNothing);
    });

    testWidgets('routeOptions을 건네면 요약 위에 그린다', (tester) async {
      await tester.pumpWidget(
        wrap(
          const EtaCard(
            distanceMeters: 3900,
            minutes: 8,
            label: '목적지까지',
            routeOptions: Text('옵션 영역'),
          ),
        ),
      );

      expect(find.text('옵션 영역'), findsOneWidget);
    });

    testWidgets('extraMetric을 건네면 소요·거리 옆에 함께 적는다', (tester) async {
      await tester.pumpWidget(
        wrap(
          EtaCard(
            distanceMeters: 3900,
            minutes: 8,
            label: '목적지까지',
            extraMetric: const RoutexTripMetric(value: '무료', label: '통행료'),
          ),
        ),
      );

      expect(find.textContaining('무료', findRichText: true), findsOneWidget);
      expect(find.textContaining('통행료', findRichText: true), findsOneWidget);
    });

    testWidgets('한 시간을 넘으면 분이 아니라 시간으로 적는다', (tester) async {
      // 도보로 272분이 실제로 나온다. 분만 적으면 사용자가 나눗셈을 해야 한다.
      await tester.pumpWidget(
        wrap(const EtaCard(distanceMeters: 20000, minutes: 272)),
      );

      expect(find.text('4시간 32분'), findsOneWidget);
      expect(find.text('272분'), findsNothing);
    });

    testWidgets('headline은 도착 시각이 아니라 소요 시간이다', (tester) async {
      await tester.pumpWidget(
        wrap(const EtaCard(distanceMeters: 3900, minutes: 8)),
      );

      // 소요가 metrics 줄(RichText)이 아니라 제 몫의 Text로 올라와 있다.
      expect(find.text('8분'), findsOneWidget);
      // 시각 표기(`오전`/`오후`)는 계획 카드에서 사라졌다.
      expect(find.textContaining('오전', findRichText: true), findsNothing);
      expect(find.textContaining('오후', findRichText: true), findsNothing);
      // 목적지 라벨은 남는다 — title은 건드리지 않았다.
      expect(find.text('목적지까지'), findsOneWidget);
    });
  });

  testWidgets('안내 중에는 남은 값과 종료 동작을 보여 준다', (tester) async {
    var closed = false;
    await tester.pumpWidget(
      wrap(
        EtaCard(
          distanceMeters: 150,
          minutes: 2,
          guidanceStarted: true,
          onClose: () => closed = true,
        ),
      ),
    );

    expect(find.text('2분'), findsOneWidget);
    expect(find.text('150m'), findsOneWidget);
    await tester.tap(find.text('안내 종료'));
    expect(closed, isTrue);
  });

  testWidgets('안내 중에는 도착 예정 시각이 그대로 남는다', (tester) async {
    await tester.pumpWidget(
      wrap(
        const EtaCard(distanceMeters: 150, minutes: 2, guidanceStarted: true),
      ),
    );

    expect(find.text('도착 예정'), findsOneWidget);
  });
}
