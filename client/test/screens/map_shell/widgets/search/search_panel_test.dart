import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/domain/route/dijkstra.dart';
import 'package:navigation_client/models/building/building.dart';
import 'package:navigation_client/models/building/category_count.dart';
import 'package:navigation_client/models/place/discovery_result.dart';
import 'package:navigation_client/models/place/poi_search_result.dart';
import 'package:navigation_client/models/place/store_index_entry.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/state/recent_searches_controller.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/domain/store/reach_label.dart';
import 'package:navigation_client/screens/map_shell/widgets/search/search_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('nameHighlightRanges', () {
    // 구간만 돌려주고 어떻게 보일지는 정하지 않는다 — 그리는 일은
    // `RoutexListCell.titleHighlights`가 맡는다. 여기 남는 것은 판정이다.
    String slice(String name, TextRange range) =>
        name.substring(range.start, range.end);

    test('검색어와 일치하는 구간만 짚는다', () {
      const name = '죠죠 더현대서울점';
      final ranges = nameHighlightRanges(name, '더현대서울');

      expect(ranges.map((range) => slice(name, range)).toList(), ['더현대서울']);
      expect(ranges.single.start, 3, reason: '앞의 `죠죠 `는 건드리지 않는다');
    });

    test('대소문자는 무시하되 원문의 표기는 보존한다', () {
      const name = 'EQL 더현대서울점';
      final ranges = nameHighlightRanges(name, 'eql');

      expect(slice(name, ranges.single), 'EQL');
    });

    test('여러 번 나오면 모두 짚는다', () {
      const name = '나이키 나이키키즈';
      final ranges = nameHighlightRanges(name, '나이키');

      expect(ranges.map((range) => slice(name, range)).toList(), [
        '나이키',
        '나이키',
      ]);
    });

    // 의미 검색("밥 먹을 곳" → "정돈프리미엄")은 이름에 검색어가 없는 결과를
    // 돌려주는 것이 목적이다. 하나도 안 걸리는 것이 정상 상태다.
    test('일치하는 구간이 없으면 빈 목록이다', () {
      expect(nameHighlightRanges('정돈프리미엄', '밥 먹을 곳'), isEmpty);
    });

    test('검색어가 비어 있으면 빈 목록이다', () {
      expect(nameHighlightRanges('나이키', '   '), isEmpty);
    });
  });

  group('검색 결과 한 줄', () {
    late DestinationRepository originalDestination;
    late BuildingRepository originalBuilding;

    setUp(() {
      originalDestination = destinationRepository;
      originalBuilding = buildingRepository;
      buildingRepository = _FakeBuildingRepository();
    });

    tearDown(() {
      destinationRepository = originalDestination;
      buildingRepository = originalBuilding;
    });

    Widget buildSubject({Map<String, NodeReach>? reachByNodeId}) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SizedBox(
          height: 400,
          child: SearchPanel(
            buildingId: 'building-1',
            query: '나이키',
            submitTick: 0,
            onStorePicked: (_) {},
            onBuildingPicked: (_) {},
            onSuggestionPicked: (_) {},
            onQueryPicked: (_) {},
            indoorContextActive: true,
            reachByNodeId: reachByNodeId,
          ),
        ),
      ),
    );

    /// 디바운스(300ms)가 끝나고 가짜 응답이 프레임에 반영될 때까지 흘려보낸다.
    Future<void> settleSearch(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
    }

    testWidgets('소분류가 있으면 이름 오른쪽에 업종으로 보여준다', (tester) async {
      destinationRepository = _FakeDestinationRepository([
        _result(subcategory: '여성패션', category: '패션'),
      ]);

      await tester.pumpWidget(buildSubject());
      await settleSearch(tester);

      // 업종은 이름 오른쪽이 아니라 맥락 줄 맨 앞이다. 그 자리는 폭 상한이 있어
      // 긴 업종이 반쯤 잘려 나왔다(포팅 가이드 단계 4의 결정).
      expect(find.text('여성패션 · 3F'), findsOneWidget);
    });

    testWidgets('소분류가 없으면 업종이 사라지지 않고 대분류로 떨어진다', (tester) async {
      destinationRepository = _FakeDestinationRepository([
        _result(subcategory: null, category: '패션'),
      ]);

      await tester.pumpWidget(buildSubject());
      await settleSearch(tester);

      expect(find.text('패션 · 3F'), findsOneWidget);
    });

    testWidgets('대분류도 없으면 업종 자리를 비운다', (tester) async {
      destinationRepository = _FakeDestinationRepository([
        _result(subcategory: null, category: null),
      ]);

      await tester.pumpWidget(buildSubject());
      await settleSearch(tester);

      // 이름과 층은 그대로 나오고, 업종만 없다.
      expect(find.text('3F'), findsOneWidget);
      expect(find.textContaining('패션'), findsNothing);
    });

    // 영어 열거값(restroom 등)은 화면에 그대로 나가면 안 된다. 상세 시트가 쓰는
    // 것과 같은 변환 규칙을 목록도 따라야 한다.
    testWidgets('영어 소분류는 한글 라벨로 바꿔 보여준다', (tester) async {
      destinationRepository = _FakeDestinationRepository([
        _result(subcategory: 'restroom', category: '편의시설'),
      ]);

      await tester.pumpWidget(buildSubject());
      await settleSearch(tester);

      expect(find.text('화장실 · 3F'), findsOneWidget);
      expect(find.textContaining('restroom'), findsNothing);
    });

    testWidgets('위치를 잡았으면 거리와 도보 시간을 함께 보여준다', (tester) async {
      destinationRepository = _FakeDestinationRepository([
        _result(subcategory: '여성패션', category: '패션'),
      ]);

      await tester.pumpWidget(
        buildSubject(
          reachByNodeId: const {
            'node-1': NodeReach(distanceM: 124.4, costM: 124.4),
          },
        ),
      );
      await settleSearch(tester);

      // 124.4m / 1.2m·s⁻¹ ≈ 104초 → 올림해서 2분.
      expect(find.text('124m · 도보 2분'), findsOneWidget);
    });

    // 위치를 아직 안 잡은 상태가 정상 경로다. 줄마다 "거리 알 수 없음"을
    // 반복하면 목록이 읽히지 않는다.
    testWidgets('위치가 없으면 거리 줄을 아예 그리지 않는다', (tester) async {
      destinationRepository = _FakeDestinationRepository([
        _result(subcategory: '여성패션', category: '패션'),
      ]);

      await tester.pumpWidget(buildSubject());
      await settleSearch(tester);

      expect(find.textContaining('도보'), findsNothing);
      expect(find.text('여성패션 · 3F'), findsOneWidget);
    });

    // 그래프가 끊겨 있으면 그 노드는 맵에 키가 없다(reachableFrom 계약).
    testWidgets('도달할 수 없는 매장은 거리 줄이 없다', (tester) async {
      destinationRepository = _FakeDestinationRepository([
        _result(subcategory: '여성패션', category: '패션'),
      ]);

      await tester.pumpWidget(
        buildSubject(
          reachByNodeId: const {'다른-노드': NodeReach(distanceM: 10, costM: 10)},
        ),
      );
      await settleSearch(tester);

      expect(find.textContaining('도보'), findsNothing);
    });
  });

  // 정렬 규칙 자체는 domain/search_result_order.dart의 테스트가 덮는다. 여기서는
  // **패널이 그 규칙을 실제로 태우는지**와, 정렬 뒤에도 추천 이유가 제 매장에
  // 붙어 있는지를 본다.
  group('검색 결과 정렬', () {
    late DestinationRepository originalDestination;
    late BuildingRepository originalBuilding;

    setUp(() {
      originalDestination = destinationRepository;
      originalBuilding = buildingRepository;
      buildingRepository = _FakeBuildingRepository();
    });

    tearDown(() {
      destinationRepository = originalDestination;
      buildingRepository = originalBuilding;
    });

    Widget buildSubject({Map<String, NodeReach>? reachByNodeId}) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: SearchPanel(
            buildingId: 'building-1',
            query: '나이키',
            submitTick: 0,
            onStorePicked: (_) {},
            onBuildingPicked: (_) {},
            onSuggestionPicked: (_) {},
            onQueryPicked: (_) {},
            indoorContextActive: true,
            reachByNodeId: reachByNodeId,
          ),
        ),
      ),
    );

    /// 1차 디바운스(300ms)와 2차 유예(400ms)를 모두 흘려보낸다.
    Future<void> settleSearch(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
    }

    const reach = {
      '노드-먼곳': NodeReach(distanceM: 200, costM: 200),
      '노드-가까운곳': NodeReach(distanceM: 50, costM: 50),
    };

    testWidgets('위치를 잡았으면 가까운 매장이 위로 올라온다', (tester) async {
      // 서버가 준 순서는 먼 곳이 먼저다.
      destinationRepository = _FakeDestinationRepository([
        _store(name: '나이키 라이즈', floor: '5F', nodeId: '노드-먼곳', placeId: '먼곳'),
        _store(name: '나이키 키즈', floor: '3F', nodeId: '노드-가까운곳', placeId: '가까운곳'),
      ]);

      await tester.pumpWidget(buildSubject(reachByNodeId: reach));
      await settleSearch(tester);

      expect(
        tester.getTopLeft(find.text('3F')).dy,
        lessThan(tester.getTopLeft(find.text('5F')).dy),
      );
    });

    // 거리를 아무도 모르는 상태에서 억지로 세우면 "위쪽이 가깝다"는 거짓말이
    // 된다. 서버가 준 순서를 그대로 둔다.
    testWidgets('위치가 없으면 서버가 준 순서를 그대로 둔다', (tester) async {
      destinationRepository = _FakeDestinationRepository([
        _store(name: '나이키 라이즈', floor: '5F', nodeId: '노드-먼곳', placeId: '먼곳'),
        _store(name: '나이키 키즈', floor: '3F', nodeId: '노드-가까운곳', placeId: '가까운곳'),
      ]);

      await tester.pumpWidget(buildSubject());
      await settleSearch(tester);

      expect(
        tester.getTopLeft(find.text('5F')).dy,
        lessThan(tester.getTopLeft(find.text('3F')).dy),
      );
    });

    // 예전에는 추천 이유를 `_discoveryMatches[index]`로 짝지었다. 정렬이 들어오면
    // 이유가 옆 매장에 붙는데, 화면은 멀쩡해 보여서 알아채기 어렵다.
    //
    // 그리고 이 조합은 가정이 아니다 — 이름이 질의로 시작하면 `_fromSemantic`이
    // false가 되어 정렬이 도는데, `_discoveryMatches`는 그대로 차 있다.
    testWidgets('정렬 뒤에도 추천 이유가 제 매장에 붙어 있다', (tester) async {
      destinationRepository = _FakeDestinationRepository(
        const [], // 1차는 빈손 → 2차 의미 검색으로 넘어간다
        discovery: DiscoveryResult(
          mode: DiscoveryMode.results,
          query: '나이키',
          matches: [
            _match(
              name: '나이키 라이즈',
              floor: '5F',
              node: '노드-먼곳',
              id: '먼곳',
              reason: '이유-먼곳',
            ),
            _match(
              name: '나이키 키즈',
              floor: '3F',
              node: '노드-가까운곳',
              id: '가까운곳',
              reason: '이유-가까운곳',
            ),
          ],
        ),
      );

      await tester.pumpWidget(buildSubject(reachByNodeId: reach));
      await settleSearch(tester);

      // 가까운 매장이 위로 올라왔고,
      // 층이 앞에 붙는다 — 근거가 층을 밀어내지 않는다(domain/reason_text.dart).
      expect(
        tester.getTopLeft(find.textContaining('3F · 이유-가까운곳')).dy,
        lessThan(tester.getTopLeft(find.textContaining('5F · 이유-먼곳')).dy),
      );
      // 그 줄의 거리도 가까운 매장의 것이다. 인덱스로 짝지었다면 이유와 거리가
      // 서로 다른 매장의 값이 되어 여기서 걸린다.
      final nearTile = find.ancestor(
        of: find.textContaining('3F · 이유-가까운곳'),
        matching: find.byType(RoutexListCell),
      );
      expect(
        find.descendant(of: nearTile, matching: find.textContaining('50m')),
        findsOneWidget,
      );
    });
  });

  // 스펙은 naver-map-ui-ux-analysis.md의 「J. 검색 빈 상태(idle) 채우기」다.
  // 저장소 규칙 자체는 state/recent_searches_controller_test.dart가 덮고,
  // 여기서는 **패널이 그 값을 실제로 그리고 다시 검색으로 이어 주는지**를 본다.
  group('빈 화면의 최근 검색어', () {
    late RecentSearchesController original;

    /// 최근 검색어를 탭했을 때 상위로 올라온 값. 콜백이 실제로 불렸는지 본다.
    String? picked;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      original = recentSearchesController;
      picked = null;
    });

    tearDown(() => recentSearchesController = original);

    Future<void> useQueries(List<String> queries) async {
      final controller = RecentSearchesController(
        prefs: await SharedPreferences.getInstance(),
      );
      await controller.ready;
      for (final query in queries) {
        await controller.add(query);
      }
      recentSearchesController = controller;
    }

    Widget buildSubject() => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SizedBox(
          height: 400,
          child: SearchPanel(
            buildingId: 'building-1',
            // 빈 질의라 검색이 돌지 않고 idle에 머문다.
            query: '',
            submitTick: 0,
            onStorePicked: (_) {},
            onBuildingPicked: (_) {},
            onSuggestionPicked: (_) {},
            onQueryPicked: (value) => picked = value,
            indoorContextActive: true,
          ),
        ),
      ),
    );

    testWidgets('저장된 검색어가 없으면 예전 안내 문구가 그대로 남는다', (tester) async {
      await useQueries(const []);

      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.textContaining('매장 이름을 입력하면'), findsOneWidget);
      expect(find.text('최근 검색어'), findsNothing);
    });

    testWidgets('최근 검색어가 있으면 최신순으로 보여준다', (tester) async {
      await useQueries(const ['화장실', '나이키']);

      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.text('최근 검색어'), findsOneWidget);
      // 나중에 넣은 '나이키'가 위로 온다.
      expect(
        tester.getTopLeft(find.text('나이키')).dy,
        lessThan(tester.getTopLeft(find.text('화장실')).dy),
      );
      // 안내 문구는 자리를 내준다.
      expect(find.textContaining('매장 이름을 입력하면'), findsNothing);
    });

    testWidgets('탭하면 그 검색어로 다시 검색한다', (tester) async {
      await useQueries(const ['나이키']);

      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();
      await tester.tap(find.text('나이키'));

      expect(picked, '나이키');
    });

    testWidgets('개별 삭제하면 그 줄만 사라진다', (tester) async {
      await useQueries(const ['화장실', '나이키']);

      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('recent-나이키')),
          matching: find.byTooltip('나이키 삭제'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('나이키'), findsNothing);
      expect(find.text('화장실'), findsOneWidget);
    });

    testWidgets('전체 삭제하면 안내 문구로 돌아간다', (tester) async {
      await useQueries(const ['화장실', '나이키']);

      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();
      await tester.tap(find.text('전체 삭제'));
      await tester.pumpAndSettle();

      expect(find.text('최근 검색어'), findsNothing);
      expect(find.textContaining('매장 이름을 입력하면'), findsOneWidget);
    });
  });

  // 후보 산출 규칙 자체는 domain/store_suggestions_test.dart가 덮는다. 여기서는
  // **패널이 그 후보를 어느 화면에 띄우는지**와, 목록을 못 받았을 때 검색이
  // 그대로 도는지를 본다(설계: search-input-assist.md K·L절).
  group('자동완성 후보', () {
    late DestinationRepository originalDestination;
    late BuildingRepository originalBuilding;
    String? picked;
    StoreIndexEntry? opened;

    setUp(() {
      originalDestination = destinationRepository;
      originalBuilding = buildingRepository;
      picked = null;
      opened = null;
    });

    tearDown(() {
      destinationRepository = originalDestination;
      buildingRepository = originalBuilding;
    });

    Widget buildSubject(
      String query, {
      bool indoor = true,
      Map<String, NodeReach>? reachByNodeId,
    }) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SizedBox(
          height: 500,
          child: SearchPanel(
            buildingId: 'building-1',
            query: query,
            submitTick: 0,
            onStorePicked: (_) {},
            onBuildingPicked: (_) {},
            onSuggestionPicked: (entry) => opened = entry,
            onQueryPicked: (value) => picked = value,
            indoorContextActive: indoor,
            reachByNodeId: reachByNodeId,
          ),
        ),
      ),
    );

    // 디바운스가 끝나기 **전**. 서버는 아직 아무 말도 안 했다.
    Future<void> pumpWhileTyping(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('서버를 기다리는 동안 후보가 먼저 뜬다', (tester) async {
      buildingRepository = _FakeBuildingRepository(
        storeIndex: [_entry('나이키 라이즈', '3F')],
      );
      destinationRepository = _FakeDestinationRepository(const []);

      await tester.pumpWidget(buildSubject('나이'));
      await pumpWhileTyping(tester);

      expect(find.text('검색어 제안'), findsOneWidget);
      expect(find.text('3F'), findsOneWidget);
    });

    // 초성은 서버 경량 매칭이 전혀 못 잡는다. 온디바이스 후보만이 답을 낸다.
    testWidgets('초성으로도 후보가 나온다', (tester) async {
      buildingRepository = _FakeBuildingRepository(
        storeIndex: [_entry('나이키 라이즈', '3F')],
      );
      destinationRepository = _FakeDestinationRepository(const []);

      await tester.pumpWidget(buildSubject('ㄴㅇㅋ'));
      await pumpWhileTyping(tester);

      expect(find.text('검색어 제안'), findsOneWidget);
    });

    // L이 실제로 값을 내는 자리. 서버가 못 찾은 뒤에도 표기 실수를 잡아 준다.
    testWidgets('서버가 못 찾아도 오타 교정 후보를 되묻는다', (tester) async {
      buildingRepository = _FakeBuildingRepository(
        storeIndex: [_entry('샤넬 뷰티', '1F')],
      );
      destinationRepository = _FakeDestinationRepository(const []);

      await tester.pumpWidget(buildSubject('샤낼 뷰티'));
      // 경량(300ms) + 의미(400ms)까지 모두 지나 noMatch가 확정된 뒤.
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();

      expect(find.text('이걸 찾으셨나요?'), findsOneWidget);
      expect(find.text('1F'), findsOneWidget);
    });

    // 한 곳짜리 후보는 **한 번 눌러 열린다.** 예전에는 이 자리에서 이름으로
    // 검색을 다시 돌렸고, 사용자는 방금 고른 것과 사실상 같은 줄을 결과 목록에서
    // 한 번 더 눌러야 했다 — 후보에 좌표가 없어서 생긴 우회였다.
    testWidgets('후보를 탭하면 그 매장을 바로 연다', (tester) async {
      buildingRepository = _FakeBuildingRepository(
        storeIndex: [_entry('나이키 라이즈', '3F')],
      );
      destinationRepository = _FakeDestinationRepository(const []);

      await tester.pumpWidget(buildSubject('나이'));
      await pumpWhileTyping(tester);
      await tester.tap(find.byKey(const Key('suggestion-PO-나이키 라이즈')));

      expect(opened?.name, '나이키 라이즈');
      expect(opened?.floorName, '3F');
      // 재검색이 돌지 않아야 한 번으로 끝난다.
      expect(picked, isNull);
    });

    // **실기기에서 잡은 회귀다.** `apc`는 서버 경량 매칭이 `name LIKE %apc%`라
    // 구두점이 든 `A.P.C.`를 못 잡고 no_match를 준다. 예전에는 그 뒤 의미 검색이
    // 돌아 임계값을 겨우 넘긴 **주차구역**을 "뜻이 비슷한 매장"이라며 확정했다 —
    // 정답이 이미 화면에 떠 있는데 오답으로 갈아치웠다.
    testWidgets('이름이 걸린 후보는 임베딩 결과에 덮이지 않는다', (tester) async {
      buildingRepository = _FakeBuildingRepository(
        storeIndex: [_entry('A.P.C.', '3F')],
      );
      final repository = _FakeDestinationRepository(
        const [],
        // 실기기에서 실제로 온 모양 — 임계값을 겨우 넘긴 주차구역이 "뜻이
        // 비슷한 매장"이라며 올라왔다.
        discovery: DiscoveryResult(
          mode: DiscoveryMode.results,
          query: 'apc',
          source: DiscoverySource.semantic,
          matches: [_gateMatch('6A', 'B5')],
        ),
      );
      destinationRepository = repository;

      await tester.pumpWidget(buildSubject('apc'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();

      // 호출은 한다 — 막아야 하는 건 임베딩 결과지 호출이 아니다.
      expect(repository.aiCallCount, 1);
      // 그리고 그 결과는 버려진다. 화면에는 이름 후보가 그대로 남는다.
      expect(find.text('검색어 제안'), findsOneWidget);
      expect(find.text('3F'), findsOneWidget);
      expect(find.text('6A'), findsNothing);
    });

    // `커피`가 상호에 그 글자가 든 4곳으로 끝나고 카페 53곳이 통째로 가려지던
    // 문제. 서버 어휘(동의어·intent·카테고리)는 이름 후보와 같은 등급이라 이긴다.
    testWidgets('어휘로 잡은 결과는 이름 후보를 대체한다', (tester) async {
      buildingRepository = _FakeBuildingRepository(
        storeIndex: [_entry('더커피', 'B1')],
      );
      final repository = _FakeDestinationRepository(
        const [],
        discovery: DiscoveryResult(
          mode: DiscoveryMode.results,
          query: '커피',
          source: DiscoverySource.light,
          matches: [_gateMatch('블루보틀', '5F'), _gateMatch('스타벅스 리저브', 'B2')],
        ),
      );
      destinationRepository = repository;

      await tester.pumpWidget(buildSubject('커피'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();

      expect(repository.aiCallCount, 1);
      expect(find.text('검색어 제안'), findsNothing);
      expect(find.text('블루보틀'), findsOneWidget);
      expect(find.text('스타벅스 리저브'), findsOneWidget);
      // 어휘로 정확히 찾아 준 것을 "뜻이 비슷한"이라고 말하지 않는다.
      expect(find.textContaining('뜻이 비슷한'), findsNothing);
    });

    testWidgets('임베딩으로 찾았을 때만 뜻이 비슷하다고 말한다', (tester) async {
      buildingRepository = _FakeBuildingRepository(storeIndex: const []);
      destinationRepository = _FakeDestinationRepository(
        const [],
        discovery: DiscoveryResult(
          mode: DiscoveryMode.results,
          query: '밥 먹을 곳',
          source: DiscoverySource.semantic,
          matches: [_gateMatch('요즘김밥', 'B1')],
        ),
      );

      await tester.pumpWidget(buildSubject('밥 먹을 곳'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();

      expect(find.textContaining('뜻이 비슷한'), findsOneWidget);
    });

    // 배포 순서가 어긋나 구버전 서버에 붙었을 때. source를 모르면 이름 후보를
    // 지키는 쪽이 안전하다 — 반대로 기울면 A.P.C. 회귀가 되살아난다.
    testWidgets('source를 모르는 응답은 이름 후보를 대체하지 않는다', (tester) async {
      buildingRepository = _FakeBuildingRepository(
        storeIndex: [_entry('A.P.C.', '3F')],
      );
      final repository = _FakeDestinationRepository(
        const [],
        discovery: DiscoveryResult(
          mode: DiscoveryMode.results,
          query: 'apc',
          matches: [_gateMatch('6A', 'B5')],
        ),
      );
      destinationRepository = repository;

      await tester.pumpWidget(buildSubject('apc'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();

      expect(find.text('검색어 제안'), findsOneWidget);
      expect(find.text('6A'), findsNothing);
    });

    // 교정 후보만 있을 때는 추측이라 의미 검색에 기회를 준다.
    testWidgets('교정 후보뿐이면 의미 검색으로 넘어간다', (tester) async {
      buildingRepository = _FakeBuildingRepository(
        storeIndex: [_entry('샤넬 뷰티', '1F')],
      );
      final repository = _FakeDestinationRepository(const []);
      destinationRepository = repository;

      await tester.pumpWidget(buildSubject('샤낼 뷰티'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();

      expect(repository.aiCallCount, 1);
      expect(find.text('이걸 찾으셨나요?'), findsOneWidget);
    });

    // **실기기에서 두 번 잡은 자리다.**
    //
    // 처음에는 1F에서 3F 매장 후보를 탭하면 층 스코프 때문에 1차가 또 빈손이
    // 되어 후보 화면으로 되돌아왔다. 그래서 "탭한 검색은 층을 안 좁힌다"로
    // 막았는데, 그러면 **어느 매장을 고를지를 서버가 자기 순서로 정한다** —
    // `화장실 · 1F 등 19곳 · 57m`을 탭했더니 `화장실 · B6 · 219m`로 갔다.
    //
    // 한 곳짜리 후보는 이제 재검색을 거치지 않으므로 서버가 고를 여지 자체가
    // 없다. 대신 **후보의 id가 그대로 올라가는지**를 본다 — 이름으로 넘기면
    // 동명 매장에서 같은 사고가 되살아난다. 묶인 시설(재검색이 남아 있는 경로)은
    // 바로 아래 테스트가 층 스코프를 계속 지킨다.
    testWidgets('후보를 탭하면 그 후보를 id로 확정해 넘긴다', (tester) async {
      buildingRepository = _FakeBuildingRepository(
        storeIndex: [_entry('A.P.C.', '3F')],
      );
      final repository = _FakeDestinationRepository(const []);
      destinationRepository = repository;

      // 상위(MapShellScreen)와 같게 배선한다 — 후보를 고르면 검색창 글자를 바꾸고
      // 확정 카운터를 올려 검색을 한 바퀴 더 돌린다. 이 되먹임이 없으면 탭이
      // 만드는 두 번째 검색 자체가 일어나지 않아 검증이 성립하지 않는다.
      final query = ValueNotifier<String>('apc');
      final submitTick = ValueNotifier<int>(0);
      addTearDown(query.dispose);
      addTearDown(submitTick.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SizedBox(
              height: 500,
              child: ListenableBuilder(
                listenable: Listenable.merge([query, submitTick]),
                builder: (_, _) => SearchPanel(
                  buildingId: 'building-1',
                  query: query.value,
                  submitTick: submitTick.value,
                  // 지금 1F를 보고 있다.
                  currentFloorId: 'FL-1F',
                  onStorePicked: (_) {},
                  onBuildingPicked: (_) {},
                  onSuggestionPicked: (entry) => opened = entry,
                  onQueryPicked: (value) {
                    query.value = value;
                    submitTick.value++;
                  },
                  indoorContextActive: true,
                ),
              ),
            ),
          ),
        ),
      );
      // 디바운스를 지나 1차 검색이 실제로 나가게 둔다. 그래야 "탭 뒤에 검색이
      // 더 나가지 않았다"를 셀 수 있다.
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('suggestion-PO-A.P.C.')));
      await tester.pumpAndSettle();

      // 이름이 아니라 id로 확정된다. 구두점이 든 이름(A.P.C.)도 그대로 실린다.
      expect(opened?.id, 'PO-A.P.C.');
      expect(opened?.floorName, '3F');
      // 검색은 탭 전 1차 한 번뿐이다 — 탭이 두 번째 검색을 만들지 않는다.
      expect(repository.floorScopes.length, 1);
      expect(repository.floorScopes.single, 'FL-1F');
      expect(query.value, 'apc');
    });

    // 같은 이름이 층마다 있는 시설은 대표(최근접)의 층으로 좁혀야 화면에 적힌
    // 층과 실제로 가는 층이 같아진다.
    testWidgets('묶인 시설은 화면에 적힌 대표의 층으로 좁힌다', (tester) async {
      buildingRepository = _FakeBuildingRepository(
        storeIndex: [
          _entry('화장실', '6F', nodeId: 'N6'),
          _entry('화장실', 'B2', nodeId: 'NB2'),
          _entry('화장실', '1F', nodeId: 'N1'),
        ],
      );
      final repository = _FakeDestinationRepository(const []);
      destinationRepository = repository;

      final query = ValueNotifier<String>('화장');
      final submitTick = ValueNotifier<int>(0);
      addTearDown(query.dispose);
      addTearDown(submitTick.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SizedBox(
              height: 500,
              child: ListenableBuilder(
                listenable: Listenable.merge([query, submitTick]),
                builder: (_, _) => SearchPanel(
                  buildingId: 'building-1',
                  query: query.value,
                  submitTick: submitTick.value,
                  currentFloorId: 'FL-1F',
                  onStorePicked: (_) {},
                  onBuildingPicked: (_) {},
                  onSuggestionPicked: (_) {},
                  onQueryPicked: (value) {
                    query.value = value;
                    submitTick.value++;
                  },
                  indoorContextActive: true,
                  // B2가 가장 가깝다 → 대표도 B2다.
                  reachByNodeId: const {
                    'N6': NodeReach(distanceM: 310, costM: 310),
                    'NB2': NodeReach(distanceM: 48, costM: 48),
                    'N1': NodeReach(distanceM: 120, costM: 120),
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('suggestion-PO-화장실-B2')));
      await tester.pumpAndSettle();

      // 인덱스 첫 번째(6F)도, 지금 보고 있는 층(1F)도 아닌 대표의 층이다.
      expect(repository.floorScopes.last, 'FL-B2');
    });

    // 최근 검색어는 문자열 하나뿐이라 어느 층 매장이었는지 알 방법이 없다.
    // 그때만 예전처럼 스코프를 뺀다 — 안 그러면 다른 층 매장에 영영 못 닿는다.
    testWidgets('최근 검색어 탭은 층으로 좁히지 않는다', (tester) async {
      final originalRecent = recentSearchesController;
      addTearDown(() => recentSearchesController = originalRecent);
      SharedPreferences.setMockInitialValues({});
      final recent = RecentSearchesController(
        prefs: await SharedPreferences.getInstance(),
      );
      await recent.ready;
      await recent.add('A.P.C.');
      recentSearchesController = recent;

      buildingRepository = _FakeBuildingRepository(
        storeIndex: [_entry('A.P.C.', '3F')],
      );
      final repository = _FakeDestinationRepository(const []);
      destinationRepository = repository;

      final query = ValueNotifier<String>('');
      final submitTick = ValueNotifier<int>(0);
      addTearDown(query.dispose);
      addTearDown(submitTick.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SizedBox(
              height: 500,
              child: ListenableBuilder(
                listenable: Listenable.merge([query, submitTick]),
                builder: (_, _) => SearchPanel(
                  buildingId: 'building-1',
                  query: query.value,
                  submitTick: submitTick.value,
                  currentFloorId: 'FL-1F',
                  onStorePicked: (_) {},
                  onBuildingPicked: (_) {},
                  onSuggestionPicked: (_) {},
                  onQueryPicked: (value) {
                    query.value = value;
                    submitTick.value++;
                  },
                  indoorContextActive: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('recent-A.P.C.')));
      await tester.pumpAndSettle();

      expect(repository.floorScopes.single, isNull);
    });

    // 후보의 원본이 건물 하나의 매장 목록이라, 야외에서 쓰면 지금 서 있는 곳과
    // 무관한 매장을 제안한다. 실기기에서 시청 앞 야외 지도에 더현대서울 3층
    // 매장이 후보로 떠서 잡았다. 야외 장소 검색은 외부 API로 따로 채운다.
    testWidgets('야외에서는 후보를 만들지 않고 원본도 받지 않는다', (tester) async {
      final repository = _FakeBuildingRepository(
        storeIndex: [_entry('A.P.C.', '3F')],
      );
      buildingRepository = repository;
      destinationRepository = _FakeDestinationRepository(const []);

      await tester.pumpWidget(buildSubject('apc', indoor: false));
      await pumpWhileTyping(tester);

      expect(find.text('검색어 제안'), findsNothing);
      // 쓰지도 않을 목록을 내려받지 않는다.
      expect(repository.storeIndexCallCount, 0);
    });

    // 자동완성은 부가 기능이다. 원본을 못 받아도 검색을 막아서는 안 된다.
    testWidgets('목록을 못 받으면 후보만 사라지고 검색은 그대로 돈다', (tester) async {
      buildingRepository = _FakeBuildingRepository(storeIndexFails: true);
      destinationRepository = _FakeDestinationRepository([
        _result(subcategory: '여성패션', category: '패션'),
      ]);

      await tester.pumpWidget(buildSubject('나이키'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.text('검색어 제안'), findsNothing);
      // 서버 결과는 정상적으로 나온다.
      expect(find.text('여성패션 · 3F'), findsOneWidget);
    });

    // 층마다 있는 시설은 한 줄로 묶여 온다. 몇 곳인지 안 적으면 사용자는
    // "왜 한 층만 나오지"로 읽는다.
    testWidgets('같은 이름 시설은 한 줄로 묶고 몇 곳인지 적는다', (tester) async {
      buildingRepository = _FakeBuildingRepository(
        storeIndex: [
          _entry('화장실', 'B2'),
          _entry('화장실', 'B1'),
          _entry('화장실', '1F'),
        ],
      );
      destinationRepository = _FakeDestinationRepository(const []);

      await tester.pumpWidget(buildSubject('화장실'));
      await pumpWhileTyping(tester);

      expect(find.textContaining('3곳'), findsOneWidget);
    });
  });

  // 후보 목록은 브랜드 질의(구찌·프라다 — 서버가 한 곳을 지목 못 한다)에서
  // 사실상 결과 화면이 된다. 그런데 거리가 없었고, 묶인 시설의 대표 층은
  // 인덱스 첫 번째(= 늘 꼭대기 층)로 고정돼 **틀린 층**을 적고 있었다.
  // 설계: docs/client/search-result-list-ux.md O절.
  group('후보 목록의 거리와 대표 층', () {
    late DestinationRepository originalDestination;
    late BuildingRepository originalBuilding;

    setUp(() {
      originalDestination = destinationRepository;
      originalBuilding = buildingRepository;
    });

    tearDown(() {
      destinationRepository = originalDestination;
      buildingRepository = originalBuilding;
    });

    Widget buildSubject(
      String query, {
      Map<String, NodeReach>? reachByNodeId,
    }) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SizedBox(
          height: 500,
          child: SearchPanel(
            buildingId: 'building-1',
            query: query,
            submitTick: 0,
            onStorePicked: (_) {},
            onBuildingPicked: (_) {},
            onSuggestionPicked: (_) {},
            onQueryPicked: (_) {},
            indoorContextActive: true,
            reachByNodeId: reachByNodeId,
          ),
        ),
      ),
    );

    Future<void> pumpWhileTyping(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 인덱스 순서는 서버가 `Floor.level DESC`로 못박아 둔다(building_queries.py).
    // 그래서 예전에는 사용자가 B2에 서 있어도 `화장실 · 6F 등 3곳`이었다.
    testWidgets('묶인 시설의 대표 층이 인덱스 첫 번째가 아니라 최근접이다', (tester) async {
      buildingRepository = _FakeBuildingRepository(
        storeIndex: [
          _entry('화장실', '6F', nodeId: 'N6'),
          _entry('화장실', 'B2', nodeId: 'NB2'),
          _entry('화장실', '1F', nodeId: 'N1'),
        ],
      );
      destinationRepository = _FakeDestinationRepository(const []);

      await tester.pumpWidget(
        buildSubject(
          '화장실',
          reachByNodeId: const {
            'N6': NodeReach(distanceM: 310, costM: 310),
            'NB2': NodeReach(distanceM: 48, costM: 48),
            'N1': NodeReach(distanceM: 120, costM: 120),
          },
        ),
      );
      await pumpWhileTyping(tester);

      expect(find.text('B2 등 3곳'), findsOneWidget);
      expect(find.text('48m · 도보 1분'), findsOneWidget);
      // 개수는 도달 가능한 수가 아니라 묶인 전체다.
      expect(find.textContaining('6F'), findsNothing);
    });

    // 19곳 중 3곳만 거리를 안다고 `등 3곳`으로 적으면 없는 사실을 만들어 낸다.
    testWidgets('일부만 도달 가능해도 묶인 개수는 그대로다', (tester) async {
      buildingRepository = _FakeBuildingRepository(
        storeIndex: [
          _entry('화장실', '6F', nodeId: 'N6'),
          _entry('화장실', 'B2', nodeId: 'NB2'),
          _entry('화장실', '1F', nodeId: 'N1'),
        ],
      );
      destinationRepository = _FakeDestinationRepository(const []);

      await tester.pumpWidget(
        buildSubject(
          '화장실',
          // 그래프가 끊겨 1F만 도달 가능한 상태.
          reachByNodeId: const {'N1': NodeReach(distanceM: 120, costM: 120)},
        ),
      );
      await pumpWhileTyping(tester);

      expect(find.text('1F 등 3곳'), findsOneWidget);
    });

    // 서버가 한 곳을 지목하지 못하는 브랜드 질의(query_search.py의 ambiguous).
    // 이 화면이 최종 결과인데 거리가 없으면 어느 층으로 갈지 고를 수 없다.
    testWidgets('묶이지 않은 후보에도 거리가 붙는다', (tester) async {
      buildingRepository = _FakeBuildingRepository(
        storeIndex: [
          _entry('구찌', '1F', nodeId: 'N1'),
          _entry('구찌 선글라스', '2F', nodeId: 'N2'),
        ],
      );
      destinationRepository = _FakeDestinationRepository(const []);

      await tester.pumpWidget(
        buildSubject(
          '구찌',
          reachByNodeId: const {
            'N1': NodeReach(distanceM: 40, costM: 40),
            'N2': NodeReach(distanceM: 180, costM: 180),
          },
        ),
      );
      await pumpWhileTyping(tester);

      expect(find.text('40m · 도보 1분'), findsOneWidget);
      expect(find.text('180m · 도보 3분'), findsOneWidget);
    });

    // 위치가 없을 때는 결과 목록과 같은 규칙이다 — 거리 줄을 아예 그리지 않는다
    // (A절 실패 조건). 줄마다 "거리 알 수 없음"이 반복되면 목록이 안 읽힌다.
    testWidgets('위치가 없으면 거리 줄이 없고 대표도 예전 그대로다', (tester) async {
      buildingRepository = _FakeBuildingRepository(
        storeIndex: [
          _entry('화장실', '6F', nodeId: 'N6'),
          _entry('화장실', 'B2', nodeId: 'NB2'),
        ],
      );
      destinationRepository = _FakeDestinationRepository(const []);

      await tester.pumpWidget(buildSubject('화장실'));
      await pumpWhileTyping(tester);

      expect(find.text('6F 등 2곳'), findsOneWidget);
      expect(find.textContaining('도보'), findsNothing);
    });

    // O는 거리 라벨만 더한다. 후보 **순서**는 매칭 품질순 그대로다 — 타이핑 중에
    // 거리로 다시 세우면 글자를 칠 때마다 목록이 튄다(O절 「순서는 건드리지 않는다」).
    testWidgets('거리가 붙어도 후보 순서는 매칭 품질순 그대로다', (tester) async {
      buildingRepository = _FakeBuildingRepository(
        storeIndex: [
          // `타임`은 짧은 이름이 위다(K절). 거리로 세우면 타임옴므가 1위가 된다.
          _entry('타임옴므', '3F', nodeId: 'N옴므'),
          _entry('타임', '3F', nodeId: 'N타임'),
        ],
      );
      destinationRepository = _FakeDestinationRepository(const []);

      await tester.pumpWidget(
        buildSubject(
          '타임',
          reachByNodeId: const {
            'N옴므': NodeReach(distanceM: 10, costM: 10),
            'N타임': NodeReach(distanceM: 300, costM: 300),
          },
        ),
      );
      await pumpWhileTyping(tester);

      final tiles = tester
          .widgetList<RoutexListCell>(find.byType(RoutexListCell))
          .toList();
      expect(
        (tiles.first.key as ValueKey<String>?)?.value,
        'suggestion-PO-타임-3F',
      );
    });
  });

  // 개수·층 머리말(Q)과 정렬 컨트롤(P)은 한 줄을 함께 쓴다.
  // 설계: docs/client/search-result-list-ux.md P·Q절.
  group('목록 머리말과 정렬 컨트롤', () {
    late DestinationRepository originalDestination;
    late BuildingRepository originalBuilding;

    setUp(() {
      originalDestination = destinationRepository;
      originalBuilding = buildingRepository;
    });

    tearDown(() {
      destinationRepository = originalDestination;
      buildingRepository = originalBuilding;
    });

    Widget buildSubject(
      String query, {
      Map<String, NodeReach>? reachByNodeId,
    }) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: SearchPanel(
            buildingId: 'building-1',
            query: query,
            submitTick: 0,
            onStorePicked: (_) {},
            onBuildingPicked: (_) {},
            onSuggestionPicked: (_) {},
            onQueryPicked: (_) {},
            indoorContextActive: true,
            reachByNodeId: reachByNodeId,
          ),
        ),
      ),
    );

    Future<void> pumpWhileTyping(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    /// 서버가 `ambiguous`(match=null)를 준 뒤 — 후보 목록이 최종 화면이다.
    Future<void> settleAmbiguous(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
    }

    void useIndoorBrand() {
      buildingRepository = _FakeBuildingRepository(
        storeIndex: [
          _entry('구찌', '1F', nodeId: 'N1'),
          _entry('구찌 뷰티', '1F', nodeId: 'N1b'),
          _entry('구찌 선글라스', '2F', nodeId: 'N2'),
        ],
      );
      destinationRepository = _FakeDestinationRepository(const []);
    }

    const brandReach = {
      'N1': NodeReach(distanceM: 300, costM: 300),
      'N1b': NodeReach(distanceM: 40, costM: 40),
      'N2': NodeReach(distanceM: 120, costM: 120),
    };

    testWidgets('확정된 후보 목록에 개수와 층 수가 뜬다', (tester) async {
      useIndoorBrand();

      await tester.pumpWidget(buildSubject('구찌', reachByNodeId: brandReach));
      await settleAmbiguous(tester);

      expect(find.text('검색 결과 3 · 2개 층'), findsOneWidget);
      expect(find.text('검색어 제안'), findsNothing);
    });

    // 타이핑 중에는 아직 결론이 아니다. 매 글자 컨트롤이 깜빡이면 결론처럼
    // 보이고, 거리로 다시 세우면 줄이 위아래로 튄다.
    testWidgets('타이핑 중에는 머리말도 컨트롤도 없다', (tester) async {
      useIndoorBrand();

      await tester.pumpWidget(buildSubject('구찌', reachByNodeId: brandReach));
      await pumpWhileTyping(tester);

      expect(find.text('검색어 제안'), findsOneWidget);
      expect(find.byType(RoutexSortMenu), findsNothing);
    });

    testWidgets('위치가 있으면 가까운 순이 기본이고 그렇게 세운다', (tester) async {
      useIndoorBrand();

      await tester.pumpWidget(buildSubject('구찌', reachByNodeId: brandReach));
      await settleAmbiguous(tester);

      expect(find.text('가까운 순'), findsOneWidget);
      final tiles = tester
          .widgetList<RoutexListCell>(find.byType(RoutexListCell))
          .toList();
      expect(
        [for (final t in tiles) (t.key as ValueKey<String>?)?.value],
        [
          'suggestion-PO-구찌 뷰티-1F', // 40m
          'suggestion-PO-구찌 선글라스-2F', // 120m
          'suggestion-PO-구찌-1F', // 300m
        ],
      );
    });

    // 매칭 품질순으로 되돌리면 K절의 순서(짧은 이름이 위)로 돌아와야 한다.
    testWidgets('이름 맞춤 순을 고르면 매칭 품질순으로 되돌아간다', (tester) async {
      useIndoorBrand();

      await tester.pumpWidget(buildSubject('구찌', reachByNodeId: brandReach));
      await settleAmbiguous(tester);

      await tester.tap(find.byType(RoutexSortMenu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('이름 맞춤 순').last);
      await tester.pumpAndSettle();

      final tiles = tester
          .widgetList<RoutexListCell>(find.byType(RoutexListCell))
          .toList();
      expect(
        [for (final t in tiles) (t.key as ValueKey<String>?)?.value],
        [
          'suggestion-PO-구찌-1F',
          'suggestion-PO-구찌 뷰티-1F',
          'suggestion-PO-구찌 선글라스-2F',
        ],
      );
    });

    // 거리를 아무도 모르면 눌러도 순서가 안 바뀐다. 고를 수 있게 두면 사용자는
    // 정렬이 고장 났다고 읽는다.
    testWidgets('위치가 없으면 기본이 이름 맞춤 순이고 가까운 순은 비활성이다', (tester) async {
      useIndoorBrand();

      await tester.pumpWidget(buildSubject('구찌'));
      await settleAmbiguous(tester);

      expect(find.text('이름 맞춤 순'), findsOneWidget);

      await tester.tap(find.byType(RoutexSortMenu));
      await tester.pumpAndSettle();

      // **쓸 수 없는 기준을 감추지 않는다.** 감추면 "가까운 순"이 아예 없는 앱으로
      // 읽히고, 눌러 본 뒤 막으면 왜 안 되는지를 그때야 안다.
      final item = tester.widget<PopupMenuItem<String>>(
        find.widgetWithText(PopupMenuItem<String>, '가까운 순 (현재 위치 필요)'),
      );
      expect(item.enabled, isFalse);
    });

    testWidgets('후보가 1건이면 머리말도 컨트롤도 없다', (tester) async {
      buildingRepository = _FakeBuildingRepository(
        storeIndex: [_entry('크록스', '4F', nodeId: 'N4')],
      );
      destinationRepository = _FakeDestinationRepository(const []);

      await tester.pumpWidget(
        buildSubject(
          '크록스',
          reachByNodeId: const {'N4': NodeReach(distanceM: 30, costM: 30)},
        ),
      );
      await settleAmbiguous(tester);

      expect(find.byType(RoutexSortMenu), findsNothing);
      expect(find.textContaining('검색 결과'), findsNothing);
    });

    // 교정 후보는 추측이다. 개수를 세고 거리로 세워 주는 건 "이게 답이다"라는
    // 말인데, 여기서 아는 건 "표기가 비슷한 이름이 있다"뿐이다.
    testWidgets('오타 교정 화면에는 머리말도 컨트롤도 없다', (tester) async {
      buildingRepository = _FakeBuildingRepository(
        storeIndex: [
          _entry('샤넬 뷰티', '1F', nodeId: 'N1'),
          _entry('샤넬', '1F', nodeId: 'N1b'),
        ],
      );
      destinationRepository = _FakeDestinationRepository(const []);

      await tester.pumpWidget(
        buildSubject(
          '샤낼 뷰티',
          reachByNodeId: const {
            'N1': NodeReach(distanceM: 300, costM: 300),
            'N1b': NodeReach(distanceM: 10, costM: 10),
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();

      expect(find.text('이걸 찾으셨나요?'), findsOneWidget);
      expect(find.byType(RoutexSortMenu), findsNothing);
    });

    // 검색어가 바뀌면 초기화한다 — 저장하면 다음 검색이 사용자가 기억 못 하는
    // 순서로 시작한다.
    testWidgets('검색어를 바꾸면 정렬 선택이 기본으로 돌아간다', (tester) async {
      useIndoorBrand();

      await tester.pumpWidget(buildSubject('구찌', reachByNodeId: brandReach));
      await settleAmbiguous(tester);
      await tester.tap(find.byType(RoutexSortMenu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('이름 맞춤 순').last);
      await tester.pumpAndSettle();
      expect(find.text('이름 맞춤 순'), findsOneWidget);

      await tester.pumpWidget(buildSubject('구찌 ', reachByNodeId: brandReach));
      await settleAmbiguous(tester);

      expect(find.text('가까운 순'), findsOneWidget);
    });
  });

  // S. 서버가 자신 있게 1건을 확정하면 같은 계열 매장이 화면에서 사라졌다.
  // 설계: docs/client/search-result-list-ux.md S절.
  group('확정된 1건 아래의 같은 계열 매장', () {
    late DestinationRepository originalDestination;
    late BuildingRepository originalBuilding;
    String? picked;
    StoreIndexEntry? opened;

    setUp(() {
      originalDestination = destinationRepository;
      originalBuilding = buildingRepository;
      picked = null;
      opened = null;
    });

    tearDown(() {
      destinationRepository = originalDestination;
      buildingRepository = originalBuilding;
    });

    Widget buildSubject(
      String query, {
      Map<String, NodeReach>? reachByNodeId,
    }) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SizedBox(
          height: 700,
          child: SearchPanel(
            buildingId: 'building-1',
            query: query,
            submitTick: 0,
            onStorePicked: (_) {},
            onBuildingPicked: (_) {},
            onSuggestionPicked: (entry) => opened = entry,
            onQueryPicked: (value) => picked = value,
            indoorContextActive: true,
            reachByNodeId: reachByNodeId,
          ),
        ),
      ),
    );

    Future<void> settle(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
    }

    /// 서버가 `구찌` 1건을 확정한 상태. 온디바이스 인덱스에는 형제 둘이 더 있다.
    void useGucci({List<PoiSearchResult>? serverResults}) {
      buildingRepository = _FakeBuildingRepository(
        storeIndex: [
          _entry('구찌', '1F', nodeId: 'N1'),
          _entry('구찌 뷰티', '1F', nodeId: 'N1b'),
          _entry('구찌 선글라스', '2F', nodeId: 'N2'),
        ],
      );
      destinationRepository = _FakeDestinationRepository(
        serverResults ??
            [
              PoiSearchResult(
                name: '구찌',
                floor: '1F',
                point: const LatLng(37.5, 127.0),
                placeId: 'place-gucci',
                nodeId: 'N1',
                category: '패션',
                subcategory: '명품',
              ),
            ],
      );
    }

    testWidgets('확정된 1건 아래에 형제가 붙는다', (tester) async {
      useGucci();

      await tester.pumpWidget(buildSubject('구찌'));
      await settle(tester);

      expect(find.text('관련 매장 2곳'), findsOneWidget);
      expect(find.byKey(const Key('suggestion-PO-구찌 뷰티-1F')), findsOneWidget);
      expect(find.byKey(const Key('suggestion-PO-구찌 선글라스-2F')), findsOneWidget);
      // 확정된 매장 자신은 형제로 중복되지 않는다.
      expect(find.byKey(const Key('suggestion-PO-구찌-1F')), findsNothing);
    });

    // 사용자가 친 그 이름이라, 거리로 밀어 내리면 "이름 맞춤"이라는 말이 무너진다.
    testWidgets('정확 일치 행이 맨 위에 고정된다', (tester) async {
      useGucci();

      await tester.pumpWidget(
        buildSubject(
          '구찌',
          // 형제가 확정된 매장보다 훨씬 가깝다.
          reachByNodeId: const {
            'N1': NodeReach(distanceM: 300, costM: 300),
            'N1b': NodeReach(distanceM: 10, costM: 10),
            'N2': NodeReach(distanceM: 40, costM: 40),
          },
        ),
      );
      await settle(tester);

      final tiles = tester
          .widgetList<RoutexListCell>(find.byType(RoutexListCell))
          .toList();
      // 첫 행은 서버 결과라 Key가 없는 _storeTile이다.
      expect((tiles.first.key as ValueKey<String>?)?.value, isNull);
      expect(
        [for (final t in tiles.skip(1)) (t.key as ValueKey<String>?)?.value],
        ['suggestion-PO-구찌 뷰티-1F', 'suggestion-PO-구찌 선글라스-2F'],
      );
    });

    // 머리 행이 고정된 목록은 정렬 기준 하나로 설명되지 않는다.
    testWidgets('이 화면에는 정렬 컨트롤을 두지 않는다', (tester) async {
      useGucci();

      await tester.pumpWidget(
        buildSubject(
          '구찌',
          reachByNodeId: const {'N1': NodeReach(distanceM: 30, costM: 30)},
        ),
      );
      await settle(tester);

      expect(find.byType(RoutexSortMenu), findsNothing);
    });

    // 형제도 후보 행과 같은 위젯이라 같은 규칙을 따른다 — 한 번 눌러 그 매장이
    // 열린다. `구찌 뷰티`를 눌렀는데 `구찌 뷰티`를 다시 검색하는 화면이 뜨는 것은
    // 사용자에게 아무것도 아니다.
    testWidgets('형제를 탭하면 그 매장을 바로 연다', (tester) async {
      useGucci();

      await tester.pumpWidget(buildSubject('구찌'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('suggestion-PO-구찌 뷰티-1F')));

      expect(opened?.id, 'PO-구찌 뷰티-1F');
      expect(picked, isNull);
    });

    // 서버는 카테고리로도 확정한다(tier 1). 그때 후보는 형제가 아니라 남남이다.
    testWidgets('확정된 매장이 후보에 없으면 형제를 붙이지 않는다', (tester) async {
      buildingRepository = _FakeBuildingRepository(
        storeIndex: [
          _entry('커피 리브레', '1F', nodeId: 'N1'),
          _entry('커피빈', '2F', nodeId: 'N2'),
        ],
      );
      destinationRepository = _FakeDestinationRepository([
        PoiSearchResult(
          name: '블루보틀',
          floor: '3F',
          point: const LatLng(37.5, 127.0),
          placeId: 'place-bb',
          nodeId: 'N3',
        ),
      ]);

      await tester.pumpWidget(buildSubject('커피'));
      await settle(tester);

      expect(find.textContaining('관련 매장'), findsNothing);
    });

    // 이름으로 걸린 게 아니라 형제라는 개념 자체가 없다.
    testWidgets('의미 검색 결과에는 붙이지 않는다', (tester) async {
      buildingRepository = _FakeBuildingRepository(
        storeIndex: [
          _entry('구찌', '1F', nodeId: 'N1'),
          _entry('구찌 뷰티', '1F', nodeId: 'N1b'),
        ],
      );
      destinationRepository = _FakeDestinationRepository(
        const [],
        discovery: const DiscoveryResult(
          mode: DiscoveryMode.results,
          query: '구찌',
          matches: [
            DiscoveryMatch(
              storeId: 'place-x',
              name: '구찌',
              category: '패션',
              subcategory: '명품',
              floorId: 'FL-1F',
              floorName: '1F',
              entranceNodeId: 'N1',
              point: LatLng(37.5, 127.0),
              matchedFacets: {},
              reason: '뜻이 비슷해요',
            ),
          ],
        ),
      );

      await tester.pumpWidget(buildSubject('구찌'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();

      expect(find.textContaining('관련 매장'), findsNothing);
    });
  });

  // R. 못 찾았을 때의 탈출구.
  group('결과 없음 — 카테고리로 둘러보기', () {
    late DestinationRepository originalDestination;
    late BuildingRepository originalBuilding;
    String? pickedCategory;

    setUp(() {
      originalDestination = destinationRepository;
      originalBuilding = buildingRepository;
      buildingRepository = _FakeBuildingRepository();
      destinationRepository = _FakeDestinationRepository(const []);
      pickedCategory = null;
    });

    tearDown(() {
      destinationRepository = originalDestination;
      buildingRepository = originalBuilding;
    });

    Widget buildSubject({
      bool indoor = true,
      Future<List<CategoryCount>>? categoryEntries,
    }) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: SearchPanel(
            buildingId: 'building-1',
            query: '읿ㄹ힣ㅎ',
            submitTick: 0,
            onStorePicked: (_) {},
            onBuildingPicked: (_) {},
            onSuggestionPicked: (_) {},
            onQueryPicked: (_) {},
            indoorContextActive: indoor,
            categoryEntries: categoryEntries,
            onCategoryPicked: (value) => pickedCategory = value,
          ),
        ),
      ),
    );

    /// 경량(300ms) + 의미(400ms)를 모두 지나 noMatch가 확정된 뒤.
    Future<void> settleNoMatch(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
    }

    Future<List<CategoryCount>> categories() async => const [
      CategoryCount(floor: '1F', category: '패션', subcategory: null, count: 3),
      CategoryCount(floor: '2F', category: '뷰티', subcategory: null, count: 2),
      CategoryCount(floor: '1F', category: '패션', subcategory: null, count: 1),
    ];

    testWidgets('실내에서는 대분류 chip 줄이 뜬다', (tester) async {
      await tester.pumpWidget(buildSubject(categoryEntries: categories()));
      await settleNoMatch(tester);

      expect(find.text('카테고리로 둘러보기'), findsOneWidget);
      // 중복 대분류는 한 번만.
      expect(find.byKey(const Key('browse-category-패션')), findsOneWidget);
      expect(find.byKey(const Key('browse-category-뷰티')), findsOneWidget);
    });

    testWidgets('chip을 누르면 그 대분류를 상위에 알린다', (tester) async {
      await tester.pumpWidget(buildSubject(categoryEntries: categories()));
      await settleNoMatch(tester);
      await tester.tap(find.byKey(const Key('browse-category-뷰티')));

      expect(pickedCategory, '뷰티');
    });

    // 아직 들어가지도 않은 건물의 카테고리를 누르게 되고, 지도 강조는 도면 위에
    // 그려지므로 결과가 보이지 않는다.
    testWidgets('야외에서는 그리지 않는다', (tester) async {
      await tester.pumpWidget(
        buildSubject(indoor: false, categoryEntries: categories()),
      );
      await settleNoMatch(tester);

      expect(find.text('카테고리로 둘러보기'), findsNothing);
      expect(find.textContaining('찾지 못했어요'), findsOneWidget);
    });

    testWidgets('카테고리를 못 받으면 줄만 조용히 사라진다', (tester) async {
      // FutureBuilder는 "찾지 못했어요" 화면에서야 트리에 붙는다. 그 전에
      // 실패한 Future는 듣는 사람이 없어 테스트 프레임워크가 미처리 오류로
      // 잡으므로, 여기서 한 번 흘려 준다. 실패 자체는 그대로 남는다.
      final failing = Future<List<CategoryCount>>.error(Exception('boom'));
      failing.ignore();

      await tester.pumpWidget(buildSubject(categoryEntries: failing));
      await settleNoMatch(tester);

      expect(find.text('카테고리로 둘러보기'), findsNothing);
      expect(find.textContaining('찾지 못했어요'), findsOneWidget);
    });
  });

  group('reachLabel', () {
    // 거리는 실제 이동 거리, 시간은 비용 기준이다. 엘리베이터 대기·탑승이
    // 비용에만 들어 있어서, 시간까지 거리로 계산하면 다른 층 매장이 실제보다
    // 가깝게 느껴진다.
    test('거리는 distanceM으로, 시간은 costM으로 계산한다', () {
      final label = reachLabel(const NodeReach(distanceM: 20, costM: 200));

      // 거리 20m는 그대로, 시간은 200m 등가라 200/1.2/60 ≈ 2.8분 → 3분.
      expect(label, '20m · 도보 3분');
    });

    test('아주 가까워도 0분이 아니라 1분으로 올린다', () {
      final label = reachLabel(const NodeReach(distanceM: 3, costM: 3));

      expect(label, '3m · 도보 1분');
    });
  });

  group('검색 결과의 건물 한 줄', () {
    // 이 그룹이 지키는 증상: 야외에서 "더현대"를 쳐도 건물 위치로 지도가
    // 움직이지 않던 문제. 지도를 옮기는 것은 상위 화면이지만, 그 콜백이
    // 불리려면 **건물 한 줄이 실제로 그려지고 눌려야** 한다. 여기서 그 앞단을
    // 못 박아, 다음에 같은 증상이 나면 원인이 이쪽인지 지도 쪽인지 바로 갈린다.
    late DestinationRepository originalDestination;
    late BuildingRepository originalBuilding;

    const building = Building(
      id: 'thehyundai-seoul',
      name: '더현대 서울',
      floors: ['6F', '1F', 'B1', 'B2'],
    );

    setUp(() {
      originalDestination = destinationRepository;
      originalBuilding = buildingRepository;
      buildingRepository = _FakeBuildingRepository(buildings: const [building]);
      destinationRepository = _FakeDestinationRepository(const []);
    });

    tearDown(() {
      destinationRepository = originalDestination;
      buildingRepository = originalBuilding;
    });

    Widget buildSubject({
      required ValueChanged<Building> onBuildingPicked,
      bool indoorContextActive = false,
    }) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SizedBox(
          height: 400,
          child: SearchPanel(
            buildingId: 'thehyundai-seoul',
            query: '더현대',
            submitTick: 0,
            onStorePicked: (_) {},
            onBuildingPicked: onBuildingPicked,
            onSuggestionPicked: (_) {},
            onQueryPicked: (_) {},
            indoorContextActive: indoorContextActive,
          ),
        ),
      ),
    );

    Future<void> settleSearch(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
    }

    testWidgets('이름이 겹치는 건물이 있으면 한 줄로 뜬다', (WidgetTester tester) async {
      await tester.pumpWidget(buildSubject(onBuildingPicked: (_) {}));
      await settleSearch(tester);

      expect(find.text('더현대 서울'), findsOneWidget);
      expect(find.text('건물 · 4개 층'), findsOneWidget);
    });

    testWidgets('그 줄을 누르면 건물이 상위로 전달된다', (WidgetTester tester) async {
      Building? picked;
      await tester.pumpWidget(
        buildSubject(onBuildingPicked: (b) => picked = b),
      );
      await settleSearch(tester);

      await tester.tap(find.text('더현대 서울'));
      await tester.pumpAndSettle();

      expect(
        picked?.id,
        'thehyundai-seoul',
        reason: '이 콜백이 안 불리면 지도를 옮길 기회 자체가 없다',
      );
    });

    testWidgets('건물 안을 보고 있어도 그 줄은 그대로 뜬다', (WidgetTester tester) async {
      // 실내에서 건물 이름을 다시 검색하는 경우다. 여기서 줄이 사라지면
      // "실내에서는 건물로 못 돌아간다"가 된다.
      Building? picked;
      await tester.pumpWidget(
        buildSubject(
          onBuildingPicked: (b) => picked = b,
          indoorContextActive: true,
        ),
      );
      await settleSearch(tester);

      expect(find.text('더현대 서울'), findsOneWidget);
      await tester.tap(find.text('더현대 서울'));
      await tester.pumpAndSettle();
      expect(picked?.id, 'thehyundai-seoul');
    });
  });
}

PoiSearchResult _result({
  required String? subcategory,
  required String? category,
}) => PoiSearchResult(
  name: '나이키 강남',
  floor: '3F',
  point: const LatLng(37.5, 127.0),
  placeId: 'place-1',
  nodeId: 'node-1',
  category: category,
  subcategory: subcategory,
);

/// 정렬 테스트용. 층 이름이 그대로 화면에 나오는 유일한 평문이라, 목록 순서는
/// 이 값의 세로 위치로 잰다(이름은 `Text.rich`라 `find.text`로 못 집는다).
PoiSearchResult _store({
  required String name,
  required String floor,
  required String nodeId,
  required String placeId,
}) => PoiSearchResult(
  name: name,
  floor: floor,
  point: const LatLng(37.5, 127.0),
  placeId: placeId,
  nodeId: nodeId,
);

/// 이름·층만 다르면 되는 게이트 테스트용 축약. 근거 문구·노드까지 지정하는
/// [_match]와 달리 "무엇이 화면에 남는가"만 본다.
DiscoveryMatch _gateMatch(String name, String floor) => _match(
  name: name,
  floor: floor,
  node: 'node-$name',
  id: 'id-$name',
  reason: '',
);

DiscoveryMatch _match({
  required String name,
  required String floor,
  required String node,
  required String id,
  required String reason,
}) => DiscoveryMatch(
  storeId: id,
  name: name,
  category: '패션',
  subcategory: null,
  floorId: 'floor-$floor',
  floorName: floor,
  entranceNodeId: node,
  point: const LatLng(37.5, 127.0),
  matchedFacets: const {},
  reason: reason,
);

class _FakeDestinationRepository implements DestinationRepository {
  _FakeDestinationRepository(this.results, {this.discovery});

  final List<PoiSearchResult> results;

  /// 2차 의미 검색 응답. 주지 않으면 `no_match`라 1차에서 끝나는 경로만 탄다.
  final DiscoveryResult? discovery;

  /// 의미 검색을 몇 번 불렀는지. "아예 안 불렀다"를 검증하려면 결과가 아니라
  /// 호출 자체를 세야 한다.
  int aiCallCount = 0;

  /// 경량 검색이 받은 층 스코프를 순서대로 기록한다.
  final List<String?> floorScopes = [];

  @override
  Future<List<PoiSearchResult>> searchDestinations(
    String buildingId,
    String query, {
    String? currentFloorId,
  }) async {
    floorScopes.add(currentFloorId);
    return results;
  }

  @override
  Future<DiscoveryResult> searchDestinationsAi(
    String buildingId,
    String query, {
    String? currentFloorId,
    Map<String, List<String>>? selectedFacets,
    bool showAll = false,
  }) async {
    aiCallCount++;
    return discovery ??
        DiscoveryResult(mode: DiscoveryMode.noMatch, query: query);
  }
}

/// [nodeId]를 주면 그 매장까지의 거리를 잴 수 있다(O절). 안 주면 예전과 같이
/// 거리를 모르는 매장이라, 후보 줄에 거리가 붙지 않는다.
StoreIndexEntry _entry(String name, String floor, {String? nodeId}) =>
    StoreIndexEntry(
      // 같은 이름이 층마다 있는 시설은 id도 층으로 갈라야 한다. 이름만으로 id를
      // 만들면 대표가 바뀌어도 Key가 그대로라 테스트가 통과해 버린다.
      id: nodeId == null ? 'PO-$name' : 'PO-$name-$floor',
      name: name,
      floorId: 'FL-$floor',
      floorName: floor,
      entranceNodeId: nodeId,
    );

/// 이 화면이 실제로 부르는 것은 `getAllBuildings`·`getStoreIndex` 둘뿐이다.
/// 나머지는 [noSuchMethod]로 열어 둬 인터페이스가 늘어도 이 테스트가 깨지지
/// 않게 한다.
class _FakeBuildingRepository implements BuildingRepository {
  _FakeBuildingRepository({
    this.storeIndex,
    this.storeIndexFails = false,
    this.buildings = const [],
  });

  /// `getAllBuildings()`가 돌려줄 목록. 검색 패널은 여기서 질의와 이름이
  /// 겹치는 건물을 찾아 결과 맨 위에 건물 한 줄을 세운다.
  final List<Building> buildings;

  final List<StoreIndexEntry>? storeIndex;

  /// 자동완성 원본을 못 받는 상태. 앱이 죽지 않고 후보만 사라져야 한다.
  final bool storeIndexFails;

  @override
  Future<List<Building>> getAllBuildings() async => buildings;

  /// 원본을 몇 번 받아갔는지. 야외에서 "받지 않는다"를 검증하려면 결과가 아니라
  /// 호출 자체를 세야 한다.
  int storeIndexCallCount = 0;

  @override
  Future<List<StoreIndexEntry>?> getStoreIndex(String buildingId) async {
    storeIndexCallCount++;
    if (storeIndexFails) throw Exception('store-index 실패');
    return storeIndex;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
