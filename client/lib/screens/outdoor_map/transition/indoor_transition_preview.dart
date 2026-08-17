/// 전환 연출을 **지도 없이** 눈으로 확인하는 하네스.
///
/// MapLibre도 GPS도 없이 가짜 지도 위에 실제 오버레이([IndoorTransitionOverlay])를
/// 얹는다 — 곡선을 고치려고 건물을 드나들 수는 없기 때문이다.
///
/// 엔트리포인트는 `lib/indoor_transition_preview_main.dart`.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import 'indoor_transition_overlay.dart';
import 'indoor_transition_timeline.dart';

/// 미리보기 화면. 두 방향을 **동시에 띄운다** — 하나씩 보면 "이탈이 진입보다
/// 빠르다" 같은 관계를 눈으로 못 잡는다.
class IndoorTransitionPreview extends StatefulWidget {
  const IndoorTransitionPreview({super.key});

  @override
  State<IndoorTransitionPreview> createState() =>
      _IndoorTransitionPreviewState();
}

class _IndoorTransitionPreviewState extends State<IndoorTransitionPreview> {
  /// 재생 배속. 어색한 지점은 1배속에서 눈에 안 띄어서 느리게 볼 수단이 필요하다.
  double _speed = 1;

  final _enterKey = GlobalKey<_TransitionCardState>();
  final _exitKey = GlobalKey<_TransitionCardState>();

  void _playBoth() {
    _enterKey.currentState?.play();
    _exitKey.currentState?.play();
  }

  @override
  Widget build(BuildContext context) {
    final cards = [
      _TransitionCard(
        key: _enterKey,
        title: '야외 → 실내 진입',
        subtitle: '왼쪽 경첩 · 당겨서 열림',
        direction: IndoorTransitionDirection.enter,
        speed: _speed,
      ),
      _TransitionCard(
        key: _exitKey,
        title: '실내 → 야외 이탈',
        subtitle: '왼쪽 경첩 · 바깥쪽으로 열림',
        direction: IndoorTransitionDirection.exit,
        speed: _speed,
      ),
    ];
    return Scaffold(
      backgroundColor: const Color(0xFF10141A),
      appBar: AppBar(
        title: const Text('실내 전환 연출 미리보기'),
        backgroundColor: const Color(0xFF181E26),
        foregroundColor: Colors.white,
        actions: [
          for (final speed in [1.0, 0.5, 0.25])
            TextButton(
              onPressed: () => setState(() => _speed = speed),
              child: Text(
                speed == 1 ? '1x' : '${speed}x',
                style: TextStyle(
                  color: _speed == speed ? Colors.tealAccent : Colors.white54,
                ),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _playBoth,
        icon: const Icon(Icons.play_arrow),
        label: const Text('둘 다 재생'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // 좁은 화면에서 가로로 두면 무대가 납작해져 카메라 이동이 안 보인다.
          final wide = constraints.maxWidth >= 720;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: 12),
                      Expanded(child: cards[1]),
                    ],
                  )
                : Column(
                    children: [
                      cards[0],
                      const SizedBox(height: 12),
                      cards[1],
                    ],
                  ),
          );
        },
      ),
    );
  }
}

/// 무대 하나 — 제목, 그림, 스크럽 슬라이더.
class _TransitionCard extends StatefulWidget {
  const _TransitionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.direction,
    required this.speed,
  });

  final String title;
  final String subtitle;
  final IndoorTransitionDirection direction;
  final double speed;

  @override
  State<_TransitionCard> createState() => _TransitionCardState();
}

