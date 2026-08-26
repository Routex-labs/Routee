import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:indoor_pdr_core/indoor_pdr_core.dart';
import 'package:navigation_client/features/indoor_navigation/application/corridor_position_tracker.dart';
import 'package:navigation_client/models/building/floor_graph.dart';

/// v10 디버그 로그(`tracker_input_events`)를 [CorridorPositionTracker] 입력으로
/// 되돌려 실측 세션을 재생한다.
///
/// v10부터 tracker가 **실제로 받은 관측 전체**를 기록하므로, anchor 변환이나
/// heading 융합을 다시 흉내 낼 필요 없이 그대로 먹이면 된다. 좌표는 이미
/// floor local이다. 재생의 목적은 픽셀 일치가 아니라 상태 전이·정지·간선
/// 선택 같은 **거동**을 고정하는 것이다.
///
/// 재생이 실측과 완전히 같지는 않다는 점을 알고 쓴다: 레코더가 걸음 변화가
/// 없는 구간을 250ms heartbeat로 솎아내므로 무입력 이벤트의 시간 해상도가
/// 실제보다 성기다. 타임아웃 경계에 걸친 전이는 실측과 다를 수 있다.
class CorridorReplay {
  CorridorReplay._({
    required this.platform,
    required this.events,
    required this.expectedSteps,
    required this.expectedDistanceM,
  });

  final String platform;
  final List<CorridorReplayEvent> events;
  final int expectedSteps;
  final double expectedDistanceM;

  /// 보정 전 원본(초록) floor 경로. 구 [FloorMapMatcher]와 A/B 할 때 쓴다.
  late final List<PdrLocalPoint> floorPath;

  static const _fixtureDir = 'test/features/indoor_navigation/fixtures';

  static FloorGraph loadGraph([String name = 'b2_graph.json']) {
    final json =
        jsonDecode(File('$_fixtureDir/$name').readAsStringSync())
            as Map<String, dynamic>;
    return FloorGraph(
      nodes: [
        for (final node in json['nodes'] as List)
          GraphNode.fromJson(node as Map<String, dynamic>),
      ],
      edges: [
        for (final edge in json['edges'] as List)
          GraphEdge.fromJson(edge as Map<String, dynamic>),
      ],
    );
  }

  static CorridorReplay load(String name) {
    final json =
        jsonDecode(File('$_fixtureDir/$name').readAsStringSync())
            as Map<String, dynamic>;
    final expected = json['expected'] as Map<String, dynamic>;
    return CorridorReplay._(
        platform:
            (json['device'] as Map<String, dynamic>)['platform'] as String,
        expectedSteps: expected['confirmed_steps'] as int,
        expectedDistanceM: (expected['confirmed_distance_m'] as num).toDouble(),
        events: [
          for (final event in json['tracker_input_events'] as List)
            CorridorReplayEvent._(event as Map<String, dynamic>),
        ],
      )
      ..floorPath = [
        for (final point
            in (json['floor_local_m_before_matching'] as List? ?? const []))
          PdrLocalPoint(
            ((point as List)[0] as num).toDouble(),
            (point[1] as num).toDouble(),
          ),
      ];
  }

  /// 앱에서 바로 내보낸 v10+ 디버그 파일을 fixture 복사 없이 재생한다.
  /// 회귀 fixture와 달리 기대값은 파일의 [summary]에서 읽는다.
  static CorridorReplay loadDebugFile(String path) {
    final json =
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    final summary = json['summary'] as Map<String, dynamic>;
    final device = json['device'] as Map<String, dynamic>? ?? const {};
    return CorridorReplay._(
        platform: device['platform'] as String? ?? 'unknown',
        expectedSteps: summary['confirmed_steps'] as int? ?? 0,
        expectedDistanceM:
            (summary['confirmed_distance_m'] as num?)?.toDouble() ?? 0,
        events: [
          for (final event in json['tracker_input_events'] as List? ?? const [])
            CorridorReplayEvent._(event as Map<String, dynamic>),
        ],
      )
      ..floorPath = [
        for (final point
            in ((json['paths']
                        as Map<String, dynamic>?)?['confirmed_pdr_local_m']
                    as List? ??
                const []))
          ?CorridorReplayEvent._point(point),
      ];
  }

  /// 이벤트를 순서대로 먹이고 각 시점의 결과를 모은다.
  ///
  /// `kind == 'reset'`은 tracker를 다시 세우는 지점이다. 실측에서 graph/anchor가
  /// 바뀌었거나 세션이 되감긴 경우이며, 재생도 같은 자리에서 초기화한다.
  CorridorReplayRun run({
    FloorGraph? graph,
    CorridorTrackerConfig config = const CorridorTrackerConfig(),
  }) {
    final resolved = graph ?? loadGraph();
    CorridorPositionTracker? tracker;
    final samples = <CorridorReplaySample>[];
    for (final event in events) {
      if (event.isReset || tracker == null) {
        tracker = CorridorPositionTracker(resolved, config: config);
        tracker.reset(
          initialPosition: event.rawConfirmedPosition ?? event.resultPosition,
          initialHeadingDeg: event.sensorHeadingDeg ?? 0,
          timestampMs: event.timestampMs ?? 0,
          initialConfirmedSteps: event.confirmedSteps ?? 0,
          initialConfirmedDistanceM: event.confirmedDistanceM ?? 0,
          initialPreviewSteps: event.previewSteps ?? 0,
        );
        samples.add(CorridorReplaySample._(event, tracker.result));
        continue;
      }
      final observation = event.toObservation();
      if (observation == null) continue;
      samples.add(CorridorReplaySample._(event, tracker.update(observation)));
    }
    return CorridorReplayRun._(this, samples);
  }
}

