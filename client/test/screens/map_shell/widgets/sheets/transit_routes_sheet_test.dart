import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/route/transit_route.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/transit_route_detail_sheet.dart';
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
            destinationLabel: '여의도공원',
            onCloseAll: () {},
            onPreview: previews.add,
          ),
        ),
      ),
    );
    await tester.pump();

    // 머리줄은 걷어냈다 — 도착지는 화면 위 길찾기 바가 이미 말하고, 제목·뒤로·X
    // 줄은 후보를 한 장 덜 보여 주는 값만 한다.
    expect(find.text('여의도공원까지 대중교통'), findsNothing);
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
  ///
  /// 진짜 라우트로 띄우는 이유는 상세가 그 위에 한 겹 더 쌓이는지, 시스템
  /// 뒤로가기가 위 한 겹만 벗기는지를 봐야 하기 때문이다.
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
                  destinationLabel: '여의도공원',
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

  /// 상세 안의 `안내 시작`. 뒤에 깔린 화면에도 같은 글자가 있을 수 있어
  /// 상세 안으로 범위를 좁힌다.
  final startInDetail = find.descendant(
    of: find.byType(TransitRouteDetailSheet),
    matching: find.text('안내 시작'),
  );

  testWidgets('카드를 누르면 상세가 열릴 뿐 목록은 닫히지 않는다', (tester) async {
    useTallViewport(tester);
    final picked = await openSheet(tester);

    await tester.tap(find.text('40분'));
    await tester.pumpAndSettle();

    expect(find.byType(TransitRouteDetailSheet), findsOneWidget);
    expect(
      find.byType(TransitRoutesSheet),
      findsOneWidget,
      reason: '목록이 닫히면 다른 후보로 돌아올 길이 없다',
    );
    expect(picked(), isNull, reason: '상세를 여는 것만으로 경로가 확정되면 견주는 단계가 사라진다');
    // 확정은 아니지만 지도는 갈아탄다 — 자동차 후보와 같은 그림이다.
    expect(previews.single.totalTimeSeconds, 2400);
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

  testWidgets('상세를 뒤로 닫으면 아무것도 고르지 않은 채 목록에 남는다', (tester) async {
    useTallViewport(tester);
    final picked = await openSheet(tester);

    await tester.tap(find.text('40분'));
    await tester.pumpAndSettle();
    // 시스템 뒤로가기는 위 한 겹만 벗긴다.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(TransitRouteDetailSheet), findsNothing);
    expect(find.byType(TransitRoutesSheet), findsOneWidget);
    expect(picked(), isNull);
  });

  testWidgets('견줘 본 뒤 안내 시작을 누른 그 경로를 돌려준다', (tester) async {
    useTallViewport(tester);
    final picked = await openSheet(tester);

    // 첫 경로를 열어 보고 뒤로 나온다.
    await tester.tap(find.text('30분'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // 두 번째 경로를 열어 안내를 시작한다. 돌아오는 것은 **나중에 고른 쪽**이다.
    await tester.tap(find.text('40분'));
    await tester.pumpAndSettle();
    await tester.tap(startInDetail);
    await tester.pumpAndSettle();

    expect(find.byType(TransitRouteDetailSheet), findsNothing);
    expect(
      find.byType(TransitRoutesSheet),
      findsNothing,
      reason: '고른 뒤에는 목록도 함께 닫힌다',
    );
    expect(picked()?.totalTimeSeconds, 2400);
    // 훑는 동안 지도도 같은 순서로 따라왔다.
    expect([for (final item in previews) item.totalTimeSeconds], [1800, 2400]);
    expect(closeAlls, 0, reason: '고르고 닫는 것은 chain을 접으라는 뜻이 아니다');
  });

  testWidgets('필터로 좁힌 뒤 누르면 그 줄의 후보로 지도가 갈아탄다', (tester) async {
    useTallViewport(tester);
    final picked = await openSheet(tester);

    // 좁히기 전 첫 줄은 버스(30분)다. 지하철만 남기면 첫 줄이 40분으로 바뀐다 —
    // 인덱스를 원본 목록에서 세면 여기서 30분짜리가 열린다.
    await tester.tap(find.text('지하철 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TransitItineraryCard).first);
    await tester.pumpAndSettle();
    await tester.tap(startInDetail);
    await tester.pumpAndSettle();

    expect(picked()?.totalTimeSeconds, 2400);
    // 인덱스를 원본 목록에서 세면 여기로 30분짜리가 나간다.
    expect(previews.single.totalTimeSeconds, 2400);
  });

  testWidgets('상세를 열었다 닫아도 좁혀 둔 필터가 그대로다', (tester) async {
    useTallViewport(tester);
    await openSheet(tester);

    await tester.tap(find.text('지하철 1'));
    await tester.pumpAndSettle();
    expect(find.byType(TransitItineraryCard), findsOneWidget);

    await tester.tap(find.byType(TransitItineraryCard).first);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // 목록이 전체로 되돌아가면 방금 좁힌 일이 없던 셈이 된다.
    expect(find.byType(TransitItineraryCard), findsOneWidget);
    expect(find.text('30분'), findsNothing);
  });

  testWidgets('상세 위 시스템 뒤로가기는 루트의 뒤로가기 사다리까지 내려가지 않는다', (tester) async {
    useTallViewport(tester);
    // 루트 화면의 PopScope 자리. 실제 앱에서는 여기에 검색·안내·종료 확인으로
    // 이어지는 다섯 겹 사다리가 걸려 있다 - 상세를 닫는 뒤로가기가 여기 닿으면
    // 상세만이 아니라 그 아래 상태까지 한 겹 벗겨진다.
    var rootPops = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PopScope(
          canPop: false,
          onPopInvokedWithResult: (_, _) => rootPops++,
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => TransitRoutesSheet.show(
                  context,
                  routes: const TransitRoutes.ok([_busOnly, _withTransfer]),
                  destinationLabel: '여의도공원',
                  onCloseAll: () {},
                  onPreview: previews.add,
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('40분'));
    await tester.pumpAndSettle();
    expect(find.byType(TransitRouteDetailSheet), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(TransitRouteDetailSheet), findsNothing);
    expect(find.byType(TransitRoutesSheet), findsOneWidget);
    expect(rootPops, 0, reason: '상세를 닫는 뒤로가기가 루트 사다리까지 샜다');
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

  testWidgets('요약 카드의 화살표는 상세와 같은 세부 설명을 그 자리에 펼친다', (tester) async {
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

    // 화면을 넘기지 않고 **그 자리에서** 펼친다. 상세 화면과 같은 위젯이라
    // 두 화면이 같은 말을 한다.
    expect(find.byType(TransitTimeline), findsOneWidget);
    expect(find.byType(TransitRouteDetailSheet), findsNothing);
    expect(find.text('여의도역'), findsOneWidget);
  });
}
