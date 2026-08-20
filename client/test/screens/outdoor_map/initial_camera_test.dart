import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/screens/outdoor_map/entry/initial_camera.dart';

/// 앱을 켠 뒤 첫 GPS 좌표로 지도를 옮길지에 대한 판정.
///
/// 이 갈래가 없던 동안 앱은 서울시청(fallbackLocation)에서 시작했고, 사용자가
/// 자기 자리를 직접 찾아야 했다. 반대로 조건을 느슨하게 잡으면 실내 도면을
/// 보는 중에 카메라가 GPS 좌표로 튄다.
void main() {
  /// 전부 통과하는 기본값. 각 테스트는 **하나만** 뒤집어 그 조건이 정말로
  /// 막는지 본다.
  bool call({
    bool alreadyCentered = false,
    bool followingUser = false,
    bool indoorEntered = false,
    bool initialCameraClaimed = false,
    bool mapReady = true,
  }) => shouldCenterOnFirstFix(
    alreadyCentered: alreadyCentered,
    followingUser: followingUser,
    indoorEntered: indoorEntered,
    initialCameraClaimed: initialCameraClaimed,
    mapReady: mapReady,
  );

  test('야외에서 지도가 준비된 첫 좌표면 옮긴다', () {
    expect(call(), isTrue);
  });

  test('이미 한 번 옮겼으면 다시 옮기지 않는다', () {
    // 두 번째부터는 사용자가 맞춰 둔 화면을 뺏는 것이 된다.
    expect(call(alreadyCentered: true), isFalse);
  });

  test('안내 중이면 추종 로직에 맡긴다', () {
    // 둘 다 카메라를 옮기면 한 좌표에 애니메이션이 두 번 걸린다.
    expect(call(followingUser: true), isFalse);
  });

  test('실내 도면을 보는 중이면 옮기지 않는다', () {
    // 카메라의 주인이 실내 위치(PDR)로 바뀐 상태다.
    expect(call(indoorEntered: true), isFalse);
  });

  test('매장 포커스가 카메라를 예약했으면 옮기지 않는다', () {
    // 공유 링크는 **지도보다 먼저 도착한다.** 그 포커스는 스타일 로드를
    // 기다리는 중이고 실내 모드는 아직 꺼져 있어, indoorEntered가 이 자리를
    // 대신하지 못한다. 막지 않으면 카메라가 사용자 위치로 갔다가 매장으로
    // 다시 가 두 번 튄다(실기기 로그로 확인).
    expect(call(initialCameraClaimed: true), isFalse);
  });

  test('지도가 아직 준비되지 않았으면 옮기지 않는다', () {
    // **여기가 핵심이다.** 이동은 조용히 무시되므로, 여기서 true를 주면
    // 호출부가 "했다"고 표시해 카메라가 영영 안 움직인다. 첫 좌표가 스타일보다
    // 빠른 실행이 실제로 있고, 그때는 스타일 로드 콜백의 pending 경로가 맡는다.
    expect(call(mapReady: false), isFalse);
  });
}
