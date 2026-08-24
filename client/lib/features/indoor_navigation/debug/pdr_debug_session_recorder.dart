import 'dart:math' as math;

import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import '../../../domain/guidance/route_progress.dart';
import '../../../domain/guidance/route_checkpoint.dart';
import '../../../domain/guidance/route_movement.dart';
import '../../../models/building/floor_graph.dart';
import '../application/corridor_position_tracker.dart';
import '../application/escalator_transition_detector.dart';
import '../application/floor_map_matcher.dart';
import '../contract/altitude_sample.dart';
import '../contract/calibration_state.dart';
import '../contract/pdr_anchor.dart';
import '../contract/pdr_runtime_status.dart';
import '../../../domain/guidance/corridor_tracking.dart';

/// 실측 뒤 원인을 되짚기 위한, 의도적으로 작은 PDR 디버그 세션 레코더.
///
/// 매 원시 IMU 샘플을 저장하지 않는다. 확정 경로 전체와 1초 단위 품질 샘플만
/// 남겨 파일 크기를 제한하면서도 보폭·heading·맵매칭 문제를 구분할 수 있게 한다.
class PdrDebugSessionRecorder {
  PdrDebugSessionRecorder({DateTime? startedAt})
    : _startedAt = startedAt ?? DateTime.now().toUtc();

  // 판을 올릴 때마다 `docs/pdr/pdr-dev-integration.md`의 「스키마 이력」에 "그전에는
  // 무엇을 못 가렸나"를 한 줄 적는다. 그게 이 숫자가 존재하는 이유다.
  // v18이 늘린 것: 문 근거가 안 걸린 이유와 그때의 최단 거리
  // `exit_door_closest_miss`, GPS 좌표별 `meters_outside`.
  // v19가 늘린 것: 도약으로 **거른** GPS 좌표 `gps_rejected_fixes`.
  // v20이 늘린 것: 진입 시각 ~ 첫 실내 위치 사이의 공백 `indoor_position_gaps`.
  static const schemaVersion = 20;

  // **표본 배열에 상한이 없다** — 품질·복도·tracker 입력·경로 진행·기압·층 전이·
  // GPS 차이는 세션이 끝날 때까지 무한히 쌓인다.
  //
  // 예전에는 900~4000건에서 **오래된 것부터** 버렸다. 그러면 15분을 넘긴 주행에서
  // 출발 구간이 통째로 사라지는데, 실내→실외→실내 한 세션에서 분석하려는 것이
  // 바로 그 앞부분이다. 20분 주행 규모는 기압 ~1,200 · 품질 ~1,200 · 걸음 ~1,500 ·
  // 경로진행 ~1,000으로 합쳐 6천 건 남짓, JSON 1 MB 안팎이라 감당된다.
  //
  // 다시 상한이 필요해지면 **주행 시간 × 표본 주기**로 잡는다: 품질·경로진행·
  // GPS 차이는 1 Hz, 기압은 Android 5 Hz·iOS 1 Hz, tracker 입력은 걸음마다 +
  // 250 ms heartbeat([_trackerInputHeartbeatMs]), 층 전이는 이벤트 단위다.

  /// 실내 이탈 이벤트 상한. 한 세션에 이탈은 많아야 몇 번이라 넉넉하다 —
  /// 여기에 걸릴 정도면 판정이 떨고 있다는 뜻이고, 그 사실 자체가 데이터다.
  /// **위 배열들과 달리 상한을 남긴 유일한 자리다**(시간이 아니라 사건 수라
  /// 주행 길이를 늘려도 안 자란다).
  static const _maxIndoorExitEvents = 50;

  /// 걸음 변화가 없어도 이 간격마다 한 건은 남긴다. turnPending 타임아웃처럼
  /// 시간만으로 진행되는 전이를 재생하려면 무입력 구간의 시각도 필요하다.
  static const _trackerInputHeartbeatMs = 250;

  final DateTime _startedAt;
  final List<_PdrQualitySample> _qualitySamples = [];
  final List<Map<String, Object?>> _corridorSamples = [];
  final List<Map<String, Object?>> _trackerInputEvents = [];
  final List<Map<String, Object?>> _routeProgressSamples = [];
  final List<Map<String, Object?>> _routeStepAdvances = [];
  final List<Map<String, Object?>> _travelDirectionTransitions = [];
  final List<Map<String, Object?>> _checkpointEvents = [];

  int? _lastLoggedBatchId;
  int? _lastLoggedBatchSpanEndMs;
  int? _lastTrackerInputAtMs;
  int? _lastTrackerInputSteps;
  int? _lastTrackerInputPreviewSteps;

  PdrSnapshot? _latestSnapshot;
  CorridorTrackingResult? _latestCorridorCorrection;
  PdrAnchor? _anchor;
  PdrRuntimeStatus _runtimeStatus = const PdrRuntimeStatus.idle();
  Map<String, Object?>? _pedometerFinalize;
  String _sessionBoundary = 'running';
  final List<Map<String, Object?>> _sessionBoundaries = [];
  final List<Map<String, Object?>> _indoorStateChanges = [];
  final List<Map<String, Object?>> _indoorPositionGaps = [];

  /// 진입은 했는데 실내 위치가 아직 없는 구간의 **시작 시각**. 위치가 잡히면
  /// null로 되돌아간다([_closeIndoorPositionGap]).
  DateTime? _awaitingIndoorPositionSince;
  bool _spansBuildingExit = false;
  DateTime? _lastQualitySampleAt;
  int? _lastSampledSteps;
  Map<String, Object?>? _routeContext;
  DateTime? _lastRouteProgressSampleAt;

  final List<Map<String, Object?>> _altimeterSamples = [];
  final List<Map<String, Object?>> _floorTransitionEvents = [];
  final List<Map<String, Object?>> _indoorExitEvents = [];

  /// 문 근거가 **안 걸린** 이유 중 문에 가장 가까웠던 한 건(v18)과 그 호출 횟수.
  ///
  /// 걸음마다 갱신되므로 배열로 두면 다른 배열들을 다 합친 것보다 커진다. 알고
  /// 싶은 것은 하나뿐이다 — **PDR이 문에 얼마나까지 다가갔었나.** 그 최솟값이
  /// 문 도달 반경(`kExitDoorReachRadiusMeters`)보다 크면 문턱이 아니라 PDR이 문제이고, 작은데도
  /// 안 걸렸다면 `reason`이 어느 게이트였는지 말해 준다.
  Map<String, Object?>? _exitDoorClosestMiss;
  int _exitDoorMissCount = 0;
  final List<Map<String, Object?>> _gpsPositionDeltas = [];

  /// 도약으로 걸러 낸 좌표(v19). **상한을 안 둔다** — 위 시계열 배열들과 같은
  /// 이유이고, 여기 쌓이는 건수 자체가 규칙이 얼마나 자주 물었는지다.
  final List<Map<String, Object?>> _gpsRejectedFixes = [];

