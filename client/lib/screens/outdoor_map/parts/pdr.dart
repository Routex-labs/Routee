// ignore_for_file: invalid_use_of_protected_member
//
// part라 `setState`(protected) 호출이 경고로 잡힌다.
/// `OutdoorMapBodyState`의 **PDR·앵커·보정** 부분.
///
/// part 규약과 이 파일로 가른 이유는 `docs/client/outdoor-map-moves.md`.
part of '../outdoor_map_screen.dart';

extension OutdoorMapPdr on OutdoorMapBodyState {
  /// 세션이 꺼져 있으면 활성 층으로 켠다.
  ///
  /// 층을 두 번 읽는 이유와 두 조건이 다른 이유는 [PdrSessionLifecycle.startIfIdle]에
  /// 있다. 화면이 사라졌으면 둘 다 null이 되어 시작이 취소된다.
  Future<void> _startPdrIfIdle() {
    return _pdrLifecycle.startIfIdle(
      readStartableFloor: () {
        if (!mounted) return null;
        final floor = _activeFloor;
        final graph = _floorGraph;
        if (floor == null ||
            graph == null ||
            graph.nodes.isEmpty ||
            graph.edges.isEmpty) {
          return null;
        }
        return floor;
      },
      readActiveFloor: () => mounted ? _activeFloor : null,
    );
  }

  /// 센서 세션이 첫 이벤트를 보고할 때까지(최대 [sensorWarmupTimeout]) 기다린다.
  ///
  /// [IndoorNavigationDriver.confirmAnchorByPin]은 **호출 시점의** heading
  /// reference로 분기한다. 자북 heading을 이미 받았으면 회전 0으로 즉시 확정하고,
  /// 아직 아무 heading도 못 받았으면 arbitrary로 보고 수동 방향 보정을 요구한다.
  /// 수동 배치에서는 사용자가 지도를 보고 탭하는 몇 초가 자연스러운 유예였지만,
  /// 자동 배치는 startGuidance 직후 곧바로 찍으므로 그 유예가 없다. 기다리지
  /// 않으면 나침반이 멀쩡한 기기까지 전부 방향 보정 분기로 빠져, 추정한 진입
  /// 방향이 회전각으로 박히고 이후 궤적 전체가 그만큼 돌아간다.
  Future<void> _awaitSensorWarmup() async {
    bool reported(PdrRuntimeState state) =>
        state == PdrRuntimeState.running || state == PdrRuntimeState.degraded;
    if (reported(indoorNavigationDriver.currentRuntimeStatus.state)) return;
    try {
      await indoorNavigationDriver.runtimeStatuses
          .firstWhere((status) => reported(status.state))
          .timeout(sensorWarmupTimeout);
    } on Object {
      // 센서가 끝내 조용해도(권한 거부·미지원 기기·타임아웃) 앵커는 찍는다 —
      // 걸음이 쌓이지 않더라도 "어느 입구로 들어왔는지"는 지도에 보여야 한다.
    }
  }

