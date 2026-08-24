/// 말이 안 되는 GPS 좌표를 **표시에서** 빼는 규칙. 사람은 5초에 50 m를 못 간다.
///
/// 오차 값이 아니라 **물리**로 거른다 — 실측에서 수신기가 오차 13 m라고 보고한
/// 좌표가 실제로는 51.7 m 틀렸다. 오차 문턱을 조이면 거짓말을 더 믿게 된다.
/// 거른 좌표도 **건물 안팎 판정에는 넣는다**. 판정에서도 빼야 하는지는
/// `gps_rejected_fixes`가 다음 실측에서 답한다.
///
/// 실측 숫자와 상한의 근거는 `docs/client/gps-stream-policy.md`.
library;

import 'package:latlong2/latlong.dart' as ll;

import '../../../models/building/floor_plan.dart';

/// 걸어서 낼 수 있다고 보는 속도 상한(m/s).
///
/// 걷기 1.4 · 빠른 걸음 2.0 · 뛰기 3.0 안팎이다. 3.5는 **뛰는 사람도 통과시키되**
/// 실측의 도약(5초에 50 m ≈ 10 m/s)은 확실히 막는 자리다. 상한을 낮게 잡을수록
/// 진짜로 뛴 사용자가 화면에서 멈추므로, 거짓 양성보다 거짓 음성을 택했다.
///
/// **보행 전용 값이다.** 자동차 안내 중에는 이 규칙을 통째로 끈다
/// ([stepGpsJumpFilter]의 `walking`).
const kWalkingJumpSpeedCapMps = 3.5;

/// 시간과 무관하게 허용하는 도약(m). 두 좌표가 **서로 다른 오차**를 갖고 있어
/// 생기는 몫이다.
///
/// 제자리에 서 있어도 연속한 두 GPS 좌표는 각자의 오차만큼 떨어져 찍힌다. 이
/// 몫이 없으면 정지 상태의 정상적인 흔들림까지 전부 거른다. 15는 진입 판정이
/// 좌표 한 건을 믿는 오차 상한(`decisiveAccuracyMeters` 20)보다 작고, 실측의
/// 51.7 m보다 한참 작은 자리다.
///
/// **이 규칙이 못 잡는 것**: 이 몫은 좌표 한 건마다 새로 주어지므로, 오차가
/// **매끄럽게 흘러가면** 걸리지 않는다 — 1 Hz에서 한 건에 18 m씩(15 + 3.5)
/// 계속 미끄러지면 전부 통과한다. 잡는 것은 **한 번에 크게 튀는 것**이고,
/// 실측이 보인 것이 그 모양이다(문 앞 → 51.7 m). 튄 뒤에는 기준점을 안 옮기므로
/// 이어지는 좌표도 계속 걸린다.
/// ponytail: 한 건 대 한 건 비교. 매끄러운 표류까지 잡으려면 마지막 N건의
/// 중앙값을 기준으로 삼아야 하는데, 그건 실측에서 그 모양이 실제로 나온 뒤에 한다.
const kJumpFilterGraceMeters = 15.0;

/// 연속으로 이만큼 거르면 **항복하고 받아들인다.**
///
/// 영원히 거르면 진짜로 이동한 사용자가 화면에서 멈춘다. 첫 좌표가 잘못 잡힌
/// 채로 시작하면(그 자리가 기준이 되면) 이후 옳은 좌표가 전부 걸리는데,
/// 항복이 그 상태의 유일한 출구다.
const kJumpFilterSurrenderCount = 5;

/// 첫 거름으로부터 이만큼 지나도 **항복한다.**
///
/// 건수와 시간을 **둘 다** 두고 먼저 오는 쪽을 쓴다. 실기기에서 스트림이 1초를
/// 약속하고도 15~36초에 한 건을 준 적이 있어(`docs/client/gps-stream-policy.md`)
/// 건수만 두면 5건을 채우는 데 몇 분이 걸릴 수 있고, 시간만 두면 1 Hz 정상
/// 스트림에서 10건을 통째로 버린다. **화면이 멈춰 있는 시간의 상한이 10초**가
/// 되도록 맞춘 값이다.
const kJumpFilterSurrenderHold = Duration(seconds: 10);

