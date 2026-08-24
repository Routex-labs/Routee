import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../service_locator.dart';
import '../../../../domain/event/building_events.dart';
import '../../../../domain/route/dijkstra.dart';
import '../../../../domain/store/nearby_stores.dart';
import '../../../../models/place/favorite_place.dart';
import '../../../../models/place/place_detail.dart';
import '../../../../models/place/store_index_entry.dart';
import '../../../../repositories/place/place_detail_repository.dart';
import '../../../../routing/place_link.dart';
import 'place_detail/place_detail_hours_section.dart';
import 'place_detail/place_detail_nearby_section.dart';
import 'place_detail/place_detail_rich_sections.dart';
import 'place_detail/place_detail_sections.dart';
import '../../../../widgets/map_overlay_guard.dart';
import '../../../../widgets/map_pass_through_sheet_route.dart';
import '../../../../domain/category/subcategory_label.dart';
import 'sheet_drag_dismiss.dart';

/// 매장 상세 시트가 처음 올라올 때 보여야 하는 높이(논리 픽셀).
///
/// **이름·층·업종·출발·도착에 사진 윗부분까지**다. 이름·버튼까지만 담는
/// 230도 화면에서 비교했는데, 사진이 있는 매장에서 사진이 통째로 숨어
/// "있는지도 모르는" 상태가 됐다. 대신 사진이 없는 매장에서는 버튼 아래가
/// 조금 빈다 — 매장마다 내용 길이가 다른데 높이는 하나라서, 어느 값을 골라도
/// 한쪽은 손해다. 셋을 나란히 보고 이 값으로 정했다.
///
/// **비율이 아니라 픽셀인 이유가 있다.** 담아야 할 내용의 높이는 화면 크기와
/// 무관하게 거의 고정인데, 비율로 잡으면 짧은 화면에서 버튼이 잘린다 —
/// 0.25로 고정했다가 위젯 테스트(600px 화면)에서 출발·도착이 사라져 17건이
/// 깨졌다. 비율은 [placeDetailSheetInitialSize]가 화면 높이에서 계산한다.
const double kPlaceDetailSheetPeekPx = 343;

/// [kPlaceDetailSheetPeekPx]를 [screenHeight]에 대한 비율로. 상·하한은 안전장치다
/// — 너무 낮으면 잡을 것이 없고, 너무 높으면 줄이려던 이동 거리가 되돌아온다.
///
/// 예전에는 화면 절반(0.5) 고정이었다. 매장을 바꿔 누를 때마다 그 절반을
/// 내려갔다 올라와(260ms + 380ms) 눈이 피로하다는 지적을 받았다.
///
/// **이 값은 지도 카메라와 짝을 이룬다.** 매장을 고르면 지도가 그 매장으로
/// 이동하는데, 시트가 덮는 만큼 위로 밀어 올려야 매장이 시트 뒤에 숨지 않는다.
/// `MapShellScreen`이 같은 함수를 불러 지도에 넘기므로 **여기만 바꾸면 카메라도
/// 따라온다** — 이동 거리를 줄이면 카메라 리프트도 함께 줄어 두 모션이 동시에
/// 작아진다.
double placeDetailSheetInitialSize(double screenHeight) => screenHeight <= 0
    ? 0.5
    : (kPlaceDetailSheetPeekPx / screenHeight).clamp(0.22, 0.5);

/// 첫 등장 전환. 바닥에서 올라오는 그 동작이 "새로 떴다"를 말해 준다.
///
/// **일부러 느리다.** 빠르게 튀어 오르면 주변시가 그 움직임에 끌려 지도를 보던
/// 눈이 아래로 딸려 내려간다. 같은 거리라도 천천히 오르면 시선을 낚아채지 않고
/// "저기에 무언가 생겼다"만 남는다. 나갈 때는 이미 다 읽은 뒤라 그럴 이유가
/// 없어 절반만 쓴다.
const kPlaceDetailSheetAnimationStyle = AnimationStyle(
  duration: Duration(milliseconds: 520),
  reverseDuration: Duration(milliseconds: 260),
  curve: Curves.easeOutCubic,
  reverseCurve: Curves.easeInCubic,
);

/// 지금 떠 있는 상세 시트의 라우트. 없으면 null.
///
/// **전역이지만 하나뿐이다.** 셸이 "상세 시트는 한 번에 하나"를 강제하므로
/// (`_openStoreFromMap`이 열려 있으면 먼저 닫는다) 이 참조가 가리킬 대상은 늘
/// 하나다. 나가는 전환을 바꾸려면 그 라우트를 잡고 있어야 하는데, 반환값은
/// Future 하나뿐이라 호출부가 라우트를 볼 길이 없다.
MapPassThroughSheetRoute<StoreInfoAction>? _currentRoute;

/// 지금 떠 있는 상세 시트를 **애니메이션 없이 즉시** 걷어낸다. 있었으면 true.
///
/// 다른 매장으로 갈아 끼우기 직전에 부른다. `pop`은 내려가는 260ms를 그대로
/// 재생하는데, 그 자리에 곧바로 새 시트가 뜨므로 내려갈 이유가 없다.
/// `removeRoute`는 전환을 건너뛰고 라우트를 떼어 낸다.
bool removePlaceDetailRouteImmediately(BuildContext context) {
  final route = _currentRoute;
  if (route == null) return false;
  _currentRoute = null;
  Navigator.of(context).removeRoute(route);
  return true;
}

