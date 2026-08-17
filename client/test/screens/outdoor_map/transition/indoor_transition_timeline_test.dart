import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/screens/outdoor_map/transition/indoor_transition_timeline.dart';

/// 연출은 눈으로 보는 것이지만, **깨지면 안 되는 관계**는 여기서 끝난다.
/// 미리보기 하네스는 "예뻐 보이는가"만 확인하면 된다.
///
/// 화면에서 실제로 어떻게 보이는지는 `lib/indoor_transition_preview_main.dart`.

const _directions = IndoorTransitionDirection.values;

/// 진행률을 촘촘히 훑는다. 사이가 벌어지는 구간은 대개 몇 프레임뿐이라
/// 성긴 표본으로는 못 잡는다.
Iterable<double> _sweep() sync* {
  for (var i = 0; i <= 200; i++) {
    yield i / 200;
  }
}

void main() {
  group('위치 아이콘은 한 프레임도 비지 않는다', () {
    // 이 그룹이 이 타임라인의 존재 이유다. 지금 화면은 진입 순간 GPS 마커를
    // 즉시 지우고 실내 마커는 앵커가 잡힌 뒤에야 그려서, 그 사이가 통째로
    // 비어 있다 — 사용자는 그때 "앱이 내 위치를 잃었다"고 읽는다.
    for (final direction in _directions) {
      test('$direction', () {
        for (final t in _sweep()) {
          final frame = indoorTransitionFrameAt(t, direction: direction);
          expect(
            frame.anyLocationMarkerOpacity,
            greaterThanOrEqualTo(0.5),
            reason: 't=$t에서 위치 아이콘이 흐려진다',
          );
        }
      });
    }

    // 위 문턱이 지켜지는 **이유**를 따로 못 박는다. 두 마커를 각각의 구간으로
    // 되돌리면 이 검사부터 깨지고, 그러면 "겹치게 고쳤는데 또 벌어졌다"를
    // 반복하지 않게 된다.
    for (final direction in _directions) {
      test('두 마커의 합이 항상 1이다 ($direction)', () {
        for (final t in _sweep()) {
          final frame = indoorTransitionFrameAt(t, direction: direction);
          expect(
            frame.gpsMarkerOpacity + frame.indoorMarkerOpacity,
            closeTo(1, 1e-9),
            reason: 't=$t에서 두 마커가 같은 교차 페이드에서 안 나온다',
          );
        }
      });
    }
  });

  group('양 끝은 두 상태 그대로다', () {
    test('진입 0은 야외, 1은 실내', () {
      final start = indoorTransitionFrameAt(
        0,
        direction: IndoorTransitionDirection.enter,
      );
      expect(start.cameraProgress, 0);
      expect(start.floorPlanOpacity, 0);
      expect(start.scrimOpacity, 0);
      expect(start.gpsMarkerOpacity, 1);
      expect(start.indoorMarkerOpacity, 0);
      expect(start.buildingFillOpacity, 1);

      final end = indoorTransitionFrameAt(
        1,
        direction: IndoorTransitionDirection.enter,
      );
      expect(end.cameraProgress, 1);
      expect(end.floorPlanOpacity, 1);
      expect(end.scrimOpacity, 1);
      expect(end.gpsMarkerOpacity, 0);
      expect(end.indoorMarkerOpacity, 1);
      expect(end.buildingFillOpacity, 0);
    });

    test('이탈의 양 끝은 진입의 양 끝을 뒤집은 것이다', () {
      // 구간표는 대칭이 아니지만 **끝 상태는 반드시 같아야 한다.** 어긋나면
      // 오갈 때마다 화면이 조금씩 다른 자리에서 시작한다.
      final enterEnd = indoorTransitionFrameAt(
        1,
        direction: IndoorTransitionDirection.enter,
      );
      final exitStart = indoorTransitionFrameAt(
        0,
        direction: IndoorTransitionDirection.exit,
      );
      expect(exitStart.cameraProgress, enterEnd.cameraProgress);
      expect(exitStart.floorPlanOpacity, enterEnd.floorPlanOpacity);
      expect(exitStart.scrimOpacity, enterEnd.scrimOpacity);
      expect(exitStart.gpsMarkerOpacity, enterEnd.gpsMarkerOpacity);
      expect(exitStart.indoorMarkerOpacity, enterEnd.indoorMarkerOpacity);
      expect(exitStart.buildingFillOpacity, enterEnd.buildingFillOpacity);
    });
  });

  group('구간 순서', () {
    test('진입은 카메라가 도면보다 먼저 움직인다', () {
      // 들어갈 때는 실내 위치를 아직 모른다. 카메라가 먼저 "여기로 들어간다"를
      // 보여 주지 않으면, 도면만 툭 켜지고 화면은 야외에 남아 있다.
      final early = indoorTransitionFrameAt(
        0.2,
        direction: IndoorTransitionDirection.enter,
      );
      expect(early.cameraProgress, greaterThan(0));
      expect(early.floorPlanOpacity, 0);
    });

    test('이탈은 위치 아이콘이 카메라보다 먼저 넘어간다', () {
      // 나올 때는 GPS 좌표를 이미 들고 있으므로 마커부터 넘겨줄 수 있고, 그게
      // 가장 급하다 — "나왔는데 내 위치가 없는" 화면을 없앤다.
      final early = indoorTransitionFrameAt(
        0.25,
        direction: IndoorTransitionDirection.exit,
      );
      expect(early.gpsMarkerOpacity, greaterThan(0));
      expect(early.cameraProgress, 1);
    });

    test('이탈이 진입보다 짧다', () {
      // 나가는 사람은 이미 문 밖이라, 같은 시간을 쓰면 화면이 굼떠 보인다.
      expect(
        indoorExitTransitionDuration,
        lessThan(indoorEnterTransitionDuration),
      );
    });
  });

  test('범위를 벗어난 진행률은 잘라 낸다', () {
    // 애니메이션 커브가 1을 아주 살짝 넘기는 일이 흔하다.
    for (final direction in _directions) {
      final over = indoorTransitionFrameAt(1.02, direction: direction);
      final at = indoorTransitionFrameAt(1, direction: direction);
      expect(over.cameraProgress, at.cameraProgress);
      final under = indoorTransitionFrameAt(-0.02, direction: direction);
      final zero = indoorTransitionFrameAt(0, direction: direction);
      expect(under.cameraProgress, zero.cameraProgress);
    }
  });
}
