import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import '../../../../domain/guidance/corridor_tracking.dart';

/// 실시간 preview 걸음 하나.
///
/// [peakId]가 **적용 식별자**다. 같은 걸음이 preview로 한 번, confirmed 배치로
/// 다시 한 번 보고돼도 optimistic cursor는 이 값으로 중복을 걸러 한 번만
/// 전진한다. 배치 크기를 어떻게 잘라도 표시 위치 시계열이 같아지는 근거다.
class TimedPreviewStep {
  const TimedPreviewStep({required this.peakId, required this.rawPoint});

  final int peakId;
  final PdrLocalPoint rawPoint;
}

class CorridorObservation {
  const CorridorObservation({
    required this.timestampMs,
    required this.rawConfirmedPosition,
    required this.confirmedSteps,
    required this.confirmedDistanceM,
    required this.rawPreviewPosition,
    required this.previewSteps,
    required this.sensorHeadingDeg,
    required this.hasHeading,
    this.rawConfirmedStepPositions = const [],
    this.rawPreviewTailPositions = const [],
    this.rawPreviewTailPeakTimesMs = const [],
    this.confirmedThroughMs,
  });

  final int timestampMs;
  final PdrLocalPoint rawConfirmedPosition;
  final int confirmedSteps;
  final double confirmedDistanceM;
  final PdrLocalPoint rawPreviewPosition;
  final int previewSteps;
  final double sensorHeadingDeg;
  final bool hasHeading;

  /// 직전 snapshot 이후 초록 경로에 추가된 걸음별 floor 좌표.
  ///
  /// 코어가 stepPeakTimes와 과거 heading으로 이미 복원한 점들이므로, 배치
  /// 수신 시점의 최신 heading 하나로 전체 배치를 다시 그리지 않는다.
  final List<PdrLocalPoint> rawConfirmedStepPositions;

  /// 아직 초록으로 확정되지 않은 최근 주황 경로의 floor 좌표.
  ///
  /// 첫 점은 tail 직전 위치이며 이후 점마다 한 걸음의 이동 벡터를 만든다.
  /// 확정 상태에는 반영하지 않고 화면용 preview에만 사용한다.
  final List<PdrLocalPoint> rawPreviewTailPositions;

  /// [rawPreviewTailPositions]와 **같은 인덱스**의 accepted peak 시각.
  ///
  /// 비어 있거나 길이가 다르면 세션 안에서만 유효한 합성 식별자로 폴백한다
  /// ([CorridorTrackingResult.previewPeakIdsSynthetic]가 true가 된다).
  final List<int?> rawPreviewTailPeakTimesMs;

  /// 확정 배치가 소비한 시간창의 끝. 이 시각 이하의 preview peak는 이미
  /// 확정으로 넘어갔으므로 optimistic cursor를 다시 전진시키지 않는다.
  final int? confirmedThroughMs;

  /// tail 직전 위치. 첫 preview 걸음의 이동 벡터 기준점이다.
  PdrLocalPoint? get previewTailOriginM =>
      rawPreviewTailPositions.isEmpty ? null : rawPreviewTailPositions.first;

  /// tail을 식별자가 붙은 걸음 목록으로 편다.
  ///
  /// 시각이 없으면 누적 preview 걸음 번호로 합성한다. 누적값이라 단조 증가하고
  /// 배치 구성과 무관하므로, 시각이 없는 Android·옛 fixture에서도 같은 걸음이
  /// 두 번 적용되지 않는다. 실제 시각과 섞이지 않게 음수로 만든다.
  List<TimedPreviewStep> get timedPreviewSteps {
    final points = rawPreviewTailPositions;
    if (points.length < 2) return const [];
    final times = rawPreviewTailPeakTimesMs.length == points.length
        ? rawPreviewTailPeakTimesMs
        : const <int?>[];
    final movementCount = points.length - 1;
    return [
      for (var index = 1; index < points.length; index += 1)
        TimedPreviewStep(
          peakId:
              (times.isEmpty ? null : times[index]) ??
              -(previewSteps - (movementCount - index) + 1),
          rawPoint: points[index],
        ),
    ];
  }

