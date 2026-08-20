// ignore_for_file: invalid_use_of_protected_member
//
// part라 `setState`(protected) 호출이 경고로 잡힌다.
/// `_MapShellScreenState`의 **하단 바 버튼 동작** 부분.
///
/// part 규약과 이 파일로 가른 이유는 `docs/client/structure-plan.md` 15단계.
part of '../map_shell_screen.dart';

extension _MapShellBottomBar on _MapShellScreenState {
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

  /// 실내 위치가 없는데 그 위치가 필요한 조작을 했다. **문장 대신 버튼을
  /// 깜빡인다** — 이유는 [MapBottomBar.attentionOnPlaceLocation].
  ///
  /// 스스로 꺼진다. 사용자가 위치를 잡을 때까지 계속 깜빡이면 그 움직임이 곧
  /// 배경이 되어 아무것도 알리지 못한다.
  void _onNeedLocationPlacement() {
    _placeLocationAttentionTimer?.cancel();
    setState(() => _placeLocationAttention = true);
    _placeLocationAttentionTimer = Timer(_placeLocationAttentionDuration, () {
      _placeLocationAttentionTimer = null;
      if (mounted) setState(() => _placeLocationAttention = false);
    });
  }

  /// 깜빡이는 시간. 세 번쯤 깜빡이고 멎는다(주기 700ms × 왕복).
  static const _placeLocationAttentionDuration = Duration(milliseconds: 2100);

  /// "가까운 매장으로 위치 지정" 버튼(하단 바). 들어올 때 띄웠던 목록을 다시 연다.
  ///
  /// 검색을 먼저 닫는 이유는 [_onPlaceLocation]과 같다 — 시트가 검색 패널
  /// 뒤로 들어가면 목록을 볼 수가 없다.
  void _onPickNearbyStore() {
    _closeSearch();
    unawaited(
      _outdoorKey.currentState?.pickNearbyStoreForAnchor() ??
          Future<void>.value(),
    );
  }
}
