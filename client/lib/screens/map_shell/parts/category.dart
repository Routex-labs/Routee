// ignore_for_file: invalid_use_of_protected_member
//
// part라 `setState`(protected) 호출이 경고로 잡힌다.
/// `_MapShellScreenState`의 **카테고리 pill·목록** 부분.
///
/// part 규약과 이 파일로 가른 이유는 `docs/client/structure-plan.md` 15단계.
part of '../map_shell_screen.dart';

extension _MapShellCategory on _MapShellScreenState {
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
    setState(() => _activeFloorNotifier.value = floor);
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
    if (!mounted) return false;
    if (_closeSheetChainRequested || picked == null) {
      // **목록이 그냥 닫혔다 — 첫 매장에 걸어 둔 강조를 여기서 걷는다.**
      // 카메라를 그 매장으로 옮기면서 강조도 함께 서는데
      // ([_focusCategoryFirstStore] → `focusStore`), 지우는 자리가 매장 상세
      // 쪽에만 있었다. 그래서 목록을 X로 닫으면 그 칸 하나가 도면에 남고,
      // 칩을 꺼도 남아 되돌릴 수단이 화면에서 사라졌다(실기기 확인).
      //
      // **상세로 이어지는 아래 갈래에서는 지우지 않는다** — 그쪽이 자기
      // 매장으로 곧바로 다시 세우므로, 여기서 지우면 한 프레임이 빈다.
      _outdoorKey.currentState?.clearHighlight();
      return false;
    }
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

  /// 층 선택기 위 편의시설 버튼. 지금 층의 시설을 **종류로 골라 지도에 띄우고**
  /// 그중 하나를 도착지로 삼는 시트를 연다.
  ///
  /// 고른 종류는 도면 위에 파랗게 칠해지고([facilityHighlightPolygons]) 줄을 누르면
  /// 곧바로 경로가 된다 — 상세 시트를 거치지 않는다. 시설을 찾는 사람이 원하는 것은
  /// 영업시간이나 사진이 아니라 길이다.
  ///
  /// **닫으면 강조도 걷는다.** 남겨 두면 시트를 닫은 사용자가 도면에 걸린 강조를
  /// 되돌릴 수단이 없다(칩 줄의 `편의시설`은 소분류까지 되돌리지 못한다).
  Future<void> _onFacilitiesTap() async {
    if (_facilitiesSheetOpen) return;
    // 색인은 저장소가 캐시한다 — 두 번째부터는 기다림이 없다.
    final index = await buildingRepository.getStoreIndex(_buildingId);
    if (!mounted) return;
    final facilities = [
      for (final entry in index ?? const <StoreIndexEntry>[])
        if (entry.category == kFacilityCategory &&
            kFacilityFilters.any((f) => f.value == entry.subcategory))
          entry,
    ];
    setState(() => _facilitiesSheetOpen = true);
    // 지도 강조가 이 시트의 결과물이라 지도를 잠그지 않는다([_withMapsLocked]를
    // 쓰지 않는 이유). 시트를 놔둔 채 도면을 움직여 확인할 수 있어야 한다.
    final picked = await showFacilityFilterSheet(
      context,
      floorLabel: _activeFloorNotifier,
      facilities: facilities,
      selected: _categorySelection?.category == kFacilityCategory
          ? _categorySelection?.subcategory
          : null,
      onSelected: (value) => _onCategorySelectionChanged(
        value == null
            ? null
            : CategorySelection(
                category: kFacilityCategory,
                subcategory: value,
              ),
      ),
    );
    if (!mounted) return;
    setState(() => _facilitiesSheetOpen = false);
    if (_categorySelection?.category == kFacilityCategory) {
      _onCategorySelectionChanged(null);
    }
    if (picked == null) return;

    // 좌표·노드 해석은 검색·근처 매장과 **같은 경로**를 쓴다([resolveIndexEntry]).
    final resolved = await _outdoorKey.currentState?.resolveIndexEntry(picked);
    if (!mounted) return;
    if (resolved == null) {
      // 도면에서 그 시설을 못 찾았다. 조용히 끝내면 누른 사람에게는 아무 일도
      // 안 일어난 화면이 된다.
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('이 시설의 위치를 찾지 못했습니다')));
      return;
    }
    // **에스컬레이터는 도착지가 아니다**([kNonDestinationSubcategoryValues]).
    // 경로를 그리면 탑승구가 아니라 옆 복도 노드에서 끝나 도착지 이름이 `복도`로
    // 뜬다. 대신 그 자리로 카메라를 옮기고 도면에 강조를 남긴다 — 이 시설에
    // 대해 화면이 정직하게 할 수 있는 일은 어디 있는지 보여 주는 것 하나다.
    if (isNonDestinationSubcategory(picked.subcategory)) {
      await _outdoorKey.currentState?.focusStore(resolved);
      return;
    }
    await _setRouteDestination(candidateForPlace(resolved));
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
}
