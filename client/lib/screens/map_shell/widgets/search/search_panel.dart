import 'dart:async';

import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';
import 'package:latlong2/latlong.dart';

import '../../../../service_locator.dart';
import '../../../../domain/route/dijkstra.dart';
import '../../../../domain/store/indoor_store_lookup.dart';
import '../../../../domain/search/name_siblings.dart';
import '../../../../domain/store/nearest_store.dart';
import '../../../../domain/store/outdoor_poi_ranking.dart';
import '../../../../domain/search/reason_text.dart';
import '../../../../domain/search/search_result_order.dart';
import '../../../../domain/search/store_suggestions.dart';
import '../../../../models/building/building.dart';
import '../../../../models/building/category_count.dart';
import '../../../../models/place/discovery_result.dart';
import '../../../../models/place/outdoor_poi.dart';
import '../../../../models/place/poi_search_result.dart';
import '../../../../models/place/store_index_entry.dart';
import '../../../../theme/app_theme.dart';
import '../../../../domain/category/category_label_order.dart';
import '../../../../domain/store/reach_label.dart';
import '../../../../domain/geo/distance_format.dart';
import '../../../../domain/category/subcategory_label.dart';

/// 상단 검색창 아래에 붙는 결과 패널. 입력창은 상단 바가 갖고 여기는 결과만 그린다.
///
/// 타이핑이 300ms 멎으면 경량 매칭, 빈손이면 400ms 뒤 의미 검색까지 이어 붙인다
/// ([submitTick]이 오르면 두 대기를 건너뛴다). 트리거·디바운스·단계 판정의 근거는
/// `docs/client/search-input-assist.md` W절이 단일 출처다.
class SearchPanel extends StatefulWidget {
  const SearchPanel({
    super.key,
    required this.buildingId,
    required this.query,
    required this.submitTick,
    required this.onStorePicked,
    required this.onBuildingPicked,
    required this.onQueryPicked,
    required this.onSuggestionPicked,
    required this.indoorContextActive,
    this.currentFloorId,
    this.reachByNodeId,
    this.outdoorSearchCenter,
    this.onOutdoorPoiPicked,
    this.isInsideIndoorBuilding,
    this.categoryEntries,
    this.onCategoryPicked,
  });

  final String buildingId;

  /// 상단 검색창에 지금 들어 있는 글자.
  final String query;

  /// 지금 보고 있는 층. 실내 지도가 열려 있을 때만 값이 있고, 야외 모드거나
  /// 층이 아직 안 잡혔으면 null이다. 시설 질의("화장실")가 건물 전체에서
  /// 정렬 순서상 우연히 걸리는 층(예: B6)이 아니라 실제로 보고 있는 층으로
  /// 확정되도록 요청에 실어 보낸다.
  final String? currentFloorId;

  /// 엔터로 확정할 때마다 상위가 1씩 올린다. 값이 바뀐 순간에만 의미 검색을
  /// 붙인다 — 같은 글자로 다시 엔터를 눌러도 재검색되게 하려고 bool이 아닌
  /// 카운터로 받는다.
  final int submitTick;

  /// 현재 위치에서 각 그래프 노드까지의 거리·비용. 상위가 한 번 계산해 내려준다.
  ///
  /// null이거나 매장 노드가 없으면 **거리 줄을 그리지 않는다** — 줄마다 "거리 알 수
  /// 없음"을 반복하면 목록이 안 읽힌다.
  final Map<String, NodeReach>? reachByNodeId;

  final ValueChanged<PoiSearchResult> onStorePicked;
  final ValueChanged<Building> onBuildingPicked;

  /// 자동완성 후보를 골랐을 때. 상위가 좌표를 붙여 상세 시트까지 연다.
  ///
  /// [onStorePicked]와 따로 두는 이유는 **패널이 좌표를 모르기 때문**이다 —
  /// `/store-index`는 1,640건을 한 번에 주느라 좌표를 싣지 않는다.
  final ValueChanged<StoreIndexEntry> onSuggestionPicked;

  /// 최근 검색어를 골랐을 때. 패널이 입력창을 갖고 있지 않으므로(클래스 주석
  /// 참고) 검색을 스스로 다시 돌릴 수 없다 — 상위가 검색창 글자를 그 값으로
  /// 바꾸고 [query]·[submitTick]을 새로 내려줘야 한 바퀴가 돈다.
  final ValueChanged<String> onQueryPicked;

  /// 지금 건물 안을 보고 있는가. 상위의 `_indoorContextActive`를 그대로 받는다.
  ///
  /// **자동완성은 참일 때만 돈다** — 후보 원본이 건물 하나의 매장 목록이라, 시청 앞에서
  /// `apc`를 치면 더현대서울 3층이 떴다. [outdoorSearchCenter]와 서로를 배제한다.
  final bool indoorContextActive;

  /// 건물 **밖** 장소를 함께 찾을 기준점. 야외를 볼 때만 값이 있다.
  ///
  /// null이면 바깥 검색을 아예 안 한다 — 실내에서 "화장실"을 찾는 사람에게 길 건너
  /// 편의점을 섞으면 지금 층의 결과가 뒤로 밀린다.
  final LatLng? outdoorSearchCenter;

  /// 야외 장소를 골랐을 때. null이면 바깥 결과 줄을 눌러도 아무 일이 없으므로,
  /// [outdoorSearchCenter]가 있어도 이 콜백이 없으면 섹션을 그리지 않는다.
  final ValueChanged<OutdoorPoi>? onOutdoorPoiPicked;

  /// 좌표가 우리 실내 도면이 있는 건물 안인지 묻는다(야외 지도가 답한다).
  ///
  /// 같은 가게가 두 줄로 뜨는 것을 막는 데 쓴다([mergeOutdoorResults]).
  final bool Function(LatLng point)? isInsideIndoorBuilding;

  /// 건물의 (층·대분류·소분류)별 매장 수. **상위 Future를 그대로 받는다** — 다시
  /// 요청하면 두 화면의 카테고리 목록이 어긋난다.
  ///
  /// "찾지 못했어요"의 둘러볼 곳 제안 전용(`search-result-list-ux.md` R절).
  final Future<List<CategoryCount>>? categoryEntries;

  /// 위 대분류를 골랐을 때. 상위가 검색을 닫고 그 카테고리의 매장 목록 시트를
  /// 연다. null이면 제안 줄을 그리지 않는다.
  final ValueChanged<String>? onCategoryPicked;

  @override
  State<SearchPanel> createState() => _SearchPanelState();
}

/// 패널이 지금 어느 단계인지. 불리언 두 개가 아니라 enum인 이유는
/// `search-input-assist.md` W절에 있다 — [noMatch]는 2차까지 끝나야 들어갈 수 있다.
///
enum _SearchPhase {
  /// 아직 아무것도 치지 않았다. 안내 문구만 보여준다.
  idle,

  /// 경량 매칭이 도는 중. 의미 검색으로 넘어가기 전 대기 시간도 여기 포함된다
  /// — 사용자 입장에서는 둘 다 "찾는 중"이고, 아직 결론이 아니다.
  typingLightSearch,

  /// 의미 검색이 도는 중. 모델 로드로 오래 걸릴 수 있어 경량과 다른 문구를
  /// 띄운다 — 같은 스피너만 돌면 멈춘 것처럼 보인다.
  semanticSearching,

  /// 후보가 넓어서 선택지를 먼저 보여 주는 탐색 응답이다.
  clarify,

  /// 보여줄 매장·건물이 있다.
  results,

  /// **온디바이스 후보로 답했다.** 서버 경량 매칭은 빈손이었지만 기기 안 인덱스가
  /// 이름으로 매장을 찾은 상태다. 이때는 의미 검색으로 넘어가지 않는다 — 근거는
  /// [_SearchPanelState._search]의 분기 주석에 있다.
  suggestions,

  /// 경량과 의미 검색을 **둘 다** 끝냈는데 없다. 최종 "결과 없음" 문구는 오직
  /// 이 단계에서만 나온다.
  noMatch,

  /// 의미 모델은 쓸 수 없지만 경량/태그 후보는 남아 있을 수 있다.
  degraded,

  /// 서버·네트워크가 끊겨 검색을 끝내지 못했다. 없는 것과 못 찾은 것은 사용자가
  /// 할 행동이 다르다 — 전자는 다른 말로 바꿔야 하고, 후자는 기다려야 한다.
  error,
}

/// 이름에서 검색어와 일치하는 구간. 이 결과가 왜 나왔는지를 화면이 설명하는 근거다.
///
/// **구간만 돌려주고 어떻게 보일지는 정하지 않는다** — 그리는 일은 `RoutexListCell`이
/// 맡는다. 여기 남는 것은 판정이고, 판정은 서버와 맞춰야 하는 도메인이다.
///
/// **하나도 안 걸리는 것이 정상 상태다** — 의미 검색은 이름에 검색어가 없는 결과를
/// 주는 게 목적이라, 못 찾으면 빈 목록을 돌려줄 뿐 실패로 다루지 않는다.
/// 대소문자·앞뒤 공백만 정규화한다(서버 Kiwi를 흉내내면 판정과 어긋난다 —
/// [isExactNameMatch]와 같은 이유).
List<TextRange> nameHighlightRanges(String name, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return const [];

  final haystack = name.toLowerCase();
  final ranges = <TextRange>[];
  var cursor = 0;
  while (true) {
    final index = haystack.indexOf(needle, cursor);
    if (index < 0) break;
    ranges.add(TextRange(start: index, end: index + needle.length));
    cursor = index + needle.length;
  }
  return ranges;
}

