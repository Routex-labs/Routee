// ignore_for_file: invalid_use_of_protected_member
//
// part라 `setState`(protected) 호출이 경고로 잡힌다.
/// `OutdoorMapBodyState`의 **GPS·위치** 부분.
///
/// part 규약과 이 파일로 가른 이유는 `docs/client/outdoor-map-moves.md`.
part of '../outdoor_map_screen.dart';

extension OutdoorMapGps on OutdoorMapBodyState {
  /// GPS 구독을 붙여 둘 상태인지. **실내에서도 끊지 않는다** — 이탈 판정의 유일한
  /// 입력이라, 끊으면 조작 없이 걸어 나갔을 때 알 방법이 없다. 끊는 경우는 화면이
  /// 안 보일 때뿐이다.
  ///
  /// 그 좌표를 **화면에 쓸지**는 별개 게이트가 맡는다([_outdoorGpsVisible]).
  bool get _gpsTrackingWanted => widget.active;

  /// GPS 기반 **표시**를 써도 되는 상태인지 — 위치 마커·'신호 약함' 배지·첫 위치
  /// 카메라가 여기 걸린다. [_gpsTrackingWanted](구독 여부)와 반드시 구분한다 —
  /// 겸하면 실내 도면 위에 건물 밖 GPS 점이 찍힌다.
  bool get _outdoorGpsVisible => widget.active && !_indoorEntered;

  void _syncGpsSubscription() {
    if (_gpsTrackingWanted) {
      _gps.start();
      return;
    }
    _gps.stop();
    // 마지막으로 알던 GPS 위치도 버린다. 남겨두면 실내에 들어간 뒤에도 마커가
    // 그려지거나("GPS 기반 위치가 보이면 안 된다"), 다시 야외로 나왔을 때 옛
    // 좌표가 잠깐 현재 위치인 것처럼 보인다.
    _pendingCenterOnPosition = false;
    if (!mounted) return;
    setState(() => _position = null);
    _syncCurrentLayer();
  }

  void _handlePositionError() {
    if (!mounted) return;
    setState(() => _position = null);
    _syncCurrentLayer();
  }

