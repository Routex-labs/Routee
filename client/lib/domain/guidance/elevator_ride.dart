/// 엘리베이터를 타는 동안 화면이 쓰는 계산들. 활강 진행률의 분모는 **고도표가
/// 아는 시작 층 → 도착 층 총 Δ**다 — 층 하나가 아니다.
///
/// 에스컬레이터 대응물은 `escalator_ride.dart`.
library;

import 'package:latlong2/latlong.dart';

import '../floor/floor_altitude_table.dart';
import '../geo/floor_label.dart';
import 'escalator_ride.dart';

/// 총 Δ의 이 비율을 지나면 도착 층 도면으로 갈아 끼운다.
///
/// 에스컬레이터의 절대 Δ 기준(2.4 m)을 그대로 쓸 수 없다. 이 건물 실측 최대
/// 이동이 8개 층·39.87 m(38.2초)라, 2.4 m에서 갈면 남은 37 m를 도착 층 도면만
/// 보며 올라간다. 비율로 잡으면 한 층을 가든 여덟 층을 가든 **탄 층과 내릴 층을
/// 반씩** 본다. 절반을 고른 이유는 그 대칭 자체다 — 더 늦추면 내리기 전에 새 층과
/// 다음 경로를 볼 시간이 모자라고(실측 탑승 18~38초), 더 당기면 에스컬레이터와
/// 같은 문제로 돌아간다.
const elevatorMapSwapProgress = 0.5;

/// 탑승 중 배너에 방향을 적기 시작하는 최소 |Δ|(m).
///
/// 노이즈가 아니라 **평활 지연** 때문에 필요한 값이다. 판정기가 `riding`에
/// 들어가는 순간의 중앙값은 아직 baseline 근처라, 그때 부호를 그대로 읽으면
/// 반대로 적었다가 뒤집는 일이 생긴다. 0.4 m는 판정기가 탑승으로 보는 최저
/// 속도(0.25 m/s)로도 2초 안에 지나는 높이다.
const elevatorRideDirectionMinDeltaM = 0.4;

/// 탑승 중 배너에 적을 이동 방향. 정하지 못하면 null.
///
/// **측정 Δ가 1순위다.** 경로가 말한 도착 층은 "갈 곳"이지 "지금 가는 쪽"이
/// 아니다 — 위층으로 가려고 탔는데 칸이 먼저 아래로 내려가는 일이 실제로 있고,
/// 그때 배너가 말해야 하는 것은 지금 내려간다는 사실이다.
///
/// Δ가 아직 [elevatorRideDirectionMinDeltaM]을 못 넘었을 때만 층 순위로 메운다.
/// 층을 모르면 null이고, 부르는 쪽은 그것을 "아직 배너를 띄우지 마라"로 읽어야
/// 한다 — 반반으로 찍은 방향은 틀리면 정반대다.
bool? elevatorRideGoingUp({
  required double? measuredDeltaM,
  required String? fromFloorLabel,
  required String? toFloorLabel,
}) {
  if (measuredDeltaM != null &&
      measuredDeltaM.abs() >= elevatorRideDirectionMinDeltaM) {
    return measuredDeltaM > 0;
  }
  if (fromFloorLabel == null || toFloorLabel == null) return null;
  final fromRank = floorLabelRank(fromFloorLabel);
  final toRank = floorLabelRank(toFloorLabel);
  // 0은 [floorLabelRank]가 "못 읽었다"로 쓰는 값이다.
  if (fromRank == 0 || toRank == 0 || fromRank == toRank) return null;
  return toRank > fromRank;
}

/// 활강을 걸 최소 총 Δ(m). 이보다 작으면 같은 층이거나 표가 두 층을 거의 같은
/// 높이로 적어 둔 것이고, 그 값을 분모로 쓰면 진행률이 한 샘플에 튄다.
const elevatorGlideMinGapM = 1.0;

