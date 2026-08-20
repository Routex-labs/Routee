// ignore_for_file: invalid_use_of_protected_member
//
// part라 `setState`(protected) 호출이 경고로 잡힌다.
/// `OutdoorMapBodyState`가 **경로·목적지를 지도에 쓰는** 부분.
///
/// part 규약과 이 파일로 가른 이유는 `docs/client/outdoor-map-moves.md`.
part of '../outdoor_map_screen.dart';

extension OutdoorMapRouteLayers on OutdoorMapBodyState {
  Future<void> _refreshIndoorDestinationPin() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    try {
      await controller.removeLayer(kOutdoorIndoorDestLayerId);
      await addIndoorDestinationPinLayer(controller);
      await _syncIndoorDestinationLayer();
    } catch (error, stackTrace) {
      // hot reload 편의 기능이라 실패해도 앱을 죽이지 않는다.
      debugPrint('destination pin refresh failed: $error\n$stackTrace');
    }
  }

  /// 야외 목적지 핀.
  ///
  /// **[_entrance]로 폴백하지 않는다.** 그 값은 진입/이탈 판정의 기준점이지
  /// 목적지가 아니다. 문 좌표가 채워지면서([_syncSelectedEntrance]) 폴백이
  /// 되살아났고, 앱을 켜고 GPS가 잡히기만 하면 아무도 고르지 않은 문에 빨간
  /// 핀이 찍혔다 — 경로 쪽에서 같은 폴백을 걷어낸 것과 같은 이유다.
  ///
  /// **문을 경유하는 안내 중에도 찍지 않는다.** 그때 [_userDestination]은
  /// 목적지가 아니라 지나갈 문이고, 진짜 목적지는 건물 안이라 실내 도착 핀이
  /// 따로 찍힌다([_syncIndoorDestinationLayer]). 둘 다 찍으면 야외 선이 끝나는
  /// 자리에 "여기가 목적지"로 읽히는 핀이 하나 더 생긴다.
  Future<void> _syncDestinationLayer() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    final passingThroughDoor =
        _pendingIndoorRoute != null || _pendingIndoorDestination != null;
    final target = passingThroughDoor ? null : _userDestination;
    await syncPointSource(controller, kOutdoorDestSourceId, target);
  }

  /// 실내 경로의 도착 노드에 물방울 핀을 찍는다.
  ///
  /// 핀을 찍는 좌표는 매장 중심(centroid)이 아니라 **경로의 마지막 점**이다 —
  /// 그래프 도착 노드는 매장 입구라 centroid와 몇 미터 어긋나고, 그 상태로
  /// centroid에 찍으면 경로선이 핀에 닿지 않고 끊긴 것처럼 보인다. 경로가 아직
  /// 계산되기 전 짧은 순간에는 경로가 없으므로 centroid로 폴백해 핀이 아예
  /// 안 보이는 구간을 만들지 않는다(실내 화면의 _destinationPinForCurrentFloor와
  /// 같은 규칙).
  ///
  /// 다층 경로에서는 **도착지 층을 보고 있을 때만** 찍는다. 중간 층은 지나가는
  /// 층이라 그 층 좌표에 도착 핀이 있으면 "여기가 목적지"로 잘못 읽힌다.
  Future<void> _syncIndoorDestinationLayer() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    await syncPointSource(
      controller,
      kOutdoorIndoorDestSourceId,
      _indoorDestinationPinForActiveFloor(),
    );
  }

  ll.LatLng? _indoorDestinationPinForActiveFloor() {
    final destination = _indoorRouteDestination;
    if (destination == null) return null;
    final multi = _indoorMultiFloorRoute;
    if (multi != null) {
      if (multi.destinationSegment.floorName != _activeFloor) return null;
      final points = multi.destinationSegment.route.points;
      return points.isNotEmpty ? points.last : destination.point;
    }
    final segment = _indoorRouteSegment;
    if (segment != null && segment.points.isNotEmpty) {
      return segment.points.last;
    }
    // 단일 층 경로는 목적지 층에서만 그려진다. 층을 옮기면 _switchOverlayFloor가
    // 세그먼트를 비우므로, 그때는 목적지 층이 아닌 곳에 centroid 폴백 핀이
    // 남지 않도록 층을 직접 확인한다.
    return destination.floor == _activeFloor ? destination.point : null;
  }

  /// 대중교통 경로선을 지도에 반영한다. feature로 펼쳐 소스에 쓰는 일은
  /// [syncTransitLayer]가 한다.
  Future<void> _syncTransitLayer() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    await syncTransitLayer(
      controller,
      _transitItinerary,
      alternatives: _transitAlternatives,
    );
  }

  Future<void> _syncRouteLayer() {
    final scheduled = _routeLayerWriteQueue.then<void>(
      (_) => _syncRouteLayerNow(),
    );
    _routeLayerWriteQueue = scheduled.catchError((Object _, StackTrace _) {});
    return _routeLayerWriteQueue;
  }

  /// 고르지 않은 자동차 후보를 회색으로 깐다.
  ///
  /// 그릴 조건(`_route != null && _routeIsDriving`)을 **그리는 쪽에** 둔다 —
  /// 수단을 바꾸거나 경로를 비우면 지우는 자리를 따로 만들지 않아도 저절로
  /// 사라진다. 후보는 상태를 새로 두지 않고 [unselectedDirectionsRoutes]로
  /// 그때그때 뽑는다.
  Future<void> _syncRouteAltLayer(MapLibreMapController controller) async {
    final alternatives = _route == null || !_routeIsDriving
        ? const <DirectionsRoute>[]
        : unselectedDirectionsRoutes(
            _directionsRouteOptions,
            _selectedDirectionsOptionIndex,
          );
    await controller.setGeoJsonSource(
      kOutdoorRouteAltSourceId,
      alternatives.isEmpty
          ? emptyGeoJsonCollection()
          : geoJsonCollection([
              for (final alternative in alternatives)
                geoJsonLineFeature(alternative.points, style: 'drive'),
            ]),
    );
  }

  Future<void> _syncRouteLayerNow() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    await _syncRouteAltLayer(controller);
    final transferSegment = _indoorMultiFloorRoute?.segmentForFloor(
      _activeFloor ?? '',
    );
    final transferPoints = transferSegment == null
        ? null
        : transferRoutePointsOnFloor(transferSegment, _floorPlan, _floorGraph);
    await controller.setGeoJsonSource(
      kOutdoorTransferRouteSourceId,
      transferPoints == null || transferPoints.length < 2
          ? emptyGeoJsonCollection()
          : geoJsonCollection([
              geoJsonLineFeature(transferPoints, style: 'indoor'),
            ]),
    );
    // 실내 경로가 활성이면 그걸 우선 그린다(GPS 걷기 경로와 동시에 표시하지
    // 않는다 — 사용자는 지금 실내에 있고 실내 경로가 유일한 관심사).
    final indoor = _indoorRouteSegment;
    if (indoor != null && indoor.points.length >= 2) {
      final visuals = _indoorRouteVisuals(indoor);
      await _syncCompletedRouteLayer(
        scopeId: _activeFloor,
        currentCompleted: visuals.completed,
      );
      await controller.setGeoJsonSource(
        kOutdoorRouteSourceId,
        visuals.remaining.length < 2
            ? emptyGeoJsonCollection()
            : geoJsonCollection([
                geoJsonLineFeature(visuals.remaining, style: 'indoor'),
              ]),
      );
      return;
    }
    final outdoorVisuals = _outdoorRouteVisuals(_route);
    await _syncCompletedRouteLayer(
      scopeId: CompletedRouteHistory.outdoorScope,
      currentCompleted: outdoorVisuals.completed,
    );
    final features = <Map<String, dynamic>>[];
    final route = _route;
    if (route != null && outdoorVisuals.remaining.length >= 2) {
      features.add(
        geoJsonLineFeature(
          outdoorVisuals.remaining,
          style: _routeIsDriving ? 'drive' : 'walk',
        ),
      );
    }
    // **밖에서도 실내 구간을 미리 보여준다.** 아직 승격 전이라 상태는
    // [_pendingIndoorRoute]에 있다. 예전에는 건물에 들어가야 그려져서, 안내를
    // 받아 든 사용자가 "매장까지"라는 라벨만 보고 정작 건물 안 어디로 가는지는
    // 도착할 때까지 알 수 없었다.
    //
    // 지금 펼쳐 둔 층의 구간만 그린다. 여러 층을 한꺼번에 겹쳐 그리면 같은
    // 좌표 위에 선이 여러 겹 쌓여, 어느 것이 이 층의 길인지 알 수 없다 —
    // 층 chip을 넘기면 그 층의 구간이 이어서 보인다.
    final preview = _pendingIndoorRoute?.segmentForFloor(_activeFloor ?? '');
    if (preview != null && preview.route.points.length >= 2) {
      features.add(geoJsonLineFeature(preview.route.points, style: 'indoor'));
    }
    await controller.setGeoJsonSource(
      kOutdoorRouteSourceId,
      features.isEmpty ? emptyGeoJsonCollection() : geoJsonCollection(features),
    );
  }

  /// 사용자에게 보여 줄 회색선 source를 갱신한다.
  ///
  /// [currentCompleted]는 아직 재탐색 이력으로 승격되지 않은 현재 경로의
  /// 완료 구간이다. 재탐색이 확정되면 같은 점들이
  /// [_completedRouteHistory]에 저장되고, 새 파란 경로가 이 자리를 대체한다.
  /// GuidanceTrailSession은 여기에 들어오지 않는다.
  Future<void> _syncCompletedRouteLayer({
    required String? scopeId,
    List<ll.LatLng> currentCompleted = const [],
  }) async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    final segments = <List<ll.LatLng>>[];
    if (scopeId != null) {
      segments.addAll(_completedRouteHistory.segmentsFor(scopeId));
    }
    if (currentCompleted.length >= 2) {
      segments.add(currentCompleted);
    }
    await controller.setGeoJsonSource(
      kOutdoorWalkedRouteSourceId,
      segments.isEmpty
          ? emptyGeoJsonCollection()
          : geoJsonCollection([
              for (final segment in segments)
                geoJsonLineFeature(segment, generation: _routeGeneration),
            ]),
    );
  }
}
