// ignore_for_file: invalid_use_of_protected_member
//
// part라 `setState`(protected) 호출이 경고로 잡힌다.
/// `OutdoorMapBodyState`의 **엘리베이터 층 이동** 부분.
///
/// 에스컬레이터와 파일을 가른 이유는 판정 근거가 달라서다. 걸음 정지만 한
/// 플래그를 공유하며, 그 근거는 [OutdoorMapElevator._resumeStepsAfterRide]에 있다.
part of '../outdoor_map_screen.dart';

extension OutdoorMapElevator on OutdoorMapBodyState {
  /// 판정기에 지금 층·그래프·건물을 알린다.
  ///
  /// 기압은 걸음과 무관하게 흐르므로 위치 갱신과 기압 양쪽에서 부른다. 층이
  /// 바뀌면 판정기가 스스로 탑승 상태를 접으므로([ElevatorTransitionDetector]),
  /// 여기서 따로 지울 것은 없다.
  void _syncElevatorContext() {
    _elevator.updateContext(
      floorLabel: _elevatorJudgementFloor,
      // 그래프는 **판정 층과 표시 층이 같을 때만** 넘긴다. 다른 층 도면의 노드
      // 좌표로는 근접을 잴 수 없고, 넘기면 판정기가 남의 층 엘리베이터에
      // 무장한다. 빈 노드 목록은 `onPosition`이 알아서 넘긴다.
      graph: _elevatorJudgementFloor == _activeFloor ? _floorGraph : null,
      buildingId: _building?.id,
      servedFloorsByCar: _elevatorServedFloorsByCar(),
    );
  }

  /// 판정기가 "지금 몇 층인가"로 읽어야 하는 층.
  ///
  /// **표시 층이 아니라 몸이 서 있는 층(앵커 층)이다.** 층 선택기로 다른 층을
  /// 훑는 것은 정상 사용인데(`parts/pdr.dart`의 `_viewingOtherFloor`), 표시 층을
  /// 넘기면 훑을 때마다 판정기가 "층이 바뀌었다"로 읽고 무장을 통째로 버렸다 —
  /// 승강장 앞에서 다른 층을 한 번 펴 본 사람은 엘리베이터를 타도 아무것도
  /// 안 잡혔다.
  ///
  /// 활강 중에는 도착 층 도면을 **미리** 열어 두므로 표시 층이 도착 층이고,
  /// 앵커는 확정 뒤에야 옮겨진다. 그래서 탄 층을 못 박은 값이 1순위다.
  String? get _elevatorJudgementFloor {
    final anchorFloor = _pdrTrailState.anchor?.floorId;
    return _elevatorRideFromFloor ??
        (anchorFloor == null || anchorFloor.isEmpty
            ? _activeFloor
            : anchorFloor);
  }

  /// 호기별 정차 층. 건물 전체 그래프가 바뀔 때만 다시 센다.
  ///
  /// 없으면 null이고, 판정기는 그걸 "후보를 좁히지 마라"로 읽는다. 층별 그래프의
  /// 노드는 `floorId`가 비어 있어 층을 셀 수 없다 — 건물 전체 그래프가 필요하다.
  Map<String, Set<String>>? _elevatorServedFloorsByCar() {
    final graph = _journeyBuildingGraph;
    if (graph == null) return null;
    if (identical(graph, _elevatorServedFloorsSource)) {
      return _elevatorServedFloors;
    }
    _elevatorServedFloorsSource = graph;
    _elevatorServedFloors = elevatorServedFloorsByCar(
      nodes: graph.nodes,
      floorLabelOf: (node) => graph.floorNamesById[node.floorId],
    );
    return _elevatorServedFloors;
  }