  /// 실내 진입 오버레이에서의 위치 보정. GPS를 호출하지 않고 PDR이 알고 있는
  /// 실내 위치·방향만 쓴다.
  ///
  /// 실제로 동작을 수행한 탭만 카운트를 올린다 — 위치나 heading을 아직 몰라
  /// 안내만 띄운 탭까지 세면, 사용자가 위치를 잡은 뒤 누른 다음 탭이 "회전"
  /// 차례로 밀려 정작 중앙 정렬이 안 된다.
  Future<void> _recalibrateIndoor() async {
    if (_recalibrateTapCount.isEven) {
      // 홀수 번째 탭 — 실내 위치를 화면 정중앙으로. 앵커가 다른 층에 있거나
      // 층 그래프가 아직 없으면 null이라 여기서 걸린다. 지도가 아직 준비되지
      // 않았더라도 "위치를 먼저 지정하라"는 안내는 먼저 띄운다.
      final target = _pdrCurrentWgs84();
      if (target == null) {
        // 눌러야 할 버튼을 깜빡여 말한다([OutdoorMapBody.onNeedLocationPlacement]).
        widget.onNeedLocationPlacement?.call();
        return;
      }
      final controller = _mapController;
      if (controller == null || !_styleReady) return;
      await controller.animateCamera(CameraUpdate.newLatLng(_toGl(target)));
    } else {
      // 짝수 번째 탭 — 바라보는 방향이 화면 위쪽에 오도록 회전. 이때 내 실내
      // 위치도 함께 화면 정중앙에 놓는다. 중앙 정렬 후 조금 걸어간 뒤 회전을
      // 누르면 화면 중심과 내 위치가 이미 어긋나 있어, 중심을 그대로 두고
      // 돌리면 내 위치가 화면 가장자리로 밀려나기 때문이다. 줌·tilt는 유지.
      final heading = _pdrCurrentHeadingDeg;
      if (heading == null) {
        // 위치를 잡으라는 말은 그 버튼이 깜빡여 대신한다([_recalibrateIndoor]의
        // 홀수 탭과 같다). 남는 것은 "조금 걸어야 방향이 잡힌다"는 사실 하나뿐
        // 이라 한 줄로 짧게, 잠깐만 띄운다.
        widget.onNeedLocationPlacement?.call();
        _showSnack('조금 걸으면 방향이 잡힙니다', duration: OutdoorMapUi._briefSnackDuration);
        return;
      }
      final controller = _mapController;
      if (controller == null || !_styleReady) return;
      final camera = controller.cameraPosition;
      // 위치를 아직 모르면(앵커가 다른 층 등) 지금 보고 있는 중심을 그대로 둔다.
      final myLocation = _pdrCurrentWgs84();
      final center = myLocation != null
          ? _toGl(myLocation)
          : camera?.target ?? _toGl(_entrance ?? fallbackLocation);
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: center,
            zoom: camera?.zoom ?? indoorEntryZoomThreshold,
            bearing: heading,
            tilt: camera?.tilt ?? 0,
          ),
        ),
      );
    }
    _recalibrateTapCount++;
  }

  /// 출발지로 고른 매장 자리에 PDR 앵커를 다시 찍어 위치 아이콘을 옮긴다.
  ///
  /// "이 매장에서 출발한다"는 곧 "나는 지금 여기 있다"라, 지도를 탭한 것과 **같은
  /// 함수**([_confirmPdrAnchor])를 쓴다 — 방향을 0으로 가정하면 이후 궤적 전체가
  /// 그만큼 돌아간 채로 쌓인다.
  ///
  /// 실패는 조용히 넘긴다(여기서 return하면 길찾기가 통째로 죽는다).
  ///
  /// **찍고 나서 알리지 않는다.** 예전에는 "여기서 출발하는 것으로 봤다"를
  /// 되돌리기 손잡이와 함께 띄웠는데, 사용자가 방금 그 매장을 출발지로 고른
  /// 직후라 이미 아는 사실이었다 — 화면 아래를 가리는 값만 냈다. 위치를 다시
  /// 잡을 길은 하단 바의 "위치 지정"에 그대로 있다.
  Future<void> _anchorAtStoreOrigin({
    required String floor,
    required String nodeId,
    required ll.LatLng storePoint,
    required String storeName,
  }) async {
    // [_confirmPdrAnchor]가 축 변환(axes)을 [_floorGraph]에서 가져오므로,
    // 앵커를 찍기 전에 그 층 그래프가 화면에 올라와 있어야 한다.
    if (floor != _activeFloor) {
      await _switchOverlayFloorCrossfaded(floor);
      if (!mounted) return;
    }
    final graph = _floorGraph;
    if (graph == null || graph.nodes.isEmpty) return;

    // 매장의 입구 노드를 그대로 쓴다. 그 노드는 이미 통로 위에 있으므로 스냅이
    // 필요 없고, 경로 탐색이 시작하는 지점과도 정확히 같은 자리가 된다.
    final node = graph.nodes.where((n) => n.id == nodeId).firstOrNull;
    final PdrLocalPoint floorPoint;
    if (node != null) {
      floorPoint = PdrLocalPoint(node.xM, node.yM);
    } else {
      // 노드를 못 찾는 경우(그래프 갱신 시차 등)는 매장 좌표를 층 좌표로 되돌려
      // 가장 가까운 통로에 붙인다 — 수동 배치가 탭 좌표에 하는 것과 같다.
      final local = fitFloorGeoTransform(
        graph.nodes,
      ).invert(storePoint.latitude, storePoint.longitude);
      if (local == null) return;
      final snapped = FloorMapMatcher(
        graph,
      ).snapToWalkableNetwork(PdrLocalPoint(local.$1, local.$2));
      if (snapped == null) return;
      floorPoint = snapped.point;
    }

    if (!await _bindPdrSessionToFloor(floor)) return;
    await _confirmPdrAnchor(floorPoint, notifyLocationChanged: false);
  }

  /// 실내 위치(PDR) 마커. 야외 상태에서는 [_indoorLocationVisible]이 false라
  /// 항상 빈 소스를 밀어 넣어 마커가 사라진다 — 야외에서는 GPS 마커
  /// ([_syncCurrentLayer])만 보이고, 실내에서는 이쪽만 보인다.
  Future<void> _syncPdrCurrentLayer() {
    final revision = ++_pdrMarkerRevision;
    final controller = _mapController;
    if (controller == null || !_styleReady) return Future<void>.value();

    final location = _indoorLocationVisible ? _pdrCurrentWgs84() : null;
    final heading = location == null ? null : _pdrCurrentHeadingDeg;
    final data = pdrLocationData(location, headingDeg: heading);
    _publishHeadingDebug(heading);

    final previous = _pdrMarkerWriteQueue;
    _pdrMarkerWriteQueue = () async {
      // 이전 native 호출이 실패해도 다음 센서 갱신은 계속 진행한다.
      try {
        await previous;
      } catch (error, stackTrace) {
        debugPrint('PDR marker update failed: $error\n$stackTrace');
      }
      // 큐에 들어온 사이 더 최신 snapshot이 왔다면 이 위치는 쓰지 않는다.
      if (revision != _pdrMarkerRevision ||
          !mounted ||
          controller != _mapController ||
          !_styleReady) {
        return;
      }
      try {
        await controller.setGeoJsonSource(kOutdoorPdrCurrentSourceId, data);
      } catch (error, stackTrace) {
        debugPrint('PDR marker update failed: $error\n$stackTrace');
      }
    }();
    return _pdrMarkerWriteQueue;
  }

  ll.LatLng? _pdrCurrentWgs84() {
    // 탑승 중에는 활강이 위치의 출처다. 걸음은 멈춰 있고 앵커는 아직 이전 층에
    // 있어서, 이 갈래가 없으면 층이 바뀌는 순간 마커가 통째로 사라진다.
    final glide = _escalatorGlide;
    if (glide != null) {
      return glide.pointAtProgress(_escalatorGlideProgress.value);
    }
    final graph = _floorGraph;
    if (graph == null || graph.nodes.isEmpty) return null;
    final position = _indoorPosition;
    if (position == null) return null;
    final wgs84 = fitFloorGeoTransform(
      graph.nodes,
    ).apply(position.localM.eastM, position.localM.northM);
    return ll.LatLng(wgs84.$1, wgs84.$2);
  }

  /// PDR 스냅샷의 층 로컬 좌표 경로들. 실내 지도와 같은 계산을 쓴다 — 두
  /// 화면이 다른 값을 그리면 진단이 서로를 반박하게 된다.
  ///
  /// 앵커가 없거나 지금 보고 있는 층과 다른 층에 찍혀 있으면 빈 경로다.
  /// 층을 바꾸면 그 층 경로만 보여야 하기 때문이다.
  List<PdrLocalPoint> get _pdrConfirmedFloorPath {
    final snapshot = _pdrTrailState.snapshot;
    final anchor = _pdrTrailState.anchor;
    final graph = _floorGraph;
    if (snapshot == null ||
        anchor == null ||
        anchor.floorId != _activeFloor ||
        graph == null ||
        graph.nodes.isEmpty) {
      return const [];
    }
    final pdrToFloor = FloorCoordinateTransform(anchor);
    return snapshot.path.map(pdrToFloor.toFloor).toList(growable: false);
  }

  /// 확정 전 미리보기(preview)까지 포함한 날것의 궤적.
  List<PdrLocalPoint> get _pdrRawFloorPath {
    final snapshot = _pdrTrailState.snapshot;
    final anchor = _pdrTrailState.anchor;
    final graph = _floorGraph;
    if (snapshot == null ||
        anchor == null ||
        anchor.floorId != _activeFloor ||
        graph == null ||
        graph.nodes.isEmpty) {
      return const [];
    }
    final pdrToFloor = FloorCoordinateTransform(anchor);
    return snapshot.reconciledPreviewPath
        .map(pdrToFloor.toFloor)
        .toList(growable: false);
  }

  /// confirmed 경로를 통행 간선에 스냅한 결과. 단순 스냅 점을 직선으로 잇지
  /// 않고 간선이 바뀌는 구간은 그래프 경로로 펼친다(matchRoutedPath).
  List<PdrLocalPoint> get _pdrMatchedFloorPath {
    final graph = _floorGraph;
    final confirmed = _pdrConfirmedFloorPath;
    if (graph == null || confirmed.isEmpty) return const [];
    return FloorMapMatcher(graph).matchRoutedPath(confirmed);
  }

  /// PDR이 올라타 있다고 판정된 간선들. 세션 시작 직후 원점 하나만 투영돼
  /// 아직 걷지도 않은 간선이 강조되는 것을 막으려고 실제 이동이 생긴 뒤에만
  /// 채운다.
  Set<String> get _pdrMatchedEdgeIds {
    final graph = _floorGraph;
    final confirmed = _pdrConfirmedFloorPath;
    if (graph == null || !_hasMeaningfulPdrMovement(confirmed)) return const {};
    return FloorMapMatcher(
      graph,
    ).matchPath(confirmed).map((point) => point.edgeId).toSet();
  }

  /// 세션 시작 직후에는 원점 한 개만 가장 가까운 간선에 투영되면서, 아직 걷지도
  /// 않았는데 그 간선 전체가 청록색으로 강조될 수 있다. 실내 지도와 같은 기준
  /// (누적 이동 0.2 m)을 쓴다 — 두 화면이 다른 기준을 쓰면 같은 세션에서 활성
  /// 간선이 한쪽에만 뜬다.
  bool _hasMeaningfulPdrMovement(List<PdrLocalPoint> path) {
    if (path.length < 2) return false;
    var distanceM = 0.0;
    for (var index = 1; index < path.length; index++) {
      final dx = path[index].eastM - path[index - 1].eastM;
      final dy = path[index].northM - path[index - 1].northM;
      distanceM += math.sqrt(dx * dx + dy * dy);
      if (distanceM >= 0.2) return true;
    }
    return false;
  }

  /// 디버그 모드의 PDR 진단 레이어(그래프 노드·간선 + 세 경로)를 갱신한다.
  ///
  /// 디버그 모드가 꺼져 있거나 개별 토글이 꺼져 있으면 빈 데이터를 넘겨 해당
  /// 소스를 비운다. 지도 소스에 실제로 쓰는 일은 [syncPdrDebugLayers]가 한다.
  /// heading이 도는 네 토막의 값을 칩 한 줄로 내보낸다.
  ///
  /// **마커를 그리는 그 자리에서 찍는다.** 따로 계산하면 칩과 화면이 다른 값을
  /// 보게 되고, 그러면 현장에서 "칩은 맞는데 마커는 틀렸다"를 어느 쪽도 못 믿는다
  /// (GPS 진입 판정 칩과 같은 규칙 — `indoor-entry-rules.md`).
  void _publishHeadingDebug(double? markerHeadingDeg) {
    if (!_debugModeController.enabled) {
      _headingDebugText.value = null;
      return;
    }
    _headingDebugText.value = describeMarkerHeading(
      deviceBearingDeg: _pdrTrailState.snapshot?.orientationHeadingDeg,
      markerBearingDeg: markerHeadingDeg,
      cameraBearingDeg: _mapController?.cameraPosition?.bearing ?? 0,
      anchorRotationDeg: _pdrTrailState.anchor?.rotationDeg,
      // **파생값이 아니라 센서가 준 원문을 띄운다.** `headingReference`만 보면
      // 실내에서 자력계가 교란돼 gyro hold에 들어간 상태도 그냥 `magneticNorth`
      // 로 보인다 — 그 구분이 안 보여서 회귀를 한참 못 찾았다.
      headingSource: _pdrTrailState.snapshot?.quality.features.headingSource,
      magneticAccuracy:
          _pdrTrailState.snapshot?.quality.features.magneticAccuracy,
      // 앵커가 이 방위를 썼는지 갈아탔는지의 근거다. rot과 나란히 있어야
      // "게이트가 안 걸렸다"와 "걸렸는데도 틀렸다"가 구분된다.
      headingErrorDeg:
          _pdrTrailState.snapshot?.quality.features.rotationHeadingAccuracyDeg,
    );
  }

  Future<void> _syncDebugPdrLayers() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    final debug = _debugModeController;
    final on = debug.enabled;

    // 그래프 노드·간선은 실내 지도와 같은 공용 변환기를 쓴다. 직접 from→to
    // 직선을 긋지 않는 것이 중요하다 — 간선에 geometryLocalM(꺾인 복도)이 있으면
    // 그 형상을 따라야 하고, 활성 간선에 물린 노드도 함께 강조돼야 한다.
    final overlay = on
        ? buildDebugMapOverlay(
            _floorGraph,
            showNodes: debug.showGraphNodes,
            showEdges: debug.showGraphEdges,
            activeEdgeIds: _pdrMatchedEdgeIds,
          )
        : const DebugMapOverlay();
    await syncPdrDebugLayers(
      controller,
      overlay: overlay,
      rawPath: on && debug.showRawPdrPath
          ? _floorPathToWgs84(_pdrRawFloorPath)
          : const [],
      confirmedPath: on && debug.showConfirmedPdrPath
          ? _floorPathToWgs84(_pdrConfirmedFloorPath)
          : const [],
      matchedPath: on && debug.showMapMatchedPdrPath
          ? _floorPathToWgs84(_pdrMatchedFloorPath)
          : const [],
    );
  }

  /// 사용자가 바라보는 방향(true north 기준, 시계방향 도). PDR 세션이 heading을
  /// 아직 못 얻은 상태(예: 자북 못 잡음 + 수동 방향 보정 아직 안 함, 첫 걸음
  /// 전)에는 null을 돌려주고, 이 경우 마커도 heading 원뿔 없이 도트만 뜬다.
  /// 계산식은 실내와 동일하며 walkOffset·복도 bias를 섞지 않는다.
  double? get _pdrCurrentHeadingDeg {
    final snapshot = _pdrTrailState.snapshot;
    final anchor = _pdrTrailState.anchor;
    if (snapshot == null || anchor == null || !snapshot.hasHeading) return null;
    final transform = FloorCoordinateTransform(anchor);
    final orientationFloorHeading = transform.toFloorBearing(
      snapshot.orientationHeadingDeg,
    );
    return transform.floorBearingToMapBearing(orientationFloorHeading);
  }

  void _syncCorridorTracking(PdrSnapshot? snapshot) {
    if (_indoorEntered) _ensureGuidanceAttached();
    _guidance
      ..setContext(
        floorId: _activeFloor,
        graph: _floorGraph,
        floorLabels: _building?.floors ?? const [],
      )
      ..setAnchor(_pdrTrailState.anchor)
      ..setEstimate(indoorLocationEstimateController.current)
      ..setRoute(_indoorMultiFloorRoute);
    final result = _guidance.onSnapshot(snapshot);
    // 탑승점 접근 배너와 마커 고정은 기압이 아니라 **걸음 갱신**에서 올라온다.
    // 여기서 비우지 않으면 다음 기압 샘플(iOS는 약 1초)까지 늦는다.
    if (result != null) _handleEscalatorPhaseChanges();
    _syncIndoorRouteProgress(result, snapshot);
    if (result == null) return;
    final anchor = _pdrTrailState.anchor;
    if (anchor != null) {
      _guidanceTrailSession.update(floorId: anchor.floorId, result: result);
    }
    _pdrDebugRecorder?.recordCorridorCorrection(result);
    if (snapshot != null) {
      _pdrDebugRecorder?.recordTrackerInput(
        observation: _guidance.lastObservation,
        wasReset: _guidance.lastWasReset,
        result: result,
        snapshot: snapshot,
        previewTailPeakTimesMs: _guidance.corridor.previewTailPeakTimesMs(
          snapshot,
        ),
      );
    }
  }

  /// PDR 세션이 [floor]를 가리키게 맞춘다. 이어서 앵커를 찍어도 되면 true.
  ///
  /// **다른 층에서 돌고 있는 세션을 그냥 재사용하면 안 된다** — 앵커에 찍히는 층은
  /// 세션의 층이라, 1층에서 지정한 뒤 2층에서 다시 지정하면 새 앵커가 여전히 1층으로
  /// 기록돼 2층 지도에 아무것도 안 나타났다(오류도 없어 단서가 없던 버그).
  ///
  /// 앵커를 새로 찍는 것은 **기준점을 새로 잡는 것**이라 궤적·복도 보정도 함께 비운다.
  ///
  /// [gatePermission]이 false면 권한 확인 없이 시작한다(GPS 자동 진입 전용 — 거기서
  /// 한 번 더 막으면 자동 추적이 시작되지 않는다). [announceFailure]는 사용자가 직접
  /// "위치 지정"을 누른 경우에만 켠다.
  Future<bool> _bindPdrSessionToFloor(
    String floor, {
    bool gatePermission = true,
    bool announceFailure = false,
  }) async {
    // 아래 사다리는 전부 "지금 세션 상태"를 읽어 갈린다. 정지가 아직 도는 중이면
    // 그 상태가 거짓말을 한다([PdrSessionLifecycle.awaitStop]).
    await _pdrLifecycle.awaitStop();
    if (!mounted) return false;
    if (indoorNavigationDriver.currentRuntimeStatus.state ==
        PdrRuntimeState.idle) {
      if (!gatePermission) {
        setState(() => _pdrTrailState.beginNewSession());
        await indoorNavigationDriver.startGuidance(floorId: floor);
        return mounted;
      }
      await _startPdrIfIdle();
      if (!mounted) return false;
      if (indoorNavigationDriver.currentRuntimeStatus.state ==
          PdrRuntimeState.idle) {
        if (announceFailure) {
          _showSnack('걸음 센서 권한이 없어 위치를 추적할 수 없습니다. 설정에서 동작·피트니스 권한을 허용해주세요.');
        }
        return false;
      }
    } else if (indoorNavigationDriver.currentFloorId != floor) {
      await indoorNavigationDriver.changeFloor(floorId: floor);
      if (!mounted) return false;
    } else if (!gatePermission) {
      // 자동 진입인데 이미 이 층 세션이 돌고 있다. 그대로 이어 쓴다.
      return true;
    }
    setState(() {
      _pdrTrailState.beginNewSession();
      // 새 PDR 세션이다. 이전 세션의 보정을 들고 가면 첫 프레임이 지난 세션
      // 좌표에서 시작한다. 층·경로 컨텍스트는 그대로 두고 보정만 비운다.
      //
      // 진행률 기준점도 함께 버린다. 앵커가 옮겨졌는데 진행거리만 이전 세션
      // 값으로 남으면, 다음 걸음에서 남은거리가 튀거나 재획득이 매 걸음 켜진다.
      _guidance
        ..resetTracking()
        ..clearProgress();
    });
    return true;
  }

  /// 앵커 배치 대기 상태 전환. 상위(MapShellScreen)에 알려 하단 바 "위치 지정"
  /// 버튼의 활성 톤을 함께 갱신한다.
  void _setPlacingAnchor(bool value) {
    if (_placingPdrAnchor == value) return;
    setState(() => _placingPdrAnchor = value);
    widget.onPlacingLocationChanged?.call(value);
  }

  /// 진단 세션은 실내 지도 탭과 같은 경계를 쓴다 — **한 번의 길안내**.
  ///
  /// 상세한 근거는 실내 화면의 `_beginRouteRecordingSession` 주석을 본다. 요지는
  /// PDR이 상시 실행이 된 뒤 "시작~종료"를 경계로 쓸 수 없고, 그대로 두면 표본
  /// 상한에 걸려 분석하려는 구간이 앞에서부터 잘려 나간다는 것이다.
  void _ensureGuidanceTrailSessionStarted() {
    if (_guidanceTrailSession.isActive) return;
    final floor = _pdrTrailState.anchor?.floorId ?? _activeFloor;
    if (floor == null) return;
    _guidanceTrailSession.start(
      floorId: floor,
      result: _guidance.trackingResult,
    );
  }

  Future<void> _exportPdrDebugJson() async {
    final recorder = _pdrDebugRecorder;
    if (recorder == null || !recorder.hasSnapshot || _exportingPdrDebugJson) {
      _showSnack('내보낼 PDR 세션이 없습니다.');
      return;
    }
    setState(() => _exportingPdrDebugJson = true);
    try {
      final device = await PdrDebugDeviceInfo.load();
      final session = recorder.buildJson(
        buildingId: _building?.id ?? demoBuildingId,
        selectedFloor: _activeFloor,
        mapCalibrationVersion: _mapCalibrationVersion,
        graph: _floorGraph,
        device: device,
      );
      await const PdrDebugSessionShare().share(
        session,
        sharePositionOrigin: _pdrSharePositionOrigin(),
      );
    } on Object catch (error) {
      if (mounted) _showSnack('PDR JSON을 내보내지 못했습니다: $error');
    } finally {
      if (mounted) setState(() => _exportingPdrDebugJson = false);
    }
  }

  /// iOS 공유 시트는 popover 기준 사각형이 필요하다. 전달하지 않으면
  /// share_plus가 `{0, 0, 0, 0}`을 보내 iOS에서 공유를 거부한다.
  Rect? _pdrSharePositionOrigin() {
    final box =
        _pdrShareButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize && !box.size.isEmpty) {
      return box.localToGlobal(Offset.zero) & box.size;
    }
    return null;
  }

  Future<void> _onMapPressedForPdr(ll.LatLng point) async {
    final graph = _floorGraph;
    if (graph == null || graph.nodes.isEmpty) {
      _showSnack('이 층의 지도 정보가 아직 없습니다.');
      _setPlacingAnchor(false);
      return;
    }
    final local = fitFloorGeoTransform(
      graph.nodes,
    ).invert(point.latitude, point.longitude);
    if (local == null) {
      _showSnack('이 층 좌표를 계산하지 못했습니다.');
      return;
    }
    final tapped = PdrLocalPoint(local.$1, local.$2);
    final snapped = FloorMapMatcher(graph).snapToWalkableNetwork(tapped);
    if (snapped == null) {
      _showSnack('이 층의 통로 위치를 찾지 못했습니다. 다시 시도해주세요.');
      return;
    }
    if (snapped.distanceToGraphM > maxPdrAnchorSnapDistanceM) {
      // **한 줄로 짧게, 잠깐만.** 예전에는 실측 거리까지 문장에 실었는데, 읽고
      // 나서 할 일은 "복도를 다시 누른다" 하나뿐이라 나머지는 화면 아래를 4초
      // 동안 가리는 값만 냈다. 거리는 로그로 남긴다 — 어디가 문제인지 가리는
      // 데는 여전히 그 숫자가 필요하고, 그건 개발자가 볼 자리다.
      debugPrint(
        '[anchor] 통로에서 ${snapped.distanceToGraphM.toStringAsFixed(1)}m 떨어진 탭',
      );
      _showSnack('복도를 선택해주세요!', duration: OutdoorMapUi._briefSnackDuration);
      return;
    }
    await _confirmPdrAnchor(snapped.point);
  }

  /// [notifyLocationChanged]는 "사용자의 현재 위치가 새로 잡혔다"를 상위에
  /// 알릴지다. 기본은 알린다 — 지도 탭·입구 자동 배치처럼 **새 위치가 생긴**
  /// 경우이기 때문이다. 출발지 매장을 따라 찍는 경우([_anchorAtStoreOrigin])만
  /// 끈다. 그쪽은 상위가 방금 정한 출발지를 되짚어 찍는 것이라, 다시 알리면
  /// 상위가 그 출발지를 스스로 버리게 된다.
  Future<void> _confirmPdrAnchor(
    PdrLocalPoint floorPoint, {
    bool notifyLocationChanged = true,
  }) async {
    final graph = _floorGraph;
    final axes = graph == null
        ? const PdrToFloorAxes.identity()
        : fitPdrToFloorAxes(graph.nodes);
    await indoorNavigationDriver.confirmAnchorByPin(
      floorPointM: floorPoint,
      axes: axes,
    );
    if (!mounted) return;
    // **방향은 사용자에게 묻지 않는다.**
    //
    // 예전에는 여기서 「바라보는 방향 맞추기」 모달을 띄웠다. 아무 조작 없이
    // 튀어나오는 창이었고, 화면 위/오른쪽 같은 보기로 실제 방위를 고르게 하는
    // 것이라 사용자가 답을 알기도 어려웠다.
    //
    // 그렇다고 그냥 지우면 안 된다 — [CalibrationPhase.awaitingHeading]은
    // `canRenderPosition`이 false라, 물음을 없애는 순간 **위치 마커가 통째로
    // 사라진다.** 그래서 묻는 대신 자동 진입과 **같은 추정**으로 채운다
    // ([_entryFloorDirection]: GPS course → 층 그래프 중심).
    if (indoorNavigationDriver.currentCalibration.phase ==
        CalibrationPhase.awaitingHeading) {
      final direction = graph == null
          ? null
          : _entryFloorDirection(
              position: _position,
              anchorFloorPoint: floorPoint,
              graph: graph,
              axes: axes,
            );
      // 추정도 실패하면(그래프가 없거나 찍은 점이 중심과 겹침) 방향을 모르는
      // 채로 둔다. 지어낸 각도로 궤적을 통째로 돌리는 것보다, 위치가 아직
      // 안 잡힌 상태로 남겨 두고 사용자가 다시 찍게 하는 편이 낫다.
      if (direction == null) {
        _showSnack('방향을 잡지 못했습니다. 조금 걸은 뒤 다시 지정해주세요.');
        return;
      }
      await indoorNavigationDriver.confirmAnchorByFloorDirection(
        floorDirection: direction,
      );
    }
    if (!mounted) return;
    _setPlacingAnchor(false);
    _syncPdrCurrentLayer();
    unawaited(_syncDebugPdrLayers());
    if (notifyLocationChanged) widget.onLocationAnchored?.call();
    // 배치가 끝났다는 안내는 따로 띄우지 않는다. 지도에 위치 마커가 바로
    // 찍히고 안내 배너가 사라지는 것으로 이미 결과가 보이는데, 토스트까지
    // 겹치면 방금 지정한 지점을 가린다.
  }

  /// 안내 오른쪽 상단 X — 위치 지정을 취소한다.
  ///
  /// 배치 대기만 끄는 게 아니라 PDR 세션까지 함께 멈춘다.
  /// [startLocationPlacement]가 idle이던 세션을 켠 뒤 대기로 넘기므로, 대기만
  /// 끄면 센서는 계속 돌면서 앵커 없는 세션이 남는다(실내 화면의 동명 함수와
  /// 같은 계약).
  Future<void> _cancelPdrAnchor() async {
    if (!_placingPdrAnchor) return;
    await indoorNavigationDriver.stopGuidance();
    _pdrDebugRecorder?.recordPedometerFinalize(
      indoorNavigationDriver.lastPedometerFinalizeInfo,
    );
    _pdrDebugRecorder?.recordSessionBoundary('sensorStopped');
    _pdrDebugRecorder?.recordRuntime(
      indoorNavigationDriver.currentRuntimeStatus,
    );
    if (mounted) _setPlacingAnchor(false);
  }
}