/// 제자리 교체용. **시트 자체의 전환을 사실상 끈다.**
///
/// `ModalBottomSheetRoute`의 올라오는 동작은 `buildTransitions`가 아니라 시트를
/// 앉히는 **레이아웃**이 만든다(애니메이션 값으로 높이를 늘린다). 그래서 전환에
/// 페이드를 얹어도 슬라이드는 그대로 남는다 — 값을 즉시 1로 보내야 안 움직인다.
///
/// 대신 부드러움은 내용 쪽 [_kSwapFadeDuration]이 맡는다.
const kPlaceDetailSheetInstantStyle = AnimationStyle(
  duration: Duration(milliseconds: 1),
  reverseDuration: Duration(milliseconds: 1),
);

/// 시트가 **떠 있는 채로 갈아 끼울 수 있는** 값 묶음.
///
/// 다른 매장을 눌러도 시트를 떼었다 붙이지 않는다 — 떼는 순간 아무것도 없는
/// 프레임이 생겨 번쩍인다(실기기에서 확인). 라우트는 그대로 두고 이 값만 바꾼다.
///
/// 건물 id·저장소·콜백은 여기 없다. 매장이 바뀌어도 안 변하는 것들이라 위젯
/// 필드로 남겨 두는 편이 "무엇이 바뀌는가"를 분명히 한다.
class PlaceDetailTarget {
  const PlaceDetailTarget({
    required this.title,
    required this.subtitle,
    required this.placeId,
    this.favorite,
    this.subcategory,
    this.reach,
    this.event,
  });

  final String title;
  final String subtitle;
  final String? placeId;
  final FavoritePlace? favorite;
  final String? subcategory;
  final NodeReach? reach;

  /// 지금 이 자리에서 열리는 행사. 있으면 [title]은 **행사 이름**이고 원래 매장
  /// 이름은 [subtitle]로 내려간다 — `POP-UP ICONIC B2`보다 `명탐정 코난`이
  /// 사용자가 찾아온 이름이다. 판단은 [PlaceDetailTarget]을 만드는 쪽이 한다.
  final BuildingEvent? event;
}

/// 장소 상세 시트에서 호출자에게 돌려주는 다음 동작.
///
/// 예전에는 `viewCategory`가 하나 더 있었는데, 대분류 칩을 시트에서 걷어낸 뒤로
/// **아무도 그 값을 만들지 않았다.** 호출부에는 그 값을 받는 분기만 남아 있어,
/// 카테고리 시트가 매장 시트를 거쳐 자기 자신을 다시 여는 것처럼 읽혔다. 실제로
/// 도달할 수 없는 경로라 지운다.
enum StoreInfoAction { setOrigin, setDestination }

/// 매장 상세 시트.
///
/// 이름·층·카테고리와 길찾기 버튼은 이미 검색 결과에 있으므로 즉시 표시한다.
/// 실패하거나 [placeId]가 없는 기존 저장 장소에서는 조용히 본문만 비운다.
class PlaceDetailSheet extends StatefulWidget {
  const PlaceDetailSheet({
    super.key,
    required this.target,
    required this.buildingId,
    this.nearbyStoresLoader,
    this.onSelectNearbyStore,
    this.onShowEvent,
    this.repository,
    required this.onCloseAll,
  });

  /// 지금 보여 줄 매장. **값이 바뀌면 시트를 다시 만들지 않고 내용만 바꾼다.**
  final ValueListenable<PlaceDetailTarget> target;

  final String buildingId;

  /// 이 매장에서 가까운 다른 매장을 찾아 온다. 인자는 **이 매장의 입구 노드**다.
  ///
  /// [PlaceDetailTarget.reach]와 **기준이 다르다** — 이쪽은 사용자가 아니라 이
  /// 매장에서 잰 거리다.
  /// 같은 기준으로 두 번 적으면 두 번째 줄이 알려 주는 게 없다.
  ///
  /// 시트가 그래프·매장 색인을 직접 들고 오지 않는 이유는, 둘 다 상위(지도 화면)가
  /// 이미 캐시해 두고 검색·경로에 쓰는 것이기 때문이다. 여기서 다시 받아 오면 같은
  /// 데이터가 두 벌이 되고, 무엇보다 시트를 테스트하려면 그래프를 만들어야 한다.
  final Future<List<NearbyStore>> Function(String entranceNodeId)?
  nearbyStoresLoader;

  /// 근처 매장 줄을 눌렀을 때. null이면 누를 수 없는 목록으로 그린다.
  final void Function(StoreIndexEntry store)? onSelectNearbyStore;

  /// 행사 카드를 눌렀을 때. null이면 카드는 읽기만 하는 표시로 남는다.
  ///
  /// 시트가 포스터를 직접 띄우지 않는 이유는 **닫는 순서 때문**이다. 시트의
  /// `context`로 라우트를 얹으면 시트가 먼저 닫힐 때 그 위의 포스터가 갈 곳을
  /// 잃는다. 라우트를 쌓는 일은 셸이 한 곳에서 맡는다.
  final void Function(BuildingEvent event)? onShowEvent;

  /// 테스트에서는 가짜를 넣고, 앱에서는 service locator의 전역 저장소를 쓴다.
  final PlaceDetailRepository? repository;
  final VoidCallback onCloseAll;

