/// 지도 좌상단의 축척 막대. "지금 이 화면에서 이만큼이 몇 m인가"만 말한다.
///
/// 얼마를 얼마 길이로 그릴지는 `map/camera/scale_bar.dart`가 정하고, 여기는
/// 그 결과를 그리기만 한다. 검증 기준은
/// `client/test/map/camera/scale_bar_test.dart`.
library;

import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../../../map/camera/scale_bar.dart';

/// 막대가 커질 수 있는 상한(논리 px).
///
/// 실제 폭은 이보다 짧다 — 딱 떨어지는 값(1·2·5 × 10ⁿ)으로 내려서 그린다.
/// 좁게 두면 같은 배율에서도 한 단계 작은 값이 걸려 막대가 뭉툭해지고, 넓게
/// 두면 지도 왼쪽 위를 그만큼 가린다.
const double kMapScaleBarMaxWidthPx = 72;

/// 축척 막대. [step]이 null이면(카메라를 아직 모르는 프레임) 아무것도 안 그린다.
class MapScaleBar extends StatelessWidget {
  const MapScaleBar({super.key, required this.step});

  final MapScaleStep? step;

  @override
  Widget build(BuildContext context) {
    final step = this.step;
    if (step == null) return const SizedBox.shrink();
    final colors = context.routexColors;
    return Semantics(
      container: true,
      label: '지도 축척 ${step.label}',
      excludeSemantics: true,
      // **면을 깔지 않는다.** 알약을 두면 지도 위에 누를 수 있는 것이 하나 더
      // 있는 것처럼 보이는데, 이건 읽기만 하는 표시다. 글자에 흰 헤일로를
      // 둘러 도면·건물 어느 배경에서도 읽히게 한다.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            step.label,
            style: RoutexTypography.control(RoutexTypography.caption).copyWith(
              color: colors.contentPrimary,
              shadows: _haloShadows(colors.surfaceBase),
            ),
          ),
          const SizedBox(height: 2),
          // 막대는 **양 끝에 턱이 있는 자**다. 선만 그으면 어디까지가 그
          // 거리인지 눈이 못 끊는다.
          CustomPaint(
            size: Size(step.widthPx, _barHeightPx),
            painter: _ScaleRulePainter(
              color: colors.contentPrimary,
              haloColor: colors.surfaceBase,
            ),
          ),
        ],
      ),
    );
  }
}

/// 글자 뒤에 사방으로 까는 헤일로. 배경이 없으므로 이것이 대비의 전부다.
List<Shadow> _haloShadows(Color color) => [
  for (final offset in const [
    Offset(1, 0),
    Offset(-1, 0),
    Offset(0, 1),
    Offset(0, -1),
  ])
    Shadow(color: color, offset: offset, blurRadius: 2),
];

/// 자의 높이(논리 px). 턱 높이가 곧 이 값이다.
const double _barHeightPx = 6;

class _ScaleRulePainter extends CustomPainter {
  const _ScaleRulePainter({required this.color, required this.haloColor});

  final Color color;

  /// 자 뒤에 한 겹 더 굵게 까는 색. 배경이 없으므로 어두운 도면 위에서도
  /// 선이 살아 있으려면 글자와 같은 방법이 필요하다.
  final Color haloColor;

  @override
  void paint(Canvas canvas, Size size) {
    void rule(Paint paint) {
      final baseY = size.height - RoutexStroke.emphasis / 2;
      canvas.drawLine(Offset(0, baseY), Offset(size.width, baseY), paint);
      canvas.drawLine(const Offset(0, 0), Offset(0, baseY), paint);
      canvas.drawLine(Offset(size.width, 0), Offset(size.width, baseY), paint);
    }

    rule(
      Paint()
        ..color = haloColor
        ..strokeWidth = RoutexStroke.emphasis + 2
        ..strokeCap = StrokeCap.round,
    );
    rule(
      Paint()
        ..color = color
        ..strokeWidth = RoutexStroke.emphasis
        ..strokeCap = StrokeCap.square,
    );
  }

  @override
  bool shouldRepaint(_ScaleRulePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.haloColor != haloColor;
}
