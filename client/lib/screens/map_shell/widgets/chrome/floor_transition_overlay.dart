import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../../../domain/guidance/escalator_ride.dart';
import '../../../../features/indoor_navigation/contract/floor_transition_ui_state.dart';
import '../../../../theme/app_theme.dart';
import '../../../../map/icon/location_marker_icon.dart';

/// 층 도면이 교체되는 구간을 덮는 스크림. 앱 셸 root Stack의 **마지막 레이어**에
/// 둔다 — 지도 안에 두면 검색창·하단 바가 그대로 보여 전환 사실이 안 드러난다.
///
/// **도면이 갈리는 앞뒤만 덮는다**(약 4.7초). 덮인 **뒤에서** 크로스페이드와 마커
/// 활강이 그대로 돌아야 걷히는 순간 "가려 놓고 순간이동시킨" 것으로 안 보인다.
///
/// 카드의 점은 **실제 진행률을 따르지 않는다** — 실제 진행은 10초 이상에 걸쳐
/// 흐르는데 덮개는 몇 초만 보여, 얹으면 점이 멈춘 것으로 읽혔다.
class FloorTransitionScrim extends StatelessWidget {
  const FloorTransitionScrim({
    super.key,
    required this.opacity,
    required this.fadeIn,
    required this.fadeOut,
    this.state,
    this.photoAssets = const [],
  });

  /// 배경을 덮는 정도. 0이면 아무것도 그리지 않고 입력도 그대로 통과한다.
  final double opacity;
  final Duration fadeIn;
  final Duration fadeOut;

  /// 가운데 카드에 표시할 `B1 → 1F`. 없으면 배경만 덮는다.
  final FloorTransitionUiState? state;

  /// 도착 층의 사진들(`domain/floor/floor_concept_photo.dart`). 비어 있으면 층
  /// 라벨과 점만 그린다 — 주차층처럼 원본이 사진을 주지 않는 층이 있다.
  final List<String> photoAssets;

  /// 이 이상 덮였으면 뒤쪽 입력을 막는다.
  ///
  /// 거의 다 가려진 동안에는 막아야 한다 — 보이지도 않는 지도 위의 탭은
  /// 사용자가 의도한 대상이 아니다. 반대로 페이드가 걷히는 동안에는 통과시킨다.
  /// 해제가 0.7초로 느려서, 그동안 막아 두면 전환이 끝난 화면이 잠깐 먹통으로
  /// 느껴진다.
  static const _inputBlockingOpacity = 0.9;

