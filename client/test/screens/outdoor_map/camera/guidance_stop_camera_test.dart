import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/screens/outdoor_map/camera/guidance_stop_camera.dart';

/// 안내를 끄고 계획 화면으로 돌아갈 때 카메라가 어디로 가는지의 검증 기준표.
///
/// 실기기 증상: 실내→야외 안내를 시작한 뒤 뒤로가기를 누르면 카메라가 야외 구간
/// 전체로 물러서면서 도면이 접혔고, 그 뒤로는 길찾기가 실내 갈래로 들어가지 못해
/// **두 번째 길찾기부터 실내 구간이 안 그려졌다.**
void main() {
  test('도면을 편 상태에서는 야외 경로 전체로 물러서지 않는다', () {
    expect(
      guidanceStopCameraTarget(
        indoorEntered: true,
        hasIndoorSegment: true,
        hasRouteToShow: true,
      ),
      GuidanceStopCameraTarget.indoorSegment,
    );
  });

  test('도면을 편 상태에 담을 실내 구간이 없으면 카메라를 건드리지 않는다', () {
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

  test('야외에서는 경로 전체를 담는다', () {
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
