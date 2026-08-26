/// 길찾기(출발/도착 칸)의 후보 목록 조립 — 실내 매장·건물·바깥 POI를 어떤 순서로
/// 섞을지가 전부다. 규칙 자체는 domain이 갖고, 여기는 아무것도 저장하지 않는다.
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:latlong2/latlong.dart';

import '../../service_locator.dart';
import '../../domain/store/indoor_store_lookup.dart';
import '../../domain/store/outdoor_poi_ranking.dart';
import '../../models/building/building.dart';
import '../../models/place/outdoor_poi.dart';
import '../../models/place/poi_search_result.dart';
import '../../models/route/directions_candidate.dart';

/// 후보 조립이 야외 지도 상태에서 읽는 값·판정.
///
/// GlobalKey로 얻는 [OutdoorMapBodyState]를 통째로 받지 않고 필요한 세 가지만
/// 받는다 — 후보 조립이 지도 화면의 나머지에 기대기 시작하면 이 파일을 뗀
/// 의미가 없다. 지도가 아직 없으면(미로드) 모두 null로 두고, 그때는 해당 정보
/// 없이 진행한다(바깥 조회 생략, 건물 좌표는 응답 값으로 폴백).
class OutdoorSearchContext {
  const OutdoorSearchContext({
    this.entrancePointFor,
    this.searchCenter,
    this.isAtIndoorBuilding,
  });

  /// 야외 지도가 상세 응답으로 이미 알고 있는 지상 출입구.
  final LatLng? Function(String buildingId)? entrancePointFor;

  /// 바깥 POI 조회의 기준점(현재 위치 또는 카메라 중심).
  final LatLng? searchCenter;

  /// 이 좌표가 우리 실내 데이터가 있는 건물 위인지.
  final bool Function(LatLng point)? isAtIndoorBuilding;
}

/// 1단계의 **실내 몫**과, 바깥 조회가 이어서 쓸 재료.
///
/// 둘을 한 함수로 묶지 않는 이유는 **대기 시간**이다. 바깥 조회(TMAP + 브랜드
/// 되묻기)는 실내 조회보다 훨씬 느린데, 예전에는 그것까지 기다린 뒤에야 후보
/// 목록이 화면에 붙었다. 야외 건물을 검색하면 실내가 빈손이라 화면에 뜰 것이
/// 전적으로 그 느린 경로에 달려 있어, 사용자에게는 **스피너만 도는 화면**으로
/// 보였다. 상단 검색창은 처음부터 둘을 나란히 돌리고 있었다(`SearchPanel._search`).
class IndoorDirectionsCandidates {
  const IndoorDirectionsCandidates({
    required this.rows,
    required this.stores,
    required this.buildingRowNames,
    required this.buildingNames,
    required this.buildingName,
    this.closed = false,
  });

  /// 바로 화면에 붙일 줄들(매장 다음 건물).
  final List<DirectionsCandidate> rows;

  /// 매장 원본. 바깥 줄과 겹치는지 판정하는 데 쓴다.
  final List<PoiSearchResult> stores;

  /// 위 [rows] 중 건물 줄의 이름(축약형). 같은 이름의 바깥 줄을 뺄 때 쓴다.
  final Set<String> buildingRowNames;

  /// 우리가 도면을 가진 건물 전체의 이름.
  final List<String> buildingNames;

  /// 지금 보고 있는 건물의 이름. 매장 줄 부제에 함께 적는다.
  final String? buildingName;

  /// 바깥 조회를 이어 붙일 필요조차 없는 상태(빈 검색어).
  ///
  /// **비어 있는 것으로 대신 판정하지 않는다.** 실내 조회가 실패해도 결과는
  /// 비는데, 그때야말로 바깥 조회가 유일한 답이다 — 비었다는 이유로 건너뛰면
  /// 백엔드가 느린 순간 야외 목적지 검색이 통째로 죽는다.
  final bool closed;
}