  static Future<StoreInfoAction?> show(
    BuildContext context, {
    required ValueListenable<PlaceDetailTarget> target,
    required String buildingId,
    Future<List<NearbyStore>> Function(String entranceNodeId)?
    nearbyStoresLoader,
    void Function(StoreIndexEntry store)? onSelectNearbyStore,
    void Function(BuildingEvent event)? onShowEvent,
    PlaceDetailRepository? repository,
    required VoidCallback onCloseAll,
    bool crossFade = false,
  }) {
    final navigator = Navigator.of(context);
    final route = MapPassThroughSheetRoute<StoreInfoAction>(
      // 이미 시트가 떠 있던 자리를 이어받으면 올라오지 않고 내용만 바뀐다.
      crossFade: crossFade,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      isScrollControlled: true,
      isDismissible: true,
      sheetAnimationStyle: crossFade
          ? kPlaceDetailSheetInstantStyle
          : kPlaceDetailSheetAnimationStyle,
      // 곡률은 시트 표면이 그린다([RoutexBottomSheet]). 라우트에도 적으면 같은
      // 값이 두 곳에서 정해진다.
      backgroundColor: Colors.transparent,
      builder: (context) => MapOverlayGuard(
        child: PlaceDetailSheet(
          target: target,
          buildingId: buildingId,
          nearbyStoresLoader: nearbyStoresLoader,
          onSelectNearbyStore: onSelectNearbyStore,
          onShowEvent: onShowEvent,
          repository: repository,
          onCloseAll: onCloseAll,
        ),
      ),
    );
    _currentRoute = route;
    return navigator.push<StoreInfoAction>(route).whenComplete(() {
      // 다음 시트가 이미 자리를 이어받았으면 그쪽 참조를 지우지 않는다.
      if (identical(_currentRoute, route)) _currentRoute = null;
    });
  }

  @override
  State<PlaceDetailSheet> createState() => _PlaceDetailSheetState();
}

class _PlaceDetailSheetState extends State<PlaceDetailSheet> {
  bool _intentionalPop = false;
  bool _isLoading = false;

  /// 위젯이 아니라 응답 모델을 들고 있는다. `kind`(excluded 판정)와 `provenance`
  /// (출처 노출)를 build 시점에 봐야 하기 때문이다 — 설계 7-A-3·7-A-4.
  PlaceDetail? _detail;

  /// 근처 매장. 비어 있으면 섹션을 통째로 그리지 않는다.
  List<NearbyStore> _nearbyStores = const [];

  /// 저장 결과 알림. **한 번에 한 개다.**
  ///
  /// 예전에는 `ScaffoldMessenger`의 SnackBar를 썼다. 이 시트는 `Navigator`에 얹힌
  /// 모달이라 SnackBar를 그리는 `Scaffold`가 시트 아래에 있고, 그래서 결과가 시트에
  /// 가려 보이지 않을 수 있었다 — 눌렀는데 아무 일도 안 일어난 것과 구분되지 않는다.
  String? _saveNotice;
  Timer? _saveNoticeTimer;

  /// 주차·에스컬레이터·엘리베이터 1,007건. 서버가 404 대신 `excluded`로 200을
  /// 주고, "시트를 열지 말지"는 클라이언트가 이 값만 보고 정한다(설계 4-1).
  /// 분류 규칙을 클라이언트에 심지 않기 위한 계약이라, 여기서 카테고리 문자열을
  /// 다시 판정하지 않는다.
  bool get _isExcluded => _detail?.kind == PlaceKind.excluded;

  /// 본문에 그릴 섹션. excluded면 비운다.
  ///
  /// 서버가 보내는 `map` 섹션은 여기까지 오지 않는다 — 모델이 파싱하지 않는다.
  /// 담긴 것이 매장 폴리곤인데 지도는 그것을 매장 색인에서 이미 갖고 있고, 화면에
  /// 남은 것은 층 이름 한 줄이라 헤더 배지와 같은 말이었다.
  List<PlaceDetailSection> get _visibleSections =>
      _isExcluded ? const [] : (_detail?.sections ?? const []);

  /// 지금 장소의 공유 링크. 만들 수 없으면 null이고 그때는 공유 버튼도 없다.
  Uri? get _shareLink {
    final placeId = _target.placeId;
    if (placeId == null) return null;
    return buildPlaceLink(buildingId: widget.buildingId, placeId: placeId);
  }

  /// 장소 이름과 링크를 시스템 공유 시트로 넘긴다.
  ///
  /// **취소를 실패로 보지 않는다.** 공유 시트를 열었다 닫는 것은 사용자의 선택이고,
  /// 거기에 오류 문구를 띄우면 아무 문제도 없는 조작이 실패로 읽힌다. 알리는 것은
  /// 플랫폼 호출 자체가 던졌을 때뿐이다.
  ///
  /// iPad는 popover가 뜰 자리를 요구한다. 0 크기를 주면 그 자리에서 공유를 거부하므로
  /// 헤더가 실제로 차지한 사각형을 넘긴다.
  Future<void> _share() async {
    final link = _shareLink;
    if (link == null) return;
    final box = context.findRenderObject() as RenderBox?;
    try {
      await Share.share(
        [_target.title, '$link'].join('\n'),
        subject: _target.title,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      );
    } catch (_) {
      if (!mounted) return;
      RoutexToast.show(context, '공유하지 못했습니다');
    }
  }

  /// 길찾기 버튼은 이름 바로 아래 한 곳에만 있다. chain 규약을 타지 않도록
  /// `_markIntentional`을 거친다(F5).
  void _pop(StoreInfoAction action) {
    _markIntentional();
    Navigator.of(context).pop(action);
  }

  /// 끌어내려 닫는다. [_markIntentional]을 부르지 않는다 — 사용자가 판을 치운
  /// 것이라, 뒤로 가기로 닫은 것과 같은 뜻이어야 한다(상세 chain 전체가 정리된다).
  void _closeByDrag() {
    if (mounted) Navigator.of(context).maybePop();
  }

  /// 장소 이름 줄의 X로 상세 chain 전체를 닫는다.
  void _closeAll() {
    _markIntentional();
    widget.onCloseAll();
    Navigator.of(context).maybePop();
  }

