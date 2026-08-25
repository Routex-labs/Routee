/// 경로 전체 단계 목록을 그리는 **한 벌의 위젯**.
///
/// 이 목록을 보여 주는 자리가 둘이다 — 걷는 중 배너를 탭해 올라오는 시트
/// (`outdoor_map/widgets/route_steps_sheet.dart`)와, 출발 전 ETA 카드 안에서
/// 접었다 펴는 줄([CollapsibleRouteSteps]). 둘이 각자 목록을 조립하면 아이콘
/// 매핑이나 도착 행 문구가 한쪽에서만 바뀐다.
library;

import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../domain/guidance/route_guidance.dart';
import 'eta_card.dart';

/// 단계 목록 본문. 스크롤도 높이 제한도 하지 않는다 — **얼마나 보여 줄지는
/// 놓는 쪽이 정한다.** 시트와 카드가 쓸 수 있는 화면 몫이 다르다.
class RouteStepsView extends StatelessWidget {
  const RouteStepsView({
    super.key,
    required this.steps,
    required this.destinationName,
  });

  final List<RouteStep> steps;
  final String destinationName;

  @override
  Widget build(BuildContext context) => RoutexStepList(
    steps: [
      for (final step in steps)
        () {
          final parts = routeStepParts(step);
          return RoutexStep(
            // 도착 행은 어디에 도착하는지까지 말한다 — "도착" 한 단어는
            // 목록의 마지막 줄로는 심심하다.
            instruction: step.action == RouteGuidanceAction.arrived
                ? '$destinationName 도착'
                : parts.instruction,
            // 걷는 중 배너와 같은 매핑 — 이유는 [routeGuidanceIcon]에.
            icon: routeGuidanceIcon(step.action),
            distance: parts.distance,
            detail: parts.detail,
          );
        }(),
    ],
    // 지금 어느 단계인지는 아직 세지 않는다. 계약상 null은 "아직 출발하지
    // 않았다"는 뜻이고, 이 목록을 여는 자리가 대부분 그 상태다.
  );
}

/// 접어 둔 단계 목록. 화살표를 누르면 그 자리에서 펴진다.
///
/// **기본은 접힘이다.** 경로를 그리자마자 전체 단계가 펼쳐지면 카드가 화면
/// 절반을 먹고, 그 높이를 재서 여백을 잡는 카메라가([OutdoorMapBody]의
/// `bottomCardLiftPx`) 방금 그린 경로를 화면 밖으로 밀어낸다. 대중교통 요약
/// 카드가 세부 타임라인을 접어 두는 것과 같은 이유·같은 조작이다
/// (`outdoor_map/widgets/transit_summary_card.dart`).
class CollapsibleRouteSteps extends StatefulWidget {
  const CollapsibleRouteSteps({
    super.key,
    required this.steps,
    required this.destinationName,
  });

  final List<RouteStep> steps;
  final String destinationName;

  @override
  State<CollapsibleRouteSteps> createState() => _CollapsibleRouteStepsState();
}

class _CollapsibleRouteStepsState extends State<CollapsibleRouteSteps> {
  bool _expanded = false;

  /// 펼친 목록이 먹어도 되는 화면 몫. 대중교통 카드(0.4)보다 조금 작다 —
  /// 이 카드에는 수직 이동 선호 줄이 위에 하나 더 있다.
  static const _expandedHeightFraction = 0.35;

  @override
  Widget build(BuildContext context) {
    if (widget.steps.isEmpty) return const SizedBox.shrink();
    return RoutexStack(
      gap: RoutexStackGap.inline,
      children: [
        RoutexShowMore(
          expanded: _expanded,
          // 접혀 있을 때 "7개 더보기"로 규모까지 말한다. 별도 요약 줄을 두는
          // 것보다 짧고, 펼칠지 말지를 그 숫자 하나로 정할 수 있다.
          hiddenCount: widget.steps.length,
          onExpanded: (value) => setState(() => _expanded = value),
        ),
        if (_expanded)
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight:
                  MediaQuery.sizeOf(context).height * _expandedHeightFraction,
            ),
            child: SingleChildScrollView(
              child: RouteStepsView(
                steps: widget.steps,
                destinationName: widget.destinationName,
              ),
            ),
          ),
      ],
    );
  }
}