  /// 층별 마지막 궤적(v15). **키가 층이라 상한을 따로 안 둔다** — 건물 층 수가
  /// 곧 상한이다. 같은 층을 다시 밟으면 그 층의 이전 궤적은 덮인다: 앵커가
  /// 새로 찍히는 순간 PDR 경로도 그 앵커 기준으로 다시 시작하므로, 두 방문을
  /// 이어 붙일 수 있는 좌표계가 애초에 없다.
  final Map<String, ({PdrAnchor anchor, List<PdrLocalPoint> rawPath})>
  _floorRawPaths = {};
  AltimeterStatus _altimeterStatus = const AltimeterStatus.unavailable();
  Map<String, Object?>? _latestAltimeterState;

  bool get hasSnapshot => _latestSnapshot != null;

  void recordSnapshot(PdrSnapshot snapshot, {DateTime? at}) {
    _latestSnapshot = snapshot;
    // 1 Hz 솎아내기 **앞에서** 층별 궤적을 갱신한다. 층이 바뀌는 순간 이 값이
    // 마지막으로 본 이전 층 경로라, 여기서 놓치면 [buildJson]이 그 층을 통째로
    // 잃는다(앵커가 새 층으로 옮겨 가면 `paths`에서도 빠진다).
    final anchor = _anchor;
    if (anchor != null) {
      _floorRawPaths[anchor.floorId] = (anchor: anchor, rawPath: snapshot.path);
    }
    final now = (at ?? DateTime.now()).toUtc();
    final shouldSample =
        _lastQualitySampleAt == null ||
        _lastSampledSteps != snapshot.steps ||
        now.difference(_lastQualitySampleAt!).inMilliseconds >= 1000;
    if (!shouldSample) return;

    _qualitySamples.add(
      _PdrQualitySample.fromSnapshot(
        now,
        snapshot,
        // 걸음 시계열과 고도를 같은 줄에서 볼 수 있어야, 에스컬레이터(걸음 정지 +
        // 고도 변화)와 계단(걸음 증가 + 고도 변화)을 파일만으로 가를 수 있다.
        altimeter: _latestAltimeterState,
      ),
    );
    _lastQualitySampleAt = now;
    _lastSampledSteps = snapshot.steps;
  }

  void recordCalibration(CalibrationStatus status) {
    // stopGuidance 뒤에는 uncalibrated로 돌아가므로, 마지막으로 확정된 anchor는
    // 세션 JSON에 보존한다.
    if (status.anchor != null) _anchor = status.anchor;
  }

  void recordRuntime(PdrRuntimeStatus status) => _runtimeStatus = status;

  /// 기압계 가용 상태. 층 전이 판정이 "안 걸린" 세션에서 센서가 없어서인지
  /// 조건이 안 맞아서인지 파일만으로 가를 수 있어야 한다.
  void recordAltimeterStatus(AltimeterStatus status) =>
      _altimeterStatus = status;

  /// 기압 원본 샘플 + 그 시점의 판정 상태.
  ///
  /// [smoothedM]·[baselineM]·[deltaM]은 판정기 내부값이다. 원본 기압만 남기면
  /// 사후 분석에서 평활·baseline 로직을 다시 구현해야 하고, 그 재구현이 실제
  /// 판정과 어긋나면 잘못된 결론이 나온다.
  void recordAltitudeSample(
    AltitudeSample sample, {
    double? smoothedM,
    double? baselineM,
    double? deltaM,
    bool armed = false,
    bool candidate = false,
    DateTime? at,
  }) {
    final now = (at ?? DateTime.now()).toUtc();
    _latestAltimeterState = {
      'pressure_hpa': sample.pressureHpa,
      'altitude_m': sample.altitudeM,
      'relative_altitude_m': sample.relativeAltitudeM,
      'smoothed_m': smoothedM,
      'baseline_m': baselineM,
      'delta_m': deltaM,
      'armed': armed,
      'candidate': candidate,
    };
    _altimeterSamples.add({
      'at_utc': now.toIso8601String(),
      'timestamp_ms': sample.timestampMs,
      'source': sample.source,
      ..._latestAltimeterState!,
    });
  }

  /// 층 전이 판정 이벤트(허가·후보·확정·거부).
  void recordFloorTransitionEvents(
    Iterable<EscalatorDetectionEvent> events, {
    DateTime? at,
  }) {
    final now = (at ?? DateTime.now()).toUtc();
    for (final event in events) {
      _floorTransitionEvents.add({
        'at_utc': now.toIso8601String(),
        ...event.toJson(),
      });
    }
  }

  /// 실내 이탈이 걸린 순간(v15). [stage]는 `weak`(재무장·기본 층 리셋)와
  /// `confirmed`(앵커 폐기·PDR 정지) 둘뿐이다.
  ///
  /// 이 두 시각을 남기는 이유는 **문을 지난 뒤 궤적이 어떻게 흘렀는지**를
  /// 사후에 보기 위해서다. 약한 이탈 시점 이후로도 걸음이 쌓이면 실외 PDR이
  /// 쓸 만하다는 뜻이고, 흩어지면 아니라는 뜻이다.
  void recordIndoorExitEvent({
    required String stage,
    required String reason,
    String? floorId,
    double? doorDistanceM,
    double? gpsAccuracyM,
    double? metersOutside,
    DateTime? at,
  }) {
    if (_indoorExitEvents.length >= _maxIndoorExitEvents) {
      _indoorExitEvents.removeAt(0);
    }
    _indoorExitEvents.add({
      'at_utc': (at ?? DateTime.now()).toUtc().toIso8601String(),
      'stage': stage,
      'reason': reason,
      'floor_id': floorId,
      'door_distance_m': doorDistanceM,
      'gps_accuracy_m': gpsAccuracyM,
      'meters_outside': metersOutside,
      'steps': _latestSnapshot?.steps,
    });
  }

  /// 문 근거가 안 걸린 한 건. **가장 가까웠던 것만** 남기고 나머지는 센다.
  ///
  /// 거리를 못 잰 건(`doorDistanceM == null`)은 잰 건에 언제나 밀린다 — 문턱을
  /// 다시 잡을 때 읽는 값이 거리다. 이유 목록의 단일 출처는
  /// `screens/outdoor_map/entry/indoor_exit_evidence.dart`의 `stepExitDoorEvidence`.
  void recordExitDoorMiss({
    required String reason,
    double? doorDistanceM,
    String? floorId,
    DateTime? at,
  }) {
    _exitDoorMissCount++;
    final previous = _exitDoorClosestMiss?['door_distance_m'] as double?;
    final closer =
        _exitDoorClosestMiss == null ||
        (doorDistanceM != null &&
            (previous == null || doorDistanceM < previous));
    if (!closer) return;
    _exitDoorClosestMiss = {
      'at_utc': (at ?? DateTime.now()).toUtc().toIso8601String(),
      'reason': reason,
      'door_distance_m': doorDistanceM,
      'floor_id': floorId,
      'steps': _latestSnapshot?.steps,
    };
  }

