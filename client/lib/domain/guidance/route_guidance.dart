import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../models/building/floor_graph.dart';
import 'route_movement.dart';
import 'route_progress.dart';

enum RouteGuidanceAction {
  wrongWay,
  straight,
  turnLeft,
  turnRight,
  escalator,
  elevator,
  arrived,
}

class RouteGuidanceInstruction {
  const RouteGuidanceInstruction({
    required this.action,
    required this.primaryText,
    required this.distanceToActionM,
  });

  final RouteGuidanceAction action;
  final String primaryText;
  final double distanceToActionM;
}

/// 도착 안내가 뜬 뒤 경로를 스스로 지울지에 대한 결정.
enum ArrivalAutoClearDecision {
  /// 지금부터 [arrivalAutoClearDelay]를 세고 그 뒤에 경로를 지운다.
  schedule,

  /// 이미 세고 있다. 다시 걸지 않는다 — 매 걸음마다 다시 걸면 사용자가
  /// 도착 지점에서 제자리걸음만 해도 카운트다운이 영원히 처음으로 돌아간다.
  keep,

  /// 도착 상태가 아니다. 세고 있던 것이 있으면 취소한다.
  cancel,
}

/// 도착 안내를 읽을 시간을 준 뒤 경로를 지우기까지의 대기 시간.
///
/// 0으로 두면 "목적지에 도착했습니다"가 뜨는 프레임과 카드가 사라지는 프레임이
/// 같아져, 사용자는 안내를 못 본 채 경로만 사라진 것으로 읽는다. 반대로 너무
/// 길면 도착 뒤에도 남은 카드가 지도를 가린다. 한 줄 안내를 읽기에 충분한
/// 정도로 잡은 임의값이다.
const Duration arrivalAutoClearDelay = Duration(seconds: 5);

/// 도착을 화면이 말해야 하는가.
///
/// **[decideArrivalAutoClear]와 조건이 다르다.** 자동 종료는 걸어서 도착했을 때만
/// 하지만(바로 옆 매장은 고르자마자 경로가 사라지면 안 된다), 도착했다는 말은 그
/// 경로에서도 해야 한다. 한때 둘을 한 조건에 묶어 뒀고, 그때 진행률이 측정되지 않는
/// 짧은 경로에서는 **도착을 말하는 것이 화면에 하나도 없었다.**
///
/// [hasDestination]은 무엇에 도착했는지를 아는가다. 이름 없는 도착 카드를 그리느니
/// 아무것도 그리지 않는다.
bool shouldAnnounceArrival({
  required RouteGuidanceAction? action,
  required bool hasDestination,
}) => action == RouteGuidanceAction.arrived && hasDestination;

/// 지금 안내 상태에서 "안내를 자동으로 끝낼지"를 판단한다.
///
/// [hasMeasuredProgress]는 **실제로 측정된 진행률이 있는지**다. 이 값이 없으면
/// [buildRouteGuidance]는 남은거리를 폴리라인 전체 길이로 대신 계산하므로, 총
/// 길이가 도착 임계값보다 짧은 경로(바로 옆 매장)는 그리는 순간 `arrived`가
/// 된다. 그대로 자동 삭제를 걸면 사용자는 도착지를 고르자마자 경로가 사라지는
/// 것을 본다. 걸어서 도착한 것과 애초에 가까운 것은 다르므로, 자동 종료는
/// 측정된 진행률이 있을 때만 한다.
ArrivalAutoClearDecision decideArrivalAutoClear({
  required RouteGuidanceAction? action,
  required bool hasMeasuredProgress,
  required bool alreadyScheduled,
}) {
  if (action != RouteGuidanceAction.arrived || !hasMeasuredProgress) {
    return ArrivalAutoClearDecision.cancel;
  }
  return alreadyScheduled
      ? ArrivalAutoClearDecision.keep
      : ArrivalAutoClearDecision.schedule;
}

class RoutePolylineSplit {
  const RoutePolylineSplit({required this.completed, required this.remaining});

  final List<LocalPoint> completed;
  final List<LocalPoint> remaining;
}

