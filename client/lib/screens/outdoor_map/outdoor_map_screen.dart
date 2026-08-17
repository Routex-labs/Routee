import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:math' show Point;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../../core/api_config.dart';
import '../../map/camera/floor_switch_progress.dart';
import '../../map/geojson.dart';
import '../../map/picked_point.dart';
import '../../service_locator.dart';
import '../../core/tile_url.dart';
import '../../domain/route/building_entrances.dart';
import '../../domain/guidance/completed_route_history.dart';
import '../../domain/geo/floor_label.dart';
import '../../domain/geo/geo_transform.dart';
import '../../domain/guidance/geo_route_progress.dart';
import '../../domain/guidance/guidance_chrome.dart';
import '../../features/debug_mode/debug_mode.dart';
import '../../domain/route/dijkstra.dart';
import '../../domain/route/route_endpoint_fill.dart';
import '../../domain/guidance/route_guidance.dart';
import '../../features/indoor_navigation/application/corridor_position_tracker.dart';
import '../../domain/guidance/escalator_ride.dart';
import '../../features/indoor_navigation/application/escalator_arrival.dart';
import '../../features/indoor_navigation/application/escalator_node_naming.dart';
import '../../features/indoor_navigation/application/escalator_transition_detector.dart';
import '../../features/indoor_navigation/contract/floor_transition_ui_state.dart';
import '../../features/indoor_navigation/application/floor_map_matcher.dart';
import '../../features/indoor_navigation/application/guidance_trail_session.dart';
import '../../features/indoor_navigation/application/indoor_guidance_position.dart';
import '../../features/indoor_navigation/application/indoor_guidance_session.dart';
import '../../features/indoor_navigation/application/indoor_location_estimate.dart';
import '../../features/indoor_navigation/contract/indoor_navigation_contract.dart';
import '../../features/indoor_navigation/debug/escalator_debug_text.dart';
import '../../features/indoor_navigation/debug/pdr_debug_device_info.dart';
import '../../features/indoor_navigation/debug/pdr_debug_session_recorder.dart';
import '../../features/indoor_navigation/debug/pdr_debug_session_share.dart';
import '../../domain/route/multi_floor_router.dart';
import '../../domain/route/transfer_route_geometry.dart';
import '../../models/building/building.dart';
import '../../models/building/building_graph.dart';
import '../../models/route/directions_route.dart';
import '../../models/building/floor_graph.dart';
import '../../models/building/floor_plan.dart';
import '../../models/route/indoor_route.dart';
import '../../models/place/poi_search_result.dart';
import '../../models/route/transit_route.dart';
import '../../theme/app_theme.dart';
import 'widgets/store_cluster_sheet.dart';
import '../../map/label/store_label_anchor.dart';
import '../../map/camera/zoom_math.dart';
import '../../map/label/store_label_fit.dart';
import '../../map/label/store_label_priority.dart';
import '../../widgets/eta_card.dart';
import 'widgets/transit_summary_card.dart';
import '../../models/place/store_index_entry.dart';
import '../../map/camera/floor_camera_bounds.dart';
import '../../map/style/category_map_filter.dart';
import '../../map/icon/category_map_icon.dart';
import '../../map/style/floor_facility_style.dart';
import 'widgets/floor_selector.dart';
import 'widgets/floor_switch_escalator_motif.dart';
import 'widgets/guidance_recenter_button.dart';
import 'widgets/indoor_arrival_card.dart';
import 'widgets/route_steps_sheet.dart';
import '../../map/icon/icon_cache.dart';
import '../../map/icon/place_pin.dart';
import 'widgets/map_overlay_tap_guard.dart';
import 'entry/floor_outline.dart';
import 'gps/gps_session.dart';
import 'entry/indoor_entry_gps.dart';
import 'entry/initial_camera.dart';
import 'camera/building_orientation.dart';
import 'entry/indoor_entry_proximity.dart';
import 'entry/indoor_entry_zoom.dart';
import 'outdoor_map_tuning.dart';
import 'widgets/placing_anchor_hint.dart';
import 'route_recompute_policy.dart';
import 'layers/indoor_overlay_layers.dart';
import 'camera/map_camera_commands.dart';
import 'layers/marker_map_layers.dart';
import 'layers/shape_map_layers.dart';
import 'layers/pdr_debug_map_layers.dart';
import 'pdr_session_lifecycle.dart';
import 'layers/route_map_layers.dart';
import 'layers/transit_map_layers.dart';

part 'parts/escalator.dart';
part 'parts/pdr.dart';
part 'parts/route.dart';
part 'parts/guidance.dart';
part 'parts/route_layers.dart';
part 'parts/indoor.dart';
part 'parts/floor_switch.dart';
part 'parts/store_tap.dart';
part 'parts/gps.dart';
part 'parts/map.dart';
part 'parts/ui.dart';

// 건물 진입/이탈 판정 정책은 indoor_entry_gps.dart가 소유한다. 임계값과 그 근거,
// "왜 직전 값 대비 비율이 아닌가"는 전부 그쪽 주석에 있다.

// 실내 지도와 같은 이유. maplibre_gl은 web/android/iOS만 지원하므로
// 데스크톱에서는 사전에 안내를 보여주고 지도 자체는 그리지 않는다.
const _mapSupportedNativePlatforms = {
  TargetPlatform.android,
  TargetPlatform.iOS,
};
bool get _isMapSupportedOnThisPlatform =>
    kIsWeb || _mapSupportedNativePlatforms.contains(defaultTargetPlatform);

// MapLibre 소스·레이어 id는 전부 `*_map_layers.dart`가 소유한다(건물·scrim은
// shape, 경로선은 route, 대중교통은 transit, 마커·핀은 marker, 실내 오버레이는
// indoor_overlay_layers). 화면은 공개 소스 id로 데이터만 밀어 넣는다.

// 디버그 모드 전용 PDR 진단 레이어(소스·레이어 id, 등록, 데이터 쓰기)는
// pdr_debug_map_layers.dart가 소유한다. 여기서는 무엇을 보여줄지(토글·층·앵커
// 판단)만 정해 완성된 데이터를 넘긴다.

// 층 전환 교차 페이드의 길이·단계·타일 대기 정책은
// core/floor_switch_progress.dart가 단일 출처다.

// 도면을 화면에 맞출 때 채우는 비율은 map_camera_commands.dart가 소유한다.

// 실내 진입/이탈 임계값·오버레이 페이드 구간은 서로 얽혀 있어 한 곳에서만
// 정의한다 — indoor_entry_zoom.dart 참고. 값 하나만 옮겨도 "도면이 다 보이기
// 전에 실내에서 튕겨 나가는" 증상이나 "이탈 순간 도면이 툭 끊기는" 증상이
// 조용히 되살아나므로, 관계를 함수로 고정하고 테스트로 지킨다.

// latlong2 <-> MapLibre 타입 브릿지.
LatLng _toGl(ll.LatLng p) => LatLng(p.latitude, p.longitude);

// 기본 지도 스타일. vworldApiKey가 있으면 VWorld Base 타일, 없으면 OSM으로 폴백해
// 로컬 개발·테스트 환경에서도 지도가 항상 뜨도록 한다.
String _baseMapStyle() {
  final Map<String, dynamic> source;
  if (vworldApiKey.isEmpty) {
    source = {
      'type': 'raster',
      'tiles': ['https://tile.openstreetmap.org/{z}/{x}/{y}.png'],
      'tileSize': 256,
      'attribution':
          '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
    };
  } else {
    source = {
      'type': 'raster',
      'tiles': [
        'https://api.vworld.kr/req/wmts/1.0.0/$vworldApiKey/Base/{z}/{y}/{x}.png',
      ],
      'tileSize': 256,
      'attribution': '© <a href="https://map.vworld.kr">VWorld</a>',
    };
  }
  return jsonEncode({
    'version': 8,
    // glyphs가 없으면 매장명 SymbolLayer가 layout을 못 끝내고, native는 같은 소스의
    // fill 레이어까지 pending에 묶어 **실내 오버레이가 통째로 사라진다.**
    // 웹은 관대해 fill만 그대로 보인다 — Chrome에서만 보면 못 잡는다.
    'glyphs': '$apiBaseUrl/fonts/{fontstack}/{range}.pbf',
    'sources': {'base': source},
    'layers': [
      // **여기 background 레이어가 없으면 지도가 검게 뜬다.**
      // MapLibre GL의 WebGL 캔버스는 base color 없이 clear되면 검정으로 남는데,
      // OSM/VWorld raster 타일이 도착하기 전(첫 진입)이나 캐시에 없는 zoom을
      // 갔다 오면(z<15까지 축소 후 다시 확대) 그 사이가 통째로 검게 보인다.
      // 실내 초기 스타일(_initialStyle)이 이미 같은 이유로 background를 깔고
      // 있다. 색은 OSM의 land 기본색에 가까운 옅은 회백색.
      {
        'id': 'background',
        'type': 'background',
        'paint': {'background-color': '#EDECE8'},
      },
      {'id': 'base', 'type': 'raster', 'source': 'base'},
    ],
  });
}

/// 야외 지도 본문(지도 + 위치/경로 오버레이). 공통 UI는 [MapShellScreen]이 얹는다.
///
/// 실내 진입은 화면을 바꾸지 않고 **이 화면 위에 오버레이를 얹는다** — 층 chip과
/// 위치 지정까지 한 화면에서 조작한다(판정: indoor-entry-rules.md).
/// 크로스페이드 중 화면에 남겨 둔 이전 층 블록 하나.
///
/// record였던 것을 클래스로 바꾼 이유는 [fadeFactor]가 **단계마다 바뀌기**
/// 때문이다 — 새 층이 올라오는 만큼 이전 층을 같이 내려야 진짜 크로스페이드가
/// 된다. record는 불변이라 매 단계 목록을 다시 만들어야 했다.
class _RetiringIndoorBlock {
  _RetiringIndoorBlock({
    required this.layerIds,
    required this.sourceId,
    required this.fadeFactor,
  });

  final List<String> layerIds;
  final String sourceId;
  double fadeFactor;
}

class OutdoorMapBody extends StatefulWidget {
  const OutdoorMapBody({
    super.key,
    this.active = true,
    this.onRouteVisibleChanged,
    this.onGuidanceDismissed,
    this.onGuidanceActiveChanged,
    this.onPlacingLocationChanged,
    this.onIndoorEnteredChanged,
    this.onStoreTap,
    this.onBuildingTap,
    this.onMapPointPicked,
    this.pickingOnMap = false,
    this.onLocationAnchored,
    this.categorySelection,
    this.onFloorChanged,
    this.onFloorTransitionChanged,
    this.outerOverlayKeys = const [],
  });

  /// 이 야외 지도가 지금 화면에 보이는지. [MapShellScreen]은 야외/실내를
  /// IndexedStack으로 겹쳐 두므로, 사용자가 실내 탭으로 넘어가도 이 위젯은
  /// 살아 있다. 알려주지 않으면 보이지도 않는 야외 지도가 GPS를 계속 구독한다 —
  /// 실내에 들어간 뒤에는 GPS를 쓰지 않는다는 규칙을 지키려면 이 값이 필요하다.
  final bool active;

  /// ETA 카드가 화면 최하단에 새로 나타나거나 사라질 때 호출된다.
  /// 상위(MapShellScreen)가 이 값으로 하단 공용 바를 그 위로 띄운다.
  final ValueChanged<bool>? onRouteVisibleChanged;

  /// 사용자가 **"안내 종료"를 눌렀을 때**. [onRouteVisibleChanged]와 구분한다 —
  /// 그쪽은 재계산·수단 변경으로도 오르내린다. 상위는 이 신호로 상단 길찾기 바까지
  /// 닫는다.
  final VoidCallback? onGuidanceDismissed;

  /// 사용자가 **직접 고른** 목적지로 안내가 시작/종료될 때 호출된다.
  /// 상위(MapShellScreen)가 이 값으로 검색창·카테고리 줄·하단 바를 접는다.
  ///
  /// [onRouteVisibleChanged]와 반드시 구분해서 쓴다 — 이유는 [_guidanceActive].
  final ValueChanged<bool>? onGuidanceActiveChanged;

  /// 층 전환 배너·스크림 상태를 셸에 넘긴다.
  ///
  /// 이 화면이 직접 그리지 않는 이유: 검색창·카테고리 줄·하단 바가 셸 Stack의
  /// 형제라, 지도 안에서 그린 배너는 그 뒤에 깔린다.
  final FloorTransitionUiChanged? onFloorTransitionChanged;

  /// PDR 앵커 배치 대기 상태가 바뀔 때 호출된다. 상위(MapShellScreen)가 이
  /// 값으로 하단 바의 "위치 지정" 버튼을 눌린(활성) 톤으로 표시한다.
  final ValueChanged<bool>? onPlacingLocationChanged;

  /// 야외 지도의 실내 진입 오버레이가 켜지거나 꺼질 때 호출된다.
  /// 상위(MapShellScreen)가 이 값으로 하단 바의 "위치 지정" 버튼 노출 여부를
  /// 결정한다 — 오버레이가 꺼져 있을 때는 눌러도 의미가 없어 아예 숨긴다.
  final ValueChanged<bool>? onIndoorEnteredChanged;

  /// 실내 진입 오버레이에서 매장 폴리곤을 탭했을 때 호출된다. 상위
  /// (MapShellScreen)가 실내 화면과 동일한 매장 정보 시트를 띄운다.
  final ValueChanged<PoiSearchResult>? onStoreTap;