  void _handlePosition(Position position, {bool fromStream = false}) {
    if (!mounted || !_gpsTrackingWanted) return;
    // 좌표가 얼마 만에 왔는지는 **기기가 찍은 시각**으로 잰다. 앱이 받은 시각을
    // 쓰면 프레임이 밀린 시간까지 섞여, 스트림이 느린 것인지 화면이 느린 것인지
    // 구분되지 않는다. 진단 칩에만 쓰이는 값이다.
    final sinceLastFix = _lastFixAt == null
        ? null
        : position.timestamp.difference(_lastFixAt!);
    _lastFixAt = position.timestamp;
    // 실내에서도 좌표는 **들고 있는다.** 진입/이탈 판정의 유일한 입력이고,
    // 화면에 그릴지는 [_outdoorGpsVisible]이 따로 가른다([_syncCurrentLayer]).
    setState(() => _position = position);
    _syncCurrentLayer();
    // 안내 중이면 카메라가 사용자를 따라간다. 판정보다 먼저 두는 이유는, 이번
    // 위치로 실내에 들어가면 따라가기가 꺼지기 때문이다 — 그때는 카메라의
    // 주인이 실내 위치(PDR)로 바뀐다.
    if (_followingUser) {
      unawaited(_moveCameraToUser(position));
    }
    // 앱을 켠 직후 딱 한 번, 첫 좌표로 지도를 옮긴다. 안 하면 서울시청
    // (fallbackLocation)에서 시작해 사용자가 직접 자기 자리를 찾아야 한다.
    // 조건과 그 근거는 [shouldCenterOnFirstFix]에 있다.
    //
    // "사용자가 이미 지도를 만졌는가"는 보지 않는다 — 그걸 추적하는 상태가
    // 없고, 첫 fix는 보통 1~2초 안에 온다.
    else if (shouldCenterOnFirstFix(
      alreadyCentered: _didInitialCenter,
      followingUser: _followingUser,
      indoorEntered: _indoorEntered,
      initialCameraClaimed: _initialCameraClaimed,
      mapReady: _styleReady && _mapController != null,
    )) {
      _didInitialCenter = true;
      // 카메라가 어디로 왜 갔는지는 화면만 봐서는 못 가린다. 공유 링크가 맞춰
      // 둔 매장 화면을 이 줄이 가져가고 있었는데, 조용해서 한참 못 찾았다.
      debugPrint('[first fix] 첫 좌표로 카메라를 옮긴다');
      unawaited(_moveCameraToUser(position));
    }
    // 문 선택은 진입 판정보다 **먼저** 갱신한다. 진입 직후 실내 위치를 잡을 때
    // 폴백으로 쓰는 문이 이 선택의 결과라, 순서를 뒤집으면 사용자가 이미 다른
    // 문으로 들어왔는데 폴백은 한 박자 전 문을 가리킨다.
    if (!_indoorEntered) _syncSelectedEntrance();
    // 좌표 한 건이 하는 일은 셋뿐이다. **진입·이탈 전환은 여기 없다** — 그것은
    // 안내 카드의 버튼이 한다(`docs/client/indoor-entry-rules.md` 6절).
    final judgement = judgeBuildingFromGps(
      fix: GpsFix(
        point: ll.LatLng(position.latitude, position.longitude),
        accuracyMeters: position.accuracy,
      ),
      footprint: _buildingFootprint,
    );
    // 1) 빗장. 밖을 한 번이라도 봤으면 이 사람은 걸어 들어온 것이다.
    if (saysOutsideBuilding(judgement)) _sawOutsideSinceLaunch = true;
    // 2) 앱을 건물 안에서 켠 사용자를 실내로 데려간다. 앱을 켠 뒤 딱 한 번이다.
    _maybeEnterIndoorOnColdStart(judgement, position);
    // 3) 진입·이탈 버튼의 게이트와 디버그 진단 칩.
    _updateTransitionDebugChip(sinceLastFix: sinceLastFix);
    // 게이트가 열리고 닫히는 것이 하단 카드의 버튼 색으로 보여야 한다. 안내 중이
    // 아니면 그 버튼 자체가 없으므로 rebuild를 걸지 않는다 — GPS 틱마다 지도 위
    // 오버레이를 통째로 다시 그리게 된다.
    if (_guidanceStarted) setState(() {});
    // 여기서부터는 야외 전용이다. 건물 안에서 GPS로 걷기 경로를 다시 그리면,
    // 실내 도면 위에 건물을 관통하는 선이 얹힌다.
    if (_indoorEntered) return;
    _updateOutdoorDisplayProgress(position);
    unawaited(_syncRouteLayer());
    // 스트림이 준 좌표라고 알려, 제자리에서 초당 한 번씩 TMAP을 다시 부르지
    // 않게 한다([_updateRoute]). 진행률·회색선 갱신은 그 거르기와 무관하게
    // 매 좌표마다 돌아야 하므로 위 두 줄은 거르지 않는다.
    _updateRoute(position, fromPositionStream: true);
  }

  /// 실내에서 앱을 켠 직후, **층을 먼저 묻고** 그 층으로 실내 위치를 잡는다.
  ///
  /// GPS는 건물 안이라는 것까지만 말한다. 그대로 두면 [_activeFloor]가 건물의
  /// `default_floor`(1F)로 굳어, B2에 서 있는 사람의 위치와 경로가 1층에 찍힌다.
  ///
  /// **묻는 것은 앱을 켠 뒤 한 번뿐이다**([_entryFloorAsked]). 건너뛰면(null)
  /// 기본 층으로 간다 — 층은 선택기로 언제든 바꿀 수 있고, 여기서 막으면 판정이
  /// 틀렸을 때의 출구가 사라진다.
  Future<void> _askEntryFloorThenTrack(Position position) async {
    // **경로를 그리는 중이면 아무것도 묻지 않는다.** 목적지를 정해 두고 앱을 켠
    // 길이 있는데, 그때 층·매장을 묻는 시트가 뜨면 방금 보던 경로를 통째로
    // 덮는다. **위치는 그대로 자동으로 잡는다** — 묻지 않는 것과 추적하지 않는
    // 것은 다르다.
    if (_guidancePlanned) {
      await _startIndoorTracking(position: position);
      return;
    }
    final floor = await _askEntryFloor();
    if (!mounted || !_indoorEntered) return;
    // 층 전환은 chip을 누른 것과 **같은 경로**를 탄다 — 도면 교체와 그 층
    // 외곽선에 맞춘 카메라 정렬이 거기 붙어 있다([_onFloorChipSelected]).
    if (floor != null && floor != _activeFloor) {
      await _onFloorChipSelected(floor);
      if (!mounted || !_indoorEntered) return;
    }
    await _startIndoorTracking(position: position);
    if (!mounted || !_indoorEntered) return;
    // 자동으로 띄우는 것은 **진입 한 번에 한 번뿐이다**. 버튼으로 다시 여는
    // 쪽은 이 제한을 받지 않는다.
    await _askNearbyStoreForAnchor(once: true);
  }

