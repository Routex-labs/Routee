import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/guidance/location_marker_glide.dart';

/// 위도 37.5 기준 미터 → 도. 경도 1도 ≈ 88.4km, 위도 1도 ≈ 111.32km.
LatLng _eastOf(LatLng from, double meters) =>
    LatLng(from.latitude, from.longitude + meters / 88400.0);

const _origin = LatLng(37.5, 127.0);

/// 반올림 없는 거리. `Distance()` 기본값은 정수 미터라 0.6m와 0m을 못 가른다.
const _distance = Distance(roundResult: false);

/// 60Hz 화면의 프레임 하나. 실제 보간은 vsync 틱이 준 **실제 경과 시간**으로
/// 하므로(`Ticker`), 여기서는 흔한 프레임 길이 하나를 표본으로 쓴다.
const _frame = Duration(milliseconds: 16);

/// 한 걸음(0.7m)만큼 앞선 목표를 주고 [ticks]번 틱을 흘린다.
LocationMarkerGlide _walkedOneStep({required int ticks}) {
  final glide = LocationMarkerGlide()..aimAt(_origin, headingDeg: 0);
  glide.aimAt(_eastOf(_origin, 0.7), headingDeg: 0);
  for (var i = 0; i < ticks; i++) {
    glide.advance(_frame);
  }
  return glide;
}

