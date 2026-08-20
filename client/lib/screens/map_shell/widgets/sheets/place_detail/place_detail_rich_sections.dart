import 'dart:async';

import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../../core/clipboard_confirmation.dart';
import '../../../../../theme/app_theme.dart';

/// 메뉴 카드에 필요한 로컬 표시 데이터다. 메뉴의 판매 여부나 가격 갱신은
/// 상위 데이터 공급자가 책임지고 이 위젯은 값을 그대로 렌더링한다.
///
/// 이름과 사진 말고는 전부 없을 수 있다. 출처마다 가진 것이 달라서다 — 공식 사이트가
/// 가격을 안 주는 대신 용량·칼로리·카페인을 주기도 하고, 푸드처럼 영양정보가 아예 없는
/// 것도 있다. 없는 값을 어떻게 메울지는 카드가 정한다([specLine]).
class PlaceMenuItem {
  const PlaceMenuItem({
    required this.name,
    this.group,
    this.category,
    this.nameEn,
    this.price,
    this.description,
    this.volume,
    this.calories,
    this.caffeine,
    this.allergens,
    this.badges = const <String>[],
    this.imageAssetPath,
  });

  final String name;
  final String? group;
  final String? category;
  final String? nameEn;
  final String? price;
  final String? description;
  final String? volume;
  final String? calories;
  final String? caffeine;

  /// 알레르기 유발 성분. 공식 사이트 문구 그대로인 한 줄(`대두 / 우유`)이다.
  final String? allergens;

  /// NEW·시즌 한정처럼 줄에 붙는 표시. 없으면 빈 목록이다.
  final List<String> badges;

  final String? imageAssetPath;

  /// 팝업에 보여 줄 영양정보 목록. 없는 값은 빠진다.
  ///
  /// 푸드에는 이 정보가 아예 없어서 빈 목록이 된다. 그때 팝업은 이 블록을 통째로
  /// 생략한다 — 라벨만 있고 값이 빈 표를 그리면 "정보가 없다"가 아니라 "불러오지
  /// 못했다"로 읽힌다.
  ///
  /// **알레르기가 이 목록의 맨 아래다.** 용량·칼로리와 같은 표에 두는 이유는 값이
  /// 같은 성격(라벨-값 한 줄)이라서고, 맨 아래인 이유는 이 값만 없는 항목이 많아
  /// (음료 122/198, 푸드 0) 중간에 끼면 표의 줄 수가 항목마다 들쭉날쭉해지기
  /// 때문이다.
  List<(String, String)> get nutritionFacts => [
    if (price != null && price!.isNotEmpty) ('가격', price!),
    if (volume != null && volume!.isNotEmpty) ('용량', volume!),
    if (calories != null && calories!.isNotEmpty) ('칼로리', calories!),
    if (caffeine != null && caffeine!.isNotEmpty) ('카페인', caffeine!),
    if (allergens != null && allergens!.isNotEmpty) ('알레르기', allergens!),
  ];

  /// 팝업을 열 만한 내용이 있는가.
  ///
  /// 없으면 카드를 누를 수 없게 만든다. 눌렀는데 카드에 이미 있는 이름만 다시
  /// 나오는 팝업은 막다른 길이고, 한 번 겪으면 다음 카드도 안 누르게 된다.
  ///
  /// 배지는 세지 않는다. 배지는 이미 줄에 그려져 있어서, 그것만 있는 항목의 팝업은
  /// 여는 사람이 이미 본 것만 다시 보여 준다 — 상세를 못 받은 4종이 정확히 그렇다.
  bool get hasDetail =>
      nutritionFacts.isNotEmpty || (description?.isNotEmpty ?? false);
}

/// 메뉴를 좁은 가로 카드 목록으로 보여 준다. 카테고리가 있으면 위에 탭을 붙인다.
class PlaceMenuSection extends StatefulWidget {
  const PlaceMenuSection({super.key, required this.items});

  final List<PlaceMenuItem> items;

  @override
  State<PlaceMenuSection> createState() => _PlaceMenuSectionState();
}

/// 등장 순서대로 값을 뽑는다. 나눌 것이 없으면 빈 목록.
///
/// **한 항목이라도 값이 없으면 나누지 않는다.** 가진 것만 탭에 넣으면 나머지 항목은
/// 어느 탭에서도 보이지 않는데, 화면에는 아무 이상이 없어 보인다. 메뉴가 조용히
/// 사라지는 쪽이 한 줄로 길게 늘어놓는 것보다 나쁘다.
///
/// 값이 한 종류뿐일 때도 만들지 않는다. 누를 곳이 하나뿐인 탭은 아무것도 나누지
/// 않으면서 자리만 차지한다.
List<String> _distinctInOrder(
  List<PlaceMenuItem> items,
  String? Function(PlaceMenuItem) pick,
) {
  final values = <String>[];
  for (final item in items) {
    final value = pick(item);
    if (value == null || value.isEmpty) return const <String>[];
    if (!values.contains(value)) values.add(value);
  }
  return values.length > 1 ? values : const <String>[];
}

