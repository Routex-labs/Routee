// ignore_for_file: invalid_use_of_protected_member
//
// part라 `setState`(protected) 호출이 경고로 잡힌다.
/// `OutdoorMapBodyState`의 **안내 진행·도착 판정** 부분.
///
/// part 규약과 이 파일로 가른 이유는 `docs/client/outdoor-map-moves.md`.
part of '../outdoor_map_screen.dart';

extension OutdoorMapGuidance on OutdoorMapBodyState {
  /// 사용자가 **직접 고른** 목적지로 안내 중인지. 안내 chrome(검색창·카테고리
  /// 줄·하단 바)을 접을지의 판정 기준이다. **층 선택기만 한 발 먼저 접는다** —
  /// [_guidancePlanned].
  ///
  /// 판정 규칙과 그렇게 나눈 이유는 [shouldFoldGuidanceChrome]에 있다. 요약하면
  /// **접는 조건은 종료 버튼이 있는 조건과 같아야 한다** — 아래 ETA 카드 두
  /// 분기가 `onClose`를 다는 조건과 이 getter가 정확히 맞물려야 하고, 어느
  /// 한쪽을 고치면 그 함수를 통해 다른 쪽도 같이 바뀐다.
  ///
  /// **도착 카드가 떠 있는 동안은 여정이 아직 안 끝났다.** 도착 몇 초 뒤 경로는
  /// 스스로 지워지는데([_syncArrival]), 그것만으로 접기를 풀면 방금 도착한 화면
  /// 위쪽에 출발/도착 두 칸이 되살아난다 — 끝난 길찾기를 다시 시키는 그림이다.
  /// 여기서도 규칙은 그대로다: 그때 종료 버튼은 도착 카드가 들고 있다.
  bool get _guidanceActive =>
      _arrivedDestination != null || (_guidanceStarted && _guidancePlanned);

  /// 하단에 **"안내 시작" 카드가 떠 있는지.** [_guidanceActive]에서 "이미
  /// 시작했는가"만 뺀 값이라, 시작 버튼을 누르기 전부터 참이다.
  ///
  /// 층 선택기는 이 시점부터 접는다. 카드가 뜬 뒤로 층은 사용자가 고르는 것이
  /// 아니라 경로가 정하고, 사용자는 "이쪽으로 가면 되는구나"를 가리는 것 없이
  /// 봐야 한다.
  ///
  /// **목적지 없이 자동으로 그린 걷기 경로는 여기 안 든다** — 그 카드에는
  /// 애초에 "안내 시작"이 없다([shouldFoldGuidanceChrome]).
  bool get _guidancePlanned =>
      _transitItinerary != null ||
      shouldFoldGuidanceChrome(
        hasUserDestination: _userDestination != null,
        hasIndoorRouteDestination: _indoorRouteDestination != null,
        hasComputedRoute: _route != null,
      );

  void _notifyRouteStateIfChanged() {
    final visible = _hasAnyRouteVisible;
    if (visible != _lastRouteVisibleNotified) {
      _lastRouteVisibleNotified = visible;
      widget.onRouteVisibleChanged?.call(visible);
    }
    final guiding = _guidanceActive;
    if (guiding != _lastGuidanceActiveNotified) {
      _lastGuidanceActiveNotified = guiding;
      widget.onGuidanceActiveChanged?.call(guiding);
    }
  }

  /// 세션에 스냅샷을 넘기고, 나온 보정 결과를 로그에 남긴다.
  ///
  /// 층·그래프·앵커·경로는 세션이 들고 있으므로 여기서 다시 확인하지 않는다.
  /// 두 곳에서 같은 조건을 세면 반드시 한쪽이 먼저 낡는다.
  /// 실내 안내를 지금 건물에 붙인다.
  ///
  /// 진입 시점에 건물이 아직 로드되지 않았을 수 있다. 그때 빈 id로 붙여 두면
  /// GPS 추정점의 건물이 영원히 안 맞아 폴백 표시가 조용히 죽는다. 로드된 뒤
  /// 처음 오는 스냅샷에서 제대로 붙인다.
  void _ensureGuidanceAttached() {
    final buildingId = _building?.id;
    if (buildingId == null || _guidance.buildingId == buildingId) return;
    _guidance.attach(buildingId: buildingId);
  }

