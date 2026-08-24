import 'pdr_local_point.dart';
import 'quality.dart';

/// 주황(accel preview) 경로 스냅샷. 독립 거리 관측치이자 품질 신호다.
/// confirmed(초록) 위치·거리·걸음수에는 절대 반영하지 않는다.
class PdrPreview {
  const PdrPreview({
    required this.position,
    required this.path,
    required this.steps,
    required this.distanceM,
    this.acceptedPeakTimesMs = const [null],
  });

  final PdrLocalPoint position;
  final List<PdrLocalPoint> path;
  final int steps;
  final double distanceM;

  /// [path]와 **같은 길이·같은 인덱스**로 정렬된, 실제 preview에 반영된 peak 시각.
  ///
  /// 네이티브 `stepPeakTimes` 원본이 아니다. [AccelPreviewTrack]이 간격·cadence·
  /// lead cap으로 거부한 peak는 경로에도 없고 여기에도 없다. 소비자는
  /// `acceptedPeakTimesMs[i]`가 `path[i]`를 만든 peak라고 가정해도 된다.
  ///
  /// 시작점(원점)에는 대응하는 peak가 없으므로 `null`이다. 한 이벤트가 여러 peak를
  /// 한꺼번에 실어 오면(`delta > 1`) 코어가 아는 시각은 `latestPeakMs` 하나뿐이라
  /// 같은 값이 반복 저장된다 — 인덱스 정렬을 깨지 않기 위한 의도된 동작이다.
  ///
  /// 네이티브는 peak 시각을 최근 20초만 보관하지만 이 배열은 코어가 독립적으로
  /// 들고 있으므로 path가 trim되기 전까지 남는다.
  final List<int?> acceptedPeakTimesMs;
}

/// confirmed(초록) 경로에 마지막으로 반영된 CMPedometer 배치의 식별 정보.
///
/// snapshot은 motion 이벤트마다 반복 방출되므로, 시간창만 보고 소비하면 같은
/// 배치를 여러 번 소비하게 된다. [batchId]로 중복 소비를 막을 수 있다.
class PdrAppliedBatch {
  const PdrAppliedBatch({
    required this.batchId,
    required this.spanStartMs,
    required this.spanEndMs,
    required this.appliedSteps,
    required this.appliedDistanceM,
    this.consumedPreviewSteps,
    this.acknowledgedPreviewSteps,
  });

  /// 세션 안에서 단조 증가한다. 같은 값이면 이미 소비한 배치다.
  final int batchId;

  /// 이 배치가 덮는 시간창. tracking split이 적용된 뒤의 값이다.
  final int? spanStartMs;
  final int? spanEndMs;

  final int appliedSteps;
  final double appliedDistanceM;

  /// 이번 배치가 실제로 대응시킨 accel preview 걸음 수.
  ///
  /// 시간창 안의 peak 수와 [appliedSteps]는 같지 않을 수 있으므로 별도 값이다.
  final int? consumedPreviewSteps;

  /// 세션 시작부터 이 배치까지 대응이 끝난 preview 걸음의 누적 번호.
  /// null은 시간창만 기록하던 이전 snapshot/fixture다.
  final int? acknowledgedPreviewSteps;
}

/// Android RoNIN 자동보폭 비교 경로.
///
/// STEP_COUNTER와 기존 heading은 confirmed 경로와 동일하고, 한 걸음 거리만
/// RoNIN 수평 속도/cadence 후보로 바꾼다. 제품 위치에는 사용하지 않는다.
class PdrRoninTrack {
  const PdrRoninTrack({
    required this.supported,
    required this.modelReady,
    required this.position,
    required this.path,
    required this.steps,
    required this.distanceM,
    required this.effectiveStrideM,
    required this.model,
    required this.status,
    this.rawStrideM,
    this.speedMps,
    this.speedStdMps,
    this.cadenceHz,
  });

  const PdrRoninTrack.empty()
    : supported = false,
      modelReady = false,
      position = PdrLocalPoint.zero,
      path = const [PdrLocalPoint.zero],
      steps = 0,
      distanceM = 0,
      effectiveStrideM = 0.70,
      model = null,
      status = 'unsupported',
      rawStrideM = null,
      speedMps = null,
      speedStdMps = null,
      cadenceHz = null;