  /// 보정된 현재 위치를 판정기에 먹인다. 원시 PDR 좌표가 아니라 **복도 보정을
  /// 거친 위치**여야 엘리베이터 노드 근접이 앵커 오차만큼 어긋나지 않는다.
  void _feedElevatorPosition(
    CorridorTrackingResult result,
    PdrSnapshot? snapshot,
  ) {
    _syncElevatorContext();
    final steps = snapshot?.steps ?? 0;
    final atMs = DateTime.now().millisecondsSinceEpoch;
    _elevator.onPosition(
      positionM: result.correctedPosition,
      steps: steps,
      timestampMs: atMs,
    );

    // 안내가 이 층에서 엘리베이터로 갈아타라고 했으면, 경로가 지목한 탑승 노드와
    // **도착 층**을 함께 알린다. 도착 층은 판정기의 1순위 근거다 — 고도표가 없는
    // 건물에서 층을 바꿀 수 있는 유일한 길이기도 하다.
    final transfer = _activeElevatorTransfer();
    final route = transfer?.segment.route;
    if (transfer != null && route != null && route.pointsLocalM.isNotEmpty) {
      final routeEnd = route.pointsLocalM.last;
      _elevator.onElevatorRouteApproach(
        positionM: result.previewPosition,
        routeEndM: PdrLocalPoint(routeEnd.x, routeEnd.y),
        expectedBoardingNodeId: transfer.segment.transferFromNodeId!,
        targetFloorLabel: transfer.nextFloorLabel,
        steps: steps,
        timestampMs: atMs,
      );
    }
    _handleElevatorPhaseChanges();
  }

  /// 지금 층 세그먼트에 붙은 **엘리베이터** 환승. 없으면 null.
  ({IndoorRouteSegment segment, String nextFloorLabel})?
  _activeElevatorTransfer() {
    final multi = _indoorMultiFloorRoute;
    final floor = _activeFloor;
    if (multi == null || floor == null) return null;
    final i = multi.segments.indexWhere((s) => s.floorName == floor);
    if (i < 0 || i + 1 >= multi.segments.length) return null;
    final segment = multi.segments[i];
    if (segment.transferModeToNext != 'elevator') return null;
    if (segment.transferFromNodeId == null) return null;
    return (segment: segment, nextFloorLabel: multi.segments[i + 1].floorName);
  }

  /// 기압 샘플 한 건을 판정기에 넣는다. [_onAltitudeSample]에서만 부른다.
  ///
  /// 반환값(층까지 정해진 확정)과 단계 전이는 **하는 일이 다르다.** 반환값은
  /// 도면 교체를 큐에 넣고, 단계 전이는 걸음 정지·재개를 건다. 층을 못 정한
  /// 확정은 반환값이 null이라 단계 전이 쪽만 지나간다.
  void _onElevatorAltitude(AltitudeSample sample) {
    _syncElevatorContext();
    final transition = _elevator.onAltitude(sample);
    // 단계 전이를 **먼저** 옮긴다. riding이 활강을 걸고, 그 다음 줄이 방금 들어온
    // 샘플로 진행률을 갱신한다 — 순서가 바뀌면 첫 샘플 한 건을 흘린다.
    _handleElevatorPhaseChanges();
    _syncElevatorRideDirection();
    _advanceElevatorGlide();
    if (transition != null) {
      _enqueueFloorTransition(() => _completeElevatorTransition(transition));
    }
  }

  /// 판정기의 단계 전이를 화면 동작으로 옮긴다.
  ///
  /// `settled`에서는 아무것도 안 한다 — 남이 눌러서 선 층일 수 있어 판정기가
  /// 확정을 미루는 구간이고, 걸음은 계속 멈춰 있어야 한다. **배너도 그대로
  /// 둔다.** 중간 정차마다 문구를 바꾸면 한 번 타는 동안 배너가 여러 번
  /// 깜빡이는데, 정작 그 사람은 문이 열리는 것을 눈으로 이미 보고 있다.
  void _handleElevatorPhaseChanges() {
    final changes = _elevator.takePhaseChanges();
    if (changes.isEmpty) return;
    for (final change in changes) {
      switch (change.phase) {
        case ElevatorPhase.riding:
          _enqueueFloorTransition(_pauseStepsForRide);
          _beginElevatorGlide(change);
          _beginElevatorBanner(change);
        case ElevatorPhase.confirmed:
          // 층까지 정해진 확정은 [_onElevatorAltitude]의 반환값이 맡는다.
          // 여기서 또 큐에 넣으면 도면을 두 번 갈아 끼운다.
          if (change.transition == null) {
            _enqueueFloorTransition(_endElevatorRideWithoutFloor);
          }
        case ElevatorPhase.cancelled:
          _enqueueFloorTransition(_endElevatorRide);
        case ElevatorPhase.idle:
        case ElevatorPhase.armed:
        case ElevatorPhase.settled:
          break;
      }
    }
  }

