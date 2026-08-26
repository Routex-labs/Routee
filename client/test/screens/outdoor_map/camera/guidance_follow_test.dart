import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/screens/outdoor_map/camera/guidance_follow.dart';

/// 걷는 안내 중 카메라가 마커를 언제 다시 부르는지의 검증 기준표.
///
/// 화면은 세로로 긴 폰(360×800)이고 배율은 실내 안내 중 흔한 배율(18)이다. 그 조합에서
/// 짧은 변(360px)이 덮는 실제 폭이 약 214 m라, 데드밴드는 그 절반의 35% ≈ 37 m다.
const _camera = LatLng(37.525862, 126.928540);
const _metersPerDegreeLat = 111320.0;
const _viewport = Size(360, 800);
const _zoom = 18.0;

LatLng _north(double meters) =>
    LatLng(_camera.latitude + meters / _metersPerDegreeLat, _camera.longitude);

bool _beyond(LatLng marker, {Size viewport = _viewport, double zoom = _zoom}) =>
    isBeyondFollowDeadband(
      camera: _camera,
      marker: marker,
      zoom: zoom,
      viewport: viewport,
    );

void main() {
  test('한두 걸음으로는 카메라를 부르지 않는다', () {
    // PDR은 한 걸음마다 값을 내놓는다. 그때마다 따라가면 지도가 걷는 내내
    // 끌려다녀 정작 도면을 읽을 수 없다.
    expect(_beyond(_north(1)), isFalse);
    expect(_beyond(_north(10)), isFalse);
  });

  test('화면 가운데를 크게 벗어나면 다시 부른다', () {
    // 이걸 안 하면 걸을수록 마커가 화면 위쪽으로 밀려 결국 가장자리에 닿는다.
    expect(_beyond(_north(60)), isTrue);
  });

  test('제자리면 부르지 않는다', () {
    expect(_beyond(_camera), isFalse);
  });

  test('확대할수록 같은 거리도 더 크게 벗어난 것이 된다', () {
    // 데드밴드는 미터가 아니라 화면 픽셀 기준이다 — 사용자가 느끼는 것은
    // 좌표 오차가 아니라 화면의 이동이다.
    expect(_beyond(_north(25), zoom: 17), isFalse);
    expect(_beyond(_north(25), zoom: 20), isTrue);
  });

  test('화면 크기나 배율을 모르면 부른다', () {
    // 계산 실패를 이유로 마커가 화면 밖으로 나간 것을 방치하는 쪽이 더 나쁘다.
    expect(_beyond(_north(1), viewport: Size.zero), isTrue);
    expect(_beyond(_north(1), zoom: double.nan), isTrue);
  });
}