  /// 실내 경로 진행률을 갱신한다. 계산은 세션이, 다시 그리기는 여기가 한다.
  ///
  /// 홈에도 이게 필요한 이유는 ETA 카드 때문이다. 예전에는 경로 전체 길이를
  /// 고정으로 보여줘서, 목적지 앞에 서 있어도 출발할 때와 같은 거리가 떠 있었다.
  void _syncIndoorRouteProgress(
    CorridorTrackingResult? result,
    PdrSnapshot? snapshot,
  ) {
    if (!_indoorEntered) return;
    final anchor = _pdrTrailState.anchor;
    final toFloor = anchor == null ? null : FloorCoordinateTransform(anchor);
    final update = _guidance.updateProgress(
      result,
      rerouteInFlight: _indoorRerouteInFlight,
      confirmedSteps: snapshot?.steps,
      previewSteps: snapshot?.preview.steps,
      orientationHeadingDeg: snapshot == null || toFloor == null
          ? null
          : toFloor.toFloorBearing(snapshot.orientationHeadingDeg),
      walkingHeadingDeg: snapshot == null || toFloor == null
          ? null
          : toFloor.toFloorBearing(snapshot.walkingHeadingDeg),
      // 탑승 중에는 이탈 판정을 건너뛴다. 조기 층 전환이 탑승점 고정을 풀어
      // `isPositionHeld`가 먼저 false가 되므로, 이 인자가 없으면 리셋된
      // 트래커 위치로 이탈 증거가 쌓여 재탐색이 돈다.
      onEscalator: _escalatorRide != null,
    );
    for (final advance in update.stepAdvances) {
      _pdrDebugRecorder?.recordRouteStepAdvance(
        advance.step,
        transition: advance.transition,
      );
    }
    for (final event in update.checkpointEvents) {
      _pdrDebugRecorder?.recordCheckpointEvent(event);
    }
    final measured = update.measuredProgress;
    if (measured != null) {
      _pdrDebugRecorder?.recordRouteProgress(
        measured,
        displayProgress: update.displayProgress,
        holdReason: update.holdReason,
      );
    }
    if (update.shouldReroute &&
        DateTime.now().millisecondsSinceEpoch - _lastIndoorRerouteAtMs >=
            2000) {
      unawaited(_rerouteIndoorFromCurrentPosition());
    }
    if (mounted) setState(() {});
    _syncArrivalHighlight();
    _syncArrival();
  }

  /// 도착을 화면에 반영한다 — 도착 카드를 띄우고, 잠시 뒤 경로를 스스로 지운다.
  ///
  /// **도착을 말하는 것과 경로를 지우는 것은 조건이 다르다.** 바로 옆 매장은 걸어서
  /// 도착한 것이 아니라 애초에 가까운 것이라 경로를 자동으로 지우지 않지만, 도착한
  /// 사실은 그때도 말해야 한다. 둘을 한 조건에 묶어 뒀더니 그 경로에서는 도착을
  /// 말하는 것이 화면에 하나도 없었다.
  ///
  /// 지우는 쪽 판단은 [decideArrivalAutoClear]가 한다. 여기서 조건을 다시 세지 않는
  /// 이유는 "도착 상태에 들락날락하는 동안 카운트다운을 다시 걸지 않는다"는 규칙이
  /// 걸음마다 돌아가는 이 자리에서 제일 틀리기 쉽기 때문이다.
  void _syncArrival() {
    if (!mounted) return;

    // **문에 닿은 것은 도착이 아니다.** 나가는 여정의 실내 구간은 목적지가
    // 출구라([_guidanceLeavesBuilding]) 여기까지 걸으면 `arrived`가 뜬다. 그대로
    // 도착으로 말하면 하단 카드가 `안내 종료` 하나로 바뀌어, 정작 눌러야 할
    // "밖으로 나가기"가 사라진다(실기기 증상). 이 여정의 도착은 바깥 목적지다.
    if (_guidanceLeavesBuilding) {
      _arrivalRouteClearTimer?.cancel();
      _arrivalRouteClearTimer = null;
      return;
    }

    final destination = _indoorRouteDestination;
    if (_arrivedDestination == null &&
        shouldAnnounceArrival(
          action: _indoorRouteGuidance?.action,
          hasDestination: destination != null,
        )) {
      setState(() => _arrivedDestination = destination);
      // 도착 카드가 뜨는 것 자체가 접기 조건이다([_guidanceActive]). 안 알리면
      // 경로가 자동으로 지워지는 순간 셸이 chrome을 펴 버린다.
      _notifyRouteStateIfChanged();
    }

    final decision = decideArrivalAutoClear(
      action: _indoorRouteGuidance?.action,
      // 측정된 진행률이 없으면 "걸어서 도착"이 아니라 애초에 가까운 것이다.
      hasMeasuredProgress: _guidance.measuredProgress != null,
      alreadyScheduled: _arrivalRouteClearTimer != null,
    );
    switch (decision) {
      case ArrivalAutoClearDecision.keep:
        return;
      case ArrivalAutoClearDecision.cancel:
        // 도착 지점을 지나쳐 계속 걸어간 경우다. 카드는 **지우지 않는다** —
        // 한 번 "도착했습니다"라고 말해 놓고 조용히 거두면 사용자는 자기가
        // 잘못 본 줄 안다. 카드를 닫는 것은 사용자의 확인뿐이다.
        _arrivalRouteClearTimer?.cancel();
        _arrivalRouteClearTimer = null;
        return;
      case ArrivalAutoClearDecision.schedule:
        _arrivalRouteClearTimer = Timer(
          arrivalAutoClearDelay,
          clearRouteAfterArrival,
        );
    }
  }