  /// GPS 좌표와 화면이 그리는 "내 위치"의 거리(v15).
  ///
  /// [distanceM]이 null이면 둘 중 하나가 없었다는 뜻이다 — **그 구간이 어디였는지도
  /// 데이터라** 나머지 항목은 그대로 남긴다. [positionSource]는
  /// `GuidancePositionSource`의 이름(tracked/anchorOnly/estimate)이고, 없으면 null이다.
  void recordGpsPositionDelta({
    required double? distanceM,
    required double gpsAccuracyM,
    required double metersOutsideM,
    required String? positionSource,
    required String verdict,
    required String? floorId,
    required bool indoorEntered,
    DateTime? at,
  }) {
    final now = (at ?? DateTime.now()).toUtc();
    // v20. `position_source`가 처음 값을 갖는 순간이 곧 "마커가 없던 구간"의
    // 끝이다. 별도 호출을 두지 않는 이유는 그 값이 이미 여기로 오기 때문이다.
    if (positionSource != null) _closeIndoorPositionGap(now, floorId);
    _gpsPositionDeltas.add({
      'at_utc': now.toIso8601String(),
      'distance_m': distanceM,
      'gps_accuracy_m': gpsAccuracyM,
      // v18. `unclear`가 이어지는 구간에서 좌표가 실제로 얼마나 바깥이었는지 —
      // 약한 이탈의 거리·지속 문턱을 이 시계열로 되짚는다.
      'meters_outside_m': metersOutsideM,
      'position_source': positionSource,
      'building_verdict': verdict,
      'floor_id': floorId,
      'indoor_entered': indoorEntered,
    });
  }

  /// 도약으로 거른 좌표 한 건(v19).
  ///
  /// 남기는 이유는 **다음 실측에서 이 규칙이 맞았는지 보기 위해서**다. 실측에서
  /// 수신기는 오차 11~13 m를 보고하면서 50~77 m를 튀었다 — [gpsAccuracyM]과
  /// [jumpM]을 나란히 남겨야 "오차 값을 못 믿는다"는 전제를 다음 로그로 다시
  /// 확인하거나 뒤집을 수 있다. [allowanceM]은 그때 허용치라, 상한을 다시 잡을
  /// 때 읽는 값이다.
  ///
  /// 규칙과 상수의 단일 출처는
  /// `screens/outdoor_map/gps/gps_jump_filter.dart`의 `stepGpsJumpFilter`.
  void recordGpsRejectedFix({
    required double jumpM,
    required double allowanceM,
    required double elapsedSeconds,
    required double gpsAccuracyM,
    required bool surrendered,
    required bool indoorEntered,
    DateTime? at,
  }) {
    _gpsRejectedFixes.add({
      'at_utc': (at ?? DateTime.now()).toUtc().toIso8601String(),
      'jump_m': jumpM,
      'allowance_m': allowanceM,
      'elapsed_s': elapsedSeconds,
      'gps_accuracy_m': gpsAccuracyM,
      'surrendered': surrendered,
      'indoor_entered': indoorEntered,
      'steps': _latestSnapshot?.steps,
    });
  }

  /// 진입 직후 **위치 마커가 하나도 없던** 구간을 닫는다(v20).
  ///
  /// 진입 시각([recordIndoorStateChange])부터 `position_source`가 처음 값을 갖는
  /// 시각까지다. 실측에서 25초였고, 그동안 야외 GPS 마커는 진입과 동시에 꺼지고
  /// 실내 마커는 앵커가 없어 안 떠서 화면에 아무것도 없었다. **그 25초가 줄었는지
  /// 다음 실측에서 숫자로 보려고 남긴다.**
  ///
  /// 두 시각의 출처가 다르다 — 진입은 앱 시계, 첫 위치는 GPS 좌표의 timestamp라
  /// 1초 안팎이 섞인다. 25초 규모를 보는 값이라 그대로 둔다.
  void _closeIndoorPositionGap(DateTime at, String? floorId) {
    final since = _awaitingIndoorPositionSince;
    if (since == null) return;
    _awaitingIndoorPositionSince = null;
    _indoorPositionGaps.add({
      'entered_at_utc': since.toIso8601String(),
      'first_position_at_utc': at.toIso8601String(),
      'gap_ms': at.difference(since).inMilliseconds,
      'floor_id': floorId,
    });
  }

  void recordCorridorCorrection(CorridorTrackingResult result, {DateTime? at}) {
    _latestCorridorCorrection = result;
    final previous = _corridorSamples.lastOrNull;
    final now = (at ?? DateTime.now()).toUtc();
    final sample = <String, Object?>{
      'at_utc': now.toIso8601String(),
      'state': result.state.name,
      'edge_id': result.currentEdgeId,
      'edge_progress_m': result.currentEdgeProgressM,
      'travel_direction_sign': result.travelDirectionSign,
      'pending_edge_id': result.pendingEdgeId,
      'last_confirmed_node_id': result.lastConfirmedNodeId,
      'position_floor_local_m': _pointJson(result.correctedPosition),
      'corrected_heading_deg': result.correctedHeadingDeg,
      'preview_position_floor_local_m': _pointJson(result.previewPosition),
      'preview_heading_deg': result.previewHeadingDeg,
      'preview_candidate_edge_ids': result.previewCandidateEdgeIds,
      'preview_is_ambiguous': result.previewIsAmbiguous,
      'heading_bias_deg': result.headingBiasDeg,
    };
    final stateChanged =
        previous == null ||
        previous['state'] != sample['state'] ||
        previous['edge_id'] != sample['edge_id'] ||
        previous['pending_edge_id'] != sample['pending_edge_id'];
    final previousAt = previous == null
        ? null
        : DateTime.tryParse(previous['at_utc']! as String);
    if (!stateChanged &&
        previousAt != null &&
        now.difference(previousAt).inMilliseconds < 1000) {
      return;
    }
    _corridorSamples.add(sample);
  }

