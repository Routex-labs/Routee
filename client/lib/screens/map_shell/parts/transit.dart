// ignore_for_file: invalid_use_of_protected_member
//
// part라 `setState`(protected) 호출이 경고로 잡힌다.
/// `_MapShellScreenState`의 **대중교통 조회·후보 선택** 부분.
///
/// part 규약과 이 파일로 가른 이유는 `docs/client/structure-plan.md` 15단계.
part of '../map_shell_screen.dart';

extension _MapShellTransit on _MapShellScreenState {
  /// [from]에서 [to]까지 보행자 경로. 이미 받아 온 구간이면 부르지 않는다.
  Future<DirectionsRoute?> _walkingRoute(LatLng from, LatLng to) async {
    final gap = TransitWalkGap(from: from, to: to);
    if (_transitWalks.containsKey(gap)) return _transitWalks[gap];
    _transitWalkCalls++;
    final route = await directionsRepository.getWalkingRoute(
      origin: from,
      destination: to,
    );
    return _transitWalks[gap] = route;
  }

  /// 대중교통 경로를 물어보고, 첫 후보를 지도에 미리 그린 뒤 목록을 띄운다.
  ///
  /// 출발지는 야외 지도가 정한다([OutdoorMapBodyState.routeOriginPoint]) —
  /// 지도에서 찍은 출발 지점이 있으면 그것을, 없으면 GPS를 쓴다. 실내 앵커는
  /// 쓰지 않는다(건물 안 좌표를 보내면 정류장이 건물 반대편에서 잡힌다).
  ///
  /// **무시한 사실을 로그로 남긴다.** 조용히 삼키면 중복을 만드는 조작이
  /// 무엇인지 영영 안 보이고, 가드가 원인을 덮은 채로 남는다.
  Future<void> _startTransitRoute(DirectionsCandidate destination) {
    return _transitRequest.run(
      () => _requestTransitRoute(destination),
      onDuplicate: () =>
          debugPrint('[transit] 조회 중이라 중복 요청 무시: ${destination.title}'),
    );
  }

  Future<void> _requestTransitRoute(DirectionsCandidate destination) async {
    debugPrint('[transit] 조회 시작: ${destination.title}');
    final outdoor = _outdoorKey.currentState;
    final origin = _transitOriginPoint(outdoor);
    if (outdoor == null || origin == null) {
      _showSnack('현재 위치를 아직 못 잡았습니다. GPS 신호를 확인하거나 출발지를 직접 지정해주세요.');
      return;
    }

    final routes = await transitRepository.getTransitRoutes(
      origin: origin,
      destination: destination.point,
    );
    if (!mounted) return;
    if (await _announceTransitFailure(routes.status, destination)) return;

    // **목록을 띄우기 전에** 앞뒤 도보를 채운다. 시트를 먼저 열고 나중에 채우면
    // 사용자가 누르는 순간 카드 높이가 튀어 엉뚱한 후보를 고른다.
    final filled = await _withListWalkLegs(
      routes,
      origin: origin,
      destination: destination.point,
    );
    if (!mounted) return;

    // **실내 구간도 목록 단계에서 붙인다.** 안 붙이면 "최적 1시간 2분"이 건물
    // 문에서 출발하는 시간인데, 정작 사용자는 3층에 서 있다 — 고른 뒤에야
    // 실내 선이 그려지고 시간은 끝까지 안 나온다.
    final withIndoor = await _withIndoorLeadLegs(filled, fallback: origin);
    if (!mounted) return;

    // **채운 목록을 보관한다** — 원본을 넣으면 뒤로가기로 다시 연 목록에서만
    // 도보가 사라진다.
    _lastTransitQuery = (
      routes: withIndoor,
      destination: destination,
      origin: origin,
    );
    // **목록보다 먼저 그린다.** 자동차·도보는 누른 즉시 경로가 뜨는데 대중교통만
    // 고를 때까지 앞 수단 경로가 남아 있었다. 조회가 성공한 뒤에 그리는 순서라야
    // 실패했을 때 앞 경로도 새 경로도 없는 빈 화면이 안 생긴다.
    await _previewTransitRoute(
      withIndoor,
      destination: destination,
      origin: origin,
    );
    if (!mounted) return;
    await _pickTransitRoute(
      withIndoor,
      destination: destination,
      origin: origin,
    );
  }