  /// 도착 안내를 읽을 시간이 지난 뒤 경로·핀·하단 배너를 정리한다. 도착 카드는
  /// 남는다 — 그것이 지금 화면에서 유일하게 "끝났다"고 말하는 것이다.
  ///
  /// **안내 세션은 끝내지 않는다.** 끝내면 접어 뒀던 상단 chrome이 펴져 방금
  /// 지운 경로의 이동 수단 줄이 되살아나고(대중교통으로 왔으면 대중교통이 선택된
  /// 채 경로만 없다), 실내→야외 이음매에서는 출구에서 `안내 시작`이 다시 뜬다
  /// ([showRouteTo]의 continueGuidance). 세션을 끝내는 것은 도착 카드의
  /// `안내 종료`뿐이다([_confirmArrival]).
  ///
  /// 타이머 콜백을 이름 있는 자리로 뺀 것은 테스트가 PDR 없이 이 순간을 부를 수
  /// 있어야 하기 때문이다. **테스트 전용 뒷문이 아니라 실제 타이머가 부르는
  /// 자리**라 `...ForTest`를 붙이지 않는다.
  @visibleForTesting
  void clearRouteAfterArrival() {
    _arrivalRouteClearTimer = null;
    if (!mounted) return;
    _clearIndoorRoute(endGuidance: false);
  }

  /// GPS가 지금 이 사람을 **건물 밖이라고 분명히 말하는가.**
  ///
  /// 판정하지 못하는 경우(`unclear`)는 밖으로 치지 않는다. 실내에서는 GPS 오차가
  /// 커서 unclear가 흔하고, 거기서 막으면 **정작 건물 안에 있는 사람이 안내를
  /// 시작하지 못한다.** 막아야 할 것은 확실히 밖인 경우뿐이다.
  bool get _gpsSaysOutsideBuilding {
    final position = _position;
    if (position == null) return false;
    final judgement = judgeBuildingFromGps(
      fix: GpsFix(
        point: ll.LatLng(position.latitude, position.longitude),
        accuracyMeters: position.accuracy,
      ),
      footprint: _buildingFootprint,
    );
    return judgement.verdict == GpsBuildingVerdict.outside;
  }

  /// 지금 걸을 구간이 실내인 여정에서 **실제 안내를 시작한다.**
  ///
  /// [_indoorRoutePreviewOrigin]이 있으면 여기서야 그 출발지 매장에 앵커를
  /// 찍는다 — 미리 보는 동안 찍지 않는 이유는 그 값의 주석에 적었다(그 사람은
  /// 아직 거기 서 있지 않다). 없으면(지금 있는 곳에서 출발, 실내→야외 여정
  /// 포함) 이미 있는 PDR 앵커를 그대로 쓴다 — 앵커를 옮길 근거가 없다.
  ///
  /// **건물 밖에서 누르면 아무것도 바꾸지 않는다.** 앵커를 찍어 봐야 다음 GPS 틱이
  /// 곧바로 뒤집어 도면과 경로가 아무 말 없이 사라진다. 그래서 화면은 그대로 두고
  /// 언제 시작할 수 있는지만 말한다 — 보던 경로를 잃지 않는 것이 이 화면의 목적이다.
  ///
  /// **이미 실내로 들어와 있으면([_indoorEntered]) GPS는 보지 않는다.** 그
  /// 판정은 아직 걸어 들어오지 않은 사람(미리 보기)을 막으려는 것인데, 실내
  /// GPS는 문을 지나 들어온 사람에게도 얼마든지 "밖"이라고 말할 수 있다(신호
  /// 오차·직전 좌표가 아직 안 갱신됨). 이미 문 노드에 앵커를 찍고 들어와 있는
  /// 사실을 흔들리는 GPS 한 건이 뒤집으면 안 된다 — 실내→야외 여정에서
  /// "안내 시작"이 매번 거부되던 원인이 이것이다.
  Future<void> _startIndoorGuidance() async {
    if (!_indoorEntered && _gpsSaysOutsideBuilding) {
      _showSnack('건물에 도착하면 안내를 시작할 수 있습니다.');
      return;
    }
    final origin = _indoorRoutePreviewOrigin;
    setState(() {
      _indoorRoutePreviewOrigin = null;
      _guidanceStarted = true;
    });
    final floor = origin?.floor;
    final nodeId = origin?.nodeId;
    if (origin != null && nodeId != null && floor != null && floor.isNotEmpty) {
      await _anchorAtStoreOrigin(
        floor: floor,
        nodeId: nodeId,
        storePoint: origin.point,
        storeName: origin.name,
      );
      if (!mounted) return;
    }
    _notifyRouteStateIfChanged();
    if (!mounted) return;
    // 야외와 **같은 약속**이다 — 시작을 누르면 화면이 내 자리로 내려간다. 실내는
    // 걸음이 카메라를 끌고 가지만([_indoorFollowActive]) 그건 다음 걸음부터라,
    // 첫 걸음을 떼기 전까지는 경로 전체를 보던 화면 그대로 서 있었다.
    await _recenterOnCurrentPosition();
  }