  /// GPS가 잡아 준 **어림 위치를 사람이 다듬게 한다.**
  ///
  /// 자동 배치는 "이쯤"까지다 — 건물 안 GPS는 오차가 십수 m라 복도 하나쯤은
  /// 예사로 틀린다. 지금 무엇 앞에 서 있는지는 **사람이 훨씬 정확히 안다.**
  /// 고른 매장의 입구 노드가 곧 위치가 된다.
  ///
  /// 어림 위치조차 없으면(층 그래프가 없거나 스냅 실패) 묻지 않는다 — 거리를
  /// 잴 기준이 없어 "가까운 순"이 성립하지 않는다. 그때는 지금까지처럼 하단
  /// 바의 "위치 지정"이 출구다.
  Future<void> _askNearbyStoreForAnchor({bool once = false}) async {
    if (once && _nearbyStoreAsked) return;
    final rows = _nearbyStoreRows();
    if (rows.isEmpty) return;
    if (once) _nearbyStoreAsked = true;
    final picked = await showNearbyStoreSheet(context, rows: rows);
    if (picked == null || !mounted || !_indoorEntered) return;
    await _anchorAtNearbyStore(picked);
  }

  /// 지금 어림 위치에서 가까운 매장 줄. 기준점이 없거나 층 도면이 없으면 빈 목록.
  List<NearbyStoreRow> _nearbyStoreRows() {
    final plan = _floorPlan;
    final graph = _floorGraph;
    if (plan == null || graph == null || graph.nodes.isEmpty) return const [];
    final from = _pdrTrailState.anchor?.anchorLocalM ?? _estimatedFloorPoint();
    if (from == null) return const [];

    final transform = fitFloorGeoTransform(graph.nodes);
    final nodeById = {for (final node in graph.nodes) node.id: node};
    // 묶음 매장(다른 매장 이름을 이어 붙인 구역 항목)은 지도에서도 탭 대상이
    // 아니다([aggregateStoreIds]). 목록에서도 빼야 같은 자리가 두 줄이 되지 않는다.
    final aggregates = aggregateStoreIds(plan.stores);
    final storeById = <String, StorePolygon>{};
    final points = <({String id, double x, double y})>[];
    for (final store in plan.stores) {
      if (aggregates.contains(store.id)) continue;
      // **수직이동 구조물은 뺀다.** 이름이 층마다 열 몇 개씩 같아서
      // ("에스컬레이터" 1F에만 16개) 목록을 채우기만 하고, 무엇을 고른 것인지
      // 사용자가 가릴 수 없다. 위치의 기준으로도 나쁘다 — 타고 오르내리는
      // 자리라 "그 앞에 서 있다"가 한 지점을 가리키지 않는다.
      if (kVerticalTransportStoreNames.contains(store.name)) continue;
      // **입구 노드를 먼저 쓴다.** 고른 뒤 앵커를 찍을 자리가 바로 그 노드라,
      // 목록에 적힌 거리와 실제로 옮겨 가는 자리가 같아야 한다.
      final node = nodeById[store.entranceNodeId];
      final double x;
      final double y;
      if (node != null) {
        x = node.xM;
        y = node.yM;
      } else {
        final local = transform.invert(
          store.centroid.latitude,
          store.centroid.longitude,
        );
        if (local == null) continue;
        x = local.$1;
        y = local.$2;
      }
      storeById[store.id] = store;
      points.add((id: store.id, x: x, y: y));
    }

    return [
      for (final near in nearestAroundMe(
        fromX: from.eastM,
        fromY: from.northM,
        points: points,
      ))
        if (storeById[near.id] case final store?)
          (store: store, distanceM: near.distanceM),
    ];
  }

  /// GPS를 층 그래프에 투영해 둔 어림 위치. 없으면 null.
  PdrLocalPoint? _estimatedFloorPoint() {
    final estimate = indoorLocationEstimateController.current;
    if (estimate == null || estimate.floorId != _activeFloor) return null;
    return estimate.localM;
  }