/// 탭으로 쓸 카테고리. 화면·테스트가 함께 쓴다.
List<String> menuCategoryTabs(List<PlaceMenuItem> items) =>
    _distinctInOrder(items, (item) => item.category);

/// 위쪽 갈래(음료·푸드).
List<String> menuGroupTabs(List<PlaceMenuItem> items) =>
    _distinctInOrder(items, (item) => item.group);

class _PlaceMenuSectionState extends State<PlaceMenuSection> {
  String? _activeGroup;
  String? _activeTab;
  String _query = '';

  /// 더보기를 눌러 전부 펼친 상태. 갈래·탭을 옮기거나 검색어를 바꾸면 다시 접는다 —
  /// 자리마다 펼침 상태를 따로 들고 있으면, 돌아왔을 때 어디까지 펼쳤는지 기억나지
  /// 않는 목록이 열려 있다.
  bool _expanded = false;

  /// 카테고리를 사람이 한 번이라도 건드렸는지.
  ///
  /// 처음에는 첫 카테고리를 골라 둔 것처럼 시작한다 — 갈래 하나에 200종 가까이
  /// 있어서 전체를 먼저 보여 주면 아무것도 좁혀 주지 않는다. 대신 **고른 칩을 다시
  /// 누르면 그때부터 전체**가 된다. 그 길을 막으면 한 번 고른 카테고리에서 빠져나올
  /// 수 없다(검색 패널에서 같은 이유로 되돌린 적이 있다).
  bool _tabTouched = false;

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    final groups = menuGroupTabs(widget.items);
    final activeGroup = groups.contains(_activeGroup)
        ? _activeGroup
        : groups.firstOrNull;
    final inGroup = activeGroup == null
        ? widget.items
        : widget.items
              .where((item) => item.group == activeGroup)
              .toList(growable: false);

    // 검색은 갈래 안에서만 한다. 음료를 보다가 친 검색어에 푸드가 섞여 나오면
    // 갈래를 고른 일이 무효가 된다.
    final searching = _query.trim().isNotEmpty;
    final matched = searching ? _search(inGroup, _query) : inGroup;

    // 검색 중에는 카테고리 탭을 숨긴다. 검색 결과가 여러 카테고리에 걸치는데 탭이
    // 남아 있으면 "지금 뭘 보고 있는지"가 두 곳에서 다르게 말해진다.
    final tabs = searching ? const <String>[] : menuCategoryTabs(matched);
    final active = _tabTouched
        ? (tabs.contains(_activeTab) ? _activeTab : null)
        : tabs.firstOrNull;
    final visible = active == null
        ? matched
        : matched
              .where((item) => item.category == active)
              .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: placeSectionGutter),
          child: RoutexSectionHeader(title: '메뉴'),
        ),
        if (groups.isNotEmpty) ...[
          const SizedBox(height: 12),
          _MenuGroupTabs(
            tabs: groups,
            active: activeGroup!,
            onSelect: (group) => setState(() {
              _activeGroup = group;
              _activeTab = null;
              _tabTouched = false;
              _expanded = false;
            }),
          ),
        ],
        // 검색창은 메뉴가 한 화면에 안 들어올 때만 의미가 있다. 열 줄도 안 되는
        // 목록에서는 눈으로 훑는 편이 빠르고, 입력창만 자리를 차지한다.
        if (widget.items.length >= _menuSearchThreshold) ...[
          const SizedBox(height: 12),
          _MenuSearchField(
            value: _query,
            onChanged: (value) => setState(() {
              _query = value;
              _expanded = false;
            }),
          ),
        ],
        if (tabs.isNotEmpty) ...[
          const SizedBox(height: 10),
          // 줄이 스스로 가로로 넘긴다. 지도 위 칩 줄과 달리 여기는 부모가 가로
          // 스크롤을 갖고 있지 않다.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: placeSectionGutter),
            child: RoutexChipBar(
              options: [
                for (final tab in tabs) RoutexChipOption(id: tab, label: tab),
              ],
              selectedId: active,
              semanticsLabel: '메뉴 분류',
              onSelected: (id) => setState(() {
                _tabTouched = true;
                _activeTab = id;
                _expanded = false;
              }),
            ),
          ),
        ],
        const SizedBox(height: 6),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              placeSectionGutter,
              14,
              placeSectionGutter,
              6,
            ),
            child: Text(
              '찾는 메뉴가 없습니다',
              style: RoutexTypography.bodySmall.copyWith(
                color: context.routexColors.contentSecondary,
              ),
            ),
          ),
        // 세로 목록이라 스크롤을 따로 갖지 않는다. 시트 본문이 이미 스크롤이고,
        // 그 안에 또 스크롤을 넣으면 어느 쪽이 움직일지가 손끝에서 갈린다.
        Padding(
          // 줄은 제 여백을 갖고 있다. 본문 여백선에 맞추려면 그만큼 뺀 값을
          // 바깥에 준다.
          padding: const EdgeInsets.symmetric(
            horizontal: placeSectionGutter - RoutexSpacing.contentGap,
          ),
          child: RoutexMenuList(
            entries: [
              for (final item in visible)
                RoutexMenuEntry(
                  name: item.name,
                  description: item.description,
                  price: item.price,
                  selectable: item.hasDetail,
                  badges: [
                    for (final badge in item.badges)
                      RoutexBadge(label: badge, accent: badgeAccentFor(badge)),
                  ],
                  thumbnail: item.imageAssetPath == null
                      ? null
                      : RoutexMediaItem(
                          image: AssetImage(item.imageAssetPath!),
                        ),
                ),
            ],
            collapsedCount: _menuVisibleCap,
            thumbnailAspectRatio: _menuImageAspect,
            expanded: _expanded,
            onExpanded: (value) => setState(() => _expanded = value),
            onSelected: (index) => showDialog<void>(
              context: context,
              builder: (_) => _menuDialog(visible[index]),
            ),
          ),
        ),
      ],
    );
  }
}