  /// 고르기 전에 후보 하나를 **지도에만** 그린다. 나머지는 회색으로 깔린다 —
  /// 자동차 후보와 같은 그림이다. 하단 요약 카드는 목록이 닫힐 때까지 접혀
  /// 있다([_transitRoutesSheetOpen]).
  ///
  /// [selected]가 null이면 첫(최적) 후보다. 목록에서 카드를 누르면 그 줄의
  /// 후보가 들어와 **같은 길로** 다시 그린다 — 그리는 자리가 둘이면 그림도 둘이다.
  ///
  /// **실내 구간도 문 재선정도 하지 않는다.** 그건 확정했을 때 할 일이라
  /// [_pickTransitRoute]가 한다. 여기서는 목록이 든 후보를 그대로 그리므로
  /// TMAP 호출이 한 건도 더 나가지 않는다.
  ///
  /// 그릴 좌표가 없으면 아무 일도 하지 않는다 — 빈 선을 그리면 앞 수단 경로만
  /// 지워져 지도가 빈 화면이 된다.
  Future<void> _previewTransitRoute(
    TransitRoutes routes, {
    required DirectionsCandidate destination,
    required LatLng origin,
    TransitItinerary? selected,
  }) async {
    final outdoor = _outdoorKey.currentState;
    if (outdoor == null || routes.itineraries.isEmpty) return;
    final best = selected ?? routes.itineraries.first;
    if (best.points.isEmpty) return;
    await outdoor.showTransitRoute(
      best,
      destination: destination.point,
      label: '${destination.title}까지',
      origin: origin,
      // 그리는 것만 빼고 전부 회색으로 깐다. `skip(1)`로 세면 두 번째 후보를
      // 그릴 때 자기 회색 선이 파란 선 밑에 한 겹 더 깔린다.
      alternatives: [
        for (final candidate in routes.itineraries)
          if (!identical(candidate, best)) candidate,
      ],
      // 이 그림 **뒤에** 후보 목록이 올라와 화면 아래를 덮는다. 카메라가
      // 전체 화면 기준으로 맞추면 경로 절반이 시트 뒤에 잠긴다.
      bottomSheetFraction: kTransitRoutesSheetInitialSize,
    );
  }

  /// 후보 **전부**의 앞뒤 도보를 채운다. 카카오는 첫 승차 전·마지막 하차 뒤
  /// 도보를 주지 않아, 그대로 그리면 목록의 선이 정류장에서 시작한다.
  ///
  /// 실호출은 [transitWalkGaps]가 중복을 지우고 상한을 건 만큼만 나간다 —
  /// TMAP 경로안내 그룹이 하루 1,000건을 공유해서 후보마다 두 번씩 부르면
  /// 자동차 조회까지 함께 죽는다. 잘린 구간과 실패한 요청은 맵에서 null로
  /// 나와 `fillTransitWalkLegs`가 직선으로 잇는다.
  Future<TransitRoutes> _withListWalkLegs(
    TransitRoutes routes, {
    required LatLng origin,
    required LatLng destination,
  }) async {
    // 새 조회는 새 출발지·목적지라 지난 조회의 구간이 맞을 일이 거의 없다.
    _transitWalks.clear();
    // 상한 없이 한 번 더 뽑아 **잘린 몫을 눈에 보이게 한다.** 순수 계산이라
    // 호출은 늘지 않는다. 상한이 넉넉한지는 이 로그 말고 볼 근거가 없다.
    final needed = transitWalkGaps(
      routes.itineraries,
      origin: origin,
      destination: destination,
      maxGaps: 1 << 30,
    );
    final gaps = transitWalkGaps(
      routes.itineraries,
      origin: origin,
      destination: destination,
    );
    if (gaps.isEmpty) return routes;

    final before = _transitWalkCalls;
    await Future.wait([
      for (final gap in gaps) _walkingRoute(gap.from, gap.to),
    ]);
    debugPrint(
      '[transit] 목록 도보 채우기: 필요 ${needed.length}건 '
      '실호출 ${_transitWalkCalls - before}건 잘림 ${needed.length - gaps.length}건',
    );
    // 받아 온 것은 메모에 그대로 있다. 상한에 잘린 구간과 실패한 요청은 null로
    // 나와 `fillTransitWalkLegs`가 직선으로 잇는다.
    DirectionsRoute? lookup(LatLng from, LatLng to) =>
        _transitWalks[TransitWalkGap(from: from, to: to)];

    return TransitRoutes(
      status: routes.status,
      itineraries: [
        for (final itinerary in routes.itineraries)
          if (itinerary.legs.isEmpty)
            itinerary
          else
            fillTransitWalkLegs(
              itinerary,
              origin: origin,
              destination: destination,
              head: itinerary.legs.first.points.isEmpty
                  ? null
                  : lookup(origin, itinerary.legs.first.points.first),
              tail: itinerary.legs.last.points.isEmpty
                  ? null
                  : lookup(itinerary.legs.last.points.last, destination),
            ),
      ],
    );
  }

