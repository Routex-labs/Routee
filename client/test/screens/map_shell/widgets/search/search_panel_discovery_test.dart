import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/building/category_count.dart';
import 'package:navigation_client/models/place/store_index_entry.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/models/building/building.dart';
import 'package:navigation_client/models/building/building_graph.dart';
import 'package:navigation_client/models/place/discovery_result.dart';
import 'package:navigation_client/models/route/indoor_route.dart';
import 'package:navigation_client/models/place/poi_search_result.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/screens/map_shell/widgets/search/search_panel.dart';

/// SearchPanel의 **대화형 탐색(discovery) 흐름** 테스트.
///
/// 경량 검색 → 의미 검색으로 넘어가는 시점, clarify 질문·선택·전체 보기,
/// 층 스코프 전달이 여기 있다. 렌더링·정렬 같은 나머지 동작은 같은 폴더의
/// `search_panel_test.dart`가 맡는다 — 한 파일에 63개가 이미 있어 더 붙이면
/// 무엇이 깨졌는지 이름만 보고 알 수 없다.

void main() {
  group('SearchPanel', () {
    // 이 그룹의 관심사는 "의미 검색이 언제 도는가"와 "최종 없음 문구가 언제
    // 나오는가" 두 가지다. 예전에는 엔터(submitTick)가 올라야만 의미 검색이
    // 돌았고, 그 전까지 경량이 빈손이면 화면에는 "찾지 못했어요"가 최종
    // 결론처럼 떠 있었다. 한글 IME에서 첫 엔터가 조합 확정에 쓰이면 엔터가
    // 아예 안 와서 의미 검색이 시작조차 안 됐다.
    late DestinationRepository originalDestinations;
    late BuildingRepository originalBuildings;

    setUp(() {
      originalDestinations = destinationRepository;
      originalBuildings = buildingRepository;
      buildingRepository = _FakeBuildingRepository();
    });
    tearDown(() {
      destinationRepository = originalDestinations;
      buildingRepository = originalBuildings;
    });

    // 상위가 검색어와 엔터 횟수를 내려주는 구조라, 테스트에서도 그 두 값만
    // 바꿔 끼운다. 패널 내부 메서드를 직접 부르지 않는 게 실제 사용 경로다.
    final query = ValueNotifier<String>('');
    final submitTick = ValueNotifier<int>(0);

    Future<void> pumpPanel(
      WidgetTester tester, {
      String? currentFloorId,
      ValueChanged<PoiSearchResult>? onStorePicked,
    }) {
      query.value = '';
      submitTick.value = 0;
      return tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ListenableBuilder(
              listenable: Listenable.merge([query, submitTick]),
              builder: (_, _) => SearchPanel(
                buildingId: 'thehyundai-seoul',
                query: query.value,
                submitTick: submitTick.value,
                onStorePicked: onStorePicked ?? (_) {},
                onBuildingPicked: (_) {},
                // 실제 화면(MapShellScreen)이 하는 것과 같다 — 골라진 말로
                // 검색창을 채우고 확정 카운터를 올려 한 바퀴를 다시 돌린다.
                onSuggestionPicked: (_) {},
                onQueryPicked: (value) {
                  query.value = value;
                  submitTick.value++;
                },
                indoorContextActive: true,
                currentFloorId: currentFloorId,
              ),
            ),
          ),
        ),
      );
    }

    /// 마이크로태스크만 흘려보낸다(가짜 시계는 그대로). 대기 시간을 실제로
    /// 건너뛰었는지 확인해야 하는 검증에서 시간을 흘리면 의미가 없어진다.
    Future<void> flush(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
    }

    /// 경량 디바운스(300ms) → 경량 응답 → 의미 대기(400ms) → 의미 응답까지
    /// 한 번에 흘려보낸다. `pumpAndSettle`을 쓰지 않는 이유는 그 함수가 **프레임이
    /// 예약돼 있는 동안만** 시계를 돌리기 때문이다. 디바운스 타이머만 남은 구간은
    /// 프레임을 예약하지 않아서 pumpAndSettle이 그냥 즉시 돌아온다.
    Future<void> settleSearch(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 350));
      await flush(tester);
      await tester.pump(const Duration(milliseconds: 450));
      await flush(tester);
    }

    /// 아직 응답을 안 준 느린 호출을 끝까지 흘려보낸다. 타이머가 남은 채 테스트가
    /// 끝나면 프레임워크가 실패로 잡는다.
    Future<void> drain(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 6));
      await flush(tester);
    }

    const store = PoiSearchResult(
      name: '스시코우지',
      floor: 'B1',
      point: LatLng(37.52, 126.92),
      nodeId: 'FL-1:ND-1',
    );

    testWidgets('경량이 빈손이어도 의미 검색 전에는 최종 없음 문구를 띄우지 않는다', (
      WidgetTester tester,
    ) async {
      // "신발"은 어떤 매장명·카테고리와도 정확히 일치하지 않아 경량이 항상 빈손이다.
      destinationRepository = _FakeSearchRepository(
        aiResults: const [store],
        aiDelay: const Duration(seconds: 5),
      );
      await pumpPanel(tester);

      query.value = '신발';
      await tester.pump();
      // 경량 디바운스(300ms)만 지난 시점 — 경량은 끝났고 의미 검색은 아직이다.
      await tester.pump(const Duration(milliseconds: 320));
      await flush(tester);

      expect(find.textContaining('찾지 못했어요'), findsNothing);
      expect(find.byType(RoutexSkeletonList), findsOneWidget);
    });

    testWidgets('엔터 없이 debounce만으로 의미 검색이 호출된다', (WidgetTester tester) async {
      final repository = _FakeSearchRepository(aiResults: const [store]);
      destinationRepository = repository;
      await pumpPanel(tester);

      query.value = '신발';
      await tester.pump();
      // submitTick은 그대로 0이다. 엔터를 누르지 않았다는 뜻.
      await settleSearch(tester);

      expect(submitTick.value, 0);
      expect(repository.aiQueries, ['신발']);
      expect(find.text('스시코우지'), findsOneWidget);
      // 왜 다른 이름이 나왔는지 알려 주는 배너는 그대로 유지한다.
      expect(find.text('뜻이 비슷한 매장을 찾았어요'), findsOneWidget);
    });

    testWidgets('의미 검색 결과가 질의와 이름이 정확히 같으면 배너를 띄우지 않는다', (
      WidgetTester tester,
    ) async {
      // 층 스코프(ea315b8) 적용 뒤: 1F에서 타 층 "나이키"를 정확한 이름으로
      // 검색하면 1차(현재 층 한정)는 빈손이고 2차 의미 검색이 찾아낸다. 이때는
      // 뜻으로 찾은 게 아니라 정확한 이름 일치이므로 "뜻이 비슷한" 배너가
      // 붙으면 안 된다.
      const nike = PoiSearchResult(
        name: '나이키',
        floor: '3F',
        point: LatLng(37.52, 126.92),
        nodeId: 'FL-3:ND-1',
      );
      final repository = _FakeSearchRepository(aiResults: const [nike]);
      destinationRepository = repository;
      await pumpPanel(tester, currentFloorId: '1F');

      query.value = '나이키';
      await tester.pump();
      await settleSearch(tester);

      expect(repository.aiQueries, ['나이키']);
      expect(find.text('나이키'), findsOneWidget);
      expect(find.text('뜻이 비슷한 매장을 찾았어요'), findsNothing);
    });

    testWidgets('의미 검색까지 빈손이어야 최종 없음 문구를 띄운다', (WidgetTester tester) async {
      final repository = _FakeSearchRepository();
      destinationRepository = repository;
      await pumpPanel(tester);

      query.value = 'asdfqwerzxcv';
      await tester.pump();
      await settleSearch(tester);

      expect(repository.aiQueries, ['asdfqwerzxcv']);
      expect(find.textContaining('찾지 못했어요'), findsOneWidget);
      expect(find.text('다른 말로 바꿔서 다시 찾아보세요.'), findsOneWidget);
    });

    testWidgets('의미 검색으로 넘어가면 다른 문구를 띄운다', (WidgetTester tester) async {
      // 여기서부터 수 초가 걸릴 수 있어, 같은 스피너만 돌면 멈춘 것처럼 보인다.
      destinationRepository = _FakeSearchRepository(
        aiDelay: const Duration(seconds: 5),
      );
      await pumpPanel(tester);

      query.value = '신발';
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await flush(tester);

      expect(find.textContaining('취향에 맞는 매장을 찾는 중'), findsOneWidget);
      expect(find.textContaining('찾지 못했어요'), findsNothing);

      await drain(tester);
    });

    testWidgets('엔터는 대기를 건너뛰고 즉시 의미 검색을 태운다', (WidgetTester tester) async {
      destinationRepository = _FakeSearchRepository(
        aiDelay: const Duration(seconds: 5),
      );
      await pumpPanel(tester);

      query.value = '신발';
      submitTick.value = 1;
      await tester.pump();
      // 가짜 시계를 1ms도 돌리지 않았는데 이미 의미 검색 단계다.
      await flush(tester);

      expect(find.textContaining('취향에 맞는 매장을 찾는 중'), findsOneWidget);

      await drain(tester);
    });

    testWidgets('경량이 잡으면 의미 검색을 부르지 않는다', (WidgetTester tester) async {
      final repository = _FakeSearchRepository(lightResults: const [store]);
      destinationRepository = repository;
      await pumpPanel(tester);

      query.value = '스시코우지';
      await tester.pump();
      await settleSearch(tester);

      expect(repository.aiQueries, isEmpty);
      expect(find.text('스시코우지'), findsOneWidget);
      // 경량 결과에는 "뜻으로 찾았다" 배너를 붙이지 않는다.
      expect(find.text('뜻이 비슷한 매장을 찾았어요'), findsNothing);
    });

    testWidgets('타이핑이 이어지면 중간 글자로 의미 검색을 태우지 않는다', (WidgetTester tester) async {
      // 의미 검색은 백엔드 모델 로드로 첫 호출이 6초대까지 간다. "신"·"신바"가
      // 각각 모델을 태우면 안 된다.
      final repository = _FakeSearchRepository();
      destinationRepository = repository;
      await pumpPanel(tester);

      query.value = '신';
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await flush(tester);
      query.value = '신바';
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await flush(tester);
      query.value = '신발';
      await tester.pump();
      await settleSearch(tester);

      expect(repository.aiQueries, ['신발']);
    });

    testWidgets('서버 장애는 결과 없음과 다른 문구로 구분한다', (WidgetTester tester) async {
      // 백엔드가 죽었을 뿐인데 "그런 매장은 없다"고 말하면 안 된다.
      destinationRepository = _FakeSearchRepository(fail: true);
      await pumpPanel(tester);

      query.value = '신발';
      await tester.pump();
      await settleSearch(tester);

      expect(find.textContaining('찾지 못했어요'), findsNothing);
      // 문구만 다른 것이 아니라 **할 수 있는 일**이 다르다. 결과 없음에는 다시
      // 시도할 것이 없고, 여기에는 있다.
      expect(find.widgetWithText(RoutexButton, '다시 시도'), findsOneWidget);
    });

    testWidgets('현재 층이 주어지면 경량·의미 검색 요청 모두에 실어 보낸다', (
      WidgetTester tester,
    ) async {
      // "화장실"은 tier 1(카테고리 정확 일치)로 경량이 빈손이라, 의미 검색까지
      // 이어진다 — 두 요청 모두 층이 실제로 실리는지 확인해야 한다.
      final repository = _FakeSearchRepository(aiResults: const [store]);
      destinationRepository = repository;
      await pumpPanel(tester, currentFloorId: '1F');

      query.value = '화장실';
      await tester.pump();
      await settleSearch(tester);

      expect(repository.lightFloorIds, ['1F']);
      expect(repository.aiFloorIds, ['1F']);
    });

    testWidgets('현재 층이 없으면(야외 모드 등) null을 그대로 보낸다', (
      WidgetTester tester,
    ) async {
      final repository = _FakeSearchRepository();
      destinationRepository = repository;
      await pumpPanel(tester);

      query.value = '화장실';
      await tester.pump();
      await settleSearch(tester);

      expect(repository.lightFloorIds, [null]);
      expect(repository.aiFloorIds, [null]);
    });

    testWidgets('검색어를 지우면 안내 문구로 돌아간다', (WidgetTester tester) async {
      destinationRepository = _FakeSearchRepository();
      await pumpPanel(tester);

      query.value = 'asdfqwerzxcv';
      await tester.pump();
      await settleSearch(tester);
      expect(find.textContaining('찾지 못했어요'), findsOneWidget);

      query.value = '';
      await tester.pump();
      await settleSearch(tester);

      expect(find.textContaining('찾지 못했어요'), findsNothing);
      expect(find.textContaining('매장 이름을 입력하면'), findsOneWidget);
    });

    testWidgets('clarify 질문·후보 이유를 표시하고 facet 전체를 다시 보낸다', (
      WidgetTester tester,
    ) async {
      final repository = _ScriptedDiscoveryRepository([
        DiscoveryResult(
          mode: DiscoveryMode.clarify,
          query: '신발',
          question: '어떤 스타일의 신발을 찾으세요?',
          options: const [
            DiscoveryOption(
              facet: 'styles',
              value: '스포츠',
              label: '스포츠',
              count: 3,
            ),
          ],
          matches: const [
            DiscoveryMatch(
              storeId: 'ST-NIKE',
              name: '나이키 라이즈',
              category: '패션',
              subcategory: '스포츠',
              floorId: 'FL-3',
              floorName: '3F',
              entranceNodeId: 'FL-3:ND-1',
              point: LatLng(37.52, 126.92),
              matchedFacets: {
                'styles': ['스포츠'],
              },
              reason: '스포츠 신발을 찾을 때 볼 만해요.',
            ),
          ],
        ),
        DiscoveryResult(
          mode: DiscoveryMode.results,
          query: '신발',
          matches: const [
            DiscoveryMatch(
              storeId: 'ST-NIKE',
              name: '나이키 라이즈',
              category: '패션',
              subcategory: '스포츠',
              floorId: 'FL-3',
              floorName: '3F',
              entranceNodeId: 'FL-3:ND-1',
              point: LatLng(37.52, 126.92),
              matchedFacets: {
                'styles': ['스포츠'],
              },
              reason: '스포츠 신발을 찾을 때 볼 만해요.',
            ),
          ],
        ),
      ]);
      destinationRepository = repository;
      await pumpPanel(tester, currentFloorId: '1F');

      query.value = '신발';
      await tester.pump();
      await settleSearch(tester);

      expect(find.text('어떤 스타일의 신발을 찾으세요?'), findsOneWidget);
      expect(find.text('스포츠 (3)'), findsOneWidget);
      // 층이 앞에 붙는다. 결과가 한 건이라 되풀이가 없어 근거는 그대로 남는다.
      expect(find.textContaining('3F · 스포츠 신발을 찾을 때 볼 만해요.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('facet-option-styles-스포츠')));
      await flush(tester);

      expect(
        find.byKey(const Key('selected-facet-styles-스포츠')),
        findsOneWidget,
      );
      expect(repository.selectedFacets, [
        null,
        {
          'styles': ['스포츠'],
        },
      ]);
      expect(repository.showAllValues, [false, false]);
      expect(repository.floorIds, ['1F', '1F']);
    });

    testWidgets('전체 보기와 다시 선택은 새 요청으로 상태를 되돌린다', (WidgetTester tester) async {
      final clarify = DiscoveryResult(
        mode: DiscoveryMode.clarify,
        query: '신발',
        question: '어떤 스타일의 신발을 찾으세요?',
        options: const [
          DiscoveryOption(
            facet: 'styles',
            value: '스포츠',
            label: '스포츠',
            count: 3,
          ),
        ],
      );
      const match = DiscoveryMatch(
        storeId: 'ST-NIKE',
        name: '나이키 라이즈',
        category: '패션',
        subcategory: '스포츠',
        floorId: 'FL-3',
        floorName: '3F',
        entranceNodeId: 'FL-3:ND-1',
        point: LatLng(37.52, 126.92),
        matchedFacets: {
          'styles': ['스포츠'],
        },
        reason: '스포츠 신발을 찾을 때 볼 만해요.',
      );
      final repository = _ScriptedDiscoveryRepository([
        clarify,
        const DiscoveryResult(
          mode: DiscoveryMode.results,
          query: '신발',
          matches: [match],
        ),
        const DiscoveryResult(
          mode: DiscoveryMode.results,
          query: '신발',
          matches: [match],
        ),
        clarify,
      ]);
      destinationRepository = repository;
      await pumpPanel(tester);

      query.value = '신발';
      await tester.pump();
      await settleSearch(tester);
      await tester.tap(find.byKey(const Key('facet-option-styles-스포츠')));
      await flush(tester);
      await tester.tap(find.byKey(const Key('show-all')));
      await flush(tester);
      await tester.tap(find.byKey(const Key('choose-again')));
      await flush(tester);

      expect(repository.showAllValues, [false, false, true, false]);
      expect(repository.selectedFacets, [
        null,
        {
          'styles': ['스포츠'],
        },
        {
          'styles': ['스포츠'],
        },
        null,
      ]);
      expect(find.text('어떤 스타일의 신발을 찾으세요?'), findsOneWidget);
    });

    testWidgets('direct 1건에는 clarify 조작 버튼을 띄우지 않는다', (
      WidgetTester tester,
    ) async {
      // 회귀 대상: 두 버튼이 조건 없이 렌더돼 되물음이 없는 화면에도 떴다.
      // "커피"가 1건으로 확정된 direct 화면에서 누를 대상 없는 버튼이 보였다.
      final repository = _ScriptedDiscoveryRepository([
        const DiscoveryResult(
          mode: DiscoveryMode.direct,
          query: '커피',
          matches: [
            DiscoveryMatch(
              storeId: 'ST-DOJO',
              name: '도조 커피',
              category: '카페',
              subcategory: '카페·베이커리',
              floorId: 'FL-B1',
              floorName: 'B1',
              entranceNodeId: 'FL-B1:ND-1',
              point: LatLng(37.52, 126.92),
              matchedFacets: {},
              reason: null,
            ),
          ],
        ),
      ]);
      destinationRepository = repository;
      await pumpPanel(tester);

      query.value = '커피';
      await tester.pump();
      await settleSearch(tester);

      expect(find.text('도조 커피'), findsOneWidget);
      expect(find.byKey(const Key('show-all')), findsNothing);
      expect(find.byKey(const Key('choose-again')), findsNothing);
    });

    testWidgets('clarify에서는 전체 보기만, 선택 뒤에는 다시 선택도 뜬다', (
      WidgetTester tester,
    ) async {
      // 되돌릴 답이 없는 첫 clarify 화면에서 "다시 선택"은 같은 질문을 다시 부르는
      // 빈 동작이라 노출하지 않는다. 선택이 생긴 뒤에만 의미가 있다.
      const option = DiscoveryOption(
        facet: 'styles',
        value: '스포츠',
        label: '스포츠',
        count: 3,
      );
      const match = DiscoveryMatch(
        storeId: 'ST-NIKE',
        name: '나이키 라이즈',
        category: '패션',
        subcategory: '스포츠',
        floorId: 'FL-3',
        floorName: '3F',
        entranceNodeId: 'FL-3:ND-1',
        point: LatLng(37.52, 126.92),
        matchedFacets: {
          'styles': ['스포츠'],
        },
        reason: '스포츠 스타일 매장이에요.',
      );
      final repository = _ScriptedDiscoveryRepository([
        const DiscoveryResult(
          mode: DiscoveryMode.clarify,
          query: '신발',
          question: '어떤 스타일을 찾으세요?',
          options: [option],
          matches: [match],
        ),
        const DiscoveryResult(
          mode: DiscoveryMode.results,
          query: '신발',
          matches: [match],
        ),
      ]);
      destinationRepository = repository;
      await pumpPanel(tester);

      query.value = '신발';
      await tester.pump();
      await settleSearch(tester);

      expect(find.byKey(const Key('show-all')), findsOneWidget);
      expect(find.byKey(const Key('choose-again')), findsNothing);

      await tester.tap(find.byKey(const Key('facet-option-styles-스포츠')));
      await flush(tester);

      expect(find.byKey(const Key('choose-again')), findsOneWidget);
    });

    testWidgets('전체 보기로 넘어간 화면에는 다시 선택만 남는다', (WidgetTester tester) async {
      // 선택 없이 질문만 건너뛴 상태다. 여기서 "다시 선택"은 질문으로 돌아가는
      // 유일한 길이라 남아야 하고, "전체 보기"는 이미 전체라 눌러도 그대로다.
      const option = DiscoveryOption(
        facet: 'styles',
        value: '스포츠',
        label: '스포츠',
        count: 3,
      );
      const match = DiscoveryMatch(
        storeId: 'ST-NIKE',
        name: '나이키 라이즈',
        category: '패션',
        subcategory: '스포츠',
        floorId: 'FL-3',
        floorName: '3F',
        entranceNodeId: 'FL-3:ND-1',
        point: LatLng(37.52, 126.92),
        matchedFacets: {},
        reason: null,
      );
      final repository = _ScriptedDiscoveryRepository([
        const DiscoveryResult(
          mode: DiscoveryMode.clarify,
          query: '신발',
          question: '어떤 스타일을 찾으세요?',
          options: [option],
          matches: [match],
        ),
        const DiscoveryResult(
          mode: DiscoveryMode.results,
          query: '신발',
          matches: [match],
        ),
      ]);
      destinationRepository = repository;
      await pumpPanel(tester);

      query.value = '신발';
      await tester.pump();
      await settleSearch(tester);
      await tester.tap(find.byKey(const Key('show-all')));
      await flush(tester);

      expect(find.byKey(const Key('show-all')), findsNothing);
      expect(find.byKey(const Key('choose-again')), findsOneWidget);
    });

    testWidgets('결과가 패널 높이를 넘으면 스크롤로 끝까지 볼 수 있다', (WidgetTester tester) async {
      // 패널은 상위(map_shell)가 maxHeight로 묶는다. 그 높이를 넘는 결과가
      // 왔을 때 목록이 스크롤되지 않으면 뒤쪽 후보는 영영 못 본다.
      final matches = [
        for (var i = 0; i < 30; i++)
          DiscoveryMatch(
            storeId: 'ST-$i',
            name: '매장$i',
            category: '패션',
            subcategory: '컨템포러리',
            floorId: 'FL-1',
            floorName: '1F',
            entranceNodeId: 'FL-1:ND-1',
            point: const LatLng(37.52, 126.92),
            matchedFacets: const {},
            reason: null,
          ),
      ];
      destinationRepository = _ScriptedDiscoveryRepository([
        DiscoveryResult(
          mode: DiscoveryMode.results,
          query: '의류',
          matches: matches,
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ListenableBuilder(
              listenable: Listenable.merge([query, submitTick]),
              builder: (_, _) => ConstrainedBox(
                // 상위가 거는 maxHeight를 그대로 흉내낸다.
                constraints: const BoxConstraints(maxHeight: 400),
                child: SearchPanel(
                  buildingId: 'thehyundai-seoul',
                  query: query.value,
                  submitTick: submitTick.value,
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

      query.value = '의류';
      await tester.pump();
      await settleSearch(tester);

      // 존재 여부가 아니라 **뷰포트 안에 보이는지**로 본다. 목록을 한꺼번에
      // 만들므로 마지막 항목도 트리에는 처음부터 있다.
      expect(find.text('매장0'), findsOneWidget);
      final viewport = tester.getRect(find.byType(SingleChildScrollView));
      expect(
        tester.getRect(find.text('매장29')).top,
        greaterThan(viewport.bottom),
        reason: '스크롤 전에는 마지막 항목이 패널 아래에 있어야 한다',
      );

      await tester.drag(find.text('매장0'), const Offset(0, -2000));
      await tester.pumpAndSettle();

      expect(
        tester.getRect(find.text('매장29')).bottom,
        lessThanOrEqualTo(viewport.bottom),
        reason: '끝까지 스크롤하면 마지막 항목이 보여야 한다',
      );
    });

    testWidgets('탐색 결과의 매장을 고르면 기존 길찾기 콜백으로 그대로 연결된다', (
      WidgetTester tester,
    ) async {
      // clarify에도 초기 후보(matches)가 함께 오므로, 질문에 답하기 전에도
      // 매장을 바로 선택할 수 있어야 한다 — 별도 경로를 새로 만들지 않고
      // 기존 onStorePicked 콜백을 그대로 탄다.
      const match = DiscoveryMatch(
        storeId: 'ST-NIKE',
        name: '나이키 라이즈',
        category: '패션',
        subcategory: '스포츠',
        floorId: 'FL-3',
        floorName: '3F',
        entranceNodeId: 'FL-3:ND-1',
        point: LatLng(37.52, 126.92),
        matchedFacets: {
          'styles': ['스포츠'],
        },
        reason: '스포츠 신발을 찾을 때 볼 만해요.',
      );
      final repository = _ScriptedDiscoveryRepository([
        const DiscoveryResult(
          mode: DiscoveryMode.clarify,
          query: '신발',
          question: '어떤 스타일의 신발을 찾으세요?',
          options: [
            DiscoveryOption(
              facet: 'styles',
              value: '스포츠',
              label: '스포츠',
              count: 3,
            ),
          ],
          matches: [match],
        ),
      ]);
      destinationRepository = repository;
      PoiSearchResult? picked;
      await pumpPanel(tester, onStorePicked: (store) => picked = store);

      query.value = '신발';
      await tester.pump();
      await settleSearch(tester);

      await tester.tap(find.text('나이키 라이즈'));
      await flush(tester);

      expect(picked, isNotNull);
      expect(picked!.name, '나이키 라이즈');
      expect(picked!.nodeId, 'FL-3:ND-1');
    });
  });
}

/// [SearchPanel]은 경량·의미 두 경로를 모두 쓰므로 각각 따로 흉내내야 한다.
class _FakeSearchRepository implements DestinationRepository {
  _FakeSearchRepository({
    this.lightResults = const [],
    this.aiResults = const [],
    this.aiDelay,
    this.fail = false,
  });

  final List<PoiSearchResult> lightResults;
  final List<PoiSearchResult> aiResults;
  final Duration? aiDelay;
  final bool fail;

  /// 의미 검색이 **몇 번, 어떤 글자로** 갔는지. 중간 글자로 모델을 태우지
  /// 않는지 확인하는 게 이 목록의 목적이다.
  final aiQueries = <String>[];

  /// 두 호출 각각에 실제로 실린 `currentFloorId`. 패널이 상위에서 받은 값을
  /// 그대로 넘기는지(빼먹거나 다른 값으로 바꾸지 않는지) 확인하는 데 쓴다.
  final lightFloorIds = <String?>[];
  final aiFloorIds = <String?>[];

  @override
  Future<List<PoiSearchResult>> searchDestinations(
    String buildingId,
    String query, {
    String? currentFloorId,
  }) async {
    lightFloorIds.add(currentFloorId);
    if (fail) throw Exception('boom');
    return lightResults;
  }

  @override
  Future<DiscoveryResult> searchDestinationsAi(
    String buildingId,
    String query, {
    String? currentFloorId,
    Map<String, List<String>>? selectedFacets,
    bool showAll = false,
  }) async {
    aiQueries.add(query);
    aiFloorIds.add(currentFloorId);
    if (aiDelay != null) await Future<void>.delayed(aiDelay!);
    if (fail) throw Exception('boom');
    return DiscoveryResult(
      mode: aiResults.isEmpty ? DiscoveryMode.noMatch : DiscoveryMode.results,
      query: query,
      matches: aiResults.map(_toDiscoveryMatch).toList(),
    );
  }
}

/// clarify 이후의 요청 body를 검증하기 위한 순차 응답 fake. 네트워크 지연을
/// 흉내 내기보다, 선택 상태가 다음 요청에 온전히 전달되는지를 명시적으로 기록한다.
class _ScriptedDiscoveryRepository implements DestinationRepository {
  _ScriptedDiscoveryRepository(this._responses);

  final List<DiscoveryResult> _responses;
  final selectedFacets = <Map<String, List<String>>?>[];
  final showAllValues = <bool>[];
  final floorIds = <String?>[];
  var _index = 0;

  @override
  Future<List<PoiSearchResult>> searchDestinations(
    String buildingId,
    String query, {
    String? currentFloorId,
  }) async => const [];

  @override
  Future<DiscoveryResult> searchDestinationsAi(
    String buildingId,
    String query, {
    String? currentFloorId,
    Map<String, List<String>>? selectedFacets,
    bool showAll = false,
  }) async {
    this.selectedFacets.add(
      selectedFacets == null
          ? null
          : Map<String, List<String>>.fromEntries(
              selectedFacets.entries.map(
                (entry) => MapEntry(entry.key, List<String>.from(entry.value)),
              ),
            ),
    );
    showAllValues.add(showAll);
    floorIds.add(currentFloorId);
    if (_index >= _responses.length) {
      throw StateError('준비한 Discovery 응답보다 요청이 많습니다.');
    }
    return _responses[_index++];
  }
}

/// [PoiSearchResult] → [DiscoveryMatch] 변환. 가짜 저장소가 미리 준비해 둔
/// 결과를 DiscoveryResponse 계약으로 감싸는 용도라 storeId·floorId는
/// 테스트가 값 자체를 검증하지 않는 placeholder다.
DiscoveryMatch _toDiscoveryMatch(PoiSearchResult result) => DiscoveryMatch(
  storeId: '${result.floor}:${result.name}',
  name: result.name,
  category: result.category,
  subcategory: result.subcategory,
  floorId: result.floor,
  floorName: result.floor,
  entranceNodeId: result.nodeId,
  point: result.point,
  matchedFacets: const {},
  reason: null,
);

/// 패널은 건물 이름 검색 때문에 getAllBuildings만 부른다. 나머지는 부르지
/// 않으므로 호출되면 테스트가 틀린 것이라 그대로 던진다.
class _FakeBuildingRepository implements BuildingRepository {
  // 카테고리 pill은 이 테스트들의 관심사가 아니다. 빈 목록이면 pill 줄이 아예
  // 뜨지 않아 검증 대상 화면이 그대로 유지된다.
  @override
  Future<List<CategoryCount>?> getCategoryCounts(String buildingId) async =>
      const [];

  // 자동완성 원본. 이 테스트들은 후보를 보지 않으므로 빈 목록으로 둔다 —
  // 패널은 목록이 비면 후보를 그리지 않고 서버 검색만 돈다.
  @override
  Future<Map<String, dynamic>?> getBuildingEvents(String buildingId) async =>
      null;

  @override
  Future<List<StoreIndexEntry>?> getStoreIndex(String buildingId) async =>
      const [];
  @override
  Future<List<Building>> getAllBuildings() async => const [];

  @override
  Future<Building?> getBuilding(String buildingId) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>?> getFloorGeoJson(
    String buildingId,
    String floor,
  ) => throw UnimplementedError();

  @override
  Future<IndoorRoute?> getShortestRoute(
    String buildingId,
    String floor,
    String startNodeId,
    String endNodeId,
  ) => throw UnimplementedError();

  @override
  Future<BuildingGraph?> getBuildingGraph(
    String buildingId, {
    String vertical = 'auto',
  }) => throw UnimplementedError();
}
