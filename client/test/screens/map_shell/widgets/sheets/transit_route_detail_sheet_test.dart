import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/route/transit_route.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/transit_route_detail_sheet.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:routex_design_system/routex_design_system.dart';

const _point = LatLng(37.5253, 126.9250);

/// 시각 단언이 실행 시각에 따라 흔들리지 않게 출발 시각을 고정한다.
final _departure = DateTime(2026, 8, 19, 15, 0);

const _walkLeg = TransitLeg(
  mode: TransitMode.walk,
  sectionTimeSeconds: 300,
  distanceMeters: 166,
  points: [_point, _point],
);

const _busLeg = TransitLeg(
  mode: TransitMode.bus,
  sectionTimeSeconds: 900,
  distanceMeters: 5200,
  points: [_point, _point],
  routeName: '지선:5623',
  startName: '여의도환승센터',
  endName: '공덕역',
  stationCount: 3,
  stopNames: ['여의도환승센터', '국회의사당', '마포대교남단', '공덕역'],
  vehicles: [(name: '5623', type: '지선'), (name: '461', type: '간선')],
);

const _withBus = TransitItinerary(
  totalTimeSeconds: 1500,
  totalWalkTimeSeconds: 300,
  totalDistanceMeters: 5400,
  transferCount: 0,
  fare: 1500,
  legs: [_walkLeg, _busLeg],
);

TransitItinerary _one(TransitLeg leg, {int total = 900, int? fare = 1500}) =>
    TransitItinerary(
      totalTimeSeconds: total,
      totalWalkTimeSeconds: 0,
      totalDistanceMeters: 1000,
      transferCount: 0,
      fare: fare,
      legs: [leg],
    );

