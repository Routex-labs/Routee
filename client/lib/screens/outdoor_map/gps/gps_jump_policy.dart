/// 좌표 한 건이 **물리적으로 가능한 이동인지** 보고 튄 값을 버리는 정책.
///
/// [gps_freshness_policy.dart]와 짝이다 — 그쪽은 "좌표가 언제 와야 하는가",
/// 여기는 "온 좌표를 받아들일 것인가"다.
///
/// 근거와 상수의 출처는 `docs/client/gps-stream-policy.md` 5절.
library;

import 'package:latlong2/latlong.dart' as ll;

export '../../../models/building/floor_plan.dart' show wgs84DistanceMeters;
import '../../../models/building/floor_plan.dart' show wgs84DistanceMeters;

/// 기준점으로 삼을 수 있는 좌표의 최대 오차(m).
///
/// 기준이 이보다 나쁘면 **거를 자격이 없다.** 튄 좌표를 버리려면 "여기가 맞다"고
/// 말할 수 있어야 하는데, 오차 40 m짜리 점을 기준으로 30 m 이동을 거부하면
/// 실제로 걸어간 사람을 제자리에 붙잡는다.
const trustedFixAccuracyMeters = 15.0;

/// 두 좌표 사이에 허용하는 최대 속도(m/s).
///
/// 15 m/s = 54 km/h. **걸음 기준으로 잡으면 안 된다** — 이 앱에는 자동차 안내가
/// 있어서(`carGuidanceZoom`) 도심 주행 속도를 덮어야 한다. 그보다 빠른 이동은
/// 지하철·고속도로인데, 그 구간은 신호가 끊겼다 돌아오므로 아래 강제 재동기가
/// 받는다.
const maxPlausibleSpeedMps = 15.0;

/// 정지 상태의 흔들림에 주는 여유(m).
///
/// 서 있어도 좌표는 오차 반경만큼 떨린다. 이 여유가 없으면 dt가 짧은 구간
/// (스트림이 1초에 한 건을 줄 때)에서 정상적인 떨림이 전부 튐으로 읽힌다.
const jumpSlackMeters = 20.0;

/// 이 시간을 넘겨 거부가 이어지면 기준을 버리고 따라간다.
///
/// **이 탈출구가 없으면 안 된다.** 기준점이 틀렸을 때(터널을 빠져나온 직후,
/// 차를 타서 실제로 멀리 이동한 경우) 거부가 스스로를 유지해 위치가 영영 옛
/// 자리에 붙는다. 같은 이유로 이 정책은 스트림 좌표에도 걸 수 있다 — 되돌아올
/// 길이 있는 거르기라, `_isStaleEcho`가 스트림을 건드리지 않는 것과 다르다.
const jumpRejectMaxHold = Duration(seconds: 15);

/// 거르기의 기준이 되는 **마지막으로 받아들인** 좌표.
class GpsFixReference {
  const GpsFixReference({
    required this.point,
    required this.accuracyMeters,
    required this.acceptedAt,
  });

  final ll.LatLng point;
  final double accuracyMeters;

  /// 이 좌표를 **받아들인** 시각. 기기가 찍은 시각이 아니다 — 거부가 얼마나
  /// 이어졌는지를 재는 값이라 앱 시계가 기준이어야 한다.
  final DateTime acceptedAt;
}

/// 좌표 하나를 받아들일지. 거부하면 화면에 그리지도, 기준을 갱신하지도 않는다.
///
/// 사다리의 순서가 곧 정책이다.
///   1. 기준이 없으면 받는다(첫 좌표).
///   2. **기준의** 오차가 크면 받는다 — 거를 자격이 없다.
///   3. **이 좌표의** 오차가 작으면 받는다 — 아래 「좋은 좌표는 거르지 않는다」.
///   4. 지난 시간 동안 갈 수 있는 거리 안이면 받는다.
///   5. 거부가 [jumpRejectMaxHold]를 넘겼으면 받는다(강제 재동기).
///   6. 나머지 — 오차가 큰데 멀리 뛴 좌표 — 가 튄 값이다.
///
/// ### 좋은 좌표는 거르지 않는다
///
/// 거르는 대상은 "믿을 만한 자리에서 **못 믿을 좌표**가 멀리 뛴 경우" 하나다.
/// 오차가 작은 좌표까지 거리로 막으면, 실제로 이동한 사용자(문을 나선 직후,
/// 차를 탄 직후)가 옛 자리에 붙는다 — 그쪽이 훨씬 나쁜 실패다. 튀는 좌표는
/// 대개 오차 값도 함께 나빠지므로, 이 조건만으로 실측 증상은 걸린다.
bool shouldAcceptGpsFix({
  required GpsFixReference? reference,
  required ll.LatLng point,
  required double accuracyMeters,
  required DateTime now,
  double maxSpeedMps = maxPlausibleSpeedMps,
  double slackMeters = jumpSlackMeters,
  Duration maxHold = jumpRejectMaxHold,
}) {
  if (reference == null) return true;
  if (reference.accuracyMeters > trustedFixAccuracyMeters) return true;
  if (accuracyMeters <= trustedFixAccuracyMeters) return true;
  final elapsed = now.difference(reference.acceptedAt);
  // 시계가 뒤로 간 경우(기기 시각 보정)는 잴 수 없으므로 거르지 않는다.
  if (elapsed.isNegative) return true;
  final seconds = elapsed.inMilliseconds / 1000;
  final jumpM = wgs84DistanceMeters(reference.point, point);
  if (jumpM <= maxSpeedMps * seconds + slackMeters) return true;
  return elapsed >= maxHold;
}