/// 다음 검색 한 번에만 적용할 층 스코프. 목록에서 **고른 그 매장의 층**을 실어
/// 보낸다 — 안 그러면 같은 이름 19곳(화장실)에서 서버가 자기 순서로 고른다.
///
/// [floorId]가 null이면 **층을 모르는 선택**(최근 검색어)이라 스코프를 뺀다.
/// 근거와 검증 기준은 `docs/client/search-result-list-ux.md` T절.
class _FloorScopeOverride {
  const _FloorScopeOverride(this.floorId);

  /// 이 층으로 좁힌다. null이면 좁히지 않는다.
  final String? floorId;
}

class _SearchPanelState extends State<SearchPanel> {
  /// 행 리듬은 이제 `RoutexListCell`이 갖는다. **한 벌의 플랫 리스트**로 보이게
  /// 하려는 것은 그대로다(naver-map-ui-ux-analysis.md 2절) — 구분선은 두지 않는다.
  /// 머리말·배너까지 칸칸이 나뉘어 보였다.

  /// 머리말(«검색 결과 N»·«검색어 제안»…) 공통 여백. 우측에 컨트롤이 붙는
  /// 머리말은 좌·상·하만 이 값을 따르고 우측만 좁힌다.
  static const _sectionLabelPadding = EdgeInsets.fromLTRB(16, 14, 16, 4);

  /// 경량 검색용 디바운스. 글자마다 서버를 때리지 않게 잠깐 모았다 보낸다.
  static const _lightDebounce = Duration(milliseconds: 300);

  /// 경량이 빈손일 때 의미 검색으로 넘어가기 전에 더 기다리는 시간.
  /// 0으로 두면 "밥"·"밥 먹"·"밥 먹을"이 전부 모델을 태운다(근거: W절).
  static const _semanticGrace = Duration(milliseconds: 400);

  /// 두 단계의 대기를 **한 필드로** 돌린다. 한 시점에 살아 있을 수 있는 대기는
  /// 하나뿐이고(경량을 기다리는 중이거나, 경량이 끝나 의미 검색을 기다리는
  /// 중이거나), 취소 지점도 같다 — 새 글자가 오면 둘 다 죽어야 한다. 필드를
  /// 나누면 "경량 타이머는 껐는데 의미 타이머는 살아 있는" 조합이 생긴다.
  Timer? _debounce;

  /// 마지막으로 결과를 확정한 질의. "…에 맞는 매장을 찾지 못했어요" 문구에 쓴다.
  String _submittedQuery = '';
  List<PoiSearchResult> _results = const [];

  /// 이름이 걸린 건물. 매장과 함께 목록 맨 위에 한 줄로 얹는다 — 예전 상단
  /// 검색이 하던 "건물 이름 검색"을 여기로 옮겨 온 것이다.
  Building? _building;

  /// 이번 질의로 찾은 건물 **밖** 장소(TMAP POI). 실내 결과와 독립적으로 찬다.
  List<OutdoorPoi> _pois = const [];

  /// 우리가 도면을 가진 건물들의 이름. POI 이름이 우리 건물을 부르고 있는지
  /// 판정하는 데 쓴다([mentionsBuilding]) — 좌표만으로는 접근점이 외곽선 밖에
  /// 찍혀 판정이 갈린다.
  List<String> _buildingNames = const [];

  /// 지금 보고 있는 건물의 이름. 매장 줄의 층 앞에 붙인다.
  String? _currentBuildingName;

  _SearchPhase _phase = _SearchPhase.idle;

  /// 이번 결과가 의미 검색에서 나왔는지. 목록에 "뜻으로 찾은 결과"라고 표시해
  /// 사용자가 왜 다른 이름이 나왔는지 납득할 수 있게 한다. 단계가 아니라 결과의
  /// 성질이라 [_SearchPhase]에 합치지 않고 따로 둔다.
  bool _fromSemantic = false;

  /// 마지막 탐색 응답의 원본 후보. [PoiSearchResult]로만 바꾸면 storeId와
  /// reason을 잃어 추천 이유·선택 후 추적을 할 수 없으므로 별도로 보존한다.
  List<DiscoveryMatch> _discoveryMatches = const [];

  /// 마지막 `/query/ai` 응답의 mode. 화면 상태는 이 값을 안전하게 명시 분기한다.
  DiscoveryMode? _discoveryMode;

  /// clarify일 때의 질문 문장.
  String? _discoveryQuestion;

  /// clarify일 때의 선택지.
  List<DiscoveryOption> _discoveryOptions = const [];

  /// stateless API에 매번 실어 보내는 facet 선택. 이 맵 하나가 화면 chip과
  /// 다음 요청 body의 공통 원본이라, 화면은 선택됐는데 요청에는 빠지는 상태를
  /// 만들지 않는다.
  Map<String, List<String>> _selectedFacets = const {};

  /// 최근 선택 순서. "다시 선택"은 마지막 질문의 답 하나만 되돌려 질문으로
  /// 복귀시킨다. 각 축은 현재 한 값을 선택하게 하므로 `(facet, value)`로 둔다.
  final List<(String facet, String value)> _facetSelectionOrder = [];

  /// 직전 요청이 "전체 보기"였는가. 선택(facet) 없이 질문만 건너뛴 상태를
  /// 가리키므로 `_selectedFacets`로는 표현되지 않는다. 이 상태에서만 "다시 선택"이
  /// 질문으로 돌아가는 유일한 길이라, 헤더 버튼 노출 조건에 필요하다.
  bool _showingAll = false;

  /// 늦게 도착한 응답이 최신 결과를 덮어쓰지 않게 하는 순번.
  int _requestId = 0;

  /// 결과 목록의 스크롤. Scrollbar와 스크롤뷰가 같은 컨트롤러를 봐야 막대가
  /// 실제 위치를 따라간다.
  final _resultScrollController = ScrollController();

  /// 온디바이스 자동완성의 원본. 건물당 1회 받아 둔다.
  ///
  /// null(못 받았거나 실패)도 **정상 경로다** — 후보만 조용히 사라지고 서버 검색은
  /// 그대로 돈다(search-input-assist.md K절 실패 조건).
  List<StoreIndexEntry>? _storeIndex;

  /// 지금 질의에 대한 후보. **질의가 바뀔 때만** 다시 계산한다 — build에서 매번
  /// 계산하면 한 프레임에 여러 번 1640건을 훑는다.
  List<StoreSuggestion> _suggestions = const [];

  /// 사용자가 직접 고른 정렬. null이면 [defaultSortOrder]가 위치 유무로 정한다.
  ///
  /// **검색어가 바뀌면 지운다**(didUpdateWidget) — 세션에 남기면 다음 검색이 기억에
  /// 없는 순서로 시작한다. 같은 검색어로 다시 엔터는 유지한다.
  SearchSortOrder? _sortOverride;

  /// 다음 검색 **한 번만** 층 스코프를 바꾼다. null이면 [SearchPanel.currentFloorId].
  ///
  /// 목록에서 무언가를 **탭한 경우**에 선다 — 층 스코프는 직접 친 시설 질의를 위한
  /// 것이지, 특정 대상을 콕 집은 행동에 적용할 것이 아니다([_FloorScopeOverride]).
  _FloorScopeOverride? _floorScopeOnce;

  @override
  void initState() {
    super.initState();
    if (widget.indoorContextActive) _loadStoreIndex();
    // 검색창에 글자가 남아 있는 채로 패널이 다시 열릴 수 있다.
    if (widget.query.trim().isNotEmpty) _scheduleSearch(widget.query);
  }

  /// 후보 원본을 받아 둔다. 실패는 삼킨다 — 위 [_storeIndex] 주석 참고.
  Future<void> _loadStoreIndex() async {
    try {
      final index = await buildingRepository.getStoreIndex(widget.buildingId);
      if (!mounted || index == null) return;
      setState(() {
        _storeIndex = index;
        // 목록이 늦게 도착하는 동안 사용자가 이미 치고 있었을 수 있다.
        _suggestions = _computeSuggestions(widget.query);
      });
    } on Object {
      // 자동완성만 포기한다. 검색을 막지 않는다.
    }
  }

  List<StoreSuggestion> _computeSuggestions(String query) {
    // 야외에서는 후보를 만들지 않는다 — 이유는 [SearchPanel.indoorContextActive].
    if (!widget.indoorContextActive) return const [];
    final index = _storeIndex;
    if (index == null) return const [];
    return suggestStores(stores: index, query: query);
  }