  /// 지금 보여 주는 매장. [PlaceDetailSheet.target]이 바뀌면 여기가 따라간다.
  PlaceDetailTarget get _target => widget.target.value;

  /// 어느 매장의 상세를 그리고 있는지. 갈아 끼운 뒤 **늦게 도착한 이전 요청**을
  /// 버리는 데 쓴다 — 안 버리면 A를 누르고 B로 옮겼을 때 A의 상세가 B 위에 얹힌다.
  String? _loadedFor;

  @override
  void initState() {
    super.initState();
    favoritesController.addListener(_onFavoritesChanged);
    widget.target.addListener(_onTargetChanged);
    _loadDetailContent();
  }

  @override
  void dispose() {
    _saveNoticeTimer?.cancel();
    favoritesController.removeListener(_onFavoritesChanged);
    widget.target.removeListener(_onTargetChanged);
    super.dispose();
  }

  /// 다른 매장으로 갈아 끼운다. **시트는 그대로 두고 내용만 바꾼다.**
  ///
  /// 이름·층·업종·길찾기 버튼은 탭 즉시 아는 값이라 곧바로 바뀐다. 본문(사진·
  /// 소개)은 **이전 것을 그대로 둔 채** 새 상세가 도착하면 교체한다 — 비우고
  /// 기다리면 그 빈 구간이 번쩍임으로 보인다.
  void _onTargetChanged() {
    if (!mounted) return;
    // 이전 장소의 저장 알림도 함께 걷는다. 남겨 두면 그 되돌리기가 방금 저장한
    // 곳이 아니라 **지금 보고 있는 곳**을 토글한다 — 문구는 이전 장소를 말하는데
    // 손대는 대상은 다른 장소다.
    _saveNoticeTimer?.cancel();
    _saveNoticeTimer = null;
    _saveNotice = null;
    setState(() {});
    _loadDetailContent();
  }

  void _markIntentional() => _intentionalPop = true;