  /// **야외에서** 건물 폴리곤을 탭했을 때 호출된다. 상위가 건물 정보 시트를 띄운다.
  ///
  /// 실내 진입은 그 시트가 시킬 때만 한다 — 예전에는 탭이 곧 진입이라, 건물을
  /// 눌러 본 사용자가 "그 건물이 무엇인지" 대신 도면부터 봤다. 값이 null이면
  /// 예전처럼 곧바로 진입한다(시트를 띄울 상위가 없는 테스트 등).
  final ValueChanged<Building>? onBuildingTap;

  /// 길찾기의 "지도에서 선택"이 켜져 있는지. 계약과 근거는 실내 화면의 동명
  /// 필드([IndoorMapBody.pickingOnMap])와 같다 — 두 화면이 같은 조작을 제공해야
  /// 하므로 규칙도 같은 것을 쓴다.
  final bool pickingOnMap;

  /// [pickingOnMap] 중 **매장이 아닌 곳**을 눌렀을 때 그래프에 스냅한 후보를 넘긴다.
  /// 이 경로가 없으면 빈 곳 탭이 [_exitIndoorByOutsideTap]으로 흘러가, 복도를
  /// 눌렀는데 실내 화면이 통째로 닫힌다.
  final ValueChanged<PoiSearchResult>? onMapPointPicked;

  /// 사용자의 현재 위치가 새로 잡혔을 때 호출된다 — "위치 지정"으로 지도를
  /// 탭했을 때와 입구 자동 배치가 여기에 해당한다.
  ///
  /// 상위(MapShellScreen)는 이 신호로 **기억해둔 출발지 매장을 버린다.** 그러지
  /// 않으면 매장을 출발지로 지정해 길찾기를 한 뒤 위치를 다시 잡아도, 다음
  /// 길찾기가 방금 잡은 위치가 아니라 예전에 고른 매장에서 출발한다.
  final VoidCallback? onLocationAnchored;

  /// 지금 카테고리 필터에서 고른 값. 실내 진입 오버레이의 매장 강조에 쓴다.
  ///
  /// **실내 화면과 같은 값을 받아야 한다.** 야외 지도는 건물을 탭하거나 줌
  /// 임계값을 넘기면 그 자리에서 실내 도면을 띄우는데(=실내 탭으로 넘어가지
  /// 않는다), 이 값을 안 받으면 사용자가 보고 있는 도면은 실내 화면과 똑같은데
  /// 카테고리를 눌러도 아무것도 강조되지 않는다.
  final CategorySelection? categorySelection;

  /// 지금 보고 있는 층이 바뀔 때 호출된다. 실내 오버레이가 꺼져 있으면 층 개념이
  /// 없으므로 null을 올린다.
  ///
  /// [IndoorMapBody.onFloorChanged]와 같은 계약이다. 카테고리 필터의 "이 층 N곳"
  /// 안내가 이 값을 쓰는데, 안 올리면 실내 탭에 들렀다 온 사용자에게 **옛 층
  /// 기준 개수**가 남는다.
  final ValueChanged<String?>? onFloorChanged;

  /// 상위(MapShellScreen)가 지도 위에 얹은 오버레이(검색창·저장한 장소 pill·
  /// 카테고리 chip 열·하단 공용 바 등)의 GlobalKey들. 이 영역 안의 탭은
  /// [_handleMapClick]에서 제외한다 — MapLibre 플랫폼 뷰가 Flutter gesture
  /// arena를 우회해 오버레이를 누른 탭도 지도 탭으로 함께 도착하기 때문이다.
  /// 실내 화면(IndoorMapBody)이 같은 목적으로 쓰는 것과 같은 목록이다.
  final List<GlobalKey> outerOverlayKeys;

  @override
  State<OutdoorMapBody> createState() => OutdoorMapBodyState();
}

/// 활강 중 마커를 다시 그리는 주기. 위젯 트리를 rebuild하지 않고 지도 소스만
/// 갱신하므로(=[_syncPdrCurrentLayer]) 이 정도 빈도를 감당할 수 있다.
/// 덮개 카드의 점은 이 값을 보간해 프레임 단위로 부드럽게 그린다.
const _escalatorGlideFrame = escalatorGlideSampleInterval;

/// 도면을 갈아 끼운 뒤 덮개를 그대로 두는 시간(페이드까지 더하면 약 4.7초).
/// 짧으면 덮개가 크로스페이드·마커 활강보다 먼저 걷혀 교체 과정이 보인다.
/// **하차까지 덮지는 않는다** — 내리기 전에 새 층 도면과 다음 경로를 봐야 한다.
const _indoorFloorSwapVeilHold = Duration(milliseconds: 3500);

/// 층 이동 확정 뒤 도착 배너를 띄워 두는 시간.
const _indoorArrivalBannerHold = Duration(seconds: 6);

/// 건물 로드 실패 시 다시 시도하는 간격 사다리(약 1분간 6번). 이 로드는 initState
/// 한 번뿐이라 실패하면 영영 복구되지 않았다. **무한 재시도는 안 한다** — 백엔드
/// 없는 환경에서 배터리만 태운다.
const _buildingRetryDelays = <Duration>[
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
  Duration(seconds: 8),
  Duration(seconds: 16),
  Duration(seconds: 30),
];

/// 목록에서 고른 매장을 볼 때의 최소 확대. 실내 화면과 같은 값이라야 두
/// 화면을 오가도 같은 크기로 보인다.
/// 매장 선택과 상세 시트 등장을 한 동작으로 읽히게 하는 카메라 이동 시간.
/// 시트(380ms)보다 한 박자만 길게 감속해, 시트가 멈춘 뒤 지도가 오래 미끄러지는
/// 느낌도 카메라가 먼저 도착해 시트만 튀어 오르는 느낌도 남기지 않는다.
const _storeFocusDuration = Duration(milliseconds: 520);

/// 폴리곤을 못 찾을 때만 쓰는 폴백 배율. 보통은 [_focusZoomForStore]가 매장
/// 크기에 맞춰 정한다.
const _storeFocusZoom = 19.0;

/// 매장 크기로 정하는 배율의 상·하한.
const _storeFocusMinZoom = 17.8;
const _storeFocusMaxZoom = 20.4;

LatLng _toMapLatLng(ll.LatLng point) => LatLng(point.latitude, point.longitude);

class OutdoorMapBodyState extends State<OutdoorMapBody> {
  /// 선택 확대 애니메이션의 지금 배수(1.0 = 확대 없음).
  /// 근거와 진행 방식은 [_animateSelectionScale].
  double _selectionScale = 1.0;
  Timer? _selectionScaleTimer;

  /// 선택 핀이 **정확한 자리**에 놓였는지. 근사 자리에 먼저 세웠다가 나중에
  /// 옮기면 순간이동으로 보이므로, 확정 전에는 아예 안 세운다.
  bool _highlightAnchorFinal = false;

  /// 카메라가 멈춘 뒤 한 번이라도 핀 자리를 다시 재 봤는지.
  ///
  /// 여기까지 왔는데도 라벨을 못 찾으면 **근사로라도 세운다** — 자리가 조금
  /// 어긋나는 것보다 핀이 아예 없는 편이 나쁘다(실기기에서 큰 매장 하나가
  /// 그렇게 사라졌다).
  bool _cameraSettled = false;
  Timer? _pinIntroTimer;

  /// 핀이 자라기 시작하는 배수. 0에서 시작하면 한 프레임 사라졌다 나온 것처럼
  /// 보이고, 0.8이면 자라는지 안 자라는지 알 수 없다.
  static const double _pinIntroFrom = 0.55;

  /// 확대 프레임 간격. 60fps로 돌리면 채널 왕복이 오히려 끊기게 만든다 —
  /// 40ms(=25fps)면 크기 변화로는 충분히 부드럽고 왕복은 절반 이하다.
  static const _selectionScaleStep = Duration(milliseconds: 40);

  /// GPS 자동 실내 진입이 지금 켜져 있는지. 1회성 플래그였을 때는 오탐 한 번이
  /// 기능 자체를 죽였다([IndoorEntryGpsDecision.rearm]이 다시 켠다).
  ///
  /// **건물 밖 탭만으로는 켜지 않는다** — 화면 조작이지 "내가 밖에 있다"가 아니다.
  bool _gpsEntryArmed = true;

  Position? _position;

  ll.LatLng? _entrance;

  Building? _building;

  List<ll.LatLng>? _buildingFootprint;

  DirectionsRoute? _route;

  final CompletedRouteHistory _completedRouteHistory = CompletedRouteHistory();

  GeoRouteProgress? _outdoorDisplayProgress;

  int _routeGeneration = 0;

  MultiFloorRoute? _indoorMultiFloorRoute;

  PoiSearchResult? _indoorRouteDestination;

  // 야외에서 실내 매장까지 안내하는 한 번의 여정은 두 구간으로 나뉜다:
  //   1) 현재 위치 → 가장 가까운 지상 출입구  (TMAP 도보 경로, [_route])
  //   2) 그 출입구 노드 → 목적지 매장         (온디바이스 다익스트라, 아래 pending)
  // 2번은 **건물에 들어가기 전에 미리 계산해 두고** 승격만 미룬다. 문 앞에
  // 도착한 순간 계산을 시작하면 그래프를 받아오는 동안 안내가 비고, 하필 그
  // 순간은 실내라 통신이 가장 불안한 지점이다.

  /// 1층 지상 출입구 목록. 못 받았거나 없는 건물이면 빈 목록이고, 그때는 문을
  /// 경유하지 않는 기존 안내로 폴백한다.
  List<BuildingEntrance> _groundEntrances = const [];

  /// 지금 안내 기준으로 쥐고 있는 문. GPS가 갱신될 때마다 히스테리시스를 거쳐
  /// 다시 고른다([_syncSelectedEntrance]).
  BuildingEntrance? _selectedEntrance;

  /// 지금 그려진 야외 구간이 향하고 있는 문. [_selectedEntrance]와 달라지는
  /// 순간이 곧 경로를 갈아 끼울 순간이다([_retargetJourneyEntrance]).
  ///
  /// 좌표가 아니라 id로 비교하려고 문 객체를 따로 들고 있다 — 좌표 비교는 같은
  /// 지점을 다른 값으로 만드는 부동소수 왕복에 걸리기 쉽다.
  BuildingEntrance? _journeyEntrance;

  /// 문 경유 안내가 쓰는 건물 그래프. 문이 바뀔 때마다 서버에 다시 묻지 않으려고
  /// 들고 있는다 — 신호가 나쁜 건물 앞에서 정확히 실패하기 때문이다.
  BuildingGraph? _journeyBuildingGraph;

  /// 건물에 들어가면 그릴 실내 구간과 그 목적지. 진입이 판정되면
  /// [_activatePendingIndoorRoute]가 실제 실내 경로 상태로 옮긴다.
  MultiFloorRoute? _pendingIndoorRoute;

  PoiSearchResult? _pendingIndoorDestination;

  /// 실내→야외 안내에서, 건물을 나간 뒤 이어 그릴 야외 목적지
  /// ([showIndoorToOutdoorRouteTo]). 위 두 값의 거울상이다.
  ll.LatLng? _pendingOutdoorDestination;

  String? _pendingOutdoorLabel;

  /// PDR 센서 세션을 언제 켜고 끌지. 정지가 끝나기를 기다리는 일도 여기가 한다.
  late final PdrSessionLifecycle _pdrLifecycle = PdrSessionLifecycle(
    driver: indoorNavigationDriver,
    // 전역 seam을 호출 시점에 읽는다 — 테스트가 setUp에서 갈아끼운다.
    isPermissionGranted: () => isPedometerPermissionGranted(),
  );

  /// 지상 출입구가 있는 층. [_groundEntrances]와 짝이라 함께 채운다 — 출구를
  /// 실내 경로의 도착 노드로 쓰려면 좌표·노드만이 아니라 **층**도 있어야 한다.
  String? _groundEntranceFloor;

  /// 지금 그려진 경로가 자동차 경로인지. 선 모양이 이 값으로 갈린다 —
  /// 자동차는 실선, 걷기는 점선이다([geoJsonLineFeature]).
  bool _routeIsDriving = false;

  /// 지금 그려진 대중교통 안내. null이면 대중교통 경로가 없다.
  TransitItinerary? _transitItinerary;

  /// 대중교통 요약 카드에 적을 목적지 이름.
  String? _transitLabel;

  /// 이번 안내의 출발점을 GPS가 아니라 이 좌표로 못박는다. 길찾기가 그린
  /// **계획 경로**는 걷는 동안 다시 계산되면 안 된다 — 사용자가 비교하려고
  /// 보고 있는 선이 GPS 틱마다 흔들린다.
  ll.LatLng? _fixedRouteOrigin;

  /// 자동차 안내가 시작돼 카메라가 사용자 위치를 따라가는 중인지.
  ///
  /// setState를 쓰지 않는다 — 이 값으로 갈리는 위젯이 없고, 위치가 올 때마다
  /// 카메라만 움직인다. rebuild를 걸면 GPS 틱마다 지도 위 오버레이가 통째로
  /// 다시 그려진다.
  bool _followingUser = false;

  /// 계획 상태로 그려 둔 자동차 경로가 있어서 "안내 시작"을 권해야 하는지.
  ///
  /// 자동차 경로를 그린 직후에는 카메라가 **경로 전체**에 맞춰져 있다. 사용자가
  /// 어디로 어떻게 가는지 한 번 보고 나서 출발하도록, 위치로 내려가는 조작은
  /// 버튼 하나로 분리했다([EtaCard.onStartGuidance]).
  bool _offerStartGuidance = false;