  /// 탑승 배너를 띄운다. 층 라벨은 판정기가 준 것을 그대로 쓴다 — 경로가 없으면
  /// 도착 층이 null이고, 그때 배너는 방향만 적는다([FloorTransitionUiState]).
  void _beginElevatorBanner(ElevatorPhaseChange change) {
    if (!mounted) return;
    setState(() {
      _elevatorRideStage = change;
      _elevatorRideGoingUp = elevatorRideGoingUp(
        measuredDeltaM: _elevator.deltaM,
        fromFloorLabel: change.fromFloorLabel,
        toFloorLabel: change.toFloorLabel,
      );
    });
  }

  /// 배너에 적을 방향을 방금 들어온 샘플로 다시 잰다.
  ///
  /// **부호가 바뀔 때만 알린다.** 매 샘플 setState를 돌리면 지도가 초당 몇 번씩
  /// 다시 그려진다. 못 정한 결과(null)로는 덮지 않는다 — Δ가 baseline 쪽으로
  /// 잠깐 돌아오는 것만으로 이미 띄운 배너가 사라지면 안 된다.
  void _syncElevatorRideDirection() {
    final stage = _elevatorRideStage;
    if (stage == null || !mounted) return;
    final goingUp = elevatorRideGoingUp(
      measuredDeltaM: _elevator.deltaM,
      fromFloorLabel: stage.fromFloorLabel,
      toFloorLabel: stage.toFloorLabel,
    );
    if (goingUp == null || goingUp == _elevatorRideGoingUp) return;
    setState(() => _elevatorRideGoingUp = goingUp);
  }

  /// 지금 엘리베이터가 쓰고 있는 안내 배너 상태. 안 타고 있으면 null.
  ///
  /// 방향을 못 정한 동안에도 null이다. 탑승 직후 1~2초가 그런데, 그 사이에
  /// 반대로 적었다가 뒤집는 것보다 조금 늦게 뜨는 편이 낫다.
  FloorTransitionUiState? get _elevatorTransitionUiState {
    final stage = _elevatorRideStage;
    final goingUp = _elevatorRideGoingUp;
    if (stage == null || goingUp == null) return null;
    return FloorTransitionUiState.elevatorRiding(
      fromFloorLabel: stage.fromFloorLabel,
      toFloorLabel: stage.toFloorLabel,
      goingUp: goingUp,
    );
  }

  /// 확정이 났는데 **도착 층을 못 정했다**(고도표도 경로도 없는 건물).
  ///
  /// 층을 안 바꾸는 것이 맞다 — 층고 상수로 찍으면 엘리베이터는 여러 층을 한 번에
  /// 가므로 맞을 때보다 틀릴 때가 많다. 대신 조용히 넘어가지 않는다. 아무 일도
  /// 안 일어나면 사용자는 "고장"으로 읽고, 층을 직접 고를 생각을 못 한다.
  Future<void> _endElevatorRideWithoutFloor() async {
    await _endElevatorRide();
    if (!mounted) return;
    _showSnack('내리신 층을 알 수 없습니다. 위쪽 층 버튼에서 직접 골라주세요.');
  }

