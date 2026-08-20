import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/route/transit_route.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/widgets/transit_timeline.dart';
import 'package:routex_design_system/routex_design_system.dart';

const _point = LatLng(37.5253, 126.9250);

/// 시각 단언이 실행 시각에 흔들리지 않게 출발을 고정한다.
final _departure = DateTime(2026, 8, 19, 15, 0);

const _walk = TransitLeg(
  mode: TransitMode.walk,
  sectionTimeSeconds: 180,
  distanceMeters: 166,
  points: [_point, _point],
);

/// 지나는 정류장이 [stops]개인 버스 구간. 본문이 길수록 선도 길어야 한다.
TransitLeg _bus(int stops) => TransitLeg(
  mode: TransitMode.bus,
  sectionTimeSeconds: 1920,
  distanceMeters: 5200,
  points: const [_point, _point],
  routeName: '지선:7734',
  startName: '은평구청',
  endName: '공덕역',
  stationCount: stops + 1,
  stopNames: ['은평구청', for (var i = 0; i < stops; i++) '정류장$i', '공덕역'],
);

Future<void> _pump(WidgetTester tester, List<TransitLeg> legs) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: TransitTimeline(
            itinerary: TransitItinerary(
              totalTimeSeconds: 2400,
              totalWalkTimeSeconds: 180,
              totalDistanceMeters: 5400,
              transferCount: 0,
              legs: legs,
            ),
            destinationLabel: '광화문역',
            departureAt: _departure,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<Rect> _connectors(WidgetTester tester) {
  final found = find.byKey(transitTimelineConnectorKey);
  return [
    for (var i = 0; i < tester.widgetList(found).length; i++)
      tester.getRect(found.at(i)),
  ];
}

Rect _icon(WidgetTester tester, IconData icon) =>
    tester.getRect(find.byIcon(icon));

void main() {
  testWidgets('선이 다음 칸의 아이콘까지 끊김 없이 내려온다', (tester) async {
    await _pump(tester, [_walk, _bus(4)]);

    final lines = _connectors(tester);
    final bus = _icon(tester, Icons.directions_bus_rounded);
    final arrived = _icon(tester, RoutexIcons.arrived);

    expect(lines, hasLength(2));
    expect(lines[0].bottom, moreOrLessEquals(bus.top, epsilon: 0.5));
    expect(lines[1].bottom, moreOrLessEquals(arrived.top, epsilon: 0.5));
  });

  testWidgets('본문이 길수록 선도 길어진다 — 16px 고정이 아니다', (tester) async {
    await _pump(tester, [_walk, _bus(4)]);
    final short = _connectors(tester)[0].height;
    final tall = _connectors(tester)[1].height;

    // 탈것 칸은 노선 칩·정류장 줄·하차 정류장을 함께 이고 있어 도보 칸보다 높다.
    expect(tall, greaterThan(short));
    expect(tall, greaterThan(RoutexSpacing.componentPadding));
  });

  testWidgets('선이 첫 아이콘 위나 마지막 아이콘 아래로 삐져나가지 않는다', (tester) async {
    await _pump(tester, [_walk, _bus(4)]);

    final lines = _connectors(tester);
    final walk = _icon(tester, Icons.directions_walk_rounded);
    final arrived = _icon(tester, RoutexIcons.arrived);
    final timeline = tester.getRect(find.byType(TransitTimeline));

    for (final line in lines) {
      expect(line.top, greaterThanOrEqualTo(walk.bottom));
      expect(line.bottom, lessThanOrEqualTo(arrived.top + 0.5));
    }
    // 도착 칸은 선을 그리지 않는다 — 목록 끝에서 선이 허공으로 이어지면 안 된다.
    expect(lines.last.bottom, lessThan(timeline.bottom));
  });

  testWidgets('정류장을 펼치면 선도 그만큼 늘어난다', (tester) async {
    await _pump(tester, [_walk, _bus(30)]);
    final folded = _connectors(tester)[1].height;

    await tester.tap(find.text('31개 정류장 이동'));
    await tester.pumpAndSettle();

    final lines = _connectors(tester);
    final arrived = _icon(tester, RoutexIcons.arrived);
    expect(lines[1].height, greaterThan(folded));
    expect(lines[1].bottom, moreOrLessEquals(arrived.top, epsilon: 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('펼친 첫 프레임에도 선은 다음 아이콘에 붙어 있다', (tester) async {
    await _pump(tester, [_walk, _bus(30)]);
    await tester.tap(find.text('31개 정류장 이동'));
    await tester.pump();

    // 펼침 직후 한 프레임. 칸 높이를 본문의 intrinsic으로 잡으면 이 프레임에서
    // 선과 다음 아이콘이 서로 다른 높이를 본다.
    expect(
      _connectors(tester)[1].bottom,
      moreOrLessEquals(_icon(tester, RoutexIcons.arrived).top, epsilon: 0.5),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('본문이 한 줄뿐인 칸도 선을 그린다', (tester) async {
    // 거리 0이면 도보 칸은 글자 한 줄이라 가장 낮다. 선이 시작하는 24px보다
    // 칸이 낮아지면 Stack이 음수 높이를 받는다.
    await _pump(tester, [
      const TransitLeg(
        mode: TransitMode.walk,
        sectionTimeSeconds: 60,
        distanceMeters: 0,
        points: [_point, _point],
      ),
    ]);

    expect(_connectors(tester), hasLength(1));
    expect(_connectors(tester).single.height, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('도보 한 구간만 있어도 선은 하나뿐이다', (tester) async {
    await _pump(tester, [_walk]);

    final lines = _connectors(tester);
    final arrived = _icon(tester, RoutexIcons.arrived);
    expect(lines, hasLength(1));
    expect(lines[0].bottom, moreOrLessEquals(arrived.top, epsilon: 0.5));
  });
}
