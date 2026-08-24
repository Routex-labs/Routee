import 'package:latlong2/latlong.dart';

import '../../models/route/directions_route.dart';

/// 이 거리보다 멀리 떨어져 끝나면 도착점까지 선을 이어 붙인다(m).
///
/// 3 m보다 가까우면 사실상 같은 점이라 이어 붙여 봐야 화면에서 보이지 않고,
/// 좌표만 하나 늘어난다.
const _minGapMeters = 3.0;

/// 이보다 멀면 잇지 않는다(m).
///
/// 이어 붙이는 선은 **직선**이라, 길면 길수록 실제 걸을 수 있는 길과 달라진다.
/// 건물 입구까지의 마지막 몇십 미터를 메우자고 200 m짜리 직선을 그으면 건물이나
/// 도로를 관통하는 안내가 되는데, 그건 끊긴 선보다 나쁘다 — 끊긴 선은 사용자가
/// "여기부터는 알아서 가야겠구나"로 읽지만, 그어진 직선은 길이라고 읽는다.
const _maxGapMeters = 150.0;

/// 이 거리 안에서 끝났으면 "도착점까지 왔다"고 본다(m).
///
/// 인도가 문 바로 앞까지 나 있어도 도로 선형은 차도 중심이라 문과 10~20 m는
/// 벌어진다. 그 정도는 도착한 것이고, 남은 몇 걸음을 직선으로 메우면 된다.
///
/// **이 값을 넘으면 이야기가 달라진다.** TMAP은 도착점이 보행 네트워크에 없으면
/// 실패로 답하지 않고 **가장 가까운 보행 노드로 목적지를 바꿔** 경로를 준다.
/// 즉 우리가 받은 선은 "우리 문까지 가는 길"이 아니라 "그 노드까지 가는 길"이다.
/// 실측(더현대 서울 남서쪽 출구): 문에서 52 m 떨어진 정류장에서 출발하면 TMAP은
/// 69 m짜리 경로를 주는데, 그 끝점은 문이 아니라 **서쪽으로 35 m 떨어진 지하철
/// 출입구 광장**이다. 화면에서는 서쪽으로 한참 돌았다가 벽을 따라 되돌아오는
/// 선으로 보인다.
const _snapToleranceMeters = 20.0;

/// 우회를 대신할 직선의 길이 상한(m).
///
/// [_maxGapMeters]보다 훨씬 짧게 잡는다. 이 직선은 "선이 끊긴 자리를 메우는"
/// 것이 아니라 **도로 경로를 덜어 내고 대신 그리는** 선이라, 틀렸을 때 사용자가
/// 실제로 그 방향으로 걷는다. 마당·광장을 가로지르는 정도(80 m)까지만 허용하고
/// 그보다 길면 TMAP이 준 우회로를 그대로 둔다 — 돌아가더라도 실제로 걸을 수
/// 있는 길이 관통선보다 낫다.
const _shortcutMaxMeters = 80.0;

/// 직선이 도로 경로보다 이 배는 짧아야 바꾼다.
///
/// 직선 거리는 언제나 도로 거리보다 짧다. 마진 없이 비교하면 정상적인 경로도
/// 전부 직선으로 갈아 치우게 되므로, "확실히 돌아간다"고 말할 수 있는 폭을 둔다.
/// 1.5배는 50% 이상 돌아가는 경우다(위 실측은 104 m 대 54 m로 1.9배였다).
const _shortcutRatio = 1.5;

const _distance = Distance();

/// 도로 경로의 끝을 실제 도착점에 맞춘다. TMAP은 **가장 가까운 보행 가능 도로**
/// 에서 끝나므로, 도착점이 건물 출입구면 선이 도로에서 뚝 끊긴다.
///
/// 벌어진 거리로 셋으로 갈린다 — [_minGapMeters] 미만은 같은 점,
/// [_snapToleranceMeters] 이하는 도착점을 뒤에 붙여 잇고, 그보다 멀면
/// **TMAP이 우리 도착점에 닿지 못한 것**이라 직선이 확실히 짧아지는 첫 지점에서
/// 끊고 직선으로 잇는다([_maxGapMeters]를 넘으면 그것도 안 한다).
///
/// 잇기만 할 때는 거리·시간을 건드리지 않는다(숫자의 출처가 둘로 갈린다).
/// 선을 잘라 낸 경우만 새 기하로 다시 계산한다.
DirectionsRoute? extendRouteToDestination(
  DirectionsRoute? route,
  LatLng? destination,
) {
  if (route == null || destination == null) return route;
  if (route.points.length < 2) return route;

  final gap = _distance.as(LengthUnit.Meter, route.points.last, destination);
  if (gap < _minGapMeters) return route;

  if (gap > _snapToleranceMeters) {
    final shortcut = _replaceDetourTail(route, destination, gap);
    if (shortcut != null) return shortcut;
  }

  if (gap > _maxGapMeters) return route;

  return DirectionsRoute(
    points: [...route.points, destination],
    distanceMeters: route.distanceMeters,
    durationSeconds: route.durationSeconds,
    tollFareWon: route.tollFareWon,
    taxiFareWon: route.taxiFareWon,
  );
}

