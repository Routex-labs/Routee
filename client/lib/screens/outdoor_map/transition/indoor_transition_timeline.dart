/// 실내 진입·이탈 **전환 연출**의 타임라인 — 진행률 하나를 각 요소의 값으로 옮긴다.
///
/// 지도도 위젯도 모른다. 그래서 미리보기 하네스와 실제 화면이 **같은 곡선**을 쓰고,
/// 곡선을 고치면 양쪽이 함께 바뀐다.
///
/// 구간을 왜 이렇게 겹쳤는지, 진입과 이탈이 왜 대칭이 아닌지는
/// `docs/client/indoor-transition-choreography.md`.
library;

import 'dart:math' as math;

/// 진입 연출 길이. 건물 탭 진입의 카메라 확대(`indoorZoomInDuration`)와 같은 값이다
/// — 두 경로가 다른 시간에 걸리면 같은 진입인데 속도가 다르게 느껴진다.
const indoorEnterTransitionDuration = Duration(milliseconds: 900);

/// 이탈 연출 길이. **진입보다 짧다.** 나가는 사람은 이미 문 밖으로 걸어 나간
/// 뒤라, 진입과 같은 시간을 쓰면 굼떠서 화면이 자기를 못 따라온다고 느낀다.
const indoorExitTransitionDuration = Duration(milliseconds: 600);

/// 전환의 방향.
enum IndoorTransitionDirection {
  /// 야외 → 실내.
  enter,

  /// 실내 → 야외.
  exit,
}

/// 한 요소가 움직이는 구간. 두 값 모두 **전체 진행률**(0~1) 위의 위치다.
///
/// 구간을 겹쳐 두는 것이 이 연출의 전부다 — 요소마다 따로 애니메이션을 걸면
/// 서로 언제 겹치는지가 코드 어디에도 안 남아, 사이가 벌어져도 아무도 모른다.
class TransitionSpan {
  const TransitionSpan(this.begin, this.end);

  final double begin;
  final double end;

  /// 전체 진행률 [t]에서 이 구간이 만드는 값(0~1). 구간 밖은 0이나 1로 굳는다.
  double rawAt(double t) {
    if (t <= begin) return 0;
    if (t >= end) return 1;
    return (t - begin) / (end - begin);
  }

  /// [rawAt]에 easeOutCubic을 먹인 값. 카메라 이징과 같은 성격이라 요소들이
  /// 따로 놀지 않는다(`_animateSelectionScale`도 같은 곡선을 쓴다).
  double easedAt(double t) => 1 - math.pow(1 - rawAt(t), 3).toDouble();
}

/// 전환 한 프레임의 모든 값. 화면은 이걸 그대로 그리기만 한다.
///
/// 값은 전부 0~1이고 **"실내 쪽에 얼마나 가까운가"가 아니라 "그 요소가 지금
/// 얼마나 보이는가"** 다. 방향마다 뜻이 뒤집히면 그리는 쪽이 매번 조건문을 쓴다.
class IndoorTransitionFrame {
  const IndoorTransitionFrame({
    required this.cameraProgress,
    required this.scrimOpacity,
    required this.floorPlanOpacity,
    required this.buildingFillOpacity,
    required this.gpsMarkerOpacity,
    required this.indoorMarkerOpacity,
  });

  /// 0이면 야외 카메라(넓게·사용자 중심), 1이면 실내 카메라(확대·건물 중심).
  final double cameraProgress;

  /// 건물 밖을 덮는 어둠. "여기부터는 실내"라는 유일한 신호다.
  final double scrimOpacity;

  /// 층 도면(매장·복도).
  final double floorPlanOpacity;

  /// 야외 지도의 옅은 건물 fill. 도면이 그 자리를 대신하므로 반대로 움직인다.
  final double buildingFillOpacity;

  /// GPS 파란 점.
  final double gpsMarkerOpacity;

  /// 실내 위치 마커.
  final double indoorMarkerOpacity;

