/// 대중교통 경로 한 벌을 요약해 그리는 공용 조각 — `소요 │ 요금` 줄과 구간 막대.
///
/// 후보 목록 카드·상세 화면·하단 요약 카드가 **같은 경로를 같은 모양으로** 말해야
/// 해서 한곳에 둔다. 모양의 근거는
/// `docs/superpowers/specs/2026-08-19-route-alternatives-and-guidance-design.md` D절.
library;

import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../models/route/transit_route.dart';
import 'transit_style.dart';

/// `59분 │ 1,850원` 한 줄. 요금을 모르면 요금과 구분선을 함께 뺀다.
class TransitDurationFare extends StatelessWidget {
  const TransitDurationFare({super.key, required this.itinerary});

  final TransitItinerary itinerary;

  @override
  Widget build(BuildContext context) {
    final colors = context.routexColors;
    final fare = itinerary.fare;

    return Row(
      children: [
        Text(
          formatTransitDuration(itinerary.totalTimeSeconds),
          style: RoutexTypography.tabular(RoutexTypography.headline),
        ),
        // 요금이 없으면 구분선도 함께 뺀다 — 안 그러면 헤더가 `19분 │`로
        // 끝난다. 짧은 버스는 실제로 null로 온다.
        if (fare != null && fare > 0) ...[
          Container(
            width: 1,
            height: 12,
            margin: const EdgeInsets.symmetric(
              horizontal: RoutexSpacing.controlGap,
            ),
            color: colors.borderStrong,
          ),
          Text(
            formatTransitFare(fare),
            style: RoutexTypography.bodySmall.copyWith(
              color: colors.contentSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// 구간을 소요 시간 비율대로 이은 막대. 연한 트랙 하나 위에 탈것만 색 pill이다.
///
/// 총 소요가 0이면 그리지 않는다 — 비율을 낼 수 없다. 짧은 구간이 사라지지
/// 않도록 [Expanded]의 flex를 최소 1로 올린다. 비율이 그만큼 거짓이 되지만,
/// 1픽셀짜리 칸은 있으나 마나다.
class TransitLegBar extends StatelessWidget {
  const TransitLegBar({super.key, required this.itinerary});

  final TransitItinerary itinerary;

  /// 트랙 높이. caption 글리프 12 px가 상하 2 px씩 남기고 들어가는 최소치다.
  static const _height = 16.0;

  /// 이 칸에 적을 시간. **0초면 null** — 값이 아니라 "모른다"는 뜻이다.
  ///
  /// TMAP 조회가 없거나 실패한 앞뒤 도보가 0초로 온다(`domain/route/
  /// transit_walk_fill.dart`). formatTransitDuration은 0초를 1분으로 올리므로
  /// 그대로 넘기면 모르는 도보에 "1분"이라고 적힌다. 그 함수는 진짜 짧은
  /// 구간에도 쓰여 올림이 맞으니, 그릴지 말지는 아는 쪽인 여기서 정한다.
  static String? _label(TransitLeg leg) => leg.sectionTimeSeconds > 0
      ? formatTransitDuration(leg.sectionTimeSeconds)
      : null;

  @override
  Widget build(BuildContext context) {
    final total = itinerary.totalTimeSeconds;
    if (total <= 0 || itinerary.legs.isEmpty) return const SizedBox.shrink();
    final colors = context.routexColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.borderSubtle,
        borderRadius: BorderRadius.circular(_height / 2),
      ),
      child: SizedBox(
        height: _height,
        child: Row(
          children: [
            for (final leg in itinerary.legs)
              Expanded(
                flex: (leg.sectionTimeSeconds * 100 / total).round().clamp(
                  1,
                  100,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: leg.mode.isWalk
                      ? Center(
                          child: _BarLabel(
                            text: _label(leg),
                            color: colors.contentSecondary,
                          ),
                        )
                      : _Pill(leg: leg, label: _label(leg)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 색을 꽉 채운 탈것 칸. **글자색은 배경에서 정한다.**
///
/// 흰색으로 못 박으면 9호선 금색·순환버스 노랑 같은 밝은 표준색에서 글자가
/// 사라진다. 판정과 그 경계값의 근거는 `transitInkOn`에 있다.
class _Pill extends StatelessWidget {
  const _Pill({required this.leg, required this.label});

  final TransitLeg leg;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final color = transitLegColor(leg);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(TransitLegBar._height / 2),
      ),
      child: Center(
        child: _BarLabel(
          icon: transitModeIcon(leg.mode),
          text: label,
          color: transitInkOn(color),
        ),
      ),
    );
  }
}

/// 막대 한 칸의 아이콘 + 소요 시간. **좁으면 글자를, 더 좁으면 전부 뺀다.**
///
/// 자르지 않는 이유는 실기기에서 "3분"이 "3"으로 잘려 정류장 수로 읽혔기
/// 때문이다. 잘린 숫자는 정보가 아니라 오독이다. [text]가 null이면 시간을
/// 모른다는 뜻이라 같은 이유로 빼고 아이콘만 남긴다 — 없는 숫자도 오독이다.
class _BarLabel extends StatelessWidget {
  const _BarLabel({required this.text, required this.color, this.icon});

  final String? text;
  final Color color;
  final IconData? icon;

  static const _iconSize = 11.0;
  static const _gap = 2.0;

  @override
  Widget build(BuildContext context) {
    // caption은 `height: 1.5`라 라인박스가 18 px다. 트랙이 16 px이므로 1.0으로
    // 눌러야 들어간다 — 안 누르면 감춰지는 게 아니라 오버플로가 난다.
    final style = RoutexTypography.caption.copyWith(color: color, height: 1);
    final label = text;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (label != null) {
          final painter = TextPainter(
            text: TextSpan(text: label, style: style),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          final iconWidth = icon == null ? 0.0 : _iconSize + _gap;
          if (painter.width + iconWidth <= constraints.maxWidth) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: _iconSize, color: color),
                  const SizedBox(width: _gap),
                ],
                Text(label, maxLines: 1, style: style),
              ],
            );
          }
        }
        if (icon != null && _iconSize <= constraints.maxWidth) {
          return Icon(icon, size: _iconSize, color: color);
        }
        return const SizedBox.shrink();
      },
    );
  }
}
