/// 대중교통 경로 후보 한 장. 배지 박스 없이 색과 글자로만 나눈다.
///
/// 실시간 도착·혼잡도·기후동행은 카카오 응답에 없어 그리지 않는다. 모양의 근거는
/// `docs/superpowers/specs/2026-08-19-route-alternatives-and-guidance-design.md` D절.
library;

import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../map/style/route_style.dart';
import '../models/route/transit_route.dart';
import 'transit_route_summary.dart';
import 'transit_style.dart';

/// 지도 본선과 같은 파랑. DS의 `actionPrimary`는 teal이라 여기 쓰면 초록이 된다.
final _accent = Color(
  0xFF000000 | int.parse(kRouteLineColor.substring(1), radix: 16),
);

class TransitItineraryCard extends StatelessWidget {
  const TransitItineraryCard({
    super.key,
    required this.itinerary,
    required this.fastest,
    required this.onTap,
    this.selected = false,
  });

  final TransitItinerary itinerary;

  /// 목록 첫 줄인지. 맞으면 `최적`을 적는다 — 정렬의 뜻을 밝히지 않으면
  /// 사용자가 첫 줄이 왜 첫 줄인지 추측해야 한다.
  final bool fastest;

  /// 카드를 누르면 상세 경로 화면이 열린다. 카드 한 장이 통째로 그 손잡이라
  /// 접기 화살표 같은 별도 버튼은 두지 않는다.
  final VoidCallback onTap;
  final bool selected;

  /// 탈것 구간만. 노선 줄과 하차 줄이 읽는 값이다.
  List<TransitLeg> get _rides => [
    for (final leg in itinerary.legs)
      if (!leg.mode.isWalk) leg,
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.routexColors;
    final rides = _rides;

    return Material(
      color: selected ? colors.actionPrimarySubtle : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(RoutexSpacing.contentGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (fastest)
                Text(
                  '최적',
                  style: RoutexTypography.bodySmall.copyWith(
                    color: _accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              TransitDurationFare(itinerary: itinerary),
              const SizedBox(height: RoutexSpacing.contentGap),
              TransitLegBar(itinerary: itinerary),
              if (rides.isNotEmpty) ...[
                const SizedBox(height: RoutexSpacing.contentGap),
                for (final ride in rides) _RideRow(leg: ride),
                if (rides.last.endName case final drop?) _DropRow(name: drop),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 탈것 한 줄 — 수단 아이콘 + 색 노선번호(왼쪽) + 승차 정류장명(오른쪽).
///
/// 긴 정류장명은 말줄임하고 **노선번호는 자르지 않는다** — 잘린 번호는 다른
/// 노선으로 읽힌다.
class _RideRow extends StatelessWidget {
  const _RideRow({required this.leg});

  final TransitLeg leg;

  @override
  Widget build(BuildContext context) {
    final colors = context.routexColors;
    final color = transitLegColor(leg);

    return Padding(
      padding: const EdgeInsets.only(bottom: RoutexSpacing.inlineGap),
      child: Row(
        children: [
          Icon(
            transitModeIcon(leg.mode),
            size: RoutexMetrics.iconSmall,
            color: color,
          ),
          const SizedBox(width: RoutexSpacing.inlineGap),
          Text(
            leg.shortLabel,
            style: RoutexTypography.tabular(
              RoutexTypography.body,
            ).copyWith(color: color),
          ),
          if (leg.startName case final board?) ...[
            const SizedBox(width: RoutexSpacing.controlGap),
            Expanded(
              child: Text(
                board,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: RoutexTypography.bodySmall.copyWith(
                  color: colors.contentSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `○ 하차 <이름>` 한 줄.
class _DropRow extends StatelessWidget {
  const _DropRow({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = context.routexColors;
    return Row(
      children: [
        Icon(
          Icons.circle_outlined,
          size: RoutexMetrics.iconSmall,
          color: colors.contentSecondary,
        ),
        const SizedBox(width: RoutexSpacing.inlineGap),
        Text(
          '하차',
          style: RoutexTypography.bodySmall.copyWith(
            color: colors.contentSecondary,
          ),
        ),
        const SizedBox(width: RoutexSpacing.controlGap),
        Expanded(child: Text(name, style: RoutexTypography.body)),
      ],
    );
  }
}
