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
    // **X는 검색을 끝낸다** — 글자만 지우고 서 있지 않는다. 이 검색창은 입력칸
    // 하나가 아니라 모드다(결과 패널이 지도를 덮고 제스처를 잠근다). 글자만
    // 지우면 키보드와 패널이 남은 채 아무 결과도 없는 화면이 되는데, 사용자는
    // 그것을 "지웠는데 아무 일도 안 일어났다"로 읽는다(실기기 확인).
    //
    // 되돌리는 일 자체는 [onCancelSearch] 하나가 맡는다 — ←(뒤로)와 같은 자리다.
    // 입구마다 따로 지우면 한쪽만 고쳐지는 날이 온다.
    onClear: onCancelSearch,
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
