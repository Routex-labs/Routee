import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../../../../domain/event/building_events.dart';
import '../../../../theme/app_theme.dart';

/// 행사 하나를 화면 가득한 포스터로 본다. 좌우로 밀면 **오늘 열리는 다른 행사**로
/// 넘어간다(공식 모바일 웹과 같은 조작).
///
/// 목록과 역할이 갈린다 — 목록은 훑는 자리고 여기는 고른 뒤 몰입하는 자리다.
/// 그래서 비교를 돕는 장치(썸네일·정렬)를 여기에 두지 않는다.
class EventPosterView extends StatefulWidget {
  const EventPosterView({
    super.key,
    required this.events,
    required this.initialIndex,
    required this.navigable,
    this.showGuide = true,
  });

  final List<BuildingEvent> events;
  final int initialIndex;

  /// 그 행사로 안내를 걸 수 있는가. [events]와 길이가 같다.
  final List<bool> navigable;

  /// 안내 버튼을 그릴지. **이미 그 매장의 상세 시트에서 열었으면 끈다** — 눌러도
  /// 방금 떠난 화면으로 돌아올 뿐이라, 잠긴 버튼을 두면 못 가는 곳처럼 읽힌다.
  final bool showGuide;

  /// 사용자가 "여기로 안내"를 누르면 그 행사의 인덱스로 pop한다. 그냥 닫으면 null.
  static Future<int?> show(
    BuildContext context, {
    required List<BuildingEvent> events,
    required int initialIndex,
    required List<bool> navigable,
    bool showGuide = true,
  }) {
    return Navigator.of(context).push<int>(
      // **불투명 라우트다.** 이 화면은 지도를 가리는 것이 목적이라, 시트들이
      // 쓰는 pass-through 라우트를 쓰지 않는다.
      MaterialPageRoute<int>(
        fullscreenDialog: true,
        builder: (_) => EventPosterView(
          events: events,
          initialIndex: initialIndex,
          navigable: navigable,
          showGuide: showGuide,
        ),
      ),
    );
  }

  @override
  State<EventPosterView> createState() => _EventPosterViewState();
}

