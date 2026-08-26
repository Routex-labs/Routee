// ignore_for_file: invalid_use_of_protected_member
//
// part라 `setState`(protected) 호출이 경고로 잡힌다.
/// `OutdoorMapBodyState`의 **층 전환 크로스페이드** 부분.
///
/// part 규약과 이 파일로 가른 이유는 `docs/client/outdoor-map-moves.md`.
part of '../outdoor_map_screen.dart';

extension OutdoorMapFloorSwitch on OutdoorMapBodyState {
  /// 층 선택기에서 사용자가 직접 층을 골랐을 때. 갈아 끼운 뒤 **그 층 외곽선에
  /// 카메라를 다시 맞춘다** — 층마다 크기가 달라(지상 180×190 m ↔ B3 286×305 m)
  /// 이전 배율이 안 맞는다.
  ///
  /// **자동 전환에는 붙이지 않는다** — 안내 중에는 카메라가 사용자를 따라가야 한다.
  Future<void> _onFloorChipSelected(String floor) async {
    if (floor == _activeFloor) return;
    // 크로스페이드 마무리(타일 대기 → 페이드인)는 떼어 둔 채 곧바로 돌아오므로
    // 카메라 재정렬(500ms)이 이전 층 도면이 아직 보이는 동안 시작된다 — 새
    // 도면은 카메라가 움직이는 위로 준비되는 대로 페이드인돼 하나의 전환으로
    // 읽힌다. 재정렬을 페이드 뒤로 미루면 전환이 두 박자("바뀌고, 그 다음
    // 움직이고")로 쪼개진다.
    await _switchOverlayFloorCrossfaded(floor, recenterIfNeeded: false);
    // 연타로 이 탭이 추월당했으면 카메라를 만지지 않는다 — 여기서 fit하면
    // 사용자가 마지막으로 고른 층 화면을 이전 탭의 층 외곽선에 맞춰 버린다
    // (지하층처럼 층마다 크기가 크게 다르면 정렬이 눈에 띄게 어긋난다).
    // 카메라는 마지막 탭의 이 함수 호출이 맞춘다.
    if (!mounted || _activeFloor != floor) return;
    // **편의시설을 종류로 골라 둔 채 층을 바꿨다면 새 층의 그 시설들에 맞춘다.**
    // 시트를 열어 둔 사람이 묻는 것은 "이 층 어디에 있나"인데, 층 전체 fit은
    // 그 답을 화면 어딘가의 작은 칸으로 만들어 다시 찾게 한다. 그 층에 그
    // 종류가 없으면 false라, 아래 층 전체 fit으로 떨어진다.
    //
    // 도면을 먼저 기다린다 — 시설 폴리곤은 [_floorPlan]에서 나오고, 그것을
    // 채우는 것이 이 로드다([_fitCameraToActiveFloor]도 같은 것을 기다린다).
    await _floorGraphLoad;
    if (!mounted || _activeFloor != floor) return;
    if (await _fitCameraToFacilityHighlight()) return;
    // 층 그래프가 도착한 뒤라 [_activeFloorOutlineRing]이 새 층 외곽선을 준다
    // (`_switchOverlayFloor`가 `_loadFloorGraph`까지 기다린다).
    await _fitCameraToActiveFloor(duration: floorSwitchZoomDuration);
  }

  /// 층 선택기 탭의 테스트 진입점. 층 chip은 셸이 그리는 위젯이라 이 화면의
  /// 위젯 테스트에서는 누를 수 없으므로, 실기기와 **같은 함수**를 부른다.
  @visibleForTesting
  Future<void> selectFloorChipForTest(String floor) =>
      _onFloorChipSelected(floor);

