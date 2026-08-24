/// 상세 하단의 "근처 매장" 목록.
///
/// 비교하기 쉽도록 한 줄에 한 매장을 놓되, 본문이 불필요하게 길어지지 않도록
/// 처음에는 3개만 보여 준다. 후보가 더 있으면 사용자가 명시적으로 펼친다.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../../../../../domain/store/nearby_stores.dart';
import '../../../../../models/place/store_index_entry.dart';
import '../../../../../theme/app_theme.dart';
import '../../../../../map/icon/category_icon.dart';
import '../../../../../domain/store/reach_label.dart';
import '../../../../../domain/category/subcategory_label.dart';
import 'place_detail_rich_sections.dart';

const _collapsedStoreCount = 3;
const _expandDuration = Duration(milliseconds: 240);

class PlaceNearbySection extends StatefulWidget {
  const PlaceNearbySection({
    super.key,
    required this.stores,
    required this.onSelect,
  });

  final List<NearbyStore> stores;
  final void Function(StoreIndexEntry store)? onSelect;

  @override
  State<PlaceNearbySection> createState() => _PlaceNearbySectionState();
}

class _PlaceNearbySectionState extends State<PlaceNearbySection> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant PlaceNearbySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIds = oldWidget.stores.map((item) => item.store.id).toList();
    final newIds = widget.stores.map((item) => item.store.id).toList();
    if (!listEquals(oldIds, newIds)) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.stores.isEmpty) return const SizedBox.shrink();

    final visibleCount = _expanded
        ? widget.stores.length
        : math.min(_collapsedStoreCount, widget.stores.length);
    final hiddenCount = widget.stores.length - _collapsedStoreCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: placeSectionGutter),
          child: RoutexSectionHeader(title: '근처 매장'),
        ),
        const SizedBox(height: 8),
        AnimatedSize(
          duration: _expandDuration,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          clipBehavior: Clip.hardEdge,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: placeSectionGutter),
            child: Column(
              children: [
                for (var index = 0; index < visibleCount; index++) ...[
                  _NearbyRow(
                    nearby: widget.stores[index],
                    onTap: widget.onSelect == null
                        ? null
                        : () => widget.onSelect!(widget.stores[index].store),
                  ),
                  if (index < visibleCount - 1)
                    const RoutexDivider(role: RoutexDividerRole.row),
                ],
              ],
            ),
          ),
        ),
        // 접었을 때만 개수가 붙는다. 펼친 뒤의 "N개 접기"는 이미 화면에 보이는
        // 것을 다시 세는 말이라 확인할 이유가 없다.
        if (hiddenCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              placeSectionGutter,
              4,
              placeSectionGutter,
              0,
            ),
            child: RoutexShowMore(
              expanded: _expanded,
              hiddenCount: hiddenCount,
              onExpanded: (value) => setState(() => _expanded = value),
            ),
          ),
      ],
    );
  }
}

class _NearbyRow extends StatelessWidget {
  const _NearbyRow({required this.nearby, required this.onTap});

  final NearbyStore nearby;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final store = nearby.store;
    final category = subcategoryLabelFor(store.subcategory) ?? store.category;
    // 파랑 하나로 칠하던 자리다. 지도에서 그 매장 배지가 대분류 색인데 목록만
    // 파랑이면 같은 매장이 두 색으로 보인다 — 카테고리 시트 헤더와 같은 규칙
    // (색 12% 바탕 + 색 글리프)을 쓴다.
    final ink = categoryColorFor(store.category ?? '');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: ink.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  storeIconFor(
                    name: store.name,
                    subcategory: store.subcategory,
                    category: store.category,
                  ),
                  size: 20,
                  color: ink,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        store.floorName,
                        reachLabel(nearby.reach),
                        if (category != null && category.isNotEmpty) category,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.25,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppColors.blue300,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
