@Tags(['diag'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'corridor_replay_harness.dart';

/// 재생 진단 덤프. 회귀 판정이 아니라 원인 추적용이라 `diag` 태그로 분리한다.
///   flutter test --tags diag test/features/indoor_navigation/corridor_replay_diag_test.dart
void main() {
  final externalLog = Platform.environment['PDR_DEBUG_LOG'];
  if (externalLog != null && externalLog.isNotEmpty) {
    test('외부 디버그 로그 덤프', () {
      _dumpRun(CorridorReplay.loadDebugFile(externalLog).run());
    });
  }
  for (final fixture in [
    'pdr_v10_ios_b2_west.json',
    'pdr_v10_android_b2_east.json',
    'pdr_v10_ios_b2_loop.json',
    'pdr_v10_ios_b2_rect.json',
    'pdr_v10_android_b2_west.json',
  ]) {
    test('덤프 $fixture', () {
      _dumpRun(CorridorReplay.load(fixture).run(), label: fixture);
    });
  }
}

void _dumpRun(CorridorReplayRun run, {String label = 'external'}) {
  final bounds = run.correctedBounds;
  // ignore: avoid_print
  print(
    '\n=== $label ===\n'
    '유지율 ${run.distanceRetention.toStringAsFixed(3)} '
    '(보정 ${run.correctedDistanceM.toStringAsFixed(1)}m / '
    '걸음 ${run.replay.expectedDistanceM.toStringAsFixed(1)}m)\n'
    '최장 정지 ${run.longestStallSeconds.toStringAsFixed(1)}초\n'
    'east ${bounds.minEast.toStringAsFixed(1)}~${bounds.maxEast.toStringAsFixed(1)} '
    'north ${bounds.minNorth.toStringAsFixed(1)}~${bounds.maxNorth.toStringAsFixed(1)}\n'
    '방문 간선 ${run.visitedEdgeIds.toSet().length}개',
  );

  var previous = run.samples.first.result.previewPosition;
  final jumps = <String>[];
  for (final sample in run.samples.skip(1)) {
    final jump = (sample.result.previewPosition - previous).distance;
    if (jump > 3) {
      jumps.add(
        't=${sample.event.timestampMs} ${jump.toStringAsFixed(1)}m '
        '(${previous.eastM.toStringAsFixed(1)},${previous.northM.toStringAsFixed(1)})'
        '→(${sample.result.previewPosition.eastM.toStringAsFixed(1)},'
        '${sample.result.previewPosition.northM.toStringAsFixed(1)}) '
        'state=${sample.result.state.name} '
        'amb=${sample.result.previewIsAmbiguous} '
        'batch=${sample.event.hasAppliedBatch} '
        'relocated=${sample.result.leaderRelocated} '
        'edge=${_short(sample.result.currentEdgeId)} '
        'preview=${_short(sample.result.optimisticEdgeId)} '
        'pend=${_short(sample.result.pendingEdgeId)}',
      );
    }
    previous = sample.result.previewPosition;
  }
  var frozen = 0;
  var prevPv = run.samples.first.result.previewPosition;
  var maxLead = 0.0;
  for (final sample in run.samples.skip(1)) {
    final pv = sample.result.previewPosition;
    if ((pv - prevPv).distance < 1e-6) frozen += 1;
    maxLead = maxLead > (pv - sample.result.correctedPosition).distance
        ? maxLead
        : (pv - sample.result.correctedPosition).distance;
    prevPv = pv;
  }
  // ignore: avoid_print
  print(
    'preview 3m 초과 점프 ${jumps.length}건 | 정지 프레임 $frozen/${run.samples.length} '
    '| 확정과의 최대 거리 ${maxLead.toStringAsFixed(1)}m',
  );
  // ignore: avoid_print
  print(jumps.take(15).join('\n'));

  // 확정 위치가 크게 튄 지점
  var prevConfirmed = run.samples.first.result.correctedPosition;
  final confirmedJumps = <String>[];
  for (final sample in run.samples.skip(1)) {
    final jump = (sample.result.correctedPosition - prevConfirmed).distance;
    if (jump > 4) {
      confirmedJumps.add(
        't=${sample.event.timestampMs} ${jump.toStringAsFixed(1)}m '
        'state=${sample.result.state.name} '
        'edge=${_short(sample.result.currentEdgeId)}',
      );
    }
    prevConfirmed = sample.result.correctedPosition;
  }
  // 확정 위치가 서쪽 끝(또는 최원점)에 언제 도달했는지
  final path = run.last.correctedPath;
  // ignore: avoid_print
  print(
    '보정 경로 끝 5점: '
    '${path.skip(path.length - 5 < 0 ? 0 : path.length - 5).map((p) => '(${p.eastM.toStringAsFixed(1)},${p.northM.toStringAsFixed(1)})').join(' ')}',
  );
  // ignore: avoid_print
  print(
    '최종 간선 ${_short(run.last.currentEdgeId)} sign=${run.last.travelDirectionSign} '
    'bias=${run.last.headingBiasDeg.toStringAsFixed(1)}도 state=${run.last.state.name}',
  );
  // ignore: avoid_print
  print('확정 4m 초과 점프 ${confirmedJumps.length}건');
  // ignore: avoid_print
  print(confirmedJumps.take(10).join('\n'));
}

String _short(String? id) =>
    id == null ? '-' : id.substring(id.length - 8 < 0 ? 0 : id.length - 8);
