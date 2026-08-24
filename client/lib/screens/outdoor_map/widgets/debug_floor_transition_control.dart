import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

/// 디버그 모드에서 층 전환을 직접 태우는 버튼 한 개.
///
/// 위젯으로 뺀 이유는 [RoutexMapControl]이 **그림을 하나만 받기 때문**이다
/// (icon·glyphBuilder·text 중 정확히 하나). 호출부에서 화살표와 층 라벨을 함께
/// 넘겼더니 그 assert가 터져 화면 절반이 빨간 오류 상자로 덮이고 탭이 통째로
/// 막혔다 — 디버그 모드에서만 나던 증상이라 분석기도 테스트도 못 잡았다.
///
/// 규칙을 여기 한 곳에 둔다: **탑승 노드를 알면 그 층 라벨, 모르면 방향 화살표.**
/// 라벨이 더 많은 것을 말하므로 알 때는 그쪽을 고른다. 방향은 어느 쪽이든
/// [Semantics] 라벨과 툴팁이 그대로 말한다.
class DebugFloorTransitionControl extends StatelessWidget {
  const DebugFloorTransitionControl({
    super.key,
    required this.up,
    required this.targetFloorLabel,
    required this.onPressed,
  });

  /// 위층으로 가는 버튼인지.
  final bool up;

  /// 태울 에스컬레이터가 닿는 층. 이 층 도면에 그 방향 탑승 노드가 없으면 null.
  final String? targetFloorLabel;

  /// null이면 회색으로 둔다. 탑승 노드가 없는 층에서 눌러도 할 일이 없다.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final label = targetFloorLabel;
    return RoutexMapControl(
      label: up ? '위층으로 층 전환' : '아래층으로 층 전환',
      // 방향 화살표는 디자인 시스템에 없다. 층 이동은 접기/펼치기가 아니라
      // 위아래 이동이라 그쪽 아이콘을 빌려 쓰지 않는다.
      icon: label != null
          ? null
          : (up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded),
      text: label,
      onPressed: onPressed,
    );
  }
}