/// 현재 투영점에서 경로를 지나온 구간과 남은 구간으로 나눈다.
RoutePolylineSplit? splitRouteAtProgress(
  List<LocalPoint> points,
  RouteProgress? progress,
) {
  final projected = progress?.projectedPoint;
  if (points.length < 2 || progress == null || projected == null) return null;
  final segment = progress.segmentIndex.clamp(0, points.length - 2);
  return RoutePolylineSplit(
    completed: [...points.take(segment + 1), projected],
    remaining: [projected, ...points.skip(segment + 1)],
  );
}

/// 현재 위치 뒤에서 첫 의미 있는 회전이나 층 이동을 찾아 한 줄 안내를 만든다.
///
/// **남은 거리가 [arrivalThresholdM] 안이면 도착이 회전을 이긴다.** 실내 경로는
/// 대개 `복도 노드 → 매장 진입 노드`로 끝나 마지막 모퉁이가 곧 목적지 문 앞이고,
/// 사람은 매장 안이 아니라 그 문 앞에서 멈춘다. 거기서 회전을 내면 진행률이 앞
/// 세그먼트에 묶인 채([computeRouteProgress]는 offset이 동률이면 앞을 고른다)
/// 도착 판정이 영영 안 선다 — 도착 카드·경로 자동 종료·도착지 강조가 통째로
/// 죽는다.
///
/// **층 이동 탑승구([transferMode])만 예외다.** 탑승구 바로 앞에서 꺾는 도면이
/// 실제로 있어(지하 2층 구호플러스 옆 엘리베이터 · 실기기 확인) 그쪽까지 회전을
/// 접으면, 아직 모퉁이를 못 돈 사용자가 "탑승하세요"만 보고 서 있게 된다. 탑승은
/// 도착과 달리 여기서 한 번 늦는다고 죽는 것이 없다 — 층 전이 감지는 이 안내가
/// 아니라 세그먼트의 `transferModeToNext`를 직접 본다.
RouteGuidanceInstruction buildRouteGuidance({
  required List<LocalPoint> localPoints,
  required List<LatLng> wgs84Points,
  required RouteProgress? progress,
  TravelDirectionState travelDirectionState = TravelDirectionState.forward,
  String? transferMode,
  bool allowArrival = true,
  double arrivalThresholdM = 5,
}) {
  if (travelDirectionState == TravelDirectionState.reverseConfirmed) {
    return const RouteGuidanceInstruction(
      action: RouteGuidanceAction.wrongWay,
      primaryText: '반대 방향입니다 · 뒤로 돌아가세요',
      distanceToActionM: 0,
    );
  }
  final remainingM = progress?.remainingM ?? _polylineLength(localPoints);
  final nearEnd = remainingM <= arrivalThresholdM;

  // 끝에 닿았으면 회전을 접는다 — 마지막 모퉁이가 곧 목적지 문 앞이라서다.
  // 탑승구만 예외로 계속 찾는다. 두 규칙의 근거는 이 함수의 doc 주석에 있다.
  if (!nearEnd || transferMode != null) {
    final turn = _nextTurn(
      localPoints: localPoints,
      wgs84Points: wgs84Points,
      progress: progress,
    );
    if (turn != null) return turn;
  }

  if (nearEnd) {
    if (transferMode == 'escalator') {
      return const RouteGuidanceInstruction(
        action: RouteGuidanceAction.escalator,
        primaryText: '에스컬레이터를 탑승하세요',
        distanceToActionM: 0,
      );
    }
    if (transferMode == 'elevator') {
      return const RouteGuidanceInstruction(
        action: RouteGuidanceAction.elevator,
        primaryText: '엘리베이터를 탑승하세요',
        distanceToActionM: 0,
      );
    }
    if (allowArrival) {
      return const RouteGuidanceInstruction(
        action: RouteGuidanceAction.arrived,
        primaryText: '목적지에 도착했습니다',
        distanceToActionM: 0,
      );
    }
    return const RouteGuidanceInstruction(
      action: RouteGuidanceAction.straight,
      primaryText: '다음 층 이동 지점입니다',
      distanceToActionM: 0,
    );
  }

  if (transferMode == 'escalator') {
    return RouteGuidanceInstruction(
      action: RouteGuidanceAction.escalator,
      primaryText: _actionDistanceText(remainingM, '에스컬레이터 탑승'),
      distanceToActionM: remainingM,
    );
  }
  if (transferMode == 'elevator') {
    return RouteGuidanceInstruction(
      action: RouteGuidanceAction.elevator,
      primaryText: _actionDistanceText(remainingM, '엘리베이터 탑승'),
      distanceToActionM: remainingM,
    );
  }
  final rounded = _roundedGuidanceMeters(remainingM);
  return RouteGuidanceInstruction(
    action: RouteGuidanceAction.straight,
    primaryText: '$rounded미터 직진',
    distanceToActionM: remainingM,
  );
}