  bool _interactive = true;

  ll.LatLng? _userDestination;

  String? _userDestinationLabel;

  MapLibreMapController? _mapController;

  bool _styleReady = false;

  /// 스타일 로드가 끝나기를 기다리는 자리를 위한 신호.
  ///
  /// 공유 링크로 들어오면 **지도보다 링크가 먼저 도착한다** — 앱을 켜자마자
  /// 매장을 여는데 컨트롤러는 아직 없다. 기다리지 않으면 [focusStore]가 조용히
  /// 포기하고 카메라는 첫 GPS 좌표로 간다(실기기 로그로 확인).
  final _styleReadySignal = Completer<void>();

  /// [focusStore]가 초기 카메라를 예약해 둔 동안만 참이다.
  ///
  /// 스타일을 기다리는 **동안에도** 첫 GPS 센터링을 막아야 한다. 안 막으면
  /// 카메라가 사용자 위치로 갔다가 매장으로 다시 가 두 번 튄다. 카메라를
  /// 실제로 잡으면 `_didInitialCenter`가 그 일을 이어받고, 중간에 포기하면
  /// 풀어 준다 — 걸린 채 남으면 첫 좌표 센터링이 영영 막힌다.
  bool _storeFocusOwnsCamera = false;

  /// PDR 마커 source 갱신은 센서·보정·층 전환에서 동시에 들어올 수 있다.
  ///
  /// MapLibre의 Future는 플랫폼 쪽 반영이 끝난 뒤 완료되므로 호출을 각각
  /// fire-and-forget하면 오래된 위치 쓰기가 최신 위치 뒤에 완료될 수 있다.
  /// revision으로 대기 중인 낡은 쓰기를 건너뛰고, 이미 시작된 native 쓰기는
  /// 직렬 queue 뒤의 최신 쓰기가 반드시 덮어쓰게 한다.
  int _pdrMarkerRevision = 0;

  Future<void> _pdrMarkerWriteQueue = Future<void>.value();

  /// 회색/파란 경로 source도 센서 틱·GPS 틱·재탐색 확정에서 동시에 갱신된다.
  /// native MapLibre 쓰기가 호출 순서와 다른 순서로 완료될 수 있으므로 한 줄의
  /// queue에서 순서대로 반영한다. 이 큐가 없으면 최신 진행률로 만든 회색선이
  /// 오래된 전체 경로 쓰기에 다시 덮일 수 있다.
  Future<void> _routeLayerWriteQueue = Future<void>.value();

  // 야외 오버레이가 지금 보여주는 층. 건물 로드 시 initialFloor로 자동 결정되고,
  // 실내 진입 상태에서 층 chip으로 사용자가 다른 층을 훑어볼 수 있다.
  String? _activeFloor;

  // 활성 층의 통행 그래프. PDR 앵커 배치 시 탭 좌표를 층 로컬로 되돌리고
  // 통로 노드에 스냅하는 데 쓴다. 층 전환마다 다시 로드한다.
  FloorGraph? _floorGraph;

  // 활성 층의 평면도(매장 목록 포함). 실내 오버레이 위에서 매장 폴리곤을
  // 탭했을 때 벡터 타일 feature id로 실제 매장 정보를 되찾는 데 쓴다.
  FloorPlan? _floorPlan;

  /// 층 도면이 바뀔 때마다 다시 매기는 매장 라벨 우선순위.
  /// 축소 단계에서 어떤 이름을 먼저 남길지 정한다([rankStoreLabels]).
  Map<String, int> _storeLabelPriorities = const {};

  // 실내 오버레이에서 지금 강조 표시 중인 매장 id. null이면 강조 없음.
  // 사용자가 매장을 탭하면 채워지고, 매장 정보 시트가 닫히면 상위가
  // [clearHighlight]로 지운다.
  String? _highlightedStoreId;

  // 지도가 아직 안 뜬 시점의 첫 GPS 위치를 잊지 않도록 pending 값을 두고,
  // 스타일 로드 콜백에서 이를 반영한다.
  bool _pendingCenterOnPosition = false;

  // 앱을 켠 뒤 첫 좌표로 지도를 한 번 옮겼는가.
  //
  // 위 pending 값만으로는 부족했다. 그 플래그는 [_syncCurrentLayer]의
  // early-return 경로에서만 서기 때문에, **스타일 로드가 끝난 뒤에 첫 GPS가
  // 도착하면** 아무도 카메라를 옮기지 않아 서울시청(fallbackLocation)에
  // 머물렀다. 평상시 [_handlePosition]은 안내 중일 때만 카메라를 옮긴다.
  bool _didInitialCenter = false;

  // 줌 임계값을 넘겼을 때 실내 진입 오버레이를 한 번만 켜기 위한 히스테리시스.
  // 임계값 아래로 다시 내려오기 전까지는 재발화하지 않는다.
  bool _autoIndoorEntryArmed = true;

  // POI/시설 아이콘 비트맵을 스타일당 한 번만 addImage로 등록하기 위한 게이팅.
  // 층 전환마다 소스/레이어는 다시 붙지만 이미지는 그대로 재사용된다.
  bool _facilityIconImagesRegistered = false;

  /// 지금 세대의 실내 오버레이 소스·레이어 ID. 층 전환마다 [IndoorOverlayIds.next]
  /// 로 갈아 끼운다(세대를 쓰는 이유는 그 클래스 주석).
  IndoorOverlayIds _indoorIds = const IndoorOverlayIds();

  /// 실내 진입 오버레이 상태. true면 층 chip과 위치 지정 버튼 등 실내 UI를
  /// 야외 지도 위에 그린다. 건물 폴리곤 탭, 줌 임계값 초과, GPS 근접 감지
  /// 중 하나로 켜지고, 사용자가 지도를 축소해 임계값 아래로 내려가면 자동으로
  /// 꺼진다 — 실내에서 벗어난 시점에는 오버레이가 시야를 방해하지 않아야 한다.
  bool _indoorEntered = false;

  /// PDR 앵커 배치 대기 중인지. true면 다음 지도 탭은 건물 진입 처리가 아닌
  /// PDR 시작점 지정으로 소비된다.
  bool _placingPdrAnchor = false;

  /// 실내 진입 오버레이에서 위치 보정 버튼을 누른 횟수. 실내 탭과 같은 규칙으로
  /// 홀수 번째(1·3·5…) 탭은 실내 위치 중앙 정렬, 짝수 번째(2·4·6…) 탭은 방향
  /// 회전을 수행한다. 순수 야외(GPS) 보정은 이 카운터를 쓰지 않는다.
  int _recalibrateTapCount = 0;

  late final DebugPdrTrailState _pdrTrailState;

  /// 실내 안내의 위치·층 판정. 실내 탭과 **같은 구현**을 쓴다.
  ///
  /// 예전에는 이 화면이 복도 보정을 따로 돌려 놓고 결과를 읽지 않은 채 앵커를
  /// 고정 표시했다 — 홈에서 실내 길안내를 하면 마커가 움직이지 않았던 이유다.
  final IndoorGuidanceSession _guidance = IndoorGuidanceSession();

  final GuidanceTrailSession _guidanceTrailSession = GuidanceTrailSession();

  StreamSubscription<PdrSnapshot>? _pdrSnapshotSub;

  StreamSubscription<CalibrationStatus>? _pdrCalibrationSub;

  StreamSubscription<AltitudeSample>? _pdrAltitudeSub;

  StreamSubscription<RawMotionActivity>? _pdrRawMotionSub;

  // --- 자동 층 전환 ---
  //
  // 실내 탭과 같은 상태 기계를 쓴다. 다른 것은 도면을 갈아 끼우는 방법뿐이다 —
  // 실내 탭은 자체 렌더러의 카메라를 인계하고, 홈은 MapLibre 오버레이 소스를
  // 통째로 바꾼다([_switchOverlayFloor]).

  /// 조기 전환으로 목적 층을 이미 열어 둔 이동. 하차 확정 전까지 유지된다.
  EscalatorTransition? _escalatorRide;

  /// 확정 직후 잠깐 "도착" 배너를 띄우는 이동. 되돌리기를 여기에 붙인다.
  EscalatorTransition? _escalatorArrival;

  Timer? _escalatorArrivalTimer;

  /// 배너만 띄우는 접근·수직이동 단계. 층 지도는 아직 안 바꾼다.
  EscalatorPhaseChange? _escalatorStage;

  /// 탑승 때문에 걸음 적용을 멈춘 상태인지. pause/resume 짝을 한 곳에서 센다.
  bool _stepsPausedForRide = false;

  /// 전환 직전 상태. 되돌리기와 취소 복원이 이 값을 쓴다.
  String? _preTransferFloor;

  IndoorRoute? _preTransferRoute;

  MultiFloorRoute? _preTransferMultiRoute;

  PoiSearchResult? _preTransferDestination;

  String? _pendingTransferCompletedScope;

  List<ll.LatLng>? _pendingTransferCompleted;

  GraphNode? _pendingArrivalNode;

  /// 화면을 덮는 정도. 0이 아니면 셸이 스크림을 그린다.
  ///
  /// **도면이 갈리는 앞뒤만 덮는다** — 하차까지 덮으면 수십 초 막힌 것으로 읽히고,
  /// 무엇보다 내리기 전에 새 층 도면을 봐 둬야 한다. 대신 크로스페이드와 마커 활강이
  /// 끝나기 전에 걷히지 않을 만큼은 잡는다.
  double _floorSwapVeil = 0;

  /// 덮개를 내리기로 예약해 둔 타이머. 탑승이 먼저 끝나면 취소한다.
  Timer? _floorSwapVeilTimer;

  /// 탑승 중 마커가 흐르는 구간(탑승 노드 → 하차 노드, WGS84).
  ///
  /// 이 값이 있으면 마커 위치의 출처가 여기다. 탑승부터 하차 확정까지는 걸음이
  /// 멈춰 있고 앵커도 아직 이전 층에 있어서, 이것이 없으면 마커가 **사라진 채**
  /// 도면만 바뀐다. 근거와 한계는 [EscalatorGlide] 주석에 적었다.
  EscalatorGlide? _escalatorGlide;

  Timer? _escalatorGlideTimer;

  /// 활강 진행률(0 = 탑승 노드, 1 = 하차 노드). 층 전환 덮개의 점이 이 값을
  /// 듣는다 — 지도 위 마커와 같은 값이라 덮개를 사이에 두고도 하나의 움직임이다.
  /// 객체 정체성이 유지돼야 셸이 매 프레임 다시 그리지 않는다.
  final ValueNotifier<double> _escalatorGlideProgress = ValueNotifier(0);

  /// 기압이 정하는 활강 진행률 목표. 표시값([_escalatorGlideProgress])은 매
  /// 틱 이 값을 지수 평활로 따라간다. 노이즈로 뒤로 가지 않게 단조 증가만
  /// 허용한다 — 하차 확정이 1.0을 채운다.
  double _escalatorRideTargetProgress = 0;

  /// 도면을 교체한 순간의 이동 방향 누적 Δ(m). 진행률 정규화의 0점이다.
  double _escalatorRideSwapDeltaM = 0;

  /// 이번 활강이 가정하는 층고(m). 같은 그룹의 직전 확정 Δ가 있으면 그 값,
  /// 없으면 [escalatorDefaultFloorHeightM]이다.
  double _escalatorRideExpectedM = escalatorDefaultFloorHeightM;

  /// 에스컬레이터 그룹별 실측 층고(|확정 Δ|). 세션 동안만 산다 — 같은 건물을
  /// 도는 동안 두 번째 탑승부터 진행률이 실측 높이로 정규화된다.
  final Map<String, double> _escalatorGroupHeightM = {};

  // 사람 조작 층 전환이 오래 걸릴 때 뜨는 에스컬레이터 모티프. 아무것도 덮지
  // 않는다 — 이전 층 도면이 그대로 보이는 위에 카드 하나만 뜬다. 언제
  // 띄우고 걷을지(모티프 임계·최소 표시)는 컨트롤러가 정한다.
  bool _floorSwitchMotifVisible = false;

  /// 모티프가 마지막으로 흘렀던 방향. 숨김 전환(AnimatedSwitcher 페이드아웃)
  /// 중에도 위젯이 잠깐 더 그려지므로, 방향 없는 프레임이 생기지 않게 마지막
  /// 값을 들고 있는다.
  FloorSwitchDirection _floorSwitchMotifDirection = FloorSwitchDirection.up;

  late final FloorSwitchProgressController _floorSwitchProgress =
      FloorSwitchProgressController(onChanged: _onFloorSwitchMotifChanged);

  /// 실내 오버레이 레이어 전체에 곱해지는 크로스페이드 계수(0=투명, 1=원래
  /// 불투명도). 크로스페이드 중이 아니면 항상 1이다. 페이드 갱신·카테고리
  /// 필터 등 오버레이 속성을 다시 쓰는 **모든** 경로가 이 계수를 거친
  /// [_overlayFadeExpr]를 써야, 페이드 도중 끼어든 갱신이 반쯤 페이드된 새
  /// 도면을 갑자기 불투명하게 되돌리지 않는다.
  double _indoorOverlayFadeFactor = 1;

  /// 크로스페이드가 끝나기를 기다리며 화면에 남아 있는 이전 층 소스·레이어
  /// 묶음(은퇴 블록). 새 도면 페이드인이 끝나면 [_removeRetiringIndoorBlocks]가
  /// 지운다. 연타로 크로스페이드가 겹치면 블록이 잠시 여러 개 쌓일 수 있고,
  /// 마지막 전환의 마무리가 한꺼번에 정리한다.
  final List<_RetiringIndoorBlock> _retiringIndoorBlocks = [];