class _EventPosterViewState extends State<EventPosterView> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
    // 양옆 **포스터**가 살짝 보여야 "옆에 더 있다"가 읽힌다. 본문까지 이웃
    // 페이지에서 비치면 아직 넘기지 않은 내용이 섞여 읽히므로 [_page]는 현재
    // 페이지에서만 텍스트를 그린다.
    viewportFraction: 0.86,
  );
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.events[_index];
    return Scaffold(
      // 지도·시트와 같은 밝은 canvas를 쓴다. 포스터가 어두워도 화면 전체를
      // 반전하면 이벤트만 별도 앱처럼 읽혔다.
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: widget.events.length,
                onPageChanged: (i) => setState(() => _index = i),
                // **한 장 안이 세로로 스크롤된다.** 포스터가 머리고 그 아래로
                // 원본 본문이 이어진다 — 특전·유의사항까지 여기서 다 읽는다.
                // 가로는 PageView가, 세로는 각 장의 ListView가 갖는다.
                itemBuilder: (context, i) => _page(widget.events[i], i),
              ),
            ),
            _action(event),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
      child: Row(
        children: [
          IconButton(
            key: const Key('poster-close'),
            icon: const Icon(Icons.close, color: AppColors.text),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Spacer(),
          if (widget.events.length > 1)
            Text(
              '${_index + 1} / ${widget.events.length}',
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }

  /// 포스터 한 장. 원본이 정사각 750이라 **세로를 채우지 않는다** — 폭에만
  /// 맞추면 1.44배지만 세로까지 채우면 3배가 되어 눈에 띄게 뭉갠다.
  Widget _poster(BuildingEvent event, int i) {
    final focused = i == _index;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      // 옆 카드를 조금 작게 두면 지금 보는 것이 어느 장인지 분명해진다.
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: focused ? 8 : 26),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: 1,
            child: event.image == null
                ? const ColoredBox(
                    color: AppColors.blue100,
                    child: Icon(
                      Icons.local_activity_outlined,
                      color: AppColors.muted,
                      size: 48,
                    ),
                  )
                : Image.asset(
                    event.image!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const ColoredBox(
                      color: AppColors.blue100,
                      child: Icon(
                        Icons.local_activity_outlined,
                        color: AppColors.muted,
                        size: 48,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  /// 한 장. 포스터 → 제목·기간·장소 → 원본 본문 순이다.
  Widget _page(BuildingEvent event, int i) {
    final focused = i == _index;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _poster(event, i),
        // 옆 페이지에서는 이미지 카드만 남긴다. PageView의 viewportFraction은
        // 유지해 다음 포스터가 보이되, 제목·본문이 아직 선택하지 않은 페이지
        // 에서 새어 나오지 않는다.
        if (focused) ...[
          _caption(event),
          for (final block in event.details) _block(block),
        ],
        // 아래 고정된 안내 버튼에 본문 끝줄이 가리지 않게 둔다.
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _caption(BuildingEvent event) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            event.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 8),
          _row('기간', '${_date(event.start)} ~ ${_date(event.end)}'),
          if (event.place.isNotEmpty) _row('장소', event.place),
        ],
      ),
    );
  }

  /// 공식 웹과 같은 `라벨 — 값` 두 칸이다. 라벨 폭을 고정해야 기간·장소의 값이
  /// 세로로 맞는다.
  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppColors.text, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  /// 본문 한 덩어리. **그릴 줄 모르는 종류는 조용히 건너뛴다** — 원본이 새
  /// 종류를 추가해도 그 자리만 비고 나머지는 그대로 읽힌다.
  Widget _block(EventBlock block) {
    const gutter = EdgeInsets.symmetric(horizontal: 24);
    switch (block.kind) {
      case 'h':
        return Padding(
          padding: gutter.copyWith(top: 22, bottom: 8),
          child: Text(
            block.text ?? '',
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        );
      case 'p':
        return Padding(
          padding: gutter.copyWith(top: 6, bottom: 6),
          child: Text(
            block.text ?? '',
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 13,
              height: 1.6,
            ),
          ),
        );
      case 'div':
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          child: Divider(height: 1, color: AppColors.hairline),
        );
      case 'img':
        return _detailImage(block.image);
      case 'prod':
        return Padding(
          padding: gutter.copyWith(top: 10, bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (block.image != null) _detailImage(block.image, inset: false),
              for (final (index, line) in block.lines.indexed)
                Padding(
                  padding: EdgeInsets.only(top: index == 0 ? 10 : 4),
                  child: Text(
                    line,
                    style: TextStyle(
                      // 첫 줄이 조건("1만원 이상 구매 특전")이라 강조한다.
                      color: index == 0 ? AppColors.text : AppColors.text,
                      fontSize: index == 0 ? 14 : 13,
                      fontWeight: index == 0
                          ? FontWeight.w700
                          : FontWeight.w400,
                      height: 1.5,
                    ),
                  ),
                ),
            ],
          ),
        );
      case 'notice':
        return Padding(
          padding: gutter.copyWith(top: 10, bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final item in block.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '· $item',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
            ],
          ),
        );
      case 'rows':
        return Padding(
          padding: gutter.copyWith(top: 8, bottom: 8),
          child: Column(
            children: [
              for (final row in block.rows)
                if (row.length >= 2) _row(row[0], row[1].replaceAll('**', '')),
            ],
          ),
        );
      case 'tel':
      case 'link':
        return Padding(
          padding: gutter.copyWith(top: 8, bottom: 8),
          child: Text(
            block.text ?? block.url ?? '',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  /// 본문 사진. **비율을 고정하지 않는다** — 특전 이미지가 세로로 긴 안내문이라
  /// 정사각으로 자르면 글자가 잘린다.
  Widget _detailImage(String? path, {bool inset = true}) {
    if (path == null) return const SizedBox.shrink();
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.asset(
        path,
        fit: BoxFit.fitWidth,
        width: double.infinity,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
    return inset
        ? Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            child: image,
          )
        : image;
  }

  /// **공식 웹에 없는 줄이다.** 웹은 읽고 끝나지만 우리는 거기까지 데려가는 것이
  /// 기능이라, 포스터를 보는 그 자리에서 안내가 시작되어야 한다.
  Widget _action(BuildingEvent event) {
    if (!widget.showGuide) return const SizedBox(height: 12);
    final can = widget.navigable[_index];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      child: SizedBox(
        width: double.infinity,
        child: RoutexButton(
          key: const Key('poster-navigate'),
          label: can ? '여기로 안내' : '위치 정보가 없어요',
          onPressed: can ? () => Navigator.of(context).pop(_index) : null,
        ),
      ),
    );
  }

  static String _date(String iso) {
    final parts = iso.split('-');
    return parts.length == 3 ? '${parts[1]}.${parts[2]}' : iso;
  }
}