  @override
  Widget build(BuildContext context) {
    final transition = state;
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      ignoring: opacity < _inputBlockingOpacity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedOpacity(
            opacity: opacity.clamp(0.0, 1.0),
            duration: opacity > 0 ? fadeIn : fadeOut,
            curve: Curves.easeOut,
            child: ColoredBox(color: scheme.surface),
          ),
          if (transition != null)
            AnimatedOpacity(
              opacity: opacity > 0 ? 1 : 0,
              duration: opacity > 0 ? fadeIn : fadeOut,
              curve: Curves.easeOut,
              child: Center(
                child: _FloorTransitionCard(
                  state: transition,
                  photoAssets: photoAssets,
                  // 걷힌 뒤에도 카드는 트리에 남는다(페이드 아웃 때문에).
                  // 애니메이션까지 남겨 두면 보이지도 않는 위젯이 매 프레임
                  // rebuild를 요청한다.
                  animating: opacity > 0,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 스크림 가운데의 층 전환 연출. 두 층 라벨을 **세로로** 세우고 점이 그 사이를
/// 탄다 — 가로로 `B1 → B2`라고 적으면 지하로 내려가는데 화면은 오른쪽으로 가는
/// 그림이라 방향 감각이 꼬인다.
///
/// 점은 자체 시계로 **한 번** 재생하고 도착 쪽에 머문다. **반복하지 않는다** —
/// 무한 반복했더니 덮개가 3초를 넘길 때 같은 장면이 두 번 재생돼 오히려 "지금
/// 어디쯤인지"를 알 수 없게 만들었다.
class _FloorTransitionCard extends StatefulWidget {
  const _FloorTransitionCard({
    required this.state,
    required this.animating,
    this.photoAssets = const [],
  });

  final FloorTransitionUiState state;

  /// 도착 층 사진들. 비어 있으면 이 카드는 라벨과 점만 그린다.
  final List<String> photoAssets;

  /// 애니메이션을 돌릴지. 스크림이 걷힌 뒤에는 false로 내려온다.
  final bool animating;

  @override
  State<_FloorTransitionCard> createState() => _FloorTransitionCardState();
}

class _FloorTransitionCardState extends State<_FloorTransitionCard>
    with SingleTickerProviderStateMixin {
  /// 한 번 재생하는 스위프의 길이. 덮개가 완전히 걷히기 전에 점이 도착 쪽에
  /// 닿아 있도록 덮개 유지 시간(약 4.7초)보다 짧게 둔다.
  static const _travel = escalatorGlideDuration;

  /// 두 라벨 사이 선의 길이. 짧으면 이동이 안 읽히고, 길면 라벨이 화면
  /// 위아래로 흩어져 한 덩어리로 안 보인다.
  static const _lineHeight = 104.0;

  /// 사진이 **덮개가 완전히 짙어진 뒤에** 들어오기 시작한다. 페이드 밑에서
  /// 미끄러지면 두 연출이 겹쳐 둘 다 뭉갠다.
  static const _photoDelay = floorTransitionScrimFadeIn;
  static const _photoEntry = floorPhotoEntrance;

  /// 사진이 미끄러져 들어오는 거리. 진행 방향에서 들어온다 — 올라가는 전환이면
  /// 아래에서 위로. 점·계단 모티프와 같은 규칙이다(움직이는 것이 곧 나다).
  static const _photoSlide = 44.0;

  static const _photoMargin = 24.0;
  static const _photoGap = 22.0;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _travel,
  );

  /// 사진 등장. 점과 **같은 컨트롤러**를 구간으로 나눠 쓴다 — 티커를 하나 더
  /// 돌리면 덮개가 걷힌 뒤 멈추는 것도 두 곳에서 챙겨야 한다.
  late final CurvedAnimation _photoIn = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      _photoDelay.inMilliseconds / _travel.inMilliseconds,
      (_photoDelay + _photoEntry).inMilliseconds / _travel.inMilliseconds,
      curve: Curves.easeOutCubic,
    ),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animating) _controller.forward();
  }

  @override
  void didUpdateWidget(covariant _FloorTransitionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animating == oldWidget.animating) return;
    if (widget.animating) {
      _controller.forward(from: 0);
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _photoIn.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) =>
          _build(context, _controller.value.clamp(0.0, 1.0)),
    );
  }

  /// 도착 층 사진. 없는 층이면 null이고, 그때 카드는 예전 모습 그대로다.
  ///
  /// 폭을 화면에 맞추되 **세로가 넘치지 않도록 한 번 더 줄인다** — 라벨·선·캡션이
  /// 먼저 자리를 잡아야 하고, 글자 배율을 키운 기기에서는 그 높이가 커진다.
  Widget? _photo(BuildContext context) {
    if (widget.photoAssets.isEmpty) return null;
    final screen = MediaQuery.sizeOf(context);
    final side = math.min(
      screen.width - 2 * _photoMargin,
      screen.height - _columnHeightBudget,
    );
    if (side <= 0) return null;
    final entered = _photoIn.value;
    return Opacity(
      opacity: entered,
      child: Transform.translate(
        offset: Offset(
          0,
          (1 - entered) * _photoSlide * (widget.state.goingUp ? 1 : -1),
        ),
        child: _FloorPhotoStrip(
          assets: widget.photoAssets,
          side: side,
          running: widget.animating,
        ),
      ),
    );
  }

  /// 사진을 뺀 나머지(라벨 둘·선·캡션·점 줄·간격)가 쓰는 세로. 사진이 이만큼은
  /// 남겨야 카드가 화면 밖으로 밀리지 않는다.
  static const _columnHeightBudget = 285.0;

  Widget _build(BuildContext context, double progress) {
    final scheme = Theme.of(context).colorScheme;
    final state = widget.state;
    // 출발 층이 늘 **점이 떠나는 쪽**이다. 내려갈 때는 위, 올라갈 때는 아래.
    final topLabel = state.goingUp ? state.toFloorLabel : state.fromFloorLabel;
    final bottomLabel = state.goingUp
        ? state.fromFloorLabel
        : state.toFloorLabel;

    // 점이 도착 쪽에 가까워질수록 강조가 넘어간다. 라벨 색이 이동과 함께
    // 변해야 "지금 어디로 가는 중"이 한 그림으로 읽힌다.
    final arriving = Curves.easeInOut.transform(progress);
    final topWeight = state.goingUp ? arriving : 1 - arriving;

    // 캡션은 **가는 방향 쪽**에 붙인다. 내려가는데 글이 위에 있으면 시선이
    // 점과 반대로 끌려간다.
    final caption = Text(
      state.detail,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: scheme.onSurface.withValues(alpha: 0.6),
      ),
    );

    // 사진은 **도착 층 라벨 쪽에** 붙는다. 캡션을 가는 방향에 붙이는 것과 같은
    // 이유다 — 지금 가는 곳과 그곳의 사진이 화면 반대편에 있으면 둘이 한 사건으로
    // 안 읽힌다.
    final photo = _photo(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (photo != null && state.goingUp) ...[
          photo,
          const SizedBox(height: _photoGap),
        ],
        if (state.goingUp) ...[caption, const SizedBox(height: 14)],
        _FloorLabel(label: topLabel, emphasis: topWeight, scheme: scheme),
        SizedBox(
          height: _lineHeight,
          width: 2 * _markerRimRadius,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              // 선은 항상 같은 자리에 옅게 깔려 있다. 지나온 구간을 따로
              // 칠하지 않는 이유는, 이 점이 곧 마커라 "지나온 길"이 아니라
              // "지금 어디"만 말하면 되기 때문이다.
              Container(
                width: 1.5,
                height: _lineHeight,
                color: scheme.onSurface.withValues(alpha: 0.18),
              ),
              Positioned(
                // 위에서 아래로 내려갈 때 progress가 곧 화면 아래 방향이다.
                top:
                    (state.goingUp ? 1 - arriving : arriving) *
                    (_lineHeight - 2 * _markerRimRadius),
                child: const _MarkerDot(key: Key('floor-transition-dot')),
              ),
            ],
          ),
        ),
        _FloorLabel(
          label: bottomLabel,
          emphasis: 1 - topWeight,
          scheme: scheme,
        ),
        if (!state.goingUp) ...[const SizedBox(height: 14), caption],
        if (photo != null && !state.goingUp) ...[
          const SizedBox(height: _photoGap),
          photo,
        ],
      ],
    );
  }
}

