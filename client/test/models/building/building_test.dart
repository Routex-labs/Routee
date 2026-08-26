import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/models/building/building.dart';

/// 층 목록 순서와 "처음 열 층"의 분리를 검증한다. 지하층이 생기면서
/// floors.first(=최상층)를 기본 층으로 쓰던 방식이 6F로 열리는 문제를 냈다.
void main() {
  test('default_floor를 처음 열 층으로 쓴다', () {
    final building = Building.fromJson({
      'id': 'thehyundai-seoul',
      'name': '더현대 서울',
      'floors': ['6F', '5F', '4F', '3F', '2F', '1F', 'B1', 'B2'],
      'default_floor': '1F',
    });

    expect(building.floors.first, '6F');
    expect(building.initialFloor, '1F');
  });

  test('서버 주소를 진입 화면용 표기로 쓴다', () {
    final building = Building.fromJson({
      'id': 'thehyundai-seoul',
      'name': '더현대 서울',
      'address': '서울특별시 영등포구 여의대로 108',
      'floors': ['1F'],
    });

    expect(building.displayAddress, '서울특별시 영등포구 여의대로 108');
  });

  test('더현대 서울 구버전 응답에는 검증된 주소를 보완한다', () {
    final building = Building.fromJson({
      'id': 'thehyundai-seoul',
      'name': '더현대 서울',
      'floors': ['1F'],
    });

    expect(building.displayAddress, '서울 영등포구 여의대로 108');
  });

  test('default_floor가 없는 응답은 목록 첫 층으로 폴백한다', () {
    final building = Building.fromJson({
      'id': 'legacy',
      'name': '구버전 백엔드',
      'floors': ['2F', '1F'],
    });

    expect(building.defaultFloor, isNull);
    expect(building.initialFloor, '2F');
  });

  test('default_floor가 층 목록에 없으면 무시한다', () {
    final building = Building.fromJson({
      'id': 'stale',
      'name': '없는 층을 가리키는 응답',
      'floors': ['2F', '1F'],
      'default_floor': 'B9',
    });

    expect(building.initialFloor, '2F');
  });

  test('층이 없으면 열 층도 없다', () {
    final building = Building.fromJson({
      'id': 'empty',
      'name': '층 없음',
      'floors': <String>[],
    });

    expect(building.initialFloor, isNull);
  });

  test('footprint_wgs84가 있으면 LatLng 리스트로 파싱된다', () {
    final building = Building.fromJson({
      'id': 'x',
      'name': 'x',
      'floors': <String>[],
      'footprint_wgs84': [
        {'lat': 37.5268, 'lng': 126.9283},
        {'lat': 37.5263, 'lng': 126.9274},
        {'lat': 37.5251, 'lng': 126.9286},
      ],
    });

    expect(building.footprintWgs84, isNotNull);
    expect(building.footprintWgs84!.length, 3);
    expect(building.footprintWgs84!.first.latitude, closeTo(37.5268, 1e-9));
    expect(building.footprintWgs84!.first.longitude, closeTo(126.9283, 1e-9));
  });

  test('footprint_wgs84가 없는 응답은 null이다', () {
    final building = Building.fromJson({
      'id': 'x',
      'name': 'x',
      'floors': <String>[],
    });

    expect(building.footprintWgs84, isNull);
  });
  group('목록 응답과 단건 응답은 같지 않다', () {
    // 이 그룹이 지키는 증상: 검색에서 "더현대 서울"을 골라도 지도가 꿈쩍 않던
    // 문제. 검색 결과의 건물 한 줄은 **목록**(`/buildings`)에서 나오는데 거기엔
    // 외곽선도 입구도 없어서, 그 Building을 그대로 들고 카메라를 옮기려 하면
    // 옮길 좌표가 하나도 없다. 화면에서는 그냥 "안 움직인다"로만 보여 원인을
    // 찾는 데 오래 걸렸다.
    //
    // 그래서 목록에서 온 건물을 쓰는 쪽은 반드시 단건으로 한 번 더 받아야 한다
    // (`OutdoorMapBodyState.focusBuilding`). 이 테스트는 그 전제 — 두 응답의
    // 모양이 실제로 다르다는 것 — 을 못 박는다.

    test('목록 응답에는 외곽선과 입구가 없다', () {
      // 실제 `/buildings` 응답 키를 그대로 옮긴 것이다.
      final fromList = Building.fromJson({
        'id': 'thehyundai-seoul',
        'name': '더현대 서울',
        'floors': ['6F', '1F', 'B1', 'B2'],
        'default_floor': '1F',
      });

      expect(fromList.footprintWgs84, isNull);
      expect(fromList.entrance, isNull);
    });

    test('단건 응답에는 외곽선이 있다', () {
      final fromDetail = Building.fromJson({
        'id': 'thehyundai-seoul',
        'name': '더현대 서울',
        'floors': ['6F', '1F', 'B1', 'B2'],
        'default_floor': '1F',
        'footprint_wgs84': [
          {'lat': 37.5259, 'lng': 126.9284},
          {'lat': 37.5263, 'lng': 126.9284},
          {'lat': 37.5263, 'lng': 126.9291},
          {'lat': 37.5259, 'lng': 126.9291},
        ],
        'tile_revision': '42bb37f872d3eaf4',
      });

      expect(fromDetail.footprintWgs84, hasLength(4));
      expect(fromDetail.tileRevision, isNotNull);
    });
  });
}
