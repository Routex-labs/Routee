import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/api_config.dart';
import '../../core/startup_loading_timing.dart';
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
import '../../widgets/sheet_stack_guard.dart';
import '../../widgets/startup_loading_overlay.dart';
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
import '../../domain/category/category_taxonomy.dart';
import '../../map/style/category_map_filter.dart';
import 'widgets/sheets/category_stores_sheet.dart';
import 'widgets/sheets/events_sheet.dart';
import '../../domain/event/building_events.dart';
import '../../domain/floor/floor_concept_photo.dart';
import 'widgets/sheets/facility_filter_sheet.dart';
import '../../models/route/directions_candidate.dart';
import 'widgets/sheets/favorites_sheet.dart';
import 'widgets/chrome/floor_transition_overlay.dart';
import 'widgets/chrome/map_bottom_bar.dart';
import 'widgets/chrome/map_top_bar.dart';
import 'widgets/sheets/building_info_sheet.dart';
import 'widgets/sheets/outdoor_poi_sheet.dart';
import 'widgets/sheets/place_detail_sheet.dart';
import 'widgets/search/route_field_results.dart';
import '../../models/route/route_plan_mode.dart';
import 'widgets/search/search_panel.dart';
import 'widgets/sheets/transit_routes_sheet.dart';
import 'widgets/chrome/category_chips_row.dart';
import 'widgets/chrome/map_overlay_scroll_row.dart';
import 'widgets/chrome/issue_diary_panel.dart';
import 'widgets/chrome/map_tab_bar.dart';
import 'widgets/sheets/today_events.dart';
import 'widgets/sheets/event_poster_view.dart';
import '../outdoor_map/outdoor_map_screen.dart';
import 'directions_candidates.dart';
import 'transit_walk_handoff.dart';
import 'walk_route_kind.dart';

part 'parts/search.dart';
part 'parts/category.dart';
part 'parts/sheets.dart';
part 'parts/route_plan.dart';
part 'parts/route_start.dart';
part 'parts/transit.dart';
part 'parts/bottom_bar.dart';

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

/// 이 앱이 다루는 건물. 한동안 햄버거 버튼이 "건물 선택 (테스트)" 시트를 열어
/// 백엔드에 적재된 건물 목록에서 바꿀 수 있었지만, 데모용 전환 수단이었고
/// 실제 사용 흐름에는 없는 조작이라 걷어냈다. 여러 건물을 실제로 다루게 되면
/// 그때는 시트가 아니라 지도에서 건물을 골라 들어오는 흐름이어야 한다.
const _buildingId = demoBuildingId;

/// 바텀시트·검색 패널이 지도 위에 떠 있는 동안.
const _mapLockSheet = 'sheet';
const _mapLockSearch = 'search';

/// 지도 위 오버레이(장소 pill·카테고리 chip 열) 위에 포인터가 올라와 있는 동안.
/// 마우스(hover)와 터치(pointer down)는 끝나는 시점이 달라 따로 센다.
const _mapLockOverlayHover = 'overlay-hover';
const _mapLockOverlayTouch = 'overlay-touch';

class _MapShellScreenState extends State<MapShellScreen> {
  /// 첫 좌표 판정과 카메라 이동이 끝날 때까지 서울시청 fallback 지도를 가린다.
  /// 위치 서비스가 응답하지 않아도 앱이 영구히 막히지 않도록 타임아웃을 둔다.
  bool _startupLoading = true;
  bool _startupMinimumElapsed = false;
  bool _startupPreparationReady = false;
  Timer? _startupMinimumTimer;
  Timer? _startupLoadingTimeout;

  /// 상단 오버레이 사이 간격. 예전 top: 78 / top: 128 같은 고정 offset을
  /// 대신하는 유일한 값이다. 상단 바 높이가 상태에 따라 달라져도 이 간격은
  /// 그대로라 어느 모드에서든 같은 여백으로 보인다.
  static const _overlayGap = RoutexSpacing.controlGap;

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
  final _activeFloorNotifier = ValueNotifier<String?>(null);

  /// 떠 있는 시트도 층을 봐야 한다. 시설 필터 시트의 제목("1F 편의시설")이
  /// 그렇다 — 시트가 뜬 뒤에도 층 선택기는 그대로 눌리므로, 값으로 넘기면
  /// 제목이 옛 층에 머문다. 상태를 두 벌로 두지 않으려고 이 화면이 읽는 쪽도
  /// 같은 notifier를 지난다.
  String? get _activeFloorLabel => _activeFloorNotifier.value;

