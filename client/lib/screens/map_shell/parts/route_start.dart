// ignore_for_file: invalid_use_of_protected_member
//
// part라 `setState`(protected) 호출이 경고로 잡힌다.
/// `_MapShellScreenState`의 **이동 수단 선택·도보/자동차 경로 시작** 부분.
///
/// part 규약과 이 파일로 가른 이유는 `docs/client/structure-plan.md` 15단계.
part of '../map_shell_screen.dart';

extension _MapShellRouteStart on _MapShellScreenState {
  /// 이동 수단 줄에서 직접 골랐을 때.
  ///
  /// 도착지가 아직 없으면 상태만 바꿔 둔다. 그 상태에서 계산하면 실패 안내만
  /// 나오고, 곧 도착지를 고르면 이 수단으로 그려진다.
  ///
  /// **이미 고른 `대중교통`을 다시 누르면 보관한 후보 목록을 연다.** 안내 중
  /// 뒤로가기로 계획 화면에 돌아온 사람이 다른 후보로 갈아탈 문이 여기뿐이다.
  /// 조회는 다시 하지 않는다([_lastTransitQuery]).
  Future<void> _onTravelModePicked(RoutePlanMode mode) async {
    if (_travelMode == mode) {
      if (mode == RoutePlanMode.transit) await _reopenTransitRoutesSheet();
      return;
    }
    setState(() => _travelMode = mode);
    final destination = _routeDraftDestination;
    if (destination == null) return;
    await _startRoute(
      origin: _selectedOrigin,
      destination: destination,
      autoSelectMode: false,
    );
  }

  /// 걸어갈 만한 거리의 상한(m).
  ///
  /// 1.5 km는 보통 걸음으로 20분쯤이다. 그보다 멀면 대중교통을 먼저 보여 주는
  /// 편이 맞다 — 도보 안내를 지나쳐 다시 누르게 하는 것보다 낫고, 반대로 이
  /// 값을 더 낮추면 두 정거장 거리를 굳이 버스로 안내하게 된다.
  static const _walkableMeters = 1500.0;

  /// 거리를 보고 처음 보여 줄 이동 수단을 정한다. 출발점을 모르면 도보로 둔다 —
  /// 대중교통을 부르면 고른 적도 없는 수단의 실패 안내를 본다.
  ///
  /// **자동차는 자동으로 고르지 않는다** — 차가 있는지 모르고, 걸어갈 거리에
  /// 운전 경로를 내밀면 무엇을 안내받는지부터 다시 읽어야 한다.
  RoutePlanMode _defaultTravelMode(
    DirectionsCandidate? origin,
    DirectionsCandidate destination,
  ) {
    if (!transitRepository.isAvailable) return RoutePlanMode.walk;
    final from = origin?.point ?? _outdoorKey.currentState?.routeOriginPoint;
    if (from == null) return RoutePlanMode.walk;
    final meters = const Distance().as(
      LengthUnit.Meter,
      from,
      destination.point,
    );
    return meters > _walkableMeters
        ? RoutePlanMode.transit
        : RoutePlanMode.walk;
  }

