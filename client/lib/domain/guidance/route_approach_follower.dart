/// 탑승점 직전의 마지막 복도 polyline을 걸음 거리로 따르는 표시 위치.
///
/// 에스컬레이터 앞에는 ㄱ자·ㄷ자 연결 간선이 많다. 이 구간에서 나침반 heading을
/// 다음 간선 선택에 다시 쓰면 몸이 아직 회전하지 않은 한두 걸음 때문에 marker가
/// 5m 앞에서 멈춘다. 이 follower는 **경로가 이미 지목한** 마지막 탑승점에 한해
/// PDR의 걸음 거리만 route progress에 더한다. 시간으로 재생하지 않으므로 멈추면
/// marker도 멈추고, 코너는 route geometry 그대로 돈다.
library;

import 'dart:math' as math;

import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import '../../models/building/floor_graph.dart' show LocalPoint;

class RouteApproachFollower {
  RouteApproachFollower._({required this.points, required this._progressM})
    : _cumulativeM = _cumulativeDistances(points);

  /// 경로 local 좌표. 첫 점부터 탑승 노드(마지막 점)까지 순서다.
  final List<LocalPoint> points;
  final List<double> _cumulativeM;
  double _progressM;

  double get progressM => _progressM;
  double get totalM => _cumulativeM.last;
  bool get isAtTerminal => totalM - _progressM <= 0.02;

  PdrLocalPoint get position => _pointAt(_progressM);

  /// raw PDR가 경로 밖으로 실제로 빠졌는지 판단할 때 쓰는 polyline 거리.
  ///
  /// 방향이 늦게 도는 것은 이탈이 아니다. 위치가 경로에서 충분히 멀어졌을 때만
  /// follower를 푼다.
  double distanceToPolyline(PdrLocalPoint point) {
    var nearestM = double.infinity;
    for (var index = 0; index < points.length - 1; index++) {
      final from = points[index];
      final to = points[index + 1];
      final east = to.x - from.x;
      final north = to.y - from.y;
      final lengthSquared = east * east + north * north;
      if (lengthSquared <= 1e-9) continue;
      final t =
          (((point.eastM - from.x) * east + (point.northM - from.y) * north) /
                  lengthSquared)
              .clamp(0.0, 1.0)
              .toDouble();
      final projected = PdrLocalPoint(from.x + east * t, from.y + north * t);
      nearestM = math.min(nearestM, (point - projected).distance);
    }
    return nearestM;
  }

  /// 실제로 인식된 새 걸음의 길이만큼 앞으로 간다.
  ///
  /// heading과 wall-clock time은 일부러 받지 않는다. 마지막 코너에서 센서의
  /// 방향이 늦어도 경로를 계속 따르게 하는 것이 이 클래스의 역할이다.
  void advance(double distanceM) {
    if (!distanceM.isFinite || distanceM <= 0) return;
    _progressM = math.min(totalM, _progressM + distanceM);
  }

  /// [seed]가 polyline에 충분히 가까울 때만 follower를 연다.
  ///
  /// 시작부터 옆 복도 marker를 경로로 끌어당기지 않기 위한 안전장치다. 이후
  /// 이탈 여부는 caller가 graph/route evidence로 판단해 follower 자체를 푼다.
  static RouteApproachFollower? start({
    required List<LocalPoint> points,
    required PdrLocalPoint seed,
    double maxSeedOffsetM = 3,
  }) {
    if (points.length < 2) return null;
    final cumulative = _cumulativeDistances(points);
    _RouteProjection? best;
    for (var index = 0; index < points.length - 1; index++) {
      final from = points[index];
      final to = points[index + 1];
      final east = to.x - from.x;
      final north = to.y - from.y;
      final lengthSquared = east * east + north * north;
      if (lengthSquared <= 1e-9) continue;
      final t =
          (((seed.eastM - from.x) * east + (seed.northM - from.y) * north) /
                  lengthSquared)
              .clamp(0.0, 1.0)
              .toDouble();
      final projected = PdrLocalPoint(from.x + east * t, from.y + north * t);
      final candidate = _RouteProjection(
        progressM: cumulative[index] + math.sqrt(lengthSquared) * t,
        offsetM: (seed - projected).distance,
      );
      if (best == null ||
          candidate.offsetM < best.offsetM - 1e-6 ||
          (candidate.offsetM - best.offsetM).abs() <= 1e-6 &&
              candidate.progressM > best.progressM) {
        best = candidate;
      }
    }
    if (best == null || best.offsetM > maxSeedOffsetM) return null;
    return RouteApproachFollower._(
      points: List.unmodifiable(points),
      progressM: best.progressM,
    );
  }

  PdrLocalPoint _pointAt(double targetM) {
    if (totalM <= 0) {
      final point = points.last;
      return PdrLocalPoint(point.x, point.y);
    }
    final clamped = targetM.clamp(0.0, totalM).toDouble();
    var index = 1;
    while (index < points.length - 1 && _cumulativeM[index] < clamped) {
      index++;
    }
    final from = points[index - 1];
    final to = points[index];
    final startM = _cumulativeM[index - 1];
    final lengthM = _cumulativeM[index] - startM;
    final t = lengthM <= 1e-9 ? 1.0 : (clamped - startM) / lengthM;
    return PdrLocalPoint(
      from.x + (to.x - from.x) * t,
      from.y + (to.y - from.y) * t,
    );
  }

  static List<double> _cumulativeDistances(List<LocalPoint> points) {
    final result = List<double>.filled(points.length, 0);
    for (var index = 1; index < points.length; index++) {
      final east = points[index].x - points[index - 1].x;
      final north = points[index].y - points[index - 1].y;
      result[index] =
          result[index - 1] + math.sqrt(east * east + north * north);
    }
    return result;
  }
}

class _RouteProjection {
  const _RouteProjection({required this.progressM, required this.offsetM});

  final double progressM;
  final double offsetM;
}