  /// 고른 매장 앞을 지금 위치로 확정한다. 지도를 탭해 찍는 것과 **같은 함수**를
  /// 지나 방향 보정까지 같은 규칙을 탄다([_confirmPdrAnchor]).
  Future<void> _anchorAtNearbyStore(StorePolygon store) async {
    final graph = _floorGraph;
    if (graph == null) return;
    final node = graph.nodes
        .where((n) => n.id == store.entranceNodeId)
        .firstOrNull;
    final PdrLocalPoint floorPoint;
    if (node != null) {
      floorPoint = PdrLocalPoint(node.xM, node.yM);
    } else {
      // 입구 노드가 없는 매장은 중심점을 통로에 붙인다 — 수동 배치가 탭 좌표에
      // 하는 것과 같다. 붙일 통로를 못 찾으면 찍지 않는다: 틀린 자리를 찍는
      // 것보다 어림 위치를 그대로 두는 편이 낫다.
      final local = fitFloorGeoTransform(
        graph.nodes,
      ).invert(store.centroid.latitude, store.centroid.longitude);
      if (local == null) return;
      final snapped = FloorMapMatcher(
        graph,
      ).snapToWalkableNetwork(PdrLocalPoint(local.$1, local.$2));
      if (snapped == null) return;
      floorPoint = snapped.point;
    }
    await _confirmPdrAnchor(floorPoint);
    if (!mounted) return;
    // **찍은 자리로 데려간다.** 시트를 걷고 나면 위치 점이 화면 밖일 수 있는데,
    // 그러면 방금 고른 것이 반영됐는지 확인할 방법이 없다. "내 위치로"와 같은
    // 함수를 써서 bearing을 건드리지 않는다 — 도면에 맞춰 둔 방향이 틀어지면
    // 사용자가 보던 배치를 잃는다.
    await _recenterOnCurrentPosition();
  }

  /// 층을 묻는다. 물을 이유가 없으면(이미 물었다·건물을 모른다·층이 하나뿐)
  /// 묻지 않고 null.
  Future<String?> _askEntryFloor() async {
    if (_entryFloorAsked) return null;
    final building = _building;
    if (building == null || building.floors.length < 2) return null;
    _entryFloorAsked = true;
    return showEntryFloorPrompt(
      context,
      buildingName: building.name,
      floors: building.floors,
    );
  }

