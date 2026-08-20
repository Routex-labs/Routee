/// 대중교통 결과 목록의 수단 갈래. 받은 경로만으로 계산하며 새 요청이 없다.
library;

import '../../models/route/transit_route.dart';

/// 결과 목록 위의 탭 한 칸.
///
/// [all]은 두 가지 뜻을 겸한다 — 탭으로는 "전부 보기"이고, 분류 결과로는
/// "버스·지하철 어느 갈래에도 안 맞음"이다. 기차·고속버스처럼 갈래가 없는
/// 수단에 탭을 새로 파지 않으려는 것이다.
enum TransitFilter {
  all,
  bus,
  subway,
  busAndSubway;

  String get label => switch (this) {
    TransitFilter.all => '전체',
    TransitFilter.bus => '버스',
    TransitFilter.subway => '지하철',
    TransitFilter.busAndSubway => '버스+지하철',
  };
}

/// [itinerary]가 어느 갈래인지. 도보 구간은 세지 않는다 — 어느 경로든 도보가
/// 붙어 있어서, 넣고 세면 모든 경로가 같은 갈래가 된다.
TransitFilter classifyItinerary(TransitItinerary itinerary) {
  final modes = {
    for (final leg in itinerary.legs)
      if (!leg.mode.isWalk) leg.mode,
  };
  if (modes.length == 1 && modes.first == TransitMode.bus) {
    return TransitFilter.bus;
  }
  if (modes.length == 1 && modes.first == TransitMode.subway) {
    return TransitFilter.subway;
  }
  if (modes.length == 2 &&
      modes.contains(TransitMode.bus) &&
      modes.contains(TransitMode.subway)) {
    return TransitFilter.busAndSubway;
  }
  return TransitFilter.all;
}

/// 그릴 탭 목록. [TransitFilter.all]이 항상 맨 앞이고, 0건인 갈래는 뺀다 —
/// 눌러도 빈 목록만 나오는 탭은 사용자에게 고장으로 읽힌다.
List<TransitFilter> availableTransitFilters(
  List<TransitItinerary> itineraries,
) {
  final present = itineraries.map(classifyItinerary).toSet();
  return [
    TransitFilter.all,
    for (final filter in const [
      TransitFilter.bus,
      TransitFilter.subway,
      TransitFilter.busAndSubway,
    ])
      if (present.contains(filter)) filter,
  ];
}

/// 탭 라벨에 붙일 개수.
int transitFilterCount(
  List<TransitItinerary> itineraries,
  TransitFilter filter,
) => filter == TransitFilter.all
    ? itineraries.length
    : itineraries.where((it) => classifyItinerary(it) == filter).length;

/// 목록을 좁힌다. 순서는 바꾸지 않는다 — 정렬은 응답이 준 그대로가 단일 출처다.
List<TransitItinerary> applyTransitFilter(
  List<TransitItinerary> itineraries,
  TransitFilter filter,
) => filter == TransitFilter.all
    ? itineraries
    : [
        for (final it in itineraries)
          if (classifyItinerary(it) == filter) it,
      ];
