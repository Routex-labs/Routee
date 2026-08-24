/// 길찾기 경로를 기준으로 현재 위치를 해석한다 — 얼마나 왔고, 얼마나 남았고,
/// 지금 경로 위에 있는지.
///
/// **경로는 위치 추정에 개입하지 않는다** — 확정된 보정 위치를 받아 경로 기준 값만
/// 만드는 단방향 소비자다. 반대로 허용하면 다른 길로 가도 위치가 경로에 붙어 있어
/// 앱이 거짓 안내를 계속한다(잘못된 이탈 판정은 알아채지만 조용히 틀린 위치는
/// 아무도 못 알아챈다). HTTP·PDR을 모르는 순수 함수다.
library;

import 'dart:math' as math;

import '../../models/building/floor_graph.dart';
import 'route_movement.dart';

/// 경로 기준으로 해석한 현재 위치.
class RouteProgress {
  const RouteProgress({
    required this.traveledM,
    required this.remainingM,
    required this.offsetM,
    required this.onRouteEdge,
    required this.reacquired,
    required this.segmentIndex,
    this.projectedPoint,
    this.headingErrorDeg,
    this.routeHeadingDeg,
  });

  /// 경로 시작점부터 투영점까지의 폴리라인 거리.
  final double traveledM;

  /// 투영점부터 경로 끝점까지의 폴리라인 거리.
  ///
  /// [traveledM] + [remainingM]은 폴리라인 전체 길이다. 간선 `lengthM` 합인
  /// `IndoorRoute.distanceMeters`와는 소수점 수준에서 다를 수 있으므로, 두
  /// 값을 섞어 쓰지 않고 진행률 표시는 이 쌍만 쓴다.
  final double remainingM;

  /// 현재 위치에서 경로 폴리라인까지의 수직 거리.
  ///
  /// **이탈 판정 근거로 쓰지 않는다.** 경로와 나란한 옆 복도에 잘못 붙으면 이
  /// 값은 1~2m로 작게 나오지만 실제로는 완전한 이탈이다. 판정은
  /// [onRouteEdge]로 하고 이 값은 진단용으로만 본다.
  final double offsetM;

  /// 확정된 현재 간선이 경로 간선 집합에 속하는지.
  ///
  /// 간선 동일성으로만 판정하므로 옆 복도 오매칭이 그대로 드러난다. 현재
  /// 간선이 아직 확정되지 않았으면(교차로 통과 중 등) false다.
  final bool onRouteEdge;

  /// 이전 진행거리 근처에서 후보를 찾지 못해 전역 재획득한 결과인지.
  ///
  /// 경로를 크게 벗어났다 돌아온 경우이거나, 위치 추정이 크게 튄 경우다. 이
  /// 값이 자주 켜지면 진행거리 시계열을 그대로 신뢰할 수 없다는 신호다.
  final bool reacquired;

  /// 투영된 폴리라인 구간 번호(0-based). 진단·회귀 테스트용.
  final int segmentIndex;

  /// 경로 폴리라인 위에 투영된 현재 위치. 남은 파란선을 이 점부터 그리고,
  /// 지나온 구간을 회색으로 나눌 때 쓴다. 예전 진단 로그를 만드는 테스트와의
  /// 호환을 위해 직접 생성 시에는 null일 수 있다.
  final LocalPoint? projectedPoint;

  /// 현재 진행 heading과 목적지 방향 경로 접선의 차이(0~180°).
  final double? headingErrorDeg;

  /// 현재 투영 segment의 목적지 방향 접선. heading 네 종류를 진단할 때 쓴다.
  final double? routeHeadingDeg;
}

