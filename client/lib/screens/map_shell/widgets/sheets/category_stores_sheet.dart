import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../../../../service_locator.dart';
import '../../../../models/building/floor_plan.dart';
import '../../../../models/place/poi_search_result.dart';
import '../../../../theme/app_theme.dart';
import '../../../../map/icon/category_icon.dart';
import '../../../../domain/category/category_taxonomy.dart';
import '../../../../widgets/sheet_header.dart';

import '../../../../widgets/map_overlay_guard.dart';
import '../../../../widgets/map_pass_through_sheet_route.dart';
import '../../../../domain/category/subcategory_label.dart';

/// 매장 정보 시트에서 카테고리 chip을 누르면 뜨는, 같은 대분류에 속하는
/// 매장을 층별로 훑어볼 수 있는 목록 시트. 사용자가 항목을 탭하면 그 매장의
/// [PoiSearchResult]로 pop해서 호출자가 다시 매장 정보 시트를 띄우게 한다.
///
/// 목록은 **현재 층 묶음이 먼저**, 굵은 구분선 뒤에 다른 층 묶음이 온다.
/// 예전에는 "현재 층만 보기" 토글로 층을 걸렀는데, 켜면 다른 층이 통째로
/// 사라지고 끄면 현재 층이 목록 한가운데 파묻혀 어느 쪽이든 한 번에 답을
/// 못 줬다. 나눠서 둘 다 보여주면 토글을 만질 일이 없다.
///
/// 건물 전체 층을 순회하며 stores를 모아야 해서 첫 로드는 층 수만큼의 API
/// 호출이 필요하다 — HttpBuildingRepository가 이 응답을 이미 캐시하므로
/// 같은 건물 안에서는 두 번째부터 즉시 뜬다.
class CategoryStoresSheet extends StatefulWidget {
  const CategoryStoresSheet({
    super.key,
    required this.buildingId,
    required this.category,
    required this.onCloseAll,
    this.currentFloor,
    this.subcategory,
    this.onSubcategoryChanged,
    this.onFirstStoreChanged,
  });

  final String buildingId;
  final String category;

  /// 실내 모드에서 지도가 지금 보여주고 있는 층 라벨. 목록을 "현재 층 → 다른
  /// 층" 두 묶음으로 나누는 기준이다. null(야외 모드 등)이면 층 개념이 없으므로
  /// 나누지 않고 전 층 목록을 한 줄기로 보여준다.
  final String? currentFloor;

  /// X 버튼이 눌리면 호출. 부모(MapShellScreen)가 chain-close 플래그를 세팅해
  /// 위쪽 시트들(예: 매장 정보 시트, 저장한 장소)이 다시 열리지 않게 한다.
  final VoidCallback onCloseAll;

  /// 시트를 열 때 이미 걸려 있던 소분류. 지도 강조와 시트 pill이 같은 값을
  /// 가리켜야 해서 상위가 소유하고 여기로 내려 준다.
  final String? subcategory;

  /// 시트 안 소분류 pill을 눌렀을 때. 이 pill은 목록만 좁히는 게 아니라 **지도
  /// 강조도 함께** 바꾼다 — 예전에 지도 위에 있던 pill 줄이 하던 일 그대로다.
  /// 상위가 받아 [CategorySelection]을 갱신하지 않으면 목록과 지도가 어긋난다.
  final ValueChanged<String?>? onSubcategoryChanged;

  /// 지금 목록 맨 위에 있는(=현재 층의 첫) 매장. 상위가 지도 카메라를 그리로
  /// 옮긴다. 층을 옮기게 하지 않으려고 **현재 층 매장만** 올린다 — 현재 층에
  /// 하나도 없으면 null이고, 그때 카메라는 그대로 둔다.
  final ValueChanged<PoiSearchResult?>? onFirstStoreChanged;

  static Future<PoiSearchResult?> show(
    BuildContext context, {
    required String buildingId,
    required String category,
    required VoidCallback onCloseAll,
    String? currentFloor,
    String? subcategory,
    ValueChanged<String?>? onSubcategoryChanged,
    ValueChanged<PoiSearchResult?>? onFirstStoreChanged,
  }) {
    // 상세 시트와 **같은 라우트**를 쓴다([MapPassThroughSheetRoute]). 예전에는
    // `showModalBottomSheet`에 `barrierColor: Colors.transparent`만 줬는데, 그건
    // barrier를 투명하게만 할 뿐 없애지 못한다 — barrier는 opaque라 포인터를
    // 전부 흡수하므로, 목록이 떠 있는 동안 위쪽 지도가 통째로 얼었다. 뒤 지도를
    // 어둡게 덮지 않으려던 원래 의도(목록을 훑는 동안에도 카테고리 강조가 보여야
    // 어느 층 어디쯤인지 가늠할 수 있다)는 이 라우트가 제대로 이룬다.
    final navigator = Navigator.of(context);
    return navigator.push<PoiSearchResult>(
      MapPassThroughSheetRoute<PoiSearchResult>(
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
          child: CategoryStoresSheet(
            buildingId: buildingId,
            category: category,
            onCloseAll: onCloseAll,
            currentFloor: currentFloor,
            subcategory: subcategory,
            onSubcategoryChanged: onSubcategoryChanged,
            onFirstStoreChanged: onFirstStoreChanged,
          ),
        ),
      ),
    );
  }

  @override
  State<CategoryStoresSheet> createState() => _CategoryStoresSheetState();
}

