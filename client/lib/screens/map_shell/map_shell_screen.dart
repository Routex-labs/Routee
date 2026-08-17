import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/api_config.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../../routing/place_link.dart';
import '../../service_locator.dart';
import '../../domain/route/dijkstra.dart';
import '../../domain/store/nearby_stores.dart';
import '../../domain/store/nearest_store.dart';
import '../../domain/route/route_endpoint_fill.dart';
import '../../domain/route/route_endpoint_swap.dart';
import '../../core/single_flight.dart';
import '../../domain/search/store_suggestions.dart';
import '../../domain/route/transit_walk_fill.dart';
import '../../features/debug_mode/debug_mode.dart';
import '../../features/indoor_navigation/contract/floor_transition_ui_state.dart';
import '../../models/building/building.dart';
import '../../models/building/category_count.dart';
import '../../models/route/directions_route.dart';
import '../../models/place/favorite_place.dart';
import '../../models/building/floor_plan.dart';
import '../../models/place/outdoor_poi.dart';
import '../../models/place/poi_search_result.dart';
import '../../models/place/store_index_entry.dart';
import '../../models/route/transit_route.dart';
import 'widgets/sheets/app_menu_sheet.dart';
import '../../map/style/category_map_filter.dart';
import 'widgets/sheets/category_stores_sheet.dart';
import '../../models/route/directions_candidate.dart';
import 'widgets/sheets/favorites_sheet.dart';
import 'widgets/chrome/floor_transition_overlay.dart';
import 'widgets/chrome/map_bottom_bar.dart';
import 'widgets/chrome/map_top_bar.dart';
import 'widgets/sheets/outdoor_poi_sheet.dart';
import 'widgets/sheets/place_detail_sheet.dart';
import 'widgets/search/route_field_results.dart';
import '../../models/route/route_plan_mode.dart';
import 'widgets/search/search_panel.dart';
import 'widgets/sheets/transit_routes_sheet.dart';
import 'widgets/chrome/category_chips_row.dart';
import 'widgets/chrome/map_overlay_scroll_row.dart';
import 'widgets/chrome/map_pick_hint_card.dart';
import 'widgets/chrome/travel_mode_bar.dart';
import '../outdoor_map/outdoor_map_screen.dart';
import 'directions_candidates.dart';
import 'transit_walk_handoff.dart';
import 'walk_route_kind.dart';

/// 야외/실내 지도의 공통 뼈대. 홈(야외) ↔ 실내 전환은 Navigator push 없이
/// 이 화면 안에서 모드만 바꿔 탭처럼 즉시 반응하게 한다. 검색·길찾기·앱
/// 메뉴·위치 보정은 전부 이 화면이 상단/하단 공용 바를 통해 중계한다.
class MapShellScreen extends StatefulWidget {
  const MapShellScreen({super.key});

  @override
  State<MapShellScreen> createState() => _MapShellScreenState();
}

/// 경로가 표시되면 ETA 카드가 화면 최하단에 직접 도킹하므로, 하단 공용 바를
/// 그 위로 띄워야 하는 높이. EtaCard 실제 높이(패딩 포함)에 여유를 더한 값.
const _etaBarLiftHeight = 92.0;

/// 카테고리 필터 pill이 쓰는 (층·대분류·소분류)별 매장 수.
///
/// pill은 대분류·소분류만 읽는다. 층·개수는 지도 위 "이 층 N곳" 안내가 쓰던
/// 값인데, 그 안내를 걷어내고 목록 시트가 층별 묶음으로 대신 답하도록 바꿨다
/// (`category_stores_sheet.dart`). 응답 스키마라 필드는 그대로 두되, 이 화면은
/// 더 이상 읽지 않는다.
typedef _CategoryEntry = CategoryCount;

class _MapShellScreenState extends State<MapShellScreen> {
  /// 상단 오버레이 사이 간격. 예전 top: 78 / top: 128 같은 고정 offset을
  /// 대신하는 유일한 값이다. 상단 바 높이가 상태에 따라 달라져도 이 간격은
  /// 그대로라 어느 모드에서든 같은 여백으로 보인다.
  static const _overlayGap = 8.0;

  /// 이 앱이 다루는 건물. 한동안 햄버거 버튼이 "건물 선택 (테스트)" 시트를 열어
  /// 백엔드에 적재된 건물 목록에서 바꿀 수 있었지만, 데모용 전환 수단이었고
  /// 실제 사용 흐름에는 없는 조작이라 걷어냈다. 여러 건물을 실제로 다루게 되면
  /// 그때는 시트가 아니라 지도에서 건물을 골라 들어오는 흐름이어야 한다.
  static const _buildingId = demoBuildingId;

  /// 지도 위 카테고리 필터에서 지금 고른 것. null이면 강조 없음(기본 상태).
  /// 실내·야외 지도에 같은 값을 내려 두 화면의 강조가 어긋나지 않게 한다.
  CategorySelection? _categorySelection;

  /// 지금 보고 있는 층 라벨. 실내 지도가 onFloorChanged로 알려준다.
  /// [_activeIndoorFloor] getter와 값은 같지만, 이쪽은 **바뀔 때 rebuild가
  /// 도는** 상태다 — getter만 읽으면 층을 바꿔도 "이 층 N곳"이 옛 층에 머문다.
  ///
  /// 야외 지도도 실내 진입 오버레이가 켜지면 같은 콜백으로 알려준다. 그쪽에서도
  /// 카테고리 필터를 쓰므로, 안 받으면 "이 층 N곳"이 실내 탭에 들렀을 때의 옛
  /// 층에 머문다. 오버레이가 꺼진 순수 야외에서는 null이 올라온다.
  String? _activeFloorLabel;

  /// 건물의 (층·대분류·소분류)별 매장 수. pill 목록과 개수 안내가 같은 데이터를
  /// 봐야 하므로 화면 하나가 소유하고 아래로 내려 준다.
  ///
  /// **요청 하나다.** 예전에는 같은 정보를 얻으려고 층 지도를 층마다 받아
  /// (더현대 서울 기준 12건) 매장을 직접 셌다. 매장 폴리곤·좌표·그래프까지
  /// 따라오는 응답이라, 세 문자열과 개수를 얻는 값으로는 너무 비쌌다.
  late Future<List<_CategoryEntry>> _categoryEntriesFuture =
      _loadCategoryEntries();

  Future<List<_CategoryEntry>> _loadCategoryEntries() async {
    return await buildingRepository.getCategoryCounts(_buildingId) ?? const [];
  }

  /// 카테고리 목록을 다시 읽는다.
  ///
  /// **이 화면이 Future를 한 번만 만들기 때문에 필요하다.** 리포지토리는 실패한
  /// 요청을 캐시에 남기지 않지만([HttpBuildingRepository] `_shared` 주석), 이
  /// 화면이 들고 있는 Future 자체는 실패한 그대로 남는다. 앱을 켠 직후 네트워크가
  /// 아직 안 붙었거나 서버가 콜드 스타트 중이면 그 한 번의 실패가 세션 내내
  /// "칩이 아예 없는 화면"으로 굳는다 — 새 Future를 만들어야 다시 시도된다.
  void _reloadCategoryEntries() {
    setState(() => _categoryEntriesFuture = _loadCategoryEntries());
  }

  void _onActiveFloorChanged(String? floor) {
    if (_activeFloorLabel == floor || !mounted) return;
    setState(() => _activeFloorLabel = floor);
  }

  /// 실내 지도가 알려 온 층 전환 상태를 받는다.
  ///
  /// 탑승이 감지되면 검색을 닫는다. 검색 패널은 상단 Column 전체를 차지해
  /// 배너가 들어갈 자리가 없고, 그 순간 사용자에게 더 급한 정보는 길안내다.
  void _onFloorTransitionChanged(
    FloorTransitionUiState? banner,
    double scrimOpacity,
  ) {
    if (!mounted) return;
    if (_floorTransition == banner && _floorScrimOpacity == scrimOpacity) {
      return;
    }
    if (banner != null && _searchActive) {
      _closeSearch();
    }
    setState(() {
      _floorTransition = banner;
      _floorScrimOpacity = scrimOpacity;
    });
  }

  /// 카테고리 선택을 바꾼다. 지도 강조는 상태를 내려받은 두 지도가 알아서
  /// 갱신하므로 여기서는 상태만 바꾼다.
  void _onCategorySelectionChanged(CategorySelection? selection) {
    if (_categorySelection == selection) return;
    setState(() => _categorySelection = selection);
  }

  /// 지도 위 대분류 chip을 눌렀을 때. 강조를 걸고 **곧바로** 목록 시트를 연다.
  ///
  /// 같은 chip을 다시 누르면([selection]이 null) 해제만 한다 — 해제 수단이 없으면
  /// 필터를 되돌릴 방법이 없다.
  ///
  /// **떠 있는 목록 시트를 먼저 닫는다.** 이 시트는 barrier가 없어 chip 줄이 위에
  /// 그대로 눌리므로, 안 닫으면 누른 횟수만큼 시트가 쌓인다.
  Future<void> _onCategoryChipTapped(CategorySelection? selection) async {
    _onCategorySelectionChanged(selection);
    final closing = _categorySheetClosing;
    if (closing != null) {
      // pop은 chain 전체를 닫으라는 신호를 만들지만(PopScope), 아래
      // `_runSheetChain`이 시작할 때 그 플래그를 초기화하므로 새 시트에는
      // 영향이 없다([_openStoreFromMap]과 같은 규칙).
      Navigator.of(context).pop();
      await closing;
      if (!mounted) return;
    }
    // 해제(다시 누르기)는 여기까지다 — 떠 있던 목록은 닫고 새로 열지는 않는다.
    final category = selection?.category;
    if (category == null) return;
    await _runSheetChain(() => _openCategoryStores(category));
  }

  /// 지금 떠 있는 카테고리 목록 시트가 닫히면 완료되는 Future. 안 떠 있으면 null.
  /// 상세 시트의 [_placeDetailClosing]과 같은 역할이다.
  Future<PoiSearchResult?>? _categorySheetClosing;

  /// 검색이 빈손일 때 패널이 제안한 카테고리를 골랐다(설계:
  /// `docs/client/search-result-list-ux.md` R절).
  ///
  /// **검색을 먼저 닫는다.** 검색 패널은 상단 Column 전체를 차지하므로, 열어 둔
  /// 채 시트를 띄우면 목록이 패널 뒤로 들어간다. 닫은 뒤에는 지도 위 chip을 누른
  /// 것과 완전히 같은 경로를 탄다 — 같은 결과에 이르는 길이 둘로 갈리면 한쪽만
  /// 고쳐지는 날이 온다.
  void _onSearchCategoryPicked(String category) {
    _closeSearch();
    _onCategoryChipTapped(CategorySelection(category: category));
  }

  bool _outdoorRouteVisible = false;

  /// 사용자가 고른 목적지로 안내 중인지. true면 지도 위 chrome(검색창·카테고리
  /// 줄·하단 바)을 접어 지도와 안내 카드만 남긴다. 판정 기준과 그렇게 나눈
  /// 이유는 `OutdoorMapBody`의 `_guidanceActive`에 있다.
  bool _guidanceActive = false;

  /// 실내 지도에서 "위치 지정" 흐름이 켜져 있는지. IndoorMapBody가 콜백으로
  /// 알려주며, 하단 바 "위치 지정" 버튼을 눌린 상태로 표시하는 데 쓴다.

  /// 야외 지도의 실내 진입 오버레이에서 "위치 지정" 흐름이 켜져 있는지.
  /// OutdoorMapBody가 콜백으로 알려주며, 실내와 동일하게 하단 바 버튼을 눌린
  /// 상태로 표시하는 데 쓴다.
  bool _outdoorPlacingLocation = false;

  /// 야외 지도의 실내 진입 오버레이가 지금 켜져 있는지. OutdoorMapBody가
  /// 건물 탭·줌 임계값 초과·GPS 근접 감지로 오버레이를 켤 때 이 값이 true가
  /// 되고, 하단 바의 "위치 지정" 버튼을 그때만 노출한다.
  bool _outdoorIndoorEntered = false;

  /// 사용자가 명시적으로 고른 출발지(매장 정보 시트 "출발지로 설정" 또는
  /// 길찾기 시트 안에서 특정 매장을 골랐을 때). 이 값이 채워져 있으면 이후
  /// 매장에서 "도착"을 누를 때 길찾기 시트를 다시 열지 않고 바로 이 출발지
  /// 기준으로 경로를 그린다. null이면 "현재 위치"(=PDR)을 기본 출발지로 쓴다.
  DirectionsCandidate? _selectedOrigin;

  /// 지금 지도에서 고르는 중인 칸. null이 아니면 매장 탭이 시트 대신 그 칸의
  /// 값이 된다.
  ///
  /// bool이 아니라 **어느 칸인지**를 들고 있어야 한다 — 출발지도 같은 방식으로
  /// 고를 수 있다. 이 상태는 화면에 안내로 띄운다. 시트만 닫히면 사용자는 아무 일도
  /// 안 일어난 것으로 본다.
  DirectionsMapPickTarget? _mapPickTarget;

  /// 도착지를 먼저 고른 길찾기 초안. 이전에는 `도착`을 누르는 즉시 경로
  /// 계산을 시도해서, 출발 위치가 준비되지 않은 경우 이 후보가 화면과 함께
  /// 사라졌다. 이 값은 검색 취소·시트 닫힘과 분리된 MapShell 상태로 두고,
  /// 명시적 초기화 또는 다른 도착지 선택 때만 바꾼다.
  DirectionsCandidate? _routeDraftDestination;

  final _outdoorKey = GlobalKey<OutdoorMapBodyState>();

  /// 층 전환 배너·스크림 상태. 판정과 상태 전이는 [IndoorMapBody]가 소유하고
  /// 여기서는 그리기만 한다.
  ///
  /// 셸이 그려야 하는 이유: 검색창·카테고리 줄·하단 바가 이 Stack의 형제라,
  /// 지도 안에서 그린 배너는 그 뒤에 깔린다.
  FloorTransitionUiState? _floorTransition;
  double _floorScrimOpacity = 0;

  // 지도 위에 얹은 공용 오버레이(검색창·카테고리 줄·하단 바)의 영역을
  // IndoorMapBody가 map click 처리에서 제외할 수 있게 넘겨줄 key들.
  // MapLibre PlatformView가 gesture arena를 우회해서 오버레이 탭이 뒤의 매장
  // 까지 새어들어가는 문제를 여기서 함께 막는다.
  final _topBarKey = GlobalKey();
  final _categoryRowKey = GlobalKey();
  final _bottomBarKey = GlobalKey();
  final _searchPanelKey = GlobalKey();

  /// "지도에서 도착지를 골라주세요" 안내. 이 카드의 X를 누른 탭이 지도까지
  /// 새어들어가면, 취소를 누른 손가락이 그 아래 매장을 도착지로 지정해 버린다.
  final _mapPickHintKey = GlobalKey();

  // 상단 검색창은 이제 여기(상위)가 소유한다. 결과 패널이 검색창 바로 아래에
  // 붙어야 하므로, 입력 상태를 검색창과 패널이 함께 볼 수 있는 이 자리에 둔다.
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  /// 검색이 활성인지 — 포커스가 들어왔거나 글자가 남아 있는 상태. true인
  /// 동안에만 결과 패널이 뜨고 지도 제스처가 잠긴다.
  bool _searchActive = false;
  String _searchQuery = '';

  /// 엔터로 확정할 때마다 1씩 오른다. 같은 글자로 다시 엔터를 눌러도 의미
  /// 검색이 다시 돌아야 하므로 bool이 아니라 카운터다.
  int _searchSubmitTick = 0;

  /// 현재 위치에서 각 그래프 노드까지의 거리·비용. 검색 결과가 매장마다
  /// "몇 m · 도보 몇 분"을 붙이는 데 쓴다. 위치가 없거나 건물 안이 아니면 null.
  ///
  /// **검색어마다 다시 계산하지 않는다.** 이 값은 검색어와 무관하게 "지금 내
  /// 위치"에만 딸려 있어서, 글자를 칠 때마다 갱신하면 건물 그래프 요청과
  /// 다익스트라를 타이핑 속도로 태우게 된다. 검색을 시작할 때와 위치를 새로
  /// 잡았을 때만 갱신한다.
  Map<String, NodeReach>? _reachByNodeId;

  /// 지금 길찾기 중인지. 참이면 상단 바가 검색창 하나 대신 **출발/도착 두 칸**이
  /// 되고 그 위에 이동 수단 줄이 붙는다.
  ///
  /// **전용 화면을 띄우지 않는다.** 한동안은 아래에서 올라오는 시트였다. 지도를
  /// 잃지는 않았지만 "방금 누른 칸"과 "실제로 치는 칸"이 달라, 목적지를 고치려면
  /// 시트를 다시 열어야 했다. 지금은 두 칸이 상단 바 그 자리에 있고 후보 목록만
  /// 아래로 펼쳐진다.
  bool _routeMode = false;

  /// 길찾기 두 칸 중 지금 글자를 치고 있는 칸. null이면 결과(지도)를 보는 중이다.
  RoutePlanField? _routeEditingField;

  final _routeOriginController = TextEditingController();
  final _routeDestinationController = TextEditingController();
  final _routeOriginFocus = FocusNode();
  final _routeDestinationFocus = FocusNode();