  /// [_switchOverlayFloor]를 크로스페이드로 돈다. **층이 바뀌는 모든 경로**가 이걸
  /// 쓴다 — 직접 부르면 타일 교체가 "지워졌다 다시 그려지는" 장면으로 드러난다.
  ///
  /// 이전 도면은 새 타일이 실제로 도착할 때까지 남는다. 마무리(타일 대기 → 페이드인
  /// → 이전 블록 제거)는 [_finalizeIndoorFloorCrossfade]가 떼어져 돌므로 이 함수는
  /// 층 그래프 로드까지만 기다린다. 타이밍 근거는 camera-choreography-plan.md 4.13.
  Future<void> _switchOverlayFloorCrossfaded(
    String floor, {
    bool recenterIfNeeded = true,
    Duration crossfadeDuration = floorSwitchCrossfadeDuration,
  }) async {
    final token = _floorSwitchProgress.begin(
      floorSwitchDirectionBetween(_activeFloor, floor),
    );
    var handedOff = false;
    try {
      handedOff = await _switchOverlayFloor(
        floor,
        recenterIfNeeded: recenterIfNeeded,
        crossfade: true,
        progressToken: token,
        crossfadeDuration: crossfadeDuration,
      );
    } finally {
      // 크로스페이드 마무리가 예약됐으면 완료 통지도 거기서 한다(타일이 아직
      // 오는 중인데 여기서 finish하면 모티프가 "로딩 중"에 걷힌다). 예약까지
      // 못 갔으면(같은 층, 지도 미준비, 예외) 여기서 반드시 알린다 — 안
      // 그러면 모티프가 영영 안 걷힌다.
      if (!handedOff) _floorSwitchProgress.finish(token);
    }
  }