/// 도로 경로의 **시작**을 실제 출발점에 맞춘다. 끝을 맞추는
/// [extendRouteToDestination]의 거울상이다.
///
/// **끝만 맞춰서는 문에서 안 이어진다.** TMAP은 출발점도 가장 가까운 보행 가능
/// 도로로 스냅하므로, 건물 출입구를 출발점으로 주면 받은 선이 문이 아니라 그
/// 앞 도로 어딘가에서 시작한다. 실내 선은 문에서 끝나 있어서 두 구간 사이가
/// 통째로 비어 보인다 — 「밖으로 나가기」를 눌러도, 아직 안에서 계획 화면을
/// 보고 있어도 같은 화면이다(실기기 증상).
///
/// 갈리는 규칙·문턱은 [extendRouteToDestination]과 **같아야 한다.** 한쪽만
/// 고치면 같은 여정의 두 끝이 서로 다른 규칙으로 이어진다. 그래서 조건을 다시
/// 세지 않고 좌표열을 뒤집어 그 함수에 넘긴다 — 거리·시간은 방향과 무관한
/// 스칼라라 뒤집어도 뜻이 그대로다. 우회를 잘라 내는 훑기 방향까지 함께
/// 뒤집히는 것이 정확히 맞는 동작이다([_replaceDetourTail]의 "앞에서부터"는
/// 여기서 "뒤에서부터"가 된다 — 우회는 출발 쪽에서 시작되므로).
///
/// **GPS를 따라가는 안내에는 쓰지 않는다**(`_updateRoute`). 그쪽 출발점은 매
/// 좌표마다 바뀌는 원시 GPS라, 앞에 붙이면 오차만큼 선 머리가 걸음마다 떤다.
/// 이 함수가 필요한 것은 출발점이 **못박힌** 경로뿐이다 — 나온 문, 길찾기
/// 시트에서 직접 고른 출발지.
DirectionsRoute? extendRouteFromOrigin(DirectionsRoute? route, LatLng? origin) {
  if (route == null || origin == null) return route;
  final reversed = _reversed(route);
  final filled = extendRouteToDestination(reversed, origin);
  // 손댈 것이 없으면 **원본을 그대로** 돌려준다. 뒤집기가 턴바이턴 미리보기를
  // 버리므로([_reversed]), 여기서 뒤집힌 것을 다시 뒤집어 돌려주면 아무 일도
  // 없었던 경로가 `steps`만 잃는다.
  if (identical(filled, reversed)) return route;
  return _reversed(filled!);
}

/// 좌표열만 뒤집은 같은 경로. 거리·시간·요금은 방향과 무관한 스칼라라 그대로다.
///
/// **턴바이턴은 들고 가지 않는다.** 순서를 뒤집어도 "좌회전"이 "우회전"이 되지
/// 않아, 그대로 옮기면 반대 방향 안내 문구가 붙는다. 끝을 잇는 쪽도 기하가
/// 바뀌면 같은 이유로 `steps`를 버린다([extendRouteToDestination]).
DirectionsRoute _reversed(DirectionsRoute route) => DirectionsRoute(
  points: route.points.reversed.toList(growable: false),
  distanceMeters: route.distanceMeters,
  durationSeconds: route.durationSeconds,
  tollFareWon: route.tollFareWon,
  taxiFareWon: route.taxiFareWon,
);

/// 도착점까지 직선으로 가는 편이 확실히 짧아지는 **가장 이른** 지점에서 경로를
/// 끊고, 거기서 도착점까지 직선으로 잇는다. 그런 지점이 없으면 null.
///
/// 앞에서부터 훑는 이유는 우회가 어디서 시작됐는지 모르기 때문이다. 뒤에서부터
/// 찾으면 이미 한참 돌아간 뒤의 짧은 꼬리만 잘라 내고, 화면에는 우회가 그대로
/// 남는다.
DirectionsRoute? _replaceDetourTail(
  DirectionsRoute route,
  LatLng destination,
  double gap,
) {
  final points = route.points;

  // 각 지점에서 경로 끝까지 남은 도로 거리. 뒤에서부터 누적한다.
  final remaining = List<double>.filled(points.length, 0);
  for (var i = points.length - 2; i >= 0; i--) {
    remaining[i] =
        remaining[i + 1] +
        _distance.as(LengthUnit.Meter, points[i], points[i + 1]);
  }
  final roadTotal = remaining[0];
  if (roadTotal <= 0) return null;

  for (var i = 0; i < points.length - 1; i++) {
    final straight = _distance.as(LengthUnit.Meter, points[i], destination);
    if (straight > _shortcutMaxMeters) continue;
    // 남은 도로 거리에 **끝점과 도착점 사이의 벌어진 거리도 더해서** 비교한다.
    // 그 구간도 결국 사용자가 걸어야 하는 거리인데 TMAP 총계에는 빠져 있다.
    if (straight * _shortcutRatio >= remaining[i] + gap) continue;

    final meters = (roadTotal - remaining[i]) + straight;
    return DirectionsRoute(
      points: [...points.sublist(0, i + 1), destination],
      distanceMeters: meters,
      durationSeconds: (route.durationSeconds * meters / roadTotal).round(),
      tollFareWon: route.tollFareWon,
      taxiFareWon: route.taxiFareWon,
    );
  }
  return null;
}