Future<void> _pump(WidgetTester tester, TransitItinerary itinerary) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: TransitRouteDetailSheet(
          itinerary: itinerary,
          destinationLabel: '광화문역',
          departureAt: _departure,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// `show`로 실제 라우트에 띄우고, 닫히며 돌아온 값을 읽는 손잡이를 준다.
///
/// 그릇(전체 화면 라우트)을 보는 단언은 위젯을 바로 심어서는 못 한다.
Future<Object? Function()> _open(WidgetTester tester) async {
  Object? result = 'not-set';
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await TransitRouteDetailSheet.show(
                context,
                itinerary: _withBus,
                destinationLabel: '광화문역',
                departureAt: _departure,
              );
            },
            child: const Text('열기'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
  return () => result;
}

void main() {
  testWidgets('요약 헤더에 총 소요·도착 예정 시각·요금을 함께 적는다', (tester) async {
    await _pump(tester, _withBus);

    expect(find.text('25분'), findsOneWidget);
    expect(find.text('1,500원'), findsOneWidget);
    // 15:00 + 1500초 = 15:25.
    expect(find.text('오후 3:25 도착'), findsOneWidget);
  });

  testWidgets('탈것 구간에 승·하차 정류장, 노선 전부, 정류장 수를 적는다', (tester) async {
    await _pump(tester, _withBus);

    expect(find.text('여의도환승센터'), findsOneWidget);
    expect(find.text('공덕역'), findsOneWidget);
    // 같은 구간을 지나는 노선은 첫 줄만이 아니라 전부 늘어놓는다.
    expect(find.text('지선 5623'), findsOneWidget);
    expect(find.text('간선 461'), findsOneWidget);
    expect(find.text('3개 정류장 이동'), findsOneWidget);
  });

  testWidgets('도보 구간에 소요 시간과 거리를 적는다', (tester) async {
    await _pump(tester, _withBus);

    expect(find.text('도보 5분'), findsOneWidget);
    expect(find.text('166m'), findsOneWidget);
  });

  testWidgets('구간 시작 시각은 출발 시각에 앞 구간을 누적해 적는다', (tester) async {
    await _pump(tester, _withBus);

    expect(find.text('오후 3:00'), findsOneWidget); // 도보 시작
    expect(find.text('오후 3:05'), findsOneWidget); // 승차 = 도보 300초 뒤
  });

  testWidgets('지나는 정류장은 접혀 있다가 펼치면 보인다', (tester) async {
    await _pump(tester, _withBus);

    expect(find.text('국회의사당'), findsNothing);
    // 상세가 아래 절반만 덮는 시트가 된 뒤로는 접기 줄이 화면 밖일 수 있다.
    // 안 굴려 주면 탭이 빗나가고 "펼쳐도 안 보인다"로 보인다.
    await tester.ensureVisible(find.text('3개 정류장 이동'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3개 정류장 이동'));
    await tester.pumpAndSettle();
    expect(find.text('국회의사당'), findsOneWidget);
    expect(find.text('마포대교남단'), findsOneWidget);
  });

  testWidgets('도보만인 경로도 그린다 — 노선 줄은 아예 없다', (tester) async {
    await _pump(tester, _one(_walkLeg, total: 300));

    expect(find.text('도보 5분'), findsOneWidget);
    expect(find.text('광화문역'), findsWidgets); // 도착 노드
    expect(tester.takeException(), isNull);
  });

  testWidgets('stopNames가 빈 탈것 구간은 접기 없이 정류장 수만 적는다', (tester) async {
    const leg = TransitLeg(
      mode: TransitMode.subway,
      sectionTimeSeconds: 600,
      distanceMeters: 6000,
      points: [_point, _point],
      routeName: '수도권5호선',
      startName: '여의도역',
      endName: '광화문역',
      stationCount: 4,
    );
    await _pump(tester, _one(leg));

    expect(find.text('4개 정류장 이동'), findsOneWidget);
    // 펼칠 것이 없으므로 펼침 화살표도 없다.
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
  });

  testWidgets('vehicles가 비면 노선명 하나로 대신하고, 그것도 없으면 칩이 없다', (tester) async {
    const named = TransitLeg(
      mode: TransitMode.bus,
      sectionTimeSeconds: 600,
      distanceMeters: 6000,
      points: [_point, _point],
      routeName: '간선:472',
      startName: '여의도환승센터',
      endName: '공덕역',
    );
    await _pump(tester, _one(named));
    expect(find.text('472'), findsOneWidget);

    const nameless = TransitLeg(
      mode: TransitMode.bus,
      sectionTimeSeconds: 600,
      distanceMeters: 6000,
      points: [_point, _point],
      startName: '여의도환승센터',
      endName: '공덕역',
    );
    await _pump(tester, _one(nameless));
    expect(find.text('여의도환승센터'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('요금이 null이면 요금과 구분선을 함께 뺀다', (tester) async {
    await _pump(tester, _one(_busLeg, fare: null));

    expect(find.textContaining('원'), findsNothing);
  });

  testWidgets('총 소요가 0이면 도착 예정 시각을 지어내지 않는다', (tester) async {
    await _pump(tester, _one(_busLeg, total: 0));

    expect(find.textContaining('도착'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('정류장이 아주 많아도 화면을 넘기지 않는다', (tester) async {
    final stops = [for (var i = 0; i < 30; i++) '정류장$i'];
    final leg = TransitLeg(
      mode: TransitMode.bus,
      sectionTimeSeconds: 3600,
      distanceMeters: 30000,
      points: const [_point, _point],
      routeName: '간선:472',
      startName: stops.first,
      endName: stops.last,
      stationCount: stops.length - 1,
      stopNames: stops,
    );
    await _pump(tester, _one(leg, total: 3600));

    await tester.tap(find.text('29개 정류장 이동'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('아주 긴 정류장명도 넘치지 않는다', (tester) async {
    const long = '국립중앙의료원영휘원산모자애기수유방문앞정류장방면환승센터';
    const leg = TransitLeg(
      mode: TransitMode.bus,
      sectionTimeSeconds: 600,
      distanceMeters: 6000,
      points: [_point, _point],
      routeName: '간선:472',
      startName: long,
      endName: long,
      stationCount: 2,
      stopNames: [long, long, long],
      vehicles: [(name: '4721234567890', type: '광역급행좌석')],
    );
    await _pump(tester, _one(leg));

    await tester.tap(find.text('2개 정류장 이동'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('상세는 아래 절반만 덮고 위는 지도로 비운다', (tester) async {
    // 시간표를 읽는 동안 그 경로가 어디로 도는지 함께 보여야 한다. 위쪽을
    // 비우지 않으면 사용자는 두 화면을 번갈아 열어 견줘야 한다.
    await _open(tester);

    // 라우트는 그대로 PageRoute다 — 시트로 바꾼 이유는 아래 목록을 트리에서
    // 내리지 않기 위해서였고(지도 플랫폼 뷰가 헐린다), 그건 그대로다.
    final route = ModalRoute.of(
      tester.element(find.byType(TransitRouteDetailSheet)),
    );
    expect(route, isA<PageRoute>(), reason: '목록이 트리에서 내려가면 지도가 헐린다');

    final screen = tester.getSize(find.byType(MaterialApp));
    final sheet = tester.getRect(find.byType(RoutexBottomSheet).first);
    expect(
      sheet.top,
      greaterThan(screen.height * 0.25),
      reason: '위쪽은 지도 자리다 — 꽉 채우면 경로를 볼 수 없다',
    );
    expect(
      sheet.bottom,
      closeTo(screen.height, 1),
      reason: '시트는 바닥에 붙어 있어야 한다',
    );
  });

  testWidgets('드래그로 시트 크기를 바꿀 수 있다', (tester) async {
    await _open(tester);

    final before = tester.getRect(find.byType(RoutexBottomSheet).first).top;
    await tester.drag(find.byType(RoutexSheetHandle), const Offset(0, -200));
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byType(RoutexBottomSheet).first).top,
      lessThan(before),
      reason: '손잡이를 위로 끌면 시트가 커져야 한다',
    );
  });

  testWidgets('끝까지 줄여도 넘치지 않는다', (tester) async {
    // 실기기에서 "BOTTOM OVERFLOWED BY 21 PIXELS"로 나타났다. 머리말과 요약까지
    // 스크롤 밖에 고정하면, 시트를 줄였을 때 고정분이 시트보다 커진다.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _open(tester);
    // 손잡이를 바닥까지 끌어 최소 크기로 만든다.
    await tester.drag(find.byType(RoutexSheetHandle), const Offset(0, 2000));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('안내 시작을 누르면 true를 돌려주고 닫힌다', (tester) async {
    final result = await _open(tester);
    expect(find.text('안내 시작'), findsOneWidget);

    await tester.tap(find.text('안내 시작'));
    await tester.pumpAndSettle();

    expect(result(), isTrue);
    expect(find.text('안내 시작'), findsNothing);
  });

  testWidgets('뒤로 닫으면 아무것도 확정하지 않는다 — null이다', (tester) async {
    final result = await _open(tester);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();

    expect(result(), isNull);
  });
}
