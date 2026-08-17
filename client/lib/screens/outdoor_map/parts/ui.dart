// ignore_for_file: invalid_use_of_protected_member
//
// part라 `setState`(protected) 호출이 경고로 잡힌다.
/// `OutdoorMapBodyState`의 **시트·배너·build 하위** 부분.
///
/// part 규약과 이 파일로 가른 이유는 `docs/client/outdoor-map-moves.md`.
part of '../outdoor_map_screen.dart';

extension OutdoorMapUi on OutdoorMapBodyState {
  void _showSnack(String message) => _showSnackGuarded(message, replace: false);

  /// 지금 떠 있는 안내를 걷어내고 새 안내를 띄운다.
  ///
  /// 자동 실내 진입은 '건물 감지 중...'을 먼저 띄우고 뒤이어 결과를 알린다.
  /// 그냥 showSnackBar를 부르면 두 번째 안내가 큐에 쌓여 첫 안내가 4초를 다
  /// 채운 뒤에야 뜬다 — 이미 끝난 작업의 진행 중 문구를 계속 보여주고, 하단
  /// 바를 그만큼 오래 가린다.
  void _replaceSnack(String message) =>
      _showSnackGuarded(message, replace: true);

  /// 같은 문구가 이미 떠 있으면(또는 큐에 남아 있으면) 다시 띄우지 않는다.
  ///
  /// GPS 틱·건물 감지처럼 **반복 호출되는 경로**가 같은 안내를 매번 다시 띄우면,
  /// 표시 시간이 그때마다 처음부터 다시 시작돼 "영원히 안 사라지는" 스낵바가
  /// 된다(replace 계열은 이전 것을 걷어내고 새로 띄우므로 특히 그렇다). 시각
  /// 기억 대신 "지금 그 문구가 떠 있는가"를 기준으로 거른다 — 닫힌 뒤의 정당한
  /// 재표시는 막지 않고, 테스트의 가짜 시계와도 어긋나지 않는다.
  void _showSnackGuarded(String message, {required bool replace}) {
    if (!mounted) return;
    if (_visibleSnackMessage == message) return;
    final messenger = ScaffoldMessenger.of(context);
    if (replace) messenger.hideCurrentSnackBar();
    _visibleSnackMessage = message;
    messenger
        .showSnackBar(SnackBar(content: Text(message)))
        .closed
        .whenComplete(() {
          if (_visibleSnackMessage == message) _visibleSnackMessage = null;
        });
  }

