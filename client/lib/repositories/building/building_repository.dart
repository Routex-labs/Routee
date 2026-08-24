import '../../models/building/building.dart';
import '../../models/building/building_graph.dart';
import '../../models/building/category_count.dart';
import '../../models/route/indoor_route.dart';
import '../../models/place/store_index_entry.dart';

abstract class BuildingRepository {
  Future<List<Building>> getAllBuildings();

  Future<Building?> getBuilding(String buildingId);

  Future<Map<String, dynamic>?> getFloorGeoJson(
    String buildingId,
    String floor,
  );

  /// 카테고리 필터가 쓰는 (층·대분류·소분류)별 매장 수. 건물이 없으면 null.
  ///
  /// 층 지도를 층마다 받아 세지 않기 위한 전용 조회다 — 근거는
  /// [CategoryCount] 주석.
  Future<List<CategoryCount>?> getCategoryCounts(String buildingId);

  /// 자동완성이 쓰는 경량 매장 목록. 건물이 없으면 null.
  ///
  /// 앱에서 건물당 1회만 받아 온디바이스 후보 산출의 원본으로 쓴다. 좌표가
  /// 빠져 있는 이유는 [StoreIndexEntry] 주석에 있다.
  Future<List<StoreIndexEntry>?> getStoreIndex(String buildingId);

  /// 그 건물에서 열리는 행사 한 벌(쪽 + 행사). **모아 둔 것이 없으면 null**이다 —
  /// 빈 목록으로 내려오면 "행사가 없는 건물"과 "아직 안 모은 건물"이 같은 화면이
  /// 된다. 서버 계약은 `backend/docs/api/contract.md`의 "행사" 절.
  ///
  /// 날짜로 좁히지 않은 통짜를 받는다 — 오늘 열리는지는 서버가 아니라 화면이
  /// 기기 로컬 날짜로 판정한다([BuildingEvents.openOn]).
  Future<Map<String, dynamic>?> getBuildingEvents(String buildingId);

  /// 두 노드 사이 최단 경로. 경로가 없거나 층/노드를 찾을 수 없으면 null.
  Future<IndoorRoute?> getShortestRoute(
    String buildingId,
    String floor,
    String startNodeId,
    String endNodeId,
  );

  /// 건물 전체 길찾기 그래프(전 층 노드 + 층 내부 간선 + 수직 전이 간선).
  /// 층 간 경로 계산의 입력이며, 건물이 없으면 null.
  Future<BuildingGraph?> getBuildingGraph(
    String buildingId, {
    String vertical = 'auto',
  });
}
