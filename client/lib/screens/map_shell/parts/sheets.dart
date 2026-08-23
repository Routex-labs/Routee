// ignore_for_file: invalid_use_of_protected_member
//
// part라 `setState`(protected) 호출이 경고로 잡힌다.
/// `_MapShellScreenState`의 **시트 chain·정보 시트·공유 링크** 부분.
///
/// part 규약과 이 파일로 가른 이유는 `docs/client/structure-plan.md` 15단계.
part of '../map_shell_screen.dart';

extension _MapShellSheets on _MapShellScreenState {
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

  /// 행사 목록에서 고른 매장으로 상세를 연다. 진입점(pill·쪽 카드)이 무엇이든
  /// 여기 하나로 모인다 — 따로 만들면 한쪽만 층을 옮기거나 한쪽만 강조가 빠진다.
  Future<void> _openPickedEvent(StoreIndexEntry? entry) async {
    if (!mounted || entry == null) return;
    // 진입은 맡겨 둔다. 이 목록은 건물 안에서만 열리지만(하단 판), 오버레이가
    // 꺼진 사이에 고른 것까지 포기하면 눌러도 아무 일이 없는 줄이 된다.
    final resolved = await _outdoorKey.currentState?.resolveIndexEntry(
      entry,
      enterBuildingIfNeeded: true,
    );
    if (!mounted || resolved == null) return;
    await _runSheetChain(() => _showStoreInfo(resolved, focusOnMap: true));
  }

  /// 하단 줄의 쪽 카드. 원본과 같은 층 구조로 내려간다 — **쪽 → 그 안의 행사
  /// 목록 → 좌우로 넘겨보는 포스터**. 목록·포스터·안내는 pill이 여는 것과 같은
  /// 화면이고, 갈래로 좁혀 들어간다는 것만 다르다.
  Future<void> _onIssueDiaryPick(EventDiaryPage page) async {
    final entry = await EventsSheet.show(
      context,
      onCloseAll: _requestCloseSheetChain,
      diary: page.diary,
      title: page.title,
    );
    await _openPickedEvent(entry);
  }

  /// 펼친 판의 목록 줄. **목록 시트를 거치지 않고 포스터로 바로 간다** — 판이
  /// 이미 목록이라, 줄을 눌러 같은 목록을 한 번 더 펴면 한 단계가 헛돈다.
  ///
  /// 색인을 여기서 한 번 더 받는 이유는 **판이 그리는 목록과 포스터가 미는 목록이
  /// 같아야** 하기 때문이다(같은 [loadTodayEvents]). 건물 안이면 색인은 이미 받아
  /// 둔 것이 캐시에 있어 기다림이 없다.
  Future<void> _onIssueDiaryEventPick(int index) async {
    final rows = await loadTodayEvents(events: _buildingEvents);
    if (!mounted || index < 0 || index >= rows.length) return;
    final picked = await EventPosterView.show(
      context,
      events: [for (final r in rows) r.event],
      initialIndex: index,
      navigable: [for (final r in rows) r.entry != null],
    );
    // 밀어서 다른 행사를 보다가 눌렀을 수 있다 — 안내는 **그때 고른 것**으로 건다.
    if (!mounted || picked == null) return;
    await _openPickedEvent(rows[picked].entry);
  }

  /// 상세 시트의 행사 카드. **포스터만 띄운다** — 이미 그 매장의 시트에 서 있어서
  /// 갈 곳을 다시 고를 일이 없다. 그래서 포스터의 안내 버튼도 감춘다(눌러도 방금
  /// 떠난 화면으로 돌아올 뿐이다). 닫으면 보고 있던 시트가 그대로 남는다.
  Future<void> _onPlaceDetailEventTap(BuildingEvent event) async {
    await EventPosterView.show(
      context,
      events: [event],
      initialIndex: 0,
      navigable: const [false],
      showGuide: false,
    );
  }

  /// 야외 지도에서 건물 폴리곤을 눌렀을 때. 시트를 먼저 띄우고, 진입은 그
  /// 시트가 시킬 때만 한다.
  void _onMapBuildingTap(Building building) {
    unawaited(_runSheetChain(() => _showBuildingInfo(building)));
  }