  /// tail 안에 시각이 빠진 걸음이 있는지. 진단 warning의 근거다.
  bool get hasSyntheticPreviewPeakIds {
    final points = rawPreviewTailPositions;
    if (points.length < 2) return false;
    if (rawPreviewTailPeakTimesMs.length != points.length) return true;
    for (var index = 1; index < points.length; index += 1) {
      if (rawPreviewTailPeakTimesMs[index] == null) return true;
    }
    return false;
  }
}

class CorridorTrackingResult {
  const CorridorTrackingResult({
    required this.state,
    required this.correctedPosition,
    required this.correctedHeadingDeg,
    required this.headingBiasDeg,
    required this.currentEdgeId,
    required this.currentEdgeProgressM,
    required this.travelDirectionSign,
    required this.pendingEdgeId,
    required this.lastConfirmedNodeId,
    required this.correctedPath,
    required this.previewPosition,
    required this.previewHeadingDeg,
    required this.previewPath,
    required this.previewCandidateEdgeIds,
    required this.previewIsAmbiguous,
    required this.rawConfirmedPosition,
    required this.rawPreviewPosition,
    required this.confirmedDisplacementM,
    required this.optimisticLeadM,
    required this.optimisticEdgeId,
    required this.optimisticEdgeProgressM,
    required this.previewPeakIdsSynthetic,
    required this.junctionNodeId,
    required this.junctionDistanceM,
    required this.junctionCandidateEdgeIds,
    required this.leaderRelocated,
    this.optimisticStepAdvances = const [],
  });

  final CorridorTrackingState state;
  final PdrLocalPoint correctedPosition;

  /// 지금 걷고 있다고 보는 **간선의 방위**. 경로 진행·역주행 판정의 기준이다.
  final double correctedHeadingDeg;

  final double headingBiasDeg;
  final String? currentEdgeId;
  final double currentEdgeProgressM;
  final int travelDirectionSign;
  final String? pendingEdgeId;
  final String? lastConfirmedNodeId;
  final List<PdrLocalPoint> correctedPath;
  final PdrLocalPoint previewPosition;
  final double previewHeadingDeg;
  final List<PdrLocalPoint> previewPath;
  final List<String> previewCandidateEdgeIds;
  final bool previewIsAmbiguous;
  final PdrLocalPoint rawConfirmedPosition;
  final PdrLocalPoint rawPreviewPosition;

  /// 이번 확정 배치 전후 보정 위치의 직선거리. 대표 가설 교체로 생긴 위치
  /// 재해석까지 포함할 수 있어 실제 보행 거리와는 구분한다.
  final double confirmedDisplacementM;

  /// 확정 cursor에서 optimistic cursor까지 그래프 경로 길이(m).
  ///
  /// 선행분을 따로 "안정화"하지 않는다. optimistic beam이 실제로 태운 거리에서
  /// 확정 보행 거리를 뺀 값이라, 배치가 도착해도 정의상 뒤로 가지 않는다.
  final double optimisticLeadM;

  /// optimistic cursor가 올라타 있는 간선과 그 위 진행 거리.
  final String? optimisticEdgeId;
  final double optimisticEdgeProgressM;

  /// preview peak 식별자를 accepted peak 시각이 아니라 걸음 번호로 합성했는지.
  final bool previewPeakIdsSynthetic;

  /// 지금 통과 중인 회전 허용 구간의 graph node. 구간 밖이면 null.
  final String? junctionNodeId;

  /// [junctionNodeId]까지(또는 그 node에서) 남은 거리(m).
  final double junctionDistanceM;

  /// 그 node에 **실제로 연결된** 간선 후보. 없는 길은 여기에 나타나지 않는다.
  final List<String> junctionCandidateEdgeIds;

  /// 회전 허용 구간 안인지. 재탐색을 잠시 유예할지 판단하는 신호다.
  bool get isInJunctionZone => junctionNodeId != null;

  /// 보정 위치 변화가 이번 확정 보행 거리로 설명되지 않는 대표 가설 재배치인지.
  final bool leaderRelocated;

  /// 이번 update에서 처음 적용된 preview peak별 이동 사건.
  final List<OptimisticStepAdvance> optimisticStepAdvances;
}
