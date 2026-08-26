/// 야외 위치 마커의 **방향 삼각형**을 GPS 좌표에서 뽑는 정책.
///
/// 실내 마커는 나침반(PDR 세션의 융합 heading)을 보지만 야외에는 그 세션이 돌지
/// 않는다. 대신 좌표마다 딸려 오는 것이 **진행 방향**(course over ground)이다 —
/// "폰이 어디를 향하고 있나"가 아니라 "직전까지 어느 쪽으로 움직였나"다. 뜻이
/// 다르므로 그리는 규칙도 다르고, 그 규칙이 이 파일이다.
///
/// 검증 기준은 `client/test/screens/outdoor_map/gps/gps_heading_policy_test.dart`.
library;

import 'package:latlong2/latlong.dart' as ll;

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

/// **우리가 직접 잰** 이동 방향과 대조할 수 있는 최소 이동 거리(m).
///
/// 이보다 짧게 움직였으면 두 좌표의 오차가 방향을 통째로 만들어 내므로 대조의
/// 자격이 없다. 보통 걸음으로 4초쯤이고, 도심 GPS 오차(5~10m)보다 크다.
const outdoorHeadingCrossCheckMinTravelM = 5.0;

/// 대조가 성립하는 자리에서 허용하는 어긋남(도).
///
/// 90°는 "앞뒤도 좌우도 아닌" 자리다. 이보다 좁히면 코너를 도는 사람의 정상적인
/// 방향 변화가 걸리고(좌표 두 건 사이의 직선은 실제 경로를 자른다), 넓히면
/// 정반대로 오는 값을 통과시킨다.
const outdoorHeadingCrossCheckMaxGapDeg = 90.0;

/// 대조에 쓸 두 좌표 사이의 최대 간격.
///
/// 이보다 오래 끊겼으면 그사이 어디를 돌아 왔는지 모른다. 직선으로 이은 방향이
/// 실제 진행 방향이라는 전제가 서지 않으므로 대조하지 않는다(거부도 하지 않는다).
const outdoorHeadingCrossCheckMaxGap = Duration(seconds: 12);

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

/// 두 방위 사이의 최단 각차(0~180).
double outdoorHeadingGapDeg(double left, double right) {
  final delta = (left - right) % 360;
  final normalized = delta < 0 ? delta + 360 : delta;
  return normalized > 180 ? 360 - normalized : normalized;
}

/// [from]에서 [to]로 가는 방위(0~360, 진북 기준).
double outdoorTravelBearingDeg(ll.LatLng from, ll.LatLng to) {
  final raw = const ll.Distance().bearing(from, to);
  final normalized = raw % 360;
  return normalized < 0 ? normalized + 360 : normalized;
}

/// 좌표마다 방향을 받아, **지금 마커에 그릴 방향**을 돌려주는 작은 상태.
///
/// 상태를 갖는 이유가 둘이다.
///   - [outdoorHeadingMemory] — 방금까지 알던 방향을 잠깐 들고 있으려면 그 값과
///     시각이 필요하다.
///   - **대조** — 수신기가 말하는 진행 방향을 우리가 잰 이동 방향과 맞춰 보려면
///     직전 좌표가 필요하다. 건물을 나선 직후가 이 대조가 필요한 자리다: 실내에
///     있는 동안 위성 신호는 벽에 반사돼 들어오고, 그 상태로 계산된 course는
///     실제로 걷는 방향과 무관하다. 밖으로 나와 다시 잡히기까지 십수 초가 걸리는데,
///     그동안 수신기는 "모른다"가 아니라 **틀린 값을 자신 있게** 준다.
class OutdoorHeadingTracker {
  double? _deg;
  DateTime? _at;
  ll.LatLng? _lastPoint;
  DateTime? _lastPointAt;

  /// 지금 그릴 방향. 아직 한 번도 못 잡았거나 기억이 낡았으면 null이다.
  double? get headingDeg => _deg;

  /// 좌표 한 건을 넣고 그릴 방향을 받는다.
  ///
  /// [at]은 **좌표를 찍은 시각**이다. 앱이 받은 시각을 쓰면 프레임이 밀린 만큼
  /// 기억이 길어진다(같은 이유로 위치 스트림의 신선도도 기기 시각으로 잰다).
  ///
  /// [point]를 주면 직전 좌표와의 실제 이동 방향으로 한 번 더 거른다. 대조가
  /// 성립하지 않는 자리(움직임이 짧다·간격이 길다·직전 좌표가 없다)에서는 아무것도
  /// 거부하지 않는다 — **틀렸다는 증거가 있을 때만** 버린다.
  double? track({
    required double headingDeg,
    required double headingAccuracyDeg,
    required double speedMps,
    required DateTime at,
    ll.LatLng? point,
  }) {
    var fresh = usableGpsHeadingDeg(
      headingDeg: headingDeg,
      headingAccuracyDeg: headingAccuracyDeg,
      speedMps: speedMps,
    );
    var contradicted = false;
    if (fresh != null && point != null) {
      final measured = _measuredBearingDeg(point, at);
      contradicted =
          measured != null &&
          outdoorHeadingGapDeg(fresh, measured) >
              outdoorHeadingCrossCheckMaxGapDeg;
      if (contradicted) fresh = null;
    }
    if (point != null) {
      _lastPoint = point;
      _lastPointAt = at;
    }
    if (fresh != null) {
      _deg = fresh;
      _at = at;
      return fresh;
    }
    // **대조에 걸린 것과 값이 안 온 것은 다르다.** 값이 안 오는 것(서 있다)은
    // 방금 알던 방향이 여전히 맞다는 뜻이라 들고 있어도 되지만, 대조에 걸렸다는
    // 것은 이 수신기가 지금 방향을 **틀리게** 말하고 있다는 증거다. 들고 있던
    // 값도 같은 수신기가 같은 상태에서 준 것이라 함께 버린다 — 안 버리면 문을
    // 나선 첫 좌표의 틀린 각이 [outdoorHeadingMemory]만큼 화면에 남는다.
    final rememberedAt = _at;
    if (contradicted ||
        rememberedAt == null ||
        at.difference(rememberedAt).abs() > outdoorHeadingMemory) {
      _deg = null;
      _at = null;
    }
    return _deg;
  }

  /// 직전 좌표에서 여기까지 **우리가 잰** 이동 방향. 잴 자격이 없으면 null.
  double? _measuredBearingDeg(ll.LatLng point, DateTime at) {
    final from = _lastPoint;
    final fromAt = _lastPointAt;
    if (from == null || fromAt == null) return null;
    final elapsed = at.difference(fromAt).abs();
    if (elapsed > outdoorHeadingCrossCheckMaxGap) return null;
    final travelM = const ll.Distance().as(ll.LengthUnit.Meter, from, point);
    if (travelM < outdoorHeadingCrossCheckMinTravelM) return null;
    return outdoorTravelBearingDeg(from, point);
  }

  /// 방향을 통째로 잊는다. **좌표를 버리는 자리마다 함께 부른다** — 스트림이
  /// 끊기거나 실내로 들어가면 마지막으로 알던 방향도 더는 지금 이야기가 아니다.
  ///
  /// 대조의 기준점도 함께 버린다. 남겨 두면 건물 안을 가로질러 나온 사람의 첫
  /// 야외 좌표가 "들어간 문 → 나온 문" 직선을 진행 방향으로 삼는다.
  void reset() {
    _deg = null;
    _at = null;
    _lastPoint = null;
    _lastPointAt = null;
  }
}
