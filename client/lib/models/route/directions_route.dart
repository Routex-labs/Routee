import 'package:latlong2/latlong.dart';

/// 자동차·도보 경로의 안내 한 지점. 정적 미리보기용이다 — 실시간 안내
/// (domain/guidance/route_guidance.dart의 RouteStep)와는 다른 개념이라
/// 섞지 않는다.
///
/// [instruction]은 TMAP 응답 문구가 아니라 좌표로 직접 계산한 값이다 —
/// TMAP 보행자 응답 픽스처에 안내 문구 필드가 없다. 도로명 없이
/// "출발"/"좌회전"/"우회전"/"직진"/"도착"만 나온다.
class DirectionsRouteStep {
  const DirectionsRouteStep({
    required this.instruction,
    required this.distanceMeters,
    required this.point,
  });

  final String instruction;
  final double distanceMeters;
  final LatLng point;
}

enum DirectionsTurn { straight, turnLeft, turnRight }

/// 안내 지점 앞뒤 구간의 방위각 차이로 회전 방향을 정한다. 임계각(20도)
/// 미만이면 직진으로 본다 — 도로가 살짝 휘는 것까지 "회전"으로 부르면
/// 문구가 과민 반응한다.
DirectionsTurn classifyTurn({
  required double bearingBeforeDeg,
  required double bearingAfterDeg,
}) {
  var delta = bearingAfterDeg - bearingBeforeDeg;
  delta = ((delta + 180) % 360) - 180; // -180..180으로 정규화
  if (delta.abs() < 20) return DirectionsTurn.straight;
  return delta > 0 ? DirectionsTurn.turnRight : DirectionsTurn.turnLeft;
}

/// 출발지에서 목적지까지의 **도로 경로**(도보 또는 자동차).
///
/// 두 수단이 같은 모델을 쓰는 이유는 화면이 묻는 것이 같기 때문이다 — 선을
/// 어디에 그리고, 얼마나 걸리고, 얼마나 먼가. 수단마다 모델을 나누면 요약
/// 카드와 지도 레이어가 각각 두 벌이 되는데, 정작 다른 것은 아래 요금 두 줄뿐이다.
class DirectionsRoute {
  const DirectionsRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    this.tollFareWon,
    this.taxiFareWon,
    this.steps = const [],
  });

  final List<LatLng> points;
  final double distanceMeters;
  final int durationSeconds;

  /// 통행료(원). 자동차 경로에만 있고, 무료 구간이면 0이다.
  ///
  /// **null과 0을 구분한다.** null은 "이 수단엔 통행료 개념이 없다"(도보)이고
  /// 0은 "유료도로를 안 탄다"이다. 하나로 뭉치면 도보 경로에 "통행료 없음"이
  /// 적힌다 — 틀린 말은 아니지만 걸어가는 사람에게 아무 의미가 없는 줄이다.
  final int? tollFareWon;

  /// 같은 구간을 택시로 갔을 때의 예상 요금(원). 자동차 경로에만 있다.
  final int? taxiFareWon;

  /// 턴바이턴 미리보기. TMAP 응답이 없으면(또는 아직 계산 안 했으면) 빈
  /// 리스트다 — null이 아니라 빈 리스트인 이유는 호출부가 매번
  /// `steps ?? const []`를 반복하지 않게 하려는 것이다.
  final List<DirectionsRouteStep> steps;
}

/// 자동차 옵션 종류. `feature-car-route-alternatives` 브랜치가 실측으로
/// 고른 TMAP `searchOption` 4개(`0,2,3,10`) 중 의미가 확인된 둘만 이름이
/// 있다. `2`·`3`은 [alternative]로 뭉뚱그린다 — 확인 못 한 의미를 지어내
/// "무료우선"처럼 틀린 이름을 붙이는 것보다 낫다. 도보용 kind는 없다.
enum DirectionsRouteOptionKind {
  /// TMAP `searchOption=0`. 교통최적+추천.
  recommended,

  /// TMAP `searchOption=10`. 최단거리.
  shortestDistance,

  /// TMAP `searchOption=2` 또는 `3`. 정확한 의미 미확인.
  alternative;

  String get label => switch (this) {
    DirectionsRouteOptionKind.recommended => '추천',
    DirectionsRouteOptionKind.shortestDistance => '최단거리',
    DirectionsRouteOptionKind.alternative => '대안',
  };
}

/// 경로 후보 한 줄. 좌표열이 같은 후보는 kinds를 합쳐 한 줄로 보여준다
/// (합치는 로직은 domain/route/directions_route_merge.dart).
class DirectionsRouteOption {
  const DirectionsRouteOption({required this.kinds, required this.route});

  /// 항상 1개 이상. 순서 = 목록에 보일 순서.
  final List<DirectionsRouteOptionKind> kinds;
  final DirectionsRoute route;
}

/// `getDrivingRoute`(단일)가 이미 성공/null 둘로만 구분하듯, TMAP 요청은
/// 네트워크 실패든 "경로 없음"이든 구분 없이 null만 준다 — 그 이상을
/// 구분하는 상태값은 지금 신호가 없다.
enum DirectionsRouteOptionsStatus { ok, failed }

class DirectionsRouteOptions {
  const DirectionsRouteOptions({required this.status, this.options = const []});

  const DirectionsRouteOptions.ok(this.options)
    : status = DirectionsRouteOptionsStatus.ok;

  const DirectionsRouteOptions.failure()
    : status = DirectionsRouteOptionsStatus.failed,
      options = const [];

  final DirectionsRouteOptionsStatus status;
  final List<DirectionsRouteOption> options;

  bool get hasRoutes =>
      status == DirectionsRouteOptionsStatus.ok && options.isNotEmpty;
}