/// 직전 채택 좌표가 이보다 오래됐으면 **거르지 않는다.**
///
/// 규칙의 전제가 "몇 초 전 그 자리에서 여기까지 못 온다"인데, 끊긴 구간이 길면
/// 그 사이 무슨 일이 있었는지 모른다(백그라운드·차량·터널). 모르는 구간을 물리로
/// 재면 근거 없이 옳은 좌표를 버린다. 고치려는 증상은 1초 간격 좌표가 51 m씩 튀는
/// 것이라 이 문턱보다 훨씬 촘촘한 자리에서 일어난다.
const kJumpFilterStaleGap = Duration(seconds: 15);

/// 거르기가 들고 있는 전부 — 마지막으로 **받아들인** 좌표와, 지금 몇 건째
/// 거르는 중인지.
class GpsJumpFilterState {
  const GpsJumpFilterState({
    this.acceptedPoint,
    this.acceptedAt,
    this.rejectedInARow = 0,
    this.firstRejectedAt,
  });

  /// 마지막으로 받아들인 좌표. null이면 아직 한 건도 없다(첫 건은 무조건 통과).
  final ll.LatLng? acceptedPoint;

  /// 그 좌표가 **찍힌** 시각(기기 시각). 받은 시각이 아니다 — 프레임이 밀린
  /// 시간이 섞이면 허용 거리가 그만큼 부풀어 도약을 통과시킨다.
  final DateTime? acceptedAt;

  /// 지금까지 연속으로 거른 건수. 한 건이라도 받아들이면 0으로 돌아간다.
  final int rejectedInARow;

  /// 이번 연속 거름이 시작된 시각.
  final DateTime? firstRejectedAt;
}