/// 검색창을 붙이는 최소 메뉴 수.
const _menuSearchThreshold = 20;

/// 이름·영문명으로 찾는다. 공백을 지우고 대소문자를 무시한다.
///
/// 설명까지 뒤지지 않는 이유는 결과가 설명 안의 흔한 낱말에 끌려다니기 때문이다 —
/// "커피"를 치면 설명에 커피가 들어간 거의 모든 음료가 나와서 걸러 주는 게 없다.
List<PlaceMenuItem> _search(List<PlaceMenuItem> items, String query) {
  String norm(String value) => value.replaceAll(' ', '').toLowerCase();
  final needle = norm(query);
  return items
      .where(
        (item) =>
            norm(item.name).contains(needle) ||
            norm(item.nameEn ?? '').contains(needle),
      )
      .toList(growable: false);
}

/// 배지 이름 → 색. 둘 다 연한 배경 + 진한 글자(tonal)라 사진 옆에서 튀지 않는다.
///
/// 갈라 놓는 이유는 **한 줄에 둘이 나란히 뜨는 항목이 있기 때문이다.** 같은 색이면
/// 두 배지가 한 덩어리로 읽힌다. 초록은 새로 나온 것, 주황은 기간이 정해진 것으로
/// 쓴다 — 빨강을 쓰지 않는 것은 앱에서 이미 오류·목적지에 배정된 색이라 뜻이
/// 겹치기 때문이다.
/// 키는 아래 [badgeAccentFor]가 쓰는 정규화된 형태(공백 제거·대문자)로 적는다.
const _badgeAccents = <String, RoutexBadgeAccent>{
  'NEW': RoutexBadgeAccent(surface: Color(0xFFE8F5EC), ink: Color(0xFF1E7B45)),
  '시즌한정': RoutexBadgeAccent(surface: Color(0xFFFDF0E7), ink: Color(0xFFB4600F)),
};

/// 배지 색을 고른다. **모르는 배지는 null이고, 그때는 무채색으로 떨어진다** —
/// 스타벅스가 새 배지를 만들면(예: "한정 판매") 그리지 못하는 것이 아니다. 색은
/// 정보를 더하는 장치이지 그리기 위한 조건이 아니다.
///
/// 공백을 지우고 대문자로 맞춰 찾는 이유는 수집 원본이 `NEW`와 `New`, `시즌 한정`과
/// `시즌한정`을 섞어 쓸 수 있어서다 — 표기 하나가 달라졌다고 색이 조용히 사라지면
/// 원인을 찾기 어렵다. 화면에 그리는 글자는 원본 그대로다.
RoutexBadgeAccent? badgeAccentFor(String label) =>
    _badgeAccents[label.replaceAll(' ', '').toUpperCase()];

/// 위쪽 갈래(음료·푸드) 선택.
///
/// **`RoutexTabs`를 쓰지 않는다.** 한 번 옮겨 폰에서 봤더니 시트 위쪽의
/// 홈·메뉴·사진 줄과 **똑같은 밑줄 탭이 둘 겹쳐** 어느 줄이 무엇을 가르는지가
/// 흐려졌다. 갈래가 둘뿐이라 균등 폭도 화면 절반씩을 먹었다. Runtime Kit의 선택
/// register는 탭과 칩 둘인데 이 화면은 셋(시트 탭 → 갈래 → 분류)이 필요하고, 그
/// 세 번째 자리를 굵기로 만든다. 색·글자·간격은 Kit 토큰을 쓴다.
class _MenuGroupTabs extends StatelessWidget {
  const _MenuGroupTabs({
    required this.tabs,
    required this.active,
    required this.onSelect,
  });

