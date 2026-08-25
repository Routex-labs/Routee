import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/features/indoor_navigation/application/elevator_arrival.dart';
import 'package:navigation_client/models/building/floor_graph.dart';

/// 픽스처는 실기기 그래프(더현대 서울, `?vertical=auto`, 2026-08-24)를 줄인 것이다.
/// 엘리베이터 노드 59개 = EV1~EV4 전 층 12개씩 + EV6 7개 층 + 이름 없는 4개(B3·B4).
/// EV5는 데이터에 없다.
const _floorIds = {
  'B4': 'FL-b4',
  'B3': 'FL-b3',
  'B2': 'FL-b2',
  'B1': 'FL-b1',
  '1F': 'FL-1f',
  '2F': 'FL-2f',
  '5F': 'FL-5f',
};

/// EV6이 서는 층. 5F·B3·B4에는 안 선다.
const _ev6Floors = {'B2', 'B1', '1F', '2F'};

GraphNode _elevator(
  String? name,
  String floorLabel, {
  double x = 100,
  double y = 120,
}) => GraphNode(
  id: '${_floorIds[floorLabel]}:ND-${name ?? 'unnamed'}-$floorLabel',
  type: 'elevator',
  name: name,
  xM: x,
  yM: y,
  floorId: _floorIds[floorLabel],
);

/// 한 층의 엘리베이터 배치. 실측 좌표 간격(EV1↔EV2 약 110m)을 따른다.
List<GraphNode> _elevatorsOn(String floorLabel) => [
  _elevator('EV1', floorLabel, x: 97, y: 120),
  _elevator('EV2', floorLabel, x: 207, y: 117),
  if (_ev6Floors.contains(floorLabel))
    _elevator('EV6', floorLabel, x: 60, y: 90),
  if (floorLabel == 'B3' || floorLabel == 'B4') ...[
    _elevator(null, floorLabel, x: 140, y: 192),
    _elevator(null, floorLabel, x: 183, y: 192),
  ],
];

FloorGraph _floorGraph(String floorLabel) => FloorGraph(
  nodes: [
    ..._elevatorsOn(floorLabel),
    const GraphNode(id: 'n-hall', type: 'corridor', xM: 150, yM: 150),
  ],
  edges: const [],
);

void main() {
  group('elevatorCarName — 호기 이름 정규화', () {
    test('엘리베이터가 아니면 null이다', () {
      expect(
        elevatorCarName(
          const GraphNode(id: 'n-hall', type: 'corridor', xM: 0, yM: 0),
        ),
        isNull,
      );
    });

    test('이름 없는 엘리베이터도 null이다 — 샤프트를 모른다', () {
      expect(elevatorCarName(_elevator(null, 'B3')), isNull);
    });

    test('대소문자·공백 차이를 흡수한다', () {
      // 층마다 다른 사람이 찍은 이름이라, 흡수하지 않으면 같은 샤프트가 갈라진다.
      expect(elevatorCarName(_elevator(' ev1 ', '1F')), 'EV1');
      expect(elevatorCarName(_elevator('EV1', '2F')), 'EV1');
    });
  });

  group('findElevatorArrivalNode — 도착 노드 찾기', () {
    test('목표 층에서 같은 호기의 노드를 돌려준다', () {
      final node = findElevatorArrivalNode(
        graph: _floorGraph('5F'),
        carName: 'EV1',
      );

      expect(node?.name, 'EV1');
      expect(node?.id, contains('FL-5f'));
    });

    test('좌표가 아니라 이름으로 잇는다', () {
      // 층 도면 등록 오차 때문에 같은 샤프트가 층마다 최대 16m 어긋나 있다
      // (실측 EV1: 1F 97.5/120.8 ↔ B5 113.2/119.1). 좌표로 이으면 옆 호기를 잡는다.
      final shifted = FloorGraph(
        nodes: [
          _elevator('EV2', '2F', x: 97, y: 120),
          _elevator('EV1', '2F', x: 113, y: 119),
        ],
        edges: const [],
      );

      expect(
        findElevatorArrivalNode(graph: shifted, carName: 'EV1')?.name,
        'EV1',
      );
    });

    test('그 호기가 안 서는 층이면 null이다', () {
      // EV6으로 5F. 가장 가까운 다른 엘리베이터를 대신 돌려주면 건물 반대편에
      // 세운다. 부르는 쪽이 "그 층에서는 못 내린다"로 읽어야 한다.
      expect(
        findElevatorArrivalNode(graph: _floorGraph('5F'), carName: 'EV6'),
        isNull,
      );
      expect(
        findElevatorArrivalNode(graph: _floorGraph('2F'), carName: 'EV6')?.name,
        'EV6',
      );
    });

    test('호기를 모르면 null이다 — 이름 없는 노드로 탔을 때', () {
      expect(
        findElevatorArrivalNode(graph: _floorGraph('B4'), carName: null),
        isNull,
      );
      expect(
        findElevatorArrivalNode(graph: _floorGraph('B4'), carName: '  '),
        isNull,
      );
    });

    test('그래프가 아직 없으면 null이다', () {
      expect(findElevatorArrivalNode(graph: null, carName: 'EV1'), isNull);
    });

    test('같은 이름이라도 엘리베이터가 아닌 노드는 안 잡는다', () {
      final graph = FloorGraph(
        nodes: const [
          GraphNode(id: 'n-store', type: 'store', name: 'EV1', xM: 0, yM: 0),
        ],
        edges: const [],
      );

      expect(findElevatorArrivalNode(graph: graph, carName: 'EV1'), isNull);
    });
  });
}
