/// 에스컬레이터를 타는 동안 화면이 쓰는 계산들.
///
/// 탑승부터 하차까지 **수평 위치를 측정하지 못한다**(걸음은 일부러 멈춰 있고 도면도
/// 중간에 갈린다). 대신 양 끝과 높이는 알므로 마커를 **기압 진행률**로 흘린다 —
/// 고정 2.4초는 실제 탑승(20~35초)보다 짧아 "점이 끝까지 안 내려온다"로 보였다.
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// 하차 지점 카메라 정렬 시간이자, 양 끝을 몰라 활강을 못 걸었을 때 스크림
/// 카드가 자체 재생하는 길이.
///
/// 마커 활강 자체는 이 시간을 쓰지 않는다 — 진행률이 기압에서 나온다.
const escalatorGlideDuration = Duration(milliseconds: 2400);

/// 표시 진행률을 목표 쪽으로 끌어당기는 틱 주기.
///
/// 기압 샘플은 기기에 따라 0.18~1.07초 간격이라 그대로 그리면 마커가 툭툭
/// 끊긴다. 이 주기로 [escalatorRideProgressEase]만큼씩 따라간다.
const escalatorGlideSampleInterval = Duration(milliseconds: 60);

/// 같은 에스컬레이터의 실측 층고를 아직 모를 때 쓰는 기본값(m).
///
/// 더현대 실측 한 층 4.4~6.2m의 가운데이며, 2026-08-13 B1↔B2 실측
/// (0.7 hPa ≈ 5.8m)과 같다. 한 번 확정하고 나면 그 에스컬레이터 그룹의 실측
/// Δ를 대신 쓴다.
const escalatorDefaultFloorHeightM = 5.8;

/// 하차 확정 전 진행률 상한.
///
/// 층고 추정이 실제보다 작으면 진행률이 하차 전에 1에 닿는다. 1은 "도착"을
/// 말하는 값이라 추정으로는 채우지 않는다 — 확정(landed)만이 1을 채운다.
const escalatorRideProgressCap = 0.95;

/// 표시 진행률이 목표를 따라가는 지수 평활 계수(틱당).
///
/// 60ms 틱 기준 시정수 약 0.5초 — 기압 샘플이 1초 간격(iOS)이어도 점이
/// 끊기지 않고, 하차 확정(목표 1.0)에는 반 초 안에 붙는다.
const escalatorRideProgressEase = 0.12;

/// 기압 누적 변화로 계산한 탑승 진행률 목표. 활강은 도면 교체 순간 시작하므로 그
/// 지점을 0으로, 남은 높이를 1로 정규화한다.
///
/// [escalatorRideProgressCap]에서 멈춘다 — 이 값은 추정이고 끝맺음은 하차 확정
/// 이벤트가 한다. 남은 높이는 1m로 하한을 둔다(즉시 상한에 붙는 것 방지).
double escalatorRideProgressTarget({
  required double deltaTowardsM,
  required double swapDeltaM,
  required double expectedTotalM,
}) {
  final remainingM = math.max(expectedTotalM - swapDeltaM, 1.0);
  return ((deltaTowardsM - swapDeltaM) / remainingM).clamp(
    0.0,
    escalatorRideProgressCap,
  );
}

/// 탑승 → 도착을 잇는 활강 한 건. 진행률을 밖에서 받고 티커를 들지 않으므로 위젯
/// 없이 검증한다.
///
/// 경로는 직선이 아니라 **폴리라인**이다 — 크로스형 뱅크에서 두 노드를 직선으로
/// 이으면 마커가 구조물을 대각선으로 가로지른다(2026-08-13 실측 지적).
class EscalatorGlide {
  EscalatorGlide({required this.points})
    : assert(points.length >= 2, '양 끝 없이 활강을 그릴 수 없다'),
      _cumulativeM = _cumulativeDistances(points);

  /// 탑승 노드 → (경유점들) → 하차 노드(WGS84).
  ///
  /// **전부 절대 좌표다.** 층 로컬 m로 들고 있으면 도면이 갈아 끼워지는
  /// 순간 같은 숫자가 다른 자리를 가리켜 마커가 튄다.
  final List<LatLng> points;

  final List<double> _cumulativeM;

  LatLng get from => points.first;
  LatLng get to => points.last;