  /// 건물의 (층·대분류·소분류)별 매장 수. pill 목록과 개수 안내가 같은 데이터를
  /// 봐야 하므로 화면 하나가 소유하고 아래로 내려 준다.
  ///
  /// **요청 하나다.** 예전에는 같은 정보를 얻으려고 층 지도를 층마다 받아
  /// (더현대 서울 기준 12건) 매장을 직접 셌다. 매장 폴리곤·좌표·그래프까지
  /// 따라오는 응답이라, 세 문자열과 개수를 얻는 값으로는 너무 비쌌다.
  late Future<List<_CategoryEntry>> _categoryEntriesFuture =
      _loadCategoryEntries();

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
    final photos = banner == null
        ? const <String>[]
        : floorConceptPhotos(banner.toFloorLabel);
    // **탑승이 잡힌 순간 미리 굽는다.** 덮개가 짙어지는 그 프레임은 도면을 갈아
    // 끼우는 중이라 이미 제일 바쁘다 — 그때 사진을 처음 디코드하면 거기서 한 번
    // 끊기고, 하필 사용자가 화면을 볼 수밖에 없는 구간이다.
    //
    // 뒷장까지 함께 굽는다. 첫 장만 구우면 사람이 곧바로 넘겼을 때 빈 칸이
    // 지나간다 — 자동 넘김은 2초 뒤지만 손은 그보다 빠르다.
    if (!listEquals(photos, _floorTransitionPhotos)) {
      for (final photo in photos) {
        unawaited(precacheImage(AssetImage(photo), context));
      }
    }
    setState(() {
      _floorTransition = banner;
      _floorTransitionPhotos = photos;
      _floorScrimOpacity = scrimOpacity;
    });
  }

  /// 시설 시트가 덮는 높이(논리 px). 층 선택기와 하단 바를 그만큼 밀어 올린다.
  ///
  /// 시트가 **높이를 비율로 고정하기 때문에** 계산이 성립한다
  /// ([kFacilitySheetHeightFraction]) — 줄 수에 따라 늘었다 줄면 여기서 알 수 없다.
  double _facilitiesSheetLiftPx(BuildContext context) => _facilitiesSheetOpen
      ? MediaQuery.sizeOf(context).height * kFacilitySheetHeightFraction
      : 0;

  /// 시설 필터 시트가 지금 떠 있는지. 층 선택기 위 버튼을 켜진 상태로 그리는
  /// 데 쓰고, 같은 버튼을 두 번 눌러 시트가 겹치는 것도 이 값으로 막는다.
  bool _facilitiesSheetOpen = false;

  /// 지금 떠 있는 카테고리 목록 시트가 닫히면 완료되는 Future. 안 떠 있으면 null.
  /// 상세 시트의 [_placeDetailClosing]과 같은 역할이다.
  Future<PoiSearchResult?>? _categorySheetClosing;

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

  /// 덮개에 깔 도착 층 사진들. 층 라벨에서 나오므로 상태로 들고 있을 필요는
  /// 없지만, **미리 굽는 시점**을 알려면 바뀌는 순간을 잡아야 한다.
  List<String> _floorTransitionPhotos = const [];

  /// 실내↔야외 전환 덮개의 불투명도. 지도가 알려 온다
  /// ([OutdoorMapBody.onIndoorTransitionVeilChanged]).
  double _indoorVeilOpacity = 0;

  /// 전환 연출이 화면을 덮고 있는지. 참이면 셸 chrome(검색창·길찾기 바·카테고리
  /// 줄·하단 바·탭 줄)을 트리에서 뺀다.
  ///
  /// 덮개가 둘이다 — 층 전환 스크림과 실내↔야외 전환 덮개. **둘 다 지도 안에서
  /// 그린다.** 셸 chrome은 그 지도의 형제라 z축으로는 이길 수 없어서, 덮는
  /// 동안에는 아예 그리지 않는 것으로 가린다.
  ///
  /// **맨 위에 두는 것만으로는 부족하다.** 페이드가 오르내리는 동안 덮개는
  /// 반투명이라 그 구간 내내 chrome이 비쳐 보인다 — 연출이 "덮었다"고 말하는
  /// 동안 화면은 아직 덮이지 않은 셈이다. 0보다 크면 곧 덮이거나 덮여 있는
  /// 것이므로, 그 순간부터 아예 그리지 않는다.
  bool get _floorTransitionCovers =>
      _floorScrimOpacity > 0 || _indoorVeilOpacity > 0;

  void _onIndoorTransitionVeilChanged(double opacity) {
    if (!mounted || _indoorVeilOpacity == opacity) return;
    // 덮개가 오르기 시작하면 검색은 접는다. 패널은 상단을 통째로 차지해, 트리에
    // 남겨 두면 덮개가 걷힌 뒤에도 키보드가 올라온 채로 돌아온다.
    if (opacity > 0 && _searchActive) _closeSearch();
    setState(() => _indoorVeilOpacity = opacity);
  }

  // 지도 위에 얹은 공용 오버레이(검색창·카테고리 줄·하단 바)의 영역을
  // IndoorMapBody가 map click 처리에서 제외할 수 있게 넘겨줄 key들.
  // MapLibre PlatformView가 gesture arena를 우회해서 오버레이 탭이 뒤의 매장
  // 까지 새어들어가는 문제를 여기서 함께 막는다.
  final _topBarKey = GlobalKey();
  final _categoryRowKey = GlobalKey();
  final _bottomBarKey = GlobalKey();

  /// 하단 이슈 다이어리 판. **[outerOverlayKeys]에 반드시 들어가야 한다** — 안
  /// 넣으면 판을 미는 손가락이 지도 탭으로 새어들어가 실내 오버레이가 닫히거나 그
  /// 자리에 PDR 앵커가 찍힌다.
  final _issueDiaryKey = GlobalKey();

  /// 맨 아래 탭 줄. 판과 같은 이유로 [outerOverlayKeys]에 들어간다.
  final _tabBarKey = GlobalKey();

  /// 사용자가 이슈 다이어리 판을 끌어내려 치웠는지. **건물을 나갔다 들어오면
  /// 풀린다** — 치운 것은 "지금 이 화면에서 비켜라"였지 "다시는 보지 말자"가
  /// 아니다.
  bool _issueDiaryDismissed = false;
  final _searchPanelKey = GlobalKey();

  /// "지도에서 도착지를 골라주세요" 안내. 이 카드의 X를 누른 탭이 지도까지
  /// 새어들어가면, 취소를 누른 손가락이 그 아래 매장을 도착지로 지정해 버린다.

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

  /// 지금 치고 있는 칸에 보여 줄 후보들.
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

  /// 후보 조회 디바운스. 글자마다 서버를 때리지 않게 잠깐 모았다 보낸다 —
  /// 상단 검색창과 **같은 리듬**이어야 같은 검색어가 어디에 치느냐에 따라
  /// 요청 수가 달라지지 않는다(`SearchPanel._lightDebounce`).
  static const _routeSearchDebounceDelay = Duration(milliseconds: 300);
  Timer? _routeSearchDebounce;

  /// 후보 조회 순번. 빠르게 타이핑하면 요청이 겹치는데, 늦게 도착한 옛 응답이
  /// 새 결과를 덮으면 목록이 방금 친 글자와 무관한 것을 보여 준다.
  int _routeSearchSeq = 0;

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

  /// 마지막으로 띄운 대중교통 후보 목록. **이미 고른 `대중교통` 칩을 다시
  /// 누르면 이것을 다시 연다**([_onTravelModePicked]).
  ///
  /// 조회 당시의 출발 좌표까지 함께 든다 — 다시 고른 경로의 앞뒤 도보를 그때와
  /// 같은 지점에서 채워야 지도에 그려지는 선이 목록과 어긋나지 않는다.
  ///
  /// 길찾기가 끝나면 반드시 비운다([_forgetRouteDraft]). 안 비우면 다른 곳으로
  /// 가는 안내 중에 뒤로가기를 눌러 **예전 목적지의 후보 목록**이 뜬다.
  ({TransitRoutes routes, DirectionsCandidate destination, LatLng origin})?
  _lastTransitQuery;

  /// 후보 목록 시트가 지금 떠 있는지. 야외 지도에 넘겨 그동안 대중교통 요약
  /// 카드를 접는다([OutdoorMapBody.transitRoutesSheetOpen]).
  ///
  /// 켜고 끄는 자리는 [_pickTransitRoute] 하나뿐이고 `finally`가 끈다 — 고르든
  /// 안 고르든, 예외로 빠져나가든 카드는 반드시 돌아온다.
  var _transitRoutesSheetOpen = false;

  /// 이번 조회에서 이미 받아 온 도보 구간. **같은 두 지점을 두 번 부르지
  /// 않는다** — 목록에서 부른 (마지막 하차 → 목적지)를 후보를 고를 때마다
  /// 그대로 다시 불러 TMAP 할당량을 선택당 1건씩 먹었다.
  ///
  /// 키가 스스로를 밝히므로(양 끝 좌표를 1m로 반올림) 적중은 곧 같은 요청이고,
  /// 실패(null)도 담는다 — 재시도가 아끼려던 그 호출이다. 조회를 새로 시작할
  /// 때 통째로 버린다([_withListWalkLegs]).
  final _transitWalks = <TransitWalkGap, DirectionsRoute?>{};

  /// 이 화면이 사는 동안 실제로 나간 보행자 경로 요청 수. **적중을 뺀 진짜
  /// 호출**이라 메모 크기로는 못 센다 — 같은 키에 두 번 써도 크기는 안 자란다.
  var _transitWalkCalls = 0;

  final _routeResultsKey = GlobalKey();

  /// 건물 밖 장소를 함께 찾을 기준점. 검색을 시작할 때 야외 지도에서 한 번
  /// 받아 둔다([_activateSearch]).
  ///
  /// **매 build마다 지도에서 읽지 않는다.** 지도 상태를 GlobalKey로 읽는 건
  /// build 중에 하기 나쁜 일이고(레이아웃 전에는 카메라가 없다), 검색 한 번
  /// 도중에 기준점이 흔들리면 같은 검색어의 결과가 타이핑 중에 바뀐다.
  LatLng? _outdoorSearchCenter;

  /// 시트 X 버튼이 눌리면 true가 된다. 시트 체인의 어떤 시점에서든 이 값이
  /// true면 부모 loop(_openFavorites, _openCategoryStores, _showStoreInfo)는
  /// 이전 시트를 다시 열지 않고 즉시 종료해서 전체 chain이 한 번에 닫힌다.
  /// 최상위 호출자가 값을 consume한 뒤 반드시 false로 되돌린다.
  bool _closeSheetChainRequested = false;

  // 아래 넷은 `addListener`/`removeListener` 짝이라 **본체에 남는다.** extension
  // 메서드는 참조할 때마다 새 클로저가 되어, part로 옮기면 remove가 아무것도
  // 지우지 못한다 — 죽은 화면이 수신함을 계속 듣는다
  // (`test/screens/map_shell/place_link_cold_start_test.dart`).

  /// 검색창에 포커스가 들어오면 그 자리에서 검색을 시작한다. 예전에는 탭이
  /// 아래에서 시트를 올렸고, 그 시트 안에 입력창이 하나 더 있었다 — 사용자가
  /// 방금 누른 창과 실제로 치는 창이 달라 검색창이 두 개인 것처럼 보였다.
  void _onSearchFocusChanged() {
    if (_searchFocus.hasFocus) _activateSearch();
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

  void _onPlaceLinkChanged() {
    final link = placeLinkInbox.value;
    if (link == null) return;
    placeLinkInbox.take();
    unawaited(_openPlaceFromLink(link));
  }

  /// 오늘 이 건물에서 열리는 행사. 상세 시트의 제목·카드가 이걸 본다
  /// ([_targetFor]). 실패하면 null로 남고 화면은 행사가 없던 때와 같아진다.
  BuildingEvents? _buildingEvents;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBuildingEvents());
    // 시트가 뜨고 지는 것을 판이 알아야 한다([_issueDiaryVisible]).
    sheetStackGuard.openSheets.addListener(_onSheetCountChanged);
    _searchFocus.addListener(_onSearchFocusChanged);
    _routeOriginFocus.addListener(_onRouteOriginFocusChanged);
    _routeDestinationFocus.addListener(_onRouteDestinationFocusChanged);
    _requestStartupPermissions();
    _startupMinimumTimer = Timer(startupLoadingMinimum, () {
      if (!mounted) return;
      _startupMinimumElapsed = true;
      _tryFinishStartupLoading();
    });
    _startupLoadingTimeout = Timer(startupLoadingFailureTimeout, () {
      if (!mounted) return;
      _startupMinimumElapsed = true;
      _startupPreparationReady = true;
      _tryFinishStartupLoading();
    });
    // 화면이 세워지기 전에 도착한 링크가 여기 남아 있을 수 있다(cold start).
    //
    // **첫 프레임 뒤에 꺼낸다.** 실패 안내가 토스트라 Overlay와 MediaQuery를
    // 건드리는데, 다른 건물을 가리키는 링크는 네트워크를 타지 않고 **동기로**
    // 그 실패 경로에 닿는다. initState 안에서 부르면 그 자리에서 프레임이
    // 깨진다(`test/screens/map_shell/place_link_cold_start_test.dart`).
    placeLinkInbox.addListener(_onPlaceLinkChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onPlaceLinkChanged();
    });
  }

  /// 시트가 뜨고 지면 판의 노출 조건이 바뀐다([_issueDiaryVisible]).
  void _onSheetCountChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _startupMinimumTimer?.cancel();
    _startupLoadingTimeout?.cancel();
    placeLinkInbox.removeListener(_onPlaceLinkChanged);
    sheetStackGuard.openSheets.removeListener(_onSheetCountChanged);
    _searchFocus.removeListener(_onSearchFocusChanged);
    _searchFocus.dispose();
    _searchController.dispose();
    _routeOriginFocus.removeListener(_onRouteOriginFocusChanged);
    _routeDestinationFocus.removeListener(_onRouteDestinationFocusChanged);
    _routeOriginFocus.dispose();
    _routeDestinationFocus.dispose();
    _routeOriginController.dispose();
    _routeDestinationController.dispose();
    _activeFloorNotifier.dispose();
    _placeLocationAttentionTimer?.cancel();
    _routeSearchDebounce?.cancel();
    super.dispose();
  }

  void _finishStartupLoading() {
    _startupPreparationReady = true;
    _tryFinishStartupLoading();
  }

  void _tryFinishStartupLoading() {
    if (!_startupLoading) return;
    if (!_startupMinimumElapsed || !_startupPreparationReady) return;
    _startupMinimumTimer?.cancel();
    _startupMinimumTimer = null;
    _startupLoadingTimeout?.cancel();
    _startupLoadingTimeout = null;
    setState(() => _startupLoading = false);
  }

  /// 시작 덮개가 이 요청 중의 지도는 가리지만, 덮개의 완료 조건을 권한 응답과
  /// 직접 묶지는 않는다. 시스템 창을 오래 열어 둬도 타임아웃으로 앱에 들어갈 수
  /// 있어야 하고, 거부된 권한은 지도 위의 짧은 안내로 따로 알린다.
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

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 근처 매장 목록에서 자기 자신을 빼려면 지금 열려 있는 매장 id가 필요하다.
  /// 시트가 인자로 넘기지 않는 이유는, 이 화면이 어차피 시트를 띄우면서 그 id를
  /// 이미 알고 있기 때문이다.
  String? _nearbyOriginPlaceId;

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

  /// "위치 지정" 버튼을 지금 깜빡이는 중인지.
  bool _placeLocationAttention = false;
  Timer? _placeLocationAttentionTimer;

  @override
  Widget build(BuildContext context) {
    final routeVisible = _outdoorRouteVisible;
    // 시트였을 때는 뒤로가기가 시트만 닫았다. 패널로 바뀌었다고 뒤로가기가
    // 앱을 종료해 버리면 안 되므로, 열려 있는 것을 한 겹씩 벗긴다. 경로가
    // 그려진 채로 pop시키면 앱이 통째로 종료된다 — 대중교통 경로를 고른 뒤
    // 뒤로가기를 눌러 앱이 꺼지던 것이 그 경우다. 어떤 상태에서 무엇이
    // 벗겨지는지는 `test/screens/map_shell/back_steps_out_of_route_test.dart`.
    return PopScope(
      // 마지막 겹에서도 그냥 pop시키지 않는다. 아무것도 안 열린 화면의
      // 뒤로가기는 종료 확인을 거쳐야 해서, pop을 여기서 가로채야 한다.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // 검색이 먼저다. 둘 다 살아 있으면 한 번에 한 겹만 벗긴다.
        if (_searchActive) {
          _closeSearch();
          return;
        }
        // 안내를 끄는 것과 경로를 지우는 것은 **다른 사건이다.** 안내 한 겹만
        // 벗겨 이동 수단을 다시 고를 수 있는 계획 화면으로 되돌린다.
        //
        // **여기서 대중교통 후보 목록을 다시 열지 않는다.** 그 목록은 modal
        // 시트라, 열리는 순간 뒤에 펴진 수단 줄이 보이기만 하고 안 눌린다
        // (barrier가 먼저 먹고 시트를 닫는다). 목록으로 가는 문은 그 수단
        // 줄의 `대중교통`을 다시 누르는 것이다([_onTravelModePicked]).
        if (_guidanceActive) {
          _outdoorKey.currentState?.stopGuidanceKeepingRoute();
          return;
        }
        // 그린 것과 찾던 것도 **다른 사건이다.** 지도의 선만 걷어내고 출발·도착은
        // 남긴다 — 목적지는 그대로인데 경로까지 지우면 다시 쳐야 한다. 보관한
        // 대중교통 조회도 그래서 남긴다(출발·도착이 그대로라 아직 유효하다).
        if (routeVisible) {
          _outdoorKey.currentState?.clearAllRoutes();
          return;
        }
        // 남은 길찾기 바를 접어 검색창으로 되돌린다. 위 겹과 합치면 상단 X의
        // 정리([_clearRouteDraft])와 같아, 종료 동작이 두 벌이 되지 않는다.
        if (_routeMode) {
          _forgetRouteDraft();
          return;
        }
        // 다 벗겼다. 여기서 그냥 나가면 지도만 보다 한 번 잘못 누른 사람이
        // 앱 밖으로 튕긴다. `confirmLabel`이 붙은 dialog는 바깥 누르기로도 안
        // 닫혀, 나가는 길이 "종료"를 누르는 것 하나가 된다.
        unawaited(
          showRoutexDialog(
            context: context,
            dialog: RoutexDialog(
              title: '앱을 종료할까요?',
              confirmLabel: '종료',
              closeLabel: '취소',
              onConfirm: SystemNavigator.pop,
            ),
          ),
        );
      },
      child: _buildShell(context, routeVisible),
    );
  }

  /// 화면은 **Stack 여섯 층**이다. 쌓임 순서가 곧 의미다.
  ///
  /// | 층 | 무엇 |
  /// |---|---|
  /// | 1 | 지도([_buildMap]) — 나머지는 전부 이 위에 얹힌다 |
  /// | 2 | 검색 막([_buildSearchBarrier]) — 바깥을 눌러 검색을 닫는 길 |
  /// | 3 | 상단 오버레이([_buildTopOverlays]) — 검색·길찾기·카테고리·배너 |
  /// | 4 | 하단 바([_buildBottomBar]) — 조작 버튼과 이슈 다이어리 판 |
  /// | 4.5 | 탭 줄([_buildTabBar]) — **바닥에 고정**. 위 것들이 이만큼 띄운다 |
  /// | 5 | 층 전환 스크림([_buildFloorScrim]) — **맨 위여야 한다.** 지도뿐 아니라 검색창·하단 바까지 덮는다 |
  /// | 6 | 시작 덮개 — 첫 위치 판정과 카메라 준비가 끝날 때까지 전부 가린다 |
  ///
  /// 층 전환 중에는 3·4·4.5층을 **덮는 것이 아니라 뺀다**
  /// ([_floorTransitionCovers]). 스크림은 맨 위지만 페이드가 오르내리는 동안
  /// 반투명이라, 그 구간 내내 검색창과 카테고리 줄이 비쳐 보였다.
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
          if (!_floorTransitionCovers) _buildTopOverlays(context),
          if (!_floorTransitionCovers && !_guidanceActive && !_routeMode)
            _buildBottomBar(routeVisible),
          if (!_floorTransitionCovers && !_guidanceActive) _buildTabBar(),
          _buildFloorScrim(),
          IgnorePointer(
            child: AnimatedSwitcher(
              duration: startupLoadingFadeOut,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInOutCubic,
              child: _startupLoading
                  ? const StartupLoadingOverlay()
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  /// 1층 — 지도. 이 화면이 지도에 넘기는 콜백이 곧 "셸이 지도에 대해 아는 것"의
  /// 전부다.
  Widget _buildMap() {
    return OutdoorMapBody(
      key: _outdoorKey,
      startupLoading: _startupLoading,
      transitRoutesSheetOpen: _transitRoutesSheetOpen,
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
          // 판을 치운 것은 "지금 이 화면에서 비켜라"였다. 건물을 나갔다 오면
          // 화면이 새로 시작하는 것이라 그 뜻도 함께 끝난다.
          if (!entered) _issueDiaryDismissed = false;
        });
        // 앱을 켜자마자 건 요청이 망보다 빨랐을 수 있다. 판이 실제로 필요해지는
        // 이 순간 한 번 더 받는다 — 이미 받아 뒀으면 그냥 돌아온다.
        if (entered) unawaited(_loadBuildingEvents());
        // 오버레이를 닫고 야외로 나온 순간부터는 위치·출발지가 GPS다.
        if (!entered) _dropIndoorOriginIfOutdoors();
        // 실내 컨텍스트가 켜지고 꺼질 때마다 거리 기준이 통째로 바뀐다.
        unawaited(_refreshReach());
      },
      onStoreTap: _onMapStoreTap,
      onBuildingTap: _onMapBuildingTap,
      // 실내 오버레이 위에서도 복도를 골라 출발/도착을 정할 수 있다.
      // 실내 탭과 같은 조작이어야 하므로 같은 값을 내려 준다.
      pickingOnMap: _routeMapPickTarget != null,
      onMapPointPicked: _onMapPointPicked,
      onLocationAnchored: _onLocationAnchored,
      onNeedLocationPlacement: _onNeedLocationPlacement,
      // 실내 도면을 보는 동안에만 뜬다. 야외에서는 층도 도달 거리도 없어
      // 가까운 시설을 셀 수 없다.
      onFacilitiesTap: _indoorContextActive
          ? () => unawaited(_onFacilitiesTap())
          : null,
      facilitiesActive: _facilitiesSheetOpen,
      bottomOverlayLiftPx: _bottomOverlayLiftPx(context),
      // 바닥에 도킹하는 카드는 **하단 바와 같은 값**으로 탭 줄을 비킨다
      // ([_buildBottomBar]도 이 값을 먼저 더한다). 두 곳이 따로 세면 한쪽만
      // 고쳐지는 날이 온다.
      bottomCardLiftPx: _tabBarLiftPx(context),
      topChromeBottomPx: _topBarBottomPx,
      // 실내 화면과 같은 선택을 넘긴다. 야외 지도도 실내 진입
      // 오버레이가 켜지면 같은 도면을 그리므로, 안 넘기면 칩을
      // 눌러도 강조가 안 뜬다.
      categorySelection: _categorySelection,
      onFloorChanged: _onActiveFloorChanged,
      onFloorTransitionChanged: _onFloorTransitionChanged,
      onIndoorTransitionVeilChanged: _onIndoorTransitionVeilChanged,
      onStartupReady: _finishStartupLoading,
      // 실내 화면과 같은 목록을 넘긴다. 야외 지도도 실내 진입
      // 오버레이가 켜지면 층 선택기·위치 지정을 함께 쓰므로, 상단
      // 검색창이나 하단 바를 누른 탭이 지도 탭으로 새어들어가면
      // 실내 오버레이가 닫히거나 그 자리에 PDR 앵커가 찍힌다.
      outerOverlayKeys: [
        _topBarKey,
        _categoryRowKey,
        _searchPanelKey,
        _bottomBarKey,
        _issueDiaryKey,
        _tabBarKey,
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
      //
      // **탭 줄도 같은 이유로 비킨다.** 목록은 [Flexible]이라 자리가 있는 만큼
      // 늘어나는데, 그 자리를 화면 끝까지 주면 마지막 줄이 탭 줄 뒤로 들어간다
      // (`ㄱ`부터 치고 목록이 길어지면 늘 그랬다).
      //
      // **더하지 않고 큰 쪽을 쓴다.** 키보드는 탭 줄을 통째로 덮으므로
      // (`resizeToAvoidBottomInset: false`라 탭 줄은 그 밑에 그대로 있다) 둘을
      // 더하면 키보드가 올라온 동안 패널이 탭 줄 높이만큼 떠 버린다.
      bottom: math.max(
        MediaQuery.viewInsetsOf(context).bottom,
        _tabBarLiftPx(context),
      ),
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
            if (!_guidanceActive) _buildTopBar(),
            // 길찾기 두 칸 중 하나를 치는 중이면 그 후보 목록이 이 자리를
            // 쓴다. 일반 검색 패널·카테고리 열과 자리를 다투므로 셋 중
            // 하나만 뜬다.
            if (!_guidanceActive)
              if (_routeEditingField case final field?)
                _buildRouteFieldResults(field),
            // 층 전환 배너는 여기 없다. 지도가 안내 배너와 **같은 자리**에
            // 그린다([GuidanceBanner]) — 셸이 따로 띄우면 안내 위에 알약이 한
            // 겹 더 겹쳐, 한 사건이 두 개의 안내로 보인다.
            //
            // 결과 패널과 카테고리 열은 같은 자리를 쓴다. 검색 중에는
            // 카테고리 열을 접어 두 오버레이가 겹치지 않게 한다.
            if (_searchActive)
              _buildSearchPanel()
            // 층 전환 중에는 카테고리 줄을 접는다. 배너가 상단 바 바로
            // 아래에 오도록 자리를 비우는 것이고, 전환은 몇 초짜리 상태다.
            // 안내 중에도 접는다. 칩을 누르면 매장 목록 시트가 올라오는데,
            // 그건 "어디 갈지 고르는" 조작이라 목적지가 이미 정해진 화면에
            // 있을 이유가 없다.
            else if (_floorTransition != null ||
                _guidanceActive ||
                _routeMode ||
                _routeEditingField != null)
              const SizedBox.shrink()
            // 두 끝점을 확정해 후보 목록이 닫힌 뒤에는 다시 보여 준다. 입력 중엔
            // 후보 패널과 키보드가 공간을 쓰므로 카테고리 조작을 함께 띄우지 않는다.
            else
              _buildCategoryRow(),
          ],
        ),
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
      routeEditingField: _routeEditingField,
      originController: _routeOriginController,
      destinationController: _routeDestinationController,
      originFocus: _routeOriginFocus,
      destinationFocus: _routeDestinationFocus,
      onOriginChanged: (value) =>
          _onRouteFieldChanged(RoutePlanField.origin, value),
      onDestinationChanged: (value) =>
          _onRouteFieldChanged(RoutePlanField.destination, value),
      onOriginPressed: () => _onRouteFieldFocused(
        RoutePlanField.origin,
        _routeOriginController.text,
      ),
      onDestinationPressed: () => _onRouteFieldFocused(
        RoutePlanField.destination,
        _routeDestinationController.text,
      ),
      onClearRouteDraft: _clearRouteDraft,
      onSwapRouteEndpoints: () => unawaited(_swapRouteEndpoints()),
      canSwapRouteEndpoints: _canSwapRouteEndpoints,
      selectedTravelMode: _travelMode,
      // 이동수단은 출발·도착이 모두 확정된 뒤에만 고른다. 입력 중에 먼저
      // 노출하면 아직 계산할 수 없는 버튼이 카드 높이만 키운다. 건물 안에서
      // 건물 안으로 가는 경로는 수단이 도보 하나로 못박혀 있어 아예 띄우지
      // 않는다([_indoorOnlyRoutePlanned]).
      availableTravelModes: _routeEndpointsReady && !_indoorOnlyRoutePlanned
          ? _availableTravelModes
          : const [],
      onTravelModeSelected: (mode) => unawaited(_onTravelModePicked(mode)),
    );
  }

  /// 길찾기 두 칸 중 지금 치고 있는 칸의 후보 목록.
  Widget _buildRouteFieldResults(RoutePlanField field) {
    return Flexible(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          RoutexSpacing.screenGutter,
          _overlayGap,
          RoutexSpacing.screenGutter,
          RoutexSpacing.contentGap,
        ),
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
          currentFloorId: _activeIndoorFloor,
          suggestions: _routeSuggestions,
          onSuggestionPicked: _onRouteSuggestionPicked,
          onCurrentLocation: _pickCurrentLocationAsOrigin,
        ),
      ),
    );
  }

  /// 검색 결과 패널.
  Widget _buildSearchPanel() {
    return Flexible(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          RoutexSpacing.screenGutter,
          _overlayGap,
          RoutexSpacing.screenGutter,
          RoutexSpacing.contentGap,
        ),
        child: SearchPanel(
          key: _searchPanelKey,
          buildingId: _buildingId,
          query: _searchQuery,
          submitTick: _searchSubmitTick,
          onStorePicked: _onSearchStorePicked,
          onBuildingPicked: _onSearchBuildingPicked,
          onQueryPicked: _onSearchQueryPicked,
          onSuggestionPicked: _onSearchSuggestionPicked,
          // 줄 끝 `도착`. 상세를 거치지 않고 곧바로 경로를 그린다.
          onStoreDestination: _onSearchStoreDestination,
          onSuggestionDestination: (entry) =>
              unawaited(_onSearchSuggestionDestination(entry)),
          indoorContextActive: _indoorContextActive,
          currentFloorId: _activeIndoorFloor,
          reachByNodeId: _reachByNodeId,
          // 검색을 시작한 순간 지도에서 받아 둔 기준점. 위치도
          // 카메라도 못 잡았으면 null이라 바깥 검색이 빈손으로 끝난다.
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
          // 같은 화면의 두 번째 탈출구 — 이 건물에 없는 이름을 실내에서
          // 쳤을 때 밖으로 나가서 다시 찾는다. 야외에서는 나갈 곳이 없어
          // null이고, 패널도 그때는 버튼을 안 그린다(양쪽에서 막는다).
          onSearchOutside: _indoorContextActive
              ? () => unawaited(_onSearchOutsideRequested())
              : null,
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
      // 검색 바와 chip은 각각 48dp hit box 안에 더 작은 시각 표면이 있다.
      // control gap을 다시 주면 보이는 면끼리는 18dp 떨어져 쇼케이스의 inline
      // 조합보다 한 단계 더 벌어진다. 열 자체는 hit box를 유지하고, 두 표면 사이는
      // inline gap으로 맞춘다.
      padding: const EdgeInsets.only(top: RoutexSpacing.inlineGap),
      child: MapOverlayScrollRow(
        key: _categoryRowKey,
        onPointerOverChanged: (over) => over
            ? _lockMaps(_mapLockOverlayHover)
            : _unlockMaps(_mapLockOverlayHover),
        onPointerDownChanged: (down) => down
            ? _lockMaps(_mapLockOverlayTouch)
            : _unlockMaps(_mapLockOverlayTouch),
        children: [
          // 예전에는 여기에 "이벤트" pill이 있었다. 지금은 맨 아래 탭 줄이 그
          // 자리를 맡는다([MapTab.events]) — 같은 조작을 두 벌 두면 사용자가 둘이
          // 다른 것인 줄 안다.
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
      // ETA 카드와 시설 시트는 같은 바닥을 두고 다툰다. 더 높은 쪽 하나만
      // 쓴다 — 더하면 둘 다 떠 있을 때 바가 화면 밖으로 밀린다.
      // 탭 줄은 늘 바닥에 있으므로 그 높이는 **더한다**. 나머지 둘(ETA 카드·시설
      // 시트)은 같은 자리를 두고 다투므로 높은 쪽 하나만 쓴다 — 더하면 둘 다 떠
      // 있을 때 바가 화면 밖으로 밀린다.
      // 시설 시트가 떠 있으면 **그 높이만** 쓴다. 시트는 라우트라 탭 줄을 이미
      // 덮고 있어, 탭 줄까지 더하면 바가 시트에서 그만큼 떠 버린다
      // ([_bottomOverlayLiftPx]와 같은 이유·같은 계산이다). 바는 제 SafeArea로
      // 올라오므로 안전영역은 여기서 뺀다.
      bottom: _facilitiesSheetLiftPx(context) > 0
          ? math.max(
              0,
              _facilitiesSheetLiftPx(context) -
                  MediaQuery.paddingOf(context).bottom,
            )
          : _tabBarLiftPx(context) + (routeVisible ? _etaBarLiftHeight : 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 조작 버튼이 판 **위에** 탄다. 판이 펼쳐지면 함께 밀려 올라가 늘 손이
          // 닿는다 — 판 뒤로 숨기면 목록을 보다가 위치를 잡을 수 없다.
          _buildBottomControls(),
          if (_issueDiaryVisible) _buildIssueDiaryPanel(),
        ],
      ),
    );
  }

  /// 지금 하단 이슈 다이어리 판을 그릴 때인가.
  ///
  /// **건물 안일 때만이다.** 밖에서는 지도에 이 건물 말고도 볼 것이 있고, 화면
  /// 아래를 행사가 차지하면 그것들을 덮는다. 스냅샷을 아직 못 읽었거나 오늘
  /// 열리는 것이 없으면 빈 줄을 남기지 않고 통째로 뺀다.
  bool get _issueDiaryVisible =>
      _indoorContextActive &&
      !_issueDiaryDismissed &&
      // **시트가 떠 있는 동안에는 물러난다.** 판은 라우트가 아니라 하단 chrome
      // 이라 [SheetStackGuard]가 세는 대상이 아니다. 그대로 두면 시트보다 짧을
      // 때 판의 윗머리가 시트 위로 삐져나와, 두 장이 겹친 것처럼 보인다.
      sheetStackGuard.openSheets.value == 0 &&
      _openDiaryPages.isNotEmpty;

  /// 오늘 열리는 행사를 가진 쪽과 그 건수. 자식이 없는 쪽은 빠진다.
  List<({EventDiaryPage page, int count})> get _openDiaryPages =>
      _buildingEvents?.diariesOpenOn(todayKey()) ?? const [];

  /// 오늘 열리는 행사, 갈래 순서로. 판이 펼쳐졌을 때의 목록이다.
  List<BuildingEvent> get _openEventsToday =>
      _buildingEvents?.openOnByDiary(todayKey()) ?? const [];

  Widget _buildIssueDiaryPanel() {
    return IssueDiaryPanel(
      key: _issueDiaryKey,
      pages: _openDiaryPages,
      events: _openEventsToday,
      onPickPage: (page) => unawaited(_onIssueDiaryPick(page)),
      onPickEvent: (index) => unawaited(_onIssueDiaryEventPick(index)),
      onDismissed: () => setState(() => _issueDiaryDismissed = true),
      // 카테고리 줄과 **같은 잠금**이다 — 이 줄 위에서 민 손가락이 지도까지
      // 내려가 지도가 함께 움직이는 것을 막는다.
      onPointerOverChanged: (over) => over
          ? _lockMaps(_mapLockOverlayHover)
          : _unlockMaps(_mapLockOverlayHover),
      onPointerDownChanged: (down) => down
          ? _lockMaps(_mapLockOverlayTouch)
          : _unlockMaps(_mapLockOverlayTouch),
    );
  }

  /// 상단 **바**가 끝나는 y(논리 px). 못 재면 0.
  ///
  /// 경로 전체를 담을 때 위로 비울 높이다. 상수로 두면 안 되는 이유는 높이가
  /// 상태마다 달라서다 — 검색창 한 줄일 때와 길찾기 두 칸 + 이동 수단 줄일 때가
  /// 크게 차이 나서, 상수(120)로 맞춰 뒀더니 길찾기 화면에서 경로의 시작점이
  /// 바 뒤로 잘렸다.
  ///
  /// **재는 것은 [MapTopBar] 하나다.** 그 위 Column 전체를 재면 검색 결과·후보
  /// 목록([Flexible])까지 딸려 들어가, 목록이 펼쳐진 순간 측정값이 화면 높이가
  /// 되고 경로가 아래로 짓눌려 카드 뒤로 통째로 들어간다(실기기에서 그렇게 깨졌다).
  ///
  /// **값이 아니라 함수로 넘긴다** — 지도가 카메라를 맞추는 그 시점에 재야 방금
  /// 두 칸으로 늘어난 바를 잰다.
  double _topBarBottomPx() {
    final box = _topBarKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return 0;
    return box.localToGlobal(Offset.zero).dy + box.size.height;
  }

  /// 탭 줄이 먹는 높이. 안전영역까지 합친 값이라 위에 얹히는 것들이 이만큼
  /// 띄우면 정확히 탭 줄 위에 앉는다.
  double _tabBarLiftPx(BuildContext context) => _guidanceActive
      ? 0
      : kMapTabBarHeight + MediaQuery.paddingOf(context).bottom;

  /// 지도가 자기 것(층 선택기·시설 버튼)을 밀어 올려야 할 높이.
  ///
  /// **안전영역을 빼고 준다** — 받는 쪽이 제 [SafeArea]로 이미 그만큼 올라와
  /// 있어서, 여기서 더하면 두 번 세어 선택기가 붕 뜬다.
  ///
  /// **시설 시트는 라우트라 탭 줄 위에 그려진다** — 그 높이 안에 탭 줄도 안전영역도
  /// 이미 들어 있다. 둘을 또 더했더니 층 선택기와 위치 버튼이 시트에서 한 뼘쯤
  /// 떠서, 시트와 아무 상관 없는 자리에 매달린 것처럼 보였다(실기기 확인).
  ///
  /// 이슈 다이어리 판은 반대다. 라우트가 아니라 탭 줄 **위에** 앉는 chrome이라
  /// 둘을 더해야 판 위에 선다. 판은 **접힌 높이만** 센다 — 펼치면 화면의 3분의
  /// 2라, 거기까지 선택기를 올리면 화면 한가운데에 매달린다. 펼친 동안은 층이
  /// 아니라 행사를 보는 중이다.
  double _bottomOverlayLiftPx(BuildContext context) {
    final facilities = _facilitiesSheetLiftPx(context);
    if (facilities > 0) {
      return math.max(0, facilities - MediaQuery.paddingOf(context).bottom);
    }
    return (_guidanceActive ? 0 : kMapTabBarHeight) +
        (_issueDiaryVisible ? IssueDiaryPanel.peekHeight : 0);
  }

  /// 지금 켜져 있는 것을 탭 줄에 표시한다. 아무것도 아니면 지도가 켜진 자리다.
  MapTab get _activeTab => switch (null) {
    _ when _routeMode => MapTab.directions,
    _ when _issueDiaryVisible => MapTab.events,
    _ => MapTab.map,
  };

  /// 지금 줄에 설 탭.
  ///
  /// **이벤트는 건물 안에서만 선다.** 밖에서 열던 오늘 목록 시트는 여기서
  /// 걷어냈다 — 야외 지도에는 이 건물 말고도 볼 것이 있는데, 그 화면에서 한
  /// 건물의 행사를 상시로 내걸면 앱이 그 건물 전용처럼 보인다. 더현대에 들어서는
  /// 순간 탭이 **하나 늘고**, 그때부터 하단 판([_issueDiaryVisible])과 같은 것을
  /// 켜고 끈다.
  ///
  /// 오늘 열리는 것이 없으면 들어가도 서지 않는다 — 눌러도 아무 일이 없는 탭은
  /// 없는 것만 못하다.
  List<MapTab> get _visibleTabs => [
    for (final tab in MapTab.values)
      if (tab != MapTab.events || _eventsTabAvailable) tab,
  ];

  bool get _eventsTabAvailable =>
      _indoorContextActive && _openDiaryPages.isNotEmpty;

  Widget _buildTabBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: MapTabBar(
        key: _tabBarKey,
        tabs: _visibleTabs,
        selected: _activeTab,
        onSelected: _onTabSelected,
      ),
    );
  }

  /// 탭 하나를 눌렀다. **화면을 갈아 끼우지 않는다** — 이 앱은 지도 한 화면이라,
  /// 탭은 그 위에 무엇을 띄울지만 고른다.
  void _onTabSelected(MapTab tab) {
    switch (tab) {
      case MapTab.map:
        // 지도는 "돌아오는 자리"다. 켜져 있던 것을 걷고 지도만 남긴다.
        _closeSearch();
        if (_routeMode) _forgetRouteDraft();
        if (_issueDiaryVisible) setState(() => _issueDiaryDismissed = true);
      case MapTab.directions:
        unawaited(_openRouteMode());
      case MapTab.events:
        _onEventsTab();
      case MapTab.saved:
        unawaited(_openFavorites());
    }
  }

  /// 이벤트 탭. 하단 판을 켜고 끈다. 이 탭은 건물 안에서만 서므로
  /// ([_visibleTabs]) 여기에 야외 갈래는 없다.
  void _onEventsTab() {
    setState(() => _issueDiaryDismissed = !_issueDiaryDismissed);
  }

  Widget _buildBottomControls() {
    return MapBottomBar(
      key: _bottomBarKey,
      // 아래 안전영역은 늘 탭 줄이 먹는다.
      bottomInset: false,
      onCalibrate: _onCalibrate,
      onPlaceLocation: _onPlaceLocation,
      placingLocation: _outdoorPlacingLocation,
      // 야외에서는 실내 진입 오버레이가 켜져 있을 때만 위치 지정
      // 버튼을 노출한다. 오버레이가 꺼진 순수 야외 상태에서는 지정할
      // 층 정보가 없어 눌러도 의미가 없다.
      showPlaceLocation: _outdoorIndoorEntered,
      attentionOnPlaceLocation: _placeLocationAttention,
      // 목록을 만들 수 있을 때만 띄운다 — 기준점이 없으면 눌러도 아무 일이
      // 없는 버튼이 된다. 판단은 목록을 실제로 만드는 쪽이 한다.
      onPickNearbyStore: (_outdoorKey.currentState?.canPickNearbyStore ?? false)
          ? _onPickNearbyStore
          : null,
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
        photoAssets: _floorTransitionPhotos,
      ),
    );
  }
}
