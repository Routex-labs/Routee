/// 진입·이탈 전환 연출을 **지도 없이** 눈으로 확인하는 하네스.
///
/// MapLibre도 GPS도 없이 [indoorTransitionFrameAt]이 만든 값만 그린다 — 곡선을
/// 고치려고 건물을 드나들 수는 없기 때문이다. `pdr_device_harness`와 같은 자리다.
///
/// 엔트리포인트는 `lib/indoor_transition_preview_main.dart`.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'indoor_transition_timeline.dart';

/// `lerpDouble`은 nullable을 돌려줘 호출마다 `!`가 붙는다. 이 파일용 껍데기다.
double _lerp(double a, double b, double t) => a + (b - a) * t;

/// 미리보기 화면. 두 방향을 **동시에 띄운다** — 하나씩 보면 "진입이 이탈보다
/// 느리다" 같은 관계를 눈으로 못 잡는다.
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
        subtitle: '카메라가 먼저, 위치 아이콘이 나중',
        direction: IndoorTransitionDirection.enter,
        speed: _speed,
      ),
      _TransitionCard(
        key: _exitKey,
        title: '실내 → 야외 이탈',
        subtitle: '위치 아이콘이 먼저, 카메라가 나중',
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
                '${speed == 1 ? '1' : speed.toString().substring(1)}x',
                style: TextStyle(
                  color: _speed == speed ? Colors.tealAccent : Colors.white54,
                  fontWeight: _speed == speed
                      ? FontWeight.w700
                      : FontWeight.w400,
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
          // 좁은 화면에서 가로로 두면 무대가 너무 납작해져 카메라 이동이 안 보인다.
          final wide = constraints.maxWidth >= 720;
          final children = [
            for (final card in cards)
              wide ? Expanded(child: card) : Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: card,
              ),
          ];
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      children[0],
                      const SizedBox(width: 12),
                      children[1],
                    ],
                  )
                : Column(children: children),
          );
        },
      ),
    );
  }
}

