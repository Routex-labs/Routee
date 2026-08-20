// ignore_for_file: invalid_use_of_protected_member
//
// part라 `setState`(protected) 호출이 경고로 잡힌다.
/// `OutdoorMapBodyState`의 **경로·안내·대중교통** 부분.
///
/// part 규약과 이 파일로 가른 이유는 `docs/client/outdoor-map-moves.md`.
part of '../outdoor_map_screen.dart';

extension OutdoorMapRoute on OutdoorMapBodyState {
  // 실내 진입 오버레이 위에 그리는 실내 경로. 현재 보고 있는 층에 해당하는
  // 세그먼트만 지도에 그려지고, 층 chip으로 다른 층을 훑으면 해당 층 세그먼트로
  // 갈아탄다. 다층 경로일 때는 [_indoorMultiFloorRoute]에 전체가 남아 있어
  // ETA 총 거리도 유지된다.
  /// 지금 이 층에 그려진 실내 경로 세그먼트. 실내 탭과 같은 세션이 소유한다 —
  /// 진행률이 이 값에 투영되므로 두 곳에 두면 남은거리가 갈라진다.
  IndoorRoute? get _indoorRouteSegment => _guidance.routeSegment;

  /// 층 전환 작업을 직렬화한다.
  ///
  /// 겹쳐 돌면 층과 경로가 서로 다른 시점을 가리킨다. 오류가 나도 탑승 상태를
  /// 화면에 남기지 않는다 — 큐가 오류만 찍고 끝나면 걸음이 멈춘 채 배너가
  /// 영구히 남고 사용자가 복구할 방법이 없다.
  void _enqueueFloorTransition(Future<void> Function() action) {
    _floorTransitionQueue = _floorTransitionQueue
        .then((_) => mounted ? action() : Future<void>.value())
        .onError(_recoverFloorTransitionFailure);
  }

  Future<void> _recoverFloorTransitionFailure(
    Object error,
    StackTrace stackTrace,
  ) async {
    debugPrint('floor transition failed: $error\n$stackTrace');
    if (!mounted) return;
    await _endEscalatorRide();
    if (!mounted) return;
    setState(() => _pendingArrivalNode = null);
    _showSnack('층 전환을 완료하지 못했습니다. 현재 층과 위치를 다시 확인해주세요.');
  }

  /// 디버그 전용 — 실제 탑승 없이 층 전환 시퀀스를 태운다.
  ///
  /// **판정기를 흉내 내는 것이지 우회하는 것이 아니다.** 확정 시 타는 경로에 합성
  /// transition을 넣을 뿐이라, 이 버튼으로 본 연출이 곧 실기기의 연출이다.
  ///
  /// 판정기([EscalatorTransitionDetector])는 건드리지 않는다 — 재작성이 예정돼 있어
  /// 디버그 주입구를 뚫으면 갈아엎을 표면만 는다.
  void _debugForceFloorTransition() {
    final transfer = _debugForceableTransfer;
    final floor = _activeFloor;
    if (transfer == null || floor == null) return;
    final (:segment, :nextFloorLabel) = transfer;
    // 자동 전환 판정기와 같은 층 라벨 순위 규칙을 쓴다.
    final goingUp = floorLabelRank(nextFloorLabel) > floorLabelRank(floor);
    final transition = EscalatorTransition(
      // 도착 노드를 경로 지목으로 찾으므로 그룹 매칭까지 갈 일이 없지만,
      // 진단 JSON에 남는 값이라 강제 전환임을 알아볼 수 있게 적는다.
      group: 'DEBUG',
      direction: goingUp ? EscalatorDirection.up : EscalatorDirection.down,
      fromFloorLabel: floor,
      toFloorLabel: nextFloorLabel,
      deltaM: goingUp ? 5.0 : -5.0,
      durationMs: 0,
      stepsDuring: 0,
      boardingNodeId: segment.transferFromNodeId!,
      boardingNodeName: null,
      boardingDistanceM: 0,
      boardingEvidence: 'debug-forced',
      expectedArrivalNodeId: segment.transferToNodeId,
    );
    _enqueueFloorTransition(() => _beginEscalatorTransition(transition));
    // 시작과 확정 사이를 벌린다. 실제 에스컬레이터는 탑승부터 하차 감지까지
    // 10초를 넘게 타는데, 처음 1.2초로 뒀더니 "이동 중" 상태가 실제보다 훨씬
    // 짧아 보였다 — 이 버튼으로 본 리듬이 곧 실기기 리듬이어야 하므로 실제
    // 탑승 시간에 가깝게 둔다. (실기기에서는 이 대기가 없다 — 판정기가 실제
    // 하차를 기다리므로 몸이 시간을 정한다.)
    _enqueueFloorTransition(
      () => Future<void>.delayed(const Duration(seconds: 5)),
    );
    _enqueueFloorTransition(() => _completeEscalatorTransition(transition));
  }

  /// 이 층 [nodeId]에서 목적지까지 경로를 다시 뽑는다. 같은 노드면 아무것도 하지
  /// 않는다(진행률 기준점만 흔들린다).
  ///
  /// **연출을 붙이지 않는다** — 카메라는 이미 하차 지점에 맞춰져 있고, 여기서 또
  /// 움직이면 방금 자리 잡은 화면이 한 번 더 흔들린다.
  Future<void> _recomputeRouteFrom({
    required String nodeId,
    required String floor,
  }) async {
    final destination = _preTransferDestination ?? _indoorRouteDestination;
    final destinationNodeId = destination?.nodeId;
    final buildingId = _building?.id;
    if (destination == null ||
        destinationNodeId == null ||
        buildingId == null) {
      return;
    }
    if (_routeStartsAt(nodeId, floor)) return;
    setState(() => _indoorRouteDestination = destination);
    if (destination.floor == floor) {
      await _computeAndShowSingleFloorIndoorRoute(
        buildingId: buildingId,
        floor: floor,
        endNodeId: destinationNodeId,
        playOverview: false,
        // 층 전환 후 재계산 — 같은 길안내의 연속이다.
        beginNewRecordingSession: false,
        startNodeId: nodeId,
      );
    } else {
      await _computeAndShowMultiFloorIndoorRoute(
        buildingId: buildingId,
        startFloor: floor,
        endFloor: destination.floor,
        endNodeId: destinationNodeId,
        playOverview: false,
        beginNewRecordingSession: false,
        startNodeId: nodeId,
      );
    }
  }