  /// 건물 안에서 출발하는 여정이면 후보 **전부**의 앞에 실내 구간을 붙인다.
  ///
  /// 카카오는 우리 건물의 복도도 엘리베이터도 모른다. 그래서 실내 구간은 총계에
  /// 없고, 붙이지 않으면 3층에 선 사용자가 "1시간 2분"이라고 적힌 목록에서
  /// 고르게 된다 — 그 값은 문에서 출발하는 시간이다. 총계를 어떻게 올리는지와
  /// 그때 생기는 근사는 [prependIndoorWalkLeg]에 적었다.
  ///
  /// **네트워크를 타지 않는다.** 문까지의 거리는 건물 그래프(이미 캐시에 있다)를
  /// 한 번 훑어 얻고([OutdoorMapBodyState.indoorExitReach]), 후보마다 다시 하는
  /// 일은 문 고르기뿐이다 — 후보가 15개라도 TMAP 할당량이 한 건도 안 나간다.
  ///
  /// 판정은 고른 뒤와 **같은 것**을 쓴다([journeyStartsIndoors]). 갈리면 목록에는
  /// 실내 시간이 들어 있는데 정작 고르면 실내 선이 안 그려지는 상태가 생긴다.
  Future<TransitRoutes> _withIndoorLeadLegs(
    TransitRoutes routes, {
    required LatLng fallback,
  }) async {
    if (routes.itineraries.isEmpty) return routes;
    if (!journeyStartsIndoors(
      origin: _selectedOrigin,
      indoorStartReady:
          indoorNavigationDriver.currentCalibration.canRenderPosition,
    )) {
      return routes;
    }
    final outdoor = _outdoorKey.currentState;
    if (outdoor == null) return routes;
    final reach = await outdoor.indoorExitReach(origin: _indoorOriginPoi());
    if (!mounted || reach == null) {
      debugPrint('[transit] 실내 선행 구간 건너뜀 — 닿는 문이 없다(그래프·앵커 확인)');
      return routes;
    }

    debugPrint('[transit] 실내 선행 구간 붙임 — 닿는 문 ${reach.legs.length}개');
    return TransitRoutes(
      status: routes.status,
      itineraries: [
        for (final itinerary in routes.itineraries)
          if (outdoor.indoorLeadFor(
                reach,
                transitBoardPoint(itinerary, fallback: fallback),
              )
              case final lead?)
            prependIndoorWalkLeg(
              itinerary,
              seconds: lead.seconds,
              meters: lead.meters,
              exitName: lead.exitName,
            )
          else
            itinerary,
      ],
    );
  }

  /// 마지막 후보 목록을 다시 연다. 보관한 조회가 없으면(대중교통이 아니었거나
  /// 길찾기가 끝났으면) 아무 일도 하지 않는다 — 자동차는 계획 카드 안에 후보
  /// 패널이 그대로 남아 있다.
  ///
  /// 중복 가드는 첫 조회와 같은 [_transitRequest]를 탄다. 칩을 연타해도 시트가
  /// 두 겹으로 뜨지 않는다.
  Future<void> _reopenTransitRoutesSheet() async {
    final last = _lastTransitQuery;
    if (last == null) return;
    await _transitRequest.run(
      () => _pickTransitRoute(
        last.routes,
        destination: last.destination,
        origin: last.origin,
      ),
      onDuplicate: () => debugPrint('[transit] 목록이 이미 떠 있어 재열기 무시'),
    );
  }

