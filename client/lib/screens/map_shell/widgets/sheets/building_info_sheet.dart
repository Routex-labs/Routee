import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../../../../service_locator.dart';
import '../../../../models/building/building.dart';
import '../../../../models/place/store_index_entry.dart';
import '../../../../theme/app_theme.dart';
import '../../../../map/icon/category_icon.dart';
import '../../../../widgets/map_overlay_guard.dart';
import '../../../../widgets/map_pass_through_sheet_route.dart';
import '../../../../widgets/sheet_header.dart';

/// 야외 지도에서 건물 폴리곤을 눌렀을 때의 다음 행동.
enum BuildingInfoAction {
  setOrigin,
  setDestination,

  /// 실내 도면으로 들어간다. **매장을 고르지 않고도 들어갈 길**이 필요하다 —
  /// 예전에는 건물 탭이 곧 진입이었으므로, 이 줄이 없으면 그 조작이 사라진다.
  enterIndoor,
}

/// 시트가 열릴 때 화면 아래를 덮는 비율. 근거는 `place_detail_sheet.dart`의
/// `kPlaceDetailSheetInitialSize` 주석과 같다.
const double kBuildingInfoSheetInitialSize = 0.5;

/// 건물 한 채의 정보 시트 — 이름·층 수, 출발/도착, 실내 지도 보기, 매장 목록.
///
/// 매장 시트([PlaceDetailSheet])와 **버튼 규칙을 맞춘다**(출발/도착 둘뿐). 수단을
/// 고르는 조작은 길찾기에 들어간 뒤 상단 줄에서 한다.
class BuildingInfoSheet extends StatefulWidget {
  const BuildingInfoSheet({
    super.key,
    required this.building,
    required this.onCloseAll,
  });

  final Building building;
  final VoidCallback onCloseAll;

  /// 매장을 골랐으면 그 항목이, 조작을 골랐으면 [BuildingInfoAction]이 돌아온다.
  /// 그냥 닫으면 null이다.
  static Future<Object?> show(
    BuildContext context, {
    required Building building,
    required VoidCallback onCloseAll,
  }) {
    // 다른 시트와 **같은 라우트**를 쓴다. `showModalBottomSheet`의 barrier는
    // 투명하게 해도 포인터를 전부 흡수해, 시트가 떠 있는 동안 뒤 지도가 언다.
    final navigator = Navigator.of(context);
    return navigator.push<Object>(
      MapPassThroughSheetRoute<Object>(
        capturedThemes: InheritedTheme.capture(
          from: context,
          to: navigator.context,
        ),
        isScrollControlled: true,
        isDismissible: true,
        // 곡률은 시트 표면이 그린다([RoutexBottomSheet]). 라우트에도 적으면 같은
        // 값이 두 곳에서 정해진다.
        backgroundColor: Colors.transparent,
        builder: (context) => MapOverlayGuard(
          child: BuildingInfoSheet(building: building, onCloseAll: onCloseAll),
        ),
      ),
    );
  }

  @override
  State<BuildingInfoSheet> createState() => _BuildingInfoSheetState();
}

class _BuildingInfoSheetState extends State<BuildingInfoSheet> {
  late final Future<List<StoreIndexEntry>> _storesFuture = _load();

  /// back/X/항목 선택처럼 명시적 조작으로 pop될 때 true. 아래로 끌어내려
  /// 닫은 것과 구분해야 상위가 시트 chain을 통째로 닫을지 정할 수 있다.
  bool _intentionalPop = false;
  void _markIntentional() => _intentionalPop = true;

  /// 건물 전체 매장 목록. **층 도면을 다시 훑지 않는다** — 이 응답은
  /// 자동완성이 이미 쓰고 있어 리포지토리가 캐시해 둔 것을 그대로 받는다.
  Future<List<StoreIndexEntry>> _load() async {
    try {
      final index = await buildingRepository.getStoreIndex(widget.building.id);
      return index ?? const [];
    } on Object {
      // 목록만 포기한다. 이름·층 수·길찾기 버튼은 그대로 쓸 수 있어야 한다.
      return const [];
    }
  }

  void _pop(Object value) {
    _markIntentional();
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_intentionalPop) widget.onCloseAll();
      },
      child: DraggableScrollableSheet(
        initialChildSize: kBuildingInfoSheetInitialSize,
        minChildSize: 0.25,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => RoutexBottomSheet(
          // 표면은 Runtime Kit이, 드래그와 라우트는 앱이 갖는다. 여백은 조각마다
          // 달라서 본문이 소유한다.
          contentInset: RoutexBottomSheetContentInset.content,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const RoutexSheetHandle(),
              SheetHeader(
                onCloseAll: widget.onCloseAll,
                onIntentionalPop: _markIntentional,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: _Core(building: widget.building),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: _Actions(
                  onOrigin: () => _pop(BuildingInfoAction.setOrigin),
                  onDestination: () => _pop(BuildingInfoAction.setDestination),
                  onEnterIndoor: () => _pop(BuildingInfoAction.enterIndoor),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(child: _storeList(scrollController)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _storeList(ScrollController controller) {
    return FutureBuilder<List<StoreIndexEntry>>(
      future: _storesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SingleChildScrollView(
            child: RoutexSkeletonList(count: 4),
          );
        }
        final stores = snapshot.data ?? const <StoreIndexEntry>[];
        if (stores.isEmpty) {
          // 목록만 비운다. 위의 이름·길찾기 버튼은 그대로 쓸 수 있다.
          return const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Text(
              '이 건물의 매장 정보가 아직 없습니다.',
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          );
        }
        return ListView.separated(
          controller: controller,
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: stores.length + 1,
          separatorBuilder: (_, _) =>
              const RoutexDivider(role: RoutexDividerRole.row),
          itemBuilder: (context, index) {
            if (index == 0) {
              return const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: RoutexSpacing.contentGap,
                ),
                child: RoutexSectionHeader(
                  title: '매장',
                  level: RoutexSectionHeaderLevel.group,
                ),
              );
            }
            final store = stores[index - 1];
            return RoutexListCell(
              key: Key('building-info-store-${store.id}'),
              title: store.name,
              subtitle: store.floorName,
              leadingIcon: categoryIconFor(store.category ?? ''),
              trailingIcon: RoutexIcons.forward,
              onPressed: () => _pop(store),
            );
          },
        );
      },
    );
  }
}

class _Core extends StatelessWidget {
  const _Core({required this.building});

  final Building building;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        building.name,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: AppColors.text,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        '${building.floors.length}개 층',
        style: const TextStyle(fontSize: 13, color: AppColors.muted),
      ),
    ],
  );
}

/// 출발·도착과 "실내 지도 보기". 앞 둘은 매장 시트의 쌍과 자리·모양을 맞춘다.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.onOrigin,
    required this.onDestination,
    required this.onEnterIndoor,
  });

  final VoidCallback onOrigin;
  final VoidCallback onDestination;
  final VoidCallback onEnterIndoor;

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('building-info-actions'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      RoutexPlaceActions(onOrigin: onOrigin, onDestination: onDestination),
      const SizedBox(height: RoutexSpacing.controlGap),
      // 매장을 고르지 않고도 도면으로 들어갈 길. 건물 탭이 곧 진입이던 조작을
      // 여기서 이어받는다.
      RoutexButton(
        key: const ValueKey('building-info-enter-indoor'),
        label: '실내 지도 보기',
        variant: RoutexButtonVariant.secondary,
        onPressed: onEnterIndoor,
      ),
    ],
  );
}