  /// 탈것을 가리지 않고 **진행 중인 탑승을 전부** 끝낸다.
  ///
  /// "무슨 일이 있었는지 모르지만 정리해야 한다"는 자리가 부르는 문이다 —
  /// 층 전환 큐의 예외 복구와 야외 이탈. 그런 자리에서 탈것을 하나씩 나열하면
  /// 새 탈것이 생길 때마다 반드시 한 곳을 빠뜨리고, 빠뜨린 탈것의 활강이 남아
  /// `_pdrCurrentWgs84()`가 영영 그 점을 돌려준다(= 마커가 고정된다).
  /// 걸음 재개를 [_resumeStepsAfterRide] 하나로 모은 것과 같은 이유다.
  Future<void> _endAnyRide() async {
    await _endEscalatorRide();
    await _endElevatorRide();
  }

  /// 탑승 상태를 끝낸다. **확정·취소·화면 종료 모든 출구가 여기를 지난다.**
  Future<void> _endElevatorRide() async {
    await _revertElevatorMapSwap();
    if (mounted && (_floorSwapVeil != 0 || _elevatorRideStage != null)) {
      _floorSwapVeilTimer?.cancel();
      _floorSwapVeilTimer = null;
      setState(() {
        _floorSwapVeil = 0;
        // 배너가 사라지는 자리는 여기 하나다. 확정·취소·세션 재시작이 모두 이
        // 문을 지나므로, 갈래마다 지우면 반드시 한 곳을 빠뜨린다.
        _elevatorRideStage = null;
        _elevatorRideGoingUp = null;
      });
    }
    _stopElevatorGlide();
    await _resumeStepsAfterRide();
  }

  /// 이번 탑승의 활강을 건다. 걸 수 있는지는 [planElevatorGlide]가 정한다.
  ///
  /// **한 번 타는 동안 한 번뿐이다.** 남의 층에 섰다가 다시 가면 판정기가 riding을
  /// 다시 내는데(`resumedRiding`), 그때 새로 걸면 B1→5F 한 번이 층마다 끊긴
  /// 여러 번이 된다. 이미 걸려 있으면 그대로 둔다 — 분모는 처음부터 총 Δ라
  /// 중간 정차를 다시 셀 이유가 없다.
  void _beginElevatorGlide(ElevatorPhaseChange change) {
    if (_elevatorGlide != null) return;
    // 에스컬레이터가 이미 흐르고 있으면 걸지 않는다. `_pdrCurrentWgs84()`가
    // 에스컬레이터를 먼저 보므로 이쪽은 **화면에 안 보이는 채로** 진행률만 돌고,
    // 도면 교체는 둘이 각각 큐에 밀어 서로 덮는다.
    if (_escalatorGlide != null || _escalatorRide != null) return;
    final transfer = _activeElevatorTransfer();
    final plan = planElevatorGlide(
      table: floorAltitudeTableFor(_building?.id),
      fromFloor: change.fromFloorLabel,
      // 경로가 준 도착 층. 자유 보행이면 판정기도 null이라 활강을 안 건다.
      toFloor: change.toFloorLabel,
      transferPoints: transfer?.segment.transferPointsToNext ?? const [],
    );
    if (plan == null) return;
    _startElevatorGlide(plan);
  }

