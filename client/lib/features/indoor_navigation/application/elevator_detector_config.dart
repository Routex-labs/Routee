/// 엘리베이터 판정 임계값 표. 층별 고도 실측의 단일 출처는
/// `docs/client/elevator-altitude-probe.md`다.
library;

/// 판정 임계값. 이름과 단위 감각은 `EscalatorDetectorConfig`에 맞췄지만 **값은
/// 따로 잡았다** — 엘리베이터는 한 번에 여러 층을 가고, 남의 층에 서고, 서 있는
/// 동안 사람이 안 움직인다. 세 가지 모두 에스컬레이터에 없는 조건이다.
class ElevatorDetectorConfig {
  const ElevatorDetectorConfig({
    this.armRadiusM = 6.0,
    this.routeApproachArmRadiusM = 16.0,
    this.armHoldMs = 120000,
    this.smoothingWindowMs = 3000,
    this.minSmoothingSamples = 3,
    this.maxSampleAgeMs = 15000,
    this.fastAltitudeTauMs = 300,
    this.fastSlopeBaseMs = 700,
    this.minVerticalSpeedMps = 0.25,
    this.settleSpeedMps = 0.12,
    this.verticalMotionMinMs = 1000,
    this.settleQuietMs = 2000,
    this.settleFallbackConfirmMs = 20000,
    this.confirmMinSteps = 2,
    this.rideTimeoutMs = 120000,
    this.minRideDeltaM = 1.6,
    this.revertM = 0.8,
    this.floorMatchMarginM = 1.0,
    this.floorMatchMaxErrorM = 2.0,
    this.routeFloorToleranceRatio = 0.5,
  });

  /// 엘리베이터 노드에 이만큼 다가오면 판정을 "허가"한다. 승강장 폭과 보정
  /// 위치 오차를 감안한 값이고, 에스컬레이터와 같다.
  final double armRadiusM;

  /// 경로가 탑승 노드를 정확히 가리킬 때만 쓰는 넓은 허가 반경(실측 위치 오차 12m).
  final double routeApproachArmRadiusM;

  /// 허가 유지 시간. **에스컬레이터의 두 배**다 — 에스컬레이터는 도착하면 바로
  /// 타지만 엘리베이터는 호출하고 서서 기다린다.
  final int armHoldMs;

  /// 중앙값 평활 창. 이 창이 곧 층 판정의 지연이지만, 확정 시점이 "내려서 걷기
  /// 시작했을 때"라 지연이 문제되지 않는다. 정확도 쪽에 몰아 준 값이다.
  final int smoothingWindowMs;

  /// 평활에 쓸 최소 샘플 수. iOS ~0.93Hz, Android 5Hz로 간격이 5배 다르므로
  /// 시간 창만으로는 개수가 보장되지 않는다.
  final int minSmoothingSamples;

  /// 이보다 오래된 샘플은 평활에 쓰지 않는다. 이만큼 시계열이 끊기면 판정 중이던
  /// 탑승도 버린다 — 끊긴 구간의 고도차는 근거가 못 된다.
  final int maxSampleAgeMs;

  /// 수직 속도를 재는 저지연 EMA의 시정수(ms). 샘플당 고정 계수로 적으면 같은
  /// α가 기기마다 다른 필터가 되므로 시정수로 적는다.
  final int fastAltitudeTauMs;

  /// 수직 속도를 잴 최소 시간 밑변(ms). 직전 샘플과 비교하면 Android 180ms
  /// 밑변에서 진짜 변화가 센서 분해능(0.01 hPa ≈ 8cm)에 묻힌다.
  final int fastSlopeBaseMs;

  /// "지금 타고 있다"로 보는 최소 수직 속도(m/s). 실측에서 정지는 |v| ≤ 0.12,
  /// 주행 최대는 1.95 m/s로 15배 넘게 갈린다. 그 사이에서 정지 쪽에 여유를 두고
  /// 잡았다([settleSpeedMps]와 함께 히스테리시스를 만든다).
  final double minVerticalSpeedMps;

  /// "섰다"로 보는 수직 속도 상한(m/s). 실측 정지 구간의 최대치다.
  final double settleSpeedMps;

  /// 단일 기압 튐을 배제하려고 같은 방향이 이어져야 하는 시간.
  final int verticalMotionMinMs;

  /// 저속이 이만큼 유지되면 `settled`로 본다. **여기서 확정하지 않으므로**
  /// 짧아도 안전하다 — 확정은 걸음이 정한다.
  final int settleQuietMs;

  /// `settled`에서 걸음이 끝내 안 잡힐 때의 상한. 넘으면 걸음 정지를 반드시
  /// 푼다. 층은 경로가 말한 층과 측정 Δ가 맞을 때만 바꾼다.
  final int settleFallbackConfirmMs;

  /// `settled`에서 하차를 확정하는 데 필요한 **누적 걸음**.
  ///
  /// **1보로 확정하면 안 된다.** 걸음 정지 중에도 흐르는 원시 걸음이 이 판정의
  /// 유일한 신호인데(`onRawMotion`), 차 안에서 자세를 고쳐 서는 것만으로 한 개가
  /// 잡힌다. 그 한 개로 확정하면 남의 층에서 문이 열린 순간 내 층이 된다.
  /// 2보는 실제로 발을 떼야 나오는 값이고, 내려서 걸어 나가는 사람은 곧바로
  /// 넘긴다 — 늦어지는 것은 한 걸음뿐이다.
  final int confirmMinSteps;

  /// 탑승 시작부터의 총 상한. 넘으면 버린다.
  final int rideTimeoutMs;

  /// 확정에 필요한 최소 이동량(m). 실측 최소 층 간격 3.23 m의 절반이다 —
  /// 이보다 작으면 어느 층에도 못 붙인다.
  final double minRideDeltaM;

  /// 출발 고도로 되돌아온 것으로 보는 폭(m). 타려다 만 경우다.
  final double revertM;

  /// 고도표에서 층을 고를 때 2등과 벌어져야 하는 여유(m). 근거는
  /// `floorAtDelta` 주석.
  final double floorMatchMarginM;

  /// 고도표에서 고른 층까지의 절대 오차 상한(m).
  final double floorMatchMaxErrorM;

  /// 경로가 말한 도착 층을 고도로 검증할 때 허용하는 **그 층 한 층 대비 비율**.
  /// 0.5면 "반 층"이다. 층고가 3.23~7.11 m로 다르므로 상수가 아니라 비율이다.
  final double routeFloorToleranceRatio;
}