  /// 자동차 경로. **경로 전체를 먼저 보여주고, 따라가기는 버튼으로 시작한다.**
  ///
  /// 한동안은 경로를 그리자마자 카메라를 현재 위치로 확대했다. "자동차를 고른
  /// 것 자체가 지금 출발한다는 뜻"이라는 판단이었는데, 그 화면에서는 사용자가
  /// 전체 경로를 **한 번도 못 본다** — 어디를 지나 어느 방향으로 가는지 확인할
  /// 기회 없이 곧바로 자기 위치에 확대된 화면을 마주한다. 지금은 경로 전체에
  /// 카메라를 맞춰 두고, 하단 카드의 "안내 시작"을 누르면 그때 위치로 내려간다.
  Future<void> _startCarRoute(
    DirectionsCandidate? origin,
    DirectionsCandidate destination,
  ) async {
    final outdoor = _outdoorKey.currentState;
    if (outdoor == null) {
      _showSnack('현재 위치를 아직 못 잡았습니다. GPS 신호를 확인하거나 출발지를 직접 지정해주세요.');
      return;
    }
    // 도착지가 건물 안이면 문으로 바꾼다. 건물 안 좌표를 그대로 보내면 TMAP이
    // 건물 반대편 도로에 스냅해, 실제로 들어가는 문과 다른 곳에서 경로가 끝난다.
    final to =
        outdoor.entranceIfInsideBuilding(destination.point) ??
        destination.point;

    // **건물 안에서 출발하면 차를 타러 나가는 실내 구간을 먼저 그린다.**
    //
    // 대중교통과 **같은 함수·같은 판정**을 쓴다([journeyStartsIndoors]) — 셋 중
    // 자동차만 이 구간이 없는 동안에는, 실내에서 수단을 자동차로 바꾸는 것만으로
    // 안내의 앞부분이 통째로 사라졌다. 게다가 출발지가 "현재 위치"면 아래
    // `routeOriginPoint`가 건물 안 GPS라, 그 좌표에서 가장 가까운 도로로 스냅해
    // 실제로 나가는 문과 반대편에서 경로가 시작하는 일이 실제로 있었다.
    //
    // 자동차 경로를 그리기 **전에** 부른다 — 그 함수가 `_userDestination`을
    // 비우므로, 뒤에 부르면 방금 세운 도착 핀이 지워진다.
    final exit =
        journeyStartsIndoors(
          origin: _selectedOrigin,
          indoorStartReady:
              indoorNavigationDriver.currentCalibration.canRenderPosition,
        )
        ? await outdoor.showIndoorLegToOutdoorStart(
            to,
            origin: _indoorOriginPoi(),
          )
        : null;
    if (!mounted) return;

    // 실내 지점이 출발지면 건물 문으로 바꾼다 — 위와 같은 스냅 문제다. 실내
    // 구간을 그렸으면 그 문이 이미 출발점이라 다시 고르지 않는다.
    final from =
        exit?.point ??
        (origin == null
            ? outdoor.routeOriginPoint
            : (outdoor.entranceIfInsideBuilding(origin.point) ?? origin.point));
    if (from == null) {
      _showSnack('현재 위치를 아직 못 잡았습니다. GPS 신호를 확인하거나 출발지를 직접 지정해주세요.');
      return;
    }
    final options = await directionsRepository.getDrivingRouteOptions(
      origin: from,
      destination: to,
    );
    if (!mounted) return;
    if (!options.hasRoutes) {
      _showSnack('자동차 경로를 불러오지 못했습니다. 잠시 후 다시 시도해주세요.');
      return;
    }
    await outdoor.showPlannedRoadRouteOptions(
      options.options,
      origin: from,
      destination: to,
      // 문을 경유하면 카드에도 적는다. 안 적으면 "계양도서관"이라고만 쓰인
      // 카드가 건물 모서리에서 시작하는 선을 가리킨다(도보 쪽
      // `showIndoorToOutdoorRouteTo`와 같은 판단).
      label: exit == null
          ? destination.title
          : '${destination.title}까지 · ${exit.label} 경유',
    );
  }