/// 1단계(경량 검색)의 실내 몫 — 실내 매장 → 건물 순.
///
/// 바깥 POI는 여기서 조회하지 않는다. 호출자가 이 결과를 **먼저 화면에 붙이고**,
/// [outdoorDirectionsCandidates]를 따로 돌려 도착하는 대로 뒤에 이어 붙인다.
Future<IndoorDirectionsCandidates> searchDirectionsCandidates(
  String query, {
  String? floorId,
  required String buildingId,
  required bool indoorContextActive,
  required OutdoorSearchContext outdoor,
}) async {
  final normalized = query.trim().toLowerCase();

  // 매장 검색은 **항상 건물 전체**를 뒤진다 — 길찾기를 여는 이유 자체가 대개
  // "지금 층에 없는 곳으로 가려고"라, 층으로 좁히면 기본값이 의도의 반대가 된다.
  // [floorId]는 후보를 콕 집은 행동에만 값이 있어 이 규칙을 깨지 않는다.
  //
  // **두 조회의 실패를 각각 삼킨다.** "한강공원"처럼 건물 밖을 찾는 검색은 실내
  // 조회가 어차피 빈손인데, 그 조회가 느려서 터졌다고 바깥 결과까지 잃으면
  // 사용자에게는 야외 목적지 검색이 통째로 죽은 것으로 보인다. 실제로 백엔드가
  // 8초를 못 지켜 그렇게 됐다(상단 검색창은 처음부터 둘을 따로 다뤘다).
  final results = await _indoorStores(buildingId, query, floorId);
  final buildings = await _allBuildings();
  // 매장 줄에 함께 적을 건물 이름. 상단 검색 패널과 같은 규칙이다.
  final buildingName = buildings
      .where((b) => b.id == buildingId)
      .map((b) => b.name)
      .firstOrNull;
  final allBuildingNames = buildings.map((b) => b.name).toList();
  IndoorDirectionsCandidates closed(List<DirectionsCandidate> rows) =>
      IndoorDirectionsCandidates(
        rows: rows,
        stores: const [],
        buildingRowNames: const {},
        buildingNames: const [],
        buildingName: buildingName,
        closed: true,
      );

  // 건물 안에서 **아무것도 안 친** 경우만 여기서 끝낸다. 그때 빈 검색어는
  // "이 건물의 장소 전체 목록"이라는 뜻이고, 그 목록에 바깥 건물을 섞으면
  // 훑어보려던 화면이 지저분해진다.
  if (indoorContextActive && normalized.isEmpty) {
    return closed(results.map((s) => _storeCandidate(s, buildingName)).toList());
  }

  // 밖에서는 **아무것도 안 쳤으면 아무것도 보여주지 않는다.**
  //
  // 그 목록이 "여기서 갈 만한 곳"이 아니라 남의 건물 내부 목록이라, 길찾기를
  // 열자마자 띄우면 치지도 않은 답이 정해져 있는 화면이 된다.
  if (normalized.isEmpty) return closed(const []);

  // **여기부터는 실내·야외를 가리지 않는다.** 실내면 매장만 돌려주던 때는 실내→
  // 야외 안내를 만들어 두고도 그 목적지를 고를 수단이 없었다.
  //
  // 섞어도 안전한 이유는 **순서**다 — 우리 매장 줄이 항상 맨 위라, 바깥이 첫 줄이
  // 되는 것은 실내가 빈손일 때뿐이고 그건 정확히 바깥이 답인 경우다.

  // 건물도 후보로 남기되 매장보다 뒤에 둔다. **좌표는 목록 응답만으로 못 구한다** —
  // `GET /buildings`에는 출입구·외곽선이 없어 야외 지도가 상세로 받아 둔 값을 쓰고,
  // 그마저 없으면 후보에서 뺀다(눌러도 경로가 안 나온다).
  final buildingCandidates = <DirectionsCandidate>[];
  for (final building in buildings) {
    if (!building.name.toLowerCase().contains(normalized)) continue;
    final point = buildingDestinationPoint(building, outdoor);
    if (point == null) continue;
    buildingCandidates.add(
      DirectionsCandidate(
        title: building.name,
        subtitle: '${building.floors.length}개 층',
        point: point,
        // 이 후보가 건물이라는 표시. 목록의 아이콘(건물/핀)이 이 값으로 갈린다.
        buildingId: building.id,
      ),
    );
  }

  // 우리 매장 줄은 **전부** 남기고 건물 줄을 그 뒤에 둔다. 바깥 줄은 이 목록
  // 뒤에 붙는다([outdoorDirectionsCandidates]) — 순서가 곧 안전장치라, 바깥이
  // 첫 줄이 되는 것은 실내가 빈손일 때뿐이고 그건 정확히 바깥이 답인 경우다.
  return IndoorDirectionsCandidates(
    rows: [
      ...results.map((s) => _storeCandidate(s, buildingName)),
      ...buildingCandidates,
    ],
    stores: results,
    buildingRowNames: buildingCandidates
        .map((c) => collapseName(c.title))
        .toSet(),
    buildingNames: allBuildingNames,
    buildingName: buildingName,
  );
}

