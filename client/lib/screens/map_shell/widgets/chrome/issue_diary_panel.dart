import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../../../../domain/event/building_events.dart';
import '../../../../theme/app_theme.dart';
import 'map_overlay_scroll_row.dart';

/// 화면 아래에 붙어 있는 이슈 다이어리 판. **건물 안에서만** 뜬다.
///
/// 접힌 채로는 쪽 카드 한 줄만 보이고, 손잡이를 끌어올리면 오늘 열리는 것 전부가
/// 목록으로 펼쳐진다. 지도 위에 떠 있는 조각이 아니라 **바닥에 붙은 면**이다 —
/// 카드가 도면 위에 그냥 얹혀 있으면 지도의 일부인지 UI인지가 매번 헷갈린다.
///
/// 카드 한 장은 행사 하나가 아니라 **원본의 쪽 하나**다(`WEEKLY POP-UP` 등).
/// 원본과 같은 층 구조라 쪽을 누르면 그 안의 행사가 쭉 나온다.
class IssueDiaryPanel extends StatefulWidget {
  const IssueDiaryPanel({
    super.key,
    required this.pages,
    required this.events,
    required this.onPickPage,
    required this.onPickEvent,
    required this.onDismissed,
    required this.onPointerOverChanged,
    required this.onPointerDownChanged,
  });

  /// 오늘 열리는 행사를 가진 쪽과 그 건수([BuildingEvents.diariesOpenOn]).
  final List<({EventDiaryPage page, int count})> pages;

  /// 펼쳤을 때 보여 줄 오늘 전체, 갈래 순서로([BuildingEvents.openOnByDiary]).
  final List<BuildingEvent> events;

  final ValueChanged<EventDiaryPage> onPickPage;

  /// 목록 줄을 눌렀을 때. 인자는 [events] 안의 자리다 — 포스터가 좌우로 밀리려면
  /// 고른 것 하나가 아니라 목록 전체와 그 안의 위치가 필요하다.
  final ValueChanged<int> onPickEvent;

  /// 접힌 높이 아래로 더 끌어내렸을 때. **판이 화면에서 아주 사라진다** —
  /// 지도를 넓게 보고 싶을 때 치우는 길이고, 돌아오는 길은 아래 탭 줄이다.
  final VoidCallback onDismissed;

  final ValueChanged<bool> onPointerOverChanged;
  final ValueChanged<bool> onPointerDownChanged;

  /// 카드 한 장의 한 변. 원본과 같은 정사각이다(대표 사진이 전부 750×750이라
  /// 다른 비율로 자르면 그림 안의 제목이 잘린다).
  static const cardSize = 128.0;

  /// 접힌 높이. 손잡이 + 이름 + 카드 한 줄이 딱 들어가는 값이다.
  static const peekHeight = 214.0;

  /// 이 높이 아래로 내려오면 치운다. 접힘의 절반쯤이라, 살짝 내렸다 놓는 것과
  /// 치우려고 끄는 것이 손끝에서 갈린다.
  static const dismissHeight = peekHeight * 0.55;

  /// 펼친 높이가 차지하는 화면 비율. **지도를 3분의 1은 남긴다** — 목록을 보는
  /// 중에도 "지금 어디쯤"이 보여야 판을 내릴지 말지를 정할 수 있다.
  static const expandedFraction = 0.66;

  @override
  State<IssueDiaryPanel> createState() => _IssueDiaryPanelState();
}

class _IssueDiaryPanelState extends State<IssueDiaryPanel> {
  /// 지금 보이는 높이. 0이면 화면 밖이다.
  ///
  /// **하나의 값이 두 가지를 한다.** 접힘 위로는 판이 실제로 커지고, 접힘 아래로는
  /// 판이 그대로인 채 아래로 미끄러진다(내용은 접힘 높이로 고정해 두고 넘치는
  /// 부분을 잘라낸다 — [build]). 값 하나라 손가락과 판이 어긋날 데가 없다.
  double? _height;

