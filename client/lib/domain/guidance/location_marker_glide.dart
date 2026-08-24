/// 현재 위치 마커를 **프레임마다 흘려 보내는** 보간기.
///
/// 걸음(PDR)은 0.4~0.6초에 한 번, 한 걸음(약 0.7m)씩 뛰어서 도착한다. 그 값을
/// 그대로 그리면 마커가 툭툭 끊긴다. 목표는 그대로 두고 **그리는 자리만**
/// 뒤따르게 해서, 사람이 걷는 속도로 이어 붙인다.
///
/// 상수를 어떻게 골랐는지와 버린 대안은 `docs/client/location-marker-glide.md`.
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// 표시 위치가 목표를 따라잡는 시정수. 한 틱에 남은 거리의
/// `1 - exp(-dt/τ)`만큼 다가간다.
///
/// 정속으로 걸을 때 표시 위치는 목표보다 `속도 × τ`만큼 뒤에 선다 — 1.4m/s면
/// 0.36m로, 걸음 하나의 절반이다. 더 키우면 멈춰 선 뒤에도 마커가 한참 미끄러져
/// "내가 멈춘 걸 앱이 모른다"로 읽히고, 더 줄이면 걸음의 각짐이 그대로 보인다.
const locationMarkerGlideTimeConstant = Duration(milliseconds: 260);

/// 방향(삼각형)이 목표를 따라잡는 시정수와 최대 각속도(도/초).
///
/// **팔로우 카메라와 같은 값이라야 한다**(`outdoor_map_tuning.dart`의
/// `followCameraBearing*`). 팔로우 중 화면 위 삼각형이 가리키는 쪽은 두 각의
/// 차라서, 한쪽만 빨리 돌면 코너마다 삼각형이 앞질렀다 되돌아온다.
///
/// 속도를 자르는 이유는 카메라와 같다 — 방향 신호가 초당 두어 번, 한 번에
/// 수십 도씩 뛰어서 온다. 근거는 `docs/client/location-marker-glide.md`.
const locationMarkerGlideHeadingTimeConstant = Duration(milliseconds: 120);
const locationMarkerGlideHeadingMaxRateDegPerSec = 90.0;

/// 이 거리를 넘게 뛰면 보간하지 않고 그 자리로 옮긴다(m).
///
/// 앵커 재배치·층 전환·GPS 폴백처럼 **걸어서 간 것이 아닌** 이동이다. 이어
/// 그리면 마커가 도면을 가로질러 미끄러져, 사용자는 자기가 걷지 않은 경로를
/// 본다. 걸음 한 번(0.7m)이나 맵매칭 보정(1~3m)은 이 아래라 그대로 흐른다.
const locationMarkerGlideSnapM = 4.0;

/// 남은 거리가 이보다 작으면 목표에 붙었다고 보고 정확히 목표를 그린다(m).
/// 지수 평활은 영원히 도착하지 않으므로 끝을 정해 줘야 타이머가 멈춘다.
const _settleM = 0.05;

/// 남은 각이 이보다 작으면 목표 각으로 붙인다(도).
const _settleDeg = 0.5;

/// 두 점 사이 거리(m, 등장방형 근사).
///
/// latlong2의 `Distance()`를 안 쓴다 — 기본값이 **정수 미터로 반올림**이라
/// 0.2m가 0m이 되어 마커가 목표에 다 온 것으로 판정된다(보간이 통째로 사라진다).
/// 여기서 재는 값은 걸음 하나(0.7m)와 스냅 경계(4m) 사이의 소수점이라
/// 지구 곡률보다 반올림이 훨씬 큰 오차다.
double _metersBetween(LatLng a, LatLng b) {
  const metersPerDegreeLat = 111320.0;
  final metersPerDegreeLng =
      metersPerDegreeLat * math.cos(a.latitude * math.pi / 180);
  final dLat = (a.latitude - b.latitude) * metersPerDegreeLat;
  final dLng = (a.longitude - b.longitude) * metersPerDegreeLng;
  return math.sqrt(dLat * dLat + dLng * dLng);
}

/// 이번 틱에 남은 거리(또는 각)의 몇 할을 좁힐지 — 지수 평활의 계수다.
///
/// 틱이 길수록 1에 가까워져, 오래 쉰 뒤에는 한 번에 목표까지 붙는다. 위치·방향·
/// 팔로우 카메라가 **같은 산수**를 쓰게 하려고 밖에 뒀다(카메라 쪽은
/// `map/camera/follow_camera.dart`).
double glideFollowFactor(Duration elapsed, Duration timeConstant) {
  final tauMs = timeConstant.inMicroseconds / 1000;
  if (tauMs <= 0) return 1;
  final dtMs = elapsed.inMicroseconds / 1000;
  return (1 - math.exp(-dtMs / tauMs)).clamp(0.0, 1.0);
}

