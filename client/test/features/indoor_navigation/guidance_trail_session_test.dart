import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_pdr_core/indoor_pdr_core.dart';
import 'package:navigation_client/features/indoor_navigation/application/corridor_position_tracker.dart';
import 'package:navigation_client/features/indoor_navigation/application/guidance_trail_session.dart';
import 'package:navigation_client/domain/guidance/corridor_tracking.dart';

CorridorTrackingResult _result({
  required PdrLocalPoint corrected,
  required List<PdrLocalPoint> path,
  List<PdrLocalPoint> preview = const [],
}) => CorridorTrackingResult(
  state: CorridorTrackingState.straightTracking,
  correctedPosition: corrected,
  correctedHeadingDeg: 90,
  headingBiasDeg: 0,
  currentEdgeId: 'edge',
  currentEdgeProgressM: corrected.eastM,
  travelDirectionSign: 1,
  pendingEdgeId: null,
  lastConfirmedNodeId: null,
  correctedPath: path,
  previewPosition: preview.isEmpty ? corrected : preview.last,
  matchedPreviewPosition: preview.isEmpty ? corrected : preview.last,
  previewUsesContinuityShadow: false,
  previewHeadingDeg: 90,
  previewPath: preview,
  previewCandidateEdgeIds: const ['edge'],
  previewIsAmbiguous: false,
  rawConfirmedPosition: corrected,
  rawPreviewPosition: preview.isEmpty ? corrected : preview.last,
  confirmedDisplacementM: 0,
  optimisticLeadM: 0,
  optimisticEdgeId: 'edge',
  optimisticEdgeProgressM: 0,
  previewPeakIdsSynthetic: false,
  junctionNodeId: null,
  junctionDistanceM: double.infinity,
  junctionCandidateEdgeIds: const [],
  leaderRelocated: false,
);

void main() {
  test('재탐색과 무관하게 시작 이후 확정 궤적을 누적한다', () {
    final session = GuidanceTrailSession()
      ..start(
        floorId: 'B2',
        result: _result(
          corrected: const PdrLocalPoint(1, 0),
          path: const [PdrLocalPoint(0, 0), PdrLocalPoint(1, 0)],
        ),
      )
      ..update(
        floorId: 'B2',
        result: _result(
          corrected: const PdrLocalPoint(3, 0),
          path: const [
            PdrLocalPoint(0, 0),
            PdrLocalPoint(1, 0),
            PdrLocalPoint(2, 0),
            PdrLocalPoint(3, 0),
          ],
        ),
      );

    expect(session.segmentsForFloor('B2').single, const [
      PdrLocalPoint(1, 0),
      PdrLocalPoint(2, 0),
      PdrLocalPoint(3, 0),
    ]);
  });

  test('preview는 화면 반환값에만 붙고 확정 이력에는 저장되지 않는다', () {
    final session = GuidanceTrailSession()
      ..start(
        floorId: '1F',
        result: _result(
          corrected: const PdrLocalPoint(0, 0),
          path: const [PdrLocalPoint(0, 0)],
        ),
      );

    expect(
      session
          .segmentsForFloor(
            '1F',
            previewPath: const [PdrLocalPoint(0, 0), PdrLocalPoint(0.7, 0)],
          )
          .single
          .last,
      const PdrLocalPoint(0.7, 0),
    );
    expect(
      session.segmentsForFloor('1F').single.last,
      const PdrLocalPoint(0, 0),
    );
  });

  test('큰 재배치는 회색 순간이동 선으로 잇지 않는다', () {
    final session = GuidanceTrailSession()
      ..start(
        floorId: '1F',
        result: _result(
          corrected: const PdrLocalPoint(0, 0),
          path: const [PdrLocalPoint(0, 0)],
        ),
      )
      ..update(
        floorId: '1F',
        result: _result(
          corrected: const PdrLocalPoint(10, 0),
          path: const [PdrLocalPoint(9, 0), PdrLocalPoint(10, 0)],
        ),
      );

    expect(session.segmentsForFloor('1F'), hasLength(2));
  });

  test('새 목적지 길안내 시작은 이전 회색 이력을 지운다', () {
    final session = GuidanceTrailSession()
      ..start(
        floorId: '1F',
        result: _result(
          corrected: const PdrLocalPoint(0, 0),
          path: const [PdrLocalPoint(0, 0)],
        ),
      )
      ..start(
        floorId: '2F',
        result: _result(
          corrected: const PdrLocalPoint(5, 5),
          path: const [PdrLocalPoint(5, 5)],
        ),
      );

    expect(session.segmentsForFloor('1F'), isEmpty);
    expect(
      session.segmentsForFloor('2F').single.single,
      const PdrLocalPoint(5, 5),
    );
  });
}
