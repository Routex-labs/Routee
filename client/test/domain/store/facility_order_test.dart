import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/route/dijkstra.dart';
import 'package:navigation_client/domain/store/facility_order.dart';
import 'package:navigation_client/models/place/store_index_entry.dart';

/// 편의시설 목록을 "가까운 순"으로 세우는 규칙.
///
/// 실제 화면에서 잡은 증상이 출발점이다 — **지하 2층에 서 있는데 1층 화장실이
/// 목록에 떴다.** 그때 목록은 보고 있는 층으로 거른 뒤 이름순으로 세우고 있었고,
/// 선 자리와는 아무 상관이 없었다.
StoreIndexEntry _facility(
  String id, {
  String? node,
  String floor = 'B2',
  String name = '화장실',
}) => StoreIndexEntry(
  id: id,
  name: name,
  floorId: floor,
  floorName: floor,
  category: '편의시설',
  subcategory: '화장실',
  kind: 'facility',
  entranceNodeId: node,
);

NodeReach _reach(double m) => NodeReach(distanceM: m, costM: m);

void main() {
  group('가까운 순으로 세운다', () {
    test('보행 거리가 짧은 시설이 앞에 온다 — 층이 달라도 그렇다', () {
      // 1층 화장실이 이름순으로는 앞이지만, 선 자리(B2)에서는 훨씬 멀다.
      final rows = facilitiesByWalkingDistance(
        facilities: [
          _facility('1f', node: 'N-1F', floor: '1F', name: '가화장실'),
          _facility('b2', node: 'N-B2', floor: 'B2', name: '나화장실'),
        ],
        reachByNodeId: {'N-1F': _reach(140), 'N-B2': _reach(12)},
      );

      expect([for (final r in rows) r.facility.id], ['b2', '1f']);
      expect(rows.first.reach!.distanceM, 12);
    });

    test('거리를 아는 것만 세우고, 모르는 것은 끝에 원래 순서로 붙인다', () {
      final rows = facilitiesByWalkingDistance(
        facilities: [
          _facility('노드없음'),
          _facility('멀다', node: 'N-far'),
          _facility('못닿음', node: 'N-unreachable'),
          _facility('가깝다', node: 'N-near'),
        ],
        // 'N-unreachable'은 그래프에서 닿지 못해 맵에 아예 없다.
        reachByNodeId: {'N-far': _reach(90), 'N-near': _reach(8)},
      );

      expect([for (final r in rows) r.facility.id], [
        '가깝다',
        '멀다',
        '노드없음',
        '못닿음',
      ]);
      // 거리를 모르는 줄은 reach가 null이다 — 0으로 채우면 "가장 가깝다"가 된다.
      expect(rows[2].reach, isNull);
      expect(rows[3].reach, isNull);
    });

    test('같은 거리는 입력 순서로 깬다 — 호출마다 순서가 바뀌면 안 된다', () {
      // 한 자리에 붙어 있는 남녀 화장실은 입구 노드를 공유해 거리가 같다.
      final facilities = [
        _facility('남', node: 'N-same'),
        _facility('여', node: 'N-same'),
        _facility('장애인', node: 'N-same'),
      ];
      final reach = {'N-same': _reach(20)};

      for (var i = 0; i < 5; i++) {
        final rows = facilitiesByWalkingDistance(
          facilities: facilities,
          reachByNodeId: reach,
        );
        expect([for (final r in rows) r.facility.id], ['남', '여', '장애인']);
      }
    });
  });

  group('거리를 모르면 순서를 건드리지 않는다', () {
    test('reach가 null이면 입력 순서 그대로다', () {
      final rows = facilitiesByWalkingDistance(
        facilities: [_facility('가', node: 'N-1'), _facility('나', node: 'N-2')],
        reachByNodeId: null,
      );

      expect([for (final r in rows) r.facility.id], ['가', '나']);
      expect(rows.every((r) => r.reach == null), isTrue);
    });

    test('reach가 비어 있어도 마찬가지다 — PDR 미시작이 이 상태다', () {
      final rows = facilitiesByWalkingDistance(
        facilities: [_facility('가', node: 'N-1'), _facility('나', node: 'N-2')],
        reachByNodeId: const {},
      );

      expect([for (final r in rows) r.facility.id], ['가', '나']);
      expect(rows.every((r) => r.reach == null), isTrue);
    });
  });

  test('빈 목록은 빈 목록이다', () {
    expect(
      facilitiesByWalkingDistance(facilities: const [], reachByNodeId: const {}),
      isEmpty,
    );
  });
}