  /// 안내 시작 판정에 쓸, 지금 지도에 그려진 야외 경로의 좌표열.
  ///
  /// 실내 경로만 살아 있으면 빈 목록이다 — 실내는 [_startIndoorGuidance]가
  /// 자기 가드를 이미 갖고 있어서 여기서 다시 막지 않는다.
  List<ll.LatLng> get _guidanceStartRoutePoints {
    final route = _route;
    if (route != null) return route.points;
    final transit = _transitItinerary;
    if (transit == null) return const [];
    return [for (final leg in transit.legs) ...leg.points];
  }

  /// 마지막으로 받은 GPS를 위경도로. 아직 못 받았으면 null이다.
  ll.LatLng? get _positionPoint {
    final position = _position;
    if (position == null) return null;
    return ll.LatLng(position.latitude, position.longitude);
  }

  /// 계획 카드의 `안내 시작`을 모든 이동수단에서 같은 상태 전이로 처리한다.
  ///
  /// **경로에서 멀면 아무것도 바꾸지 않는다.** 실내가 건물 밖에서 그렇게 하는
  /// 것과 같은 이유다([_startIndoorGuidance]) — 카메라를 GPS로 끌고 가 봐야
  /// 보던 경로가 화면에서 사라질 뿐이다. 도보도 함께 막는다. 카메라를 안 옮겨도
  /// 안내 상태로 들어가면 엉뚱한 위치에서 진행 판정이 돌기 시작한다.
  Future<void> _startCurrentGuidance() async {
    // 이번 안내는 팔로우를 켠 채로 시작한다. 지난 안내에서 지도를 만져 물려
    // 뒀던 것이 남으면, 새로 "안내 시작"을 눌러도 화면이 따라오지 않는다.
    _followCameraReleasedByUser = false;
    _followCameraBearingDeg = null;
    // 이 목록이 비었다는 것이 곧 "실내 구간만 살아 있다"이다([_guidanceStartRoutePoints]).
    final points = _guidanceStartRoutePoints;
    // **실내→야외 여정([showIndoorToOutdoorRouteTo])도 실내 갈래를 탄다.** 그
    // 함수는 문 밖 야외 구간을 "미리 보기"로 지금 함께 그려 두므로(`_route`가
    // 이미 채워진다), 위 `points.isEmpty`만으로는 걸리지 않는다. 그런데 그
    // 좌표열은 문에서 시작하는 미리 보기라, 아래 일반 갈래가 그 점들과 지금
    // 위치(건물 안 깊숙한 곳일 수 있다) 사이 거리를 재면 실내에 있는 사람은
    // 항상 "경로 근처가 아니다"로 막힌다.
    //
    // **`_indoorRouteDestination != null`만으로는 새는 자리가 있다** — 그 값은
    // 다른 실내 미리 보기가 남긴 낡은 값일 수 있고(`outdoor_to_indoor_guidance_
    // start_test.dart`가 그 자리를 지킨다), 그러면 정의상 밖에서 시작해야 하는
    // 문 경유 안내(실외 → 건물 안 매장)가 "건물에 도착하면…"에 거꾸로 막힌다.
    // 그래서 **지금 이 여정이 실내→야외라는 확실한 증거**
    // ([_pendingOutdoorDestination], 이 함수 하나만 세운다)까지 함께 본다.
    if ((points.isEmpty && _indoorRoutePreviewOrigin != null) ||
        (_indoorRouteDestination != null &&
            _pendingOutdoorDestination != null)) {
      await _startIndoorGuidance();
      return;
    }
    if (_guidanceStarted || !_hasAnyRouteVisible) return;
    // 좌표를 못 얻는 경로(실내 구간만 살아 있는 경우)에는 가드를 걸지 않는다.
    // 잴 수 없는 것을 막으면 지금 되던 흐름이 조용히 죽는다.
    if (points.length >= 2) {
      // 위치를 아직 못 받은 것과 경로에서 먼 것은 **다른 사건이다.** 둘 다 막지만
      // 문구를 같이 쓰면, GPS를 기다리는 중인 사용자가 경로를 잘못 잡았다고 읽고
      // 엉뚱한 곳을 고치러 간다.
      final position = _positionPoint;
      if (position == null) {
        _showSnack('현재 위치를 확인하는 중입니다.');
        return;
      }
      if (!canStartGuidanceFrom(
        routePoints: points,
        position: position,
        maxOffsetM: guidanceStartMaxOffsetM,
      )) {
        _showSnack('경로 근처에 있을 때 안내를 시작할 수 있습니다.');
        return;
      }
    }
    setState(() {
      _guidanceStarted = true;
    });
    _notifyRouteStateIfChanged();
    // **시작을 누른 순간 화면이 내 자리로 내려간다.** 계획 카드가 떠 있는 동안
    // 카메라는 경로 전체를 담으려고 물러서 있는데, 시작해도 그대로 두면 화면은
    // 여전히 "지도를 보고 있다"에 머문다 — 따라가야 할 화면이 아니다. 한동안
    // 자동차에만 걸려 있어서, 걷는 사람은 시작을 눌러도 아무 일도 안 일어났다.
    //
    // **대중교통만 뺀다.** 타고 가는 구간은 내가 걷는 것이 아니라, 카메라가 나를
    // 확대해 따라가면 여정 전체가 화면 귀퉁이로 밀린다
    // (`transit_guidance_does_not_follow_test.dart`).
    //
    // 배율이 갈리는 이유는 보는 거리가 달라서다 — 자동차는 다음 교차로가 화면에
    // 들어와야 하고, 걸을 때는 지금 서 있는 통로가 보여야 한다.
    // 방금까지는 경로 전체를 담으려 물러서 있던 배율이라, 여기서 붙는
    // 배율까지 여러 단계를 한 번에 건넌다. [recenterDuration](손끝 조작용
    // 300ms)을 그대로 쓰면 중간 단계 없이 화면이 튀어 보였다(실기기 확인) —
    // 물러서는 연출과 같은 길이로 되짚어 온다([guidanceStartRecenterDuration]).
    if (_indoorLocationVisible) {
      // **실내 위치로 서 있는 사람을 GPS로 데려가지 않는다.** 그 좌표는 건물
      // 밖이라(도면을 펴 놓고 손으로 위치를 찍은 경우가 특히 그렇다) 화면이
      // 통째로 튀고 보던 도면과 경로를 잃는다. 실내는 걸음이 카메라를 끌고
      // 간다([_indoorFollowActive]) — 여기서는 첫 자리만 잡아 준다.
      await _recenterOnCurrentPosition(
        duration: guidanceStartRecenterDuration,
        minZoom: guidanceStartZoom,
      );
    } else if (_transitItinerary == null) {
      await startFollowingCurrentLocation(
        zoom: _routeIsDriving ? carGuidanceZoom : guidanceStartZoom,
        duration: guidanceStartRecenterDuration,
      );
    } else {
      // 대중교통은 계속 따라가지 **않는다** — [startFollowingCurrentLocation]이
      // 켜는 지속 팔로우를 그대로 쓰면 타는 구간에서 여정 전체가 화면 귀퉁이로
      // 밀린다. 그래도 시작 순간 첫 자리로 한 번 옮기는 것은 실내 갈래와
      // 같아야 한다 — 야외에서 출발하는 대중교통만 이 한 번을 빠뜨리고 있었다.
      final position = _positionPoint;
      if (position != null) {
        await _moveCameraToPoint(
          position,
          zoom: guidanceStartZoom,
          duration: guidanceStartRecenterDuration,
        );
      }
    }
  }

