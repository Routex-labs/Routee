/// 지금 층의 **편의시설을 종류로 골라 지도에 띄우고, 그중 하나를 도착지로
/// 삼는** 시트.
///
/// 종류 줄은 필터이고 아래 목록은 그 결과다. 고른 종류가 도면 위에 파랗게 칠해져
/// (`facility_highlight.dart`) 어디인지 보이고, 줄을 누르면 그리로 경로가 그려진다.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../../../../map/style/floor_facility_style.dart';
import '../../../../models/place/store_index_entry.dart';
import '../../../../widgets/map_pass_through_sheet_route.dart';

/// 시트가 고르게 하는 시설 종류. **소분류 원본값 그대로다** — 화면 문구와 필터
/// 값을 한 값으로 합치면 지도 타일과 대조할 값을 잃는다([CategorySelection]).
///
/// 실측(`/buildings/thehyundai-seoul/floors/1F`)에서 이 셋은 한글로 적재돼 있고,
/// `화장실`에는 장애인화장실까지 함께 묶여 있다.
const kFacilityFilters = <({String value, IconData icon})>[
  (value: '화장실', icon: Icons.wc_rounded),
  (value: '엘리베이터', icon: RoutexIcons.elevator),
  (value: '에스컬레이터', icon: RoutexIcons.escalator),
];

/// 시트가 차지하는 화면 높이 비율.
///
/// **줄 수와 무관하게 고정한다.** 목록 길이를 따라 높이가 변하면 이 시트만큼
/// 밀어 올린 층 선택기가 종류를 바꿀 때마다 위아래로 들썩인다 — 밀어 올리는 쪽이
/// 같은 값을 봐야 한다(`_MapShellScreenState`의 하단 리프트).
const double kFacilitySheetHeightFraction = 0.42;

/// 시트를 처음 열 때 골라 두는 종류.
///
/// 아무것도 안 고른 빈 목록으로 여는 것보다 낫다 — 시설 질의의 대부분이
/// 화장실이고, 나머지 둘은 한 번 더 누르면 된다.
const String kFacilityDefaultFilter = '화장실';

/// 시설 필터 시트를 띄운다. 줄을 고르면 그 시설로, 그냥 닫으면 null로 끝난다.
///
/// [floorLabel]을 값이 아니라 listenable로 받는다 — 시트가 떠 있는 동안에도 층
/// 선택기는 그대로 눌리므로, 값으로 받으면 제목과 목록이 옛 층에 머문다.
///
/// **barrier가 없다**([MapPassThroughSheetRoute]). 고른 시설을 지도에서 확인하는
/// 것이 이 시트의 목적이라, 지도가 그동안 잠기면 안 된다.
Future<StoreIndexEntry?> showFacilityFilterSheet(
  BuildContext context, {
  required ValueListenable<String?> floorLabel,
  required List<StoreIndexEntry> facilities,
  required String? selected,
  required ValueChanged<String?> onSelected,
}) {
  final navigator = Navigator.of(context);
  return navigator.push<StoreIndexEntry>(
    MapPassThroughSheetRoute<StoreIndexEntry>(
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      builder: (context) => SizedBox(
        height:
            MediaQuery.sizeOf(context).height * kFacilitySheetHeightFraction,
        child: RoutexBottomSheet(
          contentInset: RoutexBottomSheetContentInset.content,
          child: _FacilityFilterBody(
            floorLabel: floorLabel,
            facilities: facilities,
            selected: selected,
            onSelected: onSelected,
          ),
        ),
      ),
    ),
  );
}

class _FacilityFilterBody extends StatefulWidget {
  const _FacilityFilterBody({
    required this.floorLabel,
    required this.facilities,
    required this.selected,
    required this.onSelected,
  });

  final ValueListenable<String?> floorLabel;

  /// 건물 전체의 시설 색인. 층으로 거르는 일은 이 위젯이 한다 — 층은 시트가 떠
  /// 있는 동안에도 바뀐다.
  final List<StoreIndexEntry> facilities;

  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  State<_FacilityFilterBody> createState() => _FacilityFilterBodyState();
}

class _FacilityFilterBodyState extends State<_FacilityFilterBody> {
  late String? _selected = widget.selected ?? kFacilityDefaultFilter;

