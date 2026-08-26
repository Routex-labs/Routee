// ignore_for_file: invalid_use_of_protected_member
//
// part라 `setState`(protected) 호출이 경고로 잡힌다.
/// `OutdoorMapBodyState`의 **시트·배너·build 하위** 부분.
///
/// part 규약과 이 파일로 가른 이유는 `docs/client/outdoor-map-moves.md`.
part of '../outdoor_map_screen.dart';

extension OutdoorMapUi on OutdoorMapBodyState {
  /// 화면 바닥에 도킹하는 카드(도착·ETA·대중교통 요약)를 **탭 줄 위에 앉힌다.**
  ///
  /// 카드는 지도 Stack 안이고 탭 줄은 셸 Stack의 윗층이라, `bottom: 0`으로 두면
  /// 탭 줄이 카드의 아랫부분을 덮는다 — 실기기에서 지표 줄("1.2km · 거리")이
  /// 통째로 사라지고 `안내 시작` 버튼의 아래 모서리가 잘렸다. 겹치는 구간은
  /// **카드가 뜬 뒤 시작을 누르기 전까지 전부**다: 탭 줄이 접히는 조건은
  /// `_guidanceActive`(=시작을 누른 뒤)이므로 그 전에는 늘 둘 다 바닥에 있다.
  ///
  /// **띄운 만큼 카드의 아래 안전영역은 끈다.** 그 영역은 탭 줄이 이미 자기
  /// [SafeArea]로 갖고 있어, 두면 두 번 세어 카드 밑에 흰 띠가 남는다.
  Widget _bottomDockedCard(Widget card) {
    final lift = widget.bottomCardLiftPx;
    return Positioned(
      left: 0,
      right: 0,
      bottom: lift,
      child: MediaQuery.removePadding(
        context: context,
        removeBottom: lift > 0,
        child: card,
      ),
    );
  }

  /// 하단 바 바로 위의 자리. 계산과 근거는 [aboveMapBottomBarPx].
  ///
  /// ETA 카드가 뜰 때의 [bottomBarLiftPx]는 **부르는 쪽이 더한다** — 카드에
  /// 따라 함께 올라갈지가 얹는 것마다 다르다(축척은 야외 경로, 스낵바는 모든
  /// 경로를 본다).
  double get _aboveBottomBarPx =>
      aboveMapBottomBarPx(widget.bottomOverlayLiftPx);

  void _showSnack(String message, {Duration? duration}) =>
      _showSnackGuarded(message, replace: false, duration: duration);

