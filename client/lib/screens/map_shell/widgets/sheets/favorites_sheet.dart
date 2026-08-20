import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../../../../service_locator.dart';
import '../../../../models/place/favorite_place.dart';
import '../../../../widgets/sheet_header.dart';

import '../../../../widgets/map_overlay_guard.dart';

/// 사용자가 저장해둔 매장 목록을 보여주는 바텀시트.
///
/// 각 항목은 탭하면 [FavoritePlace]를 반환하며(호출자가 매장 정보 시트로
/// 넘겨준다), 오른쪽 점 세개 메뉴로 삭제할 수 있고, 드래그로 순서 조정도
/// 지원한다. 저장·삭제·순서 조정은 전부 [FavoritesController]에 위임한다.
///
/// 리스트 재빌드는 [ListenableBuilder]로 처리한다 — 수동으로 addListener
/// 후 setState를 부르면 ReorderableListView의 드롭 애니메이션 중간에
/// 재빌드가 끼어들어 `_elements.contains(element)` assertion이 터진다.
class FavoritesSheet extends StatefulWidget {
  const FavoritesSheet({super.key, required this.onCloseAll});

  /// X 버튼이 눌리면 호출. 부모(MapShellScreen)가 chain-close 플래그를 세팅
  /// 해 위쪽 시트들도 다시 열리지 않게 한다.
  final VoidCallback onCloseAll;

  static Future<FavoritePlace?> show(
    BuildContext context, {
    required VoidCallback onCloseAll,
  }) {
    return showModalBottomSheet<FavoritePlace>(
      context: context,
      isScrollControlled: true,
      // 표면은 시트 본문이 그린다([RoutexBottomSheet]). 라우트까지 배경을 칠하면
      // 같은 표면이 두 겹이 되고, 곡률·그림자가 두 곳에서 정해진다.
      backgroundColor: Colors.transparent,
      builder: (context) =>
          MapOverlayGuard(child: FavoritesSheet(onCloseAll: onCloseAll)),
    );
  }

  @override
  State<FavoritesSheet> createState() => _FavoritesSheetState();
}

class _FavoritesSheetState extends State<FavoritesSheet> {
  /// back/X/항목 선택으로 명시적 pop될 때 true. PopScope가 이 값이 false인
  /// pop(=barrier/drag)을 잡아 chain 전체를 닫는다.
  bool _intentionalPop = false;
  void _markIntentional() => _intentionalPop = true;

  @override
  Widget build(BuildContext context) {
    // 화면 높이의 최대 80%까지만 잡는다. DraggableScrollableSheet를 쓰지 않는
    // 이유는 그쪽의 scrollController를 ReorderableListView에 물릴 때 드래그
    // 리오더와 시트 스크롤이 같은 컨트롤러를 공유해 element 트리가 꼬이는
    // `_elements.contains(element)` assertion이 발생하기 때문이다.
    final maxHeight = MediaQuery.of(context).size.height * 0.8;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_intentionalPop) widget.onCloseAll();
      },
      // 표면이 SafeArea 바깥이다. 안에 두면 배경이 홈 인디케이터 위에서 끊겨
      // 시트 아래로 지도가 비친다.
      child: RoutexBottomSheet(
        contentInset: RoutexBottomSheetContentInset.content,
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 손잡이가 있던 자리다. **이 시트는 끌어서 크기를 바꿀 수 없고**
                // (위 주석의 reorder assertion), 손잡이는 그 조작이 있다는 약속이라
                // 여기 두면 할 수 없는 일을 약속하게 된다. 남긴 여백은 손잡이가
                // 차지하던 값과 같고, Runtime Kit이 손잡이 없는 시트에 쓰는 값이다.
                const SizedBox(height: RoutexSpacing.componentPadding),
                SheetHeader(
                  title: '저장한 장소',
                  onCloseAll: widget.onCloseAll,
                  onIntentionalPop: _markIntentional,
                ),
                Flexible(
                  child: ListenableBuilder(
                    listenable: favoritesController,
                    builder: (context, _) {
                      final places = favoritesController.places;
                      if (places.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(RoutexSpacing.sectionGap),
                          child: RoutexEmptyState(
                            title: '아직 저장한 장소가 없어요',
                            description: '매장 정보에서 저장하면 여기에 모아 볼 수 있어요.',
                            icon: RoutexIcons.save,
                          ),
                        );
                      }
                      return ReorderableListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: places.length,
                        // 오른쪽 기본 드래그 핸들(≡ 아이콘) 제거. 아이템 아무 데나
                        // 꾹 누르면 살짝 떠오르며 이동한다.
                        buildDefaultDragHandles: false,
                        // ignore: deprecated_member_use -- onReorderItem은 최신 SDK 전용.
                        onReorder: favoritesController.reorder,
                        itemBuilder: (context, index) {
                          final place = places[index];
                          return ReorderableDelayedDragStartListener(
                            key: ValueKey(place.key),
                            index: index,
                            child: _FavoriteTile(
                              place: place,
                              onTap: () {
                                _markIntentional();
                                Navigator.of(context).pop(place);
                              },
                              onDelete: () =>
                                  favoritesController.removeByKey(place.key),
                            ),
                          );
                        },
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
}

class _FavoriteTile extends StatelessWidget {
  const _FavoriteTile({
    required this.place,
    required this.onTap,
    required this.onDelete,
  });

  final FavoritePlace place;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return RoutexListCell(
      title: place.name,
      subtitle: place.floor,
      leadingIcon: RoutexIcons.place,
      reorderable: true,
      onPressed: onTap,
      trailingActionLabel: '삭제',
      trailingActionIcon: RoutexIcons.delete,
      onTrailingAction: onDelete,
    );
  }
}
