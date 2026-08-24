import 'package:latlong2/latlong.dart';

import 'poi_search_result.dart';

/// 탐색(Discovery) 질의 응답의 mode. 백엔드 dto/query.py의
/// DiscoveryResponse.mode(문자열)와 1:1 대응한다.
///
/// 설계: docs/native/conversational-discovery.md 8-3절.
enum DiscoveryMode {
  /// 명확한 목적지 한 건 — matches 1건, 질문 없음.
  direct,

  /// 후보가 넓어 한 번 더 선택이 필요 — question + options + 초기 후보.
  clarify,

  /// 선택이 충분히 좁혀졌거나 되물을 축이 없음 — 다양성 보정된 후보 목록.
  results,

  /// 검증된 후보가 없음.
  noMatch,

  /// 의미 검색 기능 자체를 못 쓰는 상태(모델·인덱스 미가용). 경량/태그 결과가
  /// 있으면 matches에 함께 담겨 온다.
  degraded,

  /// 서버가 이 클라이언트가 모르는 값을 보낸 경우의 방어용 폴백. 백엔드가
  /// mode를 늘려도 파서가 죽지 않고, 화면은 noMatch와 같이 안전하게 처리한다.
  unknown;

  static DiscoveryMode fromWire(String value) => switch (value) {
    'direct' => DiscoveryMode.direct,
    'clarify' => DiscoveryMode.clarify,
    'results' => DiscoveryMode.results,
    'no_match' => DiscoveryMode.noMatch,
    'degraded' => DiscoveryMode.degraded,
    _ => DiscoveryMode.unknown,
  };
}

/// 서버가 후보를 **무엇으로** 잡았는지. [DiscoveryMode]와 축이 다르다 — mode는
/// "얼마나 좁혀졌나", 이건 "무엇을 근거로".
///
/// 온디바이스 이름 후보는 [semantic]에는 이기고 [light]에는 진다
/// (`docs/client/search-input-assist.md` V절).
enum DiscoverySource {
  /// 이름·카테고리·동의어·intent로 잡았다. 이름 후보만큼 결정적이다.
  light,

  /// FAISS 임베딩 유사도로 잡았다. 추측이라 이름 후보를 덮으면 안 된다.
  semantic,

  /// 서버가 이 필드를 안 보냈거나 모르는 값을 보냈다.
  ///
  /// **[semantic]과 같이 취급한다.** `source`를 모르는 구버전 서버에서도 오늘
  /// 동작(이름 후보가 이긴다)이 그대로 유지되어야 하기 때문이다. 이 폴백이
  /// [light]로 기울면 구버전 서버에 붙은 순간 A.P.C. 회귀가 되살아난다.
  unknown;

  static DiscoverySource fromWire(String? value) => switch (value) {
    'light' => DiscoverySource.light,
    'semantic' => DiscoverySource.semantic,
    _ => DiscoverySource.unknown,
  };

  /// 온디바이스 이름 후보를 이 응답으로 대체해도 되는가.
  bool get canReplaceNameSuggestions => this == DiscoverySource.light;
}

/// clarify 질문의 선택지 하나. 백엔드 DiscoveryOption(dto/query.py)과 1:1.
/// 실제 후보가 있는 값만 오므로(빈 chip 금지, 설계 문서 4-3절) 클라이언트는
/// count==0을 별도로 걸러낼 필요가 없다.
class DiscoveryOption {
  const DiscoveryOption({
    required this.facet,
    required this.value,
    required this.label,
    required this.count,
  });

  /// 축 이름(styles·cuisines·...). 사용자가 이 값을 고르면
  /// selected_facets 키로 되돌려 보낸다.
  final String facet;

  /// 축의 값(vocabulary에 선언된 값). 되돌려 보낼 실제 값.
  final String value;

  /// 화면 표시용 라벨. 현재는 value와 같지만 계약을 분리해 둔다.
  final String label;

  /// 이 값을 가진 현재 후보 수.
  final int count;

  factory DiscoveryOption.fromJson(Map<String, dynamic> json) =>
      DiscoveryOption(
        facet: json['facet'] as String,
        value: json['value'] as String,
        label: json['label'] as String,
        count: json['count'] as int,
      );
}