  /// 후보 목록을 띄우고, 확정한 하나를 지도에 그린 뒤 **안내까지 시작한다.**
  /// **첫 조회와 뒤로가기가 같이 쓴다** — 고른 뒤의 흐름을 두 벌로 만들면 한쪽만
  /// 고쳐진다.
  ///
  /// 목록이 떠 있는 동안에는 요약 카드를 접는다([_transitRoutesSheetOpen]).
  Future<void> _pickTransitRoute(
    TransitRoutes routes, {
    required DirectionsCandidate destination,
    required LatLng origin,
  }) async {
    setState(() => _transitRoutesSheetOpen = true);
    try {
      final picked = await _withMapsLocked(
        () => TransitRoutesSheet.show(
          context,
          routes: routes,
          destinationLabel: destination.title,
          onCloseAll: _requestCloseSheetChain,
          // 누른 줄로 지도를 갈아친다. 미리보기와 **같은 함수**라 TMAP 호출은
          // 한 건도 안 늘고, 고르지 않고 닫으면 마지막에 본 후보가 그대로 남는다.
          onPreview: (itinerary) => unawaited(
            _previewTransitRoute(
              routes,
              destination: destination,
              origin: origin,
              selected: itinerary,
            ),
          ),
        ),
      );
      if (!mounted || picked == null) return;
      final outdoor = _outdoorKey.currentState;
      if (outdoor == null) return;

      // **건물 안에서 출발하면 정류장까지의 실내 구간을 먼저 그린다.**
      //
      // 거울상인 하차 쪽은 아래 [prepareIndoorLegFromDrop]으로 이미 있었는데,
      // 승차 쪽은 함수([showIndoorLegToOutdoorStart])와 좌표 계산
      // ([transitBoardPoint])이 다 만들어져 있으면서 **부르는 자리만 없었다.**
      // 그래서 실내에서 대중교통을 시작하면 바깥 경로만 그려지고, 사용자는 지금
      // 서 있는 층에서 어느 문으로 나가야 하는지 화면에서 알 수 없었다.
      //
      // 대중교통 경로를 그리기 **전에** 부른다 — 그 함수가 `_userDestination`을
      // 비우므로, 뒤에 부르면 방금 세운 도착 핀이 지워진다.
      //
      // **근거는 실내 위치 하나다**([journeyStartsIndoors]) — 도보 갈래
      // ([classifyWalkRoute])와 같은 모양이라야 수단을 바꾸는 것만으로 안내
      // 앞부분이 사라지지 않는다.
      final boardingWalkOrigin =
          journeyStartsIndoors(
            origin: _selectedOrigin,
            indoorStartReady:
                indoorNavigationDriver.currentCalibration.canRenderPosition,
          )
          ? await outdoor.showIndoorLegToOutdoorStart(
              transitBoardPoint(picked, fallback: origin),
              origin: _indoorOriginPoi(),
            )
          : null;
      if (!mounted) return;

      // **건물 안 매장이면 마지막 도보는 매장이 아니라 문으로 간다.**
      //
      // 매장 좌표를 그대로 끝점으로 주면 TMAP이 그 좌표에서 가장 가까운 도로로
      // 스냅하는데, 그 도로가 내린 곳 반대편일 수 있다. 내린 자리에서 가장 가까운
      // 문을 우리가 직접 고른다 — 그 자리를 어떻게 구하는지는
      // [transitDropPoint]에 있다.
      final dropPoint = transitDropPoint(picked, fallback: destination.point);
      final indoorStore = _indoorStoreOf(destination);
      // **우리 건물을 향하는 안내면 하차 지점 기준으로 문을 다시 고른다.**
      // 후보의 문은 검색하던 시점 위치에서 가까운 문이라, 버스를 타고 반대편에서
      // 내리면 더 이상 가깝지 않다 — 실기기에서 바로 옆 문을 두고 건물을 빙 돌았다.
      final targetsOurBuilding =
          indoorStore != null || destination.buildingId == _buildingId;
      final walkTarget =
          (targetsOurBuilding ? outdoor.entranceNearestTo(dropPoint) : null) ??
          destination.point;
      debugPrint(
        '[transit] 하차 지점 기준 문 선택: 우리 건물=$targetsOurBuilding '
        '하차=(${dropPoint.latitude.toStringAsFixed(5)}, '
        '${dropPoint.longitude.toStringAsFixed(5)}) '
        '도보 도착=(${walkTarget.latitude.toStringAsFixed(5)}, '
        '${walkTarget.longitude.toStringAsFixed(5)})',
      );

      // **카카오가 마지막 도보를 줬어도 우리가 다시 그린다.**
      //
      // 그 구간은 카카오가 정한 끝점(우리가 보낸 목적지 좌표)으로 가는데, 우리는
      // 방금 하차 지점 기준으로 문을 다시 골랐다. 그대로 두면 지도에 그려진 도보는
      // 옛 끝점으로 가고 실내 구간만 새 문에서 시작해, 두 선이 서로 다른 곳을
      // 가리킨다. 자세한 근거는 [trimTrailingWalkLeg]에 있다.
      //
      // **실내 구간은 먼저 떼어 둔다.** 안 떼면 바로 아래 [trimLeadingWalkLeg]가
      // 카카오의 첫 도보 대신 그것을 잘라 낸다.
      final (lead: indoorLead, rest: outdoorOnly) = takeIndoorWalkLead(picked);
      final trimmed = trimTrailingWalkLeg(outdoorOnly);

      // **첫 도보도 문 기준으로 다시 그린다.** 목록에서 채운 그 구간은 우리가
      // 카카오에 보낸 출발 좌표(건물 안 GPS)에서 시작한다. 실내 선은 문에서
      // 끝나는데 바깥 선은 건물 한가운데서 뻗어, 지도에서 **두 선이 안 이어진
      // 채로 남았다** — 실기기에서 사용자가 지적한 화면이 이것이다. 거울상인
      // 하차 쪽은 [trimTrailingWalkLeg]로 이미 이렇게 하고 있었고,
      // [trimLeadingWalkLeg]도 그 목적으로 만들어져 있었는데 **부르는 자리만
      // 없었다.**
      //
      // TMAP 호출이 한 건 더 나간다(출발점이 달라 메모가 안 받는다). 건물 안에서
      // 출발할 때만이고, 그 한 건이 없으면 안내의 첫 구간이 통째로 어긋난다.
      final headed = boardingWalkOrigin == null
          ? trimmed
          : trimLeadingWalkLeg(trimmed);

      // 뒤 도보는 방금 고른 문으로 끝점이 바뀌었을 수 있어 다시 채우지만, 문이
      // 목적지 그대로면 목록에서 부른 그 구간이라 메모([_transitWalks])가 받아
      // 호출이 안 나간다.
      final completed = await _withTransitWalkLegs(
        headed,
        origin: boardingWalkOrigin?.point ?? origin,
        destination: walkTarget,
      );
      if (!mounted) return;

      // 떼어 둔 실내 구간을 되붙인다. 총계도 함께 돌아온다.
      final withIndoorLead = indoorLead == null
          ? completed
          : prependIndoorWalkLeg(
              completed,
              seconds: indoorLead.seconds,
              meters: indoorLead.meters,
              exitName: boardingWalkOrigin?.label ?? indoorLead.exitName,
            );

      await outdoor.showTransitRoute(
        withIndoorLead,
        destination: walkTarget,
        label: '${destination.title}까지',
        // 실내 구간을 그렸으면 바깥 도보는 **그 문에서** 시작한다. 안 그러면
        // 실내 선은 문에서 끝나는데 바깥 선은 건물 안 좌표에서 뻗어, 두 선이
        // 서로 다른 곳을 가리킨다.
        origin: boardingWalkOrigin?.point ?? origin,
        // 나머지 후보도 함께 넘겨 회색으로 깔린다. 고른 것 하나만 그리면 "다른
        // 길도 있다"가 시트를 다시 열기 전까지 화면에서 사라진다.
        //
        // **다듬기 전 것을 넘긴다.** 앞뒤 도보는 이미 붙어 있고, 고른 경로만
        // 문·하차 지점에 맞춰 끝을 다시 손본다([_withTransitWalkLegs]). 회색 선이
        // 말하는 것은 "대충 어디로 도는가"라 그 정밀도가 필요 없다.
        // **고른 것은 뺀 나머지다.** `completed`는 picked를 다듬은 사본이라
        // 목록 안의 원본과 같은 객체가 아니고, 그대로 넘기면 파란 선 밑에 자기
        // 회색 선이 한 겹 더 깔린다.
        alternatives: [
          for (final candidate in routes.itineraries)
            if (!identical(candidate, picked)) candidate,
        ],
      );
      if (!mounted) return;
      if (indoorStore != null) {
        // 실내 구간은 **showTransitRoute 뒤에** 푼다. 그 함수가 시작할 때 pending을
        // 비우므로, 앞에서 풀면 쌓아 둔 실내 구간이 곧바로 지워진다.
        await outdoor.prepareIndoorLegFromDrop(
          indoorStore,
          dropPoint: dropPoint,
        );
        if (!mounted) return;
      }

      // **여기까지 왔다는 것은 상세에서 `안내 시작`을 눌렀다는 뜻이다** — 목록은
      // 그 버튼에서만 값을 돌려준다(TransitRoutesSheet.show). 확정만 하고 멈추면
      // 하단 카드가 같은 버튼을 한 번 더 내밀어 두 번 누르게 된다.
      //
      // 계획 카드의 버튼과 **같은 함수**를 탄다. 경로에서 멀면 그쪽 가드가 막고
      // 안내 문구만 뜨는데, 그때 카드에 버튼이 남는 것이 맞는 동작이다.
      await outdoor.startGuidanceForPickedRoute();
    } finally {
      if (mounted) setState(() => _transitRoutesSheetOpen = false);
    }
  }

