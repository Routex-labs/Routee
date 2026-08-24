import 'package:flutter/material.dart';

/// 끌어내려 닫히기 시작하는 지점. 처음 높이의 이만큼까지 내려오면 닫는다.
///
/// **이 값이 곧 민감도다.** 1에 가까울수록 살짝만 내려도 닫히고, 0에 가까울수록
/// 바닥까지 끌어야 닫힌다. 0.82는 손가락 한 마디쯤(처음 높이의 18%) 내리면 닫히는
/// 값이다 — 스크롤하려던 손이 잘못 닫아 버리지 않으면서, 닫으려고 잡았을 때 한
/// 번에 닫힌다.
const double kSheetDismissRatio = 0.82;

/// 끌어내릴 수 있는 바닥을 처음 높이에 대한 비율로. **닫기 문턱보다 낮아야
/// 한다** — 같거나 높으면 문턱에 닿기 전에 시트가 더 이상 안 내려가서, 본문을
/// 아무리 끌어도 아무 일이 없다.
const double kSheetMinRatio = 0.55;

/// [DraggableScrollableSheet] 본문을 감싸, 문턱 아래로 내려오면 [onDismiss]를
/// 부른다.
///
/// **본문 어디를 잡고 내리든 같은 알림으로 온다** — 손잡이만 특별 대접하지
/// 않는다. 문턱을 지나면 **손을 떼기 전에** 닫는다. 떼야 닫히면 사용자는
/// "안 닫히나" 하고 한 번 더 끈다.
///
/// 알림은 끄는 동안 여러 번 오므로 **한 번만 받는다** — 두 번 닫으면 그 뒤에
/// 있던 시트까지 함께 걷힌다.
class SheetDragDismiss extends StatefulWidget {
  const SheetDragDismiss({
    super.key,
    required this.initialSize,
    required this.onDismiss,
    required this.child,
  });

  /// 시트의 처음 높이(화면 비율). 문턱은 이 값에서 잰다.
  final double initialSize;

  final VoidCallback onDismiss;
  final Widget child;

  @override
  State<SheetDragDismiss> createState() => _SheetDragDismissState();
}

class _SheetDragDismissState extends State<SheetDragDismiss> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (notification) {
        if (_dismissed) return false;
        if (notification.extent > widget.initialSize * kSheetDismissRatio) {
          return false;
        }
        _dismissed = true;
        widget.onDismiss();
        return false;
      },
      child: widget.child,
    );
  }
}