/// 마커의 목표 위치([aimAt])와 화면에 그릴 위치([point])를 따로 들고 있는 상태.
///
/// 화면은 매 틱 [advance]를 부르고, true가 오면 그때만 지도 소스를 다시 쓴다.
/// [isSettled]가 true면 더 그릴 것이 없으므로 타이머를 접는다.
class LocationMarkerGlide {
  LatLng? _shown;
  LatLng? _target;
  double? _shownHeadingDeg;
  double? _targetHeadingDeg;

  /// 지금 그려야 할 자리. 목표가 없으면(마커를 지운 상태) null.
  LatLng? get point => _shown;

  /// 지금 그려야 할 방향. null이면 삼각형 없이 도트만 그린다.
  double? get headingDeg => _shownHeadingDeg;

  /// 표시값이 목표에 붙어 더 흐를 것이 없다.
  bool get isSettled {
    final target = _target;
    final shown = _shown;
    if (target == null || shown == null) return true;
    if (shown.latitude != target.latitude ||
        shown.longitude != target.longitude) {
      return false;
    }
    return _shownHeadingDeg == _targetHeadingDeg;
  }

  /// 새 목표를 준다. [target]이 null이면 마커를 지운 것이라 표시값도 함께 비운다.
  ///
  /// [snap]은 **걸어서 간 이동이 아니라고 호출부가 아는 경우**다(층 전환, 앵커
  /// 재배치, 실내 진입/이탈, 에스컬레이터 활강). 호출부가 모르는 도약은
  /// [locationMarkerGlideSnapM]가 뒤에서 한 번 더 잡는다.
  void aimAt(LatLng? target, {double? headingDeg, bool snap = false}) {
    if (target == null) {
      _target = null;
      _shown = null;
      _targetHeadingDeg = null;
      _shownHeadingDeg = null;
      return;
    }
    final shown = _shown;
    final teleport =
        snap ||
        shown == null ||
        _metersBetween(shown, target) > locationMarkerGlideSnapM;
    _target = target;
    _targetHeadingDeg = headingDeg;
    if (teleport) {
      _shown = target;
      _shownHeadingDeg = headingDeg;
    }
  }

  /// [elapsed]만큼 시간을 흘려 표시값을 목표 쪽으로 당긴다. 그림이 바뀌었으면
  /// true — 호출부는 그때만 지도 소스를 다시 쓴다.
  ///
  /// 틱 간격을 인자로 받는 이유: 네이티브 쓰기가 밀려 틱이 늦게 오면 그만큼
  /// 더 당겨야 화면 속도가 실제 걸음 속도와 어긋나지 않는다.
  bool advance(Duration elapsed) {
    final target = _target;
    if (target == null || elapsed <= Duration.zero) return false;
    var moved = _advancePoint(target, elapsed);
    if (_advanceHeading(elapsed)) moved = true;
    return moved;
  }

  bool _advancePoint(LatLng target, Duration elapsed) {
    final shown = _shown;
    if (shown == null) {
      _shown = target;
      return true;
    }
    if (shown.latitude == target.latitude &&
        shown.longitude == target.longitude) {
      return false;
    }
    final k = glideFollowFactor(elapsed, locationMarkerGlideTimeConstant);
    final next = LatLng(
      shown.latitude + (target.latitude - shown.latitude) * k,
      shown.longitude + (target.longitude - shown.longitude) * k,
    );
    _shown = _metersBetween(next, target) < _settleM ? target : next;
    return true;
  }

  bool _advanceHeading(Duration elapsed) {
    final target = _targetHeadingDeg;
    final shown = _shownHeadingDeg;
    if (target == null) {
      if (shown == null) return false;
      _shownHeadingDeg = null;
      return true;
    }
    if (shown == null) {
      _shownHeadingDeg = target;
      return true;
    }
    if (shown == target) return false;
    // 짧은 쪽으로 돈다. 359°에서 1°로 갈 때 358°를 되감으면 마커가 제자리에서
    // 한 바퀴 돈다.
    final delta = _shortestArcDeg(target - shown);
    if (delta.abs() < _settleDeg) {
      _shownHeadingDeg = target;
      return true;
    }
    final k = glideFollowFactor(elapsed, locationMarkerGlideHeadingTimeConstant);
    final eased = delta * k;
    final cap =
        locationMarkerGlideHeadingMaxRateDegPerSec *
        elapsed.inMicroseconds /
        1000000;
    final step = eased.abs() <= cap ? eased : (eased.isNegative ? -cap : cap);
    _shownHeadingDeg = _normalizeDeg(shown + step);
    return true;
  }

  static double _shortestArcDeg(double deltaDeg) {
    final wrapped = _normalizeDeg(deltaDeg);
    return wrapped > 180 ? wrapped - 360 : wrapped;
  }

  static double _normalizeDeg(double deg) {
    final wrapped = deg % 360;
    return wrapped < 0 ? wrapped + 360 : wrapped;
  }
}
