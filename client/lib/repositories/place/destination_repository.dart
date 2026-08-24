import '../../models/place/discovery_result.dart';
import '../../models/place/poi_search_result.dart';

abstract class DestinationRepository {
  /// query가 비면 건물 전체 POI 목록을 준다.
  ///
  /// [currentFloorId]는 사용자에게 보이는 층 라벨("B2")도 내부 id도 받는다.
  /// null이면 건물 전체를 뒤진다 — 야외, 층 미로드, 그리고 **길찾기**가 그렇다
  /// (다른 층으로 가려고 여는 기능이라 층으로 좁히지 않는다).
  Future<List<PoiSearchResult>> searchDestinations(
    String buildingId,
    String query, {
    String? currentFloorId,
  });

  /// 탐색(Discovery) 질의 — `POST /query/ai`. 응답 계약이 [searchDestinations]와
  /// **다르다**(mode + 질문/선택지 + 여러 후보).
  ///
  /// 정확한 이름은 `direct`로 즉시 오지만 **그 외 경로는 임베딩 모델 로드로 첫
  /// 호출이 수 초 걸린다.** 호출부는 로딩 상태를 노출하고 UI를 막지 않는다.
  ///
  /// 서버가 세션을 유지하지 않으므로 [selectedFacets]·[showAll]은 **매 요청에
  /// 다시 실어야** 한다. 화면 분기의 유일한 근거는 반환값의 `mode`다.
  ///
  /// 설계는 `docs/native/conversational-discovery.md` 8-2·8-3절.
  Future<DiscoveryResult> searchDestinationsAi(
    String buildingId,
    String query, {
    String? currentFloorId,
    Map<String, List<String>>? selectedFacets,
    bool showAll = false,
  });
}