  Widget _buildBody() {
    final position = _position;
    final accuracy = position?.accuracy ?? 0;
    // GPS를 쓰지 않는 실내 상태에서는 신호 품질 배지도 띄우지 않는다. 위치가
    // 비어 있다는 이유로 "GPS 신호 약함"이 뜨면, 실내에서 GPS를 기다리는 중인
    // 것처럼 읽혀 실제 동작(PDR 기반)과 어긋난다.
    final lowAccuracy =
        _outdoorGpsVisible &&
        (position == null || accuracy > lowAccuracyThresholdMeters);
    final route = _route;
    final userDestination = _userDestination;
    final indoorRouteDestination = _indoorRouteDestination;
    // 거리·시간을 한 번에 계산한다(예전엔 같은 계산을 두 번 돌았다).
    final indoorEta = _indoorEta();
    final indoorRouteVisible = _hasAnyRouteVisible;
    final debugEnabled = _debugModeController.enabled;
    final pdrActive =
        indoorNavigationDriver.currentRuntimeStatus.state !=
        PdrRuntimeState.idle;
    final initialCenter = position == null
        ? fallbackLocation
        : ll.LatLng(position.latitude, position.longitude);

    return Stack(
      children: [
        if (_isMapSupportedOnThisPlatform)
          MapLibreMap(
            styleString: _baseMapStyle(),
            initialCameraPosition: CameraPosition(
              target: _toGl(initialCenter),
              zoom: 17,
            ),
            onMapCreated: (controller) => _mapController = controller,
            onStyleLoadedCallback: _onStyleLoaded,
            onMapClick: _handleMapClick,
            onCameraIdle: _handleCameraIdle,
            // _handleCameraIdle이 실내 진입/이탈을 판정하려면 현재 줌을 읽어야
            // 하는데, 이 값은 trackCameraPosition이 true일 때만 사용자의
            // pan/zoom을 따라 갱신된다(기본값 false면 초기 zoom 17에 고정 또는
            // 실기기에서 null). 그 상태에선 사용자가 축소해도 exit 조건이
            // 판정되지 않아 층 선택기·위치 지정 버튼이 계속 남는다.
            trackCameraPosition: true,
            // 웹의 maplibre_gl은 기본값(false)이면 상호작용 가능한 벡터 레이어
            // (건물 fill처럼 enableInteraction이 켜진 레이어)를 탭한 순간 별도
            // feature-tap만 발화하고 onMapClick은 삼켜버린다. 그러면 사용자가
            // 실내 진입 오버레이 위에서 "위치 지정" → 건물 폴리곤을 탭했을
            // 때 _handleMapClick이 아예 호출되지 않아 PDR 앵커 배치가 조용히
            // 실패한다. 이 값을 켜서 feature-tap이 있어도 onMapClick도 함께
            // 오게 만든다.
            // 실내 오버레이 레이어는 전부 인터랙션을 꺼 두었다 — 이유는
            // _ensureIndoorTilesRegistered의 레이어 등록 주석 참고.
            featureTapsTriggersMapClick: true,
            compassEnabled: false,
            myLocationEnabled: false,
            logoEnabled: false,
            attributionButtonPosition: AttributionButtonPosition.bottomRight,
            scrollGesturesEnabled: _interactive,
            zoomGesturesEnabled: _interactive,
            rotateGesturesEnabled: _interactive,
            tiltGesturesEnabled: _interactive,
            dragEnabled: _interactive,
          )
        else
          const ColoredBox(color: AppColors.surface),

        // 층 전환이 오래 걸릴 때만 지도 위 중앙에 뜨는 에스컬레이터 모티프.
        // 이전 층 도면이 그대로 보이는 위에 뜬다 — 덮개(베일)는 없다. 실기기
        // 에서 흰 베일이 캡처 플래시처럼 번쩍여 걷어냈고, 모티프는 자체 카드
        // 배경이 있어 도면 위에서도 읽힌다. 타이밍 정책은
        // map/camera/floor_switch_progress.dart. AnimatedSwitcher가 등장·퇴장을
        // 페이드로 처리하고, 숨김이 끝나면 위젯을 트리에서 내려 벨트 애니메이션
        // ticker도 함께 멈춘다. IgnorePointer라 지도 조작을 안 막는다.
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: _floorSwitchMotifVisible
                  ? Center(
                      child: FloorSwitchEscalatorMotif(
                        direction: _floorSwitchMotifDirection,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),

        // 실내 진입 시 야외만 어둡게 덮는 dim scrim은 위젯 트리가 아니라
        // MapLibre fill 레이어(_dimScrimFillLayerId)로 처리한다. 위젯 스크림은
        // PlatformView 위에 얹혀 야외 base와 실내 MVT 오버레이를 한꺼번에 덮어
        // 실내까지 어두워지는 문제가 있었다. 지금은 세계를 덮는 outer ring +
        // 건물 footprint를 hole로 뚫은 폴리곤을 스크림 레이어로 그리고, 실내
        // 오버레이 아래에 삽입해 건물 안쪽만 밝게 스포트라이트된다.
        // **낮은 강도로 둔다.** 예전에는 단색 노랑 알약에 같은 색 글로우까지
        // 얹혀 있어, 지도 위에서 가장 시끄러운 것이 "GPS가 조금 부정확하다"였다.
        // 경로를 벗어났다는 알림([EtaCard]의 wrong-way, 빨강)보다 세면 무엇이
        // 급한지가 뒤집힌다. 연한 배경 + 같은 계열 글자로 내린다.
        //
        // **누를 수 없다.** 배지는 지금 상태를 읽는 표시일 뿐이고, 사용자가
        // 할 수 있는 일이 없다 — 정확도는 기다리면 회복된다.
        if (lowAccuracy)
          const Positioned(
            top: 76,
            left: 12,
            child: RoutexBadge(
              label: 'GPS 신호 약함',
              tone: RoutexBadgeTone.warning,
              icon: Icons.warning_amber_rounded,
              surface: RoutexBadgeSurface.onMap,
            ),
          ),

        // 건물을 못 불러오면 층 선택기·위치 지정·실내 진입·실내 도면이 통째로
        // 사라진다. 그 이유를 화면에 남기고 재시도 경로를 준다 — 예전에는 이
        // 상태가 아무 표시 없이 조용히 지나갔다.
        //
        // 자리는 위치 지정 안내와 같은 [placingHintTopPx]다. **누를 수 있어야
        // 하므로 GPS 배지 자리(top 76)를 쓰면 안 된다** — 거기는 MapShellScreen의
        // 카테고리 chip 열(top 78)에 덮여 탭이 chip으로 먹힌다. 두 오버레이는
        // 동시에 뜨지 않는다.
        //
        // **배지가 아니다.** 사용자가 할 일이 있는 상태라 문장과 행동을 가진
        // 알림으로 그린다. GPS 배지와 같은 모양이면 "누르면 되는 것"과 "읽기만
        // 하는 것"이 구분되지 않는다.
        if (_buildingLoadFailed)
          Positioned(
            top: placingHintTopPx,
            left: 12,
            right: 12,
            child: SafeArea(
              bottom: false,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: KeyedSubtree(
                  key: _buildingLoadFailedKey,
                  child: RoutexInlineNotice(
                    message: _retryingBuildingLoad
                        ? '건물 정보를 다시 불러오는 중…'
                        : '건물 정보를 불러오지 못했습니다',
                    // 다시 부르는 중에는 행동을 걷는다 — 같은 요청을 겹쳐 보내는
                    // 것을 막고, 지금 무엇을 하는 중인지는 문장이 말한다.
                    actionLabel: _retryingBuildingLoad ? null : '다시 시도',
                    onAction: _retryingBuildingLoad
                        ? null
                        : () => unawaited(_retryBuildingLoad()),
                  ),
                ),
              ),
            ),
          ),

        // GPS 실내 진입 판정의 근거를 그 자리에서 읽기 위한 진단 칩.
        //
        // 실기기를 들고 건물을 드나드는 실험에서, 화면에 보이는 유일한 신호는
        // "건물 감지 중…" 스낵바와 도면 전환뿐이라 **안 걸렸을 때 원인을 알
        // 방법이 없었다.** 오차가 커서 건너뛴 것인지, 안쪽 문턱을 못 넘은
        // 것인지, 자동 진입이 꺼져 있는 것인지가 이 한 줄에서 갈린다.
        //
        // 자리는 건물 로드 실패 배지([placingHintTopPx]) 한 줄 아래다. 둘은
        // 동시에 뜰 수 있고(외곽선을 못 받으면 칩은 '외곽선 없음'을 띄운다),
        // 겹치면 정작 원인을 가린다. 칩 자체는 IgnorePointer라 탭을 안 먹는다.
        if (debugEnabled)
          Positioned(
            top: placingHintTopPx + 44,
            left: 12,
            child: SafeArea(
              bottom: false,
              // 두 칩을 한 열에 쌓는다. 각자 Positioned로 띄우고 top에 상수를
              // 더하면, 칩 높이가 바뀔 때마다 두 자리를 같이 고쳐야 하고 한쪽만
              // 고치면 겹친다. 층 전환 칩을 아래에 두는 이유는 순서다 — 건물에
              // 들어가야(위 칩) 층 판정이 돌기 시작한다(아래 칩).
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder<String?>(
                    valueListenable: _gpsVerdictDebugText,
                    builder: (_, text, _) => MapDebugChip(text: text),
                  ),
                  const SizedBox(height: 6),
                  ValueListenableBuilder<String?>(
                    valueListenable: _escalatorDebugText,
                    builder: (_, text, _) => MapDebugChip(text: text),
                  ),
                  const SizedBox(height: 6),
                  // heading 칩은 맨 아래다 — 위 둘과 같은 순서 규칙이다(건물에
                  // 들어가야 층이 돌고, 층 도면이 있어야 실내 마커가 뜬다).
                  ValueListenableBuilder<String?>(
                    valueListenable: _headingDebugText,
                    builder: (_, text, _) => MapDebugChip(text: text),
                  ),
                ],
              ),
            ),
          ),

        // 실내 진입 오버레이 — 야외 지도 위 좌측 하단에 세로 층 선택기를 얹어
        // 실내 화면과 동일한 위치·디자인으로 층을 훑을 수 있게 한다.
        //
        // **안내 중에는 접는다.** 안내가 도는 동안 층은 사용자가 고르는 것이
        // 아니라 경로가 정한다 — 층이 바뀌는 순간 [_enqueueFloorTransition]이
        // 도면을 갈아 끼운다. 안내 중에 남겨 두면 사용자가 고른 층과 경로가
        // 가리키는 층이 어긋난 화면이 생기고, 그 상태를 정리할 규칙이 없다.
        // 판정이 틀렸을 때의 출구는 안내 종료다(그러면 선택기가 다시 펴진다) —
        // 판정기가 스스로 아니라고 본 경우는 묻지 않고 화면이 되돌린다.
        if (_indoorEntered &&
            !_guidanceActive &&
            _building != null &&
            _activeFloor != null &&
            _building!.floors.isNotEmpty)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            left: 16,
            bottom:
                floorSelectorBottomOffset +
                (indoorRouteVisible ? bottomBarLiftPx : 0),
            child: SafeArea(
              top: false,
              child: FloorSelector(
                key: _floorSelectorKey,
                floors: _building!.floors,
                selectedFloor: _activeFloor!,
                onSelectFloor: _onFloorChipSelected,
              ),
            ),
          ),

