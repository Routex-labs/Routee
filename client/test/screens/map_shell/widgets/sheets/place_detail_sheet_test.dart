import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/domain/route/dijkstra.dart';
import 'package:navigation_client/models/place/favorite_place.dart';
import 'package:navigation_client/models/place/place_detail.dart';
import 'package:navigation_client/models/place/poi_search_result.dart';
import 'package:navigation_client/repositories/place/place_detail_repository.dart';
import 'package:navigation_client/state/favorites_controller.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../../../../support/routex_test_host.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/place_detail_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _favorite = FavoritePlace.fromPoiSearchResult(
  const PoiSearchResult(
    name: '테스트 매장',
    floor: '1F',
    point: LatLng(37.5, 127.0),
    placeId: 'place-1',
    nodeId: 'node-1',
  ),
  buildingId: 'building-1',
);

void main() {
  /// 시트가 떠 있는 채로 매장을 갈아 끼우는 테스트가 이 값을 바꾼다.
  late ValueNotifier<PlaceDetailTarget> target;

  setUp(() {
    target = ValueNotifier(
      const PlaceDetailTarget(
        title: '테스트 매장',
        subtitle: '1F',
        placeId: 'place-1',
      ),
    );
  });

  Widget buildSubject({
    PlaceDetailRepository? repository,
    VoidCallback? onCloseAll,
    String subtitle = '1F',
    String? subcategory,
    FavoritePlace? favorite,
    NodeReach? reach,
  }) {
    target.value = PlaceDetailTarget(
      title: '테스트 매장',
      subtitle: subtitle,
      placeId: 'place-1',
      subcategory: subcategory,
      favorite: favorite,
      reach: reach,
    );
    return appThemedHost(
      PlaceDetailSheet(
        target: target,
        buildingId: 'building-1',
        onCloseAll: onCloseAll ?? () {},
        repository: repository,
      ),
    );
  }

  testWidgets('상세를 불러오는 동안에도 코어와 길찾기 버튼을 즉시 그린다', (tester) async {
    final completer = Completer<PlaceDetail?>();
    await tester.pumpWidget(
      buildSubject(repository: _FakeRepository(completer.future)),
    );

    expect(find.text('테스트 매장'), findsOneWidget);
    expect(find.text('1F'), findsOneWidget);
    expect(find.text('출발'), findsOneWidget);
    expect(find.text('도착'), findsOneWidget);
    expect(find.byKey(const ValueKey('place-detail-loading')), findsOneWidget);
    // **동그란 로더여야 한다.** 예전엔 빈 회색 막대였는데, 그 위(이름·층·
    // 출발·도착)가 이미 다 차 있어서 기다리는 중인지 원래 그런 매장인지
    // 구분이 안 됐다. 돌아가는 것은 그 자체로 "지금 하는 중"을 말한다.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(_detailWithSummary());
    await tester.pumpAndSettle();

    expect(find.text(RoutexTypography.keepWordsWhole('상세 섹션')), findsOneWidget);
    expect(find.byKey(const ValueKey('place-detail-loading')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  // 사진을 어디서 가져올지는 이 앱이 정한다. Runtime Kit은 자산을 갖지 않아서
  // 경로가 아니라 ImageProvider를 받는다 — 그 변환이 여기서 끊기면 사진이 통째로
  // 사라지는데, 화면에는 "사진 없는 매장"과 똑같이 보인다.
  testWidgets('hero 섹션의 번들 경로가 순서대로 캐러셀 사진이 된다', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        repository: _FakeRepository(
          Future.value(
            _detail(
              sections: const [
                {
                  'type': 'hero',
                  'items': [
                    {'local_asset': 'assets/place_details/starbucks_01.jpg'},
                    {'local_asset': 'assets/place_details/starbucks_04.jpg'},
                  ],
                },
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final carousel = tester.widget<RoutexMediaCarousel>(
      find.byType(RoutexMediaCarousel),
    );
    expect(
      carousel.items.map((item) => (item.image as AssetImage).assetName),
      const [
        'assets/place_details/starbucks_01.jpg',
        'assets/place_details/starbucks_04.jpg',
      ],
    );
    expect(
      tester.getTopLeft(find.text('테스트 매장')).dy,
      lessThan(tester.getTopLeft(find.byType(RoutexMediaCarousel)).dy),
      reason: '장소 정보와 경로 행동이 대표 사진보다 먼저 보여야 한다',
    );
    expect(
      tester.getTopLeft(find.byType(RoutexPlaceActions)).dy,
      lessThan(tester.getTopLeft(find.byType(RoutexMediaCarousel)).dy),
      reason: '초기 시트 높이 안에 출발·도착이 먼저 들어와야 한다',
    );
  });

  // --- 설계 7-A-3·7-A-4 ---

  testWidgets('섹션이 0개여도 길찾기 버튼은 남는다', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        repository: _FakeRepository(Future.value(_detail(sections: const []))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('출발'), findsOneWidget);
    expect(find.text('도착'), findsOneWidget);
  });

  testWidgets('excluded는 섹션이 와도 본문을 그리지 않고 길찾기는 남긴다', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        repository: _FakeRepository(
          Future.value(_detailWithSummary(kind: 'excluded')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(RoutexTypography.keepWordsWhole('상세 섹션')), findsNothing);
    expect(find.text('출발'), findsOneWidget);
    expect(find.text('도착'), findsOneWidget);
  });

  // 라벨은 아이콘이 대신한다(설계 7-A-2). '주소'라는 글자가 아니라 장소 아이콘이
  // 떠야 하고, 값은 그대로 남는다.
  testWidgets('businessInfo는 라벨을 아이콘으로 바꿔 그린다', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        repository: _FakeRepository(
          Future.value(
            _detail(
              sections: const [
                {
                  'type': 'businessInfo',
                  'items': [
                    {'label': '주소', 'value': '서울특별시 영등포구 여의대로 108'},
                  ],
                },
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('매장 정보'), findsOneWidget);
    expect(find.text('주소'), findsNothing);
    expect(find.byIcon(Icons.place_outlined), findsOneWidget);
    expect(
      find.text(RoutexTypography.keepWordsWhole('서울특별시 영등포구 여의대로 108')),
      findsOneWidget,
    );
  });

  // 주소는 페이지 맨 아래로 내려가 소개와 떨어졌다. 둘은 각자 제목을 갖는다.
  testWidgets('소개와 매장 정보는 각각 제 제목을 갖는다', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        repository: _FakeRepository(
          Future.value(
            _detail(
              sections: const [
                {'type': 'summary', 'text': '한 줄 소개'},
                {
                  'type': 'businessInfo',
                  'items': [
                    {'label': '주소', 'value': '여의대로 108'},
                  ],
                },
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('매장 정보'), findsOneWidget);
    expect(find.text('소개'), findsOneWidget);
    expect(
      find.text(RoutexTypography.keepWordsWhole('한 줄 소개')),
      findsOneWidget,
    );
    expect(
      find.text(RoutexTypography.keepWordsWhole('여의대로 108')),
      findsOneWidget,
    );
  });

  // 메뉴가 30종까지 늘면서 한 줄로 이어 붙인 본문이 너무 길어졌다. 영업시간을 보려면
  // 메뉴를 한참 지나쳐야 했고, 반대도 마찬가지였다. 둘을 탭으로 나눈다.
  testWidgets('메뉴가 있으면 홈·메뉴 탭으로 나눈다', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        repository: _FakeRepository(
          Future.value(
            _detail(
              sections: const [
                {'type': 'summary', 'text': '한 줄 소개'},
                {
                  'type': 'menu',
                  'items': [
                    {'name': '카페 아메리카노'},
                  ],
                },
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('홈'), findsOneWidget);
    expect(find.text('메뉴'), findsOneWidget);
    // 처음엔 홈 탭. 메뉴 항목은 아직 그리지 않는다.
    expect(
      find.text(RoutexTypography.keepWordsWhole('한 줄 소개')),
      findsOneWidget,
    );
    expect(find.text('카페 아메리카노'), findsNothing);

    await tester.tap(find.text('메뉴'));
    await tester.pumpAndSettle();

    expect(find.text('카페 아메리카노'), findsOneWidget);
    expect(find.text(RoutexTypography.keepWordsWhole('한 줄 소개')), findsNothing);
  });

  // 탭 하나짜리 탭 바는 아무것도 나누지 않으면서 자리만 차지한다.
  testWidgets('메뉴가 없으면 탭을 만들지 않는다', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        repository: _FakeRepository(
          Future.value(
            _detail(
              sections: const [
                {'type': 'summary', 'text': '한 줄 소개'},
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('홈'), findsNothing);
    expect(
      find.text(RoutexTypography.keepWordsWhole('한 줄 소개')),
      findsOneWidget,
    );
  });

  // 지도 미리보기가 붙기 전까지 map 섹션은 층 이름만 적힌 중복 블록이다.
  // 그 층은 헤더 배지에 이미 있으므로 본문에 그리지 않는다.
  testWidgets('map 섹션은 본문에 그리지 않는다', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        repository: _FakeRepository(
          Future.value(
            _detail(
              sections: const [
                {'type': 'map', 'polygon_local_m': []},
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1F 위치'), findsNothing);
    // 층은 헤더 배지로 여전히 보인다.
    expect(find.text('1F'), findsOneWidget);
  });

  testWidgets('매장 정보가 없어도 소개는 제목을 갖는다', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        repository: _FakeRepository(Future.value(_detailWithSummary())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('소개'), findsOneWidget);
    expect(find.text('매장 정보'), findsNothing);
  });

  // 길찾기는 이름 바로 아래 한 줄에만 있다. 본문이 길어도 중복 없이 하나씩이어야
  // "언제든 길찾기"(F5)를 한 자리에서 지킨다.
  testWidgets('본문이 길어도 길찾기 버튼은 이름 아래 한 벌만 있다', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        repository: _FakeRepository(
          Future.value(
            _detail(
              sections: [
                for (var i = 0; i < 12; i++)
                  {'type': 'summary', 'text': '긴 본문 $i'},
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bar = find.byType(RoutexPlaceActions);
    expect(bar, findsOneWidget);

    // DraggableScrollableSheet는 첫 드래그를 시트 확장에 쓴다. 실제 본문 스크롤은
    // 시트가 maxChildSize에 닿은 뒤부터라서 두 번 끈다.
    final scrollable = find.byType(SingleChildScrollView);
    await tester.drag(scrollable, const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.drag(scrollable, const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(bar, findsOneWidget);
    // 상단에 복제본이 없으므로 버튼은 항상 하나씩이다.
    expect(find.text('출발'), findsOneWidget);
    expect(find.text('도착'), findsOneWidget);
  });

  // 이 시트는 스크롤 제스처를 이미 두 가지로 쓴다(위로 끌면 커지고, 끝에서
  // 아래로 끌면 닫힌다). 끝에서 내용이 늘어나는 표시까지 겹치면 "더 볼 게
  // 남았다"는 잘못된 신호가 된다.
  testWidgets('본문 끝에서 늘어나는 overscroll 표시를 그리지 않는다', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        repository: _FakeRepository(
          Future.value(
            _detail(
              sections: [
                for (var i = 0; i < 12; i++)
                  {'type': 'summary', 'text': '긴 본문 $i'},
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(StretchingOverscrollIndicator), findsNothing);
    expect(find.byType(GlowingOverscrollIndicator), findsNothing);
    // 표시만 끈 것이라 스크롤 자체는 그대로 동작해야 한다.
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  // **기대가 뒤집혔다.** 예전에는 상세 헤더가 목록과 같은 거리·도보 시간을 한 번 더
  // 적었고, 그 근거는 "목록에서 본 값을 상세에서도 같은 자리에 둔다"였다. 지금은
  // 반대로 정했다 — 비교해서 고를 때는 필요한 값이지만 **이미 고른 장소**의 상세에서
  // 같은 값을 반복하면 화면만 길어진다. 결정의 단일 출처는 공급 저장소의
  // place-detail-guidance-decisions.md이고, 거리는 검색 목록이 계속 말한다.
  group('상세 헤더가 반복하지 않는 것', () {
    testWidgets('거리를 알아도 도보 시간을 다시 적지 않는다', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          repository: _FakeRepository(Future.value(null)),
          reach: const NodeReach(distanceM: 124.4, costM: 124.4),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('도보'), findsNothing);
      expect(find.textContaining('124m'), findsNothing);
      // 층·업종 줄은 그대로다 — 그건 "어디인가"라서 상세에서도 필요하다.
      expect(find.textContaining('1F'), findsOneWidget);
    });
  });

  group('저장 토글', () {
    late FavoritesController original;

    setUp(() async {
      original = favoritesController;
      SharedPreferences.setMockInitialValues({});
      favoritesController = FavoritesController(
        prefs: await SharedPreferences.getInstance(),
      );
    });

    tearDown(() => favoritesController = original);

    testWidgets('X는 이름 줄에, 저장은 출발·도착 줄 오른쪽에 있다', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          favorite: _favorite,
          repository: _FakeRepository(Future.value(null)),
        ),
      );
      await tester.pumpAndSettle();

      final save = find.byTooltip('장소 저장');
      expect(save, findsOneWidget);
      expect(
        find.descendant(of: find.byType(RoutexPlaceHeader), matching: save),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(RoutexPlaceHeader),
          matching: find.byTooltip('닫기'),
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(save).dx,
        greaterThan(tester.getTopRight(find.text('도착')).dx),
      );
      expect(
        find.descendant(of: find.byType(RoutexPlaceActions), matching: save),
        findsNothing,
      );
    });

    testWidgets('저장할 대상이 없으면 상세 행동 줄에 토글을 그리지 않는다', (tester) async {
      await tester.pumpWidget(
        buildSubject(repository: _FakeRepository(Future.value(null))),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('장소 저장'), findsNothing);
      // 상세는 이전 시트를 쌓지 않으므로 같은 pop인 뒤로를 중복하지 않는다.
      expect(find.byTooltip('이전으로'), findsNothing);
      expect(find.byTooltip('닫기'), findsOneWidget);
    });

    testWidgets('저장을 눌러도 시트가 닫히지 않고 상태만 바뀐다', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          favorite: _favorite,
          repository: _FakeRepository(Future.value(null)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('장소 저장'), findsOneWidget);
      await tester.tap(find.byTooltip('장소 저장'));
      await tester.pumpAndSettle();

      // 시트는 그대로 있고, 토글만 저장됨 상태가 된다.
      expect(find.text('테스트 매장'), findsOneWidget);
      expect(find.byTooltip('저장 취소'), findsOneWidget);
      expect(favoritesController.contains(_favorite.key), isTrue);
    });

    Future<void> pumpSaved(WidgetTester tester) async {
      await tester.pumpWidget(
        buildSubject(
          favorite: _favorite,
          repository: _FakeRepository(Future.value(null)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('장소 저장'));
      await tester.pumpAndSettle();
    }

    // 이 시트는 Navigator에 얹힌 모달이라 SnackBar를 그리는 Scaffold가 아래에
    // 있다. 결과가 시트에 가려 보이지 않으면 아무 일도 안 일어난 것과 같다.
    testWidgets('저장 결과는 시트 안 알림 한 개로 알린다', (tester) async {
      await pumpSaved(tester);

      expect(find.byType(RoutexInlineNotice), findsOneWidget);
      expect(find.text('장소에 저장했습니다'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('다시 눌러도 알림은 한 개이고 문구만 바뀐다', (tester) async {
      await pumpSaved(tester);
      await tester.tap(find.byTooltip('저장 취소'));
      await tester.pumpAndSettle();

      expect(find.byType(RoutexInlineNotice), findsOneWidget);
      expect(find.text('저장을 해제했습니다'), findsOneWidget);
      expect(find.text('장소에 저장했습니다'), findsNothing);
    });

    // 되돌린 결과를 다시 알리면 한 번의 탭에 알림이 두 개가 된다. 바뀐 상태는
    // 헤더의 토글이 이미 말하고 있다.
    testWidgets('실행 취소는 저장을 되돌리고 알림을 걷는다', (tester) async {
      await pumpSaved(tester);
      await tester.tap(find.text('실행 취소'));
      await tester.pumpAndSettle();

      expect(favoritesController.contains(_favorite.key), isFalse);
      expect(find.byType(RoutexInlineNotice), findsNothing);
      expect(find.byTooltip('장소 저장'), findsOneWidget);
    });

    // 되돌릴 길이 여기뿐이 아니라 헤더 토글에도 있으므로 시간이 지나면 사라져도
    // 된다. 남겨 두면 본문 아래를 계속 가린다.
    testWidgets('알림은 시간이 지나면 사라진다', (tester) async {
      await pumpSaved(tester);

      await tester.pump(RoutexFeedbackTiming.noticeVisibility);
      await tester.pump();

      expect(find.byType(RoutexInlineNotice), findsNothing);
      expect(favoritesController.contains(_favorite.key), isTrue);
    });

    // 알림을 남겨 두면 되돌리기가 이전 장소가 아니라 지금 보고 있는 장소를
    // 토글한다. 문구와 손대는 대상이 어긋나는 자리다.
    testWidgets('다른 장소로 갈아 끼우면 이전 알림을 걷는다', (tester) async {
      await pumpSaved(tester);
      expect(find.byType(RoutexInlineNotice), findsOneWidget);

      target.value = const PlaceDetailTarget(
        title: '다른 매장',
        subtitle: 'B2',
        placeId: 'place-2',
      );
      await tester.pumpAndSettle();

      expect(find.byType(RoutexInlineNotice), findsNothing);
      // 알림만 걷힐 뿐 이전 장소의 저장은 그대로다.
      expect(favoritesController.contains(_favorite.key), isTrue);
    });
  });

  testWidgets('출발 버튼은 기존 StoreInfoAction 계약으로 닫힌다', (tester) async {
    StoreInfoAction? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await PlaceDetailSheet.show(
                context,
                target: target,
                buildingId: 'building-1',
                repository: _FakeRepository(Future.value(null)),
                onCloseAll: () {},
              );
            },
            child: const Text('열기'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('출발'));
    await tester.pumpAndSettle();

    expect(result, StoreInfoAction.setOrigin);
  });

  testWidgets('X는 전체 닫기 콜백을 호출하고 현재 시트를 닫는다', (tester) async {
    var closedAll = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => PlaceDetailSheet.show(
              context,
              target: target,
              buildingId: 'building-1',
              repository: _FakeRepository(Future.value(null)),
              onCloseAll: () => closedAll = true,
            ),
            child: const Text('열기'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();

    expect(closedAll, isTrue);
    expect(find.text('테스트 매장'), findsNothing);
  });

  testWidgets('상세 상단에는 같은 동작인 뒤로와 닫기를 함께 두지 않는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => PlaceDetailSheet.show(
              context,
              target: target,
              buildingId: 'building-1',
              repository: _FakeRepository(Future.value(null)),
              onCloseAll: () {},
            ),
            child: const Text('열기'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('이전으로'), findsNothing);
    expect(find.byTooltip('닫기'), findsOneWidget);
  });

  // --- 헤더: 카테고리 아이콘 + 층 pill ---

  testWidgets('층이 없으면 pill을 그리지 않는다', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        subtitle: '',
        subcategory: '카페·베이커리',
        repository: _FakeRepository(Future.value(null)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('카페·베이커리'), findsOneWidget);
    expect(find.text('1F'), findsNothing);
  });

  testWidgets('층도 업종도 없으면 이름만 남는다', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        subtitle: '',
        repository: _FakeRepository(Future.value(null)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('테스트 매장'), findsOneWidget);
  });

  testWidgets('영어 subcategory는 한글 라벨로 바꿔 그린다', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        subcategory: 'restroom',
        repository: _FakeRepository(Future.value(null)),
      ),
    );
    await tester.pumpAndSettle();

    // 층과 한 줄로 합쳐 그리므로 부분 일치로 본다.
    expect(find.textContaining('화장실'), findsOneWidget);
    expect(find.textContaining('restroom'), findsNothing);
  });

  // **장식용 매장 아이콘을 뺐다.** 예전에는 이름 앞에 분류 색을 입힌 44 사각형이
  // 있었고, 목록에서 보던 글리프를 상세에서도 같은 자리에 두려는 것이었다. 상세는
  // 이미 그 장소만 보여 주는 화면이라 "무엇을 눌렀는지" 확인시킬 이유가 없다.
  // 근거는 위 group과 같은 결정 문서다.
  testWidgets('이름 앞에 장식용 분류 아이콘을 두지 않는다', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        subcategory: '카페·베이커리',
        repository: _FakeRepository(Future.value(null)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.local_cafe_outlined), findsNothing);
    expect(find.byIcon(Icons.restaurant), findsNothing);
    expect(find.byIcon(Icons.storefront), findsNothing);
    // 이름과 층·업종은 그대로다.
    expect(find.text('테스트 매장'), findsOneWidget);
  });

  group('떠 있는 채로 갈아 끼우기', () {
    // 다른 매장을 눌러도 시트를 떼었다 붙이지 않는다. 떼는 순간 아무것도 없는
    // 프레임이 생겨 번쩍인다(실기기에서 확인).
    testWidgets('이름·층은 즉시 바뀌고 본문은 새 상세가 올 때까지 남는다', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          repository: _FakeRepository(Future.value(_detailWithSummary())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('테스트 매장'), findsOneWidget);
      expect(
        find.text(RoutexTypography.keepWordsWhole('상세 섹션')),
        findsOneWidget,
      );

      final next = Completer<PlaceDetail?>();
      // 다음 요청이 늦게 오는 상황을 만든다.
      target.value = const PlaceDetailTarget(
        title: '다른 매장',
        subtitle: 'B2',
        placeId: 'place-2',
      );
      await tester.pump();

      // 머리는 즉시 바뀐다.
      expect(find.text('다른 매장'), findsOneWidget);
      expect(find.text('테스트 매장'), findsNothing);
      // **본문은 아직 이전 것이다** — 비우면 그 빈 구간이 번쩍임이 된다.
      expect(
        find.text(RoutexTypography.keepWordsWhole('상세 섹션')),
        findsOneWidget,
      );
      next.complete(null);
    });

    // 손잡이 아래에서 도는 원은 "시트가 통째로 바뀌는 중"으로 읽힌다. 갈아 끼울
    // 때는 이전 본문이 그대로 떠 있어 알릴 기다림이 없다 — 결정과 근거는
    // `docs/client/kakao-map-indoor-observation.md`의 "교체할 때 로딩 표시를
    // 두지 않는다".
    testWidgets('갈아 끼울 때는 로딩 표시를 두지 않는다', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          repository: _FakeRepository(
            Completer<PlaceDetail?>().future,
            byPlaceId: {'place-1': Future.value(_detailWithSummary())},
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 처음 열 때는 뜬다 — 그때는 보여 줄 본문이 아직 없다.
      expect(find.byKey(const ValueKey('place-detail-loading')), findsNothing);

      // 두 번째 매장의 응답은 영영 오지 않는다. 그동안에도 로딩 줄은 없어야 한다.
      target.value = const PlaceDetailTarget(
        title: '다른 매장',
        subtitle: 'B2',
        placeId: 'place-2',
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('place-detail-loading')), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('늦게 온 이전 매장의 상세는 버린다', (tester) async {
      final first = Completer<PlaceDetail?>();
      await tester.pumpWidget(
        buildSubject(
          repository: _FakeRepository(
            Completer<PlaceDetail?>().future,
            byPlaceId: {'place-1': first.future},
          ),
        ),
      );
      await tester.pump();

      target.value = const PlaceDetailTarget(
        title: '다른 매장',
        subtitle: 'B2',
        placeId: 'place-2',
      );
      await tester.pump();

      // 첫 매장의 응답이 이제야 도착한다. 이미 남의 자리다.
      first.complete(_detailWithSummary());
      await tester.pumpAndSettle();

      expect(find.text('다른 매장'), findsOneWidget);
      expect(find.text(RoutexTypography.keepWordsWhole('상세 섹션')), findsNothing);
    });
  });

  group('처음 올라오는 높이', () {
    // 이름·층·출발·도착까지만 보이면 된다. 화면 절반(0.5)이던 시절에는 매장을
    // 바꿔 누를 때마다 그만큼 내려갔다 올라와 눈이 피로했다.
    test('내용 높이를 화면 비율로 환산한다', () {
      // 큰 폰(Galaxy S23 ≈ 1029dp): 이름·버튼에 사진 윗부분까지.
      expect(placeDetailSheetInitialSize(1029), closeTo(0.333, 0.005));
      // 예전 고정값(0.5)보다 확실히 낮다 — 이동 거리가 그만큼 줄었다.
      expect(placeDetailSheetInitialSize(1029), lessThan(0.4));
    });

    test('짧은 화면에서는 비율이 커진다 — 버튼이 잘리면 안 된다', () {
      // **비율로 고정했다가 실제로 깨진 적이 있다.** 0.25로 박았더니 600dp
      // 화면에서 출발·도착이 화면 밖으로 밀려 위젯 테스트 17건이 실패했다.
      // 담을 내용의 높이는 화면 크기와 무관하게 거의 고정이다.
      expect(
        placeDetailSheetInitialSize(600),
        greaterThan(placeDetailSheetInitialSize(1029)),
      );
      // 큰 화면에서는 요구한 높이를 그대로 채운다.
      expect(
        placeDetailSheetInitialSize(1029) * 1029,
        closeTo(kPlaceDetailSheetPeekPx, 1),
      );
    });

    test('아주 짧은 화면에서는 상한이 이겨 내용이 잘린다', () {
      // 600dp에서 343px는 화면의 57%다. 그대로 두면 지도가 거의 안 남으므로
      // **상한(0.5)이 이긴다** — 내용 일부가 잘리는 쪽을 택한 것이고, 잘린
      // 만큼은 끌어올려 본다. 이 절충을 모르고 상한을 올리면 작은 화면에서
      // 시트가 지도를 통째로 덮는다.
      expect(placeDetailSheetInitialSize(600), 0.5);
    });

    test('아주 짧은 화면에서도 절반을 넘지 않는다', () {
      // 상한이 없으면 작은 화면에서 시트가 지도를 통째로 덮는다.
      expect(placeDetailSheetInitialSize(300), lessThanOrEqualTo(0.5));
      expect(placeDetailSheetInitialSize(1), lessThanOrEqualTo(0.5));
    });

    test('화면 높이가 0이어도 터지지 않는다', () {
      // 첫 프레임 전 MediaQuery가 0을 줄 수 있다. 0으로 나누면 Infinity가 되고
      // DraggableScrollableSheet가 그 자리에서 assert로 죽는다.
      expect(placeDetailSheetInitialSize(0), 0.5);
    });
  });
}

class _FakeRepository implements PlaceDetailRepository {
  _FakeRepository(this.response, {this.byPlaceId});

  final Future<PlaceDetail?> response;

  /// 매장마다 다른 응답을 주고 싶을 때. 갈아 끼우기 테스트는 **요청마다 다른
  /// Future**여야 "늦게 온 이전 응답"을 만들 수 있다.
  final Map<String, Future<PlaceDetail?>>? byPlaceId;

  @override
  Future<PlaceDetail?> getPlaceDetail(String buildingId, String placeId) =>
      byPlaceId?[placeId] ?? response;
}

PlaceDetail _detail({
  required List<Map<String, dynamic>> sections,
  String kind = 'store',
  String source = 'manual',
  String? updatedAt,
}) => PlaceDetail.fromJson({
  'kind': kind,
  'id': 'place-1',
  'name': '테스트 매장',
  'subtitle': '1F',
  'category': null,
  'subcategory': null,
  'location': {
    'building_id': 'building-1',
    'floor_label': '1F',
    'position_local_m': {'x': 0, 'y': 0},
    'entrance_node_id': null,
  },
  'actions': [],
  'sections': sections,
  'provenance': {'source': source, 'updated_at': updatedAt},
});

PlaceDetail _detailWithSummary({
  String kind = 'store',
  String source = 'manual',
  String? updatedAt,
}) => _detail(
  kind: kind,
  source: source,
  updatedAt: updatedAt,
  sections: const [
    {'type': 'summary', 'text': '상세 섹션'},
  ],
);
