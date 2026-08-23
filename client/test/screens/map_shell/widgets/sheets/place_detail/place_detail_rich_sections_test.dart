import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routex_design_system/routex_design_system.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/core/clipboard_confirmation.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/place_detail/place_detail_rich_sections.dart';

void main() {
  Widget subject(Widget child) => MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  group('Place rich detail renderers', () {
    // 한 줄에 이름·영문명·설명·가격이 다 오면 무엇이 제목인지 흐려진다. 영문명은
    // 골라서 팝업을 연 사람에게만 필요하다.
    testWidgets('menu row drops the english name and keeps the description', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          const PlaceMenuSection(
            items: [
              PlaceMenuItem(
                name: '리저브 콜드 브루',
                nameEn: 'Reserve Cold Brew',
                description: '깊고 부드러운 풍미의 커피',
                volume: '355ml',
                calories: '5kcal',
                caffeine: '190mg',
                imageAssetPath: 'assets/place_details/starbucks_menu_94.jpg',
              ),
            ],
          ),
        ),
      );

      expect(find.text('메뉴'), findsOneWidget);
      expect(find.text('리저브 콜드 브루'), findsOneWidget);
      expect(find.text('깊고 부드러운 풍미의 커피'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      // 줄에는 없다. 여기가 새면 제목이 다시 흐려진 것이다.
      expect(find.text('Reserve Cold Brew'), findsNothing);
      expect(find.textContaining('355ml'), findsNothing);
      expect(find.textContaining('5kcal'), findsNothing);
    });

    // 가격은 설명 아래에 온다. 지금 데이터에는 없지만 자리는 계약으로 고정한다 —
    // 공식 가격 출처가 생기면 데이터만 채우면 되게.
    testWidgets('menu row shows the price under the description', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          const PlaceMenuSection(
            items: [
              PlaceMenuItem(
                name: '카페 아메리카노',
                description: '진한 에스프레소와 물',
                price: '4,700원',
              ),
            ],
          ),
        ),
      );

      expect(find.text('4,700원'), findsOneWidget);
    });

    // 배지는 줄에 있고, 알레르기는 팝업에 있다. 자리가 갈리는 이유는 쓰임이
    // 달라서다 — 배지는 훑으면서 고르는 단서고, 알레르기는 하나를 고른 다음
    // 확인하는 값이다. 알레르기를 줄에 올리면 316줄 중 122줄만 한 줄 더 길어진다.
    testWidgets('menu row shows badges and the popup shows allergens', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          const PlaceMenuSection(
            items: [
              PlaceMenuItem(
                name: '씨솔트 카라멜 콜드 브루',
                description: '단짠단짠 조합의 콜드 브루',
                allergens: '우유',
                badges: ['NEW', '시즌 한정'],
              ),
            ],
          ),
        ),
      );

      expect(find.text('NEW'), findsOneWidget);
      expect(find.text('시즌 한정'), findsOneWidget);
      // 줄에는 없다.
      expect(find.text('우유'), findsNothing);

      await tester.tap(find.text('씨솔트 카라멜 콜드 브루'));
      await tester.pumpAndSettle();

      expect(find.text('알레르기'), findsOneWidget);
      expect(find.text('우유'), findsOneWidget);
    });

    // 배지 색은 종류마다 다르다. 한 줄에 둘이 나란히 뜨는 항목이 있어서, 같은 색이면
    // 두 배지가 한 덩어리로 읽힌다. 모르는 배지는 색을 못 고르는 것이 아니라 무채색으로
    // 떨어진다 — 색은 정보를 더하는 장치이지 그리기 위한 조건이 아니다.
    test('배지 색은 종류마다 다르고 모르는 배지는 색을 갖지 않는다', () {
      final newAccent = badgeAccentFor('NEW')!;
      final seasonAccent = badgeAccentFor('시즌 한정')!;

      expect(newAccent.ink, const Color(0xFF1E7B45));
      expect(seasonAccent.ink, const Color(0xFFB4600F));
      expect(newAccent.surface, isNot(seasonAccent.surface));
      // 색을 못 고르는 것이 아니라 무채색으로 떨어진다. 그 판단은 Runtime Kit이
      // 한다 — 여기서는 색을 넘기지 않는다는 사실만 잠근다.
      expect(badgeAccentFor('한정 판매'), isNull);

      // 표기가 흔들려도 같은 색으로 간다. 공백 하나 때문에 색이 사라지면
      // 데이터가 아니라 화면을 의심하게 된다.
      expect(badgeAccentFor('시즌한정')!.ink, seasonAccent.ink);
      expect(badgeAccentFor('new')!.ink, newAccent.ink);
    });

    // 알레르기만 있고 설명·영양정보가 없는 항목도 팝업을 연다. `hasDetail`이
    // 알레르기를 안 세면 이런 항목은 눌러도 아무 일이 없는데, 화면상으로는 다른
    // 줄과 똑같이 보인다.
    testWidgets('a row with only allergens is still tappable', (tester) async {
      await tester.pumpWidget(
        subject(
          const PlaceMenuSection(
            items: [PlaceMenuItem(name: '카페 라떼', allergens: '우유')],
          ),
        ),
      );

      await tester.tap(find.text('카페 라떼'));
      await tester.pumpAndSettle();

      expect(find.text('알레르기'), findsOneWidget);
    });

    // 배지만 있는 항목은 팝업을 열지 않는다. 상세를 못 받은 4종이 정확히 그 모양인데,
    // 열어 봐야 줄에 이미 있는 이름과 배지만 다시 나온다.
    testWidgets('a row with only badges does not open a popup', (tester) async {
      await tester.pumpWidget(
        subject(
          const PlaceMenuSection(
            items: [
              PlaceMenuItem(name: '바나나 마카다미아 오트 프라푸치노', badges: ['NEW']),
            ],
          ),
        ),
      );

      await tester.tap(find.text('바나나 마카다미아 오트 프라푸치노'));
      await tester.pumpAndSettle();

      expect(find.text('닫기'), findsNothing);
    });

    // 알레르기 값은 `땅콩 / 대두 / 우유 / 알류 / 밀 / 오징어`처럼 27자까지 온다.
    // 팝업 폭이 340이라 감싸지 않으면 RenderFlex 오버플로가 난다 — 그 경우
    // 테스터가 예외를 잡아 이 테스트가 실패한다.
    testWidgets('a long allergen line does not overflow the popup', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          const PlaceMenuSection(
            items: [
              PlaceMenuItem(
                name: '햄 & 루꼴라 샌드위치',
                allergens: '땅콩 / 대두 / 우유 / 알류 / 밀 / 오징어',
              ),
            ],
          ),
        ),
      );

      await tester.tap(find.text('햄 & 루꼴라 샌드위치'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('땅콩 / 대두 / 우유 / 알류 / 밀 / 오징어'), findsOneWidget);
    });

    testWidgets('tapping a card opens the detail popup', (tester) async {
      await tester.pumpWidget(
        subject(
          const PlaceMenuSection(
            items: [
              PlaceMenuItem(
                name: '리저브 콜드 브루',
                nameEn: 'Reserve Cold Brew',
                description: '깊고 부드러운 풍미의 커피',
                volume: '355ml',
                calories: '5kcal',
                caffeine: '190mg',
              ),
            ],
          ),
        ),
      );

      await tester.tap(find.text('리저브 콜드 브루'));
      await tester.pumpAndSettle();

      expect(
        find.text(RoutexTypography.keepWordsWhole('깊고 부드러운 풍미의 커피')),
        findsOneWidget,
      );
      expect(find.text('355ml'), findsOneWidget);
      expect(find.text('5kcal'), findsOneWidget);
      expect(find.text('190mg'), findsOneWidget);
      expect(find.text('용량'), findsOneWidget);
    });

    // 푸드에는 영양정보가 없다. 라벨만 남은 빈 표를 그리면 "정보가 없다"가 아니라
    // "못 불러왔다"로 읽힌다.
    testWidgets('popup omits the nutrition block when there is none', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          const PlaceMenuSection(
            items: [PlaceMenuItem(name: '플레인 베이글', description: '담백한 베이글')],
          ),
        ),
      );

      await tester.tap(find.text('플레인 베이글'));
      await tester.pumpAndSettle();

      expect(
        find.text(RoutexTypography.keepWordsWhole('담백한 베이글')),
        findsOneWidget,
      );
      expect(find.text('용량'), findsNothing);
      expect(find.text('칼로리'), findsNothing);
      expect(find.text('카페인'), findsNothing);
    });

    // 눌렀는데 카드에 이미 있는 이름만 다시 나오는 팝업은 막다른 길이다. 한 번
    // 겪으면 다음 카드도 안 누르게 되므로 아예 안 눌리게 한다.
    testWidgets('a card with nothing more to show is not tappable', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          const PlaceMenuSection(
            items: [PlaceMenuItem(name: '오늘의 커피', nameEn: 'Coffee of the Day')],
          ),
        ),
      );

      await tester.tap(find.text('오늘의 커피'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
    });

    // 카드 높이를 상수로 박아 두면 기기 글자 크기 설정이 커졌을 때 넘친다. 실제로
    // `BOTTOM OVERFLOWED BY 2.0 PIXELS`가 떴다.
    testWidgets('menu card does not overflow at a large text scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: const Scaffold(
              body: SingleChildScrollView(
                child: PlaceMenuSection(
                  items: [
                    PlaceMenuItem(
                      name: '초콜릿 크림 칩 프라푸치노',
                      nameEn: 'Chocolate Cream Chip Frappuccino',
                      volume: '355ml',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    // 메뉴 사진은 402x420이라 폭에 맞춰 채우면 세로가 42% 잘린다. 잘린 사진은
    // 아무도 못 알아채므로(컵 윗부분이 원래 그런 줄 안다) 계약으로 고정한다.
    testWidgets('menu photo is not cropped', (tester) async {
      await tester.pumpWidget(
        subject(
          const PlaceMenuSection(
            items: [
              PlaceMenuItem(
                name: '카페 아메리카노',
                imageAssetPath: 'assets/place_details/starbucks_menu_94.jpg',
              ),
            ],
          ),
        ),
      );

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.fit, BoxFit.contain);

      // 사진 영역이 원본 비율(402/420)을 따라야 여백도 잘림도 없다.
      final box = tester.getSize(find.byType(Image));
      expect(box.width / box.height, closeTo(402 / 420, 0.01));
    });

    // 세로 목록이라 줄이 늘어날수록 다른 섹션이 화면 밖으로 밀린다. 상한을 넘는
    // 만큼은 더보기 뒤로 보낸다.
    testWidgets('a category over the cap gets a 더보기 row', (tester) async {
      await tester.pumpWidget(
        subject(
          PlaceMenuSection(
            items: [
              for (var index = 0; index < 6; index++)
                PlaceMenuItem(name: '메뉴 $index', description: '설명 $index'),
            ],
          ),
        ),
      );

      // 남은 개수를 적는다 — 근처 매장 줄과 같은 규칙이다. 접혀 있을 때만 세고,
      // 펼친 뒤에는 이미 보이는 것을 다시 세지 않는다.
      expect(find.text('2개 더보기'), findsOneWidget);
      expect(find.text('메뉴 0'), findsOneWidget);
      expect(find.text('메뉴 4'), findsNothing);
    });

    testWidgets('a category within the cap has no 더보기 row', (tester) async {
      await tester.pumpWidget(
        subject(
          PlaceMenuSection(
            items: [
              for (var index = 0; index < 4; index++)
                PlaceMenuItem(name: '메뉴 $index'),
            ],
          ),
        ),
      );

      expect(find.textContaining('더보기'), findsNothing);
    });

    // 팝업으로 띄우지 않고 그 자리에서 펼친다. 목록을 보러 팝업을 여는 것은
    // 목록을 두 번 만드는 일이다.
    testWidgets('더보기 expands the rest in place', (tester) async {
      await tester.pumpWidget(
        subject(
          PlaceMenuSection(
            items: [
              for (var index = 0; index < 6; index++)
                PlaceMenuItem(name: '메뉴 $index', description: '설명 $index'),
            ],
          ),
        ),
      );

      await tester.tap(find.text('2개 더보기'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      for (var index = 0; index < 6; index++) {
        expect(find.text('메뉴 $index'), findsOneWidget);
      }
      // 다 펼치면 그 줄이 돌아가는 길이 된다. 펼쳐 놓고 나가지 못하면 메뉴 하나
      // 보려던 사람이 여섯 줄을 지나 다음 섹션으로 가야 한다.
      expect(find.textContaining('더보기'), findsNothing);
      expect(find.text('접기'), findsOneWidget);

      await tester.tap(find.text('접기'));
      await tester.pumpAndSettle();

      expect(find.text('메뉴 5'), findsNothing);
      expect(find.text('2개 더보기'), findsOneWidget);
    });

    // 탭을 옮기면 다시 접는다. 카테고리마다 펼침 상태를 들고 있으면, 돌아왔을 때
    // 어디까지 펼쳤는지 기억나지 않는 목록이 열려 있다.
    testWidgets('changing the category collapses the list again', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          PlaceMenuSection(
            items: [
              for (var index = 0; index < 6; index++)
                PlaceMenuItem(name: '리저브 $index', category: '리저브'),
              PlaceMenuItem(name: '아메리카노', category: '에스프레소'),
            ],
          ),
        ),
      );

      await tester.tap(find.text('2개 더보기'));
      await tester.pumpAndSettle();
      expect(find.text('리저브 5'), findsOneWidget);

      await tester.tap(find.text('에스프레소'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('리저브').last);
      await tester.pumpAndSettle();

      expect(find.text('2개 더보기'), findsOneWidget);
      expect(find.text('리저브 5'), findsNothing);
    });

    // 갈래(음료·푸드)는 카테고리 위 단계다. 공식 사이트가 둘을 다른 페이지로
    // 나누는 것과 같은 구조다.
    testWidgets('groups split the menu above the category tabs', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          const PlaceMenuSection(
            items: [
              PlaceMenuItem(name: '카페 라떼', group: '음료', category: '에스프레소'),
              PlaceMenuItem(name: '콜드 브루', group: '음료', category: '콜드 브루'),
              PlaceMenuItem(name: '플레인 베이글', group: '푸드', category: '브레드'),
            ],
          ),
        ),
      );

      expect(find.text('음료'), findsOneWidget);
      expect(find.text('푸드'), findsOneWidget);
      // 첫 갈래가 기본. 푸드 항목은 아직 안 보인다.
      expect(find.text('카페 라떼'), findsOneWidget);
      expect(find.text('플레인 베이글'), findsNothing);

      await tester.tap(find.text('푸드'));
      await tester.pumpAndSettle();

      expect(find.text('플레인 베이글'), findsOneWidget);
      expect(find.text('카페 라떼'), findsNothing);
      // 갈래 안에 카테고리가 하나뿐이면 카테고리 탭은 만들지 않는다.
      expect(find.text('브레드'), findsNothing);
    });

    // 검색창은 메뉴가 한 화면에 안 들어올 때만 의미가 있다.
    testWidgets('search field appears only when the menu is long', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          PlaceMenuSection(
            items: [
              for (var index = 0; index < 5; index++)
                PlaceMenuItem(name: '메뉴 $index'),
            ],
          ),
        ),
      );

      expect(find.byType(TextField), findsNothing);
    });

    // 바깥 상자가 이미 배경과 모서리를 갖고 있어서 안쪽 입력칸에는 테두리가 없어야
    // 한다. `border`만 끄면 포커스됐을 때 테마의 focusedBorder가 살아나 상자 안에
    // 상자가 하나 더 그려진다 — 눈으로 봐야만 보이던 종류의 회귀라 값으로 고정한다.
    testWidgets('search field draws no border in any state', (tester) async {
      await tester.pumpWidget(
        subject(
          PlaceMenuSection(
            items: [
              for (var index = 0; index < 24; index++)
                PlaceMenuItem(name: '메뉴 $index'),
            ],
          ),
        ),
      );

      final decoration = tester
          .widget<TextField>(find.byType(TextField))
          .decoration!;

      expect(decoration.border, InputBorder.none);
      expect(decoration.focusedBorder, InputBorder.none);
      expect(decoration.enabledBorder, InputBorder.none);
      expect(decoration.filled, isFalse);
    });

    // 키보드가 올라오면 검색창을 보이는 자리로 올린다. 이 시트는 화면 비율로 크기가
    // 정해져 키보드에 덮인 아래쪽이 그대로 남으므로, 스크롤로 끌어올려 주지 않으면
    // 자기가 친 글자가 안 보인다.
    testWidgets('search field scrolls itself above the keyboard', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      // 키보드는 **화면(view)의 viewInsets**로 흉내 낸다. MediaQuery 위젯을 씌워
      // 바꾸면 MaterialApp이 화면에서 만든 자기 MediaQuery가 그 위를 덮어서 값이
      // 위젯에 닿지 않는다.
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 600);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            // 상세 시트와 같은 조건을 만든다. 시트는 화면 비율로 크기가 정해져
            // 키보드가 올라와도 **줄어들지 않는다** — Scaffold가 알아서 줄여 주면
            // Flutter 기본 동작이 대신 스크롤해 버려서, 이 테스트가 검증하려는
            // 코드가 없어도 통과한다.
            resizeToAvoidBottomInset: false,
            body: Builder(
              builder: (context) => SingleChildScrollView(
                controller: controller,
                // 실제 시트와 같은 규칙 — 키보드 높이만큼 아래를 비워 스크롤할
                // 길이를 만든다. 이게 없으면 올릴 자리가 없다.
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: Column(
                  children: [
                    // 검색창을 화면 아래쪽(키보드에 덮일 자리)에 두되 탭할 수는
                    // 있어야 한다. 테스트 뷰포트는 800×600이다.
                    const SizedBox(height: 400),
                    PlaceMenuSection(
                      items: [
                        for (var index = 0; index < 24; index++)
                          PlaceMenuItem(name: '메뉴 $index'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(controller.offset, 0);

      // 눌러서 포커스만 준 시점에는 아직 키보드가 없다. 여기서 스크롤해 버리면
      // 키보드가 올라온 뒤 다시 가려진다.
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      final afterFocus = controller.offset;

      // 키보드가 올라온다.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();

      expect(
        controller.offset,
        greaterThan(afterFocus),
        reason: '키보드가 올라온 뒤 검색창을 위로 올려야 한다',
      );
    });

    testWidgets('search narrows by name and english name', (tester) async {
      await tester.pumpWidget(
        subject(
          PlaceMenuSection(
            items: [
              for (var index = 0; index < 24; index++)
                PlaceMenuItem(name: '메뉴 $index'),
              const PlaceMenuItem(name: '카페 라떼', nameEn: 'Caffe Latte'),
            ],
          ),
        ),
      );

      expect(find.byType(TextField), findsOneWidget);

      // 영문명으로도 찾힌다. 띄어쓰기·대소문자는 무시한다.
      await tester.enterText(find.byType(TextField), 'caffelatte');
      await tester.pumpAndSettle();

      expect(find.text('카페 라떼'), findsOneWidget);
      expect(find.text('메뉴 0'), findsNothing);
    });

    // 찾는 것이 없을 때 빈 화면을 두면 앱이 멈춘 줄 안다.
    testWidgets('search tells the user when nothing matches', (tester) async {
      await tester.pumpWidget(
        subject(
          PlaceMenuSection(
            items: [
              for (var index = 0; index < 24; index++)
                PlaceMenuItem(name: '메뉴 $index'),
            ],
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '없는메뉴');
      await tester.pumpAndSettle();

      expect(find.text('찾는 메뉴가 없습니다'), findsOneWidget);
    });

    testWidgets('menu tabs filter items by category in server order', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          const PlaceMenuSection(
            items: [
              PlaceMenuItem(name: '리저브 콜드 브루', category: '리저브'),
              PlaceMenuItem(name: '카페 아메리카노', category: '에스프레소'),
              PlaceMenuItem(name: '카페 라떼', category: '에스프레소'),
            ],
          ),
        ),
      );

      // 첫 탭이 기본 선택. 다른 탭의 메뉴는 아직 그려지지 않는다.
      expect(find.text('리저브'), findsOneWidget);
      expect(find.text('에스프레소'), findsOneWidget);
      expect(find.text('리저브 콜드 브루'), findsOneWidget);
      expect(find.text('카페 아메리카노'), findsNothing);

      await tester.tap(find.text('에스프레소'));
      await tester.pumpAndSettle();

      expect(find.text('카페 아메리카노'), findsOneWidget);
      expect(find.text('카페 라떼'), findsOneWidget);
      expect(find.text('리저브 콜드 브루'), findsNothing);
    });

    // 가진 것만 탭에 넣으면 카테고리 없는 항목은 어느 탭에서도 안 보인다. 화면에는
    // 아무 이상이 없어 보이는 채로 메뉴가 사라지는 쪽이 더 나쁘다.
    testWidgets('menu tabs are dropped when any item lacks a category', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          const PlaceMenuSection(
            items: [
              PlaceMenuItem(name: '리저브 콜드 브루', category: '리저브'),
              PlaceMenuItem(name: '오늘의 커피'),
            ],
          ),
        ),
      );

      expect(find.text('리저브'), findsNothing);
      expect(find.text('리저브 콜드 브루'), findsOneWidget);
      expect(find.text('오늘의 커피'), findsOneWidget);
    });

    // 누를 곳이 하나뿐인 탭은 아무것도 나누지 않으면서 자리만 차지한다.
    testWidgets('a single category renders no tab', (tester) async {
      await tester.pumpWidget(
        subject(
          const PlaceMenuSection(
            items: [
              PlaceMenuItem(name: '리저브 콜드 브루', category: '리저브'),
              PlaceMenuItem(name: '리저브 나이트로', category: '리저브'),
            ],
          ),
        ),
      );

      expect(find.text('리저브'), findsNothing);
      expect(find.text('리저브 콜드 브루'), findsOneWidget);
      expect(find.text('리저브 나이트로'), findsOneWidget);
    });

    testWidgets('demo info renders rows without any date', (tester) async {
      await tester.pumpWidget(
        subject(
          const PlaceDemoInfoSection(
            items: [
              PlaceDemoInfo(
                label: '영업시간',
                value: '화~목 10:30-20:00',
              ),
              PlaceDemoInfo(
                label: '주차',
                value: '주차 지원 불가',
              ),
            ],
          ),
        ),
      );

      expect(find.text('영업 정보'), findsOneWidget);
      expect(find.byIcon(Icons.schedule_outlined), findsOneWidget);
      expect(find.byIcon(Icons.local_parking_outlined), findsOneWidget);
      // 확인일은 값을 다시 확인할 근거이지 읽는 사람이 무언가를 정하는 데 쓰는
      // 값이 아니다. 줄마다 날짜가 붙으면 세 줄짜리 섹션이 여섯 줄이 된다.
      expect(find.textContaining('확인'), findsNothing);
      expect(find.textContaining('2026-'), findsNothing);
      // 라벨은 아이콘이 대신하므로 글자로 남지 않는다.
      expect(find.text('영업시간'), findsNothing);
    });

    // `1522-3232`는 매장 직통이 아니라 전국 고객센터 번호다. 아이콘이 라벨을
    // 삼키면 화면에 남는 건 번호뿐이고, 그때 값은 사라진 게 아니라 **틀린 값이
    // 된다.** 그래서 이 줄만 라벨 글자를 남긴다.
    testWidgets('the customer-centre row keeps its label as text', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          const PlaceDemoInfoSection(
            items: [
              PlaceDemoInfo(
                label: '고객센터',
                value: '1522-3232 (평일 09:00–18:00)',
              ),
              PlaceDemoInfo(
                label: '주차',
                value: '주차 지원 불가',
              ),
            ],
          ),
        ),
      );

      expect(find.text('고객센터'), findsOneWidget);
      expect(find.byIcon(Icons.support_agent_outlined), findsOneWidget);
      // 매장 직통 번호가 아니므로 일반 수화기 아이콘을 쓰지 않는다.
      expect(find.byIcon(Icons.call_outlined), findsNothing);
      // 복사 버튼은 전화 줄에만 붙는다.
      expect(find.text('복사'), findsOneWidget);
    });

    testWidgets(
      'copying the phone number puts only the number on the clipboard',
      (tester) async {
        // 기기 조회에 기대지 않는다 — 이 테스트가 보려는 것은 "무엇이
        // 복사되나"이지 "누가 알리나"가 아니다.
        setClipboardAnnouncementForTest(true);
        addTearDown(() => setClipboardAnnouncementForTest(null));
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String?;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );

        await tester.pumpWidget(
          subject(
            const PlaceDemoInfoSection(
              items: [
                PlaceDemoInfo(
                  label: '고객센터',
                  value: '1522-3232 (평일 09:00–18:00)',
                ),
              ],
            ),
          ),
        );

        await tester.tap(find.text('복사'));
        // 복사 뒤 "우리가 알려야 하나"를 한 번 물어보므로(Android 13+는 시스템이
        // 대신 띄운다) 토스트는 한 프레임 늦게 붙는다.
        await tester.pumpAndSettle();

        // 부연(영업시간)까지 함께 복사하면 전화 앱에 붙여 넣을 수 없다.
        expect(copied, '1522-3232');
        expect(find.text('복사했습니다'), findsOneWidget);

        // 토스트는 스스로 사라진다. 남은 타이머를 흘려보내지 않으면 테스트가
        // 대기 중인 타이머로 실패한다.
        await tester.pump(const Duration(seconds: 2));
        expect(find.text('복사했습니다'), findsNothing);
      },
    );

    // 시스템이 이미 확인 UI를 띄우는 기기(Android 13+)에서는 우리가 침묵한다.
    // 실기기에서 "복사했습니다"가 두 번 겹쳐 보였다.
    testWidgets('시스템이 알리는 기기에서는 앱 토스트를 띄우지 않는다', (tester) async {
      setClipboardAnnouncementForTest(false);
      addTearDown(() => setClipboardAnnouncementForTest(null));
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.pumpWidget(
        subject(
          const PlaceDemoInfoSection(
            items: [
              PlaceDemoInfo(
                label: '고객센터',
                value: '1522-3232',
              ),
            ],
          ),
        ),
      );

      await tester.tap(find.text('복사'));
      await tester.pumpAndSettle();

      expect(find.text('복사했습니다'), findsNothing);
    });

    // 클립보드는 웹·리눅스에서 막힐 수 있다. 조용히 삼키면 사용자는 복사된 줄 안다.
    testWidgets('a failing clipboard says so instead of pretending', (
      tester,
    ) async {
      setClipboardAnnouncementForTest(true);
      addTearDown(() => setClipboardAnnouncementForTest(null));
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            throw PlatformException(code: 'unavailable');
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.pumpWidget(
        subject(
          const PlaceDemoInfoSection(
            items: [
              PlaceDemoInfo(
                label: '고객센터',
                value: '1522-3232 (평일 09:00–18:00)',
              ),
            ],
          ),
        ),
      );

      await tester.tap(find.text('복사'));
      await tester.pumpAndSettle();

      expect(find.text('복사하지 못했습니다'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    // 값 안에 날짜(2026-08-10)가 있는 줄에 복사 버튼이 붙으면 안 된다. 값이 아니라
    // 라벨로 먼저 거르는 이유다.
    testWidgets('non-phone rows never get a copy button', (tester) async {
      await tester.pumpWidget(
        subject(
          const PlaceDemoInfoSection(
            items: [
              PlaceDemoInfo(
                label: '영업시간',
                value: '화~목 10:30–20:00 (2026-08-10 월요일 휴점)',
              ),
            ],
          ),
        ),
      );

      expect(find.text('복사'), findsNothing);
    });

    // 웹사이트 줄만 라벨 대신 주소를 보여 준다. `공식 사이트`는 어느 사이트인지를
    // 말해 주지 않지만 `페이스북`은 라벨이 곧 정체다.
    testWidgets('links render as an SNS list with brand badges', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          const PlaceLinksSection(
            items: [
              PlaceLinkItem(
                label: '공식 사이트',
                url: 'https://www.starbucks.co.kr/index.do',
              ),
              PlaceLinkItem(
                label: '페이스북',
                url: 'https://www.facebook.com/starbuckskorea',
              ),
              PlaceLinkItem(
                label: '인스타그램',
                url: 'https://www.instagram.com/starbuckskorea',
              ),
              PlaceLinkItem(
                label: '스마트스토어',
                url: 'https://brand.naver.com/starbucks',
              ),
            ],
          ),
        ),
      );

      expect(find.text('SNS'), findsOneWidget);
      // 첫 줄은 라벨이 아니라 주소다.
      expect(find.text('공식 사이트'), findsNothing);
      expect(find.text('https://www.starbucks.co.kr/index.do'), findsOneWidget);
      expect(find.text('페이스북'), findsOneWidget);
      expect(find.text('인스타그램'), findsOneWidget);
      expect(find.text('스마트스토어'), findsOneWidget);
      // 네 줄이 다 그려졌는지는 줄마다 하나씩 붙는 `>`로 센다.
      expect(find.byIcon(Icons.chevron_right), findsNWidgets(4));
      expect(find.byIcon(Icons.open_in_new), findsNothing);
      expect(find.byIcon(Icons.public), findsOneWidget);
      expect(find.byIcon(Icons.facebook), findsOneWidget);
    });

    // 라벨은 사람이 쓰는 자유 문자열이라 언제든 빠지거나 처음 보는 값이 온다.
    testWidgets('an unknown or missing link label still renders a row', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          const PlaceLinksSection(
            items: [
              PlaceLinkItem(label: '', url: 'https://example.com/a'),
              PlaceLinkItem(label: '블로그', url: 'https://example.com/b'),
            ],
          ),
        ),
      );

      // 라벨이 없으면 주소가 대신 선다.
      expect(find.text('https://example.com/a'), findsOneWidget);
      expect(find.text('블로그'), findsOneWidget);
      expect(find.byIcon(Icons.link), findsNWidgets(2));
      expect(find.byIcon(Icons.chevron_right), findsNWidgets(2));
    });

    // 회색 기본 배지로 떨어지던 두 줄이다. 유튜브는 정확히 일치하는 가지가 없었고,
    // `네이버 브랜드스토어`는 공백을 지워도 `스마트스토어`와 글자가 달랐다.
    testWidgets('youtube and naver brand store get their own badges', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          const PlaceLinksSection(
            items: [
              PlaceLinkItem(
                label: '유튜브',
                url: 'https://www.youtube.com/channel/abc',
              ),
              PlaceLinkItem(
                label: '네이버 브랜드스토어',
                url: 'https://brand.naver.com/osulloc',
              ),
            ],
          ),
        ),
      );

      expect(find.byIcon(Icons.smart_display), findsOneWidget);
      expect(find.byIcon(Icons.storefront), findsOneWidget);
      expect(find.byIcon(Icons.link), findsNothing);
    });

    // 앞에 매장 이름이 붙은 웹사이트 라벨은 이름이 정보라 주소 위에 남는다.
    // 이름 없는 `공식 사이트`가 주소만 보여 주는 것과 갈리는 지점이다.
    testWidgets('a named website label keeps the label above the url', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          const PlaceLinksSection(
            items: [
              PlaceLinkItem(
                label: '오설록 공식 홈페이지',
                url: 'https://www.osulloc.com/kr/ko',
              ),
            ],
          ),
        ),
      );

      expect(find.text('오설록 공식 홈페이지'), findsOneWidget);
      expect(find.text('https://www.osulloc.com/kr/ko'), findsOneWidget);
    });

    // 서버가 번들 자산을 지정하면 배지가 그 그림이 된다. 지정하지 않은 줄은
    // 그대로 Material 아이콘이라, 한 목록에 둘이 섞여도 괜찮아야 한다.
    testWidgets('an icon asset replaces the brand badge', (tester) async {
      await tester.pumpWidget(
        subject(
          const PlaceLinksSection(
            items: [
              PlaceLinkItem(
                label: '오설록 공식 홈페이지',
                url: 'https://www.osulloc.com/kr/ko',
                iconAsset: 'assets/place_details/osulloc_favicon.png',
              ),
              PlaceLinkItem(
                label: '인스타그램',
                url: 'https://www.instagram.com/osulloc_official/',
              ),
            ],
          ),
        ),
      );

      final image = tester.widget<Image>(find.byType(Image));
      expect(
        (image.image as AssetImage).assetName,
        'assets/place_details/osulloc_favicon.png',
      );
      // 자산을 준 줄만 그림이고, 나머지는 아이콘 그대로다.
      expect(find.byIcon(Icons.public), findsNothing);
      expect(find.byIcon(Icons.camera_alt), findsOneWidget);
    });

    // 아주 긴 주소가 와도 줄 높이가 흔들리면 안 된다.
    testWidgets('a long url is clipped to one line', (tester) async {
      await tester.pumpWidget(
        subject(
          PlaceLinksSection(
            items: [
              PlaceLinkItem(
                label: '공식 사이트',
                url: 'https://www.starbucks.co.kr/${'very-long-path/' * 20}end',
              ),
            ],
          ),
        ),
      );

      final text = tester.widget<Text>(find.textContaining('very-long-path'));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
    });

    // 열기 실패는 **시트 위에** 떠야 한다.
    //
    // 예전에는 `ScaffoldMessenger`의 SnackBar였는데, 상세 시트는 Navigator에 얹힌
    // 모달이라 SnackBar를 그리는 Scaffold보다 위에 있다. 그래서 실패 문구가 시트
    // 뒤에 그려져 **한 번도 보이지 않았다** — 눌렀는데 아무 일도 안 일어난 것과
    // 구분되지 않았다. 같은 파일의 복사 버튼만 오버레이 토스트를 쓰고 있었다.
    testWidgets('링크를 열지 못하면 시트에 가리지 않는 알림으로 말한다', (tester) async {
      // 위젯 테스트에는 플러그인이 등록되지 않아 기본 MethodChannel 구현이 탄다.
      // `false`는 "열지 못했다"이고, 이때만 알림이 뜬다.
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => false,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          theme: AppTheme.light,
          home: const Scaffold(body: SizedBox.expand()),
        ),
      );

      unawaited(
        showModalBottomSheet<void>(
          context: navigatorKey.currentContext!,
          builder: (_) => const PlaceLinksSection(
            items: [
              PlaceLinkItem(
                label: '인스타그램',
                url: 'https://www.instagram.com/starbuckskorea',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('인스타그램'));
      await tester.pumpAndSettle();

      expect(find.text('인스타그램을(를) 열지 못했습니다'), findsOneWidget);
      // 루트 Overlay에 얹힌 토스트다. 시트 아래에 그려지는 SnackBar가 아니다.
      expect(RoutexToast.isVisible, isTrue);
      expect(find.byType(SnackBar), findsNothing);

      // 토스트는 스스로 사라진다. 남은 타이머를 흘려보내지 않으면 테스트가
      // 대기 중인 타이머로 실패한다.
      await tester.pump(RoutexToast.visibleDuration);
      expect(find.text('인스타그램을(를) 열지 못했습니다'), findsNothing);
    });

    testWidgets('business information replaces the label with an icon', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          const PlaceBusinessInfoSection(
            items: [PlaceBusinessInfo(label: '주소', value: '서울 영등포구 여의대로 108')],
          ),
        ),
      );

      expect(find.text('매장 정보'), findsOneWidget);
      expect(find.byIcon(Icons.place_outlined), findsOneWidget);
      expect(find.text('주소'), findsNothing);
      expect(
        find.text(RoutexTypography.keepWordsWhole('서울 영등포구 여의대로 108')),
        findsOneWidget,
      );
    });

    // 데이터는 사람이 쓰는 자유 문자열이라 언제든 새 라벨이 들어온다. 아무 아이콘이나
    // 물리면 그 값이 무슨 뜻인지가 화면에서 사라지므로, 모르는 라벨은 글자로 남긴다.
    testWidgets('an unmapped label keeps its text', (tester) async {
      await tester.pumpWidget(
        subject(
          const PlaceBusinessInfoSection(
            items: [PlaceBusinessInfo(label: '반려동물 동반', value: '가능')],
          ),
        ),
      );

      expect(find.text('반려동물 동반'), findsOneWidget);
      expect(find.text(RoutexTypography.keepWordsWhole('가능')), findsOneWidget);
    });

    testWidgets('contact keeps the phone label and drops the checked date', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(const PlaceContactSection(tel: '02-3277-0132')),
      );

      // 줄이 하나뿐이라 섹션 제목을 두지 않는다. `연락처`와 `전화번호`가 같은 말을
      // 두 번 하면서 38dp를 쓰던 자리다.
      expect(find.text('연락처'), findsNothing);
      expect(find.byIcon(Icons.call_outlined), findsOneWidget);
      // 아이콘만으로는 누가 받는 번호인지 말하지 못한다.
      expect(find.text('전화번호'), findsOneWidget);
      // 확인일은 값을 다시 확인할 근거이지 읽을 정보가 아니다. 한 줄짜리 섹션이
      // 날짜 때문에 두 줄이 되면 정작 정할 것("이 번호로 걸까")이 흐려진다.
      expect(find.textContaining('확인'), findsNothing);
      // 복사 버튼을 두지 않는다. 48dp 상자가 줄을 부풀려 라벨과 숫자 사이가
      // 벌어지고, 이 화면에서 하려는 일은 복사가 아니라 거는 것이다.
      expect(find.text('복사'), findsNothing);
    });

    // 눌리기는 눌렸지만 그럴 낌새가 화면에 없으면, 번호를 눈으로만 읽고 지나간다.
    // ripple은 누른 뒤에야 보이므로 표시가 되지 못한다.
    testWidgets('전화번호 줄은 누를 수 있다는 표시를 SNS 줄과 같은 꺾쇠로 둔다', (tester) async {
      await tester.pumpWidget(
        subject(const PlaceContactSection(tel: '02-3277-0132')),
      );

      expect(find.byIcon(RoutexIcons.forward), findsOneWidget);
      // 수화기를 한 번 더 그리지는 않는다 — 왼쪽 아이콘과 겹쳐 보여 무엇이 눌리는
      // 자리인지 흐려진다.
      expect(find.byIcon(Icons.call_outlined), findsOneWidget);
    });

    testWidgets('tapping the contact row dials the number as shown', (
      tester,
    ) async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      String? launched;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'launch') {
          launched = (call.arguments as Map)['url'] as String?;
        }
        return true;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      await tester.pumpWidget(
        subject(
          const PlaceContactSection(tel: '02-3277-0132'),
        ),
      );

      // 복사 버튼도 InkWell이라 타입으로 찾으면 둘이 걸린다. 줄 안쪽,
      // 복사 버튼 밖에 있는 수화기 아이콘을 누른다.
      await tester.tap(find.byIcon(Icons.call_outlined));
      await tester.pumpAndSettle();

      // 구분기호를 지우지 않는다. 화면에 보이는 번호와 걸리는 번호가 같아야
      // 무엇이 걸렸는지 확인할 수 있다.
      expect(launched, 'tel:02-3277-0132');
    });

    // 눌렀는데 아무 일도 없으면 앱이 멈춘 줄 안다. 다이얼러가 없는 기기에서도
    // 실패했다는 사실만은 알린다.
    testWidgets('전화를 걸지 못하면 시트에 가리지 않는 알림으로 말한다', (tester) async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => false,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          theme: AppTheme.light,
          home: const Scaffold(body: SizedBox.expand()),
        ),
      );

      unawaited(
        showModalBottomSheet<void>(
          context: navigatorKey.currentContext!,
          builder: (_) => const PlaceContactSection(tel: '02-3277-0132'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.call_outlined));
      await tester.pumpAndSettle();

      expect(find.text('전화를 걸지 못했습니다'), findsOneWidget);
      // 루트 Overlay에 얹힌 토스트다. 시트 아래에 그려지는 SnackBar가 아니다.
      expect(find.byType(SnackBar), findsNothing);

      // 토스트는 스스로 사라진다. 남은 타이머를 흘려보내지 않으면 테스트가
      // 대기 중인 타이머로 실패한다.
      await tester.pump(RoutexToast.visibleDuration);
      expect(find.text('전화를 걸지 못했습니다'), findsNothing);
    });

    // 서버는 번호·출처·확인일이 다 있을 때만 섹션을 만든다. 그 계약이 여기까지
    // 오는 길에 끊겨도 빈 줄이 남지는 않아야 한다.
    testWidgets('an empty number renders nothing', (tester) async {
      await tester.pumpWidget(
        subject(const PlaceContactSection(tel: '')),
      );

      expect(find.byIcon(Icons.call_outlined), findsNothing);
      expect(find.text('전화번호'), findsNothing);
    });
  });
}
