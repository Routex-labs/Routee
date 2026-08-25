import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/features/indoor_navigation/contract/floor_transition_ui_state.dart';

/// 엘리베이터 **탑승 중 배너**가 지켜야 하는 것들.
///
/// 하나, 방향은 한 줄에만 적는다. 둘, 모르는 층을 지어내지 않는다. 셋, 안내
/// 자리는 하나뿐이라 겹치면 근거가 센 쪽만 남는다.
///
/// 화면에 뜨는·사라지는 시점은 `test/screens/outdoor_map/elevator_banner_test.dart`.
void main() {
  FloorTransitionUiState riding({
    String? from = '1F',
    String? to = '5F',
    bool goingUp = true,
  }) => FloorTransitionUiState.elevatorRiding(
    fromFloorLabel: from,
    toFloorLabel: to,
    goingUp: goingUp,
  );

  group('문구', () {
    test('올라갈 때와 내려갈 때가 갈린다', () {
      expect(riding(goingUp: true).detail, '엘리베이터로 올라가는 중');
      expect(riding(goingUp: false).detail, '엘리베이터로 내려가는 중');
    });

    test('도착 층을 알면 큰 줄이 가는 곳을, 작은 줄이 방향을 맡는다', () {
      final state = riding(from: 'B2', to: '5F');

      expect(state.headline, 'B2 → 5F');
      expect(state.detail, '엘리베이터로 올라가는 중');
    });

    test('도착 층을 모르면 큰 줄이 방향을 맡는다', () {
      // 경로 없이 탄 경우다. 층을 지어내는 대신 아는 것(방향)만 적는다.
      final up = riding(to: null);

      expect(up.hasFloorLabels, isFalse);
      expect(up.headline, '올라가는 중');
      expect(riding(to: null, goingUp: false).headline, '내려가는 중');
    });

    test('방향은 한 카드에 한 번만 나온다', () {
      // 큰 줄이 이미 방향을 적었으면 작은 줄은 탑승 사실만 말한다.
      final unknown = riding(to: null);

      expect(unknown.detail, '엘리베이터 탑승 중');
      expect(unknown.detail.contains(unknown.headline), isFalse);
    });

    test('아이콘을 가르는 값이 상태에 실려 있다', () {
      expect(riding().vehicle, FloorTransitionVehicle.elevator);
    });
  });

  group('셸에 알리는 계약', () {
    test('같은 탑승은 같은 값이다', () {
      // `_reportFloorTransitionUi`가 이 비교로 재알림을 막는다. 안 성립하면
      // 매 스냅샷마다 부모 setState가 돌아 지도가 초당 몇 번씩 다시 그려진다.
      expect(riding(), riding());
      expect(riding().hashCode, riding().hashCode);
    });

    test('방향이 뒤집히면 다른 값이다', () {
      expect(riding(goingUp: true), isNot(riding(goingUp: false)));
    });

    test('수단이 다르면 다른 값이다', () {
      // 층·단계가 같아도 그리는 아이콘과 문구가 다르다.
      const escalator = FloorTransitionUiState(
        stage: FloorTransitionStage.moving,
        vehicle: FloorTransitionVehicle.escalator,
        fromFloorLabel: '1F',
        toFloorLabel: '5F',
        goingUp: true,
      );

      expect(riding(), isNot(escalator));
    });
  });

  group('한 자리에 겹칠 때', () {
    const escalatorRide = FloorTransitionUiState(
      stage: FloorTransitionStage.swapping,
      vehicle: FloorTransitionVehicle.escalator,
      fromFloorLabel: '1F',
      toFloorLabel: '2F',
      goingUp: true,
    );
    const escalatorApproach = FloorTransitionUiState(
      stage: FloorTransitionStage.moving,
      vehicle: FloorTransitionVehicle.escalator,
      fromFloorLabel: '1F',
      toFloorLabel: '2F',
      goingUp: true,
    );

    test('엘리베이터가 에스컬레이터 접근·추정을 이긴다', () {
      // 에스컬레이터의 "노드 없는 수직 이동" 갈래는 엘리베이터를 타는 동안에도
      // 발화하고 도착 층을 이웃 층으로 짐작한다. 다섯 층을 가는 중에 "1F → 2F"가
      // 뜨면 안 된다.
      final merged = mergeFloorTransitionUiState(
        escalatorRide: null,
        elevatorRide: riding(),
        escalatorApproach: escalatorApproach,
      );

      expect(merged, riding());
    });

    test('확정된 에스컬레이터 탑승은 엘리베이터보다 앞이다', () {
      // 그쪽은 이미 도면을 갈아 끼우는 중이고, 덮개 카드가 같은 값으로 같은
      // 문장을 그린다 — 배너와 덮개가 다른 층을 말하면 안 된다.
      final merged = mergeFloorTransitionUiState(
        escalatorRide: escalatorRide,
        elevatorRide: riding(),
        escalatorApproach: escalatorApproach,
      );

      expect(merged, escalatorRide);
    });

    test('아무것도 없으면 자리를 비운다', () {
      expect(
        mergeFloorTransitionUiState(
          escalatorRide: null,
          elevatorRide: null,
          escalatorApproach: null,
        ),
        isNull,
      );
    });
  });
}