  /// 도착지가 정해졌을 때 **어떻게 갈지를 먼저 고른다.** [origin]이 null이면
  /// "현재 위치"(=PDR)에서 출발한다.
  ///
  /// [autoSelectMode]가 참이면 목적지 종류를 보고 수단을 정한다 — 사용자가 직접
  /// 고른 경우에는 거짓으로 불러 그 선택을 덮지 않는다.
  ///
  Future<void> _startRoute({
    DirectionsCandidate? origin,
    required DirectionsCandidate destination,
    bool autoSelectMode = true,
  }) async {
    // **보관한 대중교통 후보를 여기서 버린다.** 길찾기는 무엇이든 이 함수를
    // 지나므로, 수단을 바꾸거나 목적지만 갈아도 낡은 목록이 남지 않는다. 비우는
    // 자리가 `_forgetRouteDraft` 하나뿐이었을 때는, 대중교통으로 찾아 본 뒤
    // 도보로 바꿔 안내를 시작하고 뒤로가기를 누르면 **도보 화면 위에 대중교통
    // 후보 시트**가 떴다. 대중교통이면 아래 `_requestTransitRoute`가 다시 채운다.
    _lastTransitQuery = null;
    // 안내가 시작되면 상단 바는 길찾기 두 칸이어야 한다. 매장 시트·검색 결과·
    // 지도 탭처럼 길찾기 바를 거치지 않고 들어오는 경로가 있어서, 여기서 한 번
    // 맞춰 준다 — 안 맞추면 경로는 그려졌는데 상단은 검색창인 화면이 된다.
    _enterRouteModeForGuidance(origin, destination);
    // 최근 목록도 **여기 한 곳에서만** 남긴다. 모든 길찾기가 반드시 이 함수를
    // 지나므로, 시트·검색·지도 탭 어느 문으로 들어와도 빠짐없이 쌓인다.
    // origin이 null이면 "현재 위치"라 남길 지점이 없다([_selectedOrigin] 주석).
    if (origin != null) unawaited(recentRoutePointsController.add(origin));
    unawaited(recentRoutePointsController.add(destination));
    // 건물 안 매장이 목적지면 **도보로 못박는다.** 그 안내는 "문을 경유해
    // 매장까지"라 도보 구간과 실내 구간이 한 몸이고([showOutdoorToIndoorRouteTo]),
    // 자동차로 가면 그 실내 구간이 통째로 사라진다.
    //
    // 자동 선택만 건너뛰면 안 된다. [_travelMode]는 화면에 남는 값이라, 직전에
    // 자동차로 길을 찾아 본 사용자에게는 그 값이 그대로 남아 있고, 그 상태로
    // 건물 안 매장을 고르면 아래 분기가 자동차로 흘려보내 실내 구간이 시작조차
    // 못 한다.
    _warnIfIndoorLegSkipped(origin, destination);
    if (autoSelectMode) {
      final mode = destination.nodeId == null
          ? _defaultTravelMode(origin, destination)
          : RoutePlanMode.walk;
      if (_travelMode != mode) setState(() => _travelMode = mode);
    }
    switch (_travelMode) {
      case RoutePlanMode.transit:
        await _startTransitRoute(destination);
        return;
      case RoutePlanMode.car:
        await _startCarRoute(origin, destination);
        return;
      case RoutePlanMode.walk:
        await _startWalkRoute(origin: origin, destination: destination);
    }
  }

  /// 건물 안에 서 있는데 **실내 위치가 없어 실내 구간이 통째로 빠지는** 경우를
  /// 말한다.
  ///
  /// 세 수단이 다 같은 문턱을 쓴다([journeyStartsIndoors]·[classifyWalkRoute]) —
  /// 도면이 떠 있어도 실내 위치가 없으면 "밖에 있는 사람"으로 보고 바깥 경로만
  /// 그린다. 그 판정 자체는 맞다(도면은 확대만으로도 켜진다). 문제는 **조용히**
  /// 그랬다는 것이다: 3층에 선 사용자가 "도보 12분"을 보는데 그 12분은 문에서
  /// 출발하는 값이고, 화면에는 왜 실내 구간이 없는지도, 무엇을 하면 되는지도
  /// 적혀 있지 않았다(실기기 지적).
  ///
  /// 경로를 막지는 않는다. 바깥 경로는 그대로 쓸모가 있고, 여기서 되돌리면
  /// 정말 밖에 있는 사용자가 길찾기를 못 한다.
  void _warnIfIndoorLegSkipped(
    DirectionsCandidate? origin,
    DirectionsCandidate destination,
  ) {
    // 출발지를 직접 골랐으면 그 노드가 시작점이라 실내 위치가 필요 없다.
    // 도착지가 건물 안이면 이 여정은 실내로 **들어가는** 쪽이라 해당 없다.
    if (origin != null || destination.nodeId != null) return;
    if (!_indoorContextActive) return;
    if (indoorNavigationDriver.currentCalibration.canRenderPosition) return;
    // 눌러야 할 버튼을 깜빡여 가리킨다 — 문장으로 버튼을 지목하면 그 문장이
    // 버튼을 가린다([_onNeedLocationPlacement]).
    _onNeedLocationPlacement();
    _showSnack('실내 위치를 잡으면 지금 층에서 출구까지도 함께 안내합니다.');
  }

