/// 빔 서치의 가중치·상한. 각 값의 근거는 그 선언 위에 있다.
class CorridorTrackerConfig {
  const CorridorTrackerConfig({
    this.beamWidth = 24,
    this.progressBucketM = 1.5,
    this.transitionPenaltyDegM = 3,
    this.deadEndPenaltyDeg = 90,
    this.reverseTriggerDeg = 115,
    this.absoluteErrorWeight = 0.25,
    this.costHorizonM = 25,
    this.maxSegmentErrorDeg = 60,
    this.seedRadiusM = 5,
    this.seedPenaltyDegM = 25,
    this.positionalWeightDegPerM = 0.5,
    this.positionalToleranceM = 6,
    this.positionalMaxOffsetM = 12,
    this.leaderSwitchMarginDeg = 2.5,
    this.ambiguousMarginDeg = 6,
    this.maxHeadingCorrectionPerStepDeg = 0.75,
    this.headingBiasLimitDeg = 60,
    this.headingBiasMaxErrorDeg = 50,
    this.maxTransitionsPerSegment = 3,
    this.maxPathPoints = 800,
    this.maxTrackedPreviewPeaks = 512,
    this.optimisticReconcileMarginM = 2,
    this.junctionZoneRadiusM = 3.5,
    this.junctionZoneEdgeLengthRatio = 0.4,
    this.junctionShortcutPenaltyDegM = 4,
    this.junctionLeaderSwitchMarginDeg = 0.5,
  });

  /// 동시에 유지하는 가설 수. 교차점이 촘촘한 층에서 정답이 살아남을 여유.
  final int beamWidth;

  /// 같은 간선·같은 방향에서 이 간격 안의 가설은 하나로 합친다.
  final double progressBucketM;

  /// 노드를 넘을 때마다 더하는 비용(도·m). 근거 없는 간선 갈아타기를 막되,
  /// 실제 회전을 이기지 못할 만큼 작아야 한다.
  final double transitionPenaltyDegM;

  /// 그래프로 설명되지 않은 이동 1m당 비용(도). 막다른 가설을 죽이지 않고
  /// 크게 벌점만 줘서, 다른 가설이 없을 때도 위치가 멈추지 않게 한다.
  final double deadEndPenaltyDeg;

  /// 관측 방향이 현재 진행 방향과 이만큼 어긋나면 유턴 가설을 함께 만든다.
  final double reverseTriggerDeg;

  /// 비용에서 절대 방위 오차가 차지하는 비중. 나머지는 형태(방위 변화) 오차다.
  ///
  /// 형태를 더 크게 보는 이유: 시작 heading이 틀어져 있어도 회전의 순서와
  /// 크기는 그대로 남기 때문이다. 다만 형태만 보면 전역 회전에 완전히
  /// 무감각해져서 **정반대 방향**도 똑같이 좋은 설명이 된다. 절대 항은 그걸
  /// 막는 최소한의 닻이다.
  ///
  /// heading이 늘 틀어져 있다고 가정하면 안 된다 — 맞는 세션이 더 많다.
  /// 틀어진 경우는 [headingBiasMaxErrorDeg] 아래의 bias 학습이 흡수하고,
  /// 그동안은 형태 항이 버틴다.
  final double absoluteErrorWeight;

  /// 시작 시 씨앗을 까는 반경(m). 사용자가 찍은 위치를 믿는 범위다.
  final double seedRadiusM;

  /// 시작 위치에서 1m 떨어진 씨앗에 매기는 **영구** 벌점(도·m).
  ///
  /// 이 벌점만은 [costHorizonM]으로 잊지 않는다. 잊으면 시작 지점 옆에 나란히
  /// 있던, 실제로는 한 번도 지나간 적 없는 복도의 씨앗이 25m 뒤에 공짜가 되어
  /// 원본 드리프트만으로 1등이 된다. 간선 전이로 도달한 가설과 달리 이 씨앗은
  /// 그래프 연결로 정당화된 적이 없으므로 끝까지 불리해야 한다.
  final double seedPenaltyDegM;

  /// 원본 위치에서 벗어난 1m당 더하는 비용(도/m).
  ///
  /// 방위·형태만으로는 **나란히 놓인 두 복도**를 구분할 수 없다. 실측에서
  /// y=131.1 복도와 9m 북쪽의 y=141.5 복도가 둘 다 동서 방향이라, 위치 항이
  /// 없을 때 엉뚱한 쪽으로 올라가 그대로 눌러앉았다. 구 map matcher가 주
  /// 신호로 쓰던 근접도를 여기서 되살린다.
  final double positionalWeightDegPerM;

  /// 이 거리 안의 어긋남은 벌하지 않는다.
  ///
  /// 넉넉해야 한다. PDR 원본은 누적 드리프트를 안고 가며(실측 106m 왕복에서
  /// 폐합오차 13.8m), 좁게 잡으면 시간이 갈수록 **정답 가설**이 더 크게
  /// 벌점을 먹는다. 나란한 복도 간격(실측 9m)보다 작기만 하면 된다.
  final double positionalToleranceM;

  /// 위치 벌점이 방위 항을 완전히 눌러 버리지 않게 하는 상한.
  final double positionalMaxOffsetM;