/// 좌표 한 건을 통과시킬지 정한다. 상태를 안 들고 있으니 호출자가
/// [GpsJumpFilterState]를 보관했다가 돌려받은 값으로 갱신한다.
///
/// [accepted]가 false면 그 좌표를 **표시에서 뺀다.** 건물 안팎 판정에는 그대로
/// 넣는다 — 처음에는 판정에서도 빼려 했으나, 그렇게 하면 판정이 늦어지는 대가만
/// 확실하고 이득은 아직 근거가 없다. 이탈은 이제 문 근거
/// (`entry/indoor_exit_evidence.dart`)가 주 경로이고 그쪽은 GPS 오차와 무관하다.
/// 판정에서도 빼야 하는지는 `gps_rejected_fixes`가 다음 실측에서 답한다 —
/// 거른 좌표가 verdict를 뒤집었을 값이었는지 보고 정한다.
///
/// [walking]이 false면(자동차 안내 중) 아무것도 거르지 않고 상태만 갱신한다.
/// 자동차는 30 m/s를 내므로 보행 상한을 그대로 대면 전부 걸린다.
///
/// [surrendered]는 **항복해서** 받아들인 건이다([accepted]도 함께 true다).
/// 레코더가 이 둘을 구분해 남긴다 — 항복이 잦으면 상한이 너무 빡빡하다는 뜻이다.
({
  GpsJumpFilterState state,
  bool accepted,
  bool surrendered,
  double? jumpM,
  double? allowanceM,
  double elapsedSeconds,
})
stepGpsJumpFilter({
  required GpsJumpFilterState state,
  required ll.LatLng point,
  required DateTime at,
  required bool walking,
  double speedCapMps = kWalkingJumpSpeedCapMps,
}) {
  ({
    GpsJumpFilterState state,
    bool accepted,
    bool surrendered,
    double? jumpM,
    double? allowanceM,
    double elapsedSeconds,
  })
  accept({
    required bool surrendered,
    double? jumpM,
    double? allowanceM,
    double elapsedSeconds = 0,
  }) => (
    state: GpsJumpFilterState(acceptedPoint: point, acceptedAt: at),
    accepted: true,
    surrendered: surrendered,
    jumpM: jumpM,
    allowanceM: allowanceM,
    elapsedSeconds: elapsedSeconds,
  );

  final last = state.acceptedPoint;
  final lastAt = state.acceptedAt;
  if (!walking || last == null || lastAt == null) {
    return accept(surrendered: false);
  }

  // **나누지 않는다.** 속도로 재려면 경과 시간으로 나눠야 하는데, 같은 시각에
  // 두 건이 오면(기기가 timestamp를 똑같이 찍는다) 0으로 나눠 무한대가 나온다.
  // 대신 "그 사이에 걸을 수 있는 거리"를 곱해서 만든다 — 같은 판정이고,
  // 경과 시간이 0이면 허용치가 [kJumpFilterGraceMeters]로 줄 뿐이다.
  // 시계가 거꾸로 간 경우(음수)도 같은 자리로 떨어진다.
  final elapsed = at.difference(lastAt).inMilliseconds / 1000.0;
  final seconds = elapsed.isFinite && elapsed > 0 ? elapsed : 0.0;
  // **오래 끊겼으면 판정하지 않는다.** 이 규칙의 전제는 "몇 초 전에 여기 있었으니
  // 지금 저기일 리 없다"인데, 그 사이가 길면 전제가 성립하지 않는다 — 앱이 백그라운드로
  // 내려가 있었을 수도, 차를 탔을 수도 있다. 모르는 구간을 물리로 재는 것은 근거가 아니다.
  // 실제로 고치려는 증상은 **1초 간격 좌표가 51 m씩 튀는 것**이라 이 문턱과 무관하다.
  //
  // **이미 거르는 중이면 여기서 빠져나가지 않는다.** 그때의 출구는 항복이고
  // ([kJumpFilterSurrenderHold]), 그 규칙은 정확히 "스트림이 15~36초에 한 건을 주는
  // 기기" 때문에 있다. 여기서 먼저 통과시키면 항복이 영영 안 걸려 진단에서 사라진다.
  if (state.rejectedInARow == 0 && seconds > kJumpFilterStaleGap.inSeconds) {
    return accept(surrendered: false);
  }
  final allowanceM = kJumpFilterGraceMeters + speedCapMps * seconds;
  final jumpM = wgs84DistanceMeters(last, point);
  if (jumpM <= allowanceM) {
    return accept(
      surrendered: false,
      jumpM: jumpM,
      allowanceM: allowanceM,
      elapsedSeconds: seconds,
    );
  }

  // 항복 판정은 **이번 건을 센 뒤**에 한다. 세기 전에 보면 상한이 5일 때 6건째에
  // 항복해, 주석에 적은 값과 실제 동작이 어긋난다.
  final rejectedInARow = state.rejectedInARow + 1;
  final firstRejectedAt = state.firstRejectedAt ?? at;
  if (rejectedInARow >= kJumpFilterSurrenderCount ||
      at.difference(firstRejectedAt) >= kJumpFilterSurrenderHold) {
    return accept(
      surrendered: true,
      jumpM: jumpM,
      allowanceM: allowanceM,
      elapsedSeconds: seconds,
    );
  }
  return (
    // 거른 건은 기준점을 **안 옮긴다.** 옮기면 튄 좌표가 다음 판정의 기준이 돼
    // 거르기가 튄 자리를 따라간다.
    state: GpsJumpFilterState(
      acceptedPoint: last,
      acceptedAt: lastAt,
      rejectedInARow: rejectedInARow,
      firstRejectedAt: firstRejectedAt,
    ),
    accepted: false,
    surrendered: false,
    jumpM: jumpM,
    allowanceM: allowanceM,
    elapsedSeconds: seconds,
  );
}
