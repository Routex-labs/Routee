import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

/// 도착 값을 Runtime Kit의 도착 패턴에 연결한다.
class IndoorArrivalCard extends StatelessWidget {
  const IndoorArrivalCard({
    super.key,
    required this.destinationName,
    required this.onConfirm,
    this.destinationFloor,
    this.onConfirmPointerDown,
  });

  final String destinationName;
  final String? destinationFloor;
  final VoidCallback onConfirm;
  final ValueChanged<Offset>? onConfirmPointerDown;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) => onConfirmPointerDown?.call(event.position),
    child: RoutexArrivalCard(
      destination: destinationName,
      floor: destinationFloor,
      onClose: onConfirm,
    ),
  );
}