  /// 마커를 [ElevatorGlidePlan.glide] 위로 옮기고 틱을 돌린다.
  ///
  /// 진행률은 시간이 아니라 **기압**이 정한다([_advanceElevatorGlide]가 목표를
  /// 갱신). 여기 틱은 그 목표를 지수 평활로 따라갈 뿐이고, 끝(1.0)은 하차 확정만
  /// 채운다 — 점이 끝에 닿는 순간이 곧 실제 하차다.
  void _startElevatorGlide(ElevatorGlidePlan plan) {
    _elevatorGlideTimer?.cancel();
    _elevatorRideFromFloor = plan.fromFloor;
    _elevatorRideToFloor = plan.toFloor;
    _elevatorRideTotalGapM = plan.totalGapM;
    _elevatorRideTargetProgress = 0;
    _elevatorGlideProgress.value = 0;
    _elevatorGlide = plan.glide;
    _elevatorGlideTimer = Timer.periodic(_elevatorGlideFrame, (timer) {
      final glide = _elevatorGlide;
      if (!mounted || glide == null) {
        timer.cancel();
        return;
      }
      final value = _elevatorGlideProgress.value;
      final target = _elevatorRideTargetProgress;
      // 기압 샘플(0.18~1.07초 간격)을 그대로 그리면 점이 툭툭 끊긴다. 틱마다
      // 목표 쪽으로 지수 평활 — 시정수 약 0.5초.
      final next = (target - value).abs() < 0.002
          ? target
          : value + (target - value) * escalatorRideProgressEase;
      if (next != value) {
        _elevatorGlideProgress.value = next;
        unawaited(_syncPdrCurrentLayer());
      }
      // 하차 확정(목표 1.0)에 다 붙었으면 틱만 접는다. 활강 자체는 확정 절차가
      // 끝날 때까지 살려 둬야 마커가 그 자리를 지킨다.
      if (target >= 1 && next >= 1) timer.cancel();
    });
    unawaited(_syncPdrCurrentLayer());
  }

  /// 방금 들어온 기압 샘플로 진행률 목표를 올리고, 절반을 지났으면 도면을 연다.
  ///
  /// 단조 증가만 허용한다 — 평활 노이즈로 점이 뒤로 가지 않는다.
  void _advanceElevatorGlide() {
    if (_elevatorGlide == null) return;
    final deltaM = _elevator.deltaM;
    if (deltaM == null) return;
    final totalGapM = _elevatorRideTotalGapM;
    final sign = totalGapM >= 0 ? 1.0 : -1.0;
    _elevatorRideTargetProgress = math.max(
      _elevatorRideTargetProgress,
      elevatorRideProgressTarget(
        deltaTowardsM: deltaM * sign,
        totalGapM: totalGapM,
      ),
    );
    if (_elevatorMapSwapped) return;
    if (_elevatorRideTargetProgress < elevatorMapSwapProgress) return;
    _elevatorMapSwapped = true;
    _enqueueFloorTransition(_swapMapForElevatorGlide);
  }

  /// 총 Δ의 절반을 지났다. 하차 전에 도착 층 도면을 연다([elevatorMapSwapProgress]).
  ///
  /// **앵커도 경로도 건드리지 않는다.** 아직 확정이 아니라 되돌릴 수 있어야 하고,
  /// 마커는 활강이 들고 있어서 도면만 갈아 끼워도 화면이 이어진다.
  Future<void> _swapMapForElevatorGlide() async {
    if (_applyingFloorTransition || _elevatorGlide == null) return;
    final floor = _elevatorRideToFloor;
    if (floor == null || !mounted || _activeFloor == floor) return;
    if (!(_building?.floors.contains(floor) ?? false)) return;

    _applyingFloorTransition = true;
    try {
      // 층을 바꾸기 **전에** 탄 층의 완료 구간을 떠 둔다. 새 그래프가 오면
      // 덮어써져서 회색선이 사라진다. 승격은 확정이 났을 때만 한다.
      final completion = _currentIndoorCompletionSnapshot();
      _pendingTransferCompletedScope = completion?.scopeId;
      _pendingTransferCompleted = completion?.points;
      if (!await _swapIndoorFloorForElevator(floor)) return;
      if (!mounted) return;
      // 덮개는 예약해서 내린다. 걷히면 사용자는 남은 절반을 새 층 도면과 다음
      // 경로를 보며 올라간다. 붙잡는 시간은 도착 층 사진 장수가 정한다.
      _floorSwapVeilTimer?.cancel();
      _floorSwapVeilTimer = Timer(
        floorTransitionScrimHold(floorConceptPhotos(floor).length),
        () {
          _floorSwapVeilTimer = null;
          if (!mounted) return;
          setState(() => _floorSwapVeil = 0);
        },
      );
    } finally {
      _applyingFloorTransition = false;
    }
  }