class CorridorReplayEvent {
  CorridorReplayEvent._(this._json);

  final Map<String, dynamic> _json;

  bool get isReset => _json['kind'] == 'reset';
  int? get timestampMs => _json['timestamp_ms'] as int?;
  int? get confirmedSteps => _json['confirmed_steps'] as int?;
  double? get confirmedDistanceM =>
      (_json['confirmed_distance_m'] as num?)?.toDouble();
  int? get previewSteps => _json['preview_steps'] as int?;
  double? get sensorHeadingDeg =>
      (_json['sensor_heading_deg'] as num?)?.toDouble();
  bool get hasHeading => _json['has_heading'] as bool? ?? false;

  PdrLocalPoint? get rawConfirmedPosition =>
      _point(_json['raw_confirmed_position']);
  PdrLocalPoint? get rawPreviewPosition =>
      _point(_json['raw_preview_position']);

  /// 실측 당시 tracker가 내놓은 위치. 재생 결과와 비교하면 회귀를 볼 수 있다.
  PdrLocalPoint get resultPosition =>
      _point((_json['result'] as Map<String, dynamic>)['position'])!;
  PdrLocalPoint get resultPreviewPosition =>
      _point((_json['result'] as Map<String, dynamic>)['preview_position'])!;
  String get recordedState =>
      (_json['result'] as Map<String, dynamic>)['state'] as String;

  /// 이 이벤트에서 확정 배치가 새로 반영됐는지.
  bool get hasAppliedBatch => _json.containsKey('applied_batch');

  CorridorObservation? toObservation() {
    final position = rawConfirmedPosition;
    final preview = rawPreviewPosition;
    if (position == null || preview == null || timestampMs == null) return null;
    return CorridorObservation(
      timestampMs: timestampMs!,
      rawConfirmedPosition: position,
      confirmedSteps: confirmedSteps ?? 0,
      confirmedDistanceM: confirmedDistanceM ?? 0,
      rawPreviewPosition: preview,
      previewSteps: previewSteps ?? 0,
      sensorHeadingDeg: sensorHeadingDeg ?? 0,
      hasHeading: hasHeading,
      rawConfirmedStepPositions: _points(_json['raw_confirmed_step_positions']),
      rawPreviewTailPositions: _points(_json['raw_preview_tail_positions']),
      rawPreviewTailPeakIds: _nullableInts(_json['raw_preview_tail_peak_ids']),
      rawPreviewTailPeakTimesMs: _nullableInts(
        _json['raw_preview_tail_peak_times_ms'],
      ),
      confirmedThroughMs:
          ((_json['applied_batch'] as Map<String, dynamic>?)?['span_end_ms'])
              as int?,
      confirmedThroughPeakId:
          ((_json['applied_batch']
                  as Map<String, dynamic>?)?['acknowledged_preview_steps'])
              as int?,
    );
  }

  static PdrLocalPoint? _point(Object? raw) {
    if (raw is Map) {
      final east = raw['east_m'] as num?;
      final north = raw['north_m'] as num?;
      if (east != null && north != null) {
        return PdrLocalPoint(east.toDouble(), north.toDouble());
      }
    }
    if (raw is! List || raw.length < 2) return null;
    return PdrLocalPoint(
      (raw[0] as num).toDouble(),
      (raw[1] as num).toDouble(),
    );
  }

  static List<PdrLocalPoint> _points(Object? raw) => [
    if (raw is List)
      for (final entry in raw) ?_point(entry),
  ];

  static List<int?> _nullableInts(Object? raw) => [
    if (raw is List)
      for (final entry in raw) entry as int?,
  ];
}

class CorridorReplaySample {
  const CorridorReplaySample._(this.event, this.result);

  final CorridorReplayEvent event;
  final CorridorTrackingResult result;
}

class CorridorReplayRun {
  const CorridorReplayRun._(this.replay, this.samples);

  final CorridorReplay replay;
  final List<CorridorReplaySample> samples;

  CorridorTrackingResult get last => samples.last.result;

  /// 보정 경로가 실제로 그린 길이. 걸은 거리 대비 비율이 "거리 소실" 지표다.
  double get correctedDistanceM {
    final path = last.correctedPath;
    var total = 0.0;
    for (var index = 1; index < path.length; index += 1) {
      total += (path[index] - path[index - 1]).distance;
    }
    return total;
  }