  /// **읽고 나서 할 일이 없는** 한 줄 안내가 떠 있는 시간.
  ///
  /// 기본 4초는 "되돌리기가 붙은 알림"의 시간이라([RoutexFeedbackTiming]) 손이
  /// 닿을 여유까지 재 둔 값이다. 누를 것이 없는 안내를 그만큼 붙들면 하단 바를
  /// 그 시간 내내 가린다 — 사용자는 그동안 다른 조작을 못 한다.
  static const _briefSnackDuration = RoutexFeedbackTiming.toastVisibility;

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
  void _showSnackGuarded(
    String message, {
    required bool replace,
    Duration? duration,
  }) {
    if (!mounted) return;
    if (_visibleSnackMessage == message) return;
    final messenger = ScaffoldMessenger.of(context);
    if (replace) messenger.hideCurrentSnackBar();
    _visibleSnackMessage = message;
    messenger
        .showSnackBar(
          SnackBar(
            content: Text(message),
            duration: duration ?? const Duration(seconds: 4),
            // **하단 바 위로 띄운다.** 기본 SnackBar는 화면 맨 아래에 붙어
            // "위치 지정"·"위치 보정" 버튼을 통째로 덮는데, 이 안내들이 하필
            // 그 버튼을 누르라고 말하는 문장이다 — 읽고 나서 누를 것을 자기가
            // 가리고 있었다. ETA 카드가 뜨면 버튼과 함께 그만큼 더 올라간다.
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              left: RoutexSpacing.componentPadding,
              right: RoutexSpacing.componentPadding,
              // **안전영역을 여기서 더한다.** floating SnackBar는 제 SafeArea를
              // 아래로는 끄고(`snack_bar.dart`), 이 화면의 Scaffold는
              // `resizeToAvoidBottomInset: false`라 배치도 그것을 안 세 준다 —
              // 안 더하면 제스처 바가 있는 기기에서 그만큼 낮게 떠 버튼을 덮는다.
              bottom:
                  _aboveBottomBarPx +
                  MediaQuery.paddingOf(context).bottom +
                  (_hasAnyRouteVisible ? bottomBarLiftPx : 0),
            ),
          ),
        )
        .closed
        .whenComplete(() {
          if (_visibleSnackMessage == message) _visibleSnackMessage = null;
        });
  }

  /// 지도 축척 막대. 카메라가 움직일 때마다 값이 바뀌므로 컨트롤러를 직접
  /// 듣는다 — `trackCameraPosition: true`라 확대/이동마다 notify가 온다.
  /// `onCameraIdle`만 보면 손가락을 떼기 전까지 옛 값이 남는다.
  ///
  /// [fallbackLatitude]는 카메라를 아직 못 읽었을 때 쓴다. 축척은 위도에 따라
  /// 달라지지만 한 도시 안에서는 차이가 0.1%도 안 돼, 첫 프레임의 근사로 충분하다.
  Widget _buildScaleBar(double fallbackLatitude) {
    final controller = _mapController;
    if (controller == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: controller,
      builder: (_, _) {
        final camera = controller.cameraPosition;
        if (camera == null) return const SizedBox.shrink();
        return MapScaleBar(
          step: mapScaleStepFor(
            metersPerPixel: metersPerPixelAt(
              zoom: camera.zoom,
              latitude: camera.target.latitude,
            ),
            maxWidthPx: kMapScaleBarMaxWidthPx,
          ),
        );
      },
    );
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
    // 안내 중 하단 카드가 셋 중 어느 것이든 같은 버튼을 받는다 — 실내→야외
    // 여정이 도보로도 대중교통으로도 시작될 수 있어서다.
    final transition = _guidanceStarted && !_showingArrivalOnly
        ? _guidanceTransitionAction()
        : null;
    final arrived = _arrivedDestination;
    // 지도 위 안내는 **한 자리**다. 무엇이 그 자리를 쓰는지는 [GuidanceBanner]가
    // 정한다 — 여기서는 각 상태의 재료만 넘긴다.
    //
    // 도착 배너는 [_guidanceStarted]가 풀린 뒤에도 남는다. 도착 몇 초 뒤 경로가
    // 스스로 지워지는데(_syncArrival), 그때 배너까지 사라지면 화면 위쪽이 안내
    // 도중에 통째로 비어 버린다. 닫는 것은 도착 카드의 `안내 종료`뿐이다.
    final topBanner = GuidanceBanner(
      instruction: _guidanceStarted && !_showingArrivalOnly
          ? _indoorRouteGuidance
          : null,
      floorTransition: _guidanceStarted ? _floorTransitionUiState : null,
      arrivalAt: arrived == null
          ? null
          : [
              arrived.name,
              if (arrived.floor.isNotEmpty) arrived.floor,
            ].join(' · '),
    );
    final initialCenter = position == null
        ? fallbackLocation
        : ll.LatLng(position.latitude, position.longitude);

    return Stack(
      children: [
        if (_isMapSupportedOnThisPlatform)
          // **손을 대면 팔로우가 물러난다.** MapLibre는 PlatformView라
          // onCameraIdle만으로는 사용자가 민 것인지 우리가 민 것인지 가릴 수
          // 없다. 지도 위 pointer-down은 어느 쪽이든 "지금은 내가 본다"는 뜻이라
          // 그걸 신호로 쓴다. 지도 위 Flutter 버튼(내 위치 등)은 Stack에서
          // 먼저 히트되므로 여기까지 내려오지 않는다.
          Listener(
            onPointerDown: (_) => _releaseFollowCamera(),
            child: MapLibreMap(
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
              // 저작권(ⓘ) 버튼은 `logoEnabled`처럼 끌 스위치가 없다 — 플러그인이
              // 네이티브에서 `attributionEnabled(true)`로 못박아 둔다(maplibre_gl
              // 0.26.2 · MapLibreMapBuilder.java). 남겨 두면 흰 동그라미가 지도
              // 오른쪽 아래, 하단 탭 줄 '저장' 글자 위에 앉는다.
              // 그래서 여백으로 화면 밖에 세운다: 아래 여백이 지도보다 크면
              // 버튼이 위쪽 경계를 넘어가 잘린다. 위치를 옮기면 다시 보인다.
              attributionButtonPosition: AttributionButtonPosition.bottomRight,
              attributionButtonMargins: const Point<num>(0, 100000),
              scrollGesturesEnabled: _interactive,
              zoomGesturesEnabled: _interactive,
              rotateGesturesEnabled: _interactive,
              tiltGesturesEnabled: _interactive,
              dragEnabled: _interactive,
            ),
          )
        else
          const ColoredBox(color: AppColors.surface),

        if (!topBanner.isEmpty)
          Positioned(
            top: 0,
            left: 12,
            right: 12,
            child: SafeArea(
              bottom: false,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: indoorRouteDestination == null
                    ? null
                    : () => _showIndoorRouteSteps(indoorRouteDestination),
                child: topBanner,
              ),
            ),
          ),

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

        // GPS 배지는 **낮은 강도로 둔다.** 예전에는 단색 노랑 알약에 같은 색 글로우까지
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

        // 축척 막대는 **위치 보정·위치 지정 버튼 바로 위**다. 그 두 버튼과 같은
        // 오른쪽 끝선(16)에 세워 한 열로 읽히게 하고, ETA 카드가 뜨면 버튼과
        // 함께 올라간다 — 따로 두면 카드가 막대만 덮는다.
        //
        // 높이는 [_aboveBottomBarPx]가 잰다. 상수(112)로 두었더니 탭 줄이 생긴
        // 뒤 그만큼 밀려 올라간 "위치 보정"(GPS) 버튼 위로 자가 걸쳤다.
        AnimatedPositioned(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          right: RoutexSpacing.componentPadding,
          bottom:
              _aboveBottomBarPx +
              (indoorRouteVisible ? bottomBarLiftPx : 0),
          child: SafeArea(
            top: false,
            child: IgnorePointer(child: _buildScaleBar(initialCenter.latitude)),
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
        // **"안내 시작" 카드가 뜨는 순간 접는다**([_guidancePlanned]). 카드가
        // 뜬 뒤로 층은 사용자가 고르는 것이 아니라 경로가 정한다 — 층이 바뀌는
        // 순간 [_enqueueFloorTransition]이 도면을 갈아 끼운다. 남겨 두면
        // 사용자가 고른 층과 경로가 가리키는 층이 어긋난 화면이 생기고, 그
        // 상태를 정리할 규칙이 없다. 판정이 틀렸을 때의 출구는 카드를 닫거나
        // 안내를 끝내는 것이다(그러면 선택기가 다시 펴진다).
        if (_indoorEntered &&
            !_guidancePlanned &&
            _building != null &&
            _activeFloor != null &&
            _building!.floors.isNotEmpty)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            left: 16,
            bottom:
                floorSelectorBottomOffset +
                (indoorRouteVisible ? bottomBarLiftPx : 0) +
                widget.bottomOverlayLiftPx,
            child: SafeArea(
              top: false,
              // 키가 열 전체를 덮어야 한다. 선택기에만 걸면 그 위 "내 위치로"를
              // 누른 탭이 지도까지 새어들어가 건물 밖 탭으로 판정된다
              // ([_floorSelectorKey]의 주석이 말하는 그 증상).
              child: KeyedSubtree(
                key: _floorSelectorKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // **다른 층을 볼 때의 "돌아오는 문"은 여기 없다.** 화살표
                    // 버튼을 따로 띄웠더니 하단 바의 "위치 보정"(GPS)과 하는 일이
                    // 같은 버튼이 화면에 둘이 되어, 어느 쪽을 눌러야 내 자리로
                    // 가는지가 갈렸다. 그 일은 GPS 버튼 하나가 한다 —
                    // 다른 층을 보는 중이면 [_recalibrateIndoor]가 층부터
                    // 되돌린다([_returnToMyFloor]).
                    //
                    // 편의시설은 **층 선택기 바로 위**다. 둘 다 "건물 안에서 몸을
                    // 옮기는" 조작이고, 상단 카테고리 칩 줄은 엄지에서 가장 먼
                    // 자리다. 조건부인 위 버튼이 이 아래가 아니라 위에 붙는 이유는
                    // 자리 이동 때문이다 — 뜨고 질 때마다 아래 둘이 밀리면 방금
                    // 누른 자리가 매번 달라진다.
                    if (widget.onFacilitiesTap case final onPressed?) ...[
                      RoutexMapControl(
                        key: const Key('nearby-facilities'),
                        label: '가까운 편의시설',
                        // Kit에 시설 글리프가 없다. `wc`는 셋 중 가장 많이 찾는
                        // 화장실을 가리키면서 "편의시설"로도 읽히는 유일한 아이콘이다
                        // (엘리베이터·에스컬레이터 글리프는 그 하나만 가리킨다).
                        icon: Icons.wc_rounded,
                        tone: widget.facilitiesActive
                            ? RoutexMapControlTone.active
                            : RoutexMapControlTone.neutral,
                        onPressed: onPressed,
                      ),
                      const SizedBox(height: RoutexSpacing.controlGap),
                    ],
                    FloorSelector(
                      floors: _building!.floors,
                      selectedFloor: _activeFloor!,
                      onSelectFloor: _onFloorChipSelected,
                    ),
                  ],
                ),
              ),
            ),
          ),

        // 안내 중의 "위치 보정" — 안내가 시작되면 셸의 하단 바가 통째로 접히므로
        // (그 줄의 나머지 둘은 출발점을 잡는 조작이라 걷는 중에는 쓸 일이 없다)
        // **그 자리에 GPS 버튼만 남긴다.** 오른쪽 끝선(16)·맨 아랫줄이라 접히기
        // 전 하단 바의 그 버튼과 같은 자리다.
        //
        // **같은 버튼이어야 한다.** 예전에는 여기에 화살표([Icons.near_me])를
        // 띄웠는데, 하는 일("내 자리로 돌아간다")이 GPS 버튼과 같으면서 모양만
        // 달라 안내를 시작하는 순간 버튼이 바뀐 것처럼 보였다. 하는 일이 하나면
        // 버튼도 하나다.
        //
        // **하는 일은 카메라 조작이다.** 평상시의 위치 보정은 PDR 앵커를 다시
        // 잡지만, 걷는 도중 앵커를 옮기면 진행률 기준이 그 자리에서 바뀐다.
        // 그래서 안내 중에는 [_recenterOnCurrentPosition]만 부른다(다른 층에
        // 있으면 층부터 되돌린다).
        //
        // **자리를 비우지 않는다.** 되돌릴 자리를 아직 모르는 동안에도 버튼은
        // 그대로 두고 꺼 둔다 — 뜨고 지는 버튼은 누르려던 손이 빈자리를 짚는다.
        if (_guidanceActive)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            right: RoutexSpacing.componentPadding,
            bottom:
                floorSelectorBottomOffset +
                (indoorRouteVisible ? bottomBarLiftPx : 0),
            child: SafeArea(
              top: false,
              child: RoutexMapControl(
                key: const Key('guidance-recenter'),
                label: '위치 보정',
                icon: Icons.my_location,
                // 접히기 전의 하단 바 버튼과 같은 tone이어야 같은 조작으로 읽힌다.
                tone: RoutexMapControlTone.accent,
                onPressed: _viewingOtherFloor
                    ? () => unawaited(_returnToMyFloor())
                    : _canRecenterOnCurrentPosition
                    ? () => unawaited(_recenterOnCurrentPosition())
                    : null,
              ),
            ),
          ),

        // 디버그 전용 — 강제 층 전환. 위층·아래층 두 개가 **오른쪽 아래**,
        // 하단 바보다 한 칸 위에 선다. 왜 그 자리인지·조건이 왜 `_activeFloor`인지는
        // docs/client/debug-floor-toggle-button.md.
        //
        // **안내 중이 아니어도 뜬다** — 책상에서는 GPS가 실내 상태를 지워 안내를
        // 끝까지 못 태우는데, 층 전환 연출은 그와 무관하게 봐야 한다. 무엇을
        // 태우는지는 [_debugForceFloorTransition]에 있다.
        //
        // 그림은 **방향 화살표**다. 실제로 가는 층은 도면의 탑승 노드 이름이
        // 정하고 두 층을 건너뛰기도 하지만, 그 층을 버튼에 적을 수는 없다 —
        // [RoutexMapControl]은 그림을 하나만 받는다(아래 주석).
        if (debugEnabled && _activeFloor != null)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            right: RoutexSpacing.componentPadding,
            // 축척 막대([_aboveBottomBarPx]) **한 칸 위**다. 예전에는 하단 바
            // baseline에서 한 칸만 올렸는데, 그 자리는 축척 막대와 "위치 보정"
            // (GPS) 버튼이 이미 쓰고 있어 셋이 겹쳤다 — 디버그 버튼이 GPS
            // 버튼을 덮어 안내 중에 위치 보정을 누를 수 없었다.
            bottom:
                _aboveBottomBarPx +
                (indoorRouteVisible ? bottomBarLiftPx : 0) +
                RoutexMetrics.minimumTouchTarget +
                RoutexSpacing.controlGap,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final up in const [true, false])
                    Padding(
                      padding: EdgeInsets.only(bottom: up ? 8 : 0),
                      child: Builder(
                        builder: (context) {
                          final boarding = _debugEscalatorBoarding(up: up);
                          return DebugFloorTransitionControl(
                            key: Key(
                              'debug-force-floor-transition-${up ? 'up' : 'down'}',
                            ),
                            up: up,
                            targetFloorLabel: boarding?.name.otherFloorLabel,
                            onPressed: boarding == null
                                ? null
                                : () => _debugForceFloorTransition(up: up),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),

        // PDR 제어 — **오른쪽 위**, 디버그 칩 열과 같은 줄이다. 하단은 도착
        // 카드·ETA 카드가 통째로 덮어, 실측 직후 세션 JSON을 꺼낼 수 없었다.
        // 자리를 고른 이유는 [pdrControlTopPx].
        //
        // 노출 조건에 pdrActive를 함께 두는 이유: 세션이 도는 중에 사용자가
        // 지도를 축소하면 _handleCameraIdle이 실내 진입 오버레이를 끄는데,
        // 그때 버튼까지 사라지면 방금 걸은 세션을 내보낼 수단이 없어진다.
        if (debugEnabled && (_indoorEntered || pdrActive))
          Positioned(
            top: pdrControlTopPx,
            right: RoutexSpacing.componentPadding,
            child: SafeArea(
              bottom: false,
              child: PdrMapControl(
                key: _pdrControlKey,
                canExport: _pdrDebugRecorder?.hasSnapshot ?? false,
                exporting: _exportingPdrDebugJson,
                onExport: () => unawaited(_exportPdrDebugJson()),
                shareButtonKey: _pdrShareButtonKey,
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

        // 도착은 Runtime Kit의 전용 표면으로 바뀐다. 안내 중 배너는 아래에서
        // 구조적으로 빠지므로 같은 자리에 있어도 진행 상태와 섞이지 않는다.
        //
        // 여기까지 안내해 놓고 "그래서 이 매장이 뭔데"로 가는 길을 끊지 않는다 —
        // 상세를 못 여는 목적지(placeId 없는 POI)에서만 그 버튼이 빠진다.
        if (arrived != null)
          _bottomDockedCard(
            IndoorArrivalCard(
              key: _arrivalCardKey,
              destinationName: arrived.name,
              destinationFloor: arrived.floor,
              onConfirm: _confirmArrival,
              onShowDetail: arrived.placeId == null
                  ? null
                  : () => widget.onStoreTap?.call(arrived),
              onConfirmPointerDown: (position) =>
                  _etaClosePointerDown = position,
            ),
          ),

        // 도착하면 남은 거리·시간 카드를 걷는다. **끝난 여정의 `0m`는 정보가
        // 아니다** — 걷는 중과 같은 자리·같은 모양으로 남아 있으면 안내가 끝난
        // 줄 모르고 계속 걷는다. 그 자리는 도착 카드가 받는다.
        //
        // 도착을 말하는 표면이 위(배너)·아래(카드) 둘인 것은 역할이 달라서다.
        // 배너는 **무슨 일이 일어났는지**를, 카드는 **이제 무엇을 할지**(매장
        // 정보·안내 종료)를 말한다.
        //
        // **`!_showingArrivalOnly`가 아니라 `_arrivedDestination == null`로
        // 가른다.** [_showingArrivalOnly]는 판정(`action`)이 `arrived`인
        // 프레임에만 참이라, 도착 직후 판정이 걸음 잡음으로 한 프레임만
        // `arrived`를 벗어나도 이 카드가 도착 카드 위에 같이 뜬다. 도착 카드가
        // 떠 있는 동안은(`_arrivedDestination != null`) 아래 세 갈래를 **밖에서
        // 한 번에** 안 그려서 끝내는 버튼을 하나로 묶는다 — 세 갈래 중 하나에만
        // 걸면 그 갈래가 Stack에서 도착 카드보다 나중에 그려져(뒤가 위) 도착
        // 카드를 덮는다. 도착했는데 `안내 종료`가 안 보이던 실기기 증상이 이것이다.
        if (_arrivedDestination == null)
          if (indoorRouteDestination != null)
            _bottomDockedCard(
              EtaCard(
                key: _etaCardKey,
                distanceMeters: indoorEta.distanceM,
                // 시간은 비용 기준 — 엘리베이터 대기·탑승 시간이 여기 들어 있다.
                minutes:
                    (indoorEta.costM / indoorWalkingSpeedMetersPerSecond / 60)
                        .ceil()
                        .clamp(1, 999),
                label: _indoorEtaLabel(indoorRouteDestination),
                guidanceStarted: _guidanceStarted,
                transition: transition,
                routeOptions: _indoorRouteExtras(indoorRouteDestination),
                onStartGuidance: _guidanceStarted
                    ? null
                    : () => unawaited(_startCurrentGuidance()),
                onClose: _dismissIndoorRouteFromEtaCard,
                onClosePointerDown: (position) =>
                    _etaClosePointerDown = position,
              ),
            )
          // 대중교통 안내는 도보 ETA 카드와 **같은 자리**를 쓰고 서로를 밀어낸다.
          // 두 카드가 함께 뜨면 한 화면에서 소요 시간이 두 개가 되어, 지도에
          // 그려진 선이 어느 쪽인지 알 수 없다.
          //
          // 후보 목록이 덮고 있는 동안에는 아예 안 그린다([OutdoorMapBody.transitRoutesSheetOpen]).
          else if (_transitItinerary case final itinerary?
              when !widget.transitRoutesSheetOpen)
            _bottomDockedCard(
              TransitSummaryCard(
                key: _etaCardKey,
                itinerary: itinerary,
                label: _transitLabel ?? '목적지까지',
                transition: transition,
                onStartGuidance: _guidanceStarted
                    ? null
                    : () => unawaited(_startCurrentGuidance()),
                onClose: _dismissUserDestinationFromEtaCard,
                onClosePointerDown: (position) =>
                    _etaClosePointerDown = position,
              ),
            )
          else if (route != null)
            _bottomDockedCard(
              EtaCard(
                key: _etaCardKey,
                distanceMeters: _outdoorEta(route).distanceM,
                minutes: _outdoorEta(route).minutes,
                label: userDestination != null
                    ? (_userDestinationLabel ?? '목적지까지')
                    : '건물 입구까지',
                guidanceStarted: _guidanceStarted,
                transition: transition,
                routeOptions: _directionsRouteExtras(context, route),
                extraMetric: _directionsFareMetric(route),
                onClose: userDestination != null
                    ? _dismissUserDestinationFromEtaCard
                    : null,
                onStartGuidance: userDestination != null && !_guidanceStarted
                    ? () => unawaited(_startCurrentGuidance())
                    : null,
                onClosePointerDown: userDestination != null
                    ? (position) => _etaClosePointerDown = position
                    : null,
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

  /// 안내 중 하단 카드의 **왼쪽 버튼**. 이 여정이 실내↔야외를 건너지 않으면 null
  /// 이라 카드는 지금까지처럼 `안내 종료` 하나만 띄운다.
  ///
  /// 두 갈래가 배타적인 것은 [_guidanceEntersBuilding]·[_guidanceLeavesBuilding]이
  /// `_indoorEntered`를 반대로 보기 때문이다 — 한 화면에 진입과 나가기가 함께
  /// 뜨는 상태는 없다.
  ///
  /// **버튼을 숨기지 않고 회색으로 둔다.** 조건을 채웠을 때만 나타나면 사용자는
  /// 그런 버튼이 있는 줄도 모르고 걷다가, 정작 문 앞에서 처음 보고 "이게 뭐지"를
  /// 한 번 더 생각해야 한다.
  GuidanceTransitionAction? _guidanceTransitionAction() {
    if (_guidanceEntersBuilding) {
      final name = _building?.name;
      if (name == null || name.isEmpty) return null;
      return GuidanceTransitionAction(
        label: '${withDirectionJosa(name)} 진입',
        onPressed: indoorEntryGate.enabled
            ? () => unawaited(enterIndoorFromGuidance())
            : null,
      );
    }
    if (_guidanceLeavesBuilding) {
      return GuidanceTransitionAction(
        label: '밖으로 나가기',
        onPressed: outdoorExitGate.enabled ? exitIndoorFromGuidance : null,
      );
    }
    return null;
  }

  /// 층을 옮길 때 무엇을 타고 갈지 고르는 줄. 층 간 경로가 아니면 null이다.
  ///
  /// **이 자리를 고른 이유.** 선호는 실내 층 간 경로에서만 뜻이 있다 — 야외·
  /// 자동차·대중교통 카드에는 탈 것이 없어 늘 보이면 소음이고, 앱 메뉴에 숨기면
  /// 정작 층을 옮기는 순간에는 안 보인다. 이 카드는 이미 제목에 "1F → 3F
  /// 에스컬레이터"를 적고 있으므로, 그 판단을 바꾸는 자리가 바로 위인 것이 가장
  /// 짧다.
  ///
  /// 안내를 시작하면 [EtaCard]가 이 자리를 그리지 않는다 — 걷는 중에 경로를
  /// 갈아 끼우는 것은 다른 사건이고, 자동차 후보 줄도 같은 규칙이다.
  Widget? _verticalPreferenceExtras() {
    if (_indoorMultiFloorRoute == null) return null;
    return VerticalPreferenceBar(
      selected: verticalPreferenceController.value,
      onSelected: (preference) =>
          unawaited(_applyVerticalPreference(preference)),
    );
  }

  /// 실내 계획 카드의 선택 영역 — 수직 이동 선호 줄 + 접어 둔 전체 단계 목록.
  ///
  /// **단계 목록은 접힌 채로 시작한다.** 이유는 [CollapsibleRouteSteps]에 있고,
  /// 대중교통 요약 카드가 세부 타임라인을 접어 두는 것과 같은 규칙이다.
  ///
  /// 둘 다 없으면 null을 돌려 카드가 **제목부터 시작하게** 한다 — 빈 줄을 남기면
  /// 그만큼 지도가 가려진다.
  Widget? _indoorRouteExtras(PoiSearchResult destination) {
    final preference = _verticalPreferenceExtras();
    final steps = _indoorRouteSteps();
    if (preference == null && steps.isEmpty) return null;
    return RoutexStack(
      gap: RoutexStackGap.inline,
      children: [
        ?preference,
        CollapsibleRouteSteps(
          steps: steps,
          destinationName: destination.name,
        ),
      ],
    );
  }

  /// 자동차 후보가 여럿일 때 고르는 줄. 하나뿐이면 null이라 카드는 **제목부터
  /// 시작한다.**
  ///
  /// **`상세보기`를 걷어냈다.** 턴 목록을 시트로 한 겹 더 띄웠는데, 지도에 이미
  /// 그려진 선보다 알려 주는 것이 적었다 — 카드만 높아져서 정작 봐야 할 경로를
  /// 그만큼 더 가렸다. 경로를 자세히 보는 자리는 지도 자체다.
  Widget? _directionsRouteExtras(BuildContext context, DirectionsRoute route) {
    if (_directionsRouteOptions.length <= 1) return null;
    return DirectionsRouteOptionsPanel(
      options: _directionsRouteOptions,
      selectedIndex: _selectedDirectionsOptionIndex,
      onSelect: (index) => unawaited(selectDirectionsOption(index)),
    );
  }

  /// 통행료가 있으면(0원 포함) 그것을, 없으면 택시비를 세 번째 지표로
  /// 쓴다. 도보 경로는 둘 다 null이라 아무것도 안 붙는다.
  RoutexTripMetric? _directionsFareMetric(DirectionsRoute route) {
    final toll = route.tollFareWon;
    if (toll != null) {
      return RoutexTripMetric(
        value: toll == 0 ? '무료' : formatTransitFare(toll),
        label: '통행료',
      );
    }
    final taxi = route.taxiFareWon;
    if (taxi != null) {
      return RoutexTripMetric(value: formatTransitFare(taxi), label: '택시비');
    }
    return null;
  }
}
