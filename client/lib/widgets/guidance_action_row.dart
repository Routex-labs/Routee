import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

/// 안내 중 하단 카드의 **왼쪽 버튼** — 실내로 들어가거나 밖으로 나가는 전환.
///
/// [onPressed]가 null이면 버튼은 자리를 지키되 눌리지 않는다. 조건을 못 채웠다고
/// 버튼을 숨기지 않는 것이 요점이다 — 문 앞에 다 와서야 처음 보이는 버튼은
/// 사용자가 그런 것이 있는 줄도 모르고, 회색으로 먼저 보여야 "가까이 가면
/// 눌리는 것"이라는 것을 걸어가는 동안 배운다.
class GuidanceTransitionAction {
  const GuidanceTransitionAction({required this.label, required this.onPressed});

  final String label;

  /// null이면 비활성. 활성 조건은 `screens/outdoor_map/entry/manual_transition_gate.dart`.
  final VoidCallback? onPressed;
}

/// 하단 카드 맨 아래 버튼 줄. 전환 버튼이 없으면 `안내 종료` 하나가 폭을 다 쓴다.
///
/// 전환 버튼이 **왼쪽**인 이유는 위계다. 오른쪽 끝은 엄지가 가장 먼저 닿는
/// 자리인데 그 자리에 되돌릴 수 없는 조작(안내 종료)이 이미 있었다. 새 버튼을
/// 거기 두면 익숙해진 손이 종료 대신 진입을 누른다.
class GuidanceActionRow extends StatelessWidget {
  const GuidanceActionRow({
    super.key,
    required this.onStop,
    this.transition,
    this.stopLabel = '안내 종료',
  });

  final VoidCallback? onStop;
  final GuidanceTransitionAction? transition;
  final String stopLabel;

  /// 전환 버튼을 위젯 테스트가 집는 손잡이.
  static const transitionButtonKey = Key('guidance-transition-button');

  @override
  Widget build(BuildContext context) {
    final stop = RoutexButton(
      label: stopLabel,
      variant: RoutexButtonVariant.secondary,
      onPressed: onStop,
    );
    final transition = this.transition;
    if (transition == null) return stop;

    return Row(
      children: [
        Expanded(
          child: RoutexButton(
            key: transitionButtonKey,
            label: transition.label,
            onPressed: transition.onPressed,
          ),
        ),
        const SizedBox(width: RoutexSpacing.controlGap),
        Expanded(child: stop),
      ],
    );
  }
}

/// 남은 시간·거리 세 값을 한 줄에 늘어놓는다.
///
/// `RoutexTripProgress`가 이미 같은 줄을 그리지만 **버튼 슬롯이 하나뿐이라**
/// 전환 버튼을 얹을 자리가 없다. 디자인시스템은 git ref로 고정돼 있어 이쪽에서
/// 못 고치므로, 전환 버튼이 있는 동안만 수치 줄을 여기서 그리고 버튼 줄을
/// 아래에 붙인다. 큰 글자에서 `RoutexTripProgress`가 스스로 택하는 배치와
/// 같은 모양이다 — 새 레이아웃을 만든 것이 아니라 그쪽 갈래를 앞당겨 쓴다.
class GuidanceTripMetricsRow extends StatelessWidget {
  const GuidanceTripMetricsRow({super.key, required this.metrics});

  final List<RoutexTripMetric> metrics;

  @override
  Widget build(BuildContext context) {
    final colors = context.routexColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final metric in metrics)
          Expanded(
            child: RoutexStack(
              gap: RoutexStackGap.inline,
              children: [
                Text(
                  metric.value,
                  style: RoutexTypography.tabular(RoutexTypography.label),
                ),
                Text(
                  metric.label,
                  style: RoutexTypography.caption.copyWith(
                    color: colors.contentSecondary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