  /// 안내만 끈다 — 경로선·후보·목적지는 남는다. **뒤로가기가 부른다.**
  ///
  /// `_dismissUserDestinationFromEtaCard`(parts/route.dart)와 다르다. 그쪽은
  /// 경로까지 지우고 `onGuidanceDismissed`로 상단 길찾기 상태까지 비운다.
  /// 여기서는 경로가 남으므로 그 신호를 **부르지 않는다** — 부르면 경로만 남고
  /// 길찾기 바가 사라져, 다른 후보를 고를 문이 닫힌다.
  void stopGuidanceKeepingRoute() {
    if (!_guidanceStarted) return;
    setState(() {
      _guidanceStarted = false;
      // 걸어온 자취를 함께 지운다. 안 지우면 계획 화면에 절반이 회색인 경로가 뜬다.
      _clearCompletedRouteHistory();
    });
    _stopFollowingUser();
    _notifyRouteStateIfChanged();
    // 계획 화면의 약속은 "경로 전체가 보인다"다. 따라가기만 풀면 카메라가
    // 사용자에게 확대된 채로 남아 어느 후보가 어느 선인지 대조할 수 없다.
    //
    // **도면을 편 상태에서는 그 약속을 지키지 않는다.** 왜 그런지와 안 지켰을 때
    // 무엇이 깨지는지는 [guidanceStopCameraTarget]에 있다.
    final itinerary = _transitItinerary;
    final route = _route;
    final segment = _indoorRouteSegment;
    switch (guidanceStopCameraTarget(
      indoorEntered: _indoorEntered,
      hasIndoorSegment: segment != null,
      hasRouteToShow: itinerary != null || route != null,
    )) {
      case GuidanceStopCameraTarget.wholeRoute:
        if (itinerary != null) {
          _fitCameraToPoints(itinerary.points);
        } else if (route != null) {
          _fitCameraToRoute(route);
        }
      case GuidanceStopCameraTarget.indoorSegment:
        unawaited(_fitCameraToRouteSegment(segment!));
      case GuidanceStopCameraTarget.keep:
        break;
    }
  }