/// 진행점 뒤에서 첫 의미 있는 회전을 찾는다. 없으면 null.
///
/// **목적지 직전 꼭짓점까지 본다**(`vertex < length - 1`). 그래서 이 함수를 언제
/// 부를지는 부르는 쪽이 가른다 — 규칙은 [buildRouteGuidance]에 있다.
///
/// 앞뒤 변이 1.5m 미만인 꼭짓점은 건너뛴다. 간선을 이어 붙이면서 생긴 잔가지라
/// 사람이 "꺾었다"고 느끼지 않는다. 각도도 35°~150°만 회전으로 본다 — 그보다
/// 작으면 완만한 곡선이고, 크면 되돌아가는 U턴이라 "우회전"이 거짓말이 된다.
RouteGuidanceInstruction? _nextTurn({
  required List<LocalPoint> localPoints,
  required List<LatLng> wgs84Points,
  required RouteProgress? progress,
}) {
  if (progress == null ||
      localPoints.length != wgs84Points.length ||
      localPoints.length < 3) {
    return null;
  }
  var distanceM = _distance(
    progress.projectedPoint ?? localPoints[progress.segmentIndex],
    localPoints[(progress.segmentIndex + 1).clamp(0, localPoints.length - 1)],
  );
  for (
    var vertex = progress.segmentIndex + 1;
    vertex < localPoints.length - 1;
    vertex++
  ) {
    final beforeM = _distance(localPoints[vertex - 1], localPoints[vertex]);
    final afterM = _distance(localPoints[vertex], localPoints[vertex + 1]);
    if (beforeM >= 1.5 && afterM >= 1.5) {
      final incoming = _bearing(wgs84Points[vertex - 1], wgs84Points[vertex]);
      final outgoing = _bearing(wgs84Points[vertex], wgs84Points[vertex + 1]);
      final turn = _signedTurn(outgoing - incoming);
      if (turn.abs() >= 35 && turn.abs() <= 150) {
        final right = turn > 0;
        final actionText = right ? '우회전' : '좌회전';
        return RouteGuidanceInstruction(
          action: right
              ? RouteGuidanceAction.turnRight
              : RouteGuidanceAction.turnLeft,
          primaryText: _actionDistanceText(distanceM, actionText),
          distanceToActionM: distanceM,
        );
      }
    }
    distanceM += afterM;
  }
  return null;
}

String _actionDistanceText(double distanceM, String action) {
  if (distanceM <= 7) return '잠시 후 $action';
  return '${_roundedGuidanceMeters(distanceM)}미터 후 $action';
}

int _roundedGuidanceMeters(double distanceM) {
  final unit = distanceM < 50 ? 5 : 10;
  return math.max(unit, (distanceM / unit).round() * unit);
}

double _polylineLength(List<LocalPoint> points) {
  var total = 0.0;
  for (var index = 1; index < points.length; index++) {
    total += _distance(points[index - 1], points[index]);
  }
  return total;
}

double _distance(LocalPoint a, LocalPoint b) {
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  return math.sqrt(dx * dx + dy * dy);
}

double _bearing(LatLng from, LatLng to) {
  final meanLat = (from.latitude + to.latitude) * math.pi / 360;
  final east = (to.longitude - from.longitude) * math.cos(meanLat) * 111320.0;
  final north = (to.latitude - from.latitude) * 111320.0;
  return math.atan2(east, north) * 180 / math.pi;
}

double _signedTurn(double degrees) {
  var value = degrees % 360;
  if (value > 180) value -= 360;
  if (value < -180) value += 360;
  return value;
}

