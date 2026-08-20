import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/models/route/transit_route.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/widgets/transit_itinerary_card.dart';
import 'package:routex_design_system/routex_design_system.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  TransitLeg leg({
    required TransitMode mode,
    int seconds = 600,
    String? routeName,
    String? startName,
    String? endName,
    int stationCount = 0,
  }) => TransitLeg(
    mode: mode,
    sectionTimeSeconds: seconds,
    distanceMeters: 500,
    points: const [],
    routeName: routeName,
    startName: startName,
    endName: endName,
    stationCount: stationCount,
  );

  final ride = TransitItinerary(
    totalTimeSeconds: 1140,
    totalWalkTimeSeconds: 300,
    totalDistanceMeters: 3000,
    transferCount: 0,
    fare: 1500,
    legs: [
      leg(mode: TransitMode.walk, seconds: 60),
      leg(
        mode: TransitMode.bus,
        seconds: 660,
        routeName: '지선:7613',
        startName: '삼부아파트',
        endName: '공덕역2번출구',
        stationCount: 2,
      ),
      leg(mode: TransitMode.walk, seconds: 240),
    ],
  );

  Widget card(TransitItinerary itinerary) => wrap(
    TransitItineraryCard(itinerary: itinerary, fastest: true, onTap: () {}),
  );

  testWidgets('소요·요금·노선·정류장명을 적는다', (tester) async {
    await tester.pumpWidget(card(ride));

    expect(find.text('19분'), findsOneWidget);
    expect(find.text('1,500원'), findsOneWidget);
    expect(find.text('7613'), findsOneWidget);
    expect(find.text('삼부아파트'), findsOneWidget);
    expect(find.text('공덕역2번출구'), findsOneWidget);
    // 카드 전체가 상세를 여는 손잡이다. 접기 화살표도, 별도 '상세보기' 줄도
    // 두지 않는다 — 둘 다 같은 자리를 두 번 차지한다.
    expect(find.byType(IconButton), findsNothing);
    expect(find.text('상세보기'), findsNothing);
  });

  testWidgets('최적은 배지 없이 지도 본선과 같은 파랑 글자다', (tester) async {
    await tester.pumpWidget(card(ride));

    // 배지 박스가 하나도 없어야 한다 — 사용자가 지적한 "박스가 너무 많다".
    expect(find.byType(RoutexBadge), findsNothing);
    final label = tester.widget<Text>(find.text('최적'));
    // teal(actionPrimary)이 아니라 지도 본선과 같은 파랑이어야 한다.
    expect(label.style?.color, const Color(0xFF4A87F1));
  });

  testWidgets('도착 시각은 적지 않는다', (tester) async {
    await tester.pumpWidget(card(ride));

    expect(find.textContaining('도착'), findsNothing);
  });

  testWidgets('요금이 없으면 요금 칸을 그리지 않는다', (tester) async {
    final noFare = TransitItinerary(
      totalTimeSeconds: 1140,
      totalWalkTimeSeconds: 300,
      totalDistanceMeters: 3000,
      transferCount: 0,
      legs: ride.legs,
    );
    await tester.pumpWidget(card(noFare));

    expect(find.textContaining('원'), findsNothing);
  });

  testWidgets('탈것이 없으면 승하차 줄을 그리지 않는다', (tester) async {
    final walkOnly = TransitItinerary(
      totalTimeSeconds: 600,
      totalWalkTimeSeconds: 600,
      totalDistanceMeters: 700,
      transferCount: 0,
      legs: [leg(mode: TransitMode.walk, seconds: 600)],
    );
    await tester.pumpWidget(card(walkOnly));

    expect(find.text('하차'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('총 소요가 0이어도 던지지 않는다', (tester) async {
    final zero = TransitItinerary(
      totalTimeSeconds: 0,
      totalWalkTimeSeconds: 0,
      totalDistanceMeters: 0,
      transferCount: 0,
      legs: [leg(mode: TransitMode.walk, seconds: 0)],
    );
    await tester.pumpWidget(card(zero));

    expect(tester.takeException(), isNull);
  });

  testWidgets('정류장명이 길어도 노선번호를 자르지 않는다', (tester) async {
    final longName = TransitItinerary(
      totalTimeSeconds: 1140,
      totalWalkTimeSeconds: 300,
      totalDistanceMeters: 3000,
      transferCount: 0,
      fare: 1500,
      legs: [
        leg(
          mode: TransitMode.bus,
          seconds: 1140,
          routeName: '지선:7613',
          startName: '서울월드컵경기장앞정류장중앙차로승강장동편임시정류소',
          endName: '공덕역2번출구',
          stationCount: 2,
        ),
      ],
    );
    await tester.pumpWidget(card(longName));

    expect(find.text('7613'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('막대 칸이 글자보다 좁으면 시간을 자르지 않고 뺀다', (tester) async {
    // 1분짜리 도보가 60분 여정에 섞이면 그 칸은 몇 픽셀이다. 실기기에서 "3분"이
    // "3"으로 잘려 정류장 수처럼 읽힌 적이 있다.
    final lopsided = TransitItinerary(
      totalTimeSeconds: 3600,
      totalWalkTimeSeconds: 60,
      totalDistanceMeters: 20000,
      transferCount: 0,
      legs: [
        leg(mode: TransitMode.walk, seconds: 60),
        leg(
          mode: TransitMode.bus,
          seconds: 3540,
          routeName: '간선:472',
          startName: '어딘가',
          endName: '어딘가2',
          stationCount: 9,
        ),
      ],
    );
    await tester.pumpWidget(card(lopsided));

    // 넓은 칸은 그대로 적고,
    expect(find.text('59분'), findsOneWidget);
    // 좁은 칸은 잘린 조각이 아니라 아무것도 안 남긴다.
    expect(find.text('1분'), findsNothing);
    expect(find.text('1'), findsNothing);
    // 막대 높이가 모자라면 오버플로로 터진다 — 그것도 여기서 잡는다.
    expect(tester.takeException(), isNull);
  });

  testWidgets('시간을 모르는 도보 칸에는 분을 적지 않고 칸만 남긴다', (tester) async {
    // TMAP 조회 상한에 잘린 후보는 앞뒤 도보가 0초 직선으로 채워진다.
    // formatTransitDuration이 0초를 "1분"으로 올리므로, 그리는 쪽이 빼야 한다.
    final unknownWalk = TransitItinerary(
      totalTimeSeconds: 1800,
      totalWalkTimeSeconds: 0,
      totalDistanceMeters: 3000,
      transferCount: 0,
      fare: 1500,
      legs: [
        leg(mode: TransitMode.walk, seconds: 0),
        leg(
          mode: TransitMode.bus,
          seconds: 300,
          routeName: '지선:7613',
          startName: '삼부아파트',
          endName: '공덕역2번출구',
          stationCount: 2,
        ),
        leg(mode: TransitMode.walk, seconds: 0),
      ],
    );
    await tester.pumpWidget(card(unknownWalk));

    // 모르는 시간을 지어내지 않는다.
    expect(find.text('1분'), findsNothing);
    expect(find.text('0분'), findsNothing);
    // 아는 시간은 그대로 적는다.
    expect(find.text('5분'), findsOneWidget);
    // 칸 자체는 비율대로 남는다 — 거기 도보가 있다는 사실은 참이고 시간만
    // 모른다. 글자가 들어가고도 남는 너비여야 "좁아서 빠진 것"과 구분된다.
    expect(tester.getSize(find.byType(Center).first).width, greaterThan(20));
    expect(tester.takeException(), isNull);
  });

  test('카드는 stateless다', () {
    expect(
      TransitItineraryCard(itinerary: ride, fastest: true, onTap: () {}),
      isA<StatelessWidget>(),
    );
  });
}
