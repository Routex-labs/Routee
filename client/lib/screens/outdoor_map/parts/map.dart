// ignore_for_file: invalid_use_of_protected_member
//
// part라 `setState`(protected) 호출이 경고로 잡힌다.
/// `OutdoorMapBodyState`의 **지도·카메라·레이어 동기화** 부분.
///
/// part 규약과 이 파일로 가른 이유는 `docs/client/outdoor-map-moves.md`.
part of '../outdoor_map_screen.dart';

extension OutdoorMapMap on OutdoorMapBodyState {
  /// 카메라를 [position]으로 옮긴다. [zoom]을 주면 그 값으로 확대하고, 없으면
  /// 지금 배율을 유지한다 — 따라가는 동안 사용자가 맞춘 배율을 빼앗지 않는다.
  /// bearing·tilt는 [animateCameraToPoint]가 항상 정북·평면으로 되돌린다.
  Future<void> _moveCameraToUser(
    Position position, {
    double? zoom,
    Duration? duration,
  }) => _moveCameraToPoint(
    ll.LatLng(position.latitude, position.longitude),
    zoom: zoom,
    duration: duration,
  );

  /// [_moveCameraToUser]와 같은 동작을 좌표 하나로 부른다. GPS 좌표가 없는
  /// 이탈 경로(문으로 걸어 나감)가 문 좌표로 화면을 되돌릴 때 쓴다.
  Future<void> _moveCameraToPoint(
    ll.LatLng point, {
    double? zoom,
    Duration? duration,
  }) async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    await animateCameraToPoint(controller, point, zoom: zoom, duration: duration);
  }

  /// 실내 위치 마커를 화면 정중앙에 놓고, **바라보는 방향이 화면 위쪽**이 되게
  /// 돌린다. 실내로 들어온 순간과 "보정" 버튼이 같은 연출을 쓴다.
  ///
  /// 위치를 아직 모르면 아무것도 하지 않는다 — 중앙에 놓을 자리가 없다. 방향만
  /// 모르면 지금 방위를 유지한 채 중앙 정렬까지만 한다(모르는 방향으로 지도를
  /// 돌리면 화면 위쪽이 갈 방향과 어긋난다).
  ///
  /// **가려지지 않는 띠 중앙 보정을 일부러 안 한다.** 이 호출이 끝나자마자
  /// 매 프레임 팔로우 루프([_driveFollowCamera])가 곧바로 카메라를 다시 잡는데,
  /// 그 루프는 그 보정을 모른다 — 한 번 밀어 놔도 다음 프레임에 보정 없는
  /// 자리로 도로 끌려가 어긋나 보였다(실기기에서 "헤딩이 튄다"로 보임).
  Future<void> _centerOnIndoorMarker({double? zoom}) async {
    final controller = _mapController;
    final here = _pdrCurrentWgs84();
    if (controller == null || !_styleReady || here == null) return;
    final camera = controller.cameraPosition;
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _toGl(here),
          zoom: zoom ?? camera?.zoom ?? indoorEntryZoomThreshold,
          bearing: _pdrCurrentHeadingDeg ?? camera?.bearing ?? 0,
          tilt: camera?.tilt ?? 0,
        ),
      ),
    );
  }

  // --- MapLibre 스타일/레이어 설정 ---

  Future<void> _onStyleLoaded() async {
    final controller = _mapController;
    if (controller == null) return;

    // 새 스타일에는 이전 스타일이 갖고 있던 addImage 비트맵이 넘어오지 않는다.
    // 다음 _ensureIndoorTilesRegistered 호출이 아이콘을 다시 등록하도록 리셋.
    _facilityIconImagesRegistered = false;

    // 건물 fill과 실내 진입 dim scrim. 등록 순서가 곧 쌓임 순서라 가장 먼저다.
    await registerBuildingAndScrimLayers(
      controller,
      buildingFillOpacity: buildingFillOpacityDefault,
    );

    // 경로선 묶음(회색 완료선 → casing → 본선들 → 화살표). 등록 순서가 곧
    // 쌓임 순서라 아래 세 호출의 순서를 바꾸면 안 된다.
    await registerRouteLayers(controller);
    // 대중교통 경로. 도보 경로 **바로 위**에 올려, 두 안내가 잠깐 겹치는
    // 순간에도 사용자가 방금 고른 대중교통 선이 가려지지 않게 한다.
    await registerTransitLayers(controller);
    await registerTransferRouteLayer(controller);

    // 현재 층 외곽선. 경로선 다음이어야 하는 이유는 그 함수 doc에 있다.
    await registerFloorOutlineLayer(controller);

    // 위치 마커 비트맵. **GPS 마커도 이 심볼을 쓰므로 그 레이어보다 먼저다** —
    // 예전에는 PDR 마커 전용이라 훨씬 뒤에서 구웠다.
    await registerLocationMarkerImages(controller);

    // 현재 위치(GPS)와 야외 목적지 핀. 등록 순서가 곧 쌓임 순서다.
    await registerCurrentLocationLayers(controller);
    await registerDestinationLayer(controller);

    // 출구 핀 → 고른 매장 칠 순. PDR 마커보다 아래·경로선보다 위다
    // (각 함수 doc 참고).
    await registerGateLayers(controller);
    await registerHighlightLayers(controller);

    // 진단 레이어를 끼운 뒤 PDR 마커를 얹는다 — 순서의 근거는 각 함수 doc에 있다.
    await registerPdrDebugLayers(controller);
    await registerPdrLocationLayer(controller);

    // 실내 경로 도착 핀 — 현재 위치 마커보다 **나중에** 등록해, 도착 노드와
    // 사용자 위치가 겹칠 때 도착 핀이 위에 오게 한다(실내 지도와 같은 순서).
    // 핀 바닥(tip)이 도착 노드 좌표에 오도록 iconAnchor는 bottom이고, 크기는
    // zoom 보간식으로 걸어 축소했을 때 핀이 도면을 다 덮지 않게 한다.
    // allowOverlap을 켜 매장 라벨과 겹쳐도 핀은 항상 보인다.
    await registerIndoorDestinationLayers(controller);

    if (!mounted) return;
    setState(() => _styleReady = true);
    if (!_styleReadySignal.isCompleted) _styleReadySignal.complete();
    _syncBuildingLayer();
    _syncCurrentLayer();
    _syncDestinationLayer();
    _syncRouteLayer();
    _syncIndoorDestinationLayer();
    _syncPdrCurrentLayer(snap: true);
    unawaited(_syncDebugPdrLayers());
    _syncHighlightLayer();
    _syncDimScrimLayer();
    // **스타일이 준비된 지금 다시 채운다.** 첫 층 도면은 스타일보다 먼저
    // 도착할 수 있는데, 그때 이 둘은 `_styleReady`가 false라 조용히 반환한다 —
    // 그리고 층을 바꾸기 전까지 아무도 다시 부르지 않아 출구 핀과 못 걷는 면이
    // 첫 화면에서 통째로 비어 있었다(실기기에서 확인).
    unawaited(_syncGateLayer());
    _ensureIndoorTilesRegistered();
    // 스타일이 뜨기 전에 받아둔 첫 GPS 위치로의 카메라 이동. 그 사이에 실내로
    // 들어갔다면(줌 임계값·건물 탭) 실행하지 않는다 — 실내 도면을 보고 있는데
    // 카메라가 GPS 좌표로 튀면 안 된다.
    // 매장 포커스가 카메라를 예약했으면 건너뛴다 — 공유 링크는 지도보다 먼저
    // 도착해 여기서 기다리는 중이고, 그 화면을 GPS로 덮으면 두 번 튄다.
    if (_pendingCenterOnPosition &&
        _position != null &&
        _outdoorGpsVisible &&
        !_initialCameraClaimed) {
      _pendingCenterOnPosition = false;
      // 첫 좌표 센터링은 여기서 끝났다. 표시해 두지 않으면 다음 좌표가 올 때
      // [_handlePosition]의 갈래가 한 번 더 옮겨 화면이 두 번 튄다.
      _didInitialCenter = true;
      await controller.animateCamera(
        CameraUpdate.newLatLng(
          LatLng(_position!.latitude, _position!.longitude),
        ),
      );
      if (mounted && !_indoorEntered) {
        _startupCameraPrepared = true;
        _maybeNotifyOutdoorStartupReady();
      }
    }
  }

  /// dim scrim 갱신. 건물 footprint가 있으면 세계 전체를 덮는 outer ring +
  /// 건물 hole 폴리곤을 넣고, 실내 진입 상태에 따라 fillOpacity를 실내 오버레이와
  /// 같은 zoom 페이드 구간(16.5~17.5)에 맞춰 0 → 0.35로 켠다. 실내 진입이 꺼져
  /// 있을 땐 opacity=0으로 완전히 사라진다. 이렇게 하면 건물 밖만 반투명 검정으로
  /// 덮이고 실내 오버레이는 그대로 밝게 보인다.
  Future<void> _syncDimScrimLayer() async {
    await _syncDimScrimGeometry();
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    await _setFloorBoundaryFadeFactor(controller, 1, outline: false);
  }

  /// dim scrim의 hole 좌표만 갱신한다. 층 크로스페이드에서는 opacity가 0인
  /// 중간 프레임에 이 함수만 불러, 새 모양이 먼저 드러나는 것을 막는다.
  Future<void> _syncDimScrimGeometry() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    // hole은 외곽선과 **같은 링**을 쓴다 — 건물 외곽선으로 뚫으면 층 도면이
    // 그 밖으로 나간 부분이 덮여 외곽선 안쪽이 어두워진다(지하가 심하다).
    // 여기만 폴백을 허용한다: 스크림은 경계선이 아니라 밝기 대비다.
    await syncDimScrimSource(
      controller,
      _activeFloorOutlineRing() ?? _buildingFootprint,
    );
  }

  /// 층 경계 두 레이어(외곽선·dim scrim)의 opacity를 같은 계수로 조절한다.
  ///
  /// 층 전환 중에 부르는 것이 요점이다 — 도면만 크로스페이드하고 경계를 즉시
  /// 갈아 끼우면 그 한 프레임이 번쩍임으로 보인다([floorBoundaryCrossfadeFactor]).
  ///
  /// 한쪽만 바꿀 때도 **전체 속성을 보낸다** — `setLayerProperties`는 전체
  /// 교체라 빠뜨린 속성이 스펙 기본값으로 되돌아간다.
  Future<void> _setFloorBoundaryFadeFactor(
    MapLibreMapController controller,
    double factor, {
    bool outline = true,
    bool scrim = true,
  }) async {
    final clamped = factor.clamp(0.0, 1.0).toDouble();
    if (outline) {
      await controller.setLayerProperties(
        kOutdoorFloorOutlineLayerId,
        floorOutlineProps(_overlayFadeExprFor(clamped)),
      );
    }
    if (scrim) {
      // 오버레이 페이드와 같은 zoom 창을 써서 함께 짙어진다. 실내가 아니면 0이다.
      await controller.setLayerProperties(
        kOutdoorDimScrimFillLayerId,
        dimScrimProps(
          _indoorEntered ? _fadeExpr(maxOpacity: 0.35 * clamped) : 0,
        ),
      );
    }
  }

  /// 지도 탭 처리의 테스트 진입점. 플랫폼 뷰가 없어 `onMapClick`이 발화하지 않으므로
  /// 실기기와 **같은 함수**를 부른다(축약 경로를 두면 검증하려는 분기를 우회한다).
  ///
  /// [screenPoint]는 지도 로컬 픽셀이다 — 늘 (0,0)이면 오버레이 배제가 검증되지 않는다.
  @visibleForTesting
  Future<void> handleMapClickForTest(
    ll.LatLng point, {
    Offset screenPoint = Offset.zero,
  }) => _handleMapClick(
    Point<double>(screenPoint.dx, screenPoint.dy),
    LatLng(point.latitude, point.longitude),
  );

  Future<void> _handleMapClick(Point<double> pointPx, LatLng coords) async {
    final point = ll.LatLng(coords.latitude, coords.longitude);

    // 지도 위에 얹은 PDR 제어·디버그 설정 버튼을 누른 탭은 여기서 끊는다.
    // 그러지 않으면 "PDR 시작"을 누른 손가락이 버튼 아래의 매장까지 함께
    // 선택하거나, 앵커 배치 대기 중에 버튼 위치에 앵커가 찍힌다.
    if (_isTapOnMapOverlay(Offset(pointPx.x, pointPx.y))) return;

    // 위치 지정 대기 중이라면 이 탭은 PDR 앵커 배치로 소비된다 — 지도 탭이
    // 건물 진입 처리로 새어들어가면 사용자가 위치를 지정하는 순간 오버레이가
    // 다시 리셋되는 것처럼 보인다.
    if (_placingPdrAnchor) {
      await _onMapPressedForPdr(point);
      return;
    }

    // 실내 진입 오버레이 위에서 매장 폴리곤을 탭하면 실내 화면과 동일한 매장
    // 정보 시트를 띄운다. 픽셀 좌표(pointPx)로 벡터 타일의 stores fill을
    // hit-test 하고 feature id로 FloorPlan에서 실제 매장을 되찾는다. 매장이
    // 아닌 곳(복도·footprint)을 탭하면 features가 비어 있어 아래 건물 진입
    // 처리로 자연스럽게 흘러간다.
    if (_indoorEntered && await _tryHandleStoreTap(pointPx)) return;

    // 매장을 맞히지 못했고 길찾기에서 지도로 고르는 중이라면, 이 탭은 복도(또는
    // 빈 공간)를 고른 것이다. **아래 진입/이탈 처리보다 먼저** 소비해야 한다 —
    // 그러지 않으면 건물 안을 눌렀을 땐 진입 트리거로, 건물 밖을 눌렀을 땐
    // 오버레이 닫기로 먹혀서 사용자는 복도를 눌렀는데 화면만 바뀌는 것을 본다.
    if (_indoorEntered && widget.pickingOnMap && _handleMapPickTap(point)) {
      return;
    }

    // 폴리곤 히트 검사만 하고, 나머지 탭은 흡수하지 않아 지도 pan/zoom 제스처를
    // 방해하지 않는다(단일 탭이 여기 오면 그건 pan이 아닌 명시적 탭).
    if (!_isInsideBuilding(point)) {
      // 실내에서 건물 밖 탭 = 야외로 나가겠다는 뜻. 단, **외곽선 바로 바깥은 이탈로
      // 치지 않는다**([isTapOutsideBuildingForExit]) — 벽에 붙은 매장을 누르다 손가락이
      // 선을 몇 미터 넘기면 매장을 누르려던 사용자가 건물에서 쫓겨난다.
      if (_indoorEntered &&
          isTapOutsideBuildingForExit(
            point: point,
            footprint: _buildingFootprint,
          )) {
        _exitIndoorByOutsideTap();
      }
      return;
    }

    // 반짝임은 장식이라 컨트롤러가 없으면 건너뛴다. 진입 자체를 컨트롤러 유무에
    // 걸면 스타일 로드 전에 건물을 탭한 사용자에게 아무 반응도 없다.
    await _flashBuildingFill();
    if (!mounted) return;
    // **건물 탭은 곧 진입이다.** 한때 정보 시트를 앞에 세워 봤는데, 도면을
    // 보려는 사용자에게 탭이 한 번 더 늘 뿐이었다 — 건물을 누르는 행동 자체가
    // 이미 "여기 안을 보겠다"는 뜻이라, 그 사이에 무엇을 끼워도 걸리적거린다.
    _triggerIndoorEntry(ignoreZoomArming: true);
    // 오버레이만 켜면 도면이 지금 배율 그대로 뜬다 — 바깥에서 건물을 눌러
    // 들어온 경우 건물이 화면의 60% 남짓이라 "들어왔다"는 느낌이 안 난다.
    // 카메라도 함께 도면이 화면을 채우는 자리까지 끌어온다.
    if (_indoorEntered) unawaited(_fitCameraToActiveFloor());
  }

  /// [box]를 **가려지지 않는 띠**에 맞춰 카메라를 움직인다. 컨트롤러가 없으면 false.
  ///
  /// 층 도면 fit과 경로 개요의 **공통 몸통**이다 — chrome 보정과 줌 하한이 한 곳에만
  /// 있어야 두 화면에서 같은 지점이 같은 높이에 온다. 상자를 구하는 규칙은 호출부가
  /// 정한다([minAreaBoxFor] / [routeBoxFor]). [maxZoom]은 경로 개요만 준다.
  Future<bool> _animateCameraToFitBox(
    BuildingBox box, {
    required double topChromePx,
    required double bottomChromePx,
    required Duration duration,
    double maxZoom = double.infinity,
  }) async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return false;
    // 층 도면 fit과 경로 개요가 도는 동안은 팔로우가 쉰다. 여기 하나로 두 주인이
    // 다 덮인다 — 각자 걸게 두면 새 fit이 생길 때마다 빠뜨린다.
    _holdFollowCamera(duration);
    await animateCameraToFitBox(
      controller,
      box,
      viewport: MediaQuery.sizeOf(context),
      topChromePx: topChromePx,
      bottomChromePx: bottomChromePx,
      duration: duration,
      maxZoom: maxZoom,
    );
    return true;
  }

  /// 지금 화면 폭에서 쓸 실내 진입 임계값([indoorEntryZoomThresholdFor]).
  ///
  /// 확대 진입 판정과 건물 포커스가 **같은 값을 봐야 한다** — 어긋나면 포커스가
  /// 맞춘 zoom이 임계값에 못 미쳐 건물로 가고도 실내로는 안 들어간다.
  double _entryZoomThreshold() {
    final footprint = _buildingFootprint;
    if (footprint == null || footprint.length < 3) {
      return indoorEntryZoomThreshold;
    }
    return indoorEntryZoomThresholdFor(
      buildingWidthMeters: polygonWidthMeters(footprint),
      // 이 화면의 지도는 Stack을 꽉 채우고, MapShellScreen도 Scaffold body
      // 전체를 내주므로 지도 폭 == 화면 폭이다.
      viewportWidthPx: MediaQuery.sizeOf(context).width,
      latitude: _buildingCenter(footprint)?.latitude ?? referenceLatitude,
    );
  }

  void _handleCameraIdle() {
    // 카메라 콜백은 위젯이 사라진 뒤에도 한 박자 늦게 도착할 수 있다.
    // _entryZoomThreshold가 context를 읽으므로 먼저 걸러낸다.
    if (!mounted) return;
    final controller = _mapController;
    if (controller == null) return;
    unawaited(_syncHighlightLayer());
    unawaited(_syncGateLayer());
    // 마지막 안전망. 크로스페이드가 도는 중이 아닐 때만(은퇴 목록이 비었을 때)
    // 이전 세대 실내 오버레이가 남아 있는지 지도에 직접 물어 지운다 — 층 전환이
    // 중간에 끊기면 그 블록을 지울 주체가 아무도 없고, 남으면 새 층이 덮지 못하는
    // 바깥쪽이 밝은 띠로 계속 보인다.
    if (_retiringIndoorBlocks.isEmpty) {
      unawaited(
        purgeStaleIndoorOverlay(
          controller,
          keepGeneration: _indoorIds.generation,
        ),
      );
    }
    // zoom과 target은 같은 CameraPosition에서 나오고 둘 다 non-nullable이므로,
    // 카메라를 받았다면 중심 좌표도 항상 있다.
    final camera = controller.cameraPosition;
    if (camera == null) return;
    // 확대만으로는 실내로 들어가지 않는다. 카메라 중심이 실내 도면이 있는 건물
    // 근처일 때만 진입을 허용한다 — 건물이 없는 지역을 확대했을 때 도면 없이
    // 층 선택기·위치 지정 버튼만 뜨는 것을 막는다.
    final buildingNearby = isIndoorBuildingNearCamera(
      camera: ll.LatLng(camera.target.latitude, camera.target.longitude),
      footprint: _buildingFootprint,
    );
    switch (indoorEntryTransitionForZoom(
      camera.zoom,
      buildingNearby: buildingNearby,
      entryZoom: _entryZoomThreshold(),
    )) {
      case IndoorEntryTransition.enter:
        // 건물 배율로 돌아왔다 — 개요 붙들기는 여기서 끝난다. 다음 축소는
        // 사용자가 한 것이므로 그때는 접혀야 한다.
        _routeOverviewHoldsIndoor = false;
        _triggerIndoorEntry();
      case IndoorEntryTransition.exit:
        // **경로 개요가 물러선 축소면 접지 않는다.** 이유는 [zoomOutKeepsIndoor]에
        // 있다. 무장도 하지 않는다 — 접지 않았으니 다시 켤 것이 없고, 무장해 두면
        // 개요에서 돌아오는 확대가 진입 연출을 한 번 더 태운다.
        if (zoomOutKeepsIndoor(
          overviewHold: _routeOverviewHoldsIndoor,
          hasRouteToShow: _hasAnyRouteVisible,
          // 실내 위치가 살아 있으면 이 사람은 건물 안이다 — 접지 않는다.
          indoorPositionLive:
              indoorNavigationDriver.currentCalibration.canRenderPosition,
        )) {
          break;
        }
        _exitIndoorByZoomOut();
      case IndoorEntryTransition.keep:
        // 히스테리시스 밴드 — 현재 상태를 그대로 유지한다.
        break;
    }
  }

  /// 축소로 실내를 벗어났을 때. 다음 확대에서 재발화할 수 있게 줌 트리거는
  /// **다시 무장한다**. 배치 대기 중이면 종료해 하단 바 표시도 함께 초기화한다.
  ///
  /// **좌표가 되끌고 들어오는 것은 여기서 막지 않는다.** 이 브랜치에서 GPS
  /// 자동 진입 자체가 없어졌기 때문이다 — 들어가는 것은 사용자가 누른 순간뿐이고,
  /// 실내에서 켠 콜드스타트만 1회성으로 남아 있다([_coldStartIndoorHandled]).
  void _exitIndoorByZoomOut() {
    _autoIndoorEntryArmed = true;
    if (!_indoorEntered) return;
    if (_placingPdrAnchor) _setPlacingAnchor(false);
    _setIndoorEntered(false);
    // 이 길도 카메라를 축소 자체 말고는 만지지 않는다 — 실내에서 건물 축에
    // 맞춰 돌아간 방위가 그대로 남으면, 이 축소로 야외로 돌아온 사용자가
    // 그 회전된 지도 위에서 걷게 된다([resetCameraToNorthUp]과 같은 이유로
    // 다른 이탈 경로에 붙인 `fe35e4cf`가 이 길은 놓쳤다).
    final controller = _mapController;
    if (controller != null && _styleReady) {
      unawaited(resetCameraToNorthUp(controller));
    }
  }

  /// 축소 이탈의 테스트 진입점. 줌 제스처는 MapLibre 플랫폼 뷰 콜백이라 위젯
  /// 테스트에서 만들 수 없으므로, 실기기와 **같은 함수**를 부른다.
  @visibleForTesting
  void exitIndoorByZoomOutForTest() => _exitIndoorByZoomOut();

  /// GPS 현재 위치 마커. 실내 위치가 화면의 주인일 때는 [_outdoorGpsVisible]이
  /// false라 항상 빈 소스로 밀어 넣어 마커가 지도에서 사라진다 —
  /// [_syncGpsSubscription]이 `_position`을 비우는 것과 이중으로 막아, 어느
  /// 경로로 들어와도 실내 마커와 GPS 마커가 함께 뜨지 않게 한다.
  ///
  /// 방향은 [_outdoorHeadingDeg]가 정한다. null이면 삼각형 없이 도트만 그려진다.
  Future<void> _syncCurrentLayer() async {
    // 실내 마커 쪽이 이 값을 보고 "GPS 마커도 다시 써야 하는가"를 가린다
    // ([_syncPdrCurrentLayer]). 컨트롤러가 없어 되돌아가는 길에서도 맞춰 둬야,
    // 지도가 붙는 순간의 첫 쓰기가 빠지지 않는다.
    _outdoorGpsMarkerShown = _outdoorGpsVisible;
    final controller = _mapController;
    if (controller == null || !_styleReady) {
      _pendingCenterOnPosition = _outdoorGpsVisible && _position != null;
      return;
    }
    final pos = _outdoorGpsVisible ? _position : null;
    await controller.setGeoJsonSource(
      kOutdoorCurrentSourceId,
      locationMarkerData(
        pos == null ? null : ll.LatLng(pos.latitude, pos.longitude),
        headingDeg: pos == null ? null : _outdoorHeadingDeg,
      ),
    );
  }

  /// 출발·도착 행 편집 중 매장이 아닌 곳을 눌렀을 때. 넘겼으면 true.
  /// 스냅 규칙은 [_onMapPressedForPdr]와 같고, 노드까지 확정해 넘긴다.
  ///
  /// 통로에서 너무 먼 탭은 **false로 흘려보낸다** — 야외에서 그 탭은 대개 "나가겠다"
  /// 는 뜻이라, 삼키면 고르는 중에 실내에서 빠져나올 방법이 사라진다.
  bool _handleMapPickTap(ll.LatLng point) {
    final floor = _activeFloor;
    final graph = _floorGraph;
    if (floor == null || graph == null || graph.nodes.isEmpty) return false;
    final transform = fitFloorGeoTransform(graph.nodes);
    final local = transform.invert(point.latitude, point.longitude);
    if (local == null) return false;
    final snapped = FloorMapMatcher(
      graph,
    ).snapToWalkableNetwork(PdrLocalPoint(local.$1, local.$2));
    if (snapped == null) return false;
    if (snapped.distanceToGraphM > maxPdrAnchorSnapDistanceM) return false;

    final nodeId = _nearestGraphNodeId(
      graph.nodes,
      snapped.point.eastM,
      snapped.point.northM,
    );
    final node = graph.nodes.where((n) => n.id == nodeId).firstOrNull;
    if (node == null) return false;
    // 노드에 실측 좌표가 있으면 그대로 쓴다. 있는 값을 두고 변환을 태우면
    // 피팅 오차만큼 어긋난 자리에 핀이 찍힌다(실내 화면과 같은 규칙).
    final latLng = node.lat != null && node.lng != null
        ? ll.LatLng(node.lat!, node.lng!)
        : () {
            final (lat, lng) = transform.apply(node.xM, node.yM);
            return ll.LatLng(lat, lng);
          }();
    widget.onMapPointPicked?.call(
      PoiSearchResult(
        name: kMapPickedPointLabel,
        floor: floor,
        point: latLng,
        nodeId: node.id,
      ),
    );
    return true;
  }
}