  @override
  void didUpdateWidget(covariant SearchPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 야외 → 실내로 들어오면 그때 원본을 받는다. 야외에서 미리 받아 두면 쓰지도
    // 않을 목록을 내려받는 것이고, 실내로 들어온 뒤에는 후보가 있어야 한다.
    if (widget.indoorContextActive && !oldWidget.indoorContextActive) {
      _loadStoreIndex();
    }
    if (widget.query != oldWidget.query ||
        widget.indoorContextActive != oldWidget.indoorContextActive) {
      // 서버 응답을 기다리지 않는다. 이게 자동완성이 즉시 뜨는 이유다.
      _suggestions = _computeSuggestions(widget.query);
    }
    // 새 검색어면 정렬 선택을 지운다. 엔터 재확정(submitTick만 오름)은 같은
    // 검색어라 유지한다.
    if (widget.query != oldWidget.query) _sortOverride = null;
    if (widget.submitTick != oldWidget.submitTick) {
      // 엔터로 확정. 사용자가 이미 "다 쳤다"고 말한 셈이라 두 대기를 모두
      // 건너뛴다. 엔터가 의미 검색의 **유일한** 트리거는 아니지만, 가장 빠른
      // 트리거로는 남는다.
      _search(widget.query, immediate: true);
    } else if (widget.query != oldWidget.query) {
      _scheduleSearch(widget.query);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _resultScrollController.dispose();
    super.dispose();
  }

  /// 타이핑마다 서버를 때리지 않도록 잠깐 모았다 보낸다. 여기서 시작한 검색도
  /// 경량이 빈손이면 의미 검색까지 이어진다 — 엔터를 안 눌러도 된다.
  void _scheduleSearch(String value) {
    _debounce?.cancel();
    // 새 입력이 들어온 순간 기존 요청을 무효화한다. 디바운스가 끝나기 전에도
    // 이전 검색의 늦은 응답이 화면을 덮으면, 화면의 검색어와 후보가 달라진다.
    _requestId++;
    _debounce = Timer(_lightDebounce, () => _search(value));
  }

  /// [immediate]가 참이면 의미 검색으로 넘어가기 전 [_semanticGrace] 대기를
  /// 건너뛴다. 엔터로 확정한 경우다.
  Future<void> _search(String raw, {bool immediate = false}) async {
    _debounce?.cancel();
    final query = raw.trim();
    if (query.isEmpty) {
      // 검색창을 비웠다. 진행 중인 응답이 나중에 도착해 빈 화면을 덮지 않도록
      // 순번도 함께 올린다.
      _requestId++;
      setState(() {
        _submittedQuery = '';
        _results = const [];
        _building = null;
        _pois = const [];
        _fromSemantic = false;
        _discoveryMatches = const [];
        _discoveryMode = null;
        _discoveryQuestion = null;
        _discoveryOptions = const [];
        _selectedFacets = const {};
        _facetSelectionOrder.clear();
        _showingAll = false;
        _phase = _SearchPhase.idle;
      });
      return;
    }

    final requestId = ++_requestId;
    setState(() {
      // 새 원문 검색은 이전 clarify 선택의 연장이 아니다. 선택을 남기면 다른
      // 문장에 이전 facet이 섞여 stateless 계약의 의미가 깨진다.
      _selectedFacets = const {};
      _facetSelectionOrder.clear();
      _showingAll = false;
      _pois = const [];
      _phase = _SearchPhase.typingLightSearch;
    });

    // 건물 밖 검색은 **기다리지 않는다.** 실내 검색과 나란히 출발시켜 두고,
    // 먼저 끝나는 쪽부터 화면에 붙인다. 순서대로 하면 실내 결과가 이미 나온
    // 화면에서 바깥 응답을 기다리느라 목록이 늦게 뜬다.
    unawaited(_searchOutdoorPois(query, requestId));

    List<PoiSearchResult> results;
    Building? building;
    try {
      // 1단계: 경량 매칭. 현재 층을 함께 보낸다(근거: W절). 목록에서 고른
      // 검색이면 고른 그 매장의 층으로 좁힌다([_FloorScopeOverride]).
      final override = _floorScopeOnce;
      final floorScope = override != null
          ? override.floorId
          : widget.currentFloorId;
      _floorScopeOnce = null;
      results = await destinationRepository.searchDestinations(
        widget.buildingId,
        query,
        currentFloorId: floorScope,
      );
      final buildings = await buildingRepository.getAllBuildings();
      building = buildings
          .where((b) => b.name.toLowerCase().contains(query.toLowerCase()))
          .firstOrNull;
      _buildingNames = buildings.map((b) => b.name).toList();
      _currentBuildingName = buildings
          .where((b) => b.id == widget.buildingId)
          .map((b) => b.name)
          .firstOrNull;
    } on Object {
      _finishFailed(query, requestId);
      return;
    }
    // 이 응답을 기다리는 사이 사용자가 더 쳤다면 버린다.
    if (!mounted || requestId != _requestId) return;

    // 2단계로 넘길지 판단한다. 예전에는 여기에 `allowSemantic`(=엔터를 눌렀다)
    // 조건이 하나 더 있었다. 그 조건이 빠지면서 "찾지 못했어요"는 의미 검색을
    // 지난 뒤에만 나올 수 있게 된다. 경량이 한 건이라도 잡으면 그대로 보여준다
    // — 잘 되던 검색은 여전히 빠르다.
    if (results.isEmpty && building == null) {
      // 이름 후보가 떠 있으면 스피너로 덮지 않는다(A.P.C. 불변).
      // 교정 후보만 있을 때는 넘긴다 — 그건 추측이라 의미 검색이 더 나을 수 있다.
      final hasNameSuggestions = _suggestions.any((s) => !s.kind.isCorrection);
      if (hasNameSuggestions) {
        // 후보를 **먼저 확정해 보여주고** 서버 탐색은 그대로 이어서 던진다.
        // 응답이 오면 [DiscoverySource]로 판정한다 — light면 교체, semantic이면 버림.
        // 온디바이스 후보는 임베딩에는 이기고 서버 어휘에는 진다
        // (근거·실측: `docs/client/search-input-assist.md` V절).
        setState(() {
          _submittedQuery = query;
          _results = const [];
          _building = null;
          _fromSemantic = false;
          _discoveryMatches = const [];
          _discoveryMode = null;
          _discoveryQuestion = null;
          _discoveryOptions = const [];
          _phase = _SearchPhase.suggestions;
        });
      }
      if (immediate) {
        await _semanticSearch(
          query,
          requestId,
          keepSuggestionsUnlessLight: hasNameSuggestions,
        );
      } else {
        // 대기를 `Future.delayed`가 아니라 Timer로 두는 이유는 취소 때문이다.
        // 패널이 닫히면 dispose가 이 타이머를 끄고, 사용자가 글자를 더 치면
        // _scheduleSearch가 같은 필드를 덮어써 끈다. `await Future.delayed`는
        // 취소할 방법이 없어 패널이 사라진 뒤에도 살아 있다.
        _debounce = Timer(
          _semanticGrace,
          () => _semanticSearch(
            query,
            requestId,
            keepSuggestionsUnlessLight: hasNameSuggestions,
          ),
        );
      }
      return;
    }

    setState(() {
      _submittedQuery = query;
      _results = results;
      _building = building;
      _fromSemantic = false;
      _discoveryMatches = const [];
      // 경량 매칭 결과라 discovery 계약과 무관하다 — 직전 AI 질의의 잔여
      // 질문/선택지가 이번 결과에 얹혀 보이지 않도록 함께 지운다.
      _discoveryMode = null;
      _discoveryQuestion = null;
      _discoveryOptions = const [];
      _phase = _SearchPhase.results;
    });
  }

  /// 건물 밖 장소 검색(TMAP POI). 실내 검색과 **독립적으로** 돌고, 실패해도
  /// 화면 단계([_phase])를 건드리지 않는다.
  Future<void> _searchOutdoorPois(String query, int requestId) async {
    final center = widget.outdoorSearchCenter;
    // **건너뛰는 이유를 반드시 남긴다.** 이 세 조건 중 하나만 걸려도 화면에는
    // "바깥 결과가 없다"와 똑같이 보인다. 실제로 기준점이 null이라 한 번도 안
    // 돌던 시기를 로그 없이 지나쳤다.
    if (center == null) {
      debugPrint('[tmap-poi] 건너뜀: 검색 기준점 없음(위치·카메라 모두 미확보)');
      return;
    }
    if (widget.onOutdoorPoiPicked == null) {
      debugPrint('[tmap-poi] 건너뜀: 선택 콜백 없음');
      return;
    }
    if (!outdoorPoiRepository.isAvailable) {
      debugPrint('[tmap-poi] 건너뜀: TMAP_APP_KEY 미주입');
      return;
    }
    final pois = await outdoorPoiRepository.searchNearby(query, center: center);
    // 늦게 도착한 응답이 다음 검색어의 화면을 덮지 않게 한다(실내와 같은 규칙).
    if (!mounted || requestId != _requestId || pois.isEmpty) return;
    // 규칙은 도메인 함수가 갖고 있다(`domain/outdoor_poi_ranking.dart`).
    // 길찾기 후보도 같은 함수를 부른다 — 여기서 다시 구현하면 또 갈린다.
    final relevant = filterByNameRelevance(query, pois);
    if (relevant.isEmpty) return;

    // 사용자가 친 말로 우리 매장을 못 찾았을 수 있다("더현대 스타벅스" →
    // no_match). 그 경우 POI 이름의 브랜드로 한 번 더 묻는다 — 안 하면 겹침을
    // 판정할 대상이 없어 TMAP 줄이 그대로 남고, 그 줄을 고르면 층·노드가 없어
    // 실내 경로가 시작되지 않는다.
    final isAt = widget.isInsideIndoorBuilding;
    final enriched = await lookUpIndoorStoresByBrand(
      pois: relevant,
      indoorStores: _results,
      isAtBuilding: (poi) => isAt?.call(poi.point) ?? false,
      buildingNames: _buildingNames,
      search: (brand) =>
          destinationRepository.searchDestinations(widget.buildingId, brand),
    );
    if (!mounted || requestId != _requestId) return;

    setState(() {
      _pois = relevant;
      _results = enriched;
      // 이름 강조가 쓰는 질의어. 실내 검색이 아직 안 끝났을 수 있어 여기서도
      // 채운다 — 안 채우면 이전 검색어 기준으로 강조가 걸린다.
      _submittedQuery = query;
    });
  }

  /// 2단계. 이 함수가 끝나야 [_SearchPhase.noMatch]를 최종 결론으로 쓸 수 있다.
  /// 응답(DiscoveryResponse)의 mode마다 명시적인 화면 상태로 옮긴다.
  ///
  /// [keepSuggestionsUnlessLight]가 참이면 이름 후보가 이미 떠 있다는 뜻이라,
  /// 어휘(`light`)로 잡은 응답만 후보를 교체한다(search-input-assist.md V절).
  Future<void> _semanticSearch(
    String query,
    int requestId, {
    bool keepSuggestionsUnlessLight = false,
  }) async {
    if (!mounted || requestId != _requestId) return;
    // 후보가 떠 있으면 스피너를 띄우지 않는다. 맞는 답을 보여주다가 "찾는 중"
    // 으로 덮는 것이 A.P.C. 사례에서 사용자가 겪은 문제의 절반이었다.
    if (!keepSuggestionsUnlessLight) {
      setState(() => _phase = _SearchPhase.semanticSearching);
    }

    DiscoveryResult discovery;
    try {
      // 백엔드의 2차(의미) 단계는 current_floor_id를 받아도 건물 전체를 본다
      // (query_search.match_ai_destination 주석 참고) — 1차만 층으로 좁혀
      // 확정하고, 1차가 실패한 뒤인 여기서는 층을 또 좁히지 않는다. 그대로
      // 넘겨도 회귀가 없다.
      discovery = await destinationRepository.searchDestinationsAi(
        widget.buildingId,
        query,
        currentFloorId: widget.currentFloorId,
      );
    } on Object {
      if (keepSuggestionsUnlessLight) return; // 후보 화면을 오류로 덮지 않는다
      _finishFailed(query, requestId);
      return;
    }
    if (!mounted || requestId != _requestId) return;

    // 임베딩 결과, 그리고 어휘라도 빈 matches면 버린다 — 화면에 떠 있던 맞는
    // 후보가 "결과 없음"으로 지워지는 쪽이 최악이다(V절 실패 조건).
    if (keepSuggestionsUnlessLight &&
        (!discovery.source.canReplaceNameSuggestions ||
            discovery.matches.isEmpty)) {
      return;
    }

    final results = discovery.matches
        .map((match) => match.toPoiSearchResult())
        .toList();
    // 결과가 사실상 정확한 이름 일치면(예: 타 층 "나이키") "뜻이 비슷한"
    // 배너를 붙이지 않는다 — 실제로는 뜻으로 찾은 게 아니라 층 스코프 때문에
    // 1차가 빈손이 되어 여기로 넘어왔을 뿐이다.
    setState(() {
      _submittedQuery = query;
      _results = results;
      _building = null;
      // "뜻이 비슷한 매장" 배너는 임베딩으로 찾았을 때만 맞는 말이라 source를 먼저
      // 본다. 휴리스틱([isExactNameMatch])도 남긴다 — 타 층 매장을 정확한 이름으로
      // 쳐서 2차로 온 경우는 source가 semantic이어도 "뜻으로 찾은" 게 아니다.
      _fromSemantic =
          results.isNotEmpty &&
          !discovery.source.canReplaceNameSuggestions &&
          !isExactNameMatch(query, results.map((r) => r.name));
      _discoveryMatches = discovery.matches;
      _discoveryMode = discovery.mode;
      _discoveryQuestion = discovery.question;
      _discoveryOptions = discovery.options;
      _phase = _phaseForDiscovery(discovery);
    });
  }

  _SearchPhase _phaseForDiscovery(DiscoveryResult discovery) {
    // 서버가 새 mode를 추가하거나 계약을 어긴 경우에는 후보를 임의로 추천하지
    // 않는다. 사용자가 다른 표현으로 재검색할 수 있는 안전한 noMatch로 보낸다.
    return switch (discovery.mode) {
      DiscoveryMode.direct =>
        discovery.matches.isEmpty ? _SearchPhase.noMatch : _SearchPhase.results,
      DiscoveryMode.clarify => _SearchPhase.clarify,
      DiscoveryMode.results =>
        discovery.matches.isEmpty ? _SearchPhase.noMatch : _SearchPhase.results,
      DiscoveryMode.noMatch || DiscoveryMode.unknown => _SearchPhase.noMatch,
      DiscoveryMode.degraded => _SearchPhase.degraded,
    };
  }

  /// facet 동작은 새 `/query/ai` 요청이다. 서버 세션이 없으므로 원문·현재 층·
  /// 선택 전체를 항상 다시 보내고, 요청 번호도 올려 과거 응답을 무효화한다.
  Future<void> _requestDiscovery({required bool showAll}) async {
    _debounce?.cancel();
    final query = widget.query.trim();
    if (query.isEmpty) return;

    final requestId = ++_requestId;
    setState(() => _phase = _SearchPhase.semanticSearching);
    try {
      final discovery = await destinationRepository.searchDestinationsAi(
        widget.buildingId,
        query,
        currentFloorId: widget.currentFloorId,
        selectedFacets: _selectedFacets.isEmpty
            ? null
            : Map<String, List<String>>.fromEntries(
                _selectedFacets.entries.map(
                  (entry) =>
                      MapEntry(entry.key, List<String>.from(entry.value)),
                ),
              ),
        showAll: showAll,
      );
      if (!mounted || requestId != _requestId) return;

      final results = discovery.matches
          .map((match) => match.toPoiSearchResult())
          .toList();
      setState(() {
        _submittedQuery = query;
        _results = results;
        _building = null;
        _fromSemantic =
            results.isNotEmpty &&
            !isExactNameMatch(query, results.map((r) => r.name));
        _discoveryMatches = discovery.matches;
        _discoveryMode = discovery.mode;
        _discoveryQuestion = discovery.question;
        _discoveryOptions = discovery.options;
        _showingAll = showAll;
        _phase = _phaseForDiscovery(discovery);
      });
    } on Object {
      _finishFailed(query, requestId);
    }
  }

  void _selectFacet(DiscoveryOption option) {
    final next = Map<String, List<String>>.fromEntries(
      _selectedFacets.entries.map(
        (entry) => MapEntry(entry.key, List<String>.from(entry.value)),
      ),
    );
    // 한 질문은 한 축을 가리키므로 같은 축의 이전 선택은 교체한다. 다중 축은
    // 그대로 유지되어 다음 요청에 모두 전송된다.
    next[option.facet] = [option.value];
    setState(() {
      _selectedFacets = next;
      _facetSelectionOrder.removeWhere((item) => item.$1 == option.facet);
      _facetSelectionOrder.add((option.facet, option.value));
    });
    _requestDiscovery(showAll: false);
  }

  void _removeFacet(String facet, String value) {
    final next = Map<String, List<String>>.fromEntries(
      _selectedFacets.entries.map(
        (entry) => MapEntry(entry.key, List<String>.from(entry.value)),
      ),
    );
    final values = next[facet];
    if (values == null) return;
    values.remove(value);
    if (values.isEmpty) next.remove(facet);
    setState(() {
      _selectedFacets = next;
      _facetSelectionOrder.removeWhere(
        (item) => item.$1 == facet && item.$2 == value,
      );
    });
    _requestDiscovery(showAll: false);
  }

  void _chooseAgain() {
    if (_facetSelectionOrder.isEmpty) {
      _requestDiscovery(showAll: false);
      return;
    }
    final last = _facetSelectionOrder.last;
    _removeFacet(last.$1, last.$2);
  }

  /// 서버 장애·네트워크 끊김. 패널을 닫지 않고 안내만 바꾼다. 이걸 "결과 없음"과
  /// 같이 처리하면, 백엔드가 죽었을 뿐인데 사용자에게 "그런 매장은 없다"고 말하는
  /// 셈이 된다 — 사용자는 말을 바꿔 가며 계속 헛수고를 하게 된다.
  void _finishFailed(String query, int requestId) {
    if (!mounted || requestId != _requestId) return;
    setState(() {
      _submittedQuery = query;
      _results = const [];
      _building = null;
      _fromSemantic = false;
      _discoveryMatches = const [];
      _discoveryMode = null;
      _discoveryQuestion = null;
      _discoveryOptions = const [];
      _selectedFacets = const {};
      _facetSelectionOrder.clear();
      _showingAll = false;
      _phase = _SearchPhase.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      // 지도를 덮는 임시 레이어다. 상단 바(chrome)보다 한 단계 앞에 둬야
      // "지금 이게 화면의 주인공"이 읽힌다(AppElevation).
      elevation: AppElevation.overlay,
      shadowColor: Colors.black.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    // **후보를 띄울지는 단계가 아니라 "이번 글자의 답이 있는가"로 정한다.**
    // [_phase]로 판단하면 디바운스 동안 직전 질의의 결과가 그대로 남는다(W절).
    final awaitingAnswer = widget.query.trim() != _submittedQuery;
    if (_suggestions.isNotEmpty &&
        awaitingAnswer &&
        // 의미 검색만 예외다. 여기까지 왔다는 건 이름으로 걸린 후보가 없었다는
        // 뜻이라(위 _search 분기) 후보로 덮을 것도 없고, 여기서만 몇 초가 걸릴 수
        // 있어 "AI가 찾는 중"이라는 사실 자체가 화면에 있어야 한다.
        _phase != _SearchPhase.semanticSearching) {
      return _suggestionList(settled: false);
    }

    // 건물 밖 결과가 하나라도 있으면 **어떤 단계에서도** 목록을 보여준다(W절).
    // 실내가 도는 중이라는 사실은 목록 안의 진행 줄이 대신 알린다.
    final hasOutdoor = _pois.isNotEmpty;
    switch (_phase) {
      case _SearchPhase.idle:
        return _idleState();
      case _SearchPhase.typingLightSearch:
      case _SearchPhase.semanticSearching:
        return hasOutdoor ? _resultList() : _searchingState();
      case _SearchPhase.suggestions:
        return _suggestionList(settled: true);
      case _SearchPhase.clarify:
      case _SearchPhase.results:
        return _resultList();
      case _SearchPhase.degraded:
        return _results.isEmpty && !hasOutdoor
            ? _degradedState()
            : _resultList();
      case _SearchPhase.error:
        return hasOutdoor ? _resultList() : _errorState();
      // **오타 교정이 실제로 값을 내는 자리다.** 서버가 못 찾은 뒤에도 "샤낼 뷰티"
      // 같은 표기 실수나 초성 질의(`ㄴㅇㅋ`)는 온디바이스 후보가 잡는다. 여기서
      // 후보를 안 보여주면 사용자가 볼 수 있는 건 "찾지 못했어요" 하나뿐이다.
      case _SearchPhase.noMatch:
        // 바깥에 답이 있으면 "찾지 못했어요"로 끝내지 않는다. 순서는 후보보다
        // 바깥 결과가 먼저다 — 교정 후보는 추측이지만 바깥 줄은 실제로 찾은
        // 장소다.
        if (hasOutdoor) return _resultList();
        return _suggestions.isEmpty
            ? _emptyState(context)
            : _suggestionList(settled: true);
    }
  }

  /// 지금 적용 중인 정렬. 사용자가 고른 값이 우선이고, 안 골랐으면 위치 유무로
  /// 정한다.
  SearchSortOrder get _sortOrder =>
      _sortOverride ?? defaultSortOrder(widget.reachByNodeId);

  /// 목록 머리말 — 개수·층 분포(Q)와 정렬 컨트롤(P)이 **한 줄**을 쓴다. 이 패널은
  /// 상단 오버레이라 세로가 가장 귀한 자원이다.
  ///
  /// [floorNames]는 **화면에 그린 줄들의 층**이다(묶인 시설의 나머지 층은 안 센다).
  /// `B2 ~ 3F` 같은 범위로 적지 않는다 — `Floor.level`이 없어 사전순으로 세우면
  /// `1F`가 `B1`보다 앞에 온다.
  /// 개수·층 머리말 문장. 서식은 앱이 정하고 자리는 `RoutexResultList`가 갖는다.
  String _listSummary({
    required int count,
    required Iterable<String> floorNames,
  }) {
    final floors = floorNames.toSet();
    final floorText = floors.length == 1 ? floors.first : '${floors.length}개 층';
    return '검색 결과 $count · $floorText';
  }

  /// 정렬 선택지. **쓸 수 없는 기준을 감추지 않는다** — 감추면 "가까운 순"이 아예
  /// 없는 앱으로 읽히고, 눌러 본 뒤 막으면 왜 안 되는지를 그때야 안다.
  List<RoutexSortOption> get _sortOptions => [
    RoutexSortOption(
      id: SearchSortOrder.nearest.name,
      label: '가까운 순',
      unavailableReason: canSortByNearest(widget.reachByNodeId)
          ? null
          : '현재 위치 필요',
    ),
    RoutexSortOption(id: SearchSortOrder.bestMatch.name, label: '이름 맞춤 순'),
  ];

  void _onSortSelected(String id) {
    final order = SearchSortOrder.values.firstWhere(
      (value) => value.name == id,
    );
    setState(() => _sortOverride = order);
  }

  /// 후보 목록. 탭하면 좌표를 들고 바로 가지 않고 그 이름으로 검색을 다시 돌린다
  /// (`onQueryPicked`) — 이유는 [StoreIndexEntry] 주석에.
  ///
  /// [settled]는 **이 화면이 이번 글자의 결론인가**다. 타이핑 중이면 정렬 컨트롤을
  /// 감추고 순서도 매칭 품질순으로 둔다 — 글자마다 줄이 거리로 다시 세워지면
  /// 눈앞에서 위아래로 튄다.
  Widget _suggestionList({required bool settled}) {
    // 머리말은 호출 자리가 아니라 **후보의 성격**으로 정한다. 전부 교정 후보면
    // "네가 치려던 게 이거냐"는 되물음이고, 하나라도 이름이 실제로 걸렸으면
    // "이런 게 있다"는 제안이다. 자리로 나누면 같은 목록에 다른 말이 붙는다.
    final allCorrections = _suggestions.every((s) => s.kind.isCorrection);
    // 교정 후보는 추측이라 개수·정렬을 붙이지 않는다. **1건짜리 목록에도 머리말을
    // 얹지 않는다** — `검색 결과 1 · 4F`는 아래 한 줄이 이미 말한 것이다.
    final showCount =
        settled &&
        !allCorrections &&
        canChooseSortOrder(itemCount: _suggestions.length, fromSemantic: false);
    final suggestions = showCount
        ? sortedSuggestions(
            suggestions: _suggestions,
            reachByNodeId: widget.reachByNodeId,
            order: _sortOrder,
          )
        : _suggestions;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!showCount)
          Padding(
            padding: _sectionLabelPadding,
            child: Text(
              allCorrections ? '이걸 찾으셨나요?' : '검색어 제안',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.muted,
              ),
            ),
          ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 8),
            child: RoutexResultList(
              status: RoutexResultStatus.ready,
              summary: showCount
                  ? _listSummary(
                      count: suggestions.length,
                      // 묶인 시설은 화면에 그린 대표의 층만 센다.
                      floorNames: [
                        for (final suggestion in suggestions)
                          nearestByWalkingDistance(
                            stores: suggestion.stores,
                            reachByNodeId: widget.reachByNodeId,
                            currentFloorId: widget.currentFloorId,
                          ).store.floorName,
                      ],
                    )
                  : null,
              sortOptions: showCount ? _sortOptions : const [],
              selectedSortId: showCount ? _sortOrder.name : null,
              onSortSelected: showCount ? _onSortSelected : null,
              children: [
                for (final suggestion in suggestions)
                  _suggestionTile(suggestion),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _suggestionTile(StoreSuggestion suggestion) {
    // 묶인 시설(화장실 19곳)에서 **어느 매장의 층을 적을지**를 여기서 정한다.
    // 예전에는 인덱스 첫 번째였고, 인덱스가 `Floor.level DESC`라 늘 꼭대기 층이
    // 대표였다 — B2에 서 있어도 `화장실 · 6F 등 19곳`. 규칙과 실패 조건은
    // [nearestByWalkingDistance](../domain/nearest_store.dart)가 단일 출처다.
    final nearest = nearestByWalkingDistance(
      stores: suggestion.stores,
      reachByNodeId: widget.reachByNodeId,
      currentFloorId: widget.currentFloorId,
    );
    final store = nearest.store;
    final reach = nearest.reach;
    final categoryLabel =
        subcategoryLabelFor(store.subcategory) ?? store.category;
    // 층마다 있는 시설(화장실 19건)은 한 줄로 묶여 온다. 몇 곳인지 적어 주지
    // 않으면 사용자는 "왜 한 층만 나오지"로 읽는다. **개수는 거리를 아는 곳이
    // 몇인지와 무관하게 묶인 전체다** — 19곳 중 3곳만 도달 가능하다고 `등 3곳`
    // 으로 적으면 없는 사실을 만들어 낸다.
    final count = suggestion.stores.length;
    final floorLine = count > 1
        ? '${store.floorName} 등 $count곳'
        : store.floorName;
    return RoutexListCell(
      key: Key('suggestion-${store.id}'),
      // 돋보기와 핀 2종만 쓰는 네이버 관례를 따른다. 교정 후보만 다른 아이콘으로
      // "이건 네가 친 말이 아니다"를 알린다 — 검증 기준(L)의 "교정 후보임이
      // 화면에 드러남"이 이 아이콘과 아래 하이라이트 없음으로 충족된다.
      leadingIcon: suggestion.kind.isCorrection
          ? Icons.auto_fix_high
          : Icons.search,
      // 종류가 섞인 목록이라 아이콘은 모양으로만 가른다. 강조색은 일치 구간 몫이다.
      leadingIconTone: RoutexListIconTone.quiet,
      title: store.name,
      // 교정 후보는 사용자가 친 글자와 이름이 어긋나 있어 하나도 안 걸린다.
      // 그게 정상이다([nameHighlightRanges] 주석).
      titleHighlights: nameHighlightRanges(store.name, widget.query),
      // 결과 목록과 같은 두 줄 구조다. 후보 목록이 사실상 결과 화면으로도 쓰이는데
      // (서버가 한 곳을 지목 못 한 브랜드 질의) 거리만 없어서, 가장 흔한 검색이
      // 가장 빈약한 화면으로 가고 있었다. 설계: docs/client/search-result-list-ux.md O절.
      subtitle: [?categoryLabel, floorLine].join(' · '),
      metric: reach == null ? null : reachLabel(reach),
      onPressed: () {
        // 한 곳짜리 후보는 그 매장을 열면 그만이다. 예전에는 여기서도 이름으로
        // 검색을 다시 돌렸는데(아래 분기), 그러면 사용자가 방금 고른 것과 사실상
        // 같은 줄을 결과 목록에서 한 번 더 눌러야 했다. 좌표가 없어서 생긴
        // 우회였고, 좌표는 상위가 층 지도에서 찾아 붙인다.
        if (count == 1) {
          widget.onSuggestionPicked(store);
          return;
        }
        // 묶인 시설(화장실 19곳)은 목록을 펼친다 — 한 곳을 바로 열면 나머지 18곳을
        // 고를 방법이 사라진다. 층은 화면에 적힌 그 층으로 확정한다.
        _floorScopeOnce = _FloorScopeOverride(store.floorId);
        widget.onQueryPicked(store.name);
      },
    );
  }

  /// 아직 아무것도 치지 않은 화면. 최근 검색어가 있으면 그걸, 없으면 안내 문구만.
  ///
  /// **"인기 매장"은 만들지 않는다** — 방문·클릭 로그가 없어 순위 근거가 없다
  /// (naver-map-ui-ux-analysis.md J절). 첫 실행의 빈 목록은 정상 상태다.
  Widget _idleState() {
    return ListenableBuilder(
      listenable: recentSearchesController,
      builder: (context, _) {
        final queries = recentSearchesController.queries;
        if (queries.isEmpty) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 22),
            child: Text(
              '매장 이름을 입력하면 바로 찾아드려요.\n'
              '"밥 먹을 곳"처럼 뜻으로 물어도 됩니다.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.muted,
                height: 1.5,
              ),
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 목록이 상한(컨트롤러의 maxEntries)까지 차도 패널이 화면을 다 먹지
            // 않도록 상위가 준 높이 안에서 스크롤시킨다. 결과 목록과 같은 이유로
            // ListView가 아니라 Column + SingleChildScrollView다(아래 _resultList
            // 주석 참고).
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 8),
                child: RoutexRecentList(
                  title: '최근 검색어',
                  onClear: recentSearchesController.clear,
                  items: [
                    for (final query in queries)
                      RoutexRecentItem(
                        id: 'recent-$query',
                        title: query,
                        onRemove: () => recentSearchesController.remove(query),
                        onPressed: () {
                          // 최근 검색어는 문자열 하나뿐이라 어느 층 매장인지
                          // 모른다. 다시 검색할 때는 층 스코프를 뺀다.
                          _floorScopeOnce = const _FloorScopeOverride(null);
                          widget.onQueryPicked(query);
                        },
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 아직 결론이 아니라는 화면. 의미 검색으로 넘어가면 기다리는 이유를 덧붙인다.
  Widget _searchingState() {
    return RoutexResultList(
      status: RoutexResultStatus.loading,
      loadingMessage: _phase == _SearchPhase.semanticSearching
          ? '취향에 맞는 매장을 찾는 중 · 처음 한 번은 조금 오래 걸릴 수 있어요'
          : null,
      children: const [],
    );
  }

  Widget _resultList() {
    // 목록 **위**에 서는 것들. 결과 행이 아니라 이 화면이 지금 무엇을 보여 주는지를
    // 말하는 조각이라, 개수·정렬 머리말보다 위에 둔다.
    final prelude = <Widget>[];
    // 바깥 결과 덕분에 목록이 먼저 떴을 뿐, 건물 안 검색은 아직 돌고 있을 수
    // 있다. 그 사실을 안 밝히면 사용자는 이게 최종 목록이라고 읽는다.
    if (_phase == _SearchPhase.typingLightSearch ||
        _phase == _SearchPhase.semanticSearching) {
      prelude.add(const _IndoorSearchingRow());
    }
    final isDiscovery = _discoveryMode != null;
    if (isDiscovery) prelude.add(_discoveryHeader());
    if (_fromSemantic) {
      prelude.add(
        const Padding(
          padding: _sectionLabelPadding,
          child: Row(
            children: [
              Icon(Icons.auto_awesome, size: 14, color: AppColors.primary),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  '뜻이 비슷한 매장을 찾았어요',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final building = _building;
    if (building != null) {
      // **결과 목록 밖이다.** "검색 결과 N"의 N은 매장 수이고 건물은 세지 않으므로,
      // 머리말 위에 두어야 그 줄까지 세는 것처럼 읽히지 않는다.
      prelude.add(
        RoutexListCell(
          // 종류는 아이콘 모양으로만 가른다(건물/매장/제안). 색까지 다르면 한 목록이
          // 칸칸이 나뉘어 보인다 — 강조색은 일치 구간 몫이다.
          leadingIcon: Icons.apartment_outlined,
          leadingIconTone: RoutexListIconTone.quiet,
          title: building.name,
          titleHighlights: nameHighlightRanges(building.name, _submittedQuery),
          subtitle: '건물 · ${building.floors.length}개 층',
          onPressed: () => widget.onBuildingPicked(building),
        ),
      );
    }
    // 규칙과 실패 조건은 domain/search/search_result_order.dart가 단일 출처.
    // build에서 세우는 이유는 `widget.reachByNodeId`가 위치를 새로 잡을 때마다
    // 바뀌기 때문이다 — 받는 시점에 한 번만 세우면 거리와 순서가 어긋난다.
    final ordered = sortedSearchResults(
      results: _results,
      reachByNodeId: widget.reachByNodeId,
      fromSemantic: _fromSemantic,
      order: _sortOrder,
    );
    // 개수·층 머리말과 정렬 컨트롤은 **결론인 목록에만** 얹는다. clarify는 아직
    // 질문이 서 있는 화면이라 질문·선택지 줄 위에 개수를 또 적으면 무엇을 먼저
    // 읽어야 할지 흐려지고, 의미 검색 결과는 유사도순이라 고를 수 있는 축이
    // 아니다(`canChooseSortOrder`).
    final canChoose =
        _discoveryMode != DiscoveryMode.clarify &&
        canChooseSortOrder(
          itemCount: ordered.length,
          fromSemantic: _fromSemantic,
        );
    final rows = <Widget>[];
    // 추천 이유는 **storeId로** 짝짓는다. 인덱스로 맞추면 정렬이 들어올 때 이유가
    // 엉뚱한 매장에 붙고, 그 조합은 실제 경로로 존재한다(`_fromSemantic`이 false
    // 인데 `_discoveryMatches`는 차 있는 경우).
    final matchByStoreId = {
      for (final match in _discoveryMatches) match.storeId: match,
    };
    // 모든 행에 똑같이 들어 있는 근거 문장은 행에서 빼고 층에 자리를 돌려준다.
    // 규칙과 이유는 [distinctiveReason](../domain/reason_text.dart)이 단일 출처다.
    final sharedReasons = sharedReasonSentences(
      _discoveryMatches.map((match) => match.reason),
    );
    // 바깥 줄이 섞이는 순간부터 우리 매장 줄에 **건물 이름**을 붙인다 — 그 줄들은
    // 주소가 있는데 우리 줄만 층 하나면 어느 건물인지 알 수 없다.
    // "실내 컨텍스트인가"로 가르지 않는다. 오버레이는 확대만 해도 켜져서
    // (indoor_entry_zoom.dart) 건물 근처 검색에서 이름이 통째로 사라졌다.
    final merged = _mergedResults(building);
    final showBuildingName = merged.outdoorRows.isNotEmpty;
    for (final store in ordered) {
      final placeId = store.placeId;
      rows.add(
        _storeTile(
          store,
          placeId == null ? null : matchByStoreId[placeId],
          sharedReasons,
          showBuildingName: showBuildingName,
        ),
      );
    }
    rows.addAll(_siblingRows(ordered));

    // 건물 밖 결과는 **항상 실내 아래**에 둔다. 이 앱의 본업은 건물 안 길찾기라,
    // 같은 이름이 안팎에 다 있으면 사용자가 지금 서 있는 건물 안 매장을 먼저
    // 보는 것이 맞다. 대신 어디까지가 우리 건물이고 어디부터 바깥인지 헤더로
    // 명확히 가른다 — 안 가르면 다른 건물 매장을 우리 매장으로 오해한다.
    final onPoiPicked = widget.onOutdoorPoiPicked;
    if (merged.outdoorRows.isNotEmpty && onPoiPicked != null) {
      rows.add(_outdoorHeader());
      for (final row in merged.outdoorRows) {
        rows.add(_poiTile(row, onPoiPicked));
      }
    }

    // 그릴 줄이 하나도 없으면 빈 패널 대신 없다고 말한다. 사용자는 빈 패널을
    // "앱이 멈췄다"로 읽는다. **안내 줄만 있어도 빈손이 아니다** — 되물음은 질문을
    // 세워 놓고 "찾지 못했어요"라고 답하면 안 된다.
    if (prelude.isEmpty && rows.isEmpty) return _emptyState(context);

    // **`ListView(shrinkWrap: true)`가 아닌 이유** — 느슨한 제약(maxHeight만 있고
    // tight가 아닌) 안에서 스크롤 범위를 내용보다 짧게 잡아 30건 중 29번째에서
    // 멈췄다(마지막 타일에 영영 도달하지 못함). 상한이 30이라 지연 생성으로 아낄
    // 것도 없다. 구분선은 두지 않는다(행 리듬은 RoutexListCell이 갖는다).
    return Scrollbar(
      controller: _resultScrollController,
      child: SingleChildScrollView(
        controller: _resultScrollController,
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...prelude,
            if (rows.isNotEmpty)
              RoutexResultList(
                status: RoutexResultStatus.ready,
                summary: canChoose
                    ? _listSummary(
                        count: ordered.length,
                        floorNames: [for (final store in ordered) store.floor],
                      )
                    : null,
                sortOptions: canChoose ? _sortOptions : const [],
                selectedSortId: canChoose ? _sortOrder.name : null,
                onSortSelected: canChoose ? _onSortSelected : null,
                children: rows,
              ),
          ],
        ),
      ),
    );
  }

  /// 서버가 확정한 1건 **아래에** 같은 계열 매장을 잇는 행들(`구찌` → `구찌 뷰티`).
  /// 규칙과 실패 조건은 domain/search/name_siblings.dart가 단일 출처다.
  ///
  /// **정확 일치 행은 맨 위에 고정**하므로 이 화면에는 정렬 컨트롤을 두지 않는다 —
  /// 머리 행이 고정된 목록은 정렬 기준 하나로 설명되지 않는다.
  List<Widget> _siblingRows(List<PoiSearchResult> ordered) {
    // 경량 경로가 확정한 1건일 때만이다. 의미 검색·discovery 결과는 이름으로
    // 걸린 게 아니라 형제라는 개념 자체가 없다.
    if (_discoveryMode != null || _fromSemantic) return const [];
    if (ordered.length != 1) return const [];

    final siblings = nameSiblings(
      suggestions: _suggestions,
      confirmedName: ordered.single.name,
    );
    if (siblings.isEmpty) return const [];

    final sorted = sortedSuggestions(
      suggestions: siblings,
      reachByNodeId: widget.reachByNodeId,
      order: _sortOrder,
    );
    return [
      Padding(
        padding: _sectionLabelPadding,
        child: Text(
          '관련 매장 ${sorted.length}곳',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.muted,
          ),
        ),
      ),
      for (final suggestion in sorted) _suggestionTile(suggestion),
    ];
  }

  Widget _discoveryHeader() {
    final isClarify = _discoveryMode == DiscoveryMode.clarify;
    final hasSelection = _selectedFacets.isNotEmpty;

    // 두 버튼은 clarify 흐름의 조작 수단이라 되물음이 없는 화면에서는 누를 대상이
    // 없다. mode가 화면 분기의 유일한 근거라는 계약(DiscoveryResponse)을 여기서도
    // 지킨다. "전체 보기"는 아직 안 본 후보가 남아 있을 때만 뜻이 있다.
    final canShowAll = (isClarify || hasSelection) && !_showingAll;
    // "다시 선택"은 되돌릴 답이 있을 때다. 선택 없이 전체 보기로 질문을 건너뛴
    // 상태도 포함한다 — 그 화면에서는 이 버튼이 질문으로 돌아가는 유일한 길이다.
    final canChooseAgain = hasSelection || _showingAll;

    // 선택·되돌리기 줄. 답을 한 번이라도 골랐을 때만 선다.
    //
    // **값 하나에 줄 하나다.** 이 줄의 선택은 축마다 하나씩 여럿인데 칩 줄의 선택은
    // 없거나 하나라, 한 줄에 다 담으면 여러 개를 동시에 강조할 수 없다. 줄을 값마다
    // 두면 각자 자기 하나를 고른 상태가 되고, 가로 스크롤은 바깥 ListView가 이미
    // 소유하고 있어 `deferToParent`가 성립한다.
    //
    // **`×`를 붙이지 않는다.** 고른 값을 다시 누르면 풀리는 것이 칩 줄의 계약이라
    // 동작은 그대로고, 위 선택지 줄은 아무것도 안 골라 회색이라 두 줄이 색으로 이미
    // 갈린다. 해제 글리프는 예전에 계약으로 냈다가 어댑터가 이미 풀고 있어 걷어낸
    // 것이다(v0.2.9).
    final selectedRow = <Widget>[];
    for (final entry in _selectedFacets.entries) {
      for (final value in entry.value) {
        if (selectedRow.isNotEmpty) {
          selectedRow.add(const SizedBox(width: RoutexSpacing.controlGap));
        }
        selectedRow.add(
          RoutexChipBar(
            key: Key('selected-facet-${entry.key}-$value'),
            options: [RoutexChipOption(id: value, label: value)],
            selectedId: value,
            overflow: RoutexChipBarOverflow.deferToParent,
            onSelected: (_) => _removeFacet(entry.key, value),
          ),
        );
      }
    }
    // 조작(전체 보기·다시 선택)은 **칩이 아니라 버튼이다.** 위 칩들은 "이 값으로
    // 좁혀라"이고 이 둘은 "좁히지 말고 다 봐라"·"방금 답을 되돌려라"라 성격이 다르다.
    // 같은 모양으로 두고 구분선으로 가르던 것을 그만둔다 — 모양이 다르면 선이 필요
    // 없다. clarify 화면에서는 전체 보기가 이미 선택지 줄 끝에 있어 여기서는 뺀다.
    final trailingActions = <Widget>[
      if (canShowAll && !isClarify)
        RoutexButton(
          key: const Key('show-all'),
          label: '전체 보기',
          variant: RoutexButtonVariant.quiet,
          onPressed: () => _requestDiscovery(showAll: true),
        ),
      if (canChooseAgain)
        RoutexButton(
          key: const Key('choose-again'),
          label: '다시 선택',
          variant: RoutexButtonVariant.quiet,
          onPressed: _chooseAgain,
        ),
    ];
    for (final action in trailingActions) {
      if (selectedRow.isNotEmpty) {
        selectedRow.add(const SizedBox(width: RoutexSpacing.controlGap));
      }
      selectedRow.add(action);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_discoveryMode == DiscoveryMode.degraded)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text(
                '일부 추천 기능이 준비되지 않아 제한된 결과만 보여드려요.',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
          if (isClarify) ...[
            // 질문은 이 패널의 다른 머리말(`검색어 제안`·`최근 검색어`)과 같은
            // 크기·색으로 둔다. 예전에는 14/굵게라 질문이 결과보다 커 보였는데,
            // 여기서 물어보는 건 답을 좁히는 보조 수단이지 화면의 주인공이 아니다.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text(
                _discoveryQuestion ?? '어떤 조건을 더 중요하게 보시나요?',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted,
                ),
              ),
            ),
            // **선택지는 한 줄에서 가로로 스크롤한다.** Wrap으로 접으면 다섯 개짜리
            // 축(styles)에서 두 줄이 되고, 질문·전체 보기까지 합쳐 세로 150px가
            // 넘어가 정작 결과 목록이 화면 밖으로 밀린다. 줄을 고정하면 선택지가
            // 몇 개든 패널 높이가 그대로다.
            if (_discoveryOptions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: RoutexChipBar(
                        options: [
                          for (final option in _discoveryOptions)
                            RoutexChipOption(
                              // 칩 줄이 이 id를 그대로 위젯 key로 쓴다.
                              id: 'facet-option-${option.facet}-${option.value}',
                              label: option.label,
                              count: option.count,
                            ),
                        ],
                        // 고르는 순간 다음 질문으로 넘어가므로 이 줄에는 선택이
                        // 머무르지 않는다.
                        selectedId: null,
                        onSelected: (id) {
                          if (id == null) return;
                          _selectFacet(
                            _discoveryOptions.firstWhere(
                              (option) =>
                                  'facet-option-${option.facet}-${option.value}' ==
                                  id,
                            ),
                          );
                        },
                        semanticsLabel: '선택지',
                      ),
                    ),
                    // **줄 안에 섞지 않는다.** 위 칩들은 "이 값으로 좁혀라"이고 이건
                    // "좁히지 말고 다 봐라"다. 예전에는 구분선으로 갈랐는데, 성격이
                    // 다른 것을 같은 줄에 두고 선으로 나누는 것보다 스크롤 밖에
                    // 고정해 두는 편이 분명하다 — 선택지가 길어도 안 밀려난다.
                    if (canShowAll) ...[
                      const SizedBox(width: RoutexSpacing.controlGap),
                      RoutexButton(
                        key: const Key('show-all'),
                        label: '전체 보기',
                        variant: RoutexButtonVariant.quiet,
                        onPressed: () => _requestDiscovery(showAll: true),
                      ),
                    ],
                  ],
                ),
              ),
          ],
          if (selectedRow.isNotEmpty) ...[
            if (isClarify) const SizedBox(height: 6),
            SizedBox(
              // 칩이 터치 영역 48을 감싸고 있어 30에 두면 그 자리에서 넘친다.
              height: RoutexMetrics.minimumTouchTarget,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: selectedRow,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 결과 한 줄. 이름(검색어 강조) + 업종을 한 줄에, 그 아래 층 또는 추천 이유.
  ///
  /// 업종을 아이콘이 아니라 **이름 오른쪽 회색 글자**로 두면 매장마다 글리프를 만들지
  /// 않고도 소분류까지 읽힌다. [showBuildingName]의 판단은 호출부([_resultList])에.
  Widget _storeTile(
    PoiSearchResult store,
    DiscoveryMatch? match,
    Set<String> sharedReasons, {
    bool showBuildingName = false,
  }) {
    // 소분류가 없는 장소에서 업종이 통째로 사라지지 않도록 대분류로 떨어뜨린다 —
    // 상세 시트를 여는 호출부(MapShellScreen._showStoreInfo)와 같은 규칙이다.
    final categoryLabel =
        subcategoryLabelFor(store.subcategory) ?? store.category;
    // 노드가 없는 매장은 애초에 경로를 못 그리므로 거리도 없다. 그 사실은
    // 아래 첫 줄의 "경로 안내 불가"가 이미 말한다.
    final nodeId = store.nodeId;
    final reach = nodeId == null ? null : widget.reachByNodeId?[nodeId];
    // 층은 **항상** 남긴다. 예전에는 reason이 층을 통째로 대체해서, 다섯 행이 같은
    // 문장을 되풀이하는 동안 정작 몇 층인지가 화면에서 사라졌다.
    final reason = distinctiveReason(match?.reason, sharedReasons);
    final buildingName = showBuildingName ? _currentBuildingName : null;
    final placeLine = buildingName == null
        ? store.floor
        : '$buildingName · ${store.floor}';
    final floorLine = nodeId == null ? '$placeLine · 경로 안내 불가' : placeLine;
    final firstLine = reason == null ? floorLine : '$floorLine · $reason';
    return RoutexListCell(
      // 후보 행과 같은 리듬이다. 예전에는 결과 행만 굵은 이름·파란 핀이라, 같은
      // 매장이 후보 화면과 결과 화면에서 다른 줄처럼 보였다. 종류는 아이콘
      // 모양(핀/돋보기)으로만 가른다.
      leadingIcon: Icons.place_outlined,
      leadingIconTone: RoutexListIconTone.quiet,
      title: store.name,
      titleHighlights: nameHighlightRanges(store.name, _submittedQuery),
      // 업종은 이름 오른쪽이 아니라 맥락 줄 맨 앞이다. 그 자리는 폭 상한이 있어
      // 긴 업종이 이미 반쯤 잘려 나왔고, 잘린 업종은 정보가 아니라 얼룩이다.
      subtitle: [?categoryLabel, firstLine].join(' · '),
      // 거리는 "지금 갈지"를 정하는 값이라 맥락과 줄을 나눈다.
      metric: reach == null ? null : reachLabel(reach),
      onPressed: () => widget.onStorePicked(store),
    );
  }

  /// 목록에 실제로 그릴 바깥 줄. 같은 곳을 두 번 보여주지 않는다.
  ///
  /// **POI 쪽으로 합친다** — 이름은 POI, 능력은 우리 데이터([mergeOutdoorResults]).
  /// 건물 줄과 이름이 **완전히 같은** POI도 뺀다. `contains`로 넓히지 않는 이유는
  /// "더현대서울 스타벅스"처럼 건물 이름을 앞에 단 진짜 결과까지 사라져서다.
  MergedOutdoorResults _mergedResults(Building? building) {
    final isAt = widget.isInsideIndoorBuilding;
    final merged = mergeOutdoorResults(
      pois: _pois,
      indoorStores: _results,
      // 판정을 못 하면 아무 POI도 건물 것으로 보지 않는다. 그러면 지금까지처럼
      // 두 줄이 남을 뿐이고, 잘못 합쳐 엉뚱한 매장으로 안내하지는 않는다.
      isAtBuilding: (poi) => isAt?.call(poi.point) ?? false,
      buildingNames: _buildingNames,
    );
    _logMerge(merged);
    if (building == null) return merged;

    final key = collapseName(building.name);
    return MergedOutdoorResults(
      merged.outdoorRows
          .where((row) => collapseName(row.poi.name) != key)
          .toList(),
      merged.indoorStores,
    );
  }

  /// 직전에 남긴 로그 한 줄. build마다 같은 말을 반복하지 않으려고 들고 있는다.
  String _lastMergeLog = '';

  /// **연결 결과를 로그로 남긴다.** 화면에서는 "연결됐다"와 "연결할 게 없었다"가
  /// 똑같이 보여(둘 다 POI 줄 하나) 규칙이 안 도는 것을 눈으로 구분할 수 없다.
  void _logMerge(MergedOutdoorResults merged) {
    if (_pois.isEmpty) return;
    final dropped = _pois.length - merged.outdoorRows.length;
    final line =
        '[poi-merge] 바깥 ${_pois.length}건 중 $dropped건이 우리 매장과 겹쳐 빠짐 '
        '(실내 후보 ${_results.length}건, 건물 이름 $_buildingNames)';
    if (line == _lastMergeLog) return;
    _lastMergeLog = line;
    debugPrint(line);
    for (final row in merged.outdoorRows) {
      debugPrint('[poi-merge]   남김: "${row.poi.name}"');
    }
  }

  /// "건물 밖" 구분선. 여기부터는 우리 백엔드가 아니라 외부 지도(TMAP)에서 온
  /// 결과라는 것도 함께 밝힌다 — 정보의 깊이가 다른 이유이고, 실제와 다를 때
  /// 사용자가 어디를 의심할지 알려 준다.
  Widget _outdoorHeader() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          Icon(Icons.explore_outlined, size: 14, color: AppColors.muted),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              '건물 밖 주변 장소',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.muted,
              ),
            ),
          ),
          Text(
            'TMAP',
            style: TextStyle(fontSize: 10.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  /// 건물 밖 장소 한 줄. 실내 줄과 모양을 맞추되, **층 대신 주소와 직선 거리**를
  /// 적는다. 밖에서는 같은 이름의 지점이 여럿이라, 어느 지점인지 가르는 단서가
  /// 층이 아니라 주소다.
  Widget _poiTile(OutdoorSearchRow row, ValueChanged<OutdoorPoi> onPicked) {
    final poi = row.poi;
    final distance = poi.distanceMeters;
    // 거리는 맥락이 아니라 **고를지 정하는 값**이라 아래 [RoutexListCell.metric]으로
    // 올라간다. 여기 남는 것은 "어디에 있는가"뿐이다.
    final subtitleParts = [
      if (poi.category != null) poi.category!,
      if (poi.address != null) poi.address!,
    ];
    return RoutexListCell(
      leadingIcon: Icons.storefront_outlined,
      leadingIconTone: RoutexListIconTone.quiet,
      title: poi.name,
      titleHighlights: nameHighlightRanges(poi.name, _submittedQuery),
      subtitle: subtitleParts.isEmpty ? null : subtitleParts.join(' · '),
      metric: distance == null ? null : '약 ${formatDistance(distance)}',
      onPressed: () => onPicked(poi),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '"$_submittedQuery"에 맞는 매장을 찾지 못했어요.',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          // 이 문구가 나오는 시점에는 경량과 의미 검색을 모두 돌린 뒤다
          // (_SearchPhase.noMatch에서만 그린다). 말을 바꿔 보라는 것 말고
          // 사용자가 더 눌러 볼 수단이 있는 것처럼 보이면 안 된다.
          const Text(
            '다른 말로 바꿔서 다시 찾아보세요.',
            style: TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
          _browseCategories(),
        ],
      ),
    );
  }

  /// 못 찾았을 때의 탈출구 — 카테고리로 둘러보기(R절). 순위 근거가 없어
  /// "인기 검색어"는 두지 않고, 이 건물에 실제로 있는 대분류만 놓는다.
  ///
  /// **야외에서는 그리지 않는다** — 아직 안 들어간 건물의 카테고리를 누르게 되고,
  /// 지도 강조는 도면 위에 그려져 결과가 보이지 않는다.
  Widget _browseCategories() {
    final entries = widget.categoryEntries;
    final onPicked = widget.onCategoryPicked;
    if (entries == null || onPicked == null || !widget.indoorContextActive) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<List<CategoryCount>>(
      future: entries,
      builder: (context, snapshot) {
        // 로드 실패·미완료는 **줄만 조용히 사라진다.** 상위 지도 오버레이는 실패를
        // 재시도 칩으로 드러내지만, 여기서는 부가 제안이라 "찾지 못했어요" 화면에
        // 오류를 하나 더 얹을 이유가 없다.
        final categories = sortedCategoryLabels(
          (snapshot.data ?? const <CategoryCount>[]).map((e) => e.category),
        );
        if (categories.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '카테고리로 둘러보기',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: 8),
              // 대분류가 6~7개라 접으면 두 줄이 된다. 이 화면은 결과가 없어
              // 세로가 남으므로 Wrap으로 두어 한눈에 다 보이게 한다.
              //
              // 칩 줄을 분류마다 하나씩 둔다. 줄이 여럿을 담으면 스스로 가로로
              // 넘기는데(`RoutexChipBarOverflow.scroll`) 그러면 이 화면의 탈출구
              // 절반이 접혀 사라진다. 하나짜리 줄은 넘칠 것이 없어 `deferToParent`가
              // 성립하고, 접는 일은 바깥 Wrap이 맡는다.
              Wrap(
                spacing: RoutexSpacing.controlGap,
                runSpacing: RoutexSpacing.controlGap,
                children: [
                  for (final category in categories)
                    RoutexChipBar(
                      key: Key('browse-category-$category'),
                      options: [RoutexChipOption.category(category)],
                      selectedId: null,
                      overflow: RoutexChipBarOverflow.deferToParent,
                      onSelected: (_) => onPicked(category),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _degradedState() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 20, 16, 22),
      child: RoutexResultList(
        status: RoutexResultStatus.degraded,
        statusMessage: '잠시 후 다시 검색하거나 다른 표현으로 찾아보세요.',
        children: [],
      ),
    );
  }

  /// 검색을 끝내지 못한 화면. "찾지 못했어요"와 문구를 나누는 이유는 사용자가
  /// 할 행동이 다르기 때문이다 — 여기서는 말을 바꿔도 소용이 없다. 다시 시도가
  /// 붙는 것도 그래서다.
  Widget _errorState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 22),
      child: RoutexResultList(
        status: RoutexResultStatus.error,
        statusMessage: '연결 상태를 확인하고 잠시 후 다시 시도해 주세요.',
        statusActionLabel: '다시 시도',
        onStatusAction: () => unawaited(_search(widget.query, immediate: true)),
        children: const [],
      ),
    );
  }
}

/// 목록 맨 위에 붙는 "건물 안은 아직 찾는 중" 줄. 바깥 결과만 뜬 상태를 최종
/// 결과로 읽으면 사용자는 "우리 건물엔 없구나"라며 검색을 닫는다.
class _IndoorSearchingRow extends StatelessWidget {
  const _IndoorSearchingRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: RoutexStatusBanner(
        title: '건물 안에서도 찾는 중…',
        detail: '바깥 결과를 먼저 보여드리고 있어요',
        icon: RoutexIcons.search,
      ),
    );
  }
}