  /// 지금 치고 있는 칸에 보여 줄 후보들. **세 출처를 각자의 칸에 담는다** — 셋이
  /// 서로 다른 속도로 도착하는데 한 리스트에 이어 붙이면 늦게 온 쪽이 먼저 온
  /// 쪽을 덮거나 순서를 흔든다.
  List<DirectionsCandidate> get _routeResults => [
    ..._routeSemanticRows,
    ..._routeIndoorRows,
    ..._routeOutdoorRows,
  ];

  /// 실내 매장·건물. 이 줄이 도착하는 순간이 곧 "찾는 중"의 끝이다.
  List<DirectionsCandidate> _routeIndoorRows = const [];

  /// 실내가 빈손일 때만 채워지는 의미 검색 결과. 맨 위에 붙는다.
  List<DirectionsCandidate> _routeSemanticRows = const [];

  /// 건물 밖 장소(TMAP). **스피너를 붙들지 않는다** — 실내보다 훨씬 느려서,
  /// 기다렸다 함께 붙이면 야외 건물 검색이 통째로 그 대기 시간이 된다.
  List<DirectionsCandidate> _routeOutdoorRows = const [];

  bool _routeSearching = false;

  /// 후보 조회 순번. 빠르게 타이핑하면 요청이 겹치는데, 늦게 도착한 옛 응답이
  /// 새 결과를 덮으면 목록이 방금 친 글자와 무관한 것을 보여 준다.
  int _routeSearchSeq = 0;

  /// 후보 조회 디바운스. 글자마다 서버를 때리지 않게 잠깐 모았다 보낸다 —
  /// 상단 검색창과 **같은 리듬**이어야 같은 검색어가 어디에 치느냐에 따라
  /// 요청 수가 달라지지 않는다(`SearchPanel._lightDebounce`).
  static const _routeSearchDebounceDelay = Duration(milliseconds: 300);
  Timer? _routeSearchDebounce;

  /// 지금 고른 이동 수단.
  RoutePlanMode _travelMode = RoutePlanMode.walk;

  /// 온디바이스 자동완성의 원본. null은 "아직 못 받았거나 받기에 실패했다"는
  /// 뜻이고, **그 상태가 정상 경로에 포함된다** — 자동완성만 빠지고 서버 검색은
  /// 그대로 돈다.
  List<StoreIndexEntry>? _routeStoreIndex;

  /// 지금 질의에 대한 온디바이스 후보. 질의가 바뀔 때만 다시 계산한다 —
  /// build에서 매번 계산하면 한 프레임에 여러 번 전체 목록을 훑는다.
  List<StoreSuggestion> _routeSuggestions = const [];

  /// 다음 후보 조회 한 번만 이 층으로 좁힌다. 후보를 **탭한 경우**에 선다.
  /// null이면 평소대로 건물 전체를 본다.
  String? _routeFloorScopeOnce;

  /// 지금 치고 있는 칸에 들어 있는 글자.
  String get _routeQuery => _routeEditingField == RoutePlanField.origin
      ? _routeOriginController.text
      : _routeDestinationController.text;

  /// 대중교통 조회가 겹쳐 나가는 것을 막는다.
  ///
  /// 실기기 로그에서 **같은 조회가 2~3번 연달아 나갔다** — 응답 세 줄이 사이에
  /// 아무 로그도 없이 붙어 있었으니 동시에 날아간 것이다. 어느 조작이 그러는지는
  /// 아직 못 짚었지만, 조회가 나가 있는 동안 같은 조회를 또 보내는 것이 맞는
  /// 상황은 없다.
  final _transitRequest = SingleFlight();

  final _travelModeBarKey = GlobalKey();
  final _routeResultsKey = GlobalKey();

  /// 건물 밖 장소를 함께 찾을 기준점. 검색을 시작할 때 야외 지도에서 한 번
  /// 받아 둔다([_activateSearch]).
  ///
  /// **매 build마다 지도에서 읽지 않는다.** 지도 상태를 GlobalKey로 읽는 건
  /// build 중에 하기 나쁜 일이고(레이아웃 전에는 카메라가 없다), 검색 한 번
  /// 도중에 기준점이 흔들리면 같은 검색어의 결과가 타이핑 중에 바뀐다.
  LatLng? _outdoorSearchCenter;

  /// 검색 결과 거리 표시용 도달 정보를 다시 계산한다.
  ///
  /// 건물 밖(순수 야외)에서는 실내 그래프 거리가 의미가 없으므로 비운다 —
  /// 남겨 두면 야외로 나온 뒤에도 예전 실내 위치 기준 거리가 목록에 남는다.
  Future<void> _refreshReach() async {
    if (!_indoorContextActive) {
      if (_reachByNodeId != null && mounted) {
        setState(() => _reachByNodeId = null);
      }
      return;
    }
    final reach = await _outdoorKey.currentState?.reachFromCurrentPosition();
    if (!mounted) return;
    setState(() => _reachByNodeId = reach);
  }

  /// 시트 X 버튼이 눌리면 true가 된다. 시트 체인의 어떤 시점에서든 이 값이
  /// true면 부모 loop(_openFavorites, _openCategoryStores, _showStoreInfo)는
  /// 이전 시트를 다시 열지 않고 즉시 종료해서 전체 chain이 한 번에 닫힌다.
  /// 최상위 호출자가 값을 consume한 뒤 반드시 false로 되돌린다.
  bool _closeSheetChainRequested = false;

  void _requestCloseSheetChain() {
    _closeSheetChainRequested = true;
  }

  /// 시트 chain을 여는 최상위 진입 지점(장소 pill 탭, 매장 폴리곤 탭,
  /// 검색으로 매장 매치 등)에서 감싸 쓴다. 시작 시 플래그를 초기화하고
  /// 끝나면 다시 리셋한다 — nested loop들이 값을 읽는 동안에는 리셋하지
  /// 않으므로, X 신호가 chain 전체까지 온전히 전파된다.
  Future<T> _runSheetChain<T>(Future<T> Function() body) async {
    _closeSheetChainRequested = false;
    try {
      return await body();
    } finally {
      _closeSheetChainRequested = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_onSearchFocusChanged);
    _routeOriginFocus.addListener(_onRouteOriginFocusChanged);
    _routeDestinationFocus.addListener(_onRouteDestinationFocusChanged);
    _requestStartupPermissions();
    // 화면이 세워지기 전에 도착한 링크가 여기 남아 있을 수 있다(cold start).
    placeLinkInbox.addListener(_onPlaceLinkChanged);
    _onPlaceLinkChanged();
  }

  @override
  void dispose() {
    placeLinkInbox.removeListener(_onPlaceLinkChanged);
    _searchFocus.removeListener(_onSearchFocusChanged);
    _searchFocus.dispose();
    _searchController.dispose();
    _routeOriginFocus.removeListener(_onRouteOriginFocusChanged);
    _routeDestinationFocus.removeListener(_onRouteDestinationFocusChanged);
    _routeOriginFocus.dispose();
    _routeDestinationFocus.dispose();
    _routeOriginController.dispose();
    _routeDestinationController.dispose();
    _routeSearchDebounce?.cancel();
    super.dispose();
  }