class _TransitionCardState extends State<_TransitionCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: indoorTransitionDuration(widget.direction),
  );

  void play() {
    _controller.duration =
        indoorTransitionDuration(widget.direction) * (1 / widget.speed);
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ms = indoorTransitionDuration(widget.direction).inMilliseconds;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF181E26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '${widget.subtitle} · ${ms}ms',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: play,
                  icon: const Icon(Icons.play_arrow),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = _controller.value;
                // 화면 교체는 덮개가 다 덮인 순간에 일어난다. 실제 화면도 같은
                // 시점에 상태를 바꾼다([indoorTransitionSwapDelay]).
                final swapped = t >= indoorTransitionVeilIn.end;
                final indoor = widget.direction ==
                        IndoorTransitionDirection.enter
                    ? swapped
                    : !swapped;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: FakeMapPainter(indoor: indoor),
                              ),
                            ),
                            Positioned.fill(
                              child: IndoorTransitionOverlay(
                                progress: t,
                                direction: widget.direction,
                                buildingName: '더현대 서울',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Slider(
                      value: t,
                      onChanged: (v) {
                        _controller.stop();
                        _controller.value = v;
                      },
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 가짜 지도 두 상태 — 야외(건물 옅은 fill + GPS 점)와 실내(층 도면 + 실내 마커).
///
/// 실제 지도가 아니라 **연출을 판단할 배경**이다. 덮개가 걷힌 순간 화면이 이미
/// 바뀌어 있는지를 눈으로 확인하는 것이 목적이라, 이 이상 정교할 필요가 없다.
class FakeMapPainter extends CustomPainter {
  const FakeMapPainter({required this.indoor});

  final bool indoor;

  static const _building = Rect.fromLTRB(-0.42, -0.30, 0.42, 0.30);
  static const _gpsPoint = Offset(0.02, 0.46);
  static const _indoorPoint = Offset(-0.04, 0.16);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFE8E4DC),
    );
    // 야외는 사용자를 중앙에 두고 넓게, 실내는 건물을 중앙에 두고 확대. 배율은
    // 건물 폭(0.84 월드 단위)에서 거꾸로 잡았다 — 더 당기면 외곽선이 화면 밖이다.
    final unit = math.min(size.width, size.height);
    final scale = (indoor ? 0.95 : 0.52) * unit;
    final focus = indoor ? _building.center : _gpsPoint;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-focus.dx, -focus.dy);

    final road = Paint()
      ..color = Colors.white
      ..strokeWidth = 0.055
      ..strokeCap = StrokeCap.round;
    for (final y in [-0.62, 0.62]) {
      canvas.drawLine(Offset(-1.6, y), Offset(1.6, y), road);
    }
    for (final x in [-0.86, 0.86]) {
      canvas.drawLine(Offset(x, -1.6), Offset(x, 1.6), road);
    }

    if (!indoor) {
      canvas.drawRect(
        _building,
        Paint()..color = AppColors.indoor.withValues(alpha: 0.22),
      );
    }
    canvas.drawRect(
      _building,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.008
        ..color = AppColors.blue600.withValues(alpha: indoor ? 0.85 : 0.3),
    );

    if (indoor) {
      for (final row in [-0.22, 0.10]) {
        for (var i = 0; i < 5; i++) {
          final rect = Rect.fromLTWH(-0.38 + i * 0.155, row, 0.135, 0.12);
          canvas.drawRect(rect, Paint()..color = Colors.white);
          canvas.drawRect(
            rect,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.006
              ..color = AppColors.blue200,
          );
        }
      }
      canvas.drawRect(
        const Rect.fromLTRB(-0.38, -0.08, 0.38, 0.08),
        Paint()..color = AppColors.blue50,
      );
      final outer = Path()..addRect(const Rect.fromLTRB(-4, -4, 4, 4));
      final hole = Path()..addRect(_building);
      canvas.drawPath(
        Path.combine(PathOperation.difference, outer, hole),
        Paint()..color = Colors.black.withValues(alpha: 0.42),
      );
      const r = 0.020;
      canvas.drawCircle(
        _indoorPoint,
        r + 0.006,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(_indoorPoint, r, Paint()..color = AppColors.blue600);
      canvas.drawPath(
        Path()
          ..moveTo(_indoorPoint.dx, _indoorPoint.dy - r - 0.028)
          ..lineTo(_indoorPoint.dx - 0.014, _indoorPoint.dy - r - 0.006)
          ..lineTo(_indoorPoint.dx + 0.014, _indoorPoint.dy - r - 0.006)
          ..close(),
        Paint()..color = AppColors.blue600,
      );
    } else {
      canvas.drawCircle(
        _gpsPoint,
        0.075,
        Paint()..color = AppColors.primary.withValues(alpha: 0.18),
      );
      canvas.drawCircle(_gpsPoint, 0.020, Paint()..color = Colors.white);
      canvas.drawCircle(_gpsPoint, 0.015, Paint()..color = AppColors.primary);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(FakeMapPainter oldDelegate) =>
      oldDelegate.indoor != indoor;
}