  /// 대중교통 조회를 보낼 출발 좌표.
  ///
  /// 명시적으로 고른 출발지라도 **실내 지점이면 쓰지 않는다.** 건물 안 좌표를
  /// 보내면 카카오가 그 좌표에서 가장 가까운 정류장을 찾는데, 건물이 크면 실제로
  /// 나가야 하는 문의 반대편이 잡힌다. 그때는 GPS로 떨어뜨린다.
  LatLng? _transitOriginPoint(OutdoorMapBodyState? outdoor) {
    final selected = _selectedOrigin;
    final outdoorOrigin =
        (selected != null && selected.floor == null && selected.nodeId == null)
        ? selected.point
        : null;
    return outdoorOrigin ?? outdoor?.routeOriginPoint;
  }

  /// 조회가 경로 없이 끝났으면 사용자에게 알리고 true. 계속 진행할 수 있으면 false.
  ///
  /// **결말마다 사용자가 할 행동이 다르다.** 한 문구로 묶으면 700m 앞 목적지를
  /// 두고 계속 재시도하게 된다([TransitRoutesStatus] 주석).
  Future<bool> _announceTransitFailure(
    TransitRoutesStatus status,
    DirectionsCandidate destination,
  ) async {
    switch (status) {
      case TransitRoutesStatus.ok:
        return false;
      case TransitRoutesStatus.unavailable:
        _showSnack('대중교통 안내를 쓸 수 없습니다. 카카오 REST 키 설정을 확인해주세요.');
        return true;
      case TransitRoutesStatus.failed:
        _showSnack('대중교통 경로를 불러오지 못했습니다. 잠시 후 다시 시도해주세요.');
        return true;
      case TransitRoutesStatus.noRoute:
        _showSnack('이 구간의 대중교통 경로를 찾지 못했습니다.');
        return true;
      case TransitRoutesStatus.tooClose:
        // 걸어갈 수 있는 거리다. 안내 없이 끝내지 않고 도보 경로로 이어 준다 —
        // 사용자가 원한 것은 "저기까지 가는 방법"이지 "대중교통 그 자체"가 아니다.
        _showSnack('가까운 거리라 대중교통 경로가 없습니다. 도보로 안내합니다.');
        setState(() => _travelMode = RoutePlanMode.walk);
        await _startRoute(
          origin: _selectedOrigin,
          destination: destination,
          autoSelectMode: false,
        );
        return true;
    }
  }

