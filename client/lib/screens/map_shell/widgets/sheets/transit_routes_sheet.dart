import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../../../../models/route/transit_route.dart';
import '../../../../widgets/map_overlay_guard.dart';
import '../../../../domain/route/transit_itinerary_filter.dart';
import '../../../../widgets/transit_itinerary_card.dart';
import 'transit_route_detail_sheet.dart';

/// 시트가 처음 덮는 화면 비율. 후보를 미리 그리는 쪽이 카메라 아래 여백을
/// 이만큼 비워야 경로가 시트 뒤에 잠기지 않는다 — 그래서 숫자를 여기 하나만
/// 두고 양쪽이 읽는다.
const double kTransitRoutesSheetInitialSize = 0.55;

/// 대중교통 경로 후보 목록 시트.
///
/// 목록으로 두는 이유는 **가장 빠른 경로가 늘 최선은 아니기 때문**이다. 3분
/// 빠른 대신 두 번 갈아타는 경로와, 조금 느려도 한 번에 가는 경로 중 무엇을
/// 고를지는 사용자만 안다. 그래서 각 줄에 소요 시간뿐 아니라 환승 횟수·도보
/// 시간·요금을 함께 적는다.
class TransitRoutesSheet extends StatefulWidget {
  const TransitRoutesSheet({
    super.key,
    required this.routes,
    required this.destinationLabel,
    required this.onCloseAll,
    required this.onPreview,
  });

  final TransitRoutes routes;

  /// 상세 화면이 "OO까지"에 쓸 도착지 이름. 목록 자신은 안 적는다 — 화면 위
  /// 길찾기 바가 이미 말하고 있어서 두 번 적으면 후보 한 장이 밀린다.
  final String destinationLabel;

  /// 고르지 않고 목록이 닫혔을 때. 시트 chain 전체를 접으라는 신호다.
  final VoidCallback onCloseAll;

  /// 카드를 눌렀을 때 **지도에 그릴** 후보. 확정이 아니라 미리보기라, 이 뒤에도
  /// 목록은 그대로 남아 다른 후보를 이어서 볼 수 있다.
  final ValueChanged<TransitItinerary> onPreview;

  /// 후보 목록을 띄우고, 사용자가 **확정한** 경로 하나를 돌려준다.
  ///
  /// 카드를 누르는 것은 고르는 것이 아니라 지도를 갈아치우고 상세를 열어 보는
  /// 것이다 — 확정은 상세 하단 `안내 시작`뿐이라, 그때만 값이 나오고 그 밖에는
  /// null이다.
  static Future<TransitItinerary?> show(
    BuildContext context, {
    required TransitRoutes routes,
    required String destinationLabel,
    required VoidCallback onCloseAll,
    required ValueChanged<TransitItinerary> onPreview,
  }) {
    return showModalBottomSheet<TransitItinerary>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      builder: (context) => MapOverlayGuard(
        child: TransitRoutesSheet(
          routes: routes,
          destinationLabel: destinationLabel,
          onCloseAll: onCloseAll,
          onPreview: onPreview,
        ),
      ),
    );
  }

  @override
  State<TransitRoutesSheet> createState() => _TransitRoutesSheetState();
}

class _TransitRoutesSheetState extends State<TransitRoutesSheet> {
  bool _intentionalPop = false;

  /// 지금 고른 갈래. **목록만 좁힌다** — 지도에 그려진 경로는 건드리지 않는다.
  /// 필터는 보는 범위를 줄이는 것이지 선택을 바꾸는 것이 아니다.
  TransitFilter _filter = TransitFilter.all;

  void _markIntentional() => _intentionalPop = true;

  /// 카드 한 장을 눌렀을 때. **여기서는 아직 아무것도 확정되지 않는다** —
  /// 지도를 그 후보로 갈아치우고 상세를 한 겹 위에 띄운다. 거기서 `안내 시작`을
  /// 눌렀을 때만(true) 그 경로를 결과로 목록을 닫는다. 뒤로 닫히면(null) 목록에
  /// 그대로 머물러 다른 후보를 이어서 볼 수 있다 — 견주는 단계가 이것이다.
  ///
  /// 상세를 띄우기 **전에** 그린다. 뒤에 그리면 상세를 닫기 전까지 지도가 앞
  /// 후보를 들고 있어, 뒤로 나온 순간 화면이 한 번 더 바뀐다.
  Future<void> _pick(TransitItinerary itinerary) async {
    widget.onPreview(itinerary);
    final start = await TransitRouteDetailSheet.show(
      context,
      itinerary: itinerary,
      destinationLabel: widget.destinationLabel,
    );
    if (!mounted || start != true) return;
    _markIntentional();
    Navigator.of(context).pop(itinerary);
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.routes.itineraries;
    final filters = availableTransitFilters(all);
    // 목록이 바뀌어 고른 갈래가 사라졌으면 전체로 되돌린다. 그러지 않으면 아무
    // 탭도 안 눌린 채 빈 목록만 남는다.
    final filter = filters.contains(_filter) ? _filter : TransitFilter.all;
    final itineraries = applyTransitFilter(all, filter);
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_intentionalPop) widget.onCloseAll();
      },
      child: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        behavior: HitTestBehavior.opaque,
        child: DraggableScrollableSheet(
          initialChildSize: kTransitRoutesSheetInitialSize,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) => GestureDetector(
            onTap: () {},
            behavior: HitTestBehavior.opaque,
            child: RoutexBottomSheet(
              // 표면은 Runtime Kit이, 드래그와 라우트는 앱이 갖는다. 여백은 조각마다
              // 달라서 본문이 소유한다.
              contentInset: RoutexBottomSheetContentInset.content,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const RoutexSheetHandle(),
                  RoutexTabs(
                    // '전체'에는 숫자를 안 붙인다. 전부라는 말 자체가 개수보다
                    // 먼저 읽히고, 나머지 탭의 숫자와 뜻이 겹친다.
                    labels: [
                      for (final item in filters)
                        item == TransitFilter.all
                            ? item.label
                            : '${item.label} ${transitFilterCount(all, item)}',
                    ],
                    selectedIndex: filters.indexOf(filter),
                    onSelected: (index) =>
                        setState(() => _filter = filters[index]),
                  ),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      padding: EdgeInsets.only(
                        top: 4,
                        bottom: 16 + MediaQuery.paddingOf(context).bottom,
                      ),
                      itemCount: itineraries.length,
                      separatorBuilder: (_, _) =>
                          const RoutexDivider(role: RoutexDividerRole.row),
                      itemBuilder: (context, index) => TransitItineraryCard(
                        itinerary: itineraries[index],
                        // 첫 줄은 정렬상 가장 빠른 경로다. 그 사실을 배지로
                        // 밝히지 않으면 사용자는 순서의 의미를 추측해야 한다.
                        fastest: index == 0 && itineraries.length > 1,
                        onTap: () => _pick(itineraries[index]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
