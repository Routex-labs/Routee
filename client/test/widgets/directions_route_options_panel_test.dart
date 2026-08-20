import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/models/route/directions_route.dart';
import 'package:navigation_client/widgets/directions_route_options_panel.dart';
import 'package:routex_design_system/routex_design_system.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: Center(child: child)),
  );

  const routeA = DirectionsRoute(
    points: [LatLng(0, 0), LatLng(1, 1)],
    distanceMeters: 3900,
    durationSeconds: 480,
  );
  const routeB = DirectionsRoute(
    points: [LatLng(0, 0), LatLng(2, 2)],
    distanceMeters: 5100,
    durationSeconds: 1500,
  );

  testWidgets('후보를 한 줄씩 그리고 탭하면 선택을 알린다', (tester) async {
    int? picked;
    await tester.pumpWidget(
      wrap(
        DirectionsRouteOptionsPanel(
          options: const [
            DirectionsRouteOption(
              kinds: [DirectionsRouteOptionKind.recommended],
              route: routeA,
            ),
            DirectionsRouteOption(
              kinds: [DirectionsRouteOptionKind.shortestDistance],
              route: routeB,
            ),
          ],
          selectedIndex: 0,
          onSelect: (index) => picked = index,
        ),
      ),
    );

    expect(find.text('추천'), findsOneWidget);
    expect(find.text('최단거리'), findsOneWidget);

    await tester.tap(find.text('최단거리'));
    expect(picked, 1);
  });

  testWidgets('후보가 1개면 아무것도 그리지 않는다', (tester) async {
    await tester.pumpWidget(
      wrap(
        DirectionsRouteOptionsPanel(
          options: const [
            DirectionsRouteOption(
              kinds: [DirectionsRouteOptionKind.recommended],
              route: routeA,
            ),
          ],
          selectedIndex: 0,
          onSelect: (_) {},
        ),
      ),
    );

    expect(find.byType(RoutexRouteOption), findsNothing);
  });

  testWidgets('kinds가 여럿이어도 라벨은 맨 앞 하나만 적는다', (tester) async {
    await tester.pumpWidget(
      wrap(
        DirectionsRouteOptionsPanel(
          options: const [
            DirectionsRouteOption(
              kinds: [
                DirectionsRouteOptionKind.recommended,
                DirectionsRouteOptionKind.alternative,
              ],
              route: routeA,
            ),
            DirectionsRouteOption(
              kinds: [DirectionsRouteOptionKind.shortestDistance],
              route: routeB,
            ),
          ],
          selectedIndex: 0,
          onSelect: (_) {},
        ),
      ),
    );

    expect(find.text('추천'), findsOneWidget);
    expect(find.text('최단거리'), findsOneWidget);
    expect(find.textContaining('대안'), findsNothing);
  });
}
