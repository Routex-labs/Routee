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

  PlaceDetailTarget _targetFor(
    PoiSearchResult match,
    FavoritePlace? favorite,
  ) => PlaceDetailTarget(
    title: match.name,
    subtitle: match.floor,
    placeId: match.placeId,
    favorite: favorite,
    // 대분류 칩을 없앴으므로 업종은 한 줄로만 보여 준다. 소분류가 없는
    // 장소에서 업종이 통째로 사라지지 않도록 대분류로 떨어뜨린다.
    subcategory: match.subcategory ?? match.category,
    // 검색 결과 목록이 쓰는 것과 **같은 계산 결과**를 넘긴다. 두 화면이
    // 같은 매장에 다른 거리를 적으면 어느 쪽도 못 믿게 된다.
    reach: match.nodeId == null ? null : _reachByNodeId?[match.nodeId],
  );

  /// 지도에서 매장을 눌러 상세를 연다. **떠 있는 상세가 있으면 먼저 닫는다.**
  ///
  /// 고른 매장의 기존 아이콘·이름이 커지고 카메라가 시트 위 영역 한가운데로 끌어온다.
  /// 이 시트는
  /// barrier가 없어 포인터를 지도로 흘리는 의도된 설계라([_withMapsLocked]),
  /// 그 대가로 시트가 쌓이는 것을 여기서 막는다.
  ///
  /// **이미 떠 있었으면 제자리에서 갈아 끼운다.** 닫고 다시 여는 기본 동작은
  /// 화면의 3분의 1을 왕복해(260ms + 380ms) 매장을 훑을수록 눈이 피로하다.
  /// 시트가 이미 그 자리에 있으니 움직일 이유가 없다 — 내용만 바꾼다.
  Future<void> _openStoreFromMap(PoiSearchResult match) async {
    if (_swapOpenPlaceDetail(match)) return;
    await _runSheetChain(
      // `focusZoomFor`는 이미 더 가까우면 그대로 두므로 훑는 중에 튀지 않는다.
      () => _showStoreInfo(match, focusOnMap: true),
    );
  }
}
