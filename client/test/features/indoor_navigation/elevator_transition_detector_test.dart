import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_pdr_core/indoor_pdr_core.dart';
import 'package:navigation_client/features/indoor_navigation/application/elevator_transition_detector.dart';
import 'package:navigation_client/features/indoor_navigation/contract/altitude_sample.dart';
import 'package:navigation_client/features/indoor_navigation/contract/raw_motion_activity.dart';
import 'package:navigation_client/models/building/floor_graph.dart';

/// 표준대기 고도 → 기압. [pressureAltitudeM]의 역함수라, 테스트는 "이 고도에
/// 있었다면 센서가 봤을 기압"을 만들어 넣는다.
double _pressureForAltitudeM(double altitudeM) =>
    1013.25 * math.pow(1.0 - altitudeM / 44330.0, 1 / 0.190295);

/// 실측과 같은 배치: 승강장에 EV1 하나, 저 멀리 다른 노드 하나.
FloorGraph _lobbyGraph({String? carName = 'EV1'}) => FloorGraph(
  nodes: [
    GraphNode(id: 'ev1-4f', type: 'elevator', name: carName, xM: 0, yM: 0),
    const GraphNode(id: 'n-far', type: 'junction', name: null, xM: 60, yM: 60),
  ],
  edges: const [],
);

class _Fixture {
  _Fixture({
    String floorLabel = '4F',
    String? buildingId = 'thehyundai-seoul',
    String? carName = 'EV1',
    ElevatorDetectorConfig config = const ElevatorDetectorConfig(),
  }) : detector = ElevatorTransitionDetector(config: config) {
    detector.updateContext(
      floorLabel: floorLabel,
      graph: _lobbyGraph(carName: carName),
      buildingId: buildingId,
    );
  }

  final ElevatorTransitionDetector detector;
  int nowMs = 1000000;
  double altitudeM = 0;
  int steps = 100;
  final confirmed = <ElevatorTransition>[];
  final changes = <ElevatorPhaseChange>[];

  static const _sampleMs = 200;

  void _pump() {
    nowMs += _sampleMs;
    final transition = detector.onAltitude(
      AltitudeSample(
        timestampMs: nowMs,
        pressureHpa: _pressureForAltitudeM(altitudeM),
        source: 'android_pressure',
      ),
    );
    if (transition != null) confirmed.add(transition);
    changes.addAll(detector.takePhaseChanges());
  }

  /// 엘리베이터 앞에 서 있다(위치 근거로 허가).
  void standAtNode() {
    detector.onPosition(
      positionM: const PdrLocalPoint(1.0, 0),
      steps: steps,
      timestampMs: nowMs,
    );
  }

  /// 경로가 이 층에서 엘리베이터를 타라고 한다.
  void routeSaysBoard(String? targetFloorLabel) {
    detector.onElevatorRouteApproach(
      positionM: const PdrLocalPoint(3.0, 0),
      routeEndM: const PdrLocalPoint(0, 0),
      expectedBoardingNodeId: 'ev1-4f',
      targetFloorLabel: targetFloorLabel,
      steps: steps,
      timestampMs: nowMs,
    );
  }

  /// 고도를 그대로 두고 시간만 흘린다. [arm]이면 매 샘플 노드 앞에 서 있다.
  void hold(int durationMs, {bool arm = false}) {
    final until = nowMs + durationMs;
    while (nowMs < until) {
      if (arm) standAtNode();
      _pump();
    }
  }

  /// [deltaM]만큼 [speedMps]로 오르내린다. 끝 고도는 정확히 맞춘다.
  void ride(double deltaM, {double speedMps = 1.2}) {
    final target = altitudeM + deltaM;
    final stepM = speedMps * _sampleMs / 1000 * (deltaM < 0 ? -1 : 1);
    while ((target - altitudeM).abs() > stepM.abs()) {
      altitudeM += stepM;
      _pump();
    }
    altitudeM = target;
    _pump();
  }

  /// 내려서 걷기 시작했다. 걸음은 위치에 반영되지 않으므로 원시 신호로 넣는다.
  void walk({int stepCount = 2}) {
    detector.onRawMotion(
      RawMotionActivity(
        timestampMs: nowMs,
        accelPeakDelta: stepCount,
        nativeStepDelta: stepCount,
      ),
    );
  }

