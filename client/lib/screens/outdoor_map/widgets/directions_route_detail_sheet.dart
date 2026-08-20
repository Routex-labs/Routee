import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../../../domain/geo/distance_format.dart';
import '../../../models/route/directions_route.dart';

/// 자동차·도보 경로의 턴바이턴 미리보기.
///
/// 실시간 안내 중 화면(route_steps_sheet.dart)과 재사용하지 않고 분리한다
/// — 그 파일 주석대로 "출발 전 미리보기"와 "걷는 중 배너"는 답하는 질문이
/// 다르다. 이쪽은 진행 중 단계 표시가 없다(아직 출발 전이라 항상 null).
void showDirectionsRouteDetailSheet(
  BuildContext context, {
  required DirectionsRoute route,
  required String destinationLabel,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.5,
    ),
    builder: (context) => _DirectionsRouteDetailSheet(
      route: route,
      destinationLabel: destinationLabel,
    ),
  );
}

class _DirectionsRouteDetailSheet extends StatelessWidget {
  const _DirectionsRouteDetailSheet({
    required this.route,
    required this.destinationLabel,
  });

  final DirectionsRoute route;
  final String destinationLabel;

  @override
  Widget build(BuildContext context) => RoutexBottomSheet(
    showHandle: true,
    header: RoutexSheetHeader(
      title: '$destinationLabel까지',
      onClose: () => Navigator.of(context).pop(),
    ),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight:
            MediaQuery.sizeOf(context).height * 0.5 -
            RoutexMetrics.minimumTouchTarget -
            RoutexSpacing.sectionGap * 2 -
            RoutexSpacing.controlGap,
      ),
      child: SingleChildScrollView(
        child: RoutexStepList(
          steps: [
            for (final step in route.steps)
              RoutexStep(
                instruction: step.instruction,
                icon: _stepIcon(step.instruction),
                distance: step.distanceMeters > 0
                    ? formatDistance(step.distanceMeters)
                    : null,
              ),
          ],
        ),
      ),
    ),
  );
}

/// [step.instruction]은 이 파일이 만든 값(출발/좌회전/우회전/직진/도착)만
/// 들어온다 — 우리가 만든 닫힌 문자열 집합이라 매칭이 안전하다.
IconData _stepIcon(String instruction) => switch (instruction) {
  '좌회전' => RoutexIcons.turnLeft,
  '우회전' => RoutexIcons.turnRight,
  '도착' => RoutexIcons.arrived,
  _ => RoutexIcons.straight,
};
