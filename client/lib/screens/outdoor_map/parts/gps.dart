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
  /// 겸하면 실내 위치가 있는 사람의 도면 위에 건물 밖 GPS 점이 함께 찍힌다.
  ///
  /// **도면을 편 것만으로는 꺼지지 않는다.** 밖에 서서 매장을 찾아보는 사람의
  /// 위치를 그리는 것은 여전히 GPS다([_indoorViewedFromOutside]) — 그때 이 마커를
  /// 끄면 화면에 자기 자리가 하나도 없거나, 실내 마커가 건물 밖 좌표를 도면 위에
  /// 흐리게 찍어 "안에 있다"고 거짓말한다.
  bool get _outdoorGpsVisible => widget.active && !_indoorLocationVisible;

  /// 진입 직후 실내 위치가 아직 없을 때 **자리만 지키는** GPS 좌표. 없으면 null.
  ///
  /// 실내로 들어간 순간 GPS 마커는 꺼지는데([_outdoorGpsVisible]), 실내 마커는
  /// 앵커를 찍고 보정이 수렴해야 나온다([_startIndoorTracking]). 실측에서 그
  /// 공백이 25초였고 그동안 화면에 위치가 하나도 없었다 — 진입 판정은 맞았는데
  /// "내 위치를 알려주는 게 안 뜬다"로 올라온 화면이 이것이다. 그 구간을 이
  /// 좌표가 흐린 점 하나로 메운다([indoorMarkerAt]의 3순위).
  ///
  /// **표시 전용이다.** 건물 밖에서 찍힌 좌표라 도면 위 엉뚱한 자리일 수 있어,
  /// 앵커·길안내 출발지·"내 위치로"([_canRecenterOnCurrentPosition])는 이 값을
  /// 보지 않는다 — 그쪽은 전부 [_pdrCurrentWgs84]만 본다.
  ll.LatLng? get _indoorGapGpsPoint {
    if (!_indoorLocationVisible) return null;
    final position = _position;
    if (position == null) return null;
    return ll.LatLng(position.latitude, position.longitude);
  }

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
    _positionDropTimer?.cancel();
    _positionDropTimer = null;
    if (!mounted) return;
    setState(() => _position = null);
    // 구독이 끊긴 동안 사용자는 어디로든 갈 수 있다. 옛 기준점을 들고 있으면
    // 돌아왔을 때 옳은 좌표를 거른다. 방향도 함께 잊는다 — 좌표를 버리는 자리라,
    // 남겨 두면 돌아온 첫 마커가 끊기기 전 방향을 가리킨다.
    _gpsJumpFilter = const GpsJumpFilterState();
    _outdoorHeading.reset();
    _lastOutdoorCourseDeg = null;
    _lastOutdoorCourseAt = null;
    _syncCurrentLayer();
  }

  /// 위치 스트림이 **에러로** 닫혔다.
  ///
  /// **마커를 그 자리에서 지우지 않는다.** 에러는 "스트림이 끊겼다"이지 "이
  /// 사람이 사라졌다"가 아니다. 재구독은 [streamRetryMinDelay](2초) 뒤에 돌고
  /// 일회성 조회는 그동안에도 1초마다 나가므로 대개 몇 초 안에 좌표가 다시
  /// 온다 — 그 사이 지웠다 그리면 사용자에게는 **깜빡임**으로만 보인다.
  ///
  /// 그래도 영영 안 오는 경우(권한 회수·위치 서비스 종료)에는 옛 자리를 계속
  /// 그리면 안 된다. 그건 시간으로 끊는다([_positionDropTimer]).
  ///
  /// **방향은 지금 버린다.** 자리는 "몇 초 전에는 여기였다"로 여전히 쓸모가
  /// 있지만, 진행 방향은 끊긴 순간부터 아무 근거가 없다.
  void _handlePositionError() {
    if (!mounted) return;
    _gpsJumpFilter = const GpsJumpFilterState();
    _outdoorHeading.reset();
    _lastOutdoorCourseDeg = null;
    _lastOutdoorCourseAt = null;
    if (_position == null) return;
    _positionDropTimer?.cancel();
    _positionDropTimer = Timer(streamSilenceTimeout, () {
      _positionDropTimer = null;
      if (!mounted || _position == null) return;
      setState(() => _position = null);
      unawaited(_syncCurrentLayer());
    });
    unawaited(_syncCurrentLayer());
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
    // 오차 값이 아니라 **물리**로 거른다. 상한·유예·항복의 근거는
    // [stepGpsJumpFilter]. 거른 좌표는 표시에서도 판정에서도 뺀다.
    final jump = stepGpsJumpFilter(
      state: _gpsJumpFilter,
      point: ll.LatLng(position.latitude, position.longitude),
      at: position.timestamp,
      walking: !_routeIsDriving,
    );
    _gpsJumpFilter = jump.state;
    if (!jump.accepted || jump.surrendered) {
      // 거른 건과 **항복해서 받아들인** 건을 같은 배열에 남긴다. 항복이 잦으면
      // 상한이 너무 빡빡하다는 뜻이라, 다음 실측에서 그것부터 본다.
      _pdrDebugRecorder?.recordGpsRejectedFix(
        jumpM: jump.jumpM!,
        allowanceM: jump.allowanceM!,
        elapsedSeconds: jump.elapsedSeconds,
        gpsAccuracyM: position.accuracy,
        surrendered: jump.surrendered,
        indoorEntered: _indoorEntered,
        at: position.timestamp,
      );
      if (!jump.accepted) {
        // **표시에서만 뺀다.** 진단 칩은 그대로 갱신해, 화면이 멈춘 이유가
        // "좌표가 안 온다"인지 "와서 버렸다"인지 현장에서 가릴 수 있게 한다.
        _updateTransitionDebugChip(sinceLastFix: sinceLastFix);
        return;
      }
    }
    // 방향은 **받아들인 좌표에서만** 뽑는다. 거른 좌표(위에서 이미 return한 것)
    // 로 방향을 갱신하면, 그리지도 않는 자리로 튄 각이 삼각형에 남는다.
    //
    // **건물 안에서는 아예 넣지 않는다.** 실내 좌표는 벽에 반사된 신호로 계산된
    // 것이라, 거기서 나온 course는 걷는 방향과 아무 관계가 없다. 그래도 계속
    // 넣고 있었더니 문을 나선 첫 몇 초 동안 그 값이 삼각형에 남아 있었다 —
    // "밖으로 나오면 한동안 엉뚱한 데를 가리키다 제자리를 찾는다"가 이것이다.
    // 좌표 자체는 이탈 판정에 계속 쓰이므로 여기서만 가른다.
    if (!_indoorEntered) {
      final course = _outdoorHeading.track(
        headingDeg: position.heading,
        headingAccuracyDeg: position.headingAccuracy,
        speedMps: position.speed,
        at: position.timestamp,
        // 수신기가 말하는 진행 방향을 **우리가 잰** 이동 방향과 대조하는 근거다.
        // 재획득 중의 수신기는 "모른다"가 아니라 틀린 값을 자신 있게 준다.
        point: ll.LatLng(position.latitude, position.longitude),
      );
      // 문 앞에서 나침반을 대조할 근거로 따로 들고 있는다([_entryReferenceCourseDeg]).
      if (course != null) {
        _lastOutdoorCourseDeg = course;
        _lastOutdoorCourseAt = DateTime.now();
      }
    }
    // 좌표가 왔으니 스트림 에러로 예약해 둔 "마지막 자리 버리기"는 접는다.
    _positionDropTimer?.cancel();
    _positionDropTimer = null;
    // 실내에서도 좌표는 **들고 있는다.** 진입/이탈 판정의 유일한 입력이고,
    // 화면에 그릴지는 [_outdoorGpsVisible]이 따로 가른다([_syncCurrentLayer]).
    setState(() => _position = position);
    _syncCurrentLayer();
    // 실내 공백 구간에는 이 좌표가 마커의 자리를 지킨다([_indoorGapGpsPoint]).
    // 좌표가 갱신되면 실내 마커 소스도 다시 써야 그 점이 따라 움직인다 — 안
    // 쓰면 진입 순간의 좌표에 점이 못 박힌 채로 25초를 버틴다.
    if (_indoorEntered) unawaited(_syncPdrCurrentLayer());
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
    }
    // 문 선택은 진입 판정보다 **먼저** 갱신한다. 진입 직후 실내 위치를 잡을 때
    // 폴백으로 쓰는 문이 이 선택의 결과라, 순서를 뒤집으면 사용자가 이미 다른
    // 문으로 들어왔는데 폴백은 한 박자 전 문을 가리킨다.
    if (!_indoorEntered) _syncSelectedEntrance();
    _applyPositionToIndoorGates(position, sinceLastFix: sinceLastFix);
    // 건물 안이면 아래 이동을 생략한다. 실내 도면 카메라와 첫 GPS 카메라가
    // 경합해 선택기 뒤에서 지도가 한 번 더 튀는 것을 막는다.
    if (!_indoorEntered &&
        !_startupCameraPrepared &&
        !_initialCameraClaimed &&
        _styleReady &&
        _mapController != null) {
      unawaited(
        _moveCameraToUser(position).whenComplete(() {
          if (!mounted || _indoorEntered) return;
          _startupCameraPrepared = true;
          _maybeNotifyOutdoorStartupReady();
        }),
      );
    }
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
  /// **묻는 것은 진입 한 번에 한 번뿐이다**([_entryFloorAsked]). 벽 근처에서
  /// 판정이 오가면 이 화면이 되풀이해 뜨는데, 그러면 지도에 닿을 수가 없다.
  ///
  /// **아무도 답하지 않았으면**(안 물었다·건너뛰었다) 지금 보고 있는 층이 아니라
  /// **진입 근거가 정한다**([_entryEvidenceFloor]). 보고 있는 층은 목적지를
  /// 고르는 것만으로 갈리고, 그 층에 앵커를 찍으면 실제로는 1F에 서 있는 사람이
  /// B2 그래프에 못 박힌다 — 층이 1F로 돌아오는 순간 위치 마커가 사라진다.
  /// 판정이 틀렸을 때의 출구는 그대로다: 안내 중이 아니면 층 선택기가 떠 있다.
  Future<void> _askEntryFloorThenTrack(Position position) async {
    // **경로를 그리는 중이면 아무것도 묻지 않는다.** "서울창업허브 → 더현대
    // 서울"처럼 목적지를 정해 두고 걸어 들어오는 길이 있는데, 그때 도착해서
    // 층을 묻는 화면이 뜨면 방금 보던 경로를 통째로 덮는다. 어디로 가는
    // 중인지는 이미 화면이 말하고 있고, 위치가 필요하면 하단 바의 두 버튼이
    // 그 자리에 있다. **위치는 그대로 자동으로 잡는다** — 묻지 않는 것과
    // 추적하지 않는 것은 다르다.
    // **묻지 않는 것과 층을 안 고르는 것은 다르다.** 예전에는 안내 중이면 여기서
    // 곧장 빠져나가 보고 있던 층(= 목적지 층)에 앵커를 찍었다. 지금은 묻지만
    // 않고 아래 진입 근거로 층을 고른다.
    final answer = _guidancePlanned ? null : await _askEntryFloor();
    if (!mounted || !_indoorEntered) return;
    if (answer != null) {
      // 사람이 고른 층이 가장 강한 근거다. 층 전환은 chip을 누른 것과 **같은
      // 경로**를 탄다 — 도면 교체와 그 층 외곽선에 맞춘 카메라 정렬이 거기
      // 붙어 있다([_onFloorChipSelected]).
      if (answer != _activeFloor) await _onFloorChipSelected(answer);
    } else {
      await _moveToEntryEvidenceFloor();
    }
    if (!mounted || !_indoorEntered) return;
    await _startIndoorTracking(position: position);
    if (!mounted || !_indoorEntered) return;
    // 시작 화면은 **모든 갈래에서** 걷힌다. 위치를 잡은 시점이 곧 가릴 이유가
    // 없어진 시점이다.
    _notifyStartupReady();
    if (_guidancePlanned) return;
    // 시작 화면이 걷히는 애니메이션과 겹치면 그 위로 시트가 반쯤 가려진 채
    // 뜬다 — 예전에 이 자동 오픈을 걷어냈던 이유가 그 겹침이었다. 시작 화면과
    // 같은 전환 길이만큼 물러선 뒤 연다.
    await Future<void>.delayed(RoutexMotion.transition);
    if (!mounted || !_indoorEntered) return;
    // 자동으로 띄우는 것은 **진입 한 번에 한 번뿐이다**. 버튼으로 다시 여는
    // 쪽은 이 제한을 받지 않는다([_nearbyStoreAsked]).
    await _askNearbyStoreForAnchor(once: true);
  }

  /// 진입 근거가 가리키는 층으로 도면을 옮긴다. 옮길 근거가 없거나 이미 그
  /// 층이면 아무것도 하지 않는다.
  ///
  /// **[_onFloorChipSelected]를 쓰지 않는다** — 그쪽은 사용자가 chip을 눌렀을
  /// 때의 경로라 카메라를 그 층 외곽선에 맞춘다. 여기는 아무도 누르지 않았고,
  /// 안내 중이면 카메라의 주인은 사용자 위치다.
  Future<void> _moveToEntryEvidenceFloor() async {
    final floor = _entryEvidenceFloor;
    if (floor == null || floor == _activeFloor) return;
    await _switchOverlayFloorCrossfaded(floor);
  }

  /// 이 사람이 서 있다고 볼 층. 고르는 규칙과 그 근거는 [gpsEntryAnchorFloor].
  String? get _entryEvidenceFloor => gpsEntryAnchorFloor(
    groundEntranceFloor: _groundEntranceFloor,
    defaultFloor: _building?.initialFloor,
    viewedFloor: _activeFloor,
  );

  /// GPS가 잡아 준 **어림 위치를 사람이 다듬게 한다.**
  ///
  /// 자동 배치는 "이쯤"까지다 — 건물 안 GPS는 오차가 십수 m라 복도 하나쯤은
  /// 예사로 틀린다. 지금 무엇 앞에 서 있는지는 **사람이 훨씬 정확히 안다.**
  /// 고른 매장의 입구 노드가 곧 위치가 된다.
  ///
  /// 층 도면·그래프가 없으면 묻지 않는다 — 목록을 세울 재료가 없다. 반대로
  /// **기준점(앵커·어림 위치)이 없다고 물러나지는 않는다**: 그때는 화면 한가운데를
  /// 기준으로 세운다([_nearbyStoreRows]).
  Future<void> _askNearbyStoreForAnchor({bool once = false}) async {
    if (once && _nearbyStoreAsked) return;
    final rows = _nearbyStoreRows();
    if (rows.isEmpty) return;
    if (once) _nearbyStoreAsked = true;
    final picked = await showNearbyStoreSheet(context, rows: rows);
    if (picked == null || !mounted || !_indoorEntered) return;
    await _anchorAtNearbyStore(picked);
  }

  /// 지금 기준점에서 가까운 매장 줄. 층 도면·그래프가 없으면 빈 목록.
  List<NearbyStoreRow> _nearbyStoreRows() {
    final plan = _floorPlan;
    final graph = _floorGraph;
    if (plan == null || graph == null || graph.nodes.isEmpty) return const [];
    // **기준점은 지금 보는 층의 것이어야 한다.** 층 로컬 좌표계는 층마다 따로
    // 맞춰지므로, 다른 층 앵커를 이 층 그래프에 대면 "가까운 순"이 통째로
    // 엉뚱해진다 — 앵커가 1F 문에 찍힌 채 B2를 보던 실기기 상태가 그것이다.
    // 마지막 기준은 **화면 한가운데**다: 위치가 없어도 사용자가 보고 있는
    // 자리가 곧 "여기 어디쯤"이라, 그 덕에 이 버튼이 정작 위치를 고치려는
    // 순간에 사라지지 않는다.
    final from =
        _anchorPointOnActiveFloor() ??
        _estimatedFloorPoint() ??
        _cameraCenterFloorPoint(graph);
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
  /// 앵커가 **지금 보는 층**에 있을 때만 그 좌표. 다른 층이면 null이다 —
  /// [_estimatedFloorPoint]가 층을 보는 것과 같은 이유다.
  PdrLocalPoint? _anchorPointOnActiveFloor() {
    final anchor = _pdrTrailState.anchor;
    if (anchor == null || anchor.floorId != _activeFloor) return null;
    return anchor.anchorLocalM;
  }

  /// 화면 한가운데를 이 층 좌표로 옮긴다. 지도를 아직 못 읽었으면 null.
  PdrLocalPoint? _cameraCenterFloorPoint(FloorGraph graph) {
    final camera = _mapController?.cameraPosition;
    if (camera == null) return null;
    final local = fitFloorGeoTransform(
      graph.nodes,
    ).invert(camera.target.latitude, camera.target.longitude);
    return local == null ? null : PdrLocalPoint(local.$1, local.$2);
  }

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
  ///
  /// [force]면 "한 번뿐"을 건너뛴다. 사용자가 위치를 **다시 잡겠다고 누른**
  /// 경우라, 그때 안 묻고 보고 있는 층에 찍으면 층을 훑어보던 사람이 그 층에
  /// 못 박힌다.
  Future<String?> _askEntryFloor({bool force = false}) async {
    if (_entryFloorAsked && !force) return null;
    final building = _building;
    if (building == null || building.floors.length < 2) return null;
    _entryFloorAsked = true;
    // 시작 덮개 자체의 타이머만 기다리게 하면 이 Navigator 화면이 그 위를 먼저
    // 덮어, 로고가 2초보다 훨씬 짧게 보인다. 질문을 올리는 시점도 같은 최소
    // 노출 시간 뒤로 맞춘다. 앱을 사용하다 다시 들어온 경우에는 이미 지난 값이라
    // 지연이 생기지 않는다.
    await _startupMinimumElapsed.future;
    if (!mounted || !_indoorEntered) return null;
    return showEntryFloorPrompt(
      context,
      buildingName: building.name,
      buildingAddress: building.displayAddress,
      floors: building.floors,
      fallbackFloor: _entryEvidenceFloor ?? building.initialFloor!,
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
  /// **실패 조건 둘** — 층 그래프가 없다·사다리 셋이 다 실패. 하나라도 걸리면
  /// 포기하고 수동 경로를 안내한다: 틀린 위치를 찍는 것보다 위치가 없는 편이 낫다.
  Future<void> _startIndoorTracking({
    required Position position,
    BuildingEntrance? entrance,
  }) async {
    // **이미 확정된 앵커는 [entrance]를 아는 호출에서만 덮는다.**
    //
    // 문을 아는 호출은 사용자가 방금 「진입」을 누른 것이고, 그 문은 지금 이
    // 사람이 서 있는 자리를 말하는 가장 새로운 근거다. 반대로 문을 모르는 호출
    // (실내 콜드스타트)이 덮으면 GPS 스냅이 이미 잡아 둔 좋은 앵커를 밀어낸다.
    //
    // 이 갈래가 없으면 **나갔다 다시 들어올 때 마커가 통째로 사라진다**(실기기
    // 증상). 나갈 때 [_dropIndoorPosition]은 화면 쪽 앵커
    // ([DebugPdrTrailState.beginNewSession])와 추정치를 비우는데, 드라이버의
    // 보정은 센서 세션이 실제로 멈춰야 풀린다 — 정지는 기다리지 않는 호출이고
    // (`stopWithoutWaiting`), 디버그 모드에서는 기록을 이으려고 아예 세션을
    // 살려 둔다. 그 사이 `canRenderPosition`은 참인 채로 남아, 다시 들어와도
    // 여기서 곧장 돌아섰다. 앵커는 비었고 추정치도 비어 그릴 것이 없었다.
    if (entrance == null &&
        indoorNavigationDriver.currentCalibration.canRenderPosition) {
      return;
    }

    // 건물이 막 도착한 직후라면 층 그래프 요청이 아직 도는 중이다.
    await _floorGraphLoad;
    if (!mounted || !_indoorEntered) return;

    // 앵커 층은 **호출자가 이미 옮겨 둔** 층이다([_askEntryFloorThenTrack]) —
    // 사람이 고른 층이거나 진입 근거가 고른 층이지 목적지 층이 아니다. 여기서
    // 다시 고르지 않는 이유는 그 층의 그래프·도면이 이미 이 값에 맞춰져 있기
    // 때문이다.
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
    unawaited(_syncPdrCurrentLayer(snap: true));

    // GPS로 건물 안임을 이미 확인했으므로 권한 게이트를 다시 두지 않는다. 세션이
    // 다른 층에서 돌고 있으면 이 층으로 옮겨야 앵커가 이 층으로 기록된다.
    //
    // [entrance]가 있으면(문을 지나 들어온 진짜 재진입) 세션이 이미 돌고
    // 있어도 방위만은 새로 잡는다([forceFreshHeading]) — 밖을 걷는 동안 흔들린
    // 방위가 이번에 찍는 문 앞 앵커의 회전각에 그대로 구워지는 것을 막는다.
    if (!await _bindPdrSessionToFloor(
      floor,
      gatePermission: false,
      forceFreshHeading: entrance != null,
    )) {
      return;
    }
    await _awaitSensorWarmup();
    if (!mounted || !_indoorEntered) return;

    final axes = fitPdrToFloorAxes(graph.nodes);
    await indoorNavigationDriver.confirmAnchorByPin(
      floorPointM: estimatedPoint,
      axes: axes,
      // **문 하나를 사이에 두고 방향의 근거가 바뀌는 자리다.** 밖에서 보던
      // 삼각형은 GPS 진행 방향이었고 안에서는 나침반인데, 그 나침반 값이 이
      // 앵커의 회전각으로 구워져 이후 실내 궤적 전체를 돌린다. 문 앞은 하필
      // 자력계에 가장 나쁜 자리(철제 문틀·회전문·보안 게이트)이므로, 넘어가기
      // 전에 방금 밖에서 걷던 방향과 한 번 맞춰 본다.
      trueCourseDeg: _entryReferenceCourseDeg,
    );
    if (!mounted) return;

    // 자북 heading을 못 얻는 기기는 여기서 방향 보정을 기다린다. 묻지 않고
    // 추정해 그 자리에서 확정한다([_entryFloorDirection]) — 아무 조작 없이 모달이
    // 튀어나오면 사용자는 자기가 뭘 눌러 띄운 건지 알 수 없다.
    if (indoorNavigationDriver.currentCalibration.phase ==
        CalibrationPhase.awaitingHeading) {
      final estimate = _entryFloorDirection(
        anchorFloorPoint: estimatedPoint,
        graph: graph,
        axes: axes,
      );
      if (estimate == null) {
        _replaceSnack('진입 방향을 알 수 없습니다. 위치 지정으로 직접 지정해주세요.');
        return;
      }
      await indoorNavigationDriver.confirmAnchorByFloorDirection(
        floorDirection: estimate.direction,
        basis: estimate.basis,
      );
      if (!mounted) return;
    }

    debugPrint(
      '[anchor] 찍음 — 층 $floor · 출처 $estimateSource · '
      '문 ${entrance?.id} · 스냅오차 ${snapped.gapM.toStringAsFixed(1)}m',
    );
    _syncPdrCurrentLayer(snap: true);
    unawaited(_syncDebugPdrLayers());
    // 이제 실내 마커가 있다. 진입 순간에는 위치를 몰라 건너뛴 연출
    // ([_setIndoorEntered])을 여기서 한다 — 카메라는 아직 진입 직전의 야외
    // 화면이라, 방금 찍은 마커가 화면 밖일 수 있다.
    unawaited(_centerOnIndoorMarker());
    // 입구에서 위치를 새로 잡았으므로, 건물에 들어오기 전에 골라둔 출발지 매장은
    // 더 이상 "지금 내가 있는 곳"이 아니다. 상위가 그 값을 버리게 알린다.
    widget.onLocationAnchored?.call();
  }

  /// 야외 안내를 시작한다 — 카메라를 현재 위치로 확대하고, 이후 위치가 갱신될
  /// 때마다 그 자리를 따라간다.
  ///
  /// [zoom]이 수단마다 다른 이유는 **보는 거리가 달라서**다. 자동차는 다음
  /// 교차로가 화면에 들어와야 하고([carGuidanceZoom]), 걸을 때는 지금 서 있는
  /// 통로가 보여야 한다([walkingViewZoom]).
  ///
  /// 위치를 아직 못 잡았어도 **켜 둔다.** 신호가 잡히는 순간 첫 위치가 카메라를
  /// 데려가므로, 여기서 포기하면 터널을 나오며 안내를 시작한 사용자가 영영
  /// 따라가지 못한다. 대신 지금 아무 일도 안 일어나는 이유는 알린다.
  Future<void> startFollowingCurrentLocation({
    double zoom = carGuidanceZoom,
    Duration? duration,
  }) async {
    final position = _position;
    if (position == null) {
      // 아직 옮길 좌표가 없으니 지금 켜 둬야 신호가 잡히는 순간 놓치지 않는다.
      _followingUser = true;
      _showSnack('현재 위치를 아직 못 잡았습니다. 신호가 잡히면 그 자리로 지도를 옮깁니다.');
      return;
    }
    // **애니메이션이 끝난 뒤에 켠다.** 먼저 켜면 도는 동안 들어오는 GPS 틱마다
    // [_handlePosition]이 배율 없이 또 한 번 옮겨, 두 애니메이션이 겹쳐 화면이
    // 튄다 — 전체 경로 개요에서 확대해 들어올 때 특히 두드러졌다.
    await _moveCameraToUser(position, zoom: zoom, duration: duration);
    _followingUser = true;
  }

  /// 따라가기를 멈춘다. 안내가 끝나거나(경로 삭제) 카메라의 주인이 바뀌는
  /// 지점(새 경로 계산)에서 부른다 — 안 멈추면 사용자가 지도를 옮겨도 다음 위치
  /// 한 건이 곧바로 되돌려 놓아 지도를 조작할 수 없다.
  void _stopFollowingUser() => _followingUser = false;

  /// 안내 중 "내 위치로" 버튼. **실내는 bearing·tilt를 건드리지 않는다** — 정북
  /// 으로 돌아가면 화면 위쪽이 갈 방향과 어긋난다. **야외는 정북·평면으로
  /// 되돌린다** — 야외에는 세워 둘 방향이 없고, 남아 있는 bearing은 직전 실내
  /// 나침반 추종이 새어 나온 값일 뿐이다. 배율도 [walkingViewZoom]까지만 당긴다.
  ///
  /// **팔로우를 다시 켜는 유일한 문이다.** 지도를 손으로 움직이면 두 팔로우가
  /// 함께 물리는데([_releaseFollowCamera]), 그걸 푸는 자리가 없으면 안내가 끝날
  /// 때까지 화면이 사용자를 따라가지 않는다.
  ///
  /// **실내·야외 어느 쪽이든 이 버튼 하나다.** 실내는 PDR 위치로, 야외는 마지막
  /// 좌표로 돌아간다 — 사용자에게는 같은 "내 위치로"라, 어느 쪽인지 가려 두 개를
  /// 만들 이유가 없다.
  Future<void> _recenterOnCurrentPosition({
    Duration duration = recenterDuration,
    double minZoom = walkingViewZoom,
  }) async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    final indoorHere = _pdrCurrentWgs84();
    final here = indoorHere ?? _positionPoint;
    // 실내 위치로 못 갔으면 그 이유가 대개 **층 어긋남**이다 — 앵커가 다른 층에
    // 있으면 이 값이 null이라 조용히 GPS 좌표로 떨어진다(화면은 건물 바깥 어림
    // 자리로 간다). 실기기에서 "실내로 포커싱이 안 됨"이 이것이었다.
    if (indoorHere == null) {
      debugPrint(
        '[recenter] 실내 위치 없음 — 보는 층 $_activeFloor · '
        '앵커 층 ${_pdrTrailState.anchor?.floorId} · GPS로 대체 ${here != null}',
      );
    }
    // 위치를 아직 못 그리는 상태면 되돌릴 자리도 없다. 버튼 노출 조건이 같은
    // 값을 보므로([_canRecenterOnCurrentPosition]) 보통은 여기 안 걸린다.
    if (here == null) return;
    _followCameraReleasedByUser = false;
    // 야외 안내라면 따라가기도 다시 켠다. 버튼을 누른 사람이 원한 것은 "지금
    // 내 자리"가 아니라 **"다시 나를 따라와라"**다 — 한 번 데려다 놓고 그대로
    // 두면 다음 걸음부터 또 뒤에 남는다.
    if (_guidanceActive && !_indoorLocationVisible) _followingUser = true;
    // **걸음 팔로우가 도는 중이면 그쪽과 같은 구도로 간다.**
    //
    // 팔로우는 내 위치를 화면 한가운데가 아니라 조금 아래에 둔다 — 진행 방향이
    // 보여야 하기 때문이다([_followCameraTargetFor]). 여기서 정중앙으로 데려다
    // 놓으면, 유예가 풀리는 순간 팔로우가 곧바로 자기 구도로 되돌려 버튼 한 번에
    // 화면이 갔다가 돌아온다(실기기: "위치 갱신을 누르면 왔다갔다"). 두 명령이
    // 같은 자리를 목표로 하면 되돌릴 것이 없다.
    final target = _indoorFollowActive
        ? _followCameraTargetFor(
            here,
            controller.cameraPosition?.bearing ?? 0,
          )
        : here;
    // 이 애니메이션이 도는 동안은 팔로우를 재운다. 안 재우면 같은 프레임에 두
    // 명령이 겹쳐, 눌러서 돌아가는 도중에 화면이 한 번 튄다.
    _holdFollowCamera(duration);
    await recenterKeepingBearing(
      controller,
      target,
      minZoom: minZoom,
      duration: duration,
      keepBearing: _indoorLocationVisible,
      // 가려지지 않는 띠의 한가운데에 놓는다 — 안 주면 하단 chrome(탭 줄·안내
      // 카드)이 상단보다 대개 높아서 화면 중앙보다 위로 치우친다.
      //
      // **실내에서는 주지 않는다.** 이 호출이 끝나자마자 매 프레임 팔로우
      // 루프([_indoorFollowActive] → `_driveFollowCamera`)가 곧바로 카메라를
      // 다시 잡는데, 그 루프는 이 보정을 모른다 — 한 번 밀어 놔도 다음
      // 프레임에 보정 없는 자리로 도로 끌려가 어긋나 보였다(실기기에서
      // "헤딩이 튄다"로 보임). 경쟁자가 없는 순수 야외 재정렬에만 준다.
      topChromePx: _indoorLocationVisible ? 0 : _topChromeBottomPx(),
      bottomChromePx: _indoorLocationVisible ? 0 : _bottomChromePx(),
    );
  }

  /// "내 위치로" 버튼을 띄울지. 누를 자리가 없는 버튼을 띄우지 않기 위해
  /// [_recenterOnCurrentPosition]이 실제로 쓰는 값과 **같은 값**을 본다.
  ///
  /// 야외도 포함한다 — 한동안 실내에만 떠서, 걷는 안내 중 지도를 한 번 밀면
  /// 화면을 되돌릴 손잡이가 아예 없었다.
  bool get _canRecenterOnCurrentPosition =>
      (_indoorLocationVisible && _pdrCurrentWgs84() != null) ||
      _positionPoint != null;

  /// 내 위치가 찍힌 층으로 도면을 되돌리고 카메라를 그 자리에 놓는다.
  ///
  /// **층 전환에 카메라를 맡기지 않는다.** [_onFloorChipSelected]는 새 층
  /// 외곽선에 맞추므로, 그걸 쓰면 층 전체가 잡힌 뒤 내 자리로 한 번 더 움직여
  /// 전환이 두 박자로 쪼개진다. 여기서는 도면만 갈아 끼우고 카메라는 곧바로
  /// 내 위치로 간다.
  Future<void> _returnToMyFloor() async {
    final anchorFloor = _pdrTrailState.anchor?.floorId;
    if (anchorFloor == null) return;
    if (anchorFloor != _activeFloor) {
      await _switchOverlayFloorCrossfaded(anchorFloor, recenterIfNeeded: false);
      // 연타로 이 호출이 추월당했으면 카메라를 만지지 않는다 — 사용자가 마지막에
      // 고른 층 위에서 엉뚱한 자리로 끌려간다([_onFloorChipSelected]와 같은 규칙).
      if (!mounted || _activeFloor != anchorFloor) return;
    }
    await _recenterOnCurrentPosition();
  }
}
