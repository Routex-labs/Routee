/// 야외 위치 마커의 **방향 삼각형**을 GPS 좌표에서 뽑는 정책.
///
/// 실내 마커는 나침반(PDR 세션의 융합 heading)을 보지만 야외에는 그 세션이 돌지
/// 않는다. 대신 좌표마다 딸려 오는 것이 **진행 방향**(course over ground)이다 —
/// "폰이 어디를 향하고 있나"가 아니라 "직전까지 어느 쪽으로 움직였나"다. 뜻이
/// 다르므로 그리는 규칙도 다르고, 그 규칙이 이 파일이다.
///
/// 검증 기준은 `client/test/screens/outdoor_map/gps/gps_heading_policy_test.dart`.
library;

/// 이 속도 아래에서는 진행 방향을 믿지 않는다(m/s).
///
/// 보통 걸음이 1.1~1.5 m/s다. 0.5는 그 3분의 1로, 천천히 걷는 사람은 통과하고
/// 서 있는 사람은 걸린다. 더 올리면 느린 걸음에서 삼각형이 깜빡이고, 더 내리면
/// 서 있는 동안 좌표 잡음이 만든 가짜 속도가 통과해 삼각형이 제자리에서 돈다.
const outdoorHeadingMinSpeedMps = 0.5;

/// 방향 정확도가 이보다 나쁘면 버린다(도). **값이 실려 온 경우에만 본다** —
/// Android는 못 구하면 0을 주는데, 그것을 "0도 오차"로 읽으면 거꾸로 가장
/// 못 믿을 값이 가장 정확한 값이 된다.
const outdoorHeadingMaxAccuracyDeg = 60.0;

/// 마지막으로 믿은 방향을 이만큼 들고 있는다.
///
/// 횡단보도 신호(20~30초)를 다 덮지는 않는다 — 그렇게 오래 서 있었으면 몸이
/// 돌아갔을 수 있어서, 없는 편이 틀린 것보다 낫다. 6초는 걸음을 멈췄다 다시
/// 떼는 정도를 덮는 길이다.
const outdoorHeadingMemory = Duration(seconds: 6);

/// 좌표 한 건이 실어 온 방향을 **그대로 써도 되는지** 가른다. 못 쓰면 null.
///
/// [headingDeg]가 음수인 것은 iOS가 "못 구했다"를 말하는 방식이고(`course`가
/// -1), Android는 같은 상황에서 0을 준다 — 그쪽은 [speedMps]가 걸러 준다.
double? usableGpsHeadingDeg({
  required double headingDeg,
  required double headingAccuracyDeg,
  required double speedMps,
}) {
  if (!headingDeg.isFinite || headingDeg < 0 || headingDeg > 360) return null;
  if (!speedMps.isFinite || speedMps < outdoorHeadingMinSpeedMps) return null;
  if (headingAccuracyDeg.isFinite &&
      headingAccuracyDeg > 0 &&
      headingAccuracyDeg > outdoorHeadingMaxAccuracyDeg) {
    return null;
  }
  return headingDeg % 360;
}

/// 좌표마다 방향을 받아, **지금 마커에 그릴 방향**을 돌려주는 작은 상태.
///
/// 상태를 갖는 이유는 [outdoorHeadingMemory] 하나뿐이다 — 방금까지 알던 방향을
/// 잠깐 들고 있으려면 그 값과 시각이 필요하다.
class OutdoorHeadingTracker {
  double? _deg;
  DateTime? _at;

  /// 지금 그릴 방향. 아직 한 번도 못 잡았거나 기억이 낡았으면 null이다.
  double? get headingDeg => _deg;

  /// 좌표 한 건을 넣고 그릴 방향을 받는다.
  ///
  /// [at]은 **좌표를 찍은 시각**이다. 앱이 받은 시각을 쓰면 프레임이 밀린 만큼
  /// 기억이 길어진다(같은 이유로 위치 스트림의 신선도도 기기 시각으로 잰다).
  double? track({
    required double headingDeg,
    required double headingAccuracyDeg,
    required double speedMps,
    required DateTime at,
  }) {
    final fresh = usableGpsHeadingDeg(
      headingDeg: headingDeg,
      headingAccuracyDeg: headingAccuracyDeg,
      speedMps: speedMps,
    );
    if (fresh != null) {
      _deg = fresh;
      _at = at;
      return fresh;
    }
    final rememberedAt = _at;
    if (rememberedAt == null ||
        at.difference(rememberedAt).abs() > outdoorHeadingMemory) {
      _deg = null;
      _at = null;
    }
    return _deg;
  }

  /// 방향을 통째로 잊는다. **좌표를 버리는 자리마다 함께 부른다** — 스트림이
  /// 끊기거나 실내로 들어가면 마지막으로 알던 방향도 더는 지금 이야기가 아니다.
  void reset() {
    _deg = null;
    _at = null;
  }
}
