/// 맵매칭 후보 교체를 화면 마커의 순간이동으로 노출하지 않는 연속성 상태.
///
/// 내부 graph cursor는 최적 후보로 즉시 갈아타야 다음 간선과 경로 진행률을 제대로
/// 계산할 수 있다. 하지만 그 후보의 절대 좌표를 화면에도 바로 쓰면 평행 간선이나
/// 촘촘한 직각 간선에서 한 걸음 사이에 몇 m를 앞뒤로 뛴다. 이 상태는 그때만 raw
/// PDR 이동 벡터를 이어서 표시하고, graph cursor가 다시 따라오면 천천히 합친다.
library;

import 'dart:math' as math;

import 'package:indoor_pdr_core/indoor_pdr_core.dart';

/// 한 걸음의 맵매칭 변화가 raw PDR 이동보다 이만큼 더 크면 후보 재배치로 본다.
const locationMarkerRelocationSlackM = 0.5;

/// 후보가 안정된 뒤 한 걸음에 graph cursor 쪽으로 합치는 최대 거리.
const locationMarkerReconcilePerStepM = 0.2;

/// 이 거리 안에서 두 번 연속 안정되면 graph cursor에 다시 붙는다.
const locationMarkerContinuitySettleM = 0.08;

/// 연속성 shadow가 보행 가능 간선 중심에서 벗어날 수 있는 최대 거리.
///
/// 후보 하나의 좌표로 되돌리면 평행 간선 교체 때 점프가 다시 생긴다. 호출자가
/// 안내 경로와 살아 있는 후보 간선 중 가장 가까운 투영점을 주고, 여기서는 그
/// 주변의 좁은 통로 안에서만 raw PDR 연속성을 허용한다. 0은 투영 가능한
/// 선이 있으면 마커 중심을 그 선 위에 정확히 붙인다는 뜻이다.
const locationMarkerNavigableLeashM = 0.0;

typedef LocationMarkerProjection =
    PdrLocalPoint? Function(PdrLocalPoint position);

class LocationMarkerContinuity {
  PdrLocalPoint? _position;
  PdrLocalPoint? _lastRawPosition;
  PdrLocalPoint? _lastMatchedPosition;
  bool _active = false;
  int _settledMovementCount = 0;

  PdrLocalPoint? get position => _position;
  bool get isActive => _active;

  void reset({
    required PdrLocalPoint matchedPosition,
    required PdrLocalPoint rawPosition,
  }) {
    _position = matchedPosition;
    _lastRawPosition = rawPosition;
    _lastMatchedPosition = matchedPosition;
    _active = false;
    _settledMovementCount = 0;
  }

  PdrLocalPoint update({
    required PdrLocalPoint matchedPosition,
    required PdrLocalPoint rawPosition,
    required double headingBiasDeg,
    required bool leaderRelocated,
    required bool ambiguous,
    bool forceMatchedPosition = false,
    LocationMarkerProjection? projectToNavigableGraph,
  }) {
    final shown = _position;
    final previousRaw = _lastRawPosition;
    final previousMatched = _lastMatchedPosition;
    if (shown == null || previousRaw == null || previousMatched == null) {
      reset(matchedPosition: matchedPosition, rawPosition: rawPosition);
      return matchedPosition;
    }
    if (forceMatchedPosition) {
      reset(matchedPosition: matchedPosition, rawPosition: rawPosition);
      return matchedPosition;
    }

    final rawDelta = _rotate(rawPosition - previousRaw, headingBiasDeg);
    final rawDistanceM = rawDelta.distance;
    final matchedDelta = matchedPosition - previousMatched;
    final matchedDistanceM = matchedDelta.distance;
    final unexplainedRelocation =
        matchedDistanceM > rawDistanceM + locationMarkerRelocationSlackM ||
        ambiguous &&
            (matchedDelta - rawDelta).distance > locationMarkerRelocationSlackM;
    if (leaderRelocated || unexplainedRelocation) {
      _active = true;
      _settledMovementCount = 0;
    }

    if (!_active) {
      _position = matchedPosition;
      _rememberInputs(rawPosition, matchedPosition);
      return matchedPosition;
    }

    // heartbeat나 확정 배치가 graph lineage만 재해석한 프레임에서는 화면을
    // 움직이지 않는다. 실제 accepted peak가 있어 raw 좌표가 움직였을 때만 간다.
    if (rawDistanceM <= 1e-6) {
      _rememberInputs(rawPosition, matchedPosition);
      return shown;
    }

    var next = shown + rawDelta;
    final stable = !leaderRelocated && !unexplainedRelocation && !ambiguous;
    if (stable) {
      var correction = matchedPosition - next;
      // graph cursor가 뒤에 있다는 이유로, 실제로 앞으로 걷는 마커를 뒤로
      // 당기지 않는다. 진행 방향 성분은 0 이상만 허용하고 횡방향 오차만 합친다.
      final direction = _scale(rawDelta, 1 / rawDistanceM);
      final along = _dot(correction, direction);
      if (along < 0) correction = correction - _scale(direction, along);
      final correctionDistanceM = correction.distance;
      if (correctionDistanceM > locationMarkerReconcilePerStepM) {
        correction = _scale(
          correction,
          locationMarkerReconcilePerStepM / correctionDistanceM,
        );
      }
      next = next + correction;

      if ((matchedPosition - next).distance <=
          locationMarkerContinuitySettleM) {
        _settledMovementCount += 1;
        if (_settledMovementCount >= 2) {
          next = matchedPosition;
          _active = false;
          _settledMovementCount = 0;
        }
      } else {
        _settledMovementCount = 0;
      }
    } else {
      _settledMovementCount = 0;
    }

    final navigable = projectToNavigableGraph?.call(next);
    if (navigable != null) {
      final offset = next - navigable;
      final offsetM = offset.distance;
      if (offsetM > locationMarkerNavigableLeashM) {
        // shadow의 연속성은 간선을 따라가는 방향에서만 지킨다. 이 횡방향
        // 보정까지 제한하면 화면 마커가 복도·경로 밖을 몇 걸음씩 떠다닌다.
        next =
            next -
            _scale(offset, (offsetM - locationMarkerNavigableLeashM) / offsetM);
      }
    }

    _position = next;
    _rememberInputs(rawPosition, matchedPosition);
    return next;
  }

  void _rememberInputs(
    PdrLocalPoint rawPosition,
    PdrLocalPoint matchedPosition,
  ) {
    _lastRawPosition = rawPosition;
    _lastMatchedPosition = matchedPosition;
  }
}

PdrLocalPoint _rotate(PdrLocalPoint point, double degrees) {
  if (point.distance <= 1e-9 || degrees.abs() <= 1e-9) return point;
  final radians = degrees * math.pi / 180;
  final cosine = math.cos(radians);
  final sine = math.sin(radians);
  return PdrLocalPoint(
    point.eastM * cosine + point.northM * sine,
    -point.eastM * sine + point.northM * cosine,
  );
}

PdrLocalPoint _scale(PdrLocalPoint point, double scale) =>
    PdrLocalPoint(point.eastM * scale, point.northM * scale);

double _dot(PdrLocalPoint left, PdrLocalPoint right) =>
    left.eastM * right.eastM + left.northM * right.northM;
