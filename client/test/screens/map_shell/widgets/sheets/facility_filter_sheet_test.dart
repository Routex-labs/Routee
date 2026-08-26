/// 시설 시트의 **계약**: 목록이 선 자리에서 가까운 순으로 서고, 고른 종류가 그대로
/// 상위(지도 강조)로 나가며, 줄을 누르면 그 시설을 돌려준다(호출부가 경로를 그린다).
///
/// **한때 보고 있는 층으로 걸렀다.** 그래서 지하 2층에 서서 1층 도면을 펴 둔
/// 사람에게 1층 화장실이 떴다 — 슬라이드는 "누르면 가장 가까운 곳으로 안내가
/// 시작됩니다"라고 적어 두고 코드는 그걸 안 지키고 있었다. 지금은 층을 넘나들며
/// 보행 거리로 세운다(`facility_order.dart`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/route/dijkstra.dart';
import 'package:navigation_client/models/place/store_index_entry.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/facility_filter_sheet.dart';
import 'package:navigation_client/theme/app_theme.dart';

void main() {
  late List<String?> picks;
  StoreIndexEntry? picked;

  setUp(() {
    picks = [];
    picked = null;
  });

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

  /// 사용자는 B2에 서 있다 — B2 화장실이 코앞이고 1층 것은 한참 멀다.
  const reach = {
    'node-t3': NodeReach(distanceM: 12, costM: 12),
    'node-t1': NodeReach(distanceM: 140, costM: 190),
    'node-t2': NodeReach(distanceM: 150, costM: 200),
    'node-e1': NodeReach(distanceM: 30, costM: 30),
  };

  Future<void> openSheet(
    WidgetTester tester, {
    String? selected,
    Map<String, NodeReach>? reachByNodeId = reach,
    List<StoreIndexEntry>? rows,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await showFacilityFilterSheet(
                  context,
                  facilities: rows ?? facilities,
                  reachByNodeId: reachByNodeId,
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

  /// 지금 목록에 그려진 시설 id를 **화면에 보이는 순서대로**(위 → 아래).
  ///
  /// 트리 순회 순서가 아니라 실제 y좌표로 세운다 — 목록 순서는 사용자가 눈으로
  /// 읽는 순서이지 위젯이 만들어진 순서가 아니다.
  List<String> rowOrder(WidgetTester tester) {
    const prefix = 'facility-row-';
    final found = find.byWidgetPredicate((w) {
      final key = w.key;
      return key is ValueKey<String> && key.value.startsWith(prefix);
    });
    final rows = <({double y, String id})>[
      for (final element in found.evaluate())
        (
          y: tester.getTopLeft(find.byWidget(element.widget)).dy,
          id: (element.widget.key! as ValueKey<String>).value.substring(
            prefix.length,
          ),
        ),
    ]..sort((a, b) => a.y.compareTo(b.y));
    return [for (final r in rows) r.id];
  }

  testWidgets('열면 화장실이 골라져 있고 그 사실을 상위에도 알린다', (tester) async {
    await openSheet(tester);

    // 안 알리면 시트에는 켜져 있는데 도면에는 아무것도 칠해지지 않는다.
    expect(picks, ['화장실']);
    expect(find.text('가까운 편의시설'), findsOneWidget);
  });

  testWidgets('층을 넘어 가까운 순으로 선다 — 선 자리가 B2면 B2 화장실이 맨 위다', (
    tester,
  ) async {
    await openSheet(tester);

    // 이름순이었다면 '장애인화장실'(t2)이 앞에 왔을 것이다. 거리로 세우므로
    // 12m인 B2 화장실이 먼저다.
    //
    // **`containsAllInOrder`인 이유**: 시트 높이가 고정이라
    // ([kFacilitySheetHeightFraction]) ListView가 보이는 줄만 만든다. 몇 줄이
    // 들어가는지에 기대면 시트 높이를 손대는 날 이 테스트가 엉뚱하게 깨진다 —
    // 여기서 지킬 것은 "가까운 것이 위"라는 순서 하나다.
    expect(rowOrder(tester).first, 't3');
    expect(rowOrder(tester), containsAllInOrder(['t3', 't1']));
    // 다른 종류는 섞이지 않는다.
    expect(find.byKey(const ValueKey('facility-row-e1')), findsNothing);
  });

  testWidgets('거리를 알면 층과 함께 적는다 — 어느 층 몇 m인지가 이 줄의 정체다', (tester) async {
    await openSheet(tester);

    expect(find.text('B2 · 12m · 도보 1분'), findsOneWidget);
  });

  testWidgets('거리를 모르면 순서를 건드리지 않고 거리도 안 적는다 — PDR 미시작', (tester) async {
    await openSheet(tester, reachByNodeId: null);

    // 이름 → id 순 그대로다('장애인화장실' < '화장실'). 0으로 채워 "가장 가깝다"고
    // 적지 않는다.
    expect(rowOrder(tester).first, 't2');
    expect(rowOrder(tester), containsAllInOrder(['t2', 't1']));
    // 거리를 모르면 줄에 거리가 아예 안 붙는다 — 층만 남는다.
    expect(find.textContaining('도보'), findsNothing);
    expect(find.text('1F'), findsWidgets);
  });

  testWidgets('종류를 바꾸면 그 값이 나가고 목록도 바뀐다', (tester) async {
    await openSheet(tester);
    picks.clear();

    await tester.tap(find.byKey(const Key('facility-filter-엘리베이터')));
    await tester.pump();

    // 지도 필터는 원본값으로 걸린다. 표시 문구를 넘기면 필터가 조용히 0건이 된다.
    expect(picks, ['엘리베이터']);
    expect(rowOrder(tester), ['e1']);
  });

  testWidgets('같은 것을 다시 누르면 해제하고 목록 자리에 할 일을 적는다', (tester) async {
    await openSheet(tester, selected: '화장실');

    await tester.tap(find.byKey(const Key('facility-filter-화장실')));
    await tester.pump();

    expect(picks, [null]);
    expect(find.text('종류를 고르면 가까운 순으로 보여드려요'), findsOneWidget);
  });

  testWidgets('줄을 누르면 그 시설을 돌려주고 닫힌다 — 호출부가 경로를 그린다', (tester) async {
    await openSheet(tester);

    await tester.tap(find.byKey(const ValueKey('facility-row-t3')));
    await tester.pumpAndSettle();

    expect(picked?.id, 't3');
  });

  testWidgets('건물에 그 종류가 없으면 그렇다고 적는다 — 빈 화면과 고장을 구분한다', (tester) async {
    await openSheet(tester, rows: [facilities.last]); // 엘리베이터만 있다

    expect(find.text('이 건물에는 없습니다.'), findsOneWidget);
  });

  testWidgets('X를 누르면 아무것도 고르지 않고 닫힌다', (tester) async {
    await openSheet(tester);

    await tester.tap(find.byKey(const Key('facility-filter-close')));
    await tester.pumpAndSettle();

    expect(find.text('가까운 편의시설'), findsNothing);
    expect(picked, isNull);
  });
}