  /// 이 후보가 **우리 건물 안 매장**이면 실내 라우팅용 값으로 바꾼다. 층이나
  /// 노드가 없으면 null — 좌표까지만 안내할 수 있는 바깥 장소다.
  PoiSearchResult? _indoorStoreOf(DirectionsCandidate candidate) {
    final floor = candidate.floor;
    final nodeId = candidate.nodeId;
    if (floor == null || nodeId == null) return null;
    return PoiSearchResult(
      name: candidate.title,
      floor: floor,
      point: candidate.point,
      nodeId: nodeId,
    );
  }

  /// 사용자가 **출발지로 고른 실내 매장**. 안 골랐으면 null이라 실내 구간이
  /// PDR 앵커(=지금 서 있는 자리)에서 시작한다.
  ///
  /// [_indoorStoreOf]의 출발지 쪽 짝이다. 좌표만 있는 야외 지점은 실내 라우팅의
  /// 시작 노드가 못 되므로 걸러 낸다.
  PoiSearchResult? _indoorOriginPoi() {
    final selected = _selectedOrigin;
    if (selected == null) return null;
    return _indoorStoreOf(selected);
  }

  /// 고른 한 경로의 출발·도착 도보를 TMAP 보행자 경로로 채운다.
  ///
  /// 두 요청을 동시에 보낸다. 순서대로 기다리면 지도가 뜨기까지 왕복 시간이
  /// 두 배가 되는데, 두 구간은 서로를 필요로 하지 않는다. 목록에서 온 경로는
  /// 앞 도보가 이미 붙어 있어(첫 구간이 도보라) 앞쪽 요청이 저절로 빠지고,
  /// 뒤 도보도 끝점이 그대로면 [_walkingRoute]의 메모가 받는다.
  ///
  /// 실패해도 안내를 막지 않는다. 도보선이 직선으로 떨어질 뿐이고, 사용자가
  /// 기다린 것은 "저기까지 가는 방법"이지 도보 구간의 정확한 모양이 아니다.
  Future<TransitItinerary> _withTransitWalkLegs(
    TransitItinerary itinerary, {
    required LatLng origin,
    required LatLng destination,
  }) async {
    if (itinerary.legs.isEmpty) return itinerary;
    final first = itinerary.legs.first;
    final last = itinerary.legs.last;

    final before = _transitWalkCalls;
    final routes = await Future.wait([
      (first.mode.isWalk || first.points.isEmpty)
          ? Future<DirectionsRoute?>.value()
          : _walkingRoute(origin, first.points.first),
      (last.mode.isWalk || last.points.isEmpty)
          ? Future<DirectionsRoute?>.value()
          : _walkingRoute(last.points.last, destination),
    ]);

    debugPrint('[transit] 고른 경로 도보 채우기: 실호출 ${_transitWalkCalls - before}건');

    return fillTransitWalkLegs(
      itinerary,
      origin: origin,
      destination: destination,
      // **첫 도보도 출발점까지 이어 붙인다.** 뒤 도보와 같은 이유다 — 건물
      // 안에서 출발하면 이 출발점이 문 좌표이고, TMAP 보행자 경로는 그 문이
      // 아니라 가장 가까운 보행 도로에서 시작한다. 그대로 두면 실내 선이 끝난
      // 문과 바깥 선이 시작하는 도로 사이가 비어, 두 구간이 남남으로 보인다.
      head: extendRouteFromOrigin(routes[0], origin),
      // 마지막 도보는 **도착점까지 이어 붙인다.** TMAP 보행자 경로는 가장 가까운
      // 보행 가능 도로에서 끝나는데, 여기 도착점은 건물 출입구라 도로에서 몇십
      // 미터 떨어져 있다. 그대로 두면 선이 건물 앞 도로에서 뚝 끊기고, 정작 문
      // 앞 구간과 그 문에서 이어지는 실내 구간 사이가 비어 두 선이 남남으로
      // 보인다.
      tail: extendRouteToDestination(routes[1], destination),
    );
  }
}
