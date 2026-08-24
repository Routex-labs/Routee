/// 자동완성 인덱스 한 줄. 백엔드 `GET /buildings/{id}/store-index`의 응답 1건과
/// 1:1 대응한다(`app/dto/building.py`의 `StoreIndexResponse`).
///
/// **좌표가 없는 것이 이 모델의 요점이다** — 후보 목록은 이름과 층만 그리는데,
/// 1640건 전부에 좌표를 붙이면 응답이 333KB에서 최대 1.6배가 된다(K절).
///
/// 그래서 **후보를 고르면 그 이름으로 검색을 다시 돌린다** — 경량 매칭이 좌표까지
/// 갖춘 1건을 주므로 좌표를 두 벌로 들고 다닐 이유가 사라진다.
class StoreIndexEntry {
  const StoreIndexEntry({
    required this.id,
    required this.name,
    required this.floorId,
    required this.floorName,
    this.category,
    this.subcategory,
    this.kind = 'store',
    this.entranceNodeId,
  });

  /// 매장 고유 id. 상세(`/places/{id}`) 조회 키.
  final String id;

  /// 매장명. **원문 그대로다** — `A.P.C.`의 구두점을 지우지 않는다. 검색용
  /// 정규화는 `domain/store_suggestions.dart`가 별도 키로 만들어 쓰고, 화면에는
  /// 이 값이 나간다.
  final String name;

  /// 소속 층 id. 층 지도 응답(`StoreResponse.floor_id`)·현재 층 필터와 대조하는 키.
  final String floorId;

  /// 사람이 보는 층 라벨(예: `B2`). 후보 한 줄에 그대로 표시한다.
  final String floorName;

  /// 대분류(예: 패션). 없는 매장이 있어 선택.
  final String? category;

  /// 소분류(예: 여성패션). 선택.
  final String? subcategory;

  /// 상세와 같은 분류(`store`·`facility`·`excluded`). 서버가 준다.
  ///
  /// 이 색인에는 주차 787·에스컬레이터 152·엘리베이터 68이 섞여 있다(전체의 61%).
  /// 매장만 골라야 하는 화면(근처 매장)이 소분류 목록을 여기에 베껴 판정하면, 서버가
  /// 규칙을 고친 날 두 화면이 서로 다른 말을 한다.
  ///
  /// 기본값이 `store`인 이유는 이 필드가 없던 서버 응답과 섞여도 **후보 목록이
  /// 사라지지 않게** 하기 위해서다 — 자동완성은 kind를 보지 않는다.
  final String kind;

  /// 도착 노드. null이면 그 매장은 경로 안내가 불가능하다.
  final String? entranceNodeId;

  factory StoreIndexEntry.fromJson(Map<String, dynamic> json) {
    return StoreIndexEntry(
      id: json['id'] as String,
      name: json['name'] as String,
      floorId: json['floor_id'] as String,
      floorName: json['floor_name'] as String,
      category: json['category'] as String?,
      subcategory: json['subcategory'] as String?,
      kind: json['kind'] as String? ?? 'store',
      entranceNodeId: json['entrance_node_id'] as String?,
    );
  }
}