  /// 미리 갈아 끼운 도면을 탄 층으로 되돌린다. 확정이 넘겨받았으면 아무 일도 안 한다.
  ///
  /// 되돌릴 상황은 취소와 "층을 못 정한 확정" 둘이다. 그대로 두면 사용자는 자기가
  /// 가지도 않은 층 도면 위에 서 있게 된다. 사람 조작과 같은 크로스페이드를 쓴다 —
  /// 없던 일로 만드는 전환이라 안내 전환처럼 늦출 이유가 없다.
  Future<void> _revertElevatorMapSwap() async {
    if (!_elevatorMapSwapped) return;
    _elevatorMapSwapped = false;
    _discardPendingTransferCompletion();
    final floor = _elevatorRideFromFloor;
    if (floor == null || !mounted || _activeFloor == floor) return;
    if (!(_building?.floors.contains(floor) ?? false)) return;
    await _switchOverlayFloorCrossfaded(floor);
  }

  void _stopElevatorGlide() {
    _elevatorGlideTimer?.cancel();
    _elevatorGlideTimer = null;
    _elevatorRideTargetProgress = 0;
    _elevatorRideTotalGapM = 0;
    _elevatorRideFromFloor = null;
    _elevatorRideToFloor = null;
    if (_elevatorGlide == null) return;
    _elevatorGlide = null;
    _elevatorGlideProgress.value = 0;
    unawaited(_syncPdrCurrentLayer());
  }

  /// PDR 세션을 새로 열 때 판정기를 비운다.
  ///
  /// 층 전이 판정은 **연속된 기압 시계열**을 전제로 한다. 세션이 끊긴 자리의
  /// 고도차는 근거가 못 되고, 무엇보다 타는 중으로 남은 판정기는 걸음 재개를
  /// 영영 막는다([_resumeStepsAfterRide]).
  void _resetElevatorForNewSession() {
    _elevator.reset(atMs: DateTime.now().millisecondsSinceEpoch);
    _elevator.takePhaseChanges();
    unawaited(_endElevatorRide());
  }

  /// 걸음 재개의 **단일 출구.**
  ///
  /// 두 판정기가 플래그([_stepsPausedForRide]) 하나를 공유하는 이유가 여기 있다.
  /// 드라이버의 pause/resume은 횟수를 세지 않으므로, 플래그를 둘로 나눠도 먼저
  /// 끝난 쪽이 `resumeStepTracking()`을 부르면 아직 타는 중인 쪽까지 걸음이
  /// 흐른다 — 플래그만 늘고 증상은 그대로다. 대신 **아직 타는 중인 판정기가
  /// 하나라도 있으면 안 푼다.** 화면의 `dispose`도 갈래 하나로 끝난다.
  Future<void> _resumeStepsAfterRide() async {
    if (!_stepsPausedForRide) return;
    // 화면이 닫히는 중이면 어느 판정도 더 진행하지 않는다. 무조건 푼다 —
    // 걸음이 멈춘 채 남은 전역 PDR 세션은 사용자가 복구할 방법이 없다.
    if (mounted && _anyRideStillHoldsSteps) return;
    _stepsPausedForRide = false;
    await indoorNavigationDriver.resumeStepTracking();
  }

  /// 아직 걸음을 붙들고 있는 판정이 있는가. 부르는 쪽은 **자기 탑승 상태를 먼저
  /// 비운 뒤에** 물어야 한다(안 그러면 자기 자신 때문에 영영 참이다).
  bool get _anyRideStillHoldsSteps =>
      _elevator.pausesStepTracking ||
      _escalatorRide != null ||
      _escalatorStage?.phase == EscalatorPhase.verticalMotionDetected;