  /// [progress](0=탑승, 1=하차)에서 마커를 그릴 자리. **등속(선형)이다** — 진행률
  /// 자체가 실제 높이에서 나오므로 여기 완화 곡선을 얹으면 화면이 물리에서 벗어난다.
  LatLng pointAtProgress(double progress) {
    final totalM = _cumulativeM.last;
    if (totalM <= 0) return to;
    final targetM = progress.clamp(0.0, 1.0) * totalM;
    var index = 1;
    while (index < points.length - 1 && _cumulativeM[index] < targetM) {
      index++;
    }
    final segmentStartM = _cumulativeM[index - 1];
    final segmentM = _cumulativeM[index] - segmentStartM;
    final t = segmentM <= 0 ? 1.0 : (targetM - segmentStartM) / segmentM;
    final a = points[index - 1];
    final b = points[index];
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  /// 각 점까지의 누적 거리(m, 등장방형 근사). 진행률을 길이 비율로 옮길 때
  /// 쓰므로 절대 정확도는 필요 없다 — 구간끼리의 비만 맞으면 된다.
  static List<double> _cumulativeDistances(List<LatLng> points) {
    const metersPerDegreeLat = 111320.0;
    final result = List<double>.filled(points.length, 0);
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      final meanLatRad = (a.latitude + b.latitude) * math.pi / 360;
      final eastM =
          (b.longitude - a.longitude) *
          math.cos(meanLatRad) *
          metersPerDegreeLat;
      final northM = (b.latitude - a.latitude) * metersPerDegreeLat;
      result[i] = result[i - 1] + math.sqrt(eastM * eastM + northM * northM);
    }
    return result;
  }
}

/// 하차 지점에서 두 점이 이만큼은 떨어져 있어야 방향을 말한다. 도면이 두 노드를
/// 같은 자리에 찍어 둔 층이 있고, 그때 방위각은 좌표 오차가 만드는 **아무 방향**
/// 이다 — 그 값으로 돌리느니 안 돌리는 편이 낫다.
const escalatorExitBearingMinSeparationM = 3.0;

/// 에스컬레이터를 내리는 순간 사용자가 바라보는 방향(탑승 → 도착 방위각).
///
/// **경로 방향이 아니다** — 새 층 경로 축에 맞추면 화면은 "앞으로 갈 방향"인데
/// 몸은 아직 에스컬레이터 정면이라, 사용자가 화면과 몸을 맞추는 것부터 다시 한다.
///
/// 두 점이 너무 가까우면 null이고, 호출부는 카메라 각도를 그대로 둔다.
double? escalatorExitBearingDeg({
  required LatLng boarding,
  required LatLng arrival,
  double minSeparationM = escalatorExitBearingMinSeparationM,
}) {
  const metersPerDegreeLat = 111320.0;
  final meanLatRad = (boarding.latitude + arrival.latitude) * math.pi / 360;
  final eastM =
      (arrival.longitude - boarding.longitude) *
      math.cos(meanLatRad) *
      metersPerDegreeLat;
  final northM = (arrival.latitude - boarding.latitude) * metersPerDegreeLat;
  if (math.sqrt(eastM * eastM + northM * northM) < minSeparationM) return null;
  final deg = math.atan2(eastM, northM) * 180 / math.pi;
  return deg < 0 ? deg + 360 : deg;
}

/// 활강 폴리라인. **축을 알면 탑승점도 축 위에서 고른다.**
///
/// [from](그래프 탑승 노드)과 [axis](도면 폴리곤 긴 축)는 별개 데이터라 서로
/// 어긋난다 — 서버의 에스컬레이터 도형은 실제 탑승 노드가 아니라 주변 junction을
/// 가리킨다(`domain/route/transfer_route_geometry.dart` 참고). 그 둘을 이어
/// 그리면 첫 구간이 폴리곤 **밖에서 안으로** 들어오는 선분이 되고, 마커가 그
/// 위를 지나며 위치가 한 번 튄다.
///
/// 그래서 축이 있으면 [from]은 폴리라인에 넣지 않는다. 축의 두 끝 중 [to]에서
/// **먼** 쪽이 곧 탑승 지점이다. 축을 모르면 옮길 근거가 없으니 예전처럼 두
/// 노드를 직선으로 잇는다.
///
/// [to]와 1m 안으로 겹치는 축 끝은 버린다 — 남기면 그 구간 진행률이 0으로 나뉜다.
List<LatLng> escalatorGlidePoints({
  required LatLng from,
  required LatLng to,
  (LatLng, LatLng)? axis,
}) {
  if (axis == null) return [from, to];
  const distance = Distance();
  final (a, b) = axis;
  final (far, near) = distance(a, to) >= distance(b, to) ? (a, b) : (b, a);
  // 축 전체가 하차 노드에 겹쳐 있으면(도형이 뭉개진 층) 축으로 옮길 것이 없다.
  if (distance(far, to) < 1.0) return [from, to];
  return [far, if (distance(near, to) >= 1.0) near, to];
}

/// 활강 폴리라인에서 뽑은 하차 방향.
///
/// 폴리라인이 이미 축에 정렬돼 있으므로 끝 구간이 곧 내리는 방향이다. 마지막
/// 구간이 [escalatorExitBearingMinSeparationM]보다 짧으면(도면이 하차 노드를 축
/// 끝에 거의 겹쳐 찍는다) 한 점씩 거슬러 올라가 축 전체를 본다. 그래도 못 채우면
/// null — 호출부는 카메라를 안 돌린다.
double? escalatorGlideExitBearingDeg(List<LatLng> points) {
  for (var i = points.length - 2; i >= 0; i--) {
    final bearing = escalatorExitBearingDeg(
      boarding: points[i],
      arrival: points.last,
    );
    if (bearing != null) return bearing;
  }
  return null;
}
