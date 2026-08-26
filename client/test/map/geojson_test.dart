import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/map/geojson.dart';

void main() {
  test('경로 prefix는 길이 비율만큼 다음 꼭짓점 사이에서 끝난다', () {
    final prefix = routeLinePrefix(const [
      LatLng(37, 127),
      LatLng(37, 127.0001),
      LatLng(37.0001, 127.0001),
    ], 0.75);

    expect(prefix, hasLength(3));
    expect(prefix[1], const LatLng(37, 127.0001));
    expect(prefix.last.latitude, closeTo(37.000055, 1e-7));
    expect(prefix.last.longitude, closeTo(127.0001, 1e-7));
  });

  test('경로 prefix가 시작 전이면 그릴 선을 내지 않는다', () {
    expect(
      routeLinePrefix(const [LatLng(37, 127), LatLng(37, 127.0001)], 0),
      isEmpty,
    );
  });
}