  /// 실내 위치(PDR 앵커)를 잡고 센서 추적을 시작한다. 부르는 곳이 둘이고, 그
  /// 둘이 **아는 것이 다르다**.
  ///
  ///   - 진입 버튼([enterIndoorFromGuidance]) — [entrance]를 준다. 사용자가 방금
  ///     그 문을 통과했다는 것이 가장 확실한 근거이고, 문 노드는 이미 통로 위의
  ///     점이라 붙일 필요도 없다.
  ///   - 실내에서 앱을 켠 경우([_askEntryFloorThenTrack]) — 문을 모른다. 어느
  ///     복도에 서 있는지 아는 것은 GPS뿐이라 그 좌표를 통로에 붙인다.
  ///
  /// 그래서 사다리가 셋이다: 문 노드 → GPS 스냅 → 아는 문 좌표. [entrance]가
  /// null이면 첫 칸을 건너뛴다.
  ///
  /// **실패 조건 셋** — 이미 확정된 앵커가 있다·층 그래프가 없다·사다리 셋이 다
  /// 실패. 하나라도 걸리면 포기하고 수동 경로를 안내한다: 틀린 위치를 찍는
  /// 것보다 위치가 없는 편이 낫다.
  Future<void> _startIndoorTracking({
    required Position position,
    BuildingEntrance? entrance,
  }) async {
    if (indoorNavigationDriver.currentCalibration.canRenderPosition) return;

    // 건물이 막 도착한 직후라면 층 그래프 요청이 아직 도는 중이다.
    await _floorGraphLoad;
    if (!mounted || !_indoorEntered) return;

    final floor = _activeFloor;
    final graph = _floorGraph;
    final buildingId = _building?.id;
    if (buildingId == null ||
        floor == null ||
        graph == null ||
        graph.nodes.isEmpty ||
        graph.edges.isEmpty) {
      _replaceSnack('이 층의 지도 정보가 없어 실내 위치를 자동으로 잡지 못했습니다. 위치 지정으로 직접 지정해주세요.');
      return;
    }

    final transform = fitFloorGeoTransform(graph.nodes);
    final matcher = FloorMapMatcher(graph);

    /// [point](WGS84)를 층 좌표로 옮겨 통로에 붙인다. 옮기지 못했거나 통로에서
    /// [maxGapM]보다 멀면 null — 그 자리는 걸을 수 있는 곳이 아니다.
    ({PdrLocalPoint point, double gapM})? snap(
      ll.LatLng point,
      double maxGapM,
    ) {
      final local = transform.invert(point.latitude, point.longitude);
      if (local == null) return null;
      final snapped = matcher.snapToWalkableNetwork(
        PdrLocalPoint(local.$1, local.$2),
      );
      if (snapped == null || snapped.distanceToGraphM > maxGapM) return null;
      return (point: snapped.point, gapM: snapped.distanceToGraphM);
    }

    // 1순위는 방금 통과한 문의 **그래프 노드**다. 좌표 변환도 스냅도 거치지
    // 않으므로 [_groundEntranceNodesM](나가기 게이트가 재는 값)과 정확히 같은
    // 점이고, 오차가 끼어들 자리가 없다.
    final doorNode = entrance == null
        ? null
        : graph.nodes.where((node) => node.id == entrance.nodeId).firstOrNull;
    ({PdrLocalPoint point, double gapM})? snapped = doorNode == null
        ? null
        : (point: PdrLocalPoint(doorNode.xM, doorNode.yM), gapM: 0);
    var estimateSource = 'entrance';
    if (snapped == null) {
      // 2순위는 GPS 좌표를 통로에 붙이는 것. 실내에서 앱을 켠 사용자에게는 이것이
      // 1순위이고, 진입 버튼 쪽에서는 문 노드가 이 층 그래프에 없을 때의 폴백이다
      // (출입구 데이터와 층 그래프가 어긋난 건물).
      snapped = snap(
        ll.LatLng(position.latitude, position.longitude),
        autoEntryGpsSnapDistanceM,
      );
      estimateSource = 'gps';
    }
    if (snapped == null) {
      // 3순위는 지금 안내 기준으로 쥐고 있는 문. GPS 점이 매장 한가운데에 찍혀
      // 통로를 못 찾은 경우의 안전한 폴백이다 — 건물 안에 있는 사람은 어느 문이든
      // 통과했다.
      final known = _entrance;
      snapped = known == null
          ? null
          : snap(known, maxEntranceAnchorSnapDistanceM);
      estimateSource = 'entrance';
    }
    if (snapped == null) {
      // 실측 거리를 함께 노출하고 싶지만, 여기까지 왔다는 것은 두 좌표 모두
      // 스냅에 실패했다는 뜻이라 적을 거리 자체가 없다. 사용자가 할 수 있는 일만
      // 알린다 — 수동 지정은 탭한 자리를 그대로 쓰므로 이 실패와 무관하다.
      _replaceSnack('실내 위치를 자동으로 잡지 못했습니다. 위치 지정으로 직접 지정해주세요.');
      return;
    }

    final estimatedPoint = snapped.point;
    final estimatedWgs84 = transform.apply(
      estimatedPoint.eastM,
      estimatedPoint.northM,
    );
    indoorLocationEstimateController.update(
      IndoorLocationEstimate(
        buildingId: buildingId,
        floorId: floor,
        localM: estimatedPoint,
        wgs84: ll.LatLng(estimatedWgs84.$1, estimatedWgs84.$2),
        accuracyMeters: position.accuracy,
        observedAt: position.timestamp,
        source: estimateSource,
      ),
    );
    unawaited(_syncPdrCurrentLayer());

    // GPS로 건물 안임을 이미 확인했으므로 권한 게이트를 다시 두지 않는다. 세션이
    // 다른 층에서 돌고 있으면 이 층으로 옮겨야 앵커가 이 층으로 기록된다.
    if (!await _bindPdrSessionToFloor(floor, gatePermission: false)) return;
    await _awaitSensorWarmup();
    if (!mounted || !_indoorEntered) return;

    final axes = fitPdrToFloorAxes(graph.nodes);
    await indoorNavigationDriver.confirmAnchorByPin(
      floorPointM: estimatedPoint,
      axes: axes,
    );
    if (!mounted) return;

    // 자북 heading을 못 얻는 기기는 여기서 방향 보정을 기다린다. 수동 배치는
    // 사용자에게 다이얼로그로 물어보지만, 자동 진입에서 아무 조작 없이 모달이
    // 튀어나오면 사용자는 자기가 뭘 눌러 띄운 건지 알 수 없다. 대신 진입 방향을
    // 추정해 그 자리에서 확정한다([_entryFloorDirection]).
    if (indoorNavigationDriver.currentCalibration.phase ==
        CalibrationPhase.awaitingHeading) {
      final direction = _entryFloorDirection(
        position: position,
        anchorFloorPoint: estimatedPoint,
        graph: graph,
        axes: axes,
      );
      if (direction == null) {
        _replaceSnack('진입 방향을 알 수 없습니다. 위치 지정으로 직접 지정해주세요.');
        return;
      }
      await indoorNavigationDriver.confirmAnchorByFloorDirection(
        floorDirection: direction,
      );
      if (!mounted) return;
    }

    _syncPdrCurrentLayer();
    unawaited(_syncDebugPdrLayers());
    // 이제 실내 마커가 있다. 진입 순간에는 위치를 몰라 건너뛴 연출
    // ([_setIndoorEntered])을 여기서 한다 — 카메라는 아직 진입 직전의 야외
    // 화면이라, 방금 찍은 마커가 화면 밖일 수 있다.
    unawaited(_centerOnIndoorMarker());
    // 입구에서 위치를 새로 잡았으므로, 건물에 들어오기 전에 골라둔 출발지 매장은
    // 더 이상 "지금 내가 있는 곳"이 아니다. 상위가 그 값을 버리게 알린다.
    widget.onLocationAnchored?.call();
    _replaceSnack('입구를 기준으로 실내 위치를 잡았습니다. 걸음 추적을 시작합니다.');
  }