  final List<String> tabs;
  final String active;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.routexColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: placeSectionGutter),
      child: Row(
        children: [
          for (final tab in tabs)
            Semantics(
              button: true,
              selected: tab == active,
              label: tab,
              excludeSemantics: true,
              child: GestureDetector(
                onTap: () => onSelect(tab),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  // 보이는 크기는 글자 그대로 두고 누르는 상자만 세로로 넓힌다.
                  padding: const EdgeInsets.only(
                    right: RoutexSpacing.sectionGap,
                    top: RoutexSpacing.contentGap,
                    bottom: RoutexSpacing.contentGap,
                  ),
                  child: Text(
                    tab,
                    style: RoutexTypography.body.copyWith(
                      fontWeight: tab == active
                          ? FontWeight.w800
                          : FontWeight.w500,
                      color: tab == active
                          ? colors.contentPrimary
                          : colors.contentSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 메뉴 이름으로 좁히는 검색창.
class _MenuSearchField extends StatefulWidget {
  const _MenuSearchField({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_MenuSearchField> createState() => _MenuSearchFieldState();
}

class _MenuSearchFieldState extends State<_MenuSearchField>
    with WidgetsBindingObserver {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  final _focusNode = FocusNode();

  /// 포커스는 받았는데 키보드가 아직 안 올라온 상태. 이때 스크롤하면 **지금 비어
  /// 있는 자리**를 기준으로 계산해서, 키보드가 올라온 뒤 다시 가려진다.
  var _revealPending = false;

  /// 마지막 빌드에서 본 키보드 높이. [build]가 기록한다.
  var _keyboardInset = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusNode
      ..removeListener(_onFocusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) return;
    // 이미 다른 입력칸을 쓰다 넘어온 경우라 키보드가 떠 있다. 기다릴 것이 없다.
    if (_keyboardInset > 0) {
      _reveal();
    } else {
      _revealPending = true;
    }
  }

  /// 키보드가 실제로 올라온 순간을 여기서 잡는다.
  ///
  /// 고정 지연(`Future.delayed`)으로 맞추지 않는 이유는 그 값이 기기·키보드마다 다른
  /// 애니메이션 길이를 추측한 숫자이기 때문이다 — 느린 기기에서 먼저 스크롤해 버리면
  /// 아무 일도 없어 보인다.
  ///
  /// 키보드는 **화면(view)의 메트릭**이라 이 콜백으로 온다. `didChangeDependencies`로
  /// 잡으려다 실패했는데, 이 위젯을 감싸는 MediaQuery가 바뀌지 않기 때문이다 —
  /// 바뀌는 것은 그 위의 화면이고 MediaQuery는 그 값을 옮겨 담을 뿐이다.
  @override
  void didChangeMetrics() {
    if (!_revealPending) return;
    // 메트릭 콜백은 프레임 밖에서 오고 MediaQuery는 다음 빌드에 갱신되므로,
    // 값을 보는 것도 스크롤하는 것도 다음 프레임에 한다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_revealPending) return;
      if (MediaQuery.viewInsetsOf(context).bottom <= 0) return;
      _revealPending = false;
      _reveal();
    });
  }

  /// 검색창을 화면 위쪽으로 올린다. 끝에 붙이지 않고 조금 띄우는(0.08) 이유는
  /// 검색이 결과를 보려고 하는 일이라, 입력칸만 보이고 아래가 키보드면 친 보람이
  /// 없기 때문이다.
  void _reveal() {
    if (!mounted) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.08,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    // **여기서 읽어야 한다.** MediaQuery 의존은 빌드마다 새로 등록되고 리빌드 직전에
    // 비워지므로, 포커스 리스너 안에서만 읽으면 그 등록이 다음 리빌드에 지워져
    // 키보드가 올라와도 [didChangeDependencies]가 오지 않는다. 화면에 쓰지 않는
    // 값을 굳이 빌드에서 읽는 이유가 이것이다.
    _keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: placeSectionGutter),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.blue50,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const Icon(Icons.search, size: 19, color: AppColors.muted),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  onChanged: widget.onChanged,
                  style: const TextStyle(fontSize: 14, color: AppColors.text),
                  // 상태별 테두리를 **전부** 끈다. `border`만 끄면 포커스됐을 때
                  // 테마의 focusedBorder(파랑 1.5px)가 살아나 알약 테두리가 뜬다 —
                  // `border`는 기본 상태의 테두리일 뿐이고 상태별 값이 우선한다.
                  // 이 칸은 이미 바깥 상자가 배경·모서리를 갖고 있어서, 안쪽에 또
                  // 테두리가 그려지면 상자 안에 상자가 생긴다. `filled`도 같은
                  // 이유로 끈다(테마가 채우면 바깥 상자 위에 한 겹 더 칠한다).
                  decoration: const InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    hintText: '메뉴 검색',
                    hintStyle: TextStyle(fontSize: 14, color: AppColors.muted),
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              if (widget.value.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    _controller.clear();
                    widget.onChanged('');
                  },
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.close, size: 18, color: AppColors.muted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 메뉴 사진의 가로÷세로. 번들에 든 316장이 전부 300×313이라 그 값을 그대로 쓴다.
///
/// **썸네일을 이 비율로 잡는 이유는 자르지 않기 위해서다.** 정사각으로 넣으면 비율이
/// 0.96인 사진의 위아래가 잘려 컵이 뭉툭해진다. 배경색으로 여백을 채우는 방식은 못 쓴다 —
/// 사진 배경이 제품마다 다크그린·크림색으로 갈리고 단색이 아닌 것도 있다.
///
/// 30종일 때는 402×420이었다. 전량 316종은 공식 목록 페이지의 같은 사진을 받은 것이라
/// 해상도가 300×313으로 바뀌었고, 비율은 0.957 → 0.958로 사실상 같다. **비율이 다른
/// 사진이 섞여 들어오면 `BoxFit.contain`이 남는 쪽을 여백으로 남긴다** — 잘리지는
/// 않지만 줄마다 사진 크기가 달라 보인다. 그때는 이 상수가 아니라 사진을 맞춘다.
const _menuImageAspect = 300 / 313;

/// 한 카테고리에서 접힌 상태로 보여 주는 줄 수. 넘는 만큼은 "더보기" 뒤로 보낸다.
///
/// 세로 목록이라 줄이 늘어날수록 다른 섹션(영업 정보·매장 정보)이 화면 밖으로 밀린다.
/// 상한을 두면 상세를 처음 열었을 때 어떤 섹션들이 있는지가 한눈에 들어오고, 메뉴를
/// 더 볼 사람만 펼치면 된다.
const _menuVisibleCap = 4;

/// 메뉴 하나의 상세. 줄에서 뺀 영문명·설명·영양정보가 여기 모인다.
///
/// 시트가 아니라 다이얼로그인 이유는 **뒤로가기 규약**(설계 F5) 때문이다. 상세 시트는
/// 자기 라우트가 pop되면 `onCloseAll`로 시트 묶음 전체를 닫는데, 그 위에 시트를 하나
/// 더 쌓으면 뒤로가기 한 번이 어디까지 닫는지가 흐려진다. 다이얼로그는 별도 라우트라
/// 뒤로가기가 팝업만 닫고 상세 시트는 그대로 남는다.
RoutexDialog _menuDialog(PlaceMenuItem item) => RoutexDialog(
  title: item.name,
  subtitle: item.nameEn,
  description: item.description,
  media: item.imageAssetPath == null
      ? null
      // 높이를 박아 두면 폭이 넓어 세로를 60% 넘게 잘라낸다 — 메뉴를 자세히 보려고
      // 연 팝업에서 정작 사진이 제일 많이 잘렸다. 그래서 비율을 사진에 맞춘다.
      : AspectRatio(
          aspectRatio: _menuImageAspect,
          child: Image.asset(item.imageAssetPath!, fit: BoxFit.contain),
        ),
  facts: [
    for (final fact in item.nutritionFacts)
      RoutexKeyValue(label: fact.$1, value: fact.$2),
  ],
);

/// 주소·주차처럼 매장을 설명하는 운영 정보다.
///
/// 영업시간·연락처류는 이 자리에 오지 못한다. 시간이 지나면 자동으로 거짓이 되는데
/// 갱신을 보장할 방법이 없어서이고, 서버 검증기의 `forbidden_labels`가 데이터
/// 단계에서 막는다(설계 9-1).
class PlaceBusinessInfo {
  const PlaceBusinessInfo({required this.label, required this.value});

  final String label;
  final String value;
}

/// 매장 운영 정보를 아이콘-값 행으로 보여 준다.
///
/// 카드 테두리 없이 여백만 쓴다. 위쪽 summary·hero가 이미 시각적으로 묶여 있어서
/// 여기에 상자를 하나 더 두면 시트가 카드의 나열처럼 보인다.
class PlaceBusinessInfoSection extends StatelessWidget {
  const PlaceBusinessInfoSection({super.key, required this.items});

  final List<PlaceBusinessInfo> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const RoutexSectionHeader(title: '매장 정보'),
        const SizedBox(height: 12),
        for (var index = 0; index < items.length; index++) ...[
          if (index > 0) const SizedBox(height: infoRowGap),
          RoutexInfoRow(
            label: items[index].label,
            value: items[index].value,
            icon: infoIconFor(items[index].label),
          ),
        ],
      ],
    );
  }
}

/// 공식 채널 링크 하나.
class PlaceLinkItem {
  const PlaceLinkItem({required this.label, required this.url, this.iconAsset});

  final String label;
  final String url;

  /// 번들에 든 브랜드 아이콘. 있으면 배지가 이 그림이 되고, 없으면 라벨로 고른
  /// Material 아이콘([linkBrandFor])으로 떨어진다.
  final String? iconAsset;
}

/// 링크 줄 왼쪽 배지의 모양.
///
/// **원격 favicon URL은 쓰지 않는다.** 시트 첫 프레임이 네트워크를 기다리게 해서
/// 설계 9-1 D1′이 금지한 것과 같은 문제가 된다. 기본은 Material 아이콘에
/// **브랜드 색만** 입히는 것이다 — 색은 로고가 아니라서 담을 것이 없다.
///
/// 예외는 서버가 [PlaceLinkItem.iconAsset]으로 **번들에 든 그림**을 지정한 경우다.
/// 그때는 저작권 범위가 이미 그 매장 자산과 같아진 상태이므로(오설록은 제품 사진
/// 309장이 같은 데모 식별용으로 들어 있다) 새로 생기는 위험이 없다. 아무 매장에나
/// 로고를 담자는 뜻은 아니고, **담기로 이미 정한 매장에만** 열어 둔 문이다.
class PlaceLinkBrand {
  const PlaceLinkBrand({required this.icon, required this.colors});

  final IconData icon;

  /// 배지 바탕색. 한 색이면 단색, 여러 색이면 좌상→우하 그라데이션이다.
  /// 인스타그램처럼 브랜드 자체가 그라데이션인 곳이 있어 목록으로 받는다.
  final List<Color> colors;
}

/// 라벨로 고른 브랜드 배지. 모르는 라벨에도 배지를 준다 — 라벨 글자가 항상 옆에
/// 있어서 아이콘이 뜻을 혼자 짊어지지 않는다([infoIconFor]와 다른 점).
PlaceLinkBrand linkBrandFor(String label) {
  final key = label.replaceAll(' ', '');
  if (isWebsiteLabel(label)) {
    return const PlaceLinkBrand(
      icon: Icons.public,
      colors: [Color(0xFF3C4043)],
    );
  }
  return switch (key) {
    '페이스북' => const PlaceLinkBrand(
      icon: Icons.facebook,
      colors: [Color(0xFF1877F2)],
    ),
    '인스타그램' => const PlaceLinkBrand(
      icon: Icons.camera_alt,
      colors: [Color(0xFFF58529), Color(0xFFDD2A7B), Color(0xFF8134AF)],
    ),
    // 유튜브는 재생 삼각형이 브랜드 자체라 `play_arrow`가 아니라 화면 안에 삼각형이
    // 든 글리프를 쓴다 — 빨간 원 안의 홑 삼각형은 다른 재생 버튼과 구분되지 않는다.
    '유튜브' || 'youtube' || 'YouTube' => const PlaceLinkBrand(
      icon: Icons.smart_display,
      colors: [Color(0xFFFF0000)],
    ),
    // `네이버 브랜드스토어`가 공백을 지우면 `네이버브랜드스토어`라 정확히 일치하는
    // 가지가 없어 회색 기본값으로 떨어져 있었다. 스토어류는 이름이 계속 바뀌므로
    // (스마트스토어 → 브랜드스토어) 조각 일치로 받는다.
    _ when key.contains('스토어') || key.contains('네이버') => const PlaceLinkBrand(
      icon: Icons.storefront,
      colors: [Color(0xFF03C75A)],
    ),
    _ => const PlaceLinkBrand(icon: Icons.link, colors: [AppColors.muted]),
  };
}

/// 주소를 함께 보여 줄 줄인가.
///
/// **차례가 아니라 라벨로 판단한다.** 참고 화면에서 주소가 보이는 것은 그 줄이 첫
/// 줄이어서가 아니라 웹사이트 줄이어서다 — `공식 사이트`라는 라벨은 어느 사이트인지를
/// 말해 주지 않지만 `페이스북`·`인스타그램`은 라벨이 곧 정체다. 순서로 정하면 배열
/// 순서를 바꿨을 때 뜻 없이 화면이 따라 바뀐다.
///
/// 앞에 매장 이름이 붙은 `오설록 공식 홈페이지`도 웹사이트 줄이다. 그래서 정확히
/// 일치가 아니라 **끝이 맞는지**를 본다 — 이름은 매장마다 다르고 뒤 낱말은 같다.
bool isWebsiteLabel(String label) => websiteNamePrefix(label) != null;

/// 긴 것부터 본다. `오설록공식홈페이지`에서 `홈페이지`를 먼저 떼면 남는 것이
/// `오설록공식`이 되어 이름이 아니게 된다.
const _websiteSuffixes = ['공식홈페이지', '공식사이트', '홈페이지', '웹사이트'];

/// 웹사이트 라벨에서 뒤 낱말을 뗀 앞부분. 웹사이트 줄이 아니면 `null`이고,
/// **낱말만 있는 라벨(`공식 사이트`)이면 빈 문자열**이다.
///
/// 이 둘을 나누는 이유는 화면이 다르기 때문이다 — 앞에 이름이 있으면 그 이름이
/// 정보라 주소 위에 남기고, 없으면 라벨이 어느 사이트인지 말해 주지 않으므로
/// 주소만 보여 준다.
String? websiteNamePrefix(String label) {
  final key = label.replaceAll(' ', '');
  for (final suffix in _websiteSuffixes) {
    if (key.endsWith(suffix)) {
      return key.substring(0, key.length - suffix.length);
    }
  }
  return null;
}

/// 공식 채널 링크 목록. 누르면 외부 브라우저로 연다.
class PlaceLinksSection extends StatelessWidget {
  const PlaceLinksSection({super.key, required this.items});

  final List<PlaceLinkItem> items;

  // 열기에 실패하면 조용히 넘기지 않는다. 눌렀는데 아무 일도 일어나지 않으면
  // 사용자는 앱이 멈춘 줄 안다 — 실패했다는 사실만이라도 알려 준다.
  Future<void> _open(BuildContext context, String url, String label) async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    // SnackBar를 쓰던 자리다. **이 시트에서는 보이지 않았다** — 상세 시트가
    // Navigator에 얹힌 모달이라 SnackBar를 그리는 Scaffold보다 위에 있다. 열기가
    // 실패해도 화면에는 아무 일도 안 일어난 것으로 보였다. 이유는 [RoutexToast].
    if (!opened && context.mounted) {
      RoutexToast.show(context, '$label을(를) 열지 못했습니다');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const RoutexSectionHeader(title: 'SNS'),
        const SizedBox(height: 12),
        RoutexLinkList(
          items: [
            for (final item in items)
              RoutexLinkItem(
                label: item.label,
                url: item.url,
                display: _displayFor(item.label),
                accent: _accentFor(item),
              ),
          ],
          // 여는 일은 앱이 한다 — 외부 앱을 여는 것은 플랫폼 능력이다.
          onSelected: (selected) =>
              _open(context, selected.url, selected.label),
        ),
      ],
    );
  }

  /// 이 줄에서 사람이 읽을 값이 무엇인가. **라벨의 성격으로 정한다** — 차례로
  /// 정하면 배열을 바꿨을 때 뜻 없이 화면이 따라 바뀐다.
  static RoutexLinkDisplay _displayFor(String rawLabel) {
    final label = rawLabel.trim();
    if (label.isEmpty) return RoutexLinkDisplay.url;
    // `오설록 공식 홈페이지`처럼 **브랜드를 말하는 웹사이트 라벨**이 먼저다. 이걸
    // 뒤에 두면 웹사이트 판정이 먼저 걸려 라벨이 주소에 덮인다.
    if ((websiteNamePrefix(label) ?? '').isNotEmpty) {
      return RoutexLinkDisplay.labelAndUrl;
    }
    if (isWebsiteLabel(label)) return RoutexLinkDisplay.url;
    return RoutexLinkDisplay.label;
  }

  static RoutexLinkAccent _accentFor(PlaceLinkItem item) {
    final brand = linkBrandFor(item.label.trim());
    final asset = item.iconAsset;
    return RoutexLinkAccent(
      icon: brand.icon,
      colors: brand.colors,
      image: asset == null || asset.isEmpty ? null : AssetImage(asset),
    );
  }
}

/// 정보 행 사이 간격. 행마다 구분선을 긋지 않는 이유는 6줄짜리 목록이 표처럼
/// 보이면서 시트 전체가 글 덩어리로 읽히기 때문이다. 섹션 경계는 이미
/// `_SectionBreak`가 긋고 있어서 행 사이까지 그을 필요가 없다.
const infoRowGap = 14.0;

/// 라벨을 대신하는 아이콘. 없으면 `null`이고, 그때는 라벨을 글자로 남긴다.
///
/// **모르는 라벨에 기본 아이콘을 물리지 않는다.** 아이콘이 라벨을 대신할 수 있는
/// 것은 그 아이콘이 라벨을 정확히 가리킬 때뿐이고, 아무 아이콘이나 붙이면 값이
/// 무슨 뜻인지가 화면에서 사라진다. 데이터는 사람이 쓰는 자유 문자열이라
/// 언제든 새 라벨이 들어온다.
IconData? infoIconFor(String label) => switch (label.replaceAll(' ', '')) {
  '영업시간' || '운영시간' => Icons.schedule_outlined,
  // 고객센터는 수화기가 아니라 상담원 아이콘이다. 같은 전화번호라도 "이 매장에
  // 건다"와 "본사 콜센터에 건다"는 다른 일이고, 둘을 같은 글리프로 그리면 화면이
  // 그 차이를 지운다. 아이콘만으로는 부족해서 이 줄은 라벨 글자도 함께 남긴다
  // (`RoutexInfoRow.keepLabel`).
  '고객센터' => Icons.support_agent_outlined,
  '대표번호' || '전화번호' || '연락처' || '문의' => Icons.call_outlined,
  '매장타입' || '매장유형' => Icons.storefront_outlined,
  '주차' => Icons.local_parking_outlined,
  '위생등급' => Icons.verified_outlined,
  '주소' || '위치' => Icons.place_outlined,
  '홈페이지' || '웹사이트' => Icons.language_outlined,
  _ => null,
};

/// 영업시간·대표번호처럼 **시간이 지나면 저절로 거짓이 되는** 운영 정보다.
///
/// [PlaceBusinessInfo]와 갈라 둔 이유가 여기 있다. 저쪽은 주소처럼 잘 변하지 않는 값만
/// 담고 확인일을 붙이지 않는다 — 정보량 대비 소음만 늘기 때문이다(설계 7-A-3). 이쪽은
/// 반대로 확인일 없이는 값 자체를 믿을 수 없어서, 서버가 항목마다 확인일을 필수로 준다.
class PlaceDemoInfo {
  const PlaceDemoInfo({
    required this.label,
    required this.value,
    required this.confirmedAt,
  });

  final String label;
  final String value;
  final String confirmedAt;
}

/// 전화번호가 들어 있는 줄인가.
///
/// **값이 아니라 라벨로 먼저 거른다.** 값만 보고 판단하면 영업시간 줄의
/// `2026-08-10`이나 층 안내의 `B2-1` 같은 토막에 복사 버튼이 붙는다.
bool isPhoneLabel(String label) => switch (label.replaceAll(' ', '')) {
  '고객센터' || '대표번호' || '전화번호' || '연락처' || '문의' => true,
  _ => false,
};

/// 값에서 전화번호로 보이는 첫 토막. 없으면 null이고, 그때는 복사 버튼도 없다.
///
/// 값은 `1522-3232 (평일 09:00–18:00)`처럼 번호 뒤에 부연이 붙는다. 통째로 복사하면
/// 전화 앱에 붙여 넣을 수 없으므로 번호만 떼어 낸다.
String? phoneNumberIn(String value) =>
    _phonePattern.firstMatch(value)?.group(0);

final _phonePattern = RegExp(r'\d{2,4}-\d{3,4}(?:-\d{4})?');

/// 확인일이 붙은 운영 정보를 라벨-값 행으로 보여 준다.
class PlaceDemoInfoSection extends StatelessWidget {
  const PlaceDemoInfoSection({super.key, required this.items});

  final List<PlaceDemoInfo> items;

  Widget _row(BuildContext context, PlaceDemoInfo item, String? sharedDate) {
    final isPhone = isPhoneLabel(item.label);
    return RoutexInfoRow(
      label: item.label,
      value: item.value,
      icon: infoIconFor(item.label),
      // 전화 줄만 라벨을 남긴다. 누가 받는 번호인지는 아이콘이 말해 주지 못하고,
      // 그 한 단어가 빠지면 값의 뜻이 달라진다.
      keepLabel: isPhone,
      copyText: isPhone ? phoneNumberIn(item.value) : null,
      onCopied: () => announceClipboardCopy(context),
      // 확인일이 제각각일 때만 항목마다 붙인다. 묶을 수 없기 때문이다.
      caption: sharedDate == null ? '${item.confirmedAt} 확인' : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    // 확인일이 전부 같으면 섹션 아래에 한 번만 적는다. 다섯 항목에 같은 날짜를 다섯
    // 번 적으면 읽히지 않는 소음이 되고, **다르면 묶을 수 없다** — 묶는 순간 오래된
    // 항목이 최근에 확인된 것처럼 보인다.
    final dates = {for (final item in items) item.confirmedAt};
    final sharedDate = dates.length == 1 ? dates.single : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const RoutexSectionHeader(title: '영업 정보'),
        const SizedBox(height: 12),
        for (var index = 0; index < items.length; index++) ...[
          if (index > 0) const SizedBox(height: infoRowGap),
          _row(context, items[index], sharedDate),
        ],
        if (sharedDate != null) ...[
          const SizedBox(height: 12),
          Text(
            '$sharedDate 확인',
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ],
      ],
    );
  }
}

/// 상세 본문의 좌우 여백. 사진처럼 끝까지 채우는 섹션만 이 값을 쓰지 않는다.
const placeSectionGutter = RoutexSpacing.componentPadding;
