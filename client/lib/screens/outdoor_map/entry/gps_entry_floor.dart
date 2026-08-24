/// GPS 자동 실내 진입에서 **앵커를 찍을 층**을 고르는 순수 로직.
///
/// "지금 보고 있는 층"과 "이 사람이 서 있는 층"은 다른 값이다. 목적지를 고르는
/// 것만으로 도면은 그 층으로 갈리는데(미리보기는 기능이다), 그 층을 앵커 층까지
/// 쓰면 지상 입구로 들어온 사람이 지하 그래프에 못 박힌다.
///
/// 검증 기준은 test/screens/outdoor_map/entry/gps_entry_floor_test.dart.
library;

/// 진입 근거가 가리키는 층. 근거가 하나도 없으면 null.
///
/// GPS 판정으로 건물 안이 된 사람은 **지상 출입구를 지났다.** 그 사실이
/// 목적지보다 강한 근거다. 근거를 센 순서가 이 함수의 전부다.
///
/// 1. [groundEntranceFloor] — 지상 출입구 목록을 추려 온 층. 그 목록이 곧
///    "걸어 들어올 수 있는 문"이라, 문을 지난 사람이 서 있는 층이 이 층이다.
/// 2. [defaultFloor] — 건물 `default_floor`. 출입구를 못 받은 건물의 폴백.
/// 3. [viewedFloor] — 둘 다 없을 때만. 여기까지 왔다는 것은 근거가 없다는
///    뜻이고, 근거 없이 층을 옮기면 보고 있던 도면만 사라진다.
///
/// **목적지 층은 세지 않는다.** 목적지는 "가려는 곳"이지 "서 있는 곳"이 아닌데,
/// B2 매장을 찍고 1F로 들어온 사람의 앵커가 B2에 찍혀 있었다. 그 뒤 화면이 1F로
/// 돌아오면 `IndoorGuidanceSession.position`이 층이 안 맞아 null이 되어 위치
/// 마커가 통째로 사라진다 — 실측 세션(schema v16)에 `position_source = null`로
/// 남은 그 화면이다.
String? gpsEntryAnchorFloor({
  required String? groundEntranceFloor,
  required String? defaultFloor,
  required String? viewedFloor,
}) => groundEntranceFloor ?? defaultFloor ?? viewedFloor;