  /// corridor tracker가 실제로 받은 입력 이벤트(v10).
  ///
  /// 좌표는 anchor 변환이 끝난 floor local 값이라, 재생 시 anchor를 다시 적용할
  /// 필요 없이 그대로 [CorridorObservation]으로 되돌릴 수 있다.
  ///
  /// [observation]이 null이면 재초기화(reset) 지점이다.
  void recordTrackerInput({
    required CorridorObservation? observation,
    required bool wasReset,
    required CorridorTrackingResult result,
    required PdrSnapshot snapshot,
    required List<int?> previewTailPeakTimesMs,
    DateTime? at,
  }) {
    final now = (at ?? DateTime.now()).toUtc();
    final batch = snapshot.lastAppliedBatch;
    final isNewBatch = batch != null && batch.batchId != _lastLoggedBatchId;
    final stepsChanged =
        _lastTrackerInputSteps != snapshot.steps ||
        _lastTrackerInputPreviewSteps != snapshot.preview.steps;
    // heartbeat는 tracker 시간축(observation.timestampMs)에서만 잰다. 관측이
    // 없는 reset 지점에 벽시계를 섞으면 두 시계 차이만큼 뒤따르는 update가
    // 통째로 버려진다.
    final atMs = observation?.timestampMs;
    final staleEnough =
        atMs == null ||
        _lastTrackerInputAtMs == null ||
        atMs - _lastTrackerInputAtMs! >= _trackerInputHeartbeatMs;
    if (!wasReset && !isNewBatch && !stepsChanged && !staleEnough) return;

    _trackerInputEvents.add({
      'at_utc': now.toIso8601String(),
      'timestamp_ms': ?atMs,
      'kind': wasReset ? 'reset' : 'update',
      'orientation_heading_deg': snapshot.orientationHeadingDeg,
      'walking_heading_deg': snapshot.walkingHeadingDeg,
      if (observation != null) ...{
        'confirmed_steps': observation.confirmedSteps,
        'confirmed_distance_m': observation.confirmedDistanceM,
        'preview_steps': observation.previewSteps,
        'sensor_heading_deg': observation.sensorHeadingDeg,
        'has_heading': observation.hasHeading,
        'raw_confirmed_position': _pairJson(observation.rawConfirmedPosition),
        'raw_preview_position': _pairJson(observation.rawPreviewPosition),
        'raw_confirmed_step_positions': [
          for (final point in observation.rawConfirmedStepPositions)
            _pairJson(point),
        ],
        'raw_preview_tail_positions': [
          for (final point in observation.rawPreviewTailPositions)
            _pairJson(point),
        ],
        // 꼬리 좌표와 같은 인덱스. 확정 배치 시간창과 대조하는 기준이다.
        'raw_preview_tail_peak_times_ms': previewTailPeakTimesMs,
      },
      if (isNewBatch)
        'applied_batch': {
          'batch_id': batch.batchId,
          'span_start_ms': batch.spanStartMs,
          'span_end_ms': batch.spanEndMs,
          'applied_steps': batch.appliedSteps,
          'applied_distance_m': batch.appliedDistanceM,
          // 이 배치 시간창에서 확정으로 넘어간 주황 peak. 걸음 수 차감이 아니라
          // 시간창이 기준이라는 것을 파일만으로 확인할 수 있게 남긴다.
          'consumed_preview_peak_times_ms': _consumedPreviewPeaks(
            snapshot,
            spanEndMs: batch.spanEndMs,
          ),
        },
      'result': {
        'state': result.state.name,
        'edge_id': result.currentEdgeId,
        'edge_progress_m': result.currentEdgeProgressM,
        'travel_direction_sign': result.travelDirectionSign,
        'pending_edge_id': result.pendingEdgeId,
        'last_confirmed_node_id': result.lastConfirmedNodeId,
        'position': _pairJson(result.correctedPosition),
        'corrected_heading_deg': result.correctedHeadingDeg,
        'preview_position': _pairJson(result.previewPosition),
        'actual_marker_position': _pairJson(result.previewPosition),
        'preview_heading_deg': result.previewHeadingDeg,
        'map_matched_heading_deg': result.previewHeadingDeg,
        'preview_candidate_edge_ids': result.previewCandidateEdgeIds,
        'preview_is_ambiguous': result.previewIsAmbiguous,
        'heading_bias_deg': result.headingBiasDeg,
        'confirmed_displacement_m': result.confirmedDisplacementM,
        // optimistic cursor(화면 위치)의 독립 상태. 확정 cursor와 나란히
        // 남겨야 "배치가 마커를 뒤로 보냈는가"를 파일만으로 판정할 수 있다.
        'optimistic_lead_m': result.optimisticLeadM,
        'optimistic_edge_id': result.optimisticEdgeId,
        'optimistic_edge_progress_m': result.optimisticEdgeProgressM,
        'preview_peak_ids_synthetic': result.previewPeakIdsSynthetic,
        // 회전 허용 구간. 정지·재탐색이 "교차점을 지나는 중"이었는지 아니면
        // 실제 이탈이었는지는 이 값이 없으면 파일에서 가릴 수 없다.
        'junction_node_id': result.junctionNodeId,
        'junction_distance_m': result.junctionDistanceM.isFinite
            ? result.junctionDistanceM
            : null,
        'junction_candidate_edge_ids': result.junctionCandidateEdgeIds,
        'leader_relocated': result.leaderRelocated,
        'optimistic_step_advances': [
          for (final step in result.optimisticStepAdvances)
            _optimisticStepAdvanceJson(step),
        ],
      },
    });

    // reset 지점은 tracker 시각을 모르므로 baseline을 비워, 다음 update가
    // heartbeat와 무관하게 반드시 남도록 한다(재생 시작점 직후를 놓치지 않는다).
    _lastTrackerInputAtMs = atMs;
    _lastTrackerInputSteps = snapshot.steps;
    _lastTrackerInputPreviewSteps = snapshot.preview.steps;
    if (isNewBatch) {
      _lastLoggedBatchId = batch.batchId;
      _lastLoggedBatchSpanEndMs = batch.spanEndMs;
    }
  }

  /// 직전 배치 끝 ~ 이번 배치 끝 사이에 찍힌 accepted preview peak.
  List<int> _consumedPreviewPeaks(
    PdrSnapshot snapshot, {
    required int? spanEndMs,
  }) {
    if (spanEndMs == null) return const [];
    final from = _lastLoggedBatchSpanEndMs;
    return [
      for (final time in snapshot.preview.acceptedPeakTimesMs)
        if (time != null && time <= spanEndMs && (from == null || time > from))
          time,
    ];
  }

  /// stopGuidance에서 native가 돌려준 pedometer 동결/재조회 결과.
  void recordPedometerFinalize(Map<String, Object?>? info) =>
      _pedometerFinalize = info;

  /// 세션 경계 한 건. `_sessionBoundary`(마지막 값)와 시계열을 **함께** 남긴다 —
  /// 마지막 값만으로는 실내→실외→실내 한 세션에서 어디가 실외 구간이었는지
  /// 가릴 수 없다(경계가 덮어써지므로).
  void recordSessionBoundary(String boundary, {DateTime? at}) {
    _sessionBoundary = boundary;
    _sessionBoundaries.add({
      'at_utc': (at ?? DateTime.now()).toUtc().toIso8601String(),
      'boundary': boundary,
      'steps': _latestSnapshot?.steps,
    });
  }

  /// 건물을 나갔지만 **기록은 이어 가는** 경계(디버그 모드 전용).
  ///
  /// 원칙은 "기록은 잇고 위치는 잇지 않는다" — 여기서 세운 [spansBuildingExit]는
  /// 재진입 뒤 새 길안내가 시작돼도 이 레코더를 갈아 끼우지 말라는 표식일 뿐이고,
  /// 실외 궤적을 다시 들어왔을 때 **위치의 근거로 쓰라는 뜻이 아니다.**
  void recordBuildingExit({DateTime? at}) {
    _spansBuildingExit = true;
    recordSessionBoundary('leftBuilding', at: at);
  }

  /// 실외 구간을 품은 채 이어 가는 중인 세션인지. 참이면 새 길안내가 시작돼도
  /// 이 레코더를 새것으로 갈아 끼우면 안 된다 — 나갈 때 걸은 구간이 사라진다.
  bool get spansBuildingExit => _spansBuildingExit;