  /// 건물 정보 시트. 돌려주는 값에 따라 길찾기·실내 진입·매장 상세로 갈린다.
  ///
  /// 반환값 규칙은 매장 시트와 같다 — "출발/도착을 실제로 골랐는가"다.
  Future<bool> _showBuildingInfo(Building building) async {
    final picked = await _withMapsLocked(
      () => BuildingInfoSheet.show(
        context,
        building: building,
        onCloseAll: _requestCloseSheetChain,
      ),
    );
    if (!mounted || _closeSheetChainRequested) return true;
    if (picked == null) return false;

    // 매장을 골랐으면 매장 상세로 넘긴다. 좌표·노드 해석과 실내 진입은
    // [_onNearbyStorePicked]와 **같은 경로**를 쓴다 — 진입점마다 따로 만들면
    // 한쪽만 층을 옮기거나 한쪽만 강조가 빠진다.
    if (picked is StoreIndexEntry) {
      final resolved = await _outdoorKey.currentState?.resolveIndexEntry(
        picked,
      );
      if (!mounted || resolved == null) return false;
      return _showStoreInfo(resolved, focusOnMap: true);
    }

    // 좌표만 있는 후보다. 건물 안 매장이 아니므로 실내 라우팅으로 가지 않고,
    // 목적지 건물의 출입구를 경유하는 갈래는 [classifyWalkRoute]가 정한다.
    final point = building.outdoorAnchor;
    switch (picked) {
      case BuildingInfoAction.enterIndoor:
        // 건물 탭이 곧 진입이던 조작을 여기서 이어받는다.
        _outdoorKey.currentState?.enterIndoorFromSheet();
        return false;
      case BuildingInfoAction.setOrigin when point != null:
        final candidate = _buildingCandidate(building, point);
        setState(() => _selectedOrigin = candidate);
        final destination = _routeDraftDestination;
        if (destination != null) {
          await _startRoute(origin: candidate, destination: destination);
        } else {
          await _openRouteMode(presetOrigin: candidate);
        }
        return true;
      case BuildingInfoAction.setDestination when point != null:
        final candidate = _buildingCandidate(building, point);
        setState(() => _routeDraftDestination = candidate);
        final origin = _selectedOrigin;
        if (origin != null || _canRouteFromCurrentLocation) {
          await _startRoute(origin: origin, destination: candidate);
        } else {
          await _openRouteMode(
            presetDestination: candidate,
            focusField: RoutePlanField.origin,
          );
        }
        return true;
      default:
        // 좌표를 모르는 건물이다(출입구도 외곽선도 없음). 경로의 끝점을 정할 수
        // 없으므로 아무것도 하지 않는다 — 후보 목록이 같은 이유로 이런 건물을
        // 아예 빼고 있다([searchDirectionsCandidates]).
        _showSnack('이 건물의 위치 정보가 없어 길찾기를 시작할 수 없습니다.');
        return false;
    }
  }

  /// 건물 한 채를 길찾기 후보로 옮긴다. 후보 목록이 만드는 것과 같은 모양이라야
  /// 두 경로가 같은 갈래로 흘러간다([searchDirectionsCandidates]).
  DirectionsCandidate _buildingCandidate(Building building, LatLng point) =>
      DirectionsCandidate(
        title: building.name,
        subtitle: '${building.floors.length}개 층',
        point: point,
        buildingId: building.id,
      );

