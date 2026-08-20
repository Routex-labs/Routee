import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/models/route/transit_route.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/widgets/transit_route_summary.dart';
import 'package:navigation_client/widgets/transit_style.dart';

/// 대비비(WCAG). 1(같은 색) ~ 21(검정 대 흰색).
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

TransitItinerary _one(TransitMode mode, String routeName) => TransitItinerary(
  totalTimeSeconds: 600,
  totalWalkTimeSeconds: 0,
  totalDistanceMeters: 5000,
  transferCount: 0,
  legs: [
    TransitLeg(
      mode: mode,
      sectionTimeSeconds: 600,
      distanceMeters: 5000,
      points: const [],
      routeName: routeName,
    ),
  ],
);

void main() {
  testWidgets('막대 칸의 글자는 그 칸 색 위에서 4.5:1을 넘는다', (tester) async {
    // 9호선 금색·순환버스 노랑 같은 밝은 표준색이 들어온다. 글자색을 흰색으로
    // 못 박으면 거기서 시간이 안 읽힌다 — 상수가 아니라 대비비로 잰다.
    for (final (mode, name) in [
      (TransitMode.subway, '9호선'),
      (TransitMode.subway, '1호선'),
      (TransitMode.bus, '순환:01'),
      (TransitMode.bus, '간선:472'),
    ]) {
      final itinerary = _one(mode, name);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: TransitLegBar(itinerary: itinerary),
            ),
          ),
        ),
      );
      await tester.pump();

      final ink = tester.widget<Text>(find.text('10분')).style?.color;
      expect(ink, isNotNull, reason: '$name 칸에 시간이 안 그려졌다');
      expect(
        _contrast(transitLegColor(itinerary.legs.first), ink!),
        greaterThanOrEqualTo(4.5),
        reason: '$name 막대 칸의 글자가 안 읽힌다',
      );
    }
  });
}