  final bool supported;
  final bool modelReady;
  final PdrLocalPoint position;
  final List<PdrLocalPoint> path;
  final int steps;
  final double distanceM;
  final double effectiveStrideM;
  final String? model;
  final String status;
  final double? rawStrideM;
  final double? speedMps;
  final double? speedStdMps;
  final double? cadenceHz;
}

/// 코어가 내보내는 관측 스냅샷. UI는 이것을 구독해 렌더한다.
class PdrSnapshot {
  const PdrSnapshot({
    required this.position,
    required this.path,
    required this.steps,
    required this.distanceM,
    required this.orientationHeadingDeg,
    required this.walkingHeadingDeg,
    required this.hasHeading,
    required this.preview,
    required this.quality,
    this.ronin = const PdrRoninTrack.empty(),
    this.lastAppliedBatch,
  });

  /// 초록 confirmed 센서 원본 위치. 로컬 미터, 세션 시작점 기준.
  ///
  /// 제품 현재 위치는 클라이언트가 이 원본을 복도 graph 제약 상태기에 넣어
  /// 별도로 유지한다. 원본은 진단·비교를 위해 수정하지 않는다.
  final PdrLocalPoint position;
  final List<PdrLocalPoint> path;
  final int steps;
  final double distanceM;

  /// walkOffset을 적용하기 전 기기 전방축의 안정화된 방향.
  ///
  /// 마커 화살표와 카메라 bearing은 이 값을 쓴다. 보행 벡터 적분에 쓰는
  /// [walkingHeadingDeg]와 분리해야, 휴대폰을 들고 걷는 자세 보정이 사용자가
  /// 실제로 바라보는 방향까지 강제로 돌리지 않는다.
  final double orientationHeadingDeg;

  /// fused heading + walkOffset 보정이 들어간 실제 보행 방향(자북 기준일 때).
  final double walkingHeadingDeg;
  final bool hasHeading;

  final PdrPreview preview;
  final PdrRoninTrack ronin;
  final PdrQuality quality;

  /// 마지막으로 confirmed 경로에 반영된 배치. 아직 없으면 null.
  ///
  /// preview의 어느 구간까지 확정으로 소비할지 판단하는 기준이다. 새 snapshot은
  /// [PdrAppliedBatch.acknowledgedPreviewSteps]를 쓰고, 이전 fixture만 시간창으로
  /// 폴백한다.
  final PdrAppliedBatch? lastAppliedBatch;

  /// 확정 경로 끝에서 아직 확정되지 않은 preview peak만 다시 이어 붙인 표시
  /// 경로. [preview.path] 원본은 진단·품질 계산을 위해 그대로 보존한다.
  ///
  /// 초록 배치가 도착했다고 주황 전체를 reset하지 않는다. 배치 끝 시각 이하의
  /// peak만 소비하고, 이후 peak의 이동 벡터를 새 초록 끝점에 재부착하므로
  /// 마커가 과거 위치로 튀었다 다시 전진하는 현상을 막는다.
  List<PdrLocalPoint> get reconciledPreviewPath {
    final acknowledgedSteps = lastAppliedBatch?.acknowledgedPreviewSteps;
    final spanEndMs = lastAppliedBatch?.spanEndMs;
    final rawPath = preview.path;
    final times = preview.acceptedPeakTimesMs;
    if (acknowledgedSteps == null &&
        (spanEndMs == null ||
            rawPath.length < 2 ||
            times.length != rawPath.length)) {
      return rawPath;
    }

    var firstPending = -1;
    if (acknowledgedSteps != null) {
      final firstPathStep = preview.steps - (rawPath.length - 1);
      for (var index = 1; index < rawPath.length; index++) {
        if (firstPathStep + index > acknowledgedSteps) {
          firstPending = index;
          break;
        }
      }
    } else {
      for (var index = 1; index < times.length; index++) {
        final peakMs = times[index];
        if (peakMs != null && peakMs > spanEndMs!) {
          firstPending = index;
          break;
        }
      }
    }
    final output = <PdrLocalPoint>[...path];
    if (firstPending < 0) return List.unmodifiable(output);

    var current = position;
    for (var index = firstPending; index < rawPath.length; index++) {
      current += rawPath[index] - rawPath[index - 1];
      output.add(current);
    }
    return List.unmodifiable(output);
  }

  PdrLocalPoint get reconciledPreviewPosition =>
      reconciledPreviewPath.isEmpty ? position : reconciledPreviewPath.last;
}