  /// 매장 정보 시트를 띄운다. 검색 결과 탭과 지도 폴리곤 탭이 모두 여기를 거친다.
  ///
  /// 반환값은 사용자가 출발/도착 액션을 골랐는지다 — "그냥 닫힘"이면 호출자가 저장된
  /// 장소 시트로 되돌린다.
  ///
  /// [keepZoom]이면 **배율은 그대로 둔다.** [focusRatio]는 그보다 부드러운
  /// 조절기다 — 0.5면 지금 배율과 그 매장에 맞춘 배율의 중간까지만 간다.
  /// 이미 상세 시트가 떠 있으면 **그 시트의 내용만** 갈아 끼운다. 갈아 끼웠으면 true.
  ///
  /// 떼었다 붙이면 빈 프레임이 생겨 번쩍이고, 그냥 얹으면 같은 시트가 두 겹으로
  /// 쌓인다 — 검색으로 같은 매장을 두 번 열면 뒤로가기 한 번에 화면이 안 바뀌는
  /// 것으로 드러났다. 자세한 것은
  /// `docs/client/kakao-map-indoor-observation.md` S절.
  ///
  /// [focusOnMap]이 false면 **카메라는 그대로 둔다.** 갈아 끼우기는 시트를 다시
  /// 열지 않으므로 카메라를 여기서 따로 움직인다 — 지도 탭의 포커스 세기는
  /// 두 입구([_openStoreFromMap]과 여기)가 같은 [focusRatio]를 써야 맞는다.
  bool _swapOpenPlaceDetail(
    PoiSearchResult match, {
    bool focusOnMap = true,
    bool keepZoom = false,
    double focusRatio = 1,
  }) {
    if (_placeDetailClosing == null) return false;
    _activePlaceMatch = match;
    _nearbyOriginPlaceId = match.placeId;
    _placeDetailTarget.value = _targetFor(
      match,
      FavoritePlace.fromPoiSearchResult(match, buildingId: _buildingId),
    );
    if (focusOnMap) {
      unawaited(
        (_outdoorKey.currentState?.focusStore(
                  match,
                  bottomSheetFraction: placeDetailSheetInitialSize(
                    MediaQuery.sizeOf(context).height,
                  ),
                  keepZoom: keepZoom,
                  focusRatio: focusRatio,
                  enterBuildingIfNeeded: true,
                ) ??
                Future.value())
            .catchError((Object error, StackTrace _) {
              debugPrint('[place focus] $error');
            }),
      );
    }
    return true;
  }

