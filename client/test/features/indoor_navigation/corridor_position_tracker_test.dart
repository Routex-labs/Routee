import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_pdr_core/indoor_pdr_core.dart';
import 'package:navigation_client/features/indoor_navigation/application/corridor_position_tracker.dart';
import 'package:navigation_client/features/indoor_navigation/contract/pdr_anchor.dart';
import 'package:navigation_client/models/building/floor_graph.dart';
import 'package:navigation_client/domain/guidance/corridor_tracking.dart';
import 'package:navigation_client/domain/guidance/location_marker_continuity.dart';
import 'package:navigation_client/domain/geo/geo_transform.dart';

const _crossGraph = FloorGraph(
  nodes: [
    GraphNode(id: 'a', type: 'corridor', xM: 0, yM: 0),
    GraphNode(id: 'b', type: 'junction', xM: 10, yM: 0),
    GraphNode(id: 'c', type: 'corridor', xM: 10, yM: 10),
    GraphNode(id: 'd', type: 'corridor', xM: 20, yM: 0),
    GraphNode(id: 'e', type: 'junction', xM: 20, yM: 3),
    GraphNode(id: 'f', type: 'corridor', xM: 0, yM: 3),
  ],
  edges: [
    GraphEdge(
      id: 'ab',
      fromNodeId: 'a',
      toNodeId: 'b',
      lengthM: 10,
      bidirectional: true,
      geometryLocalM: [LocalPoint(0, 0), LocalPoint(10, 0)],
    ),
    GraphEdge(
      id: 'bd',
      fromNodeId: 'b',
      toNodeId: 'd',
      lengthM: 10,
      bidirectional: true,
      geometryLocalM: [LocalPoint(10, 0), LocalPoint(20, 0)],
    ),
    GraphEdge(
      id: 'bc',
      fromNodeId: 'b',
      toNodeId: 'c',
      lengthM: 10,
      bidirectional: true,
      geometryLocalM: [LocalPoint(10, 0), LocalPoint(10, 10)],
    ),
    GraphEdge(
      id: 'de',
      fromNodeId: 'd',
      toNodeId: 'e',
      lengthM: 3,
      bidirectional: true,
      geometryLocalM: [LocalPoint(20, 0), LocalPoint(20, 3)],
    ),
    GraphEdge(
      id: 'ef',
      fromNodeId: 'e',
      toNodeId: 'f',
      lengthM: 20,
      bidirectional: true,
      geometryLocalM: [LocalPoint(20, 3), LocalPoint(0, 3)],
    ),
  ],
);

/// 직진 간선 옆에 짧은 연결 간선을 거쳐 다시 동쪽으로 향하는 탑승 경로가 있다.
/// 실제 사용자는 두 직각을 꼭짓점대로 밟지 않고 하나의 완만한 S자로 자른다.
const _doubleTurnGraph = FloorGraph(
  nodes: [
    GraphNode(id: 'a', type: 'corridor', xM: 0, yM: 0),
    GraphNode(id: 'b', type: 'junction', xM: 10, yM: 0),
    GraphNode(id: 'straight', type: 'corridor', xM: 20, yM: 0),
    GraphNode(id: 'c', type: 'junction', xM: 10, yM: 2.4),
    GraphNode(id: 'es', type: 'escalator', xM: 18, yM: 2.4),
  ],
  edges: [
    GraphEdge(
      id: 'ab',
      fromNodeId: 'a',
      toNodeId: 'b',
      lengthM: 10,
      bidirectional: true,
      geometryLocalM: [LocalPoint(0, 0), LocalPoint(10, 0)],
    ),
    GraphEdge(
      id: 'b-straight',
      fromNodeId: 'b',
      toNodeId: 'straight',
      lengthM: 10,
      bidirectional: true,
      geometryLocalM: [LocalPoint(10, 0), LocalPoint(20, 0)],
    ),
    GraphEdge(
      id: 'bc',
      fromNodeId: 'b',
      toNodeId: 'c',
      lengthM: 2.4,
      bidirectional: true,
      geometryLocalM: [LocalPoint(10, 0), LocalPoint(10, 2.4)],
    ),
    GraphEdge(
      id: 'c-es',
      fromNodeId: 'c',
      toNodeId: 'es',
      lengthM: 8,
      bidirectional: true,
      geometryLocalM: [LocalPoint(10, 2.4), LocalPoint(18, 2.4)],
    ),
  ],
);

const _longStraightGraph = FloorGraph(
  nodes: [
    GraphNode(id: 'start', type: 'corridor', xM: 0, yM: 0),
    GraphNode(id: 'end', type: 'corridor', xM: 50, yM: 0),
  ],
  edges: [
    GraphEdge(
      id: 'straight',
      fromNodeId: 'start',
      toNodeId: 'end',
      lengthM: 50,
      bidirectional: true,
      geometryLocalM: [LocalPoint(0, 0), LocalPoint(50, 0)],
    ),
  ],
);

const _parallelGraph = FloorGraph(
  nodes: [
    GraphNode(id: 'low-start', type: 'corridor', xM: 0, yM: 0),
    GraphNode(id: 'low-end', type: 'corridor', xM: 20, yM: 0),
    GraphNode(id: 'high-start', type: 'corridor', xM: 0, yM: 7),
    GraphNode(id: 'high-end', type: 'corridor', xM: 20, yM: 7),
  ],
  edges: [
    GraphEdge(
      id: 'low',
      fromNodeId: 'low-start',
      toNodeId: 'low-end',
      lengthM: 20,
      bidirectional: true,
      geometryLocalM: [LocalPoint(0, 0), LocalPoint(20, 0)],
    ),
    GraphEdge(
      id: 'high',
      fromNodeId: 'high-start',
      toNodeId: 'high-end',
      lengthM: 20,
      bidirectional: true,
      geometryLocalM: [LocalPoint(0, 7), LocalPoint(20, 7)],
    ),
  ],
);

CorridorObservation _observation({
  required int atMs,
  required int confirmedSteps,
  required double confirmedDistanceM,
  required int previewSteps,
  required double headingDeg,
  PdrLocalPoint raw = PdrLocalPoint.zero,
  List<PdrLocalPoint> rawConfirmedStepPositions = const [],
  List<PdrLocalPoint> rawPreviewTailPositions = const [],
  List<int?> rawPreviewTailPeakIds = const [],
  List<int?> rawPreviewTailPeakTimesMs = const [],
  int? confirmedThroughMs,
  int? confirmedThroughPeakId,
}) => CorridorObservation(
  timestampMs: atMs,
  rawConfirmedPosition: raw,
  confirmedSteps: confirmedSteps,
  confirmedDistanceM: confirmedDistanceM,
  rawPreviewPosition: raw,
  previewSteps: previewSteps,
  sensorHeadingDeg: headingDeg,
  hasHeading: true,
  rawConfirmedStepPositions: rawConfirmedStepPositions,
  rawPreviewTailPositions: rawPreviewTailPositions,
  rawPreviewTailPeakIds: rawPreviewTailPeakIds,
  rawPreviewTailPeakTimesMs: rawPreviewTailPeakTimesMs,
  confirmedThroughMs: confirmedThroughMs,
  confirmedThroughPeakId: confirmedThroughPeakId,
);

/// 동쪽으로 [count]걸음(0.7m) 걷는 preview/confirmed 시계열을 만든다.
///
/// 같은 peak 시계열을 서로 다른 배치 크기로 확정시켜도 optimistic 위치가
/// 같아야 한다는 것을 확인하기 위한 생성기다.
List<PdrLocalPoint> _eastPoints(double startEastM, int count) => [
  for (var index = 0; index <= count; index += 1)
    PdrLocalPoint(startEastM + index * 0.7, 0),
];

