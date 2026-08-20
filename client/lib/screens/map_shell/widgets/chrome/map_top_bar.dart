import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../../../../models/route/route_plan_mode.dart';

/// 지도 상단의 검색과 경로 계획을 Runtime Kit 패턴에 연결한다.
///
/// 검색·경로 상태와 후보 조회는 상위가 소유하고, 이 위젯은 공개 패턴에 값과
/// callback만 전달한다. 경로 위치를 고치는 동안에는 해당 행 자체가
/// 입력칸이 되며, 독립된 두 번째 검색 바를 만들지 않는다.
class MapTopBar extends StatelessWidget {
  const MapTopBar({
    super.key,
    required this.onMenuTap,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.searchActive,
    required this.onCancelSearch,
    required this.onDirectionsTap,
    this.routeMode = false,
    this.routeEditingField,
    this.originController,
    this.destinationController,
    this.originFocus,
    this.destinationFocus,
    this.onOriginChanged,
    this.onDestinationChanged,
    this.onOriginPressed,
    this.onDestinationPressed,
    this.onClearRouteDraft,
    this.onSwapRouteEndpoints,
    this.canSwapRouteEndpoints = false,
    this.selectedTravelMode = RoutePlanMode.walk,
    this.availableTravelModes = const [RoutePlanMode.walk],
    this.onTravelModeSelected,
    this.hintText = '건물, 장소를 검색하세요',
  });

  final VoidCallback onMenuTap;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final bool searchActive;
  final VoidCallback onCancelSearch;
  final VoidCallback onDirectionsTap;
  final bool routeMode;
  final RoutePlanField? routeEditingField;
  final TextEditingController? originController;
  final TextEditingController? destinationController;
  final FocusNode? originFocus;
  final FocusNode? destinationFocus;
  final ValueChanged<String>? onOriginChanged;
  final ValueChanged<String>? onDestinationChanged;
  final VoidCallback? onOriginPressed;
  final VoidCallback? onDestinationPressed;
  final VoidCallback? onClearRouteDraft;
  final VoidCallback? onSwapRouteEndpoints;
  final bool canSwapRouteEndpoints;
  final RoutePlanMode selectedTravelMode;
  final List<RoutePlanMode> availableTravelModes;
  final ValueChanged<RoutePlanMode>? onTravelModeSelected;
  final String hintText;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      RoutexSpacing.screenGutter,
      RoutexSpacing.controlGap,
      RoutexSpacing.screenGutter,
      0,
    ),
    child:
        routeMode && originController != null && destinationController != null
        ? _routePlanner()
        : _searchBar(),
  );

  Widget _searchBar() => RoutexSearchBar(
    placeholder: hintText,
    controller: controller,
    focusNode: focusNode,
    onSearchPressed: focusNode.requestFocus,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
    onClear: () {
      controller.clear();
      onChanged('');
    },
    leading: searchActive ? RoutexSearchLeading.back : RoutexSearchLeading.menu,
    onLeadingPressed: searchActive ? onCancelSearch : onMenuTap,
    onDirectionsPressed: onDirectionsTap,
  );

  Widget _routePlanner() {
    final planner = RoutexRoutePlanner(
      originLabel: originController!.text.trim().isEmpty
          ? '현재 위치'
          : originController!.text,
      destinationLabel: destinationController!.text.trim().isEmpty
          ? '도착지를 정해 주세요'
          : destinationController!.text,
      travelModes: [
        for (final mode in availableTravelModes)
          RoutexTravelModeOption(
            id: mode.name,
            label: mode.label,
            icon: mode.icon,
          ),
      ],
      selectedTravelModeId: selectedTravelMode.name,
      onTravelModeSelected: (id) {
        final mode = RoutePlanMode.values.firstWhere((item) => item.name == id);
        onTravelModeSelected?.call(mode);
      },
      onOriginPressed: () {
        originFocus?.requestFocus();
        onOriginPressed?.call();
      },
      onDestinationPressed: () {
        destinationFocus?.requestFocus();
        onDestinationPressed?.call();
      },
      onClose: onClearRouteDraft,
      onDestinationMore: canSwapRouteEndpoints ? onSwapRouteEndpoints : null,
      editingField: switch (routeEditingField) {
        RoutePlanField.origin => RoutexRouteField.origin,
        RoutePlanField.destination => RoutexRouteField.destination,
        null => null,
      },
      editingController: switch (routeEditingField) {
        RoutePlanField.origin => originController,
        RoutePlanField.destination => destinationController,
        null => null,
      },
      editingFocusNode: switch (routeEditingField) {
        RoutePlanField.origin => originFocus,
        RoutePlanField.destination => destinationFocus,
        null => null,
      },
      editingFieldKey: switch (routeEditingField) {
        RoutePlanField.origin => const Key('route-draft-origin'),
        RoutePlanField.destination => const Key('route-draft-destination'),
        null => null,
      },
      onEditingChanged: switch (routeEditingField) {
        RoutePlanField.origin => onOriginChanged,
        RoutePlanField.destination => onDestinationChanged,
        null => null,
      },
      onEditingSubmitted: switch (routeEditingField) {
        RoutePlanField.origin => onOriginChanged,
        RoutePlanField.destination => onDestinationChanged,
        null => null,
      },
    );
    return KeyedSubtree(key: const Key('route-planner'), child: planner);
  }
}