  /// 확정이 났다. 목표 층 도면으로 갈아 끼우고 도착 호기에 앵커를 다시 찍는다.
  ///
  /// 도면은 보통 활강이 절반에서 이미 열어 뒀다([_swapMapForElevatorGlide]).
  /// 여기서 다시 여는 경우는 둘뿐이다 — 활강을 못 건 탑승(경로도 고도표도
  /// 없다), 그리고 확정된 층이 경로가 말한 층과 다른 경우다.
  Future<void> _completeElevatorTransition(
    ElevatorTransition transition,
  ) async {
    if (_applyingFloorTransition) return;
    final floor = transition.toFloorLabel;
    if (!(_building?.floors.contains(floor) ?? false)) {
      await _endElevatorRide();
      if (mounted) _showSnack('$floor 지도를 불러오지 못했습니다. 현재 층을 유지합니다.');
      return;
    }

    _applyingFloorTransition = true;
    try {
      // 하차가 확정됐다 — 진행률 1.0은 오직 여기서 채워진다. 표시값은 틱마다
      // 따라붙어(시정수 0.5초) 마커가 도착 노드에 부드럽게 닿는다.
      _elevatorRideTargetProgress = 1;
      // 층을 바꾸기 **전에** 현재 층의 완료 구간을 떠 둔다. 새 그래프가 오면
      // 덮어써져서 회색선이 사라진다. 활강이 도면을 먼저 열었으면 그때 떠 둔
      // 것이 탄 층의 것이라, 여기서 다시 뜨면 도착 층 것으로 덮인다.
      if (_pendingTransferCompleted == null) {
        final completion = _currentIndoorCompletionSnapshot();
        _pendingTransferCompletedScope = completion?.scopeId;
        _pendingTransferCompleted = completion?.points;
      }

      if (!await _swapIndoorFloorForElevator(floor)) {
        _discardPendingTransferCompletion();
        await _endElevatorRide();
        if (mounted) _showSnack('$floor 지도를 불러오지 못했습니다. 현재 층을 유지합니다.');
        return;
      }
      // 미리 갈아 끼운 도면을 이 확정이 넘겨받았다. 되돌릴 대상이 아니다.
      _elevatorMapSwapped = false;

      final graph = _floorGraph;
      // 도착 노드는 **좌표가 아니라 호기 이름**으로 찾는다. 층 도면의 등록 오차
      // 때문에 같은 샤프트가 층마다 십수 미터 어긋나 있다([findElevatorArrivalNode]).
      final arrival = findElevatorArrivalNode(
        graph: graph,
        carName: transition.carName,
      );
      if (graph == null || arrival == null) {
        _discardPendingTransferCompletion();
        // 도착 지점을 못 찾아도 **탑승 상태는 반드시 끝낸다.**
        await _endElevatorRide();
        if (!mounted) return;
        _showSnack('$floor 도착 지점을 찾지 못했습니다. 하단 "위치 지정"으로 현재 위치를 찍어주세요.');
        return;
      }

      setState(() {
        // 이전 층 궤적과 복도 보정 상태는 새 층에서 이어지지 않는다.
        _pdrTrailState.beginNewSession();
        _guidance.resetTracking();
      });
      await indoorNavigationDriver.applyVerticalTransfer(
        floorId: floor,
        anchorLocalM: PdrLocalPoint(arrival.xM, arrival.yM),
        axes: fitPdrToFloorAxes(graph.nodes),
      );
      if (!mounted) return;
      // 걸음 재개는 applyVerticalTransfer가 경로 원점을 옮긴 **뒤에** 한다.
      // 먼저 켜면 탑승 중 걸음이 새 층 원점에 붙는다.
      await _endElevatorRide();
      if (!mounted) return;
      _commitPendingTransferCompletion();

      await _rerouteAfterVerticalTransfer(
        arrivalNodeId: arrival.id,
        floor: floor,
      );
    } finally {
      _applyingFloorTransition = false;
    }
  }