  /// 지금 [floor]에 그려진 경로가 [nodeId]에서 시작하는가.
  bool _routeStartsAt(String nodeId, String floor) {
    final multi = _indoorMultiFloorRoute;
    final route = multi == null
        ? (_activeFloor == floor ? _indoorRouteSegment : null)
        : multi.segmentForFloor(floor)?.route;
    return route != null && route.nodeIds.firstOrNull == nodeId;
  }

  /// 지금 화면이 그려야 하는 층 전환 배너 상태.
  FloorTransitionUiState? get _floorTransitionUiState => floorTransitionUiState(
    arrival: _escalatorArrival,
    ride: _escalatorRide,
    stage: _escalatorStage,
  );

  /// 배너·스크림 상태가 바뀌면 셸에 알린다. 같은 값이면 알리지 않는다.
  ///
  /// 값 비교로 막지 않으면 매 스냅샷마다 부모 setState가 돌아, 지도 전체가
  /// 초당 수 회 다시 그려진다.
  void _reportFloorTransitionUi() {
    final banner = _floorTransitionUiState;
    final scrim = _floorSwapVeil;
    if (banner == _reportedFloorTransition &&
        scrim == _reportedFloorScrimOpacity) {
      return;
    }
    _reportedFloorTransition = banner;
    _reportedFloorScrimOpacity = scrim;
    final notify = widget.onFloorTransitionChanged;
    if (notify == null) return;
    // build 중에는 부모 setState를 호출할 수 없다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) notify(banner, scrim);
    });
  }

  /// 건물(입구·footprint·층 목록)을 로드한다.
  ///
  /// **실패를 조용히 삼키면 안 된다** — 실내 기능 전부가 [_building]에 걸려 있어,
  /// 예외가 unhandled async error로만 남으면 "야외는 멀쩡한데 실내 기능만 없는"
  /// 화면이 단서 없이 남는다. 야외는 건물 없이도 쓸 수 있으므로 전체 화면 에러
  /// 대신 재시도가 달린 배지만 띄운다.
  Future<void> _loadBuildingEntrance() async {
    final Building? building;
    try {
      building = await buildingRepository.getBuilding(demoBuildingId);
    } catch (_) {
      if (!mounted) return;
      if (!_buildingLoadFailed) setState(() => _buildingLoadFailed = true);
      _scheduleBuildingRetry();
      return;
    }
    if (!mounted) return;
    // 성공했으면 예약된 재시도는 필요 없다. 사다리도 되돌려, 나중에 다시
    // 끊겼을 때 짧은 간격부터 새로 시작하게 한다.
    _buildingRetryTimer?.cancel();
    _buildingRetryTimer = null;
    _buildingRetryAttempt = 0;
    setState(() {
      _buildingLoadFailed = false;
      _building = building;
      _entrance = building?.entrance;
      _buildingFootprint = building?.footprintWgs84;
      _activeFloor = building?.initialFloor;
    });
    if (building != null && !_buildingReadySignal.isCompleted) {
      _buildingReadySignal.complete();
    }
    _notifyActiveFloor();
    _syncDestinationLayer();
    _syncBuildingLayer();
    // 스타일이 이미 로드된 뒤 건물이 늦게 도착한 케이스(테스트/느린 네트워크)를
    // 위해 실내 MVT 소스도 여기서 한 번 더 등록 시도.
    _ensureIndoorTilesRegistered();
    final floor = _activeFloor;
    if (building != null && floor != null) {
      // 지상 출입구는 층 그래프와 **독립적으로** 필요하다. 사용자가 층 chip으로
      // 다른 층을 훑는 순간 [_floorPlan]은 그 층 것으로 갈리는데, 문 목록은
      // 그동안에도 남아 있어야 야외 안내가 끊기지 않는다.
      unawaited(_loadGroundEntrances(building.id, floor));
      await _loadFloorGraph(building.id, floor);
    }
  }

  /// 지상 출입구 목록을 받아 [_groundEntrances]를 채운다.
  ///
  /// **실패는 조용히 넘긴다** — 문을 못 받으면 목적지 좌표로 바로 걷는 예전 안내로
  /// 폴백하는 것이 맞고, 에러를 띄워 봐야 사용자가 할 수 있는 조치가 없다.
  Future<void> _loadGroundEntrances(String buildingId, String floor) async {
    final Map<String, dynamic>? geojson;
    try {
      geojson = await buildingRepository.getFloorGeoJson(buildingId, floor);
    } catch (_) {
      return;
    }
    if (!mounted || geojson == null) return;
    final entrances = groundEntrancesFrom(FloorPlan.fromJson(geojson));
    if (entrances.isEmpty) return;
    setState(() {
      _groundEntrances = entrances;
      _groundEntranceFloor = floor;
    });
    _syncSelectedEntrance();
  }

  /// 현재 위치에서 가장 가까운 문을 다시 고르고, [_entrance]도 함께 갱신한다.
  /// 그 값은 **실내 진입/이탈 판정 전체**의 기준점이라, null이던 동안 GPS 자동
  /// 진입이 조건을 만족해도 발화하지 못했다.
  ///
  /// 위치를 못 잡았으면 건물 중심을 쓴다 — 하나라도 골라 둬야 판정이 살아 있다.
  void _syncSelectedEntrance() {
    if (_groundEntrances.isEmpty) return;
    final position = _position;
    final reference = position != null
        ? ll.LatLng(position.latitude, position.longitude)
        : _buildingCenter(_buildingFootprint ?? const []);
    if (reference == null) return;

    final picked = nearestEntrance(
      _groundEntrances,
      reference,
      current: _selectedEntrance,
    );
    if (picked == null || picked.id == _selectedEntrance?.id) return;
    setState(() {
      _selectedEntrance = picked;
      _entrance = picked.point;
    });
  }

  /// [fromPositionStream]이 true면 **충분히 움직였을 때만** TMAP을 다시 부른다
  /// ([shouldRecomputeRouteAfterMove]) — 안 그러면 초당 한 번씩 외부 API를 두드린다.
  ///
  /// **사용자가 목적지를 고른 호출(false)은 절대 거르지 않는다** — 제자리에서
  /// 도착지를 눌렀을 때 아무 일도 안 일어나는 화면이 된다.
  Future<void> _updateRoute(
    Position position, {
    bool fromPositionStream = false,
  }) async {
    // 문 경유 안내 중이면 이번 위치로 다시 고른 문이 목적지다. 걸어가는 동안
    // 더 가까운 문이 생기면([_syncSelectedEntrance]가 이미 갱신했다) 야외 구간의
    // 도착점과 실내 구간의 시작점을 함께 갈아 끼운다 — 한쪽만 바꾸면 도보 경로는
    // 새 문으로 가는데 실내 경로는 옛 문에서 시작하는 화면이 된다.
    if (_pendingIndoorDestination != null) _retargetJourneyEntrance();

    // 길찾기가 그린 **계획 경로**는 출발점이 못박혀 있다. GPS가 갱신될 때마다
    // 다시 계산하면 사용자가 비교하려고 보고 있는 선이 걸음마다 흔들린다.
    if (_fixedRouteOrigin != null) return;

    // 야외 걷기 경로는 **사용자가 목적지를 고른 경우에만** 그린다. [_entrance]로
    // 폴백하면 앱을 켜고 GPS가 잡히는 것만으로 아무도 요청하지 않은 경로가 그려지고
    // 좌표마다 TMAP 요청이 나간다 — 그 값은 판정 기준점이지 목적지가 아니다.
    final target = _userDestination;
    if (target == null) return;

    final origin = ll.LatLng(position.latitude, position.longitude);
    if (fromPositionStream &&
        !shouldRecomputeRouteAfterMove(
          origin: origin,
          lastRequestedOrigin: _lastRouteRequestOrigin,
        )) {
      return;
    }
    _lastRouteRequestOrigin = origin;

    final route = await directionsRepository.getWalkingRoute(
      origin: origin,
      destination: target,
    );
    if (!mounted) return;
    // **재탐색이 실패하면 보던 경로를 지우지 않는다.** 도보는 출발점을 박지
    // 않아([_fixedRouteOrigin]) GPS가 움직일 때마다 여기로 다시 온다. 실패한
    // null을 그대로 넣으면 걷는 중에 경로가 사라지고, 안내 판정도 함께 풀려
    // 뒤로가기가 안내 겹을 건너뛰어 길찾기 전체를 지운다. 조회 실패는 화면을
    // 비울 이유가 아니다 — 다음 GPS 틱이 다시 물어본다.
    if (route == null && _route != null) return;
    // 도착점이 문이면 TMAP 선이 문 앞에서 끊기거나, 아예 문에 닿지 못한 채
    // 엉뚱한 곳으로 돌아간다([extendRouteToDestination]).
    _applyRoute(extendRouteToDestination(route, target));
  }

  /// 새 목적지를 선택하거나 안내를 끝낼 때만 완료 이력을 비운다.
  ///
  /// 재탐색으로 [_route] 또는 [_indoorRouteSegment]를 교체하는 동안에는 이
  /// 함수를 부르면 안 된다. 그 순간은 같은 여정의 다음 경로를 붙이는 시점이라
  /// 기존 회색선이 살아 있어야 한다.
  void _clearCompletedRouteHistory() {
    _completedRouteHistory.clear();
    _routeGeneration = 0;
    _outdoorDisplayProgress = null;
  }

  /// 확정된 새 실내 경로를 현재 세대에 연결한다.
  ///
  /// 네트워크/그래프 계산이 성공한 뒤에만 호출한다. 이전 실내 경로의 현재
  /// displayProgress를 그때 회색 이력으로 넘기므로, 재탐색 대기 중에는 기존
  /// 파란·회색 분할이 그대로 고정된다.
  void _acceptIndoorRouteGeneration({
    ({String scopeId, List<ll.LatLng> points})? previousCompletion,
  }) {
    final previous = _indoorRouteSegment;
    final completion = previousCompletion ?? _currentIndoorCompletionSnapshot();
    final replacing =
        previous != null ||
        _indoorMultiFloorRoute != null ||
        completion != null;
    if (replacing && completion != null) {
      _completedRouteHistory.append(
        scopeId: completion.scopeId,
        points: completion.points,
      );
    }
    _routeGeneration++;
  }

  /// 야외 GPS 진행률을 갱신한다.
  ///
  /// 정확도가 나쁘거나 경로에서 멀리 떨어진 GPS, 이전 진행점 주변에서
  /// 재획득한 후보는 채택하지 않는다. 따라서 그 틱에서는 회색선과 파란선의
  /// 분할점이 움직이지 않는다. 다음에 정상 좌표가 들어오면 직전 표시에서
  /// 이어진다.
  void _updateOutdoorDisplayProgress(Position position) {
    final route = _route;
    if (_indoorEntered ||
        _routeIsDriving ||
        _fixedRouteOrigin != null ||
        route == null ||
        route.points.length < 2) {
      return;
    }
    if (!position.accuracy.isFinite ||
        position.accuracy > lowAccuracyThresholdMeters) {
      return;
    }

    final candidate = computeGeoRouteProgress(
      routePoints: route.points,
      position: ll.LatLng(position.latitude, position.longitude),
      previousTraveledM: _outdoorDisplayProgress?.traveledM,
    );
    if (candidate == null ||
        candidate.offsetM > outdoorRouteMaxProjectionOffsetM ||
        candidate.reacquired) {
      return;
    }

    final previous = _outdoorDisplayProgress;
    if (previous != null &&
        candidate.traveledM <
            previous.traveledM - outdoorRouteRegressionToleranceM) {
      return;
    }
    _outdoorDisplayProgress = candidate;
  }

  List<ll.LatLng> _localRoutePointsToWgs84(
    List<LocalPoint> points,
    FloorGraph graph,
  ) {
    final transform = fitFloorGeoTransform(graph.nodes);
    return [
      for (final point in points)
        (() {
          final wgs84 = transform.apply(point.x, point.y);
          return ll.LatLng(wgs84.$1, wgs84.$2);
        })(),
    ];
  }

  void _captureOutdoorCompletedRouteBeforeReplace() {
    final completed = _outdoorRouteVisuals(_route).completed;
    if (completed.length >= 2) {
      _completedRouteHistory.append(
        scopeId: CompletedRouteHistory.outdoorScope,
        points: completed,
      );
    }
  }

  /// 경로가 새로 생기면(이전엔 없다가 이번에 생김) 상위에 ETA 바가 보인다고
  /// 알리고, 경로 전체가 화면에 들어오도록 카메라를 자동으로 줌아웃한다.
  /// 이미 경로가 있는 상태에서 위치가 갱신돼 경로가 매번 다시 계산될 때는
  /// (걷는 동안 계속 일어남) 다시 맞추지 않는다 — 사용자가 지도를 보는 중에
  /// 카메라가 계속 튀면 방해가 된다. 새 목적지를 고르면(showRouteTo) 그때는
  /// 다시 한번 전체 경로가 보이도록 맞춘다.
  void _applyRoute(DirectionsRoute? route) {
    final wasVisible = _route != null;
    final replacingOutdoorWalkingRoute =
        route != null &&
        _route != null &&
        !_routeIsDriving &&
        _fixedRouteOrigin == null &&
        !_indoorEntered;
    if (replacingOutdoorWalkingRoute) {
      // TMAP 응답이 성공해 새 파란 경로를 확정하는 순간에만 이전 경로의
      // 완료 구간을 이력으로 승격한다. 요청 중에는 기존 경로를 건드리지 않는다.
      _captureOutdoorCompletedRouteBeforeReplace();
    }
    if (route != null) {
      _routeGeneration++;
      _outdoorDisplayProgress = null;
    }
    setState(() => _route = route);
    if (route != null && _position != null) {
      _updateOutdoorDisplayProgress(_position!);
    }
    _syncRouteLayer();
    _notifyRouteStateIfChanged();
    final isVisible = route != null;
    if (!wasVisible && isVisible) {
      // **자동으로 생긴 경로는 카메라를 가져가지 않는다.** 맞춰 버리면 막 확대한
      // 화면이 도시 축척으로 바뀌고 건물이 점이 된다 — "건물 위치가 안 나온다"의
      // 정체가 이것이다. 사용자가 직접 고른 목적지면 그대로 맞춘다.
      if (_userDestination != null) _fitCameraToRoute(route);
    }
  }

  void _fitCameraToRoute(DirectionsRoute route) {
    // 출발점과 도착점이 사실상 같은 좌표면(예: 건물 입구 바로 앞) 경계 상자
    // 폭이 0에 가까워져 줌 계산이 발산한다 — 이 경우엔 화면에 맞출 "경로"랄
    // 게 없으니 자동 줌은 건너뛴다.
    if (route.points.length < 2 || route.distanceMeters < 5) return;
    _fitCameraToPoints(route.points);
  }

  /// 길찾기가 **미리 계산해 온** 도로 경로를 그대로 그린다. [showRouteTo]와 나눈
  /// 이유는 다시 부르면 같은 구간을 두 번 조회하고, 두 응답이 달라지면 카드와
  /// 지도가 다른 경로를 말하기 때문이다.
  ///
  /// 출발점을 [_fixedRouteOrigin]으로 박는다 — 따라가는 안내가 아니라 **비교하는
  /// 계획 화면**이라, GPS마다 다시 계산되면 보던 선이 흔들린다.
  Future<void> showPlannedRoadRoute(
    DirectionsRoute route, {
    required ll.LatLng origin,
    required ll.LatLng destination,
    required String label,
    bool driving = false,
  }) async {
    _clearCompletedRouteHistory();
    _clearPendingIndoorRoute();
    clearTransitRoute();
    // 경로를 **다시 그리는** 중이다(수단 변경·끝점 변경). 아직 "안내 시작" 전
    // 이므로 카메라는 경로 전체를 보여 줘야 한다.
    _stopFollowingUser();
    setState(() {
      _guidanceStarted = false;
      _routeIsDriving = driving;
      _fixedRouteOrigin = origin;
      _userDestination = destination;
      _userDestinationLabel = label;
      // 먼저 비워야 [_applyRoute]가 "새로 생김"으로 보고 카메라를 경로 전체에
      // 맞춘다. 안 비우면 수단을 바꿔도 카메라가 옛 경로 자리에 머문다.
      _route = null;
    });
    _syncDestinationLayer();
    _syncRouteLayer();
    _applyRoute(route);
  }

  /// 자동차 후보 목록을 받아 첫 번째(추천)를 그린다. 이후
  /// [selectDirectionsOption]으로 다른 후보를 고르면 다시 그린다.
  Future<void> showPlannedRoadRouteOptions(
    List<DirectionsRouteOption> options, {
    required ll.LatLng origin,
    required ll.LatLng destination,
    required String label,
  }) async {
    _directionsRouteOptions = options;
    _selectedDirectionsOptionIndex = 0;
    await showPlannedRoadRoute(
      options.first.route,
      origin: origin,
      destination: destination,
      label: label,
      driving: true,
    );
  }

  /// 목록에서 다른 자동차 후보를 골랐을 때. 출발·도착·라벨은 그대로다 —
  /// 바뀌는 것은 경로 선뿐이다.
  Future<void> selectDirectionsOption(int index) async {
    if (index == _selectedDirectionsOptionIndex) return;
    final origin = _fixedRouteOrigin;
    final destination = _userDestination;
    final label = _userDestinationLabel;
    if (origin == null || destination == null || label == null) return;
    setState(() => _selectedDirectionsOptionIndex = index);
    await showPlannedRoadRoute(
      _directionsRouteOptions[index].route,
      origin: origin,
      destination: destination,
      label: label,
      driving: true,
    );
  }

  /// [point]가 우리 도면이 있는 건물 **안**이면 그 건물의 지상 출입구 좌표를
  /// 돌려준다. POI 좌표를 그대로 끝점으로 쓰면 TMAP이 가장 가까운 도로로 스냅해
  /// 들어갈 수 없는 면에 사용자를 내려놓는다.
  ///
  /// **엄격한 판정을 쓴다** — 여유를 주면 건물 옆 노점까지 건물 문으로 안내한다.
  ll.LatLng? entranceIfInsideBuilding(ll.LatLng point) {
    final footprint = _buildingFootprint;
    final inside = footprint != null && isPointInPolygon(point, footprint);
    if (!inside) return null;
    final building = _building;
    return building == null ? null : entrancePointFor(building.id);
  }

  /// 문 경유 안내의 ETA 카드 라벨. 목적지와 경유하는 문을 함께 적어, 왜 경로가
  /// 목적지가 아니라 건물 모서리로 향하는지 사용자가 화면에서 바로 알 수 있게 한다.
  String _journeyEtaLabel(
    PoiSearchResult destination,
    BuildingEntrance entrance,
  ) {
    final label = entranceDirectionLabel(
      entrance,
      _buildingCenter(_buildingFootprint ?? const []),
    );
    return '${destination.name}까지 · $label 경유';
  }

  /// 안내 중인 문이 바뀌었으면 야외 도착점과 실내 구간을 새 문 기준으로 다시 맞춘다.
  ///
  /// 실내 구간은 서버에 다시 묻지 않고 들고 있던 그래프로 그 자리에서 푼다 —
  /// 문 선택은 GPS를 따라 여러 번 바뀔 수 있고, 그때마다 네트워크를 타면 신호가
  /// 나쁜 건물 앞에서 정확히 실패한다.
  void _retargetJourneyEntrance() {
    final entrance = _selectedEntrance;
    final destination = _pendingIndoorDestination;
    if (entrance == null || destination == null) return;
    // 이미 이 문을 향하고 있으면 할 일이 없다.
    if (entrance.id == _journeyEntrance?.id) return;

    final graph = _journeyBuildingGraph;
    final endNodeId = destination.nodeId;
    final leg = (graph == null || endNodeId == null)
        ? null
        : computeMultiFloorRoute(graph, entrance.nodeId, endNodeId);
    setState(() {
      _journeyEntrance = entrance;
      _userDestination = entrance.point;
      _userDestinationLabel = _journeyEtaLabel(destination, entrance);
      // 새 문에서 경로가 안 풀리면 옛 구간을 남기지 않는다. 남기면 사용자는
      // 남쪽 문으로 걸어가는데 실내 안내만 서쪽 문에서 시작하는 상태가 된다.
      _pendingIndoorRoute = (leg == null || leg.isEmpty) ? null : leg;
    });
  }

  /// 건물에 들어간 순간, 미리 풀어 둔 실내 구간을 실제 안내로 승격한다.
  ///
  /// **야외 구간은 지우지 않고 들고 있는다.** 예전에는 지웠는데, 그러면 건물에
  /// 들어갔다가 다시 밖으로 나온 사용자에게 아무 경로도 안 남는다 — 안내가
  /// 통째로 사라진 것처럼 보이고, 처음부터 다시 검색해야 한다.
  Future<void> _activatePendingIndoorRoute() async {
    final route = _pendingIndoorRoute;
    final destination = _pendingIndoorDestination;
    if (route == null || destination == null) return;

    final startFloor = route.segments.first.floorName;
    if (_activeFloor != startFloor) {
      await _switchOverlayFloor(startFloor);
      if (!mounted) return;
    }
    _routeGeneration++;
    setState(() {
      // _route·_userDestination(야외 구간)은 그대로 둔다. 밖으로 나오면 다시
      // 그려야 하는 값이다.
      _pendingIndoorRoute = null;
      _pendingIndoorDestination = null;
      _journeyEntrance = null;
      _indoorRouteDestination = destination;
      // 새 안내가 시작되면 지난 도착 카드는 자리를 비운다.
      _arrivedDestination = null;
      _indoorMultiFloorRoute = route;
      // 층별 구간은 공용 세션이 소유한다 — 진행률이 그 값에 투영되므로 여기서
      // 따로 들면 남은거리가 갈라진다([_indoorRouteSegment]). 같은 층 경로를
      // 얹는 자리와 같은 순서를 쓴다.
      _guidance
        ..setRouteSegment(route.segmentForFloor(startFloor)?.route)
        ..seedProgress(null)
        ..setRoute(route);
    });
    _syncRouteLayer();
    _syncIndoorDestinationLayer();
    _notifyRouteStateIfChanged();
    final segment = route.segmentForFloor(startFloor);
    if (segment != null && segment.route.points.length >= 2) {
      _fitCameraToIndoorRoute(segment.route);
    }
    _beginRouteRecordingSession();
  }

  /// 건물을 나간 순간, 예약해 둔 야외 구간을 실제 안내로 올린다.
  ///
  /// 출발지를 못박지 않는 이유는 **현재 위치에서 출발해야 하기 때문**이다.
  /// 출구 좌표를 출발지로 주면 [showRouteTo]가 그 값을 [_fixedRouteOrigin]에
  /// 넣어 경로를 고정하고, 그러면 걸어가는 동안 경로가 사용자를 따라오지 않는다.
  Future<void> _activatePendingOutdoorRoute() async {
    final destination = _pendingOutdoorDestination;
    final label = _pendingOutdoorLabel;
    if (destination == null || label == null) return;
    _clearPendingOutdoorRoute();
    // 완료 이력은 들고 간다. 이 호출은 같은 여정의 다음 구간이라, 거울상인
    // [_activatePendingIndoorRoute]가 야외 회색선을 남겨 두는 것과 대칭이다.
    await showRouteTo(destination, label: label, keepCompletedHistory: true);
  }

  /// 실내→야외 예약을 접는다. 그 안내가 더는 유효하지 않은 모든 자리에서 부른다.
  void _clearPendingOutdoorRoute() {
    if (_pendingOutdoorDestination == null && _pendingOutdoorLabel == null) {
      return;
    }
    setState(() {
      _pendingOutdoorDestination = null;
      _pendingOutdoorLabel = null;
    });
  }

  /// 문 경유 안내를 접는다. 야외 구간이 사라지는 모든 경로에서 함께 불린다 —
  /// 남겨 두면 사용자가 안내를 끈 뒤에 건물에 들어갔을 때 지웠던 실내 경로가
  /// 혼자 되살아난다.
  void _clearPendingIndoorRoute() {
    if (_pendingIndoorRoute == null && _pendingIndoorDestination == null) {
      return;
    }
    setState(() {
      _pendingIndoorRoute = null;
      _pendingIndoorDestination = null;
      _journeyEntrance = null;
    });
    // 문 경유가 끝나면 목적지 핀의 조건도 바뀐다([_syncDestinationLayer]).
    unawaited(_syncDestinationLayer());
  }

  /// "이 건물까지" 안내할 때 쓸 도착 좌표. 지상 출입구 → [_entrance] → 외곽선
  /// 중심 순으로 떨어지고, 셋 다 없으면 null(호출부가 버튼을 감춘다).
  ///
  /// [buildingId]를 받는 이유는 이 화면이 **한 채**만 로드하기 때문이다 — 좌표만
  /// 돌려주면 다른 건물을 물었을 때도 이 건물의 문이 그 건물 도착지로 박힌다.
  ll.LatLng? entrancePointFor(String buildingId) {
    if (_building?.id != buildingId) return null;
    final position = _position;
    final reference = position == null
        ? null
        : ll.LatLng(position.latitude, position.longitude);
    if (reference != null) {
      final door = nearestEntrance(_groundEntrances, reference);
      if (door != null) return door.point;
    }
    final known = _entrance;
    if (known != null) return known;
    final footprint = _buildingFootprint;
    if (footprint == null || footprint.isEmpty) return null;
    return _buildingCenter(footprint);
  }

  void _clearUserDestination() {
    _clearCompletedRouteHistory();
    clearTransitRoute();
    // 안내가 여기서 끝난다. 따라가기를 남기면 카메라가 계속 사용자를 쫓아다녀
    // 지도를 훑어볼 수 없다.
    _stopFollowingUser();
    _clearPendingIndoorRoute();
    setState(() {
      _userDestination = null;
      _userDestinationLabel = null;
      _route = null;
      _fixedRouteOrigin = null;
      _guidanceStarted = false;
      // 목적지를 지우면 그 목적지에 딸려 있던 자동차 후보 목록도 같이 접는다 —
      // 안 지우면 목적지가 없는 화면에 후보 패널만 혼자 남는다.
      _directionsRouteOptions = const [];
      _selectedDirectionsOptionIndex = 0;
    });
    _syncDestinationLayer();
    _syncRouteLayer();
    _notifyRouteStateIfChanged();
  }

  /// 같은 층 안에서 계산한 실내 경로를 지도에 얹는다. [startNodeId]가 없으면 PDR
  /// 앵커 주변 최근접 통로 노드를 찾는다.
  ///
  /// [playOverview]·[beginNewRecordingSession] **둘 다 기본값을 두지 않는다** —
  /// 안내 시작이냐 재탐색이냐에 따라 답이 정반대라 빠뜨리면 조용히 틀린 쪽으로
  /// 굴러간다. 특히 후자를 재탐색에서 true로 두면 층 전환마다 진단 로그가 지워져
  /// 분석하려는 구간이 파일에 안 남는다(실측: 마지막 재탐색 이후 10초만 남았다).
  Future<void> _computeAndShowSingleFloorIndoorRoute({
    required String buildingId,
    required String floor,
    required String endNodeId,
    required bool playOverview,
    required bool beginNewRecordingSession,
    String? startNodeId,
  }) async {
    final completionAtRequest = _currentIndoorCompletionSnapshot();
    final hadExistingIndoorRoute =
        _indoorRouteSegment != null || _indoorMultiFloorRoute != null;
    if (floor != _activeFloor) {
      // 목적지 층으로 화면을 옮기는 사람 조작 흐름이다. 새 도면 페이드인은
      // 이어지는 경로 개요 연출(playOverview)과 겹쳐 하나의 전환으로 읽힌다.
      await _switchOverlayFloorCrossfaded(floor);
      if (!mounted) return;
    }
    final graph = _floorGraph;
    if (graph == null) {
      _showSnack('경로 계산에 필요한 층 정보를 불러오지 못했습니다.');
      return;
    }
    if (startNodeId == null) {
      final anchor = _pdrTrailState.anchor;
      if (anchor == null || anchor.floorId != floor) {
        _showSnack('경로 계산에 필요한 층 정보를 불러오지 못했습니다.');
        return;
      }
      startNodeId = _nearestNodeId(
        graph.nodes,
        anchor.anchorLocalM.eastM,
        anchor.anchorLocalM.northM,
        excludingNodeId: endNodeId,
      );
    }
    if (startNodeId == null) {
      _showSnack('시작 위치 주변에서 통로 노드를 찾지 못했습니다.');
      return;
    }
    final route = await buildingRepository.getShortestRoute(
      buildingId,
      floor,
      startNodeId,
      endNodeId,
    );
    if (!mounted) return;
    if (route == null) {
      _showSnack('경로를 찾지 못했습니다. 다른 매장을 골라보거나 출발지를 다시 지정해주세요.');
      // 재탐색 실패는 현재 안내의 종료가 아니다. 기존 파란/회색 분할을
      // 유지해 센서·네트워크가 잠깐 불안정해도 화면이 비지 않게 한다.
      if (!hadExistingIndoorRoute) _clearIndoorRoute();
      return;
    }
    _acceptIndoorRouteGeneration(
      previousCompletion:
          _currentIndoorCompletionSnapshot() ?? completionAtRequest,
    );
    setState(() {
      _guidance
        ..setRouteSegment(route)
        ..seedProgress(null)
        ..setRoute(null);
      _indoorMultiFloorRoute = null;
    });
    _syncRouteLayer();
    _syncIndoorDestinationLayer();
    _notifyRouteStateIfChanged();
    if (playOverview) unawaited(_fitCameraToRouteSegment(route));
    // 진단 세션의 경계는 **길안내 한 건**이다. 목적지를 새로 고른 경우에만
    // 이전 세션을 버리고 새로 연다 — 재탐색·층 전환 후 재계산에서 세션을 갈면
    // 층을 옮길 때마다 로그가 지워진다.
    if (beginNewRecordingSession) {
      if (_pdrDebugRecorder != null) {
        _endRouteRecordingSession(announceExport: false);
      }
      _beginRouteRecordingSession();
    }
  }

  /// 층 간 경로를 층별 세그먼트로 나누고 현재 층 세그먼트를 지도에 얹는다. 활성
  /// 층은 시작 층으로 자동 전환되고, 층 chip으로 훑으면 그 층 세그먼트로 갈아탄다.
  /// 인자의 뜻은 [_computeAndShowSingleFloorIndoorRoute]와 같다.
  Future<void> _computeAndShowMultiFloorIndoorRoute({
    required String buildingId,
    required String startFloor,
    required String endFloor,
    required String endNodeId,
    required bool playOverview,
    required bool beginNewRecordingSession,
    String? startNodeId,
  }) async {
    final completionAtRequest = _currentIndoorCompletionSnapshot();
    final hadExistingIndoorRoute =
        _indoorRouteSegment != null || _indoorMultiFloorRoute != null;
    final buildingGraph = await buildingRepository.getBuildingGraph(buildingId);
    if (!mounted) return;
    if (buildingGraph == null || buildingGraph.nodes.isEmpty) {
      _showSnack('층 간 경로 계산에 필요한 그래프를 불러오지 못했습니다.');
      _clearIndoorRoute();
      return;
    }
    startNodeId ??= _pickStartNodeIdInBuildingGraph(
      graph: buildingGraph,
      startFloorName: startFloor,
      excludingNodeId: endNodeId,
    );
    if (startNodeId == null) {
      _showSnack('시작 층 주변에서 통로 노드를 찾지 못했습니다.');
      _clearIndoorRoute();
      return;
    }
    final route = computeMultiFloorRoute(buildingGraph, startNodeId, endNodeId);
    if (!mounted) return;
    if (route == null || route.isEmpty) {
      _showSnack('층 간 경로를 찾지 못했습니다. 엘리베이터/에스컬레이터 연결을 확인해주세요.');
      if (!hadExistingIndoorRoute) _clearIndoorRoute();
      return;
    }
    // 새 경로를 확정하기 전에 이전 층의 displayProgress를 이력으로 저장한다.
    // 층을 먼저 바꾸면 이전 그래프가 사라져 WGS84 변환을 할 수 없다.
    _acceptIndoorRouteGeneration(
      previousCompletion:
          _currentIndoorCompletionSnapshot() ?? completionAtRequest,
    );
    // 시작 층으로 화면을 전환한 뒤, 그 층 세그먼트를 지도에 얹는다. 사용자가
    // 훑던 층과 다르더라도 시작 층부터 보는 게 "지금 어디서 어느 방향으로
    // 첫 걸음"을 파악하는 데 자연스럽다(실내 화면과 동일 규칙).
    if (_activeFloor != startFloor) {
      await _switchOverlayFloorCrossfaded(startFloor);
      if (!mounted) return;
    }
    final segment = route.segmentForFloor(startFloor);
    setState(() {
      _indoorMultiFloorRoute = route;
      _guidance
        ..setRouteSegment(segment?.route)
        ..seedProgress(null)
        ..setRoute(route);
    });
    _syncRouteLayer();
    _syncIndoorDestinationLayer();
    _notifyRouteStateIfChanged();
    if (playOverview && segment != null) {
      unawaited(_fitCameraToRouteSegment(segment.route));
    }
    // 세션 경계 규칙은 [_computeAndShowSingleFloorIndoorRoute]와 같다.
    if (beginNewRecordingSession) {
      if (_pdrDebugRecorder != null) {
        _endRouteRecordingSession(announceExport: false);
      }
      _beginRouteRecordingSession();
    }
  }

  void _fitCameraToIndoorRoute(IndoorRoute route) {
    if (route.points.length < 2 || route.distanceMeters < 1) return;
    final controller = _mapController;
    if (controller == null || !_styleReady) return;

    var minLat = double.infinity;
    var maxLat = double.negativeInfinity;
    var minLng = double.infinity;
    var maxLng = double.negativeInfinity;
    for (final p in route.points) {
      minLat = p.latitude < minLat ? p.latitude : minLat;
      maxLat = p.latitude > maxLat ? p.latitude : maxLat;
      minLng = p.longitude < minLng ? p.longitude : minLng;
      maxLng = p.longitude > maxLng ? p.longitude : maxLng;
    }
    controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        left: 40,
        top: 110,
        right: 40,
        bottom: 180,
      ),
    );
  }

  /// ETA 카드 라벨. 다층 경로는 층별 이동수단(엘리베이터/에스컬레이터)까지 요약
  /// 노출해 "이 층에 안 그려진 이유"를 사용자가 이해할 수 있게 한다(실내 화면
  /// 규칙과 동일).
  String _indoorEtaLabel(PoiSearchResult destination) {
    final multi = _indoorMultiFloorRoute;
    if (multi == null) return '${destination.name}까지';
    final buffer = StringBuffer('${destination.name}까지');
    for (var index = 0; index < multi.segments.length; index++) {
      final segment = multi.segments[index];
      buffer.write(
        index == 0 ? ' · ${segment.floorName}' : ' → ${segment.floorName}',
      );
      final transferMode = segment.transferModeToNext;
      if (transferMode != null) {
        buffer.write(transferMode == 'elevator' ? ' (엘리베이터)' : ' (에스컬레이터)');
      }
    }
    return buffer.toString();
  }

  /// 실내 경로 표시를 초기화한다. ETA 카드 닫기 버튼과 사용자 destination 초기화
  /// 시 호출된다.
  ///
  /// [endGuidance]가 거짓이면 그린 것만 지우고 **안내 세션은 살려 둔다.** 도착
  /// 자동 지움만 그렇게 부른다 — 이유는 [clearRouteAfterArrival]에 있다.
  void _clearIndoorRoute({bool endGuidance = true}) {
    _clearCompletedRouteHistory();
    setState(() {
      _guidance
        ..setRouteSegment(null)
        ..clearProgress()
        ..setRoute(null);
      _indoorMultiFloorRoute = null;
      _indoorRouteDestination = null;
      _indoorRoutePreviewOrigin = null;
      if (endGuidance) _guidanceStarted = false;
      _guidanceTrailSession.clear();
    });
    _syncRouteLayer();
    _syncIndoorDestinationLayer();
    _notifyRouteStateIfChanged();
    // 한 번의 길안내가 여기서 끝난다.
    _endRouteRecordingSession();
  }

  /// 안내 배너를 탭했을 때 — 경로 전체를 단계 목록으로 펴서 시트로 보여준다.
  ///
  /// 다층 경로면 **모든 층의 세그먼트**를 순서대로 편다. 화면에 그려지는 것은
  /// 지금 층 세그먼트뿐이지만, 목록의 존재 이유가 "이 다음에 뭐가 오는지"라
  /// 아직 안 간 층의 단계까지 있어야 한다.
  void _showIndoorRouteSteps(PoiSearchResult destination) {
    final multi = _indoorMultiFloorRoute;
    final List<RouteStepLeg> legs;
    if (multi != null && multi.isNotEmpty) {
      legs = [
        for (var i = 0; i < multi.segments.length; i++)
          (
            wgs84Points: multi.segments[i].route.points,
            localPoints: multi.segments[i].route.pointsLocalM,
            floorLabel: multi.segments[i].floorName,
            transferModeToNext: multi.segments[i].transferModeToNext,
            nextFloorLabel: i + 1 < multi.segments.length
                ? multi.segments[i + 1].floorName
                : null,
          ),
      ];
    } else {
      final segment = _indoorRouteSegment;
      final floor = _activeFloor;
      if (segment == null || floor == null) return;
      legs = [
        (
          wgs84Points: segment.points,
          localPoints: segment.pointsLocalM,
          floorLabel: floor,
          transferModeToNext: null,
          nextFloorLabel: null,
        ),
      ];
    }
    final steps = buildRouteStepList(legs);
    if (steps.isEmpty) return;
    showRouteStepsSheet(
      context,
      steps: steps,
      destinationName: destination.name,
    );
  }

  void _dismissUserDestinationFromEtaCard() {
    _retainEtaClosePointer();
    _clearUserDestination();
    widget.onGuidanceDismissed?.call();
  }

  void _dismissIndoorRouteFromEtaCard() {
    _retainEtaClosePointer();
    // 야외 구간도 함께 지운다. 실내 구간은 그 야외 구간의 뒷부분이라, 실내만
    // 지우면 밖으로 나갔을 때 방금 끝낸 안내의 앞부분이 혼자 되살아난다.
    _clearUserDestination();
    _clearIndoorRoute();
    widget.onGuidanceDismissed?.call();
  }

  void _retainEtaClosePointer() {
    final pointerDown = _etaClosePointerDown;
    _etaClosePointerDown = null;
    if (pointerDown != null) {
      _mapOverlayTapGuard.retainPointerDown(pointerDown);
    }
  }

  /// 안내가 시작된 순간 **지금 층 경로 전체**가 들어오도록 카메라를 한 번 크게
  /// 움직인다. 층 도면이 아니라 경로에 맞추는 이유는 사용자가 알고 싶은 것이
  /// "어디로 얼마나 가나"이기 때문이고, 지금 층만 담는 이유는 다층 상자에는
  /// 화면에 없는 층 좌표까지 들어가 지금 걸을 구간이 도리어 안 보이기 때문이다.
  ///
  /// **`newLatLngBounds`를 쓰지 않는다** — 그 API는 bearing을 0으로 되돌려, 애써
  /// 세워 둔 도면이 안내를 시작하는 순간 도로 눕는다
  /// (`docs/client/camera-choreography-plan.md` 4.1).
  Future<void> _fitCameraToRouteSegment(
    IndoorRoute route, {
    Duration duration = routeOverviewDuration,
  }) async {
    // 바로 옆 매장이면 담을 것이 없다 — 물러섰다 돌아오는 동작만 남는다.
    if (route.distanceMeters < routeOverviewMinDistanceM) return;
    // 퇴화한 경로(점 2개, 일직선)를 견디는 몫은 [routeBoxFor]가 진다.
    final box = routeBoxFor(route.points, minSideM: routeFitMinSideM);
    if (box == null) return;
    await _animateCameraToFitBox(
      box,
      topChromePx: guidanceFitTopChromePx,
      bottomChromePx: guidanceFitBottomChromePx,
      duration: duration,
      maxZoom: routeFitMaxZoom,
    );
  }

  /// 고른 대중교통 경로를 지도에 그린다.
  ///
  /// 도보 안내는 여기서 **지운다.** 두 선을 겹쳐 두면 어느 쪽이 지금 안내인지
  /// 알 수 없고, 하단 카드가 서로 다른 소요 시간을 말하게 된다.
  ///
  /// [bottomSheetFraction]은 이 호출 **직후에** 열려 화면 아래를 덮을 시트의
  /// 비율이다. 아직 트리에 없어 잴 수 없으므로 부르는 쪽만 안다.
  Future<void> showTransitRoute(
    TransitItinerary itinerary, {
    required ll.LatLng destination,
    required String label,
    ll.LatLng? origin,
    List<TransitItinerary> alternatives = const [],
    double bottomSheetFraction = 0,
  }) async {
    _clearCompletedRouteHistory();
    _clearPendingIndoorRoute();
    _stopFollowingUser();
    setState(() {
      _transitItinerary = itinerary;
      _transitAlternatives = alternatives;
      _transitLabel = label;
      _fixedRouteOrigin = origin;
      // 도보 경로와 그 목적지 핀은 접는다. 목적지 자체는 대중교통 경로의 끝점
      // 으로 그대로 남아 있다.
      _route = null;
      // **자동차 표시를 함께 되돌린다.** 이 값이 남으면 안내를 시작할 때
      // [_startCurrentGuidance]가 자동차 따라가기를 켜, 카메라가 경로 개요
      // 대신 사용자 위치로 끌려간다(경로가 화면 귀퉁이로 밀린다).
      _routeIsDriving = false;
      _guidanceStarted = false;
      _userDestination = destination;
      _userDestinationLabel = label;
    });
    _syncDestinationLayer();
    _syncRouteLayer();
    await _syncTransitLayer();
    _notifyRouteStateIfChanged();
    _fitCameraToPoints(
      itinerary.points,
      bottomSheetFraction: bottomSheetFraction,
    );
  }

  /// 후보 상세에서 확정한 경로로 **안내를 시작한다.** 셸(길찾기 화면)이
  /// [showTransitRoute] 뒤에 부른다.
  ///
  /// 계획 카드의 `안내 시작`과 **같은 함수**를 태운다 — 여기에만 있는 판단이
  /// 생기면 두 버튼이 서로 다른 조건에서 시작한다. 경로에서 멀면 그쪽 가드가
  /// 막고 안내 문구만 뜬다(그때 카드에 버튼이 남는 것이 맞다).
  Future<void> startGuidanceForPickedRoute() => _startCurrentGuidance();

  /// 대중교통 안내를 끈다. 경로선·요약 카드가 함께 사라진다.
  void clearTransitRoute() {
    if (_transitItinerary == null) return;
    setState(() {
      _transitItinerary = null;
      _transitAlternatives = const [];
      _transitLabel = null;
      _guidanceStarted = false;
    });
    unawaited(_syncTransitLayer());
    _notifyRouteStateIfChanged();
  }

  /// [point]에서 가장 가까운 지상 출입구 좌표. 문 데이터가 없으면 null이다.
  ///
  /// 대중교통 안내가 **내린 자리 기준으로** 문을 고를 때 쓴다. 예전에는 이
  /// 판단이 없어 하차 지점과 무관하게 매장 좌표로 도보 경로를 그렸고, 그러면
  /// TMAP이 매장에서 가장 가까운 도로로 스냅해 **내린 곳 반대편 문**으로
  /// 데려가는 일이 실제로 있었다.
  ll.LatLng? entranceNearestTo(ll.LatLng point) =>
      nearestEntrance(_groundEntrances, point)?.point;

  /// 실내/야외 경로 중 하나라도 활성이면 true. ETA 카드 노출과 하단 바 리프트
  /// 판정에 쓴다.
  bool get _hasAnyRouteVisible =>
      _route != null ||
      _transitItinerary != null ||
      _indoorRouteSegment != null ||
      _indoorMultiFloorRoute != null;
}