  /// 실내 상태가 바뀐 순간과 **그 출처**(v16).
  ///
  /// [source]는 `cameraZoom`·`gps`·`sheetTap`·`outsideTap`·`other` 중 하나다.
  /// `_indoorEntered`가 "도면을 보고 있다"와 "이 사람이 건물 안에 있다"를 겸하고
  /// 있어서, 확대만으로 켜진 실내 상태와 GPS가 판정한 실내 상태를 파일에서
  /// 가릴 수 없었다. 그 둘을 가르는 것이 이 배열의 유일한 목적이다.
  void recordIndoorStateChange({
    required bool entered,
    required String source,
    String? floorId,
    DateTime? at,
  }) {
    final now = (at ?? DateTime.now()).toUtc();
    // v20. 진입한 순간이 곧 "마커가 없는" 구간의 시작이다. 나가면 잴 대상이
    // 없어지므로 되돌린다 — 안 지우면 다음 진입의 공백이 실외 구간까지 삼킨다.
    _awaitingIndoorPositionSince = entered ? now : null;
    _indoorStateChanges.add({
      'at_utc': now.toIso8601String(),
      'entered': entered,
      'source': source,
      'floor_id': floorId,
      'steps': _latestSnapshot?.steps,
    });
  }

  /// 이번 세션에서 사용자가 따라간 경로가 무엇인지(v11).
  ///
  /// 경로가 새로 계산될 때마다 갱신하며, 마지막 경로만 남는다. 진행률 시계열을
  /// 사후에 검증하려면 어떤 간선 집합을 기준으로 판정했는지가 함께 있어야 한다.
  void recordRouteContext({
    required String? destinationName,
    required String? destinationNodeId,
    required String? floorId,
    required List<String> edgeIds,
    List<String> nodeIds = const [],
    int routeGeneration = 0,
    required double routeDistanceM,
    required bool isMultiFloor,
  }) {
    _routeContext = {
      'destination_name': destinationName,
      'destination_node_id': destinationNodeId,
      'floor_id': floorId,
      'edge_ids': edgeIds,
      'node_ids': nodeIds,
      'route_generation': routeGeneration,
      'route_distance_m': routeDistanceM,
      'is_multi_floor': isMultiFloor,
    };
  }

  /// 경로 기준 진행률 시계열(v11).
  ///
  /// on-route 여부나 재획득이 바뀐 순간은 무조건 남기고, 변화가 없으면 1초에
  /// 한 건으로 줄인다. 이탈이 시작·종료된 정확한 시각을 잃으면 "몇 걸음 뒤에
  /// 복구됐는지"를 사후에 셀 수 없다.
  void recordRouteProgress(
    RouteProgress progress, {
    RouteProgress? displayProgress,
    String? holdReason,
    DateTime? at,
  }) {
    final now = (at ?? DateTime.now()).toUtc();
    final previous = _routeProgressSamples.lastOrNull;
    final changed =
        previous == null ||
        previous['on_route_edge'] != progress.onRouteEdge ||
        previous['reacquired'] != progress.reacquired ||
        previous['hold_reason'] != holdReason;
    if (!changed &&
        _lastRouteProgressSampleAt != null &&
        now.difference(_lastRouteProgressSampleAt!).inMilliseconds < 1000) {
      return;
    }
    _lastRouteProgressSampleAt = now;
    _routeProgressSamples.add({
      'at_utc': now.toIso8601String(),
      'traveled_m': progress.traveledM,
      'remaining_m': progress.remainingM,
      'measured_route_progress_m': progress.traveledM,
      'display_route_progress_m': (displayProgress ?? progress).traveledM,
      'display_remaining_m': (displayProgress ?? progress).remainingM,
      'hold_reason': holdReason,
      'offset_m': progress.offsetM,
      'on_route_edge': progress.onRouteEdge,
      'reacquired': progress.reacquired,
      'segment_index': progress.segmentIndex,
      'route_heading_deg': progress.routeHeadingDeg,
    });
  }

  void recordRouteStepAdvance(
    RouteStepAdvance step, {
    TravelDirectionTransition? transition,
  }) {
    _routeStepAdvances.add({
      'peak_id': step.peakId,
      'occurred_at_ms': step.occurredAtMs,
      'signed_route_distance_m': step.signedRouteDistanceM,
      'relation': step.relation.name,
      'crossed_route_waypoint_ids': step.crossedRouteWaypointIds,
      'optimistic_edge_id': step.optimisticEdgeId,
      'preview_is_ambiguous': step.previewIsAmbiguous,
      'actual_marker_position': step.actualMarkerPosition == null
          ? null
          : _pairJson(step.actualMarkerPosition!),
      'orientation_heading_deg': step.orientationHeadingDeg,
      'walking_heading_deg': step.walkingHeadingDeg,
      'map_matched_heading_deg': step.mapMatchedHeadingDeg,
      'route_heading_deg': step.routeHeadingDeg,
      'heading_error_deg': step.headingErrorDeg,
    });
    if (transition == null) return;
    _travelDirectionTransitions.add({
      'from': transition.from.name,
      'to': transition.to.name,
      'peak_id': transition.peakId,
      'occurred_at_ms': transition.occurredAtMs,
      'evidence_peak_count': transition.evidencePeakCount,
      'evidence_distance_m': transition.evidenceDistanceM,
    });
  }

  void recordCheckpointEvent(RouteCheckpointEvent event) {
    _checkpointEvents.add({
      'route_generation': event.routeGeneration,
      'waypoint_node_id': event.waypoint.nodeId,
      'kind': event.waypoint.kind.name,
      'route_distance_m': event.waypoint.routeDistanceM,
      'incoming_edge_id': event.waypoint.incomingEdgeId,
      'outgoing_edge_id': event.waypoint.outgoingEdgeId,
      'decision': event.decision.name,
      'reason': event.reason,
      'peak_id': event.peakId,
      'occurred_at_ms': event.occurredAtMs,
      'waypoint_distance_m': event.waypointDistanceM,
      'shadow': true,
    });
  }

