/// 에스컬레이터 판정 임계값 표. 값은 전부 실측에서 나왔고, 근거는
/// `docs/client/escalator-thresholds.md`가 단일 출처다.
library;

/// 판정 임계값. 값마다의 실측 근거는 `docs/client/escalator-thresholds.md`에 있고,
/// 조정은 로그(schema v12 `altimeter_samples`·`floor_transition_events`)를 보고 한다.
class EscalatorDetectorConfig {
  const EscalatorDetectorConfig({
    this.armRadiusM = 6.0,
    this.routeApproachArmRadiusM = 16.0,
    this.armHoldMs = 60000,
    this.smoothingWindowMs = 3000,
    this.minSmoothingSamples = 3,
    this.maxSampleAgeMs = 15000,
    this.minDeltaM = 1.2,
    this.mapSwapDeltaM = 2.4,
    this.minConfirmDeltaM = 2.2,
    this.rampConsistencyWindowMs = 5000,
    this.minDirectionalRampStrides = 3,
    this.directionalStrideMs = 1000,
    this.minDirectionalSampleDeltaM = 0.04,
    this.minRampMs = 2500,
    this.settleWindowMs = 2500,
    this.minRampRiseM = 0.45,
    this.settleSlopeM = 0.25,
    this.fastAltitudeTauMs = 300,
    this.fastSlopeBaseMs = 700,
    this.fastExitSlopeMps = 0.12,
    this.fastExitWithStepSlopeMps = 0.18,
    this.fastExitQuietMs = 1000,
    this.candidateTimeoutMs = 90000,
    this.multiFloorRejectM = 10.0,
    this.baselineTrackAlpha = 0.02,
    this.boardingApproachRadiusM = 3.0,
    this.boardingAbandonRadiusM = 8.0,
    this.boardingAbandonGraceMs = 15000,
    this.boardingApproachUpdates = 2,
    this.boardingPhaseTimeoutMs = 40000,
    this.minVerticalSpeedMps = 0.12,
    this.verticalMotionMinMs = 1000,
    this.visibleVerticalDeltaM = 1.2,
    this.minVisibleRiseM = 0.5,
    this.earlyVerticalQuietMs = 1000,
  });

  /// 에스컬레이터 노드에 이만큼 다가오면 판정을 "허가"한다. 랜딩 폭과 보정
  /// 위치 오차를 감안한 값이다.
  final double armRadiusM;

  /// 경로가 탑승 노드를 정확히 가리킬 때만 쓰는 넓은 허가 반경(실측 위치 오차 12m).
  final double routeApproachArmRadiusM;

  /// 허가 유지 시간. 탑승 뒤에는 걸음이 멈춰 위치가 갱신되지 않으므로, 노드에서
  /// 멀어진 것으로 계산되는 동안에도 판정할 수 있어야 한다.
  final int armHoldMs;

  /// 중앙값 평활 창. **이 창이 곧 판정 지연이다**(중앙값은 창의 절반쯤 뒤처진다).
  /// 2000ms에서 iOS 판정이 한 번도 안 돌았던 사고가 여기 있다.
  final int smoothingWindowMs;

  /// 평활에 쓸 최소 샘플 수. iOS ~0.93Hz, Android 5Hz로 간격이 5배 다르므로
  /// 시간 창만으로는 개수가 보장되지 않는다. 창보다 오래된 샘플이라도 최근
  /// 이 개수는 남겨 두어, 센서 주기가 어떻든 판정이 돌게 한다.
  final int minSmoothingSamples;

  /// 이보다 오래된 샘플은 평활에 쓰지 않는다. 시계열이 끊긴 구간은 판정하지 않고
  /// 창을 다시 채운다.
  final int maxSampleAgeMs;

  /// 후보를 여는 최소 고도 변화(m). 도면 교체는 [mapSwapDeltaM]에서 따로 한다.
  ///
  /// **이 문턱 하나로 층이 바뀌지 않는다** — 노드 허가·방향 일관성
  /// ([minDirectionalRampStrides])·수직 속도([minRampRiseM])가 함께 성립해야 한다.
  final double minDeltaM;

  /// 목적 층 도면으로 갈아 끼우는 누적 변화량. [minConfirmDeltaM](2.2)보다 크므로
  /// 낮은 층고에서는 조기 신호 없이 `landed`에서 한 번에 전환된다.
  final double mapSwapDeltaM;

  /// 층 이동을 최종 확정할 최소 변화량. 고정된 층고를 맞히려 하지 않고, 같은 방향
  /// 등속 변화와 하차 시 속도 감소가 함께 확인될 때만 쓴다.
  final double minConfirmDeltaM;

  /// 후보 시작 전 상승·하강이 한 번의 압력 튐이 아니라 같은 방향으로 이어졌는지
  /// 확인하는 시간 창이다.
  final int rampConsistencyWindowMs;

  /// 그 창 안에서 같은 방향을 확인할 **구간(stride) 수**. 샘플 수로 세면 같은 5초가
  /// iOS 4~5개 · Android 27개가 되어 기기마다 다른 문턱이 된다.
  final int minDirectionalRampStrides;

  /// 한 구간의 최소 길이. 이 값이 곧 [minDirectionalSampleDeltaM]의 의미를 정한다 —
  /// 1초에 4cm와 0.18초에 4cm는 전혀 다른 속도다.
  final int directionalStrideMs;

  final double minDirectionalSampleDeltaM;

  /// 후보가 최소 이만큼 유지돼야 확정 판단으로 넘어간다. 중앙값 평활이 꺾이는
  /// 지점에 만드는 **평평한 구간**을 확정으로 오인하지 않기 위한 것이다.
  final int minRampMs;

  /// 상승/하강이 멈췄는지 보는 창. "움직이는 중"인지도 같은 창으로 본다.
  final int settleWindowMs;