  /// 도착 카드의 `안내 종료`. 남은 여정을 통째로 정리한다.
  void _confirmArrival() {
    _arrivalRouteClearTimer?.cancel();
    _arrivalRouteClearTimer = null;
    setState(() => _arrivedDestination = null);
    _dismissIndoorRouteFromEtaCard();
  }

  /// 도착한 순간 목적지 매장 폴리곤을 강조하고, 벗어나면 되돌린다.
  ///
  /// 카드가 "여기에 도착했다"고 말할 때 지도에서 **그 여기가 어디인지**를 함께
  /// 보여 준다. 이름만 적힌 카드로는 눈앞의 여러 매장 중 어느 쪽인지 알 수 없다.
  ///
  /// 도착이 아닐 때 강조를 지우는 쪽도 함께 둔다 — 도착 판정은 걸음에 따라
  /// 들락날락할 수 있어서, 켜기만 하면 지나쳐 걸어간 뒤에도 강조가 남는다.
  /// 사용자가 매장을 눌러 직접 켜 둔 강조는 건드리지 않는다.
  void _syncArrivalHighlight() {
    if (!mounted) return;
    final destinationId = _indoorRouteDestination?.placeId;
    if (destinationId == null) return;
    final arrived = _indoorRouteGuidance?.action == RouteGuidanceAction.arrived;
    final shouldHighlight = arrived ? destinationId : null;
    if (shouldHighlight == null && _highlightedStoreId != destinationId) return;
    if (_highlightedStoreId == shouldHighlight) return;
    setState(() => _highlightedStoreId = shouldHighlight);
    unawaited(_syncHighlightLayer());
  }