        // 안내 중 "내 위치로" — 방금 접힌 층 선택기와 **같은 자리**에 놓는다.
        // 안내가 시작되면 그 자리가 비고, 사용자는 이미 거기에 조작이 있다는
        // 것을 알고 있다.
        //
        // 안내 중에만 띄우는 이유는 [GuidanceRecenterButton] 주석에 있다 —
        // 평상시에는 하단 바의 "위치 보정"이 그 자리를 대신하므로, 둘을 같이
        // 띄우면 비슷하게 생긴 두 조작이 화면에 남는다.
        if (_guidanceActive && _canRecenterOnCurrentPosition)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            left: 16,
            bottom:
                floorSelectorBottomOffset +
                (indoorRouteVisible ? bottomBarLiftPx : 0),
            child: SafeArea(
              top: false,
              child: GuidanceRecenterButton(
                key: const Key('guidance-recenter'),
                onPressed: () => unawaited(_recenterOnCurrentPosition()),
              ),
            ),
          ),

        // 디버그 전용 — 강제 층 전환. "내 위치로" 버튼 바로 위, 안내 중 +
        // 디버그 모드 + 에스컬레이터 환승이 남아 있을 때만 뜬다.
        // 무엇을 태우는지는 [_debugForceFloorTransition]에 있다.
        if (debugEnabled && _guidanceActive && _debugForceableTransfer != null)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            left: 16,
            bottom:
                floorSelectorBottomOffset +
                (indoorRouteVisible ? bottomBarLiftPx : 0) +
                52,
            child: SafeArea(
              top: false,
              child: Material(
                color: Colors.white.withValues(alpha: 0.96),
                elevation: 3,
                shadowColor: Colors.black.withValues(alpha: 0.16),
                shape: StadiumBorder(
                  side: BorderSide(
                    color: AppColors.indoor.withValues(alpha: 0.2),
                  ),
                ),
                child: IconButton(
                  key: const Key('debug-force-floor-transition'),
                  tooltip: '층 전환 시뮬레이션',
                  onPressed: _debugForceFloorTransition,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 44,
                  ),
                  icon: const Icon(Icons.escalator, size: 20),
                ),
              ),
            ),
          ),

        // PDR 제어 — 실내 지도 탭과 같은 자리(하단 홈/실내 세그먼트 왼쪽,
        // 층 선택기 옆)에 같은 위젯으로 놓는다. 두 화면에서 버튼이 옮겨 다니면
        // 실측 중에 "지금 어느 화면인지"를 먼저 확인해야 해서 테스트가 끊긴다.
        //
        // 노출 조건에 pdrActive를 함께 두는 이유: 세션이 도는 중에 사용자가
        // 지도를 축소하면 _handleCameraIdle이 실내 진입 오버레이를 끄는데,
        // 그때 버튼까지 사라지면 방금 걸은 세션을 내보낼 수단이 없어진다.
        if (debugEnabled && (_indoorEntered || pdrActive))
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            right: pdrControlRightInsetPx,
            bottom: indoorRouteVisible ? bottomBarLiftPx : 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(
                  bottom: bottomBarInnerBottomPaddingPx,
                ),
                child: PdrMapControl(
                  key: _pdrControlKey,
                  canExport: _pdrDebugRecorder?.hasSnapshot ?? false,
                  exporting: _exportingPdrDebugJson,
                  onExport: () => unawaited(_exportPdrDebugJson()),
                  shareButtonKey: _pdrShareButtonKey,
                ),
              ),
            ),
          ),

        // 디버그 설정 진입점(왼쪽 하단 벌레 아이콘)은 앱 메뉴(햄버거)로 옮겼다.
        // 실내 진입 오버레이가 켜졌을 때만 뜨는 버튼이라, 그 상태에 있는지에 따라
        // 개발 도구가 나타났다 사라지는 화면이기도 했다.
        if (_indoorEntered && _placingPdrAnchor)
          Positioned(
            top: placingHintTopPx,
            left: 12,
            right: 12,
            child: SafeArea(
              bottom: false,
              child: PlacingAnchorHint(
                key: _placingHintKey,
                onCancel: () => unawaited(_cancelPdrAnchor()),
              ),
            ),
          ),

        // 도착 카드는 지도 한가운데다. 하단 배너와 같은 자리에 두면 도착도
        // 걷는 중 안내와 같은 무게로 읽혀, 안내가 끝난 줄 모르고 계속 걷는다.
        if (_arrivedDestination case final arrived?)
          // 카드 바깥은 그대로 지도다 — Center는 자식 밖의 탭을 잡지 않으므로
          // 도착 뒤에도 주변을 둘러볼 수 있다.
          Positioned.fill(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: IndoorArrivalCard(
                  key: _arrivalCardKey,
                  destinationName: arrived.name,
                  destinationFloor: arrived.floor,
                  onConfirm: _confirmArrival,
                  onConfirmPointerDown: (position) =>
                      _etaClosePointerDown = position,
                ),
              ),
            ),
          ),

        // 도착하면 하단 배너를 걷는다. 도착 문구는 화면에 하나여야 하고, 그
        // 하나는 위 도착 카드다 — 걷는 중 안내와 같은 자리·같은 무게로 또 말하면
        // 안내가 끝난 줄 모르고 계속 걷는다. 지나쳐 걸어가 안내가 되살아나면
        // (`arrived`가 풀리면) 배너도 함께 돌아온다.
        if (indoorRouteDestination != null && !_showingArrivalOnly)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                // 배너를 탭하면 경로 전체 단계 목록이 올라온다. 배너 자체는
                // "다음 한 수"만 말하므로, 전체를 보고 싶은 사용자가 갈 곳이
                // 여기뿐이다. 종료 버튼은 Listener가 먼저 받아 탭과 겹치지
                // 않는다.
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _showIndoorRouteSteps(indoorRouteDestination),
                  child: EtaCard(
                    key: _etaCardKey,
                    distanceMeters: indoorEta.distanceM,
                    // 시간은 비용 기준 — 엘리베이터 대기·탑승 시간이 여기 들어 있다.
                    minutes:
                        (indoorEta.costM /
                                indoorWalkingSpeedMetersPerSecond /
                                60)
                            .ceil()
                            .clamp(1, 999),
                    label: _indoorEtaLabel(indoorRouteDestination),
                    instruction: _indoorRouteGuidance,
                    // 미리 보는 동안은 계획 카드다 — 경로만 그려 두고, 따라가기는
                    // 이 버튼을 누른 뒤에 시작한다.
                    onStartGuidance: _indoorRoutePreview
                        ? () => unawaited(_startIndoorGuidance())
                        : null,
                    onClose: _dismissIndoorRouteFromEtaCard,
                    onClosePointerDown: (position) =>
                        _etaClosePointerDown = position,
                  ),
                ),
              ),
            ),
          )
        // 대중교통 안내는 도보 ETA 카드와 **같은 자리**를 쓰고 서로를 밀어낸다.
        // 두 카드가 함께 뜨면 한 화면에서 소요 시간이 두 개가 되어, 지도에
        // 그려진 선이 어느 쪽인지 알 수 없다.
        else if (_transitItinerary case final itinerary?)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: TransitSummaryCard(
                  key: _etaCardKey,
                  itinerary: itinerary,
                  label: _transitLabel ?? '목적지까지',
                  onClose: _dismissUserDestinationFromEtaCard,
                  onClosePointerDown: (position) =>
                      _etaClosePointerDown = position,
                ),
              ),
            ),
          )
        else if (route != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: EtaCard(
                  key: _etaCardKey,
                  distanceMeters: _outdoorEta(route).distanceM,
                  minutes: _outdoorEta(route).minutes,
                  label: userDestination != null
                      ? (_userDestinationLabel ?? '목적지까지')
                      : '건물 입구까지',
                  onClose: userDestination != null
                      ? _dismissUserDestinationFromEtaCard
                      : null,
                  // 자동차 계획 상태에서만 붙는다. 누르면 카메라가 현재 위치로
                  // 내려가고 버튼은 사라진다([startFollowingCurrentLocation]).
                  onStartGuidance: _offerStartGuidance
                      ? () => unawaited(startFollowingCurrentLocation())
                      : null,
                  onClosePointerDown: userDestination != null
                      ? (position) => _etaClosePointerDown = position
                      : null,
                ),
              ),
            ),
          ),

        // 진입·이탈 전환 연출. **Stack 맨 위여야 한다** — 덮개의 존재 이유가
        // 화면이 갈리는 순간을 가리는 것이라, 배지·ETA 카드·층 선택기가 그 위에
        // 남으면 덮은 의미가 없다. 연출 중이 아니면 스스로 빈 위젯이 된다.
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _indoorTransition,
            builder: (context, _) => IndoorTransitionOverlay(
              progress: _indoorTransition.value,
              direction: _indoorTransitionDirection,
              buildingName: _building?.name,
            ),
          ),
        ),
      ],
    );
  }
}