  void _onFavoritesChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadDetailContent() async {
    final placeId = _target.placeId;
    if (placeId == null) {
      // 상세를 받을 수 없는 장소로 갈아 끼웠다면 이전 매장의 본문을 지운다.
      if (_loadedFor != null && mounted) {
        setState(() {
          _detail = null;
          _nearbyStores = const [];
          _loadedFor = null;
        });
      }
      return;
    }

    // **갈아 끼울 때는 로딩 표시를 두지 않는다.** 이전 매장의 본문이 그대로 떠
    // 있어 알릴 기다림이 없고, 손잡이 아래에서 도는 원은 "시트가 통째로 바뀌는
    // 중"이라는 잘못된 신호가 된다. 처음 열 때만(보여 줄 본문이 아직 없을 때만)
    // 켠다. 근거는 `docs/client/kakao-map-indoor-observation.md`의
    // "교체할 때 로딩 표시를 두지 않는다".
    if (_detail == null) setState(() => _isLoading = true);
    try {
      final detail = await (widget.repository ?? placeDetailRepository)
          .getPlaceDetail(widget.buildingId, placeId);
      // 그 사이 다른 매장으로 옮겼으면 이 응답은 이미 남의 것이다.
      if (placeId != _target.placeId) return;
      if (mounted && detail != null) {
        setState(() {
          _detail = detail;
          _loadedFor = placeId;
          // 이전 매장의 근처 목록이 남아 있으면 새 상세와 섞인다.
          _nearbyStores = const [];
        });
        // 상세가 온 **뒤에** 시작한다. 근처 매장은 이 매장의 입구 노드에서 재는데,
        // 그 값이 상세 응답에 들어 있기 때문이다.
        unawaited(_loadNearbyStores(detail));
      }
    } catch (_) {
      // 상세 조회는 부가 정보다. 실패를 다이얼로그로 승격하면 길찾기를 막는다.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 근처 매장. **본문 로딩을 붙잡지 않는다** — 그래프를 받아 다익스트라를 한 번
  /// 도는 일이라, 이걸 기다리면 이미 받아 둔 소개·메뉴까지 늦게 뜬다. 목록이
  /// 준비되면 아래에 조용히 붙는다.
  Future<void> _loadNearbyStores(PlaceDetail detail) async {
    final loader = widget.nearbyStoresLoader;
    final entranceNodeId = detail.location.entranceNodeId;
    // 입구 노드가 없으면 잴 출발점이 없다. 이 매장은 길찾기 버튼도 안 나온다.
    if (loader == null || entranceNodeId == null) return;

    try {
      final nearby = await loader(entranceNodeId);
      if (mounted) setState(() => _nearbyStores = nearby);
    } catch (_) {
      // 그래프를 못 받았거나 끊겼다. 목록만 빠지고 상세는 그대로 뜬다.
    }
  }

  Future<void> _onToggleFavorite() async {
    final favorite = _target.favorite;
    if (favorite == null) return;
    await favoritesController.toggle(favorite);
    if (!mounted) return;
    // 컴포넌트가 넘긴 값이 아니라 controller의 실제 상태를 읽는다. 저장이
    // 실패했는데 성공했다고 말하지 않기 위해서다.
    _showSaveNotice(favoritesController.contains(favorite.key));
  }

  /// 저장 한 사건에 알림 한 개. 이전 알림은 새 알림이 걷어낸다 — 같은 자리에 둘이
  /// 쌓이면 어느 쪽이 방금 누른 결과인지 알 수 없다.
  void _showSaveNotice(bool saved) {
    _saveNoticeTimer?.cancel();
    setState(() => _saveNotice = saved ? '장소에 저장했습니다' : '저장을 해제했습니다');
    _saveNoticeTimer = Timer(
      RoutexFeedbackTiming.noticeVisibility,
      _dismissSaveNotice,
    );
  }

  void _dismissSaveNotice() {
    _saveNoticeTimer?.cancel();
    _saveNoticeTimer = null;
    if (mounted) setState(() => _saveNotice = null);
  }

  /// 알림의 되돌리기.
  ///
  /// 되돌린 결과를 다시 알리지 않는다. 한 번의 탭에 알림이 두 개 뜨는 것을 막고,
  /// 헤더의 저장 토글이 이미 바뀐 상태를 말하고 있다. 이 지름길을 놓쳐도 그 토글로
  /// 언제든 되돌릴 수 있어서 알림은 시간이 지나면 사라져도 된다.
  Future<void> _undoSave() async {
    final favorite = _target.favorite;
    if (favorite == null) return;
    _dismissSaveNotice();
    await favoritesController.toggle(favorite);
  }

  @override
  Widget build(BuildContext context) {
    final favorite = _target.favorite;
    final saved =
        favorite != null && favoritesController.contains(favorite.key);
    final subcategory = _target.subcategory;
    final sections = _visibleSections;
    final heroItems = [
      for (final section in sections.whereType<HeroSection>())
        for (final item in section.items)
          RoutexMediaItem(image: AssetImage(item.localAsset)),
    ];
    final initialSize = placeDetailSheetInitialSize(
      MediaQuery.sizeOf(context).height,
    );

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_intentionalPop) widget.onCloseAll();
      },
      // **여기에 전체 화면 `GestureDetector(opaque)`를 두면 안 된다.**
      // `isScrollControlled: true`라 child가 화면 전체 높이를 차지해, 위쪽 투명한
      // 영역까지 히트 테스트에 걸려 지도가 보이는데 만질 수 없게 된다
      // ([MapPassThroughSheetRoute] 주석의 세 겹 중 두 번째).
      //
      // `expand: false`면 실제로 그려지는 영역만 잡히고 그 위는 포인터를 흘린다.
      child: DraggableScrollableSheet(
        initialChildSize: initialSize,
        // **초기 높이보다 크면 안 된다.** 크면 시트가 뜨자마자 최소 높이까지
        // 스스로 튀어 올라, 줄이려던 세로 운동이 오히려 하나 더 생긴다.
        //
        // 그렇다고 **같아서도 안 된다.** 같으면 본문을 잡고 내려도 시트가 내려갈
        // 자리가 없어 손이 헛돈다 — 닫을 수 있는 곳이 손잡이 언저리뿐인 것처럼
        // 느껴지던 원인이다. 아래로 여유를 두고, 그 여유를 다 쓰기 전에
        // [_dismissRatio]에서 닫는다.
        minChildSize: initialSize * kSheetMinRatio,
        maxChildSize: 0.92,
        // 놓으면 처음 높이나 끝까지 중 가까운 쪽으로 붙는다. 없으면 반쯤 내린
        // 어중간한 높이에 그대로 멎는다.
        snap: true,
        snapSizes: [initialSize],
        expand: false,
        builder: (context, scrollController) => GestureDetector(
          onTap: () {},
          behavior: HitTestBehavior.opaque,
          // 표면(색·곡률·그림자·자르기)은 Runtime Kit이 소유하고, 드래그와 라우트는
          // 여기 남는다([MapPassThroughSheetRoute]). 여백은 본문이 갖는다 — 대표
          // 사진이 가장자리까지 닿아야 해서 표면이 넣어 주면 표현할 수 없다.
          child: SheetDragDismiss(
            initialSize: initialSize,
            onDismiss: _closeByDrag,
            child: RoutexBottomSheet(
              contentInset: RoutexBottomSheetContentInset.content,
              child: Stack(
                children: [
                  ScrollConfiguration(
                    behavior: const _NoOverscrollIndicator(),
                    child: SingleChildScrollView(
                      controller: scrollController,
                      // 키보드(`viewInsets`)만큼 아래를 더 비운다. 이 시트는 화면 높이의
                      // 비율로 크기가 정해져서 키보드가 올라와도 **줄어들지 않는다** —
                      // 아래쪽이 키보드에 덮인 채로 남는다. 그 자리에 있는 입력칸은
                      // 가려지고, 스크롤로 끌어올리려 해도 스크롤할 길이가 없어서 꺼낼
                      // 수가 없다. 여기서 길이를 만들어 줘야 [_MenuSearchField]가
                      // 자기를 보이는 자리로 올릴 수 있다.
                      padding: EdgeInsets.only(
                        bottom:
                            20 +
                            MediaQuery.paddingOf(context).bottom +
                            MediaQuery.viewInsetsOf(context).bottom,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const RoutexSheetHandle(),
                          _SheetLoadingLine(visible: _isLoading),
                          // Showcase의 장소 상세와 같은 조립 순서다:
                          // 장소 이름/메타/X → 출발·도착/공유/저장 → 대표 사진 → 본문.
                          // 사진이 없을 때도 overview는 그대로 첫 내용이 된다.
                          PlaceDetailSections(
                            sections: sections,
                            showHeroCarousel: false,
                            // **행사 카드는 overview 안에 붙인다.** overview가 그냥
                            // Widget이라 새 슬롯을 만들 이유가 없다. 자리도 여기가
                            // 맞다 — 이름·행동 바로 밑, 서버 본문보다 위다.
                            overview: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                RoutexPlaceOverview(
                                  mediaItems: heroItems,
                                  name: _target.title,
                                  metadata: [
                                    if (_target.subtitle.isNotEmpty)
                                      _target.subtitle,
                                    ?subcategoryLabelFor(subcategory),
                                  ].join(' · '),
                                  saved: saved,
                                  onClose: _closeAll,
                                  onSaved: favorite == null
                                      ? null
                                      : (_) => _onToggleFavorite(),
                                  onShare: _shareLink == null ? null : _share,
                                  onOrigin: () =>
                                      _pop(StoreInfoAction.setOrigin),
                                  onDestination: () =>
                                      _pop(StoreInfoAction.setDestination),
                                ),
                                if (_target.event case final event?)
                                  _EventCard(
                                    event: event,
                                    onTap: widget.onShowEvent == null
                                        ? null
                                        : () => widget.onShowEvent!(event),
                                  ),
                              ],
                            ),
                            homeFooter: _nearbyStores.isEmpty
                                ? null
                                : PlaceNearbySection(
                                    stores: _nearbyStores,
                                    onSelect: widget.onSelectNearbyStore,
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 스크롤과 함께 흘러가지 않게 시트 안에 고정한다. 결과를 말하는
                  // 줄이 본문을 따라 올라가 버리면, 저장을 누른 뒤 목록을 조금만
                  // 내려도 되돌리기가 화면 밖으로 나간다.
                  if (_saveNotice case final notice?)
                    PositionedDirectional(
                      start: RoutexSpacing.componentPadding,
                      end: RoutexSpacing.componentPadding,
                      bottom:
                          MediaQuery.paddingOf(context).bottom +
                          RoutexSpacing.componentPadding,
                      child: RoutexInlineNotice(
                        message: notice,
                        actionLabel: '실행 취소',
                        onAction: _undoSave,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 본문 끝에서 내용이 늘어나는 overscroll 표시를 끈다.
///
/// 이 시트는 스크롤 제스처를 이미 두 가지로 쓰고 있다 — 위로 끌면 시트가 커지고,
/// 끝에서 아래로 끌면 닫힌다([DraggableScrollableSheet]). 거기에 끝에서 내용이
/// 늘어나는 표시까지 겹치면 "아직 더 볼 게 남았다"는 잘못된 신호가 된다.
///
/// **표시만 끄고 물리는 건드리지 않는다.** 스크롤 physics를 바꾸면 시트를
/// 끌어 키우고 줄이는 동작 자체가 이 스크롤의 overscroll에 얹혀 있어서 함께 깨진다.
class _NoOverscrollIndicator extends MaterialScrollBehavior {
  const _NoOverscrollIndicator();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

/// 손잡이 **바로 아래**에 놓이는 얇은 로딩 줄. **처음 열 때만 뜬다** —
/// 다른 매장으로 갈아 끼울 때는 이전 본문이 그대로 있어 알릴 기다림이 없다
/// ([_PlaceDetailSheetState._loadDetailContent]).
///
/// 예전에는 본문에 회색 막대를 놓고, 갈아 끼울 때는 시트 전체를 페이드했다.
/// 전체 페이드는 내용이 사라졌다 다시 뜨는 것처럼 보여 번쩍였다 — 시트가
/// 그대로 있는데 화면만 깜빡이는 셈이라 오히려 더 눈에 띄었다.
///
/// 로딩이 끝난 뒤에는 높이도 없앤다. 보이지 않는 18dp 슬롯을 남겨 두면 핸들과
/// 헤더 사이가 벌어져 상세 시트의 첫 줄이 아래로 처져 보인다.
class _SheetLoadingLine extends StatelessWidget {
  const _SheetLoadingLine({required this.visible});

  final bool visible;

  static const double _height = RoutexMetrics.iconSmall;

  @override
  Widget build(BuildContext context) {
    // **안 보일 때는 트리에서 뺀다.** 투명도만 0으로 두면 인디케이터가 계속
    // 돌아 프레임이 멎지 않는다 — 앱에서는 배터리를, 위젯 테스트에서는
    // `pumpAndSettle`을 영원히 붙잡는다(실제로 26건이 그렇게 멈췄다).
    return SizedBox(
      height: visible ? _height : 0,
      child: visible
          ? const Center(
              child: SizedBox.square(
                key: ValueKey('place-detail-loading'),
                dimension: RoutexMetrics.iconSmall,
                child: CircularProgressIndicator(
                  strokeWidth: RoutexStroke.emphasis,
                ),
              ),
            )
          : null,
    );
  }
}

/// 닫힌 섹션 집합을 화면 위젯으로 바꾼다. 모델 파싱 단계에서 모르는 type은 이미
/// 버려졌지만, 여기서도 타입별로만 분기해 새 서버 섹션이 길찾기 UI를 깨지 않게 한다.
class PlaceDetailSections extends StatefulWidget {
  const PlaceDetailSections({
    super.key,
    required this.sections,
    this.overview,
    this.showHeroCarousel = true,
    this.now,
    this.homeFooter,
  });

  final List<PlaceDetailSection> sections;

  /// 대표 사진 바로 뒤, 나머지 상세 섹션보다 앞에 놓는 장소 요약과 주 행동.
  final Widget? overview;

  /// false면 overview가 같은 대표 사진을 이미 그린다. 사진 탭의 원본으로는
  /// 계속 사용하되 캐러셀을 두 번 만들지 않는다.
  final bool showHeroCarousel;

  /// 영업시간 판정의 기준 시각. 테스트가 넘기고 앱에서는 null이라
  /// [DateTime.now]가 쓰인다 — 시각에 의존하는 화면을 고정할 수 있어야 한다.
  final DateTime? now;

  /// 홈 탭 **맨 아래**에 붙는 블록. 근처 매장이 여기 온다.
  ///
  /// 서버 섹션 배열이 아니라 별도 인자인 이유는, 이 내용이 서버가 내려보내는 값이
  /// 아니라 **클라이언트가 그래프로 계산한 것**이기 때문이다. 섹션 배열에 섞으면
  /// "순서는 서버가 정한다"는 계약(4-2 규칙 3)이 반만 참이 된다.
  ///
  /// 메뉴·사진 탭에는 붙이지 않는다. 그쪽은 이 매장 안의 것을 보러 들어간 자리라,
  /// 옆 매장 목록이 끼면 탭을 나눈 이유가 흐려진다.
  final Widget? homeFooter;

  @override
  State<PlaceDetailSections> createState() => _PlaceDetailSectionsState();
}

/// 상단 탭 이름.
const _homeTab = '홈';
const _menuTab = '메뉴';
const _photoTab = '사진';

class _PlaceDetailSectionsState extends State<PlaceDetailSections> {
  String _activeTab = _homeTab;

  @override
  Widget build(BuildContext context) {
    final hero = widget.sections.whereType<HeroSection>().toList(
      growable: false,
    );
    final menu = widget.sections.whereType<MenuSection>().toList(
      growable: false,
    );
    final home = widget.sections
        .where((section) => section is! HeroSection && section is! MenuSection)
        .toList(growable: false);

    // 대표 사진은 탭 위에 남긴다. 어느 탭을 보고 있든 "무슨 매장인지"는 계속
    // 보여야 하고, 사진 탭은 그 사진들을 한눈에 늘어놓는 자리다.
    final photos = [
      for (final section in hero)
        for (final item in section.items) item.localAsset,
    ];

    // 메뉴가 30종까지 늘면서 한 줄로 이어 붙인 본문이 너무 길어졌다. 영업시간을
    // 보려면 메뉴를 한참 지나야 했고 그 반대도 마찬가지다. 어느 쪽을 보러 왔는지는
    // 사람마다 다르므로 둘을 나란히 두고 고르게 한다. 섹션 **순서**는 그대로 서버가
    // 정하고(계약 4-2 규칙 3), 여기가 하는 것은 묶는 일뿐이다.
    //
    // 있는 탭만 만든다. 탭 하나짜리 탭 바는 아무것도 나누지 않으면서 자리만
    // 차지한다(메뉴 카테고리 탭과 같은 규칙).
    final tabs = [
      if (home.isNotEmpty) _homeTab,
      if (menu.isNotEmpty) _menuTab,
      // 사진이 한 장뿐이면 위 캐러셀이 이미 다 보여 준 것이다.
      if (photos.length > 1) _photoTab,
    ];
    final tabbed = tabs.length > 1;
    final active = tabs.contains(_activeTab) ? _activeTab : tabs.firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showHeroCarousel && hero.isNotEmpty) ...[
          _render(hero),
          const SizedBox(height: RoutexSpacing.contentGap),
        ],
        if (widget.overview case final overview?) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: placeSectionGutter),
            child: overview,
          ),
          if (home.isNotEmpty || menu.isNotEmpty)
            const SizedBox(height: RoutexSpacing.contentGap),
        ],
        if (tabbed) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: placeSectionGutter),
            child: RoutexTabs(
              labels: tabs,
              selectedIndex: tabs.indexOf(active!),
              onSelected: (index) => setState(() => _activeTab = tabs[index]),
            ),
          ),
          const SizedBox(height: 18),
        ],
        if (!tabbed)
          _render([...home, ...menu])
        else if (active == _menuTab)
          _render(menu)
        else if (active == _photoTab)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: placeSectionGutter),
            child: RoutexPhotoGrid(items: _mediaItems(photos)),
          )
        else
          _render(home),
        // 탭이 없으면 본문이 곧 홈이므로 그때도 붙인다.
        if (widget.homeFooter != null && (!tabbed || active == _homeTab)) ...[
          const _SectionBreak(),
          widget.homeFooter!,
        ],
      ],
    );
  }

  Widget _render(List<PlaceDetailSection> sections) {
    final widgets = <Widget>[];
    for (final section in sections) {
      final rendered = switch (section) {
        SummarySection(:final text) => _TitledSection(
          title: '소개',
          child: PlaceSummarySection(text: text),
        ),
        HeroSection(:final items) => Padding(
          // 캐러셀은 페이지 **안쪽**에 여백을 두고 넘긴다. 사진 가장자리를 본문
          // 여백선에 맞추려면 그만큼 뺀 값을 바깥에 준다.
          padding: const EdgeInsets.symmetric(
            horizontal: placeSectionGutter - RoutexSpacing.inlineGap,
          ),
          child: RoutexMediaCarousel(
            items: _mediaItems([for (final item in items) item.localAsset]),
          ),
        ),
        KeyValueSection(:final items) when items.isNotEmpty =>
          RoutexKeyValueRows(
            rows: [
              for (final item in items)
                RoutexKeyValue(label: item.label, value: item.value),
            ],
          ),
        // 라벨만 있고 값이 빈 표는 "정보가 없다"가 아니라 "불러오지 못했다"로
        // 읽힌다. 서버가 빈 목록을 보내지 않지만, 그 계약이 여기까지 오는 길에
        // 끊기면 표가 아니라 아무것도 없는 편이 낫다.
        KeyValueSection() => const SizedBox.shrink(),
        TagsSection(:final tags) => PlaceTagsSection(tags: tags),
        NoticeSection(:final text, :final until) => PlaceNoticeSection(
          text: text,
          until: until,
        ),
        MenuSection(:final items) => PlaceMenuSection(
          items: [
            for (final item in items)
              PlaceMenuItem(
                name: item.name,
                // group을 빠뜨리면 음료·푸드 갈래 탭이 통째로 사라진다. 화면에는
                // 아무 이상이 없어 보이고 316종이 한 목록에 이어 붙을 뿐이라,
                // 빠진 것을 알아채기 어려운 자리다.
                group: item.group,
                category: item.category,
                nameEn: item.nameEn,
                price: item.price,
                description: item.description,
                volume: item.volume,
                calories: item.calories,
                caffeine: item.caffeine,
                allergens: item.allergens,
                badges: item.badges,
                imageAssetPath: item.imageAsset,
              ),
          ],
        ),
        // 영업시간만 렌더러가 시각을 넘긴다. "지금 영업 중"은 저장된 값이 아니라
        // 그릴 때마다 계산되는 값이라, 계산의 기준 시각이 화면 밖에서 들어와야
        // 테스트가 시각에 매이지 않는다.
        HoursSection() => PlaceHoursSection(
          hours: section,
          now: widget.now ?? DateTime.now(),
        ),
        ContactSection(:final tel) => PlaceContactSection(tel: tel),
        DemoInfoSection(:final items) => PlaceDemoInfoSection(
          items: [
            for (final item in items)
              PlaceDemoInfo(label: item.label, value: item.value),
          ],
        ),
        LinksSection(:final items) => PlaceLinksSection(
          items: [
            for (final item in items)
              PlaceLinkItem(
                label: item.label,
                url: item.url,
                iconAsset: item.iconAsset,
              ),
          ],
        ),
        BusinessInfoSection(:final items) => PlaceBusinessInfoSection(
          items: [
            for (final item in items)
              PlaceBusinessInfo(label: item.label, value: item.value),
          ],
        ),
      };
      // 사진은 시트 끝까지, 메뉴는 줄 전체가 눌리도록 스스로 여백을 갖는다.
      // 나머지 섹션만 여기서 본문 거터를 씌운다.
      final fullBleed = section is HeroSection || section is MenuSection;
      final padded = fullBleed
          ? rendered
          : Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: placeSectionGutter,
              ),
              child: rendered,
            );
      // 여백만으로는 섹션이 어디서 끝났는지 읽히지 않는다. 카드로 감싸는 대신
      // 시트 폭을 가로지르는 얇은 선 하나로만 끊는다.
      if (widgets.isNotEmpty) widgets.add(const _SectionBreak());
      widgets.add(padded);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }
}

/// 번들 asset 경로를 사진 항목으로 바꾼다.
///
/// 이 앱의 매장 사진은 전부 번들에 들어 있어서 `AssetImage` 하나로 끝난다. 어디서
/// 가져올지를 Runtime Kit이 정하지 않는 이유는 자산을 갖지 않기 때문이다.
List<RoutexMediaItem> _mediaItems(List<String> assetPaths) => [
  for (final path in assetPaths) RoutexMediaItem(image: AssetImage(path)),
];

/// 섹션과 섹션 사이의 경계. 여백 + 시트 폭을 가로지르는 선 한 줄이다.
class _SectionBreak extends StatelessWidget {
  const _SectionBreak();

  // **여백을 따로 주지 않는다.** `RoutexDivider(section)`의 height가 선과 앞뒤 여백을
  // 함께 잡는다 — 여기서 Padding을 또 씌우면 같은 값이 두 곳에 생겨 경계마다 여백이
  // 두 배가 된다. 실제로 그랬고, 섹션이 선에서 멀찍이 떨어져 보였다.
  @override
  Widget build(BuildContext context) =>
      const RoutexDivider(role: RoutexDividerRole.section);
}

/// 제목 + 본문 한 쌍. 섹션 위젯 자체가 제목을 갖지 않는 경우(소개)에 씌운다.
class _TitledSection extends StatelessWidget {
  const _TitledSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      RoutexSectionHeader(title: title),
      const SizedBox(height: 8),
      child,
    ],
  );
}

