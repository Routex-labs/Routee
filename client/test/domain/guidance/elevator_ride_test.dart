import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/floor/floor_altitude_table.dart';
import 'package:navigation_client/domain/guidance/elevator_ride.dart';
import 'package:navigation_client/domain/guidance/escalator_ride.dart';

/// 엘리베이터 활강의 **검증 기준**. 지키려는 것은 셋이다.
///
/// 하나, 진행률의 분모는 한 층이 아니라 시작 층 → 도착 층 총 Δ다. 이 건물에서
/// 한 번 타는 이동이 8개 층·39.87 m까지 나왔으므로, 두 층짜리로 가정하면 점이
/// 첫 층에서 끝에 닿고 남은 30여 m를 멈춰 선 채 올라간다.
///
/// 둘, 끝(1.0)은 하차 확정만 채운다. 셋, 근거(고도표·경로)가 없으면 아예 안 건다.
void main() {
  // 더현대 서울 실측표와 같은 값. 표 자체의 검증은
  // `test/domain/floor/floor_altitude_table_test.dart`가 한다.
  const table = <String, double>{
    'B2': 0.00,
    'B1': 5.83,
    '1F': 12.94,
    '2F': 18.50,
    '3F': 23.89,
    '4F': 29.23,
    '5F': 34.56,
  };

  const boarding = LatLng(37.5663, 126.9777);
  const arrival = LatLng(37.5665, 126.9781);
  const transferPoints = [boarding, arrival];

  group('진행률 분모', () {
    test('B1→5F는 한 층이 아니라 5개 층 합(28.73m)으로 정규화한다', () {
      final gapM = floorGapM(table: table, from: 'B1', to: '5F')!;
      expect(gapM, closeTo(28.73, 0.01));

      // 한 층(5.56m)만큼 올라간 시점. 분모가 한 층이면 여기서 이미 1.0이다.
      final target = elevatorRideProgressTarget(
        deltaTowardsM: 5.56,
        totalGapM: gapM,
      );
      expect(target, closeTo(5.56 / 28.73, 0.001));
      expect(target, lessThan(0.25));
    });

    test('내려가는 이동도 같은 분모를 쓴다(부호는 호출부가 맞춘다)', () {
      final gapM = floorGapM(table: table, from: '5F', to: 'B2')!;
      expect(gapM, closeTo(-34.56, 0.01));
      // 절반쯤 내려온 자리. deltaM(-17.3)에 부호를 뒤집어 넣는다.
      expect(
        elevatorRideProgressTarget(deltaTowardsM: 17.28, totalGapM: gapM),
        closeTo(0.5, 0.01),
      );
    });

    test('총 Δ가 0에 가까우면 진행률을 만들지 않는다', () {
      expect(
        elevatorRideProgressTarget(deltaTowardsM: 3, totalGapM: 0),
        0,
      );
    });
  });

  group('끝(1.0)', () {
    test('기압이 총 Δ를 넘겨도 확정 전에는 1.0에 안 닿는다', () {
      final gapM = floorGapM(table: table, from: 'B1', to: '5F')!;
      expect(
        elevatorRideProgressTarget(deltaTowardsM: gapM * 1.5, totalGapM: gapM),
        escalatorRideProgressCap,
      );
      expect(escalatorRideProgressCap, lessThan(1.0));
    });

    test('진행률이 음수로 내려가지 않는다', () {
      expect(
        elevatorRideProgressTarget(deltaTowardsM: -4, totalGapM: 28.73),
        0,
      );
    });
  });

  group('활강을 걸 조건', () {
    test('표와 경로가 다 있으면 계획이 나온다', () {
      final plan = planElevatorGlide(
        table: table,
        fromFloor: 'B1',
        toFloor: '5F',
        transferPoints: transferPoints,
      );
      expect(plan, isNotNull);
      expect(plan!.totalGapM, closeTo(28.73, 0.01));
      expect(plan.glide.from, boarding);
      expect(plan.glide.to, arrival);
    });

    test('고도표가 없으면 안 건다', () {
      expect(
        planElevatorGlide(
          table: null,
          fromFloor: 'B1',
          toFloor: '5F',
          transferPoints: transferPoints,
        ),
        isNull,
      );
    });

    test('표에 없는 층이 끼면 안 건다', () {
      expect(
        planElevatorGlide(
          table: table,
          fromFloor: 'B1',
          toFloor: 'B6',
          transferPoints: transferPoints,
        ),
        isNull,
      );
    });

    test('경로가 도착 층을 안 말하면 안 건다', () {
      expect(
        planElevatorGlide(
          table: table,
          fromFloor: 'B1',
          toFloor: null,
          transferPoints: transferPoints,
        ),
        isNull,
      );
    });

    test('경로가 수직 이동선을 안 주면 안 건다', () {
      expect(
        planElevatorGlide(
          table: table,
          fromFloor: 'B1',
          toFloor: '5F',
          transferPoints: const [],
        ),
        isNull,
      );
    });

    test('같은 층이면 안 건다', () {
      expect(
        planElevatorGlide(
          table: table,
          fromFloor: '2F',
          toFloor: '2F',
          transferPoints: transferPoints,
        ),
        isNull,
      );
    });
  });

  group('마커 자리', () {
    const glide = ElevatorGlide(from: boarding, to: arrival);

    test('진행률이 두 점 사이를 등속으로 잇는다', () {
      expect(glide.pointAtProgress(0), boarding);
      expect(glide.pointAtProgress(1), arrival);
      final mid = glide.pointAtProgress(0.5);
      expect(mid.latitude, closeTo(37.5664, 1e-6));
      expect(mid.longitude, closeTo(126.9779, 1e-6));
    });

    test('범위를 벗어난 진행률은 양 끝에 묶인다', () {
      expect(glide.pointAtProgress(-1), boarding);
      expect(glide.pointAtProgress(2), arrival);
    });
  });

  group('탑승 중 배너 방향', () {
    test('측정 Δ의 부호가 방향을 정한다', () {
      expect(
        elevatorRideGoingUp(
          measuredDeltaM: 2.4,
          fromFloorLabel: null,
          toFloorLabel: null,
        ),
        isTrue,
      );
      expect(
        elevatorRideGoingUp(
          measuredDeltaM: -2.4,
          fromFloorLabel: null,
          toFloorLabel: null,
        ),
        isFalse,
      );
    });

    test('경로가 위층을 말해도 지금 내려가면 내려가는 것이다', () {
      // 5F로 가려고 탔는데 칸이 먼저 B2로 내려가는 일이 실제로 있다. 배너가
      // 말해야 하는 것은 "갈 곳"이 아니라 지금 일어나는 일이다.
      expect(
        elevatorRideGoingUp(
          measuredDeltaM: -3.0,
          fromFloorLabel: '1F',
          toFloorLabel: '5F',
        ),
        isFalse,
      );
    });

    test('Δ가 임계 미만이면 층 순위로 메운다', () {
      expect(
        elevatorRideGoingUp(
          measuredDeltaM: elevatorRideDirectionMinDeltaM / 2,
          fromFloorLabel: 'B2',
          toFloorLabel: '1F',
        ),
        isTrue,
      );
      expect(
        elevatorRideGoingUp(
          measuredDeltaM: 0,
          fromFloorLabel: '5F',
          toFloorLabel: 'B1',
        ),
        isFalse,
      );
    });

    test('Δ도 층도 없으면 방향을 단정하지 않는다', () {
      // 반반으로 찍은 방향은 틀리면 정반대다. 부르는 쪽은 null을 "아직 배너를
      // 띄우지 마라"로 읽는다.
      expect(
        elevatorRideGoingUp(
          measuredDeltaM: null,
          fromFloorLabel: '1F',
          toFloorLabel: null,
        ),
        isNull,
      );
      expect(
        elevatorRideGoingUp(
          measuredDeltaM: 0.1,
          fromFloorLabel: '1F',
          toFloorLabel: '1F',
        ),
        isNull,
      );
      // 숫자를 못 읽는 라벨(옥상 등)의 순위는 0 — "모른다"는 뜻이다.
      expect(
        elevatorRideGoingUp(
          measuredDeltaM: null,
          fromFloorLabel: '1F',
          toFloorLabel: 'RF',
        ),
        isNull,
      );
    });
  });

  test('도면은 총 Δ의 절반에서 간다 — 8개 층을 가도 반씩 본다', () {
    expect(elevatorMapSwapProgress, 0.5);
    // 실측 최대 이동(6F→B2, 39.87m). 에스컬레이터 기준(2.4m)이면 6%에서 갈린다.
    const totalGapM = 39.87;
    expect(elevatorMapSwapProgress * totalGapM, closeTo(19.9, 0.1));
    expect(2.4 / totalGapM, lessThan(0.07));
  });
}
