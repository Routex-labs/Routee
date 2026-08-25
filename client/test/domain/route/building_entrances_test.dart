import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/route/building_entrances.dart';
import 'package:navigation_client/models/building/floor_plan.dart';

/// 더현대 서울 1층의 실제 출구 5개(라이브 API 값). 축약하지 않고 그대로 쓴다 —
/// 문 사이 거리와 배치가 히스테리시스 검증의 전제이기 때문이다.
const _northWest = LatLng(37.526549, 126.927834);
const _northEast = LatLng(37.526251, 126.928894);
const _southEast = LatLng(37.525538, 126.929258);
const _south = LatLng(37.525205, 126.928708);
const _west = LatLng(37.525666, 126.927933);
const _center = LatLng(37.525862, 126.928540);

StorePolygon _store({
  required String id,
  required String name,
  required LatLng centroid,
  String? subcategory,
  String? entranceNodeId,
}) => StorePolygon(
  id: id,
  name: name,
  polygon: const [],
  centroid: centroid,
  entranceNodeId: entranceNodeId,
  category: '편의시설',
  subcategory: subcategory,
);

FloorPlan _planWithExits() => FloorPlan(
  pois: const [],
  stores: [
    _store(
      id: 'exit-nw',
      name: '출구',
      centroid: _northWest,
      subcategory: '교통',
      entranceNodeId: 'ND-nw',
    ),
    _store(
      id: 'exit-s',
      name: '출구',
      centroid: _south,
      subcategory: '교통',
      entranceNodeId: 'ND-s',
    ),
    // 같은 소분류지만 그래프 노드가 없는 지하철역 마커. 문으로 받으면 실내
    // 구간의 시작점을 만들 수 없다.
    _store(
      id: 'subway',
      name: '9호선, 5호선 여의도역',
      centroid: _west,
      subcategory: '교통',
    ),
    // 소분류가 다른 일반 매장.
    _store(
      id: 'aesop',
      name: '이솝',
      centroid: _center,
      subcategory: '뷰티',
      entranceNodeId: 'ND-aesop',
    ),
  ],
);

BuildingEntrance _entrance(String id, LatLng point) =>
    BuildingEntrance(id: id, name: '출구', nodeId: 'ND-$id', point: point);

