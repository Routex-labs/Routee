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
  ///
  /// **디버그 모드에서 진단 세션이 열려 있으면 센서만 살려 둔다** — 원칙은
  /// "기록은 잇고 위치는 잇지 않는다". 위 셋(앵커·궤적·경로)은 그대로 버리므로
  /// 재진입 때 위치는 지금처럼 새로 잡히고, 실외를 걸은 구간은 레코더에만 남는다.
  /// 스냅샷·보정 리스너가 화면 갱신 **앞에서** 레코더에 먼저 넣기 때문에, 센서
  /// 세션만 살아 있으면 실외 걸음이 실내 좌표계를 오염시키지 않고도 기록이 이어진다.
  void _dropIndoorPosition() {
    _pdrTrailState.beginNewSession();
    _syncCorridorTracking(null);
    // **실내 구간이 끝난 것과 안내가 끝난 것은 다르다.** 야외 구간이 예약돼
    // 있으면([_pendingOutdoorDestination]) 이 사람의 여정은 문 밖에서 이어진다.
    // 기본값대로 세션까지 끝내면 곧이어 도는 [_activatePendingOutdoorRoute]가
    // `_guidanceStarted`를 이미 false로 읽어, 이어받을 안내가 없다고 판단한다 —
    // 출구에서 `안내 시작` 버튼이 다시 뜨던 화면이 이것이다(실기기 증상).
    //
    // **세 수단이 같은 값을 본다.** [_pendingOutdoorDestination]은 도보만 세우고,
    // 대중교통·자동차는 야외 구간을 예약하지 않고 안내를 걸 때 통째로 그린다
    // ([showIndoorLegToOutdoorStart]). 그 값만 보면 그 둘로 나가는 사람은 항상
    // 세션이 끝나, 정류장·차로 가는 길에 `안내 시작`이 다시 뜬다.
    //
    // 지금 실내 구간이 **바깥 여정의 앞 구간인가**([_indoorLegIsPrelude])가 곧
    // 그 질문이고, 셋이 다 세운다. `_clearIndoorRoute`가 이 값을 내리므로 **그
    // 앞에서** 읽어야 한다.
    final continuesOutdoors =
        _indoorLegIsPrelude || _pendingOutdoorDestination != null;
    _clearIndoorRoute(endGuidance: !continuesOutdoors);
    final recorder = _pdrDebugRecorder;
    if (_debugModeController.enabled && recorder != null) {
      // 방금 [_clearIndoorRoute]가 'routeEnded'를 찍었으므로 **그 뒤에** 덮는다.
      recorder.recordBuildingExit();
      return;
    }
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
      // 복도 지름길을 **여기에도** 얹는다. 라우팅 그래프(리포지토리)에만 얹으면
      // 경로는 지름길로 가는데 복도 추적은 그 간선을 몰라 마커가 예전 ㄱ자에
      // 스냅된다 — 경로와 마커가 다른 길을 가리키는, 지금보다 나쁜 상태다.
      // 출구 문 노드를 화면 그래프에 **안** 넣은 것과 반대 판단인데, 문 노드는
      // 건물 밖 가짜 복도를 만들지만 지름길은 실제로 걷는 자리이기 때문이다.
      // 채택 근거와 대조군 숫자는 `docs/client/corridor-graph-detour.md`.
      final graph = graphJson is Map<String, dynamic>
          ? floorGraphWithCorridorShortcuts(
              FloorGraph.fromJson(graphJson),
              kCorridorShortcuts,
              buildingId: buildingId,
              floorName: floor,
            )
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
      _syncPdrCurrentLayer(snap: true);
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

  /// **도면만 펴 놓았을 뿐, 위치의 주인은 아직 GPS**인 상태.
  ///
  /// 확대나 건물 시트 탭으로 도면을 편 사람은 대개 건물 밖에 서 있다. 그 상태에서
  /// 실내 마커를 그리면 그릴 근거가 건물 밖 GPS 좌표뿐이라
  /// ([_indoorGapGpsPoint]), 흐린 점이 도면 위 엉뚱한 자리에 떠 "내가 건물 안에
  /// 있다"로 읽힌다 — 밖에서 매장을 찾아보는 화면에서는 그게 거짓말이다.
  ///
  /// **실내 위치를 실제로 잡으면 끝난다.** 앵커가 찍혔다는 것은 이 사람이 건물
  /// 안에 있다고 스스로 말했거나 문 앞 GPS가 그렇게 판정했다는 뜻이라, 어떻게
  /// 도면을 폈는지는 더 볼 이유가 없다.
  ///
  /// **GPS 판정으로 매 좌표마다 다시 묻지 않는다.** 실내 GPS는 같은 자리에서
  /// "밖"과 "모르겠다"를 오가서, 그걸 보면 마커가 흐려졌다 진해졌다 한다.
  /// 도면을 편 순간의 조작 하나로 못박는다([IndoorEntrySource.isViewingOnly]).
  bool get _indoorViewedFromOutside =>
      _indoorOpenedByViewing &&
      !indoorNavigationDriver.currentCalibration.canRenderPosition;

  /// 실내(PDR) 위치를 써도 되는 상태인지 — [_outdoorGpsVisible]의 반대쪽 짝이고
  /// **동시에 true가 되지 않는다.**
  ///
  /// 없으면 축소해 나온 야외 지도에 실내 위치 아이콘이 공중에 떠 있고, 길찾기
  /// 출발지도 그 실내 앵커로 잡힌다.
  bool get _indoorLocationVisible =>
      _indoorEntered && !_indoorViewedFromOutside;

  /// 지금 화면 위 위치 마커의 **주인이 누구인지.** 두 값은 서로의 반대쪽이라
  /// 동시에 참이 되지 않는다(`widget.active`가 꺼져 있으면 둘 다 거짓이다).
  ///
  /// MapLibre 레이어는 위젯 트리에 없어 픽셀을 볼 수 없다 — 테스트가 그 배타성을
  /// 확인할 수 있는 유일한 창이라 열어 둔다([indoorMarkerPointForTest]와 같은 이유).
  @visibleForTesting
  bool get indoorMarkerOwnsLocationForTest => _indoorLocationVisible;

  @visibleForTesting
  bool get outdoorGpsMarkerVisibleForTest => _outdoorGpsVisible;

  /// 좌표 한 건이 실내 쪽에 하는 일 **전부**. 부르는 자리가 둘이다 — 좌표
  /// 스트림([_handlePosition])과, 건물이 좌표보다 늦게 도착한 뒤의 재판정
  /// ([_onBuildingLoaded]).
  ///
  /// **여기에 진입·이탈 전환은 없다.** 그것은 안내 카드의 버튼이 한다
  /// (`docs/client/indoor-entry-rules.md` 6절). 좌표가 바꾸는 것은 버튼의 활성
  /// 여부와 진단 기록뿐이고, 유일한 예외가 2)의 실내 콜드스타트다.
  void _applyPositionToIndoorGates(
    Position position, {
    Duration? sinceLastFix,
  }) {
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
    // 3) 진입·이탈 버튼의 게이트와 디버그 진단 칩. 화면과 파일에만 남는다.
    _updateTransitionDebugChip(sinceLastFix: sinceLastFix);
    _recordGpsPositionDelta(position, judgement);
    // 게이트가 열리고 닫히는 것이 하단 카드의 버튼 색으로 보여야 한다. 안내 중이
    // 아니면 그 버튼 자체가 없으므로 rebuild를 걸지 않는다 — GPS 틱마다 지도 위
    // 오버레이를 통째로 다시 그리게 된다.
    if (_guidanceStarted) setState(() {});
  }

  /// 실내↔야외 **수동 전환**의 게이트 두 개와, 그 근거를 화면 진단 칩에 적는 일.
  ///
  /// 예전에는 이 자리에서 좌표 한 건이 화면 상태를 통째로 바꿨다(자동 진입·자동
  /// 이탈). **지금은 아무것도 바꾸지 않는다** — 버튼을 켜고 끌 뿐이고, 실제로
  /// 들어가고 나가는 것은 사용자가 누른 순간뿐이다
  /// ([enterIndoorFromGuidance]·[exitIndoorFromGuidance]).
  ///
  /// 왜 자동을 버렸는지는 `docs/client/indoor-entry-rules.md` 6절.
  /// [sinceLastFix]는 좌표 간격이다. 게이트와 무관하지만 같은 줄에 있어야 한다 —
  /// 버튼이 안 켜질 때 **"거리가 모자라다"와 "좌표가 안 온다"는 완전히 다른
  /// 문제**인데, 이 값이 없으면 화면만 보고 구분할 수 없다.
  void _updateTransitionDebugChip({Duration? sinceLastFix}) {
    if (!_debugModeController.enabled) {
      _gpsVerdictDebugText.value = null;
      return;
    }
    var line = _indoorEntered
        ? describeManualTransitionGate(
            outdoorExitGate,
            label: '나가기',
            radiusMeters: manualOutdoorExitRadiusMeters,
          )
        : describeManualTransitionGate(
            indoorEntryGate,
            label: '진입',
            radiusMeters: manualIndoorEntryRadiusMeters,
          );
    if (sinceLastFix != null) {
      final seconds = (sinceLastFix.inMilliseconds / 1000).toStringAsFixed(1);
      line = '$line · +${seconds}s';
    }
    line =
        '$line · ${_gps.lastFixFromStream ? '스트림' : '직접'}'
        ' · 재시작${_gps.restartCount}';
    _gpsVerdictDebugText.value = line;
  }

  /// 지금 그려진 안내가 **건물 안으로 들어가는 여정**인지.
  ///
  /// 근거는 예약된 실내 구간이다([_pendingIndoorDestination]) — 야외 구간을 다
  /// 걸으면 문 앞이고, 그 다음이 실내라는 사실을 이 예약 하나가 담고 있다. 목적지
  /// 좌표가 건물 안인지를 다시 재지 않는다: 같은 사실을 두 곳에서 계산하면
  /// 폴백(그래프를 못 받아 실내 구간이 안 풀린 경우)에서 둘이 어긋나, 들어가 봐야
  /// 이어질 경로가 없는데 버튼만 뜬다.
  bool get _guidanceEntersBuilding =>
      _guidanceStarted && !_indoorEntered && _pendingIndoorDestination != null;

  /// 지금 그려진 안내가 **건물 밖으로 나가는 여정**인지.
  ///
  /// 실내 구간의 목적지 노드가 지상 출입구면 그렇다. 실내→야외 도보
  /// ([showIndoorToOutdoorRouteTo])와 실내→대중교통
  /// ([showIndoorLegToOutdoorStart])이 **둘 다 출구를 목적지로 삼는 실내 경로**를
  /// 그리므로, 한 조건이 두 여정을 함께 잡는다.
  ///
  /// [_pendingOutdoorDestination]으로 가르지 않는 이유가 그것이다 — 대중교통 쪽은
  /// 야외 구간을 예약하지 않고 처음부터 통째로 그린다(사진의 그 화면이다).
  bool get _guidanceLeavesBuilding =>
      _guidanceStarted && _indoorEntered && _exitEntranceOfIndoorRoute != null;

  /// 실내 구간이 목적지로 삼은 지상 출입구. 나가는 여정이 아니면 null.
  ///
  /// 문 하나에 노드가 둘이라는 것과 그 판정은 [exitEntranceForRouteNodeId]가
  /// 단일 출처다.
  BuildingEntrance? get _exitEntranceOfIndoorRoute =>
      exitEntranceForRouteNodeId(
        _groundEntrances,
        _indoorRouteDestination?.nodeId,
      );

  /// **앱을 건물 안에서 켠 사용자**를 실내로 데려간다.
  ///
  /// 좌표 한 건이 화면을 실내로 바꾸는, 이제 유일하게 남은 자리다. 자동 진입을
  /// 걷어낸 뒤에도 이것만 남긴 이유는 **이것이 전환이 아니기 때문**이다 —
  /// 야외에서 실내로 넘어가는 순간을 잡는 것이 아니라, 앱이 처음 눈을 떴을 때
  /// 사용자가 어디에 서 있는지를 읽는 것이다. 전환할 야외 화면 자체가 없으므로
  /// 문 연출도 붙이지 않는다.
  ///
  /// 벽 안팎을 가르는 것보다 훨씬 쉬운 판정이기도 하다. 이 건물은 폭이 180 m라,
  /// 오차 15 m로도 "건물 한가운데"는 넉넉히 구분된다.
  ///
  /// **막는 조건 넷.** 하나라도 걸리면 아무것도 하지 않는다.
  ///   - 이미 한 번 처리했다([_coldStartIndoorHandled]) — 건물 밖을 탭해 나온
  ///     사용자를 다음 좌표가 되끌고 들어가지 않게 한다.
  ///   - 밖을 한 번이라도 봤다 — 걸어 들어온 사람이다. 그쪽은 안내 카드의
  ///     진입 버튼으로 들어간다.
  ///   - 이미 실내다 — 건물을 탭해 도면을 편 사용자다.
  ///   - 좌표가 건물 안이라고 말하지 않는다.
  void _maybeEnterIndoorOnColdStart(
    GpsBuildingJudgement judgement,
    Position position,
  ) {
    if (_coldStartIndoorHandled || _sawOutsideSinceLaunch || _indoorEntered) {
      return;
    }
    if (judgement.verdict != GpsBuildingVerdict.inside) return;
    _coldStartIndoorHandled = true;
    _setIndoorEntered(true, source: IndoorEntrySource.gpsColdStart);
    unawaited(_askEntryFloorThenTrack(position));
  }

  /// 지금 GPS 좌표. 없으면 null이라 진입 게이트가 닫힌다.
  ll.LatLng? get _gpsPoint {
    final position = _position;
    if (position == null) return null;
    return ll.LatLng(position.latitude, position.longitude);
  }

  /// "OO(으)로 진입" 버튼을 켤 수 있는지. 근거는 GPS 좌표와 건물 외곽선이다.
  ManualTransitionGate get indoorEntryGate =>
      manualIndoorEntryGate(fix: _gpsPoint, footprint: _buildingFootprint);

  /// "밖으로 나가기" 버튼을 켤 수 있는지. 근거는 PDR 위치와 출입구 노드다.
  ///
  /// **복도 보정을 거친 위치**를 쓴다. 화면의 실내 마커가 그 값이라, 사용자가
  /// 자기 점을 문 앞에서 보고 있는데 버튼은 회색인 상태가 생기지 않는다.
  ManualTransitionGate get outdoorExitGate => manualOutdoorExitGate(
    positionM: _guidance.trackingResult?.previewPosition,
    entranceNodesM: _groundEntranceNodesM,
  );

  /// 지금 덮개의 불투명도를 셸에 흘려보낸다
  /// ([OutdoorMapBody.onIndoorTransitionVeilChanged]).
  ///
  /// **진행률이 아니라 불투명도다.** 덮개는 구간 앞뒤로 투명해서
  /// ([indoorTransitionFrameAt]), 진행률만 넘기면 아직 아무것도 안 가린
  /// 프레임에서도 셸이 chrome을 걷는다 — 검색창이 이유 없이 한 번 깜빡인다.
  ///
  /// 같은 값은 두 번 보내지 않는다. 셸의 setState를 부르는 콜백이라, 값이
  /// 같은데 부르면 애니메이션 프레임마다 셸 전체가 다시 그려진다.
  void _publishIndoorTransitionVeil() {
    final veil = indoorTransitionFrameAt(
      _indoorTransition.value,
    ).veilOpacity.clamp(0.0, 1.0);
    if (veil == _lastPublishedIndoorVeil) return;
    _lastPublishedIndoorVeil = veil;
    widget.onIndoorTransitionVeilChanged?.call(veil);
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

  /// 지금 층의 지상 출입구 노드들을 **층 좌표(m)**로 모은다.
  ///
  /// 문 목록은 출입구 층 것이라([_groundEntranceFloor]) 다른 층을 보고 있으면 빈
  /// 목록이다 — 같은 local m 숫자가 층마다 다른 자리를 가리키므로, 그대로 쓰면
  /// 지하 3층에 선 사람에게 "밖으로 나가기"가 켜진다.
  ///
  /// 좌표를 그래프 노드에서 직접 읽는다. 문의 위경도를 되돌려 쓸 수도 있지만,
  /// 그러면 같은 지점이 아핀 왕복을 한 번 더 거쳐 몇십 cm씩 어긋난다 — 앵커를
  /// 찍는 [_startIndoorTracking]이 쓰는 값과 같아야 "문에 앵커를 찍었는데
  /// 나가기 버튼이 안 켜진다"가 생기지 않는다.
  List<PdrLocalPoint> get _groundEntranceNodesM {
    final graph = _floorGraph;
    final floor = _activeFloor;
    if (graph == null ||
        floor == null ||
        floor != _groundEntranceFloor ||
        _groundEntrances.isEmpty) {
      return const [];
    }
    final doorNodeIds = {for (final e in _groundEntrances) e.nodeId};
    return [
      for (final node in graph.nodes)
        if (doorNodeIds.contains(node.id)) PdrLocalPoint(node.xM, node.yM),
    ];
  }

  /// 안내 카드의 **"OO(으)로 진입"**. 사용자가 눌렀을 때만 불린다.
  ///
  /// 앵커는 **GPS 좌표에서 가장 가까운 지상 출입구 노드**에 찍는다. 버튼이 켜졌다는
  /// 것은 사용자가 건물 코앞에 있다는 뜻이고, 코앞에 있는 사람이 실제로 밟는 지점은
  /// 문이다 — 실내 GPS 좌표를 통로에 붙이는 것보다 훨씬 확실한 근거다.
  ///
  /// **깨지는 자리 둘.** 위치를 아직 못 잡았거나(GPS null) 출입구 데이터가 없으면
  /// 아무것도 하지 않고 이유만 말한다. 버튼 게이트가 앞의 것을 이미 막지만, 좌표는
  /// 누르는 사이에도 사라질 수 있다.
  /// 지금 통과한다고 볼 문. 앵커를 찍는 자리와 안내가 향하던 자리를 **하나로**
  /// 묶는다.
  ///
  /// **안내가 향하던 문이 있으면 그것이다**([_journeyEntrance]). 앵커만 GPS
  /// 최근접으로 따로 고르면, 실내 경로는 A문에서 시작하는데 마커는 B문에 찍혀
  /// 들어서자마자 둘이 어긋난다 — 문 선택에는 15 m 히스테리시스가 있어
  /// ([kEntranceSwitchMarginMeters]) 두 값이 실제로 갈리는 구간이 생긴다.
  ///
  /// 향하던 문이 없으면(문 재선정 전이거나 여정 그래프를 못 받은 경우) GPS
  /// 최근접으로 물러선다.
  BuildingEntrance? _entranceBeingEntered(Position position) =>
      _journeyEntrance ??
      nearestEntrance(
        _groundEntrances,
        ll.LatLng(position.latitude, position.longitude),
      );

  Future<void> enterIndoorFromGuidance() async {
    if (_indoorEntered) return;
    final position = _position;
    if (position == null) {
      _showSnack('현재 위치를 아직 못 잡았습니다. 신호가 잡히면 다시 눌러주세요.');
      return;
    }
    final entrance = _entranceBeingEntered(position);
    final floor = _groundEntranceFloor;
    if (entrance == null || floor == null) {
      _showSnack('건물 출입구 정보가 없어 실내로 들어갈 수 없습니다.');
      return;
    }
    // 층을 먼저 맞춘다. 실내 구간의 시작 층은 문이 있는 층이고, [_setIndoorEntered]
    // 안에서 승격되는 [_activatePendingIndoorRoute]가 그 층 도면 위에 경로를 얹는다.
    if (_activeFloor != floor) {
      await _switchOverlayFloor(floor);
      if (!mounted) return;
    }
    await _runIndoorTransition(IndoorTransitionDirection.enter, () {
      _setIndoorEntered(true, source: IndoorEntrySource.guidance);
      unawaited(_startIndoorTracking(entrance: entrance, position: position));
    });
  }

  /// 안내 카드의 **"밖으로 나가기"**. 사용자가 눌렀을 때만 불린다.
  ///
  /// 실내 위치를 버리고 위치의 주인을 GPS로 되돌린다([_setIndoorEntered]의
  /// `leftBuilding`). 카메라 이동을 덮개 **안에** 넣는 이유는 자동 이탈 때와 같다 —
  /// 화면은 아직 도면에 맞춰 확대돼 있어서, 방금 켠 GPS 마커가 화면 밖일 수 있다.
  ///
  /// GPS 좌표가 없으면 방금 지난 문 좌표로 옮긴다. 건물을 나선 사람이 서 있는
  /// 자리에 가장 가까운 값이고, 아무 데도 안 옮기는 것보다 낫다.
  ///
  /// **나온 문을 들고 나간다**([_exitDoorPoint]). 야외 구간은 그 문에서 다시
  /// 그려져야 한다 — 안내를 걸 때 그려 둔 것은 *경로가 향하던* 문 기준이고,
  /// 사용자는 다른 문으로 나갈 수 있다.
  void exitIndoorFromGuidance() {
    if (!_indoorEntered) return;
    if (_placingPdrAnchor) _setPlacingAnchor(false);
    // **문을 먼저 고른다.** [_setIndoorEntered]가 실내 위치를 버리므로
    // ([_dropIndoorPosition]) 그 뒤에는 마커에서 가장 가까운 문을 물을 수 없다.
    final door = _nearestEntranceToIndoorMarker() ?? _exitEntranceOfIndoorRoute;
    final position = _position;
    final target = position != null
        ? ll.LatLng(position.latitude, position.longitude)
        : door?.point;
    unawaited(
      _runIndoorTransition(IndoorTransitionDirection.exit, () {
        _exitDoorPoint = door?.point;
        _setIndoorEntered(
          false,
          leftBuilding: true,
          source: IndoorEntrySource.guidance,
        );
        if (target != null) unawaited(_moveCameraToPoint(target));
      }),
    );
  }

  /// 실내 마커에서 가장 가까운 지상 출입구. 마커가 없으면 null.
  ///
  /// 나가기 게이트가 이미 "어느 문에서 15 m 안"을 확인했으므로, 여기서 고르는 문은
  /// 사용자가 방금 지난 그 문이다.
  BuildingEntrance? _nearestEntranceToIndoorMarker() {
    final here = _pdrCurrentWgs84();
    if (here == null) return null;
    return nearestEntrance(_groundEntrances, here);
  }

  /// 자북을 못 얻은 기기에서 쓸 "진행 방향"을 층 좌표 벡터와 그 근거로 만든다.
  /// GPS 좌표와 화면이 그리는 "내 위치"의 거리를 레코더에 남긴다.
  ///
  /// 위치의 우선순위는 [IndoorGuidanceSession.position]이 정한 것을 그대로
  /// 쓴다([_indoorPosition]) — 여기서 다시 고르면 화면과 다른 값을 재게 된다.
  /// 둘 중 하나가 없으면 거리는 null이고, 있는 쪽 정보는 그대로 남는다.
  void _recordGpsPositionDelta(
    Position position,
    GpsBuildingJudgement judgement,
  ) {
    final recorder = _pdrDebugRecorder;
    if (recorder == null) return;
    final indoor = _indoorPosition;
    final here = indoor == null
        ? null
        : _floorPathToWgs84([indoor.localM]).firstOrNull;
    recorder.recordGpsPositionDelta(
      distanceM: here == null
          ? null
          : wgs84DistanceMeters(
              ll.LatLng(position.latitude, position.longitude),
              here,
            ),
      gpsAccuracyM: position.accuracy,
      metersOutsideM: judgement.metersOutside,
      positionSource: indoor?.source.name,
      verdict: judgement.verdict.name,
      floorId: _activeFloor,
      indoorEntered: _indoorEntered,
      at: position.timestamp,
    );
  }

  /// 층 좌표계는 데이터셋마다 축이 뒤집혀 있을 수 있어, 나침반 각도는 반드시
  /// [axes]를 거쳐 층 벡터로 바꾼다. 복도 축은 이미 층 좌표라 그대로 쓴다.
  ///
  /// [position]은 없을 수 있다 — 지도를 직접 찍는 경로는 GPS를 안 지난다.
  /// 지하에서 앱을 켠 사용자에게는 course도 없으므로, 실질적으로는 복도 축
  /// 하나로 간다. 둘 다 없으면 null이고, 그때는 앵커를 찍지 않는다.
  ({PdrLocalPoint direction, AnchorRotationBasis basis})? _entryFloorDirection({
    required Position? position,
    required PdrLocalPoint anchorFloorPoint,
    required FloorGraph graph,
    required PdrToFloorAxes axes,
  }) {
    // 1순위: GPS course. 실제로 측정된 이동 방향이라 가장 정확하다. 다만 멈춰
    // 있을 때는 값이 의미 없고 플랫폼이 0으로 채우므로 속도로 먼저 거른다.
    final course = position?.heading;
    if (position != null &&
        course != null &&
        position.speed >= entryCourseMinSpeedMps &&
        course > 0 &&
        course < 360) {
      return (
        direction: axes.apply(pdrDirectionForBearing(course)),
        basis: AnchorRotationBasis.gpsCourse,
      );
    }
    // 2순위: 찍은 자리에 놓인 **복도의 축**. 사람은 복도를 따라 걷지, 층 중심을
    // 향해 걷지 않는다 — 중심 방향을 각도로 쓰던 예전 폴백이 실기기에서 궤적을
    // 51° 비스듬히 돌려 놓았다(`docs/client/android-heading-drift.md` 7절).
    // 중심은 앞뒤를 고르는 힌트로만 남긴다.
    final axis = corridorAxisAtAnchor(
      graph: graph,
      anchorFloorPoint: anchorFloorPoint,
      inwardHint: inwardHintFromGraphCentroid(graph, anchorFloorPoint),
    );
    if (axis == null) return null;
    return (direction: axis, basis: AnchorRotationBasis.corridorAxis);
  }

  /// 좌표열 전체가 **가려지지 않는 띠**에 들어오도록 카메라를 맞춘다.
  ///
  /// 아래를 덮는 하단 카드는 여기서 직접 잰다 — 자동차 후보 3줄이면 카드가
  /// 392px까지 자라 상수로는 못 따라간다. [bottomSheetFraction]은 이 fit **뒤에**
  /// 열려 아직 트리에 없는 시트 몫이라 부르는 쪽이 알려 준다(0이면 시트 없음).
  void _fitCameraToPoints(
    List<ll.LatLng> points, {
    double bottomSheetFraction = 0,
  }) {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    // 이 맞추기에는 줌 하한이 없어서 배율이 실내 이탈 임계값 아래로 내려간다.
    // **그 축소로 도면을 접지 않는다** — 근거와 안 지켰을 때 무엇이 깨지는지는
    // [zoomOutKeepsIndoor]에 있다. 여기 한 곳에서 세우는 이유는 경로 전체를
    // 담는 자리가 전부 이 함수를 지나기 때문이다(새 자리가 빠뜨릴 수 없다).
    if (_indoorEntered) _routeOverviewHoldsIndoor = true;
    // 카드는 방금 setState로 바뀌었다. 한 프레임 뒤라야 **새** 카드를 잰다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _mapController != controller || !_styleReady) return;
      // **그 사이 안내가 시작됐으면 접는다.** 경로 전체 담기는 *계획* 화면의
      // 카메라다. 예약과 실행 사이에 `안내 시작`이 눌리면(대중교통 흐름은
      // 시트에서 경로를 그린 직후 곧바로 시작을 태운다) 이미 내 자리로
      // 확대해 들어가는 중인 화면을 도로 도시 축척까지 밀어냈다 — 실기기에서
      // "확대됐다가 다시 전체 경로가 떴다가 또 확대되는" 그 자리다.
      // 프레임이 밀리면 이 콜백은 반 초씩도 늦으므로, 위 셋과 같은 이유로
      // 여기서 다시 확인해야 한다.
      if (_guidanceStarted) return;
      final viewport = MediaQuery.sizeOf(context);
      final topChrome = _topChromeBottomPx();
      unawaited(
        animateCameraToPoints(
          controller,
          points,
          viewport: viewport,
          // **잰 값을 우선한다.** 상수는 길찾기 플래너 한 줄일 때의 실측이라,
          // 출발/도착 두 줄에 이동 수단 칩까지 붙은 화면에서는 모자란다 —
          // 그만큼 경로 위쪽(대개 목적지)이 카드 뒤로 들어가 안 보인다.
          // 못 재는 프레임에서만 상수로 떨어진다(상태 표시줄은 기기마다 다르다).
          // 끝점 핀은 좌표 위로 솟아 있어 그 높이를 따로 얹는다.
          topInsetPx:
              (topChrome > 0
                  ? topChrome + routeFitChromeGapPx
                  : MediaQuery.paddingOf(context).top + routeFitTopInsetPx) +
              routeFitPinAllowancePx,
          // 카드는 탭 줄 **위에** 앉는다([_bottomDockedCard]) — 아래가 가려지는
          // 높이는 카드 높이 + 그 리프트다. 리프트를 빼먹었더니 경로가 카드 쪽으로
          // 밀려 화면 가운데에 오지 않았다(실기기 확인). 위쪽과 같은 틈
          // ([routeFitChromeGapPx])을 여기도 더한다 — 안 더하면 위아래 여백이
          // 어긋나 카드가 짧을 때(하한이 대신 메워 줄 때)만 우연히 안 보이다가,
          // 대중교통 요약 카드처럼 하한을 넘어서는 순간 경로 아래쪽이 살짝 잘렸다.
          bottomInsetPx: math.max(
            _bottomCardHeightPx() +
                widget.bottomCardLiftPx +
                routeFitChromeGapPx +
                routeFitPinAllowancePx,
            viewport.height * bottomSheetFraction,
          ),
        ),
      );
    });
  }

  /// 지금 화면 **위쪽**을 덮고 있는 chrome의 아래 끝(논리 px). 없으면 0.
  ///
  /// 상수로 못 박는다 — 검색창 한 줄일 때와 출발/도착 두 줄 + 이동 수단 칩까지
  /// 있을 때가 배로 다르다. 상태 표시줄은 이미 포함된 값이다(화면 위 끝 기준).
  ///
  /// 상위가 넘겨 준 오버레이 키를 그대로 쓰되 **위쪽 절반에 있는 것만** 센다.
  /// 하단 바도 같은 목록에 있어서, 안 가르면 화면 전체가 가려진 것으로 읽혀
  /// 경로가 점이 된다.
  double _topChromeBottomPx() {
    final half = MediaQuery.sizeOf(context).height / 2;
    var bottom = 0.0;
    for (final key in widget.outerOverlayKeys) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (top > half) continue;
      final edge = top + box.size.height;
      if (edge > bottom) bottom = edge;
    }
    return bottom;
  }

  /// 지금 화면 **아래쪽**을 덮고 있는 chrome의 높이(논리 px). [_topChromeBottomPx]의
  /// 아래쪽 짝이다 — "내 위치로" 재정렬이 화면 기하학적 중앙이 아니라 **가려지지
  /// 않는 띠**의 중앙에 오도록 [recenterKeepingBearing]에 넘긴다.
  ///
  /// 두 값 중 큰 쪽을 쓴다: 하단 탭 줄(`outerOverlayKeys`의 아래쪽 절반)은 안내
  /// 중이 아니어도 늘 떠 있고, 안내 카드는 뜨면 탭 줄보다 훨씬 높이 덮는다.
  double _bottomChromePx() {
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final half = viewportHeight / 2;
    var top = viewportHeight;
    for (final key in widget.outerOverlayKeys) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final boxTop = box.localToGlobal(Offset.zero).dy;
      if (boxTop <= half) continue;
      if (boxTop < top) top = boxTop;
    }
    final navChrome = viewportHeight - top;
    final cardHeight = _bottomCardHeightPx();
    final cardChrome = cardHeight > 0
        ? cardHeight + widget.bottomCardLiftPx
        : 0.0;
    return math.max(navChrome, cardChrome);
  }

  /// 지금 화면 아래를 덮고 있는 카드(ETA·대중교통 요약)의 높이(논리 px).
  /// 트리에 없으면 0 — 가릴 것이 없다는 뜻이다.
  double _bottomCardHeightPx() {
    final box = _etaCardKey.currentContext?.findRenderObject() as RenderBox?;
    return box == null || !box.hasSize ? 0 : box.size.height;
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
      // 고른 매장은 크기를 흔들지 않고 기존 아이콘의 색만 포인트 색으로 바꾼다.
      highlightedStoreId: _highlightedStoreId,
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
        // 아래에 판이 붙어 있으면 그 높이를 쓴다 — 규칙과 근거는
        // [floorFitBottomChromeFor].
        bottomChromePx: floorFitBottomChromeFor(widget.bottomOverlayLiftPx),
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
  /// 건물 정보 시트가 "실내 지도 보기"로 진입을 시킬 때. 건물을 직접 탭하던
  /// 조작과 **같은 자리로 들어간다** — 오버레이를 켜고 카메라를 도면에 맞춘다.
  ///
  /// 줌 무장([_autoIndoorEntryArmed])은 무시한다. 사용자가 명시적으로 누른
  /// 것이라, zoom 트리거용 플래그로 막으면 눌러도 아무 일이 없다.
  ///
  /// **전환 연출은 붙이지 않는다.** 시트를 눌러 도면을 여는 조작이지 건물로
  /// 걸어 들어간 것이 아니다(`docs/client/indoor-transition-choreography.md` 6절).
  void enterIndoorFromSheet() {
    _triggerIndoorEntry(ignoreZoomArming: true);
    if (_indoorEntered) unawaited(_fitCameraToActiveFloor());
  }

  void _triggerIndoorEntry({bool ignoreZoomArming = false}) {
    if (!ignoreZoomArming && !_autoIndoorEntryArmed) return;
    // **문 경유 안내가 걸려 있으면 확대만으로 들어가지 않는다.**
    //
    // 그 여정의 실내 구간은 "건물에 들어간 순간" 승격되는데
    // ([_activatePendingIndoorRoute]), 계획 화면이 목적지 매장을 보여 주려고
    // 확대해 둔 것을 그 순간으로 읽으면 아직 밖에 선 사용자의 실내 구간이 먼저
    // 소비된다 — 야외 구간은 그려져 있는데 안내는 이미 건물 안에서 시작한 화면이
    // 된다. 실제로 들어가는 문은 안내 카드의 "OO(으)로 진입"뿐이다
    // ([enterIndoorFromGuidance]).
    //
    // **무장은 내리지 않는다.** 예약이 소비되거나 안내가 끝나면 확대 진입이 다시
    // 살아나야 한다.
    if (!ignoreZoomArming && _pendingIndoorRoute != null) return;
    _autoIndoorEntryArmed = false;
    if (_indoorEntered) return;
    // 이 함수의 두 호출자가 곧 출처다 — 카메라 정지(확대)와 건물 정보 시트 탭.
    // 확대만으로 켜진 실내 상태를 사후에 가리려면 그 둘을 섞으면 안 된다.
    _setIndoorEntered(
      true,
      source: ignoreZoomArming
          ? IndoorEntrySource.sheetTap
          : IndoorEntrySource.cameraZoom,
    );
    // **여기서 앵커를 찍지 않는다.** 이 진입은 도면을 편 것이지 건물에 들어온
    // 것이 아니다([IndoorEntrySource.isViewingOnly]) — 확대와 시트 탭은 밖에 선
    // 사람도 하는 조작이라, 그 순간 위치를 찍으면 건물 밖 GPS 좌표 하나가 도면
    // 위 자리로 굳는다. 들어왔다고 말하는 것은 "OO(으)로 진입" 하나뿐이다
    // (`docs/client/indoor-entry-rules.md` 6절).
  }

  /// 실내 모드에서 건물 바깥을 탭했을 때의 이탈.
  ///
  /// **재무장하지 않는다** — 그 시점의 줌은 보통 임계값 위라, 재무장하면 다음 카메라
  /// 정지에서 곧바로 되끌려 들어가 "나갈 수 없는" 상태가 된다.
  ///
  /// [exitIndoorFromGuidance]와 달리 `leftBuilding`을 세우지 않는다. 이건 "바깥
  /// 지도를 보여줘"라는 화면 조작이지 "내가 건물을 나왔다"가 아니라서, 실내 위치를
  /// 버리면 도면을 다시 폈을 때 위치를 처음부터 다시 지정해야 한다.
  void _exitIndoorByOutsideTap() {
    // 앵커 배치 대기 중이었다면 함께 종료해 하단 바 버튼 톤도 되돌린다.
    // (배치 대기 중인 탭은 위에서 이미 소비되므로 방어적 처리다.)
    if (_placingPdrAnchor) _setPlacingAnchor(false);
    _setIndoorEntered(false, source: IndoorEntrySource.outsideTap);
    // 이 길은 카메라를 아예 안 만진다 — 배율도 그대로 두는 것이 맞다(사용자가
    // 도면을 보려고 당겨 둔 자리다). 되돌릴 것은 방위뿐이고, 그걸 안 되돌리면
    // 야외 지도가 돌아간 채로 남는다([resetCameraToNorthUp]).
    final controller = _mapController;
    if (controller != null && _styleReady) {
      unawaited(resetCameraToNorthUp(controller));
    }
  }

  /// [_indoorEntered] 상태 변경을 한 곳으로 모은 헬퍼. setState·상위 통지에 더해
  /// dim scrim·마커·페이드까지 여기서 함께 갱신한다.
  ///
  /// [leftBuilding]은 **실제로 건물을 나갔다**는 뜻이다(GPS 판정). 도면만 접은 것
  /// ([returnToOutdoorView])과 구분해야 실내 위치를 버릴지, 야외 구간을 올릴지가
  /// 갈린다 — 접은 사용자는 다시 펼 수 있으니 앵커를 남기고 예약도 소비하지 않는다.
  ///
  /// [source]는 이 변경을 부른 것이 무엇인지다([IndoorEntrySource]). 진단 파일에
  /// 남고, **위치의 주인이 누구인지도 이 값이 가른다** — [_indoorEntered]가
  /// "도면을 보고 있다"와 "건물 안에 있다"를 겸하고 있어서, 확대로 켜진 실내
  /// 상태와 실제로 걸어 들어온 실내 상태를 이 값 없이는 구분할 수 없다.
  void _setIndoorEntered(
    bool value, {
    bool leftBuilding = false,
    IndoorEntrySource source = IndoorEntrySource.other,
  }) {
    if (_indoorEntered == value) return;
    _pdrDebugRecorder?.recordIndoorStateChange(
      entered: value,
      source: source.name,
      floorId: _activeFloor,
    );
    // 도면만 편 진입인지 여기서 못박는다. 뒤에서 다시 물으면 그때의 GPS 판정에
    // 기대게 되는데, 실내 GPS는 같은 자리에서 "밖"과 "모르겠다"를 오가므로
    // 마커가 흐려졌다 진해졌다 한다([_indoorViewedFromOutside]).
    _indoorOpenedByViewing = value && source.isViewingOnly;
    // 실외 구간을 품은 채 이어 온 세션이면 재진입 시각을 남긴다 — 'leftBuilding'
    // 과 이 경계 사이가 곧 실외 구간이다([_dropIndoorPosition]).
    final recorder = _pdrDebugRecorder;
    if (value && (recorder?.spansBuildingExit ?? false)) {
      recorder!.recordSessionBoundary('reEntered');
    }
    // 실내 상태가 뒤집히는 순간 개요 붙들기는 뜻을 잃는다. 남겨 두면 다음 진입이
    // "이미 개요를 보는 중"으로 시작해, 사용자가 직접 축소해도 안 접힌다.
    _routeOverviewHoldsIndoor = false;
    // 상태를 내리기 **전에** 버린다. 아래 [_syncPdrCurrentLayer]가 이 값을 보고
    // 그릴지 말지를 정하므로, 뒤에 버리면 그 한 프레임 동안 옛 위치가 남는다.
    if (!value && leftBuilding) _dropIndoorPosition();
    // **정말로 나갔을 때만** 층·매장 질문을 다시 열어 둔다. 도면만 접은 사용자는 같은
    // 자리에 그대로 있어서, 다시 펼 때마다 묻는 것은 답을 아는 질문을 되묻는 것이다.
    if (!value && leftBuilding) {
      _entryFloorAsked = false;
      _nearbyStoreAsked = false;
    }
    // 실내 안내를 켜고 끄는 유일한 지점이다.
    //
    // 예전에는 오버레이가 꺼져도 복도 보정이 계속 돌았다 — 화면에 안 보일 뿐
    // 야외를 걸어 다닌 거리가 실내 좌표계에 누적되다가, 다시 들어오는 순간
    // 걸어 본 적 없는 자리에서 시작했다.
    if (value) {
      // **카메라 주인을 실내 쪽으로 완전히 넘긴다.** 안 끄면 야외 GPS
      // 따라가기([_followingUser])가 실내로 들어온 뒤에도 GPS 틱마다 카메라를
      // 끌어당겨, 실내 PDR 팔로우([_indoorFollowActive])와 같은 카메라를 두고
      // 서로 다른 자리로 당긴다 — "GPS 위치와 실내 위치가 번갈아 온다"로 보인
      // 자리다. 실내에서도 GPS 좌표는 계속 들고 있지만(진입/이탈 판정용),
      // 화면을 끄는 것은 이제부터 PDR뿐이어야 한다.
      _stopFollowingUser();
      _ensureGuidanceAttached();
    } else {
      _guidance.detach();
      // GPS를 층 그래프에 투영한 추정치도 함께 버린다. 이 값은 30초 동안
      // "신선"하고([IndoorLocationEstimate.isFresh]) 앵커가 없을 때의 마지막
      // 폴백이라, 남겨 두면 야외로 나간 뒤에도 30초간 실내 좌표가 살아 있다.
      // **호출처가 여기 하나뿐이다** — 만들기만 하고 버리는 자리가 없었다.
      indoorLocationEstimateController.clear();
      // 야외로 나가면 진행 중이던 층 전환도 끝난다. 남겨 두면 배너가 야외
      // 화면에 떠 있고 걸음이 멈춘 채로 유지된다. 탈것을 가리지 않는다 —
      // 나가는 쪽은 무엇을 타고 있었는지 모른다([OutdoorMapElevator._endAnyRide]).
      _enqueueFloorTransition(_endAnyRide);
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
    unawaited(_syncPdrCurrentLayer(snap: true));
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
    // 앵커가 잡히는 자리에서 같은 연출을 한다([_startIndoorTracking]).
    if (value) unawaited(_centerOnIndoorMarker());
    // 문 경유 안내의 구간 승격은 여기 한 곳에만 둔다 — 진입도 이탈도 어느 경로로
    // 판정되든 이 함수를 지난다. 나가는 쪽만 [leftBuilding]으로 한 번 더 좁힌다.
    if (value) {
      unawaited(_activatePendingIndoorRoute());
    } else if (leftBuilding) {
      unawaited(_activatePendingOutdoorRoute());
      unawaited(_resetActiveFloorToDefault());
    }
  }

  /// 건물을 나간 순간 활성 층을 건물 기본 층(`default_floor`)으로 되돌린다.
  ///
  /// 안 되돌리면 **다시 들어올 때 지난 세션의 마지막 층에서 시작한다.** B2에서
  /// 나갔다가 지상 1F 입구로 다시 들어와도 활성 층이 B3라, 기압 판정이 그 층을
  /// 기준으로 다시 시작해 B3→B4 층 전환 배너까지 띄웠다(실기기 실측).
  ///
  /// **들어온 문의 층은 못 쓴다** — [BuildingEntrance]에 층이 없고, 그 목록
  /// 자체가 기본 층 도면에서만 추려진다([_loadGroundEntrances]). 지하 주차장
  /// 입구로 들어오는 경우를 가리려면 입구 데이터에 층이 먼저 실려야 한다.
  ///
  /// 도면만 접은 경우([returnToOutdoorView])에는 안 부른다 — 같은 자리에 그대로
  /// 서 있는 사용자라 층이 유지돼야 한다.
  Future<void> _resetActiveFloorToDefault() async {
    final floor = _building?.initialFloor;
    if (floor == null || floor == _activeFloor) return;
    // 층 값만 바꾸면 도면·층 그래프·등록된 MVT 타일이 이전 층 것으로 남아,
    // 다시 들어오면 1F라고 말하면서 B3 도면을 그린다. 크로스페이드는 빼다 —
    // 야외 화면에는 가릴 이전 도면이 없고, 전환 모티프만 뜨게 된다.
    await _switchOverlayFloor(floor, recenterIfNeeded: false);
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
      final selectedImageName = selectedStoreCategoryIconImageName(category);
      await controller.addImage(
        selectedImageName,
        await cachedIconPng(
          selectedImageName,
          () => renderStoreCategoryIconPng(category, selected: true),
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
        await buildingRepository.getBuildingGraph(
          building.id,
          vertical: _verticalQuery,
        );
    if (!mounted) return;
    // 진입 구간도 문에서 시작한다(outdoor_map_screen의 같은 자리와 한 규칙).
    final leg = graph == null
        ? null
        : computeMultiFloorRoute(
            graph,
            entranceRouteNodeId(graph.nodes, entrance),
            endNodeId,
          );
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

  /// 출구 라벨 되읽기가 실패했을 때 쓸 **근사** 앵커.
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
      final rendered = await controller.queryRenderedFeaturesInRect(probe, [
        _indoorIds.sharedStoresLabel,
        _indoorIds.storesLabel,
        _indoorIds.facilityLabel,
      ], null);
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

  /// 고른 매장을 **폴리곤 칠 + 아이콘 색** 두 가지로 표시한다.
  ///
  /// 아이콘은 "이거 하나"를 콕 집고, 칠은 "여기까지"를 말한다 — 둘이 다른 일을
  /// 해서 함께 쓴다. 별도 핀은 세우지 않는다: 같은 장소에 기존 아이콘과 핀이
  /// 함께 서면 무엇이 실제 POI이고 무엇이 선택 장식인지 위계가 갈라진다.
  ///
  /// 폴리곤이 없는 매장(점만 있는 시설)은 칠할 것이 없어 아이콘 색만 바뀐다 —
  /// 칠 하나만 쓰던 시절 그런 자리에서 **아무 일도 안 일어나던** 것이 아이콘
  /// 색을 함께 두는 이유다.
  Future<void> _syncHighlightLayer() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    final target = _highlightTarget();
    await syncPolygonsSource(
      controller,
      kOutdoorHighlightSourceId,
      target.polygons,
      // 면·선 색을 이 값으로 고른다. 없으면 회색 잉크로 떨어진다.
      properties: {'category': target.category},
    );
    await _syncIndoorOverlayFade(scope: IndoorOverlaySyncScope.labels);
  }

  /// 고른 시설이 **한 화면에 다 들어오도록 물러선다.**
  ///
  /// 시설을 고르는 사람이 알고 싶은 것은 "이 층 어디에 있나"인데, 그 직전 화면은
  /// 매장 하나를 보던 배율이라 강조된 칸이 화면 밖이기 일쑤였다 — 종류를 바꿔
  /// 눌러도 도면이 그대로라 **아무 일도 안 일어난 것처럼** 보인다(실기기 확인).
  ///
  /// **층 전체가 아니라 그 시설들만 담는다.** 화장실 둘이 한쪽에 몰려 있으면
  /// 굳이 층 끝까지 물러설 이유가 없고, 흩어져 있으면 상자가 알아서 커진다.
  /// 아래를 비우는 높이는 셸이 이미 내려 준다([OutdoorMapBody.bottomOverlayLiftPx])
  /// — 시트가 떠 있으면 그 높이가 그 값에 들어 있다. **지도가 시트를 알지 않고
  /// 높이만 값으로 받는다**는 그 필드의 계약을 여기서도 그대로 쓴다.
  /// **맞출 것이 있었으면 true.** 층을 바꾼 쪽이 이 값을 보고 층 전체 fit으로
  /// 갈지 정한다([_onFloorChipSelected]) — 고른 종류가 그 층에 없으면 여기서는
  /// 아무 일도 일어나지 않으므로, 그때는 층 전체를 보여 주는 편이 낫다.
  Future<bool> _fitCameraToFacilityHighlight() async {
    final plan = _floorPlan;
    if (plan == null || !_indoorEntered) return false;
    final polygons = facilityHighlightPolygons(
      stores: plan.stores,
      selection: widget.categorySelection,
    );
    if (polygons.isEmpty) return false;
    final box = routeBoxFor([
      for (final polygon in polygons) ...polygon,
    ], minSideM: facilityFitMinSideM);
    if (box == null) return false;
    return _animateCameraToFitBox(
      box,
      topChromePx: floorFitTopChromePx,
      bottomChromePx: widget.bottomOverlayLiftPx,
      duration: floorSwitchZoomDuration,
      // 시설 하나만 고르면 상자가 작아 배율이 끝까지 올라간다. 그러면 도면이
      // 한 칸으로 가득 차, 물러서라고 만든 동작이 되레 더 들어가 버린다.
      maxZoom: facilityFitMaxZoom,
    );
  }

  /// 지금 강조할 폴리곤들과 그 색을 고를 대분류. 매장을 탭했으면 그 하나,
  /// 편의시설을 종류로 골랐으면 이 층의 그 종류 전부다
  /// ([facilityHighlightPolygons]가 고른다).
  ///
  /// 둘이 겹치면 탭이 이긴다 — 방금 누른 것이 먼저다.
  ({List<List<ll.LatLng>> polygons, String? category}) _highlightTarget() {
    final plan = _floorPlan;
    if (plan == null) return (polygons: const [], category: null);
    final storeId = _highlightedStoreId;
    if (storeId != null) {
      final store = plan.stores.where((s) => s.id == storeId).firstOrNull;
      return (
        polygons: [if (store != null) store.polygon],
        category: store?.category,
      );
    }
    return (
      polygons: facilityHighlightPolygons(
        stores: plan.stores,
        selection: widget.categorySelection,
      ),
      // 시설은 한 소분류를 통째로 고르는 자리라 색도 하나다.
      category: widget.categorySelection?.category,
    );
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