/// 추천 매장 1건. 백엔드 DiscoveryMatch와 1:1.
///
/// [PoiSearchResult]와 필드가 겹쳐도 별도 클래스로 둔다 — matchedFacets·reason은
/// destination 계약에 없는 개념이라, 끼워 넣으면 "목적지 결과인데 추천 이유가
/// 있다"는 모순된 모양이 된다.
class DiscoveryMatch {
  const DiscoveryMatch({
    required this.storeId,
    required this.name,
    required this.category,
    required this.subcategory,
    required this.floorId,
    required this.floorName,
    required this.entranceNodeId,
    required this.point,
    required this.matchedFacets,
    required this.reason,
  });

  final String storeId;
  final String name;
  final String? category;
  final String? subcategory;
  final String floorId;
  final String floorName;

  /// 온디바이스 다익스트라의 도착 노드. null이면 아직 입구가 스냅되지 않은
  /// 매장이라 실제 경로 계산은 불가능하다(destination 계약과 동일한 규약).
  final String? entranceNodeId;

  /// 지도 표시용 실좌표. 파서가 이미 centroid_wgs84 null인 매장을 걸러낸
  /// 뒤에만 이 타입이 만들어지므로 여기서는 non-null이다.
  final LatLng point;

  /// 이번 질문/선택과 실제로 일치한 검증 태그. 축 이름 → 값 목록. 원본
  /// facet 전체가 아니라 이번에 실제로 맞은 것만 담겨 온다(설계 문서 8-3절).
  final Map<String, List<String>> matchedFacets;

  /// matchedFacets에서만 템플릿으로 조립된 추천 이유. 근거 태그가 없으면 null.
  final String? reason;

  /// 기존 화면(PoiSearchResult 리스트 기반)에 그대로 얹기 위한 변환.
  /// floorId·matchedFacets·reason은 아직 화면에서 쓰이지 않으므로 여기서
  /// 버려진다 — 그 화면이 필요해지면 이 변환을 걷어내고 DiscoveryMatch를
  /// 직접 그리면 된다. storeId는 매장 상세 조회 키라서 placeId로 넘긴다.
  PoiSearchResult toPoiSearchResult() => PoiSearchResult(
    name: name,
    floor: floorName,
    point: point,
    placeId: storeId,
    nodeId: entranceNodeId,
    category: category,
    subcategory: subcategory,
  );
}

/// 의미 검색 결과가 사실상 정확한 이름 일치인지 휴리스틱으로 판정한다. 1차가 층
/// 스코프로 빈손이 되어 2차로 넘어온 경우, 정확한 이름을 쳤는데 "뜻으로 찾았다"고
/// 말하는 배너를 막는다.
///
/// 대소문자·앞뒤 공백만 정규화한다 — 서버 Kiwi를 흉내내면 오히려 판정과 어긋난다.
/// 두 화면이 같은 배너 규칙을 써야 해서 모델 쪽에 둔다.
bool isExactNameMatch(String query, Iterable<String> names) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) return false;
  return names.any((raw) {
    final name = raw.trim().toLowerCase();
    return name == normalizedQuery || name.startsWith(normalizedQuery);
  });
}

/// 탐색(Discovery) 질의 응답. mode가 화면 분기의 유일한 근거다. 백엔드
/// dto/query.py의 DiscoveryResponse와 1:1 대응.
class DiscoveryResult {
  const DiscoveryResult({
    required this.mode,
    required this.query,
    this.source = DiscoverySource.unknown,
    this.question,
    this.options = const [],
    this.matches = const [],
  });

  final DiscoveryMode mode;

  /// 사용자가 보낸 원문. 화면에 되비추는 용도.
  final String query;

  /// 후보를 무엇으로 잡았는가. 기본값이 [DiscoverySource.unknown]인 이유는
  /// 그 enum 주석에 있다 — 모르면 이름 후보를 덮지 않는 쪽이 안전하다.
  final DiscoverySource source;

  /// clarify일 때만 값이 있다. 7-3절 템플릿에서 고른 질문 문장.
  final String? question;

  /// clarify일 때만 채워진다.
  final List<DiscoveryOption> options;

  /// mode에 따라 1건(direct)·여러 건(clarify 초기 후보·results)·0건(no_match)
  /// 이 온다. degraded는 가능한 결과가 있으면 함께 담아 온다.
  final List<DiscoveryMatch> matches;
}