  /// 경로를 벗어난 것이 확인되면 목적지는 유지한 채 현 위치에서 다시 뽑는다.
  ///
  /// **층 선택기 층이 아니라 앵커 층을 기준으로 한다.** 선택기는 사용자가 다른
  /// 층을 둘러보는 UI 상태일 뿐이다. 그 층으로 재탐색하면 다층 안내 중간
  /// 세그먼트가 단층 경로로 바뀌어 최종 도착처럼 보인다.
  Future<void> _rerouteIndoorFromCurrentPosition() async {
    if (_indoorRerouteInFlight) return;
    final destination = _indoorRouteDestination;
    final destinationNodeId = destination?.nodeId;
    final floor = _pdrTrailState.anchor?.floorId;
    final graph = _floorGraph;
    final buildingId = _building?.id;
    final current = _guidance.trackingResult?.previewPosition;
    final currentEdgeId = _guidance.trackingResult?.currentEdgeId;
    if (destination == null ||
        destinationNodeId == null ||
        floor == null ||
        graph == null ||
        buildingId == null ||
        current == null) {
      return;
    }
    final startNodeId = _nearestNodeId(
      graph.nodes,
      current.eastM,
      current.northM,
      excludingNodeId: destinationNodeId,
    );
    if (startNodeId == null) return;

    _indoorRerouteInFlight = true;
    try {
      // **재탐색에는 개요 연출을 붙이지 않는다.** 재탐색은 사용자가 걷고 있는
      // 도중에 일어난다. 그때 카메라가 경로 전체를 담으러 크게 물러섰다 돌아오면
      // 연출이 아니라 방해다 — 다음 걸음을 보려던 화면이 통째로 바뀐다.
      if (destination.floor == floor) {
        await _computeAndShowSingleFloorIndoorRoute(
          buildingId: buildingId,
          floor: floor,
          endNodeId: destinationNodeId,
          playOverview: false,
          // 이탈 재탐색 — 같은 길안내의 연속이다.
          beginNewRecordingSession: false,
          startNodeId: startNodeId,
          rerouteOrigin: current,
          rerouteIngressEdgeId: currentEdgeId,
        );
      } else {
        await _computeAndShowMultiFloorIndoorRoute(
          buildingId: buildingId,
          startFloor: floor,
          endFloor: destination.floor,
          endNodeId: destinationNodeId,
          playOverview: false,
          beginNewRecordingSession: false,
          startNodeId: startNodeId,
          rerouteOrigin: current,
          rerouteIngressEdgeId: currentEdgeId,
        );
      }
      _lastIndoorRerouteAtMs = DateTime.now().millisecondsSinceEpoch;
    } finally {
      _indoorRerouteInFlight = false;
    }
  }

  /// 지금 이 층 실내 경로의 턴바이턴 안내. 없으면 null.
  ///
  /// 실내 탭과 같은 규칙을 쓴다 — 도착 안내는 **목적지 세그먼트에서만** 낸다.
  /// 중간 층 세그먼트의 끝은 도착이 아니라 환승이라, 거기서 "도착했습니다"를
  /// 띄우면 사용자가 남은 층을 안 가고 멈춘다.
  RouteGuidanceInstruction? get _indoorRouteGuidance {
    final route = _indoorRouteSegment;
    if (route == null || route.pointsLocalM.isEmpty) return null;
    // **실내 위치가 없으면 한 줄 안내를 내지 않는다.**
    //
    // [buildRouteGuidance]는 진행률이 null이면 경로 **전체**를 기준으로 다음
    // 회전을 찾는다. 그래서 건물 밖에 서 있어도 "110미터 후 에스컬레이터 탑승"
    // 같은 문장이 떴다 — 사용자는 아직 버스에서 내려 걷는 중인데 화면은 건물 안
    // 몇 미터 앞을 말한다. 실내 오버레이만으로 가르면 안 되는 이유는, 그 오버레이가
    // 건물로 확대하기만 해도 켜지기 때문이다(indoor_entry_zoom.dart).
    //
    // 기준은 "우리가 이 사람이 실내 어디에 있는지 아는가"다. 보통은 진행률이
    // 그 근거지만, 안내 시작 직후 첫 걸음 전에는 출발 앵커만 먼저 존재한다.
    // 바로 옆 에스컬레이터에서는 그 짧은 틈에도 탑승 안내가 보여야 한다.
    if (!canShowIndoorRouteGuidance(
      hasProgress: _guidance.displayProgress != null,
      hasIndoorPosition: _guidance.position != null,
    )) {
      return null;
    }
    final multi = _indoorMultiFloorRoute;
    final segment = multi?.segmentForFloor(_activeFloor ?? '');
    final allowArrival =
        multi == null ||
        (segment != null &&
            identical(segment, multi.destinationSegment) &&
            _activeFloor == _indoorRouteDestination?.floor);
    return buildRouteGuidance(
      localPoints: route.pointsLocalM,
      wgs84Points: route.points,
      progress: _guidance.displayProgress,
      travelDirectionState: _guidance.travelDirectionState,
      transferMode: segment?.transferModeToNext,
      allowArrival: allowArrival,
    );
  }