  /// 기압 시계열에 공백을 낸다(앱 백그라운드 복귀). [_Fixture]의 시계만 밀고
  /// 다음 샘플을 넣으면 판정기가 `timelineGap`으로 탑승을 버린다.
  void skipTimeline(int gapMs) {
    nowMs += gapMs;
    _pump();
  }

  List<ElevatorPhase> get phaseSequence =>
      changes.map((change) => change.phase).toList();
}

void main() {
  test('여러 층을 한 번에 가도 한 번에 확정된다', () {
    final fixture = _Fixture()
      ..hold(4000, arm: true)
      // 4F(+29.23) → B1(+5.83). ±1층 제한이 있으면 여기서 깨진다.
      ..ride(-23.40)
      ..hold(5000)
      ..walk()
      ..hold(1000);

    expect(fixture.confirmed, hasLength(1));
    final transition = fixture.confirmed.single;
    expect(transition.fromFloorLabel, '4F');
    expect(transition.toFloorLabel, 'B1');
    expect(transition.deltaM, closeTo(-23.40, 0.3));
    expect(transition.arrivalSource, 'table');
    expect(transition.boardingNodeId, 'ev1-4f');
    expect(transition.carName, 'EV1');
    expect(fixture.detector.pausesStepTracking, isFalse);
  });

  test('탑승 순간 걸음 정지 신호가 나오고 확정에서 풀린다', () {
    final fixture = _Fixture()
      ..hold(4000, arm: true)
      ..ride(-23.40);

    expect(fixture.detector.phase, ElevatorPhase.riding);
    expect(fixture.detector.pausesStepTracking, isTrue);
    final riding = fixture.changes.firstWhere(
      (change) => change.phase == ElevatorPhase.riding,
    );
    expect(riding.pausesStepTracking, isTrue);

    fixture
      ..hold(5000)
      ..walk()
      ..hold(1000);

    final confirmed = fixture.changes.last;
    expect(confirmed.phase, ElevatorPhase.confirmed);
    expect(confirmed.pausesStepTracking, isFalse);
  });

  test('남의 층에 섰다 다시 가면 확정되지 않는다', () {
    final fixture = _Fixture()
      ..hold(4000, arm: true)
      // 3F에 서서 문이 열렸다 닫힌다(6초). 지금 임계값이면 "멈췄다"만으로는
      // 여기서 확정된다 — 확정을 걸음에 걸어 둔 이유가 이 구간이다.
      ..ride(-5.34)
      ..hold(6000)
      ..ride(-18.06)
      ..hold(5000);

    expect(fixture.confirmed, isEmpty);
    expect(
      fixture.phaseSequence,
      containsAllInOrder([
        ElevatorPhase.riding,
        ElevatorPhase.settled,
        ElevatorPhase.riding,
        ElevatorPhase.settled,
      ]),
    );

    fixture
      ..walk()
      ..hold(1000);

    expect(fixture.confirmed, hasLength(1));
    expect(fixture.confirmed.single.toFloorLabel, 'B1');
  });

  test('settled 뒤 걸음이 없으면 확정되지 않는다', () {
    final fixture = _Fixture()
      ..hold(4000, arm: true)
      ..ride(-23.40)
      ..hold(10000);

    expect(fixture.detector.phase, ElevatorPhase.settled);
    expect(fixture.confirmed, isEmpty);

    fixture
      ..walk()
      ..hold(1000);

    expect(fixture.confirmed, hasLength(1));
  });

  test('가장 좁은 지하 한 층(B4→B3 3.23m)이 갈린다', () {
    final fixture = _Fixture(floorLabel: 'B4')
      ..hold(4000, arm: true)
      ..ride(3.23, speedMps: 0.8)
      ..hold(5000)
      ..walk()
      ..hold(1000);

    expect(fixture.confirmed, hasLength(1));
    expect(fixture.confirmed.single.toFloorLabel, 'B3');
  });

  test('표에 없는 건물이면 층을 안 바꾸고 걸음만 재개한다', () {
    final fixture = _Fixture(buildingId: 'someone-elses-mall')
      ..hold(4000, arm: true)
      ..ride(-23.40)
      ..hold(5000)
      ..walk()
      ..hold(1000);

    expect(fixture.confirmed, isEmpty);
    final last = fixture.changes.last;
    expect(last.phase, ElevatorPhase.confirmed);
    expect(last.transition, isNull);
    expect(last.reason, 'unknownTargetFloor');
    expect(last.pausesStepTracking, isFalse);
    expect(fixture.detector.pausesStepTracking, isFalse);
  });

  test('표가 없어도 경로가 아는 층은 쓴다', () {
    final fixture = _Fixture(buildingId: 'someone-elses-mall')
      ..hold(2000, arm: true)
      ..routeSaysBoard('B1')
      ..hold(2000)
      ..ride(-23.40)
      ..hold(5000)
      ..walk()
      ..hold(1000);

    expect(fixture.confirmed, hasLength(1));
    expect(fixture.confirmed.single.toFloorLabel, 'B1');
    expect(fixture.confirmed.single.arrivalSource, 'route');
  });

  test('경로가 말한 층과 Δ가 반 층 넘게 어긋나면 표로 다시 푼다', () {
    final fixture = _Fixture()
      ..hold(2000, arm: true)
      ..routeSaysBoard('B1')
      ..hold(2000)
      // 경로는 B1이라 했지만 3F에서 내렸다.
      ..ride(-5.34)
      ..hold(5000)
      ..walk()
      ..hold(1000);

    expect(fixture.confirmed, hasLength(1));
    expect(fixture.confirmed.single.toFloorLabel, '3F');
    expect(fixture.confirmed.single.arrivalSource, 'table');
  });

  test('호기가 안 서는 층은 후보에서 빠진다', () {
    final fixture = _Fixture()
      ..detector.updateContext(
        floorLabel: '4F',
        graph: _lobbyGraph(),
        buildingId: 'thehyundai-seoul',
        // EV6은 5F에 안 선다. 노드 이름이 EV1이므로 EV1의 정차 층을 준다.
        servedFloorsByCar: const {
          'EV1': {'B2', 'B1', '1F', '2F', '3F', '4F', '6F'},
        },
      );
    fixture
      ..hold(4000, arm: true)
      ..ride(5.33)
      ..hold(5000)
      ..walk()
      ..hold(1000);

    expect(fixture.confirmed, isEmpty);
    expect(fixture.changes.last.reason, 'unknownTargetFloor');
    expect(fixture.detector.pausesStepTracking, isFalse);
  });

  test('탑승 근거 없이 시간이 지나면 idle로 돌아간다', () {
    final fixture = _Fixture(
      config: const ElevatorDetectorConfig(armHoldMs: 5000),
    )..hold(1000, arm: true);

    expect(fixture.detector.phase, ElevatorPhase.armed);

    fixture.hold(8000);

    expect(fixture.detector.phase, ElevatorPhase.idle);
    final last = fixture.changes.last;
    expect(last.phase, ElevatorPhase.cancelled);
    expect(last.reason, 'armTimeout');
    expect(last.pausesStepTracking, isFalse);
  });

  test('출발 고도로 되돌아오면 취소하고 걸음을 재개한다', () {
    final fixture = _Fixture()
      ..hold(4000, arm: true)
      ..ride(5.33)
      ..hold(1000)
      ..ride(-5.33)
      ..hold(5000);

    expect(fixture.confirmed, isEmpty);
    expect(fixture.detector.phase, ElevatorPhase.idle);
    expect(fixture.detector.pausesStepTracking, isFalse);
    expect(
      fixture.changes.map((change) => change.reason),
      contains('reverted'),
    );
  });

  test('걸음이 끝내 안 잡혀도 걸음 정지는 반드시 풀린다', () {
    final fixture =
        _Fixture(
            config: const ElevatorDetectorConfig(settleFallbackConfirmMs: 4000),
          )
          ..hold(4000, arm: true)
          ..ride(-23.40)
          ..hold(12000);

    // 경로가 없으니 층은 안 바꾼다. 하지만 걸음은 풀렸다.
    expect(fixture.confirmed, isEmpty);
    expect(fixture.detector.pausesStepTracking, isFalse);
    expect(fixture.changes.last.reason, 'unverifiedTargetFloor');
  });

  test('걸음이 없어도 경로가 말한 층과 맞으면 확정한다', () {
    final fixture =
        _Fixture(
            config: const ElevatorDetectorConfig(settleFallbackConfirmMs: 4000),
          )
          ..hold(2000, arm: true)
          ..routeSaysBoard('B1')
          ..hold(2000)
          ..ride(-23.40)
          ..hold(12000);

    expect(fixture.confirmed, hasLength(1));
    expect(fixture.confirmed.single.arrivalSource, 'route');
  });

  test('노드도 경로도 없으면 판정을 시작하지 않는다', () {
    final fixture = _Fixture()
      ..hold(4000)
      ..ride(-23.40)
      ..hold(5000)
      ..walk()
      ..hold(1000);

    expect(fixture.confirmed, isEmpty);
    expect(fixture.changes, isEmpty);
    expect(fixture.detector.phase, ElevatorPhase.idle);
  });

  test('층이 바뀌면 걸음 정지가 남지 않는다', () {
    final fixture = _Fixture()
      ..hold(4000, arm: true)
      ..ride(-23.40);

    expect(fixture.detector.pausesStepTracking, isTrue);

    fixture.detector.updateContext(
      floorLabel: 'B1',
      graph: _lobbyGraph(),
      buildingId: 'thehyundai-seoul',
    );

    expect(fixture.detector.pausesStepTracking, isFalse);
    expect(fixture.detector.takePhaseChanges().last.reason, 'floorChanged');
  });

  test('elevatorServedFloorsByCar는 같은 이름을 층으로 모은다', () {
    const nodes = [
      GraphNode(
        id: 'a',
        type: 'elevator',
        name: 'EV6',
        xM: 0,
        yM: 0,
        floorId: 'f-1',
      ),
      GraphNode(
        id: 'b',
        type: 'elevator',
        name: 'EV6',
        xM: 0,
        yM: 0,
        floorId: 'f-2',
      ),
      GraphNode(
        id: 'c',
        type: 'escalator',
        name: 'ES1-UP(TO3F)',
        xM: 0,
        yM: 0,
        floorId: 'f-1',
      ),
    ];
    const labels = {'f-1': '1F', 'f-2': '2F'};

    expect(
      elevatorServedFloorsByCar(
        nodes: nodes,
        floorLabelOf: (node) => labels[node.floorId],
      ),
      {
        'EV6': {'1F', '2F'},
      },
    );
  });

  test('호기 이름을 읽는 규칙이 도착 노드 찾기와 같다', () {
    // 정차 층 후보와 도착 노드가 이름을 다르게 다루면 둘 중 한쪽만 맞는다.
    // 배포 데이터에는 이런 변형이 없지만, 규칙이 한 곳인지는 여기서 지킨다.
    const nodes = [
      GraphNode(
        id: 'a',
        type: 'elevator',
        name: 'EV1',
        xM: 0,
        yM: 0,
        floorId: 'f-1',
      ),
      GraphNode(
        id: 'b',
        type: 'elevator',
        name: ' ev1 ',
        xM: 0,
        yM: 0,
        floorId: 'f-2',
      ),
    ];
    const labels = {'f-1': '1F', 'f-2': '2F'};

    expect(
      elevatorServedFloorsByCar(
        nodes: nodes,
        floorLabelOf: (node) => labels[node.floorId],
      ),
      {
        'EV1': {'1F', '2F'},
      },
      reason: '같은 샤프트가 두 호기로 쪼개지면 후보가 반쪽만 남는다',
    );
  });

  group('하차 확정에 필요한 걸음', () {
    test('한 개로는 확정하지 않는다', () {
      // 원시 걸음은 걸음 정지 중에도 흐르는 신호라, 차 안에서 자세를 고쳐 서는
      // 것만으로 한 개가 잡힌다. 그 한 개로 확정하면 남의 층에서 문이 열린
      // 순간 내 층이 된다.
      final fixture = _Fixture()
        ..hold(4000, arm: true)
        ..ride(-23.40)
        ..hold(5000)
        ..walk(stepCount: 1)
        ..hold(1000);

      expect(fixture.confirmed, isEmpty);
      expect(fixture.detector.phase, ElevatorPhase.settled);
    });

    test('두 걸음째에 확정된다 — 늦어지는 것은 한 걸음뿐이다', () {
      final fixture = _Fixture()
        ..hold(4000, arm: true)
        ..ride(-23.40)
        ..hold(5000)
        ..walk(stepCount: 1)
        ..hold(1000)
        ..walk(stepCount: 1)
        ..hold(1000);

      expect(fixture.confirmed, hasLength(1));
      expect(fixture.confirmed.single.toFloorLabel, 'B1');
    });

    test('중간 정차에서 뒤척인 걸음은 다음 정차로 넘어가지 않는다', () {
      // 4F에서 한 걸음치 뒤척이고 다시 올라가면, 그 한 개가 다음 층 확정의
      // 절반을 미리 채워 두면 안 된다.
      final fixture = _Fixture()
        ..hold(4000, arm: true)
        ..ride(-11.0)
        ..hold(3000)
        ..walk(stepCount: 1)
        ..hold(1000)
        ..ride(-12.4)
        ..hold(5000)
        ..walk(stepCount: 1)
        ..hold(1000);

      expect(fixture.confirmed, isEmpty);
    });
  });

  group('취소 뒤 층 신뢰', () {
    test('움직인 탑승이 취소되면 다음 확정이 층을 바꾸지 않는다', () {
      // 1F→8F 중 앱을 15초 넘게 백그라운드로 보냈다 돌아온 경우다. 사람은
      // 아직 차 안이라 곧바로 다시 무장하는데, baseline은 중간 층 고도로
      // 잡히고 층 라벨은 탄 층 그대로다 — 그 둘로 푼 도착 층은 반드시 틀린다.
      final fixture = _Fixture()
        ..hold(4000, arm: true)
        ..ride(-11.0)
        ..skipTimeline(20000)
        ..hold(4000, arm: true)
        ..ride(-12.4)
        ..hold(5000)
        ..walk()
        ..hold(1000);

      expect(fixture.confirmed, isEmpty, reason: '틀린 층 하나보다 놓친 층 하나가 싸다');
      expect(fixture.changes.last.phase, ElevatorPhase.confirmed);
      expect(fixture.changes.last.reason, 'unknownTargetFloor');
      // 걸음은 반드시 풀린다 — 층을 못 정한 것과 걸음이 멈춰 있는 것은 다른 일이다.
      expect(fixture.detector.pausesStepTracking, isFalse);
    });

    test('층이 실제로 정해지면 신뢰가 돌아온다', () {
      final fixture = _Fixture()
        ..hold(4000, arm: true)
        ..ride(-11.0)
        ..skipTimeline(20000);

      // 사용자가 위치를 다시 찍었다(= 앵커 층이 새로 정해졌다).
      fixture.detector.updateContext(
        floorLabel: '1F',
        graph: _lobbyGraph(),
        buildingId: 'thehyundai-seoul',
      );
      fixture.altitudeM = 0;
      fixture
        ..hold(4000, arm: true)
        ..ride(16.29)
        ..hold(5000)
        ..walk()
        ..hold(1000);

      expect(fixture.confirmed, hasLength(1));
      expect(fixture.confirmed.single.fromFloorLabel, '1F');
    });

    test('움직이지 않은 취소는 신뢰를 건드리지 않는다', () {
      // 타려다 만 경우(`reverted`)다. 층 라벨은 여전히 탄 층이 맞다.
      final fixture = _Fixture()
        ..hold(4000, arm: true)
        ..ride(-1.0)
        ..ride(1.0)
        ..hold(4000, arm: true)
        ..ride(-23.40)
        ..hold(5000)
        ..walk()
        ..hold(1000);

      expect(fixture.confirmed, hasLength(1));
      expect(fixture.confirmed.single.toFloorLabel, 'B1');
    });
  });

  test('확정에 실리는 호기 이름은 정규화된 값이다', () {
    // 이 값이 그대로 findElevatorArrivalNode로 넘어간다. 날것으로 실으면
    // 정차 층 조회 키와 어긋난다.
    final fixture = _Fixture(carName: ' ev1 ')
      ..hold(4000, arm: true)
      ..ride(-23.40)
      ..hold(5000)
      ..walk()
      ..hold(1000);

    expect(fixture.confirmed.single.carName, 'EV1');
  });
}
