/// 층별 고도표를 현장에서 찍는 화면. 값을 모으는 쪽은
/// [ElevatorAltitudeProbe]이고 여기는 그것을 보여 주고 찍게만 한다.
///
/// **한 손으로, 엘리베이터 안에서 쓴다.** 그래서 층 고르기가 드롭다운이 아니라
/// 큰 버튼 격자다 — 문이 열린 몇 초 안에 한 번 눌러야 한다.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../indoor_navigation/debug/elevator_altitude_probe.dart';

/// 측정 화면을 띄운다. 닫으면 녹화가 멈춘다.
Future<void> showElevatorAltitudeSheet(
  BuildContext context, {
  required ElevatorAltitudeProbe probe,
  required List<String> floors,
  required Future<void> Function(Rect? origin) onShare,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // 지도를 볼 일이 없는 화면이라 높이를 크게 잡는다 — 층 버튼과 찍은 목록이
    // 함께 보여야 "몇 층을 아직 안 찍었나"를 알 수 있다.
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.9,
    ),
    builder: (context) => _ElevatorAltitudeSheet(
      probe: probe,
      floors: floors,
      onShare: onShare,
    ),
  );
}

class _ElevatorAltitudeSheet extends StatefulWidget {
  const _ElevatorAltitudeSheet({
    required this.probe,
    required this.floors,
    required this.onShare,
  });

  final ElevatorAltitudeProbe probe;
  final List<String> floors;
  final Future<void> Function(Rect? origin) onShare;

  @override
  State<_ElevatorAltitudeSheet> createState() => _ElevatorAltitudeSheetState();
}

class _ElevatorAltitudeSheetState extends State<_ElevatorAltitudeSheet> {
  /// 샘플은 최대 5Hz로 들어오지만 **화면은 그렇게 자주 안 고친다.** 읽는 사람이
  /// 따라올 수 없고, 숫자가 흔들려서 오히려 언제 멈췄는지 알기 어렵다.
  static const _refreshInterval = Duration(milliseconds: 250);

  Timer? _ticker;
  final _shareButtonKey = GlobalKey();
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    widget.probe.start();
    _ticker = Timer.periodic(_refreshInterval, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    // **세션은 지우지 않고 녹화만 멈춘다.** 시트를 닫았다 다시 열어 이어 찍는
    // 것이 정상 사용이다 — 층을 오가는 사이에 지도를 봐야 할 때가 있다.
    widget.probe.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final probe = widget.probe;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              contentPadding: EdgeInsets.symmetric(horizontal: 4),
              leading: Icon(Icons.elevator_outlined),
              title: Text(
                '엘리베이터 고도 측정',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text('층마다 멈춰 서서 그 층 버튼을 누르세요. 기준 층은 마지막에 한 번 더 누릅니다.'),
            ),
            _LiveReadout(probe: probe),
            const SizedBox(height: 12),
            _FloorButtons(
              floors: widget.floors,
              onPick: (floor) {
                final mark = probe.mark(floor);
                setState(() {});
                if (!mounted) return;
                final messenger = ScaffoldMessenger.maybeOf(context);
                messenger?.hideCurrentSnackBar();
                messenger?.showSnackBar(
                  SnackBar(
                    duration: const Duration(milliseconds: 1200),
                    content: Text(
                      mark == null
                          ? '기압 샘플이 아직 없습니다'
                          : mark.settled
                          ? '$floor 기록 ${mark.smoothedAltitudeM.toStringAsFixed(2)}m'
                          : '$floor 기록 — 아직 움직이는 중이라 표에서 빠집니다',
                    ),
                  ),
                );
              },
            ),
            const Divider(height: 24),
            _FloorTable(probe: probe),
            const Divider(height: 24),
            _MarkList(
              probe: probe,
              onRemove: (index) => setState(() => probe.removeMarkAt(index)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: _shareButtonKey,
                    onPressed: probe.marks.isEmpty || _sharing
                        ? null
                        : () => unawaited(_share()),
                    icon: _sharing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.ios_share_rounded, size: 18),
                    label: const Text('JSON 공유'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: probe.marks.isEmpty
                      ? null
                      : () => unawaited(_confirmReset()),
                  child: const Text('초기화'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      await widget.onShare(_shareOrigin());
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// iPad 공유 팝오버가 설 자리. 못 재면 null이고 시스템 기본 위치로 뜬다.
  Rect? _shareOrigin() {
    final box = _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// **되돌릴 수 없으니 한 번 묻는다.** 층을 열두 개 찍은 뒤 잘못 눌러 전부
  /// 날리면 그 세션을 통째로 다시 걸어야 한다.
  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('측정을 초기화할까요?'),
        content: Text('찍은 점 ${widget.probe.marks.length}개와 원시 샘플이 모두 지워집니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('초기화'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      widget.probe.reset();
      widget.probe.start();
    });
  }
}

/// 지금 값. **정지 표시가 이 화면에서 가장 중요한 한 줄이다** — 움직이는 중에
/// 찍은 점은 그 층의 고도가 아니라 지나가는 중의 고도라 표에서 빠진다.
class _LiveReadout extends StatelessWidget {
  const _LiveReadout({required this.probe});

  final ElevatorAltitudeProbe probe;

  @override
  Widget build(BuildContext context) {
    final latest = probe.latest;
    final smoothed = probe.smoothedAltitudeM;
    final speed = probe.verticalSpeedMps;
    if (latest == null || smoothed == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Text('기압 샘플을 기다리는 중… (기압계가 없는 기기면 영영 안 옵니다)'),
      );
    }
    final settled = probe.isSettled;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: settled
            ? const Color(0xFF1B5E20).withValues(alpha: 0.08)
            : const Color(0xFFE65100).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                settled ? Icons.check_circle_outline : Icons.swap_vert_rounded,
                size: 18,
                color: settled
                    ? const Color(0xFF1B5E20)
                    : const Color(0xFFE65100),
              ),
              const SizedBox(width: 6),
              Text(
                settled ? '멈춰 있음 — 지금 찍으세요' : '움직이는 중',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: settled
                      ? const Color(0xFF1B5E20)
                      : const Color(0xFFE65100),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '고도 ${smoothed.toStringAsFixed(2)} m   '
            '(원시 ${latest.altitudeM.toStringAsFixed(2)})\n'
            '기압 ${latest.pressureHpa.toStringAsFixed(2)} hPa   '
            '수직속도 ${(speed ?? 0).toStringAsFixed(3)} m/s\n'
            '샘플 ${probe.sampleCount}개   경과 ${_mmss(probe.elapsedMs)}',
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _FloorButtons extends StatelessWidget {
  const _FloorButtons({required this.floors, required this.onPick});

  final List<String> floors;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    if (floors.isEmpty) {
      return const Text('건물 층 목록이 없습니다. 건물 안에서 열어주세요.');
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final floor in floors)
          SizedBox(
            width: 64,
            height: 48,
            child: OutlinedButton(
              key: ValueKey('elevator-probe-floor-$floor'),
              style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () => onPick(floor),
              child: Text(floor, style: const TextStyle(fontSize: 13)),
            ),
          ),
      ],
    );
  }
}

/// 지금까지 나온 표. **인접 층 Δ가 이 측정의 결과물이다.**
class _FloorTable extends StatelessWidget {
  const _FloorTable({required this.probe});