  double get distanceRetention => correctedDistanceM / replay.expectedDistanceM;

  /// 보정 경로 안에서 한 걸음 이상 건너뛴 구간들(m).
  ///
  /// 보정 경로는 그래프를 따라가므로 이웃한 두 점 사이는 한 걸음 남짓이어야
  /// 한다. 여기 큰 값이 나오면 서로 다른 가설의 조각을 이어 붙였다는 뜻이고,
  /// 화면에는 매장을 가로지르는 직선으로 그려진다.
  List<double> get correctedTeleports => teleportsOf(last.correctedPath);

  static List<double> teleportsOf(List<PdrLocalPoint> path) => [
    for (var index = 1; index < path.length; index += 1)
      if ((path[index] - path[index - 1]).distance > 2)
        (path[index] - path[index - 1]).distance,
  ];

  static double lengthOf(List<PdrLocalPoint> path) {
    var total = 0.0;
    for (var index = 1; index < path.length; index += 1) {
      total += (path[index] - path[index - 1]).distance;
    }
    return total;
  }

  /// 확정 위치가 한 지점에 머문 최장 시간(초).
  ///
  /// 걷고 있는데 마커가 멈춰 있으면 그만큼 이동이 통째로 버려졌다는 뜻이다.
  double get longestStallSeconds {
    var longest = 0.0;
    PdrLocalPoint? held;
    int? heldSinceMs;
    for (final sample in samples) {
      final atMs = sample.event.timestampMs;
      if (atMs == null) continue;
      final position = sample.result.correctedPosition;
      if (held != null && (held - position).distance <= 0.01) {
        longest = math.max(longest, (atMs - heldSinceMs!) / 1000);
        continue;
      }
      held = position;
      heldSinceMs = atMs;
    }
    return longest;
  }

  /// 확정 배치가 도착한 이벤트에서 preview가 튄 거리들.
  ///
  /// preview를 매번 재생성하면 여기서만 점프가 몰린다. 상태형으로 바꾸면
  /// 배치 도착이 특별한 사건이 아니게 되므로 분포가 평평해져야 한다.
  List<double> get previewJumpsOnBatch => _previewJumps(onBatch: true);
  List<double> get previewJumpsElsewhere => _previewJumps(onBatch: false);

  List<double> _previewJumps({required bool onBatch}) {
    final jumps = <double>[];
    PdrLocalPoint? previous;
    for (final sample in samples) {
      final position = sample.result.previewPosition;
      final isBatch = sample.event._json.containsKey('applied_batch');
      if (previous != null && isBatch == onBatch) {
        jumps.add((position - previous).distance);
      }
      previous = position;
    }
    return jumps;
  }

  /// preview가 확정 위치에서 떨어진 최대 거리(m).
  ///
  /// 화면 마커는 preview 위치다. 이 값이 크면 마커가 보라선 끝을 한참 벗어나
  /// 사용자에게는 "마커가 선을 안 따라간다"로 보인다.
  double get maxPreviewLeadM {
    var longest = 0.0;
    for (final sample in samples) {
      final lead =
          (sample.result.previewPosition - sample.result.correctedPosition)
              .distance;
      if (lead > longest) longest = lead;
    }
    return longest;
  }

  /// 내부 optimistic graph cursor가 확정 cursor보다 앞선 최대 직선거리(m).
  /// 표시 연속성 shadow는 후보 재배치 중 graph 선에서 잠시 떨어질 수 있으므로,
  /// 맵매칭 자체의 거리 보존은 이 값으로 따로 잰다.
  double get maxMatchedPreviewLeadM {
    var longest = 0.0;
    for (final sample in samples) {
      final lead =
          (sample.result.matchedPreviewPosition -
                  sample.result.correctedPosition)
              .distance;
      if (lead > longest) longest = lead;
    }
    return longest;
  }

  int previewJumpsOver(double meters) => [
    ...previewJumpsOnBatch,
    ...previewJumpsElsewhere,
  ].where((jump) => jump > meters).length;

  /// 확정 위치가 지나간 간선 목록(중복 제거, 순서 유지).
  List<String> get visitedEdgeIds {
    final visited = <String>[];
    for (final sample in samples) {
      final id = sample.result.currentEdgeId;
      if (id != null && (visited.isEmpty || visited.last != id)) {
        visited.add(id);
      }
    }
    return visited;
  }

  /// 보정 경로가 실제로 커버한 좌표 범위. 모양이 무너졌는지 본다.
  ({double minEast, double maxEast, double minNorth, double maxNorth})
  get correctedBounds {
    var minEast = double.infinity, maxEast = -double.infinity;
    var minNorth = double.infinity, maxNorth = -double.infinity;
    for (final point in last.correctedPath) {
      minEast = math.min(minEast, point.eastM);
      maxEast = math.max(maxEast, point.eastM);
      minNorth = math.min(minNorth, point.northM);
      maxNorth = math.max(maxNorth, point.northM);
    }
    return (
      minEast: minEast,
      maxEast: maxEast,
      minNorth: minNorth,
      maxNorth: maxNorth,
    );
  }
}
