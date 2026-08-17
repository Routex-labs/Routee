// ignore_for_file: invalid_use_of_protected_member
//
// part라 `setState`(protected) 호출이 경고로 잡힌다.
/// `OutdoorMapBodyState`의 **실내 오버레이·층·매장** 부분.
///
/// part 규약과 이 파일로 가른 이유는 `docs/client/outdoor-map-moves.md`.
part of '../outdoor_map_screen.dart';

extension OutdoorMapIndoor on OutdoorMapBodyState {
  /// 지금 보고 있는 층을 상위에 알린다. 실내 오버레이가 꺼져 있으면 층 개념이
  /// 없으므로 null이다 — 층·진입 상태 둘 중 하나만 바뀌어도 결과가 달라지므로
  /// 양쪽 변경 지점에서 모두 부른다.
  void _notifyActiveFloor() {
    final floor = _indoorEntered ? _activeFloor : null;
    if (_notifiedFloor == floor) return;
    _notifiedFloor = floor;
    widget.onFloorChanged?.call(floor);
  }

  /// 다음 자동 재시도를 예약한다. 이미 예약돼 있거나 사다리를 다 썼으면 아무
  /// 것도 하지 않는다.
  void _scheduleBuildingRetry() {
    if (_buildingRetryTimer != null) return;
    if (_buildingRetryAttempt >= _buildingRetryDelays.length) return;
    final delay = _buildingRetryDelays[_buildingRetryAttempt++];
    _buildingRetryTimer = Timer(delay, () {
      _buildingRetryTimer = null;
      // 사람이 누른 재시도가 도는 중이면 그 결과를 기다린다. 실패하면 그쪽이
      // 다시 사다리를 이어 준다.
      if (!mounted || _retryingBuildingLoad) return;
      unawaited(_loadBuildingEntrance());
    });
  }

  Future<void> _retryBuildingLoad() async {
    if (_retryingBuildingLoad) return;
    // 사람이 직접 눌렀다는 것은 "지금은 될 것 같다"는 신호다. 사다리를 처음
    // 부터 다시 쓸 수 있게 되돌려, 이번에도 실패하면 짧은 간격부터 다시 시도한다.
    _buildingRetryTimer?.cancel();
    _buildingRetryTimer = null;
    _buildingRetryAttempt = 0;
    setState(() => _retryingBuildingLoad = true);
    await _loadBuildingEntrance();
    if (!mounted) return;
    setState(() => _retryingBuildingLoad = false);
  }

  /// 실내 위치를 통째로 버린다 — 앵커, 걸음 궤적, PDR 세션, 실내 경로.
  ///
  /// 사용자가 건물을 나갔다고 GPS가 판정했을 때만 부른다. **넷을 함께 비운다** —
  /// 하나라도 남으면 야외 지도 위에 실내의 흔적이 남는다(세션을 안 끄면 밖에서
  /// 걷는 걸음이 실내 좌표계에 계속 쌓여, "나갔는데도 실내에서 움직인다"가 된다).
  ///
  /// 세션 정지는 기다리지 않는다 — 화면 상태는 지금 즉시 맞아야 한다. 그 Future는
  /// [PdrSessionLifecycle.awaitStop]이 들고 있다가 다음 시작이 기다리게 한다.
  void _dropIndoorPosition() {
    _pdrTrailState.beginNewSession();
    _syncCorridorTracking(null);
    _clearIndoorRoute();
    _pdrLifecycle.stopWithoutWaiting();
  }

  /// 활성 층의 통행 그래프와 매장 목록(FloorPlan)을 함께 로드한다.
  /// - 그래프: PDR 앵커 배치·스냅과 마커 렌더링에 쓰인다.
  /// - 평면도: 실내 오버레이 위 매장 폴리곤 탭으로 벡터 타일 feature id를
  ///   실제 매장 정보로 되돌리는 데 쓴다.
  /// 실패는 조용히 넘겨 그래프/평면도 없이 층 시각화만 유지한다.
  Future<void> _loadFloorGraph(String buildingId, String floor) =>
      _floorGraphLoad = _fetchFloorGraph(buildingId, floor);

  Future<void> _fetchFloorGraph(String buildingId, String floor) async {
    try {
      final geojson = await buildingRepository.getFloorGeoJson(
        buildingId,
        floor,
      );
      // **추월당한 응답은 버린다.** 층을 연달아 바꾸면 요청이 겹치는데,
      // 저장소가 층별 future를 캐시하므로 이미 가 본 층은 즉시, 처음 가는
      // 층은 네트워크 시간 뒤에 도착한다 — 나중에 도착한 이전 층 응답이
      // 지금 층의 도면·그래프를 덮어쓰면, 화면에 그려진 층과 [_floorPlan]이
      // 어긋난다. 그 상태로는 카메라 fit이 엉뚱한 외곽선에 맞고(지하층 정렬
      // 이상), 매장 탭이 feature id를 다른 층 목록에서 찾다 실패하며(탭 불능
      // + 건물 파란 반짝임만 남음), 검색 포커스도 매장을 못 찾는다.
      if (!mounted || _activeFloor != floor) {
        debugPrint(
          '[outdoor overlay] 층 도면 버림: 요청=$floor 지금=$_activeFloor '
          'mounted=$mounted',
        );
        return;
      }
      final graphJson = geojson?['navigation_graph'];
      final graph = graphJson is Map<String, dynamic>
          ? FloorGraph.fromJson(graphJson)
          : null;
      final plan = geojson != null ? FloorPlan.fromJson(geojson) : null;
      final labelPriorities = rankStoreLabels(plan?.stores ?? const []);
      setState(() {
        _floorGraph = graph;
        _floorPlan = plan;
        _storeLabelPriorities = labelPriorities;
        _mapCalibrationVersion =
            geojson?['map_calibration_version'] as String? ?? 'unversioned';
      });
      _syncCorridorTracking(_pdrTrailState.snapshot);
      _syncPdrCurrentLayer();
      unawaited(_syncDebugPdrLayers());
      // 출구 핀은 도면에서만 나오므로 도면이 바뀔 때마다 다시 세운다.
      // 1F 외 층에서는 0개가 되는 것이 정상이다.
      unawaited(_syncGateLayer());
      // 일반 로드에서는 즉시 새 경계를 반영한다. 층 크로스페이드 중에는 이전
      // 경계를 유지하고 [_finalizeIndoorFloorCrossfade]가 투명한 중간 프레임에서
      // 지오메트리를 교체한다 — 바닥보다 외곽선만 먼저 바뀌는 팝을 막는다.
      if (!_deferFloorBoundarySync) {
        unawaited(_syncFloorOutlineLayer());
        _syncDimScrimLayer();
      }
      // MVT 라벨에는 클라이언트가 계산한 순위가 없으므로 레이어의 sort-key
      // 표현식을 새 층 매장 id 순위로 갱신한다.
      unawaited(_syncIndoorOverlayFade());
      // 도면이 없어서 미뤄 둔 카메라 fit이 이 층 것이면 지금 실행한다
      // ([_pendingFloorFit]). 이 자리가 "그 층 외곽선이 처음으로 존재하는"
      // 시점이라, 여기서 맞춰야 배율이 정확히 한 번에 잡힌다.
      final pending = _pendingFloorFit;
      if (pending != null && pending.floor == floor) {
        _pendingFloorFit = null;
        // 이 함수 자체가 `_floorGraphLoad`라서, 기다리는 껍데기를 부르면
        // 자기 자신을 기다린다 — 몸통을 직접 부른다.
        unawaited(_fitCameraToLoadedFloor(pending.duration));
      }
    } catch (error, stackTrace) {
      // 로드 실패 시 앵커 배치·매장 탭은 안내로 막고 나머지 야외 지도 동작은
      // 그대로 유지한다. 성공 경로와 같은 이유로, 추월당한 요청의 실패가
      // 지금 층의 도면을 지우면 안 된다.
      //
      // **삼키되 조용하지는 않게 한다.** 여기서 터지면 층 외곽선·매장 탭·카메라
      // fit이 한꺼번에 죽는데, 화면에는 "실내 기능만 없는" 상태로만 보여서
      // 원인을 화면 밖에서 찾을 단서가 하나도 없다.
      debugPrint('[outdoor overlay] 층 도면 로드 실패($floor): $error\n$stackTrace');
      if (mounted && _activeFloor == floor) {
        setState(() {
          _floorGraph = null;
          _floorPlan = null;
          _storeLabelPriorities = const {};
          _mapCalibrationVersion = 'unversioned';
        });
        // 도면이 사라졌으므로 출구 핀·못 걷는 면도 함께 지운다. 남겨 두면
        // 다른 층 도면 위에 이전 층의 도형이 떠 있다.
        unawaited(_syncGateLayer());
        if (!_deferFloorBoundarySync) {
          unawaited(_syncFloorOutlineLayer());
          _syncDimScrimLayer();
        }
      }
    }
  }

