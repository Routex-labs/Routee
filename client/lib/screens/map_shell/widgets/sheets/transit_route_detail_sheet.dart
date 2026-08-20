/// 대중교통 경로 하나를 자세히 보는 시트. 목록 위에 라우트로 쌓인다.
///
/// **화면 아래 절반만 덮고 위는 지도로 비운다** — 사용자가 시간표를 읽는 동안
/// 그 경로가 어디로 도는지 함께 보여야 한다. 드래그로 크기를 바꾼다.
///
/// 여기서는 아무것도 확정되지 않는다 — 지도를 바꾸는 것은 `안내 시작`뿐이다.
/// 실시간 도착·혼잡도·정류장 번호는 응답에 없어 자리도 두지 않는다. 근거는
/// `docs/superpowers/specs/2026-08-19-route-alternatives-and-guidance-design.md` 4단계 F절.
library;

import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../../../../models/route/transit_route.dart';
import '../../../../widgets/map_overlay_guard.dart';
import '../../../../widgets/transit_route_summary.dart';
import '../../../../widgets/transit_style.dart';
import '../../../../widgets/transit_timeline.dart';
import 'transit_routes_sheet.dart' show kTransitRoutesSheetInitialSize;

/// 상세가 처음 덮는 화면 비율.
///
/// 목록과 **같은 값을 쓴다.** 이 시트가 뜨기 전에 카메라가 그 비율만큼 아래를
/// 비워 두고 경로를 맞춰 놓기 때문이다(`_previewTransitRoute`의
/// `bottomSheetFraction`). 여기서만 다른 값을 쓰면 방금 맞춘 경로가 시트 뒤에
/// 잠기거나 화면 위쪽에 붕 뜬다.
const double kTransitRouteDetailSheetInitialSize =
    kTransitRoutesSheetInitialSize;

/// 드래그로 줄일 수 있는 하한. 이보다 낮추면 요약 한 줄도 안 남아, 접는 것과
/// 닫는 것이 구분되지 않는다.
const double kTransitRouteDetailSheetMinSize = 0.25;

/// 드래그로 키울 수 있는 상한. 1을 주면 지도가 완전히 사라져 "위는 지도"라는
/// 이 화면의 약속이 깨진다.
const double kTransitRouteDetailSheetMaxSize = 0.92;

/// 고른 경로 한 가지의 상세. **보는 화면이지 고르는 화면이 아니다.**
///
/// 뒤로 닫으면 목록이 그대로 남아 다른 경로를 눌러 볼 수 있어야 하므로,
/// 목록 시트를 대체하지 않고 그 위에 라우트를 한 겹 쌓는다.
class TransitRouteDetailSheet extends StatefulWidget {
  const TransitRouteDetailSheet({
    super.key,
    required this.itinerary,
    required this.destinationLabel,
    this.departureAt,
  });

  final TransitItinerary itinerary;

  /// 헤더와 마지막 타임라인 칸에 적을 도착지 이름.
  final String destinationLabel;

  /// 지금 출발한다고 볼 시각. 구간 시작 시각과 도착 예정 시각의 기준이며,
  /// null이면 화면을 그리는 순간이다(테스트만 값을 넘긴다).
  final DateTime? departureAt;

  /// 목록 시트 위에 상세를 띄운다.
  ///
  /// `안내 시작`을 눌렀을 때만 **true**를 돌려주고, 뒤로가기로 닫으면 null이다.
  /// 상세는 보는 화면이라 열고 닫는 것만으로는 지도에 아무 일도 일어나지
  /// 않는다 — 배선하는 쪽은 true일 때만 경로를 확정한다.
  static Future<bool?> show(
    BuildContext context, {
    required TransitItinerary itinerary,
    required String destinationLabel,
    DateTime? departureAt,
  }) {
    return Navigator.of(context).push<bool>(
      _DetailRoute(
        builder: (context) => MapOverlayGuard(
          child: TransitRouteDetailSheet(
            itinerary: itinerary,
            destinationLabel: destinationLabel,
            departureAt: departureAt,
          ),
        ),
      ),
    );
  }

  @override
  State<TransitRouteDetailSheet> createState() =>
      _TransitRouteDetailSheetState();
}

class _TransitRouteDetailSheetState extends State<TransitRouteDetailSheet> {
  /// 화면을 다시 그려도 시각이 흔들리지 않게 한 번만 읽는다.
  late final DateTime _departure = widget.departureAt ?? DateTime.now();

  /// 손잡이·머리말 드래그를 시트 크기로 옮기는 손잡이.
  final _sheet = DraggableScrollableController();

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  /// 스크롤되지 않는 부분(손잡이·머리말)을 끌어도 시트가 커지고 작아지게 한다.
  ///
  /// [DraggableScrollableSheet]는 **자기 스크롤 뷰에 실린 드래그만** 크기로
  /// 옮긴다. 그래서 시간표를 끌면 되는데 정작 눈에 보이는 손잡이를 끌면 아무
  /// 일도 안 일어났다 — 사용자가 가장 먼저 잡는 자리가 그곳이다.
  void _dragSheet(DragUpdateDetails details) {
    if (!_sheet.isAttached) return;
    final height = MediaQuery.sizeOf(context).height;
    if (height <= 0) return;
    // 위로 끌면(dy < 0) 커진다. 화면 높이로 나눠 픽셀을 비율로 옮긴다.
    final next = (_sheet.size - details.delta.dy / height).clamp(
      kTransitRouteDetailSheetMinSize,
      kTransitRouteDetailSheetMaxSize,
    );
    _sheet.jumpTo(next);
  }