  /// 도면을 목표 층으로 갈아 끼운다. 성공하면 true.
  ///
  /// 덮개가 다 올라온 **뒤에** 교체한다 — 어긋나면 아직 덜 덮인 화면에서 도면이
  /// 바뀌는 장면이 그대로 보인다. 덮개는 재앵커까지 끝난 [_endElevatorRide]가
  /// 걷는다. 타이머로 늦추지 않는 것은 확정이 곧 하차라, 에스컬레이터처럼
  /// "내리기 전에 새 층을 봐 둘" 시간이 필요 없기 때문이다.
  Future<bool> _swapIndoorFloorForElevator(String floor) async {
    // 활강이 이미 이 층을 열어 뒀으면 덮을 것이 없다. 덮개를 다시 올리면 하차
    // 순간 화면이 까닭 없이 한 번 깜빡인다.
    if (_activeFloor == floor) return true;
    setState(() => _floorSwapVeil = 1);
    await Future<void>.delayed(floorTransitionScrimFadeIn);
    if (!mounted) return false;
    await _switchOverlayFloorCrossfaded(
      floor,
      recenterIfNeeded: false,
      crossfadeDuration: floorSwitchGuidedCrossfadeDuration,
    );
    return mounted && _activeFloor == floor;
  }

  /// 확정이 났을 때 화면이 하는 일 전부. 실기기에서는 [_onAltitudeSample]이
  /// 판정기에서 받아 이 자리를 지나는데, 기압 시계열은 플랫폼 이벤트 채널로만
  /// 들어와 위젯 테스트의 가짜 시계로는 흘릴 수 없다.
  @visibleForTesting
  Future<void> applyElevatorTransitionForTest(ElevatorTransition transition) =>
      _completeElevatorTransition(transition);

  /// 판정기가 `riding`을 낸 뒤의 배선을 위젯 테스트에서 태운다. 활강을 걸지 말지
  /// 고르는 갈래까지 그대로 지난다([_beginElevatorGlide]).
  @visibleForTesting
  void beginElevatorGlideForTest(ElevatorPhaseChange change) =>
      _beginElevatorGlide(change);

  /// 계획이 이미 정해진 활강을 태운다. 타이머가 실제로 도는 상태를 만드는 자리다.
  @visibleForTesting
  void startElevatorGlideForTest(ElevatorGlidePlan plan) =>
      _startElevatorGlide(plan);

  /// 지금 엘리베이터 활강이 걸려 있는가.
  @visibleForTesting
  bool get elevatorGlideActive => _elevatorGlide != null;

  /// 화면이 들고 있는 판정기. **배선을 재는 자리다** — 판정기 단위 테스트는
  /// 메서드를 직접 불러서 "그 메서드를 실기기에서 부르는 사람이 없다"를 못 본다.
  @visibleForTesting
  ElevatorTransitionDetector get elevatorDetectorForTest => _elevator;

  /// 판정기에 층·그래프를 알리는 자리를 위젯 테스트가 직접 태운다. 실기기에서는
  /// 위치 갱신과 기압 샘플이 매번 지나는 길이다.
  @visibleForTesting
  void syncElevatorContextForTest() => _syncElevatorContext();

  /// 판정기가 지금 "몇 층인가"로 읽는 층. 표시 층과 갈리는지를 본다.
  @visibleForTesting
  String? get elevatorJudgementFloorForTest => _elevatorJudgementFloor;

  /// 탈것을 가리지 않는 정리 출구([_endAnyRide]).
  @visibleForTesting
  Future<void> endAnyRideForTest() => _endAnyRide();

  /// 판정기의 단계 전이 배선을 위젯 테스트에서 태운다. 기압 시계열은 플랫폼
  /// 이벤트 채널로만 들어와 가짜 시계로는 흘릴 수 없어, 단계만 직접 넣는다.
  @visibleForTesting
  void beginElevatorBannerForTest(ElevatorPhaseChange change) =>
      _beginElevatorBanner(change);

  /// 탑승을 끝내는 공통 출구를 위젯 테스트에서 태운다.
  @visibleForTesting
  Future<void> endElevatorRideForTest() => _endElevatorRide();
}