  /// 층 도면을 갈아 끼운다(MVT 소스 + PDR 스냅용 층 그래프).
  ///
  /// [recenterIfNeeded]가 false면 재정렬을 건너뛴다 — 호출자가 곧바로 카메라를 맞출
  /// 때 쓴다(두 애니메이션이 겹치면 지도가 한 번 움찔한다).
  ///
  /// [crossfade]가 false면 즉시 교체, true면 새 블록을 **투명하게** 얹고 마무리를
  /// 예약한다. 반환값은 그 예약 여부이고, 예약됐으면 [progressToken]도 마무리가 맡는다.
  Future<bool> _switchOverlayFloor(
    String floor, {
    bool recenterIfNeeded = true,
    bool crossfade = false,
    int? progressToken,
    Duration crossfadeDuration = floorSwitchCrossfadeDuration,
  }) async {
    if (floor == _activeFloor) return false;
    final controller = _mapController;
    final building = _building;
    if (building == null) return false;
    // **컨트롤러가 없어도 층 상태와 그래프는 바꾼다.** 예전에는 여기서 통째로
    // 빠져나갔는데, 그러면 스타일이 아직 안 올라온 사이에 온 층 전환(자동 층
    // 이동이 대표적이다)이 조용히 사라진다. 지도 레이어를 만지는 부분만
    // 컨트롤러가 있을 때 한다.
    final canDrawLayers = controller != null && _styleReady;
    final deferFloorBoundarySync =
        crossfade && canDrawLayers && _indoorTilesRegistered;
    _deferFloorBoundarySync = deferFloorBoundarySync;

    // 다층 경로가 있으면 새 층의 세그먼트로 갈아 끼운다(없으면 이 층에는
    // 안 그린다). 단일층 경로였다면 다른 층으로 옮기는 순간 경로가 무의미해지므로
    // 지도에서 지운다 — 실내 화면과 동일 규칙.
    final multiRoute = _indoorMultiFloorRoute;
    final nextSegmentRoute = multiRoute?.segmentForFloor(floor)?.route;
    debugPrint(
      '[floor] 보는 층 $_activeFloor → $floor · '
      '앵커 층 ${_pdrTrailState.anchor?.floorId} · '
      '다층경로 ${_indoorMultiFloorRoute?.segments.map((s) => s.floorName).toList()}',
    );
    setState(() {
      _activeFloor = floor;
      _floorGraph = null;
      _floorPlan = null;
      _storeLabelPriorities = const {};
      _mapCalibrationVersion = 'unversioned';
      // 세그먼트가 갈아타면 진행거리 기준점도 새 세그먼트 기준으로 다시 잡아야
      // 한다. 남겨두면 층을 바꾼 순간 남은거리가 튄다.
      _guidance
        ..setRouteSegment(multiRoute == null ? null : nextSegmentRoute)
        ..seedProgress(null);
      // 층이 바뀌면 그 층에 강조하던 매장은 지도에 없다. 강조도 초기화.
      _highlightedStoreId = null;
    });
    // **세션에도 지금 알린다.** 다음 스냅샷까지 미루면 그 사이 세션은 이전 층
    // 기준 보정 위치를 들고 있고, 화면은 새 층 그래프로 좌표를 되돌린다 —
    // 마커가 새 층 도면 위 엉뚱한 자리에 찍힌다. 서 있으면 스냅샷이 몇 초씩
    // 안 오므로 한 프레임이 아니라 눈에 보이는 시간 동안 어긋난다.
    _guidance.setContext(
      floorId: floor,
      graph: _floorGraph,
      floorLabels: building.floors,
    );
    _notifyActiveFloor();
    // 층이 바뀐 순간 이전 층의 외곽선은 더 이상 맞지 않는다. 새 도면이 도착할
    // 때까지(지하 → 다른 층) 선을 지워 둔다 — 틀린 경계를 보여주지 않는다.
    unawaited(_syncFloorOutlineLayer());
    // 크로스페이드면 이전 층 블록을 지우지 않고 은퇴 목록으로 넘긴다 — 새 층
    // 타일이 도착할 때까지 이전 도면이 그대로 보이는 것이 연출의 핵심이다.
    // 제거는 페이드인이 끝난 뒤 [_finalizeIndoorFloorCrossfade]가 한다.
    var retiredForCrossfade = false;
    if (canDrawLayers && _indoorTilesRegistered) {
      if (crossfade) {
        _retiringIndoorBlocks.add(
          _RetiringIndoorBlock(
            layerIds: _indoorIds.layersTopFirst,
            sourceId: _indoorIds.source,
            fadeFactor: _indoorOverlayFadeFactor,
          ),
        );
        retiredForCrossfade = true;
        _indoorTilesRegistered = false;
        _indoorIds = _indoorIds.next();
      } else {
        // 앞선 크로스페이드가 마무리 전에 이 경로(안내 중 자동 전환)로
        // 끊겼으면 은퇴 블록이 남아 있을 수 있다 — 여기서 함께 지운다.
        await _removeRetiringIndoorBlocks(controller);
        // 순서 중요: 레이어부터 지워야 소스를 지울 수 있다(레이어가 붙어있으면
        // 오류). 이미 없는 레이어에 대해 removeLayer가 예외를 던지는 native
        // 구현도 있어 각 항목을 try/catch로 감싼다.
        for (final id in _indoorIds.layersTopFirst) {
          try {
            await controller.removeLayer(id);
          } catch (_) {}
        }
        try {
          await controller.removeSource(_indoorIds.source);
        } catch (_) {}
        _indoorTilesRegistered = false;
        // 다음 등록은 새 세대 ID로. 같은 ID로 즉시 addSource를 다시 부르면
        // native(Android/iOS)가 이전 remove의 정리를 아직 못 끝내 조용히
        // 실패하는 경우가 있다(특정 층으로 전환 시 아무것도 안 그려지는
        // 원인이었음).
        _indoorIds = _indoorIds.next();
      }
    }
    // 은퇴 블록이 있으면 새 블록은 투명(계수 0)하게 얹는다 — 타일이 도착해도
    // 페이드인 전까지는 이전 도면이 보인다. 은퇴 블록이 없으면(첫 등록) 가릴
    // 이전 도면 자체가 없으므로 원래 불투명도로 바로 얹는다.
    await _ensureIndoorTilesRegistered(fadeFactor: retiredForCrossfade ? 0 : 1);
    var crossfadeScheduled = false;
    if (crossfade && canDrawLayers && _indoorTilesRegistered) {
      crossfadeScheduled = true;
      unawaited(
        _finalizeIndoorFloorCrossfade(
          generation: _indoorIds.generation,
          progressToken: progressToken,
          crossfadeDuration: crossfadeDuration,
        ),
      );
    } else if (controller != null) {
      // **마무리를 예약하지 못했으면 여기서 지운다.** 은퇴 블록을 지우는 곳은
      // [_finalizeIndoorFloorCrossfade] 하나뿐인데, 새 층 등록이 실패했거나
      // (`_indoorTilesRegistered`가 false) 크로스페이드가 아닌 전환이면 그것이
      // 예약되지 않는다. 그러면 이전 층 블록이 영영 남는다.
      await _removeRetiringIndoorBlocks(controller);
      await purgeStaleIndoorOverlay(
        controller,
        keepGeneration: _indoorIds.generation,
      );
      await _syncFloorBoundaryToActiveFloor();
    }
    await _loadFloorGraph(building.id, floor);
    _syncPdrCurrentLayer(snap: true);
    unawaited(_syncDebugPdrLayers());
    _syncRouteLayer();
    // 층이 바뀌면 도착 핀도 다시 판정한다 — 다층 경로에서 도착지 층을 벗어나면
    // 핀이 사라지고, 다시 그 층으로 돌아오면 살아난다.
    _syncIndoorDestinationLayer();
    _syncHighlightLayer();
    _notifyRouteStateIfChanged();
    // 카메라가 건물 밖이거나 페이드인 전 zoom이면 "골랐는데 아무것도 안 나온다"가
    // 된다. 층 chip 탭은 "그 층을 보고 싶다"는 신호라 그때만 카메라를 옮긴다 —
    // 이미 잘 보이는 상태에서 재정렬하면 view가 불필요하게 튄다.
    if (recenterIfNeeded) await _recenterOnBuildingIfNeeded();
    return crossfadeScheduled;
  }

