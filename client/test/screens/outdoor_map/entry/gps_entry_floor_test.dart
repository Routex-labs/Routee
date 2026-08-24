import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/screens/outdoor_map/entry/gps_entry_floor.dart';

/// **목적지 층은 앵커 층을 정하지 않는다.**
///
/// 실측 증상: 야외에서 B2 매장(스타벅스 리저브)을 목적지로 찍으면 도면이 B2로
/// 갈리고, 그 상태로 지상 1F 입구로 걸어 들어오면 앵커가 B2에 찍혔다. 화면이
/// 1F로 돌아오는 순간 `IndoorGuidanceSession.position`이 층이 안 맞아 null이 되어
/// 파란 위치 마커가 통째로 사라졌다(schema v16 세션의 position_source=null).
void main() {
  test('목적지 층으로 도면을 펴 놓았어도 앵커 층은 출입구 층이다', () {
    expect(
      gpsEntryAnchorFloor(
        groundEntranceFloor: '1F',
        defaultFloor: '1F',
        viewedFloor: 'B2',
      ),
      '1F',
      reason: '보고 있는 층에 앵커를 찍으면 1F에 선 사람이 B2 그래프에 못 박힌다',
    );
  });

  test('출입구를 못 받은 건물은 기본 층으로 떨어진다', () {
    // 출입구가 안 찍힌 건물은 정상 상황이다(groundEntrancesFrom 주석). 그때
    // 남는 근거는 건물이 스스로 말하는 default_floor 하나다.
    expect(
      gpsEntryAnchorFloor(
        groundEntranceFloor: null,
        defaultFloor: '1F',
        viewedFloor: 'B2',
      ),
      '1F',
    );
  });

  test('근거가 하나도 없으면 보고 있는 층을 그대로 둔다', () {
    // 건물 정보 자체가 아직 안 왔을 때다. 근거 없이 층을 옮기면 보고 있던
    // 도면만 사라지고 나아지는 것이 없다.
    expect(
      gpsEntryAnchorFloor(
        groundEntranceFloor: null,
        defaultFloor: null,
        viewedFloor: 'B2',
      ),
      'B2',
    );
    expect(
      gpsEntryAnchorFloor(
        groundEntranceFloor: null,
        defaultFloor: null,
        viewedFloor: null,
      ),
      isNull,
    );
  });

  test('출입구 층이 지하인 건물은 그 층을 그대로 쓴다', () {
    // 지상 출입구가 B1에 있는 건물(경사지·지하철 연결)이 있을 수 있다. 규칙은
    // "1F로 되돌린다"가 아니라 "문이 있는 층으로 간다"다.
    expect(
      gpsEntryAnchorFloor(
        groundEntranceFloor: 'B1',
        defaultFloor: '1F',
        viewedFloor: '5F',
      ),
      'B1',
    );
  });
}