/// 시트가 열릴 때 화면 아래를 덮는 비율. 지도 카메라가 "시트 위에 남는 띠"의
/// 한가운데를 잡을 때 이 값을 그대로 쓴다 — 근거는 `place_detail_sheet.dart`의
/// `kPlaceDetailSheetInitialSize` 주석과 같다.
const double kCategoryStoresSheetInitialSize = 0.55;

class _CategoryStoresSheetState extends State<CategoryStoresSheet> {
  late final Future<List<_CategoryStoreEntry>> _entriesFuture = _load();
  late String? _subcategory = widget.subcategory;

  /// 마지막으로 상위에 알린 첫 매장의 id. 같은 매장을 반복해서 올리면 소분류를
  /// 만질 때마다 카메라가 제자리에서 다시 움직인다.
  String? _notifiedFirstStoreId;
  bool _firstStoreNotified = false;

  /// back/X/항목 선택처럼 명시적 조작으로 pop될 때 true. PopScope가 pop을
  /// 받았을 때 이 값이 false면 아래로 끌어내려 dismiss된 것으로 보고 chain
  /// 전체를 닫는다(barrier는 [MapPassThroughSheetRoute]가 없앴다).
  bool _intentionalPop = false;
  void _markIntentional() => _intentionalPop = true;

  List<_CategoryStoreEntry> _applyFilters(List<_CategoryStoreEntry> all) {
    final subcategory = _subcategory;
    if (subcategory == null) return all;
    return all
        .where((entry) => entry.store.subcategory == subcategory)
        .toList();
  }

  Future<List<_CategoryStoreEntry>> _load() async {
    final building = await buildingRepository.getBuilding(widget.buildingId);
    if (building == null) return const [];
    // 제외 목록은 지도 필터 pill과 **같은 상수**를 쓴다. 예전에는 이 파일이
    // 같은 값을 따로 들고 있었는데, 한쪽만 고치면 같은 항목이 시트에서는 빠지고
    // pill에서는 나오는 상태가 된다(근거는 kHiddenSubcategoryValues 주석).
    const hiddenSubs = kHiddenSubcategoryValues;
    final entries = <_CategoryStoreEntry>[];
    for (final floor in building.floors) {
      final json = await buildingRepository.getFloorGeoJson(
        widget.buildingId,
        floor,
      );
      if (json == null) continue;
      final plan = FloorPlan.fromJson(json);
      for (final store in plan.stores) {
        if (store.category != widget.category) continue;
        if (hiddenSubs.contains(store.subcategory)) continue;
        entries.add(_CategoryStoreEntry(store: store, floor: floor));
      }
    }
    // 층수 낮은 순(지하 최하층 → 지상 최상층)으로 정렬. 백엔드가 floors를
    // 층 level 내림차순으로 내려주므로 여기서 오름차순으로 다시 뒤집는다.
    // 같은 층 안에서는 매장 이름 순으로 보조 정렬해 화면상 순서를 안정화.
    entries.sort((a, b) {
      final la = _floorLevel(a.floor);
      final lb = _floorLevel(b.floor);
      if (la != lb) return la.compareTo(lb);
      return a.store.name.compareTo(b.store.name);
    });
    return entries;
  }

  /// "B6", "1F" 같은 층 라벨을 정렬용 정수 level로 바꾼다. `B<n>=-n`, `<n>F=n`.
  /// 알 수 없는 형태의 라벨은 0으로 두어 지상·지하 사이에 놓는다.
  static int _floorLevel(String label) {
    final upper = label.toUpperCase();
    final basement = RegExp(r'^B(\d+)$').firstMatch(upper);
    if (basement != null) return -int.parse(basement.group(1)!);
    final above = RegExp(r'^(\d+)F$').firstMatch(upper);
    if (above != null) return int.parse(above.group(1)!);
    return 0;
  }