  /// 지금 화면에 위치 아이콘이 얼마나 보이는가. 둘 중 진한 쪽이다.
  ///
  /// 이 값이 0에 닿는 순간이 **연출이 실패한 순간**이다 — 사용자는 그때 "앱이
  /// 내 위치를 잃었다"고 읽는다. 두 마커가 하나의 교차 페이드에서 나오므로
  /// (`_enter.handover`) 구조상 0.5 아래로는 못 내려간다.
  double get anyLocationMarkerOpacity =>
      math.max(gpsMarkerOpacity, indoorMarkerOpacity);
}

/// 두 마커는 **구간을 따로 갖지 않는다.**
///
/// 처음에는 "GPS 점 사라짐"과 "실내 마커 나타남"을 각각 구간으로 뒀는데, 겹쳐
/// 놨는데도 사이가 벌어졌다(진입 t≈0.6에서 둘 다 0.2 아래). easeOutCubic이 빨리
/// 올라가는 곡선이라 **사라지는 쪽이 그만큼 빨리 죽기** 때문이다.
///
/// 그래서 하나의 교차 페이드로 묶는다 — 한쪽이 `v`면 다른 쪽은 `1 - v`라 합이
/// 항상 1이고, 진한 쪽은 어떤 곡선을 써도 0.5 아래로 안 내려간다. 구간을 맞추는
/// 대신 **어긋날 수 없게** 만든 것이다.
typedef _Handover = TransitionSpan;

/// 진입 구간표. **카메라가 먼저, 위치 아이콘이 나중이다.**
///
/// 들어갈 때는 실내 위치를 아직 모른다(앵커는 층 그래프·센서가 준비된 뒤에야
/// 잡힌다). 그래서 카메라가 먼저 건물로 들어가 "여기로 들어간다"를 보여 주고,
/// 인수인계는 도면이 다 깔린 뒤에 한다.
const _enter = (
  camera: TransitionSpan(0.00, 0.55),
  scrim: TransitionSpan(0.10, 0.45),
  floorPlan: TransitionSpan(0.25, 0.65),
  buildingFill: TransitionSpan(0.25, 0.55),
  handover: _Handover(0.45, 0.85),
);

/// 이탈 구간표. **위치 아이콘이 먼저, 카메라가 나중이다** — 진입과 반대다.
///
/// 나올 때는 GPS 좌표를 이미 들고 있으므로 마커부터 넘겨줄 수 있고, 그게 가장
/// 급한 일이다(나왔는데 내 위치가 없는 화면을 없앤다). 카메라는 그 뒤에 따라간다.
const _exit = (
  handover: _Handover(0.00, 0.35),
  floorPlan: TransitionSpan(0.20, 0.55),
  scrim: TransitionSpan(0.30, 0.65),
  buildingFill: TransitionSpan(0.40, 0.75),
  camera: TransitionSpan(0.35, 1.00),
);

/// 진행률 [t](0~1)에서 그려야 할 한 프레임. 범위 밖 값은 잘라 낸다 —
/// 애니메이션 컨트롤러가 커브 때문에 아주 살짝 넘기는 일이 흔하다.
IndoorTransitionFrame indoorTransitionFrameAt(
  double t, {
  required IndoorTransitionDirection direction,
}) {
  final p = t.clamp(0.0, 1.0).toDouble();
  return switch (direction) {
    IndoorTransitionDirection.enter => () {
      final handover = _enter.handover.easedAt(p);
      return IndoorTransitionFrame(
        cameraProgress: _enter.camera.easedAt(p),
        scrimOpacity: _enter.scrim.easedAt(p),
        floorPlanOpacity: _enter.floorPlan.easedAt(p),
        buildingFillOpacity: 1 - _enter.buildingFill.easedAt(p),
        gpsMarkerOpacity: 1 - handover,
        indoorMarkerOpacity: handover,
      );
    }(),
    IndoorTransitionDirection.exit => () {
      final handover = _exit.handover.easedAt(p);
      return IndoorTransitionFrame(
        cameraProgress: 1 - _exit.camera.easedAt(p),
        scrimOpacity: 1 - _exit.scrim.easedAt(p),
        floorPlanOpacity: 1 - _exit.floorPlan.easedAt(p),
        buildingFillOpacity: _exit.buildingFill.easedAt(p),
        gpsMarkerOpacity: handover,
        indoorMarkerOpacity: 1 - handover,
      );
    }(),
  };
}