/// 1단계의 **바깥 몫**. [indoor]가 붙는 자리 뒤에 이어 붙일 줄만 돌려준다.
/// 겹치는 POI는 여기서 빠진다([mergeOutdoorResults]).
///
/// **[indoor]를 Future로 받는 것이 핵심이다.** TMAP 조회를 먼저 띄우고 실내
/// 결과는 **합칠 때만** 기다리므로, 두 조회가 나란히 돈다. 실내를 먼저 await하면
/// 백엔드가 느린 순간 그 시간만큼 바깥 조회가 통째로 밀리고, 야외 목적지 검색은
/// 답이 바깥에만 있어서 그 대기가 그대로 빈 화면이 된다.
///
/// 실내 매장 목록이 되묻기로 **늘어날 수 있다**("더현대 스타벅스" → 브랜드
/// 재조회). 늘어난 매장 줄도 함께 돌려주므로 호출자가 실내 줄을 갈아 끼운다.
///
/// 실패·기준점 없음·TMAP 키 없음은 전부 빈 결과다.
Future<({List<DirectionsCandidate> stores, List<DirectionsCandidate> outdoor})>
outdoorDirectionsCandidates(
  String query, {
  required Future<IndoorDirectionsCandidates> indoor,
  required String buildingId,
  required OutdoorSearchContext outdoor,
}) async {
  const empty = (
    stores: <DirectionsCandidate>[],
    outdoor: <DirectionsCandidate>[],
  );
  final center = outdoor.searchCenter;
  if (query.trim().isEmpty ||
      !outdoorPoiRepository.isAvailable ||
      center == null) {
    return empty;
  }

  final List<OutdoorPoi> pois;
  try {
    pois = await outdoorPoiRepository.searchNearby(query, center: center);
  } on Object catch (error) {
    debugPrint('[route-search] "$query" 바깥 조회 실패: $error');
    return empty;
  }

  // 여기서야 실내를 기다린다. 위 TMAP 왕복과 겹쳐 돌았으므로 둘 중 느린 쪽의
  // 시간만 든다.
  final resolved = await indoor;
  if (resolved.closed) return empty;

  final merged = await _mergeOutdoor(
    query,
    pois,
    resolved.stores,
    resolved.buildingNames,
    buildingId: buildingId,
    outdoor: outdoor,
  );
  return (
    stores: merged.indoorStores
        .map((s) => _storeCandidate(s, resolved.buildingName))
        .toList(),
    outdoor: [
      for (final row in merged.outdoorRows)
        if (!resolved.buildingRowNames.contains(collapseName(row.poi.name)))
          _outdoorRowCandidate(row),
    ],
  );
}

/// 실내 매장 조회. 실패는 **빈 목록**이다 — 부르는 쪽이 바깥 조회를 계속할 수
/// 있어야 한다. 조용히 삼키지 않고 이유를 남긴다: 화면에서는 "그런 매장이 없다"와
/// "못 물어봤다"가 똑같이 보인다.
Future<List<PoiSearchResult>> _indoorStores(
  String buildingId,
  String query,
  String? floorId,
) async {
  try {
    return await destinationRepository.searchDestinations(
      buildingId,
      query,
      currentFloorId: floorId,
    );
  } on Object catch (error) {
    debugPrint('[route-search] "$query" 실내 매장 조회 실패(바깥은 계속한다): $error');
    return const [];
  }
}

/// 건물 목록. 실패하면 빈 목록이라 건물 줄과 겹침 판정만 빠진다.
Future<List<Building>> _allBuildings() async {
  try {
    return await buildingRepository.getAllBuildings();
  } on Object catch (error) {
    debugPrint('[route-search] 건물 목록 조회 실패(바깥은 계속한다): $error');
    return const [];
  }
}

/// 2단계(의미 검색). 경량이 빈손일 때만 부르고, 층은 넘기지 않는다(백엔드도
/// 건물 전체를 본다). 실패는 빈 목록으로 삼킨다 — 오류 화면으로 덮어도 사용자가
/// 할 수 있는 일이 늘지 않는다.
Future<List<DirectionsCandidate>> semanticDirectionsCandidates(
  String query, {
  required String buildingId,
}) async {
  try {
    final discovery = await destinationRepository.searchDestinationsAi(
      buildingId,
      query,
    );
    return discovery.matches
        .map(
          (m) => DirectionsCandidate(
            title: m.name,
            subtitle: m.floorName,
            point: m.point,
            nodeId: m.entranceNodeId,
            floor: m.floorName,
            reason: m.reason,
          ),
        )
        .toList();
  } on Object {
    return const [];
  }
}

