import 'dart:async';

import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../../../../domain/event/building_events.dart';
import 'event_poster_view.dart';
import 'sheet_drag_dismiss.dart';
import 'today_events.dart';
import '../../../../models/place/store_index_entry.dart';
import '../../../../theme/app_theme.dart';
import '../../../../widgets/map_overlay_guard.dart';
import '../../../../widgets/map_pass_through_sheet_route.dart';
import '../../../../widgets/sheet_header.dart';

/// 처음 떠오르는 높이. 목록이 몇 줄인지와 무관하게 고정이다 — 줄 수를 따라
/// 높이가 변하면 같은 조작이 매번 다른 거리를 움직인다.
const double _initialSize = 0.55;

/// 오늘 이 건물에서 열리는 행사 목록. 한 줄을 누르면 그 매장의
/// [StoreIndexEntry]로 pop해서, 호출자가 **검색 후보를 고른 것과 같은 경로**로
/// 상세와 안내를 잇는다.
///
/// 원본과 수집 방법은 `docs/client/thehyundai-event-source.md`.
class EventsSheet extends StatefulWidget {
  const EventsSheet({
    super.key,
    required this.onCloseAll,
    this.diary,
    this.title,
  });

  final VoidCallback onCloseAll;

  /// 이 쪽에서 온 것만 보인다. null이면 오늘 열리는 것 전부다.
  final EventDiary? diary;

  /// 머리에 적을 이름. 없으면 오늘 전체를 뜻하는 이름을 쓴다.
  final String? title;

  static Future<StoreIndexEntry?> show(
    BuildContext context, {
    required VoidCallback onCloseAll,
    EventDiary? diary,
    String? title,
  }) {
    // 카테고리 목록 시트와 **같은 라우트**다 — 뒤 지도를 얼리지 않으려는 이유가
    // 같다([MapPassThroughSheetRoute]).
    final navigator = Navigator.of(context);
    return navigator.push<StoreIndexEntry>(
      MapPassThroughSheetRoute<StoreIndexEntry>(
        capturedThemes: InheritedTheme.capture(
          from: context,
          to: navigator.context,
        ),
        isScrollControlled: true,
        isDismissible: true,
        backgroundColor: Colors.transparent,
        builder: (context) => MapOverlayGuard(
          child: EventsSheet(
            onCloseAll: onCloseAll,
            diary: diary,
            title: title,
          ),
        ),
      ),
    );
  }

  @override
  State<EventsSheet> createState() => _EventsSheetState();
}

class _EventsSheetState extends State<EventsSheet> {
  // 목록·하단 줄·포스터가 **같은 순서의 같은 목록**을 쓴다([loadTodayEvents]).
  late final Future<List<TodayEvent>> _rowsFuture = loadTodayEvents(
    diary: widget.diary,
  );
  bool _intentionalPop = false;

  void _markIntentional() => _intentionalPop = true;