  Map<String, Object?> buildJson({
    required String buildingId,
    required String? selectedFloor,
    required String mapCalibrationVersion,
    required FloorGraph? graph,
    required Map<String, Object?> device,
    DateTime? exportedAt,
  }) {
    final snapshot = _latestSnapshot;
    final anchor = _anchor;
    final hasMapContext =
        snapshot != null &&
        anchor != null &&
        graph != null &&
        graph.nodes.isNotEmpty &&
        anchor.floorId == selectedFloor;
    final rawPath = snapshot?.path ?? const <PdrLocalPoint>[];
    final floorPath = hasMapContext
        ? rawPath
              .map(FloorCoordinateTransform(anchor).toFloor)
              .toList(growable: false)
        : const <PdrLocalPoint>[];
    final corridorCorrection = _latestCorridorCorrection;
    final matchedPath = hasMapContext
        ? corridorCorrection?.correctedPath ??
              FloorMapMatcher(graph).matchRoutedPath(floorPath)
        : const <PdrLocalPoint>[];
    final roninRawPath = snapshot == null || !snapshot.ronin.supported
        ? const <PdrLocalPoint>[]
        : snapshot.ronin.path;
    final roninFloorPath = hasMapContext && snapshot.ronin.supported
        ? roninRawPath
              .map(FloorCoordinateTransform(anchor).toFloor)
              .toList(growable: false)
        : const <PdrLocalPoint>[];

    return {
      'schema_version': schemaVersion,
      'type': 'pdr_debug_session',
      'started_at_utc': _startedAt.toIso8601String(),
      'exported_at_utc': (exportedAt ?? DateTime.now().toUtc())
          .toIso8601String(),
      'device': device,
      'map_context': {
        'building_id': buildingId,
        'floor_id': selectedFloor,
        'map_calibration_version': mapCalibrationVersion,
        'graph_node_count': graph?.nodes.length ?? 0,
        'graph_edge_count': graph?.edges.length ?? 0,
      },
      'anchor': _anchorJson(anchor),
      'summary': _summaryJson(
        snapshot,
        floorPathDistanceM: _pathLength(floorPath),
        mapMatchedDistanceM: _pathLength(matchedPath),
        corridorCorrection: corridorCorrection,
      ),
      'paths': {
        'confirmed_pdr_local_m': _pointsJson(rawPath),
        'ronin_stride_pdr_local_m': _pointsJson(roninRawPath),
        'floor_local_m_before_matching': _pointsJson(floorPath),
        'ronin_stride_floor_local_m': _pointsJson(roninFloorPath),
        'map_matched_floor_local_m': _pointsJson(matchedPath),
        'corridor_corrected_floor_local_m': _pointsJson(
          corridorCorrection?.correctedPath ?? const [],
        ),
        'corridor_preview_floor_local_m': _pointsJson(
          corridorCorrection?.previewPath ?? const [],
        ),
      },
      // 층별 궤적(v15). `paths`는 **지금 보고 있는 층**만 그리므로, 층이 바뀌면
      // 이전 층 궤적이 통째로 빠진다. 이벤트 배열들은 세션 전체를 담는데 궤적만
      // 마지막 층이라, 층을 오간 세션은 그림을 맞출 수 없었다.
      // `paths`는 그대로 두고 여기에 층별로 한 번 더 담는다.
      'paths_by_floor': [
        for (final entry in _floorRawPaths.entries)
          {
            'floor_id': entry.key,
            'anchor': _anchorJson(entry.value.anchor),
            'floor_local_m_before_matching': _pointsJson(
              entry.value.rawPath
                  .map(FloorCoordinateTransform(entry.value.anchor).toFloor)
                  .toList(growable: false),
            ),
          },
      ],
      'quality_samples_1hz': [
        for (final sample in _qualitySamples) sample.toJson(),
      ],
      'corridor_correction_samples': _corridorSamples,
      // corridor tracker 정확 재생용 입력 이벤트(v10). `kind: 'reset'`에서
      // 상태를 다시 세우고, 이후 `update`를 순서대로 먹이면 재현된다.
      'tracker_input_events': _trackerInputEvents,
      // 상한을 없앤 뒤로 두 `*_dropped*` 키는 항상 0이다. **키는 남긴다** —
      // 이 파일을 읽는 분석 도구가 없는 키에서 깨지는 것보다 0이 낫다.
      'tracker_input_dropped': 0,
      // 경로 기준 계측(v11). route_context가 null이면 이번 세션은 길찾기 없이
      // 자유보행만 한 것이다.
      'route_context': _routeContext,
      'route_progress_samples': _routeProgressSamples,
      'route_progress_summary': _routeProgressSummaryJson(),
      'route_step_advances': _routeStepAdvances,
      'travel_direction_transitions': _travelDirectionTransitions,
      'checkpoint_events': _checkpointEvents,
      // 기압계·층 전이 판정(v12). available=false면 이 기기에서는 층 추종이
      // 애초에 돌지 않은 세션이다.
      'altimeter': {
        'available': _altimeterStatus.available,
        'source': _altimeterStatus.source,
        'sensor_name': _altimeterStatus.sensorName,
        'sample_count': _altimeterSamples.length,
        'dropped_samples': 0,
      },
      'altimeter_samples': _altimeterSamples,
      'floor_transition_events': _floorTransitionEvents,
      // 실외 이탈 계측(v15). weak는 되돌리기 쉬운 일만, confirmed는 앵커 폐기다.
      'indoor_exit_events': _indoorExitEvents,
      'exit_door_closest_miss': _exitDoorClosestMiss == null
          ? null
          : {..._exitDoorClosestMiss!, 'sample_count': _exitDoorMissCount},
      'gps_position_deltas': _gpsPositionDeltas,
      // 도약으로 거른 좌표(v19). `surrendered`가 true인 건은 **거르다 항복해서
      // 받아들인** 것이라, 이 값이 잦으면 상한이 너무 빡빡하다는 뜻이다.
      'gps_rejected_fixes': _gpsRejectedFixes,
      'runtime': {
        'state': _runtimeStatus.state.name,
        'warnings': _runtimeStatus.warnings,
      },
      'pedometer_finalize': _pedometerFinalizeJson(),
      'session_boundary': _sessionBoundary,
      // 세션 경계 시계열과 실내 상태 변경의 출처(v16). 실내→실외→실내 한 세션의
      // 실외 구간은 `leftBuilding`~`reEntered` 사이다.
      'session_boundaries': _sessionBoundaries,
      'spans_building_exit': _spansBuildingExit,
      'indoor_state_changes': _indoorStateChanges,
      // 진입 직후 위치 마커가 하나도 없던 구간(v20). [_closeIndoorPositionGap].
      'indoor_position_gaps': _indoorPositionGaps,
    };
  }

  /// 경로 기준 지표 3개를 파일 안에서 바로 읽을 수 있게 요약한다(v11).
  ///
  /// 시계열만 남기면 매번 계산해야 하고, 실측 직후 현장에서 파일을 열어
  /// "이번 주행이 쓸 만했는지"를 판단할 수 없다.
  ///
  /// `on_route_ratio`는 샘플 수 기준이지 시간·거리 가중이 아니다 — 샘플이
  /// 상태 변화마다 추가되므로 이탈이 잦은 주행에서는 이탈 쪽이 과대 대표될
  /// 수 있다. 주행 간 비교가 아니라 한 주행 안에서의 눈대중용 값이다.
  Map<String, Object?>? _routeProgressSummaryJson() {
    if (_routeProgressSamples.isEmpty) return null;
    var onRouteCount = 0;
    var reacquiredCount = 0;
    var maxOffsetM = 0.0;
    for (final sample in _routeProgressSamples) {
      if (sample['on_route_edge'] == true) onRouteCount++;
      if (sample['reacquired'] == true) reacquiredCount++;
      final offsetM = (sample['offset_m'] as num?)?.toDouble() ?? 0;
      if (offsetM > maxOffsetM) maxOffsetM = offsetM;
    }
    final first = _routeProgressSamples.first;
    final last = _routeProgressSamples.last;
    return {
      'sample_count': _routeProgressSamples.length,
      'on_route_ratio': onRouteCount / _routeProgressSamples.length,
      'reacquired_count': reacquiredCount,
      'max_offset_m': maxOffsetM,
      'first_traveled_m': (first['traveled_m'] as num?)?.toDouble(),
      'last_traveled_m': (last['traveled_m'] as num?)?.toDouble(),
      'last_remaining_m': (last['remaining_m'] as num?)?.toDouble(),
    };
  }

