/// 대중교통 경로 하나를 자세히 보는 **전체 화면**. 목록 시트 위에 라우트로 쌓인다.
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

/// 고른 경로 한 가지의 상세. **보는 화면이지 고르는 화면이 아니다.**
///
/// 뒤로 닫으면 목록이 그대로 남아 다른 경로를 눌러 볼 수 있어야 하므로,
/// 목록 시트를 대체하지 않고 그 위에 라우트를 한 겹 쌓는다. 이름의 `Sheet`는
/// 시트였던 시절의 흔적이다 — 여러 테스트가 이 타입으로 화면을 찾는다.
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

  /// 목록 시트 위에 상세를 전체 화면으로 띄운다.
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

  @override
  Widget build(BuildContext context) {
    final itinerary = widget.itinerary;

    return Scaffold(
      // 아래 목록이 비치지 않으려면 표면이 불투명해야 한다. 이것이 시트를
      // 그만둔 이유다 — 투명한 시트 위에 시트를 얹으니 둘이 겹쳐 보였다.
      backgroundColor: context.routexColors.surfaceBase,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: RoutexSpacing.contentGap,
              ),
              child: RoutexSheetHeader(
                title: '${widget.destinationLabel}까지',
                // 뒤로는 이 화면만 닫는다. 목록이 그대로 남아 다른 경로를
                // 눌러 보는 것이 이 화면의 존재 이유다.
                onBack: () => Navigator.of(context).pop(),
              ),
            ),
            _Summary(
              itinerary: itinerary,
              arrival: transitArrivalTime(_departure, itinerary),
            ),
            const RoutexDivider(role: RoutexDividerRole.section),
            Expanded(
              child: SingleChildScrollView(
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
            ),
            const RoutexDivider(role: RoutexDividerRole.section),
            Padding(
              // 아래 여백은 SafeArea가 이미 홈 인디케이터만큼 밀어 둔다.
              padding: const EdgeInsets.symmetric(
                horizontal: RoutexSpacing.componentPadding,
                vertical: RoutexSpacing.contentGap,
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

/// 목록을 **화면에서 내리지 않는** 전체 화면 라우트.
///
/// 불투명 라우트는 아래 라우트를 offstage로 내린다. 그러면 목록이 위젯 트리에서
/// 사라져 지도 플랫폼 뷰가 헐렸다 다시 붙고, 웹에서는 [MapOverlayGuard]가 막을
/// 대상 자체가 없어진다. 겹쳐 보이던 문제는 막이 아니라 이 화면의 불투명한
/// 표면이 막으므로 라우트 자체는 투명해도 된다.
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