/// 지도 위 현재 위치 마커와 **같은 그림**의 점.
///
/// 크기·색을 마커와 맞춰야 덮개가 마커를 가져온 것으로 읽힌다. 값의 출처는
/// [kLocationMarkerCoreRadiusPx]·[kLocationMarkerRimRadiusPx]로, 지도가 아이콘을
/// 그릴 때 쓰는 것과 같은 상수다 — 한쪽만 바꾸면 두 점의 크기가 어긋난다.
class _MarkerDot extends StatelessWidget {
  const _MarkerDot({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 2 * _markerRimRadius,
      height: 2 * _markerRimRadius,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        // 지도 아이콘의 그림자와 **같은 무게**로 맞춘다. 아이콘은 2배 캔버스에
        // 그려 절반으로 축소되므로, 캔버스에서 blur 5 / offset 2인 그림자가
        // 화면에서는 blur 2.5 / offset 1이 된다. 여기에 원래 값을 그대로 쓰면
        // 점이 한 겹 더 두꺼워 보이고, 그게 "덮개 점이 더 크다"로 읽힌다.
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 2.5,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 2 * kLocationMarkerCoreRadiusPx,
          height: 2 * kLocationMarkerCoreRadiusPx,
          decoration: const BoxDecoration(
            color: kLocationMarkerColor,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

const _markerRimRadius = kLocationMarkerRimRadiusPx;

/// 층 라벨 한 개. [emphasis] 1이면 도착 층(포인트 파랑·큼), 0이면 지나온 층
/// (옅은 회색·작음)이다. 그 사이를 연속으로 오간다.
class _FloorLabel extends StatelessWidget {
  const _FloorLabel({
    required this.label,
    required this.emphasis,
    required this.scheme,
  });

  final String label;
  final double emphasis;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final t = emphasis.clamp(0.0, 1.0);
    return Text(
      label,
      style: TextStyle(
        fontSize: 20 + 10 * t,
        fontWeight: FontWeight.w800,
        color: Color.lerp(
          scheme.onSurface.withValues(alpha: 0.35),
          AppColors.primary,
          t,
        ),
      ),
    );
  }
}

/// 도착 층 사진 여러 장. 스스로 넘어가고, 사람이 넘길 수도 있다.
///
/// **액자는 고정이고 사진만 바뀐다.** 정사각 액자를 두고 안에서만 갈아 끼워야
/// "같은 곳을 여러 각도로 본다"로 읽힌다. 사진마다 높이가 달라지면 그 아래 층
/// 라벨과 점이 매번 밀려, 넘어가는 것이 사진인지 화면인지 알 수 없다.
///
/// 원본 비율이 층마다 다르다(키비주얼은 정사각, 공간 사진은 3:2·세로 9:16).
/// 액자를 채우고 남는 쪽을 덮는다 — 비율을 살리면 액자에 여백이 생겨 사진이
/// 바뀔 때마다 여백 모양이 달라진다.
class _FloorPhotoStrip extends StatefulWidget {
  const _FloorPhotoStrip({
    required this.assets,
    required this.side,
    required this.running,
  });

  final List<String> assets;
  final double side;

  /// 덮개가 떠 있는 동안만 true. 걷히면 자동 넘김을 멈춘다.
  final bool running;

  @override
  State<_FloorPhotoStrip> createState() => _FloorPhotoStripState();
}

class _FloorPhotoStripState extends State<_FloorPhotoStrip> {
  /// 한 장이 머무는 시간. **덮개를 붙잡는 시간에서 거꾸로 나온다**
  /// ([floorPhotoDwellFor]) — 따로 두면 마지막 장이 뜨기 전에 덮개가 걷히거나,
  /// 다 넘긴 뒤로 빈 시간이 남는다.
  Duration get _dwell => floorPhotoDwellFor(widget.assets.length);
  static const _slide = Duration(milliseconds: 420);

  final _controller = PageController();
  Timer? _timer;
  int _index = 0;

  /// 사람이 한 번이라도 넘겼는가. **넘긴 순간 자동 넘김을 놓는다** — 보고 있는
  /// 사진을 앱이 뺏어 가면 다시 돌아오는 방법이 없다.
  bool _taken = false;

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  /// **새 전환이면 첫 장으로 되돌린다.**
  ///
  /// 이 위젯은 층 전환 사이에 살아남는다 — 앞 전환에서 두 번째 장까지 넘어간
  /// 채였으면 다음 전환이 두 번째 장에서 시작한다. 실기기에서 "어떨 때는 1번,
  /// 어떨 때는 2번부터 뜬다"로 보인 것이 이것이다(2026-08-22). 사진 목록이
  /// 바뀌었거나 덮개가 다시 올라오는 것이 곧 새 전환이다.
  @override
  void didUpdateWidget(covariant _FloorPhotoStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newRun = widget.running && !oldWidget.running;
    if (newRun || !listEquals(widget.assets, oldWidget.assets)) {
      _taken = false;
      if (_controller.hasClients && _controller.page != 0) {
        _controller.jumpToPage(0);
      }
      if (_index != 0) setState(() => _index = 0);
      _restartTimer();
      return;
    }
    if (widget.running != oldWidget.running) _restartTimer();
  }

  /// 첫 장만 **등장이 끝난 뒤부터** 센다. 덮개가 짙어지고(0.52초) 사진이
  /// 미끄러져 들어오는(0.36초) 동안은 아직 보고 있는 시간이 아니다 — 그만큼을
  /// 안 빼면 첫 장만 1.3초 만에 지나가, 실기기에서 "첫 장을 아예 안 보여 준다"로
  /// 보였다.
  void _restartTimer() {
    _timer?.cancel();
    _timer = null;
    if (!widget.running || _taken || widget.assets.length < 2) return;
    _timer = Timer(floorPhotoSettled + _dwell, () {
      _advance();
      if (!mounted) return;
      _timer = Timer.periodic(_dwell, (_) => _advance());
    });
  }

  void _advance() {
    if (!mounted) return;
    final next = _index + 1;
    // **되감지 않는다.** 마지막 장에서 처음으로 돌아가면 덮개가 걷히기 직전에
    // 같은 사진이 두 번 지나가, 몇 장이었는지가 흐려진다.
    if (next >= widget.assets.length) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _controller.animateToPage(next, duration: _slide, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // **액자 테두리를 보이게 긋는다.** 바닥을 깔아도 액자가 흰 화면 위의
        // 흰 사각이라 경계가 안 보였고, 키비주얼은 아래 3분의 1이 투명이라
        // 그 장만 사진이 더 짧게 끝난 것처럼 읽혔다 — 넘길 때 액자가 커졌다
        // 작아지는 것으로 보인 원인이다(2026-08-22 실기기).
        DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.hairline),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox.square(
              dimension: widget.side,
              child: Listener(
                // 손가락이 닿는 순간 놓는다. PageView의 onPageChanged로는 자동
                // 넘김과 손 넘김을 가릴 수 없다.
                onPointerDown: (_) {
                  if (_taken) return;
                  _taken = true;
                  _restartTimer();
                },
                child: PageView.builder(
                  controller: _controller,
                  itemCount: widget.assets.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  // **액자 바닥을 깔아 준다.** 키비주얼은 컨셉 글자가 놓인 아래
                  // 3분의 1이 투명이라, 안 깔면 그 장만 액자 밖으로 흘러나온 것처럼
                  // 보인다. 옆으로 넘길 때 사진의 아래 끝이 장마다 달라져 액자가
                  // 흔들리는 것으로 읽혔다(2026-08-22 실기기).
                  // 장마다 [RepaintBoundary]로 끊는다. 안 끊으면 한 장이
                  // 미끄러지는 동안 액자·테두리·점까지 매 프레임 다시 그린다.
                  //
                  // 원본이 화면보다 작아(828~870px → 1026px) 늘려 그리므로 보간
                  // 품질을 한 단계 올린다. 기본값(low)은 정지 화면에서는 티가
                  // 안 나지만 움직이는 동안 가장자리가 자글거린다.
                  itemBuilder: (context, i) => RepaintBoundary(
                    child: ColoredBox(
                      color: scheme.surface,
                      child: Image.asset(
                        widget.assets[i],
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (widget.assets.length > 1) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.assets.length; i++)
                Container(
                  key: Key('floor-photo-dot-$i'),
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _index
                        ? AppColors.primary
                        : scheme.onSurface.withValues(alpha: 0.22),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
