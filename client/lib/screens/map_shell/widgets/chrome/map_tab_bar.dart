import 'package:flutter/material.dart';

import '../../../../theme/app_theme.dart';

/// 화면 맨 아래에 **고정**된 탭 줄. 다른 것들이 뜨고 지고 끌려 올라가도 이 줄만은
/// 늘 같은 자리에 있다 — 여기가 바닥이라는 것을 알려 주는 것이 이 줄의 첫 일이다.
///
/// **탭이 화면을 갈아 끼우지는 않는다.** 이 앱은 지도 한 화면이고, 나머지는 그
/// 위에 뜨는 시트·모드다. 그래서 [MapTab.map]만 "돌아오는 자리"이고 나머지는 각자
/// 자기 것을 연다. 대신 지금 켜져 있는 것은 [selected]로 표시해, 누른 것이 어디에
/// 남아 있는지 보이게 한다.
///
/// **줄에 설 탭은 부르는 쪽이 정한다**([tabs]) — 어떤 탭은 지금 이 자리에서만
/// 뜻이 있다(이벤트는 건물 안에서만). 여기서 조건을 알면 화면이 늘 때마다 이
/// 위젯이 함께 불어난다.
enum MapTab {
  map('지도', Icons.map_outlined, Icons.map),
  directions('길찾기', Icons.alt_route_outlined, Icons.alt_route),
  events('이벤트', Icons.local_activity_outlined, Icons.local_activity),
  saved('저장', Icons.bookmark_border, Icons.bookmark);

  const MapTab(this.label, this.icon, this.activeIcon);

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

/// 탭 줄의 높이. **안전영역은 여기에 포함되지 않는다** — 위에 얹히는 것들이
/// 띄워야 할 거리를 재려면 두 값을 따로 더해야 한다.
const double kMapTabBarHeight = 56;

class MapTabBar extends StatelessWidget {
  const MapTabBar({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelected,
  });

  /// 이 줄에 세울 탭, 왼쪽부터의 순서 그대로.
  final List<MapTab> tabs;

  final MapTab selected;
  final ValueChanged<MapTab> onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      // 그림자가 아니라 실선으로 가른다. 위에 붙는 판도 흰 면이라, 그림자를 쓰면
      // 두 흰 면 사이에 그림자가 끼어 판이 떠 있는 것처럼 보인다.
      shape: const Border(top: BorderSide(color: AppColors.hairline)),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: kMapTabBarHeight,
          child: Row(
            children: [
              for (final tab in tabs)
                Expanded(
                  child: _TabItem(
                    key: Key('map-tab-${tab.name}'),
                    tab: tab,
                    selected: tab == selected,
                    onTap: () => onSelected(tab),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    super.key,
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final MapTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.muted;
    return InkWell(
      onTap: onTap,
      child: Semantics(
        selected: selected,
        button: true,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? tab.activeIcon : tab.icon, size: 22, color: color),
            const SizedBox(height: 2),
            Text(
              tab.label,
              style: TextStyle(
                fontSize: 11,
                height: 1.1,
                // 고른 것은 색과 굵기 **둘 다**로 가른다. 색만으로 가르면 색을
                // 구분하기 어려운 사람에게는 아무 표시도 없는 줄이 된다.
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