  /// 크로스페이드 마무리 — 타일 도착을 기다려 페이드인하고 이전 블록을 지운다.
  /// 등록 직후 떼어서(unawaited) 부르므로 카메라 재정렬이 로드와 겹쳐 돈다.
  ///
  /// "타일 도착"은 `querySourceFeatures` 폴링으로 잡는 **실제 로드 신호**다. 타일
  /// 요청 자체가 없으면 영영 안 잡히므로 [floorSwitchTilesReadyTimeout]에서 끊는다.
  ///
  /// [generation]이 어긋나면(새 전환이 시작됨) 즉시 물러난다 — 은퇴 블록 정리까지
  /// 마지막 전환이 이어받는다.
  Future<void> _finalizeIndoorFloorCrossfade({
    required int generation,
    int? progressToken,
    Duration crossfadeDuration = floorSwitchCrossfadeDuration,
  }) async {
    try {
      final elapsed = Stopwatch()..start();
      while (true) {
        if (!mounted || _indoorIds.generation != generation) return;
        final controller = _mapController;
        if (controller == null) return;
        List<dynamic> features = const [];
        try {
          features = await controller.querySourceFeatures(
            _indoorIds.source,
            'footprint',
            null,
          );
        } catch (_) {}
        if (features.isNotEmpty ||
            elapsed.elapsed >= floorSwitchTilesReadyTimeout) {
          break;
        }
        await Future<void>.delayed(floorSwitchTilesPollInterval);
      }
      if (!mounted || _indoorIds.generation != generation) return;
      final controller = _mapController;
      if (controller == null) return;

      // 즉시 교체 임계 안에 준비된 전환(캐시된 층)은 페이드 없이 바로 보여
      // 준다 — 빠른 층 훑기에 페이드 잔상이 끌리지 않게. 계수가 이미 1이면
      // (첫 등록이라 은퇴 블록이 없던 경우) 페이드할 것도 없다.
      final animate =
          _indoorOverlayFadeFactor < 1 &&
          elapsed.elapsed >= floorSwitchInstantSwapThreshold;
      if (animate) {
        final stepInterval = crossfadeDuration ~/ floorSwitchCrossfadeSteps;
        for (var step = 1; step <= floorSwitchCrossfadeSteps; step++) {
          _indoorOverlayFadeFactor = Curves.easeOut.transform(
            step / floorSwitchCrossfadeSteps,
          );
          await _applyOverlayFillFadeFactor(controller);
          if (step < floorSwitchCrossfadeSteps) {
            await Future<void>.delayed(stepInterval);
          }
          if (!mounted || _indoorIds.generation != generation) return;
        }
      }
      // 최종 상태: 계수 1로 전체 레이어(심볼 포함)를 원래 불투명도로 되돌린다.
      // 심볼(라벨·아이콘)은 단계 페이드에서 뺐다 — 성긴 점 요소라 fill이 다
      // 올라온 끝에 한 번에 켜져도 팝이 안 읽히고, 단계마다 보내는 전체 속성
      // 교체(플랫폼 채널 호출)를 절반으로 줄인다.
      _indoorOverlayFadeFactor = 1;
      await _syncIndoorOverlayFade();
      if (!mounted || _indoorIds.generation != generation) return;
      // 새 도면이 완전히 올라왔으니 이전 층 블록(연타로 쌓인 것 포함)을 지운다.
      await _removeRetiringIndoorBlocks(controller);
      // 그리고 **지도에 직접 물어** 우리 장부에 없는 이전 세대까지 쓸어 담는다.
      // 위 목록은 이 함수가 중간에 물러난 전환의 블록을 담고 있지 않다.
      await purgeStaleIndoorOverlay(
        controller,
        keepGeneration: _indoorIds.generation,
      );
      await _syncFloorBoundaryToActiveFloor();
    } finally {
      if (progressToken != null) {
        _floorSwitchProgress.finish(progressToken);
      }
    }
  }

