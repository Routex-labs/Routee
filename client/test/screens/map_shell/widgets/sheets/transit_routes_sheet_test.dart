import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/route/transit_route.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/transit_routes_sheet.dart';
import 'package:navigation_client/screens/outdoor_map/widgets/transit_summary_card.dart';
import 'package:navigation_client/widgets/sheet_header.dart';
import 'package:navigation_client/widgets/transit_itinerary_card.dart';
import 'package:navigation_client/widgets/transit_route_summary.dart';
import 'package:navigation_client/widgets/transit_timeline.dart';
import 'package:routex_design_system/routex_design_system.dart';

const _walkLeg = TransitLeg(
  mode: TransitMode.walk,
  sectionTimeSeconds: 300,
  distanceMeters: 380,
  points: [LatLng(37.5253, 126.9250), LatLng(37.5215, 126.9245)],
);

const _subwayLeg = TransitLeg(
  mode: TransitMode.subway,
  sectionTimeSeconds: 900,
  distanceMeters: 8000,
  points: [LatLng(37.5215, 126.9245), LatLng(37.5710, 126.9769)],
  routeName: '수도권5호선',
  routeColorHex: '#00A5DE',
  startName: '여의도역',
  endName: '광화문역',
  stationCount: 3,
);

const _busOnly = TransitItinerary(
  totalTimeSeconds: 1800,
  totalWalkTimeSeconds: 420,
  totalDistanceMeters: 11000,
  transferCount: 0,
  fare: 1600,
  legs: [
    TransitLeg(
      mode: TransitMode.bus,
      sectionTimeSeconds: 1380,
      distanceMeters: 10500,
      points: [LatLng(37.5250, 126.9240), LatLng(37.5660, 126.9775)],
      routeName: '간선:472',
      routeColorHex: '#0068B7',
    ),
  ],
);

const _withTransfer = TransitItinerary(
  totalTimeSeconds: 2400,
  totalWalkTimeSeconds: 600,
  totalDistanceMeters: 12000,
  transferCount: 1,
  fare: 1500,
  legs: [_walkLeg, _subwayLeg],
);