  /// 예전에는 스플래시 화면이 이 요청을 진행 중 화면과 함께 보여줬지만,
  /// 이제 앱이 바로 지도 화면으로 시작하므로 화면을 막지 않고 백그라운드로
  /// 요청만 하고, 거부된 게 있으면 지도 위에 짧게 안내만 띄운다.
  ///
  /// 권한 요청은 한 번에 하나씩 순서대로 뜬다([requestStartupPermissions]).
  Future<void> _requestStartupPermissions() async {
    try {
      final statuses = await requestStartupPermissions();
      final anyDenied = statuses.values.any((status) => !status.isGranted);
      if (!mounted || !anyDenied) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('일부 권한이 거부되어 위치·실내 이동 관련 기능이 제한될 수 있습니다')),
      );
    } catch (_) {
      // 권한 플러그인을 쓸 수 없는 환경(테스트 등)에서도 앱을 계속 진행한다.
    }
  }

  /// 야외로 나왔을 때 실내 지점으로 잡아둔 출발지를 버린다. 안 버리면 칸에는
  /// 건물 안 매장이 적혀 있는데 경로는 GPS에서 시작한다.
  ///
  /// **칸의 글자까지 지운다.** 상태만 비웠더니 화면은 "스타벅스 → 런던베이글"인데
  /// 계산은 "GPS → 런던베이글"이라 같은 건물 두 매장이 20 km·270분으로 나왔다.
  /// 두 칸은 라벨이 아니라 입력창이라, 상태를 바꾸는 쪽이 글자도 책임진다.
  void _dropIndoorOriginIfOutdoors() {
    if (_indoorContextActive) return;
    final origin = _selectedOrigin;
    if (origin == null) return;
    if (origin.floor == null && origin.nodeId == null) return;
    setState(() {
      _selectedOrigin = null;
      _routeOriginController.clear();
    });
  }

  /// 지금 화면이 "건물 안"을 보고 있는지. 실내 탭이거나, 야외 탭이어도 실내
  /// 진입 오버레이가 켜져 있으면 사용자에게는 똑같이 건물 내부를 보고 있는
  /// 상태다. 길찾기·카테고리 시트는 이 값으로 분기해야 한다 — 진입 여부만
  /// 보고 분기하면, 야외 지도 위에서 실내 도면을 훑는 동안 길찾기 후보가
  /// 매장이 아닌 건물 이름만 뒤져 "아무것도 안 나오는" 상태가 된다.
  bool get _indoorContextActive => _outdoorIndoorEntered;

  /// 지금 "현재 위치에서 출발"로 경로를 그릴 수 있는지.
  ///
  /// [_selectedOrigin]이 null인 것은 **두 가지가 겹친 값**이다 — "현재 위치에서
  /// 출발"과 "출발지가 아직 없음". 뭉개면 위치를 찍어 둔 사용자가 도착을 눌러도
  /// 아무 일도 안 일어난다.
  ///
  /// 실내 기준은 PDR 앵커(없으면 라우팅이 시작 노드를 못 고른다), 야외는 GPS다.
  bool get _canRouteFromCurrentLocation => _indoorContextActive
      ? indoorNavigationDriver.currentCalibration.canRenderPosition
      : true;

  /// 지금 보고 있는 층. 실내 탭이면 실내 화면의 층, 야외 탭에서 실내 진입
  /// 오버레이를 보고 있으면 그 오버레이의 층. 어느 쪽도 아니면 null이라
  /// 호출부가 "층 개념 없음"으로 처리한다.
  String? get _activeIndoorFloor {
    if (_outdoorIndoorEntered) return _outdoorKey.currentState?.currentFloor;
    return null;
  }

  /// 지금 지도 제스처를 잠그고 있는 이유들. 잠금 요청이 겹칠 수 있어서 bool이
  /// 아니라 집합이다 — 예전처럼 각자 `setInteractive(true)`로 풀면, 카테고리 열
  /// 위에 마우스를 올린 채 시트를 닫는 순간 아직 필요한 잠금까지 함께 풀린다.
  final _mapLockReasons = <String>{};

  /// 바텀시트·검색 패널이 지도 위에 떠 있는 동안.
  static const _mapLockSheet = 'sheet';
  static const _mapLockSearch = 'search';

  /// 지도 위 오버레이(장소 pill·카테고리 chip 열) 위에 포인터가 올라와 있는 동안.
  /// 마우스(hover)와 터치(pointer down)는 끝나는 시점이 달라 따로 센다.
  static const _mapLockOverlayHover = 'overlay-hover';
  static const _mapLockOverlayTouch = 'overlay-touch';

  void _lockMaps(String reason) {
    if (!_mapLockReasons.add(reason)) return;
    if (_mapLockReasons.length == 1) _applyMapInteractive();
  }

  void _unlockMaps(String reason) {
    if (!_mapLockReasons.remove(reason)) return;
    if (_mapLockReasons.isEmpty) _applyMapInteractive();
  }

  void _applyMapInteractive() {
    final interactive = _mapLockReasons.isEmpty;
    _outdoorKey.currentState?.setInteractive(interactive);
  }

  /// 시트가 떠 있는 동안 지도 제스처를 꺼, 휠 스크롤이 아래 지도로 새지 않게 한다.
  ///
  /// **웹에서만 잠근다.** 웹 전용 증상이라(`widgets/map_overlay_guard.dart`) 플랫폼을
  /// 가리지 않고 걸었더니 실기기에서 **시트가 떠 있는 동안 지도가 통째로 얼었다** —
  /// 상세 시트가 barrier까지 없애 포인터를 흘리는 작업이 통째로 무효가 됐다.
  Future<T?> _withMapsLocked<T>(Future<T?> Function() showSheet) async {
    if (!kIsWeb) return showSheet();
    _lockMaps(_mapLockSheet);
    try {
      return await showSheet();
    } finally {
      _unlockMaps(_mapLockSheet);
    }
  }

  /// 검색창에 포커스가 들어오면 그 자리에서 검색을 시작한다. 예전에는 탭이
  /// 아래에서 시트를 올렸고, 그 시트 안에 입력창이 하나 더 있었다 — 사용자가
  /// 방금 누른 창과 실제로 치는 창이 달라 검색창이 두 개인 것처럼 보였다.
  void _onSearchFocusChanged() {
    if (_searchFocus.hasFocus) _activateSearch();
  }

  void _activateSearch() {
    if (_searchActive) return;
    // 검색을 시작했다는 것은 지도에서 고르는 걸 그만뒀다는 뜻이다. 안내만 남으면
    // 검색 결과를 고른 뒤에도 다음 매장 탭이 출발지/도착지로 먹혀 버린다.
    _stopPickingOnMap();
    setState(() {
      _searchActive = true;
      // **실내 도면을 보는 중에도 바깥을 함께 찾는다.** 실내일 때 껐더니 기능이
      // 통째로 죽었다 — 폰에서는 진입 임계 zoom이 16.8까지 내려가고 초기 zoom이
      // 17이라 건물 근처에서는 첫 프레임부터 오버레이가 켜져 있다.
      //
      // 원래 걱정은 **순서**가 이미 해결한다. 바깥 결과는 항상 실내 아래에 별도
      // 헤더로 붙으므로, 바깥이 첫 줄이 되는 건 실내가 빈손일 때뿐이다.
      _outdoorSearchCenter = _outdoorKey.currentState?.outdoorSearchCenter;
    });
    // 결과에 붙일 거리는 여기서 한 번만 준비한다. 결과가 나오기 전에 시작하므로
    // 그래프 요청이 늦어도 목록은 먼저 뜨고, 거리 줄만 뒤늦게 채워진다.
    unawaited(_refreshReach());
    // 결과 패널이 지도 위에 떠 있는 동안 지도 제스처를 잠근다. 실내는 웹에서
    // 실제 DOM 캔버스(MapLibre)라 패널 위 휠 이벤트가 지도로 새어나간다.
    _lockMaps(_mapLockSearch);
  }

  /// 검색을 끝낸다. 결과를 골라 시트로 넘어갈 때도, 사용자가 뒤로/바깥을
  /// 눌러 그냥 닫을 때도 같은 경로를 탄다 — 어느 쪽이든 패널이 시트 뒤에
  /// 남아 겹치면 안 된다.
  void _closeSearch() {
    _searchFocus.unfocus();
    _searchController.clear();
    // 잠금 해제는 조기 반환보다 먼저 한다. 잡고 있지 않은 이유를 푸는 것은
    // no-op이므로, 상태가 어긋나도 잠금이 남아 지도가 굳는 일이 없다.
    _unlockMaps(_mapLockSearch);
    if (!_searchActive && _searchQuery.isEmpty) return;
    setState(() {
      _searchActive = false;
      _searchQuery = '';
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 상단 길찾기 바의 X. **지도에 그려진 경로까지 함께 지운다.**
  ///
  /// 예전에는 출발/도착 값만 비웠다. 그래서 X를 눌러도 지도에는 경로선과 도착
  /// 핀이 그대로 남았고, 그걸 지우려면 하단 안내 카드의 "안내 종료"를 한 번 더
  /// 눌러야 했다 — 사용자에게는 초기화 버튼이 먹지 않은 것으로 보인다. 길찾기
  /// 바가 사라지는 것과 경로가 사라지는 것은 같은 사건이므로 한 번에 처리한다.
  void _clearRouteDraft() {
    _closeSearch();
    _outdoorKey.currentState?.clearAllRoutes();
    _forgetRouteDraft();
  }

  /// 지도에 그려진 것은 두고 **상단 길찾기 상태만** 비운다. 지도가 이미 자기 경로를
  /// 지운 뒤 알려오는 경로라, 되돌려 보내면 같은 일을 두 번 한다.
  ///
  /// 이동 수단도 잊는다 — 안 지우면 다음 길찾기가 지난번 자동차로 시작한다.
  void _forgetRouteDraft() {
    _unfocusRouteFields();
    _routeOriginController.clear();
    _routeDestinationController.clear();
    // 걸려 있던 조회를 끊고 스피너도 함께 내린다. 순번만 올리면 조기 반환한
    // 조회가 [_routeSearching]을 안 내려 빈 카드에 스피너만 남는다.
    _stopRouteSearch();
    setState(() {
      _routeMode = false;
      _routeEditingField = null;
      _clearRouteResults();
      _routeSuggestions = const [];
      _selectedOrigin = null;
      _routeDraftDestination = null;
      _travelMode = RoutePlanMode.walk;
    });
  }

  void _onSearchChanged(String value) {
    _activateSearch();
    if (_searchQuery == value) return;
    setState(() => _searchQuery = value);
  }

  /// 엔터로 확정. 패널이 이 시점에만 의미 검색(`/query/ai`)까지 이어 붙인다.
  void _onSearchSubmitted(String value) {
    _activateSearch();
    // 엔터는 "이 말로 찾겠다"는 분명한 신호라 여기서 최근 검색어에 남긴다.
    // 결과가 있었는지는 보지 않는다 — 못 찾은 말도 다시 시도하거나 고쳐 치는
    // 대상이라, 목록에 남는 편이 사용자에게 쓸모 있다.
    recentSearchesController.add(value);
    setState(() {
      _searchQuery = value;
      _searchSubmitTick++;
    });
  }

  /// 검색 패널의 최근 검색어를 골랐을 때. 패널은 입력창을 갖고 있지 않으므로
  /// 검색창 글자까지 여기서 맞춰 줘야 화면과 질의가 갈라지지 않는다.
  void _onSearchQueryPicked(String query) {
    _searchController.text = query;
    _onSearchSubmitted(query);
  }

  Future<void> _onSearchStorePicked(PoiSearchResult store) async {
    // 엔터 없이 디바운스 검색 결과를 바로 고르는 흐름이 더 흔하다. 그 경우도
    // "이 검색은 쓸모가 있었다"는 신호라 함께 남긴다. 같은 말이면 컨트롤러가
    // 중복 없이 맨 앞으로 올린다.
    recentSearchesController.add(_searchQuery);
    _closeSearch();
    await _runSheetChain(() => _showStoreInfo(store, focusOnMap: true));
  }

  /// 자동완성 후보를 골랐을 때. 좌표를 붙여 **검색 결과와 같은 자리로 합류시킨다.**
  ///
  /// 좌표는 층 도면에서 찾으므로 추가 요청이 없다. 못 찾으면 그 이름으로 검색을 다시
  /// 돌린다 — 아무 일도 안 일어나는 것보다 한 번 더 누르더라도 도달하는 편이 낫다.
  Future<void> _onSearchSuggestionPicked(StoreIndexEntry entry) async {
    recentSearchesController.add(_searchQuery);
    final resolved = await _outdoorKey.currentState?.resolveIndexEntry(entry);
    if (!mounted) return;
    if (resolved == null) {
      _onSearchQueryPicked(entry.name);
      return;
    }
    _closeSearch();
    await _runSheetChain(() => _showStoreInfo(resolved, focusOnMap: true));
  }

  /// 상세 시트가 부르는 "근처 매장" 계산.
  ///
  /// **여기서 하는 이유**는 그래프와 매장 색인을 이 화면이 이미 들고 있어서다. 시트가
  /// 직접 받아 오면 데이터가 두 벌이 되고, 시트 테스트에 그래프부터 필요해진다.
  Future<List<NearbyStore>> _loadNearbyStores(String entranceNodeId) async {
    final graph = await buildingRepository.getBuildingGraph(_buildingId);
    final index = await buildingRepository.getStoreIndex(_buildingId);
    if (graph == null || index == null || graph.nodes.isEmpty) return const [];

    final Map<String, NodeReach> reach;
    try {
      reach = reachableFrom(
        nodes: graph.nodes,
        edges: graph.edges,
        startNodeId: entranceNodeId,
      );
    } on ArgumentError {
      // 이 매장의 입구 노드가 그래프에 없다. 시드와 그래프가 어긋난 경우라
      // 목록만 빠지고 상세는 그대로 뜬다.
      return const [];
    }

    return nearbyStores(
      stores: index,
      reachByNodeId: reach,
      excludePlaceId: _nearbyOriginPlaceId ?? '',
    );
  }

  /// 근처 매장 목록에서 자기 자신을 빼려면 지금 열려 있는 매장 id가 필요하다.
  /// 시트가 인자로 넘기지 않는 이유는, 이 화면이 어차피 시트를 띄우면서 그 id를
  /// 이미 알고 있기 때문이다.
  String? _nearbyOriginPlaceId;

  /// 근처 매장 줄을 눌렀다. **검색 후보를 고른 것과 같은 경로**를 탄다 —
  /// 같은 결과에 이르는 길이 둘로 갈리면 한쪽만 고쳐지는 날이 온다.
  Future<void> _onNearbyStorePicked(StoreIndexEntry entry) async {
    // 지금 시트를 먼저 닫는다. 닫지 않고 새 시트를 올리면 상세가 상세 위에 쌓여
    // 뒤로 가기가 몇 번인지 사용자가 알 수 없게 된다.
    Navigator.of(context).pop();

    // `_onSearchSuggestionPicked`를 그대로 부르지 않는 이유는 그쪽이 **최근 검색어를
    // 남기기** 때문이다. 근처 매장을 누른 것은 검색이 아니라서, 부르면 방금 친 적도
    // 없는 말이 최근 목록에 쌓인다. 좌표를 찾고 시트를 여는 부분은 같은 함수를 쓴다.
    final resolved = await _outdoorKey.currentState?.resolveIndexEntry(entry);
    if (!mounted || resolved == null) return;
    await _runSheetChain(() => _showStoreInfo(resolved, focusOnMap: true));
  }

  void _onSearchBuildingPicked(Building building) {
    _closeSearch();
    // 카드만 띄우고 지도를 그대로 두면 사용자는 자기가 고른 건물이 화면 어디에
    // 있는지 알 수 없다 — 이름만 적힌 카드가 뜰 뿐 지도는 방금 보던 자리 그대로다.
    // 매장을 골랐을 때 [_showStoreInfo]가 카메라를 옮기는 것과 같은 규칙이다.
    unawaited(
      _outdoorKey.currentState?.focusBuilding(building) ?? Future.value(),
    );
  }

  /// 매장 정보 시트를 띄운다. 검색 결과 탭과 지도 폴리곤 탭이 모두 여기를 거친다.
  ///
  /// 반환값은 사용자가 출발/도착 액션을 골랐는지다 — "그냥 닫힘"이면 호출자가 저장된
  /// 장소 시트로 되돌린다.
  ///
  /// [keepZoom]이면 **배율은 그대로 둔다.** 지도에서 직접 누른 매장은 이미 화면에
  /// 있으므로, 확대까지 하면 방금 보던 층 배치를 잃는다.
  /// 이미 상세 시트가 떠 있으면 **그 시트의 내용만** 갈아 끼운다. 갈아 끼웠으면 true.
  ///
  /// 떼었다 붙이면 빈 프레임이 생겨 번쩍이고, 그냥 얹으면 같은 시트가 두 겹으로
  /// 쌓인다 — 검색으로 같은 매장을 두 번 열면 뒤로가기 한 번에 화면이 안 바뀌는
  /// 것으로 드러났다. 자세한 것은
  /// `docs/client/kakao-map-indoor-observation.md` S절.
  bool _swapOpenPlaceDetail(PoiSearchResult match) {
    if (_placeDetailClosing == null) return false;
    _activePlaceMatch = match;
    _nearbyOriginPlaceId = match.placeId;
    _placeDetailTarget.value = _targetFor(
      match,
      FavoritePlace.fromPoiSearchResult(match, buildingId: _buildingId),
    );
    unawaited(
      (_outdoorKey.currentState?.focusStore(
                match,
                bottomSheetFraction: placeDetailSheetInitialSize(
                  MediaQuery.sizeOf(context).height,
                ),
                enterBuildingIfNeeded: true,
              ) ??
              Future.value())
          .catchError((Object error, StackTrace _) {
            debugPrint('[place focus] $error');
          }),
    );
    return true;
  }

  Future<bool> _showStoreInfo(
    PoiSearchResult match, {
    bool focusOnMap = false,
    bool keepZoom = false,
    bool crossFade = false,
  }) async {
    // **여기가 상세 시트의 유일한 입구다.** 검색·근처 매장·저장한 장소·지도 탭이
    // 모두 이 함수를 지나므로, 중복 방지를 각 호출부에 흩지 않고 여기 한 곳에
    // 둔다. 갈아 끼웠다면 이 호출은 시트를 열지 않았으므로 false로 끝낸다 —
    // 사용자가 고른 동작은 원래 떠 있던 시트의 await가 받는다.
    if (_swapOpenPlaceDetail(match)) return false;
    // 카메라와 시트를 같은 박자에 시작한다. 카메라 완료를 기다린 뒤 시트를
    // 올리면 `지도 이동 → 시트 등장`이 두 동작으로 끊겨 보이고, 반대로 시트를
    // 먼저 다 올리면 목적지가 잠깐 시트 뒤에 남는다. focusStore는 최종 위치를
    // 한 번의 애니메이션으로 계산하므로 둘을 병렬로 시작해도 중간 점프가 없다.
    Future<void>? focusing;
    if (focusOnMap) {
      // 곧 올라올 시트 높이를 함께 넘겨, 매장이 시트 뒤가 아니라 그 위 영역
      // 한가운데에 놓이게 한다. 시트 높이를 바꾸면 카메라도 자동으로 따라온다.
      focusing = _outdoorKey.currentState?.focusStore(
        match,
        bottomSheetFraction: placeDetailSheetInitialSize(
          MediaQuery.sizeOf(context).height,
        ),
        keepZoom: keepZoom,
        // 검색·목록에서 고른 매장은 건물 밖에서 골랐어도 보여 준다. 지도에서
        // 직접 누른 매장은 이미 건물 안이라 이 값과 무관하다.
        enterBuildingIfNeeded: true,
      );
    }
    final favorite = FavoritePlace.fromPoiSearchResult(
      match,
      buildingId: _buildingId,
    );
    if (!mounted) return false;
    // 근처 매장 목록에서 자기 자신을 빼는 데 쓴다.
    _nearbyOriginPlaceId = match.placeId;
    _activePlaceMatch = match;
    _placeDetailTarget.value = _targetFor(match, favorite);
    final showing = _withMapsLocked(
      () => PlaceDetailSheet.show(
        context,
        crossFade: crossFade,
        target: _placeDetailTarget,
        buildingId: _buildingId,
        // "이 매장에서" 잰 근처 매장. target의 reach와 기준이 다르다 — 사용자
        // 기준 거리는 이미 헤더에 있고, 같은 기준으로 두 번 적으면 두 번째 줄이
        // 알려 주는 게 없다.
        nearbyStoresLoader: _loadNearbyStores,
        onSelectNearbyStore: _onNearbyStorePicked,
        onCloseAll: _requestCloseSheetChain,
      ),
    );
    // 지도 플러그인 오류는 상세 열기를 막을 이유가 없다. 사용자는 정보·길찾기
    // 버튼을 계속 쓸 수 있고, 다음 지도 조작이 카메라를 다시 맞춘다.
    if (focusing != null) {
      unawaited(
        focusing.catchError((Object error, StackTrace stackTrace) {
          debugPrint('[place focus] $error');
        }),
      );
    }
    // 떠 있는 동안만 값이 있다. 지도에서 다른 매장을 눌렀을 때 이 시트를 먼저
    // 닫고 기다리는 데 쓴다([_openStoreFromMap]).
    _placeDetailClosing = showing;
    final action = await showing;
    if (identical(_placeDetailClosing, showing)) _placeDetailClosing = null;
    if (!mounted) return false;
    // 시트가 어떻게 닫혔든(선택 없이 닫힘 포함) 지도 위 강조 표시도 같이 지운다.
    _outdoorKey.currentState?.clearHighlight();
    // 닫기는 선택 강조만 해제한다. 시트를 열어 둔 채 사용자가 지도를 움직일 수
    // 있으므로, 여기서 층 전체 fit을 호출하면 사용자가 맞춘 중심·줌·회전까지
    // 전부 잃는다. 카메라는 다음 명시적 조작(층 선택, 내 위치, 다른 매장)이
    // 바꿀 때까지 그대로 둔다.
    // X로 chain 전체를 닫으라는 신호가 왔다면, 여기서 곧장 종료해 부모 loop가
    // 다음 시트를 다시 열지 못하게 한다.
    if (_closeSheetChainRequested) return true;
    if (action == null) return false;

    // **처음 누른 매장이 아니라 지금 시트가 보여 주던 매장**이다. 갈아 끼우기가
    // 라우트를 그대로 두므로, 여기 `match`는 첫 매장에 묶여 있다.
    final active = _activePlaceMatch ?? match;
    final candidate = DirectionsCandidate(
      title: active.name,
      subtitle: active.floor,
      point: active.point,
      nodeId: active.nodeId,
      floor: active.floor,
    );
    if (action == StoreInfoAction.setOrigin) {
      // 출발지를 지정하면 다음 "도착" 탭이 시트를 다시 열지 않고 바로 이
      // 매장을 출발지로 쓸 수 있도록 상위 상태에도 기억해둔다. 이미 도착
      // 초안이 있으면 이 선택으로만 경로 조건이 완성되므로 즉시 계산한다.
      setState(() => _selectedOrigin = candidate);
      final destination = _routeDraftDestination;
      if (destination != null) {
        await _startRoute(origin: candidate, destination: destination);
      } else {
        // 아직 도착지가 없어 경로를 그리지 않는다. 그래서 카메라를 잡아 줄
        // 경로 개요도 없다 — 여기서 직접 그 매장(과 그 층)을 보여 준다.
        _focusIndoorOrigin(candidate);
        await _openRouteMode(presetOrigin: candidate);
      }
    } else if (action == StoreInfoAction.setDestination) {
      // 출발지가 준비돼 있으면 바로 그린다. 명시적으로 고른 매장이든 위치가 잡힌
      // 현재 위치든([_canRouteFromCurrentLocation]) 둘 다 완전하다 — 후자를 빼면
      // 위치를 찍어둔 사용자가 "도착"을 눌러도 아무 일도 안 일어난다.
      setState(() => _routeDraftDestination = candidate);
      final origin = _selectedOrigin;
      if (origin != null || _canRouteFromCurrentLocation) {
        await _startRoute(origin: origin, destination: candidate);
      } else {
        // 출발지가 없다. **여기서 멈추면 아무 일도 안 일어난 화면이 된다** — 길찾기
        // 바는 [_routeMode]가 참일 때만 그려지는데 이 갈래가 그걸 안 세웠다.
        // 도착지를 채운 채로 바를 열고 커서를 출발 칸에 둔다.
        await _openRouteMode(
          presetDestination: candidate,
          focusField: RoutePlanField.origin,
        );
      }
    }
    return true;
  }

  /// 검색 결과에서 **건물 밖 장소**를 골랐을 때. 매장을 고른 경로와 같은 모양이다
  /// — 검색을 닫고 시트 chain 안에서 그 장소의 시트를 연다.
  Future<void> _onSearchPoiPicked(OutdoorPoi poi) async {
    _closeSearch();
    await _runSheetChain(() => _showOutdoorPoiInfo(poi));
  }

  /// 야외 장소 시트. 매장 시트와 같은 규칙으로 "출발/도착을 실제로 골랐는가"를
  /// 돌려준다 — 부모 loop가 그 값으로 이전 시트로 되돌릴지 정한다.
  Future<bool> _showOutdoorPoiInfo(OutdoorPoi poi) async {
    // 목록에서 고른 장소는 지금 화면 어디에 있는지 알 수 없다. 시트가 덮기
    // 전에 지도를 그쪽으로 옮겨, 시트를 닫으면 바로 그 자리가 보이게 한다.
    await _outdoorKey.currentState?.focusPoint(poi.point);
    if (!mounted) return false;

    final action = await _withMapsLocked(
      () => OutdoorPoiSheet.show(
        context,
        poi: poi,
        onCloseAll: _requestCloseSheetChain,
      ),
    );
    if (!mounted) return false;
    if (_closeSheetChainRequested) return true;
    if (action == null) return false;

    // 야외 좌표뿐인 후보다. 노드·층이 없으므로 [_startRoute]는 이 값을 실내
    // 라우팅으로 보내지 않고 도보 경로로 흘려보낸다. 좌표가 우리 건물 안일
    // 때의 보정도 [_startRoute]가 한다 — 진입점마다 하면 또 갈린다.
    final candidate = DirectionsCandidate(
      title: poi.name,
      subtitle: poi.address ?? '건물 밖 장소',
      point: poi.point,
    );
    switch (action) {
      case OutdoorPoiAction.setOrigin:
        setState(() => _selectedOrigin = candidate);
        final destination = _routeDraftDestination;
        if (destination != null) {
          await _startRoute(origin: candidate, destination: destination);
        } else {
          await _openRouteMode(presetOrigin: candidate);
        }
      case OutdoorPoiAction.setDestination:
        setState(() => _routeDraftDestination = candidate);
        final origin = _selectedOrigin;
        if (origin != null || _canRouteFromCurrentLocation) {
          await _startRoute(origin: origin, destination: candidate);
        } else {
          // 매장 시트와 **같은 규칙**이다. 실내에서 위치 지정 전에 바깥 목적지를
          // 고르는 흐름이 실제로 있고, 멈추면 도착을 누른 적 없는 화면이 된다.
          // 바로 위 setOrigin 갈래는 이미 같은 else를 갖고 있었다.
          await _openRouteMode(
            presetDestination: candidate,
            focusField: RoutePlanField.origin,
          );
        }
    }
    return true;
  }

  /// 카테고리 매장 목록 시트. 항목을 탭하면 목록이 닫히고 상세가 뜬다.
  ///
  /// **상세를 닫아도 목록으로 돌아가지 않는다.** loop였을 때는 시트가 겹겹이 쌓인
  /// 것으로 읽혔다. 목록을 다시 보려면 chip을 다시 누른다.
  Future<bool> _openCategoryStores(String category) async {
    final currentFloor = _activeIndoorFloor;
    final showing = _withMapsLocked(
      () => CategoryStoresSheet.show(
        context,
        buildingId: _buildingId,
        category: category,
        onCloseAll: _requestCloseSheetChain,
        currentFloor: currentFloor,
        // 지도 강조와 시트 목록이 같은 소분류를 가리키게 한다. 다른 대분류가
        // 걸려 있었다면(매장 정보 시트에서 카테고리를 타고 들어온 경우) 그
        // 소분류는 이 대분류에 없는 값이므로 넘기지 않는다.
        subcategory: _categorySelection?.category == category
            ? _categorySelection?.subcategory
            : null,
        onFirstStoreChanged: _focusCategoryFirstStore,
        onSubcategoryChanged: (value) => _onCategorySelectionChanged(
          CategorySelection(category: category, subcategory: value),
        ),
      ),
    );
    // 떠 있는 동안만 값이 있다. 다른 chip을 눌렀을 때 이 시트를 먼저 닫고
    // 기다리는 데 쓴다([_onCategoryChipTapped]).
    _categorySheetClosing = showing;
    final picked = await showing;
    if (identical(_categorySheetClosing, showing)) _categorySheetClosing = null;
    if (_closeSheetChainRequested || picked == null || !mounted) return false;
    return _showStoreInfo(picked, focusOnMap: true);
  }

  /// 카테고리 목록 맨 위 매장으로 지도를 옮긴다. **배율은 건드리지 않는다** —
  /// 업종을 훑는 행동이라 화면이 당겨지면 층 전체 배치를 잃는다.
  ///
  /// 목표는 시트(아래)와 chip 줄(위) **사이에 남는 띠 한가운데**다. 정중앙이면 시트
  /// 뒤에 숨고, 시트 높이만 빼면 chip 줄 뒤로 올라간다.
  void _focusCategoryFirstStore(PoiSearchResult? store) {
    if (store == null || !mounted) return;
    final topInsetPx = _categoryRowBottomPx();
    if (_outdoorIndoorEntered) {
      _outdoorKey.currentState?.focusStore(
        store,
        bottomSheetFraction: kCategoryStoresSheetInitialSize,
        topInsetPx: topInsetPx,
        keepZoom: true,
      );
    }
  }

  /// 지도 위 카테고리 chip 줄의 아래 끝(화면 좌표·논리 픽셀). 상수로 박지 않고
  /// 실제로 재는 이유는, 이 줄이 길찾기 초안 바 때문에 아래로 밀리거나 검색 중
  /// 접히기 때문이다. 트리에 없으면 0 — 가릴 것이 없다는 뜻이다.
  double _categoryRowBottomPx() {
    final box =
        _categoryRowKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return 0;
    return box.localToGlobal(Offset.zero).dy + box.size.height;
  }

  /// 길찾기 두 칸에 보여 줄 후보. 매장·건물·건물 밖 장소를 한 목록으로 합친다.
  ///
  /// 상단 검색과 **같은 재료**를 쓴다. 진입점마다 규칙이 갈리면 같은 검색어가
  /// 어디에 치느냐에 따라 다른 곳을 찾아 주고, 실제로 그런 시기가 있었다.
  // 후보 목록 조립(경량·의미 검색, 실내/건물/바깥 섞기)은
  // directions_candidates.dart가 소유한다. 화면은 야외 지도에서 읽을 세 가지만
  // [OutdoorSearchContext]로 묶어 넘긴다.
  OutdoorSearchContext get _outdoorSearchContext {
    final outdoor = _outdoorKey.currentState;
    return OutdoorSearchContext(
      entrancePointFor: outdoor?.entrancePointFor,
      searchCenter: outdoor?.outdoorSearchCenter,
      isAtIndoorBuilding: outdoor?.isAtIndoorBuilding,
    );
  }

  // ---------------------------------------------------------------------
  // 길찾기 — 상단 바의 출발/도착 두 칸 + 그 위 이동 수단 줄.
  //
  // 시트가 아니라 여기로 옮긴 이유는 [_routeMode] 주석에 있다.
  // ---------------------------------------------------------------------

  /// 길찾기를 시작한다(상단 바를 두 칸으로 바꾼다).
  ///
  /// preset을 안 넘기면 기억해 둔 값을 이어 간다. [focusField]를 안 넘기면 비어 있는
  /// 칸으로 커서를 보내고, 둘 다 차 있으면 바로 결과를 보여 준다.
  Future<void> _openRouteMode({
    DirectionsCandidate? presetOrigin,
    DirectionsCandidate? presetDestination,
    RoutePlanField? focusField,
  }) async {
    _closeSearch();
    // 지도에서 고르는 중이었다면 그 상태는 끝난다. 안 끄면 다음 지도 탭이
    // 엉뚱하게 출발지/도착지로 먹힌다.
    _stopPickingOnMap();
    // 자동완성 원본은 여기서 한 번만 받아 둔다. 결과를 기다리지 않으므로
    // 목록은 먼저 뜨고, 도착하면 후보 줄만 뒤늦게 채워진다.
    unawaited(_loadRouteStoreIndex());
    if (presetOrigin != null) _selectedOrigin = presetOrigin;
    if (presetDestination != null) _routeDraftDestination = presetDestination;
    _routeOriginController.text = _selectedOrigin?.title ?? '';
    _routeDestinationController.text = _routeDraftDestination?.title ?? '';
    final field =
        focusField ??
        (_routeDraftDestination == null ? RoutePlanField.destination : null);
    setState(() {
      _routeMode = true;
      _routeEditingField = field;
    });
    if (field == null) {
      _unfocusRouteFields();
      return;
    }
    // 커서를 넣는 것과 후보 목록을 그 칸 기준으로 여는 것은 같이 가야 한다.
    // 하나만 하면 커서는 출발 칸에 있는데 목록은 도착지 후보인 상태가 된다.
    (field == RoutePlanField.origin
            ? _routeOriginFocus
            : _routeDestinationFocus)
        .requestFocus();
    _scheduleRouteCandidates('', immediate: true);
  }

  /// 자동완성 원본을 받아 둔다. 실패는 삼킨다 — 자동완성만 포기하고 검색은
  /// 막지 않는다. 리포지토리가 상단 검색과 같은 Future를 공유하므로 두 번
  /// 받지 않는다.
  Future<void> _loadRouteStoreIndex() async {
    if (_routeStoreIndex != null) return;
    try {
      final index = await buildingRepository.getStoreIndex(_buildingId);
      if (!mounted || index == null) return;
      setState(() {
        _routeStoreIndex = index;
        // 목록이 늦게 도착하는 동안 사용자가 이미 치고 있었을 수 있다.
        _routeSuggestions = _computeRouteSuggestions(_routeQuery);
      });
    } on Object {
      // 자동완성만 포기한다.
    }
  }

  void _onPlaceLinkChanged() {
    final link = placeLinkInbox.value;
    if (link == null) return;
    placeLinkInbox.take();
    unawaited(_openPlaceFromLink(link));
  }

  /// 링크가 가리키는 매장을 연다.
  ///
  /// **이름으로 찾거나 첫 결과로 대신하지 않는다.** 같은 이름의 매장이 층마다 있는
  /// 시설이라, 한 번이라도 흉내를 내면 공유받은 사람이 **다른 매장**을 보고 그것을
  /// 공유한 사람의 의도로 읽는다. 정확히 그 id가 없으면 아무것도 열지 않고 지금
  /// 지도에 머문다.
  Future<void> _openPlaceFromLink(PlaceLink link) async {
    if (link.buildingId != _buildingId) {
      _showLinkFailure();
      return;
    }
    await _loadRouteStoreIndex();
    if (!mounted) return;
    final entry = _routeStoreIndex
        ?.where((e) => e.id == link.placeId)
        .firstOrNull;
    if (entry == null) {
      _showLinkFailure();
      return;
    }
    // 링크를 받은 사람은 대개 건물 밖에 있다 — 그게 공유의 목적이다. 밖이라고
    // 타 층을 포기하면 공유가 주 사용 맥락에서 아무것도 열지 못한다.
    final resolved = await _outdoorKey.currentState?.resolveIndexEntry(
      entry,
      enterBuildingIfNeeded: true,
    );
    if (!mounted) return;
    if (resolved == null) {
      _showLinkFailure();
      return;
    }
    _closeSearch();
    await _runSheetChain(() => _showStoreInfo(resolved, focusOnMap: true));
  }

  /// 링크로 아무것도 열지 못했을 때. **원인을 과장하지 않는다** — 네트워크 실패와
  /// 삭제를 클라이언트가 구분할 수 없어서, 둘 다 같은 한 줄로 끝낸다.
  void _showLinkFailure() {
    if (!mounted) return;
    RoutexToast.show(context, '장소를 찾을 수 없습니다');
  }

  /// 후보 계산. **건물 안을 보고 있을 때만** 만든다 — 원본이 건물 하나의 매장
  /// 목록이라, 야외에서 쓰면 지금 서 있는 곳과 무관한 매장을 제안하게 된다
  /// (상단 검색 패널의 `indoorContextActive`와 같은 이유).
  List<StoreSuggestion> _computeRouteSuggestions(String query) {
    final index = _routeStoreIndex;
    if (index == null || !_indoorContextActive) return const [];
    return suggestStores(stores: index, query: query);
  }

  /// 온디바이스 후보를 눌렀을 때. 그 이름으로 검색을 다시 돌리되, **고른 그
  /// 매장의 층**으로 한 번만 좁힌다 — 같은 이름이 층마다 있는 시설에서 화면에
  /// 적힌 층과 실제로 가는 층이 어긋나지 않게 한다.
  void _onRouteSuggestionPicked(StoreSuggestion suggestion) {
    final nearest = nearestByWalkingDistance(
      stores: suggestion.stores,
      reachByNodeId: _reachByNodeId,
    );
    final store = nearest.store;
    _routeFloorScopeOnce = store.floorId;
    final controller = _routeEditingField == RoutePlanField.origin
        ? _routeOriginController
        : _routeDestinationController;
    controller.text = store.name;
    // 사용자가 콕 집어 골랐다. 여기서 300ms를 더 기다릴 이유가 없다.
    _scheduleRouteCandidates(store.name, immediate: true);
  }

  void _onRouteOriginFocusChanged() {
    if (!_routeOriginFocus.hasFocus) return;
    _onRouteFieldFocused(RoutePlanField.origin, _routeOriginController.text);
  }

  void _onRouteDestinationFocusChanged() {
    if (!_routeDestinationFocus.hasFocus) return;
    _onRouteFieldFocused(
      RoutePlanField.destination,
      _routeDestinationController.text,
    );
  }

  void _onRouteFieldFocused(RoutePlanField field, String query) {
    if (_routeEditingField == field) return;
    // 다시 치기 시작했다는 것은 지도에서 고르는 걸 그만뒀다는 뜻이다. 안 끄면
    // 후보를 골라 경로를 그린 **뒤에도** 다음 지도 탭이 그 칸으로 먹힌다.
    _stopPickingOnMap();
    setState(() => _routeEditingField = field);
    // 칸을 옮긴 것이지 글자를 친 것이 아니다 — 이미 들어 있던 글자의 답은
    // 기다릴 것 없이 바로 찾는다.
    _scheduleRouteCandidates(query, immediate: true);
  }

  void _unfocusRouteFields() {
    _routeOriginFocus.unfocus();
    _routeDestinationFocus.unfocus();
  }

  /// 두 칸 중 하나에 글자가 들어왔을 때.
  ///
  /// 글자를 고치는 것은 **지금 잡혀 있는 값을 버렸다는 뜻**이다. 안 버리면
  /// "강남역"을 지우고 다른 곳을 쳐도 경로는 강남역에서 계산된다.
  void _onRouteFieldChanged(RoutePlanField field, String query) {
    setState(() {
      _routeEditingField = field;
      if (field == RoutePlanField.origin) {
        _selectedOrigin = null;
      } else {
        _routeDraftDestination = null;
      }
    });
    _scheduleRouteCandidates(query);
  }

  void _clearRouteResults() {
    _routeIndoorRows = const [];
    _routeSemanticRows = const [];
    _routeOutdoorRows = const [];
  }

  /// 진행 중인 후보 조회를 끊고 스피너도 함께 내린다.
  ///
  /// **순번만 올리면 안 된다.** 무효화된 조회는 조기 반환하면서 [_routeSearching]을
  /// 안 내리므로, 뒤이어 새 조회를 걸지 않는 경로(칸 교체·초안 비우기)에서는
  /// 스피너가 영영 남는다.
  void _stopRouteSearch() {
    _routeSearchDebounce?.cancel();
    _routeSearchDebounce = null;
    _routeSearchSeq++;
    if (!mounted) return;
    setState(() => _routeSearching = false);
  }

  /// 후보 조회를 예약한다. 글자마다 서버를 때리지 않게 잠깐 모았다 보낸다.
  ///
  /// [immediate]는 사용자가 이미 "다 쳤다"고 말한 경우다(후보를 탭했거나, 글자가
  /// 남아 있는 칸에 커서가 들어왔거나). 그때 300ms를 더 기다리면 목록이 늦게 뜬 것
  /// 처럼만 보인다.
  void _scheduleRouteCandidates(String query, {bool immediate = false}) {
    _routeSearchDebounce?.cancel();
    _routeSearchDebounce = null;
    // 새 입력이 들어온 순간 진행 중인 조회를 무효화한다. 디바운스가 끝나기
    // 전에도 이전 조회의 늦은 응답이 화면을 덮으면 목록과 검색어가 어긋난다.
    _routeSearchSeq++;
    setState(() {
      // 서버 응답을 기다리지 않는다. 이게 후보가 즉시 뜨는 이유다.
      _routeSuggestions = _computeRouteSuggestions(query.trim());
      _routeSearching = true;
    });
    if (immediate) {
      unawaited(_searchRouteCandidates(query));
      return;
    }
    _routeSearchDebounce = Timer(
      _routeSearchDebounceDelay,
      () => unawaited(_searchRouteCandidates(query)),
    );
  }

  /// 실내 후보를 조회해 화면에 붙이고, 느린 두 갈래(바깥 POI·의미 검색)는
  /// **기다리지 않고** 따로 띄운다.
  ///
  /// 「찾는 중」이 끝나는 시점은 **실내 답이 나온 순간**이다. 예전에는 바깥
  /// 조회까지 직렬로 기다렸는데, 야외 건물을 검색하면 실내가 빈손이라 화면에 뜰
  /// 것이 전적으로 그 느린 경로에 달려 있었다 — 사용자에게는 스피너만 도는
  /// 화면이었다.
  Future<void> _searchRouteCandidates(String query) async {
    final seq = ++_routeSearchSeq;
    // 층을 좁히는 경우는 둘뿐이다.
    //  1. 온디바이스 후보를 **탭한** 경우 — 그 후보의 층(한 번 쓰고 지운다).
    //  2. 질의가 **층마다 있는 시설**을 가리키는 경우 — 가장 가까운 층.
    // 그 밖에는 null이라 「길찾기는 항상 건물 전체」 규칙이 그대로 유지된다.
    final floorId =
        _routeFloorScopeOnce ??
        nearestFloorForGroupedFacility(
          suggestions: _routeSuggestions,
          reachByNodeId: _reachByNodeId,
        );
    _routeFloorScopeOnce = null;

    // **두 조회를 같은 순간에 띄운다.** 바깥 조회는 실내 결과를 합칠 때만
    // 기다리므로(`outdoorDirectionsCandidates`), 백엔드가 느려도 TMAP 왕복이
    // 그만큼 밀리지 않는다. 실내를 먼저 await하던 동안 "한강공원"처럼 답이
    // 바깥에만 있는 검색이 백엔드 대기 시간만큼 빈 화면이었다.
    final indoorFuture = searchDirectionsCandidates(
      query,
      floorId: floorId,
      buildingId: _buildingId,
      indoorContextActive: _indoorContextActive,
      outdoor: _outdoorSearchContext,
    );
    unawaited(_appendOutdoorRouteCandidates(query, indoorFuture, seq));

    final IndoorDirectionsCandidates indoor;
    try {
      indoor = await indoorFuture;
    } on Object catch (error) {
      // 여기까지 오는 실패는 조회 하나가 터진 것이 아니라 조립 자체가 깨진
      // 경우다(개별 조회 실패는 [searchDirectionsCandidates] 안에서 빈 목록으로
      // 흡수된다). 그때도 스피너는 반드시 내린다.
      debugPrint('[route-search] "$query" 후보 조립 실패: $error');
      if (!mounted || seq != _routeSearchSeq) return;
      setState(() {
        _clearRouteResults();
        _routeSearching = false;
      });
      return;
    }
    // 여러 조회가 겹쳐 뜰 수 있어(빠른 타이핑) 마지막 요청 결과만 반영한다.
    if (!mounted || seq != _routeSearchSeq) return;

    setState(() {
      _routeIndoorRows = indoor.rows;
      _routeSemanticRows = const [];
      _routeOutdoorRows = const [];
      // **실내가 빈손이면 아직 「찾는 중」이다.** 야외 목적지 검색은 답이 바깥
      // 조회에만 있어서, 여기서 스피너를 내리면 "결과 없음"을 잠깐 보여 준 뒤
      // 목록이 뒤늦게 튀어나온다. 실내 줄이 있으면 이미 볼 것이 생겼으므로
      // 그 자리에서 끝낸다.
      _routeSearching = indoor.rows.isEmpty && !indoor.closed;
    });

    // 경량이 빈손이면 **의미 검색까지 이어 간다.** 건물 안을 보고 있을 때만 부른다 —
    // `/query/ai`는 건물 안 매장을 찾는 계약이다.
    //
    // "빈손"의 기준은 **실내 줄이 없는가**이지 결과가 비었는가가 아니다. 개수로 재면
    // 바깥 POI가 채워 주는 순간부터 실내 의미 검색이 영영 안 돈다.
    if (indoor.rows.every((c) => c.nodeId == null) &&
        query.trim().isNotEmpty &&
        _indoorContextActive) {
      unawaited(_appendSemanticRouteCandidates(query, seq));
    }
  }

  /// 바깥(TMAP) 줄을 뒤늦게 이어 붙인다. 되묻기로 실내 매장이 늘어날 수 있어
  /// 실내 줄도 함께 갈아 끼운다([outdoorDirectionsCandidates]).
  Future<void> _appendOutdoorRouteCandidates(
    String query,
    Future<IndoorDirectionsCandidates> indoor,
    int seq,
  ) async {
    final ({List<DirectionsCandidate> stores, List<DirectionsCandidate> outdoor})
    found;
    try {
      found = await outdoorDirectionsCandidates(
        query,
        indoor: indoor,
        buildingId: _buildingId,
        outdoor: _outdoorSearchContext,
      );
    } on Object catch (error) {
      debugPrint('[route-search] "$query" 바깥 후보 조회 실패: $error');
      // **여기서도 스피너는 내린다.** 바깥이 마지막 갈래라, 안 내리면 실내까지
      // 빈손인 검색이 영원히 「찾는 중」에 남는다.
      if (mounted && seq == _routeSearchSeq) {
        setState(() => _routeSearching = false);
      }
      return;
    }
    if (!mounted || seq != _routeSearchSeq) return;
    if (found.stores.isEmpty && found.outdoor.isEmpty) {
      setState(() => _routeSearching = false);
      return;
    }
    setState(() {
      _routeSearching = false;
      if (found.stores.isNotEmpty) {
        // 되묻기 결과는 건물 줄 **앞**에 온다. 실내 줄과 건물 줄의 순서는
        // [searchDirectionsCandidates]가 정한 그대로 유지한다.
        _routeIndoorRows = [
          ...found.stores,
          ..._routeIndoorRows.where((c) => c.buildingId != null),
        ];
      }
      _routeOutdoorRows = found.outdoor;
    });
  }

  /// 의미 검색 결과를 맨 위에 얹는다. 실패는 [semanticDirectionsCandidates]가
  /// 빈 목록으로 삼킨다 — 여기까지 왔다는 것은 이미 다른 후보가 화면에 있거나
  /// 아무것도 없다는 뜻이라, 오류 화면으로 덮어도 할 수 있는 일이 늘지 않는다.
  Future<void> _appendSemanticRouteCandidates(String query, int seq) async {
    final semantic = await semanticDirectionsCandidates(
      query,
      buildingId: _buildingId,
    );
    if (!mounted || seq != _routeSearchSeq || semantic.isEmpty) return;
    setState(() => _routeSemanticRows = semantic);
  }

  /// 출발지 ↔ 도착지 교체. **확정된 후보만 뒤집는다** — 타이핑 중인 글자는 검색어라,
  /// 옮기면 고른 적 없는 값이 확정된 것처럼 칸에 앉는다.
  ///
  /// 출발지가 "현재 위치"면 **가장 가까운 매장**으로 굳혀 도착지에 놓는다. 규칙과
  /// 실패 조건은 [nearestStoreForCurrentLocation]에 있다. 못 고르면 상태를
  /// 건드리지 않고 이유만 알린다 — 절반만 바뀐 초안(출발지는 새 값, 도착지는 옛
  /// 값)을 남기면 사용자가 무엇을 누른 것인지 알 수 없게 된다.
  Future<void> _swapRouteEndpoints() async {
    final destination = _routeDraftDestination;
    if (destination == null) return;
    final origin = _selectedOrigin;

    // 출발지가 실제 지점이면 그냥 맞바꾼다. 색인도 그래프도 필요 없다.
    if (origin != null) {
      _applySwappedEndpoints(newOrigin: destination, newDestination: origin);
      await _startRoute(
        origin: destination,
        destination: origin,
        // 사용자가 방금 직접 뒤집었다 — 위치가 옮겨간 것을 새삼 알릴 이유가 없다.
        announceOriginAnchor: false,
      );
      return;
    }

    final replacement = await _nearestStoreAsCandidate(
      excludeNodeId: destination.nodeId,
    );
    if (!mounted) return;
    if (replacement == null) {
      _showSnack('현재 위치를 대신할 가까운 매장을 찾지 못했어요.');
      return;
    }

    _applySwappedEndpoints(newOrigin: destination, newDestination: replacement);
    await _startRoute(
      origin: destination,
      destination: replacement,
      announceOriginAnchor: false,
    );
  }

  /// 뒤집은 결과를 두 칸과 상태에 함께 반영한다.
  ///
  /// 칸의 **글자**까지 같이 바꾸는 것이 핵심이다. 우리 상단 바는 라벨이 아니라
  /// 입력창이라, 상태만 뒤집으면 화면에는 옛 글자가 그대로 남아 사용자가 보는
  /// 것과 실제로 계산되는 경로가 어긋난다.
  void _applySwappedEndpoints({
    required DirectionsCandidate newOrigin,
    required DirectionsCandidate newDestination,
  }) {
    setState(() {
      _selectedOrigin = newOrigin;
      _routeDraftDestination = newDestination;
      _routeOriginController.text = newOrigin.title;
      _routeDestinationController.text = newDestination.title;
      _routeEditingField = null;
    });
    // 교체 직전에 걸려 있던 조회를 무효화한다. 늦게 도착한 응답이 반대 칸의
    // 목록을 덮으면, 방금 만든 조합과 무관한 후보가 뜬다.
    _stopRouteSearch();
    _unfocusRouteFields();
    // 출발점이 바뀌었으니 목록 거리도 전부 옛 값이다.
    unawaited(_refreshReach());
  }

  /// 후보 목록에서 하나를 골랐을 때. 아직 도착지가 없으면 도착지 칸으로 넘겨
  /// 주고, 둘 다 준비됐으면 입력을 닫고 경로를 계산한다.
  void _pickRouteCandidate(DirectionsCandidate candidate) {
    final field = _routeEditingField ?? RoutePlanField.destination;
    setState(() {
      if (field == RoutePlanField.origin) {
        _selectedOrigin = candidate;
        _routeOriginController.text = candidate.title;
      } else {
        _routeDraftDestination = candidate;
        _routeDestinationController.text = candidate.title;
      }
    });
    if (field == RoutePlanField.origin) unawaited(_refreshReach());
    // 도착지가 아직 없으면 [_afterRouteFieldPicked]가 경로를 시작하지 않는다.
    // 그때만 카메라를 옮긴다(겹침 이유는 [_focusIndoorOrigin] 주석).
    if (field == RoutePlanField.origin && _routeDraftDestination == null) {
      _focusIndoorOrigin(candidate);
    }
    _afterRouteFieldPicked();
  }

  /// 출발지로 고른 실내 매장으로 실내 지도를 옮긴다(층 전환 포함).
  ///
  /// 없으면 B2 매장을 출발지로 잡아도 화면은 보고 있던 층 그대로다 — 사용자는
  /// 자기가 어디서 출발하는 것으로 잡혔는지 확인할 방법이 없다.
  ///
  /// **경로를 바로 계산하지 않는 경우에만 부른다.** 계산이 시작되면 경로 개요가
  /// 두 끝점을 함께 담도록 카메라를 다시 잡으므로, 여기서 또 옮기면 두
  /// 애니메이션이 겹쳐 화면이 두 번 튄다.
  void _focusIndoorOrigin(DirectionsCandidate candidate) {
    if (!candidate.isIndoorPoint) return;
    unawaited(
      _outdoorKey.currentState?.focusStore(
            _asPoi(candidate),
            // 밖에서 골랐어도 들어가서 보여 준다. 실내 모드를 직접 켜지는
            // 않는다 — focusStore가 카메라만 옮기고 진입 판정은 그대로 둔다.
            enterBuildingIfNeeded: true,
          ) ??
          Future<void>.value(),
    );
  }

  /// 출발지를 "현재 위치"로 되돌린다. 값을 비우는 것이 곧 현재 위치라
  /// ([_selectedOrigin] 주석) 글자도 함께 지운다.
  void _pickCurrentLocationAsOrigin() {
    setState(() {
      _selectedOrigin = null;
      _routeOriginController.clear();
    });
    _afterRouteFieldPicked();
  }

  void _afterRouteFieldPicked() {
    final destination = _routeDraftDestination;
    if (destination == null) {
      setState(() => _routeEditingField = RoutePlanField.destination);
      _routeDestinationFocus.requestFocus();
      _scheduleRouteCandidates(
        _routeDestinationController.text,
        immediate: true,
      );
      return;
    }
    setState(() => _routeEditingField = null);
    _unfocusRouteFields();
    unawaited(_startRoute(origin: _selectedOrigin, destination: destination));
  }

  /// 후보 목록의 "지도에서 선택". 목록을 접고 지도 탭을 기다린다 — 고른 값은
  /// [_applyPickedCandidate]가 그 칸에 넣는다.
  void _pickRouteEndpointOnMap(RoutePlanField field) {
    _unfocusRouteFields();
    setState(() {
      _routeEditingField = null;
      _mapPickTarget = field == RoutePlanField.origin
          ? DirectionsMapPickTarget.origin
          : DirectionsMapPickTarget.destination;
      // 안내 카드와 자리가 겹치므로 장소 카드는 접는다.
    });
  }

  /// 지금 화면에서 고를 수 있는 이동 수단.
  ///
  /// 대중교통은 카카오 키가 주입됐을 때만 낀다. 키 없이 띄우면 누를 때마다
  /// 실패 안내만 나오는 버튼이 된다.
  List<RoutePlanMode> get _availableTravelModes => [
    for (final mode in RoutePlanMode.values)
      if (mode != RoutePlanMode.transit || transitRepository.isAvailable) mode,
  ];

  /// 이동 수단 줄에서 직접 골랐을 때.
  ///
  /// 도착지가 아직 없으면 상태만 바꿔 둔다. 그 상태에서 계산하면 실패 안내만
  /// 나오고, 곧 도착지를 고르면 이 수단으로 그려진다.
  Future<void> _onTravelModePicked(RoutePlanMode mode) async {
    if (_travelMode == mode) return;
    setState(() => _travelMode = mode);
    final destination = _routeDraftDestination;
    if (destination == null) return;
    await _startRoute(
      origin: _selectedOrigin,
      destination: destination,
      autoSelectMode: false,
    );
  }

  /// 안내가 시작되면 상단 바는 길찾기 두 칸이어야 한다. 매장 시트·검색 결과·
  /// 지도 탭처럼 길찾기 바를 거치지 않고 들어오는 경로가 있어서, 경로를 그리기
  /// 직전에 여기서 한 번 맞춰 준다 — 안 맞추면 경로는 그려졌는데 상단은
  /// 검색창인 화면이 된다.
  void _enterRouteModeForGuidance(
    DirectionsCandidate? origin,
    DirectionsCandidate destination,
  ) {
    _routeOriginController.text = origin?.title ?? '';
    _routeDestinationController.text = destination.title;
    if (_routeMode && _routeEditingField == null) return;
    setState(() {
      _routeMode = true;
      _routeEditingField = null;
    });
  }

  /// 걸어갈 만한 거리의 상한(m).
  ///
  /// 1.5 km는 보통 걸음으로 20분쯤이다. 그보다 멀면 대중교통을 먼저 보여 주는
  /// 편이 맞다 — 도보 안내를 지나쳐 다시 누르게 하는 것보다 낫고, 반대로 이
  /// 값을 더 낮추면 두 정거장 거리를 굳이 버스로 안내하게 된다.
  static const _walkableMeters = 1500.0;

  /// 거리를 보고 처음 보여 줄 이동 수단을 정한다. 출발점을 모르면 도보로 둔다 —
  /// 대중교통을 부르면 고른 적도 없는 수단의 실패 안내를 본다.
  ///
  /// **자동차는 자동으로 고르지 않는다** — 차가 있는지 모르고, 걸어갈 거리에
  /// 운전 경로를 내밀면 무엇을 안내받는지부터 다시 읽어야 한다.
  RoutePlanMode _defaultTravelMode(
    DirectionsCandidate? origin,
    DirectionsCandidate destination,
  ) {
    if (!transitRepository.isAvailable) return RoutePlanMode.walk;
    final from = origin?.point ?? _outdoorKey.currentState?.routeOriginPoint;
    if (from == null) return RoutePlanMode.walk;
    final meters = const Distance().as(
      LengthUnit.Meter,
      from,
      destination.point,
    );
    return meters > _walkableMeters
        ? RoutePlanMode.transit
        : RoutePlanMode.walk;
  }

  /// 대중교통 경로를 물어보고, 후보 중 하나를 고르면 야외 지도에 그린다.
  ///
  /// 출발지는 야외 지도가 정한다([OutdoorMapBodyState.routeOriginPoint]) —
  /// 지도에서 찍은 출발 지점이 있으면 그것을, 없으면 GPS를 쓴다. 실내 앵커는
  /// 쓰지 않는다(건물 안 좌표를 보내면 정류장이 건물 반대편에서 잡힌다).
  ///
  /// **무시한 사실을 로그로 남긴다.** 조용히 삼키면 중복을 만드는 조작이
  /// 무엇인지 영영 안 보이고, 가드가 원인을 덮은 채로 남는다.
  Future<void> _startTransitRoute(
    DirectionsCandidate? origin,
    DirectionsCandidate destination,
  ) {
    return _transitRequest.run(
      () => _requestTransitRoute(origin, destination),
      onDuplicate: () =>
          debugPrint('[transit] 조회 중이라 중복 요청 무시: ${destination.title}'),
    );
  }

  Future<void> _requestTransitRoute(
    DirectionsCandidate? routeOrigin,
    DirectionsCandidate destination,
  ) async {
    debugPrint('[transit] 조회 시작: ${destination.title}');
    final outdoor = _outdoorKey.currentState;
    final startsIndoors = transitStartsIndoors(
      origin: routeOrigin,
      indoorContextActive: _indoorContextActive,
      indoorStartReady:
          indoorNavigationDriver.currentCalibration.canRenderPosition,
    );
    final origin = _transitOriginPoint(
      outdoor,
      destination,
      startsIndoors: startsIndoors,
    );
    if (outdoor == null || origin == null) {
      _showSnack('현재 위치를 아직 못 잡았습니다. GPS 신호를 확인하거나 출발지를 직접 지정해주세요.');
      return;
    }

    final routes = await transitRepository.getTransitRoutes(
      origin: origin,
      destination: destination.point,
    );
    if (!mounted) return;
    if (await _announceTransitFailure(routes.status, destination)) return;

    final picked = await _withMapsLocked(
      () => TransitRoutesSheet.show(
        context,
        routes: routes,
        destinationLabel: destination.title,
        onCloseAll: _requestCloseSheetChain,
      ),
    );
    if (!mounted || picked == null) return;

    // **건물 안 매장이면 마지막 도보는 매장이 아니라 문으로 간다.**
    //
    // 매장 좌표를 그대로 끝점으로 주면 TMAP이 그 좌표에서 가장 가까운 도로로
    // 스냅하는데, 그 도로가 내린 곳 반대편일 수 있다. 내린 자리에서 가장 가까운
    // 문을 우리가 직접 고른다 — 그 자리를 어떻게 구하는지는
    // [transitDropPoint]에 있다.
    final dropPoint = transitDropPoint(picked, fallback: destination.point);
    final indoorStore = _indoorStoreOf(destination);
    // **우리 건물을 향하는 안내면 하차 지점 기준으로 문을 다시 고른다.**
    // 후보의 문은 검색하던 시점 위치에서 가까운 문이라, 버스를 타고 반대편에서
    // 내리면 더 이상 가깝지 않다 — 실기기에서 바로 옆 문을 두고 건물을 빙 돌았다.
    final targetsOurBuilding =
        indoorStore != null || destination.buildingId == _buildingId;
    final walkTarget =
        (targetsOurBuilding ? outdoor.entranceNearestTo(dropPoint) : null) ??
        destination.point;
    debugPrint(
      '[transit] 하차 지점 기준 문 선택: 우리 건물=$targetsOurBuilding '
      '하차=(${dropPoint.latitude.toStringAsFixed(5)}, '
      '${dropPoint.longitude.toStringAsFixed(5)}) '
      '도보 도착=(${walkTarget.latitude.toStringAsFixed(5)}, '
      '${walkTarget.longitude.toStringAsFixed(5)})',
    );

    // **건물 안에서 출발하면 첫 도보도 문에서 시작한다.** 하차 쪽의 거울상이다.
    //
    // 안 고치면 앞쪽 도보가 건물 안 GPS 좌표에서 시작해 TMAP이 그 좌표에서 가장
    // 가까운 도로로 스냅한다 — 출구가 아닌 자리가 도보 시작점으로 잡히고, 실내
    // 구간은 아예 그려지지 않는다(실기기 확인).
    var walkOrigin = origin;
    var walkStartsAtDoor = false;
    if (startsIndoors) {
      final boardingPoint = transitBoardPoint(picked, fallback: origin);
      final exit = await outdoor.showIndoorLegToTransitBoarding(
        boardingPoint,
        // origin이 없으면 "지금 있는 곳"이라 PDR 앵커에서 출발한다.
        origin: routeOrigin == null ? null : _indoorStoreOf(routeOrigin),
      );
      if (!mounted) return;
      if (exit != null) {
        walkOrigin = exit;
        walkStartsAtDoor = true;
      }
      debugPrint(
        '[transit] 승차 지점 기준 문 선택: '
        '승차=(${boardingPoint.latitude.toStringAsFixed(5)}, '
        '${boardingPoint.longitude.toStringAsFixed(5)}) '
        '도보 출발=(${walkOrigin.latitude.toStringAsFixed(5)}, '
        '${walkOrigin.longitude.toStringAsFixed(5)})',
      );
    }

    // **카카오가 붙여 준 양 끝 도보는 우리가 다시 그린다.**
    //
    // 그 구간은 카카오가 정한 끝점(우리가 보낸 좌표)을 쓰는데, 우리는 방금
    // 하차·승차 지점 기준으로 문을 다시 골랐다. 그대로 두면 지도에 그려진 도보는
    // 옛 끝점으로 가고 실내 구간만 새 문에서 시작해, 두 선이 서로 다른 곳을
    // 가리킨다. 자세한 근거는 [trimTrailingWalkLeg]에 있다.
    var trimmed = trimTrailingWalkLeg(picked);
    // 문을 못 골랐으면(문 데이터 없음·실내 경로 실패) 자르지 않는다 — 자르고
    // 나면 시작점이 여전히 건물 안 좌표라 더 짧은 직선만 남는다.
    if (walkStartsAtDoor) trimmed = trimLeadingWalkLeg(trimmed);

    // 고른 **뒤에** 앞뒤 도보를 채운다. 후보는 최대 15개까지 오는데, 목록을
    // 만들자고 후보마다 두 번씩 보행자 API를 부르면 30번이 나가고 사용자는
    // 그중 하나만 본다. 목록 단계에서 도보가 없어도 총 소요시간은 정확하다 —
    // 카카오 totalTime에 이미 포함돼 있다([fillTransitWalkLegs] 주석).
    final completed = await _withTransitWalkLegs(
      trimmed,
      origin: walkOrigin,
      destination: walkTarget,
    );
    if (!mounted) return;

    await outdoor.showTransitRoute(
      completed,
      destination: walkTarget,
      label: '${destination.title}까지',
      origin: walkOrigin,
    );
    if (!mounted || indoorStore == null) return;

    // 실내 구간은 **showTransitRoute 뒤에** 푼다. 그 함수가 시작할 때 pending을
    // 비우므로, 앞에서 풀면 쌓아 둔 실내 구간이 곧바로 지워진다.
    await outdoor.prepareIndoorLegFromDrop(indoorStore, dropPoint: dropPoint);
  }

  /// 대중교통 조회를 보낼 출발 좌표.
  ///
  /// **건물 안 좌표는 절대 보내지 않는다.** 카카오가 그 좌표에서 가장 가까운
  /// 정류장을 찾는데, 건물이 크면 실제로 나가야 하는 문의 반대편이 잡힌다.
  ///
  /// [startsIndoors]면 목적지 쪽 문을 씨앗으로 쓴다 — 어느 정류장에서 탈지는
  /// 아직 모르므로 방향만이라도 맞는 값을 보내고, 후보를 고른 **뒤에** 승차
  /// 지점 기준으로 문을 다시 잡는다([transitBoardPoint]). 문 데이터가 없으면
  /// 예전처럼 GPS로 떨어진다.
  LatLng? _transitOriginPoint(
    OutdoorMapBodyState? outdoor,
    DirectionsCandidate destination, {
    required bool startsIndoors,
  }) {
    if (startsIndoors) {
      final door = outdoor?.entranceNearestTo(destination.point);
      if (door != null) return door;
      return outdoor?.routeOriginPoint;
    }
    final selected = _selectedOrigin;
    final outdoorOrigin =
        (selected != null && selected.floor == null && selected.nodeId == null)
        ? selected.point
        : null;
    return outdoorOrigin ?? outdoor?.routeOriginPoint;
  }

  /// 조회가 경로 없이 끝났으면 사용자에게 알리고 true. 계속 진행할 수 있으면 false.
  ///
  /// **결말마다 사용자가 할 행동이 다르다.** 한 문구로 묶으면 700m 앞 목적지를
  /// 두고 계속 재시도하게 된다([TransitRoutesStatus] 주석).
  Future<bool> _announceTransitFailure(
    TransitRoutesStatus status,
    DirectionsCandidate destination,
  ) async {
    switch (status) {
      case TransitRoutesStatus.ok:
        return false;
      case TransitRoutesStatus.unavailable:
        _showSnack('대중교통 안내를 쓸 수 없습니다. 카카오 REST 키 설정을 확인해주세요.');
        return true;
      case TransitRoutesStatus.failed:
        _showSnack('대중교통 경로를 불러오지 못했습니다. 잠시 후 다시 시도해주세요.');
        return true;
      case TransitRoutesStatus.noRoute:
        _showSnack('이 구간의 대중교통 경로를 찾지 못했습니다.');
        return true;
      case TransitRoutesStatus.tooClose:
        // 걸어갈 수 있는 거리다. 안내 없이 끝내지 않고 도보 경로로 이어 준다 —
        // 사용자가 원한 것은 "저기까지 가는 방법"이지 "대중교통 그 자체"가 아니다.
        _showSnack('가까운 거리라 대중교통 경로가 없습니다. 도보로 안내합니다.');
        setState(() => _travelMode = RoutePlanMode.walk);
        await _startRoute(
          origin: _selectedOrigin,
          destination: destination,
          autoSelectMode: false,
        );
        return true;
    }
  }

  /// 이 후보가 **우리 건물 안 매장**이면 실내 라우팅용 값으로 바꾼다. 층이나
  /// 노드가 없으면 null — 좌표까지만 안내할 수 있는 바깥 장소다.
  PoiSearchResult? _indoorStoreOf(DirectionsCandidate candidate) {
    final floor = candidate.floor;
    final nodeId = candidate.nodeId;
    if (floor == null || nodeId == null) return null;
    return PoiSearchResult(
      name: candidate.title,
      floor: floor,
      point: candidate.point,
      nodeId: nodeId,
    );
  }

  /// 카카오가 주지 않는 출발·도착 도보를 TMAP 보행자 경로로 채운다.
  ///
  /// 두 요청을 동시에 보낸다. 순서대로 기다리면 지도가 뜨기까지 왕복 시간이
  /// 두 배가 되는데, 두 구간은 서로를 필요로 하지 않는다.
  ///
  /// 실패해도 안내를 막지 않는다. 도보선이 직선으로 떨어질 뿐이고, 사용자가
  /// 기다린 것은 "저기까지 가는 방법"이지 도보 구간의 정확한 모양이 아니다.
  Future<TransitItinerary> _withTransitWalkLegs(
    TransitItinerary itinerary, {
    required LatLng origin,
    required LatLng destination,
  }) async {
    if (itinerary.legs.isEmpty) return itinerary;
    final first = itinerary.legs.first;
    final last = itinerary.legs.last;

    final routes = await Future.wait([
      (first.mode.isWalk || first.points.isEmpty)
          ? Future<DirectionsRoute?>.value()
          : directionsRepository.getWalkingRoute(
              origin: origin,
              destination: first.points.first,
            ),
      (last.mode.isWalk || last.points.isEmpty)
          ? Future<DirectionsRoute?>.value()
          : directionsRepository.getWalkingRoute(
              origin: last.points.last,
              destination: destination,
            ),
    ]);

    return fillTransitWalkLegs(
      itinerary,
      origin: origin,
      destination: destination,
      head: routes[0],
      // 마지막 도보는 **도착점까지 이어 붙인다.** TMAP 보행자 경로는 가장 가까운
      // 보행 가능 도로에서 끝나는데, 여기 도착점은 건물 출입구라 도로에서 몇십
      // 미터 떨어져 있다. 그대로 두면 선이 건물 앞 도로에서 뚝 끊기고, 정작 문
      // 앞 구간과 그 문에서 이어지는 실내 구간 사이가 비어 두 선이 남남으로
      // 보인다.
      tail: extendRouteToDestination(routes[1], destination),
    );
  }

  /// 자동차 경로. **경로 전체를 먼저 보여주고, 따라가기는 버튼으로 시작한다.**
  ///
  /// 한동안은 경로를 그리자마자 카메라를 현재 위치로 확대했다. "자동차를 고른
  /// 것 자체가 지금 출발한다는 뜻"이라는 판단이었는데, 그 화면에서는 사용자가
  /// 전체 경로를 **한 번도 못 본다** — 어디를 지나 어느 방향으로 가는지 확인할
  /// 기회 없이 곧바로 자기 위치에 확대된 화면을 마주한다. 지금은 경로 전체에
  /// 카메라를 맞춰 두고, 하단 카드의 "안내 시작"을 누르면 그때 위치로 내려간다.
  Future<void> _startCarRoute(
    DirectionsCandidate? origin,
    DirectionsCandidate destination,
  ) async {
    final outdoor = _outdoorKey.currentState;
    // 실내 지점이 출발지면 건물 문으로 바꾼다. 건물 안 좌표를 그대로 보내면
    // TMAP이 건물 반대편 도로에 스냅해, 실제로 나가는 문과 다른 곳에서 경로가
    // 시작한다. 도착지도 같은 이유로 문으로 바꾼다.
    final from = origin == null
        ? outdoor?.routeOriginPoint
        : (outdoor?.entranceIfInsideBuilding(origin.point) ?? origin.point);
    if (outdoor == null || from == null) {
      _showSnack('현재 위치를 아직 못 잡았습니다. GPS 신호를 확인하거나 출발지를 직접 지정해주세요.');
      return;
    }
    final to =
        outdoor.entranceIfInsideBuilding(destination.point) ??
        destination.point;
    final route = await directionsRepository.getDrivingRoute(
      origin: from,
      destination: to,
    );
    if (!mounted) return;
    if (route == null) {
      _showSnack('자동차 경로를 불러오지 못했습니다. 잠시 후 다시 시도해주세요.');
      return;
    }
    await outdoor.showPlannedRoadRoute(
      route,
      origin: from,
      destination: to,
      label: destination.title,
      offerStartGuidance: true,
      driving: true,
    );
  }

  /// 지도가 "위치를 새로 잡았다"고 알려올 때. 기억해둔 출발지 매장을 버려 다음
  /// 길찾기가 **방금 잡은 위치**에서 출발하게 한다 — 없으면 새 위치 아이콘을 두고
  /// 경로만 옛 매장에서 시작해 위치 지정이 무시된 것처럼 보인다.
  ///
  /// 버릴 매장 출발지가 없어도 **다시 그린다** — 출발 행 라벨을 가르는
  /// [_canRouteFromCurrentLocation]이 이 시점에 막 참이 되기 때문이다.
  void _onLocationAnchored() {
    setState(() => _selectedOrigin = null);
    // 출발점이 바뀌었으니 목록에 적힌 거리도 전부 옛 값이다. 다시 계산한다.
    unawaited(_refreshReach());
  }

  /// 지도에서 고르기를 끝낸다(선택 완료·취소 공통, 출발지·도착지 공통).
  void _stopPickingOnMap() {
    if (_mapPickTarget == null) return;
    setState(() => _mapPickTarget = null);
  }

  /// 지도에서 매장을 눌렀을 때의 분기점. 지도에서 고르는 중이면 매장 정보
  /// 시트를 열지 않고 그 매장을 해당 칸(출발지/도착지)의 값으로 쓴다.
  ///
  /// 두 지도(야외의 실내 진입 오버레이·실내 탭)가 같은 콜백을 쓰므로, 어느 쪽에서
  /// 골라도 동일하게 동작한다.
  void _onMapStoreTap(PoiSearchResult match) {
    final target = _mapPickTarget;
    if (target == null) {
      unawaited(_openStoreFromMap(match));
      return;
    }
    _applyMapPick(match, target);
  }

  /// 지금 떠 있는 상세 시트가 닫히면 완료되는 Future. 안 떠 있으면 null.
  Future<StoreInfoAction?>? _placeDetailClosing;

  /// 시트가 보여 주는 매장. **떠 있는 채로 갈아 끼운다** — 다른 매장을 눌러도
  /// 라우트를 떼지 않으므로 아무것도 없는 프레임이 생기지 않는다.
  final _placeDetailTarget = ValueNotifier(
    const PlaceDetailTarget(title: '', subtitle: '', placeId: null),
  );

  /// 시트가 지금 가리키는 매장. 시트가 닫힌 뒤 출발·도착 후보를 만들 때 쓴다 —
  /// 갈아 끼웠다면 **처음 누른 매장이 아니라 마지막 매장**이어야 한다.
  PoiSearchResult? _activePlaceMatch;

  PlaceDetailTarget _targetFor(
    PoiSearchResult match,
    FavoritePlace? favorite,
  ) => PlaceDetailTarget(
    title: match.name,
    subtitle: match.floor,
    placeId: match.placeId,
    favorite: favorite,
    // 대분류는 화면에 글자로 나오지 않고 헤더 아이콘의 폴백·강조색으로만 쓴다.
    category: match.category,
    // 대분류 칩을 없앴으므로 업종은 한 줄로만 보여 준다. 소분류가 없는
    // 장소에서 업종이 통째로 사라지지 않도록 대분류로 떨어뜨린다.
    subcategory: match.subcategory ?? match.category,
    // 검색 결과 목록이 쓰는 것과 **같은 계산 결과**를 넘긴다. 두 화면이
    // 같은 매장에 다른 거리를 적으면 어느 쪽도 못 믿게 된다.
    reach: match.nodeId == null ? null : _reachByNodeId?[match.nodeId],
  );

  /// 지도에서 매장을 눌러 상세를 연다. **떠 있는 상세가 있으면 먼저 닫는다.**
  ///
  /// 고른 매장에 핀이 서고 카메라가 시트 위 영역 한가운데로 끌어온다. 이 시트는
  /// barrier가 없어 포인터를 지도로 흘리는 의도된 설계라([_withMapsLocked]),
  /// 그 대가로 시트가 쌓이는 것을 여기서 막는다.
  ///
  /// **이미 떠 있었으면 제자리에서 갈아 끼운다.** 닫고 다시 여는 기본 동작은
  /// 화면의 3분의 1을 왕복해(260ms + 380ms) 매장을 훑을수록 눈이 피로하다.
  /// 시트가 이미 그 자리에 있으니 움직일 이유가 없다 — 내용만 바꾼다.
  Future<void> _openStoreFromMap(PoiSearchResult match) async {
    if (_swapOpenPlaceDetail(match)) return;
    await _runSheetChain(
      // **배율을 유지하지 않는다.** 예전에는 "지도에서 직접 누른 매장은 이미
      // 화면에 있으니 확대하면 층 배치를 잃는다"는 이유로 유지했는데, 선택
      // 강조가 폴리곤 칠에서 핀으로 바뀌면서 전제가 깨졌다 — 칠은 축소 상태에서도
      // 면으로 보이지만 핀은 점이라, 멀리서 누르면 무엇이 골라졌는지 안 보인다.
      // `focusZoomFor`는 이미 더 가까우면 그대로 두므로 훑는 중에 튀지 않는다.
      () => _showStoreInfo(match, focusOnMap: true),
    );
  }

  /// 지도에서 고르는 중에 **매장이 아닌 곳**을 눌렀을 때. 매장을 눌렀을 때와
  /// **완전히 같은 처리**를 태운다 — 갈리면 "복도로 지정한 출발지만 위치 아이콘이
  /// 안 따라온다" 같은 절반짜리 동작이 생긴다.
  ///
  /// 고르는 중이 아니면 아무 일도 하지 않는다(지도 쪽도 막지만, 두 값이 한 프레임
  /// 어긋나는 순간을 없애려 상태 주인이 한 번 더 막는다).
  void _onMapPointPicked(PoiSearchResult picked) {
    final target = _mapPickTarget;
    if (target == null) return;
    _applyMapPick(picked, target);
  }

  /// 지도 탭으로 확정된 지점을 출발지/도착지에 반영한다. 매장 탭과 복도 탭이
  /// 공유하는 유일한 경로다.
  void _applyMapPick(PoiSearchResult match, DirectionsMapPickTarget target) {
    _stopPickingOnMap();
    // 강조 표시는 남겨두지 않는다 — 곧 경로와 핀이 그 자리를 대신한다.
    _outdoorKey.currentState?.clearHighlight();
    final picked = DirectionsCandidate(
      title: match.name,
      subtitle: match.floor,
      point: match.point,
      nodeId: match.nodeId,
      floor: match.floor,
    );

    if (target == DirectionsMapPickTarget.origin) {
      setState(() => _selectedOrigin = picked);
      // 출발점이 바뀌면 목록에 적힌 거리도 전부 옛 값이다.
      unawaited(_refreshReach());
      final destination = _routeDraftDestination;
      if (destination == null) {
        // 아직 도착지가 없다. 여기서 멈추면 사용자는 매장을 눌렀는데 아무 일도
        // 안 일어난 화면을 본다 — 시트의 [_afterOriginPicked]와 같은 규칙으로
        // 길찾기 시트를 다시 열어 도착지 입력을 이어 준다.
        unawaited(_openRouteMode(presetOrigin: picked));
        return;
      }
      unawaited(_startRoute(origin: picked, destination: destination));
      return;
    }

    // 지도 탭도 도착지를 확정하는 경로다. 다른 확정 경로와 같이 상단 초안에
    // 남겨, 출발 위치가 없어 경로가 끊겨도 후보가 사라지지 않게 한다.
    setState(() => _routeDraftDestination = picked);
    unawaited(_startRoute(origin: _selectedOrigin, destination: picked));
  }

  /// 지금 출발↔도착을 맞바꿀 수 있는지(⇅ 버튼 활성 조건).
  ///
  /// 출발지가 "현재 위치"일 때만 조건이 붙는다 — 도착지 자리에는 그 표현이 없어
  /// 가장 가까운 매장으로 굳혀야 하고, 그러려면 [_reachByNodeId]가 있어야 한다.
  ///
  /// 매 프레임 색인을 뒤질 수 없어 **고를 수 있는 상태인지**만 본다. 실제 선택은
  /// [_swapRouteEndpoints]가 하므로 눌렀는데 못 고르는 경우가 남는다.
  bool get _canSwapRouteEndpoints {
    if (_routeDraftDestination == null) return false;
    if (_selectedOrigin != null) return true;
    return (_reachByNodeId?.isNotEmpty ?? false);
  }

  /// 현재 위치에서 가장 가까운 매장을 경로 후보로 만든다. 못 만들면 null.
  ///
  /// 좌표는 매장 색인이 아니라 **그래프 노드**에서 가져온다. [StoreIndexEntry]에는
  /// 좌표가 없고(온디바이스 검색용이라 이름·층·입구 노드만 든다), 어차피 경로가
  /// 이어지는 지점은 매장 중심이 아니라 입구 노드다 — 노드 좌표를 쓰면 계산 전에
  /// 잠깐 뜨는 핀도 실제로 경로가 닿을 자리에 선다.
  Future<DirectionsCandidate?> _nearestStoreAsCandidate({
    String? excludeNodeId,
  }) async {
    final stores = await buildingRepository.getStoreIndex(_buildingId);
    if (!mounted || stores == null || stores.isEmpty) return null;
    final nearest = nearestStoreForCurrentLocation(
      stores: stores,
      reachByNodeId: _reachByNodeId,
      excludeNodeId: excludeNodeId,
    );
    if (nearest == null) return null;

    final graph = await buildingRepository.getBuildingGraph(_buildingId);
    if (!mounted || graph == null) return null;
    final nodeId = nearest.entranceNodeId;
    final node = graph.nodes.where((n) => n.id == nodeId).firstOrNull;
    final lat = node?.lat;
    final lng = node?.lng;
    // 건물에 실측 wgs84 앵커가 없으면 노드에 좌표가 없다(GraphNode.lat 주석).
    // 좌표 없이는 핀도 야외 폴백 경로도 자리를 못 잡으므로 여기서 멈춘다.
    if (lat == null || lng == null) return null;

    return DirectionsCandidate(
      title: nearest.name,
      subtitle: nearest.floorName,
      point: LatLng(lat, lng),
      nodeId: nodeId,
      floor: nearest.floorName,
    );
  }

  /// 도착지가 정해졌을 때 **어떻게 갈지를 먼저 고른다.** [origin]이 null이면
  /// "현재 위치"(=PDR)에서 출발한다.
  ///
  /// [autoSelectMode]가 참이면 목적지 종류를 보고 수단을 정한다 — 사용자가 직접
  /// 고른 경우에는 거짓으로 불러 그 선택을 덮지 않는다.
  ///
  /// [announceOriginAnchor]가 false면 "여기서 출발하는 것으로 봤다" 안내를 띄우지
  /// 않는다(출발↔도착 맞바꾸기처럼 방금 직접 시킨 경우).
  Future<void> _startRoute({
    DirectionsCandidate? origin,
    required DirectionsCandidate destination,
    bool autoSelectMode = true,
    bool announceOriginAnchor = true,
  }) async {
    // 안내가 시작되면 상단 바는 길찾기 두 칸이어야 한다. 매장 시트·검색 결과·
    // 지도 탭처럼 길찾기 바를 거치지 않고 들어오는 경로가 있어서, 여기서 한 번
    // 맞춰 준다 — 안 맞추면 경로는 그려졌는데 상단은 검색창인 화면이 된다.
    _enterRouteModeForGuidance(origin, destination);
    // 최근 목록도 **여기 한 곳에서만** 남긴다. 모든 길찾기가 반드시 이 함수를
    // 지나므로, 시트·검색·지도 탭 어느 문으로 들어와도 빠짐없이 쌓인다.
    // origin이 null이면 "현재 위치"라 남길 지점이 없다([_selectedOrigin] 주석).
    if (origin != null) unawaited(recentRoutePointsController.add(origin));
    unawaited(recentRoutePointsController.add(destination));
    // 건물 안 매장이 목적지면 **도보로 못박는다.** 그 안내는 "문을 경유해
    // 매장까지"라 도보 구간과 실내 구간이 한 몸이고([showOutdoorToIndoorRouteTo]),
    // 자동차로 가면 그 실내 구간이 통째로 사라진다.
    //
    // 자동 선택만 건너뛰면 안 된다. [_travelMode]는 화면에 남는 값이라, 직전에
    // 자동차로 길을 찾아 본 사용자에게는 그 값이 그대로 남아 있고, 그 상태로
    // 건물 안 매장을 고르면 아래 분기가 자동차로 흘려보내 실내 구간이 시작조차
    // 못 한다.
    if (autoSelectMode) {
      final mode = destination.nodeId == null
          ? _defaultTravelMode(origin, destination)
          : RoutePlanMode.walk;
      if (_travelMode != mode) setState(() => _travelMode = mode);
    }
    switch (_travelMode) {
      case RoutePlanMode.transit:
        await _startTransitRoute(origin, destination);
        return;
      case RoutePlanMode.car:
        await _startCarRoute(origin, destination);
        return;
      case RoutePlanMode.walk:
        await _startWalkRoute(
          origin: origin,
          destination: destination,
          announceOriginAnchor: announceOriginAnchor,
        );
    }
  }

  /// 도보 길찾기. **어느 갈래인지는 [classifyWalkRoute]가 정하고, 여기서는 그
  /// 갈래에 맞는 지도 메서드를 부르기만 한다.**
  ///
  /// 판정을 따로 둔 이유는 그 파일에 적었다 — 요약하면 갈래 하나가 빠져 있어도
  /// 화면에는 "경로를 계산할 수 없습니다"만 뜨고, 그게 판정 누락인지 데이터
  /// 문제인지 구분되지 않는다. 판정만 떼면 지도 없이 시험할 수 있다.
  Future<void> _startWalkRoute({
    required DirectionsCandidate? origin,
    required DirectionsCandidate destination,
    required bool announceOriginAnchor,
  }) async {
    final map = _outdoorKey.currentState;
    final kind = classifyWalkRoute(
      origin: origin,
      destination: destination,
      indoorContextActive: _indoorContextActive,
      indoorStartReady:
          indoorNavigationDriver.currentCalibration.canRenderPosition,
    );
    switch (kind) {
      // 화면(탭)을 바꾸지 않고 야외 화면 그대로에 실내 경로를 그린다 — 방금
      // 지정한 위치·매장·경로를 한 시야에서 확인하도록.
      case WalkRouteKind.indoorToIndoor:
        await map?.showIndoorRouteTo(
          _asPoi(destination),
          origin: origin == null ? null : _asPoi(origin),
          announceOriginAnchor: announceOriginAnchor,
          // 실내 위치가 아직 없으면 그 사람은 건물 밖이다. 경로는 그려 주되
          // 현재 위치를 출발지 매장으로 잡지는 않는다 — 시작은 카드의
          // `안내 시작`이 맡는다.
          preview:
              origin != null &&
              !indoorNavigationDriver.currentCalibration.canRenderPosition,
        );

      // 실내 구간까지 미리 풀어 두었다가 건물에 들어가면 이어 붙인다.
      case WalkRouteKind.outdoorToIndoor:
        await map?.showOutdoorToIndoorRouteTo(
          _asPoi(destination),
          origin: origin?.point,
        );

      // 나가는 방향도 실내 구간을 먼저 풀어 두고, 건물을 나가면 야외 경로를
      // 이어 붙인다. origin이 있으면 그 매장에서, 없으면 PDR 앵커에서 출발한다.
      case WalkRouteKind.indoorToOutdoor:
        await map?.showIndoorToOutdoorRouteTo(
          destination.point,
          label: destination.title,
          origin: origin == null ? null : _asPoi(origin),
        );

      case WalkRouteKind.outdoor:
        // 야외 걷기 경로(TMAP)는 출발지도 야외 좌표여야 한다. 실내 지점이
        // 출발지로 남아 있으면(실내에서 "출발지로 설정"한 매장을 그대로 들고
        // 나온 경우) 버리고 GPS 현재 위치에서 시작한다 — 건물 안 좌표를 그대로
        // 보내면 실내 두 지점 사이에 직선이 그려진다.
        // [_dropIndoorOriginIfOutdoors]가 상태도 함께 비우지만, 그 경로를 타지
        // 않은 호출(모드 전환 없이 들어온 경우)에도 같은 규칙이 적용되도록
        // 여기서 한 번 더 막는다.
        final indoorOrigin = origin?.floor != null || origin?.nodeId != null;
        await map?.showRouteTo(
          destination.point,
          label: destination.title,
          origin: indoorOrigin ? null : origin?.point,
        );

      // 층이 다르면 건물 전체 그래프로 층 간 경로(엘리베이터·에스컬레이터
      // 포함)를 계산한다. origin/destination을 다듬지 않고 그대로 넘긴다.
      //
      // 야외 경로(`showRouteTo`)와 **다른 메서드**다. 이름이 비슷하지만 하나는
      // Tmap 보행 경로, 하나는 건물 그래프 탐색이라 인자 타입부터 다르다.
      case WalkRouteKind.indoorFallback:
        await map?.showIndoorRouteTo(
          _asPoi(destination),
          origin: origin == null ? null : _asPoi(origin),
        );
    }
  }

  /// 길찾기 후보를 지도가 받는 형태로 옮긴다.
  ///
  /// 층이 없으면 빈 문자열이다. 실내 갈래로 가는 후보는 [classifyWalkRoute]가
  /// 이미 층·노드를 둘 다 확인했으므로 그쪽에서는 이 폴백이 쓰이지 않는다.
  PoiSearchResult _asPoi(DirectionsCandidate candidate) => PoiSearchResult(
    name: candidate.title,
    floor: candidate.floor ?? '',
    point: candidate.point,
    nodeId: candidate.nodeId,
  );

  /// 저장한 장소 목록을 연다. 항목을 탭하면 목록이 닫히고 상세 시트가 뜬다.
  ///
  /// 상세를 닫아도 목록으로 돌아가지 않는다 — 이유는 [_openCategoryStores]와 같다.
  Future<void> _openFavorites() async {
    await _runSheetChain(() async {
      final picked = await _withMapsLocked(
        () => FavoritesSheet.show(context, onCloseAll: _requestCloseSheetChain),
      );
      if (_closeSheetChainRequested || picked == null || !mounted) return;
      final enriched = await _favoriteWithCategory(picked);
      if (_closeSheetChainRequested || !mounted) return;
      await _showStoreInfo(enriched.toPoiSearchResult(), focusOnMap: true);
    });
  }

  /// 저장된 항목에 카테고리 필드가 비어 있으면(이 필드가 도입되기 전에 저장
  /// 된 경우), 그 매장을 실시간 매장 데이터에서 찾아 category/subcategory를
  /// 채워 넣는다. 이렇게 해야 저장한 장소를 통해 열린 매장 정보 시트에서도
  /// 지도에서 직접 탭한 것과 똑같이 카테고리 chip이 뜬다.
  Future<FavoritePlace> _favoriteWithCategory(FavoritePlace favorite) async {
    if (favorite.category != null) return favorite;
    try {
      final json = await buildingRepository.getFloorGeoJson(
        favorite.buildingId,
        favorite.floor,
      );
      if (json == null) return favorite;
      final plan = FloorPlan.fromJson(json);
      final match = plan.stores.where((s) {
        if (favorite.nodeId != null) return s.entranceNodeId == favorite.nodeId;
        return s.name == favorite.name;
      }).firstOrNull;
      if (match == null || match.category == null) return favorite;
      return favorite.copyWithCategory(
        category: match.category,
        subcategory: match.subcategory,
      );
    } catch (_) {
      // enrich 실패는 표시 품질만 낮출 뿐 흐름을 막지 않는다.
      return favorite;
    }
  }

  /// 상단 바 햄버거 → 앱 메뉴. 시트는 **고른 항목만 돌려주고**, 실제 동작은
  /// 시트가 닫힌 뒤 여기서 실행한다. 시트가 콜백을 직접 들고 실행하면 이미
  /// 닫힌 시트의 `context`로 다음 시트를 띄우게 되고, 그 사이 모드가 바뀌면
  /// 옛 상태에 대고 동작한다.
  Future<void> _onMenuTap() async {
    final action = await _withMapsLocked(
      () => AppMenuSheet.show(
        context,
        // 하단 바의 "위치 지정" 버튼과 같은 조건이다. 건물 밖에서는 지정할
        // 층이 없어 눌러도 아무 일도 일어나지 않는다.
        showPlaceLocation: _outdoorIndoorEntered,
        debugEnabled: debugModeController.enabled,
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case AppMenuAction.favorites:
        await _openFavorites();
      case AppMenuAction.directions:
        await _openRouteMode();
      case AppMenuAction.placeLocation:
        _onPlaceLocation();
      case AppMenuAction.calibrate:
        _onCalibrate();
      case AppMenuAction.debugSettings:
        // 디버그 설정은 메인 지도에서 걷어냈으므로 이 메뉴가 유일한 진입점이다.
        // 시트 안에서 토글하면 지도 두 화면이 전역 컨트롤러의 알림을 받아
        // 알아서 다시 그린다.
        await _withMapsLocked<bool>(() async {
          await showDebugModeSettingsSheet(context, debugModeController);
          return true;
        });
    }
  }

  void _onCalibrate() {
    _outdoorKey.currentState?.recalibrate();
  }

  /// "위치 지정" 버튼(하단 바). 야외 지도에서 실내 진입 오버레이가 켜져 있으면
  /// 그 위에서 앵커 배치를 시작하고, 실내 지도 모드면 IndoorMapBody가 처리한다.
  /// 두 화면 모두 같은 PDR 세션을 사용하므로 어느 쪽에서 지정해도 이후 다른
  /// 쪽에서도 그대로 이어져 보인다.
  void _onPlaceLocation() {
    // 이제부터 지도를 탭해야 하므로 검색 막을 먼저 걷는다.
    _closeSearch();
    _outdoorKey.currentState?.startLocationPlacement();
  }

  @override
  Widget build(BuildContext context) {
    final routeVisible = _outdoorRouteVisible;
    // 시트였을 때는 뒤로가기가 시트만 닫았다. 패널로 바뀌었다고 뒤로가기가
    // 앱을 종료해 버리면 안 되므로, 검색 중에는 pop을 가로채 검색만 닫는다.
    return PopScope(
      canPop: !_searchActive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeSearch();
      },
      child: _buildShell(context, routeVisible),
    );
  }

  /// 화면은 **Stack 다섯 층**이다. 쌓임 순서가 곧 의미다.
  ///
  /// | 층 | 무엇 |
  /// |---|---|
  /// | 1 | 지도([_buildMap]) — 나머지는 전부 이 위에 얹힌다 |
  /// | 2 | 검색 막([_buildSearchBarrier]) — 바깥을 눌러 검색을 닫는 길 |
  /// | 3 | 상단 오버레이([_buildTopOverlays]) — 검색·길찾기·카테고리·배너 |
  /// | 4 | 하단 바([_buildBottomBar]) |
  /// | 5 | 층 전환 스크림([_buildFloorScrim]) — **맨 위여야 한다.** 지도뿐 아니라 검색창·하단 바까지 덮는다 |
  Widget _buildShell(BuildContext context, bool routeVisible) {
    return Scaffold(
      // 상단 검색창(MapTopBar)에 포커스가 들어가 소프트키보드가 올라올 때
      // Scaffold body가 리사이즈되면 그 안의 MapLibre PlatformView(지도)도
      // 함께 줄어들며 리레이아웃이 발생해 모바일에서 화면이 눌리듯 버벅인다.
      // 키보드는 지도 위에 그대로 덮이도록 두어 지도 자체는 리사이즈되지 않게 한다.
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          _buildMap(),
          if (_searchActive) _buildSearchBarrier(),
          _buildTopOverlays(context),
          if (!_guidanceActive) _buildBottomBar(routeVisible),
          _buildFloorScrim(),
        ],
      ),
    );
  }

  /// 1층 — 지도. 이 화면이 지도에 넘기는 콜백이 곧 "셸이 지도에 대해 아는 것"의
  /// 전부다.
  Widget _buildMap() {
    return OutdoorMapBody(
      key: _outdoorKey,
      onRouteVisibleChanged: (visible) =>
          setState(() => _outdoorRouteVisible = visible),
      // 지도가 "안내 종료를 눌렀다"고 알려오는 신호. 경로는 그쪽이 이미
      // 지웠으므로 여기서는 상단 길찾기 상태만 비운다 — 안 비우면 경로만
      // 사라지고 출발/도착 칸이 남아, 안내를 껐는데 화면은 아직 길찾기
      // 중인 상태가 된다.
      onGuidanceDismissed: _forgetRouteDraft,
      onGuidanceActiveChanged: (active) {
        if (_guidanceActive == active) return;
        setState(() => _guidanceActive = active);
        // 안내가 시작되면 검색창이 사라진다. 검색이 열린 채였다면 입력
        // 대상이 없는 결과 패널과 지도를 덮은 막만 남으므로 함께 닫는다.
        if (active) _closeSearch();
      },
      onPlacingLocationChanged: (placing) {
        if (_outdoorPlacingLocation == placing) return;
        setState(() => _outdoorPlacingLocation = placing);
      },
      onIndoorEnteredChanged: (entered) {
        if (_outdoorIndoorEntered == entered) return;
        setState(() {
          _outdoorIndoorEntered = entered;
          // 오버레이가 닫히면 카테고리 칩 줄도 함께 사라진다. 선택만
          // 남겨 두면 사용자가 해제할 수단이 없는 채로, 다시 들어갔을
          // 때 영문 모를 강조가 걸려 있다(홈 탭으로 나갈 때와 같은 이유).
          if (!entered) _categorySelection = null;
        });
        // 오버레이를 닫고 야외로 나온 순간부터는 위치·출발지가 GPS다.
        if (!entered) _dropIndoorOriginIfOutdoors();
        // 실내 컨텍스트가 켜지고 꺼질 때마다 거리 기준이 통째로 바뀐다.
        unawaited(_refreshReach());
      },
      onStoreTap: _onMapStoreTap,
      // 실내 오버레이 위에서도 복도를 골라 출발/도착을 정할 수 있다.
      // 실내 탭과 같은 조작이어야 하므로 같은 값을 내려 준다.
      pickingOnMap: _mapPickTarget != null,
      onMapPointPicked: _onMapPointPicked,
      onLocationAnchored: _onLocationAnchored,
      // 실내 화면과 같은 선택을 넘긴다. 야외 지도도 실내 진입
      // 오버레이가 켜지면 같은 도면을 그리므로, 안 넘기면 칩을
      // 눌러도 강조가 안 뜬다.
      categorySelection: _categorySelection,
      onFloorChanged: _onActiveFloorChanged,
      onFloorTransitionChanged: _onFloorTransitionChanged,
      // 실내 화면과 같은 목록을 넘긴다. 야외 지도도 실내 진입
      // 오버레이가 켜지면 층 선택기·위치 지정을 함께 쓰므로, 상단
      // 검색창이나 하단 바를 누른 탭이 지도 탭으로 새어들어가면
      // 실내 오버레이가 닫히거나 그 자리에 PDR 앵커가 찍힌다.
      outerOverlayKeys: [
        _topBarKey,
        _categoryRowKey,
        _searchPanelKey,
        _bottomBarKey,
        _mapPickHintKey,
      ],
    );
  }

  /// 2층 — 검색 중 지도 전체를 덮는 얇은 막.
  ///
  /// 바깥을 누르면 검색이 닫힌다. 예전 바텀시트의 barrier가 하던 역할이다 —
  /// 이게 없으면 결과 패널이 뜬 채로 지도를 조작하게 되어 상태가 어긋난다.
  Widget _buildSearchBarrier() {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _closeSearch,
        child: ColoredBox(color: Colors.black.withValues(alpha: 0.12)),
      ),
    );
  }

  /// 3층 — 상단 오버레이. 검색창·후보 목록·배너·카테고리가 **하나의 Column**으로
  /// 쌓인다. 고정 offset이던 시절에는 `MapTopBar` 높이가 상태에 따라 달라져
  /// (검색창 한 줄 ↔ 출발/도착 두 줄) 평소엔 여백이 남고 길찾기에서는 칩과 겹쳤다.
  ///
  /// 히트 테스트용 GlobalKey는 그대로다 — localToGlobal은 부모가 무엇이든 같다.
  Widget _buildTopOverlays(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      // 키보드가 올라와도 Scaffold를 리사이즈하지 않으므로
      // (resizeToAvoidBottomInset: false), 여기서 바닥을 직접 올려 검색
      // 패널이 키보드 밑으로 들어가지 않게 한다. 예전에는 상단 바 높이를
      // 상수로 가정해 별도 계산했지만, 이제는 Column의 실제 높이를 쓴다.
      bottom: MediaQuery.viewInsetsOf(context).bottom,
      // 상태 표시줄 여백은 이 Column 전체가 한 번만 먹는다. 예전에는
      // MapTopBar가 자기 안에서 SafeArea를 썼는데, 그 위에 다른 줄(이동
      // 수단)이 오는 순간 둘이 각자 여백을 먹어 간격이 두 배가 된다.
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          // 예전 Positioned가 left·right로 강제하던 폭을 대신한다. 기본값
          // (center)이면 자식이 제 내용 너비로 줄어들어, 검색 패널이 결과
          // 개수에 따라 폭이 들쭉날쭉해진다.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 이동 수단 줄은 **두 칸보다 위**다. "어떻게 갈지"를 먼저 정하고
            // 목적지를 넣는 순서이며, 아래에 두면 두 칸과 후보 목록 사이에
            // 끼어 입력하는 동안 시선을 가로막는다.
            //
            // 안내가 시작되면 접는다. 수단을 고르는 것은 "어떻게 갈지 정하는"
            // 조작이라 이미 그 길을 따라가는 중인 화면에 있을 이유가 없고,
            // 누르면 경로가 통째로 다시 계산돼 따라가던 안내가 끊긴다.
            // 하단 바(아래)·카테고리 줄과 같은 규칙이다.
            if (_routeMode && !_guidanceActive) _buildTravelModeBar(),
            _buildTopBar(),
            // 길찾기 두 칸 중 하나를 치는 중이면 그 후보 목록이 이 자리를
            // 쓴다. 일반 검색 패널·카테고리 열과 자리를 다투므로 셋 중
            // 하나만 뜬다.
            if (_routeEditingField case final field?)
              _buildRouteFieldResults(field),
            // 층 전환 배너는 고정 top 숫자가 아니라 **이 Column 흐름**에
            // 놓는다. 상단 바 높이는 상태마다 달라지므로(검색 한 줄 ↔
            // 출발/도착 두 줄), 상수로 잡으면 어느 한쪽에서 반드시 겹친다.
            //
            // 스크림이 올라온 구간에서는 배너를 접는다. 스크림 카드가 같은
            // 사실을 화면 한가운데에서 더 크게 말하고 있어서, 둘을 같이
            // 띄우면 같은 내용이 두 벌로 보인다(배너는 스크림 **아래** 층에
            // 깔리므로 흐려지기까지 한다).
            if (_floorTransition case final transition?
                when _floorScrimOpacity <= 0)
              _buildFloorTransitionBanner(transition),
            // 결과 패널과 카테고리 열은 같은 자리를 쓴다. 검색 중에는
            // 카테고리 열을 접어 두 오버레이가 겹치지 않게 한다.
            if (_searchActive)
              _buildSearchPanel()
            // 층 전환 중에는 카테고리 줄을 접는다. 배너가 상단 바 바로
            // 아래에 오도록 자리를 비우는 것이고, 전환은 몇 초짜리 상태다.
            // 안내 중에도 접는다. 칩을 누르면 매장 목록 시트가 올라오는데,
            // 그건 "어디 갈지 고르는" 조작이라 목적지가 이미 정해진 화면에
            // 있을 이유가 없다.
            else if (_floorTransition != null || _guidanceActive)
              const SizedBox.shrink()
            // 길찾기 draft에서는 **접지 않고 내려온다.** 상단 바가 출발/도착
            // 두 줄로 커지면 이 Column이 그만큼 아래로 밀어 주므로 겹치지
            // 않는다. 한때 접어 뒀지만, 도착지를 정한 뒤에도 "그럼 저긴
            // 뭐였지" 하고 카테고리를 다시 훑는 흐름이 끊겼다.
            else
              _buildCategoryRow(),
            // 지도에서 고르는 중이라는 안내. 이게 없으면 "지도에서 선택"을
            // 눌렀을 때 시트만 닫히고 아무 일도 안 일어난 것처럼 보인다.
            if (_mapPickTarget != null && !_searchActive) _buildMapPickHint(),
          ],
        ),
      ),
    );
  }

  /// 이동 수단 줄(도보·자동차·대중교통).
  Widget _buildTravelModeBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: TravelModeBar(
        key: _travelModeBarKey,
        selected: _travelMode,
        modes: _availableTravelModes,
        onSelected: (mode) => unawaited(_onTravelModePicked(mode)),
      ),
    );
  }

  /// 검색창, 또는 길찾기 draft에서는 출발/도착 두 칸.
  Widget _buildTopBar() {
    return MapTopBar(
      key: _topBarKey,
      onMenuTap: _onMenuTap,
      controller: _searchController,
      focusNode: _searchFocus,
      onChanged: _onSearchChanged,
      onSubmitted: _onSearchSubmitted,
      searchActive: _searchActive,
      onCancelSearch: _closeSearch,
      onDirectionsTap: () => unawaited(_openRouteMode()),
      routeMode: _routeMode,
      originController: _routeOriginController,
      destinationController: _routeDestinationController,
      originFocus: _routeOriginFocus,
      destinationFocus: _routeDestinationFocus,
      onOriginChanged: (value) =>
          _onRouteFieldChanged(RoutePlanField.origin, value),
      onDestinationChanged: (value) =>
          _onRouteFieldChanged(RoutePlanField.destination, value),
      onClearRouteDraft: _clearRouteDraft,
      onSwapRouteEndpoints: () => unawaited(_swapRouteEndpoints()),
      canSwapRouteEndpoints: _canSwapRouteEndpoints,
    );
  }

  /// 길찾기 두 칸 중 지금 치고 있는 칸의 후보 목록.
  Widget _buildRouteFieldResults(RoutePlanField field) {
    return Flexible(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, _overlayGap, 12, 12),
        child: RouteFieldResults(
          key: _routeResultsKey,
          field: field,
          results: _routeResults,
          // 아직 아무것도 안 친 상태에서는 진행 표시를 하지 않는다.
          // 밖에서 빈 검색어는 결과가 없는 것이 정상이라
          // ([searchDirectionsCandidates]) 스피너가 떴다가 곧바로
          // 빈 화면으로 바뀌는 깜빡임만 남는다.
          searching: _routeSearching && _routeQuery.isNotEmpty,
          onPicked: _pickRouteCandidate,
          // 상단 검색 결과와 **같은 계산 결과**를 넘긴다. 두
          // 화면이 같은 매장에 다른 거리를 적으면 어느 쪽도 못
          // 믿게 된다.
          reachByNodeId: _reachByNodeId,
          suggestions: _routeSuggestions,
          onSuggestionPicked: _onRouteSuggestionPicked,
          onPickOnMap: () => _pickRouteEndpointOnMap(field),
          // 야외 지도에서 누르면 이름 없는 좌표가 잡힌다. 도면을
          // 보고 있을 때만 매장(층·노드)이 잡히므로 그때만 준다.
          showPickOnMap: _indoorContextActive,
          onCurrentLocation: _pickCurrentLocationAsOrigin,
        ),
      ),
    );
  }

  /// 층 전환 배너. 전환 중에는 아래 카테고리 줄을 접어 자리를 보장한다.
  Widget _buildFloorTransitionBanner(FloorTransitionUiState transition) {
    return Padding(
      padding: const EdgeInsets.only(top: _overlayGap),
      child: Center(child: FloorTransitionBanner(state: transition)),
    );
  }

  /// 검색 결과 패널.
  Widget _buildSearchPanel() {
    return Flexible(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, _overlayGap, 12, 12),
        child: SearchPanel(
          key: _searchPanelKey,
          buildingId: _buildingId,
          query: _searchQuery,
          submitTick: _searchSubmitTick,
          onStorePicked: _onSearchStorePicked,
          onBuildingPicked: _onSearchBuildingPicked,
          onQueryPicked: _onSearchQueryPicked,
          onSuggestionPicked: _onSearchSuggestionPicked,
          indoorContextActive: _indoorContextActive,
          currentFloorId: _activeIndoorFloor,
          reachByNodeId: _reachByNodeId,
          // 검색을 시작한 순간 지도에서 받아 둔 기준점. 위치도
          // 카메라도 못 잡았으면 null이라 바깥 검색이 돌지 않는다.
          outdoorSearchCenter: _outdoorSearchCenter,
          onOutdoorPoiPicked: (poi) => unawaited(_onSearchPoiPicked(poi)),
          // 같은 가게가 두 줄로 뜨지 않게 하는 판정. 야외 지도가
          // 외곽선을 들고 있으므로 그쪽에 묻는다.
          isInsideIndoorBuilding: (point) =>
              _outdoorKey.currentState?.isAtIndoorBuilding(point) ?? false,
          // "찾지 못했어요" 화면의 탈출구. 지도 위 chip 줄과 **같은
          // Future**를 넘긴다 — 다시 요청하면 같은 정보를 두 번
          // 받게 되고, 두 화면의 카테고리 목록이 어긋날 수 있다.
          categoryEntries: _categoryEntriesFuture,
          onCategoryPicked: _onSearchCategoryPicked,
        ),
      ),
    );
  }

  /// 지도 위 카테고리 칩 줄.
  ///
  /// 지도 위에는 **대분류 한 줄만** 둔다. 소분류는 chip을 누르면 바로 올라오는
  /// 매장 목록 시트 안으로 옮겼다 — 시트가 곧장 뜨는 마당에 같은 pill 줄을
  /// 지도에도 그리면 화면에 같은 조작이 두 벌 남는다.
  Widget _buildCategoryRow() {
    return Padding(
      padding: const EdgeInsets.only(top: _overlayGap),
      child: MapOverlayScrollRow(
        key: _categoryRowKey,
        onPointerOverChanged: (over) => over
            ? _lockMaps(_mapLockOverlayHover)
            : _unlockMaps(_mapLockOverlayHover),
        onPointerDownChanged: (down) => down
            ? _lockMaps(_mapLockOverlayTouch)
            : _unlockMaps(_mapLockOverlayTouch),
        children: [
          // 카테고리 필터는 모드가 아니라 [_indoorContextActive]로 가른다 —
          // 야외 탭이어도 오버레이가 켜지면 도면과 강조가 이미 떠 있다. 순수
          // 야외에서는 감춘다(강조가 도면 위에 그려져 결과가 안 보인다).
          if (_indoorContextActive) ...[
            CategoryChipsRow(
              entriesFuture: _categoryEntriesFuture,
              selection: _categorySelection,
              onSelectionChanged: _onCategoryChipTapped,
              onRetry: _reloadCategoryEntries,
            ),
          ],
        ],
      ),
    );
  }

  /// 지도에서 고르는 중이라는 안내.
  ///
  /// 이게 없으면 "지도에서 선택"을 눌렀을 때 시트만 닫히고 아무 일도 안 일어난
  /// 것처럼 보인다.
  Widget _buildMapPickHint() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, _overlayGap, 12, 0),
      child: MapPickHintCard(
        key: _mapPickHintKey,
        target: _mapPickTarget!,
        // 지금 고르는 칸의 **반대쪽**을 보여준다. 출발지를 고르는
        // 중이면 도착지가, 도착지를 고르는 중이면 출발지가 무엇으로
        // 잡혀 있는지 알아야 지금 무엇을 누를지 판단할 수 있다.
        counterpartLabel: _mapPickTarget == DirectionsMapPickTarget.origin
            ? _routeDraftDestination?.title
            : (_selectedOrigin?.title ?? '현재 위치'),
        onCancel: _stopPickingOnMap,
      ),
    );
  }

  /// 4층 — 하단 바.
  ///
  /// 안내 중에는 아예 그리지 않는다([_buildShell]이 걸러낸다). 두 버튼
  /// ("위치 지정"·"위치 보정") 모두 안내를 시작하기 **전에** 출발점을 잡는
  /// 조작이라, 이미 경로를 따라가는 중에는 쓸 일이 없다. 접히면 리프트도
  /// 의미가 없으므로 [routeVisible] 분기는 접히지 않은 자동 안내에서만 남는다.
  Widget _buildBottomBar(bool routeVisible) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      left: 0,
      right: 0,
      bottom: routeVisible ? _etaBarLiftHeight : 0,
      child: MapBottomBar(
        key: _bottomBarKey,
        onCalibrate: _onCalibrate,
        onPlaceLocation: _onPlaceLocation,
        placingLocation: _outdoorPlacingLocation,
        // 야외에서는 실내 진입 오버레이가 켜져 있을 때만 위치 지정
        // 버튼을 노출한다. 오버레이가 꺼진 순수 야외 상태에서는 지정할
        // 층 정보가 없어 눌러도 의미가 없다.
        showPlaceLocation: _outdoorIndoorEntered,
      ),
    );
  }

  /// 5층 — 층 전환 스크림.
  ///
  /// root Stack의 **마지막** 레이어라 지도뿐 아니라 검색창·카테고리·하단 바까지
  /// 함께 덮는다. 탑승이 잡힌 순간부터 하차까지 덮으며, 그동안 뒤쪽 입력을
  /// 막는다 — 걸음이 멈춰 있어 지도에서 할 수 있는 일도 없는 구간이다.
  Widget _buildFloorScrim() {
    return Positioned.fill(
      child: FloorTransitionScrim(
        opacity: _floorScrimOpacity,
        fadeIn: floorTransitionScrimFadeIn,
        fadeOut: floorTransitionScrimFadeOut,
        state: _floorTransition,
      ),
    );
  }
}
