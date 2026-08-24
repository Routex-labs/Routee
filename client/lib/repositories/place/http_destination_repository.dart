import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../core/api_config.dart';
import '../../models/place/discovery_result.dart';
import '../../models/place/poi_search_result.dart';
import 'destination_repository.dart';

/// api/app/routers/query.py의 POST /query/destination·/query/ai를 호출한다.
///
/// **두 엔드포인트는 응답 계약이 다르다.** `/query/destination`은 최적 매장
/// 1건만 돌려주는 DestinationResponse이고(app/dto/query.py), `/query/ai`는
/// mode + 질문/선택지 + 여러 후보를 담는 DiscoveryResponse다(설계:
/// docs/native/conversational-discovery.md 8-3절). 예전에는 두 계약이
/// 같아서 [_query] 하나로 파싱을 공유했지만, 지금은 분리한다 — 하나를 고치면
/// 다른 하나가 조용히 깨지는 걸 막기 위해서다.
///
/// `/query/destination`은 매칭 최적 1건만 돌려주므로(app/repositories/
/// query_search.py의 _rank가 tier+level+id로 정렬 후 첫 번째), [_query]가
/// 돌려주는 리스트는 최대 원소 1개 또는 빈 리스트가 된다.
class HttpDestinationRepository implements DestinationRepository {
  HttpDestinationRepository({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  /// 응답 스키마는 app/dto/query.py의 DestinationResponse와 정확히 맞춘다:
  ///   { "status": "ok" | "ok_no_route" | "no_match",
  ///     "query": "...",
  ///     "match": { store_id, name, category, subcategory, floor_id,
  ///                floor_name, entrance_node_id, centroid_local_m,
  ///                centroid_wgs84 } | null }
  @override
  Future<List<PoiSearchResult>> searchDestinations(
    String buildingId,
    String query, {
    String? currentFloorId,
  }) =>
      _query('destination', buildingId, query, currentFloorId: currentFloorId);

  Future<List<PoiSearchResult>> _query(
    String endpoint,
    String buildingId,
    String query, {
    String? currentFloorId,
  }) async {
    // 백엔드는 text.min_length=1을 강제해 빈 문자열이면 422를 낸다. 시트를
    // 처음 열 때(_search('')) 등 정상 흐름에서도 빈 쿼리가 들어오므로,
    // HTTP를 아예 태우지 않고 조용히 빈 결과를 돌려준다.
    if (query.trim().isEmpty) return const [];

    // 상한을 두는 이유는 [searchRequestTimeout]에 있다 — 없으면 멎은 소켓 하나가
    // 화면의 「찾는 중」을 영구히 붙든다. 초과는 예외라 호출자의 실패 경로를 탄다.
    final response = await _client
        .post(
          Uri.parse('$apiBaseUrl/query/$endpoint'),
          headers: const {'Content-Type': 'application/json; charset=utf-8'},
          body: utf8.encode(
            jsonEncode({
              'text': query,
              'building_id': buildingId,
              'current_floor_id': ?currentFloorId,
            }),
          ),
        )
        .timeout(searchRequestTimeout);

    // 건물이 없거나(404) 검증 실패(422) 등은 검색 UX 관점에서 "결과 없음"과
    // 같아서 그대로 빈 리스트를 돌려준다 — 시트가 계속 뜨도록 예외를 던지지
    // 않는다. 다른 5xx는 진짜 서버 장애이므로 호출자에게 전파한다.
    if (response.statusCode == 404 || response.statusCode == 422) {
      return const [];
    }
    if (response.statusCode >= 500) {
      throw http.ClientException(
        '$endpoint query failed: ${response.statusCode}',
        response.request?.url,
      );
    }

    final body =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final match = body['match'];
    if (match is! Map<String, dynamic>) return const [];

    // 서버는 centroid_wgs84가 null일 수 있다(건물에 실측 wgs84 앵커가 없어
    // GeoTransform을 못 피팅할 때 — thehyundai-seoul은 합성 앵커로 항상
    // 값이 있지만, 다른 건물이 붙었을 때 폴백을 지도 위 (0,0)으로 튀지
    // 않게 걸러낸다). 지도에 놓을 자리가 없으면 결과에서 뺀다.
    final centroidWgs84 = match['centroid_wgs84'];
    if (centroidWgs84 is! Map<String, dynamic>) return const [];
    final lat = (centroidWgs84['lat'] as num?)?.toDouble();
    final lng = (centroidWgs84['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return const [];

    return [
      PoiSearchResult(
        name: match['name'] as String,
        // 백엔드는 UI에 보여줄 층 라벨을 floor_name으로 준다(예: "B2").
        // Floor 테이블의 name 컬럼과 일치하므로 클라이언트가 이 값 그대로
        // 층 선택·필터에 쓸 수 있다.
        floor: match['floor_name'] as String,
        point: LatLng(lat, lng),
        // 매장 상세 조회 키. 서버가 QueryMatch.store_id로 늘 내려주지만,
        // 계약이 바뀌어 빠지더라도 검색 자체는 계속 동작해야 하므로
        // 캐스팅은 nullable로 둔다(상세만 조용히 비는 쪽이 안전하다).
        placeId: match['store_id'] as String?,
        // 온디바이스 다익스트라의 도착 노드. status == "ok_no_route"면
        // 서버가 이 필드를 null로 준다(입구 노드가 아직 스냅되지 않은
        // 매장) — 그 경우엔 nodeId 없이 후보만 노출하고 실제 경로 계산은
        // 시도되지 않게 둔다.
        nodeId: match['entrance_node_id'] as String?,
        category: match['category'] as String?,
        subcategory: match['subcategory'] as String?,
      ),
    ];
  }

  /// `POST /query/ai` — 탐색(Discovery) 질의. 경량 1차 확정 → facet 해석 →
  /// FAISS 의미 검색까지의 결과를 mode 기반 계약(DiscoveryResponse)으로
  /// 받는다. [_query]와 파싱을 공유하지 않는다 — 계약 자체가 다르다(위 클래스
  /// 주석 참고).
  @override
  Future<DiscoveryResult> searchDestinationsAi(
    String buildingId,
    String query, {
    String? currentFloorId,
    Map<String, List<String>>? selectedFacets,
    bool showAll = false,
  }) async {
    // 백엔드는 text.min_length=1을 강제해 빈 문자열이면 422를 낸다. HTTP를
    // 아예 태우지 않고 조용히 "빈 결과"와 같은 no_match를 돌려준다.
    if (query.trim().isEmpty) {
      return DiscoveryResult(mode: DiscoveryMode.noMatch, query: query);
    }

    // 의미 검색은 모델 로드로 첫 한 번이 느리므로 상한을 넉넉히 잡는다.
    // 그래도 상한 자체는 있어야 한다 — 근거는 [searchRequestTimeout].
    final response = await _client
        .post(
          Uri.parse('$apiBaseUrl/query/ai'),
          headers: const {'Content-Type': 'application/json; charset=utf-8'},
          body: utf8.encode(
            jsonEncode({
              'text': query,
              'building_id': buildingId,
              'current_floor_id': ?currentFloorId,
              'selected_facets': ?selectedFacets,
              'show_all': showAll,
            }),
          ),
        )
        .timeout(searchRequestTimeout * 3);

    // 건물이 없거나(404) 검증 실패(422)는 검색 UX 관점에서 "결과 없음"과
    // 같다 — 예외를 던지지 않고 no_match로 흡수한다. 다른 5xx는 진짜 서버
    // 장애이므로 호출자에게 전파한다.
    if (response.statusCode == 404 || response.statusCode == 422) {
      return DiscoveryResult(mode: DiscoveryMode.noMatch, query: query);
    }
    if (response.statusCode >= 500) {
      throw http.ClientException(
        'ai query failed: ${response.statusCode}',
        response.request?.url,
      );
    }

    final body =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return _parseDiscoveryResponse(body);
  }

  /// 응답 스키마는 app/dto/query.py의 DiscoveryResponse와 정확히 맞춘다:
  ///   { "mode": "direct"|"clarify"|"results"|"no_match"|"degraded",
  ///     "query": "...", "question": "..."?,
  ///     "options": [{facet,value,label,count}],
  ///     "matches": [{...QueryMatch 필드, matched_facets, reason}] }
  DiscoveryResult _parseDiscoveryResponse(Map<String, dynamic> body) {
    final options = ((body['options'] as List<dynamic>?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(DiscoveryOption.fromJson)
        .toList();

    final matches = ((body['matches'] as List<dynamic>?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(_parseDiscoveryMatch)
        .whereType<DiscoveryMatch>()
        .toList();

    return DiscoveryResult(
      mode: DiscoveryMode.fromWire(body['mode'] as String),
      query: body['query'] as String,
      // 구버전 서버에는 이 키가 없다. nullable로 읽어 unknown으로 떨어뜨린다 —
      // 캐스팅을 non-null로 두면 배포 순서가 어긋난 순간 검색이 통째로 죽는다.
      source: DiscoverySource.fromWire(body['source'] as String?),
      question: body['question'] as String?,
      options: options,
      matches: matches,
    );
  }

  /// 지도에 놓을 실좌표가 없는 매장(centroid_wgs84 null)은 [_query]와 같은
  /// 정책으로 걸러낸다 — 건물에 wgs84 앵커가 없을 때 지도 위 (0,0)으로 튀지
  /// 않도록 한다. 반환이 null이면 호출자가 이 후보를 목록에서 제외한다.
  DiscoveryMatch? _parseDiscoveryMatch(Map<String, dynamic> match) {
    final centroidWgs84 = match['centroid_wgs84'];
    if (centroidWgs84 is! Map<String, dynamic>) return null;
    final lat = (centroidWgs84['lat'] as num?)?.toDouble();
    final lng = (centroidWgs84['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;

    // matched_facets는 null(태그 근거가 없는 degraded 결과 등)일 수 있다.
    // 빈 맵으로 정규화해 호출부가 매번 null 체크를 하지 않게 한다.
    final matchedFacetsJson =
        match['matched_facets'] as Map<String, dynamic>? ?? const {};
    final matchedFacets = matchedFacetsJson.map(
      (key, value) => MapEntry(key, (value as List<dynamic>).cast<String>()),
    );

    return DiscoveryMatch(
      storeId: match['store_id'] as String,
      name: match['name'] as String,
      category: match['category'] as String?,
      subcategory: match['subcategory'] as String?,
      floorId: match['floor_id'] as String,
      floorName: match['floor_name'] as String,
      entranceNodeId: match['entrance_node_id'] as String?,
      point: LatLng(lat, lng),
      matchedFacets: matchedFacets,
      reason: match['reason'] as String?,
    );
  }
}