  @override
  void initState() {
    super.initState();
    // 기본 선택도 지도에 알린다. 안 알리면 시트에는 화장실이 켜져 있는데 도면에는
    // 아무것도 칠해지지 않는다. build 중에 상위 setState를 부를 수 없어 첫 프레임
    // 뒤로 미룬다.
    if (widget.selected == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onSelected(_selected);
      });
    }
  }

  void _pick(String value) {
    // 같은 것을 다시 누르면 해제한다. 해제 수단이 없으면 시트를 닫는 것 말고는
    // 강조를 되돌릴 방법이 없다(카테고리 칩과 같은 규칙).
    final next = _selected == value ? null : value;
    setState(() => _selected = next);
    widget.onSelected(next);
  }

  /// 지금 층의 고른 종류만. 이름 → id 순으로 고정한다 — 응답 순서에 기대면 같은
  /// 층을 다시 열었을 때 줄 순서가 바뀐다.
  List<StoreIndexEntry> _rows(String? floor) {
    final subcategory = _selected;
    if (subcategory == null) return const [];
    return widget.facilities
        .where(
          (entry) =>
              entry.subcategory == subcategory &&
              (floor == null || entry.floorName == floor),
        )
        .toList()
      ..sort((a, b) {
        final byName = a.name.compareTo(b.name);
        return byName != 0 ? byName : a.id.compareTo(b.id);
      });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.routexColors;
    return ValueListenableBuilder<String?>(
      valueListenable: widget.floorLabel,
      builder: (context, floor, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RoutexSheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RoutexSpacing.contentGap,
              0,
              RoutexSpacing.inlineGap,
              0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: RoutexSectionHeader(
                    // 층을 모르면 층 없이 적는다. `null층 편의시설`을 띄우느니
                    // 한 단어를 잃는 편이 낫다.
                    title: floor == null ? '편의시설' : '$floor 편의시설',
                  ),
                ),
                IconButton(
                  key: const Key('facility-filter-close'),
                  icon: const Icon(RoutexIcons.close),
                  color: colors.contentSecondary,
                  tooltip: '닫기',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RoutexSpacing.contentGap,
              RoutexSpacing.inlineGap,
              RoutexSpacing.contentGap,
              RoutexSpacing.inlineGap,
            ),
            child: Row(
              children: [
                for (final filter in kFacilityFilters)
                  Padding(
                    padding: const EdgeInsets.only(
                      right: RoutexSpacing.contentGap,
                    ),
                    child: _FacilityPick(
                      value: filter.value,
                      icon: filter.icon,
                      selected: _selected == filter.value,
                      onPressed: () => _pick(filter.value),
                    ),
                  ),
              ],
            ),
          ),
          const RoutexDivider(role: RoutexDividerRole.section),
          Expanded(child: _list(context, _rows(floor))),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, List<StoreIndexEntry> rows) {
    if (_selected == null) {
      return _note(context, '종류를 고르면 이 층의 시설을 보여드려요');
    }
    if (rows.isEmpty) {
      // 목록을 통째로 비우면 "이 층에 없음"과 "목록이 고장남"이 구분되지 않는다
      // (`category_stores_sheet.dart`와 같은 규칙).
      return _note(context, '이 층에는 없습니다.');
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: rows.length,
      separatorBuilder: (_, _) =>
          const RoutexDivider(role: RoutexDividerRole.row),
      itemBuilder: (context, index) {
        final entry = rows[index];
        return RoutexListCell(
          key: ValueKey('facility-row-${entry.id}'),
          title: entry.name,
          subtitle: entry.floorName,
          leadingIcon: _iconFor(entry.subcategory),
          // 이 줄은 **누르면 곧장 경로가 된다.** 다른 조작이 없으므로 끝 버튼(⋯)이
          // 아니라 그 동작의 글리프를 둔다([RoutexListCell.trailingActionIcon]의 규칙).
          trailingIcon: RoutexIcons.directions,
          onPressed: () => Navigator.of(context).pop(entry),
        );
      },
    );
  }

  Widget _note(BuildContext context, String message) => Padding(
    padding: const EdgeInsets.fromLTRB(
      RoutexSpacing.contentGap,
      RoutexSpacing.contentGap,
      RoutexSpacing.contentGap,
      0,
    ),
    child: Text(
      message,
      style: RoutexTypography.bodySmall.copyWith(
        color: context.routexColors.contentSecondary,
      ),
    ),
  );

  static IconData _iconFor(String? subcategory) {
    for (final filter in kFacilityFilters) {
      if (filter.value == subcategory) return filter.icon;
    }
    return RoutexIcons.place;
  }
}

/// 동그란 아이콘 + 그 아래 이름. 고른 것은 **색을 뒤집는다** — 채운 원 위에
/// 흰 글리프다(층 선택기의 고른 칸과 같은 규칙).
///
/// 테두리 두께나 색조만 바꾸는 표시는 옆 칸과 나란히 놓았을 때 어느 쪽이 켜진
/// 것인지 한눈에 안 갈린다. 채움은 멀리서도 갈린다.
///
/// **물결(ripple)을 쓰지 않는다.** 원 바깥의 사각 여백까지 잉크가 번져 동그란
/// 표면과 모양이 어긋나고, 채움으로 이미 결과가 보이므로 누른 순간의 표시가
/// 따로 필요하지 않다.
class _FacilityPick extends StatelessWidget {
  const _FacilityPick({
    required this.value,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String value;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.routexColors;
    return Semantics(
      button: true,
      selected: selected,
      label: value,
      excludeSemantics: true,
      child: GestureDetector(
        key: Key('facility-filter-$value'),
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: RoutexSpacing.inlineGap,
            vertical: RoutexSpacing.inlineGap,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: RoutexMetrics.minimumTouchTarget,
                height: RoutexMetrics.minimumTouchTarget,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // 채우는 색은 **지도가 이 시설을 그리는 색**이다. 시트에서만
                  // 쓰는 색을 새로 고르면 같은 시설이 두 화면에서 다른 색이 된다.
                  color: selected ? kPoiIconBackgroundColor : null,
                  border: Border.all(
                    color: selected
                        ? kPoiIconBackgroundColor
                        : colors.borderStrong,
                  ),
                ),
                child: Icon(
                  icon,
                  color: selected
                      ? colors.contentInverse
                      : colors.contentSecondary,
                  size: RoutexMetrics.iconMedium,
                ),
              ),
              const SizedBox(height: RoutexSpacing.inlineGap),
              Text(
                value,
                style: RoutexTypography.label.copyWith(
                  color: selected
                      ? kPoiIconBackgroundColor
                      : colors.contentSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