  /// 도보 길찾기. **어느 갈래인지는 [classifyWalkRoute]가 정하고, 여기서는 그
  /// 갈래에 맞는 지도 메서드를 부르기만 한다.**
  ///
  /// 판정을 따로 둔 이유는 그 파일에 적었다 — 요약하면 갈래 하나가 빠져 있어도
  /// 화면에는 "경로를 계산할 수 없습니다"만 뜨고, 그게 판정 누락인지 데이터
  /// 문제인지 구분되지 않는다. 판정만 떼면 지도 없이 시험할 수 있다.
  Future<void> _startWalkRoute({
    required DirectionsCandidate? origin,
    required DirectionsCandidate destination,
  }) async {
    final map = _outdoorKey.currentState;
    final kind = classifyWalkRoute(
      origin: origin,
      destination: destination,
      indoorContextActive: _indoorContextActive,
      indoorStartReady:
          indoorNavigationDriver.currentCalibration.canRenderPosition,
    );
    debugPrint(
      '[walk] 갈래 $kind · 도면 $_indoorContextActive · '
      '실내위치 ${indoorNavigationDriver.currentCalibration.canRenderPosition}',
    );
    switch (kind) {
      // 화면(탭)을 바꾸지 않고 야외 화면 그대로에 실내 경로를 그린다 — 방금
      // 지정한 위치·매장·경로를 한 시야에서 확인하도록.
      case WalkRouteKind.indoorToIndoor:
        await map?.showIndoorRouteTo(
          _asPoi(destination),
          origin: origin == null ? null : _asPoi(origin),
          // 실내 위치가 아직 없으면 그 사람은 건물 밖이다. 경로는 그려 주되
          // 현재 위치를 출발지 매장으로 잡지는 않는다 — 시작은 카드의
          // `안내 시작`이 맡는다.
          preview: true,
        );

      // 실내 구간까지 미리 풀어 두었다가 건물에 들어가면 이어 붙인다.
      case WalkRouteKind.outdoorToIndoor:
        await map?.showOutdoorToIndoorRouteTo(
          _asPoi(destination),
          origin: origin?.point,
        );

      // 나가는 방향도 실내 구간을 먼저 풀어 두고, 건물을 나가면 야외 경로를
      // 이어 붙인다. origin이 있으면 그 매장에서, 없으면 PDR 앵커에서 출발한다.
      case WalkRouteKind.indoorToOutdoor:
        await map?.showIndoorToOutdoorRouteTo(
          destination.point,
          label: destination.title,
          origin: origin == null ? null : _asPoi(origin),
        );

      case WalkRouteKind.outdoor:
        // 야외 걷기 경로(TMAP)는 출발지도 야외 좌표여야 한다. 실내 지점이
        // 출발지로 남아 있으면(실내에서 "출발지로 설정"한 매장을 그대로 들고
        // 나온 경우) 버리고 GPS 현재 위치에서 시작한다 — 건물 안 좌표를 그대로
        // 보내면 실내 두 지점 사이에 직선이 그려진다.
        // [_dropIndoorOriginIfOutdoors]가 상태도 함께 비우지만, 그 경로를 타지
        // 않은 호출(모드 전환 없이 들어온 경우)에도 같은 규칙이 적용되도록
        // 여기서 한 번 더 막는다.
        final indoorOrigin = origin?.floor != null || origin?.nodeId != null;
        await map?.showRouteTo(
          destination.point,
          label: destination.title,
          origin: indoorOrigin ? null : origin?.point,
        );

      // 층이 다르면 건물 전체 그래프로 층 간 경로(엘리베이터·에스컬레이터
      // 포함)를 계산한다. origin/destination을 다듬지 않고 그대로 넘긴다.
      //
      // 야외 경로(`showRouteTo`)와 **다른 메서드**다. 이름이 비슷하지만 하나는
      // Tmap 보행 경로, 하나는 건물 그래프 탐색이라 인자 타입부터 다르다.
      case WalkRouteKind.indoorFallback:
        await map?.showIndoorRouteTo(
          _asPoi(destination),
          origin: origin == null ? null : _asPoi(origin),
          preview: true,
        );
    }
  }

  /// 길찾기 후보를 지도가 받는 형태로 옮긴다.
  ///
  /// 층이 없으면 빈 문자열이다. 실내 갈래로 가는 후보는 [classifyWalkRoute]가
  /// 이미 층·노드를 둘 다 확인했으므로 그쪽에서는 이 폴백이 쓰이지 않는다.
  PoiSearchResult _asPoi(DirectionsCandidate candidate) => PoiSearchResult(
    name: candidate.title,
    floor: candidate.floor ?? '',
    point: candidate.point,
    nodeId: candidate.nodeId,
  );
}
