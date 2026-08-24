import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import 'altitude_sample.dart';
import 'calibration_state.dart';
import 'pdr_heading_sample.dart';
import 'pdr_runtime_status.dart';
import 'raw_motion_activity.dart';

/// UI가 **구독**하는 읽기 전용 관찰 계약. 구현체는 headless 로직이고, UI는 이
/// 인터페이스만 보고 렌더한다.
abstract interface class IndoorNavigationView {
  /// PDR 스냅샷(초록 위치·경로, 주황 preview, 품질).
  Stream<PdrSnapshot> get snapshots;

  /// 가장 최근 스냅샷. 세션 시작 전이면 null.
  PdrSnapshot? get currentSnapshot;

  /// 캘리브레이션 상태 스트림. 위치 렌더 여부·캘리브레이션 UI를 이걸로 결정한다.
  Stream<CalibrationStatus> get calibration;

  /// 가장 최근 캘리브레이션 상태.
  CalibrationStatus get currentCalibration;

  /// 플랫폼 센서 파이프라인 실행 상태 스트림.
  Stream<PdrRuntimeStatus> get runtimeStatuses;

  /// 가장 최근 센서 파이프라인 실행 상태.
  PdrRuntimeStatus get currentRuntimeStatus;

  /// 지금 세션이 붙어 있는 층. 확정되는 anchor에 이 값이 찍히고, 마커·경로는
  /// `anchor.floorId == 보여주는 층`일 때만 그려진다.
  ///
  /// **위치를 다시 지정하기 전에 지금 층과 같은지 확인한다** — 다르면 새 anchor가
  /// 옛 층으로 기록돼 화면에 아무것도 안 뜬다.
  String? get currentFloorId;

  /// 기압계 샘플 스트림. 층 전이 판정의 입력이며 위치 추정에는 쓰지 않는다.
  Stream<AltitudeSample> get altitudeSamples;

  /// 가장 최근 기압 샘플. 아직 없으면 null.
  AltitudeSample? get currentAltitude;

  /// 기압계 가용 상태. native snapshot이 오기 전에는 `unavailable`이다.
  AltimeterStatus get altimeterStatus;

  /// 화면 회전용 방향만 흐르는 스트림. native motion 주기(≈33Hz)라
  /// [snapshots]보다 열 배 이상 촘촘하다 — 카메라·마커 삼각형 **전용**이고,
  /// 위치·층 판정에 쓰면 안 된다([PdrHeadingSample]).
  Stream<PdrHeadingSample> get headings;

  /// 위치 적용과 **무관한** 원시 움직임. 걸음 적용을 멈춘 동안에도 흐른다 —
  /// 층 전이 판정기가 "하차해서 걷기 시작했다"를 아는 유일한 근거다.
  Stream<RawMotionActivity> get rawMotion;

  /// heading이 자리를 잡았는지. 수렴 전에 앵커를 확정하면 첫 걸음들이 틀어진
  /// 방향으로 눕는다(실측 17.6°). native의 `headingStable`은 기기 기울기만 보므로
  /// 이 판단에 쓸 수 없다.
  bool get isHeadingConverged;

  /// `stopGuidance`에서 native가 돌려준 pedometer 동결 결과. **진단 전용**이고
  /// 경로·거리 보정에는 쓰지 않는다.
  Map<String, Object?>? get lastPedometerFinalizeInfo;
}