// ---------------------------------------------------------------------------
// 경로 전체 단계 목록
// ---------------------------------------------------------------------------

/// 단계 목록의 한 줄. 지도앱의 "직진 40m → 우회전 → …" 목록에서 한 행이다.
///
/// [action]은 실시간 안내([RouteGuidanceInstruction])와 같은 enum을 쓴다 —
/// 목록의 아이콘·용어가 걷는 중 배너와 어긋나면 같은 지시를 두 이름으로
/// 부르게 된다.
class RouteStep {
  const RouteStep({
    required this.action,
    this.distanceM = 0,
    this.fromFloor,
    this.toFloor,
  });

  final RouteGuidanceAction action;

  /// [RouteGuidanceAction.straight]에서만 의미 있다 — 이 직진 구간의 길이(m).
  final double distanceM;

  /// 층 이동([RouteGuidanceAction.escalator]/[elevator])의 출발·도착 층 라벨.
  final String? fromFloor;
  final String? toFloor;
}

/// [buildRouteStepList]의 입력 한 조각 — 한 층 안에서 이어지는 폴리라인과
/// 다음 층으로 넘어가는 수단.
///
/// [IndoorRouteSegment]를 그대로 받지 않는 이유: 그 모델은 다층 경로 전용이라
/// 단일 층 경로는 이 함수를 못 쓰게 된다. 필요한 필드만 뽑은 record면 단일 층
/// 호출부는 transferModeToNext에 null을 주면 된다.
typedef RouteStepLeg = ({
  List<LatLng> wgs84Points,
  List<LocalPoint> localPoints,
  String floorLabel,
  String? transferModeToNext,
  String? nextFloorLabel,
});

/// 경로 전체를 "직진 N미터 → 우회전 → … → 에스컬레이터 → … → 도착" 단계
/// 목록으로 편다.
///
/// 회전 판정은 실시간 안내([buildRouteGuidance])와 **같은 임계값**을 쓴다 —
/// 변 1.5 m 이상, 회전각 35~150도. 목록에는 회전으로 적혔는데 걷다 보니
/// 배너에는 안 나오는(또는 반대) 어긋남을 만들지 않기 위해서다.
///
/// 거리는 층 로컬 좌표(m)로 재고, 로컬 좌표가 없으면([IndoorRoute.fromJson]
/// 직후) wgs84 근사로 잰다. 둘의 오차는 목록에 적는 반올림 단위(5 m) 아래다.
List<RouteStep> buildRouteStepList(List<RouteStepLeg> legs) {
  final steps = <RouteStep>[];
  for (final leg in legs) {
    final wgs84 = leg.wgs84Points;
    if (wgs84.length >= 2) {
      final useLocal = leg.localPoints.length == wgs84.length;
      double edgeM(int from, int to) => useLocal
          ? _distance(leg.localPoints[from], leg.localPoints[to])
          : _wgs84DistanceMeters(wgs84[from], wgs84[to]);

      var straightM = 0.0;
      for (var vertex = 0; vertex < wgs84.length - 1; vertex++) {
        straightM += edgeM(vertex, vertex + 1);
        final isLast = vertex + 2 >= wgs84.length;
        if (isLast) break;
        final beforeM = edgeM(vertex, vertex + 1);
        final afterM = edgeM(vertex + 1, vertex + 2);
        if (beforeM < 1.5 || afterM < 1.5) continue;
        final incoming = _bearing(wgs84[vertex], wgs84[vertex + 1]);
        final outgoing = _bearing(wgs84[vertex + 1], wgs84[vertex + 2]);
        final turn = _signedTurn(outgoing - incoming);
        if (turn.abs() < 35 || turn.abs() > 150) continue;
        steps.add(
          RouteStep(action: RouteGuidanceAction.straight, distanceM: straightM),
        );
        steps.add(
          RouteStep(
            action: turn > 0
                ? RouteGuidanceAction.turnRight
                : RouteGuidanceAction.turnLeft,
          ),
        );
        straightM = 0.0;
      }
      // 1 m 미만 꼬리는 버린다 — "0미터 직진" 행은 정보가 아니라 소음이다.
      if (straightM >= 1.0) {
        steps.add(
          RouteStep(action: RouteGuidanceAction.straight, distanceM: straightM),
        );
      }
    }
    final transfer = leg.transferModeToNext;
    if (transfer == 'escalator' || transfer == 'elevator') {
      steps.add(
        RouteStep(
          action: transfer == 'escalator'
              ? RouteGuidanceAction.escalator
              : RouteGuidanceAction.elevator,
          fromFloor: leg.floorLabel,
          toFloor: leg.nextFloorLabel,
        ),
      );
    }
  }
  if (steps.isNotEmpty) {
    steps.add(const RouteStep(action: RouteGuidanceAction.arrived));
  }
  return steps;
}

