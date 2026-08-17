import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/features/indoor_navigation/contract/indoor_navigation_contract.dart';
import 'package:navigation_client/screens/outdoor_map/entry/indoor_exit_walkout.dart';

/// 걸어 나감 판정의 **검증 기준표**다. 실기기 실험은 "PDR 좌표가 정말 그
/// 자리인가"만 확인하면 되고, 어떤 숫자가 어떤 결론을 만드는지는 여기서 끝난다.
///
/// 축은 문 노드 (0, 0)에서 **북쪽으로 10 m** 떨어진 문 좌표를 향한다. 실제
/// 데이터에서 두 점의 거리가 7~12 m이므로 그 한가운데를 쓴다. 그래서 이 파일에서
/// `north`가 곧 "바깥쪽 전진", `east`가 "축에서 옆으로 벗어난 거리"다.
const _nodeId = 'door-north';

EntranceAxis _axis() => entranceAxisFrom(
  nodeId: _nodeId,
  nodeM: const PdrLocalPoint(0, 0),
  doorM: const PdrLocalPoint(0, 10),
)!;

PdrLocalPoint _at({double north = 0, double east = 0}) =>
    PdrLocalPoint(east, north);

void main() {
  group('entranceAxisFrom', () {
    test('문 안쪽에서 바깥쪽을 가리키는 단위 벡터를 만든다', () {
      final axis = _axis();
      expect(axis.outward.eastM, closeTo(0, 1e-9));
      expect(axis.outward.northM, closeTo(1, 1e-9));
    });

    test('두 점이 사실상 같으면 축을 만들지 않는다', () {
      // 방향을 모르는 축으로 판정하면 전진과 후퇴가 뒤집혀, 건물 안으로 걸어
      // 들어가는 사람을 내보낸다.
      final axis = entranceAxisFrom(
        nodeId: _nodeId,
        nodeM: const PdrLocalPoint(0, 0),
        doorM: const PdrLocalPoint(0.4, 0.3),
      );
      expect(axis, isNull);
    });
  });

  group('projectOnEntranceAxis', () {
    test('건물 안쪽은 전진 거리가 음수다', () {
      final projection = projectOnEntranceAxis(_axis(), _at(north: -12));
      expect(projection.forwardM, closeTo(-12, 1e-9));
      expect(projection.lateralM, closeTo(0, 1e-9));
    });

    test('옆으로 벗어난 거리는 부호를 버린다', () {
      final left = projectOnEntranceAxis(_axis(), _at(north: 2, east: -7));
      final right = projectOnEntranceAxis(_axis(), _at(north: 2, east: 7));
      expect(left.lateralM, closeTo(7, 1e-9));
      expect(right.lateralM, closeTo(7, 1e-9));
    });
  });

  group('EntranceWalkoutDetector', () {
    late EntranceWalkoutDetector detector;
    late List<EntranceAxis> axes;

    setUp(() {
      detector = EntranceWalkoutDetector();
      axes = [_axis()];
    });

    String? feed({double north = 0, double east = 0}) =>
        detector.update(axes: axes, positionM: _at(north: north, east: east));

    test('문 앞에 섰다가 바깥으로 전진하면 나간 것이다', () {
      expect(feed(north: -20), isNull); // 아직 문에서 멀다
      expect(feed(north: -3), isNull); // 문 앞 — 여기서 무장한다
      expect(detector.armedNodeId, _nodeId);
      expect(feed(north: walkoutAdvanceMeters), _nodeId);
    });

    test('무장 없이 바깥에서 시작하면 나가지 않는다', () {
      // 앵커가 어긋난 채 시작하면 첫 좌표가 문 바깥에 놓일 수 있다. 그때
      // 발화하면 사용자는 건물 한가운데에서 야외 지도로 튕겨 나간다.
      expect(feed(north: 3), isNull);
      expect(feed(north: 20), isNull);
      expect(detector.armedNodeId, isNull);
    });

    test('안쪽으로 걸으면 나가지 않는다', () {
      expect(feed(north: -2), isNull);
      expect(feed(north: -20), isNull);
      expect(feed(north: -40), isNull);
    });

    test('전진이 문턱에 못 미치면 아직 나간 것이 아니다', () {
      feed(north: -2);
      expect(feed(north: walkoutAdvanceMeters - 0.5), isNull);
      expect(detector.armedNodeId, _nodeId);
    });

    test('문 앞을 옆으로 스쳐 지나가면 나가지 않는다', () {
      // 벽을 따라 걷는 동선은 축과 나란해서 전진 거리만으로는 통과와 구분되지
      // 않는다. 옆으로 벗어난 거리가 그 둘을 가른다.
      final aside = walkoutHalfWidthMeters + 1;
      expect(feed(north: -2, east: aside), isNull);
      expect(feed(north: 20, east: aside), isNull);
    });

    test('문 안쪽 무장 반경 밖에서는 무장하지 않는다', () {
      feed(north: -walkoutArmInsideMeters - 1);
      expect(detector.armedNodeId, isNull);
    });

    test('한 번 발화하면 무장을 스스로 푼다', () {
      // 화면이 이탈을 처리하는 동안 같은 좌표가 다시 들어와도 두 번 부르면 안
      // 된다.
      feed(north: -2);
      expect(feed(north: 6), _nodeId);
      expect(feed(north: 6), isNull);
      expect(detector.armedNodeId, isNull);
    });

    test('가까이 간 문만 무장한다', () {
      // 문이 여러 개여도 무장은 하나다. 멀리 있는 문이 무장을 가로채면 그
      // 문의 축으로 판정하게 되어, 엉뚱한 방향의 전진이 이탈로 읽힌다.
      final other = entranceAxisFrom(
        nodeId: 'door-south',
        nodeM: const PdrLocalPoint(0, -60),
        doorM: const PdrLocalPoint(0, -70),
      )!;
      axes = [_axis(), other];
      feed(north: -2); // 북쪽 문 앞에서 무장
      expect(detector.armedNodeId, _nodeId);
      expect(feed(north: 6), _nodeId);
    });

    test('reset하면 다시 다가서야 나갈 수 있다', () {
      feed(north: -2);
      detector.reset();
      expect(feed(north: 20), isNull);
    });
  });
}