  Future<bool> _showStoreInfo(
    PoiSearchResult match, {
    bool focusOnMap = false,
    bool keepZoom = false,
    bool crossFade = false,
    double focusRatio = 1,
  }) async {
    // **여기가 상세 시트의 유일한 입구다.** 검색·근처 매장·저장한 장소·지도 탭이
    // 모두 이 함수를 지나므로, 중복 방지를 각 호출부에 흩지 않고 여기 한 곳에
    // 둔다. 갈아 끼웠다면 이 호출은 시트를 열지 않았으므로 false로 끝낸다 —
    // 사용자가 고른 동작은 원래 떠 있던 시트의 await가 받는다.
    if (_swapOpenPlaceDetail(
      match,
      focusOnMap: focusOnMap,
      keepZoom: keepZoom,
    )) {
      return false;
    }
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
        focusRatio: focusRatio,
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
        onShowEvent: (event) => unawaited(_onPlaceDetailEventTap(event)),
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
    final candidate = candidateForPlace(active);
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
      await _setRouteDestination(candidate);
    }
    return true;
  }

  /// 검색 결과 한 줄을 길찾기 후보로 옮긴다. 상세 시트·검색 결과·시설 목록이
  /// **같은 변환**을 써야 세 입구가 같은 경로로 흘러간다.
  DirectionsCandidate candidateForPlace(PoiSearchResult place) =>
      DirectionsCandidate(
        title: place.name,
        subtitle: place.floor,
        point: place.point,
        nodeId: place.nodeId,
        floor: place.floor,
      );

  /// 도착지를 확정한다. 상세 시트의 "도착"과 시설 목록의 줄 선택이 **같은 이
  /// 함수**를 지난다 — 같은 결과에 이르는 길이 둘로 갈리면 한쪽만 고쳐지는 날이 온다.
  Future<void> _setRouteDestination(DirectionsCandidate candidate) async {
    // 출발지가 준비돼 있으면 바로 그린다. 명시적으로 고른 매장이든 위치가 잡힌
    // 현재 위치든([_canRouteFromCurrentLocation]) 둘 다 완전하다 — 후자를 빼면
    // 위치를 찍어둔 사용자가 "도착"을 눌러도 아무 일도 안 일어난다.
    setState(() => _routeDraftDestination = candidate);
    final origin = _selectedOrigin;
    if (origin != null || _canRouteFromCurrentLocation) {
      await _startRoute(origin: origin, destination: candidate);
      return;
    }
    // 출발지가 없다. **여기서 멈추면 아무 일도 안 일어난 화면이 된다** — 길찾기
    // 바는 [_routeMode]가 참일 때만 그려지는데 이 갈래가 그걸 안 세웠다.
    // 도착지를 채운 채로 바를 열고 커서를 출발 칸에 둔다.
    await _openRouteMode(
      presetDestination: candidate,
      focusField: RoutePlanField.origin,
    );
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

  /// 링크가 가리키는 매장을 연다.
  ///
  /// **이름으로 찾거나 첫 결과로 대신하지 않는다.** 같은 이름의 매장이 층마다 있는
  /// 시설이라, 한 번이라도 흉내를 내면 공유받은 사람이 **다른 매장**을 보고 그것을
  /// 공유한 사람의 의도로 읽는다. 정확히 그 id가 없으면 아무것도 열지 않고 지금
  /// 지도에 머문다.
  Future<void> _openPlaceFromLink(PlaceLink link) async {
    // **초기 카메라는 이 링크의 것이다.** 여기서부터 매장을 그리기까지 색인 조회와
    // 층 전환을 거치는데, 그 사이 첫 GPS 좌표가 오면 화면이 사용자 위치로 튄다.
    // 예약을 지도 쪽 포커스 시점에 걸었더니 그보다 늦어 못 막았다(실기기 확인).
    final map = _outdoorKey.currentState?..claimInitialCamera();
    try {
      await _openPlaceFromLinkInner(link);
    } finally {
      // 열었으면 지도가 `_didInitialCenter`로 이어받았고, 못 열었으면 첫 좌표
      // 센터링을 되살려야 한다. 어느 쪽이든 예약은 여기서 끝난다.
      map?.releaseInitialCamera();
    }
  }

  Future<void> _openPlaceFromLinkInner(PlaceLink link) async {
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

  /// 지도에서 매장을 눌렀을 때의 분기점. 지도에서 고르는 중이면 매장 정보
  /// 시트를 열지 않고 그 매장을 해당 칸(출발지/도착지)의 값으로 쓴다.
  ///
  /// 두 지도(야외의 실내 진입 오버레이·실내 탭)가 같은 콜백을 쓰므로, 어느 쪽에서
  /// 골라도 동일하게 동작한다.
  void _onMapStoreTap(PoiSearchResult match) {
    final target = _routeMapPickTarget;
    if (target == null) {
      unawaited(_openStoreFromMap(match));
      return;
    }
    _applyMapPick(match, target);
  }

  /// 행사를 서버에서 받아 둔다. **실패를 삼킨다** — 행사는 곁들이라, 못 받았다고
  /// 지도 화면이 뜨지 못하면 손해가 훨씬 크다.
  ///
  /// **한 번으로 끝내지 않는다.** 앱을 켜자마자 부르는 자리라 그때는 DNS도 아직
  /// 안 선다 — 실기기에서 첫 요청이 `Failed host lookup`으로 떨어졌고, 삼킨 뒤로는
  /// 다시 받을 길이 없어 그 세션 내내 판이 안 떴다. 그래서 **받은 것이 없으면 또
  /// 부를 수 있게** 두고, 건물에 들어가는 순간 한 번 더 부른다(그때쯤이면 GPS와
  /// 지도 요청이 이미 오간 뒤라 망이 서 있다).
  Future<void> _loadBuildingEvents() async {
    if (_buildingEvents != null) return;
    try {
      final events = await fetchBuildingEvents();
      if (!mounted || events == null) return;
      setState(() => _buildingEvents = events);
    } on Object catch (error) {
      debugPrint('[events] $error');
    }
  }

  /// 지금 이 자리에서 열리는 행사. 없으면 null.
  ///
  /// **매장 색인이 아니라 placeId로 찾는다** — 같은 팝업 공간에 행사가 며칠씩
  /// 갈아드는데, 이름으로 맞추면 `POP-UP EAST`처럼 이름이 겹치는 칸에서 엉뚱한
  /// 행사가 붙는다.
  BuildingEvent? _eventAt(String? placeId) {
    if (placeId == null) return null;
    for (final event in _buildingEvents?.openOn(todayKey()) ?? const []) {
      if (event.storeId == placeId) return event;
    }
    return null;
  }

  PlaceDetailTarget _targetFor(PoiSearchResult match, FavoritePlace? favorite) {
    final event = _eventAt(match.placeId);
    return PlaceDetailTarget(
      // **행사 중이면 행사 이름이 제목이다.** 사용자가 찾아온 이름은
      // `POP-UP ICONIC B2`가 아니라 `명탐정 코난`이다. 원래 매장명은 아래
      // 메타 줄에 남겨 둔다 — 지도 라벨·검색은 그대로라 두 이름이 이어져야 한다.
      title: event?.title ?? match.name,
      subtitle: event == null
          ? match.floor
          : [match.floor, match.name].join(' · '),
      event: event,
      placeId: match.placeId,
      favorite: favorite,
      // 대분류 칩을 없앴으므로 업종은 한 줄로만 보여 준다. 소분류가 없는
      // 장소에서 업종이 통째로 사라지지 않도록 대분류로 떨어뜨린다.
      subcategory: match.subcategory ?? match.category,
      // 검색 결과 목록이 쓰는 것과 **같은 계산 결과**를 넘긴다. 두 화면이
      // 같은 매장에 다른 거리를 적으면 어느 쪽도 못 믿게 된다.
      reach: match.nodeId == null ? null : _reachByNodeId?[match.nodeId],
    );
  }

  /// 지도에서 매장을 눌러 상세를 연다. **떠 있는 상세가 있으면 먼저 닫는다.**
  ///
  /// 이 시트는 barrier가 없어 포인터를 지도로 흘리는 의도된 설계라
  /// ([_withMapsLocked]), 그 대가로 시트가 쌓이는 것을 여기서 막는다.
  ///
  /// **이미 떠 있었으면 제자리에서 갈아 끼운다.** 닫고 다시 여는 기본 동작은
  /// 화면의 3분의 1을 왕복해(260ms + 380ms) 매장을 훑을수록 눈이 피로하다.
  /// 시트가 이미 그 자리에 있으니 움직일 이유가 없다 — 내용만 바꾼다.
  Future<void> _openStoreFromMap(PoiSearchResult match) async {
    // **카테고리를 켜 놓고 누른 매장은 보러 간 것이다.** 칩으로 그 대분류만
    // 남겨 놓고 하나를 고르는 흐름이라 예전 그대로 완전히 포커스한다.
    // 그냥 도면을 훑다 누른 것은 다르다 — 화면이 통째로 끌려가면 방금까지
    // 보던 자리를 잃으므로 그 절반까지만 간다.
    final focusRatio = _categorySelection == null ? 0.5 : 1.0;
    if (_swapOpenPlaceDetail(match, focusOnMap: true, focusRatio: focusRatio)) {
      return;
    }
    await _runSheetChain(
      // 예전에는 이 입구만 카메라를 아예 안 움직였다("이미 보이던 것"). 시트가
      // 화면 아래 절반을 덮는 것을 못 본 규칙이라, 아래쪽을 눌렀으면 방금 고른
      // 매장이 시트 뒤로 들어갔다. 배율을 고정한 채 자리만 맞추는 것
      // (`keepZoom`)도 답이 아니었다 — 도면 전체가 보이는 상태에서는 리프트가
      // 수십 px이라 화면이 그대로였다. 배율까지 같은 비율로 함께 끈다.
      () => _showStoreInfo(match, focusOnMap: true, focusRatio: focusRatio),
    );
  }
}
