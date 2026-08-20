import 'package:latlong2/latlong.dart';

import '../../models/route/directions_route.dart';
import '../../models/route/transit_route.dart';

/// 카카오 대중교통 경로에 빠져 있는 **앞뒤 도보 구간**을 채운다. 그대로 그리면
/// 사용자가 선 자리에서 한참 떨어진 허공에서 선이 시작한다.
///
/// **총 시간·거리는 건드리지 않는다** — 카카오 `totalTime`에 이 도보가 이미 들어
/// 있다(실측: steps 합보다 786초 큼 ≒ 807m).
///
/// [head]·[tail]이 null이면 직선으로 잇는다 — 실제 보도 모양은 아니지만 비워 두면
/// 그 구간만 툭 끊겨 어느 쪽으로 가야 할지 알 수 없다.
TransitItinerary fillTransitWalkLegs(
  TransitItinerary itinerary, {
  required LatLng origin,
  required LatLng destination,
  DirectionsRoute? head,
  DirectionsRoute? tail,
}) {
  if (itinerary.legs.isEmpty) return itinerary;

  final first = itinerary.legs.first;
  final last = itinerary.legs.last;

  final legs = <TransitLeg>[
    // 이미 도보로 시작하면 카카오가 준 것을 그대로 둔다. 앞에 하나를 더 붙이면
    // 도보 구간이 둘 연달아 나오고, 목록에 "도보 → 도보 → 버스"가 찍힌다.
    if (!first.mode.isWalk)
      _walkLeg(
        route: head,
        from: origin,
        to: first.points.isEmpty ? origin : first.points.first,
        endName: first.startName,
      ),
    ...itinerary.legs,
    if (!last.mode.isWalk)
      _walkLeg(
        route: tail,
        from: last.points.isEmpty ? destination : last.points.last,
        to: destination,
        startName: last.endName,
      ),
  ];

  return TransitItinerary(
    totalTimeSeconds: itinerary.totalTimeSeconds,
    totalWalkTimeSeconds: itinerary.totalWalkTimeSeconds,
    totalDistanceMeters: itinerary.totalDistanceMeters,
    transferCount: itinerary.transferCount,
    legs: legs,
    fare: itinerary.fare,
  );
}

/// 붙일 도보 구간 하나. [route]가 없으면 [from]-[to] 직선으로 떨어진다.
///
/// 시간·거리는 [route]가 있을 때만 채운다. 직선일 때 거리를 지어내면 목록의
/// 구간 시간이 실제와 달라지는데, 그 숫자는 총계와 달리 검증할 근거가 없다.
TransitLeg _walkLeg({
  required DirectionsRoute? route,
  required LatLng from,
  required LatLng to,
  String? startName,
  String? endName,
}) {
  final points = (route != null && route.points.length >= 2)
      ? route.points
      : <LatLng>[from, to];
  return TransitLeg(
    mode: TransitMode.walk,
    sectionTimeSeconds: route?.durationSeconds ?? 0,
    distanceMeters: route?.distanceMeters ?? 0,
    points: points,
    startName: startName,
    endName: endName,
  );
}

/// 채워야 할 도보 한 구간. 좌표는 **소수 5자리(약 1m)로 반올림해** 담는다 —
/// 부동소수 끝자리가 달라 같은 정류장을 두 번 부르는 일을 막고, 그래서 조회
/// 결과를 담는 Map의 키로 그대로 쓸 수 있다(직접 만들어 조회해도 맞물린다).
class TransitWalkGap {
  TransitWalkGap({required LatLng from, required LatLng to})
    : from = _snapTo1m(from),
      to = _snapTo1m(to);

  final LatLng from;
  final LatLng to;

  @override
  bool operator ==(Object other) =>
      other is TransitWalkGap && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// 후보 목록 전체에서 실제로 불러야 할 도보 구간을 **중복 없이** 뽑는다.
/// 부르는 일은 화면이 하고, 여기서는 무엇을 부를지만 정한다.
///
/// 순서는 후보 순서 그대로, 한 후보 안에서는 앞 도보 → 뒤 도보다. 중복을 지운
/// 뒤 [maxGaps]개까지만 남긴다 — 잘리는 것은 **뒤쪽 후보**이고, 잘린 구간은
/// `fillTransitWalkLegs`에 null이 들어가 직선으로 떨어질 뿐 목록은 그대로 뜬다.
/// TMAP 경로안내 그룹이 하루 1,000건을 공유해서 그냥 다 부르면 자동차까지 죽는다.
///
/// 이미 도보로 시작·끝나는 후보와 좌표가 빈 leg는 뽑지 않는다 — 불러도
/// `fillTransitWalkLegs`가 붙이지 않으므로 호출이 통째로 낭비다.
List<TransitWalkGap> transitWalkGaps(
  List<TransitItinerary> itineraries, {
  required LatLng origin,
  required LatLng destination,
  int maxGaps = 10,
}) {
  // Set 리터럴은 넣은 순서를 지킨다 — 같은 입력이면 같은 순서로 나와야 한다.
  final gaps = <TransitWalkGap>{};
  for (final itinerary in itineraries) {
    if (itinerary.legs.isEmpty) continue;
    final first = itinerary.legs.first;
    final last = itinerary.legs.last;
    if (!first.mode.isWalk && first.points.isNotEmpty) {
      gaps.add(TransitWalkGap(from: origin, to: first.points.first));
    }
    if (!last.mode.isWalk && last.points.isNotEmpty) {
      gaps.add(TransitWalkGap(from: last.points.last, to: destination));
    }
  }
  return gaps.take(maxGaps).toList();
}

/// 소수 5자리 ≒ 1m. 이보다 가까운 두 좌표는 걸어서 같은 자리다.
LatLng _snapTo1m(LatLng point) => LatLng(
  (point.latitude * 1e5).round() / 1e5,
  (point.longitude * 1e5).round() / 1e5,
);