  /// 층 chip 탭·자동 실내 진입 뒤에 실내 오버레이를 보장 노출하기 위한 헬퍼.
  /// - 카메라 zoom이 이탈 임계값 미만(=도면이 사실상 안 보임)이면 진입 임계값
  ///   + 건물 중심으로 이동.
  /// - 카메라가 건물 중심에서 크게 벗어나 있으면 zoom 유지한 채 건물 중심으로 이동.
  /// - 두 조건 모두 아니면 아무 것도 하지 않는다(사용자의 현재 view 존중).
  Future<void> _recenterOnBuildingIfNeeded() async {
    final controller = _mapController;
    final footprint = _buildingFootprint;
    if (controller == null || footprint == null || footprint.length < 3) {
      return;
    }
    final cam = controller.cameraPosition;
    if (cam == null) return;
    final center = _buildingCenter(footprint);
    if (center == null) return;

    // 이탈 임계값 기준으로 판정한다. 진입 임계값(17.5)으로 재면, 넓은 지하층
    // 전체를 담으려고 z≈16.05까지 축소해 둔 사용자가 층 chip을 누르는 순간
    // 카메라가 다시 17.5로 튀어올라 방금 맞춘 view를 빼앗긴다.
    final needZoomIn = cam.zoom < indoorExitZoomThreshold;
    // 건물 중심에서 카메라까지 대략적인 거리. 위경도 도 단위지만 근사적으로
    // 계산해 "화면 밖" 판정에만 쓴다 — 정확한 거리 계산은 필요 없다.
    final distDeg = math.sqrt(
      math.pow(cam.target.latitude - center.latitude, 2) +
          math.pow(cam.target.longitude - center.longitude, 2),
    );
    // 대략 300m 이상 떨어져 있으면 화면 밖으로 간주(37°에서 0.003° ≈ 300m).
    final farFromBuilding = distDeg > 0.003;

    if (!needZoomIn && !farFromBuilding) return;

    // 확대해 줄 때의 목표 zoom도 화면 폭에 맞춘 임계값을 쓴다. 고정 17.5로
    // 올리면 폰에서는 건물이 화면 밖으로 넘치게 확대돼, 포커스를 맞췄는데
    // 오히려 건물이 안 보이게 된다.
    final targetZoom = needZoomIn ? _entryZoomThreshold() : cam.zoom;
    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(_toGl(center), targetZoom),
    );
  }

  ll.LatLng? _buildingCenter(List<ll.LatLng> footprint) {
    if (footprint.isEmpty) return null;
    var minLat = double.infinity, maxLat = double.negativeInfinity;
    var minLng = double.infinity, maxLng = double.negativeInfinity;
    for (final p in footprint) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return ll.LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
  }

  /// 실내(PDR) 위치를 써도 되는 상태인지 — [_outdoorGpsVisible]의 반대쪽 짝이고
  /// **동시에 true가 되지 않는다.**
  ///
  /// 없으면 축소해 나온 야외 지도에 실내 위치 아이콘이 공중에 떠 있고, 길찾기
  /// 출발지도 그 실내 앵커로 잡힌다.
  bool get _indoorLocationVisible => _indoorEntered;

  /// 위치 한 건이 말하는 건물 안팎을 상태에 반영한다. 판정 자체는
  /// [judgeBuildingFromGps]가 하고 여기서는 **그 판정으로 무엇을 할지**만 정한다.
  ///
  ///   - 안 + 야외 상태 + 자동 진입 무장 → 실내로 들어가고 위치를 잡는다.
  ///   - 밖 + 실내 위치가 잡혀 있던 사람 → 야외로 되돌린다.
  ///   - 모름 → 아무것도 하지 않는다.
  ///
  /// **재무장은 이 셋과 별개 갈래다**([shouldRearmGpsEntry]).
  ///
  /// 이탈 기준이 [_indoorEnteredByGps]가 아니라 [_indoorPositionPlaced]인 이유는
  /// **걸어서 들어온 사람을 놓치기 때문**이다. 앵커가 있다는 건 앱이 이 사람을
  /// 건물 안이라고 믿는다는 뜻이고, 그 믿음은 밖으로 나온 순간 틀린 것이 된다.
  /// 도면만 구경하는 사용자는 앵커가 없어 예전처럼 화면이 안 닫힌다.
  void _applyBuildingVerdict(Position position, {Duration? sinceLastFix}) {
    final judgement = judgeBuildingFromGps(
      fix: GpsFix(
        point: ll.LatLng(position.latitude, position.longitude),
        accuracyMeters: position.accuracy,
      ),
      footprint: _buildingFootprint,
    );
    // 진단 칩은 아래 switch가 상태를 바꾸기 **전에** 채운다. 무장 여부는 이 판정을
    // 내릴 때의 값이어야 하는데, switch가 그 값을 갱신하기 때문이다.
    _gpsVerdictDebugText.value = _debugModeController.enabled
        ? describeGpsBuildingJudgement(
            judgement,
            armed: _gpsEntryArmed,
            sinceLastFix: sinceLastFix,
            fromStream: _gps.lastFixFromStream,
            streamRestarts: _gps.restartCount,
          )
        : null;
    // **재무장은 이 한 줄뿐이다.** 예전에는 아래 outside 갈래 안에 있었는데,
    // 그러면 오차가 커서 `unclear`로 떨어진 좌표는 아무리 건물 밖을 가리켜도
    // 빗장을 못 풀었다 — 유리 외벽 앞처럼 오차가 30 m 아래로 안 내려오는
    // 자리에서 걸어 나감이 끈 빗장이 **영구히** 걸린 채로 남는다.
    //
    // 진단 칩 **뒤에** 둔다. 칩의 무장 표시는 이 판정을 내릴 때의 값이어야 한다.
    if (shouldRearmGpsEntry(judgement)) _gpsEntryArmed = true;
    switch (judgement.verdict) {
      case GpsBuildingVerdict.inside:
        if (_indoorEntered || !_gpsEntryArmed) return;
        // **스낵바를 띄우지 않는다.** 전환 연출의 문구가 같은 말을 더 크게 하고,
        // 둘이 함께 뜨면 하단에서 스낵이 올라오며 덮개와 겹친다.
        //
        // _setIndoorEntered가 이 표식을 보므로 **먼저** 세운다. 연출을 기다리는
        // 동안 좌표가 또 들어와도 위 `_indoorEntered` 검사에 걸리지 않으므로,
        // 겹침 방지는 [_runIndoorTransition]이 맡는다.
        _indoorEnteredByGps = true;
        unawaited(
          _runIndoorTransition(IndoorTransitionDirection.enter, () {
            _setIndoorEntered(true);
            unawaited(_startTrackingFromGpsFix(position));
          }),
        );
      case GpsBuildingVerdict.outside:
        // 재무장은 위에서 이미 했다(이 판정은 거리 조건을 반드시 만족한다).
        if (!_indoorEntered) return;
        if (!_indoorEnteredByGps && !_indoorPositionPlaced) return;
        // 앵커 배치 대기 중이었다면 함께 종료해 하단 바 버튼 톤도 되돌린다.
        if (_placingPdrAnchor) _setPlacingAnchor(false);
        // **이 자리가 유일하게 "정말로 나갔다"고 말할 수 있는 곳이다.**
        // 실내 위치를 버리는 것도, 실내→야외 안내의 야외 구간을 올리는 것도
        // 여기서만 일어난다([_setIndoorEntered]의 leftBuilding).
        //
        // 카메라 이동을 덮개 **안에** 넣는다. 위치의 주인이 GPS로 돌아오는 순간
        // 카메라는 아직 건물을 확대해 보고 있어서, 방금 켠 GPS 마커가 화면 밖일
        // 수 있다 — 그 되돌아오는 움직임을 덮개가 가린다.
        unawaited(
          _runIndoorTransition(IndoorTransitionDirection.exit, () {
            _setIndoorEntered(false, leftBuilding: true);
            unawaited(_moveCameraToUser(position));
          }),
        );
      case GpsBuildingVerdict.unclear:
        break;
    }
  }

  /// 전환 연출을 덮고, **덮개 뒤에서** [apply]를 실행한 뒤 걷어낸다.
  ///
  /// 요점은 순서다. 상태를 먼저 바꾸고 연출을 얹으면 도면·마커가 갈리는 순간이
  /// 그대로 보여서, 이 연출이 없애려는 깜빡임이 남는다. 그래서 덮개가 다 덮일
  /// 때까지([indoorTransitionSwapDelay]) 기다린 다음에 바꾼다.
  ///
  /// **물리적인 진입·이탈에서만 부른다.** 건물 탭·홈 버튼·축소처럼 사용자가 도면을
  /// 여닫는 조작에는 붙이지 않는다 — 2 km 밖에서 건물을 눌러 본 사람에게
  /// "들어가는 중"이라고 말하게 된다.
  ///
  /// 연출 중에 또 불리면 **연출은 겹치지 않게 버리고 [apply]는 그대로 실행한다.**
  ///
  /// 버리는 것이 연출뿐이라는 점이 중요하다. 한때 둘 다 버렸는데, 그러면 문을
  /// 통과했다 곧바로 돌아 나가는 사용자의 이탈이 통째로 삼켜졌다 — 상태는 실내인데
  /// 사람은 밖이고, 다음 좌표가 올 때까지 그대로다. 연출이 어긋나 보이는 것보다
  /// 상태가 틀린 것이 나쁘다.
  Future<void> _runIndoorTransition(
    IndoorTransitionDirection direction,
    VoidCallback apply,
  ) async {
    if (_indoorTransition.isAnimating) {
      apply();
      return;
    }
    setState(() => _indoorTransitionDirection = direction);
    _indoorTransition.duration = indoorTransitionDuration(direction);
    final playing = _indoorTransition.forward(from: 0);
    await Future<void>.delayed(indoorTransitionSwapDelay(direction));
    // 기다리는 동안 화면이 사라졌으면 상태를 바꿀 대상이 없다. 컨트롤러는
    // dispose가 정리한다.
    if (!mounted) return;
    apply();
    await playing;
    if (!mounted) return;
    _indoorTransition.value = 0;
  }

  /// 지금 층의 지상 출입구들을 "안 → 밖" 축으로 만든다.
  ///
  /// 문 목록은 출입구 층 것이고([_groundEntranceFloor]) 축의 두 점은 **그 층의**
  /// 층 좌표라, 다른 층을 보고 있으면 빈 목록이다 — 같은 local m 숫자가 층마다
  /// 다른 자리를 가리키므로 그대로 쓰면 엉뚱한 곳에서 이탈이 발화한다.
  List<EntranceAxis> get _walkoutEntranceAxes {
    final graph = _floorGraph;
    final floor = _activeFloor;
    if (graph == null ||
        graph.nodes.isEmpty ||
        floor == null ||
        floor != _groundEntranceFloor ||
        _groundEntrances.isEmpty) {
      return const [];
    }
    final transform = fitFloorGeoTransform(graph.nodes);
    final axes = <EntranceAxis>[];
    for (final entrance in _groundEntrances) {
      final node = graph.nodes
          .where((n) => n.id == entrance.nodeId)
          .firstOrNull;
      if (node == null) continue;
      final door = transform.invert(
        entrance.point.latitude,
        entrance.point.longitude,
      );
      if (door == null) continue;
      final axis = entranceAxisFrom(
        nodeId: entrance.nodeId,
        nodeM: PdrLocalPoint(node.xM, node.yM),
        doorM: PdrLocalPoint(door.$1, door.$2),
      );
      if (axis != null) axes.add(axis);
    }
    return axes;
  }

  /// 걸어서 출입구를 통과했으면 **GPS를 기다리지 않고** 야외로 되돌린다.
  ///
  /// 나갔으면 true — 호출자는 그 뒤의 실내 갱신을 건너뛴다. 판정에 쓰는 좌표는
  /// 복도 보정 **전** 값이다([EntranceWalkoutDetector.update]).
  ///
  /// 앵커가 다른 층에 있으면 판정하지 않는다. 그때의 층 좌표는 남의 층 숫자다.
  bool _exitIndoorIfWalkedOut() {
    if (!_indoorEntered) return false;
    final anchor = _pdrTrailState.anchor;
    final tracking = _guidance.trackingResult;
    if (anchor == null ||
        tracking == null ||
        anchor.floorId != _activeFloor) {
      return false;
    }
    final axes = _walkoutEntranceAxes;
    if (axes.isEmpty) return false;
    final nodeId = _walkoutDetector.update(
      axes: axes,
      positionM: tracking.rawPreviewPosition,
    );
    if (nodeId == null) return false;

    final entrance = _groundEntrances
        .where((candidate) => candidate.nodeId == nodeId)
        .firstOrNull;
    if (_placingPdrAnchor) _setPlacingAnchor(false);
    // **GPS 자동 진입을 끈다.** 문 앞에서는 건물 Wi-Fi가 아직 잡혀 좌표가 건물
    // 안을 가리키는데, 켜 둔 채 나가면 다음 좌표 한 건이 방금 나온 사용자를
    // 도로 끌고 들어간다. 다시 켜는 곳은 좌표가 건물 밖 거리 문턱을 넘을 때
    // 한 곳뿐이다([shouldRearmGpsEntry]).
    _gpsEntryArmed = false;
    // 위치의 주인이 GPS로 돌아왔다. 실내에서 도면에 맞춰 확대해 둔 화면 그대로
    // 두면 방금 켠 GPS 마커가 화면 밖일 수 있다. 상태 교체와 카메라 되돌리기를
    // 둘 다 덮개 안에 넣는다.
    final position = _position;
    final target = position != null
        ? ll.LatLng(position.latitude, position.longitude)
        : entrance?.point;
    unawaited(
      _runIndoorTransition(IndoorTransitionDirection.exit, () {
        _setIndoorEntered(false, leftBuilding: true);
        if (target != null) unawaited(_moveCameraToPoint(target));
      }),
    );
    // 되돌릴 손잡이를 함께 띄운다. PDR heading이 180도 어긋난 기기에서는 건물
    // 안으로 걸어 들어가는 것이 "나가는 것"으로 읽힐 수 있는데, 그 오판을
    // 사용자가 한 번에 되돌릴 수 있어야 한다.
    //
    // **연출이 끝난 뒤에 띄운다.** 덮개 위로 토스트가 올라오면 문구가 둘이 되고,
    // 손잡이는 사용자가 "어, 잘못 나왔다"고 느낀 다음에 필요한 것이다.
    unawaited(
      Future<void>.delayed(indoorExitTransitionDuration, () {
        if (!mounted) return;
        showDebugToast(
          context,
          message: '출입구를 지나 밖으로 나온 것으로 보고 야외 지도로 돌아갑니다.',
          bottomOffset: mapShellBottomChromePx + 12,
          actionLabel: '실내로 되돌리기',
          onAction: _returnIndoorAfterWalkout,
        );
      }),
    );
    return true;
  }

  /// 걸어 나감 판정이 틀렸을 때 사용자가 되돌리는 길.
  ///
  /// 실내 위치는 [_dropIndoorPosition]이 이미 버렸으므로 되살릴 수 없다 —
  /// 도면만 다시 펴고 위치는 사용자가 다시 지정한다. **GPS 자동 진입은 계속
  /// 꺼 둔다**: 방금 그 판정이 틀렸다는 뜻이지 GPS가 맞다는 뜻이 아니다.
  void _returnIndoorAfterWalkout() {
    if (_indoorEntered) return;
    _walkoutDetector.reset();
    _setIndoorEntered(true);
    unawaited(_recenterOnBuildingIfNeeded());
  }

  /// arbitrary reference 기기에서 쓸 "진입 방향"을 층 좌표 벡터로 만든다.
  /// 층 좌표계는 데이터셋마다 축이 뒤집혀 있을 수 있어, 나침반 각도는 반드시
  /// [axes]를 거쳐 층 벡터로 바꾼다.
  PdrLocalPoint? _entryFloorDirection({
    required Position position,
    required PdrLocalPoint anchorFloorPoint,
    required FloorGraph graph,
    required PdrToFloorAxes axes,
  }) {
    // 1순위: GPS course. 실제로 측정된 이동 방향이라 가장 정확하다. 다만 멈춰
    // 있을 때는 값이 의미 없고 플랫폼이 0으로 채우므로 속도로 먼저 거른다.
    final course = position.heading;
    if (position.speed >= entryCourseMinSpeedMps &&
        course > 0 &&
        course < 360) {
      return axes.apply(pdrDirectionForBearing(course));
    }
    // 2순위: 입구 → 층 그래프 중심. 입구를 통과한 사람은 건물 안쪽을 향한다.
    // GPS course보다 거칠지만, 방향을 몰라 awaitingHeading에 멈춰 서면 앵커가
    // 확정되지 않아 위치 아이콘도 걸음 추적도 아예 없다. 회전이 어긋나면
    // 사용자가 "위치 지정"으로 다시 잡을 수 있으므로 되돌릴 수 있는 오차다.
    var sumX = 0.0;
    var sumY = 0.0;
    for (final node in graph.nodes) {
      sumX += node.xM;
      sumY += node.yM;
    }
    final dx = sumX / graph.nodes.length - anchorFloorPoint.eastM;
    final dy = sumY / graph.nodes.length - anchorFloorPoint.northM;
    // 입구가 그래프 중심과 사실상 같은 점이면 방향 벡터가 0이 된다.
    if (dx * dx + dy * dy < 1e-6) return null;
    return PdrLocalPoint(dx, dy);
  }

  /// 좌표열 전체가 화면에 들어오도록 카메라를 맞춘다. 도보 경로와 대중교통
  /// 경로가 같은 여백 규칙을 쓰도록 뽑아 두었다 — 값이 갈리면 안내를 바꿀
  /// 때마다 경로가 화면에서 다른 크기로 잡힌다.
  void _fitCameraToPoints(List<ll.LatLng> points) {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    unawaited(animateCameraToPoints(controller, points));
  }

  String? _pickStartNodeIdInBuildingGraph({
    required BuildingGraph graph,
    required String startFloorName,
    String? excludingNodeId,
  }) {
    final anchor = _pdrTrailState.anchor;
    if (anchor == null || anchor.floorId != startFloorName) return null;
    // 앵커의 floorId는 사람이 보는 층 라벨이고, 그래프 노드의 floorId는 내부
    // Floor.id다. floorNamesById로 매핑해 그 층의 노드만 후보로 쓴다.
    final floorId = graph.floorNamesById.entries
        .firstWhere(
          (entry) => entry.value == startFloorName,
          orElse: () => const MapEntry('', ''),
        )
        .key;
    if (floorId.isEmpty) return null;
    final candidates = graph.nodes
        .where((node) => node.floorId == floorId)
        .toList(growable: false);
    if (candidates.isEmpty) return null;
    return _nearestNodeId(
      candidates,
      anchor.anchorLocalM.eastM,
      anchor.anchorLocalM.northM,
      excludingNodeId: excludingNodeId,
    );
  }

  Future<void> _syncBuildingLayer() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    await syncPolygonSource(
      controller,
      kOutdoorBuildingSourceId,
      _buildingFootprint,
    );
    // 건물 footprint가 바뀌면 dim scrim의 hole과 층 외곽선도 함께 갱신해야 한다.
    _syncDimScrimLayer();
    _syncFloorOutlineLayer();
  }

  /// 지금 "층 경계"로 삼아야 하는 링. 어느 층이든 그 층 도면의 외곽선이고,
  /// 실내에 들어가 있지 않거나 도면이 아직 없으면 null이다. 규칙과 근거(특히
  /// 지상층에서도 건물 외곽선을 쓰지 않는 이유)는 [floorOutlineRing] 참고.
  ///
  /// 외곽선·dim scrim hole·건물 안 탭 판정이 **모두 이 하나를 본다.** 셋이 서로
  /// 다른 링을 쓰면 사용자가 보는 선 안쪽이 어두워지거나(scrim), 선 안쪽을
  /// 탭했는데 야외로 튕겨 나가는(탭 판정) 모순이 생긴다.
  List<ll.LatLng>? _activeFloorOutlineRing() => floorOutlineRing(
    indoorEntered: _indoorEntered,
    floorFootprint: _floorPlan?.footprint,
  );

  /// 현재 층 외곽선 갱신. 그릴 링이 없으면 소스를 비워 선을 지운다 — 레이어
  /// 속성은 건드리지 않는다(등록 시 넣은 값 그대로 쓴다).
  Future<void> _syncFloorOutlineLayer() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    await syncPolygonSource(
      controller,
      kOutdoorFloorOutlineSourceId,
      _activeFloorOutlineRing(),
    );
  }

  /// 축소 단계에서 어떤 라벨을 먼저 남길지 정하는 `symbolSortKey` 표현식.
  ///
  /// 값이 작을수록 먼저 그려진다(MapLibre 규약). 지금 고른 매장은 항상 0으로
  /// 내려 충돌에서 절대 지워지지 않게 한다 — 강조해 놓고 이름이 사라지면
  /// 무엇을 고른 것인지 화면에서 읽을 수 없다.
  Object _storeLabelSortKeyExpression() => storeLabelSortKeyExpression(
    _storeLabelPriorities,
    selectedStoreId: _highlightedStoreId,
  );

  /// 지금 선택에 해당하는 MapLibre 필터 표현식. 선택이 없으면 아무것도 맞지
  /// 않는 필터를 돌려준다. 레이어 등록 시점과 갱신 시점이 같은 함수를 쓰게 해서
  /// 한쪽만 고쳐 어긋나는 일을 막는다(indoor_overlay_layers.dart의 "등록과
  /// 갱신이 같은 함수를 쓴다" 규칙과 같은 이유).
  List<Object> _categoryFilterExpression() {
    final selection = widget.categorySelection;
    if (selection == null) return kCategoryHighlightNoneFilter;
    return categoryHighlightFilter(selection);
  }

  /// 선택이 바뀌었을 때 오버레이에 반영한다 — 강조 fill의 **필터**와 라벨의
  /// **layout 속성** 둘이 바뀐다.
  ///
  /// 강조 fill에 `setLayerProperties`를 쓰지 않는 이유는 전체 교체라 지도가 검게
  /// 덮이기 때문이다(map-style-rules.md 0절). 라벨은 필터로 못 바꿔 전체 속성을
  /// 다시 만들어 넘긴다.
  Future<void> _applyCategoryFilter() async {
    final controller = _mapController;
    if (controller == null || !_styleReady || !_indoorTilesRegistered) return;
    // 층 전환과 겹치면 이미 제거된 레이어를 가리킬 수 있다. 페이드 갱신과 같은
    // 이유로 삼킨다 — 다음 등록이 어차피 현재 선택으로 필터를 넣어 준다.
    try {
      await controller.setFilter(
        _indoorIds.categoryHighlightFill,
        _categoryFilterExpression(),
      );
    } catch (_) {}
    await syncIndoorOverlayProps(
      controller,
      ids: _indoorIds,
      fadeExpr: _overlayFadeExpr(),
      categorySelection: widget.categorySelection,
      devicePixelRatio: _devicePixelRatio,
      symbolSortKey: _storeLabelSortKeyExpression(),
      // fill·아이콘은 카테고리 선택과 무관하다. 라벨만 다시 민다.
      scope: IndoorOverlaySyncScope.labels,
    );
  }

  /// 오버레이 **레이어**용 페이드 표현식 — [_fadeExpr]에 크로스페이드 계수를 곱한
  /// 것. 레이어 속성을 쓰는 모든 경로가 이걸 써야 페이드 도중 끼어든 갱신이 계수를
  /// 되돌리지 않는다(dim scrim은 층 전환과 무관해 [_fadeExpr] 그대로).
  List<Object> _overlayFadeExpr() {
    return _overlayFadeExprFor(_indoorOverlayFadeFactor);
  }

  List<Object> _overlayFadeExprFor(double factor) {
    if (factor >= 1) return _fadeExpr();
    return indoorOverlayCrossfadeExpr(
      entered: _indoorEntered,
      crossfadeFactor: factor.clamp(0.0, 1.0).toDouble(),
    );
  }

  /// 실내 진입/이탈로 페이드 구간이 바뀌었을 때 이미 등록된 오버레이 레이어의
  /// opacity 표현식을 갈아 끼운다. 레이어가 아직 등록되지 않았으면
  /// [_ensureIndoorTilesRegistered]가 등록 시점의 상태로 넣어주므로 아무것도
  /// 하지 않아도 된다.
  ///
  /// **각 레이어의 전체 속성을 매번 다시 넘긴다.** opacity만 넘기면 안 된다 —
  /// 이유는 indoor_overlay_layers.dart 상단 주석 참고.
  /// 선택 확대를 **카메라 이동과 같은 시간에 걸쳐** 진행한다.
  ///
  /// 크기는 layout 속성이라 MapLibre transition이 안 걸려 손으로 보간한다.
  /// 시작 시점·간격·이징의 근거는
  /// `docs/client/kakao-map-indoor-observation.md` S절.
  Future<void> _animateSelectionScale({required bool selected}) async {
    _selectionScaleTimer?.cancel();
    final from = _selectionScale;
    final to = selected ? kSelectedLabelScale : 1.0;
    if ((from - to).abs() < 0.001) return;

    final started = DateTime.now();
    final completer = Completer<void>();
    _selectionScaleTimer = Timer.periodic(OutdoorMapBodyState._selectionScaleStep, (
      timer,
    ) async {
      final elapsed = DateTime.now().difference(started);
      final t = (elapsed.inMilliseconds / _storeFocusDuration.inMilliseconds)
          .clamp(0.0, 1.0);
      // easeOutCubic — 카메라 이징과 같은 성격이라 둘이 따로 놀지 않는다.
      final eased = 1 - math.pow(1 - t, 3).toDouble();
      _selectionScale = from + (to - from) * eased;
      await _applySelectionScale();
      if (t >= 1.0) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete();
      }
    });
    return completer.future;
  }

  /// 지금 배수를 라벨 두 레이어에 반영한다. **핀은 여기서 건드리지 않는다** —
  /// 핀은 자리가 확정된 뒤에야 나타나므로 시작 시점이 라벨과 다르다
  /// ([_animatePinIn]).
  Future<void> _applySelectionScale() async {
    if (_mapController == null || !_styleReady) return;
    await _syncIndoorOverlayFade(scope: IndoorOverlaySyncScope.labels);
  }

  /// 확정된 자리에서 핀을 자라나게 한다(0.55배 → 1배).
  ///
  /// 자리를 잡은 **뒤에** 도는 것이 핵심이다. 근사 자리에 먼저 세워 두고 나중에
  /// 옮기면 그게 곧 순간이동이다.
  Future<void> _animatePinIn() async {
    _pinIntroTimer?.cancel();
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    final started = DateTime.now();
    await setSelectedPinScale(controller, OutdoorMapBodyState._pinIntroFrom);
    _pinIntroTimer = Timer.periodic(OutdoorMapBodyState._selectionScaleStep, (
      timer,
    ) async {
      final t = (DateTime.now().difference(started).inMilliseconds / 220)
          .clamp(0.0, 1.0);
      final eased = 1 - math.pow(1 - t, 3).toDouble();
      const from = OutdoorMapBodyState._pinIntroFrom;
      final scale = from + (1.0 - from) * eased;
      final live = _mapController;
      if (live == null) {
        timer.cancel();
        return;
      }
      await setSelectedPinScale(live, scale);
      if (t >= 1.0) timer.cancel();
    });
  }

  Future<void> _syncIndoorOverlayFade({
    IndoorOverlaySyncScope scope = IndoorOverlaySyncScope.all,
  }) async {
    final controller = _mapController;
    if (controller == null || !_styleReady || !_indoorTilesRegistered) return;
    await syncIndoorOverlayProps(
      controller,
      ids: _indoorIds,
      fadeExpr: _overlayFadeExpr(),
      categorySelection: widget.categorySelection,
      devicePixelRatio: _devicePixelRatio,
      symbolSortKey: _storeLabelSortKeyExpression(),
      // 고른 매장의 이름·아이콘을 함께 키운다(핀만 키우면 어중간해진다).
      highlightedStoreId: _highlightedStoreId,
      selectionScale: _selectionScale,
      scope: scope,
    );
  }

  /// 탭한 위경도가 건물 footprint 내부인지. 근접 판정과 **같은 계산**
  /// ([isPointInPolygon])을 써야 "탭은 안인데 근접은 아니다"가 안 생긴다.
  ///
  /// 실내 진입 중이면 그 층 외곽선 안쪽도 "건물 안"으로 본다(지하는 건물 외곽선
  /// 밖까지 뻗는다). 두 링의 **합집합**이라 야외 판정은 그대로다.
  bool _isInsideBuilding(ll.LatLng point) {
    final footprint = _buildingFootprint;
    if (footprint != null && isPointInPolygon(point, footprint)) return true;
    final ring = _activeFloorOutlineRing();
    return ring != null && isPointInPolygon(point, ring);
  }

  /// 실내 진입 오버레이를 켜는 테스트 진입점.
  ///
  /// 실기기에서는 GPS·줌·건물 탭이 [_setIndoorEntered]를 부르는데, 그 셋 다
  /// 건물 폴리곤과 입구 좌표가 있어야 한다. 그래프만 있는 fixture로 실내 동작을
  /// 검증하려는 테스트는 그 준비를 할 수 없으므로, 실기기가 지나는 것과 **같은
  /// 함수**를 직접 부른다.
  @visibleForTesting
  void enterIndoorForTest() => _setIndoorEntered(true);

  /// 지금 보고 있는 **층 도면**이 화면을 채우도록 카메라를 맞춘다. 기준은 건물이
  /// 아니라 **그 층의 외곽선**이다(지상 180×190 m ↔ B3 286×305 m).
  ///
  /// 건물 외곽선은 시드 구조상 1F의 것이라 지하에서 안 맞는다. 그래서 도면 로드를
  /// 기다리되, 없으면 일단 맞추고 **다시 맞추기를 예약한다**([_pendingFloorFit]) —
  /// 폴백을 없앴더니 실기기에서 진입 줌인이 통째로 사라졌다.
  ///
  /// 배율은 **진입 임계값 아래로 내려가지 않는다** — 내려가면 도착한 뒤
  /// [_handleCameraIdle]이 이탈로 판정해 방금 연 도면이 도로 닫힌다.
  Future<void> _fitCameraToActiveFloor({
    Duration duration = indoorZoomInDuration,
  }) async {
    // 층을 막 바꾼 직후면 도면이 아직 오는 중이다. 여기서 기다려야 대부분의
    // 경우 예약까지 가지 않고 바로 맞는다.
    await _floorGraphLoad;
    if (!mounted) return;
    await _fitCameraToLoadedFloor(duration);
  }

  /// [_fitCameraToActiveFloor]의 몸통 — **도면 로드를 기다리지 않는다.**
  ///
  /// 예약분을 실행하는 쪽([_fetchFloorGraph])은 이미 그 로드 **안에** 있어서,
  /// 거기서 `_floorGraphLoad`를 기다리면 자기 자신을 기다리다 멈춘다. 그래서
  /// 기다리는 껍데기와 실제로 맞추는 몸통을 나눠 둔다.
  Future<void> _fitCameraToLoadedFloor(Duration duration) async {
    final ring = _activeFloorOutlineRing();
    // 층 도면이 없으면 건물 외곽선으로 **일단 맞춘다.** 그 값은 1F 외곽선이라
    // 지하에서는 크기가 안 맞지만, 안 맞추면 진입 줌인 연출이 통째로 사라진다 —
    // 실기기에서 확인했다. 대신 도면이 도착하면 그 층 크기로 다시 맞추도록
    // 예약해 둔다([_pendingFloorFit]).
    final footprint = ring ?? _buildingFootprint;
    if (footprint == null || footprint.length < 3) return;
    final floor = _activeFloor;
    if (ring == null) {
      if (floor != null) _pendingFloorFit = (floor: floor, duration: duration);
      debugPrint(
        '[outdoor overlay] fit 폴백(건물 외곽선): $floor 도면 없음 '
        '(entered=$_indoorEntered)',
      );
    } else {
      _pendingFloorFit = null;
    }
    // 화면에 그려지는 것은 외곽선만이 아니다 — 매장·POI까지 덮어야 "층 전체가
    // 보인다"가 된다([_activeFloorDrawnPoints]). 폴백 중이면 그 층 도면이 없으니
    // 덮을 점도 없다.
    final box = minAreaBoxFor(
      footprint,
      covering: ring == null ? const [] : _activeFloorDrawnPoints(),
    );
    if (box != null) {
      await _animateCameraToFitBox(
        box,
        topChromePx: floorFitTopChromePx,
        bottomChromePx: floorFitBottomChromePx,
        duration: duration,
      );
      return;
    }
    // 상자를 못 구하면(퇴화한 외곽선) 돌리지 않고 임계값까지만 간다.
    final center = _buildingCenter(footprint);
    final controller = _mapController;
    if (center == null || controller == null || !_styleReady) return;
    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(_toGl(center), _entryZoomThreshold()),
      duration: duration,
    );
  }

  List<ll.LatLng> _activeFloorDrawnPoints() {
    final plan = _floorPlan;
    if (plan == null) return const [];
    return <ll.LatLng>[
      ...plan.footprint,
      for (final store in plan.stores) ...[store.centroid, ...store.polygon],
      for (final poi in plan.pois) poi.point,
    ];
  }

  /// 건물 폴리곤을 잠깐 진하게 칠했다 되돌린다 — 탭과 검색 선택이 **같은 신호**를
  /// 써야 한다. 장식이라 컨트롤러가 없으면 건너뛴다(진입이나 카메라 이동을 여기
  /// 걸면 안 된다).
  Future<void> _flashBuildingFill() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    // fillColor를 매번 함께 넘긴다 — 빼면 검정으로 되돌아간다
    // (indoor_overlay_layers.dart 상단 주석 참고).
    await controller.setLayerProperties(
      kOutdoorBuildingFillLayerId,
      buildingFillProps(buildingFillOpacityPressed),
    );
    await Future<void>.delayed(
      const Duration(milliseconds: buildingPressedHoldMs),
    );
    if (!mounted) return;
    await controller.setLayerProperties(
      kOutdoorBuildingFillLayerId,
      buildingFillProps(buildingFillOpacityDefault),
    );
  }

  /// 실내 진입 트리거 — 건물 탭·줌 초과·GPS 근접 중 하나로 호출. 화면 모드는
  /// 바꾸지 않고 오버레이만 켠다.
  ///
  /// [ignoreZoomArming]은 **자기 게이트를 따로 가진 호출자**가 쓴다.
  /// [_autoIndoorEntryArmed]는 zoom 트리거 전용 플래그라, 이걸로 다른 경로까지
  /// 막으면 건물 직접 탭과 GPS 재무장이 조용히 죽는다.
  void _triggerIndoorEntry({bool ignoreZoomArming = false}) {
    if (!ignoreZoomArming && !_autoIndoorEntryArmed) return;
    _autoIndoorEntryArmed = false;
    if (_indoorEntered) return;
    _setIndoorEntered(true);
  }

  /// 실내 모드에서 건물 바깥을 탭했을 때의 이탈.
  ///
  /// **재무장하지 않는다** — 그 시점의 줌은 보통 임계값 위라, 재무장하면 다음 카메라
  /// 정지에서 곧바로 되끌려 들어가 "나갈 수 없는" 상태가 된다. **GPS 자동 진입도
  /// 함께 끈다** — GPS는 여전히 "건물 안"이라 다음 좌표 한 건이 다시 끌고 들어간다.
  void _exitIndoorByOutsideTap() {
    // 앵커 배치 대기 중이었다면 함께 종료해 하단 바 버튼 톤도 되돌린다.
    // (배치 대기 중인 탭은 위에서 이미 소비되므로 방어적 처리다.)
    if (_placingPdrAnchor) _setPlacingAnchor(false);
    _gpsEntryArmed = false;
    _setIndoorEntered(false);
  }

  /// 실내 위치가 지금 잡혀 있는지. 자동 이탈을 허용할지 가르는 기준이다
  /// ([_applyBuildingVerdict]).
  ///
  /// 앵커만으로 판단한다 — 궤적은 세션이 끝난 뒤에도 남아 "지금 안에 있다"의
  /// 근거가 못 된다.
  bool get _indoorPositionPlaced => _pdrTrailState.anchor != null;

  /// [_indoorEntered] 상태 변경을 한 곳으로 모은 헬퍼. setState·상위 통지에 더해
  /// dim scrim·마커·페이드까지 여기서 함께 갱신한다.
  ///
  /// [leftBuilding]은 **실제로 건물을 나갔다**는 뜻이다(GPS 판정). 도면만 접은 것
  /// ([returnToOutdoorView])과 구분해야 실내 위치를 버릴지, 야외 구간을 올릴지가
  /// 갈린다 — 접은 사용자는 다시 펼 수 있으니 앵커를 남기고 예약도 소비하지 않는다.
  void _setIndoorEntered(bool value, {bool leftBuilding = false}) {
    if (_indoorEntered == value) return;
    // 걸어 나감 무장은 **이 세션의 층 좌표**로 쌓은 근거다. 오갈 때마다 버려야
    // 다음 진입이 지난번 문 앞에 서 있던 상태로 시작하지 않는다.
    _walkoutDetector.reset();
    // 상태를 내리기 **전에** 버린다. 아래 [_syncPdrCurrentLayer]가 이 값을 보고
    // 그릴지 말지를 정하므로, 뒤에 버리면 그 한 프레임 동안 옛 위치가 남는다.
    if (!value && leftBuilding) _dropIndoorPosition();
    // 자동으로 들어왔다는 표식은 야외로 나가는 순간 내린다. 남겨 두면 다음에
    // 사용자가 건물을 직접 탭해 연 도면까지 GPS가 제멋대로 닫는다
    // ([_applyBuildingVerdict]의 outside 갈래).
    if (!value) _indoorEnteredByGps = false;
    // 실내 안내를 켜고 끄는 유일한 지점이다.
    //
    // 예전에는 오버레이가 꺼져도 복도 보정이 계속 돌았다 — 화면에 안 보일 뿐
    // 야외를 걸어 다닌 거리가 실내 좌표계에 누적되다가, 다시 들어오는 순간
    // 걸어 본 적 없는 자리에서 시작했다.
    if (value) {
      _ensureGuidanceAttached();
    } else {
      _guidance.detach();
      // GPS를 층 그래프에 투영한 추정치도 함께 버린다. 이 값은 30초 동안
      // "신선"하고([IndoorLocationEstimate.isFresh]) 앵커가 없을 때의 마지막
      // 폴백이라, 남겨 두면 야외로 나간 뒤에도 30초간 실내 좌표가 살아 있다.
      // **호출처가 여기 하나뿐이다** — 만들기만 하고 버리는 자리가 없었다.
      indoorLocationEstimateController.clear();
      // 야외로 나가면 진행 중이던 층 전환도 끝난다. 남겨 두면 배너가 야외
      // 화면에 떠 있고 걸음이 멈춘 채로 유지된다.
      _enqueueFloorTransition(_endEscalatorRide);
    }
    setState(() => _indoorEntered = value);
    widget.onIndoorEnteredChanged?.call(value);
    // 진입/이탈로 "지금 보고 있는 층"의 유무 자체가 바뀐다.
    _notifyActiveFloor();
    // 구독 자체는 실내에서도 유지된다(이탈 판정의 유일한 입력이다) — 여기서
    // 하는 일은 이 화면이 안 보이게 됐을 때 끊는 것뿐이다.
    _syncGpsSubscription();
    // GPS 마커는 **이 자리에서 직접** 지운다.
    //
    // [_syncCurrentLayer]가 [_outdoorGpsVisible]을 보고 알아서 비우기는 하지만,
    // 그 함수는 다음 위치 이벤트가 와야 불린다. 진입 순간에 안 지우면 마지막
    // 야외 좌표가 실내 도면 위에 그대로 남아, 사용자는 실내 위치 아이콘과 건물
    // 밖 파란 점을 **동시에** 보게 된다. 위치 아이콘의 주인이 바뀌는 시점은
    // 다음 좌표가 아니라 지금이다.
    unawaited(_syncCurrentLayer());
    // 위치 아이콘의 주인이 바뀌는 순간이다. 야외로 나가면 실내 위치 마커를
    // 지우고(GPS 마커가 그 역할을 받는다), 실내로 들어가면 다시 그린다.
    unawaited(_syncPdrCurrentLayer());
    _syncDimScrimLayer();
    // 외곽선은 실내 진입 상태에서만 그린다 — 이탈하면 여기서 소스가 비워진다.
    unawaited(_syncFloorOutlineLayer());
    // 진입/이탈로 페이드 구간 자체가 바뀌므로 이미 붙어 있는 오버레이 레이어의
    // opacity 표현식도 함께 갈아 끼운다.
    unawaited(_syncIndoorOverlayFade());
    // 실내로 들어온 시점이 PDR을 켤 지점이다. 미리 돌려 두면 사용자가 위치를
    // 지정하는 순간 heading이 이미 수렴해 있다. **야외로 나갈 때는 끄지 않는다** —
    // 오갈 때마다 껐다 켜지면 앵커와 걸음 누적이 매번 초기화된다.
    if (value) unawaited(_startPdrIfIdle());
    // 실내로 들어오면 화면의 주인은 실내 마커다. 위치를 이미 알고 있으면 그
    // 자리로 옮기고 바라보는 방향으로 돌린다. 아직 모르면 아무것도 하지 않고,
    // 앵커가 잡히는 자리에서 같은 연출을 한다([_startTrackingFromGpsFix]).
    if (value) unawaited(_centerOnIndoorMarker());
    // 문 경유 안내의 구간 승격은 여기 한 곳에만 둔다 — 진입도 이탈도 어느 경로로
    // 판정되든 이 함수를 지난다. 나가는 쪽만 [leftBuilding]으로 한 번 더 좁힌다.
    if (value) {
      unawaited(_activatePendingIndoorRoute());
    } else if (leftBuilding) {
      unawaited(_activatePendingOutdoorRoute());
    }
  }

  /// [fadeFactor]는 등록되는 레이어에 곱할 층 전환 크로스페이드 계수다. 기본
  /// 1(원래 불투명도). 크로스페이드가 이전 층 위에 새 블록을 투명하게 얹을
  /// 때만 0을 넘긴다 — 이후 [_finalizeIndoorFloorCrossfade]가 1까지 올린다.
  Future<void> _ensureIndoorTilesRegistered({double fadeFactor = 1}) async {
    final controller = _mapController;
    final building = _building;
    if (controller == null || !_styleReady || building == null) {
      debugPrint(
        '[outdoor overlay] skip register: controller=${controller != null} '
        'styleReady=$_styleReady building=${building != null}',
      );
      return;
    }
    if (_indoorTilesRegistered) return;
    final floor = _activeFloor ?? building.initialFloor;
    if (floor == null) {
      debugPrint('[outdoor overlay] skip register: no active floor');
      return;
    }

    final tileUrl = indoorTileUrl(
      buildingId: building.id,
      floorName: floor,
      tileRevision: building.tileRevision,
    );
    debugPrint(
      '[outdoor overlay] registering MVT source url=$tileUrl '
      'apiBaseUrl=$apiBaseUrl',
    );
    // zoom-interpolate 표현식이라 카메라 이동 중에는 setLayerProperties 없이도
    // 실시간으로 반영된다.
    //
    // **아래 호출보다 먼저** 반영해야 한다 — [_overlayFadeExpr]이 이 값을 읽으므로,
    // 순서를 바꾸면 새 층이 처음부터 불투명하게 튀어나온다.
    _indoorOverlayFadeFactor = fadeFactor;
    // 실패 시 부분 등록분 정리까지 저쪽이 한다. 여기서는 성공 여부만 받아
    // 플래그에 반영한다.
    final registered = await registerIndoorOverlayLayers(
      controller,
      ids: _indoorIds,
      tileUrl: tileUrl,
      fadeExpr: _overlayFadeExpr(),
      categoryFilter: _categoryFilterExpression(),
      categorySelection: widget.categorySelection,
      devicePixelRatio: _devicePixelRatio,
      symbolSortKey: _storeLabelSortKeyExpression(),
      ensureIconImages: _ensureFacilityIconImagesRegistered,
    );
    _indoorTilesRegistered = registered;
    if (registered) {
      debugPrint('[outdoor overlay] MVT source+layers registered ($floor)');
    }
  }

  /// POI/편의시설 아이콘 비트맵을 스타일당 한 번만 addImage로 등록한다.
  /// [_ensureIndoorTilesRegistered]가 층 전환마다 소스/레이어를 다시 붙일 때
  /// 매번 렌더를 반복하지 않도록 [_facilityIconImagesRegistered]로 게이팅한다.
  /// 스타일이 바뀌면(개발 hot restart 등) MapLibre가 이미지를 잃을 수 있어
  /// 그때는 [_onStyleLoaded]에서 다시 false로 리셋된다.
  Future<void> _ensureFacilityIconImagesRegistered(
    MapLibreMapController controller,
  ) async {
    if (_facilityIconImagesRegistered) return;
    for (final icon in {...kPoiIconByType.values, kDefaultPoiIcon}) {
      final imageName = poiIconImageName(icon);
      await controller.addImage(
        imageName,
        // 실내 화면과 같은 비트맵 캐시를 공유한다([map_icon_cache.dart]).
        await cachedIconPng(imageName, () => renderPoiIconPng(icon)),
      );
    }
    for (final entry in kStoreFacilityStyleByName.entries) {
      final imageName = facilityIconImageName(entry.key);
      await controller.addImage(
        imageName,
        await cachedIconPng(
          imageName,
          () => renderFacilityIconPng(entry.value),
        ),
      );
    }
    // 매장명 라벨에 붙는 대분류 아이콘. 실내 화면과 같은 이름·같은 비트맵이라
    // 두 화면 사이를 오가도 같은 매장이 같은 아이콘을 단다.
    for (final category in storeCategoryIconKeys) {
      final imageName = storeCategoryIconImageName(category);
      await controller.addImage(
        imageName,
        await cachedIconPng(
          imageName,
          () => renderStoreCategoryIconPng(category),
        ),
      );
    }
    _facilityIconImagesRegistered = true;
  }

  /// 대중교통에서 내린 뒤 들어갈 문을 정하고, 그 문에서 매장까지의 실내 구간을
  /// 미리 풀어 둔다. 실제로 그리는 것은 [_syncRouteLayer]다(밖에서는 미리보기,
  /// 건물에 들어가면 [_activatePendingIndoorRoute]가 승격한다).
  ///
  /// [showTransitRoute]가 시작할 때 pending을 비우므로 **그 뒤에** 불러야 한다.
  /// 순서를 뒤집으면 여기서 쌓은 실내 구간이 곧바로 지워진다.
  Future<void> prepareIndoorLegFromDrop(
    PoiSearchResult destination, {
    required ll.LatLng dropPoint,
  }) async {
    final building = _building;
    final endNodeId = destination.nodeId;
    if (building == null || endNodeId == null || destination.floor.isEmpty) {
      return;
    }
    final entrance = nearestEntrance(_groundEntrances, dropPoint);
    if (entrance == null) return;

    final graph =
        _journeyBuildingGraph ??
        await buildingRepository.getBuildingGraph(building.id);
    if (!mounted) return;
    final leg = graph == null
        ? null
        : computeMultiFloorRoute(graph, entrance.nodeId, endNodeId);
    setState(() {
      _journeyBuildingGraph = graph;
      _journeyEntrance = entrance;
      _pendingIndoorDestination = destination;
      _pendingIndoorRoute = (leg == null || leg.isEmpty) ? null : leg;
    });
    _syncRouteLayer();
    _syncDestinationLayer();
    _syncIndoorDestinationLayer();
  }

  /// 지금 그려야 하는 실내 위치. 출처 판단은 [IndoorGuidanceSession]이 한다.
  ///
  /// 예전에는 여기서 **앵커만** 그렸다. 홈은 층 전환을 감지하지 못하니 걸음
  /// 누적 위치를 그리면 엉뚱한 층 도면 위에서 점이 걸어간다는 이유였는데,
  /// 이제 세션이 에스컬레이터 층 전환까지 판정하므로 그 전제가 사라졌다.
  GuidancePosition? get _indoorPosition => _guidance.position;

  List<ll.LatLng> _floorPathToWgs84(List<PdrLocalPoint> path) {
    final graph = _floorGraph;
    if (graph == null || path.isEmpty) return const [];
    final floorToWgs84 = fitFloorGeoTransform(graph.nodes);
    return path
        .map((point) {
          final wgs84 = floorToWgs84.apply(point.eastM, point.northM);
          return ll.LatLng(wgs84.$1, wgs84.$2);
        })
        .toList(growable: false);
  }

  /// 폴리곤이 없는 매장(점만 있는 시설)에서 라벨을 찾을 때 쓰는 사각형 한 변
  /// (기기 픽셀). 폴리곤이 있으면 그 범위를 그대로 쓰므로 이 값은 안 쓴다.
  static const double _labelProbePx = 400;

  /// 폴리곤 범위로 찾을 때 사방에 더하는 여백(기기 픽셀). 라벨 심볼은 점이
  /// 아니라 글자 상자라 폴리곤 경계에 딱 붙으면 판정에서 빠질 수 있다.
  static const double _labelProbePadPx = 60;

  /// 되읽기가 실패했을 때 쓸 **근사** 앵커. 두 핀(선택·출구)이 같은 규칙을 써야
  /// 한 화면에서 서로 다른 기준으로 어긋나지 않는다.
  ///
  /// 혼자 쓰는 폴리곤에서는 centroid가 `label_point`와 사실상 같다(더현대 1F
  /// 출구 5개에서 0.04~0.13 m). **나눠 쓰는 폴리곤만 예외로** `entrance`를
  /// 쓴다 — 거기서는 centroid가 전부 같은 값이라 매장을 가리지 못한다.
  /// 수치와 경위는 `docs/client/kakao-map-indoor-observation.md` S절.
  ll.LatLng _labelAnchorFor(StorePolygon store, Map<String, int> shareCounts) {
    final shared = (shareCounts[store.id] ?? 1) > 1;
    return shared ? (store.entrance ?? store.centroid) : store.centroid;
  }

  /// [store]의 라벨이 **화면에 실제로 그려진** 좌표. 못 찾으면 null.
  ///
  /// 타일은 라벨을 centroid가 아니라 `label_point`에 찍는다. 그 계산은 백엔드가
  /// 갖고 있고 베껴 오지 않는다 — 그려진 결과를 되읽는다.
  ///
  /// **화면 전체 rect로 물으면 0건이 돌아온다**(실기기 확인). 그래서 좁은
  /// 사각형만 묻는데, **그 범위는 폴리곤에서 잡는다** — 라벨은 정의상 폴리곤
  /// 안에 있기 때문이다. 근사 위치 주변 고정 크기로 물었더니 ARKET(917 m²)처럼
  /// 큰 매장에서 라벨이 상자 밖으로 나가 핀만 딴 곳에 섰다.
  ///
  /// 좌표는 **기기 픽셀**이다. 근거는
  /// `docs/client/kakao-map-indoor-observation.md` S절.
  Future<ll.LatLng?> _renderedLabelAnchor(
    StorePolygon store,
    ll.LatLng near,
  ) async {
    final controller = _mapController;
    if (controller == null) return null;
    try {
      final probe = await _labelProbeRect(controller, store, near);
      if (probe == null) return null;
      final rendered = await controller.queryRenderedFeaturesInRect(
        probe,
        [
          _indoorIds.sharedStoresLabel,
          _indoorIds.storesLabel,
          _indoorIds.facilityLabel,
        ],
        null,
      );
      for (final feature in rendered) {
        final map = feature as Map;
        if ((map['properties'] as Map?)?['id'] != store.id) continue;
        final coords = (map['geometry'] as Map?)?['coordinates'] as List?;
        if (coords == null || coords.length < 2) continue;
        return ll.LatLng(
          (coords[1] as num).toDouble(),
          (coords[0] as num).toDouble(),
        );
      }
    } catch (_) {}
    return null;
  }

  /// 라벨을 찾을 화면 사각형(기기 픽셀). 좌표 변환이 실패하면 null.
  ///
  /// 폴리곤이 있으면 그 **네 모서리**를 화면 좌표로 옮겨 감싸는 상자를 만든다.
  /// 점을 전부 옮기지 않는 이유는 변환 한 번이 플랫폼 채널 왕복이라서다 —
  /// 모서리 넷이면 범위는 같고 왕복은 폴리곤 점 수와 무관하게 넷이다.
  Future<Rect?> _labelProbeRect(
    MapLibreMapController controller,
    StorePolygon store,
    ll.LatLng near,
  ) async {
    final polygon = store.polygon;
    if (polygon.length < 3) {
      final screen = await controller.toScreenLocation(_toMapLatLng(near));
      return Rect.fromCenter(
        center: Offset(screen.x.toDouble(), screen.y.toDouble()),
        width: _labelProbePx,
        height: _labelProbePx,
      );
    }
    var minLat = polygon.first.latitude, maxLat = minLat;
    var minLng = polygon.first.longitude, maxLng = minLng;
    for (final point in polygon) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }
    // 지도가 회전해 있으면 위경도 모서리가 화면 모서리와 다르므로 넷을 모두
    // 옮겨 감싼다.
    var left = double.infinity, top = double.infinity;
    var right = double.negativeInfinity, bottom = double.negativeInfinity;
    for (final corner in [
      ll.LatLng(minLat, minLng),
      ll.LatLng(minLat, maxLng),
      ll.LatLng(maxLat, minLng),
      ll.LatLng(maxLat, maxLng),
    ]) {
      final screen = await controller.toScreenLocation(_toMapLatLng(corner));
      final x = screen.x.toDouble(), y = screen.y.toDouble();
      left = math.min(left, x);
      right = math.max(right, x);
      top = math.min(top, y);
      bottom = math.max(bottom, y);
    }
    return _clampToViewport(
      Rect.fromLTRB(
        left - _labelProbePadPx,
        top - _labelProbePadPx,
        right + _labelProbePadPx,
        bottom + _labelProbePadPx,
      ),
    );
  }

  /// 화면 밖으로 나간 부분을 잘라 낸다. 잘라 낸 뒤 남는 것이 없으면 null.
  ///
  /// **뷰포트를 넘는 사각형으로 물으면 0건이 돌아온다**(실기기 확인). 폴리곤이
  /// 화면 밖까지 뻗은 큰 매장에서 그 일이 났고, 라벨이 화면 안에 있는데도
  /// 못 찾아 핀이 근사 위치로 밀렸다.
  Rect? _clampToViewport(Rect rect) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return rect;
    final viewport = Offset.zero & (box.size * _devicePixelRatio);
    final clamped = rect.intersect(viewport);
    if (clamped.width <= 1 || clamped.height <= 1) return null;
    return clamped;
  }

  /// 강조 매장 자리에 핀을 세운다. null 또는 미매치면 비운다.
  ///
  /// **폴리곤이 아니라 점을 쓴다.** 폴리곤을 칠하던 시절에는 폴리곤이 없는
  /// 시설(점만 있는 화장실 등)을 고르면 아무 일도 일어나지 않았다.
  Future<void> _syncHighlightLayer() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    final storeId = _highlightedStoreId;
    final plan = _floorPlan;
    final store = (storeId == null || plan == null)
        ? null
        : plan.stores.where((s) => s.id == storeId).firstOrNull;
    if (store == null) {
      _highlightAnchorFinal = false;
      _cameraSettled = false;
      await syncPointSource(controller, kOutdoorHighlightSourceId, null);
    } else {
      final fallback = _labelAnchorFor(
        store,
        storeLabelShareCounts(plan!.stores),
      );
      final exact = await _renderedLabelAnchor(store, fallback);
      // **정확해지기 전에는 세우지 않는다.** 근사로 먼저 세웠다가 카메라가 멈춘 뒤
      // 옮기면 다 온 다음 핀이 순간이동하는 것으로 보인다. 라벨이 아직 안 그려진
      // 동안만 비우고, [_handleCameraIdle]이 다시 불러 그때 세운다.
      //
      // **카메라가 멈춘 뒤에도 못 찾으면 근사로라도 세운다.** 안 그러면 라벨을
      // 끝내 못 찾는 매장에서 핀이 영영 안 뜬다 — 자리가 조금 어긋나는 것보다
      // 아무것도 없는 편이 나쁘다.
      if (exact == null && !_highlightAnchorFinal && !_cameraSettled) {
        await syncPointSource(controller, kOutdoorHighlightSourceId, null);
      } else {
        final placing = !_highlightAnchorFinal;
        _highlightAnchorFinal = true;
        await syncPointSource(
          controller,
          kOutdoorHighlightSourceId,
          exact ?? fallback,
        );
        // 처음 세우는 순간에만 자라나게 한다. 이후 갱신에서 다시 돌면 깜빡인다.
        if (placing) unawaited(_animatePinIn());
      }
    }
    // **여기서 크기를 바꾸지 않는다.** 확대는 카메라와 같은 박자로 굴러야 하므로
    // [_animateSelectionScale]이 맡는다 — 여기서 한 번에 바꾸면 글자가 먼저
    // 커지고 그다음 화면이 움직이는, 사용자가 지적한 그 순서가 된다.
    // 선택이 풀린 경우만 즉시 되돌린다(되돌릴 카메라 이동이 없다).
    if (store == null && _selectionScale != 1.0) {
      _selectionScaleTimer?.cancel();
      _selectionScale = 1.0;
      await _applySelectionScale();
    }
  }

  /// 현재 층의 지상 출입구에 방위 핀을 세운다.
  ///
  /// 출구는 1F에만 있으므로 **다른 층에서 0개인 것이 정상**이다. 방위를 계산할
  /// 수 없는 문(외곽선을 못 받은 건물)은 건너뛴다 — 글자 없는 핀을 세우면 그게
  /// 무엇인지 알 수 없다.
  ///
  /// 비트맵은 방위마다 다르므로 여기서 굽는다. 등록 키가 곧 feature의 `icon`
  /// 속성이다([kGatePinImagePrefix]).
  Future<void> _syncGateLayer() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    final plan = _floorPlan;
    if (plan == null) {
      await syncPointsSource(controller, kOutdoorGateSourceId, const []);
      return;
    }

    final center = _buildingCenter(_buildingFootprint ?? const []);
    final storeById = {for (final store in plan.stores) store.id: store};
    final shareCounts = storeLabelShareCounts(plan.stores);
    final points = <(ll.LatLng, Map<String, dynamic>)>[];
    for (final entrance in groundEntrancesFrom(plan)) {
      final direction = entranceDirection(entrance, center);
      if (direction == null) continue;
      final imageName = '$kGatePinImagePrefix$direction';
      await controller.addImage(
        imageName,
        await cachedIconPng(imageName, () => renderGatePinIcon(direction)),
      );
      final store = storeById[entrance.id];
      // **[BuildingEntrance.point]를 그대로 쓰지 않는다.** 그리는 점은 라벨에
      // 맞춰야 하고([_labelAnchorFor]), 그 필드는 야외 도보가 끝날 *문 바깥*
      // 좌표다. 둘이 다른 것은 어긋난 게 아니라 서로 다른 일이다.
      final fallback = store == null
          ? entrance.point
          : _labelAnchorFor(store, shareCounts);
      final anchor = store == null
          ? fallback
          : await _renderedLabelAnchor(store, fallback) ?? fallback;
      points.add((anchor, {'icon': imageName}));
    }
    await syncPointsSource(controller, kOutdoorGateSourceId, points);
  }

  /// [localPoint]가 지도 위 Flutter 오버레이(층 선택기·PDR 제어와 상위가 얹은
  /// 검색창·카테고리 열·하단 바) 영역이면 true. 인자는 MapLibre가
  /// 준 지도 위젯 로컬 좌표라 전역 좌표로 바꿔 비교한다.
  bool _isTapOnMapOverlay(Offset localPoint) {
    final mapBox = context.findRenderObject() as RenderBox?;
    if (mapBox == null || !mapBox.attached) return false;
    final globalPoint = mapBox.localToGlobal(localPoint);
    if (_mapOverlayTapGuard.consumeIfBlocked(globalPoint)) return true;

    for (final key in [
      _floorSelectorKey,
      _pdrControlKey,
      _placingHintKey,
      _buildingLoadFailedKey,
      _etaCardKey,
      _arrivalCardKey,
      ...widget.outerOverlayKeys,
    ]) {
      final ctx = key.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      if ((box.localToGlobal(Offset.zero) & box.size).contains(globalPoint)) {
        return true;
      }
    }
    return false;
  }
}
