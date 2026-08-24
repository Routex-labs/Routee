import 'package:navigation_client/models/building/category_count.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';

/// 카테고리 칩 줄과 매장 목록을 띄울 수 있는 목업.
///
/// 기본 목업([MockBuildingRepository])은 업종이 비어 있어 칩 줄이 그려지지
/// 않는다. 칩을 눌러야 하는 테스트가 둘 이상이라 여기 한 벌만 둔다.
class CategorizedBuildingRepository extends MockBuildingRepository {
  static const _storesByFloor = {
    '1F': ['우리은행 ATM'],
    '2F': ['신한은행 ATM'],
  };

  @override
  Future<List<CategoryCount>?> getCategoryCounts(String buildingId) async => [
    for (final entry in _storesByFloor.entries)
      CategoryCount(
        floor: entry.key,
        category: '서비스',
        subcategory: 'ATM',
        count: entry.value.length,
      ),
  ];

  @override
  Future<Map<String, dynamic>?> getFloorGeoJson(
    String buildingId,
    String floor,
  ) async {
    final names = _storesByFloor[floor] ?? const <String>[];
    return {
      'footprint_wgs84': <dynamic>[],
      'stores': [
        for (var i = 0; i < names.length; i++)
          {
            'id': '$floor-$i',
            'name': names[i],
            'category': '서비스',
            'subcategory': 'ATM',
            'centroid_wgs84': {'lat': 37.5665, 'lng': 126.978},
          },
      ],
      'pois': <dynamic>[],
    };
  }
}
