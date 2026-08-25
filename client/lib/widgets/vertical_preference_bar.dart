import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../domain/route/vertical_preference.dart';

/// 층을 옮길 때 무엇을 타고 싶은지 고르는 한 줄.
///
/// 세그먼트 컨트롤을 쓴다 — 선택지가 세 개로 고정이고 서로 배타적이라, 개수가
/// 바뀌는 필터용 칩 줄([RoutexChipBar])이 아니라 이쪽이 맞다.
///
/// **아이콘 매핑이 여기 있는 이유**: [VerticalPreference]는 서버 질의 값과 이름만
/// 아는 도메인 타입이라 `IconData`를 들지 않는다. 그림은 그리는 쪽의 몫이다.
class VerticalPreferenceBar extends StatelessWidget {
  const VerticalPreferenceBar({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final VerticalPreference selected;
  final ValueChanged<VerticalPreference> onSelected;

  static IconData _iconFor(VerticalPreference preference) =>
      switch (preference) {
        // "알아서 고른다"를 그림 하나로 말할 수 없어 갈림길 기호를 쓴다 —
        // 엘리베이터·에스컬레이터 글리프와 섞이지 않는 유일한 축이다.
        VerticalPreference.auto => Icons.alt_route_rounded,
        VerticalPreference.escalator => Icons.escalator_rounded,
        VerticalPreference.elevator => Icons.elevator_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return RoutexTravelModeBar(
      options: [
        for (final preference in VerticalPreference.values)
          RoutexTravelModeOption(
            id: preference.wireValue,
            label: preference.label,
            icon: _iconFor(preference),
          ),
      ],
      selectedId: selected.wireValue,
      onSelected: (id) => onSelected(VerticalPreference.fromWireValue(id)),
    );
  }
}