  /// 목록 맨 위 매장을 상위에 알린다.
  ///
  /// build 중에 콜백을 부르면 상위가 그 자리에서 setState를 돌게 되므로 프레임
  /// 뒤로 미룬다. 층이 다른 매장은 올리지 않는다 — 카메라를 옮기려면 지도가
  /// 층을 갈아타야 하는데, 그러면 시트 머리글("현재 층 · 1F")이 가리키는 층과
  /// 지도가 보여주는 층이 어긋난다.
  void _notifyFirstStore(List<_CategoryStoreEntry> entries) {
    final callback = widget.onFirstStoreChanged;
    if (callback == null) return;
    final current = widget.currentFloor;
    _CategoryStoreEntry? first;
    for (final entry in entries) {
      if (current == null || entry.floor == current) {
        first = entry;
        break;
      }
    }
    if (_firstStoreNotified && _notifiedFirstStoreId == first?.store.id) return;
    _firstStoreNotified = true;
    _notifiedFirstStoreId = first?.store.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      callback(first?.toPoiSearchResult());
    });
  }

  @override
  Widget build(BuildContext context) {
    // 아래로 끌어내려 닫히면 PopScope가 잡아 chain 전체를 닫는다(back 버튼과
    // 구분됨). 내부 콘텐츠는 inner GestureDetector가 dismiss 전파를 막는다.
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_intentionalPop) widget.onCloseAll();
      },
      // **여기에 전체 화면 `GestureDetector(opaque)`를 두면 안 된다.** 이 시트는
      // `isScrollControlled: true`라 라우트의 child가 화면 전체 높이를 차지해,
      // 시트가 아래쪽만 그려져도 위쪽 투명 영역까지 히트 테스트에 걸린다 —
      // 지도가 보이는 자리의 탭·드래그가 전부 빨려 들어갔다. 상세 시트가 같은
      // 이유로 걷어낸 두 번째 겹이다([MapPassThroughSheetRoute] 주석).
      //
      // 이 래퍼가 하던 "바깥을 눌러 닫기"는 함께 사라진다. 그 자리는 지도가
      // 가져가고, 닫기는 X·뒤로 가기·아래로 끌어내리기가 맡는다.
      child: DraggableScrollableSheet(
        initialChildSize: kCategoryStoresSheetInitialSize,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return GestureDetector(
            onTap: () {},
            behavior: HitTestBehavior.opaque,
            child: RoutexBottomSheet(
              // 표면은 Runtime Kit이, 드래그와 라우트는 앱이 갖는다. 여백은 조각마다
              // 달라서 본문이 소유한다.
              contentInset: RoutexBottomSheetContentInset.content,
              child: FutureBuilder<List<_CategoryStoreEntry>>(
                future: _entriesFuture,
                builder: (context, snapshot) {
                  return CustomScrollView(
                    controller: scrollController,
                    slivers: [
                      const SliverToBoxAdapter(child: RoutexSheetHandle()),
                      SliverToBoxAdapter(
                        child: SheetHeader(
                          title: widget.category,
                          leading: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: categoryColorFor(
                                widget.category,
                              ).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              categoryIconFor(widget.category),
                              size: 16,
                              color: categoryColorFor(widget.category),
                            ),
                          ),
                          onCloseAll: widget.onCloseAll,
                          onIntentionalPop: _markIntentional,
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: _buildFilterBar(
                          snapshot.data ?? const <_CategoryStoreEntry>[],
                        ),
                      ),
                      ..._buildBody(snapshot),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildBody(AsyncSnapshot<List<_CategoryStoreEntry>> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: RoutexResultList(
              status: RoutexResultStatus.loading,
              loadingMessage: '매장 목록을 불러오는 중',
              children: [],
            ),
          ),
        ),
      ];
    }
    if (snapshot.hasError) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Text('매장 목록을 불러오지 못했습니다. 서버 연결을 확인해주세요.'),
          ),
        ),
      ];
    }
    final all = snapshot.data ?? const <_CategoryStoreEntry>[];
    if (all.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Text('이 카테고리에 해당하는 매장이 없습니다.'),
          ),
        ),
      ];
    }
    final entries = _applyFilters(all);
    _notifyFirstStore(entries);
    if (entries.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Text('조건에 맞는 매장이 없습니다.'),
          ),
        ),
      ];
    }

    final current = widget.currentFloor;
    // 층 개념이 없거나(야외) 결과가 한 층에만 몰려 있으면 나눌 것이 없다.
    // 묶음이 하나뿐인데 머리글을 붙이면 읽을 정보 없이 줄만 늘어난다.
    final onCurrent = current == null
        ? const <_CategoryStoreEntry>[]
        : entries.where((e) => e.floor == current).toList();
    final others = current == null
        ? entries
        : entries.where((e) => e.floor != current).toList();
    if (current == null || others.isEmpty) {
      return [
        ..._storeSlivers(entries),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
      ];
    }

    return [
      _sectionHeader('현재 층 · $current', count: onCurrent.length),
      // 현재 층에 없을 때도 머리글은 남기고 그 사실을 적는다. 묶음을 통째로
      // 빼 버리면 "이 층에 없다"와 "필터가 고장났다"가 화면에서 같아 보인다.
      if (onCurrent.isEmpty)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 2, 20, 12),
            child: Text(
              '이 층에는 없습니다.',
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ),
        )
      else
        ..._storeSlivers(onCurrent),
      const SliverToBoxAdapter(
        child: RoutexDivider(role: RoutexDividerRole.section),
      ),
      _sectionHeader('다른 층', count: others.length),
      ..._storeSlivers(others),
      const SliverToBoxAdapter(child: SizedBox(height: 12)),
    ];
  }

  /// 묶음 하나를 그리는 목록 sliver. 탭 처리(=pop으로 결과 반환)가 묶음마다
  /// 같아야 해서 한 곳에서 만든다.
  List<Widget> _storeSlivers(List<_CategoryStoreEntry> entries) {
    return [
      SliverList.separated(
        itemCount: entries.length,
        separatorBuilder: (_, _) =>
            const RoutexDivider(role: RoutexDividerRole.row),
        itemBuilder: (context, index) => _StoreTile(
          entry: entries[index],
          onTap: () {
            _markIntentional();
            Navigator.of(context).pop(entries[index].toPoiSearchResult());
          },
        ),
      ),
    ];
  }

  Widget _sectionHeader(String label, {required int count}) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
        child: Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$count곳',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar(List<_CategoryStoreEntry> all) {
    // pill 목록은 **불러온 매장에서** 뽑는다. 지도 위 pill 줄이 쓰던
    // `/category-counts` 응답과 같은 규칙(`subcategoryOptionsFor`)이라 같은
    // 항목이 나오고, 데이터에 없는 소분류가 pill로 뜨는 일도 없다.
    final options = subcategoryOptionsFor(
      widget.category,
      all.map((entry) => (entry.store.category, entry.store.subcategory)),
    );
    // 고를 것이 하나뿐인 줄은 탭만 한 번 더 요구한다(지도 pill 줄과 같은 규칙).
    // 걸 것이 없으면 줄 자체를 지운다 — 예전에는 이 자리에 검색창이 늘 있어
    // 빈 줄이 생기지 않았지만, 지금은 pill이 없으면 남길 것이 없다.
    if (!hasMeaningfulSubcategories(options)) return const SizedBox.shrink();
    // `전체`는 "좁히지 않음"을 뜻하는 칩이다. 칩 줄은 선택이 없는 상태를 null로
    // 말하는데, 이 화면에서 그것은 곧 전체다 — 어댑터가 둘을 이어 주므로 화면에는
    // 늘 하나가 강조돼 있다. 그래서 고른 소분류를 다시 눌러 전체로 돌아오는 길도
    // 그대로 남는다.
    const allId = '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: RoutexChipBar(
        options: [
          const RoutexChipOption(id: allId, label: '전체'),
          for (final option in options)
            RoutexChipOption(id: option.value, label: option.label),
        ],
        selectedId: _subcategory ?? allId,
        onSelected: (value) =>
            _selectSubcategory(value == null || value == allId ? null : value),
        semanticsLabel: '소분류',
      ),
    );
  }

  /// 소분류를 바꾼다. 목록만 좁히는 게 아니라 지도 강조도 같이 바뀌어야 해서
  /// 상위에 올린다 — 한쪽만 바뀌면 시트엔 세 곳, 지도엔 스무 곳이 칠해진다.
  void _selectSubcategory(String? value) {
    if (_subcategory == value) return;
    setState(() => _subcategory = value);
    widget.onSubcategoryChanged?.call(value);
  }
}

class _StoreTile extends StatelessWidget {
  const _StoreTile({required this.entry, required this.onTap});

  final _CategoryStoreEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final store = entry.store;
    final subcategory = subcategoryLabelFor(store.subcategory);
    final subtitle = subcategory != null && subcategory != store.category
        ? '${entry.floor} · $subcategory'
        : entry.floor;
    return RoutexListCell(
      title: store.name,
      subtitle: subtitle,
      leadingIcon: storeIconFor(
        name: store.name,
        subcategory: store.subcategory,
        category: store.category,
      ),
      trailingIcon: RoutexIcons.forward,
      onPressed: onTap,
    );
  }
}

class _CategoryStoreEntry {
  const _CategoryStoreEntry({required this.store, required this.floor});

  final StorePolygon store;
  final String floor;

  PoiSearchResult toPoiSearchResult() => PoiSearchResult(
    name: store.name,
    floor: floor,
    point: store.centroid,
    placeId: store.id,
    nodeId: store.entranceNodeId,
    category: store.category,
    subcategory: store.subcategory,
  );
}