  /// 비용이 기억하는 이동 거리(m). 이보다 오래된 증거는 지수적으로 잊는다.
  ///
  /// 없으면 비용이 세션 전체 평균이 되어, 후반에는 누적 거리에 눌려 새 증거가
  /// 순위를 못 바꾼다. 실측에서 130m를 걸은 뒤 마지막 12m를 서쪽으로 갔는데도
  /// 1등이 초반에 고른 간선에 붙박여 확정 위치가 0.5m만 움직였다. 최근 구간을
  /// 더 무겁게 봐야 "지금 어디를 걷고 있는가"에 반응한다.
  final double costHorizonM;

  /// 한 걸음이 낼 수 있는 최대 비용(도). 그 이상은 잘라낸다.
  ///
  /// 안드로이드 실측에서 heading이 직선 복도 위에서도 ±35° 흔들렸다. 이런
  /// 튀는 한 걸음이 비용을 독점하면, 실제로는 없는 회전을 그래프에서 찾아
  /// 엉뚱한 간선으로 갈아탄다. 포화시키면 "많이 틀렸다"까지만 반영된다.
  final double maxSegmentErrorDeg;

  /// 표시 중인 간선을 다른 가설이 이만큼 이겨야 1등을 넘겨준다.
  ///
  /// 없으면 점수가 근소하게 오갈 때마다 화면 위치가 복도 사이를 오간다.
  final double leaderSwitchMarginDeg;

  /// 1·2등 평균 오차가 이 안이면 갈렸다고 본다.
  final double ambiguousMarginDeg;

  final double maxHeadingCorrectionPerStepDeg;
  final double headingBiasLimitDeg;

  /// 이 각도보다 크게 틀어진 상태에서는 bias를 학습하지 않는다. 엉뚱한 간선에
  /// 붙어 있는 동안 bias까지 오염되는 것을 막는다.
  ///
  /// 넉넉해야 한다. 시작 heading 오차는 **세션마다 달라지는 미지수**다(같은
  /// 기기에서도 켤 때마다 다르다). 실측 한 세션에서 복도 대비 28° 넘게
  /// 틀어진 채로 "수렴"한 적이 있다 — 수렴은 흔들림이 작다는 뜻이지 방향이
  /// 맞다는 뜻이 아니다. 이 값이 작으면 정작 보정이 필요한 세션에서 bias가
  /// 영원히 0에 머문다.
  final double headingBiasMaxErrorDeg;

  final int maxTransitionsPerSegment;
  final int maxPathPoints;

  /// optimistic beam이 "이미 태운 걸음"으로 기억하는 peak 식별자 수 상한.
  ///
  /// 확정 시간창을 지난 식별자는 어차피 다시 들어오지 않으므로 먼저 버린다.
  /// 이 상한은 시각이 없어 합성 식별자를 쓰는 세션의 안전장치다.
  final int maxTrackedPreviewPeaks;

  /// 확정 1등에서 optimistic cursor까지 그래프로 도달 가능한지 볼 때 선행분에
  /// 더해 주는 여유(m). 노드 좌표와 보행 거리의 미세한 차이를 흡수한다.
  final double optimisticReconcileMarginM;

  /// 방향 선택이 생기는 graph node 앞뒤로 회전을 허용하는 구간의 반경(m).
  ///
  /// 사람은 node 좌표를 정확히 밟지 않는다. 넓은 코너에서는 안쪽을 잘라 2~3m
  /// 일찍 꺾고, 짐을 들었거나 사람을 피하면 2~3m 지나서 꺾는다. node 통과를
  /// 기다렸다가 후보를 열면 그 사이 걸음이 전부 직진 가설에만 쌓여, 실제로
  /// 꺾은 사람의 마커가 코너에 붙어 버린다.
  ///
  /// 이 값은 **표시·상태 완충 구간**이지 없는 geometry를 만드는 장치가 아니다.
  /// 후보는 언제나 해당 node에 실제로 연결된 간선뿐이다.
  final double junctionZoneRadiusM;

  /// 짧은 간선에서 반경이 간선을 통째로 삼키지 않게 하는 비율 상한.
  ///
  /// 3m 간선이 연달아 붙은 구간에서 반경 3m를 그대로 쓰면 모든 노드가 항상
  /// 전환 구간이 되어, 전환 구간이라는 개념 자체가 무의미해진다.
  final double junctionZoneEdgeLengthRatio;

  /// 전환 구간에서 node로 당겨 붙일 때 남은 거리 1m당 물리는 벌점(도·m).
  ///
  /// 조기/지연 회전 가설은 아직 걷지 않은(또는 이미 지나친) 거리를 건너뛴다.
  /// 그 건너뛴 만큼 불리하게 두면, 방향 증거가 여러 걸음 이어질 때만 이긴다.
  final double junctionShortcutPenaltyDegM;

  /// 전환 구간 안에서 **연결된** 간선으로 1등을 넘겨줄 때의 완화된 여유(도).
  ///
  /// [leaderSwitchMarginDeg]는 평균 오차 기준이라 누적 보행 거리(약 25m)를
  /// 곱하면 60도·m가 넘는 관성이 된다. 직선 복도에서 화면이 복도 사이를 오가는
  /// 것을 막는 데는 옳지만, **회전이 예정된 지점**에서는 정상 회전조차 대여섯
  /// 걸음 늦게 반영된다. 전환 구간에서 연결된 간선으로 넘어가는 경우에만
  /// 관성을 줄인다 — 연결되지 않은 평행 간선에는 여전히 원래 여유를 쓴다.
  final double junctionLeaderSwitchMarginDeg;
}