/// 무대 하나 — 제목, 그림, 스크럽 슬라이더, 값 표시.
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
    duration: _baseDuration,
  );

  Duration get _baseDuration =>
      widget.direction == IndoorTransitionDirection.enter
      ? indoorEnterTransitionDuration
      : indoorExitTransitionDuration;

  void play() {
    _controller.duration = _baseDuration * (1 / widget.speed);
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${widget.subtitle} · ${_baseDuration.inMilliseconds}ms',
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
                final frame = indoorTransitionFrameAt(
                  _controller.value,
                  direction: widget.direction,
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 1.15,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: CustomPaint(
                          painter: IndoorTransitionStagePainter(frame),
                          size: Size.infinite,
                        ),
                      ),
                    ),
                    Slider(
                      value: _controller.value,
                      onChanged: (v) {
                        _controller.stop();
                        _controller.value = v;
                      },
                    ),
                    _MeterRow('카메라', frame.cameraProgress),
                    _MeterRow('바깥 어둠', frame.scrimOpacity),
                    _MeterRow('층 도면', frame.floorPlanOpacity),
                    _MeterRow('건물 fill', frame.buildingFillOpacity),
                    _MeterRow('GPS 점', frame.gpsMarkerOpacity),
                    _MeterRow('실내 마커', frame.indoorMarkerOpacity),
                    const Divider(color: Colors.white12, height: 18),
                    // 이 줄이 이 하네스의 존재 이유다 — 0에 닿으면 사용자는 그
                    // 순간 "앱이 내 위치를 잃었다"고 읽는다.
                    _MeterRow(
                      '위치 아이콘(둘 중 진한 쪽)',
                      frame.anyLocationMarkerOpacity,
                      warnBelow: 0.2,
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

/// 값 하나를 막대로 보여 준다. [warnBelow] 아래로 내려가면 빨갛게 물든다.
class _MeterRow extends StatelessWidget {
  const _MeterRow(this.label, this.value, {this.warnBelow});

  final String label;
  final double value;
  final double? warnBelow;

  @override
  Widget build(BuildContext context) {
    final warn = warnBelow != null && value < warnBelow!;
    final color = warn ? Colors.redAccent : Colors.tealAccent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: value.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: Colors.white10,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              value.toStringAsFixed(2),
              textAlign: TextAlign.right,
              style: TextStyle(color: color, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

/// 한 프레임을 가짜 지도로 그린다.
///
/// 좌표는 무대 짧은 변을 1로 본 **월드 단위**이고, 카메라(확대·이동)를 canvas
/// 변환으로 한 번에 건다. 배경 도로를 함께 그리는 이유는 **카메라가 움직였다는
/// 것을 그것으로만 알 수 있기 때문**이다 — 건물만 있으면 확대와 이동이 구분되지
/// 않는다.
class IndoorTransitionStagePainter extends CustomPainter {
  const IndoorTransitionStagePainter(this.frame);

  final IndoorTransitionFrame frame;

  /// 건물 크기(월드 단위)와 문·사용자 위치. 더현대 서울처럼 가로로 넓은 건물이다.
  static const _building = Rect.fromLTRB(-0.42, -0.30, 0.42, 0.30);
  static const _door = Offset(0, 0.30);
  static const _gpsPoint = Offset(0.02, 0.46);
  static const _indoorPoint = Offset(-0.04, 0.16);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFE8E4DC),
    );

    // 카메라 — 야외는 사용자를 중앙에 두고 넓게, 실내는 건물을 중앙에 두고 확대.
    //
    // 두 배율은 **건물 폭(0.84 월드 단위)에서 거꾸로 잡았다.** 야외는 건물이
    // 화면 폭의 절반쯤(주변 길이 같이 보임), 실내는 8할쯤(바깥 어둠이 테두리로
    // 남음). 실내를 더 당기면 외곽선도 scrim도 화면 밖으로 나가 연출이 통째로
    // 안 보인다 — 실제로 2.15로 잡았다가 그렇게 됐다.
    final unit = math.min(size.width, size.height);
    final scale = _lerp(0.52, 0.95, frame.cameraProgress) * unit;
    final focus = Offset.lerp(_gpsPoint, _building.center, frame.cameraProgress)!;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-focus.dx, -focus.dy);

    _paintRoads(canvas);
    _paintBuilding(canvas);
    _paintFloorPlan(canvas);
    _paintScrim(canvas);
    _paintMarkers(canvas, scale);
    canvas.restore();
  }

  void _paintRoads(Canvas canvas) {
    final road = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = 0.055
      ..strokeCap = StrokeCap.round;
    for (final y in [-0.62, 0.62]) {
      canvas.drawLine(Offset(-1.6, y), Offset(1.6, y), road);
    }
    for (final x in [-0.86, 0.86]) {
      canvas.drawLine(Offset(x, -1.6), Offset(x, 1.6), road);
    }
  }

  void _paintBuilding(Canvas canvas) {
    final rrect = RRect.fromRectAndRadius(
      _building,
      const Radius.circular(0.02),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        // 야외 지도의 건물 fill 기본값(0.15)에 맞춘다 — 진하게 두면 진입 전부터
        // 건물이 "이미 켜진" 것처럼 보여 연출이 뭘 바꿨는지 안 읽힌다.
        ..color = const Color(
          0xFF4A6FA5,
        ).withValues(alpha: 0.18 * frame.buildingFillOpacity),
    );
    // 외곽선은 진입할수록 진해진다 — 도면이 켜지면 이 선이 "층 경계"가 된다.
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.008
        ..color = const Color(0xFF2F4B73).withValues(
          alpha: 0.25 + 0.55 * frame.floorPlanOpacity,
        ),
    );
  }

  void _paintFloorPlan(Canvas canvas) {
    final alpha = frame.floorPlanOpacity;
    if (alpha <= 0.01) return;
    final store = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.92 * alpha);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.006
      ..color = const Color(0xFFBFC7D2).withValues(alpha: alpha);
    // 위·아래 두 줄의 매장과 그 사이 복도. 실제 도면의 최소 형태다.
    for (final row in [-0.22, 0.10]) {
      for (var i = 0; i < 5; i++) {
        final rect = Rect.fromLTWH(-0.38 + i * 0.155, row, 0.135, 0.12);
        canvas.drawRect(rect, store);
        canvas.drawRect(rect, stroke);
      }
    }
    canvas.drawRect(
      const Rect.fromLTRB(-0.38, -0.08, 0.38, 0.08),
      Paint()..color = const Color(0xFFF3F1EC).withValues(alpha: 0.9 * alpha),
    );
    // 출입구 — 이 연출에서 사용자가 지나는 지점이라 눈에 띄어야 한다.
    canvas.drawCircle(
      _door,
      0.022,
      Paint()..color = const Color(0xFF2F8F6B).withValues(alpha: alpha),
    );
  }

  void _paintScrim(Canvas canvas) {
    if (frame.scrimOpacity <= 0.01) return;
    final outer = Path()..addRect(const Rect.fromLTRB(-4, -4, 4, 4));
    final hole = Path()
      ..addRRect(
        RRect.fromRectAndRadius(_building, const Radius.circular(0.02)),
      );
    canvas.drawPath(
      Path.combine(PathOperation.difference, outer, hole),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.42 * frame.scrimOpacity),
    );
  }

  void _paintMarkers(Canvas canvas, double scale) {
    if (frame.gpsMarkerOpacity > 0.01) {
      final a = frame.gpsMarkerOpacity;
      canvas.drawCircle(
        _gpsPoint,
        0.075,
        Paint()..color = const Color(0xFF1E88E5).withValues(alpha: 0.18 * a),
      );
      canvas.drawCircle(
        _gpsPoint,
        0.020,
        Paint()..color = Colors.white.withValues(alpha: a),
      );
      canvas.drawCircle(
        _gpsPoint,
        0.015,
        Paint()..color = const Color(0xFF1E88E5).withValues(alpha: a),
      );
    }
    if (frame.indoorMarkerOpacity > 0.01) {
      final a = frame.indoorMarkerOpacity;
      // 자리를 잡은 뒤 자라난다 — 근사 자리에 먼저 세우면 그게 곧 순간이동이다.
      final r = 0.020 * (0.55 + 0.45 * a);
      canvas.drawCircle(
        _indoorPoint,
        r + 0.006,
        Paint()..color = Colors.white.withValues(alpha: a),
      );
      canvas.drawCircle(
        _indoorPoint,
        r,
        Paint()..color = const Color(0xFF00A28A).withValues(alpha: a),
      );
      final arrow = Path()
        ..moveTo(_indoorPoint.dx, _indoorPoint.dy - r - 0.028)
        ..lineTo(_indoorPoint.dx - 0.014, _indoorPoint.dy - r - 0.006)
        ..lineTo(_indoorPoint.dx + 0.014, _indoorPoint.dy - r - 0.006)
        ..close();
      canvas.drawPath(
        arrow,
        Paint()..color = const Color(0xFF00A28A).withValues(alpha: a),
      );
    }
  }

  // 프레임은 매 tick마다 새로 만들어지므로 값 비교를 해 봐야 항상 다르다.
  @override
  bool shouldRepaint(IndoorTransitionStagePainter oldDelegate) => true;
}