  /// 끌어내려 닫는다. 상세 시트와 같은 뜻이다 — 뒤로 가기로 닫은 것과 같이 본다.
  void _closeByDrag() {
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_intentionalPop) widget.onCloseAll();
      },
      child: DraggableScrollableSheet(
        initialChildSize: _initialSize,
        // 상세 시트와 **같은 감각**이다([SheetDragDismiss]) — 본문 어디를 잡고
        // 내려도 따라 내려오고, 처음 높이의 18%쯤에서 닫힌다. 예전에는 바닥이
        // 0.35라 거기서 멎어 버려, 닫으려고 끌면 손이 헛돌았다.
        minChildSize: _initialSize * kSheetMinRatio,
        maxChildSize: 0.9,
        // 놓으면 처음 높이나 끝까지 중 가까운 쪽으로 붙는다. 없으면 반쯤 내린
        // 어중간한 높이에 그대로 멎는다.
        snap: true,
        snapSizes: const [_initialSize],
        expand: false,
        builder: (context, scrollController) => GestureDetector(
          onTap: () {},
          behavior: HitTestBehavior.opaque,
          child: SheetDragDismiss(
            initialSize: _initialSize,
            onDismiss: _closeByDrag,
            child: RoutexBottomSheet(
              contentInset: RoutexBottomSheetContentInset.content,
              child: FutureBuilder<List<TodayEvent>>(
                future: _rowsFuture,
                builder: (context, snapshot) => CustomScrollView(
                  controller: scrollController,
                  slivers: [
                    const SliverToBoxAdapter(child: RoutexSheetHandle()),
                    SliverToBoxAdapter(
                      child: SheetHeader(
                        title: widget.title ?? '오늘의 이벤트',
                        onCloseAll: widget.onCloseAll,
                        onIntentionalPop: _markIntentional,
                      ),
                    ),
                    ..._body(snapshot),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body(AsyncSnapshot<List<TodayEvent>> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ];
    }
    final rows = snapshot.data ?? const <TodayEvent>[];
    if (rows.isEmpty || snapshot.hasError) {
      // 파일이 깨진 경우와 오늘 열리는 것이 없는 경우를 **가르지 않는다** —
      // 사용자가 할 일이 어느 쪽이든 같고(다음에 다시 보기), 굳이 가르면
      // "파일이 깨졌어요"라는, 사용자가 손쓸 수 없는 문구가 화면에 남는다.
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 40, horizontal: 16),
            child: Text(
              '오늘 열리는 이벤트가 없어요.',
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ),
        ),
      ];
    }
    return [
      SliverList.builder(
        itemCount: rows.length,
        itemBuilder: (context, i) => _tile(rows[i]),
      ),
    ];
  }

  /// 행사 한 줄. **[RoutexListCell]을 쓰지 않는다** — 그 셀은 leading이
  /// `IconData`뿐이라 사진이 못 들어가는데, 이 목록은 사진이 요점이다(어디를
  /// 갈지 정하는 데 글자보다 사진이 빠르다). 대신 색·간격은 셀과 맞춘다.
  Widget _tile(TodayEvent row) {
    final event = row.event;
    final navigable = row.entry != null;
    return InkWell(
      key: Key('event-${event.title}'),
      // **못 가는 줄도 눌린다.** 포스터는 좌표 없이도 볼 값이 있고, 안내
      // 버튼만 그 화면에서 잠긴다. 목록에서 막으면 사진을 아예 못 본다.
      onTap: () => unawaited(_openPoster(row)),
      child: Opacity(
        // 못 가는 줄은 흐리게 둔다. 감추지는 않는다 — 장소 문구는 읽을 값이 있다.
        opacity: navigable ? 1 : 0.55,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _thumbnail(event),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      // 갈래를 맨 앞에 둔다 — 목록이 갈래 순서로 서 있으므로,
                      // 여기서 갈래가 바뀌는 자리가 곧 묶음의 경계로 읽힌다.
                      // 이미 한 갈래로 좁혀 들어왔으면 적지 않는다 — 모든 줄에
                      // 같은 낱말이 반복되면 그 자리는 읽히지 않는 여백이 된다.
                      [
                        if (widget.diary == null &&
                            event.diary.label.isNotEmpty)
                          event.diary.label,
                        if (event.place.isNotEmpty) event.place,
                        _period(event),
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 대표 사진 64×64. 사진이 없거나 못 읽으면 **아이콘으로 떨어진다** — 에셋이
  /// 빠져도 목록 한 줄이 통째로 깨지지는 않아야 한다.
  /// 포스터를 연다. **좌우로 미는 대상은 목록 전체**라, 사용자가 목록으로
  /// 돌아가지 않고도 오늘 뭘 하는지 다 훑을 수 있다(공식 모바일 웹과 같다).
  ///
  /// 포스터에서 안내를 고르면 **그때 고른 행사**로 시트를 닫는다 — 밀어서 다른
  /// 행사를 보다가 눌렀는데 처음 줄로 안내되면 안 된다.
  Future<void> _openPoster(TodayEvent row) async {
    final rows = await _rowsFuture;
    if (!mounted) return;
    final start = rows.indexOf(row);
    final picked = await EventPosterView.show(
      context,
      events: [for (final r in rows) r.event],
      initialIndex: start < 0 ? 0 : start,
      navigable: [for (final r in rows) r.entry != null],
    );
    if (!mounted || picked == null) return;
    _markIntentional();
    Navigator.of(context).pop(rows[picked].entry);
  }

  Widget _thumbnail(BuildingEvent event) {
    const size = 64.0;
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.muted.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(
        Icons.local_activity_outlined,
        size: 22,
        color: AppColors.muted,
      ),
    );
    final path = event.image;
    if (path == null || path.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.asset(
        path,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }

  /// `08.26까지`. 시작일은 적지 않는다 — 이미 열려 있는 행사만 목록에 있으므로
  /// 사용자가 정할 것은 "언제까지 갈 수 있나" 하나다.
  String _period(BuildingEvent event) {
    final end = event.end.split('-');
    return end.length == 3 ? '${end[1]}.${end[2]}까지' : event.end;
  }
}