void main() {
  group('groundEntrancesFrom', () {
    test('교통 소분류이면서 노드가 있는 항목만 문으로 받는다', () {
      final entrances = groundEntrancesFrom(_planWithExits());

      expect(entrances.map((e) => e.id), ['exit-nw', 'exit-s']);
      expect(entrances.first.nodeId, 'ND-nw');
      expect(entrances.first.point, _northWest);
    });

    test('노드 없는 지하철역 마커는 제외한다', () {
      final entrances = groundEntrancesFrom(_planWithExits());

      expect(entrances.any((e) => e.id == 'subway'), isFalse);
    });

    test('문이 없는 층이면 빈 목록이다(예외를 던지지 않는다)', () {
      expect(groundEntrancesFrom(const FloorPlan(pois: [])), isEmpty);
    });
  });

  group('nearestEntrance', () {
    final all = [
      _entrance('nw', _northWest),
      _entrance('ne', _northEast),
      _entrance('se', _southEast),
      _entrance('s', _south),
      _entrance('w', _west),
    ];

    test('후보가 없으면 null', () {
      expect(nearestEntrance(const [], _center), isNull);
    });

    test('이력이 없으면 그냥 가장 가까운 문', () {
      // 남쪽 문 바로 앞.
      final picked = nearestEntrance(all, const LatLng(37.52515, 126.92871));

      expect(picked!.id, 's');
    });

    test('건물 반대편으로 넘어가면 문을 바꾼다', () {
      final picked = nearestEntrance(
        all,
        const LatLng(37.52660, 126.92780), // 북서쪽 문 앞
        current: _entrance('s', _south),
      );

      expect(picked!.id, 'nw');
    });

    test('이득이 마진보다 작으면 쥐고 있던 문을 유지한다', () {
      // 북서와 서 두 문의 거의 중간. 새 후보가 조금 가깝더라도 바꾸지 않는다.
      final midpoint = LatLng(
        (_northWest.latitude + _west.latitude) / 2,
        (_northWest.longitude + _west.longitude) / 2,
      );
      final held = _entrance('nw', _northWest);

      final picked = nearestEntrance(all, midpoint, current: held);

      final heldDistance = wgs84DistanceMeters(midpoint, _northWest);
      final rivalDistance = wgs84DistanceMeters(midpoint, _west);
      // 전제 확인: 이 지점은 실제로 마진 안쪽이다(테스트가 조용히 무의미해지는
      // 것을 막는다).
      expect(
        (heldDistance - rivalDistance).abs(),
        lessThan(kEntranceSwitchMarginMeters),
      );
      expect(picked!.id, 'nw');
    });

    test('쥐고 있던 문이 목록에서 사라졌으면 이력 없이 다시 고른다', () {
      final picked = nearestEntrance(
        all,
        const LatLng(37.52515, 126.92871), // 남쪽 문 앞
        current: _entrance('gone', _northWest),
      );

      expect(picked!.id, 's');
    });

    test('실내→야외 안내는 목적지 기준으로 나갈 문을 고른다', () {
      // 실내→야외([showIndoorToOutdoorRouteTo])는 같은 함수에 **목적지**를
      // 넘긴다. 현재 위치 기준으로 고르면 건물 반대편으로 나가게 되어, 실내에서
      // 아낀 몇십 m를 바깥에서 몇백 m로 갚는다.
      final all = [
        _entrance('nw', _northWest),
        _entrance('s', _south),
        _entrance('se', _southEast),
      ];
      // 건물 남쪽 바깥의 목적지(핏타민약국 방향).
      final picked = nearestEntrance(all, const LatLng(37.52470, 126.92880));

      expect(picked!.id, 's');
    });

    test('목적지가 북서쪽이면 북서쪽 문으로 나간다', () {
      // 방향만 뒤집은 같은 규칙인지 확인한다 — 한 방향만 맞으면 우연일 수 있다.
      final all = [
        _entrance('nw', _northWest),
        _entrance('s', _south),
        _entrance('se', _southEast),
      ];
      final picked = nearestEntrance(all, const LatLng(37.52710, 126.92760));

      expect(picked!.id, 'nw');
    });
  });

  group('nearestEntranceByTotalJourney', () {
    test('후보가 없으면 null', () {
      expect(nearestEntranceByTotalJourney(const [], _center), isNull);
    });

    test('실내에서 더 가까운 문이라도 야외로 훨씬 멀면 고르지 않는다', () {
      // 실측 증상 재현: 목적지(정류장)는 서쪽 문 바로 앞인데, 실내 복도로는
      // 동쪽 문이 20 m 더 가깝다고 하자. 실내 거리만 보면 동쪽 문을 고르지만
      // (예전 버그), 총 이동거리로 보면 서쪽 문이 훨씬 짧다.
      final destination = LatLng(
        _west.latitude,
        _west.longitude - 0.00002, // 서쪽 문 바로 옆(약 2 m)
      );
      final picked = nearestEntranceByTotalJourney([
        (entrance: _entrance('east', _northEast), indoorDistanceM: 10.0),
        (entrance: _entrance('west', _west), indoorDistanceM: 30.0),
      ], destination);

      expect(picked!.id, 'west');
    });

    test('실내 거리 차가 야외 거리 차보다 크면 실내가 가까운 문을 고른다', () {
      // 두 문 다 목적지에서 비슷하게 멀 때는 실내 복도가 짧은 쪽이 총 거리도
      // 짧다 — 이 함수가 실내 거리를 무시하지 않는다는 것을 확인한다.
      final picked = nearestEntranceByTotalJourney([
        (entrance: _entrance('near', _south), indoorDistanceM: 5.0),
        (entrance: _entrance('far', _southEast), indoorDistanceM: 200.0),
      ], _center);

      expect(picked!.id, 'near');
    });
  });

  group('entranceDirectionLabel', () {
    test('건물 중심 기준 방위를 이름 앞에 붙인다', () {
      expect(entranceDirectionLabel(_entrance('s', _south), _center), '남쪽 출구');
      expect(
        entranceDirectionLabel(_entrance('nw', _northWest), _center),
        '북서쪽 출구',
      );
      expect(
        entranceDirectionLabel(_entrance('se', _southEast), _center),
        '남동쪽 출구',
      );
    });

    test('건물 중심을 모르면 원본 이름을 그대로 쓴다', () {
      expect(entranceDirectionLabel(_entrance('s', _south), null), '출구');
    });
  });

  group('entranceDirection', () {
    test('지도 핀에 굽는 방위 글자만 돌려준다', () {
      expect(entranceDirection(_entrance('s', _south), _center), '남');
      expect(entranceDirection(_entrance('nw', _northWest), _center), '북서');
      expect(entranceDirection(_entrance('se', _southEast), _center), '남동');
    });

    test('문구와 계산을 공유한다 — 핀 글자와 안내 문구가 어긋나면 안 된다', () {
      for (final point in [_south, _northWest, _southEast]) {
        final entrance = _entrance('e', point);
        final direction = entranceDirection(entrance, _center);
        expect(
          entranceDirectionLabel(entrance, _center),
          '$direction쪽 ${entrance.name}',
        );
      }
    });

    test('중심을 모르면 null — 호출자는 글자 없는 핀을 세우지 않는다', () {
      expect(entranceDirection(_entrance('s', _south), null), isNull);
    });

    test('문이 정확히 중심이면 방위가 없다', () {
      expect(entranceDirection(_entrance('c', _center), _center), isNull);
    });
  });
}
