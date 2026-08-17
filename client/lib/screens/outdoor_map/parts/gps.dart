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
      storeFocusOwnsCamera: _storeFocusOwnsCamera,
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
    _applyBuildingVerdict(position, sinceLastFix: sinceLastFix);
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

  /// 자동 실내 진입 직후, 실내 위치(PDR 앵커)를 잡고 센서 추적을 시작한다.
  ///
  /// **시작점은 방금 그 GPS 좌표에서 가장 가까운 통로 지점**이고, 스냅이 안 되면
  /// 방금 지나온 문으로 폴백한다(들어온 사람은 어느 문이든 통과했다).
  ///
  /// **실패 조건 셋** — 이미 확정된 앵커가 있다·층 그래프가 없다·스냅도 폴백도
  /// 실패. 하나라도 걸리면 포기하고 수동 경로를 안내한다: 틀린 위치를 찍는 것보다
  /// 위치가 없는 편이 낫다.
  Future<void> _startTrackingFromGpsFix(Position position) async {
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

    // 1순위는 GPS 좌표다. 진입 판정을 통과한 좌표라 이미 "믿을 수 있고 건물 안"
    // 이며, 사용자가 실제로 서 있는 곳에 가장 가깝다.
    var snapped = snap(
      ll.LatLng(position.latitude, position.longitude),
      autoEntryGpsSnapDistanceM,
    );
    var estimateSource = 'gps';
    if (snapped == null) {
      // 2순위는 방금 지나온 문. 건물에 들어온 사람은 어느 문이든 통과했으므로,
      // GPS 점이 매장 한가운데에 찍혀 통로를 못 찾은 경우의 안전한 폴백이다.
      final entrance = _entrance;
      snapped = entrance == null
          ? null
          : snap(entrance, maxEntranceAnchorSnapDistanceM);
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
    // 버튼을 눌렀으면 이제 안내 중이다. 계획 상태로 되돌리는 길은 안내 종료뿐.
    if (_offerStartGuidance) setState(() => _offerStartGuidance = false);
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