  bool _dragging = false;

  /// 끝까지 미끄러져 나가는 중. 다 나가면 [IssueDiaryPanel.onDismissed]를 부른다.
  bool _leaving = false;

  double _expandedHeight(BuildContext context) =>
      MediaQuery.sizeOf(context).height * IssueDiaryPanel.expandedFraction;

  double _current(BuildContext context) =>
      _height ?? IssueDiaryPanel.peekHeight;

  /// 손가락이 [dy]만큼 움직였다(아래가 양수). **판은 끝까지 따라간다** — 중간에
  /// 툭 사라지면 사용자는 자기가 무엇을 눌러 없앤 줄 안다.
  void _drag(double dy, BuildContext context) {
    if (_leaving) return;
    final next = (_current(context) - dy).clamp(0.0, _expandedHeight(context));
    setState(() {
      _dragging = true;
      _height = next;
    });
  }

  /// 손을 뗐다. 놓은 자리보다 **던진 방향**을 먼저 본다 — 조금만 끌어도 방향이
  /// 분명하면 그쪽으로 붙어야, 끝까지 끌지 않고도 펼치거나 치울 수 있다.
  void _settle(double velocity, BuildContext context) {
    if (_leaving) return;
    final max = _expandedHeight(context);
    final height = _current(context);
    final flungDown = velocity > 400;
    final flungUp = velocity < -400;

    setState(() {
      _dragging = false;
      if (!flungUp &&
          (flungDown && height < IssueDiaryPanel.peekHeight ||
              height <= IssueDiaryPanel.dismissHeight)) {
        // 나머지 길은 판이 알아서 미끄러진다. 다 나간 뒤에 치운다.
        _leaving = true;
        _height = 0;
        return;
      }
      final middle = (IssueDiaryPanel.peekHeight + max) / 2;
      final expand = velocity.abs() > 200 ? flungUp : height > middle;
      _height = expand ? max : IssueDiaryPanel.peekHeight;
    });
  }

  /// 펼친 목록을 **맨 위에서 더 내렸을 때**. 스크롤이 소화하지 못한 만큼을
  /// 그대로 판에 넘긴다 — 목록 맨 위에서 아래로 끄는 손짓은 "목록을 더 보자"가
  /// 아니라 "판을 내리자"다.
  bool _onListScroll(ScrollNotification notification, BuildContext context) {
    if (notification is OverscrollNotification &&
        notification.overscroll < 0 &&
        notification.dragDetails != null) {
      _drag(-notification.overscroll, context);
      return true;
    }
    if (notification is ScrollEndNotification && _dragging) {
      _settle(0, context);
    }
    return false;
  }

  /// 다시 열릴 때는 **접힌 자리에서 시작한다**. 치우기 직전 높이를 기억해 두면
  /// 반쯤 내려간 채로 되살아나 고장처럼 보인다.
  @override
  void didUpdateWidget(covariant IssueDiaryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pages.isEmpty && widget.pages.isNotEmpty) {
      _height = null;
      _leaving = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pages.isEmpty) return const SizedBox.shrink();
    final max = _expandedHeight(context);
    final height = _current(context).clamp(0.0, max);
    final expanded = height > IssueDiaryPanel.peekHeight + 1;
    // 접힘 아래에서는 **내용을 줄이지 않는다.** 줄이면 글자가 눌리며 사라지는데,
    // 실제로 일어나는 일은 판이 아래로 빠지는 것이다. 내용은 접힘 높이 그대로
    // 두고 상자만 줄여, 넘치는 아래쪽이 탭 줄 뒤로 잘려 나가게 한다.
    final contentHeight = math.max(height, IssueDiaryPanel.peekHeight);