  /// 자동차 안내를 시작한다 — 카메라를 현재 위치로 확대하고, 이후 위치가 갱신될
  /// 때마다 그 자리를 따라간다.
  ///
  /// 위치를 아직 못 잡았어도 **켜 둔다.** 신호가 잡히는 순간 첫 위치가 카메라를
  /// 데려가므로, 여기서 포기하면 터널을 나오며 안내를 시작한 사용자가 영영
  /// 따라가지 못한다. 대신 지금 아무 일도 안 일어나는 이유는 알린다.
  Future<void> startFollowingCurrentLocation() async {
    _followingUser = true;
    final position = _position;
    if (position == null) {
      _showSnack('현재 위치를 아직 못 잡았습니다. 신호가 잡히면 그 자리로 지도를 옮깁니다.');
      return;
    }
    await _moveCameraToUser(position, zoom: carGuidanceZoom);
  }

  /// 따라가기를 멈춘다. 안내가 끝나거나(경로 삭제) 카메라의 주인이 바뀌는
  /// 지점(새 경로 계산)에서 부른다 — 안 멈추면 사용자가 지도를 옮겨도 다음 위치
  /// 한 건이 곧바로 되돌려 놓아 지도를 조작할 수 없다.
  void _stopFollowingUser() => _followingUser = false;

  /// 안내 중 "내 위치로" 버튼. **bearing과 tilt는 건드리지 않는다** — 정북으로
  /// 돌아가면 화면 위쪽이 갈 방향과 어긋난다. 배율도 [walkingViewZoom]까지만 당긴다.
  Future<void> _recenterOnCurrentPosition() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    final here = _pdrCurrentWgs84();
    // 위치를 아직 못 그리는 상태면 되돌릴 자리도 없다. 버튼 노출 조건이 같은
    // 값을 보므로([_canRecenterOnCurrentPosition]) 보통은 여기 안 걸린다.
    if (here == null) return;
    await recenterKeepingBearing(
      controller,
      here,
      minZoom: walkingViewZoom,
      duration: recenterDuration,
    );
  }

  /// "내 위치로" 버튼을 띄울지. 누를 자리가 없는 버튼을 띄우지 않기 위해
  /// [_recenterOnCurrentPosition]이 실제로 쓰는 값과 **같은 값**을 본다.
  bool get _canRecenterOnCurrentPosition =>
      _indoorLocationVisible && _pdrCurrentWgs84() != null;
}
