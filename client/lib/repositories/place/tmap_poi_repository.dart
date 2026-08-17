import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../core/api_config.dart';
import '../../models/place/outdoor_poi.dart';
import 'outdoor_poi_repository.dart';

/// TMAP(SK Open API) POI 통합검색 `GET /tmap/pois`.
/// https://openapi.sk.com/products/detail?linkMenuSeq=57
class TmapPoiRepository implements OutdoorPoiRepository {
  TmapPoiRepository({http.Client? client, String? appKey})
    : _client = client ?? http.Client(),
      _appKey = appKey ?? tmapAppKey;

  final http.Client _client;
  final String _appKey;

  @override
  bool get isAvailable => _appKey.isNotEmpty;

  @override
  Future<List<OutdoorPoi>> searchNearby(
    String keyword, {
    required LatLng center,
    int radiusMeters = 0,
    // 10건이면 **이름이 맞는 결과가 잘려 나간다.** TMAP은 이름을 조각내 훑기
    // 때문에 "더현대"에도 "…더원아파트", "…현대썬앤빌…"이 함께 오고, 거리순
    // 정렬이라 그것들이 앞을 채우면 정작 "더현대 대구"가 10건 밖으로 밀린다.
    // 넉넉히 받아 두고 이름 관련성으로 거르는 쪽이(`filterByNameRelevance`)
    // 응답 한 번으로 끝난다.
    int limit = 30,
  }) async {
    final query = keyword.trim();
    if (query.isEmpty) return const [];

    // radius는 **km 단위 정수**이고, 0이면 TMAP이 반경으로 자르지 않는다.
    //
    // 기본값이 0인 이유는 인터페이스 주석에 적었다 — 반경을 걸면 멀리 있는
    // 목적지가 "그런 곳 없음"으로 보인다. 화면은 m로 말하는 게 자연스러우므로
    // 경계인 여기서 km로 바꾸고, 0보다 크면 올림한다(500m를 0km로 깎아 반경
    // 제한이 통째로 풀리는 일이 없게).
    final radiusKm = radiusMeters <= 0
        ? 0
        : (radiusMeters / 1000).ceil().clamp(1, 33);

    final uri = Uri.parse('$tmapBaseUrl/pois').replace(
      queryParameters: {
        'version': '1',
        'searchKeyword': query,
        'centerLon': center.longitude.toString(),
        'centerLat': center.latitude.toString(),
        'radius': radiusKm.toString(),
        // 중심 좌표 기준 가까운 순. 이름 관련도 순(0)으로 두면 같은 브랜드의
        // 다른 지역 지점이 위로 올라와, 걸어갈 수 없는 후보가 첫 줄이 된다.
        'searchtypCd': 'R',
        'count': limit.clamp(1, 200).toString(),
        'resCoordType': 'WGS84GEO',
        'searchType': 'all',
        'multiPoint': 'N',
      },
    );

    final http.Response response;
    try {
      // **상한이 없으면 이 await가 안 풀린다.** 소켓이 끊기지 않고 멎는 경우가
      // 있는데, 그때 호출자(길찾기 후보 목록)의 「찾는 중」이 함께 멈춘다.
      response = await _client
          .get(uri, headers: {'appKey': _appKey})
          .timeout(searchRequestTimeout);
    } on Object catch (error) {
      // 네트워크 실패는 실내 검색까지 막을 이유가 없다. 이 화면에서 POI는
      // 곁들이는 정보라, 조용히 빠지고 나머지 결과는 그대로 뜬다.
      //
      // **다만 로그에는 남긴다.** 조용한 실패는 화면에서 "결과가 없다"와
      // 구분되지 않아, 기능이 통째로 안 도는 것을 아무도 모른 채 지나간다.
      _log('"$query" 요청 실패: $error');
      return const [];
    }
    if (response.statusCode != 200) {
      _log('"$query" HTTP ${response.statusCode}');
      return const [];
    }

    // TMAP은 한글 이름을 UTF-8로 내려주지만 charset을 헤더에 안 실어 줄 때가
    // 있다. http 패키지는 그 경우 latin1으로 디코딩해 "�"가 박히므로, 본문을
    // bodyBytes에서 직접 UTF-8로 읽는다.
    final Map<String, dynamic> body;
    try {
      body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } on Object catch (error) {
      _log('"$query" 응답 파싱 실패: $error');
      return const [];
    }

    // 결과가 없으면 `searchPoiInfo`가 통째로 빠지거나 null로 온다. 중간 어느
    // 단계가 비어도 빈 목록으로 끝난다.
    final searchPoiInfo = body['searchPoiInfo'];
    if (searchPoiInfo is! Map<String, dynamic>) {
      _log('"$query" 결과 없음');
      return const [];
    }
    final pois = searchPoiInfo['pois'];
    if (pois is! Map<String, dynamic>) {
      _log('"$query" 결과 없음');
      return const [];
    }
    final list = pois['poi'];
    if (list is! List) {
      _log('"$query" 결과 없음');
      return const [];
    }

    final results = <OutdoorPoi>[];
    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      final poi = OutdoorPoi.fromTmapJson(item);
      if (poi != null) results.add(poi);
    }
    // 받은 건수와 살아남은 건수를 함께 남긴다. 두 값이 갈리면 응답은 왔는데
    // 파싱에서 떨어뜨린 것이라, 네트워크 문제와 계약 문제를 바로 가를 수 있다.
    _log('"$query" ${results.length}건 (응답 ${list.length}건)');
    return results;
  }

  void _log(String message) => debugPrint('[tmap-poi] $message');
}
