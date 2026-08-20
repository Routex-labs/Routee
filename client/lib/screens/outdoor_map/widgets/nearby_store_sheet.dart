/// 위치를 확정하기 위해 **내 주변 매장 하나를 고르는** 시트.
///
/// GPS는 "이쯤"까지만 말한다. 그 자리에서 가장 가까운 매장을 사람이 고르면
/// 그 매장의 노드가 곧 실제 위치가 된다 — 사람 눈이 GPS보다 정확한 유일한
/// 정보(지금 무엇 앞에 서 있는가)를 쓰는 셈이다.
library;

import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../../../map/icon/category_icon.dart';
import '../../../models/building/floor_plan.dart';
import '../../../widgets/map_pass_through_sheet_route.dart';

/// 목록 한 줄 — 매장과 거기까지의 거리.
typedef NearbyStoreRow = ({StorePolygon store, double distanceM});

/// 시트가 처음 차지하는 화면 비율.
///
/// **절반을 넘지 않는다.** 위쪽에 지도가 남아야 지금 찍힌 위치와 목록의 매장이
/// 같은 화면에서 보이고, 사용자가 "이게 맞나"를 눈으로 대조할 수 있다.
const double kNearbyStoreSheetInitialSize = 0.42;

/// 매장을 고르게 하고 고른 매장을 돌려준다. 끌어내려 닫으면 null.
///
/// **barrier가 없다**([MapPassThroughSheetRoute]). 시트를 놔둔 채 지도를 움직여
/// 주변을 확인할 수 있어야 한다 — 그러라고 띄우는 목록이다.
Future<StorePolygon?> showNearbyStoreSheet(
  BuildContext context, {
  required List<NearbyStoreRow> rows,
}) {
  return Navigator.of(context).push(
    MapPassThroughSheetRoute<StorePolygon>(
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: Navigator.of(context).context,
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: kNearbyStoreSheetInitialSize,
        minChildSize: 0.2,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => RoutexBottomSheet(
          contentInset: RoutexBottomSheetContentInset.content,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const RoutexSheetHandle(),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: RoutexSpacing.contentGap,
                ),
                child: const RoutexSectionHeader(title: '근처 매장에서 골라주세요'),
              ),
              // 무엇이 일어나는지 한 줄로만 말한다. 제목이 이미 할 일을
              // 가리키므로 여기는 결과만 적는다.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  RoutexSpacing.contentGap,
                  0,
                  RoutexSpacing.contentGap,
                  RoutexSpacing.controlGap,
                ),
                child: Text(
                  '고른 매장 앞을 지금 위치로 잡습니다',
                  style: RoutexTypography.bodySmall.copyWith(
                    color: context.routexColors.contentSecondary,
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  itemCount: rows.length,
                  separatorBuilder: (_, _) =>
                      const RoutexDivider(role: RoutexDividerRole.row),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final category = row.store.category;
                    return RoutexListCell(
                      key: ValueKey('nearby-store-${row.store.id}'),
                      title: row.store.name,
                      subtitle: row.store.subcategory,
                      // 거리는 **고르는 근거**라 제목 줄 끝에 붙인다. 부제로
                      // 내리면 업종과 섞여 어느 쪽이 거리인지 한 번 더 읽어야 한다.
                      metric: _distanceLabel(row.distanceM),
                      leadingIcon: category != null
                          ? categoryIconFor(category)
                          : RoutexIcons.place,
                      onPressed: () => Navigator.of(context).pop(row.store),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 실내 거리는 **1 m 단위로 끊는다.** 소수점을 남기면 GPS가 만든 어림값에
/// 없는 정밀도를 말하게 된다.
String _distanceLabel(double meters) => '${meters.round()}m';