/// 기압 누적 변화로 계산한 활강 진행률 목표.
///
/// [deltaTowardsM]는 **도착 층 방향으로** 잰 누적 고도차(m)다 — 내려가는 이동이면
/// 부호를 뒤집어 넣는다. [totalGapM]은 시작 층 → 도착 층 총 Δ이고 이것이 분모다.
/// B1→5F면 한 층이 아니라 5개 층 합(28.73 m)이다.
///
/// 상한은 에스컬레이터와 같은 값을 쓴다([escalatorRideProgressCap]). 1.0은
/// "내렸다"를 말하는 값이라 추정으로 채우지 않는다 — 하차 확정만이 채운다.
double elevatorRideProgressTarget({
  required double deltaTowardsM,
  required double totalGapM,
}) {
  final total = totalGapM.abs();
  if (total < elevatorGlideMinGapM) return 0;
  return (deltaTowardsM / total).clamp(0.0, escalatorRideProgressCap);
}

/// 탑승 노드(시작 층) → 도착 노드(도착 층)를 잇는 활강 한 건.
///
/// 에스컬레이터와 달리 경유점이 없다. 두 점이 화면에서 벌어지는 이유가 구조물의
/// 모양이 아니라 **층마다 다른 도면 등록 오차**이기 때문이다 — 같은 EV1이 1F와
/// B5에서 약 16 m 어긋나 있다(`elevator_arrival.dart`). 그 사이를 직선으로 잇는
/// 것 말고 그릴 근거가 없다.
class ElevatorGlide {
  const ElevatorGlide({required this.from, required this.to});

  /// 둘 다 **절대 좌표(WGS84)다.** 층 로컬 m로 들고 있으면 도면이 갈리는 순간
  /// 같은 숫자가 다른 자리를 가리킨다.
  final LatLng from;
  final LatLng to;

  /// [progress](0 = 탑승, 1 = 하차)에서 마커를 그릴 자리. **등속이다** — 진행률
  /// 자체가 실제 높이에서 나오므로 여기 완화 곡선을 얹으면 화면이 물리에서
  /// 벗어난다.
  LatLng pointAtProgress(double progress) {
    final t = progress.clamp(0.0, 1.0);
    return LatLng(
      from.latitude + (to.latitude - from.latitude) * t,
      from.longitude + (to.longitude - from.longitude) * t,
    );
  }
}

/// 활강 한 건의 계획. **이 값이 만들어졌다는 것 자체가 "활강을 걸 수 있다"**이고,
/// null은 그 반대다.
class ElevatorGlidePlan {
  const ElevatorGlidePlan({
    required this.fromFloor,
    required this.toFloor,
    required this.totalGapM,
    required this.glide,
  });

  final String fromFloor;
  final String toFloor;

  /// 시작 층 → 도착 층 총 고도차(m). 올라가면 양수. 진행률의 분모다.
  final double totalGapM;

  final ElevatorGlide glide;
}

/// 이번 탑승에 활강을 걸 수 있으면 계획을, 아니면 null.
///
/// 셋 중 하나라도 없으면 안 건다. **어림값으로 메우지 않는다** — 분모나 양 끝을
/// 지어내면 마커는 흐르지만 그 진행률이 거짓이 된다.
/// - [table]에 두 층이 다 있어야 한다. 없으면 총 Δ를 모른다.
/// - [toFloor]는 활성 경로가 말한 도착 층이다. 자유 보행이면 null이고, 그때
///   도착 층은 확정 뒤에야 나와 활강을 걸기에 이미 늦다.
/// - [transferPoints]는 경로가 그리는 수직 이동선(탑승→도착, WGS84)이다. 같은 선
///   위를 마커가 흘러야 안내선과 점이 따로 놀지 않는다.
ElevatorGlidePlan? planElevatorGlide({
  required FloorAltitudeTable? table,
  required String? fromFloor,
  required String? toFloor,
  required List<LatLng> transferPoints,
}) {
  if (table == null || fromFloor == null || toFloor == null) return null;
  if (transferPoints.length < 2) return null;
  final gapM = floorGapM(table: table, from: fromFloor, to: toFloor);
  if (gapM == null || gapM.abs() < elevatorGlideMinGapM) return null;
  return ElevatorGlidePlan(
    fromFloor: fromFloor,
    toFloor: toFloor,
    totalGapM: gapM,
    glide: ElevatorGlide(from: transferPoints.first, to: transferPoints.last),
  );
}
