import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import '../../../domain/geo/geo_transform.dart';

/// UI가 **호출**하는 명령 계약(UI → 로직).
///
/// 세션 lifecycle과 anchor 확정은 headless 컨트롤러가 소유한다. UI는 사용자 제스처를
/// 이 메서드로 전달만 한다.
abstract interface class IndoorNavigationIntents {
  /// 실내 안내 시작. anchor 확정 절차를 개시하고 센서 세션을 켠다.
  Future<void> startGuidance({required String floorId});

  /// 실내 안내 종료. 센서 세션을 끈다.
  Future<void> stopGuidance();

  /// 사용자가 지도에 현재 위치를 찍어 anchor 위치를 확정한다. 이전 누적
  /// 걸음·경로·preview는 버리고 새 pin을 센서 세션의 원점으로 삼는다.
  /// [floorPointM]은 사용자가 지목한 floor local_m 좌표이고, [axes]는 PDR의
  /// east/north를 이 floor의 축 규약으로 바꾸는 변환이다.
  Future<void> confirmAnchorByPin({
    required PdrLocalPoint floorPointM,
    PdrToFloorAxes axes = const PdrToFloorAxes.identity(),
    String? floorId,
  });

  /// 사용자가 현재 진행 방향을 floor local_m 방향으로 맞춰 rotation을 확정한다.
  /// [floorDirection]은 위치가 아닌 단위와 무관한 방향 벡터다. 컨트롤러가 anchor
  /// 확정 때 받은 axes로 PDR 동·북 방향에 역변환한다.
  Future<void> confirmAnchorByFloorDirection({
    required PdrLocalPoint floorDirection,
  });

  /// 층 변경. PDR 세션을 reset하고 새 층 anchor 확정을 다시 요구한다.
  Future<void> changeFloor({required String floorId});

  /// 수직 이동(에스컬레이터·엘리베이터)이 확인돼 새 층의 도착 지점으로 위치를
  /// 옮긴다. [changeFloor]와 달리 사용자 pin을 다시 요구하지 않는다.
  ///
  /// [anchorLocalM]은 도착 지점의 새 층 local_m 좌표다. 회전값과 축 규약은
  /// 직전 anchor에서 물려받는다 — 같은 센서 세션이므로 heading frame이 바뀌지
  /// 않고, 그래서 사용자가 방향 보정을 다시 하지 않아도 된다. 직전 anchor가
  /// 없으면(보정 전) 아무 일도 하지 않는다.
  ///
  /// [axes]를 주면 새 층의 축 규약으로 교체한다. 층마다 도면 축이 다를 수
  /// 있으므로, 호출자가 새 층 기준으로 피팅한 값을 넘겨야 방향이 맞는다.
  Future<void> applyVerticalTransfer({
    required String floorId,
    required PdrLocalPoint anchorLocalM,
    PdrToFloorAxes? axes,
  });

  /// 걸음 누적만 멈춘다. 센서 구독은 그대로 둔다.
  ///
  /// 에스컬레이터에 탄 동안을 위한 것이다. 이때 pedometer는 진동을 걸음으로
  /// 세고 accel peak도 계속 잡히는데, 사용자는 실제로 걷고 있지 않으므로 그
  /// 걸음이 위치에 쌓이면 하차 지점이 통째로 어긋난다.
  ///
  /// **센서를 끄면 안 된다.** 하차 판정의 근거가 기압계이고 방향도 계속
  /// 따라가야 하므로, [onAppBackgrounded]처럼 native source를 멈추는 경로와는
  /// 구분한다. 여기서 멈추는 것은 tracking 플래그 하나다.
  Future<void> pauseStepTracking();

  /// [pauseStepTracking]으로 멈춘 걸음 누적을 다시 켠다.
  Future<void> resumeStepTracking();

  /// 앱이 백그라운드로 내려갔다. native 센서 소스를 멈추고 세션을 일시정지한다.
  ///
  /// [pauseStepTracking]과 다르다 — 저쪽은 플래그 하나만 내리고 센서는 계속
  /// 돌지만, 이쪽은 소스 자체를 끈다(위 주석 참고).
  Future<void> onAppBackgrounded();

  /// 앱이 다시 앞으로 나왔다. [onAppBackgrounded]로 멈춘 소스를 되살린다.
  Future<void> onAppForegrounded();
}
