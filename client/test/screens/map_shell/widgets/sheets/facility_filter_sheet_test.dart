/// 시설 시트의 **계약**: 제목·목록이 지금 층을 따라가고, 고른 종류가 그대로
/// 상위(지도 강조)로 나가며, 줄을 누르면 그 시설을 돌려준다(호출부가 경로를 그린다).
///
/// 층을 값이 아니라 listenable로 받는 이유가 여기 걸려 있다 — 시트가 떠 있는
/// 동안에도 층 선택기는 그대로 눌린다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/models/place/store_index_entry.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/facility_filter_sheet.dart';

void main() {
  late ValueNotifier<String?> floor;
  late List<String?> picks;
  StoreIndexEntry? picked;

  setUp(() {
    floor = ValueNotifier<String?>('1F');
    picks = [];
    picked = null;
  });

  tearDown(() => floor.dispose());

  StoreIndexEntry facility({
    required String id,
    required String name,
    required String subcategory,
    String floorName = '1F',
  }) => StoreIndexEntry(
    id: id,
    name: name,
    floorId: 'FL-$floorName',
    floorName: floorName,
    category: '편의시설',
    subcategory: subcategory,
    kind: 'facility',
    entranceNodeId: 'node-$id',
  );

  final facilities = [
    facility(id: 't1', name: '화장실', subcategory: '화장실'),
    facility(id: 't2', name: '장애인화장실', subcategory: '화장실'),
    facility(id: 't3', name: '화장실', subcategory: '화장실', floorName: 'B2'),
    facility(id: 'e1', name: '엘리베이터', subcategory: '엘리베이터'),
  ];

  Future<void> openSheet(WidgetTester tester, {String? selected}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await showFacilityFilterSheet(
                  context,
                  floorLabel: floor,
                  facilities: facilities,
                  selected: selected,
                  onSelected: picks.add,
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('열면 화장실이 골라져 있고 그 사실을 상위에도 알린다', (tester) async {
    await openSheet(tester);

    // 안 알리면 시트에는 켜져 있는데 도면에는 아무것도 칠해지지 않는다.
    expect(picks, ['화장실']);
    expect(find.text('1F 편의시설'), findsOneWidget);
    expect(find.byKey(const ValueKey('facility-row-t1')), findsOneWidget);
    expect(find.byKey(const ValueKey('facility-row-t2')), findsOneWidget);
    // 다른 층·다른 종류는 섞이지 않는다.
    expect(find.byKey(const ValueKey('facility-row-t3')), findsNothing);
    expect(find.byKey(const ValueKey('facility-row-e1')), findsNothing);
  });

  testWidgets('제목과 목록은 지금 층을 따라간다 — 떠 있는 동안 층을 바꿔도', (tester) async {
    await openSheet(tester);

    floor.value = 'B2';
    await tester.pump();

    expect(find.text('B2 편의시설'), findsOneWidget);
    expect(find.byKey(const ValueKey('facility-row-t3')), findsOneWidget);
    expect(find.byKey(const ValueKey('facility-row-t1')), findsNothing);
  });

  testWidgets('종류를 바꾸면 그 값이 나가고 목록도 바뀐다', (tester) async {
    await openSheet(tester);
    picks.clear();

    await tester.tap(find.byKey(const Key('facility-filter-엘리베이터')));
    await tester.pump();

    // 지도 필터는 원본값으로 걸린다. 표시 문구를 넘기면 필터가 조용히 0건이 된다.
    expect(picks, ['엘리베이터']);
    expect(find.byKey(const ValueKey('facility-row-e1')), findsOneWidget);
    expect(find.byKey(const ValueKey('facility-row-t1')), findsNothing);
  });

  testWidgets('같은 것을 다시 누르면 해제하고 목록 자리에 할 일을 적는다', (tester) async {
    await openSheet(tester, selected: '화장실');

    await tester.tap(find.byKey(const Key('facility-filter-화장실')));
    await tester.pump();

    expect(picks, [null]);
    expect(find.text('종류를 고르면 이 층의 시설을 보여드려요'), findsOneWidget);
  });

  testWidgets('줄을 누르면 그 시설을 돌려주고 닫힌다 — 호출부가 경로를 그린다', (tester) async {
    await openSheet(tester);

    await tester.tap(find.byKey(const ValueKey('facility-row-t2')));
    await tester.pumpAndSettle();

    expect(picked?.id, 't2');
  });

  testWidgets('이 층에 없으면 그렇다고 적는다 — 빈 화면과 고장을 구분한다', (tester) async {
    floor.value = '3F';
    await openSheet(tester);

    expect(find.text('이 층에는 없습니다.'), findsOneWidget);
  });

  testWidgets('X를 누르면 아무것도 고르지 않고 닫힌다', (tester) async {
    await openSheet(tester);

    await tester.tap(find.byKey(const Key('facility-filter-close')));
    await tester.pumpAndSettle();

    expect(find.text('1F 편의시설'), findsNothing);
    expect(picked, isNull);
  });
}