    return AnimatedContainer(
      // 끄는 동안에는 손가락과 판이 어긋나면 안 되므로 애니메이션이 없다.
      duration: _dragging ? Duration.zero : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      height: height,
      onEnd: () {
        if (_leaving) widget.onDismissed();
      },
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: contentHeight,
          maxHeight: contentHeight,
          child: RoutexBottomSheet(
            expand: true,
            // 아래 안전영역은 이 판이 아니라 그 밑에 고정된 탭 줄이 먹는다.
            includeBottomSafeArea: false,
            contentInset: RoutexBottomSheetContentInset.content,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 손잡이와 이름줄이 끄는 자리다. 카드 줄은 가로로 밀리므로 여기서
                // 세로 제스처를 받으면 두 방향이 서로를 뺏는다.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (d) => _drag(d.delta.dy, context),
                  onVerticalDragEnd: (d) =>
                      _settle(d.velocity.pixelsPerSecond.dy, context),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [RoutexSheetHandle(), _PanelTitle()],
                  ),
                ),
                const SizedBox(height: RoutexSpacing.controlGap),
                _cards(),
                if (expanded) ...[
                  const SizedBox(height: RoutexSpacing.controlGap),
                  const RoutexDivider(),
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (n) => _onListScroll(n, context),
                      child: _list(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cards() {
    return SizedBox(
      height: IssueDiaryPanel.cardSize,
      child: MapOverlayScrollRow(
        onPointerOverChanged: widget.onPointerOverChanged,
        onPointerDownChanged: widget.onPointerDownChanged,
        children: [
          for (var i = 0; i < widget.pages.length; i++) ...[
            if (i > 0) const SizedBox(width: RoutexSpacing.controlGap),
            _DiaryCard(
              key: Key('issue-diary-${widget.pages[i].page.diary.name}'),
              page: widget.pages[i].page,
              count: widget.pages[i].count,
              size: IssueDiaryPanel.cardSize,
              onTap: () => widget.onPickPage(widget.pages[i].page),
            ),
          ],
        ],
      ),
    );
  }

  /// 펼쳤을 때의 오늘 전체. **갈래로 나눠 머리를 단다** — 카드가 세 장뿐이라
  /// 목록도 같은 세 묶음으로 보여야 위아래가 같은 것을 말하는 것으로 읽힌다.
  Widget _list() {
    EventDiary? shown;
    final rows = <Widget>[];
    for (var i = 0; i < widget.events.length; i++) {
      final event = widget.events[i];
      if (event.diary != shown) {
        shown = event.diary;
        rows.add(_GroupHeader(diary: event.diary));
      }
      rows.add(
        _EventRow(
          key: Key('issue-diary-row-${event.title}'),
          event: event,
          onTap: () => widget.onPickEvent(i),
        ),
      );
    }
    return ListView(
      // **튕기지 않는다.** 튕기는 물리(iOS 기본)는 맨 위에서 당긴 만큼을 스스로
      // 늘어나며 삼켜, 판에 넘길 초과분이 오지 않는다.
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 8),
      children: rows,
    );
  }
}

/// 판의 이름. **원본이 이 자리에 쓰는 것과 같은 글자·같은 폰트다** — 사용자가
/// 웹에서 보던 것과 같은 묶음임을 이름이 잇는다.
class _PanelTitle extends StatelessWidget {
  const _PanelTitle();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: RoutexSpacing.screenGutter),
    child: Text(
      'Issue Diary',
      style: TextStyle(
        fontFamily: 'PlayfairDisplay',
        // 가변 폰트라 굵기를 축으로 고른다. [fontWeight]도 함께 적어야 축을 못
        // 읽는 환경에서 굵게라도 떨어진다.
        fontVariations: [FontVariation('wght', 700)],
        fontWeight: FontWeight.w700,
        fontSize: 20,
        height: 1.1,
        // 원본의 `tracking-tight`. 세리프 제목은 자간이 벌어지면 헐거워 보인다.
        letterSpacing: -0.4,
        color: AppColors.text,
      ),
    ),
  );
}

