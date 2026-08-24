import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/floor/floor_altitude_table.dart';

void main() {
  final table = floorAltitudeTableFor('thehyundai-seoul')!;

  test('모르는 건물은 표가 없다', () {
    expect(floorAltitudeTableFor('someone-elses-mall'), isNull);
    expect(floorAltitudeTableFor(null), isNull);
  });

  test('지상 여러 층을 한 번에 푼다', () {
    // 4F(+29.23) → B1(+5.83). 엘리베이터의 기본 사용이고, ±1층 제한이 있으면
    // 여기서 깨진다.
    expect(floorAtDelta(table: table, fromFloor: '4F', deltaM: -23.40), 'B1');
    expect(floorAtDelta(table: table, fromFloor: 'B2', deltaM: 39.93), '6F');
  });

  test('가장 좁은 지하 간격(B4→B3 3.23m)이 갈린다', () {
    expect(floorAtDelta(table: table, fromFloor: 'B4', deltaM: 3.23), 'B3');
    expect(floorAtDelta(table: table, fromFloor: 'B4', deltaM: 3.53), 'B3');
    expect(floorAtDelta(table: table, fromFloor: 'B3', deltaM: -3.23), 'B4');
  });

  test('층 사이 어중간한 자리는 고르지 않는다', () {
    // B4→B3 한가운데. 2등과의 여유가 0이라 어느 쪽도 못 고른다.
    expect(floorAtDelta(table: table, fromFloor: 'B4', deltaM: 1.615), isNull);
    // 지상도 같다(4F→5F 5.33m의 한가운데).
    expect(floorAtDelta(table: table, fromFloor: '4F', deltaM: 2.66), isNull);
  });

  test('여유 규칙의 경계는 (G-margin)/2에서 갈린다', () {
    // B4→B3 간격 3.23, 기본 여유 1.0 → B3에서 1.11m까지 통과.
    expect(
      floorAtDelta(table: table, fromFloor: 'B4', deltaM: 3.23 - 1.10),
      'B3',
    );
    expect(
      floorAtDelta(table: table, fromFloor: 'B4', deltaM: 3.23 - 1.13),
      isNull,
    );
  });

  test('호기가 서는 층만 후보로 좁힌다', () {
    // EV6은 5F에 안 선다. 4F에서 +5.33이면 5F이 정답이지만, 후보에서 빠지면
    // 남은 층(6F·3F 등)과 멀어 아무것도 못 고른다.
    const ev6 = {'B2', 'B1', '1F', '2F', '3F', '4F', '6F'};
    expect(floorAtDelta(table: table, fromFloor: '4F', deltaM: 5.33), '5F');
    expect(
      floorAtDelta(
        table: table,
        fromFloor: '4F',
        deltaM: 5.33,
        servedFloors: ev6,
      ),
      isNull,
    );
    expect(
      floorAtDelta(
        table: table,
        fromFloor: '4F',
        deltaM: 10.70,
        servedFloors: ev6,
      ),
      '6F',
    );
  });

  test('후보가 하나뿐이어도 절대 오차 상한이 막는다', () {
    // 2등이 없어 여유 규칙이 못 돈다. maxErrorM이 없으면 어떤 Δ든 통과한다.
    expect(
      floorAtDelta(
        table: table,
        fromFloor: '1F',
        deltaM: 20.0,
        servedFloors: const {'2F'},
      ),
      isNull,
    );
    expect(
      floorAtDelta(
        table: table,
        fromFloor: '1F',
        deltaM: 5.56,
        servedFloors: const {'2F'},
      ),
      '2F',
    );
  });

  test('표에 없는 출발 층은 풀지 않는다', () {
    expect(floorAtDelta(table: table, fromFloor: '7F', deltaM: 5.3), isNull);
  });

  test('floorGapM은 두 층의 차이를 준다', () {
    expect(
      floorGapM(table: table, from: '4F', to: 'B1'),
      closeTo(-23.40, 0.01),
    );
    expect(floorGapM(table: table, from: 'B4', to: 'B3'), closeTo(3.23, 0.01));
    expect(floorGapM(table: table, from: '4F', to: '7F'), isNull);
  });

  test('nearestFloorGapM은 그 층에서의 "한 층"이다', () {
    // B3의 이웃은 B2(3.54)와 B4(3.23) — 좁은 쪽이 한 층이다.
    expect(nearestFloorGapM(table: table, floor: 'B3'), closeTo(3.23, 0.01));
    // 1F은 아래로 7.11, 위로 5.56.
    expect(nearestFloorGapM(table: table, floor: '1F'), closeTo(5.56, 0.01));
    expect(nearestFloorGapM(table: table, floor: '7F'), isNull);
  });
}
