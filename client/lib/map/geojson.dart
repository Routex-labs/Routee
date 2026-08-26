/// MapLibre 소스에 밀어 넣는 GeoJSON을 만드는 최소 헬퍼.
///
/// "공용 유틸"이라서가 아니라 **분해의 선행 조건**으로 존재한다 — Dart의 `_`는 파일
/// 단위라, 이 세 함수가 화면 파일 안에 private으로 있는 한 거기서 레이어 코드를
/// 한 줄도 떼어낼 수 없었다.
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart' as ll;

/// 빈 FeatureCollection. 레이어를 지웠다 다시 만드는 대신 데이터만 비울 때 쓴다.
///
/// 레이어 제거·재생성은 층 전환이나 스타일 재로드와 경쟁해서 "레이어가 없다"는
/// 예외로 터지는데, 소스를 빈 컬렉션으로 덮어쓰면 그 경쟁이 아예 생기지 않는다.
Map<String, dynamic> emptyGeoJsonCollection() => {
  'type': 'FeatureCollection',
  'features': const <Map<String, dynamic>>[],
};

/// [features]를 담은 FeatureCollection.
Map<String, dynamic> geoJsonCollection(List<Map<String, dynamic>> features) => {
  'type': 'FeatureCollection',
  'features': features,
};

/// 경로선 feature 하나. [style]이 어느 레이어가 이 선을 그릴지 가른다 —
/// `drive`(실선·파랑), `walk`(점선·회색), `indoor`(실선·야외 본선과 같은 파랑).
Map<String, dynamic> geoJsonLineFeature(
  List<ll.LatLng> points, {
  String style = 'walk',
  int? generation,
}) {
  final properties = <String, dynamic>{'style': style};
  if (generation != null) properties['routeGeneration'] = generation;
  return {
    'type': 'Feature',
    'properties': properties,
    'geometry': {
      'type': 'LineString',
      'coordinates': [
        for (final p in points) [p.longitude, p.latitude],
      ],
    },
  };
}

/// [fraction]만큼의 폴리라인을 시작점부터 잘라, 경로가 자라나는 표시를 만든다.
List<ll.LatLng> routeLinePrefix(List<ll.LatLng> points, double fraction) {
  if (points.length < 2 || fraction <= 0) return const [];
  if (fraction >= 1) return List<ll.LatLng>.of(points);
  final lengths = <double>[];
  var totalM = 0.0;
  for (var index = 1; index < points.length; index += 1) {
    final lengthM = _lineDistanceM(points[index - 1], points[index]);
    lengths.add(lengthM);
    totalM += lengthM;
  }
  if (totalM <= 1e-9) return const [];
  final targetM = totalM * fraction;
  final prefix = <ll.LatLng>[points.first];
  var coveredM = 0.0;
  for (var index = 1; index < points.length; index += 1) {
    final lengthM = lengths[index - 1];
    if (coveredM + lengthM <= targetM) {
      prefix.add(points[index]);
      coveredM += lengthM;
      continue;
    }
    final t = lengthM <= 1e-9 ? 0.0 : (targetM - coveredM) / lengthM;
    final start = points[index - 1];
    final end = points[index];
    prefix.add(
      ll.LatLng(
        start.latitude + (end.latitude - start.latitude) * t,
        start.longitude + (end.longitude - start.longitude) * t,
      ),
    );
    return prefix;
  }
  return prefix;
}

double _lineDistanceM(ll.LatLng start, ll.LatLng end) {
  const metersPerDegreeLat = 111320.0;
  final metersPerDegreeLng =
      metersPerDegreeLat *
      math.cos((start.latitude + end.latitude) * math.pi / 360);
  final northM = (end.latitude - start.latitude) * metersPerDegreeLat;
  final eastM = (end.longitude - start.longitude) * metersPerDegreeLng;
  return math.sqrt(northM * northM + eastM * eastM);
}