/// 쪽 카드 한 장.
///
/// 평소에는 **사진만** 보인다 — 원본 대표 사진에 쪽 이름이 이미 그려져 있어서,
/// 그 위에 같은 이름을 또 얹으면 글자가 두 벌 겹친다. 손가락이 닿거나 마우스가
/// 올라오면 그때 막이 내려오고 갈래·이름·건수가 올라온다(원본 웹의 hover와 같은
/// 동작이고, 터치에서는 누르는 동안 같은 것을 보여 준다).
class _DiaryCard extends StatefulWidget {
  const _DiaryCard({
    super.key,
    required this.page,
    required this.count,
    required this.size,
    required this.onTap,
  });

  final EventDiaryPage page;

  /// 오늘 이 쪽에서 열리는 행사 수.
  final int count;

  final double size;
  final VoidCallback onTap;

  @override
  State<_DiaryCard> createState() => _DiaryCardState();
}

class _DiaryCardState extends State<_DiaryCard> {
  bool _hovered = false;
  bool _pressed = false;

  bool get _lit => _hovered || _pressed;

  @override
  Widget build(BuildContext context) {
    final image = widget.page.image;
    return MouseRegion(
      // 마우스가 있는 환경(웹·데스크톱)에서만 뜻이 있다. 터치에서는 onEnter가
      // 오지 않으므로 [_pressed]가 같은 자리를 맡는다.
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Material(
          color: AppColors.muted.withValues(alpha: 0.18),
          borderRadius: RoutexRadii.card,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: (down) => setState(() => _pressed = down),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (image != null && image.isNotEmpty)
                  Image.asset(
                    image,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                _scrim(),
                _caption(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 막. 사진이 없을 때도 같은 막을 깔아 두 경우의 글자 색이 갈리지 않게 한다.
  Widget _scrim() => AnimatedContainer(
    duration: const Duration(milliseconds: 160),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: _lit
            ? const [Color(0xE0000000), Color(0x99000000)]
            : const [Color(0x66000000), Color(0x00000000)],
        stops: const [0, 1],
      ),
    ),
  );

  /// 갈래(작게) → 이름(굵게). 원본 웹의 hover 자막과 같은 위계다.
  Widget _caption() => AnimatedOpacity(
    duration: const Duration(milliseconds: 160),
    opacity: _lit ? 1 : 0,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 26),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            // 건수를 갈래 옆에 붙인다 — 이 카드를 눌러 무엇이 몇 개 나오는지가
            // 누르기 전에 알아야 할 전부다.
            [
              if (widget.page.diary.label.isNotEmpty) widget.page.diary.label,
              '${widget.count}건',
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            widget.page.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              height: 1.2,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    ),
  );
}

/// 펼친 목록의 갈래 머리.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.diary});

  final EventDiary diary;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(RoutexSpacing.screenGutter, 14, 16, 6),
    child: Text(
      diary.label.isEmpty ? '그 밖' : diary.label,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppColors.muted,
      ),
    ),
  );
}

/// 펼친 목록의 한 줄. 사진이 요점이라 [RoutexListCell] 대신 직접 짠다 — 그 셀은
/// leading이 `IconData`뿐이다.
class _EventRow extends StatelessWidget {
  const _EventRow({super.key, required this.event, required this.onTap});

  final BuildingEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: RoutexSpacing.screenGutter,
          vertical: 8,
        ),
        child: Row(
          children: [
            _thumbnail(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title.replaceAll('\n', ' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (event.place.isNotEmpty) event.place,
                      _until(event.end),
                    ].join(' · '),
                    maxLines: 1,
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
    );
  }

  Widget _thumbnail() {
    const size = 48.0;
    const fallback = SizedBox(
      width: size,
      height: size,
      child: Icon(
        Icons.local_activity_outlined,
        size: 20,
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

  /// `08.26까지`. 시작일은 적지 않는다 — 이미 열려 있는 것만 있으므로 사용자가
  /// 정할 것은 "언제까지 갈 수 있나" 하나다.
  static String _until(String end) {
    final parts = end.split('-');
    return parts.length == 3 ? '${parts[1]}.${parts[2]}까지' : end;
  }
}
