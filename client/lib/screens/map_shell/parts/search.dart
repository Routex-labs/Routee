// ignore_for_file: invalid_use_of_protected_member
//
// part라 `setState`(protected) 호출이 경고로 잡힌다.
/// `_MapShellScreenState`의 **검색창·검색 패널** 부분.
///
/// part 규약과 이 파일로 가른 이유는 `docs/client/structure-plan.md` 15단계.
part of '../map_shell_screen.dart';

extension _MapShellSearch on _MapShellScreenState {
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

  void _activateSearch() {
    if (_searchActive) return;
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

  void _onSearchBuildingPicked(Building building) {
    _closeSearch();
    // 카드만 띄우고 지도를 그대로 두면 사용자는 자기가 고른 건물이 화면 어디에
    // 있는지 알 수 없다 — 이름만 적힌 카드가 뜰 뿐 지도는 방금 보던 자리 그대로다.
    // 매장을 골랐을 때 [_showStoreInfo]가 카메라를 옮기는 것과 같은 규칙이다.
    unawaited(
      _outdoorKey.currentState?.focusBuilding(building) ?? Future.value(),
    );
  }

  /// 검색 결과에서 **건물 밖 장소**를 골랐을 때. 매장을 고른 경로와 같은 모양이다
  /// — 검색을 닫고 시트 chain 안에서 그 장소의 시트를 연다.
  Future<void> _onSearchPoiPicked(OutdoorPoi poi) async {
    _closeSearch();
    await _runSheetChain(() => _showOutdoorPoiInfo(poi));
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
}