/// 현재 위치를 새 경로의 첫 점에 붙여 만든 진행률 기준점.
///
/// 재탐색 직후 일반 투영을 바로 실행하면, 물리적으로 가까운 뒷 구간을 골라
/// 이미 걸은 것처럼 시작할 수 있다. 새 경로가 현재 위치를 첫 점으로 붙였다는
/// 전제에서 진행거리는 항상 0으로 시작하고 이후 걸음만 누적한다.
RouteProgress? seedRouteProgressAtRouteStart({
  required List<LocalPoint> routePointsLocalM,
  required Set<String> routeEdgeIds,
  required String? currentEdgeId,
  double? headingDeg,
}) {
  if (routePointsLocalM.length < 2) return null;
  var firstSegmentIndex = -1;
  var totalLengthM = 0.0;
  for (var index = 0; index < routePointsLocalM.length - 1; index++) {
    final start = routePointsLocalM[index];
    final end = routePointsLocalM[index + 1];
    final lengthM = math.sqrt(
      math.pow(end.x - start.x, 2) + math.pow(end.y - start.y, 2),
    );
    if (lengthM > 0 && firstSegmentIndex < 0) firstSegmentIndex = index;
    totalLengthM += lengthM;
  }
  if (firstSegmentIndex < 0) return null;
  final first = routePointsLocalM.first;
  final routeBearingDeg = _bearingForSegment(
    routePointsLocalM[firstSegmentIndex],
    routePointsLocalM[firstSegmentIndex + 1],
  );
  final headingErrorDeg = headingDeg == null
      ? null
      : _bearingError(headingDeg, routeBearingDeg);
  final onRouteEdge =
      currentEdgeId != null && routeEdgeIds.contains(currentEdgeId);
  return RouteProgress(
    traveledM: 0,
    remainingM: totalLengthM,
    offsetM: 0,
    onRouteEdge: onRouteEdge,
    reacquired: false,
    segmentIndex: firstSegmentIndex,
    projectedPoint: first,
    headingErrorDeg: headingErrorDeg,
    routeHeadingDeg: routeBearingDeg,
  );
}

/// 새 진행점이 마지막으로 받아들인 진행점에서 실제 걸음으로 설명할 수 없을
/// 만큼 멀리 튀었는지 판단한다.
///
/// PDR의 복도 매칭이 교차점이나 평행 통로에서 순간적으로 다른 구간을 고르면
/// 현재 간선이 여전히 경로 간선인 채로도 진행거리가 수십 m 바뀔 수 있다.
/// 마지막 채택 뒤 늘어난 걸음마다 [maxStepLengthM]를 허용하고, 투영·보폭
/// 오차를 위한 [baseSlackM]만 추가한다. 걸음 없는 위치 점프는 표시에서
/// 제외되지만, 걸음이 계속 늘면 실제 빠른 이동은 자연스럽게 받아들인다.
bool shouldHoldImplausibleRouteJump({
  required RouteProgress? previous,
  required RouteProgress candidate,
  required int? acceptedAtSteps,
  required int? currentSteps,
  double maxStepLengthM = 1.2,
  double baseSlackM = 3.0,
}) {
  if (previous == null || acceptedAtSteps == null || currentSteps == null) {
    return false;
  }
  final stepDelta = math.max(0, currentSteps - acceptedAtSteps);
  final plausibleDistanceM = baseSlackM + stepDelta * maxStepLengthM;
  return (candidate.traveledM - previous.traveledM).abs() > plausibleDistanceM;
}

