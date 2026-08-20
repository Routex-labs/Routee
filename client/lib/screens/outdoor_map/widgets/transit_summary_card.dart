import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../../../models/route/transit_route.dart';
import '../../../widgets/transit_route_summary.dart';
import '../../../widgets/transit_style.dart';
import '../../../widgets/transit_timeline.dart';

/// 확정한 대중교통 경로의 하단 요약. **후보 목록 카드와 같은 구간 막대로 말한다.**
///
/// 환승 횟수·도보 시간을 나열하던 글과 노선 칩 스트립은 걷어냈다 — 막대가 이미
/// 그림으로 말하는 것을 글로 다시 적으면 카드만 높아지고, 그만큼 지도가 가려진다
/// (카메라 여백을 `outdoor_map/parts/indoor.dart`의 `_fitCameraToPoints`가 이 카드
/// 높이로 잰다). 세부는 접어 두고 화살표로 그 자리에서 펼친다.
class TransitSummaryCard extends StatefulWidget {
  const TransitSummaryCard({
    super.key,
    required this.itinerary,
    required this.label,
    required this.onClose,
    this.onStartGuidance,
    this.onClosePointerDown,
  });

  final TransitItinerary itinerary;
  final String label;
  final VoidCallback onClose;

  /// null이면 이미 안내 중이라는 뜻이다 — 그때는 `안내 종료`만 남는다.
  final VoidCallback? onStartGuidance;

  final ValueChanged<Offset>? onClosePointerDown;

  @override
  State<TransitSummaryCard> createState() => _TransitSummaryCardState();
}

class _TransitSummaryCardState extends State<TransitSummaryCard> {
  /// 세부 타임라인을 펼쳐 뒀는지. **기본은 접힘** — 펼친 채로 시작하면 확정
  /// 직후 카메라가 잰 카드 높이만큼 지도가 밀려 경로가 화면 밖으로 나간다.
  bool _expanded = false;

  /// 펼친 세부가 먹어도 되는 화면 몫. 나머지는 지도로 남는다.
  static const _detailHeightFraction = 0.4;

  @override
  Widget build(BuildContext context) {
    final itinerary = widget.itinerary;
    // 안내 중에도 "지금 출발한다면"으로 계산한다. 지나온 구간을 지우려면 진행
    // 위치가 필요한데 이 카드는 그것을 모른다 — 도착 시각도 같은 기준이다.
    final departure = DateTime.now();
    final fare = itinerary.fare;
    final start = widget.onStartGuidance;

    final child = start == null
        ? RoutexBottomSheet(
            showHandle: false,
            includeBottomSafeArea: true,
            child: RoutexStack(
              gap: RoutexStackGap.content,
              children: [
                TransitDurationFare(itinerary: itinerary),
                _details(context, departure),
                RoutexButton(
                  label: '안내 종료',
                  variant: RoutexButtonVariant.secondary,
                  onPressed: widget.onClose,
                ),
              ],
            ),
          )
        // 안내 전에는 소요·요금을 카드가 이미 지표 줄로 적는다. 위에 같은 값을
        // 한 줄 더 두면 한 화면에 소요 시간이 두 개가 된다.
        : RoutexEtaCard(
            title: widget.label,
            arrivalTime: TimeOfDay.fromDateTime(
              transitArrivalTime(departure, itinerary) ?? departure,
            ).format(context),
            metrics: [
              RoutexTripMetric(
                value: formatTransitDuration(itinerary.totalTimeSeconds),
                label: '소요',
              ),
              if (fare != null && fare > 0)
                RoutexTripMetric(value: formatTransitFare(fare), label: '요금'),
            ],
            routeOptions: _details(context, departure),
            onStart: start,
          );

    return Listener(
      onPointerDown: (event) => widget.onClosePointerDown?.call(event.position),
      child: child,
    );
  }

  /// 구간 막대 + 펼치기 + (펼쳤을 때) 세부 타임라인.
  Widget _details(BuildContext context, DateTime departure) {
    return RoutexStack(
      gap: RoutexStackGap.inline,
      children: [
        TransitLegBar(itinerary: widget.itinerary),
        RoutexShowMore(
          expanded: _expanded,
          onExpanded: (value) => setState(() => _expanded = value),
        ),
        if (_expanded)
          ConstrainedBox(
            // 세부는 구간 수만큼 길어진다. 상한을 안 두면 환승이 많은 경로에서
            // 카드가 지도를 통째로 덮는다.
            constraints: BoxConstraints(
              maxHeight:
                  MediaQuery.sizeOf(context).height * _detailHeightFraction,
            ),
            child: SingleChildScrollView(
              child: TransitTimeline(
                itinerary: widget.itinerary,
                destinationLabel: widget.label,
                departureAt: departure,
              ),
            ),
          ),
      ],
    );
  }
}
