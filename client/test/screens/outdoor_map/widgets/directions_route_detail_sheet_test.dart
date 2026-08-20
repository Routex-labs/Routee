import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/models/route/directions_route.dart';
import 'package:navigation_client/screens/outdoor_map/widgets/directions_route_detail_sheet.dart';

void main() {
  testWidgets('경로 단계를 순서대로 문구·거리와 함께 보여준다', (tester) async {
    const route = DirectionsRoute(
      points: [LatLng(0, 0), LatLng(0.002, 0), LatLng(0.002, 0.002)],
      distanceMeters: 380,
      durationSeconds: 290,
      steps: [
        DirectionsRouteStep(
          instruction: '출발',
          distanceMeters: 0,
          point: LatLng(0, 0),
        ),
        DirectionsRouteStep(
          instruction: '우회전',
          distanceMeters: 200,
          point: LatLng(0.002, 0),
        ),
        DirectionsRouteStep(
          instruction: '도착',
          distanceMeters: 180,
          point: LatLng(0.002, 0.002),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDirectionsRouteDetailSheet(
                context,
                route: route,
                destinationLabel: '서울창업허브',
              ),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    expect(find.text('서울창업허브까지'), findsOneWidget);
    expect(find.text('출발'), findsOneWidget);
    expect(find.text('우회전'), findsOneWidget);
    expect(find.text('도착'), findsOneWidget);
    expect(find.text('200m'), findsOneWidget);
  });
}