  /// 진단 세션 하나를 새로 연다.
  ///
  /// **디버그 모드에서는 레코더를 갈아 끼우지 않는다.** 경계만 찍고 이어 간다.
  /// 여기가 실측에서 파일이 잘리던 자리다 — 문 앞에서 안내가 끝나면
  /// [_endRouteRecordingSession]이 `routeEnded`를 찍고, 밖에서 다시 길을 잡는
  /// 순간 이 함수가 새 레코더를 만들어 방금까지의 구간을 통째로 버렸다. 정작
  /// 보려던 것(문 밖 GPS 표류, 길 건너에서 시작하는 경로, 재진입 뒤 마커)은
  /// 전부 그 다음에 일어난다.
  ///
  /// **닫는 것은 사람이다** — 사용자가 JSON을 내보내는 순간이 세션의 끝이다
  /// ([_exportPdrDebugJson]). 그래야 파일이 무한히 자라지 않는다(표본 배열에는
  /// 상한이 없다).
  ///
  /// 디버그가 꺼진 일반 사용자에게는 예전 그대로 **길안내 한 건이 세션 하나**다.
  /// 실외 구간을 품은 세션만은 그때도 갈지 않는다
  /// ([PdrDebugSessionRecorder.spansBuildingExit]) — 나갈 때 걸은 구간이 사라진다.
  void _beginRouteRecordingSession() {
    _ensureGuidanceTrailSessionStarted();
    final continued = _pdrDebugRecorder;
    if (continued != null &&
        (_debugModeController.enabled || continued.spansBuildingExit)) {
      continued.recordSessionBoundary(
        continued.spansBuildingExit
            ? 'routeStartedAfterReEntry'
            : 'routeStarted',
      );
      return;
    }
    _pdrDebugRecorder = _openRouteRecordingSession();
  }

  /// 레코더 하나를 만들어 지금의 런타임·스냅샷·보정으로 채운다. 새 세션이
  /// 열리는 자리가 둘이라([_beginRouteRecordingSession]·[_exportPdrDebugJson])
  /// 채우는 순서를 한 곳에 둔다.
  PdrDebugSessionRecorder _openRouteRecordingSession() {
    final recorder = PdrDebugSessionRecorder()
      ..recordRuntime(indoorNavigationDriver.currentRuntimeStatus);
    final snapshot = indoorNavigationDriver.currentSnapshot;
    if (snapshot != null) recorder.recordSnapshot(snapshot);
    recorder.recordCalibration(indoorNavigationDriver.currentCalibration);
    return recorder;
  }

  /// 진단 세션을 여는 테스트 진입점. 실기기에서는 길안내 시작이 이 자리를
  /// 지나는데(`_computeAndShow*IndoorRoute`), 그 흐름은 층 그래프·목적지·경로
  /// 응답을 모두 갖춰야 해서 GPS 출입만 시험하는 테스트는 준비할 수 없다
  /// ([OutdoorMapIndoor.enterIndoorForTest]와 같은 이유).
  @visibleForTesting
  void beginRouteRecordingSessionForTest() => _beginRouteRecordingSession();

  /// 안내가 끝나는 순간의 테스트 진입점. 위와 같은 이유로 실제 경로 해제
  /// 흐름(`_clearIndoorRoute`)을 준비할 수 없다.
  @visibleForTesting
  void endRouteRecordingSessionForTest() => _endRouteRecordingSession();

  /// 지금 열려 있는 진단 세션. 나갔다 들어와도 **같은 인스턴스**인지가
  /// "한 주행이 JSON 하나로 남는가"의 검증 기준이다.
  @visibleForTesting
  PdrDebugSessionRecorder? get debugRecorderForTest => _pdrDebugRecorder;

  /// 경로가 해제된 것을 시계열에 남긴다. [announceExport]는 세션 경계 기록에만
  /// 쓴다 — 사용자가 끝낸 것(routeEnded)과 새 경로로 갈아탄 것(routeReplaced)을
  /// 사후 분석에서 구분하기 위해서다.
  ///
  /// **레코더는 여기서 놓지 않는다.** 경계를 찍을 뿐이고, 갈아 끼울지는
  /// [_beginRouteRecordingSession]이 정한다.
  ///
  /// 예전에는 여기서 "진단 JSON을 내보낼 수 있다"는 토스트를 띄웠다. 안내가
  /// 끝나는 순간은 도착 카드가 뜨는 순간이라 토스트가 그 위를 덮었고, 내보내기
  /// 진입점은 디버그 모드의 공유 버튼([PdrMapControl])이 이미 지도에 상시로
  /// 있다 — 같은 일을 하는 두 번째 입구가 화면을 가리기만 했다.
  void _endRouteRecordingSession({bool announceExport = true}) {
    final recorder = _pdrDebugRecorder;
    if (recorder == null) return;
    final snapshot = indoorNavigationDriver.currentSnapshot;
    if (snapshot != null) recorder.recordSnapshot(snapshot);
    recorder.recordRuntime(indoorNavigationDriver.currentRuntimeStatus);
    recorder.recordSessionBoundary(
      announceExport ? 'routeEnded' : 'routeReplaced',
    );
  }
}
