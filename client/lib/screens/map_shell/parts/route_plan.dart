// ignore_for_file: invalid_use_of_protected_member
//
// part라 `setState`(protected) 호출이 경고로 잡힌다.
/// `_MapShellScreenState`의 **길찾기 두 칸 입력** 부분.
///
/// part 규약과 이 파일로 가른 이유는 `docs/client/structure-plan.md` 15단계.
part of '../map_shell_screen.dart';

extension _MapShellRoutePlan on _MapShellScreenState {
  // ---------------------------------------------------------------------
  // 길찾기 — 상단 바의 출발/도착 두 칸 + 그 위 이동 수단 줄.
  //
  // 시트가 아니라 여기로 옮긴 이유는 [_routeMode] 주석에 있다.
  // ---------------------------------------------------------------------

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
    _lastTransitQuery = null;
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
    // 이 함수는 [_onRouteFieldFocused]를 거치지 않고 칸을 직접 연다. 시트를
    // 걷는 일도 그래서 여기 한 번 더 있다([_closeSheetsUnderTopPanel]).
    _closeSheetsUnderTopPanel();
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
      // 화면에 적힌 층과 실제로 가는 층이 어긋나지 않게 지금 층을 함께 넘긴다.
      // 안 넘기면 거리를 모를 때 색인 첫 줄(B6)이 대표가 된다.
      currentFloorId: _activeIndoorFloor,
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

  void _onRouteFieldFocused(RoutePlanField field, String query) {
    if (_routeEditingField == field) return;
    // 후보 목록도 검색 패널과 **같은 자리**를 쓴다([_closeSheetsUnderTopPanel]).
    _closeSheetsUnderTopPanel();
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
      _MapShellScreenState._routeSearchDebounceDelay,
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
      await _startRoute(origin: destination, destination: origin);
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
    await _startRoute(origin: destination, destination: replacement);
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
    _routeSearchSeq++;
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

  /// 경로 행을 편집하는 동안은 지도 탭도 같은 입력의 다른 방법이다.
  DirectionsMapPickTarget? get _routeMapPickTarget =>
      switch (_routeEditingField) {
        RoutePlanField.origin => DirectionsMapPickTarget.origin,
        RoutePlanField.destination => DirectionsMapPickTarget.destination,
        null => null,
      };

  /// 지금 화면에서 고를 수 있는 이동 수단.
  ///
  /// 대중교통은 카카오 키가 주입됐을 때만 낀다. 키 없이 띄우면 누를 때마다
  /// 실패 안내만 나오는 버튼이 된다.
  List<RoutePlanMode> get _availableTravelModes => [
    for (final mode in RoutePlanMode.values)
      if (mode != RoutePlanMode.transit || transitRepository.isAvailable) mode,
  ];

  /// 지금 계획 중인 것이 **건물 안에서 건물 안으로** 가는 경로인지.
  ///
  /// 참이면 이동 수단 줄을 아예 띄우지 않는다. [_startRoute]가 이미 도보로
  /// 못박는데 화면에는 세 수단이 떠 있었고, 직접 누르면 [_onTravelModePicked]가
  /// 자동 선택을 건너뛰어 그 못이 풀렸다 — 실내 구간이 통째로 빠진 자동차
  /// 경로가 그려진다. 눌리면 안 되는 버튼은 띄우지 않는다.
  ///
  /// **두 끝점을 다 본다.** 도착지만 보고 감췄더니 "서울창업허브 → 샤브미담"
  /// 처럼 멀리서 건물 안 매장을 찍는 길에서 자동차·대중교통이 함께 사라졌다 —
  /// 그건 실내 안내가 아니라 야외 이동이 대부분인 여정이다.
  ///
  /// 판정 규칙과 그 근거는 [isIndoorOnlyWalk]에 있다 — 도보 갈래를 정하는
  /// [classifyWalkRoute] 바로 옆에 둬야 둘이 갈리지 않는다.
  bool get _indoorOnlyRoutePlanned => isIndoorOnlyWalk(
    origin: _selectedOrigin,
    destination: _routeDraftDestination,
    indoorContextActive: _indoorContextActive,
  );

  /// 두 끝점이 검색어가 아니라 실제 위치로 확정됐는지.
  ///
  /// 빈 출발지는 현재 위치라는 유효한 선택이다. 반대로 글자가 있으면 후보를
  /// 골라 [_selectedOrigin]이 생겨야 확정이다. 편집 중에는 기존 값을 지웠을 수
  /// 있으므로 이동수단을 잠시 감춘다.
  bool get _routeEndpointsReady =>
      _routeEditingField == null &&
      _routeDraftDestination != null &&
      (_routeOriginController.text.trim().isEmpty || _selectedOrigin != null);

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

  /// 지도에서 고르는 중에 **매장이 아닌 곳**을 눌렀을 때. 매장을 눌렀을 때와
  /// **완전히 같은 처리**를 태운다 — 갈리면 "복도로 지정한 출발지만 위치 아이콘이
  /// 안 따라온다" 같은 절반짜리 동작이 생긴다.
  ///
  /// 고르는 중이 아니면 아무 일도 하지 않는다(지도 쪽도 막지만, 두 값이 한 프레임
  /// 어긋나는 순간을 없애려 상태 주인이 한 번 더 막는다).
  void _onMapPointPicked(PoiSearchResult picked) {
    final target = _routeMapPickTarget;
    if (target == null) return;
    _applyMapPick(picked, target);
  }

  /// 지도 탭으로 확정된 지점을 출발지/도착지에 반영한다. 매장 탭과 복도 탭이
  /// 공유하는 유일한 경로다.
  void _applyMapPick(PoiSearchResult match, DirectionsMapPickTarget target) {
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
}