void main() {
  /// 카드를 눌렀을 때 지도로 나간 후보. 목록은 지도를 직접 안 그리므로, 이
  /// 콜백이 눌린 그 줄의 후보를 제때 내보내는지가 유일한 검증점이다.
  final previews = <TransitItinerary>[];

  /// chain 전체를 닫으라는 신호가 몇 번 갔는지. X 버튼을 없앤 뒤로 이 신호를
  /// 내는 길은 "고르지 않고 닫기"뿐이다.
  var closeAlls = 0;
  setUp(() {
    previews.clear();
    closeAlls = 0;
  });

  /// 결과 카드가 커져 기본 600px 뷰포트에는 한 장밖에 안 들어간다. `ListView`가
  /// 지연 생성이라 두 번째 줄은 위젯 자체가 안 만들어져, 높이를 안 키우면 이
  /// 파일의 단언이 "필터가 아니라 화면 높이"를 재게 된다.
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('경로마다 소요 시간·요금·노선·정류장을 함께 적는다', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: TransitRoutesSheet(
            routes: const TransitRoutes.ok([_busOnly, _withTransfer]),
            onCloseAll: () {},
            onPreview: previews.add,
          ),
        ),
      ),
    );
    await tester.pump();

    // 머리줄은 걷어냈다 — 도착지는 화면 위 길찾기 바가 이미 말하고, 제목·뒤로·X
    // 줄은 후보를 한 장 덜 보여 주는 값만 한다.
    expect(find.byType(SheetHeader), findsNothing);
    // 30분 / 40분 두 후보.
    expect(find.text('30분'), findsOneWidget);
    expect(find.text('40분'), findsOneWidget);
    // 첫 줄에만 "최적" — 배지 박스가 아니라 색 글자다.
    expect(find.text('최적'), findsOneWidget);
    expect(find.textContaining('1,600원'), findsOneWidget);
    // 버스 노선은 "간선:" 접두사를 떼고 번호만 남는다. 접두사를 적던 배지는
    // 없앴고(참조 캡처에 없다) 수단은 아이콘이 말한다.
    expect(find.text('472'), findsOneWidget);
    expect(find.text('수도권5호선'), findsOneWidget);
    // 승·하차 지점. 환승 횟수·도보 시간을 글자로 적던 자리는 구간 비율 막대가
    // 대신한다.
    expect(find.text('여의도역'), findsOneWidget);
    expect(find.text('광화문역'), findsOneWidget);
    // 카드는 늘 펼친 모양 하나다 — 접기 화살표는 두지 않는다.
    expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsNothing);
  });

  /// 목록을 모달로 띄우고, **닫힐 때 돌려준 후보를 읽는 손잡이**를 준다.
  Future<TransitItinerary? Function()> openSheet(WidgetTester tester) async {
    TransitItinerary? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await TransitRoutesSheet.show(
                  context,
                  routes: const TransitRoutes.ok([_busOnly, _withTransfer]),
                  onCloseAll: () => closeAlls++,
                  onPreview: previews.add,
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
    return () => picked;
  }

  testWidgets('카드를 누르면 그 자리에서 목록이 닫히고 그 후보가 확정된다', (tester) async {
    useTallViewport(tester);
    final picked = await openSheet(tester);

    await tester.tap(find.text('40분'));
    await tester.pumpAndSettle();

    // 상세 페이지를 한 겹 더 쌓지 않는다 — 지도 위 요약 카드와 겹치는 중첩
    // 시트를 만들던 옛 흐름이 이것이었다.
    expect(
      find.byType(TransitRoutesSheet),
      findsNothing,
      reason: '카드를 누르면 목록도 함께 닫혀야 요약 카드가 그 자리에 돌아온다',
    );
    expect(picked()?.totalTimeSeconds, 2400);
    expect(previews.single.totalTimeSeconds, 2400);
    expect(closeAlls, 0, reason: '고르고 닫는 것은 chain을 접으라는 뜻이 아니다');
  });

  testWidgets('아무것도 안 고르고 닫으면 chain 종료 신호가 간다', (tester) async {
    useTallViewport(tester);
    await openSheet(tester);

    // X 버튼이 하던 일이다. 머리줄을 걷어낸 뒤에는 바깥 탭·시스템 뒤로가기가
    // 그 신호를 대신 낸다 — 이 길까지 막히면 chain을 한 번에 닫을 문이 없다.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(TransitRoutesSheet), findsNothing);
    expect(closeAlls, 1);
  });

  testWidgets('필터로 좁힌 뒤 누르면 그 줄의 후보로 지도가 갈아탄다', (tester) async {
    useTallViewport(tester);
    final picked = await openSheet(tester);

    // 좁히기 전 첫 줄은 버스(30분)다. 지하철만 남기면 첫 줄이 40분으로 바뀐다.
    await tester.tap(find.text('지하철 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TransitItineraryCard).first);
    await tester.pumpAndSettle();

    expect(picked()?.totalTimeSeconds, 2400);
    expect(previews.single.totalTimeSeconds, 2400);
  });

  testWidgets('요약 카드는 후보 목록과 같은 막대로 말하고 안내 종료만 남긴다', (tester) async {
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: TransitSummaryCard(
            itinerary: _withTransfer,
            label: '여의도공원까지',
            onClose: () => closed = true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('40분'), findsOneWidget);
    expect(find.textContaining('1,500원'), findsOneWidget);
    // 후보 목록 카드와 **같은 막대**다. 확정 전후로 그림이 바뀌면 사용자는
    // 자기가 고른 그 경로가 맞는지 다시 확인해야 한다.
    expect(find.byType(TransitLegBar), findsOneWidget);
    // 환승 횟수·도보 시간을 나열하던 글과 노선 칩 스트립은 걷어냈다 — 막대가
    // 이미 그림으로 말한다.
    expect(find.byType(RoutexTransitItinerary), findsNothing);
    expect(find.textContaining('환승'), findsNothing);
    // 이동 수단을 고르는 자리는 상단 이동 수단 줄 하나다. 카드에 "도보"를 다시
    // 두면 같은 선택이 두 군데로 흩어진다.
    expect(find.textContaining('도보'), findsNothing);

    await tester.tap(find.text('안내 종료'));
    await tester.pump();
    expect(closed, isTrue);
  });

  testWidgets('요약 카드의 화살표는 세부 타임라인을 그 자리에 펼친다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: TransitSummaryCard(
            itinerary: _withTransfer,
            label: '여의도공원까지',
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 접힌 채로 시작한다 — 확정 직후 카드가 지도를 덮으면 경로가 안 보인다.
    expect(find.byType(TransitTimeline), findsNothing);

    await tester.tap(find.text('더보기'));
    await tester.pumpAndSettle();

    // 화면을 넘기지 않고 **그 자리에서** 펼친다.
    expect(find.byType(TransitTimeline), findsOneWidget);
    expect(find.text('여의도역'), findsOneWidget);
  });
}