  final ElevatorAltitudeProbe probe;

  @override
  Widget build(BuildContext context) {
    final rows = probe.floorSummary;
    if (rows.isEmpty) {
      return const Text(
        '아직 표가 없습니다. 멈춘 상태에서 층 버튼을 누르면 한 줄씩 쌓입니다.',
        style: TextStyle(fontSize: 12),
      );
    }
    final base = rows.first.meanAltitudeM;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('층별 표', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '${rows[i].floorLabel.padRight(4)} '
              '기준+${(rows[i].meanAltitudeM - base).toStringAsFixed(2)}m   '
              '${i == 0 ? '—' : 'Δ${(rows[i].meanAltitudeM - rows[i - 1].meanAltitudeM).toStringAsFixed(2)}m'}'
              '   n=${rows[i].count}'
              '${rows[i].spreadM > 0 ? '  흔들림 ${rows[i].spreadM.toStringAsFixed(2)}m' : ''}',
              style: const TextStyle(
                fontSize: 12,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        const SizedBox(height: 6),
        // 같은 층 재방문이 벌어진 폭이 곧 드리프트다. 층고(4~6m)에 가까워지면
        // 그 세션의 표는 못 믿는다 — 다시 재야 한다.
        Text(
          _driftNote(rows),
          style: const TextStyle(fontSize: 11, color: Color(0xFF616161)),
        ),
      ],
    );
  }

  String _driftNote(List<ElevatorFloorSummary> rows) {
    final worst = rows.fold<double>(0, (a, r) => r.spreadM > a ? r.spreadM : a);
    if (worst == 0) return '같은 층을 두 번 이상 찍으면 드리프트를 알 수 있습니다.';
    if (worst < 1.0) return '재방문 흔들림 최대 ${worst.toStringAsFixed(2)}m — 쓸 만합니다.';
    return '재방문 흔들림 최대 ${worst.toStringAsFixed(2)}m — 층고에 가까우면 다시 재세요.';
  }
}

class _MarkList extends StatelessWidget {
  const _MarkList({required this.probe, required this.onRemove});

  final ElevatorAltitudeProbe probe;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final marks = probe.marks;
    if (marks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '찍은 점 ${marks.length}개',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        for (var i = marks.length - 1; i >= 0; i--)
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_mmss(marks[i].elapsedMs)}  ${marks[i].floorLabel}  '
                  '${marks[i].smoothedAltitudeM.toStringAsFixed(2)}m'
                  '${marks[i].settled ? '' : '  (이동 중)'}',
                  style: TextStyle(
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: marks[i].settled ? null : const Color(0xFFE65100),
                  ),
                ),
              ),
              IconButton(
                tooltip: '이 점 지우기',
                visualDensity: VisualDensity.compact,
                onPressed: () => onRemove(i),
                icon: const Icon(Icons.close_rounded, size: 16),
              ),
            ],
          ),
      ],
    );
  }
}

String _mmss(int ms) {
  final total = ms ~/ 1000;
  final m = (total ~/ 60).toString().padLeft(2, '0');
  final s = (total % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
