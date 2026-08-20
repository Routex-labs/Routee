import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/route/transit_itinerary_filter.dart';
import 'package:navigation_client/models/route/transit_route.dart';

void main() {
  TransitLeg leg(TransitMode mode) => TransitLeg(
    mode: mode,
    sectionTimeSeconds: 600,
    distanceMeters: 500,
    points: const [],
  );

  TransitItinerary itinerary(List<TransitMode> modes) => TransitItinerary(
    totalTimeSeconds: 1200,
    totalWalkTimeSeconds: 300,
    totalDistanceMeters: 3000,
    transferCount: modes.where((m) => !m.isWalk).length - 1,
    legs: [for (final mode in modes) leg(mode)],
  );

  final busOnly = itinerary([
    TransitMode.walk,
    TransitMode.bus,
    TransitMode.walk,
  ]);
  final subwayOnly = itinerary([TransitMode.walk, TransitMode.subway]);
  final mixed = itinerary([
    TransitMode.bus,
    TransitMode.subway,
    TransitMode.walk,
  ]);
  final train = itinerary([TransitMode.walk, TransitMode.train]);
  final walkOnly = itinerary([TransitMode.walk]);

  group('분류', () {
    test('도보를 빼고 버스만 남으면 버스다', () {
      expect(classifyItinerary(busOnly), TransitFilter.bus);
    });

    test('도보를 빼고 지하철만 남으면 지하철이다', () {
      expect(classifyItinerary(subwayOnly), TransitFilter.subway);
    });

    test('버스와 지하철을 함께 타면 버스+지하철이다', () {
      expect(classifyItinerary(mixed), TransitFilter.busAndSubway);
    });

    test('기차처럼 갈래가 없는 수단은 전체에만 남는다', () {
      expect(classifyItinerary(train), TransitFilter.all);
    });

    test('탈것이 하나도 없으면 전체에만 남는다', () {
      expect(classifyItinerary(walkOnly), TransitFilter.all);
    });
  });

  group('탭 목록', () {
    test('전체가 항상 맨 앞이고 0건인 갈래는 빠진다', () {
      expect(availableTransitFilters([busOnly, busOnly, mixed]), [
        TransitFilter.all,
        TransitFilter.bus,
        TransitFilter.busAndSubway,
      ]);
    });

    test('경로가 없으면 전체만 남는다', () {
      expect(availableTransitFilters([]), [TransitFilter.all]);
    });
  });

  group('집계와 적용', () {
    test('전체는 전부를 센다', () {
      expect(
        transitFilterCount([busOnly, subwayOnly, train], TransitFilter.all),
        3,
      );
    });

    test('갈래는 그 갈래만 센다', () {
      expect(
        transitFilterCount([busOnly, subwayOnly, train], TransitFilter.bus),
        1,
      );
    });

    test('전체는 순서를 바꾸지 않고 그대로 돌려준다', () {
      final input = [busOnly, subwayOnly, train];
      expect(applyTransitFilter(input, TransitFilter.all), input);
    });

    test('갈래는 그 갈래만 남긴다', () {
      expect(
        applyTransitFilter([busOnly, subwayOnly, train], TransitFilter.subway),
        [subwayOnly],
      );
    });
  });
}