/// 단계 한 줄의 표시 문구. 걷는 중 배너와 같은 반올림 규칙을 쓴다.
String routeStepText(RouteStep step) => switch (step.action) {
  RouteGuidanceAction.straight =>
    '${_roundedGuidanceMeters(step.distanceM)}미터 직진',
  RouteGuidanceAction.turnLeft => '좌회전',
  RouteGuidanceAction.turnRight => '우회전',
  RouteGuidanceAction.escalator => _transferText('에스컬레이터', step),
  RouteGuidanceAction.elevator => _transferText('엘리베이터', step),
  RouteGuidanceAction.arrived => '도착',
  RouteGuidanceAction.wrongWay => '',
};

/// 단계 한 줄을 **방향·거리·부연 셋으로 나눈다.**
///
/// [routeStepText]는 셋을 한 문장으로 이어 붙인 값이고, 이쪽은 거리를 목록 오른쪽
/// 열에 따로 세우는 화면이 쓴다. 두 함수가 같은 헬퍼([_roundedGuidanceMeters],
/// [_transferFloors])를 부르므로 **반올림·층 표기 규칙은 한 곳에만 있다** — 갈라
/// 두면 배너의 `10미터`와 목록의 `9m`가 같은 구간을 다르게 말한다.
({String instruction, String? distance, String? detail}) routeStepParts(
  RouteStep step,
) => switch (step.action) {
  RouteGuidanceAction.straight => (
    instruction: '직진',
    distance: '${_roundedGuidanceMeters(step.distanceM)}m',
    detail: null,
  ),
  RouteGuidanceAction.turnLeft => (
    instruction: '좌회전',
    distance: null,
    detail: null,
  ),
  RouteGuidanceAction.turnRight => (
    instruction: '우회전',
    distance: null,
    detail: null,
  ),
  RouteGuidanceAction.escalator => (
    instruction: '에스컬레이터 탑승',
    distance: null,
    detail: _transferFloors(step),
  ),
  RouteGuidanceAction.elevator => (
    instruction: '엘리베이터 탑승',
    distance: null,
    detail: _transferFloors(step),
  ),
  RouteGuidanceAction.arrived => (
    instruction: '도착',
    distance: null,
    detail: null,
  ),
  RouteGuidanceAction.wrongWay => (
    instruction: '',
    distance: null,
    detail: null,
  ),
};

/// `1F → B1`. 층을 모르면 null이라 부연 줄 자체가 생기지 않는다.
String? _transferFloors(RouteStep step) {
  final from = step.fromFloor;
  final to = step.toFloor;
  if (from == null || to == null) return null;
  return '$from → $to';
}

String _transferText(String mode, RouteStep step) {
  final from = step.fromFloor;
  final to = step.toFloor;
  if (from == null || to == null) return '$mode 탑승';
  return '$mode 탑승 · $from → $to';
}

/// wgs84 두 점 사이 거리(m) — 로컬 좌표가 없는 경로의 폴백. [_bearing]과 같은
/// 평면 근사라, 두 계산이 같은 왜곡을 공유한다.
double _wgs84DistanceMeters(LatLng a, LatLng b) {
  final meanLat = (a.latitude + b.latitude) * math.pi / 360;
  final east = (b.longitude - a.longitude) * math.cos(meanLat) * 111320.0;
  final north = (b.latitude - a.latitude) * 111320.0;
  return math.sqrt(east * east + north * north);
}
