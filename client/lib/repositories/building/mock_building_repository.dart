import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:latlong2/latlong.dart';

import '../../models/building/building.dart';
import '../../models/building/building_graph.dart';
import '../../models/building/category_count.dart';
import '../../models/place/store_index_entry.dart';
import '../../models/building/floor_plan.dart';
import '../../models/route/indoor_route.dart';
import 'building_repository.dart';

/// api/app/data/sample_building.json과 동일한 형태를 assets/mock/sample_building.json에
/// 미러링해두고 읽는다. 백엔드가 준비되면 [HttpBuildingRepository]로 교체한다.
class MockBuildingRepository implements BuildingRepository {
  MockBuildingRepository({this.assetPath = 'assets/mock/sample_building.json'});

  final String assetPath;
  Map<String, dynamic>? _cache;

  Future<Map<String, dynamic>> _load() async {
    final cached = _cache;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    _cache = decoded;
    return decoded;
  }

  /// 목업에는 행사가 없다. 화면은 이 값으로 "아직 안 모은 건물"과 같은 길을
  /// 탄다 — 판이 아예 안 뜨고 조용하다.
  @override
  Future<Map<String, dynamic>?> getBuildingEvents(String buildingId) async =>
      null;

  @override
  Future<List<Building>> getAllBuildings() async {
    final data = await _load();
    return [Building.fromJson(data)];
  }

  @override
  Future<Building?> getBuilding(String buildingId) async {
    final data = await _load();
    if (data['id'] != buildingId) return null;
    return Building.fromJson(data);
  }

  @override
  Future<Map<String, dynamic>?> getFloorGeoJson(
    String buildingId,
    String floor,
  ) async {
    final data = await _load();
    if (data['id'] != buildingId) return null;
    final floorData = data['floor_data'] as Map<String, dynamic>;
    final geojson = floorData[floor];
    return geojson == null ? null : geojson as Map<String, dynamic>;
  }

  /// 목업은 전용 응답이 없으므로 층 지도에서 직접 센다. 서버가 GROUP BY로
  /// 접어 주는 것과 같은 결과를 만들면 되고, 목업은 층이 몇 개뿐이라 비용도
  /// 문제되지 않는다.
  @override
  Future<List<CategoryCount>?> getCategoryCounts(String buildingId) async {
    final data = await _load();
    if (data['id'] != buildingId) return null;

    // 키를 문자열로 이어 붙이지 않고 레코드로 둔다. 문자열 키는 되쪼갤 때
    // 분류 이름에 든 구분자(`TAX REFUND`의 공백 같은)에서 조각이 어긋난다.
    final counts =
        <({String floor, String category, String? subcategory}), int>{};
    final floorData = data['floor_data'] as Map<String, dynamic>;
    for (final entry in floorData.entries) {
      final plan = FloorPlan.fromJson(entry.value as Map<String, dynamic>);
      for (final store in plan.stores) {
        final category = store.category;
        if (category == null || category.isEmpty) continue;
        counts.update(
          (
            floor: entry.key,
            category: category,
            subcategory: store.subcategory,
          ),
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
    }

    return counts.entries
        .map(
          (entry) => CategoryCount(
            floor: entry.key.floor,
            category: entry.key.category,
            subcategory: entry.key.subcategory,
            count: entry.value,
          ),
        )
        .toList();
  }

  @override
  Future<List<StoreIndexEntry>?> getStoreIndex(String buildingId) async {
    final data = await _load();
    if (data['id'] != buildingId) return null;

    // 목업 자산은 층 도면만 갖고 있어 매장 id를 따로 주지 않는다. 자동완성은
    // 이름으로 다시 검색하는 흐름이라(StoreIndexEntry 주석) id를 키로 쓰지
    // 않으므로, 층·이름을 합친 값으로 채워 유일성만 맞춘다.
    final entries = <StoreIndexEntry>[];
    final floorData = data['floor_data'] as Map<String, dynamic>;
    for (final entry in floorData.entries) {
      final plan = FloorPlan.fromJson(entry.value as Map<String, dynamic>);
      for (final store in plan.stores) {
        entries.add(
          StoreIndexEntry(
            id: '${entry.key}/${store.name}',
            name: store.name,
            floorId: entry.key,
            floorName: entry.key,
            category: store.category,
            subcategory: store.subcategory,
            entranceNodeId: store.entranceNodeId,
          ),
        );
      }
    }
    return entries;
  }

  @override
  Future<IndoorRoute?> getShortestRoute(
    String buildingId,
    String floor,
    String startNodeId,
    String endNodeId,
  ) async {
    // mock 데이터엔 그래프가 없다. 매장의 entranceNodeId로 두 지점을 찾아
    // 직선으로 잇는 정도로만 흉내 낸다 (실제 다익스트라 그래프는 백엔드에서만 존재).
    final geojson = await getFloorGeoJson(buildingId, floor);
    if (geojson == null) return null;

    final floorPlan = FloorPlan.fromJson(geojson);
    final start = _findEntrance(floorPlan, startNodeId);
    final end = _findEntrance(floorPlan, endNodeId);
    if (start == null || end == null) return null;

    return IndoorRoute(
      points: [start, end],
      distanceMeters: wgs84DistanceMeters(start, end),
    );
  }

  LatLng? _findEntrance(FloorPlan floorPlan, String nodeId) {
    for (final store in floorPlan.stores) {
      if (store.entranceNodeId == nodeId) return store.centroid;
    }
    return null;
  }

  @override
  Future<BuildingGraph?> getBuildingGraph(
    String buildingId, {
    String vertical = 'auto',
  }) async {
    // mock 데이터엔 층 간 그래프가 없다. 층 간 경로 기능은 HTTP 리포지토리로만
    // 검증한다 — mock에서 null을 돌려주면 호출자가 단일 층 경로로 폴백한다.
    return null;
  }
}