/// 멀리 재해석된 [candidate]를 한 번에 채택하지 않고, 이번에 실제로 승인된
/// 이동거리만큼만 경로 위에서 따라간다.
///
/// 위치를 두 좌표 사이 직선으로 보간하지 않는다. 코너에서 직선 보간하면 매장
/// 안을 가로지르므로, 경로 누적거리로 새 점을 다시 만든다. 이 함수의 검증 기준은
/// `client/test/domain/guidance/route_progress_test.dart`가 단일 출처다.
RouteProgress moveRouteProgressToward({
  required RouteProgress previous,
  required RouteProgress candidate,
  required List<LocalPoint> routePointsLocalM,
  required double maxDistanceM,
}) {
  if (routePointsLocalM.length < 2 || maxDistanceM <= 0) return previous;
  final deltaM = candidate.traveledM - previous.traveledM;
  if (deltaM.abs() <= maxDistanceM) return candidate;

  final targetM = previous.traveledM + deltaM.sign * maxDistanceM;
  var cumulativeM = 0.0;
  var totalM = 0.0;
  var targetSegmentIndex = -1;
  LocalPoint? targetPoint;
  for (var index = 0; index < routePointsLocalM.length - 1; index++) {
    final start = routePointsLocalM[index];
    final end = routePointsLocalM[index + 1];
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final segmentM = math.sqrt(dx * dx + dy * dy);
    if (segmentM <= 1e-9) continue;
    final segmentEndM = cumulativeM + segmentM;
    if (targetPoint == null && targetM <= segmentEndM + 1e-9) {
      final withinM = (targetM - cumulativeM).clamp(0.0, segmentM).toDouble();
      final t = withinM / segmentM;
      targetPoint = LocalPoint(start.x + dx * t, start.y + dy * t);
      targetSegmentIndex = index;
    }
    cumulativeM = segmentEndM;
    totalM = segmentEndM;
  }
  if (targetPoint == null || targetSegmentIndex < 0) return previous;
  final boundedTraveledM = targetM.clamp(0.0, totalM).toDouble();
  return RouteProgress(
    traveledM: boundedTraveledM,
    remainingM: math.max(0.0, totalM - boundedTraveledM),
    offsetM: 0,
    onRouteEdge: candidate.onRouteEdge,
    reacquired: false,
    segmentIndex: targetSegmentIndex,
    projectedPoint: targetPoint,
  );
}

/// 실제 역방향 걸음이 확정되기 전 **표시 진행률**의 큰 후퇴를 보류한다.
///
/// 되돌아 걷는 것은 정상이라 후퇴 자체를 막으면 안 된다. 문제는 **무엇이 되돌아
/// 걸었다는 증거인가**다.
///
/// 걸음 수는 증거가 못 된다 — pedometer는 방향을 몰라 앞으로 걸은 걸음이 그대로
/// "뒤로 갈 여유"가 된다(앞으로 5걸음에 6m 뒤로 튀는 것이 허용됐다). heading도 쓰지
/// 않는다(제자리 회전이 보행으로 오인된다). accepted preview peak의 traversal로 만든
/// [TravelDirectionState.reverseConfirmed]만 후퇴를 승인한다.
bool shouldHoldDisplayRouteRegression({
  required RouteProgress? previous,
  required RouteProgress candidate,
  required TravelDirectionState travelDirectionState,
  double freeRegressionM = 2.0,
}) {
  if (previous == null) return false;
  final regressionM = previous.traveledM - candidate.traveledM;
  if (regressionM <= freeRegressionM) return false;
  return travelDirectionState != TravelDirectionState.reverseConfirmed;
}

/// [previousTraveledM] 주변에서 후보를 찾는 기본 탐색 창(±m).
///
/// 임의값이다. 실측 진행거리 분포를 보고 조정해야 하며, 현재는 한 걸음
/// (약 0.7m)과 1Hz 갱신 간 이동량에 비해 넉넉하되 ㄷ자 경로의 마주보는
/// 구간까지는 닿지 않는 값으로 잡았다.
const double defaultRouteSearchWindowM = 15.0;

