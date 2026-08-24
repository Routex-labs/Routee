import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:navigation_client/screens/outdoor_map/layers/marker_map_layers.dart';

/// 위치 마커 소스에 담기는 값. 레이어의 `iconOpacity` 표현식이 `off_floor`
/// 속성 하나만 보므로, 그 속성이 언제 붙는지가 곧 "다른 층에 있다"의 표시다.
void main() {
  const point = ll.LatLng(37.5665, 126.978);

  Map<String, dynamic> propertiesOf(Map<String, dynamic> data) =>
      (data['features'] as List).single['properties'] as Map<String, dynamic>;

  test('이 층에 서 있으면 off_floor 속성이 붙지 않는다', () {
    final properties = propertiesOf(pdrLocationData(point, headingDeg: 90));
    expect(properties['heading'], 90);
    expect(properties.containsKey('off_floor'), isFalse);
  });

  test('다른 층에 서 있으면 off_floor 속성이 붙는다', () {
    // 붙지 않으면 마커가 이 층에 선 것과 똑같이 그려진다 — 흐리게 그리는
    // 근거가 이 속성 하나뿐이다([kOffFloorMarkerOpacity]).
    final properties = propertiesOf(pdrLocationData(point, offFloor: true));
    expect(properties['off_floor'], isTrue);
    // 방향은 붙이지 않는다. 그 층에서 마지막으로 알던 자리라 지금 어디를
    // 보고 있는지는 모른다.
    expect(properties.containsKey('heading'), isFalse);
  });

  test('그릴 자리가 없으면 빈 컬렉션이다', () {
    expect(pdrLocationData(null, offFloor: true)['features'], isEmpty);
  });
}