  @override
  Widget build(BuildContext context) {
    final itinerary = widget.itinerary;

    // 시트 **바깥**(=지도)을 누르면 닫는다. 목록 시트와 같은 규약이라 두 겹이
    // 같은 방식으로 걷힌다.
    return GestureDetector(
      onTap: () => Navigator.of(context).maybePop(),
      behavior: HitTestBehavior.opaque,
      child: DraggableScrollableSheet(
        controller: _sheet,
        initialChildSize: kTransitRouteDetailSheetInitialSize,
        minChildSize: kTransitRouteDetailSheetMinSize,
        maxChildSize: kTransitRouteDetailSheetMaxSize,
        expand: false,
        builder: (context, scrollController) => GestureDetector(
          // 시트 안의 탭은 바깥 제스처로 새지 않는다.
          onTap: () {},
          behavior: HitTestBehavior.opaque,
          child: RoutexBottomSheet(
            contentInset: RoutexBottomSheetContentInset.content,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 손잡이만 스크롤 밖에 둔다. **머리말과 요약까지 고정하면
                // 시트를 끝까지 줄였을 때 고정분이 시트보다 커져 Column이
                // 넘친다**(실기기에서 21px 넘침으로 나타났다). 스크롤 안에
                // 있으면 줄인 만큼 자연스럽게 가려질 뿐이다.
                GestureDetector(
                  onVerticalDragUpdate: _dragSheet,
                  behavior: HitTestBehavior.opaque,
                  child: const RoutexSheetHandle(),
                ),
                Expanded(
                  // **시트의 스크롤 컨트롤러를 그대로 쓴다.** 자기 컨트롤러를
                  // 두면 맨 위에서 아래로 끌 때 시트가 안 줄어들고, 반대로
                  // 시트를 키우는 드래그가 목록 스크롤로 새어 든다.
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: RoutexSpacing.contentGap,
                          ),
                          child: RoutexSheetHeader(
                            title: '${widget.destinationLabel}까지',
                            // 뒤로는 이 화면만 닫는다. 목록이 그대로 남아 다른
                            // 경로를 눌러 보는 것이 이 화면의 존재 이유다.
                            onBack: () => Navigator.of(context).pop(),
                          ),
                        ),
                        _Summary(
                          itinerary: itinerary,
                          arrival: transitArrivalTime(_departure, itinerary),
                        ),
                        const RoutexDivider(role: RoutexDividerRole.section),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: RoutexSpacing.componentPadding,
                            vertical: RoutexSpacing.contentGap,
                          ),
                          child: TransitTimeline(
                            itinerary: itinerary,
                            destinationLabel: widget.destinationLabel,
                            departureAt: _departure,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const RoutexDivider(role: RoutexDividerRole.section),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    RoutexSpacing.componentPadding,
                    RoutexSpacing.contentGap,
                    RoutexSpacing.componentPadding,
                    RoutexSpacing.contentGap +
                        MediaQuery.paddingOf(context).bottom,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: RoutexButton(
                      label: '안내 시작',
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 총 소요 · 요금 · 도착 예정 시각.
class _Summary extends StatelessWidget {
  const _Summary({required this.itinerary, required this.arrival});

  final TransitItinerary itinerary;
  final DateTime? arrival;

  @override
  Widget build(BuildContext context) {
    final colors = context.routexColors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RoutexSpacing.componentPadding,
        RoutexSpacing.controlGap,
        RoutexSpacing.componentPadding,
        RoutexSpacing.contentGap,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TransitDurationFare(itinerary: itinerary),
          if (arrival case final arrival?) ...[
            const SizedBox(height: RoutexSpacing.inlineGap),
            Text(
              '${formatTransitClockTime(arrival)} 도착',
              style: RoutexTypography.bodySmall.copyWith(
                color: colors.contentSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 목록을 **화면에서 내리지 않는** 라우트.
///
/// 불투명 라우트는 아래 라우트를 offstage로 내린다. 그러면 목록이 위젯 트리에서
/// 사라져 지도 플랫폼 뷰가 헐렸다 다시 붙고, 웹에서는 [MapOverlayGuard]가 막을
/// 대상 자체가 없어진다. **투명해야 위 절반의 지도도 보인다** — 목록은 상세가
/// 떠 있는 동안 스스로 물러난다(`TransitRoutesSheet`).
///
/// `MaterialPageRoute` 대신 mixin을 직접 쓰는 이유는 하나다 — 그 생성자가
/// `assert(opaque)`라 상속으로는 투명하게 만들 수 없다. 전환 효과는 같다.
class _DetailRoute<T> extends PageRoute<T> with MaterialRouteTransitionMixin<T> {
  _DetailRoute({required this.builder});

  final WidgetBuilder builder;

  @override
  Widget buildContent(BuildContext context) => builder(context);

  @override
  bool get maintainState => true;

  @override
  bool get opaque => false;
}