/// 경로 폴리라인에 [position]을 투영해 진행률을 계산한다.
///
/// 폴리라인 점이 2개 미만이면(그릴 경로가 없음) null.
///
/// [previousTraveledM]을 주면 그 값 ±[searchWindowM] 안의 후보만 본다. 경로가
/// ㄷ자로 겹치면 시작 구간과 끝 구간이 물리적으로 가까워지는데, 전역 최소만
/// 쓰면 이때 진행거리가 경로 끝에서 시작으로 순간이동한다. 창 안에 후보가
/// 없으면 전역 최소로 재획득하고 [RouteProgress.reacquired]를 켠다.
RouteProgress? computeRouteProgress({
  required List<LocalPoint> routePointsLocalM,
  required Set<String> routeEdgeIds,
  required LocalPoint position,
  required String? currentEdgeId,
  double? headingDeg,
  double? previousTraveledM,
  double searchWindowM = defaultRouteSearchWindowM,
}) {
  if (routePointsLocalM.length < 2) return null;

  final candidates = <_Projection>[];
  var cumulativeM = 0.0;

  for (var index = 0; index < routePointsLocalM.length - 1; index++) {
    final start = routePointsLocalM[index];
    final end = routePointsLocalM[index + 1];
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final lengthSq = dx * dx + dy * dy;

    // 같은 좌표가 연달아 들어온 구간(간선 이어붙이기 경계에서 생길 수 있다)은
    // 투영할 방향이 없어 건너뛴다. 누적 거리도 늘지 않는다.
    if (lengthSq == 0) continue;

    final segmentLengthM = math.sqrt(lengthSq);
    final t =
        (((position.x - start.x) * dx + (position.y - start.y) * dy) / lengthSq)
            .clamp(0.0, 1.0);
    final footX = start.x + t * dx;
    final footY = start.y + t * dy;
    final offsetM = math.sqrt(
      math.pow(position.x - footX, 2) + math.pow(position.y - footY, 2),
    );

    candidates.add(
      _Projection(
        segmentIndex: index,
        traveledM: cumulativeM + t * segmentLengthM,
        offsetM: offsetM,
        footX: footX,
        footY: footY,
      ),
    );
    cumulativeM += segmentLengthM;
  }

  if (candidates.isEmpty) return null;
  final totalLengthM = cumulativeM;

  _Projection? chosen;
  var reacquired = false;

  if (previousTraveledM != null) {
    chosen = _nearestOffset(
      candidates.where(
        (candidate) =>
            (candidate.traveledM - previousTraveledM).abs() <= searchWindowM,
      ),
    );
    // 창 안에 아무것도 없다 = 이전 진행거리와 이어지지 않는 위치다. 진행거리를
    // 억지로 유지하는 대신 전역 최소로 다시 잡고, 그 사실을 표시한다.
    reacquired = chosen == null;
  }
  chosen ??= _nearestOffset(candidates)!;
  final routeBearingDeg = _bearingForSegment(
    routePointsLocalM[chosen.segmentIndex],
    routePointsLocalM[chosen.segmentIndex + 1],
  );
  final headingErrorDeg = headingDeg == null
      ? null
      : _bearingError(headingDeg, routeBearingDeg);

  return RouteProgress(
    traveledM: chosen.traveledM,
    remainingM: math.max(0.0, totalLengthM - chosen.traveledM),
    offsetM: chosen.offsetM,
    onRouteEdge: currentEdgeId != null && routeEdgeIds.contains(currentEdgeId),
    reacquired: reacquired,
    segmentIndex: chosen.segmentIndex,
    projectedPoint: LocalPoint(chosen.footX, chosen.footY),
    headingErrorDeg: headingErrorDeg,
    routeHeadingDeg: routeBearingDeg,
  );
}

double _bearingForSegment(LocalPoint start, LocalPoint end) {
  final east = end.x - start.x;
  final north = end.y - start.y;
  final bearing = math.atan2(east, north) * 180 / math.pi;
  return bearing < 0 ? bearing + 360 : bearing;
}

double _bearingError(double a, double b) {
  final delta = ((a - b + 540) % 360) - 180;
  return delta.abs();
}

_Projection? _nearestOffset(Iterable<_Projection> candidates) {
  _Projection? best;
  for (final candidate in candidates) {
    if (best == null || candidate.offsetM < best.offsetM) best = candidate;
  }
  return best;
}

class _Projection {
  const _Projection({
    required this.segmentIndex,
    required this.traveledM,
    required this.offsetM,
    required this.footX,
    required this.footY,
  });

  final int segmentIndex;
  final double traveledM;
  final double offsetM;
  final double footX;
  final double footY;
}
