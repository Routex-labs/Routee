import 'package:navigation_client/domain/route/dijkstra.dart';
import 'package:navigation_client/domain/store/nearest_store.dart';
import 'package:navigation_client/domain/search/store_suggestions.dart';
import 'package:navigation_client/models/place/store_index_entry.dart';
import 'package:flutter_test/flutter_test.dart';

/// 설계와 검증 기준은 `docs/client/search-result-list-ux.md` O절이 단일 출처다.

StoreIndexEntry _store(String floor, {String? nodeId, String name = '화장실'}) =>
    StoreIndexEntry(
      id: 'PO-$name-$floor',
      name: name,
      floorId: 'FL-$floor',
      floorName: floor,
      entranceNodeId: nodeId,
    );

NodeReach _reach(double distanceM) =>
    NodeReach(distanceM: distanceM, costM: distanceM);

void main() {
  group('O. 묶인 시설의 대표는 가장 가까운 곳이다', () {
    // 인덱스 순서는 서버가 `Floor.level DESC`로 못박아 둔다. 그래서 예전 구현
    // ("처음 나온 것")은 사용자가 어디 있든 늘 꼭대기 층을 대표로 세웠다.
    test('인덱스 첫 번째가 아니라 최근접을 고른다', () {
      final stores = [
        _store('6F', nodeId: 'N6'),
        _store('B2', nodeId: 'NB2'),
        _store('1F', nodeId: 'N1'),
      ];

      final result = nearestByWalkingDistance(
        stores: stores,
        reachByNodeId: {
          'N6': _reach(310),
          'NB2': _reach(48),
          'N1': _reach(120),
        },
      );

      expect(result.store.floorName, 'B2');
      expect(result.reach?.distanceM, 48);
    });

    test('묶이지 않은 단일 매장도 거리를 얻는다', () {
      final result = nearestByWalkingDistance(
        stores: [_store('1F', nodeId: 'N1', name: '구찌 뷰티')],
        reachByNodeId: {'N1': _reach(120)},
      );

      expect(result.store.floorName, '1F');
      expect(result.reach?.distanceM, 120);
    });
  });

  group('O. 거리를 모를 때는 지금 동작 그대로', () {
    test('reach가 null이면 첫 번째를 그대로 쓰고 거리는 없다', () {
      final stores = [_store('6F', nodeId: 'N6'), _store('B2', nodeId: 'NB2')];

      final result = nearestByWalkingDistance(
        stores: stores,
        reachByNodeId: null,
      );

      expect(result.store.floorName, '6F');
      expect(result.reach, isNull);
    });

    test('reach가 비어 있어도 마찬가지다', () {
      final result = nearestByWalkingDistance(
        stores: [_store('6F', nodeId: 'N6')],
        reachByNodeId: const {},
      );

      expect(result.store.floorName, '6F');
      expect(result.reach, isNull);
    });

    // 그래프가 끊겨 아무도 reach에 없는 경우. 도달 못 하는 곳을 "가장 가깝다"고
    // 적지 않는다.
    test('전원 도달 불가면 첫 번째 + 거리 없음', () {
      final result = nearestByWalkingDistance(
        stores: [
          _store('6F', nodeId: 'N6'),
          _store('B2', nodeId: 'NB2'),
        ],
        reachByNodeId: {'N-다른층': _reach(10)},
      );

      expect(result.store.floorName, '6F');
      expect(result.reach, isNull);
    });
  });

  // 측위가 아직 안 잡힌 상태에서도 **지금 보고 있는 층**은 안다. 거리를 모른다고
  // 입력 첫 번째로 돌아가면 서버 색인이 `Floor.level DESC`라 늘 꼭대기 층이 뽑혀,
  // B2에 서 있는 사람이 `화장실 · 6F`를 보게 된다.
  group('O. 거리를 몰라도 지금 층은 안다', () {
    test('reach가 없으면 현재 층 매장을 대표로 고른다', () {
      final stores = [
        _store('6F', nodeId: 'N6'),
        _store('B2', nodeId: 'NB2'),
        _store('1F', nodeId: 'N1'),
      ];

      final result = nearestByWalkingDistance(
        stores: stores,
        reachByNodeId: null,
        currentFloorId: 'FL-B2',
      );

      expect(result.store.floorName, 'B2');
      // 층을 골랐다고 거리를 아는 것은 아니다. 거리 줄은 여전히 뜨지 않는다.
      expect(result.reach, isNull);
    });

    test('전원 도달 불가여도 현재 층을 고른다', () {
      final result = nearestByWalkingDistance(
        stores: [_store('6F', nodeId: 'N6'), _store('B2', nodeId: 'NB2')],
        reachByNodeId: {'N-다른층': _reach(10)},
        currentFloorId: 'FL-B2',
      );

      expect(result.store.floorName, 'B2');
      expect(result.reach, isNull);
    });

    test('화면이 넘기는 층 라벨(B2)로도 그 층을 고른다', () {
      // 실기기에서 잡힌 회귀다: B2 스타벅스 앞에서 `화장실`을 치면 늘 B6가 떴다.
      // 화면은 층을 라벨로 넘기는데(`_activeIndoorFloor`) 여기서는 내부 id만
      // 대조해서, 한 번도 안 맞고 색인 첫 줄로 떨어지고 있었다.
      final result = nearestByWalkingDistance(
        stores: [_store('B6', nodeId: 'N6'), _store('B2', nodeId: 'NB2')],
        reachByNodeId: null,
        currentFloorId: 'B2',
      );

      expect(result.store.floorName, 'B2');
    });

    test('현재 층에 없으면 예전처럼 첫 번째다', () {
      final result = nearestByWalkingDistance(
        stores: [_store('6F', nodeId: 'N6'), _store('B2', nodeId: 'NB2')],
        reachByNodeId: null,
        currentFloorId: 'FL-3F',
      );

      expect(result.store.floorName, '6F');
    });

    // 거리를 알면 거리가 이긴다. 현재 층은 어디까지나 모를 때의 차선책이다 —
    // 같은 층 200m보다 아래층 30m가 실제로 가깝다.
    test('거리를 알면 현재 층보다 거리가 우선한다', () {
      final result = nearestByWalkingDistance(
        stores: [_store('6F', nodeId: 'N6'), _store('B2', nodeId: 'NB2')],
        reachByNodeId: {'N6': _reach(200), 'NB2': _reach(30)},
        currentFloorId: 'FL-6F',
      );

      expect(result.store.floorName, 'B2');
      expect(result.reach?.distanceM, 30);
    });
  });

  group('O. 일부만 도달 가능할 때', () {
    test('entranceNodeId가 없는 매장은 후보에서 빠진다', () {
      // 가장 가까울 수도 있지만 경로를 못 그리므로 대표가 될 수 없다.
      final result = nearestByWalkingDistance(
        stores: [
          _store('6F', nodeId: null),
          _store('3F', nodeId: 'N3'),
          _store('B2', nodeId: 'NB2'),
        ],
        reachByNodeId: {'N3': _reach(90), 'NB2': _reach(200)},
      );

      expect(result.store.floorName, '3F');
      expect(result.reach?.distanceM, 90);
    });

    test('도달 가능한 것이 하나뿐이면 그것이 대표다', () {
      final result = nearestByWalkingDistance(
        stores: [
          _store('6F', nodeId: 'N6'),
          _store('B2', nodeId: 'NB2'),
          _store('1F', nodeId: 'N1'),
        ],
        reachByNodeId: {'NB2': _reach(500)},
      );

      expect(result.store.floorName, 'B2');
      expect(result.reach?.distanceM, 500);
    });
  });

  group('O. 결정성', () {
    // 같은 입구 노드를 공유하는 인접 매장은 거리가 정확히 같다. 동점에서 대표가
    // 흔들리면 위치를 갱신할 때마다 후보 줄의 층 라벨이 바뀐다.
    //
    // 40건인 이유는 `search_result_order_test.dart`와 같다 — 2~3건은 어떤
    // 구현으로도 우연히 통과한다.
    test('동점 40건에서 매 호출 같은 대표가 나온다', () {
      final stores = [
        for (var i = 0; i < 40; i++) _store('F$i', nodeId: 'N$i'),
      ];
      final reach = {for (var i = 0; i < 40; i++) 'N$i': _reach(100)};

      final first = nearestByWalkingDistance(
        stores: stores,
        reachByNodeId: reach,
      );
      for (var attempt = 0; attempt < 20; attempt++) {
        final again = nearestByWalkingDistance(
          stores: stores,
          reachByNodeId: reach,
        );
        expect(again.store.id, first.store.id);
      }
      // 동점은 입력 순서로 깬다.
      expect(first.store.floorName, 'F0');
    });

    test('입력 목록을 건드리지 않는다', () {
      final stores = [_store('6F', nodeId: 'N6'), _store('B2', nodeId: 'NB2')];
      final before = [for (final s in stores) s.id];

      nearestByWalkingDistance(
        stores: stores,
        reachByNodeId: {'NB2': _reach(10)},
      );

      expect([for (final s in stores) s.id], before);
    });
  });

  // U. 길찾기가 「항상 건물 전체」를 유지하면서도 시설만 가까운 층으로 좁히는 판정.
  // 설계와 검증 기준은 `docs/client/search-result-list-ux.md` U절이 단일 출처다.
  group('U. 층마다 있는 시설이면 가장 가까운 층', () {
    StoreSuggestion group(
      List<StoreIndexEntry> stores, {
      SuggestionKind kind = SuggestionKind.prefix,
    }) => (stores: stores, kind: kind);

    test('같은 이름이 여러 층이면 최근접의 층을 돌려준다', () {
      final floor = nearestFloorForGroupedFacility(
        suggestions: [
          group([
            _store('6F', nodeId: 'N6'),
            _store('B2', nodeId: 'NB2'),
            _store('1F', nodeId: 'N1'),
          ]),
        ],
        reachByNodeId: {
          'N6': _reach(310),
          'NB2': _reach(48),
          'N1': _reach(120),
        },
      );

      expect(floor, 'FL-B2');
    });

    // `나이키`는 서로 다른 이름 3건이라 시설이 아니다. 길찾기의 「항상 건물
    // 전체」 규칙이 그대로 유지돼야 한다.
    test('같은 이름이 하나뿐이면 좁히지 않는다', () {
      final floor = nearestFloorForGroupedFacility(
        suggestions: [
          group([_store('4F', nodeId: 'N4', name: '나이키스윔')]),
          group([_store('B2', nodeId: 'NB2', name: '나이키 라이즈')]),
        ],
        reachByNodeId: {'N4': _reach(118), 'NB2': _reach(168)},
      );

      expect(floor, isNull);
    });

    // 어느 층이 가까운지 모르는데 아무 층이나 고르면 문제를 옮기는 것뿐이다.
    test('거리를 모르면 좁히지 않는다', () {
      final stores = [_store('6F', nodeId: 'N6'), _store('B2', nodeId: 'NB2')];

      expect(
        nearestFloorForGroupedFacility(
          suggestions: [group(stores)],
          reachByNodeId: null,
        ),
        isNull,
      );
      expect(
        nearestFloorForGroupedFacility(
          suggestions: [group(stores)],
          reachByNodeId: {'다른-노드': _reach(10)},
        ),
        isNull,
      );
    });

    // 오타 교정은 추측이다. 그걸 근거로 층까지 확정하면 틀린 추측이 목적지가 된다.
    test('최상위가 교정 후보면 좁히지 않는다', () {
      final floor = nearestFloorForGroupedFacility(
        suggestions: [
          group([
            _store('6F', nodeId: 'N6'),
            _store('B2', nodeId: 'NB2'),
          ], kind: SuggestionKind.correction),
        ],
        reachByNodeId: {'N6': _reach(310), 'NB2': _reach(48)},
      );

      expect(floor, isNull);
    });

    test('후보가 없으면 좁히지 않는다', () {
      expect(
        nearestFloorForGroupedFacility(
          suggestions: const [],
          reachByNodeId: {'N1': _reach(10)},
        ),
        isNull,
      );
    });
  });
}
