import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/screens/outdoor_map/camera/route_overview_camera.dart';

/// 개요로 물러선 카메라가 실내 상태를 붙드는 기준과, 안내를 끈 카메라가 갈 곳.
///
/// 실기기 증상 둘이 여기서 갈린다.
/// - 건물 안에서 대중교통을 고르면 시작을 누르기 전에 여정 전체가 안 보였다.
///   도면을 편 동안에는 아예 물러서지 않았기 때문이다.
/// - 그렇다고 그냥 물러서면 카메라가 멈추는 순간 도면이 접히고, 접힌 뒤로는
///   길찾기가 실내 갈래로 못 들어가 **실내 구간이 통째로 안 그려졌다.**
void main() {
  test('개요가 물러선 축소는 도면을 접지 않는다', () {
    expect(
      zoomOutKeepsIndoor(
        overviewHold: true,
        hasRouteToShow: true,
        indoorPositionLive: false,
      ),
      isTrue,
    );
  });

  test('사용자가 직접 축소한 것이면 접는다', () {
    // 개요가 세운 붙들기가 없다 = 이 축소의 뜻은 "건물에서 나가겠다"다.
    expect(
      zoomOutKeepsIndoor(
        overviewHold: false,
        hasRouteToShow: true,
        indoorPositionLive: false,
      ),
      isFalse,
    );
  });

  test('경로가 사라지면 붙들기도 끝난다', () {
    // 없으면 개요에서 경로를 지운 사용자가 도시 배율에 실내 상태로 갇힌다.
    expect(
      zoomOutKeepsIndoor(
        overviewHold: true,
        hasRouteToShow: false,
        indoorPositionLive: false,
      ),
      isFalse,
    );
  });

  test('실내 위치가 살아 있으면 사용자가 축소해도 안 접는다', () {
    // 접으면 **눈에 보이는 도면과 앱의 판정이 어긋난다** — 축소는 실내 위치를
    // 버리지 않으므로, 접힌 뒤에도 사용자는 건물 안에 서 있다. 실기기에서 그
    // 어긋남이 21 km짜리 야외 도보로 나왔다(`도면 false · 실내위치 true`).
    expect(
      zoomOutKeepsIndoor(
        overviewHold: false,
        hasRouteToShow: false,
        indoorPositionLive: true,
      ),
      isTrue,
    );
  });

  test('안내를 끌 때 도면을 편 상태면 실내 구간에 맞춘다', () {
    // 여정 전체로 물러서면 방금까지 따라가던 실내 선이 배율에 지워진다.
    expect(
      guidanceStopCameraTarget(
        indoorEntered: true,
        hasIndoorSegment: true,
        hasRouteToShow: true,
      ),
      GuidanceStopCameraTarget.indoorSegment,
    );
  });

  test('안내를 끌 때 담을 실내 구간이 없으면 카메라를 건드리지 않는다', () {
    // 맞출 대상 없이 배율만 되돌리면 방금 보던 화면을 이유 없이 잃는다.
    expect(
      guidanceStopCameraTarget(
        indoorEntered: true,
        hasIndoorSegment: false,
        hasRouteToShow: true,
      ),
      GuidanceStopCameraTarget.keep,
    );
  });

  test('안내를 야외에서 끄면 경로 전체를 담는다', () {
    // 계획 화면의 약속이다 — 어느 후보가 어느 선인지 대조할 수 있어야 한다.
    expect(
      guidanceStopCameraTarget(
        indoorEntered: false,
        hasIndoorSegment: false,
        hasRouteToShow: true,
      ),
      GuidanceStopCameraTarget.wholeRoute,
    );
  });

  test('야외에 그려진 경로가 없으면 카메라를 건드리지 않는다', () {
    expect(
      guidanceStopCameraTarget(
        indoorEntered: false,
        hasIndoorSegment: false,
        hasRouteToShow: false,
      ),
      GuidanceStopCameraTarget.keep,
    );
  });

  test('실내 구간이 남아 있어도 야외로 나왔으면 야외 경로를 담는다', () {
    // 밖으로 나간 사람에게 필요한 것은 지나온 실내 구간이 아니라 남은 길이다.
    expect(
      guidanceStopCameraTarget(
        indoorEntered: false,
        hasIndoorSegment: true,
        hasRouteToShow: true,
      ),
      GuidanceStopCameraTarget.wholeRoute,
    );
  });
}