  /// 후보를 열려면 [settleWindowMs] 동안 이만큼은 실제로 움직여야 한다.
  /// **누적 변화량만으로는 부족하다** — 기상 드리프트도 누적 [minDeltaM]을 넘는다.
  final double minRampRiseM;

  /// 이 창 동안 고도 변화가 이 값 이하면 "멈췄다"로 본다. 확정 시점을 하차
  /// 순간에 맞추려면 임계값 통과가 아니라 **정지**를 기다려야 한다. 임계값
  /// 통과에서 바로 확정하면 아직 탑승 중인데 지도가 바뀐다.
  final double settleSlopeM;

  /// 하차를 빠르게 잡는 저지연 EMA의 **시정수**(ms). 샘플당 고정 계수로 적으면
  /// 같은 α가 기기마다 다른 필터가 되므로 시정수로 적고, 계수는 매 샘플
  /// `1 - exp(-dt/tau)`로 만든다. 평활의 몫은 [fastSlopeBaseMs]가 맡는다.
  final int fastAltitudeTauMs;

  /// 수직 속도를 잴 **최소 시간 밑변**(ms). 직전 샘플과 비교하면 Android 180ms
  /// 밑변에서 진짜 변화(5cm)가 센서 분해능(0.01 hPa ≈ 8cm)보다 작아 속도가 0으로
  /// 읽힌다 — 타는 중에 "멈췄다"가 된다.
  final int fastSlopeBaseMs;

  /// 빠른 EMA의 수직 속도가 이 값 이하로 유지되면 하차로 본다.
  final double fastExitSlopeMps;

  /// 새 걸음이 함께 관측된 경우의 완화된 속도 상한. 사용자가 에스컬레이터에서
  /// 걷더라도 수직 속도가 계속 크면 통과하지 않고, 하차 뒤 첫 걸음과 수직 속도
  /// 감소가 겹치면 곧바로 재개한다.
  final double fastExitWithStepSlopeMps;

  /// 걸음 근거가 없을 때 저속이 **유지돼야 하는 시간**. 개수로 세면 Android에서
  /// 0.36초가 되어 노이즈 한 번이 하차로 읽혔다(= 한 층에 층이 두 번 바뀌는 증상).
  final int fastExitQuietMs;

  /// 후보가 이 시간 안에 안정되지 않으면 기상 변화·센서 드리프트로 보고 버린다.
  final int candidateTimeoutMs;

  /// 한 층으로 설명되지 않는 변화(엘리베이터·연속 탑승). v1은 ±1층만 지원해
  /// 확정하지 않고 거부하되, 빈도는 로그로 남긴다. 실측 한 층은 6.2m·두 층은 12m.
  final double multiFloorRejectM;

  /// 허가/후보가 없는 동안 baseline을 천천히 따라가는 비율. 기상 드리프트를
  /// 흡수한다. 허가 중에는 추적하지 않는다 — 상승분을 같이 먹어버린다.
  final double baselineTrackAlpha;

  /// 활성 경로의 탑승점에 이만큼 다가오면 **배너만** 띄운다. 되돌리기 비용이 거의
  /// 없어 [minDeltaM]보다 훨씬 이른 근거로 띄운다.
  final double boardingApproachRadiusM;

  /// 보인 탑승 안내를 거리로 접는 반경(m). 접근 반경보다 넓어야 탑승점을 지나
  /// 에스컬레이터에 올라서는 동작을 이탈로 오인하지 않는다.
  final double boardingAbandonRadiusM;

  /// 탑승 안내 직후 tracker 걸음이 반경 밖으로 흘러도 기압이 이어받기를 기다리는 시간.
  final int boardingAbandonGraceMs;

  /// 탑승점까지 거리가 줄어드는 것을 확인할 **서로 다른 걸음 갱신** 횟수.
  /// 한 프레임의 근접만으로 띄우면 옆을 스쳐 지나가는 사람에게도 뜬다.
  final int boardingApproachUpdates;

  /// 배너를 띄운 뒤 아무 이동 근거 없이 기다리는 최대 시간. 넘으면 취소한다.
  final int boardingPhaseTimeoutMs;

  /// "지금 실제로 오르내리는 중"으로 보는 최소 수직 속도(m/s). 누적 고도가
  /// [minDeltaM]에 닿기 **전에** 걸음을 멈추기 위한 근거이고, 층은 안 바꾼다.
  final double minVerticalSpeedMps;

  /// 단일 기압 튐을 배제하려고 같은 방향이 이어져야 하는 시간(iOS 2샘플 길이).
  /// 개수로 적으면 Android 0.36초가 되어 걷는 중 노이즈로도 마커가 멈춘다.
  final int verticalMotionMinMs;

  /// 노드 근접 없이 **걸음을 멈추는** 갈래의 누적 고도 변화(m).
  ///
  /// [minDeltaM]과 값은 같지만 하는 일이 다르다 — 이쪽은 마커 정지까지고, 도면
  /// 교체는 그 위에 노드 허가와 램프 일관성을 더 요구한다.
  final double visibleVerticalDeltaM;

  /// 경로 탑승 후보를 처음 본 고도에서 요구하는 최소 방향성 누적 변화(m).
  /// 순간 속도의 지속 여부와 독립적으로 먼저 도달할 수 있고, 정식 1.2m 후보 전에는
  /// 수직 이동이 멎으면 취소되는 가역 잠금만 연다.
  final double minVisibleRiseM;

  /// 가역 2차 단계를 접는 복귀/정지 상태의 유지 시간. 경로 후보는 시작 고도
  /// 근처까지 돌아온 뒤, 노드 없는 후보는 수직 속도가 멎은 뒤부터 잰다.
  final int earlyVerticalQuietMs;
}