  /// 층 크로스페이드 중에는 외곽선과 dim scrim hole을 새 층 도면 로드 시점에
  /// 즉시 바꾸지 않는다. 두 경계는 MVT 9개 레이어와 별도 GeoJSON 소스라서,
  /// 미루지 않으면 바닥은 페이드하는데 파란 외곽선만 먼저 `띡` 바뀐다.
  bool _deferFloorBoundarySync = false;

  /// 층 전환 작업을 직렬화한다. 겹쳐 돌면 층과 경로가 서로 다른 시점을 가리킨다.
  Future<void> _floorTransitionQueue = Future<void>.value();

  bool _applyingFloorTransition = false;

  // 셸에 마지막으로 알린 층 전환 UI 상태. 같은 값이면 다시 알리지 않는다.
  FloorTransitionUiState? _reportedFloorTransition;

  double _reportedFloorScrimOpacity = 0;

  /// 디버그 설정은 실내 지도와 공유한다 — 어느 화면에서 켜든 같은 상태를 본다.
  final DebugModeController _debugModeController = debugModeController;

  /// 이번 PDR 세션의 기록기. "PDR 시작"에서 새로 만들고 종료 시 JSON으로
  /// 내보낸다. 실내 화면과 같은 포맷이라 두 화면에서 받은 로그를 같은 분석
  /// 스크립트로 비교할 수 있다.
  PdrDebugSessionRecorder? _pdrDebugRecorder;

  bool _exportingPdrDebugJson = false;

  /// 활성 층 GeoJSON의 map_calibration_version. 내보낸 세션이 어떤 보정본
  /// 도면 위에서 측정된 것인지 구분하는 데 쓴다.
  String _mapCalibrationVersion = 'unversioned';

  // 지도 위 Flutter 오버레이(PDR 제어 등) 영역. MapLibre는 PlatformView라 이
  // 위젯들 위의 탭도 native 지도까지 흘러들어가 onMapClick이 함께 발화한다 —
  // 버튼을 눌렀을 뿐인데 뒤의 매장이 열리거나 앵커가 버튼 아래에 찍히는 것을
  // 막기 위해 좌표로 걸러낸다(실내 화면의 overlayHitTest와 같은 목적).
  final GlobalKey _pdrControlKey = GlobalKey();

  final GlobalKey _pdrShareButtonKey = GlobalKey();

  final GlobalKey _etaCardKey = GlobalKey();

  /// 실내 경로를 **미리 보는 중**인가. 참이면 안내가 아직 시작되지 않았다.
  ///
  /// 건물 밖에서도 "거기는 어떻게 되어 있지?" 하고 안을 볼 수 있어야 한다. 그때
  /// 사용자는 그 매장에 서 있지 않으므로 **현재 위치를 그 매장으로 잡지 않는다** —
  /// 잡아 버리면 화면이 사실이 아닌 위치를 말하고, PDR이 거기서부터 걸음을 센다.
  /// 경로선과 요약은 그대로 그리고, 시작은 카드의 `안내 시작`이 맡는다.
  bool _indoorRoutePreview = false;

  /// 미리 보기에서 `안내 시작`을 누르면 앵커를 찍을 출발지. 없으면 지금 위치다.
  PoiSearchResult? _indoorRoutePreviewOrigin;

  /// 도착 카드가 가리키는 목적지. 사용자가 확인을 누를 때까지 남는다.
  PoiSearchResult? _arrivedDestination;

  /// 지금 화면에서 도착만 말하고 있는가. 참이면 하단 안내 배너를 그리지 않는다.
  ///
  /// 도착 문구는 화면에 하나여야 한다. 카드가 떠 있는 것만으로는 부족하다 —
  /// 도착 지점을 지나쳐 계속 걸으면 카드는 그대로 두고(한 번 말한 것을 조용히
  /// 거두지 않는다) 안내는 되살아나야 하므로, 지금 판정이 도착인지도 함께 본다.
  bool get _showingArrivalOnly =>
      _arrivedDestination != null &&
      _indoorRouteGuidance?.action == RouteGuidanceAction.arrived;

  /// 도착 안내를 읽을 시간을 준 뒤 경로를 지우는 타이머. 살아 있다는 것 자체가
  /// "이미 카운트다운 중"이라는 상태다([decideArrivalAutoClear]).
  Timer? _arrivalRouteClearTimer;

  final GlobalKey _arrivalCardKey = GlobalKey();

  final _mapOverlayTapGuard = MapOverlayTapGuard();

  Offset? _etaClosePointerDown;

  /// 층 선택기. **가장 중요한 항목이다.** 이 열은 실내 진입 상태에서만 뜨는데,
  /// 그 상태에서 chip을 누른 탭이 지도까지 새어들어가면 그 좌표가 건물 밖으로
  /// 판정돼 `_exitIndoorByOutsideTap`이 걸린다 — 층을 바꿨을 뿐인데 야외로
  /// 튕겨 나간다. 지도를 크게 확대해 두면 chip 자리도 건물 안이라 증상이 숨고,
  /// 건물이 화면 일부만 차지할 만큼 축소했을 때만 재현된다.
  final GlobalKey _floorSelectorKey = GlobalKey();

  /// 위치 지정 안내 배너. 오른쪽 상단 X를 누른 탭이 지도까지 새어들어가 배너
  /// 아래 지점에 앵커가 찍히는 것을 막는다 — 취소했는데 위치가 지정되면
  /// 사용자 입장에선 취소가 안 먹은 것으로 보인다.
  final GlobalKey _placingHintKey = GlobalKey();

  /// 건물 로드 실패 배지("다시 시도"). 이 탭이 지도까지 새어들어가면 재시도를
  /// 누른 손가락이 배지 아래 지점의 건물 진입·앵커 배치까지 함께 발화시킨다.
  final GlobalKey _buildingLoadFailedKey = GlobalKey();

  /// 검색·길찾기 시트가 지도 위에 떠 있는 동안 지도 제스처를 꺼서, 시트를
  /// 마우스 휠로 스크롤할 때 그 아래 지도까지 같이 움직이지 않게 한다.
  void setInteractive(bool value) {
    if (_interactive == value) return;
    setState(() => _interactive = value);
  }

  /// 실내 진입 오버레이에서 지금 보고 있는 층. 상위(MapShellScreen)가 상단
  /// 검색·길찾기 시트를 "현재 층 우선"으로 좁힐 때 쓴다 — 실내 화면의
  /// [IndoorMapBodyState.currentFloor]와 같은 계약이라 상위가 두 화면을
  /// 동일하게 다룰 수 있다.
  String? get currentFloor => _activeFloor;

  /// 마지막으로 상위에 알린 층. 같은 값을 반복해서 올리면 상위가 매번 setState를
  /// 돌게 되므로 여기서 걸러 낸다.
  String? _notifiedFloor;