  /// live stream이 센 걸음(`live_steps`)과 같은 구간을 사후 재조회한
  /// 걸음(`queried_steps`)의 대조.
  ///
  /// 이 둘의 관계가 초반 구간 부족분의 성격을 가른다:
  ///  - `queried > live`  -> OS는 봤는데 live stream이 늦게/적게 흘린 것.
  ///                         재조회 값으로 백필하는 게 옳다.
  ///  - `queried == live` -> OS가 그 걸음들을 아예 못 봤다. 백필할 근거가 없고
  ///                         다른 방법을 찾아야 한다.
  ///
  /// 판단 근거를 모으는 단계이므로 이 값으로 경로를 보정하지 않는다.
  Map<String, Object?>? _pedometerFinalizeJson() {
    final info = _pedometerFinalize;
    if (info == null) return null;
    final live = (info['steps'] as num?)?.toInt();
    final queried = (info['queriedSteps'] as num?)?.toInt();
    return {
      'live_steps': live,
      'queried_steps': queried,
      'queried_distance_m': (info['queriedDistanceM'] as num?)?.toDouble(),
      'query_available': info['queryAvailable'],
      'query_error': info['queryError'],
      'session_start_ms': (info['sessionStartMs'] as num?)?.toDouble(),
      'stopped_at_ms': (info['stoppedAtMs'] as num?)?.toDouble(),
      if (live != null && queried != null) 'queried_minus_live': queried - live,
    };
  }

  static Map<String, Object?>? _anchorJson(PdrAnchor? anchor) {
    if (anchor == null) return null;
    return {
      'floor_id': anchor.floorId,
      'floor_local_m': _pointJson(anchor.anchorLocalM),
      'rotation_deg': anchor.rotationDeg,
      // rotation_deg의 내역. 상수는 코드에서 바로 읽고, 현장에서 돌린 노브 값만
      // anchor가 들고 온다 — 다음에 상수로 굳힐 근거가 세션 파일에 남아야 한다.
      'magnetic_declination_deg': magneticDeclinationDeg,
      'debug_heading_offset_deg': anchor.headingOffsetDeg,
      'pdr_to_floor_axes': {
        'east_to_x': anchor.axes.eastToX,
        'north_to_x': anchor.axes.northToX,
        'east_to_y': anchor.axes.eastToY,
        'north_to_y': anchor.axes.northToY,
      },
      'heading_reference': anchor.headingReference.name,
      'requires_manual_rotation_calibration':
          anchor.requiresManualRotationCalibration,
      'source': anchor.source.name,
      'confidence': anchor.confidence,
    };
  }

  static Map<String, Object?> _summaryJson(
    PdrSnapshot? snapshot, {
    required double floorPathDistanceM,
    required double mapMatchedDistanceM,
    required CorridorTrackingResult? corridorCorrection,
  }) {
    if (snapshot == null) return const {'recorded': false};
    final features = snapshot.quality.features;
    return {
      'recorded': true,
      'confirmed_steps': snapshot.steps,
      'confirmed_distance_m': snapshot.distanceM,
      'floor_path_distance_m_before_matching': floorPathDistanceM,
      'map_matched_path_distance_m': mapMatchedDistanceM,
      'walking_heading_deg': snapshot.walkingHeadingDeg,
      'orientation_heading_deg': snapshot.orientationHeadingDeg,
      'has_heading': snapshot.hasHeading,
      'preview_steps': snapshot.preview.steps,
      'preview_distance_m': snapshot.preview.distanceM,
      'ronin': {
        'supported': snapshot.ronin.supported,
        'model_ready': snapshot.ronin.modelReady,
        'model': snapshot.ronin.model,
        'status': snapshot.ronin.status,
        'steps': snapshot.ronin.steps,
        'distance_m': snapshot.ronin.distanceM,
        'effective_stride_m': snapshot.ronin.effectiveStrideM,
        'raw_stride_m': snapshot.ronin.rawStrideM,
        'speed_mps': snapshot.ronin.speedMps,
        'speed_std_mps': snapshot.ronin.speedStdMps,
        'cadence_hz': snapshot.ronin.cadenceHz,
      },
      'quality': {
        'state': snapshot.quality.state.name,
        'warnings': snapshot.quality.warnings,
        'heading_stable': features.headingStable,
        'heading_source': features.headingSource,
        'magnetic_accuracy': features.magneticAccuracy,
        'rotation_heading_accuracy_deg': features.rotationHeadingAccuracyDeg,
        'heading_reference_is_magnetic_north':
            features.headingReferenceIsMagneticNorth,
        'cadence_hz': features.cadenceHz,
        'pitch_deg': features.pitchDeg,
        'roll_deg': features.rollDeg,
        'green_orange_distance_divergence_pct':
            features.greenOrangeDistanceDivergencePct,
        'orange_step_ratio': features.orangeStepRatio,
        'orange_overcount_likely': features.orangeOvercountLikely,
        'pedometer_undercount_suspected': features.pedometerUndercountSuspected,
        'pedometer_flagged_span_s': features.pedometerFlaggedSpanS,
        'peak_reject_histogram': features.peakRejectHistogram,
      },
      'heading_breakdown': headingBreakdownJson(features),
      'corridor_correction': corridorCorrection == null
          ? null
          : {
              'state': corridorCorrection.state.name,
              'edge_id': corridorCorrection.currentEdgeId,
              'edge_progress_m': corridorCorrection.currentEdgeProgressM,
              'travel_direction_sign': corridorCorrection.travelDirectionSign,
              'pending_edge_id': corridorCorrection.pendingEdgeId,
              'last_confirmed_node_id': corridorCorrection.lastConfirmedNodeId,
              'position_floor_local_m': _pointJson(
                corridorCorrection.correctedPosition,
              ),
              'corrected_heading_deg': corridorCorrection.correctedHeadingDeg,
              'preview_position_floor_local_m': _pointJson(
                corridorCorrection.previewPosition,
              ),
              'actual_marker_position': _pointJson(
                corridorCorrection.previewPosition,
              ),
              'preview_heading_deg': corridorCorrection.previewHeadingDeg,
              'map_matched_heading_deg': corridorCorrection.previewHeadingDeg,
              'optimistic_edge_id': corridorCorrection.optimisticEdgeId,
              'optimistic_edge_progress_m':
                  corridorCorrection.optimisticEdgeProgressM,
              'preview_candidate_edge_ids':
                  corridorCorrection.previewCandidateEdgeIds,
              'preview_is_ambiguous': corridorCorrection.previewIsAmbiguous,
              'heading_bias_deg': corridorCorrection.headingBiasDeg,
            },
    };
  }

