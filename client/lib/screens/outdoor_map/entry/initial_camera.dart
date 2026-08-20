/// 앱을 켠 뒤 **첫 GPS 좌표로 지도를 옮길지** 정하는 판정.
///
/// 지도 컨트롤러를 세울 수 없어 이 갈래는 위젯 테스트로 확인할 수 없다. 그래서
/// 판정만 뗐다 — `walk_route_kind.dart`와 같은 이유다.
///
/// 검증 기준은 `client/test/screens/outdoor_map/initial_camera_test.dart`.
library;

/// 이번 좌표로 첫 센터링을 해야 하는가.
///
/// 다섯 중 하나라도 걸리면 하지 않는다.
///   - [alreadyCentered] — 앱 수명 동안 한 번뿐이다. 두 번째부터는 사용자가
///     맞춰 둔 화면을 뺏는 것이 된다.
///   - [followingUser] — 안내 중이면 추종 로직이 카메라의 주인이다.
///   - [indoorEntered] — 실내 도면을 보는 중에 GPS 좌표로 튀면 안 된다.
///   - [initialCameraClaimed] — 공유 링크·검색이 카메라를 예약했다. 실내 모드는
///     아직 꺼져 있으므로 [indoorEntered]가 이것을 대신하지 못한다.
///   - [mapReady] — 컨트롤러·스타일이 없으면 이동이 조용히 무시된다. 그때
///     "했다"고 표시하면 카메라가 영영 안 움직인다(그 경우는 스타일 로드
///     콜백의 pending 경로가 처리한다).
bool shouldCenterOnFirstFix({
  required bool alreadyCentered,
  required bool followingUser,
  required bool indoorEntered,
  required bool initialCameraClaimed,
  required bool mapReady,
}) {
  if (alreadyCentered) return false;
  if (followingUser) return false;
  if (indoorEntered) return false;
  if (initialCameraClaimed) return false;
  return mapReady;
}