  /// 화면 배율. `icon-size`가 **물리 픽셀**에 곱해지는 값이라 논리 px으로 잡은
  /// 마커 크기를 여기로 환산한다([indoorMarkerIconSize]).
  ///
  /// 레이어를 등록하는 코드가 여러 번의 `await` 뒤라 그 자리에서
  /// `MediaQuery.devicePixelRatioOf(context)`를 읽으면 위젯이 그 사이 사라졌을 때
  /// 터진다. 그래서 의존성이 잡히는 시점에 한 번 받아 둔다.
  double _devicePixelRatio = 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  }

  @override
  void initState() {
    super.initState();
    _pdrTrailState = DebugPdrTrailState.fromCurrent(
      snapshot: indoorNavigationDriver.currentSnapshot,
      calibration: indoorNavigationDriver.currentCalibration,
    );
    _debugModeController.addListener(_onDebugModeChanged);
    _pdrSnapshotSub = indoorNavigationDriver.snapshots.listen((snapshot) {
      _pdrDebugRecorder?.recordSnapshot(snapshot);
      if (!mounted) return;
      // **야외에서는 실내 위치에 반영하지 않는다.** 센서 세션은 계속 돌지만
      // (오갈 때마다 껐다 켜면 heading이 매번 처음부터다), 그 걸음을 여기서
      // 받으면 야외를 걸어 다닌 거리가 실내 좌표계에 그대로 쌓인다. 사용자에게는
      // 밖에 서 있는데 실내 위치 아이콘만 도면 위를 계속 걸어가는 것으로 보인다.
      // 진단 기록(_pdrDebugRecorder)은 위에서 이미 받았다 — 무슨 일이 있었는지는
      // 남기되 화면 위치만 멈춘다.
      if (!_indoorEntered) return;
      setState(() {
        _pdrTrailState.recordSnapshot(snapshot);
        _syncCorridorTracking(snapshot);
      });
      _syncPdrCurrentLayer();
      // 사용자 회색선은 실제 PDR 궤적이 아니라 현재 계획 경로의 완료 구간이다.
      // 진행률이 바뀐 같은 틱에 경로 source도 갱신해야 파란 잔여선과 회색 완료선이
      // 같은 투영점을 공유한다. GuidanceTrailSession은 별도 진단 궤적으로만 남긴다.
      unawaited(_syncRouteLayer());
      unawaited(_syncDebugPdrLayers());
    });
    _pdrCalibrationSub = indoorNavigationDriver.calibration.listen((status) {
      _pdrDebugRecorder?.recordCalibration(status);
      if (!mounted) return;
      // 스냅샷과 같은 이유로 야외에서는 받지 않는다. 앵커가 바뀌는 사건이라
      // 여기서 받으면 야외에 선 채로 실내 위치가 한 번 더 움직인다.
      if (!_indoorEntered) return;
      setState(() {
        _pdrTrailState.recordCalibration(status);
        _syncCorridorTracking(_pdrTrailState.snapshot);
      });
      if (status.phase == CalibrationPhase.calibrated ||
          status.phase == CalibrationPhase.uncalibrated) {
        _setPlacingAnchor(false);
      }
      _syncPdrCurrentLayer();
      unawaited(_syncRouteLayer());
      unawaited(_syncDebugPdrLayers());
    });
    // 층 전환 판정. 실내 탭에만 있던 구독을 여기에도 둔다 — 이게 없으면 홈에서
    // 에스컬레이터를 타도 층이 그대로라, 마커가 이전 층 도면 위를 걸어간다.
    _pdrAltitudeSub = indoorNavigationDriver.altitudeSamples.listen(
      _onAltitudeSample,
    );
    _pdrRawMotionSub = indoorNavigationDriver.rawMotion.listen(
      _guidance.onRawMotion,
    );
    unawaited(_loadBuildingEntrance());
    _syncGpsSubscription();
  }

  /// 그래프 노드 하나의 WGS84 좌표. 노드를 못 찾으면 null.
  ll.LatLng? _nodeWgs84(FloorGraph? graph, String? nodeId) {
    if (graph == null || nodeId == null || graph.nodes.isEmpty) return null;
    final node = graph.nodes.where((n) => n.id == nodeId).firstOrNull;
    if (node == null) return null;
    final wgs84 = fitFloorGeoTransform(graph.nodes).apply(node.xM, node.yM);
    return ll.LatLng(wgs84.$1, wgs84.$2);
  }

  /// 건물 로드가 실패한 상태인지. 배지를 띄우는 유일한 근거이며, 재시도가
  /// 성공하면 [_loadBuildingEntrance]가 다시 false로 되돌린다.
  bool _buildingLoadFailed = false;

  /// 재시도 요청이 아직 도는 중인지. 연타로 요청이 겹치는 것을 막고, 배지
  /// 문구를 "다시 불러오는 중"으로 바꿔 사용자가 눌린 걸 알 수 있게 한다.
  bool _retryingBuildingLoad = false;

  int _buildingRetryAttempt = 0;

  Timer? _buildingRetryTimer;

  @override
  void didUpdateWidget(covariant OutdoorMapBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 실내 탭으로 넘어가면(active=false) GPS 구독을 끊고, 돌아오면 다시 붙인다.
    if (oldWidget.active != widget.active) _syncGpsSubscription();
    // 카테고리 선택이 바뀌면 강조 레이어의 필터만 갈아 끼운다. 레이어를 지웠다
    // 다시 만들지 않는 이유는 kCategoryHighlightNoneFilter 주석 참고.
    if (oldWidget.categorySelection != widget.categorySelection) {
      unawaited(_applyCategoryFilter());
    }
  }

  /// 지도는 PlatformView라 hot reload로 살아남고 `onStyleLoadedCallback`이 다시
  /// 불리지 않는다. 이 훅이 없으면 **레이어 속성을 고쳐도 화면이 그대로**인데
  /// 위젯 코드는 즉시 반영돼, 코드를 의심하게 만드는 함정이 된다.
  @override
  void reassemble() {
    super.reassemble();
    unawaited(_refreshIndoorDestinationPin());
  }

  @override
  void dispose() {
    // 스타일을 기다리던 매장 포커스를 풀어 준다. 안 풀면 그 await가 영영
    // 돌아오지 않아 뒤따르는 mounted 검사에 닿지 못한다.
    if (!_styleReadySignal.isCompleted) _styleReadySignal.complete();
    _buildingRetryTimer?.cancel();
    _selectionScaleTimer?.cancel();
    _pinIntroTimer?.cancel();
    _gps.dispose();
    _pdrSnapshotSub?.cancel();
    _pdrCalibrationSub?.cancel();
    _pdrAltitudeSub?.cancel();
    _pdrRawMotionSub?.cancel();
    _escalatorArrivalTimer?.cancel();
    _escalatorGlideTimer?.cancel();
    _arrivalRouteClearTimer?.cancel();
    _floorSwapVeilTimer?.cancel();
    _escalatorGlideProgress.dispose();
    // 탑승 중 화면이 닫히면 걸음이 멈춘 채로 전역 PDR 세션이 남는다. 다음
    // 화면에서 아무리 걸어도 위치가 갱신되지 않는다.
    if (_stepsPausedForRide) {
      _stepsPausedForRide = false;
      unawaited(indoorNavigationDriver.resumeStepTracking());
    }
    // 앱 전역 인스턴스라 dispose하지 않는다 — 실내 화면이 같은 컨트롤러를
    // 계속 구독한다.
    _debugModeController.removeListener(_onDebugModeChanged);
    _gpsVerdictDebugText.dispose();
    _escalatorDebugText.dispose();
    super.dispose();
  }

  /// 디버그 모드는 이제 **표시만** 바꾼다.
  ///
  /// 예전에는 디버그를 끄면 PDR 진입점(시작/종료 버튼)이 사라지므로 세션을 함께
  /// 정지시켰다. PDR이 실내 진입 중 상시 실행이 된 뒤에는 끌 대상이 없고, 여기서
  /// 정지시키면 "선을 숨기려다 위치 추적이 끊기는" 결과가 된다.
  void _onDebugModeChanged() {
    // 디버그 시트에서 개별 경로 토글을 켜고 끄면 여기로 들어온다. 레이어는
    // 이미 등록돼 있으므로 데이터만 다시 채우면 즉시 반영된다.
    unawaited(_syncDebugPdrLayers());
    // 디버그를 끄면 마지막 판정 문구를 버린다. 남겨 두면 다시 켰을 때 몇 분 전
    // 좌표의 숫자가 지금 값인 것처럼 떠 있고, 현장에서는 그걸 구분할 수 없다.
    if (!_debugModeController.enabled) {
      _gpsVerdictDebugText.value = null;
      _escalatorDebugText.value = null;
    }
    if (mounted) setState(() {});
  }

  /// 진행 중인 층 그래프 로드. 자동 실내 진입은 GPS 이벤트를 따라 발화하므로
  /// 건물이 막 도착한 직후, 즉 층 그래프 요청이 아직 도는 중에 걸릴 수 있다.
  /// 그 순간 [_floorGraph]만 보면 "그래프 없음"으로 오판해 자동 앵커를 포기하게
  /// 되므로, [_startTrackingFromEntrance]가 이 future를 먼저 기다린다.
  Future<void>? _floorGraphLoad;

  /// 직전 좌표를 기기가 찍은 시각. 좌표 사이 간격을 진단 칩에 띄우는 데만 쓴다.
  DateTime? _lastFixAt;

  /// 마지막으로 TMAP 도보 경로를 요청한 좌표.
  ///
  /// 위치 스트림이 1초에 한 번으로 빨라졌기 때문에 필요해졌다. 예전에는 스트림
  /// 자체가 5 m마다 왔으므로 좌표 한 건 = 요청 한 번이어도 됐다.
  ll.LatLng? _lastRouteRequestOrigin;

  /// 디버그 모드에서 지도 위에 띄우는 GPS 진입 판정 근거 한 줄. null이면 안 그린다.
  ///
  /// [ValueNotifier]인 이유는 갱신 빈도다 — 좌표마다 화면 전체를 다시 그리면
  /// 진단을 켰다는 이유로 측정 대상인 성능이 달라진다.
  final ValueNotifier<String?> _gpsVerdictDebugText = ValueNotifier<String?>(
    null,
  );

  /// 층 전환 판정의 근거를 띄우는 칩 문구. GPS 칩과 같은 이유로 [ValueNotifier]다
  /// — 기압은 초당 여러 건 들어오므로 화면 전체를 다시 그리면 안 된다.
  final ValueNotifier<String?> _escalatorDebugText = ValueNotifier<String?>(
    null,
  );

  /// 마지막으로 나온 층 전환 진단 이벤트.
  ///
  /// 이벤트는 무슨 일이 일어난 순간에만 나온다. 들고 있지 않으면 거부 사유가
  /// 한 프레임 떴다 사라져, 정작 읽어야 할 사람이 못 읽는다.
  EscalatorDetectionEvent? _lastEscalatorEvent;

  /// 이번 실내 상태가 **자동 진입**으로 켜졌는지.
  ///
  /// 자동 이탈은 자동 진입을 되돌리기 위한 것이다. 사용자가 건물을 직접 탭해서
  /// 도면을 연 경우까지 자동으로 닫으면, 입구 앞에 서서 층 도면을 보려던 사람의
  /// 화면이 신호가 잡히는 순간 제멋대로 닫힌다.
  bool _indoorEnteredByGps = false;

  /// GPS 구독을 [_gpsTrackingWanted] 상태에 맞춘다. 구독 시작/해제의 유일한
  /// 진입점이라 중복 구독이나 해제 누락이 생기지 않는다.
  /// 위치 스트림의 수명(구독·재연결·벙어리 감시·일회성 조회)은 여기가 소유한다.
  /// 화면은 좌표를 받아 쓰기만 한다.
  late final GpsSession _gps = GpsSession(
    onFix: (position, {bool fromStream = false}) =>
        _handlePosition(position, fromStream: fromStream),
    isActive: () => mounted && _gpsTrackingWanted,
    onStreamError: _handlePositionError,
  );

  ({String scopeId, List<ll.LatLng> points})?
  _currentIndoorCompletionSnapshot() {
    final route = _indoorRouteSegment;
    final floor = _activeFloor;
    if (route == null || floor == null) return null;
    final completed = _indoorRouteVisuals(route).completed;
    if (completed.length < 2) return null;
    return (scopeId: floor, points: completed);
  }

  /// 야외 계획 경로를 현재 투영점에서 완료/잔여 구간으로 나눈다.
  ({List<ll.LatLng> completed, List<ll.LatLng> remaining}) _outdoorRouteVisuals(
    DirectionsRoute? route,
  ) {
    if (route == null || route.points.length < 2) {
      return (completed: const [], remaining: route?.points ?? const []);
    }
    final progress = _outdoorDisplayProgress;
    if (progress == null) {
      return (completed: const [], remaining: route.points);
    }
    final segment = progress.segmentIndex.clamp(0, route.points.length - 2);
    return (
      completed: [...route.points.take(segment + 1), progress.projectedPoint],
      remaining: [progress.projectedPoint, ...route.points.skip(segment + 1)],
    );
  }

  /// 현재 실내 계획 경로를 displayProgress 기준으로 나눈다.
  ///
  /// 진행률이 없거나 현재 층 그래프가 아직 준비되지 않은 동안은 파란 경로
  /// 전체를 유지한다. 회색선을 만들기 위해 위치를 임의로 경로 위에 붙이지
  /// 않는 것이 중요하다.
  ({List<ll.LatLng> completed, List<ll.LatLng> remaining}) _indoorRouteVisuals(
    IndoorRoute route,
  ) {
    if (route.points.length < 2 ||
        route.pointsLocalM.length != route.points.length) {
      return (completed: const [], remaining: route.points);
    }
    final split = splitRouteAtProgress(
      route.pointsLocalM,
      _guidance.displayProgress,
    );
    final graph = _floorGraph;
    if (split == null || graph == null || graph.nodes.isEmpty) {
      return (completed: const [], remaining: route.points);
    }
    return (
      completed: _localRoutePointsToWgs84(split.completed, graph),
      remaining: _localRoutePointsToWgs84(split.remaining, graph),
    );
  }

  /// 위치 보정 버튼. 실내 오버레이가 켜져 있으면 **GPS를 건드리지 않는다** —
  /// 건물 안에서 다시 찍으면 지도가 건물 밖으로 튀어 실내 위치를 잃는다.
  ///
  /// 탭마다 번갈아 돈다: 홀수는 화면 정중앙, 짝수는 바라보는 방향을 위로 회전.
  /// 순수 야외에서만 GPS를 한 번 더 조회한다.
  Future<void> recalibrate() async {
    if (_indoorEntered) {
      await _recalibrateIndoor();
      return;
    }
    try {
      final position = await currentPosition();
      _handlePosition(position);
      final controller = _mapController;
      if (controller != null && _styleReady) {
        await controller.animateCamera(
          CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
        );
      }
    } catch (_) {
      _showSnack('위치를 다시 확인하지 못했습니다');
    }
  }

  /// 길찾기 시트에서 도착지를 고르면 호출된다. [origin]을 주면(길찾기
  /// 시트에서 출발지도 직접 고른 경우) 현재 GPS 위치 대신 그 지점을
  /// 출발점으로 써서 경로를 한 번만 계산한다 — 두 지점 사이 경로를 보는
  /// 용도라 GPS를 따라 계속 갱신할 필요가 없다. 없으면 기존처럼 현재
  /// 위치에서 [destination]까지의 보행 경로를 계산해 지도 위에 표시한다.
  Future<void> showRouteTo(
    ll.LatLng destination, {
    required String label,
    ll.LatLng? origin,
    bool keepPendingIndoorRoute = false,
    bool keepCompletedHistory = false,
  }) async {
    // 새 야외 목적지를 시작하는 진입점이다. 같은 목적지의 재탐색은
    // _updateRoute/_applyRoute로만 들어오므로, 여기서만 이전 여정을 끊는다.
    // 예외는 실내→야외 예약을 소비하는 호출뿐이다([_activatePendingOutdoorRoute]) —
    // 그건 새 여정이 아니라 **같은 여정의 다음 구간**이라, 방금 걸어온 실내
    // 층의 회색선까지 지우면 안 된다. 야외 쪽 진행률은 이 경로가 확정될 때
    // [_applyRoute]가 어차피 새로 잡는다.
    if (!keepCompletedHistory) _clearCompletedRouteHistory();
    // 문 경유 안내가 스스로를 부를 때만 pending을 지키고, 그 밖의 새 안내는
    // 이전 여정을 걷어낸다. 남겨 두면 사용자가 다른 곳으로 안내를 바꾼 뒤에
    // 건물에 들어갔을 때 지웠어야 할 실내 경로가 혼자 되살아난다.
    if (!keepPendingIndoorRoute) _clearPendingIndoorRoute();
    // 실내→야외 예약은 조건 없이 접는다. 이 호출 자체가 "새 야외 목적지"라,
    // 남겨 두면 나중에 건물을 나가는 순간 방금 지운 목적지가 되살아난다.
    // (예약을 소비하는 [_activatePendingOutdoorRoute]는 부르기 전에 이미 비운다.)
    _clearPendingOutdoorRoute();
    // 새 도보 목적지를 받으면 이전 대중교통 안내는 끝난 것이다. 남겨 두면
    // 다른 곳으로 걸어가는 화면 위에 예전 버스 노선이 계속 그려진다.
    clearTransitRoute();
    // 새 안내는 새 계획이다. 이전 자동차 안내의 따라가기를 남기면 경로 전체를
    // 보여 줘야 할 화면이 사용자 위치에 붙들린다.
    _stopFollowingUser();
    setState(() {
      // 이번 안내의 출발지가 무엇인지 여기서 확정한다. origin이 없으면 GPS로
      // 되돌아가야 하므로 반드시 null로 지워야 한다 — 안 지우면 예전에 찍어 둔
      // 지점이 계속 출발지로 남아, 현재 위치에서 출발하는 안내가 영영 안 된다.
      _fixedRouteOrigin = origin;
      // 이 경로는 걷는 안내다. 자동차에서 넘어왔으면 실선으로 남지 않게 되돌린다.
      _routeIsDriving = false;
      _offerStartGuidance = false;
      _userDestination = destination;
      _userDestinationLabel = label;
      // 새 목적지를 받을 때마다 초기화해서, 이번 경로가 계산되면
      // _applyRoute가 "새로 생김"으로 보고 카메라를 다시 맞추게 한다.
      _route = null;
    });
    _syncDestinationLayer();
    _syncRouteLayer();
    // 여기서는 아직 chrome이 접히지 않는다 — `_route`를 방금 null로 되돌렸고,
    // 안내 chrome은 경로가 실제로 그려진 뒤에야 접힌다([shouldFoldGuidanceChrome]).
    // 그래도 통보한다: 앞선 안내가 돌고 있었다면 그게 여기서 끝나므로 접혀 있던
    // chrome을 되돌려야 하고, 아래 경로 계산이 실패해 그대로 return하는 경로에서도
    // 화면이 접힌 채 남지 않는다.
    _notifyRouteStateIfChanged();

    if (origin != null) {
      final route = await directionsRepository.getWalkingRoute(
        origin: origin,
        destination: destination,
      );
      if (!mounted) return;
      _applyRoute(extendRouteToDestination(route, destination));
      return;
    }

    // 야외 길찾기의 출발지는 GPS 현재 위치뿐이다(실내 앵커는 쓰지 않는다).
    // 아직 신호를 못 잡았으면 경로를 계산할 수 없으므로, 조용히 끝내지 않고
    // 이유를 알린다 — 안내가 없으면 "도착을 눌렀는데 아무 일도 안 일어남"이 된다.
    final position = _position;
    if (position == null) {
      _showSnack('현재 위치를 아직 못 잡았습니다. GPS 신호를 확인해주세요.');
      return;
    }
    await _updateRoute(position);
  }

  /// 이 화면이 아는 "지금 출발할 자리". 지도에서 찍어 둔 출발 지점이 있으면 그
  /// 값을, 없으면 GPS를 쓴다.
  ///
  /// **실내 PDR 앵커는 쓰지 않는다.** 건물 안 좌표를 도로 경로의 출발지로 보내면
  /// TMAP이 건물 반대편 도로로 스냅한다.
  ll.LatLng? get routeOriginPoint {
    final fixed = _fixedRouteOrigin;
    if (fixed != null) return fixed;
    final position = _position;
    if (position == null) return null;
    return ll.LatLng(position.latitude, position.longitude);
  }

  /// 야외(GPS)에서 건물 안 매장까지. 야외 구간만 그리고 실내 구간은 들어간 순간
  /// [_activatePendingIndoorRoute]가 이어 붙인다.
  ///
  /// **폴백을 먼저 정한다** — 노드·출입구·그래프 중 하나라도 없으면 목적지 좌표로
  /// 곧장 그린다. [origin]을 주면 문도 그 지점 기준으로 고른다.
  Future<void> showOutdoorToIndoorRouteTo(
    PoiSearchResult destination, {
    ll.LatLng? origin,
  }) async {
    // **실내 오버레이가 켜져 있으면 먼저 접는다.** 이 메서드는 "사용자가 밖에
    // 있다"는 전제인데, 오버레이는 확대만으로도 켜져 밖에 선 사용자가 도면을 편 채
    // 여기 들어온다.
    //
    // 접지 않으면 실내 구간이 **영영 안 그려진다** — [_pendingIndoorRoute]를 올리는
    // 트리거가 "실내로 들어가는 순간"인데 이미 들어와 있으면 그 순간이 오지 않는다.
    await returnToOutdoorView();
    if (!mounted) return;

    final building = _building;
    final endNodeId = destination.nodeId;
    if (building == null || endNodeId == null || destination.floor.isEmpty) {
      await showRouteTo(
        destination.point,
        label: destination.name,
        origin: origin,
      );
      return;
    }
    // 문은 출발 지점에서 가까운 것을 고른다. 지도에서 찍은 출발지가 있으면 그
    // 좌표가, 없으면 GPS가 기준이다. 둘 다 없으면 경로 자체를 못 만드는데,
    // showRouteTo가 그 안내를 이미 갖고 있으므로 거기로 흘려보낸다.
    final position = _position;
    final reference =
        origin ??
        (position == null
            ? null
            : ll.LatLng(position.latitude, position.longitude));
    if (reference == null) {
      await showRouteTo(destination.point, label: destination.name);
      return;
    }
    // [_selectedEntrance]가 아니라 [_journeyEntrance]를 이력으로 넘긴다. 앞의
    // 값은 **GPS 기준**으로 진입 판정이 쓰는 문이라, 멀리 찍은 출발지로 안내할
    // 때 그 값을 섞으면 두 판단이 서로를 끌어당긴다.
    final entrance = nearestEntrance(
      _groundEntrances,
      reference,
      current: _journeyEntrance,
    );
    if (entrance == null) {
      await showRouteTo(
        destination.point,
        label: destination.name,
        origin: origin,
      );
      return;
    }

    // 실내 구간을 **먼저** 푼다. 그래야 야외 경로를 그리기 전에 "이 문으로
    // 들어가면 목적지까지 갈 수 있는가"가 확정된다.
    final graph =
        _journeyBuildingGraph ??
        await buildingRepository.getBuildingGraph(building.id);
    if (!mounted) return;
    final leg = graph == null
        ? null
        : computeMultiFloorRoute(graph, entrance.nodeId, endNodeId);

    setState(() {
      _journeyBuildingGraph = graph;
      _journeyEntrance = entrance;
      _pendingIndoorDestination = destination;
      _pendingIndoorRoute = (leg == null || leg.isEmpty) ? null : leg;
      // 실내 경로가 남아 있으면 [_syncRouteLayer]가 야외 구간 대신 그것을 그린다.
      _guidance
        ..setRouteSegment(null)
        ..clearProgress()
        ..setRoute(null);
      _indoorMultiFloorRoute = null;
      _indoorRouteDestination = null;
    });
    _syncDestinationLayer();
    _syncIndoorDestinationLayer();

    if (leg == null || leg.isEmpty) {
      // 문까지는 안내하되 침묵하지 않는다 — 안내가 문 앞에서 끝나는 이유를
      // 사용자가 알아야 그 자리에서 다른 방법을 찾을 수 있다.
      _showSnack('건물 안 경로를 계산하지 못했습니다. 출입구까지만 안내합니다.');
    }
    await showRouteTo(
      entrance.point,
      label: _journeyEtaLabel(destination, entrance),
      origin: origin,
      keepPendingIndoorRoute: true,
    );
  }

  /// 건물 **안**에서 바깥 목적지까지. [showOutdoorToIndoorRouteTo]의 거울상이다.
  ///
  /// **출구는 목적지 기준으로 고른다** — 반대편으로 나가면 실내에서 아낀 30 m를
  /// 바깥에서 200 m로 갚는다.
  ///
  /// [origin]을 주면 PDR 앵커 대신 그 실내 매장에서 출발한다. 앵커가 없어도
  /// 그릴 수 있어야 하므로 [showIndoorRouteTo]가 그 검사를 건너뛴다.
  ///
  /// 깨지는 자리 셋: 출구가 없으면 야외 경로만, 실내 위치가 없으면 안내로 되돌리고,
  /// **실내 경로가 안 풀리면 예약을 걸지 않는다.**
  Future<void> showIndoorToOutdoorRouteTo(
    ll.LatLng destination, {
    required String label,
    PoiSearchResult? origin,
  }) async {
    final exitFloor = _groundEntranceFloor;
    final exit = exitFloor == null
        ? null
        : nearestEntrance(_groundEntrances, destination);
    if (exitFloor == null || exit == null) {
      // 출입구 데이터가 없으면 실내 구간을 만들 수 없다. 야외 경로만 그리되,
      // 사용자가 실내 매장을 출발지로 **골랐다면** 그 선택이 조용히 무시되므로
      // 말해 준다 — 안 그러면 "출발지를 잡았는데 왜 여기서 시작하지"가 된다.
      if (origin != null) {
        _showSnack('건물 출입구 정보가 없어 실내 구간을 건너뛰고 바깥 경로만 안내합니다.');
      }
      await showRouteTo(destination, label: label);
      return;
    }

    final exitLabel = entranceDirectionLabel(
      exit,
      _buildingCenter(_buildingFootprint ?? const []),
    );
    // 실내 구간은 기존 실내 라우팅을 그대로 쓴다. 출구도 노드를 가진 지점이라
    // 매장과 다를 게 없다 — 따로 만들면 층 전환·재탐색·진행률이 전부 갈라진다.
    await showIndoorRouteTo(
      PoiSearchResult(
        name: exitLabel,
        floor: exitFloor,
        point: exit.point,
        nodeId: exit.nodeId,
      ),
      origin: origin,
    );
    if (!mounted) return;
    // 실내 구간이 실제로 그려졌을 때만 야외 구간을 예약한다. 위 호출은 실패해도
    // 스낵바만 띄우고 조용히 돌아오므로, 성공 여부는 결과 상태로 확인한다.
    if (_indoorRouteDestination == null) return;
    setState(() {
      _pendingOutdoorDestination = destination;
      _pendingOutdoorLabel = label;
    });
    _showSnack('$exitLabel로 안내합니다. 건물을 나가면 바깥 경로가 이어집니다.');
  }

  /// 이 화면에 그려진 안내를 **전부** 지운다 — 야외 도보 구간과 실내 구간까지.
  ///
  /// 상단 길찾기 바의 X처럼 "길찾기 자체를 끝낸다"는 뜻일 때 쓴다. 재계산 직전에
  /// 옛 선만 치우는 경로와 나누지 않으면, 수단을 바꿀 때마다 문 경유 안내의
  /// 실내 뒷부분이 함께 날아가 문 앞에서 안내가 끊긴다.
  void clearAllRoutes() {
    _clearUserDestination();
    _clearIndoorRoute();
  }

  /// 실내 경로를 계산해 야외 화면 위에 그대로 그린다. 같은 층이면 단층 API를,
  /// 다르면 건물 전체 그래프로 계산해 **보고 있는 층의 세그먼트만** 얹는다.
  ///
  /// [origin]을 주면 PDR 앵커 대신 그 매장에서 출발한다. 그때는 앵커가 없어도 그릴 수
  /// 있어야 하므로 앵커 필수 검사는 origin이 없을 때만 건다.
  Future<void> showIndoorRouteTo(
    PoiSearchResult destination, {
    PoiSearchResult? origin,
    bool announceOriginAnchor = true,
    bool preview = false,
  }) async {
    final anchor = _pdrTrailState.anchor;
    // 명시적 출발지는 노드 id와 층이 둘 다 있어야 그래프 탐색을 시작할 수 있다.
    // 하나라도 비면 앵커 경로로 폴백해, 사용자가 "출발지를 골랐는데 아무 일도
    // 안 일어나는" 상태에 빠지지 않게 한다.
    final originNodeId = origin?.nodeId;
    final originFloor = origin?.floor;
    final hasExplicitOrigin =
        originNodeId != null && originFloor != null && originFloor.isNotEmpty;
    if (!hasExplicitOrigin && anchor == null) {
      _showSnack('출발 위치를 먼저 지정해주세요. 하단 "위치 지정" 버튼으로 시작점을 탭하면 됩니다.');
      return;
    }
    final endFloor = destination.floor;
    final endNodeId = destination.nodeId;
    final building = _building;
    if (endNodeId == null || endFloor.isEmpty || building == null) {
      _showSnack('도착지 노드 정보가 없어 경로를 계산할 수 없습니다.');
      return;
    }
    final startFloor = hasExplicitOrigin ? originFloor : anchor!.floorId;
    final explicitStartNodeId = hasExplicitOrigin ? originNodeId : null;
    // 매장을 출발지로 골랐으면 현재 위치도 그 매장으로 옮긴다. 이걸 안 하면
    // 경로는 그 매장에서 뻗어 나가는데 위치 아이콘만 예전 자리(또는 아무 데도)
    // 남아, 사용자는 자기가 어디 있다고 표시되는지와 경로가 어긋난 화면을 본다.
    //
    // **미리 보기에서는 찍지 않는다.** 그 사람은 그 매장에 서 있지 않다 — 찍으면
    // 화면이 사실이 아닌 위치를 말하고 PDR이 거기서부터 걸음을 센다. 앵커는
    // 카드의 `안내 시작`을 누른 순간에 찍는다.
    if (hasExplicitOrigin && !preview) {
      await _anchorAtStoreOrigin(
        floor: originFloor,
        nodeId: originNodeId,
        storePoint: origin!.point,
        storeName: origin.name,
        announce: announceOriginAnchor,
      );
      if (!mounted) return;
    }
    // 새 실내 목적지를 고른 것이므로 실내→야외 예약도 접는다. 남겨 두면 다른
    // 매장으로 안내를 바꾼 사용자가 건물을 나가는 순간 옛 야외 목적지가 뜬다.
    // ([showIndoorToOutdoorRouteTo]는 이 호출이 끝난 **뒤에** 예약을 건다.)
    _clearPendingOutdoorRoute();
    // 새 목적지를 고른 순간에는 이전 여정의 완료 이력도 함께 끝낸다. 이후
    // 실내 재탐색은 이 함수가 아니라 _computeAndShow*에서 이력을 이어 붙인다.
    _clearCompletedRouteHistory();
    // 이전 걷기 경로가 남아 있으면 함께 지워, 실내 경로만 화면에 뜨도록 한다.
    setState(() {
      _route = null;
      _userDestination = null;
      _userDestinationLabel = null;
      _indoorRouteDestination = destination;
      _indoorRoutePreview = preview && hasExplicitOrigin;
      _indoorRoutePreviewOrigin = preview ? origin : null;
      _arrivedDestination = null;
      // 목적지가 바뀌면 새로운 길안내다. 기존 궤적을 남기면 새 파란 경로와
      // 이전 목적지로 걸어간 회색선이 한 여정처럼 섞인다.
      _guidanceTrailSession.clear();
      // 새 경로를 그리기 전에 초기화 — 아래 compute가 성공하면 다시 채운다.
      _guidance.setRouteSegment(null);
      _indoorMultiFloorRoute = null;
    });
    _syncDestinationLayer();
    _syncRouteLayer();
    // 경로 계산 전에도 도착지 centroid에 핀을 먼저 띄운다 — 사용자가 고른
    // 매장이 어디인지 즉시 보이고, 계산이 끝나면 도착 노드로 옮겨 붙는다.
    _syncIndoorDestinationLayer();
    _notifyRouteStateIfChanged();

    // 사용자가 목적지를 고른 **이 순간**이 개요 연출을 하는 유일한 자리다.
    // 여기서만 켜 두면 "안내당 한 번"이 별도 플래그 없이 지켜진다 — 재탐색은
    // 아래 [_rerouteIndoorFromCurrentPosition]에서 끄고, 층 전환은 하차 지점
    // 기준으로 따로 맞춘다([_swapIndoorFloorForRide]).
    if (startFloor == endFloor) {
      await _computeAndShowSingleFloorIndoorRoute(
        buildingId: building.id,
        floor: endFloor,
        endNodeId: endNodeId,
        playOverview: true,
        // 목적지를 새로 고른 순간 — 여기서만 진단 세션이 새로 열린다.
        beginNewRecordingSession: true,
        startNodeId: explicitStartNodeId,
      );
    } else {
      await _computeAndShowMultiFloorIndoorRoute(
        buildingId: building.id,
        startFloor: startFloor,
        endFloor: endFloor,
        endNodeId: endNodeId,
        playOverview: true,
        beginNewRecordingSession: true,
        startNodeId: explicitStartNodeId,
      );
    }
  }

  /// 현재 위치에서 건물 안 **모든 노드**까지의 거리·비용. 검색 결과가 매장마다
  /// "몇 m · 도보 몇 분"을 붙이는 데 쓴다.
  ///
  /// **null인 경우가 여럿이다**(앵커 없음·그래프 없음·그 층에 노드 없음). 호출부는
  /// 어느 쪽이든 거리 줄을 안 그린다 — 줄마다 "알 수 없음"을 반복하면 목록이 안 읽힌다.
  Future<Map<String, NodeReach>?> reachFromCurrentPosition() async {
    final anchor = _pdrTrailState.anchor;
    final buildingId = _building?.id;
    if (anchor == null || buildingId == null) return null;

    final graph = await buildingRepository.getBuildingGraph(buildingId);
    if (!mounted || graph == null || graph.nodes.isEmpty) return null;

    // 경로 계산과 **같은 시작 노드**를 쓴다. 여기서 다른 규칙으로 고르면 목록에
    // 적힌 거리와 실제로 길찾기를 눌렀을 때 나오는 거리가 서로 달라진다.
    final startNodeId = _pickStartNodeIdInBuildingGraph(
      graph: graph,
      startFloorName: anchor.floorId,
    );
    if (startNodeId == null) return null;

    try {
      return reachableFrom(
        nodes: graph.nodes,
        edges: graph.edges,
        startNodeId: startNodeId,
      );
    } on ArgumentError {
      // 그래프가 깨져 있어도 목록 자체는 계속 떠야 한다 — 거리만 빠진다.
      return null;
    }
  }

  String? _nearestNodeId(
    List<GraphNode> nodes,
    double xM,
    double yM, {
    String? excludingNodeId,
  }) {
    GraphNode? nearest;
    double? nearestDistanceSquared;
    for (final node in nodes) {
      if (node.id == excludingNodeId) continue;
      final dx = node.xM - xM;
      final dy = node.yM - yM;
      final distanceSquared = dx * dx + dy * dy;
      if (nearestDistanceSquared == null ||
          distanceSquared < nearestDistanceSquared) {
        nearestDistanceSquared = distanceSquared;
        nearest = node;
      }
    }
    return nearest?.id;
  }

  /// 야외 구간 ETA. 문 경유 안내 중이면 실내 구간까지 더한다 — 안 더하면 "이솝까지"
  /// 라고 적어 두고 **문까지의** 값을 보여 준다.
  ///
  /// 시간은 실내 구간의 **비용**(costM)으로 잰다(엘리베이터 대기가 거기 있다).
  /// 거리는 실거리로 더한다. [_indoorEta]와 같은 규칙이다.
  ({double distanceM, int minutes}) _outdoorEta(DirectionsRoute route) {
    final leg = _pendingIndoorRoute;
    if (leg == null) {
      return (
        distanceM: route.distanceMeters,
        minutes: (route.durationSeconds / 60).ceil().clamp(1, 999),
      );
    }
    final indoorSeconds =
        leg.totalCostMeters / indoorWalkingSpeedMetersPerSecond;
    return (
      distanceM: route.distanceMeters + leg.totalDistanceMeters,
      minutes: ((route.durationSeconds + indoorSeconds) / 60).ceil().clamp(
        1,
        999,
      ),
    );
  }

  /// ETA 카드에 쓸 거리와 비용. 다층 경로면 전 세그먼트 합, 단일 층이면 그 세그먼트
  /// 값. 실내 화면과 같은 규칙이다.
  ///
  /// `distanceM`은 실제 수평 거리만("m 남음"), `costM`은 탑승·대기 시간까지 담은 보행
  /// 등가값(소요 시간)이다. 한 값으로 겸하면 남은거리가 비용만큼 부풀어 보인다.
  ({double distanceM, double costM}) _indoorEta() {
    // 걸은 만큼 줄어든 값이 있으면 그것을 쓴다. 예전에는 항상 경로 전체 길이를
    // 돌려줘서, 목적지 앞에 서 있어도 "출발할 때와 같은 거리"가 떠 있었다.
    final remaining = _guidance.displayProgress?.remainingM;
    final multi = _indoorMultiFloorRoute;
    if (multi != null) {
      if (remaining == null) {
        return (
          distanceM: multi.totalDistanceMeters,
          costM: multi.totalCostMeters,
        );
      }
      // 이 층 세그먼트만 진행률을 갖는다. 남은 층들의 거리·비용은 그대로 더한다.
      final segmentM = _indoorRouteSegment?.distanceMeters ?? 0;
      final walkedM = (segmentM - remaining).clamp(0.0, segmentM);
      return (
        distanceM: (multi.totalDistanceMeters - walkedM).clamp(
          0.0,
          multi.totalDistanceMeters,
        ),
        costM: (multi.totalCostMeters - walkedM).clamp(
          0.0,
          multi.totalCostMeters,
        ),
      );
    }
    // 단층 경로에는 수직 이동이 없어 거리와 비용이 같다.
    final remainingM = remaining ?? _indoorRouteSegment?.distanceMeters ?? 0;
    return (distanceM: remainingM, costM: remainingM);
  }

  /// 현재 진입 상태에 맞는 오버레이 페이드 표현식.
  /// 구간이 진입 전후로 왜 다른지는 [indoorOverlayFadeExpr] 쪽 주석 참고.
  List<Object> _fadeExpr({double maxOpacity = 1}) =>
      indoorOverlayFadeExpr(entered: _indoorEntered, maxOpacity: maxOpacity);

  /// 지금 층에서 **실제로 그려지는** 좌표 전부 — 외곽선 + 매장 폴리곤·중심 + POI.
  ///
  /// 외곽선만으로는 모자란다. 1F는 매장이 외곽선 밖으로 12·19 m 튀어나오고, B2는
  /// footprint가 매장보다 9 m 넓어 도면이 프레임에서 치우친다.
  ({String floor, Duration duration})? _pendingFloorFit;

  /// 하단 바 '홈'으로 야외에 돌아왔을 때의 이탈. **오버레이만 끄면 부족하다** —
  /// 확대된 채면 도면이 그대로 보인다. 카메라도 축소하고 실내 앵커 경로도 지운다.
  ///
  /// [_exitIndoorByOutsideTap]과 달리 **재무장한다**(축소까지 하므로 안전하다).
  Future<void> returnToOutdoorView() async {
    if (!_indoorEntered) return;
    if (_placingPdrAnchor) _setPlacingAnchor(false);
    _clearIndoorRoute();
    _autoIndoorEntryArmed = true;
    _setIndoorEntered(false);
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    await controller.animateCamera(CameraUpdate.zoomTo(outdoorReturnZoom));
  }

  // 실내 MVT 소스·레이어는 스타일 로드와 활성 건물 로드 둘 다 되면 한 번만 등록.
  bool _indoorTilesRegistered = false;

  /// 상위(MapShellScreen)의 하단 바 리프트/ETA 카드 표시와 안내 chrome 접기가
  /// 어긋나지 않도록, 경로·목적지를 건드린 뒤 이 헬퍼로 상태 변화만 통보한다.
  /// 걷기 경로 쪽 [_applyRoute]와 같은 규칙(변화가 있을 때만 콜백)을 쓴다.
  ///
  /// 두 신호를 한 함수에서 같이 본다. 호출 지점을 나누면 목적지만 바뀌고 경로는
  /// 그대로인 순간(예: [showRouteTo] 진입 직후)에 한쪽만 통보되기 쉽다.
  bool _lastRouteVisibleNotified = false;

  bool _lastGuidanceActiveNotified = false;

  bool _indoorRerouteInFlight = false;

  int _lastIndoorRerouteAtMs = 0;

  /// 야외 POI 검색의 기준점.
  ///
  /// GPS를 먼저 쓰고, 아직 신호가 없으면 **지금 보고 있는 지도 중심**으로
  /// 떨어진다. 후자를 폴백으로 두는 이유는, 기준점이 없으면 TMAP POI 검색이
  /// 전국을 뒤져 걸어갈 수 없는 후보를 첫 줄에 올리기 때문이다. 사용자가 보고
  /// 있는 화면 중심은 "여기 근처"라는 의도로 읽어도 무리가 없다.
  ll.LatLng? get outdoorSearchCenter {
    final position = _position;
    if (position != null) {
      return ll.LatLng(position.latitude, position.longitude);
    }
    final target = _mapController?.cameraPosition?.target;
    if (target == null) return null;
    return ll.LatLng(target.latitude, target.longitude);
  }

  /// 이 좌표가 우리 실내 도면이 있는 건물의 것인가. 검색 결과를 합칠 때 쓴다
  /// ([SearchPanel.isInsideIndoorBuilding]).
  ///
  /// **외곽선 안인지만 보면 안 된다** — 여유 폭의 근거는
  /// [poiBuildingProximityMeters]에.
  bool isAtIndoorBuilding(ll.LatLng point) {
    final footprint = _buildingFootprint;
    if (footprint == null || footprint.length < 3) return false;
    return metersToPolygon(point, footprint) <= poiBuildingProximityMeters;
  }

  /// 지도를 한 지점으로 옮긴다. 검색 결과에서 고른 야외 장소를 시트가 덮기 전에
  /// 화면에 먼저 보여 주는 용도다.
  Future<void> focusPoint(ll.LatLng point) async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(_toGl(point), poiFocusZoom),
    );
  }

  /// 상위(MapShellScreen)가 매장 정보 시트가 닫힐 때 호출해 강조를 지운다.
  void clearHighlight() {
    if (_highlightedStoreId == null) return;
    setState(() => _highlightedStoreId = null);
    _syncHighlightLayer();
  }

  /// 지금 층을 **다시 고른 것과 같은 화면**으로 되돌린다. 시트를 닫은 사용자가
  /// 보려던 것은 다시 층 전체인데, 매장으로 치우친 화면이 남으면 다시 찾아야 한다.
  /// 층 전환과 같은 함수·같은 시간을 쓴다.
  Future<void> realignToActiveFloor() async {
    if (!_indoorEntered) return;
    await _fitCameraToActiveFloor(duration: floorSwitchZoomDuration);
  }

  /// 검색 후보(`StoreIndexEntry`)를 좌표까지 갖춘 [PoiSearchResult]로 바꾼다.
  /// 찾지 못하면 null — 상위가 이름으로 검색을 다시 돌린다.
  ///
  /// 후보 목록에 좌표가 없어서 필요한 변환이고, 층 도면([_floorPlan])이 이미 들고
  /// 있는 `centroid`에서 찾으므로 추가 요청이 없다. 이름은 유일 키가 아니라
  /// **id로 찾는다.**
  ///
  /// **실내가 아니면 층을 옮기지 않고 포기한다** — 야외에서 부르면 카메라만 건물로
  /// 튀는 반쪽 이동이 남는다. [enterBuildingIfNeeded]면 밖에서도 옮긴다
  /// ([focusStore]와 같은 뜻이며, 공유 링크로 들어온 경로가 그렇다 — 링크를 받은
  /// 사람은 대개 건물 밖에 있어서, 막으면 공유가 주 사용 맥락에서 아무것도 열지
  /// 못한다). 층 교체는 도면 소스만 갈아 끼우므로 **실내 모드를 켜지 않는다.**
  Future<PoiSearchResult?> resolveIndexEntry(
    StoreIndexEntry entry, {
    bool enterBuildingIfNeeded = false,
  }) async {
    if (entry.floorName.isNotEmpty && entry.floorName != _activeFloor) {
      if (!_indoorEntered && !enterBuildingIfNeeded) return null;
      // 검색에서 타 층 매장을 고른 경로 — 사용자가 층 전환을 가장 자주 체감하는
      // 자리다. 새 도면 페이드인은 이어지는 매장 포커스 카메라 이동과 겹친다.
      await _switchOverlayFloorCrossfaded(entry.floorName);
      if (!mounted) return null;
      // 기다리는 사이 다른 전환이 추월했으면 다른 층 도면에서 좌표를 찾게
      // 되므로 여기서 멈춘다([focusStore]와 같은 규칙).
      if (_activeFloor != entry.floorName) return null;
    }
    // 층은 맞지만 그 층 도면 로드가 아직 도는 중일 수 있다 — 층을 막 바꾼
    // 직후의 검색 탭이 대표적이다. 기다리지 않으면 [_floorPlan]이 비어 있어
    // 첫 탭이 조용히 null로 떨어지고, 상위가 이름 재검색으로 돌려 사용자는
    // 같은 매장을 **두 번** 눌러야 한다.
    await _floorGraphLoad;
    if (!mounted) return null;
    final stores = _floorPlan?.stores;
    if (stores == null) return null;

    for (final store in stores) {
      if (store.id != entry.id) continue;
      return PoiSearchResult(
        name: entry.name,
        floor: entry.floorName,
        point: store.centroid,
        placeId: entry.id,
        // 도착 노드는 색인 쪽을 쓴다. 층 도면에도 같은 값이 있지만, 후보 줄에
        // "길찾기 가능"을 판단한 근거가 색인이라 화면과 행동이 갈리지 않는다.
        nodeId: entry.entranceNodeId,
        category: entry.category,
        subcategory: entry.subcategory,
      );
    }
    return null;
  }

  /// 목록에서 고른 매장을 실내 오버레이 위에서 보여 준다.
  /// [IndoorMapBodyState.focusStore]와 같은 계약이되 **층은 옮기지 않는다** —
  /// 목록을 훑는 중에 보고 있던 층이 소리 없이 바뀐다.
  ///
  /// [enterBuildingIfNeeded]면 건물 밖에서 골랐어도 들어가서 보여 준다(검색 결과
  /// 전용이다. 카테고리 목록은 지금 층 매장만 올려 주므로 이 값을 주지 않는다).
  Future<void> focusStore(
    PoiSearchResult store, {
    double bottomSheetFraction = 0,
    double topInsetPx = placingHintTopPx,
    bool keepZoom = false,
    bool enterBuildingIfNeeded = false,
  }) async {
    // 밖에서 들어온 경우 배율을 유지하면 도시 축척 그대로 매장 위에 서게 된다.
    // 그때는 keepZoom 요청을 무시하고 매장이 보이는 배율까지 확대한다.
    final fromOutside = !_indoorEntered;
    if (fromOutside && !enterBuildingIfNeeded) return;

    // **여기서부터 카메라는 이 포커스의 것이다.** 아래에서 층 도면과 스타일을
    // 기다리는데, 그 사이 첫 GPS 좌표가 오면 화면을 사용자 위치로 가져간다.
    _storeFocusOwnsCamera = true;

    // **여기서 실내 모드를 직접 켜지 않는다.** 켜면 길찾기 출발지 규칙이 PDR 앵커로
    // 바뀌어, 멀리서 매장을 고른 사용자가 "출발 위치를 먼저 지정해주세요"로 막힌다.
    // 카메라만 옮기고 진입 판정은 [_handleCameraIdle] 한 곳에 남긴다.
    if (store.floor.isNotEmpty && store.floor != _activeFloor) {
      if (!enterBuildingIfNeeded) return;
      // 층 교체는 실내 모드와 무관하다 — 도면 소스만 갈아 끼우므로, 카메라가
      // 도착했을 때 그 매장이 있는 층이 그려져 있게 된다.
      await _switchOverlayFloorCrossfaded(store.floor);
      if (!mounted) return;
      // 층 전환이 실패했으면(그 층 그래프·도면을 못 받음) 다른 층 도면 위에
      // 엉뚱한 자리를 강조하게 되므로 여기서 멈춘다. 예약도 함께 푼다 — 걸어
      // 둔 채 나가면 첫 좌표 센터링이 영영 막혀 카메라가 서울시청에 남는다.
      if (store.floor != _activeFloor) {
        _storeFocusOwnsCamera = false;
        return;
      }
    }
    // 도면 로드가 아직 도는 중이면 기다린다 — 아래 강조([_syncHighlightLayer])가
    // [_floorPlan]에서 매장 폴리곤을 찾으므로, 로드 전에 그리면 강조 없이
    // 카메라만 움직이는 반쪽 포커스가 된다([resolveIndexEntry]와 같은 이유).
    await _floorGraphLoad;
    if (!mounted) return;
    // **지도를 기다린다.** 공유 링크로 앱이 켜지면 여기 도달할 때 컨트롤러가
    // 아직 없다. 예전에는 그대로 포기해, 층 도면과 시트는 매장을 가리키는데
    // 카메라만 첫 GPS 좌표로 가 있었다.
    if (!_styleReady) await _styleReadySignal.future;
    if (!mounted) return;
    final controller = _mapController;
    if (controller == null || !_styleReady) {
      _storeFocusOwnsCamera = false;
      return;
    }

    // 초기 카메라를 이 포커스가 썼다. 뒤늦은 첫 좌표가 화면을 뺏지 않는다.
    // 여기서부터는 [_didInitialCenter]가 그 일을 맡으므로 예약을 놓아 준다.
    _didInitialCenter = true;
    _pendingCenterOnPosition = false;
    _storeFocusOwnsCamera = false;

    setState(() => _highlightedStoreId = store.placeId);
    // 핀 **자리**는 먼저 잡는다(점 하나라 순간이다). **크기**는 아래
    // animateCamera와 함께 출발한다 — 여기서 키우면 글자가 먼저 커진 뒤
    // 화면이 움직인다.
    await _syncHighlightLayer();
    if (!mounted) return;

    // 뷰포트는 카메라 이동 전에 읽는다(실내 화면과 같은 이유 — await 뒤에
    // MediaQuery를 보면 그 사이 위젯이 트리에서 빠졌을 수 있다).
    final viewport = MediaQuery.sizeOf(context);
    final camera = controller.cameraPosition;
    final currentZoom = camera?.zoom ?? 0;
    final bearing = camera?.bearing ?? 0;
    // 배율 규칙은 실내 도면과 한 함수를 공유한다(focusZoomFor).
    final zoom = focusZoomFor(
      currentZoom: currentZoom,
      keepZoom: keepZoom && !fromOutside,
      storeFocusZoom: _focusZoomForStore(
        store,
        viewport: viewport,
        bottomSheetFraction: bottomSheetFraction,
        topInsetPx: topInsetPx,
        bearing: bearing,
      ),
    );
    // **한 번만 움직인다.** 예전에는 매장 중앙으로 옮긴 뒤 `scrollBy`로 띠 한가운데로
    // 다시 밀었는데, 첫 이동이 한 프레임 드러나 카메라가 두 번 튀었다. 최종 목표를
    // 먼저 계산해 한 애니메이션으로 간다.
    final lift = math.max(
      0.0,
      (viewport.height * bottomSheetFraction - topInsetPx) / 2,
    );
    final target = cameraTargetForScreenLift(
      store.point,
      bearing: bearing,
      zoom: zoom,
      liftPx: lift,
    );
    // 카메라와 확대를 **같이** 출발시킨다. 둘 다 _storeFocusDuration이라 끝도 같다.
    unawaited(_animateSelectionScale(selected: true));
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _toGl(target),
          zoom: zoom,
          bearing: bearing,
          tilt: camera?.tilt ?? 0,
        ),
      ),
      duration: _storeFocusDuration,
    );
  }

  /// 이 매장이 화면의 **보이는 띠**(시트와 상단 chrome 사이)에서 약 42%를 차지하는
  /// 배율. 작은 매장은 읽을 만큼 확대하고, 백화점의 큰 앵커 매장은 한 면이 화면을
  /// 가득 덮지 않게 한다.
  ///
  /// 폴리곤을 못 찾으면 [_storeFocusZoom]으로 떨어진다.
  double _focusZoomForStore(
    PoiSearchResult store, {
    required Size viewport,
    required double bottomSheetFraction,
    required double topInsetPx,
    required double bearing,
  }) {
    final polygon = _floorPlan?.stores
        .where((candidate) => candidate.id == store.placeId)
        .firstOrNull
        ?.polygon;
    if (polygon == null || polygon.length < 3) return _storeFocusZoom;

    final box = storeLabelBoxMeters(polygon: polygon, bearingDeg: bearing);
    final visibleBandHeight = math.max(
      1.0,
      viewport.height * (1 - bottomSheetFraction) - topInsetPx,
    );
    final fitted = zoomToFitRotatedBox(
      widthMeters: math.max(box.widthM, 3.5),
      heightMeters: math.max(box.heightM, 3.5),
      viewportWidthPx: math.max(1, viewport.width * 0.42),
      viewportHeightPx: math.max(1, visibleBandHeight * 0.46),
      latitude: store.point.latitude,
    );
    return fitted.clamp(_storeFocusMinZoom, _storeFocusMaxZoom).toDouble();
  }

  /// 검색 결과에서 고른 **건물**의 바깥 모습이 보이도록 카메라를 옮긴다. 건물은
  /// 면이라 입구 좌표 하나로 옮기면 큰 건물이 화면 밖으로 삐져나간다.
  ///
  /// **여기서 실내로 들어가지 않는다.** 외곽선을 화면에 꼭 맞추면 그 배율이 곧
  /// 진입 임계값이라 누르자마자 도면이 열렸다 — 배율은 [exteriorViewZoomFor]가
  /// 정한다(진입 판정과 같은 파일에 두어 어긋날 수 없게 묶었다).
  Future<void> focusBuilding(Building building) async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;

    // **목록 응답으로 온 건물은 외곽선이 없다.** `/buildings`는 id·이름·층만
    // 내려주고 `footprint_wgs84`·`entrance`는 단건(`/buildings/{id}`)에만 있다
    // (같은 이유로 [_fetchAllBuildings]가 목록으로 단건 캐시를 채우지 않는다).
    // 검색 결과의 건물 한 줄은 그 목록에서 나오므로, 여기 그대로 쓰면 옮길
    // 좌표가 하나도 없어 아무 일도 일어나지 않는다 — 화면에서는 "눌렀는데
    // 지도가 안 움직인다"로만 보인다.
    final resolved = building.id == _building?.id
        // 지금 지도에 올라온 건물이면 이미 단건으로 받아 둔 것을 쓴다.
        ? _building!
        : (await buildingRepository.getBuilding(building.id) ?? building);
    if (!mounted) return;

    final footprint = resolved.footprintWgs84;
    final center = footprint == null || footprint.length < 3
        ? null
        : _buildingCenter(footprint);
    if (footprint != null && center != null) {
      final width = polygonWidthMeters(footprint);
      // 폭이 0이면 zoom 계산이 발산한다. 그런 외곽선은 점이나 마찬가지라
      // 아래 입구 폴백으로 흘려보낸다.
      if (width > 0) {
        final zoom = exteriorViewZoomFor(
          buildingWidthMeters: width,
          viewportWidthPx: MediaQuery.sizeOf(context).width,
          latitude: center.latitude,
        );
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(_toGl(center), zoom),
        );
        // 카메라만 움직이면 "뭔가 지나갔다"로 끝난다. 건물을 탭했을 때와 같은
        // 반짝임을 줘서 어느 건물을 말하는 것인지 화면에 못 박는다.
        await _flashBuildingFill();
        return;
      }
    }

    final entrance = resolved.entrance;
    if (entrance == null) {
      // 옮길 좌표가 하나도 없다. 조용히 끝내면 "눌렀는데 아무 일도 안 일어난다"의
      // 원인을 화면 밖에서 찾을 수 없다 — 실제로 이 침묵 때문에 목록 응답에
      // 외곽선이 없다는 사실을 한참 뒤에야 찾았다.
      debugPrint(
        '[outdoor overlay] focusBuilding ${building.id}: 좌표 없음 '
        '(footprint=${footprint?.length ?? 0}pts, entrance=null)',
      );
      return;
    }
    await controller.animateCamera(CameraUpdate.newLatLng(_toGl(entrance)));
  }

  /// 하단 바 "위치 지정" 버튼 진입점. PDR 세션이 꺼져 있으면 활성 층으로 시작
  /// 하고, 이미 켜져 있으면(다른 층에서 이어서 진입 등) 앵커만 다시 잡도록
  /// 대기 상태로 넘긴다. 실제 탭 처리는 [_onMapPressedForPdr]가 맡는다.
  Future<void> startLocationPlacement() async {
    if (!_indoorEntered) {
      // 실내 진입 오버레이가 아직 열리지 않은 상태에서 호출되면 (예: 사용자가
      // 하단 세그먼트에서 실내로 갔다가 다시 야외로 온 뒤 눌렀을 때) 오버레이를
      // 먼저 켜서 다음 동작을 알린다.
      _autoIndoorEntryArmed = false;
      _setIndoorEntered(true);
    }
    final floor = _activeFloor;
    final graph = _floorGraph;
    if (floor == null ||
        graph == null ||
        graph.nodes.isEmpty ||
        graph.edges.isEmpty) {
      _showSnack('이 층은 위치 지정에 필요한 지도 정보가 아직 없습니다.');
      return;
    }
    // 위치를 다시 지정하는 것은 기준점을 새로 잡는 것이다. 세션을 이 층에 맞추고
    // 이전 기준점 기준의 궤적·보정을 비우는 일은 모두 여기서 처리한다.
    if (!await _bindPdrSessionToFloor(floor, announceFailure: true)) return;
    _setPlacingAnchor(true);
    _showSnack('지도에서 현재 서 있는 위치를 탭해 지정해주세요.');
  }

  /// [xM], [yM]에 가장 가까운 그래프 노드 id. 실내 화면의 동명 헬퍼와 같은
  /// 계산이다.
  String? _nearestGraphNodeId(List<GraphNode> nodes, double xM, double yM) {
    GraphNode? nearest;
    double? nearestDistanceSquared;
    for (final node in nodes) {
      final dx = node.xM - xM;
      final dy = node.yM - yM;
      final distanceSquared = dx * dx + dy * dy;
      if (nearestDistanceSquared == null ||
          distanceSquared < nearestDistanceSquared) {
        nearestDistanceSquared = distanceSquared;
        nearest = node;
      }
    }
    return nearest?.id;
  }

  /// 마지막으로 띄운(아직 닫히지 않은) 스낵바 문구. 같은 문구의 연속 재표시를
  /// 막는 근거다.
  String? _visibleSnackMessage;

  @override
  Widget build(BuildContext context) {
    // 어느 경로로 상태가 바뀌든 여기서 한 번 보고한다. 상태를 바꾸는 자리마다
    // 호출을 흩뿌리면 반드시 한 곳을 빠뜨리고, 그러면 배너가 남거나 안 뜬다.
    // 같은 값이면 알리지 않으므로 매 프레임 불러도 부모가 다시 그리지 않는다.
    _reportFloorTransitionUi();
    return _buildBody();
  }
}
