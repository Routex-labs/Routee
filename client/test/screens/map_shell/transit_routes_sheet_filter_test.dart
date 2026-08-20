import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/models/route/transit_route.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/transit_routes_sheet.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/widgets/transit_itinerary_card.dart';

/// 결과 목록 위 수단 필터. 분류 규칙 자체는
/// `test/domain/route/transit_itinerary_filter_test.dart`가 지킨다 — 여기서는
/// 탭이 목록을 실제로 좁히는지만 본다.
void main() {
  TransitLeg leg(TransitMode mode) => TransitLeg(
    mode: mode,
    sectionTimeSeconds: 600,
    distanceMeters: 500,
    points: const [],
    startName: '어딘가',
    endName: '어딘가2',
    stationCount: 2,
  );

  // 소요 시간을 갈래마다 다르게 준다. 목록이 좁혀졌는지를 **카드 개수로 세지
  // 않기 위해서다** — ListView가 지연 생성이라 시트 높이에 안 들어가는 줄은
  // 애초에 만들어지지 않는다. 개수를 세면 필터가 아니라 화면 높이를 재게 된다.
  TransitItinerary itinerary(List<TransitMode> modes, int seconds) =>
      TransitItinerary(
        totalTimeSeconds: seconds,
        totalWalkTimeSeconds: 300,
        totalDistanceMeters: 3000,
        transferCount: 0,
        fare: 1500,
        legs: [for (final mode in modes) leg(mode)],
      );

  final routes = TransitRoutes.ok([
    itinerary([TransitMode.walk, TransitMode.bus], 1200), // 20분
    itinerary([TransitMode.walk, TransitMode.subway], 1800), // 30분
    itinerary([TransitMode.walk, TransitMode.bus], 2400), // 40분
  ]);

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: TransitRoutesSheet(
            routes: routes,
            destinationLabel: '목적지',
            onCloseAll: () {},
            onPreview: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('있는 갈래만 탭으로 세운다', (tester) async {
    await pumpSheet(tester);

    expect(find.text('전체'), findsOneWidget);
    expect(find.text('버스 2'), findsOneWidget);
    expect(find.text('지하철 1'), findsOneWidget);
    // 버스+지하철을 함께 타는 경로가 없으므로 그 탭은 아예 없다.
    expect(find.textContaining('버스+지하철'), findsNothing);
  });

  testWidgets('탭을 고르면 그 갈래만 남는다', (tester) async {
    await pumpSheet(tester);

    // 전체에서는 맨 위가 버스 경로(20분)다.
    expect(find.text('20분'), findsOneWidget);
    expect(find.byType(TransitItineraryCard), findsWidgets);

    await tester.tap(find.text('지하철 1'));
    await tester.pumpAndSettle();

    // 지하철만 남았으므로 맨 위가 30분짜리로 바뀌고 버스 경로는 사라진다.
    expect(find.text('30분'), findsOneWidget);
    expect(find.text('20분'), findsNothing);
    expect(find.text('40분'), findsNothing);
  });
}