/// "이 건물까지" 안내할 때의 도착 좌표. **지상 출입구**를 우선한다 — 건물 중심을
/// 주면 TMAP이 아무 도로로나 스냅해 들어갈 수 없는 면에 내려놓는다.
/// 없으면 [Building.outdoorAnchor]로, 그것도 없으면 null.
LatLng? buildingDestinationPoint(
  Building building,
  OutdoorSearchContext outdoor,
) {
  return outdoor.entrancePointFor?.call(building.id) ?? building.outdoorAnchor;
}

/// 매장 하나를 후보로 만든다. [buildingName]을 주면 부제에 함께 적는다.
///
/// "스타벅스 리저브 / B2"만으로는 어느 건물의 스타벅스인지 알 수 없다. 밖에서
/// 검색하면 길 건너 스타벅스도 함께 뜨고 그쪽에는 주소가 적혀 있어, 정작
/// 실내까지 안내되는 우리 줄만 층 하나로 남아 가장 안 읽혔다.
DirectionsCandidate _storeCandidate(
  PoiSearchResult store, [
  String? buildingName,
]) => DirectionsCandidate(
  title: store.name,
  subtitle: buildingName == null
      ? store.floor
      : '$buildingName · ${store.floor}',
  point: store.point,
  nodeId: store.nodeId,
  floor: store.floor,
);

/// 바깥 줄 하나를 후보로 만든다.
///
/// 여기까지 온 POI는 우리가 모르는 곳이다 — 우리 실내 데이터가 아는 가게를
/// 가리키는 POI는 목록을 만들 때 이미 빠진다([mergeOutdoorResults]).
DirectionsCandidate _outdoorRowCandidate(OutdoorSearchRow row) =>
    DirectionsCandidate(
      title: row.poi.name,
      subtitle: row.poi.address ?? '건물 밖 장소',
      point: row.poi.point,
    );

/// 이미 받아 둔 바깥 [pois]를 우리 실내 결과와 합친다.
///
/// **조회는 여기서 하지 않는다** — 부르는 쪽이 실내 조회와 나란히 먼저 띄운다
/// ([outdoorDirectionsCandidates]).
Future<MergedOutdoorResults> _mergeOutdoor(
  String query,
  List<OutdoorPoi> pois,
  List<PoiSearchResult> indoorStores,
  List<String> buildingNames, {
  required String buildingId,
  required OutdoorSearchContext outdoor,
}) async {
  // 규칙은 도메인 함수가 갖고 있다(`domain/outdoor_poi_ranking.dart`).
  // 상단 검색 패널도 같은 함수를 부른다 — 여기서 다시 구현하면 또 갈린다.
  final relevant = filterByNameRelevance(query, pois);
  bool isAtBuilding(OutdoorPoi poi) =>
      outdoor.isAtIndoorBuilding?.call(poi.point) ?? false;

  // 사용자가 친 말로 우리 매장을 못 찾았을 수 있다("더현대 스타벅스" →
  // no_match). 그 경우 POI 이름의 브랜드로 한 번 더 묻는다 — 안 하면 겹침을
  // 판정할 대상이 없어 TMAP 줄이 그대로 남고, 그 줄에는 층·노드가 없다.
  final enrichedStores = await lookUpIndoorStoresByBrand(
    pois: relevant,
    indoorStores: indoorStores,
    isAtBuilding: isAtBuilding,
    buildingNames: buildingNames,
    // 되묻기 실패는 그 브랜드만 건너뛴다([lookUpIndoorStoresByBrand]). 백엔드가
    // 느려 터지는 상황에서도 바깥 줄은 그대로 남아야 한다.
    search: (brand) =>
        destinationRepository.searchDestinations(buildingId, brand),
  );

  final merged = mergeOutdoorResults(
    pois: relevant,
    indoorStores: enrichedStores,
    isAtBuilding: isAtBuilding,
    buildingNames: buildingNames,
  );
  // **중복 제거 결과를 로그로 남긴다.** 화면에서는 "겹쳐서 뺐다"와 "원래
  // 한 줄이었다"가 똑같이 보여서, 규칙이 통째로 안 도는 것을 눈으로 구분할
  // 수 없다. 실제로 이 자리를 세 번 잘못 짚었다.
  final dropped = pois.length - merged.outdoorRows.length;
  debugPrint(
    '[poi-merge] "$query" 바깥 ${pois.length}건 중 $dropped건이 '
    '우리 매장과 겹쳐 빠짐 (실내 후보 ${enrichedStores.length}건, '
    '건물 이름 $buildingNames)',
  );
  return merged;
}