void main() {
  group('첫 목표', () {
    test('그리던 자리가 없으면 보간 없이 그 자리에 선다', () {
      final glide = LocationMarkerGlide()..aimAt(_origin, headingDeg: 12);
      expect(glide.point, _origin);
      expect(glide.headingDeg, 12);
      expect(glide.isSettled, isTrue);
    });

    test('목표가 null이면 마커가 사라진다', () {
      final glide = LocationMarkerGlide()..aimAt(_origin);
      glide.aimAt(null);
      expect(glide.point, isNull);
      expect(glide.isSettled, isTrue);
    });
  });

  group('걸음 하나', () {
    test('첫 틱에는 목표에 닿지 않는다 — 이 지연이 곧 부드러움이다', () {
      final glide = _walkedOneStep(ticks: 1);
      final left = _distance(glide.point!, _eastOf(_origin, 0.7));
      expect(left, greaterThan(0.05));
      expect(left, lessThan(0.7));
      expect(glide.isSettled, isFalse);
    });

    test('뒤로 가지 않고 목표 쪽으로만 간다', () {
      final glide = LocationMarkerGlide()..aimAt(_origin, headingDeg: 0);
      final target = _eastOf(_origin, 0.7);
      glide.aimAt(target, headingDeg: 0);
      var previous = _origin.longitude;
      for (var i = 0; i < 10; i++) {
        glide.advance(_frame);
        expect(glide.point!.longitude, greaterThan(previous));
        expect(glide.point!.longitude, lessThanOrEqualTo(target.longitude));
        previous = glide.point!.longitude;
      }
    });

    test('계속 걸어도 뒤처짐이 쌓이지 않는다', () {
      // 걸음(0.7m)이 0.5초마다 오는 동안 표시 위치는 목표를 못 따라잡는다.
      // 그 잔여가 **쌓이면** 마커가 걸을수록 뒤로 밀려 결국 다른 통로에 선다.
      // 지수 평활에서 잔여는 걸음마다 같은 값으로 수렴한다.
      final glide = LocationMarkerGlide()..aimAt(_origin, headingDeg: 0);
      var walkedM = 0.0;
      var earlyLagM = 0.0;
      var lastLagM = 0.0;
      for (var step = 1; step <= 20; step++) {
        walkedM += 0.7;
        final target = _eastOf(_origin, walkedM);
        glide.aimAt(target, headingDeg: 0);
        for (
          var tick = 0;
          tick < (500 / _frame.inMilliseconds).floor();
          tick++
        ) {
          glide.advance(_frame);
        }
        lastLagM = _distance(glide.point!, target);
        // 걸음 하나(0.7m)보다 뒤처지면 사용자가 지나온 자리를 그리게 된다.
        expect(lastLagM, lessThan(0.7));
        if (step == 2) earlyLagM = lastLagM;
      }
      expect(lastLagM, closeTo(earlyLagM, 0.01));
    });

    test('멈춰 서면 목표에 붙고 타이머가 스스로 멈춘다', () {
      final glide = _walkedOneStep(
        ticks: (1000 / _frame.inMilliseconds).ceil(),
      );
      expect(glide.point, _eastOf(_origin, 0.7));
      expect(glide.isSettled, isTrue);
    });

    test('틱이 밀려 늦게 와도 그만큼 더 당긴다', () {
      final slow = LocationMarkerGlide()..aimAt(_origin, headingDeg: 0);
      slow.aimAt(_eastOf(_origin, 0.7), headingDeg: 0);
      slow.advance(_frame * 10);

      final steady = _walkedOneStep(ticks: 10);
      expect(slow.point!.longitude, closeTo(steady.point!.longitude, 1e-9));
    });
  });

  group('걸어서 간 이동이 아닌 것', () {
    test('스냅 거리를 넘으면 그 자리로 옮긴다', () {
      final glide = LocationMarkerGlide()..aimAt(_origin, headingDeg: 0);
      final far = _eastOf(_origin, locationMarkerGlideSnapM + 1);
      glide.aimAt(far, headingDeg: 90);
      expect(glide.point, far);
      expect(glide.headingDeg, 90);
      expect(glide.isSettled, isTrue);
    });

    test('호출부가 snap을 주면 가까운 거리도 옮긴다', () {
      final glide = LocationMarkerGlide()..aimAt(_origin, headingDeg: 0);
      final near = _eastOf(_origin, 0.7);
      glide.aimAt(near, headingDeg: 0, snap: true);
      expect(glide.point, near);
      expect(glide.isSettled, isTrue);
    });

    test('같은 보행 여정의 표시 근거 교체는 멀어도 이어 간다', () {
      // 에스컬레이터 직전 shadow → follower → hold 전환은 같은 사용자의
      // 보행인데도 계산 좌표가 몇 m 벌 수 있다. 일반 4m 안전 스냅이 여기서
      // 켜지면 마지막 코너에서 마커가 순간이동한다.
      final glide = LocationMarkerGlide()..aimAt(_origin, headingDeg: 0);
      final handoff = _eastOf(_origin, locationMarkerGlideSnapM + 1);

      glide.aimAt(handoff, headingDeg: 90, preserveContinuity: true);

      expect(glide.point, _origin);
      expect(glide.isSettled, isFalse);
      glide.advance(_frame);
      expect(glide.point!.longitude, greaterThan(_origin.longitude));
      expect(glide.point!.longitude, lessThan(handoff.longitude));
    });

    test('연속 보행 전환이어도 명시적 snap은 우선한다', () {
      final glide = LocationMarkerGlide()..aimAt(_origin, headingDeg: 0);
      final handoff = _eastOf(_origin, locationMarkerGlideSnapM + 1);

      glide.aimAt(
        handoff,
        headingDeg: 90,
        snap: true,
        preserveContinuity: true,
      );

      expect(glide.point, handoff);
      expect(glide.isSettled, isTrue);
    });
  });

  group('방향', () {
    test('359°에서 1°로 갈 때 짧은 쪽으로 돈다', () {
      final glide = LocationMarkerGlide()..aimAt(_origin, headingDeg: 359);
      glide.aimAt(_origin, headingDeg: 1);
      glide.advance(_frame);
      final shown = glide.headingDeg!;
      // 되감으면 358°를 지나간다 — 제자리에서 한 바퀴 도는 그림이다.
      expect(shown > 359 || shown < 1.0001, isTrue, reason: '실제: $shown');
    });

    test('방향을 모르는 목표는 삼각형을 즉시 지운다', () {
      final glide = LocationMarkerGlide()..aimAt(_origin, headingDeg: 30);
      glide.aimAt(_origin);
      expect(glide.advance(_frame), isTrue);
      expect(glide.headingDeg, isNull);
      expect(glide.isSettled, isTrue);
    });

    test('각이 통째로 바뀌어도 상한을 넘지는 않는다', () {
      // 앵커를 다시 찍으면 방향이 한 번에 90° 바뀔 수 있다. 그때 삼각형이 한
      // 프레임에 튀지 않게 막는 안전판이다.
      final glide = LocationMarkerGlide()..aimAt(_origin, headingDeg: 0);
      glide.aimAt(_origin, headingDeg: 90);
      final perFrame =
          locationMarkerGlideHeadingMaxRateDegPerSec *
          _frame.inMilliseconds /
          1000;

      var previous = 0.0;
      final steps = <double>[];
      for (var i = 0; i < 10; i++) {
        glide.advance(_frame);
        steps.add(glide.headingDeg! - previous);
        previous = glide.headingDeg!;
      }
      for (final step in steps) {
        expect(step, lessThanOrEqualTo(perFrame + 1e-9));
      }
    });

    test('위치가 붙어도 방향이 남았으면 아직 끝나지 않았다', () {
      final glide = LocationMarkerGlide()..aimAt(_origin, headingDeg: 0);
      glide.aimAt(_origin, headingDeg: 40);
      expect(glide.isSettled, isFalse);

      var ticks = 0;
      while (!glide.isSettled && ticks < 100) {
        glide.advance(_frame);
        ticks++;
      }
      expect(glide.headingDeg, 40);
      // 40°를 도는 데 1초를 넘기면 몸을 튼 뒤에도 삼각형이 한참 뒤를 가리킨다.
      expect(ticks * _frame.inMilliseconds, lessThan(1000));
    });
  });
}