  /// `walking_heading_deg`가 어떻게 만들어졌는지의 분해.
  ///
  /// `walking = fused + walk_offset`이므로, 방향이 틀렸을 때 이 값들을 비교하면
  /// 자력계(device≈fused가 함께 틀림)·walkOffset(fused는 맞음)·네이티브
  /// 유도식(device는 맞고 fused만 틀림)을 구분할 수 있다. `gyro`는 자력계와
  /// 독립이라, fused만 흔들리면 자기장 문제이고 셋이 같이 움직이면 실제 회전이다.
  static Map<String, Object?> headingBreakdownJson(
    PdrQualityFeatures features,
  ) => {
    'fused_heading_deg': features.fusedHeadingDeg,
    'walk_offset_deg': features.walkOffsetDeg,
    'walk_offset_active': features.walkOffsetActive,
    'device_heading_deg': features.deviceHeadingDeg,
    'gyro_heading_deg': features.gyroHeadingDeg,
    'walk_dir_deg': features.walkDirDeg,
    'walk_dir_confidence': features.walkDirConfidence,
    'heading_converged': features.headingConverged,
    'heading_spread_deg': features.headingSpreadDeg,
  };

  static List<Map<String, double>> _pointsJson(
    Iterable<PdrLocalPoint> points,
  ) => [for (final point in points) _pointJson(point)];

  static Map<String, double> _pointJson(PdrLocalPoint point) => {
    'east_m': point.eastM,
    'north_m': point.northM,
  };

  /// tracker 입력 이벤트 전용 압축 좌표 `[east_m, north_m]`.
  ///
  /// 이벤트 수가 많아 키 이름 반복이 파일 크기를 크게 좌우한다. mm 단위로
  /// 끊어도 재생 결과는 달라지지 않는다.
  static List<double> _pairJson(PdrLocalPoint point) => [
    _round3(point.eastM),
    _round3(point.northM),
  ];

  static double _round3(double value) => (value * 1000).roundToDouble() / 1000;

  static Map<String, Object?> _optimisticStepAdvanceJson(
    OptimisticStepAdvance step,
  ) => {
    'peak_id': step.peakId,
    'occurred_at_ms': step.occurredAtMs,
    'hypothesis_id': step.hypothesisId,
    'parent_hypothesis_id': step.parentHypothesisId,
    'distance_m': step.distanceM,
    'position': _pairJson(step.position),
    'traversals': [
      for (final traversal in step.traversals)
        {
          'edge_id': traversal.edgeId,
          'from_progress_m': traversal.fromProgressM,
          'to_progress_m': traversal.toProgressM,
        },
    ],
    'crossed_node_ids': step.crossedNodeIds,
    'leader_relocated': step.leaderRelocated,
  };

  static double _pathLength(List<PdrLocalPoint> points) {
    var total = 0.0;
    for (var index = 1; index < points.length; index++) {
      final dx = points[index].eastM - points[index - 1].eastM;
      final dy = points[index].northM - points[index - 1].northM;
      total += math.sqrt(dx * dx + dy * dy);
    }
    return total;
  }
}

class _PdrQualitySample {
  const _PdrQualitySample({
    required this.at,
    required this.steps,
    required this.distanceM,
    required this.orientationHeadingDeg,
    required this.walkingHeadingDeg,
    required this.headingStable,
    required this.magneticAccuracy,
    required this.rotationHeadingAccuracyDeg,
    required this.cadenceHz,
    required this.previewSteps,
    required this.previewDistanceM,
    required this.ronin,
    required this.headingBreakdown,
    this.altimeter,
  });

  final DateTime at;
  final int steps;
  final double distanceM;
  final double orientationHeadingDeg;
  final double walkingHeadingDeg;
  final bool headingStable;
  final String magneticAccuracy;
  final double rotationHeadingAccuracyDeg;
  final double cadenceHz;

  /// 주황(accel preview) 시계열. 초록만 남기면 둘이 **언제** 벌어졌는지를
  /// 파일에서 못 읽는다 — 초반 지연인지 전 구간에 걸친 과다 계수인지 구분하려면
  /// 두 곡선을 같은 시간축에 놓아야 한다.
  final int previewSteps;
  final double previewDistanceM;
  final Map<String, Object?> ronin;

  /// 시간에 따른 비교가 핵심이라(초반 수렴 구간, 구간별 자기 왜곡) summary뿐
  /// 아니라 매 샘플에 남긴다.
  final Map<String, Object?> headingBreakdown;

  /// 이 시점의 마지막 기압 관측·판정 상태. 기압계가 없거나 첫 샘플 전이면 null.
  final Map<String, Object?>? altimeter;

  factory _PdrQualitySample.fromSnapshot(
    DateTime at,
    PdrSnapshot snapshot, {
    Map<String, Object?>? altimeter,
  }) {
    final features = snapshot.quality.features;
    return _PdrQualitySample(
      at: at,
      steps: snapshot.steps,
      distanceM: snapshot.distanceM,
      orientationHeadingDeg: snapshot.orientationHeadingDeg,
      walkingHeadingDeg: snapshot.walkingHeadingDeg,
      headingStable: features.headingStable,
      magneticAccuracy: features.magneticAccuracy,
      rotationHeadingAccuracyDeg: features.rotationHeadingAccuracyDeg,
      cadenceHz: features.cadenceHz,
      previewSteps: snapshot.preview.steps,
      previewDistanceM: snapshot.preview.distanceM,
      ronin: {
        'supported': snapshot.ronin.supported,
        'model_ready': snapshot.ronin.modelReady,
        'status': snapshot.ronin.status,
        'distance_m': snapshot.ronin.distanceM,
        'effective_stride_m': snapshot.ronin.effectiveStrideM,
        'raw_stride_m': snapshot.ronin.rawStrideM,
        'speed_mps': snapshot.ronin.speedMps,
        'speed_std_mps': snapshot.ronin.speedStdMps,
        'cadence_hz': snapshot.ronin.cadenceHz,
      },
      headingBreakdown: PdrDebugSessionRecorder.headingBreakdownJson(features),
      altimeter: altimeter,
    );
  }

  Map<String, Object?> toJson() => {
    'at_utc': at.toIso8601String(),
    'steps': steps,
    'distance_m': distanceM,
    'preview_steps': previewSteps,
    'preview_distance_m': previewDistanceM,
    'ronin': ronin,
    'orientation_heading_deg': orientationHeadingDeg,
    'walking_heading_deg': walkingHeadingDeg,
    'heading_stable': headingStable,
    'magnetic_accuracy': magneticAccuracy,
    'rotation_heading_accuracy_deg': rotationHeadingAccuracyDeg,
    'cadence_hz': cadenceHz,
    'altimeter': altimeter,
    ...headingBreakdown,
  };
}
