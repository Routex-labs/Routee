import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/map/icon/category_icon.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/domain/route/dijkstra.dart';
import 'package:navigation_client/domain/store/nearby_stores.dart';
import 'package:navigation_client/models/place/store_index_entry.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/place_detail/place_detail_nearby_section.dart';

void main() {
  NearbyStore nearby(
    String name,
    double distanceM, {
    String floor = 'B2',
    String? category,
  }) => (
    store: StoreIndexEntry(
      id: name,
      name: name,
      floorId: 'floor',
      floorName: floor,
      category: category,
      subcategory: '카페·베이커리',
    ),
    reach: NodeReach(distanceM: distanceM, costM: distanceM),
  );

  Widget subject(Widget child) => MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  testWidgets('이름·층·거리를 한 줄에 그린다', (tester) async {
    await tester.pumpWidget(
      subject(
        PlaceNearbySection(stores: [nearby('탬버린즈', 24)], onSelect: (_) {}),
      ),
    );

    expect(find.text('근처 매장'), findsOneWidget);
    expect(find.text('탬버린즈'), findsOneWidget);
    // 층과 거리는 한 줄에 붙는다. 거리 문구는 검색 결과 목록과 같은 함수
    // (reachLabel)가 만든다.
    expect(find.textContaining('B2 · '), findsOneWidget);
    expect(find.textContaining('24'), findsOneWidget);
  });

  // "근처 매장 (없음)"은 정보가 아니라 고장으로 읽힌다.
  testWidgets('아이콘은 그 매장의 대분류 색을 쓴다', (tester) async {
    // 파랑 하나로 칠하던 자리다. 지도에서 그 매장 배지는 대분류 색인데 목록만
    // 파랑이면 같은 매장이 두 색으로 보인다.
    await tester.pumpWidget(
      subject(
        PlaceNearbySection(
          stores: [nearby('나스', 24, category: '뷰티')],
          onSelect: (_) {},
        ),
      ),
    );

    // subcategory가 `카페·베이커리`라 글리프는 커피잔이다(storeIconFor).
    final icon = tester.widget<Icon>(find.byIcon(Icons.local_cafe_outlined));
    expect(icon.color, categoryColorFor('뷰티'));
    expect(icon.color, isNot(AppColors.primary));
  });

  testWidgets('고를 것이 없으면 제목까지 그리지 않는다', (tester) async {
    await tester.pumpWidget(
      subject(const PlaceNearbySection(stores: [], onSelect: null)),
    );

    expect(find.text('근처 매장'), findsNothing);
  });

  testWidgets('줄을 누르면 그 매장을 알린다', (tester) async {
    StoreIndexEntry? picked;
    await tester.pumpWidget(
      subject(
        PlaceNearbySection(
          stores: [nearby('탬버린즈', 24)],
          onSelect: (store) => picked = store,
        ),
      ),
    );

    await tester.tap(find.text('탬버린즈'));
    await tester.pumpAndSettle();

    expect(picked?.name, '탬버린즈');
  });

  testWidgets('처음에는 세 매장만 보이고 나머지는 부드럽게 펼친다', (tester) async {
    await tester.pumpWidget(
      subject(
        PlaceNearbySection(
          stores: [
            for (var index = 0; index < 5; index++)
              nearby('매장 $index', 10.0 + index),
          ],
          onSelect: (_) {},
        ),
      ),
    );

    expect(find.text('매장 0'), findsOneWidget);
    expect(find.text('매장 2'), findsOneWidget);
    expect(find.text('매장 3'), findsNothing);
    expect(find.text('2개 더보기'), findsOneWidget);

    await tester.tap(find.text('2개 더보기'));
    await tester.pumpAndSettle();

    expect(find.text('매장 3'), findsOneWidget);
    expect(find.text('매장 4'), findsOneWidget);
    expect(find.text('접기'), findsOneWidget);
  });
}
