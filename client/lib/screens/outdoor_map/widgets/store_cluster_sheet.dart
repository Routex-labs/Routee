import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../../../models/building/floor_plan.dart';
import '../../../map/icon/category_icon.dart';

/// 한 자리를 세 곳 이상이 나눠 쓸 때 뜨는 **매장 고르기 시트**.
///
/// 그런 자리를 칸으로 나눠 라벨을 전부 박으면 도면이 줄무늬 표처럼 보인다
/// (실기기 확인 — B1 푸드트럭 8곳·공차 골목 4곳). 지도에는 「첫 매장 외 N」
/// 라벨 하나만 두고, 누르면 이 시트가 매장 목록을 펼친다. 항목을 고르면 그
/// [StorePolygon]으로 pop하고, 호출자가 상세 시트를 잇는다. 밖을 눌러 닫으면
/// null이다.
///
/// 상세·카테고리 시트와 달리 barrier를 그대로 둔다 — 이 시트는 "이 자리에서
/// 하나를 고르는" 짧은 분기라, 열린 채 지도를 만질 이유가 없다.
Future<StorePolygon?> showStoreClusterSheet(
  BuildContext context,
  List<StorePolygon> stores,
) {
  return showModalBottomSheet<StorePolygon>(
    context: context,
    // 표면은 시트 본문이 그린다([RoutexBottomSheet]).
    backgroundColor: Colors.transparent,
    builder: (context) => RoutexBottomSheet(
      contentInset: RoutexBottomSheetContentInset.content,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 손잡이가 있던 자리다. 이 시트는 내용 높이로 뜨고 끌어서 크기를 바꿀
            // 수 없어, 손잡이를 두면 할 수 없는 조작을 약속하게 된다.
            const SizedBox(height: RoutexSpacing.componentPadding),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: RoutexSpacing.contentGap,
              ),
              child: RoutexSectionHeader(title: '이 자리의 매장 ${stores.length}곳'),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: stores.length,
                separatorBuilder: (_, _) =>
                    const RoutexDivider(role: RoutexDividerRole.row),
                itemBuilder: (context, index) {
                  final store = stores[index];
                  final category = store.category;
                  return RoutexListCell(
                    title: store.name,
                    subtitle: store.subcategory,
                    leadingIcon: category != null
                        ? categoryIconFor(category)
                        : RoutexIcons.place,
                    onPressed: () => Navigator.of(context).pop(store),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
