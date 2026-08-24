import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

/// 도착 값을 Runtime Kit의 도착 패턴에 연결한다.
class IndoorArrivalCard extends StatelessWidget {
  const IndoorArrivalCard({
    super.key,
    required this.destinationName,
    required this.onConfirm,
    this.destinationFloor,
    this.onShowDetail,
    this.onConfirmPointerDown,
  });

  final String destinationName;
  final String? destinationFloor;
  final VoidCallback onConfirm;

  /// 매장 상세를 연다. null이면 상세가 없는 목적지(출구·복도 등)라 버튼이 빠진다.
  final VoidCallback? onShowDetail;

  final ValueChanged<Offset>? onConfirmPointerDown;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) => onConfirmPointerDown?.call(event.position),
    child: RoutexArrivalCard(
      destination: destinationName,
      floor: destinationFloor,
      onClose: onConfirm,
      onShowDetail: onShowDetail,
    ),
  );
}
