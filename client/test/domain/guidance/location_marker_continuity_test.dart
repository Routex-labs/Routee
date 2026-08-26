import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_pdr_core/indoor_pdr_core.dart';
import 'package:navigation_client/domain/guidance/location_marker_continuity.dart';

void main() {
  test('후보가 몇 m 재배치돼도 화면은 raw 한 걸음만 전진한다', () {
    final continuity = LocationMarkerContinuity()
      ..reset(
        matchedPosition: PdrLocalPoint.zero,
        rawPosition: PdrLocalPoint.zero,
      );

    var raw = PdrLocalPoint.zero;
    var shown = PdrLocalPoint.zero;
    for (final matchedEastM in const [4.83, 3.28, 6.36, 4.21, 9.60, 5.74]) {
      final previousRaw = raw;
      final previousShown = shown;
      raw = PdrLocalPoint(raw.eastM + 0.77, 0);
      shown = continuity.update(
        matchedPosition: PdrLocalPoint(matchedEastM, 0),
        rawPosition: raw,
        headingBiasDeg: 0,
        leaderRelocated: true,
        ambiguous: true,
      );

      expect(
        (shown - previousShown).distance,
        closeTo((raw - previousRaw).distance, 1e-9),
      );
      expect(shown.eastM, greaterThan(previousShown.eastM));
    }
    expect(shown.eastM, closeTo(4.62, 1e-9));
    expect(continuity.isActive, isTrue);
  });

  test('걸음 없는 확정 재해석은 화면 위치를 움직이지 않는다', () {
    final continuity = LocationMarkerContinuity()
      ..reset(
        matchedPosition: const PdrLocalPoint(2, 0),
        rawPosition: const PdrLocalPoint(2, 0),
      );

    final shown = continuity.update(
      matchedPosition: const PdrLocalPoint(8, 3),
      rawPosition: const PdrLocalPoint(2, 0),
      headingBiasDeg: 0,
      leaderRelocated: true,
      ambiguous: false,
    );

    expect(shown.eastM, 2);
    expect(shown.northM, 0);
  });

  test('명시 신호가 없어도 raw 이동으로 설명되지 않는 도약을 보호한다', () {
    final continuity = LocationMarkerContinuity()
      ..reset(
        matchedPosition: PdrLocalPoint.zero,
        rawPosition: PdrLocalPoint.zero,
      );

    final shown = continuity.update(
      matchedPosition: const PdrLocalPoint(3, 0),
      rawPosition: const PdrLocalPoint(0.7, 0),
      headingBiasDeg: 0,
      leaderRelocated: false,
      ambiguous: false,
    );

    expect(shown.eastM, closeTo(0.7, 1e-9));
    expect(continuity.isActive, isTrue);
  });

  test('거리만 같고 graph가 다른 방향으로 꺾인 걸음도 raw 벡터를 잇는다', () {
    final continuity = LocationMarkerContinuity()
      ..reset(
        matchedPosition: PdrLocalPoint.zero,
        rawPosition: PdrLocalPoint.zero,
      );

    final shown = continuity.update(
      matchedPosition: const PdrLocalPoint(0, 0.7),
      rawPosition: const PdrLocalPoint(0.7, 0),
      headingBiasDeg: 0,
      leaderRelocated: false,
      ambiguous: true,
    );

    expect(shown.eastM, closeTo(0.7, 1e-9));
    expect(shown.northM, closeTo(0, 1e-9));
    expect(continuity.isActive, isTrue);
  });

  test('실제 raw 유턴은 연속성 보호 중에도 그대로 뒤로 간다', () {
    final continuity = LocationMarkerContinuity()
      ..reset(
        matchedPosition: PdrLocalPoint.zero,
        rawPosition: PdrLocalPoint.zero,
      );
    final forward = continuity.update(
      matchedPosition: const PdrLocalPoint(5, 0),
      rawPosition: const PdrLocalPoint(0.7, 0),
      headingBiasDeg: 0,
      leaderRelocated: true,
      ambiguous: true,
    );
    final reversed = continuity.update(
      matchedPosition: const PdrLocalPoint(-4, 0),
      rawPosition: PdrLocalPoint.zero,
      headingBiasDeg: 0,
      leaderRelocated: true,
      ambiguous: true,
    );

    expect(forward.eastM, closeTo(0.7, 1e-9));
    expect(reversed.eastM, closeTo(0, 1e-9));
  });

  test('안정화 보정은 횡방향으로만 조금씩 붙이고 전진을 되감지 않는다', () {
    final continuity = LocationMarkerContinuity()
      ..reset(
        matchedPosition: PdrLocalPoint.zero,
        rawPosition: PdrLocalPoint.zero,
      );
    continuity.update(
      matchedPosition: const PdrLocalPoint(1, 4),
      rawPosition: const PdrLocalPoint(1, 0),
      headingBiasDeg: 0,
      leaderRelocated: true,
      ambiguous: true,
    );

    final shown = continuity.update(
      // graph cursor가 화면보다 뒤쪽·북쪽이어도 서쪽으로 당기면 안 된다.
      matchedPosition: const PdrLocalPoint(1.5, 4),
      rawPosition: const PdrLocalPoint(2, 0),
      headingBiasDeg: 0,
      leaderRelocated: false,
      ambiguous: false,
    );

    expect(shown.eastM, closeTo(2, 1e-9));
    expect(shown.northM, closeTo(locationMarkerReconcilePerStepM, 1e-9));
  });

  test('heading bias는 shadow의 raw 이동 벡터에도 같은 각도로 적용한다', () {
    final continuity = LocationMarkerContinuity()
      ..reset(
        matchedPosition: PdrLocalPoint.zero,
        rawPosition: PdrLocalPoint.zero,
      );

    final shown = continuity.update(
      matchedPosition: const PdrLocalPoint(0, 5),
      rawPosition: const PdrLocalPoint(1, 0),
      headingBiasDeg: 90,
      leaderRelocated: true,
      ambiguous: true,
    );

    expect(shown.eastM, closeTo(0, 1e-9));
    expect(shown.northM, closeTo(-1, 1e-9));
  });

  test('graph cursor가 두 걸음 연속 따라오면 보호를 종료한다', () {
    final continuity = LocationMarkerContinuity()
      ..reset(
        matchedPosition: PdrLocalPoint.zero,
        rawPosition: PdrLocalPoint.zero,
      );
    continuity.update(
      matchedPosition: const PdrLocalPoint(0.1, 0),
      rawPosition: const PdrLocalPoint(0.1, 0),
      headingBiasDeg: 0,
      leaderRelocated: true,
      ambiguous: false,
    );

    continuity.update(
      matchedPosition: const PdrLocalPoint(0.2, 0),
      rawPosition: const PdrLocalPoint(0.2, 0),
      headingBiasDeg: 0,
      leaderRelocated: false,
      ambiguous: false,
    );
    expect(continuity.isActive, isTrue);

    final shown = continuity.update(
      matchedPosition: const PdrLocalPoint(0.3, 0),
      rawPosition: const PdrLocalPoint(0.3, 0),
      headingBiasDeg: 0,
      leaderRelocated: false,
      ambiguous: false,
    );
    expect(shown.eastM, closeTo(0.3, 1e-9));
    expect(continuity.isActive, isFalse);
  });

  test('경로 탑승 종점 잠금은 shadow보다 우선해 graph 위치로 복귀한다', () {
    final continuity = LocationMarkerContinuity()
      ..reset(
        matchedPosition: PdrLocalPoint.zero,
        rawPosition: PdrLocalPoint.zero,
      );
    continuity.update(
      matchedPosition: const PdrLocalPoint(5, 0),
      rawPosition: const PdrLocalPoint(0.7, 0),
      headingBiasDeg: 0,
      leaderRelocated: true,
      ambiguous: true,
    );

    final shown = continuity.update(
      matchedPosition: const PdrLocalPoint(6, 0),
      rawPosition: const PdrLocalPoint(1.4, 0),
      headingBiasDeg: 0,
      leaderRelocated: false,
      ambiguous: true,
      forceMatchedPosition: true,
    );

    expect(shown.eastM, 6);
    expect(continuity.isActive, isFalse);
  });

  test('후보가 계속 불안정해도 raw shadow는 보행 가능 간선 밖으로 누적되지 않는다', () {
    final continuity = LocationMarkerContinuity()
      ..reset(
        matchedPosition: PdrLocalPoint.zero,
        rawPosition: PdrLocalPoint.zero,
      );

    var shown = PdrLocalPoint.zero;
    for (var step = 1; step <= 8; step += 1) {
      shown = continuity.update(
        // 현재 1등 후보 좌표 자체는 멀리 재배치되는 상황을 재현한다.
        matchedPosition: PdrLocalPoint(step.isEven ? 8 : 5, 4),
        rawPosition: PdrLocalPoint(step * 0.6, step * 0.6),
        headingBiasDeg: 0,
        leaderRelocated: true,
        ambiguous: true,
        // 실제 보행 가능한 복도는 동서 방향 중심선이다.
        projectToNavigableGraph: (position) => PdrLocalPoint(position.eastM, 0),
      );

      expect(shown.northM, lessThanOrEqualTo(locationMarkerNavigableLeashM));
    }

    expect(shown.eastM, closeTo(4.8, 1e-9));
    expect(shown.northM, closeTo(locationMarkerNavigableLeashM, 1e-9));
    expect(continuity.isActive, isTrue);
  });

  test('보행 가능 투영은 멀리 튄 현재 1등이 아니라 로컬 간선을 유지한다', () {
    final continuity = LocationMarkerContinuity()
      ..reset(
        matchedPosition: PdrLocalPoint.zero,
        rawPosition: PdrLocalPoint.zero,
      );

    final shown = continuity.update(
      matchedPosition: const PdrLocalPoint(12, 5),
      rawPosition: const PdrLocalPoint(0.7, 0.2),
      headingBiasDeg: 0,
      leaderRelocated: true,
      ambiguous: true,
      projectToNavigableGraph: (position) => PdrLocalPoint(position.eastM, 0),
    );

    expect(shown.eastM, closeTo(0.7, 1e-9));
    expect(shown.northM, closeTo(0.2, 1e-9));
  });
}
