import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../../../../domain/route/dijkstra.dart';
import '../../../../domain/search/store_suggestions.dart';
import '../../../../domain/store/nearest_store.dart';
import '../../../../domain/store/reach_label.dart';
import '../../../../models/route/directions_candidate.dart';
import '../../../../models/route/route_plan_mode.dart';
import '../../../../service_locator.dart';

/// 출발지·도착지를 고르는 후보를 Runtime Kit 목록 패턴으로 표시한다.
///
/// 후보 생성·거리 계산·최근 기록은 앱이 소유하고, 행의 위계와 로딩 표현은
/// `RoutexResultList`와 `RoutexListCell`이 소유한다.
class RouteFieldResults extends StatelessWidget {
  const RouteFieldResults({
    super.key,
    required this.field,
    required this.results,
    required this.searching,
    required this.onPicked,
    required this.onCurrentLocation,
    this.suggestions = const [],
    this.onSuggestionPicked,
    this.reachByNodeId,
    this.currentFloorId,
  });

  final RoutePlanField field;
  final List<DirectionsCandidate> results;
  final bool searching;
  final ValueChanged<DirectionsCandidate> onPicked;
  final VoidCallback onCurrentLocation;
  final List<StoreSuggestion> suggestions;
  final ValueChanged<StoreSuggestion>? onSuggestionPicked;
  final Map<String, NodeReach>? reachByNodeId;

  /// 지금 보고 있는 층. 거리를 모를 때(위치 미지정) 묶인 시설의 대표를 이 층에서
  /// 고른다 — 안 넘기면 색인 첫 줄(B6)이 대표가 되어, B2에 서 있어도 `화장실`이
  /// B6로 나온다([nearestByWalkingDistance]).
  final String? currentFloorId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: recentRoutePointsController,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final isOrigin = field == RoutePlanField.origin;
    final hasShortcut = isOrigin;
    final showSuggestions =
        suggestions.isNotEmpty && onSuggestionPicked != null;
    final recents = results.isEmpty && !searching && !showSuggestions
        ? recentRoutePointsController.points
        : const <DirectionsCandidate>[];
    if (!hasShortcut &&
        results.isEmpty &&
        !searching &&
        !showSuggestions &&
        recents.isEmpty) {
      return const SizedBox.shrink();
    }

    final hasResults = results.isNotEmpty || searching;
    return RoutexSurface(
      role: RoutexSurfaceRole.chrome,
      // 키보드가 올라오면 최근 항목까지 포함한 패널 전체가 남은 높이 안에서
      // 스크롤되어야 한다. 결과 목록만 스크롤하면 헤더·최근 항목이 먼저 잘린다.
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom > 0
              ? RoutexSpacing.controlGap
              : 0,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isOrigin)
              RoutexListCell(
                key: const Key('route-field-current-location'),
                title: '현재 위치',
                leadingIcon: RoutexIcons.currentLocation,
                onPressed: onCurrentLocation,
              ),
            if (hasShortcut &&
                (recents.isNotEmpty || showSuggestions || hasResults))
              const RoutexDivider(role: RoutexDividerRole.section),
            if (recents.isNotEmpty)
              RoutexRecentList(
                title: '최근 출발지 · 목적지',
                onClear: recentRoutePointsController.clear,
                items: [
                  for (final point in recents)
                    RoutexRecentItem(
                      id: 'route-field-recent-${point.dedupeKey}',
                      title: point.title,
                      subtitle: point.subtitle.isEmpty ? null : point.subtitle,
                      onRemove: () => recentRoutePointsController.remove(point),
                      onPressed: () => onPicked(point),
                    ),
                ],
              ),
            if (showSuggestions) ...[
              if (recents.isNotEmpty)
                const RoutexDivider(role: RoutexDividerRole.section),
              for (final suggestion in suggestions) _suggestionCell(suggestion),
            ],
            if (showSuggestions && hasResults)
              const RoutexDivider(role: RoutexDividerRole.section),
            if (hasResults)
              RoutexResultList(
                status: searching && results.isEmpty
                    ? RoutexResultStatus.loading
                    : RoutexResultStatus.ready,
                loadingMessage: '경로 후보를 찾는 중',
                children: [
                  for (final candidate in results) _candidateCell(candidate),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _candidateCell(DirectionsCandidate candidate) {
    final unroutable = candidate.floor != null && candidate.nodeId == null;
    final subtitle =
        candidate.reason ??
        (unroutable ? '${candidate.subtitle} · 경로 안내 불가' : candidate.subtitle);
    final nodeId = candidate.nodeId;
    final reach = nodeId == null ? null : reachByNodeId?[nodeId];
    return RoutexListCell(
      title: candidate.title,
      subtitle: subtitle,
      metric: reach == null ? null : reachLabel(reach),
      leadingIcon: candidate.buildingId == null
          ? RoutexIcons.place
          : RoutexIcons.building,
      leadingIconTone: RoutexListIconTone.quiet,
      onPressed: () => onPicked(candidate),
    );
  }

  Widget _suggestionCell(StoreSuggestion suggestion) {
    final nearest = nearestByWalkingDistance(
      stores: suggestion.stores,
      reachByNodeId: reachByNodeId,
      currentFloorId: currentFloorId,
    );
    final store = nearest.store;
    final count = suggestion.stores.length;
    return RoutexListCell(
      key: Key('route-field-suggestion-${store.id}'),
      title: store.name,
      subtitle: count > 1 ? '${store.floorName} 등 $count곳' : store.floorName,
      metric: nearest.reach == null ? null : reachLabel(nearest.reach!),
      leadingIcon: RoutexIcons.search,
      leadingIconTone: RoutexListIconTone.quiet,
      onPressed: () => onSuggestionPicked?.call(suggestion),
    );
  }
}
