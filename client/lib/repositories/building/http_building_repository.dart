import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/api_config.dart';
import '../../domain/route/corridor_shortcuts.dart';
import '../../domain/route/corridor_shortcuts_data.dart';
import '../../domain/route/entrance_door_nodes.dart';
import '../../domain/route/floor_router.dart';
import '../../models/building/building.dart';
import '../../models/building/building_graph.dart';
import '../../models/building/category_count.dart';
import '../../models/building/floor_graph.dart';
import '../../models/building/floor_plan.dart';
import '../../models/route/indoor_route.dart';
import '../../models/place/store_index_entry.dart';
import 'building_repository.dart';

/// `/buildings` 엔드포인트를 호출하고 응답을 메모리에 캐싱한다.
///
/// **값이 아니라 Future를 캐시한다.** 값을 캐시하면 `await`가 끝나야 채워져서,
/// 그 사이 호출은 전부 미스로 각자 네트워크를 탄다 — 이 앱은 세 화면이 **같은
/// 프레임에** 같은 층을 불러 그 창이 항상 열린다(실측 645건 중 `/floors`가 130건,
/// 상당수가 같은 초에 몰린 중복). Future를 넣어 두면 요청 수가 "동시 호출자 수"가
/// 아니라 "서로 다른 리소스 수"로 떨어진다.
class HttpBuildingRepository implements BuildingRepository {
  HttpBuildingRepository({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<Building>>? _allBuildingsFuture;
  final Map<String, Future<Building?>> _buildingFutures = {};
  final Map<String, Future<Map<String, dynamic>?>> _floorGeoJsonFutures = {};
  final Map<String, Future<BuildingGraph?>> _buildingGraphFutures = {};
  final Map<String, Future<List<CategoryCount>?>> _categoryCountFutures = {};
  final Map<String, Future<List<StoreIndexEntry>?>> _storeIndexFutures = {};
  final Map<String, Future<Map<String, dynamic>?>> _eventFutures = {};

  // 아래 둘은 네트워크가 아니라 계산 결과라 값 캐시로 충분하다.
  final Map<String, FloorGraph> _floorGraphCache = {};
  final Map<String, IndoorRoute> _routeCache = {};

  /// 진행 중인 요청을 공유한다. 같은 키면 떠 있는 Future를 그대로 돌려준다.
  ///
  /// **실패와 404는 캐시에 남기지 않는다** — 전자는 잠깐 끊긴 순간이 영구 실패로
  /// 굳어 재시도 버튼이 같은 예외만 받고, 후자는 나중에 생긴 데이터를 영영 못 찾는다.
  /// 둘 다 Future가 **끝난 뒤에** 지우므로 동시 호출을 합치는 효과는 남는다.
  Future<T> _shared<T>(
    Map<String, Future<T>> cache,
    String key,
    Future<T> Function() fetch,
  ) {
    final inflight = cache[key];
    if (inflight != null) return inflight;

    final future = fetch();
    cache[key] = future;
    // 결과를 삼키는 파생 Future로 감시만 한다. 여기서 다시 throw하면 아무도
    // 기다리지 않는 Future의 미처리 예외가 되므로 던지지 않는다 — 호출자에게는
    // 원본 future가 그대로 값·예외를 전달한다.
    unawaited(
      future.then(
        (value) {
          if (value == null) _evict(cache, key, future);
        },
        onError: (Object error, StackTrace stackTrace) {
          _evict(cache, key, future);
        },
      ),
    );
    return future;
  }

  /// 그 사이 같은 키로 새 요청이 시작됐으면 건드리지 않는다.
  void _evict<T>(Map<String, Future<T>> cache, String key, Future<T> future) {
    if (identical(cache[key], future)) cache.remove(key);
  }

  @override
  Future<List<Building>> getAllBuildings() {
    return _allBuildingsFuture ??= _fetchAllBuildings();
  }

  Future<List<Building>> _fetchAllBuildings() async {
    try {
      final response = await _client.get(Uri.parse('$apiBaseUrl/buildings'));
      final list = jsonDecode(response.body) as List<dynamic>;
      final buildings = list
          .map((item) => Building.fromJson(item as Map<String, dynamic>))
          .toList();

      // **목록 응답으로 개별 조회 캐시를 채우지 않는다.** 목록에는 `tile_revision`이
      // 없어서, 채우면 [getBuilding]이 버전 없는 Building을 돌려준다 — 타일 URL에
      // `?v=`가 안 붙고 서버가 `immutable` 대신 `max-age=60`을 준다(실측).
      // 검색 한 번이 그 뒤의 모든 층 전환을 느리게 만들었다.
      return buildings;
    } catch (_) {
      _allBuildingsFuture = null; // 재시도 가능하게 (위 _shared와 같은 이유)
      rethrow;
    }
  }

  @override
  Future<Building?> getBuilding(String buildingId) {
    return _shared(_buildingFutures, buildingId, () async {
      final response = await _client.get(
        Uri.parse('$apiBaseUrl/buildings/$buildingId'),
      );
      if (response.statusCode == 404) return null;
      return Building.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    });
  }

  @override
  Future<List<CategoryCount>?> getCategoryCounts(String buildingId) {
    return _shared(_categoryCountFutures, buildingId, () async {
      final response = await _client.get(
        Uri.parse('$apiBaseUrl/buildings/$buildingId/categories'),
      );
      if (response.statusCode == 404) return null;
      final list = jsonDecode(response.body) as List<dynamic>;
      return list
          .map((item) => CategoryCount.fromJson(item as Map<String, dynamic>))
          .toList();
    });
  }

  @override
  Future<List<StoreIndexEntry>?> getStoreIndex(String buildingId) {
    return _shared(_storeIndexFutures, buildingId, () async {
      final response = await _client.get(
        Uri.parse('$apiBaseUrl/buildings/$buildingId/store-index'),
      );
      if (response.statusCode == 404) return null;
      final list = jsonDecode(response.body) as List<dynamic>;
      return list
          .map((item) => StoreIndexEntry.fromJson(item as Map<String, dynamic>))
          .toList();
    });
  }

  @override
  Future<Map<String, dynamic>?> getBuildingEvents(String buildingId) {
    return _shared(_eventFutures, buildingId, () async {
      final response = await _client.get(
        Uri.parse('$apiBaseUrl/buildings/$buildingId/events'),
      );
      if (response.statusCode == 404) return null;
      return jsonDecode(response.body) as Map<String, dynamic>;
    });
  }

  @override
  Future<Map<String, dynamic>?> getFloorGeoJson(
    String buildingId,
    String floor,
  ) {
    final cacheKey = '$buildingId/$floor';
    return _shared(_floorGeoJsonFutures, cacheKey, () async {
      final response = await _client.get(
        Uri.parse('$apiBaseUrl/buildings/$buildingId/floors/$floor'),
      );
      if (response.statusCode == 404) return null;

      final geojson = jsonDecode(response.body) as Map<String, dynamic>;
      final navigationGraph =
          geojson['navigation_graph'] as Map<String, dynamic>?;

      // /floors/{floor}는 매장 폴리곤이 없는(점 정보만 있는) 건물에서는 지도가
      // 텅 비어 보인다. 응답에 함께 내려오는 navigation_graph의 간선 geometry를
      // 복도선으로 얹어서 FloorPlan._fromApiResponse가 그대로 그릴 수 있게 한다.
      final corridors = _corridorsFromNavigationGraph(navigationGraph);
      if (corridors != null) geojson['corridors_local_m'] = corridors;

      // navigation_graph가 이 응답에 이미 포함돼 있으므로, 최단 경로 계산용
      // nodes/edges도 여기서 함께 캐싱해둔다 — getShortestRoute가 별도로
      // /floors/{floor}/graph를 다시 호출하지 않게 하기 위함이다.
      // 출구 문 노드도 **여기서** 꿰맨다. 이 응답 하나에 그래프와 출구가 함께
      // 있어 추가 요청이 0이고, 화면이 따로 파싱하는 FloorGraph(지도 매칭·복도
      // 추적용)와는 다른 인스턴스라 스냅 동작에 영향이 없다.
      if (navigationGraph != null) {
        // 지름길은 출구 문 노드와 달리 **화면 쪽 FloorGraph에도 같이 들어가야
        // 한다**(corridor_shortcuts.dart 머리말). 여기서만 얹으면 경로선은
        // 대각선인데 복도 추적은 그 간선을 몰라 마커가 ㄱ자에 남는다.
        _floorGraphCache[cacheKey] = floorGraphWithEntranceDoors(
          floorGraphWithCorridorShortcuts(
            FloorGraph.fromJson(navigationGraph),
            kCorridorShortcuts,
            buildingId: buildingId,
            floorName: floor,
          ),
          FloorPlan.fromJson(geojson),
        );
      }
      return geojson;
    });
  }

  List<List<dynamic>>? _corridorsFromNavigationGraph(
    Map<String, dynamic>? navigationGraph,
  ) {
    if (navigationGraph == null) return null;

    final edges = (navigationGraph['edges'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    return edges
        .map((edge) => edge['geometry_local_m'] as List<dynamic>? ?? const [])
        .where((points) => points.length >= 2)
        .toList();
  }

  @override
  Future<IndoorRoute?> getShortestRoute(
    String buildingId,
    String floor,
    String startNodeId,
    String endNodeId,
  ) async {
    final cacheKey = '$buildingId/$floor/$startNodeId/$endNodeId';
    final cached = _routeCache[cacheKey];
    if (cached != null) return cached;

    // 다익스트라 입력(nodes+edges)은 별도 /graph 엔드포인트가 아니라
    // /floors/{floor} 응답의 navigation_graph에서만 얻는다. 아직 그 응답을
    // 받은 적이 없으면(캐시 미스) getFloorGeoJson이 한 번 받아와 채워준다 —
    // 이미 캐시돼 있으면 getFloorGeoJson 자체가 네트워크를 타지 않는다.
    final graphCacheKey = '$buildingId/$floor';
    var graph = _floorGraphCache[graphCacheKey];
    if (graph == null) {
      await getFloorGeoJson(buildingId, floor);
      graph = _floorGraphCache[graphCacheKey];
    }
    if (graph == null) return null;

    // 다익스트라는 그래프에 없는 노드 ID를 ArgumentError로 거부한다(백엔드가
    // 이 경우를 400으로 응답하던 것과 동일하게 "경로 없음"으로 단순화한다).
    IndoorRoute? route;
    try {
      route = computeShortestRoute(graph, startNodeId, endNodeId);
    } on ArgumentError {
      return null;
    }
    if (route == null) return null;

    _routeCache[cacheKey] = route;
    return route;
  }

  @override
  Future<BuildingGraph?> getBuildingGraph(
    String buildingId, {
    String vertical = 'auto',
  }) {
    return _shared(_buildingGraphFutures, '$buildingId/$vertical', () async {
      final response = await _client.get(
        Uri.parse('$apiBaseUrl/buildings/$buildingId/graph?vertical=$vertical'),
      );
      if (response.statusCode == 404) return null;
      final graph = BuildingGraph.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
      return _withEntranceDoors(buildingId, graph);
    });
  }

  /// 지상 출구의 문 노드를 꿰맨 그래프. 출구를 못 얻으면 [graph] 그대로.
  ///
  /// 출구는 지상 기본 층 도면에서만 추려지므로 그 층 응답이 필요하다. 둘 다
  /// 이미 캐시하는 접근자를 그대로 쓴다 — 야외 안내 흐름에서는 그때 이미 받아
  /// 둔 값이라 네트워크가 늘지 않는다. **실패하면 꿰매지 않고 원본을 돌려준다**:
  /// 출구 데이터를 못 받았다고 층 간 길찾기까지 죽으면 안 된다.
  Future<BuildingGraph> _withEntranceDoors(
    String buildingId,
    BuildingGraph graph,
  ) async {
    try {
      final floor = (await getBuilding(buildingId))?.initialFloor;
      if (floor == null) return graph;
      final geojson = await getFloorGeoJson(buildingId, floor);
      if (geojson == null) return graph;
      return buildingGraphWithEntranceDoors(graph, FloorPlan.fromJson(geojson));
    } catch (_) {
      return graph;
    }
  }
}
