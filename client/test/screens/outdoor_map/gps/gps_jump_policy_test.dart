import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/screens/outdoor_map/gps/gps_jump_policy.dart';

/// 튄 좌표를 버리는 규칙의 검증 기준표.
///
/// 좌표는 기준점에서 북쪽으로 N m 떨어뜨려 만든다 — 거리 하나만 보는 정책이라
/// 방향은 판정에 들어가지 않는다.
const _origin = LatLng(37.525862, 126.928540);
const _metersPerDegreeLat = 111320.0;

LatLng _north(double meters) =>
    LatLng(_origin.latitude + meters / _metersPerDegreeLat, _origin.longitude);

final _t0 = DateTime.utc(2026, 8, 20, 12);

GpsFixReference _ref({double accuracy = 8, LatLng? at}) => GpsFixReference(
  point: at ?? _origin,
  accuracyMeters: accuracy,
  acceptedAt: _t0,
);

bool _accept({
  required GpsFixReference? reference,
  required LatLng point,
  required int afterSeconds,
  double accuracy = 40,
}) => shouldAcceptGpsFix(
  reference: reference,
  point: point,
  accuracyMeters: accuracy,
  now: _t0.add(Duration(seconds: afterSeconds)),
);

void main() {
  test('첫 좌표는 비교 대상이 없어 그대로 받는다', () {
    expect(_accept(reference: null, point: _north(9999), afterSeconds: 0), isTrue);
  });

  test('1초 만에 200m를 뛴 좌표는 버린다', () {
    // 이게 이 정책의 존재 이유다 — 실내에서 튄 한 건이 마커를 건물 밖으로
    // 던지고, 그 좌표로 진입/이탈 판정까지 내려진다.
    expect(_accept(reference: _ref(), point: _north(200), afterSeconds: 1), isFalse);
  });

  test('제자리에서 흔들리는 정도는 튐이 아니다', () {
    // 서 있어도 좌표는 오차 반경만큼 떨린다. 여기서 거부하면 정상 세션이
    // 초당 한 번씩 버려진다.
    expect(_accept(reference: _ref(), point: _north(12), afterSeconds: 1), isTrue);
  });

  test('시간이 지난 만큼은 실제로 갈 수 있다', () {
    // 15 m/s로 20초면 300 m다. 자동차 안내가 있으므로 걸음 속도로 잡으면 안 된다.
    expect(_accept(reference: _ref(), point: _north(250), afterSeconds: 20), isTrue);
  });

  test('기준의 오차가 크면 거를 자격이 없다', () {
    // 오차 40m짜리 점을 기준으로 삼아 이동을 거부하면, 실제로 걸어간 사람을
    // 제자리에 붙잡는다.
    expect(
      _accept(reference: _ref(accuracy: 40), point: _north(200), afterSeconds: 1),
      isTrue,
    );
  });

  test('거부가 오래 이어지면 기준을 버리고 따라간다', () {
    // 이 탈출구가 없으면 기준점이 틀렸을 때(터널을 빠져나옴, 차를 탐) 거부가
    // 스스로를 유지해 위치가 영영 옛 자리에 붙는다.
    final far = _north(100000);
    expect(_accept(reference: _ref(), point: far, afterSeconds: 5), isFalse);
    expect(
      _accept(reference: _ref(), point: far, afterSeconds: jumpRejectMaxHold.inSeconds),
      isTrue,
    );
  });

  test('오차가 작은 좌표가 말하는 이동은 그대로 믿는다', () {
    // 거르는 대상은 "못 믿을 좌표가 멀리 뛴 경우" 하나다. 좋은 좌표까지 거리로
    // 막으면 문을 나선 직후·차를 탄 직후의 사용자가 옛 자리에 붙는다.
    expect(
      _accept(reference: _ref(), point: _north(200), afterSeconds: 1, accuracy: 8),
      isTrue,
    );
  });

  test('기기 시계가 뒤로 가면 거르지 않는다', () {
    expect(_accept(reference: _ref(), point: _north(500), afterSeconds: -5), isTrue);
  });
}
