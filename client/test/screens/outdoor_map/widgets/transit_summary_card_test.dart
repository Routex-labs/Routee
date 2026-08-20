import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/route/transit_route.dart';
import 'package:navigation_client/screens/outdoor_map/widgets/transit_summary_card.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/widgets/transit_route_summary.dart';
import 'package:navigation_client/widgets/transit_timeline.dart';
import 'package:routex_design_system/routex_design_system.dart';

const _point = LatLng(37.5253, 126.9250);

const _walk = TransitLeg(
  mode: TransitMode.walk,
  sectionTimeSeconds: 300,
  distanceMeters: 380,
  points: [_point, _point],
);

const _bus = TransitLeg(
  mode: TransitMode.bus,
  sectionTimeSeconds: 600,
  distanceMeters: 5000,
  points: [_point, _point],
  routeName: '간선:472',
  startName: '여의도환승센터',
  endName: '공덕역',
  stationCount: 3,
  stopNames: ['여의도환승센터', '국회의사당', '마포대교남단', '공덕역'],
);

const _oneTransfer = TransitItinerary(
  totalTimeSeconds: 2400,
  totalWalkTimeSeconds: 600,
  totalDistanceMeters: 12000,
  transferCount: 1,
  fare: 1500,
  legs: [_walk, _bus],
);

/// 환승 3회. 옛 칩 스트립은 여기서 두 줄로 접혀 카드가 그만큼 높아졌다.
const _threeTransfers = TransitItinerary(
  totalTimeSeconds: 4200,
  totalWalkTimeSeconds: 900,
  totalDistanceMeters: 22000,
  transferCount: 3,
  fare: 1850,
  legs: [_walk, _bus, _walk, _bus, _walk, _bus, _walk, _bus, _walk],
);

void main() {
  var closed = false;

  setUp(() => closed = false);

  Future<void> pump(
    WidgetTester tester,
    TransitItinerary itinerary, {
    bool guiding = true,
  }) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: TransitSummaryCard(
                  itinerary: itinerary,
                  label: '여의도공원까지',
                  onClose: () => closed = true,
                  onStartGuidance: guiding ? null : () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double height(WidgetTester tester) =>
      tester.getSize(find.byType(TransitSummaryCard)).height;

  testWidgets('후보 목록과 같은 구간 막대를 쓴다 — 칩 스트립은 없다', (tester) async {
    await pump(tester, _oneTransfer);

    expect(find.byType(TransitLegBar), findsOneWidget);
    expect(find.byType(RoutexTransitItinerary), findsNothing);
  });

  testWidgets('소요와 요금만 적고 환승·도보 나열은 걷어낸다', (tester) async {
    await pump(tester, _oneTransfer);

    expect(find.text('40분'), findsOneWidget);
    expect(find.text('1,500원'), findsOneWidget);
    // 막대가 이미 도보와 환승을 그림으로 말한다. 같은 것을 글로 다시 적으면
    // 사용자가 지적한 "장황한 글 설명"이 된다.
    expect(find.textContaining('환승'), findsNothing);
    expect(find.textContaining('도보'), findsNothing);
  });

  testWidgets('화살표를 펼치면 전체 경로 세부가 나오고 다시 접힌다', (tester) async {
    await pump(tester, _oneTransfer);

    expect(find.byType(TransitTimeline), findsNothing, reason: '접힌 채로 시작해야 지도가 보인다');
    expect(find.byIcon(RoutexIcons.expand), findsOneWidget);

    await tester.tap(find.text('더보기'));
    await tester.pumpAndSettle();

    expect(find.byType(TransitTimeline), findsOneWidget);
    expect(find.text('여의도환승센터'), findsOneWidget);
    expect(find.text('도보 5분'), findsOneWidget);

    await tester.tap(find.text('접기'));
    await tester.pumpAndSettle();

    expect(find.byType(TransitTimeline), findsNothing);
  });

  testWidgets('안내 전에도 같은 막대와 펼치기를 쓰고 안내 시작·도착 시각은 그대로다', (
    tester,
  ) async {
    await pump(tester, _oneTransfer, guiding: false);

    expect(find.byType(TransitLegBar), findsOneWidget);
    expect(find.byType(RoutexTransitItinerary), findsNothing);
    expect(find.text('안내 시작'), findsOneWidget);
    // 도착 예정 줄의 제목. 이 카드의 존재 이유라 남긴다.
    expect(find.text('여의도공원까지'), findsOneWidget);

    await tester.tap(find.text('더보기'));
    await tester.pumpAndSettle();
    expect(find.byType(TransitTimeline), findsOneWidget);
  });

  testWidgets('환승이 늘어도 접힌 카드는 높아지지 않는다', (tester) async {
    await pump(tester, _oneTransfer);
    final one = height(tester);
    await pump(tester, _threeTransfers);

    // 막대는 구간 수와 무관하게 한 줄이다. 카드가 높아지면 카메라 여백
    // (`_fitCameraToPoints`)이 그만큼 밀려 경로가 덜 보인다.
    expect(height(tester), one);
  });

  testWidgets('펼친 카드도 화면을 다 덮지 않는다', (tester) async {
    await pump(tester, _threeTransfers);
    final collapsed = height(tester);

    await tester.tap(find.text('더보기'));
    await tester.pumpAndSettle();

    expect(height(tester), greaterThan(collapsed));
    expect(height(tester), lessThan(800 * 0.75));
    expect(tester.takeException(), isNull);
  });

  testWidgets('요금을 모르면 요금 칸을 그리지 않는다', (tester) async {
    const noFare = TransitItinerary(
      totalTimeSeconds: 2400,
      totalWalkTimeSeconds: 600,
      totalDistanceMeters: 12000,
      transferCount: 1,
      legs: [_walk, _bus],
    );
    await pump(tester, noFare);

    expect(find.textContaining('원'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('도보만인 경로도, 총 소요가 0인 경로도 던지지 않는다', (tester) async {
    const walkOnly = TransitItinerary(
      totalTimeSeconds: 600,
      totalWalkTimeSeconds: 600,
      totalDistanceMeters: 700,
      transferCount: 0,
      legs: [_walk],
    );
    await pump(tester, walkOnly);
    expect(find.byType(TransitLegBar), findsOneWidget);
    expect(tester.takeException(), isNull);

    const zero = TransitItinerary(
      totalTimeSeconds: 0,
      totalWalkTimeSeconds: 0,
      totalDistanceMeters: 0,
      transferCount: 0,
      legs: [_walk],
    );
    await pump(tester, zero);
    await tester.tap(find.text('더보기'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('안내 종료는 그대로 남는다', (tester) async {
    await pump(tester, _oneTransfer);

    await tester.tap(find.text('안내 종료'));
    await tester.pump();

    expect(closed, isTrue);
  });
}