void main() {
  group('배치 독립 optimistic preview cursor', () {
    CorridorPositionTracker straightTracker() =>
        CorridorPositionTracker(_longStraightGraph)..reset(
          initialPosition: const PdrLocalPoint(1, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );

    test('배치가 이미 본 preview peak를 확인만 하면 표시 위치가 그대로다', () {
      final tracker = straightTracker();
      final afterPreview = tracker.update(
        _observation(
          atMs: 1600,
          confirmedSteps: 0,
          confirmedDistanceM: 0,
          previewSteps: 2,
          headingDeg: 90,
          rawPreviewTailPositions: _eastPoints(1, 2),
          rawPreviewTailPeakTimesMs: const [null, 1000, 1500],
        ),
      );
      expect(afterPreview.previewPosition.eastM, closeTo(2.4, 1e-9));
      expect(afterPreview.optimisticStepAdvances, hasLength(2));
      expect(
        afterPreview.optimisticStepAdvances
            .map((event) => event.distanceM)
            .toList(),
        everyElement(closeTo(0.7, 1e-9)),
      );
      expect(
        afterPreview.optimisticStepAdvances
            .expand((event) => event.traversals)
            .map((traversal) => traversal.edgeId)
            .toSet(),
        {'straight'},
      );

      final afterFirstBatch = tracker.update(
        _observation(
          atMs: 2000,
          confirmedSteps: 1,
          confirmedDistanceM: 0.7,
          previewSteps: 2,
          headingDeg: 90,
          raw: const PdrLocalPoint(1.7, 0),
          rawConfirmedStepPositions: const [PdrLocalPoint(1.7, 0)],
          rawPreviewTailPositions: const [
            PdrLocalPoint(1.7, 0),
            PdrLocalPoint(2.4, 0),
          ],
          rawPreviewTailPeakTimesMs: const [null, 1500],
          confirmedThroughMs: 1200,
        ),
      );
      expect(afterFirstBatch.correctedPosition.eastM, closeTo(1.7, 1e-9));
      expect(
        afterFirstBatch.previewPosition.eastM,
        closeTo(2.4, 1e-9),
        reason: '배치는 이미 보인 걸음을 확인했을 뿐이므로 marker가 움직이면 안 된다',
      );
      expect(afterFirstBatch.optimisticLeadM, closeTo(0.7, 1e-9));

      final afterSecondBatch = tracker.update(
        _observation(
          atMs: 2400,
          confirmedSteps: 2,
          confirmedDistanceM: 1.4,
          previewSteps: 2,
          headingDeg: 90,
          raw: const PdrLocalPoint(2.4, 0),
          rawConfirmedStepPositions: const [PdrLocalPoint(2.4, 0)],
          confirmedThroughMs: 1700,
        ),
      );
      expect(afterSecondBatch.previewPosition.eastM, closeTo(2.4, 1e-9));
      expect(afterSecondBatch.optimisticLeadM, closeTo(0, 1e-9));
      expect(afterSecondBatch.optimisticStepAdvances, isEmpty);
    });

    test('초록 1걸음 시간창에 주황 peak가 2개여도 실제 대응한 ID만 소비한다', () {
      final tracker = straightTracker();
      tracker.update(
        _observation(
          atMs: 1600,
          confirmedSteps: 0,
          confirmedDistanceM: 0,
          previewSteps: 2,
          headingDeg: 90,
          raw: const PdrLocalPoint(1, 0),
          rawPreviewTailPositions: _eastPoints(1, 2),
          rawPreviewTailPeakIds: const [0, 1, 2],
          rawPreviewTailPeakTimesMs: const [null, 1000, 1500],
        ),
      );

      final result = tracker.update(
        _observation(
          atMs: 2000,
          confirmedSteps: 1,
          confirmedDistanceM: 0.7,
          previewSteps: 2,
          headingDeg: 90,
          raw: const PdrLocalPoint(1.7, 0),
          rawConfirmedStepPositions: const [PdrLocalPoint(1.7, 0)],
          // 시간창만 보면 두 peak 모두 과거지만 실제로 대응된 것은 ID 1뿐이다.
          rawPreviewTailPositions: const [
            PdrLocalPoint(1.7, 0),
            PdrLocalPoint(2.4, 0),
          ],
          rawPreviewTailPeakIds: const [1, 2],
          rawPreviewTailPeakTimesMs: const [1000, 1500],
          confirmedThroughMs: 2000,
          confirmedThroughPeakId: 1,
        ),
      );

      expect(result.previewPosition.eastM, closeTo(2.4, 1e-9));
      expect(result.optimisticLeadM, closeTo(0.7, 1e-9));
      expect(result.previewPeakIdsSynthetic, isFalse);
    });

    test('확정 간선이 바뀌어도 pending preview 걸음을 새 간선에 다시 태운다', () {
      final tracker =
          CorridorPositionTracker(
            _parallelGraph,
            config: const CorridorTrackerConfig(
              seedRadiusM: 8,
              seedPenaltyDegM: 0,
              positionalToleranceM: 0,
              positionalWeightDegPerM: 10,
            ),
          )..reset(
            initialPosition: const PdrLocalPoint(1, 0),
            initialHeadingDeg: 90,
            timestampMs: 0,
          );

      tracker.update(
        _observation(
          atMs: 1500,
          confirmedSteps: 0,
          confirmedDistanceM: 0,
          previewSteps: 3,
          headingDeg: 90,
          rawPreviewTailPositions: const [
            PdrLocalPoint(1, 0),
            PdrLocalPoint(1.7, 0),
            PdrLocalPoint(2.4, 0),
            PdrLocalPoint(3.1, 0),
          ],
          rawPreviewTailPeakTimesMs: const [null, 500, 1000, 1500],
        ),
      );
      expect(tracker.result.optimisticEdgeId, 'low');
      expect(tracker.result.previewPosition.eastM, closeTo(3.1, 1e-9));

      final afterBatch = tracker.update(
        _observation(
          atMs: 1800,
          confirmedSteps: 1,
          confirmedDistanceM: 0.7,
          previewSteps: 3,
          headingDeg: 90,
          raw: const PdrLocalPoint(1.7, 7),
          rawConfirmedStepPositions: const [PdrLocalPoint(1.7, 7)],
          rawPreviewTailPositions: const [
            PdrLocalPoint(1.7, 7),
            PdrLocalPoint(2.4, 7),
            PdrLocalPoint(3.1, 7),
          ],
          rawPreviewTailPeakTimesMs: const [500, 1000, 1500],
          confirmedThroughMs: 500,
        ),
      );

      expect(afterBatch.currentEdgeId, 'high');
      expect(afterBatch.optimisticEdgeId, 'high');
      expect(afterBatch.matchedPreviewPosition.eastM, closeTo(3.1, 1e-9));
      expect(afterBatch.matchedPreviewPosition.northM, closeTo(7, 1e-9));
      expect(afterBatch.previewPosition.eastM, closeTo(3.1, 1e-9));
      expect(
        afterBatch.previewPosition.northM,
        closeTo(locationMarkerNavigableLeashM, 1e-9),
        reason: '내부 후보는 교체하되 연결되지 않은 평행 간선으로 화면을 점프시키지 않는다',
      );
      expect(afterBatch.previewUsesContinuityShadow, isTrue);
      expect(afterBatch.optimisticLeadM, closeTo(1.4, 1e-9));
    });

    test('preview tail이 비어도 안정된 경로 확정 걸음으로 shadow를 복귀시킨다', () {
      final tracker =
          CorridorPositionTracker(
              _parallelGraph,
              config: const CorridorTrackerConfig(
                seedRadiusM: 8,
                seedPenaltyDegM: 0,
                positionalToleranceM: 0,
                positionalWeightDegPerM: 10,
              ),
            )
            ..setPreferredRoute(
              edgeIds: const ['high'],
              nodeIds: const ['high-start', 'high-end'],
            )
            ..reset(
              initialPosition: const PdrLocalPoint(1, 0),
              initialHeadingDeg: 90,
              timestampMs: 0,
            );

      final relocated = tracker.update(
        _observation(
          atMs: 1000,
          confirmedSteps: 1,
          confirmedDistanceM: 0.7,
          previewSteps: 0,
          headingDeg: 90,
          raw: const PdrLocalPoint(1.7, 7),
          rawConfirmedStepPositions: const [PdrLocalPoint(1.7, 7)],
        ),
      );
      expect(relocated.matchedPreviewPosition.northM, 7);
      expect(relocated.previewUsesContinuityShadow, isTrue);

      tracker.update(
        _observation(
          atMs: 1500,
          confirmedSteps: 2,
          confirmedDistanceM: 1.4,
          previewSteps: 0,
          headingDeg: 90,
          raw: const PdrLocalPoint(2.4, 7),
          rawConfirmedStepPositions: const [PdrLocalPoint(2.4, 7)],
        ),
      );
      final released = tracker.update(
        _observation(
          atMs: 2000,
          confirmedSteps: 3,
          confirmedDistanceM: 2.1,
          previewSteps: 0,
          headingDeg: 90,
          raw: const PdrLocalPoint(3.1, 7),
          rawConfirmedStepPositions: const [PdrLocalPoint(3.1, 7)],
        ),
      );

      expect(released.matchedPreviewPosition.northM, 7);
      expect(released.previewPosition.northM, 7);
      expect(released.previewUsesContinuityShadow, isFalse);
    });

    test('큰 preview 선행분은 배치 한 번으로 폐기하지 않는다', () {
      final tracker =
          CorridorPositionTracker(
            _parallelGraph,
            config: const CorridorTrackerConfig(
              seedRadiusM: 8,
              seedPenaltyDegM: 0,
              positionalToleranceM: 0,
              positionalWeightDegPerM: 10,
            ),
          )..reset(
            initialPosition: const PdrLocalPoint(1, 0),
            initialHeadingDeg: 90,
            timestampMs: 0,
          );

      tracker.update(
        _observation(
          atMs: 2500,
          confirmedSteps: 0,
          confirmedDistanceM: 0,
          previewSteps: 5,
          headingDeg: 90,
          rawPreviewTailPositions: _eastPoints(1, 5),
          rawPreviewTailPeakTimesMs: const [null, 500, 1000, 1500, 2000, 2500],
        ),
      );
      final beforeBatch = tracker.result.previewPosition;

      final afterBatch = tracker.update(
        _observation(
          atMs: 2800,
          confirmedSteps: 1,
          confirmedDistanceM: 0.7,
          previewSteps: 5,
          headingDeg: 90,
          raw: const PdrLocalPoint(1.7, 7),
          rawConfirmedStepPositions: const [PdrLocalPoint(1.7, 7)],
          rawPreviewTailPositions: const [
            PdrLocalPoint(1.7, 7),
            PdrLocalPoint(2.4, 7),
            PdrLocalPoint(3.1, 7),
            PdrLocalPoint(3.8, 7),
            PdrLocalPoint(4.5, 7),
          ],
          rawPreviewTailPeakTimesMs: const [500, 1000, 1500, 2000, 2500],
          confirmedThroughMs: 500,
        ),
      );

      expect(afterBatch.currentEdgeId, 'high');
      expect(afterBatch.optimisticEdgeId, 'low');
      expect(afterBatch.previewPosition, beforeBatch);
      expect(afterBatch.optimisticLeadM, closeTo(2.8, 1e-9));
      expect(afterBatch.leaderRelocated, isTrue);
    });

    test('preview에 없이 배치로만 들어온 걸음도 한 번은 태운다', () {
      final tracker = straightTracker();
      final result = tracker.update(
        _observation(
          atMs: 2000,
          confirmedSteps: 2,
          confirmedDistanceM: 1.4,
          previewSteps: 0,
          headingDeg: 90,
          raw: const PdrLocalPoint(2.4, 0),
          rawConfirmedStepPositions: const [
            PdrLocalPoint(1.7, 0),
            PdrLocalPoint(2.4, 0),
          ],
          confirmedThroughMs: 1700,
        ),
      );

      expect(result.correctedPosition.eastM, closeTo(2.4, 1e-9));
      expect(result.previewPosition.eastM, closeTo(2.4, 1e-9));
      expect(result.optimisticLeadM, closeTo(0, 1e-9));
    });

    test('옛 로그의 같은 시각 tail도 누적 걸음 ID로 한 번만 태운다', () {
      final tracker = straightTracker();
      const tail = [PdrLocalPoint(1, 0), PdrLocalPoint(1.7, 0)];
      const times = <int?>[null, 1000];
      tracker.update(
        _observation(
          atMs: 1100,
          confirmedSteps: 0,
          confirmedDistanceM: 0,
          previewSteps: 1,
          headingDeg: 90,
          rawPreviewTailPositions: tail,
          rawPreviewTailPeakTimesMs: times,
        ),
      );
      final result = tracker.update(
        _observation(
          atMs: 1200,
          confirmedSteps: 0,
          confirmedDistanceM: 0,
          previewSteps: 1,
          headingDeg: 90,
          rawPreviewTailPositions: tail,
          rawPreviewTailPeakTimesMs: times,
        ),
      );

      expect(result.previewPosition.eastM, closeTo(1.7, 1e-9));
      expect(result.previewPeakIdsSynthetic, isTrue);
    });

    test('옛 로그에서 확정 시간창이 pending peak 시각을 지나도 다시 태우지 않는다', () {
      final tracker = straightTracker();
      tracker.update(
        _observation(
          atMs: 1600,
          confirmedSteps: 0,
          confirmedDistanceM: 0,
          previewSteps: 2,
          headingDeg: 90,
          rawPreviewTailPositions: _eastPoints(1, 2),
          rawPreviewTailPeakTimesMs: const [null, 1000, 1500],
        ),
      );
      tracker.update(
        _observation(
          atMs: 2000,
          confirmedSteps: 1,
          confirmedDistanceM: 0.7,
          previewSteps: 2,
          headingDeg: 90,
          raw: const PdrLocalPoint(1.7, 0),
          rawConfirmedStepPositions: const [PdrLocalPoint(1.7, 0)],
          rawPreviewTailPositions: const [
            PdrLocalPoint(1.7, 0),
            PdrLocalPoint(2.4, 0),
          ],
          rawPreviewTailPeakTimesMs: const [1000, 1500],
          // 구형 로그에는 실제 소비 개수가 없어 시간창이 pending 시각까지 덮는다.
          confirmedThroughMs: 2000,
        ),
      );

      final heartbeat = tracker.update(
        _observation(
          atMs: 2100,
          confirmedSteps: 1,
          confirmedDistanceM: 0.7,
          previewSteps: 2,
          headingDeg: 90,
          raw: const PdrLocalPoint(1.7, 0),
          rawPreviewTailPositions: const [
            PdrLocalPoint(1.7, 0),
            PdrLocalPoint(2.4, 0),
          ],
          rawPreviewTailPeakTimesMs: const [1000, 1500],
          confirmedThroughMs: 2000,
        ),
      );

      expect(heartbeat.previewPosition.eastM, closeTo(2.4, 1e-9));
      expect(heartbeat.optimisticLeadM, closeTo(0.7, 1e-9));
      expect(heartbeat.optimisticStepAdvances, isEmpty);
    });

    test('peak 시각이 없어도 걸음 번호로 중복을 거른다', () {
      final tracker = straightTracker();
      tracker.update(
        _observation(
          atMs: 1100,
          confirmedSteps: 0,
          confirmedDistanceM: 0,
          previewSteps: 2,
          headingDeg: 90,
          rawPreviewTailPositions: _eastPoints(1, 2),
        ),
      );
      final result = tracker.update(
        _observation(
          atMs: 1600,
          confirmedSteps: 0,
          confirmedDistanceM: 0,
          previewSteps: 3,
          headingDeg: 90,
          // 겹치는 두 걸음(1.7·2.4)이 다시 들어오고 3.1만 새 걸음이다.
          rawPreviewTailPositions: const [
            PdrLocalPoint(1.7, 0),
            PdrLocalPoint(2.4, 0),
            PdrLocalPoint(3.1, 0),
          ],
        ),
      );

      expect(result.previewPosition.eastM, closeTo(3.1, 1e-9));
      expect(result.previewPeakIdsSynthetic, isTrue);
    });

    test('같은 peak 시계열은 배치 구성이 달라도 같은 optimistic 위치를 만든다', () {
      double runWithBatchSize(int batchSize) {
        final tracker = straightTracker();
        final points = _eastPoints(1, 10);
        var confirmedSteps = 0;
        for (var step = 1; step <= 10; step += 1) {
          final tail = points.sublist(confirmedSteps, step + 1);
          final times = <int?>[
            null,
            for (var index = confirmedSteps + 1; index <= step; index += 1)
              index * 500,
          ];
          final confirmNow = step % batchSize == 0;
          tracker.update(
            _observation(
              atMs: step * 500 + 100,
              confirmedSteps: confirmNow ? step : confirmedSteps,
              confirmedDistanceM: (confirmNow ? step : confirmedSteps) * 0.7,
              previewSteps: step,
              headingDeg: 90,
              raw: points[confirmNow ? step : confirmedSteps],
              rawConfirmedStepPositions: confirmNow
                  ? points.sublist(confirmedSteps + 1, step + 1)
                  : const [],
              rawPreviewTailPositions: tail,
              rawPreviewTailPeakTimesMs: times,
              confirmedThroughMs: confirmNow ? step * 500 : null,
            ),
          );
          if (confirmNow) confirmedSteps = step;
        }
        return tracker.result.previewPosition.eastM;
      }

      final single = runWithBatchSize(1);
      expect(runWithBatchSize(2), closeTo(single, 1e-9));
      expect(runWithBatchSize(5), closeTo(single, 1e-9));
      expect(runWithBatchSize(10), closeTo(single, 1e-9));
      expect(single, closeTo(8, 1e-9));
    });

    test('실제 유턴은 optimistic cursor의 후퇴로 반영한다', () {
      final tracker = CorridorPositionTracker(_longStraightGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(25, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );

      tracker.update(
        _observation(
          atMs: 1000,
          confirmedSteps: 0,
          confirmedDistanceM: 0,
          previewSteps: 2,
          headingDeg: 90,
          rawPreviewTailPositions: _eastPoints(25, 2),
          rawPreviewTailPeakTimesMs: const [null, 500, 1000],
        ),
      );
      final forward = tracker.result.previewPosition.eastM;
      expect(forward, closeTo(26.4, 1e-9));

      for (var step = 1; step <= 4; step += 1) {
        tracker.update(
          _observation(
            atMs: 1000 + step * 500,
            confirmedSteps: 0,
            confirmedDistanceM: 0,
            previewSteps: 2 + step,
            headingDeg: 270,
            rawPreviewTailPositions: [
              PdrLocalPoint(26.4 - (step - 1) * 0.7, 0),
              PdrLocalPoint(26.4 - step * 0.7, 0),
            ],
            rawPreviewTailPeakTimesMs: [null, 1000 + step * 500],
          ),
        );
      }

      expect(tracker.result.previewPosition.eastM, lessThan(forward - 2));
    });

    test('시작 직후 두 걸음 뒤로 갔다 유턴해도 전진을 다시 잡는다', () {
      final tracker = CorridorPositionTracker(_longStraightGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(25, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );
      var rawEastM = 25.0;
      var previewSteps = 0;
      var atMs = 0;

      void walk(double deltaEastM) {
        final before = rawEastM;
        rawEastM += deltaEastM;
        previewSteps += 1;
        atMs += 500;
        tracker.update(
          _observation(
            atMs: atMs,
            confirmedSteps: 0,
            confirmedDistanceM: 0,
            previewSteps: previewSteps,
            headingDeg: deltaEastM > 0 ? 90 : 270,
            rawPreviewTailPositions: [
              PdrLocalPoint(before, 0),
              PdrLocalPoint(rawEastM, 0),
            ],
            rawPreviewTailPeakTimesMs: [null, atMs],
          ),
        );
      }

      walk(-0.7);
      walk(-0.7);
      final afterReverse = tracker.result.previewPosition.eastM;
      expect(afterReverse, lessThan(25));

      for (var index = 0; index < 6; index += 1) {
        walk(0.7);
      }

      expect(tracker.result.previewPosition.eastM, greaterThan(26));
      expect(
        tracker.result.previewPosition.eastM,
        greaterThan(afterReverse + 3.5),
        reason: '유턴 후 계속 앞으로 걷는데 역방향 가설에 남으면 안 된다',
      );
    });

    test('강한 경로 연속성 중이어도 180도 역방향 걸음은 따른다', () {
      final tracker = CorridorPositionTracker(_longStraightGraph)
        ..setPreferredRoute(
          edgeIds: const ['straight'],
          nodeIds: const ['start', 'end'],
          preferContinuity: true,
        )
        ..reset(
          initialPosition: const PdrLocalPoint(25, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );

      for (var step = 1; step <= 3; step += 1) {
        tracker.update(
          _observation(
            atMs: step * 500,
            confirmedSteps: 0,
            confirmedDistanceM: 0,
            previewSteps: step,
            headingDeg: 270,
            rawPreviewTailPositions: [
              PdrLocalPoint(25 - (step - 1) * 0.7, 0),
              PdrLocalPoint(25 - step * 0.7, 0),
            ],
            rawPreviewTailPeakTimesMs: [null, step * 500],
          ),
        );
      }

      expect(tracker.result.previewPosition.eastM, lessThan(23.5));
    });

    test('탑승 종점 잠금은 180도 관측과 남은 걸음을 연결 복도로 넘기지 않는다', () {
      final tracker = CorridorPositionTracker(_crossGraph)
        ..setPreferredRoute(
          edgeIds: const ['ab'],
          nodeIds: const ['a', 'b'],
          preferContinuity: true,
          lockTerminal: true,
        )
        ..reset(
          initialPosition: const PdrLocalPoint(8.6, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );

      for (var step = 1; step <= 6; step += 1) {
        tracker.update(
          _observation(
            atMs: step * 500,
            confirmedSteps: 0,
            confirmedDistanceM: 0,
            previewSteps: step,
            headingDeg: 270,
            rawPreviewTailPositions: [
              PdrLocalPoint(8.6 - (step - 1) * 0.7, 0),
              PdrLocalPoint(8.6 - step * 0.7, 0),
            ],
            rawPreviewTailPeakTimesMs: [null, step * 500],
          ),
        );
      }

      expect(tracker.result.optimisticEdgeId, 'ab');
      expect(tracker.result.travelDirectionSign, 1);
      expect(tracker.result.previewPosition, const PdrLocalPoint(10, 0));
    });
  });

  test('도면 y축이 반전되면 위치와 동일하게 heading도 반전한다', () {
    const anchor = PdrAnchor(
      floorId: '1F',
      anchorLocalM: PdrLocalPoint.zero,
      rotationDeg: 0,
      headingReference: HeadingReference.magneticNorth,
      requiresManualRotationCalibration: false,
      source: AnchorSource.userPin,
      confidence: 1,
      axes: PdrToFloorAxes(eastToX: 1, northToX: 0, eastToY: 0, northToY: -1),
    );
    final transform = FloorCoordinateTransform(anchor);

    expect(transform.toFloorBearing(0), closeTo(180, 1e-9));
    expect(transform.toFloorBearing(90), closeTo(90, 1e-9));
    expect(transform.floorBearingToMapBearing(180), closeTo(0, 1e-9));
    expect(
      transform.mapBearingForPdrBearing(0, floorBiasDeg: 20),
      closeTo(340, 1e-9),
      reason: '복도 bias는 floor 좌표에서 더한 뒤 지도 방위로 되돌려야 한다',
    );
  });

  group('교차점 전후 회전 허용 구간', () {
    /// [turnOffsetM]만큼 어긋난 지점에서 북쪽으로 꺾는 보행을 재생한다.
    ///
    /// 음수면 노드(10,0)보다 일찍, 양수면 늦게 꺾는다. 두 경우 모두 실제
    /// 사람이 코너를 도는 방식이고, graph node 좌표를 정확히 밟지 않는다.
    CorridorPositionTracker walkAndTurnNorth({
      required double turnOffsetM,
      int northSteps = 3,
    }) {
      final tracker = CorridorPositionTracker(_crossGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(4, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );
      final turnEastM = 10 + turnOffsetM;
      var atMs = 0;
      var steps = 0;
      var raw = const PdrLocalPoint(4, 0);

      void walk(PdrLocalPoint next, double headingDeg) {
        atMs += 500;
        steps += 1;
        tracker.update(
          _observation(
            atMs: atMs,
            confirmedSteps: steps,
            confirmedDistanceM: steps * 0.7,
            previewSteps: steps,
            headingDeg: headingDeg,
            raw: next,
            rawConfirmedStepPositions: [next],
          ),
        );
        raw = next;
      }

      while (raw.eastM < turnEastM - 1e-9) {
        walk(PdrLocalPoint(math.min(raw.eastM + 0.7, turnEastM), 0), 90);
      }
      for (var index = 1; index <= northSteps; index += 1) {
        walk(PdrLocalPoint(turnEastM, index * 0.7), 0);
      }
      return tracker;
    }

    test('노드보다 3m 일찍 꺾어도 연결된 간선으로 수렴한다', () {
      final tracker = walkAndTurnNorth(turnOffsetM: -3);
      expect(tracker.result.currentEdgeId, 'bc');
    });

    test('노드 근처에서 꺾으면 연결된 간선으로 수렴한다', () {
      final tracker = walkAndTurnNorth(turnOffsetM: 0);
      expect(tracker.result.currentEdgeId, 'bc');
    });

    test('노드보다 3m 늦게 꺾어도 지나온 노드의 연결 간선으로 되돌아간다', () {
      final tracker = walkAndTurnNorth(turnOffsetM: 3);
      expect(tracker.result.currentEdgeId, 'bc');
    });

    test('활성 경로의 짧은 두 코너를 완만하게 잘라도 탑승 간선 가설을 보존한다', () {
      final tracker = CorridorPositionTracker(_doubleTurnGraph)
        ..setPreferredRoute(
          edgeIds: const ['ab', 'bc', 'c-es'],
          nodeIds: const ['a', 'b', 'c', 'es'],
          preferContinuity: true,
        )
        ..reset(
          initialPosition: const PdrLocalPoint(6.5, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );
      final points = <(PdrLocalPoint, double)>[
        (const PdrLocalPoint(7.2, 0), 90),
        (const PdrLocalPoint(7.9, 0.1), 82),
        (const PdrLocalPoint(8.5, 0.35), 68),
        (const PdrLocalPoint(9.0, 0.8), 48),
        (const PdrLocalPoint(9.5, 1.3), 42),
        (const PdrLocalPoint(10.0, 1.8), 48),
        (const PdrLocalPoint(10.6, 2.15), 60),
        (const PdrLocalPoint(11.3, 2.35), 74),
        (const PdrLocalPoint(12.0, 2.4), 86),
        (const PdrLocalPoint(12.7, 2.4), 90),
        (const PdrLocalPoint(13.4, 2.4), 90),
      ];
      var distanceM = 0.0;
      var previous = const PdrLocalPoint(6.5, 0);
      for (var index = 0; index < points.length; index++) {
        final (point, heading) = points[index];
        distanceM += (point - previous).distance;
        tracker.update(
          _observation(
            atMs: (index + 1) * 500,
            confirmedSteps: index + 1,
            confirmedDistanceM: distanceM,
            previewSteps: index + 1,
            headingDeg: heading,
            raw: point,
            rawConfirmedStepPositions: [point],
          ),
        );
        previous = point;
      }

      expect(tracker.result.currentEdgeId, 'c-es');
      expect(tracker.result.correctedPosition.northM, closeTo(2.4, 0.1));
    });

    test('탑승 직전 ㄱ자 간선에서 heading이 늦어도 예상 경로를 계속 따른다', () {
      final tracker = CorridorPositionTracker(_doubleTurnGraph)
        ..setPreferredRoute(
          edgeIds: const ['ab', 'bc', 'c-es'],
          nodeIds: const ['a', 'b', 'c', 'es'],
          preferContinuity: true,
        )
        ..reset(
          initialPosition: const PdrLocalPoint(6.5, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );
      final points = <PdrLocalPoint>[
        const PdrLocalPoint(7.2, 0),
        const PdrLocalPoint(7.9, 0.1),
        const PdrLocalPoint(8.5, 0.35),
        const PdrLocalPoint(9.0, 0.8),
        const PdrLocalPoint(9.5, 1.3),
        const PdrLocalPoint(10.0, 1.8),
        const PdrLocalPoint(10.6, 2.15),
        const PdrLocalPoint(11.3, 2.35),
        const PdrLocalPoint(12.0, 2.4),
      ];
      var distanceM = 0.0;
      var previous = const PdrLocalPoint(6.5, 0);
      for (var index = 0; index < points.length; index++) {
        final point = points[index];
        distanceM += (point - previous).distance;
        tracker.update(
          _observation(
            atMs: (index + 1) * 500,
            confirmedSteps: index + 1,
            confirmedDistanceM: distanceM,
            previewSteps: index + 1,
            headingDeg: 90,
            raw: point,
            rawConfirmedStepPositions: [point],
          ),
        );
        previous = point;
      }

      expect(tracker.result.currentEdgeId, 'c-es');
      expect(tracker.result.previewPosition.northM, closeTo(2.4, 0.2));
    });

    test('다음 경로 간선에서 두 걸음이 확인된 뒤에만 새 직선 epoch를 연다', () {
      final tracker = CorridorPositionTracker(_crossGraph)
        ..setPreferredRoute(
          edgeIds: const ['ab', 'bd'],
          nodeIds: const ['a', 'b', 'd'],
        )
        ..reset(
          initialPosition: const PdrLocalPoint(8.6, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );

      // 화면은 이미 두 걸음 앞서 있다. epoch가 이 cursor를 확정점으로 되감으면
      // 사용자가 보는 marker가 정확히 이 순간 뒤로 튄다.
      tracker.update(
        _observation(
          atMs: 3000,
          confirmedSteps: 0,
          confirmedDistanceM: 0,
          previewSteps: 6,
          headingDeg: 90,
          raw: const PdrLocalPoint(8.6, 0),
          rawPreviewTailPositions: const [
            PdrLocalPoint(8.6, 0),
            PdrLocalPoint(9.3, 0),
            PdrLocalPoint(10, 0),
            PdrLocalPoint(10.7, 0),
            PdrLocalPoint(11.4, 0),
            PdrLocalPoint(12.1, 0),
            PdrLocalPoint(12.8, 0),
          ],
          rawPreviewTailPeakTimesMs: const [
            null,
            500,
            1000,
            1500,
            2000,
            2500,
            3000,
          ],
        ),
      );
      final previewBefore = tracker.result.previewPosition;

      final beforeThreshold = tracker.update(
        _observation(
          atMs: 3200,
          confirmedSteps: 3,
          confirmedDistanceM: 2.1,
          previewSteps: 6,
          headingDeg: 90,
          raw: const PdrLocalPoint(10.7, 0),
          rawConfirmedStepPositions: const [
            PdrLocalPoint(9.3, 0),
            PdrLocalPoint(10, 0),
            PdrLocalPoint(10.7, 0),
          ],
          rawPreviewTailPositions: const [
            PdrLocalPoint(10.7, 0),
            PdrLocalPoint(11.4, 0),
            PdrLocalPoint(12.1, 0),
            PdrLocalPoint(12.8, 0),
          ],
          rawPreviewTailPeakTimesMs: const [1500, 2000, 2500, 3000],
          confirmedThroughMs: 1500,
        ),
      );
      expect(beforeThreshold.currentEdgeId, 'bd');
      expect(beforeThreshold.routeStraightEpochNodeId, isNull);

      final afterThreshold = tracker.update(
        _observation(
          atMs: 3400,
          confirmedSteps: 4,
          confirmedDistanceM: 2.8,
          previewSteps: 6,
          headingDeg: 90,
          raw: const PdrLocalPoint(11.4, 0),
          rawConfirmedStepPositions: const [PdrLocalPoint(11.4, 0)],
          rawPreviewTailPositions: const [
            PdrLocalPoint(11.4, 0),
            PdrLocalPoint(12.1, 0),
            PdrLocalPoint(12.8, 0),
          ],
          rawPreviewTailPeakTimesMs: const [2000, 2500, 3000],
          confirmedThroughMs: 2000,
        ),
      );

      expect(afterThreshold.routeStraightEpochNodeId, 'b');
      expect(afterThreshold.state, CorridorTrackingState.straightTracking);
      expect(afterThreshold.previewPosition, previewBefore);
      expect(afterThreshold.optimisticLeadM, closeTo(1.4, 1e-9));
    });

    test('활성 경로가 있어도 센서가 명확히 이탈하면 비경로 간선이 이긴다', () {
      final tracker = CorridorPositionTracker(_doubleTurnGraph)
        ..setPreferredRoute(
          edgeIds: const ['ab', 'bc', 'c-es'],
          nodeIds: const ['a', 'b', 'c', 'es'],
        )
        ..reset(
          initialPosition: const PdrLocalPoint(6.5, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );
      var distanceM = 0.0;
      var previous = const PdrLocalPoint(6.5, 0);
      final epochNodes = <String>[];
      for (var index = 0; index < 12; index++) {
        final point = PdrLocalPoint(7.2 + index * 0.7, 0);
        distanceM += (point - previous).distance;
        final result = tracker.update(
          _observation(
            atMs: (index + 1) * 500,
            confirmedSteps: index + 1,
            confirmedDistanceM: distanceM,
            previewSteps: index + 1,
            headingDeg: 90,
            raw: point,
            rawConfirmedStepPositions: [point],
          ),
        );
        if (result.routeStraightEpochNodeId case final nodeId?) {
          epochNodes.add(nodeId);
        }
        previous = point;
      }

      expect(tracker.result.currentEdgeId, 'b-straight');
      expect(
        epochNodes,
        isEmpty,
        reason: '경로와 다른 간선을 실제로 택한 보행을 route epoch가 잠그면 안 된다',
      );
    });

    test('교차점을 직진으로 통과하면 회전 후보로 넘어가지 않는다', () {
      final tracker = CorridorPositionTracker(_crossGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(4, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );
      for (var step = 1; step <= 14; step += 1) {
        final raw = PdrLocalPoint(4 + step * 0.7, 0);
        tracker.update(
          _observation(
            atMs: step * 500,
            confirmedSteps: step,
            confirmedDistanceM: step * 0.7,
            previewSteps: step,
            headingDeg: 90,
            raw: raw,
            rawConfirmedStepPositions: [raw],
          ),
        );
      }

      expect(tracker.result.currentEdgeId, 'bd');
      expect(tracker.result.correctedPosition.northM.abs(), lessThan(1e-6));
    });

    test('전환 구간 안에서는 연결된 간선만 후보로 알린다', () {
      final tracker = walkAndTurnNorth(turnOffsetM: -1, northSteps: 1);
      final result = tracker.result;

      expect(result.junctionNodeId, 'b');
      expect(result.junctionDistanceM, lessThanOrEqualTo(3));
      expect(result.junctionCandidateEdgeIds, containsAll(['ab', 'bd', 'bc']));
      expect(
        result.junctionCandidateEdgeIds,
        isNot(contains('ef')),
        reason: '노드 b에 연결되지 않은 평행 간선은 후보가 될 수 없다',
      );
    });

    test('전환 구간 밖 직선 구간에서는 회전 구간 상태가 아니다', () {
      final tracker = CorridorPositionTracker(_crossGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(4, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );
      tracker.update(
        _observation(
          atMs: 500,
          confirmedSteps: 1,
          confirmedDistanceM: 0.7,
          previewSteps: 1,
          headingDeg: 90,
          raw: const PdrLocalPoint(4.7, 0),
          rawConfirmedStepPositions: const [PdrLocalPoint(4.7, 0)],
        ),
      );

      expect(tracker.result.isInJunctionZone, isFalse);
    });

    test('걸음 없이 휴대폰만 돌려서는 간선이 바뀌지 않는다', () {
      final tracker = CorridorPositionTracker(_crossGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(8.5, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );
      for (var step = 1; step <= 5; step += 1) {
        tracker.update(
          _observation(
            atMs: step * 400,
            confirmedSteps: 0,
            confirmedDistanceM: 0,
            previewSteps: 0,
            headingDeg: 0,
            raw: const PdrLocalPoint(8.5, 0),
          ),
        );
      }

      expect(tracker.result.currentEdgeId, 'ab');
      expect(tracker.result.correctedPosition.eastM, closeTo(8.5, 0.5));
    });
  });

  group('하차 직후 다음 간선 선택', () {
    /// 에스컬레이터 도착 노드(10,0)에서 새 앵커를 잡은 직후를 재현한다.
    ///
    /// 사용자는 아직 동쪽을 보고 서 있고([initialHeadingDeg]), 그 상태에서
    /// 실제로 [stepHeadingDeg] 방향으로 걷기 시작한다. 바라보는 방향은 약한
    /// 근거일 뿐이고 실제 걸음이 간선을 정해야 한다.
    CorridorPositionTracker landAndWalk({
      required double stepHeadingDeg,
      required PdrLocalPoint stepDelta,
      int steps = 2,
    }) {
      final tracker = CorridorPositionTracker(_crossGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(10, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );
      var raw = const PdrLocalPoint(10, 0);
      for (var step = 1; step <= steps; step += 1) {
        raw = PdrLocalPoint(
          raw.eastM + stepDelta.eastM,
          raw.northM + stepDelta.northM,
        );
        tracker.update(
          _observation(
            atMs: step * 500,
            confirmedSteps: step,
            confirmedDistanceM: step * 0.7,
            previewSteps: step,
            headingDeg: stepHeadingDeg,
            raw: raw,
            rawConfirmedStepPositions: [raw],
          ),
        );
      }
      return tracker;
    }

    test('직진 하차는 두 걸음 안에 정면 간선으로 수렴한다', () {
      final tracker = landAndWalk(
        stepHeadingDeg: 90,
        stepDelta: const PdrLocalPoint(0.7, 0),
      );
      expect(tracker.result.currentEdgeId, 'bd');
    });

    test('좌회전 하차는 바라보던 방향이 아니라 걸음 방향을 따른다', () {
      final tracker = landAndWalk(
        stepHeadingDeg: 0,
        stepDelta: const PdrLocalPoint(0, 0.7),
      );
      expect(tracker.result.currentEdgeId, 'bc');
    });

    test('우회전 하차도 두 걸음 안에 연결 간선으로 수렴한다', () {
      final tracker = landAndWalk(
        stepHeadingDeg: 270,
        stepDelta: const PdrLocalPoint(-0.7, 0),
      );
      expect(tracker.result.currentEdgeId, 'ab');
    });

    test('걸음 전에는 도착 노드에 연결된 간선을 모두 후보로 둔다', () {
      final tracker = CorridorPositionTracker(_crossGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(10, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );
      final result = tracker.update(
        _observation(
          atMs: 300,
          confirmedSteps: 0,
          confirmedDistanceM: 0,
          previewSteps: 0,
          headingDeg: 90,
          raw: const PdrLocalPoint(10, 0),
        ),
      );

      expect(result.junctionNodeId, 'b');
      expect(result.junctionCandidateEdgeIds, containsAll(['ab', 'bd', 'bc']));
    });
  });

  group('CorridorPositionTracker', () {
    test('직선에서는 위치를 간선에 고정하고 heading bias를 복도 방향으로 수렴시킨다', () {
      final tracker = CorridorPositionTracker(_longStraightGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(1, 0),
          initialHeadingDeg: 80,
          timestampMs: 0,
        );

      for (var step = 1; step <= 10; step += 1) {
        tracker.update(
          _observation(
            atMs: step * 500,
            confirmedSteps: step,
            confirmedDistanceM: step * 0.7,
            previewSteps: step,
            headingDeg: 80,
            raw: PdrLocalPoint(1 + step * 0.7, step * 0.7 * 0.173648),
          ),
        );
      }

      final result = tracker.result;
      expect(result.currentEdgeId, 'straight');
      expect(result.state, CorridorTrackingState.straightTracking);
      expect(result.headingBiasDeg, greaterThan(0));
      expect(result.correctedHeadingDeg, closeTo(90, 1e-9));
      expect(result.correctedPosition.northM, closeTo(0, 1e-9));
      expect(
        result.correctedPath.every((point) => point.northM.abs() < 1e-9),
        isTrue,
      );
    });

    test('원본이 평행 복도에 가까워져도 연결 노드 도달 전에는 전환하지 않는다', () {
      final tracker = CorridorPositionTracker(_crossGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(2, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );

      for (var step = 1; step <= 8; step += 1) {
        tracker.update(
          _observation(
            atMs: step * 500,
            confirmedSteps: step,
            confirmedDistanceM: step * 0.7,
            previewSteps: step,
            headingDeg: 90,
            raw: PdrLocalPoint(2 + step * 0.7, 2.8),
          ),
        );
      }

      expect(tracker.result.currentEdgeId, 'ab');
      expect(tracker.result.correctedPosition.northM.abs(), lessThan(0.1));
    });

    test('초록 배치는 복원된 걸음별 방향으로 간선 진행 방향을 정한다', () {
      final tracker = CorridorPositionTracker(_longStraightGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(1, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );

      final result = tracker.update(
        CorridorObservation(
          timestampMs: 1000,
          rawConfirmedPosition: const PdrLocalPoint(2.4, 0),
          confirmedSteps: 2,
          confirmedDistanceM: 1.4,
          rawPreviewPosition: const PdrLocalPoint(2.4, 0),
          previewSteps: 2,
          // 배치가 늦게 도착한 시점에는 폰이 이미 동쪽을 향한 상황.
          sensorHeadingDeg: 90,
          hasHeading: true,
          rawConfirmedStepPositions: const [
            PdrLocalPoint(1.7, 0),
            PdrLocalPoint(2.4, 0),
          ],
        ),
      );

      expect(result.correctedPosition.eastM, closeTo(2.4, 1e-9));
      expect(result.correctedPosition.northM, closeTo(0, 1e-9));
    });

    test('초록보다 앞선 주황 tail은 확정 위치를 바꾸지 않고 보라 preview만 진행한다', () {
      final tracker = CorridorPositionTracker(_longStraightGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(1, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );

      final result = tracker.update(
        _observation(
          atMs: 1000,
          confirmedSteps: 0,
          confirmedDistanceM: 0,
          previewSteps: 3,
          headingDeg: 90,
          rawPreviewTailPositions: const [
            PdrLocalPoint(1, 0),
            PdrLocalPoint(1.7, 0),
            PdrLocalPoint(2.4, 0),
            PdrLocalPoint(3.1, 0),
          ],
        ),
      );

      expect(result.correctedPosition, const PdrLocalPoint(1, 0));
      expect(result.previewPosition.eastM, closeTo(3.1, 1e-9));
      expect(result.previewPosition.northM, closeTo(0, 1e-9));
      expect(result.previewPath, hasLength(4));
    });

    test('주황 tail의 직진-회전 형태를 연결 간선 후보와 비교한다', () {
      final tracker = CorridorPositionTracker(_crossGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(9, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );

      final result = tracker.update(
        _observation(
          atMs: 1000,
          confirmedSteps: 0,
          confirmedDistanceM: 0,
          previewSteps: 4,
          headingDeg: 0,
          rawPreviewTailPositions: const [
            PdrLocalPoint(9, 0),
            PdrLocalPoint(9.7, 0),
            PdrLocalPoint(10, 0),
            PdrLocalPoint(10, 0.7),
            PdrLocalPoint(10, 1.4),
          ],
        ),
      );

      expect(result.correctedPosition, const PdrLocalPoint(9, 0));
      expect(result.previewPosition.eastM, closeTo(10, 1e-9));
      expect(result.previewPosition.northM, closeTo(1.4, 1e-9));
      expect(result.previewCandidateEdgeIds, contains('bc'));
    });

    test('교차로에서 먼 곳에서 휴대폰만 돌리면 회전 후보로 진입하지 않는다', () {
      final tracker = CorridorPositionTracker(_crossGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(2, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );

      final result = tracker.update(
        _observation(
          atMs: 800,
          confirmedSteps: 0,
          confirmedDistanceM: 0,
          previewSteps: 1,
          headingDeg: 0,
        ),
      );

      expect(result.state, CorridorTrackingState.straightTracking);
      expect(result.currentEdgeId, 'ab');
    });

    test('복도 중간 유턴은 교차로 진입이나 다른 간선 전환으로 보지 않는다', () {
      final tracker = CorridorPositionTracker(_crossGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(5, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );

      final result = tracker.update(
        _observation(
          atMs: 1000,
          confirmedSteps: 2,
          confirmedDistanceM: 1.4,
          previewSteps: 2,
          headingDeg: 270,
        ),
      );

      expect(result.state, CorridorTrackingState.straightTracking);
      expect(result.currentEdgeId, 'ab');
    });

    test('heading이 계속 흔들려도 보정 경로는 활성 간선 밖으로 나가지 않는다', () {
      final tracker = CorridorPositionTracker(_longStraightGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(45, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );

      const headings = [40.0, 150.0, 300.0, 20.0, 280.0];
      for (var step = 1; step <= headings.length; step += 1) {
        tracker.update(
          _observation(
            atMs: step * 500,
            confirmedSteps: step,
            confirmedDistanceM: step * 0.7,
            previewSteps: step,
            headingDeg: headings[step - 1],
            raw: PdrLocalPoint(45 + step * 0.4, step * 0.8),
            rawConfirmedStepPositions: [
              PdrLocalPoint(45 + step * 0.4, step * 0.8),
            ],
          ),
        );
      }

      expect(
        tracker.result.correctedPath.every(
          (point) =>
              point.northM.abs() < 1e-9 &&
              point.eastM >= 0 &&
              point.eastM <= 50,
        ),
        isTrue,
      );
    });

    test('시간 변화가 없는 heading 오차는 교차로 회전으로 오인하지 않는다', () {
      final tracker = CorridorPositionTracker(_crossGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(8.5, 0),
          initialHeadingDeg: 20,
          timestampMs: 0,
        );

      tracker.update(
        _observation(
          atMs: 600,
          confirmedSteps: 0,
          confirmedDistanceM: 0,
          previewSteps: 1,
          headingDeg: 20,
        ),
      );
      final result = tracker.update(
        _observation(
          atMs: 1200,
          confirmedSteps: 0,
          confirmedDistanceM: 0,
          previewSteps: 2,
          headingDeg: 20,
        ),
      );

      expect(result.state, CorridorTrackingState.straightTracking);
      expect(result.pendingEdgeId, isNull);
    });

    test('진행 방향을 잠근 뒤 휴대폰 heading이 반대로 튀어도 위치와 표시 방향은 유지한다', () {
      final tracker = CorridorPositionTracker(_longStraightGraph)
        ..reset(
          initialPosition: const PdrLocalPoint(5, 0),
          initialHeadingDeg: 90,
          timestampMs: 0,
        );

      tracker.update(
        _observation(
          atMs: 500,
          confirmedSteps: 1,
          confirmedDistanceM: 0.7,
          previewSteps: 1,
          headingDeg: 90,
          raw: const PdrLocalPoint(5.7, 0),
          rawConfirmedStepPositions: const [PdrLocalPoint(5.7, 0)],
        ),
      );
      final result = tracker.update(
        _observation(
          atMs: 1000,
          confirmedSteps: 2,
          confirmedDistanceM: 1.4,
          previewSteps: 2,
          headingDeg: 270,
          raw: const PdrLocalPoint(6.4, 0),
          rawConfirmedStepPositions: const [PdrLocalPoint(6.4, 0)],
        ),
      );

      expect(result.correctedPosition.eastM, closeTo(6.4, 1e-9));
      expect(result.correctedHeadingDeg, closeTo(90, 1e-9));
    });
  });

  group('직선 헤딩 보정 잠금', () {
    const correctionConfig = CorridorTrackerConfig(
      headingCorrectionMinEvidenceM: 4.2,
      headingCorrectionMinEvidenceSamples: 6,
      headingCorrectionMaxSpreadDeg: 1,
    );

    test('최소 거리 전에는 learning이고 충분한 일관성 뒤 +20도로 한 번 잠긴다', () {
      final tracker =
          CorridorPositionTracker(_longStraightGraph, config: correctionConfig)
            ..reset(
              initialPosition: const PdrLocalPoint(5, 0),
              initialHeadingDeg: 70,
              timestampMs: 0,
            );
      var raw = const PdrLocalPoint(5, 0);

      CorridorTrackingResult walk(int step, double bearingDeg) {
        raw = raw + _scaleForTest(pdrDirectionForBearing(bearingDeg), 0.7);
        return tracker.update(
          _observation(
            atMs: step * 500,
            confirmedSteps: step,
            confirmedDistanceM: step * 0.7,
            previewSteps: step,
            headingDeg: bearingDeg,
            raw: raw,
            rawConfirmedStepPositions: [raw],
          ),
        );
      }

      for (var step = 1; step <= 5; step += 1) {
        walk(step, 70);
      }
      expect(
        tracker.result.headingCorrectionState,
        HeadingCorrectionState.learning,
      );
      expect(tracker.result.lockedHeadingCorrectionDeg, isNull);
      expect(tracker.result.headingCorrectionEvidenceDistanceM, lessThan(4.2));

      var step = 6;
      var beforeLock = tracker.result.previewPosition;
      var locked = walk(step, 70);
      while (locked.headingCorrectionState != HeadingCorrectionState.locked &&
          step < 10) {
        step += 1;
        beforeLock = tracker.result.previewPosition;
        locked = walk(step, 70);
      }

      expect(locked.headingCorrectionState, HeadingCorrectionState.locked);
      expect(locked.lockedHeadingCorrectionDeg, closeTo(20, 0.2));
      expect(locked.headingCorrectionEvidenceSpreadDeg, lessThan(0.1));
      expect(
        (locked.previewPosition - beforeLock).distance,
        lessThanOrEqualTo(0.9),
        reason: '잠금 상태 전환 자체가 마커를 재배치하면 안 된다',
      );

      // 실제 회전과 유턴은 잠금값을 다시 학습하지 않고 그대로 적용한다.
      final afterCorner = walk(7, 160);
      expect(afterCorner.headingBiasDeg, closeTo(20, 0.2));
      expect(
        normalizePdrBearing(160 + afterCorner.headingBiasDeg),
        closeTo(180, 0.2),
      );
      final afterUturn = walk(8, 250);
      expect(afterUturn.headingBiasDeg, closeTo(20, 0.2));
      expect(afterUturn.headingCorrectionState, HeadingCorrectionState.locked);
    });

    test('tracker reset은 잠금과 이전 층의 근거를 모두 버린다', () {
      final tracker =
          CorridorPositionTracker(
            _longStraightGraph,
            config: const CorridorTrackerConfig(
              headingCorrectionMinEvidenceM: 1.4,
              headingCorrectionMinEvidenceSamples: 2,
            ),
          )..reset(
            initialPosition: const PdrLocalPoint(5, 0),
            initialHeadingDeg: 70,
            timestampMs: 0,
          );
      var raw = const PdrLocalPoint(5, 0);
      for (var step = 1; step <= 3; step += 1) {
        raw = raw + _scaleForTest(pdrDirectionForBearing(70), 0.7);
        tracker.update(
          _observation(
            atMs: step * 500,
            confirmedSteps: step,
            confirmedDistanceM: step * 0.7,
            previewSteps: step,
            headingDeg: 70,
            raw: raw,
            rawConfirmedStepPositions: [raw],
          ),
        );
      }
      expect(
        tracker.result.headingCorrectionState,
        HeadingCorrectionState.locked,
      );

      tracker.reset(
        initialPosition: const PdrLocalPoint(2, 0),
        initialHeadingDeg: 100,
        timestampMs: 5000,
        initialConfirmedSteps: 3,
        initialConfirmedDistanceM: 2.1,
        initialPreviewSteps: 3,
      );

      expect(
        tracker.result.headingCorrectionState,
        HeadingCorrectionState.learning,
      );
      expect(tracker.result.headingBiasDeg, 0);
      expect(tracker.result.lockedHeadingCorrectionDeg, isNull);
      expect(tracker.result.headingCorrectionEvidenceDistanceM, 0);
    });

    test('평행 후보가 애매하거나 경로 prior만 고른 간선에서는 잠그지 않는다', () {
      final ambiguous =
          CorridorPositionTracker(
            _parallelGraph,
            config: const CorridorTrackerConfig(
              seedRadiusM: 8,
              seedPenaltyDegM: 0,
              ambiguousMarginDeg: 1000,
              headingCorrectionMinEvidenceM: 1.4,
              headingCorrectionMinEvidenceSamples: 2,
            ),
          )..reset(
            initialPosition: const PdrLocalPoint(2, 3.5),
            initialHeadingDeg: 90,
            timestampMs: 0,
          );
      for (var step = 1; step <= 8; step += 1) {
        ambiguous.update(
          _observation(
            atMs: step * 500,
            confirmedSteps: step,
            confirmedDistanceM: step * 0.7,
            previewSteps: step,
            headingDeg: 90,
            raw: PdrLocalPoint(2 + step * 0.7, 3.5),
            rawConfirmedStepPositions: [PdrLocalPoint(2 + step * 0.7, 3.5)],
          ),
        );
      }
      expect(
        ambiguous.result.headingCorrectionState,
        HeadingCorrectionState.learning,
      );
      expect(ambiguous.result.headingCorrectionEvidenceDistanceM, 0);

      final priorOnly =
          CorridorPositionTracker(
              _parallelGraph,
              config: const CorridorTrackerConfig(
                seedRadiusM: 8,
                seedPenaltyDegM: 0,
                positionalToleranceM: 0,
                positionalWeightDegPerM: 10,
                routePreferenceMarginDeg: 1000,
                headingCorrectionMinEvidenceM: 1.4,
                headingCorrectionMinEvidenceSamples: 2,
              ),
            )
            ..setPreferredRoute(
              edgeIds: const ['high'],
              nodeIds: const ['high-start', 'high-end'],
            )
            ..reset(
              initialPosition: const PdrLocalPoint(2, 0),
              initialHeadingDeg: 90,
              timestampMs: 0,
            );
      for (var step = 1; step <= 5; step += 1) {
        priorOnly.update(
          _observation(
            atMs: step * 500,
            confirmedSteps: step,
            confirmedDistanceM: step * 0.7,
            previewSteps: step,
            headingDeg: 90,
            raw: PdrLocalPoint(2 + step * 0.7, 0),
            rawConfirmedStepPositions: [PdrLocalPoint(2 + step * 0.7, 0)],
          ),
        );
      }
      expect(priorOnly.result.currentEdgeId, 'high');
      expect(
        priorOnly.result.headingCorrectionState,
        HeadingCorrectionState.learning,
      );
      expect(priorOnly.result.headingCorrectionEvidenceDistanceM, 0);
    });
  });
}

PdrLocalPoint _scaleForTest(PdrLocalPoint point, double scale) =>
    PdrLocalPoint(point.eastM * scale, point.northM * scale);