/// 상세 시트 위쪽에 붙는 행사 카드. 사진·기간·장소를 한 장에 담는다.
///
/// 매장 이름이 이미 행사 이름으로 바뀌어 있으므로([PlaceDetailTarget.event])
/// 여기서 제목을 다시 적지 않는다 — 같은 글자가 두 줄 겹친다.
class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, this.onTap});

  final BuildingEvent event;

  /// 누르면 포스터 상세로 간다. null이면 누를 수 없는 카드로 그린다 — 특전·
  /// 유의사항이 없는 행사도 있어, 열 것이 없으면 누를 수 있게 두지 않는다.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.routexColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        placeSectionGutter,
        4,
        placeSectionGutter,
        12,
      ),
      child: Material(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (event.image case final path?)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                  child: AspectRatio(
                    // 원본이 정사각·가로 섞여 있어 비율을 카드가 정한다. 사진에
                    // 맞추면 카드 높이가 매장마다 널뛴다.
                    aspectRatio: 16 / 9,
                    child: Image.asset(
                      path,
                      fit: BoxFit.cover,
                      // 에셋이 빠져도 카드는 남아야 한다 — 기간·장소가 본문이다.
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.local_activity_outlined,
                          size: 14,
                          color: colors.accentBrand,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '진행 중인 행사',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: colors.accentBrand,
                          ),
                        ),
                        if (onTap != null) ...[
                          const Spacer(),
                          Text(
                            '자세히',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colors.contentSecondary,
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: colors.contentSecondary,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_date(event.start)} ~ ${_date(event.end)}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.contentPrimary,
                      ),
                    ),
                    if (event.place.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        event.place,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.contentSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// `2026-08-26` → `08.26`.
  static String _date(String iso) {
    final parts = iso.split('-');
    return parts.length == 3 ? '${parts[1]}.${parts[2]}' : iso;
  }
}