  /// 층 경계 둘(외곽선·dim scrim 구멍)을 지금 층 것으로 맞춘다.
  ///
  /// **층을 바꾸면 둘 다 낡는다.** 전환 초입에서 외곽선은 지우지만(틀린 경계를
  /// 보여주지 않으려고) 다시 그리는 곳이 없었고, 스크림 구멍은 아예 손대지 않아
  /// 이전 층 링에 머물렀다. 스크림은 구멍 **밖**을 어둡게 하는 층이라, 구멍이 이전
  /// 층(더 넓은 지하) 링이면 새 층 도면 밖인데도 어두워지지 않는 영역이 남는다 —
  /// 화면에서는 도로 위에 매장이 하나 더 있는 것처럼 밝은 띠로 보인다.
  ///
  /// 부르는 자리는 **새 도면이 다 올라온 뒤**다. 크로스페이드 중에 구멍을 새 층
  /// 것으로 좁히면 아직 보이고 있는 이전 도면이 그만큼 어두워진다.
  Future<void> _syncFloorBoundaryToActiveFloor() async {
    await _syncFloorOutlineLayer();
    await _syncDimScrimGeometry();
  }

  /// 크로스페이드 뒤에 남은 이전 층 소스·레이어 묶음을 전부 지운다. 이미 없는
  /// 레이어에 removeLayer가 예외를 던지는 native 구현이 있어 각각 삼킨다.
  Future<void> _removeRetiringIndoorBlocks(
    MapLibreMapController controller,
  ) async {
    while (_retiringIndoorBlocks.isNotEmpty) {
      final block = _retiringIndoorBlocks.removeLast();
      for (final id in block.layerIds) {
        try {
          await controller.removeLayer(id);
        } catch (_) {}
      }
      try {
        await controller.removeSource(block.sourceId);
      } catch (_) {}
    }
  }

  /// 크로스페이드 단계마다 현재 계수([_indoorOverlayFadeFactor])를 fill 레이어
  /// 4종에 적용한다.
  Future<void> _applyOverlayFillFadeFactor(MapLibreMapController controller) {
    return syncIndoorOverlayProps(
      controller,
      ids: _indoorIds,
      fadeExpr: _overlayFadeExpr(),
      categorySelection: widget.categorySelection,
      devicePixelRatio: _devicePixelRatio,
      symbolSortKey: _storeLabelSortKeyExpression(),
      scope: IndoorOverlaySyncScope.fills,
    );
  }
}
