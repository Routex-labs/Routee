import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// 재탐색으로 교체된 경로에서 이미 완료한 구간을 보존한다.
///
/// 이 클래스는 실제 센서 궤적을 저장하지 않는다. 사용자가 지도에서 보는
/// "계획 경로를 이미 지나온 부분"만 저장하며, PDR 궤적은
/// [GuidanceTrailSession]이 별도로 소유한다.
class CompletedRouteHistory {
  final Map<String, List<List<LatLng>>> _segmentsByScope = {};

  /// 실내 층과 야외 경로를 서로 연결하지 않기 위한 표시 범위다.
  ///
  /// 야외는 `outdoor`, 실내는 층 이름을 넣는다. 다층 안내에서 다른 층의
  /// 회색선이 현재 층 도면 위에 나타나지 않도록 하는 경계이기도 하다.
  static const String outdoorScope = 'outdoor';

  bool get isEmpty =>
      _segmentsByScope.values.every((segments) => segments.isEmpty);

  void clear() {
    _segmentsByScope.clear();
    _watermarkByScope.clear();
    _watermarkGeneration = null;
  }

  /// 지금 경로의 완료 구간에서 **실제로 그릴** 회색선을 고른다.
  ///
  /// [completed]가 직전보다 짧거나 비어 있으면 직전 값을 그대로 돌려준다. 이
  /// 앞으로만 자라는 성질이 이 함수의 전부다 — 확정 위치가 뒤로 튀거나, 경로를
  /// 벗어나 진행률이 잠깐 사라지는 순간마다 회색선이 통째로 사라졌다. 사용자
  /// 눈에는 "지나온 길이 없어지고 마커만 떠 있는" 화면이다.
  ///
  /// [generation]이 바뀌면 수위를 버린다. 새 경로는 지나온 구간도 새로 세야
  /// 하고, 옛 구간은 그때 [append]로 이력에 넘어간다. 세대를 인자로 받는 이유는
  /// 호출부가 초기화를 잊을 자리를 만들지 않기 위해서다.
  List<LatLng> advance({
    required String scopeId,
    required int generation,
    required List<LatLng> completed,
  }) {
    if (_watermarkGeneration != generation) {
      _watermarkGeneration = generation;
      _watermarkByScope.clear();
    }
    final previous = _watermarkByScope[scopeId];
    if (completed.length >= 2 &&
        (previous == null || _lengthM(completed) >= _lengthM(previous))) {
      _watermarkByScope[scopeId] = List<LatLng>.unmodifiable(completed);
      return completed;
    }
    return previous ?? completed;
  }

  /// [points]를 기존 이력에 추가한다.
  ///
  /// 같은 경로를 두 번 저장해도 마지막 선과 가까우면 이어 붙이고, 서로
  /// 떨어진 재탐색 구간은 별도 선으로 남긴다. 멀리 떨어진 두 점을 무조건
  /// 직선으로 잇지 않는 것이 중요하다 — 재탐색 중 GPS/PDR이 튄 흔적이
  /// 회색 지름길처럼 보이는 것을 막는다.
  void append({required String scopeId, required List<LatLng> points}) {
    final cleaned = _removeConsecutiveDuplicates(points);
    if (cleaned.length < 2) return;

    final segments = _segmentsByScope.putIfAbsent(scopeId, () => []);
    if (segments.isEmpty) {
      segments.add(cleaned);
      return;
    }

    final previous = segments.last;
    if (_distanceM(previous.last, cleaned.first) <= _joinToleranceM) {
      final joined = [...previous];
      for (final point in cleaned) {
        if (_distanceM(joined.last, point) > _duplicateToleranceM) {
          joined.add(point);
        }
      }
      segments[segments.length - 1] = joined;
      return;
    }

    segments.add(cleaned);
  }

  /// [scopeId]에 해당하는 회색선만 반환한다.
  ///
  /// 호출자가 내부 리스트를 바꿔도 이력 자체가 변하지 않도록 복사본을
  /// 돌려준다. 현재 진행 중인 경로의 완료 구간은 호출자가 여기에 합쳐서
  /// 렌더링하고, 재탐색이 확정될 때만 [append]한다.
  List<List<LatLng>> segmentsFor(String scopeId) => [
    for (final segment in _segmentsByScope[scopeId] ?? const <List<LatLng>>[])
      List<LatLng>.unmodifiable(segment),
  ];

  /// 세대별 최고 수위. 세대가 바뀌면 통째로 버린다([advance]).
  final Map<String, List<LatLng>> _watermarkByScope = {};
  int? _watermarkGeneration;

  static const _duplicateToleranceM = 0.5;
  static const _joinToleranceM = 2.0;

  static double _lengthM(List<LatLng> points) {
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += _distanceM(points[i - 1], points[i]);
    }
    return total;
  }

  static List<LatLng> _removeConsecutiveDuplicates(List<LatLng> points) {
    if (points.isEmpty) return const [];
    final result = <LatLng>[points.first];
    for (final point in points.skip(1)) {
      if (_distanceM(result.last, point) > _duplicateToleranceM) {
        result.add(point);
      }
    }
    return result;
  }

  /// 짧은 구간에서 충분히 정확한 미터 단위 거리다. 회색선의 연결 여부만
  /// 판단하므로 지구 곡률보다 좌표계 변환의 일관성이 더 중요하다.
  static double _distanceM(LatLng a, LatLng b) {
    final meanLat = (a.latitude + b.latitude) * math.pi / 360.0;
    final east = (b.longitude - a.longitude) * math.cos(meanLat) * 111320.0;
    final north = (b.latitude - a.latitude) * 111320.0;
    return math.sqrt(east * east + north * north);
  }
}
