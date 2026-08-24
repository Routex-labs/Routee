import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_pdr_core/indoor_pdr_core.dart';
import 'package:navigation_client/features/indoor_navigation/application/escalator_node_naming.dart';
import 'package:navigation_client/features/indoor_navigation/application/escalator_transition_detector.dart';
import 'package:navigation_client/features/indoor_navigation/contract/altitude_sample.dart';
import 'package:navigation_client/features/indoor_navigation/contract/raw_motion_activity.dart';
import 'package:navigation_client/models/building/floor_graph.dart';

/// 표준대기 고도 → 기압. [pressureAltitudeM]의 역함수라, 테스트는 "이 고도에
/// 있었다면 센서가 봤을 기압"을 만들어 넣는다.
double _pressureForAltitudeM(double altitudeM) =>
    1013.25 * math.pow(1.0 - altitudeM / 44330.0, 1 / 0.190295);

const _floors = ['6F', '5F', '4F', '3F', '2F', '1F', 'B1'];

GraphNode _escalator(String id, String? name, double x, double y) =>
    GraphNode(id: id, type: 'escalator', name: name, xM: x, yM: y);

/// 실측 데이터와 같은 배치: 한 랜딩에 상행 탑승/도착 노드가 1.5m 거리로 붙어
/// 있고, 하행 쌍은 조금 떨어져 있다.
FloorGraph _graphFor2F() => FloorGraph(
  nodes: [
    _escalator('n-up-to3f', 'ES1-UP(TO3F)', 0, 0),
    _escalator('n-up-fr1f', 'ES1-UP(FR1F)', 1.5, 0),
    _escalator('n-dn-to1f', 'ES1-DN(TO1F)', 3.0, 0),
    _escalator('n-dn-fr3f', 'ES1-DN(FR3F)', 4.5, 0),
    GraphNode(id: 'n-far', type: 'junction', name: null, xM: 60, yM: 60),
  ],
  edges: const [],
);

FloorGraph _graphFor3F() => FloorGraph(
  nodes: [
    _escalator('n3-up-to4f', 'ES1-UP(TO4F)', 0, 0),
    _escalator('n3-up-fr2f', 'ES1-UP(FR2F)', 1.5, 0),
  ],
  edges: const [],
);

class _Fixture {
  _Fixture({
    FloorGraph? graph,
    String floorLabel = '2F',
    List<String> floorLabels = _floors,
    EscalatorDetectorConfig config = const EscalatorDetectorConfig(),
  }) : detector = EscalatorTransitionDetector(config: config) {
    detector.updateContext(
      floorLabel: floorLabel,
      graph: graph ?? _graphFor2F(),
      floorLabels: floorLabels,
    );
  }

  final EscalatorTransitionDetector detector;
  int nowMs = 1000000;
  int steps = 40;
  final started = <EscalatorTransition>[];
  final cancelled = <EscalatorTransition>[];
  final confirmed = <EscalatorTransition>[];

  /// 에스컬레이터 탑승 노드 근처에 서 있다고 알린다.
  void standNearBoarding({double x = 0.5, double y = 0.5}) {
    detector.onPosition(
      positionM: PdrLocalPoint(x, y),
      steps: steps,
      timestampMs: nowMs,
    );
  }

  /// 에스컬레이터에서 멀리 떨어진 복도에 있다고 알린다. 어느 허가 반경에도
  /// 안 들어가는 거리다(근접 6m·경로 16m·기압 16m 전부 밖).
  void standFarAway() {
    detector.onPosition(
      positionM: const PdrLocalPoint(60, 60),
      steps: steps,
      timestampMs: nowMs,
    );
  }

  /// 층 로컬 좌표 한 점에 서 있다고 알린다. 랜딩에서 보정 위치가 어긋난 상황을
  /// 만들 때 쓴다.
  void standAt(double x, double y) {
    detector.onPosition(
      positionM: PdrLocalPoint(x, y),
      steps: steps,
      timestampMs: nowMs,
    );
  }

  /// 샘플 간격(ms). 기본값은 iOS `CMAltimeter` 실측 간격이다 — 정확히 1000ms로
  /// 테스트하면 평활 창 경계에 걸리는 버그를 놓친다(실제로 놓쳤다).
  int sampleIntervalMs = 1069;

  /// 기압 보고 격자(hPa). 0이면 격자 없음(iOS `CMAltimeter`처럼 연속값).
  ///
  /// Android `TYPE_PRESSURE`는 흔히 0.01 hPa(약 8.4cm) 단위로 끊어서 준다.
  /// 5.5Hz에서 에스컬레이터가 한 샘플에 움직이는 거리는 5cm라 **격자보다
  /// 작고**, 그러면 연속 두 샘플이 같은 값으로 나와 수직 속도가 0으로 읽힌다.
  /// 판정기가 그것을 "하차"로 보면 타는 도중에 확정이 난다.
  double quantizeHpa = 0;

  /// [seconds]초 동안 고도를 [fromM] → [toM]으로 선형 변화시킨다.
  void ramp({
    required double fromM,
    required double toM,
    required int seconds,
    int stepsPerSecond = 0,
    int rawPeaksPerSample = 0,
  }) {
    final sampleCount = (seconds * 1000 / sampleIntervalMs).round();
    for (var index = 1; index <= sampleCount; index++) {
      final altitude = fromM + (toM - fromM) * (index / sampleCount);
      nowMs += sampleIntervalMs;
      if (stepsPerSecond > 0) {
        // 걸으면 snapshot이 갱신되므로 실제 앱과 같이 위치·걸음도 함께 들어온다.
        steps += (stepsPerSecond * sampleIntervalMs / 1000).round();
        standNearBoarding();
      }
      if (rawPeaksPerSample > 0) {
        // 걸음 적용이 멈춘 동안에도 흐르는 원시 움직임. `steps`는 늘지 않는다.
        detector.onRawMotion(
          RawMotionActivity(
            timestampMs: nowMs,
            accelPeakDelta: rawPeaksPerSample,
          ),
        );
      }
      feed(altitude);
    }
  }

  void hold({required double atM, required int seconds}) =>
      ramp(fromM: atM, toM: atM, seconds: seconds);

  void feed(double altitudeM) {
    var pressureHpa = _pressureForAltitudeM(altitudeM);
    if (quantizeHpa > 0) {
      pressureHpa = (pressureHpa / quantizeHpa).roundToDouble() * quantizeHpa;
    }
    final transition = detector.onAltitude(
      AltitudeSample(
        timestampMs: nowMs,
        pressureHpa: pressureHpa,
        source: 'test',
      ),
    );
    final startedTransition = detector.takeStartedTransition();
    if (startedTransition != null) started.add(startedTransition);
    final cancelledTransition = detector.takeCancelledTransition();
    if (cancelledTransition != null) cancelled.add(cancelledTransition);
    if (transition != null) confirmed.add(transition);
    phases.addAll(detector.takePhaseChanges());
  }

  final phases = <EscalatorPhaseChange>[];

  /// 활성 경로를 따라 탑승점으로 [steps]걸음 다가간다.
  void approachBoarding({
    required List<double> remainingM,
    PdrLocalPoint routeEnd = const PdrLocalPoint(0, 0),
    String boardingNodeId = 'n-up-to3f',
    String? arrivalNodeId = 'n3-up-fr2f',
    bool immediateTransfer = false,
  }) {
    for (final remaining in remainingM) {
      steps += 2;
      nowMs += 700;
      detector.onEscalatorRouteApproach(
        positionM: PdrLocalPoint(routeEnd.eastM + remaining, routeEnd.northM),
        routeEndM: routeEnd,
        expectedBoardingNodeId: boardingNodeId,
        expectedArrivalNodeId: arrivalNodeId,
        steps: steps,
        timestampMs: nowMs,
        immediateTransfer: immediateTransfer,
      );
      phases.addAll(detector.takePhaseChanges());
    }
  }

  List<EscalatorPhase> phasesOf() => phases.map((c) => c.phase).toList();

  List<String> rejectionReasons() => detector
      .takeEvents()
      .where((event) => event.kind == 'rejected')
      .map((event) => event.reason)
      .toList();
}

void main() {
  group('에스컬레이터 상행', () {
    test('탑승 노드 근처에서 한 층 올라가면 도착 층을 확정한다', () {
      final fixture = _Fixture();
      // baseline을 채우고 탑승 노드 근처에 선다.
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      // 에스컬레이터 상승: 20초에 4.5m. 그 사이 걸음은 늘지 않는다.
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);
      // 하차 후 평지.
      fixture.hold(atM: 4.5, seconds: 5);

      expect(fixture.confirmed, hasLength(1));
      final transition = fixture.confirmed.single;
      expect(transition.direction, EscalatorDirection.up);
      expect(transition.fromFloorLabel, '2F');
      expect(transition.toFloorLabel, '3F');
      expect(transition.group, 'ES1');
      expect(transition.boardingNodeId, 'n-up-to3f');
      expect(transition.boardingEvidence, 'observed');
      expect(transition.stepsDuring, 0);
      expect(transition.deltaM, closeTo(4.5, 0.5));
    });

    test('상승 중에는 확정하지 않고 멈춘 뒤에 확정한다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);
      // 아직 안정 창을 채우지 않았다 = 탑승 중.
      expect(fixture.confirmed, isEmpty);
      fixture.hold(atM: 4.5, seconds: 5);
      expect(fixture.confirmed, hasLength(1));
    });

    test('반 층을 지나면 하차 전에도 조기 층 전환 신호를 낸다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      fixture.ramp(fromM: 0, toM: 3.2, seconds: 12);

      expect(fixture.started, hasLength(1));
      expect(fixture.started.single.fromFloorLabel, '2F');
      expect(fixture.started.single.toFloorLabel, '3F');
      expect(fixture.confirmed, isEmpty);
      expect(fixture.detector.pendingTransition, isNotNull);
    });

    test('하차 뒤 첫 걸음과 수직 속도 감소가 겹치면 다음 샘플에 확정한다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);
      expect(fixture.started, hasLength(1));
      expect(fixture.confirmed, isEmpty);

      fixture.nowMs += fixture.sampleIntervalMs;
      fixture.steps++;
      fixture.standNearBoarding();
      fixture.feed(4.5);

      expect(
        fixture.confirmed,
        hasLength(1),
        reason: '하차 후 첫 걸음을 2.5초 settle 창 때문에 늦추면 안 된다',
      );
    });

    test('연속 두 층을 각각 확정한다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);
      fixture.hold(atM: 4.5, seconds: 5);
      expect(fixture.confirmed, hasLength(1));

      // 확정 뒤 화면이 3F로 바뀌고 그 층 그래프가 들어온다.
      fixture.detector.updateContext(
        floorLabel: '3F',
        graph: _graphFor3F(),
        floorLabels: _floors,
      );
      fixture.hold(atM: 4.5, seconds: 5);
      fixture.standNearBoarding();
      fixture.ramp(fromM: 4.5, toM: 9.0, seconds: 20);
      fixture.hold(atM: 9.0, seconds: 5);

      expect(fixture.confirmed, hasLength(2));
      expect(fixture.confirmed.last.fromFloorLabel, '3F');
      expect(fixture.confirmed.last.toFloorLabel, '4F');
    });

    test('하차 직후에도 상대 고도는 0에서 다시 시작한다', () {
      // 연속 환승(내리자마자 다음 에스컬레이터)에서 중요한 두 가지를 함께 본다.
      // (1) 새 0점은 **하차 시점**에 잡힌다 — 이미 올라와 있는 것으로 읽지 않는다.
      // (2) 층이 바뀌었다고 기압 창까지 버리지 않는다 — 버리면 최소 샘플을 다시
      //     채울 때까지(iOS 약 3초) 판정이 아예 죽어 두 번째 층이 늦는다.
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);
      fixture.hold(atM: 4.5, seconds: 4);
      expect(fixture.confirmed, hasLength(1));

      fixture.detector.updateContext(
        floorLabel: '3F',
        graph: _graphFor3F(),
        floorLabels: _floors,
      );

      expect(
        fixture.detector.smoothedAltitudeM,
        isNotNull,
        reason: '평활값이 null이면 다시 채울 때까지 판정이 죽는다',
      );
      final delta = fixture.detector.deltaM;
      expect(delta, isNotNull);
      expect(
        delta!.abs(),
        lessThan(0.6),
        reason: '4.5m를 올라왔어도 새 층에서의 상대 고도는 0 근처여야 한다',
      );
    });
  });

  group('센서 주기 (실측 회귀)', () {
    test('iOS 1069ms 간격에서도 평활값이 나오고 확정된다', () {
      // 실측 로그(2026-07-30, iPhone 13 Pro)에서 CMAltimeter 간격은 1069ms였다.
      // 평활 창이 2000ms일 때는 창 안에 항상 2개만 들어와 최소 샘플 수를
      // 영원히 못 채웠고, 판정기가 한 번도 돌지 않았다(smoothed_m 전 구간 null).
      final fixture = _Fixture()..sampleIntervalMs = 1069;
      fixture.hold(atM: 0, seconds: 6);
      expect(
        fixture.detector.smoothedAltitudeM,
        isNotNull,
        reason: '평활값이 null이면 이후 모든 판정이 죽는다',
      );
      expect(fixture.detector.baselineM, isNotNull);

      fixture.standNearBoarding();
      fixture.ramp(fromM: 0, toM: 6.2, seconds: 24);
      fixture.hold(atM: 6.2, seconds: 8);
      expect(fixture.confirmed, hasLength(1));
      expect(fixture.confirmed.single.toFloorLabel, '3F');
    });

    test('실측 한 층 상승폭(6.2m)은 다층으로 거부하지 않는다', () {
      // 더현대 B2→B1 실측값. 거부선이 8.0m였다면 정상 이동이 잘려 나갔다.
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 6);
      fixture.standNearBoarding();
      fixture.ramp(fromM: 0, toM: 6.2, seconds: 24);
      fixture.hold(atM: 6.2, seconds: 8);
      expect(fixture.confirmed, hasLength(1));
      expect(
        fixture.rejectionReasons(),
        isNot(contains('multiFloorUnsupported')),
      );
    });

    test('Android 180ms 간격에서도 한 층 하강은 한 번만 확정된다', () {
      // 친구 갤럭시에서 "한 층 내려가는데 층이 두 번 바뀐다"로 보고된 증상.
      // 판정 문턱이 "연속 샘플 수"였을 때, 그 2개가 iOS에서는 2.1초지만
      // Android 5.5Hz에서는 0.36초라 노이즈 한 번이 하차로 읽혔다. 그러면 타는
      // 도중에 확정이 나고 baseline이 중간 높이로 다시 잡혀, 남은 반 층이
      // **또 하나의 층 이동**이 된다.
      final fixture = _Fixture()..sampleIntervalMs = 180;
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding(x: 3.0, y: 0.5);
      fixture.ramp(fromM: 0, toM: -4.5, seconds: 20);
      fixture.hold(atM: -4.5, seconds: 5);

      expect(fixture.confirmed, hasLength(1));
      expect(fixture.confirmed.single.direction, EscalatorDirection.down);
      expect(fixture.confirmed.single.toFloorLabel, '1F');
    });

    test('기압을 0.01hPa 격자로 끊어 주는 기기에서도 타는 중에 확정하지 않는다', () {
      // 격자(8.4cm)가 한 샘플의 실제 변화(5cm)보다 커서 연속 샘플이 같은 값으로
      // 나오는 구간이 생긴다. 속도를 직전 샘플과의 차이로 재면 그때마다 0으로
      // 읽혀 "멈췄다"가 된다 — 밑변을 시간으로 고정해야 사라지는 오탐이다.
      final fixture = _Fixture()
        ..sampleIntervalMs = 180
        ..quantizeHpa = 0.01;
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding(x: 3.0, y: 0.5);
      fixture.ramp(fromM: 0, toM: -4.5, seconds: 20);
      // 아직 타는 중이다. 여기서 확정이 나 있으면 남은 반 층이 두 번째 층
      // 이동으로 이어진다.
      expect(fixture.confirmed, isEmpty);

      fixture.hold(atM: -4.5, seconds: 5);
      expect(fixture.confirmed, hasLength(1));
      expect(fixture.confirmed.single.toFloorLabel, '1F');
    });

    test('시계열이 끊긴 뒤에는 옛 고도를 섞지 않고 창을 다시 채운다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 6);
      fixture.standNearBoarding();
      // 앱이 background에 다녀와 30초 공백이 생겼고, 그 사이 고도가 바뀌었다.
      fixture.nowMs += 30000;
      fixture.feed(6.2);
      expect(
        fixture.detector.smoothedAltitudeM,
        isNull,
        reason: '공백 직후 첫 샘플로 판정하면 30초 전 고도가 중앙값에 섞인다',
      );
      expect(fixture.confirmed, isEmpty);
    });
  });

  group('탑승 중간 오확정 (2026-08-13 실측 회귀)', () {
    test('진동이 흐르는 중의 순간 저속으로는 탑승 중에 확정하지 않는다', () {
      // Samsung 실측: 발판 진동이 원시 걸음으로 세어지는 상태에서 순간 속도가
      // 한 샘플 문턱 아래로 읽히자(격자 정체) 유지 시간 없이 그 자리에서
      // 확정됐다 — Δ3.83m, 실제 층고 5.9m의 65% 지점, 하차 10초 전.
      final fixture = _Fixture()
        ..sampleIntervalMs = 180
        ..quantizeHpa = 0.01;
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      // 상승 내내 발판 진동 peak가 흐른다.
      fixture.ramp(fromM: 0, toM: 3.0, seconds: 13, rawPeaksPerSample: 2);
      // 센서가 0.54초 동안 같은 값을 준다 — 순간 속도는 문턱 아래, 진동은 계속.
      for (var i = 0; i < 3; i++) {
        fixture.nowMs += fixture.sampleIntervalMs;
        fixture.detector.onRawMotion(
          RawMotionActivity(timestampMs: fixture.nowMs, accelPeakDelta: 2),
        );
        fixture.feed(3.0);
      }
      expect(
        fixture.confirmed,
        isEmpty,
        reason: '진동은 걸음이 아니다 — 저속이 유지되지 않으면 확정하지 않는다',
      );

      // 남은 반 층을 마저 오르고 실제로 내린다.
      fixture.ramp(fromM: 3.0, toM: 5.9, seconds: 13, rawPeaksPerSample: 2);
      fixture.hold(atM: 5.9, seconds: 4);

      expect(fixture.confirmed, hasLength(1));
      expect(fixture.confirmed.single.toFloorLabel, '3F');
      expect(fixture.confirmed.single.deltaM, closeTo(5.9, 0.7));
    });

    test('확정이 하차보다 일러도 잔여 이동분이 두 번째 층이 되지 않는다', () {
      // Samsung 실측: 조기 확정으로 baseline이 탑승 중간 높이에 잡히자 남은
      // 상승 2.1m가 새 후보로 열렸고, 확정 문턱(2.2m)에 6cm 차이로만
      // 살아남았다 — 이전에 관측된 "한 번 타면 두 층"의 정체다. 확정 직후에는
      // 수직 이동이 멎을 때까지 후보를 잠그고, 멎는 순간 잔여분을 baseline에
      // 흡수해야 한다.
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);
      // 하차 첫 걸음으로 보이는 입력과 함께 그 자리에서 확정된다(조기 확정).
      fixture.nowMs += fixture.sampleIntervalMs;
      fixture.steps++;
      fixture.standNearBoarding();
      fixture.feed(4.5);
      expect(fixture.confirmed, hasLength(1));

      // 화면은 3F로 넘어갔지만 실제 탑승은 안 끝났다 — 2.5m를 더 오른다.
      fixture.detector.updateContext(
        floorLabel: '3F',
        graph: _graphFor3F(),
        floorLabels: _floors,
      );
      fixture.standNearBoarding();
      fixture.ramp(fromM: 4.5, toM: 7.0, seconds: 11);
      fixture.hold(atM: 7.0, seconds: 6);

      expect(fixture.confirmed, hasLength(1), reason: '잔여 상승분은 층 이동이 아니다');
      expect(
        fixture.started,
        hasLength(1),
        reason: '잔여 상승분으로 조기 전환 신호를 또 내면 안 된다',
      );
      expect(
        fixture.detector.deltaM!.abs(),
        lessThan(0.6),
        reason: '멎은 뒤에는 잔여분이 0점에 흡수되어야 다음 판정이 기울지 않는다',
      );
    });
  });

  group('에스컬레이터에서 걷는 경우', () {
    test('걸음이 늘어도 확정하고, 걸음 수를 근거로 남긴다', () {
      // 걸음은 확정 조건이 아니다(가점도 감점도 아님). 계단과 구분하기 위한
      // 사후 분석용으로만 기록한다.
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 6);
      fixture.standNearBoarding();
      fixture.ramp(fromM: 0, toM: 5.0, seconds: 16, stepsPerSecond: 2);
      fixture.hold(atM: 5.0, seconds: 8);

      expect(fixture.confirmed, hasLength(1));
      expect(fixture.confirmed.single.toFloorLabel, '3F');
      // 후보가 열린 시점부터 센 값이라 전체 걸음보다 작다.
      expect(fixture.confirmed.single.stepsDuring, greaterThan(5));
    });
  });

  group('원시 움직임과 하차 재개', () {
    test('걸음 적용이 멈춰 있어도 원시 움직임으로 하차를 빠르게 확정한다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      // 탑승 중: 걸음 적용은 pause라 steps가 늘지 않는다.
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);
      final beforeSteps = fixture.steps;
      // 하차: 수직 속도가 잦아드는 첫 샘플에 원시 걸음이 함께 들어온다.
      fixture.ramp(fromM: 4.5, toM: 4.5, seconds: 3, rawPeaksPerSample: 2);

      expect(fixture.steps, beforeSteps, reason: '적용 걸음은 여전히 멈춰 있어야 한다');
      expect(fixture.confirmed, hasLength(1));
      expect(fixture.confirmed.single.toFloorLabel, '3F');
    });

    test('수직 이동 중 진동 peak로는 재개하지 않는다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      // 에스컬레이터 진동이 계속 peak로 잡히지만 수직 속도는 크다.
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20, rawPeaksPerSample: 3);

      expect(
        fixture.confirmed,
        isEmpty,
        reason: '진동 peak가 아무리 많아도 오르내리는 중에는 확정하지 않는다',
      );
    });

    test('원시 움직임이 없으면 연속 저속 샘플로 확정한다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);
      fixture.hold(atM: 4.5, seconds: 5);

      expect(fixture.confirmed, hasLength(1));
    });
  });

  group('에스컬레이터 하행', () {
    test('내려가면 하행 탑승 노드의 목표 층으로 확정한다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      // 하행 탑승 노드(3.0, 0) 근처.
      fixture.standNearBoarding(x: 3.0, y: 0.5);
      fixture.ramp(fromM: 0, toM: -4.5, seconds: 20);
      fixture.hold(atM: -4.5, seconds: 5);

      expect(fixture.confirmed, hasLength(1));
      expect(fixture.confirmed.single.direction, EscalatorDirection.down);
      expect(fixture.confirmed.single.toFloorLabel, '1F');
      expect(fixture.confirmed.single.boardingEvidence, 'observed');
      expect(fixture.confirmed.single.boardingNodeId, 'n-dn-to1f');
    });

    test('활성 경로가 하행 탑승점을 가리키면 12m 위치 오차에서도 확정한다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.detector.onEscalatorRouteApproach(
        // 실측 로그처럼 보정 위치는 탑승점보다 늦게 따라온다.
        positionM: const PdrLocalPoint(15, 0),
        routeEndM: const PdrLocalPoint(3, 0),
        expectedBoardingNodeId: 'n-dn-to1f',
        expectedArrivalNodeId: 'n1-dn-fr2f',
        steps: fixture.steps,
        timestampMs: fixture.nowMs,
      );
      fixture.ramp(fromM: 0, toM: -5.5, seconds: 24);
      fixture.hold(atM: -5.5, seconds: 6);

      expect(fixture.confirmed, hasLength(1));
      expect(fixture.confirmed.single.direction, EscalatorDirection.down);
      expect(fixture.confirmed.single.toFloorLabel, '1F');
      expect(fixture.confirmed.single.boardingEvidence, 'routeExpected');
      expect(fixture.confirmed.single.expectedArrivalNodeId, 'n1-dn-fr2f');
    });

    test('허가가 늦게 걸려도 그 전 하강분을 baseline이 먹지 않는다', () {
      // 보정 위치가 탑승 노드에 늦게 수렴하는 경우(하행 랜딩 실측). 허가 전에
      // 이미 내려간 만큼이 baseline에 흡수되면, 허가 시점의 Δ가 0에 가까워져
      // 사용자는 이미 반쯤 내려왔는데 판정은 처음부터 다시 시작한다.
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standFarAway();
      fixture.ramp(fromM: 0, toM: -2.0, seconds: 8);

      final deltaBeforeArming = fixture.detector.deltaM;
      expect(deltaBeforeArming, isNotNull);
      expect(
        deltaBeforeArming!.abs(),
        greaterThan(1.5),
        reason: '움직이는 중에는 baseline이 하강분을 따라가지 않아야 한다',
      );
    });
  });

  group('단계 분리', () {
    test('탑승점 접근만으로 배너 단계에 올라가고 층은 그대로다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.approachBoarding(remainingM: const [12, 8, 4, 2]);

      expect(fixture.phasesOf(), contains(EscalatorPhase.boardingDetected));
      final boarding = fixture.phases.firstWhere(
        (change) => change.phase == EscalatorPhase.boardingDetected,
      );
      expect(boarding.fromFloorLabel, '2F');
      expect(boarding.toFloorLabel, '3F');
      expect(boarding.boardingNodeId, 'n-up-to3f');
      expect(boarding.expectedArrivalNodeId, 'n3-up-fr2f');
      expect(fixture.started, isEmpty, reason: '층 전환은 아직 시작하지 않는다');
      expect(fixture.confirmed, isEmpty);
    });

    test('한 프레임 근접만으로는 배너를 띄우지 않는다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.approachBoarding(remainingM: const [2]);

      expect(
        fixture.phasesOf(),
        isNot(contains(EscalatorPhase.boardingDetected)),
      );
    });

    test('탑승점에서 분명히 멀어지면 배너 단계를 되돌린다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.approachBoarding(remainingM: const [12, 8, 4, 2]);
      fixture.approachBoarding(remainingM: const [6, 10]);

      expect(fixture.phasesOf(), contains(EscalatorPhase.cancelled));
    });

    test('탑승점을 지나 올라서는 동안에는 배너를 접지 않는다', () {
      // 실기기 증상: 에스컬레이터 노드 앞까지 가서 실제로 탔는데 배너가 풀리고
      // 멈춰야 할 걸음이 다시 흘러 마커가 복도를 걸어갔다. 탑승점을 **통과**하는
      // 순간부터 거리는 계속 늘어나므로, 그것을 이탈로 읽으면 안 된다.
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.approachBoarding(remainingM: const [12, 8, 4, 2]);
      expect(fixture.phasesOf(), contains(EscalatorPhase.boardingDetected));

      fixture.approachBoarding(remainingM: const [1, 2, 3.5, 5]);

      expect(
        fixture.phasesOf(),
        isNot(contains(EscalatorPhase.cancelled)),
        reason: '올라선 만큼 멀어지는 것은 탑승의 증거지 이탈의 증거가 아니다',
      );
    });

    test('탑승점을 지나 올라서면 그대로 층 전환까지 간다', () {
      // 위 테스트의 결과가 실제로 무엇을 살리는지 — 배너가 유지되어야 걸음이
      // 멈추고([verticalMotionDetected]) 도면 교체와 확정까지 이어진다.
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.approachBoarding(remainingM: const [12, 8, 4, 2]);
      fixture.approachBoarding(remainingM: const [1, 2, 3.5, 5]);
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);
      fixture.hold(atM: 4.5, seconds: 5);

      expect(fixture.confirmed, hasLength(1));
      expect(fixture.confirmed.single.toFloorLabel, '3F');
    });

    test('허가 반경 밖으로 걸어가면 타임아웃을 기다리지 않고 접는다', () {
      // 예전에는 이 경로가 _resetApproach만 하고 단계를 두어, 탑승점을 지나쳐
      // 걸어간 사용자에게 배너가 40초 동안 남았다.
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.approachBoarding(remainingM: const [12, 8, 4, 2]);
      fixture.approachBoarding(remainingM: const [20]);

      expect(fixture.phasesOf(), contains(EscalatorPhase.cancelled));
    });

    test('걸음 pause는 지도 전환 문턱 이전 수직 속도에서 시작한다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.approachBoarding(remainingM: const [12, 8, 4, 2]);
      // 지도 전환 문턱(minDeltaM)에 한참 못 미치는 0.8m만 오른다.
      fixture.ramp(fromM: 0, toM: 0.8, seconds: 5);

      expect(
        fixture.phasesOf(),
        contains(EscalatorPhase.verticalMotionDetected),
      );
      expect(
        fixture.phasesOf(),
        isNot(contains(EscalatorPhase.midpointReached)),
        reason: '목적 층 지도는 midpoint 근거 전에는 열지 않는다',
      );
    });

    test('지도 전환은 반 층 부근에서 열린다', () {
      // 실측 층고 4.5m를 20초에 오르는 에스컬레이터(0.22 m/s). 처음에는 후보
      // 문턱(1.2m)에서 바로 도면을 갈았는데, 2026-08-13 더현대 실측에서 26초
      // 탑승 중 21초를 도착 층 도면으로 보게 되어 "층 전환이 너무 빠르다"는
      // 피드백을 받았다. 지금은 반 층 부근(mapSwapDeltaM)에서 간다. 너무 이른
      // 쪽과 너무 늦은 쪽 회귀를 모두 여기서 잡는다.
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);

      final midpoint = fixture.phases
          .where((change) => change.phase == EscalatorPhase.midpointReached)
          .firstOrNull;
      expect(midpoint, isNotNull, reason: '탑승 중에 지도가 넘어가야 한다');
      expect(
        midpoint!.deltaM.abs(),
        greaterThanOrEqualTo(2.4),
        reason: '후보 문턱(1.2m)에서 바로 갈면 탑승 대부분을 도착 층 도면으로 보낸다',
      );
      expect(
        midpoint.deltaM.abs(),
        lessThan(3.4),
        reason: '하차 직전에야 갈리면 조기 전환의 의미가 없다',
      );
    });

    test('층 지도 전환과 하차 재개는 서로 다른 시점이다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);
      final midpointIndex = fixture.phasesOf().indexOf(
        EscalatorPhase.midpointReached,
      );
      expect(midpointIndex, greaterThanOrEqualTo(0));
      expect(fixture.phasesOf(), isNot(contains(EscalatorPhase.landed)));

      fixture.hold(atM: 4.5, seconds: 5);
      final landedIndex = fixture.phasesOf().indexOf(EscalatorPhase.landed);
      expect(landedIndex, greaterThan(midpointIndex));
    });

    test('접근만 하고 지나가면 제한 시간 뒤 단계를 되돌린다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.approachBoarding(remainingM: const [12, 8, 4, 2]);
      expect(fixture.phasesOf(), contains(EscalatorPhase.boardingDetected));

      // 고도 변화 없이 제한 시간을 넘긴다.
      fixture.hold(atM: 0, seconds: 50);

      expect(fixture.phasesOf(), contains(EscalatorPhase.cancelled));
    });
  });

  group('2차 감지 — 탑승점 근접으로 올라가는 갈래', () {
    // 허가 반경(6m, 경로가 지목하면 16m)은 "층을 바꿔도 되는가"의 허가일 뿐이다.
    // 그 거리에서 마커를 세우면 사용자는 아직 통로 한복판을 걷고 있는데 점만
    // 저 앞 에스컬레이터에 붙어 멈춘 화면을 본다.

    test('허가만 걸리고 아직 멀면 사용자에게 알리지 않는다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      // 허가 반경(6m) 안이지만 탑승 반경(3m) 밖이다.
      fixture.standNearBoarding(x: 5, y: 0);
      // 아직 누적 고도 갈래(1.8m)에도 못 미친다.
      fixture.ramp(fromM: 0, toM: 1.0, seconds: 4, rawPeaksPerSample: 2);

      expect(
        fixture.phasesOf(),
        isNot(contains(EscalatorPhase.verticalMotionDetected)),
      );
    });

    test('탑승점까지 붙으면 그때 알린다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding(x: 5, y: 0);
      fixture.ramp(fromM: 0, toM: 0.5, seconds: 2, rawPeaksPerSample: 2);
      expect(
        fixture.phasesOf(),
        isNot(contains(EscalatorPhase.verticalMotionDetected)),
      );

      fixture.standNearBoarding();
      fixture.ramp(fromM: 0.5, toM: 1.2, seconds: 3, rawPeaksPerSample: 2);

      final change = fixture.phases.firstWhere(
        (c) => c.phase == EscalatorPhase.verticalMotionDetected,
      );
      expect(change.reason, 'rising');
      expect(change.boardingNodeId, 'n-up-to3f');
    });
  });

  group('2차 감지 — 안내가 지목한 에스컬레이터', () {
    test('기압 노이즈 한 번으로는 멈추지 않는다', () {
      // 빠른 EMA는 튐 하나를 0.6 m/s로 읽는다. 속도만 보면 복도를 걷는 동안에도
      // 단계가 올라가고, 그때마다 마커가 탑승 노드로 끌려갔다 돌아온다.
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.approachBoarding(remainingM: const [14, 11, 8]);
      // 0.4m 올랐다 그대로 되돌아오는 튐.
      fixture.ramp(fromM: 0, toM: 0.4, seconds: 2, rawPeaksPerSample: 2);
      fixture.ramp(fromM: 0.4, toM: 0, seconds: 2, rawPeaksPerSample: 2);

      expect(
        fixture.phasesOf(),
        isNot(contains(EscalatorPhase.verticalMotionDetected)),
      );
    });

    test('연속 환승이면 최소 변화를 기다리지 않는다', () {
      // 내리자마자 두어 걸음 옆의 다음 에스컬레이터를 타는 구간. 걸어갈 거리가
      // 없으니 기다릴 이유가 없고, 기다리면 환승마다 마커가 먼저 흘러간다.
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.approachBoarding(
        remainingM: const [3, 2],
        immediateTransfer: true,
      );
      // 최소 변화(0.5m)에 못 미치는 0.45m만 오른다.
      fixture.ramp(fromM: 0, toM: 0.45, seconds: 3, rawPeaksPerSample: 2);

      expect(
        fixture.phasesOf(),
        contains(EscalatorPhase.verticalMotionDetected),
      );
    });

    test('연속 환승이 아니면 같은 변화로는 아직 멈추지 않는다', () {
      // 위 테스트와 **같은 시계열**이다. 다른 것은 안내가 알려 준 연속 환승
      // 여부뿐이라, 그 신호가 실제로 문턱을 낮춘다는 것을 이 쌍이 고정한다.
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.approachBoarding(remainingM: const [3, 2]);
      fixture.ramp(fromM: 0, toM: 0.45, seconds: 3, rawPeaksPerSample: 2);

      expect(
        fixture.phasesOf(),
        isNot(contains(EscalatorPhase.verticalMotionDetected)),
      );
    });

    test('경로가 지목했으면 3m까지 붙기 전에도 걸음을 멈춘다', () {
      // "다음에 탈 것"이 정해져 있고 기압이 실제로 오르내리면 그 둘로 이미
      // 확정에 가깝다. 여기서 3m를 더 기다리면 보정 위치가 늦게 수렴하는
      // 랜딩에서 영영 안 걸린다.
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      // 경로 끝(탑승점)에서 아직 8m 떨어져 있다.
      fixture.approachBoarding(remainingM: const [14, 11, 8]);
      fixture.ramp(fromM: 0, toM: 1.0, seconds: 4, rawPeaksPerSample: 2);

      final change = fixture.phases.firstWhere(
        (c) => c.phase == EscalatorPhase.verticalMotionDetected,
      );
      expect(change.reason, 'rising');
      expect(change.boardingNodeId, 'n-up-to3f');
      expect(
        change.deltaM.abs(),
        lessThan(1.2),
        reason: '누적 고도 갈래가 아니라 경로 지목으로 걸렸다',
      );
    });
  });

  group('2차 감지 — 누적 고도로 올라가는 갈래', () {
    // 탑승 노드를 아무 반경으로도 못 고르는 구간(여기 테스트들은 60m 밖에 선다)
    // 에서도 걸음은 멈춰야 한다 — 몸이 수직으로 실려 가는 중이라는 근거는 기압이
    // 이미 주고 있다. 대신 층은 바꾸지 않는다. 노드를 고를 수 있는 거리면 그때는
    // 층까지 바꾼다(아래 「기압 근거 허가」).

    test('허가가 없어도 누적 고도가 문턱을 넘으면 걸음을 멈춘다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      // 위치를 한 번도 탑승 노드 근처로 주지 않는다(허가 없음).
      fixture.standFarAway();
      fixture.ramp(fromM: 0, toM: -3, seconds: 10, rawPeaksPerSample: 2);

      final change = fixture.phases.firstWhere(
        (c) => c.phase == EscalatorPhase.verticalMotionDetected,
      );
      expect(change.reason, 'fallingByAltitude');
      expect(change.toFloorLabel, '1F', reason: '2F에서 내려가면 한 칸 아래는 1F다');
      expect(change.boardingNodeId, isNull);
      expect(fixture.started, isEmpty, reason: '층은 노드 허가 없이 바꾸지 않는다');
      expect(fixture.confirmed, isEmpty);
    });

    test('중앙값이 문턱에 닿기 전에 빠른 적분으로 먼저 멈춘다', () {
      // 중앙값 평활은 창 절반(약 1.1초)만큼 뒤처진다. 그 1초가 곧 발판 진동이
      // 위치에 쌓이는 시간이라, 걸음 정지만은 덜 늦은 값으로 건다.
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standFarAway();
      fixture.ramp(fromM: 0, toM: -2.0, seconds: 7, rawPeaksPerSample: 2);

      final change = fixture.phases.firstWhere(
        (c) => c.phase == EscalatorPhase.verticalMotionDetected,
      );
      expect(
        change.deltaM.abs(),
        lessThan(1.2),
        reason: '중앙값 delta가 아직 문턱에 못 미친 시점에 이미 멈춰야 한다',
      );
    });

    test('문턱에 못 미치는 고도 변화로는 멈추지 않는다', () {
      // 1차 감지(수직 속도)는 서지만 화면에는 알리지 않는다. 근거가 옅은
      // 시점에 마커를 세우면 아직 통로를 걷는 사용자의 점이 먼저 멈춰 버린다.
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standFarAway();
      fixture.ramp(fromM: 0, toM: -0.9, seconds: 3, rawPeaksPerSample: 2);

      expect(
        fixture.phasesOf(),
        isNot(contains(EscalatorPhase.verticalMotionDetected)),
      );
    });

    test('기기가 멈춰 있으면 고도가 변해도 멈추지 않는다', () {
      // 책상 위에 둔 폰의 기압 드리프트로 화면이 덮이면 안 된다.
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standFarAway();
      fixture.ramp(fromM: 0, toM: -3, seconds: 10);

      expect(
        fixture.phasesOf(),
        isNot(contains(EscalatorPhase.verticalMotionDetected)),
      );
    });

    test('수직 이동이 멎으면 곧바로 접는다', () {
      // 하차를 확정할 노드가 없으므로 40초 타임아웃을 기다리면 안 된다 —
      // 내려서 걷기 시작한 사용자에게 그 시간은 앱이 죽은 것과 같다.
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standFarAway();
      fixture.ramp(fromM: 0, toM: -3, seconds: 10, rawPeaksPerSample: 2);
      expect(
        fixture.phasesOf(),
        contains(EscalatorPhase.verticalMotionDetected),
      );

      fixture.hold(atM: -3, seconds: 5);

      expect(fixture.phasesOf(), contains(EscalatorPhase.cancelled));
    });
  });

  group('기압 근거 허가', () {
    // 2026-08-17 현장: "1F → B1 이동 중" 배너는 뜨는데 층이 끝내 안 바뀌었다.
    // 근접 허가(6m)가 랜딩에서 안 걸리면 후보 자체가 안 열려, 화면은 이동을
    // 말하면서 아무 일도 일어나지 않는 상태로 남는다.

    test('보정 위치가 탑승 노드에서 12m 어긋나도 층을 바꾼다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      // 근접 허가 반경(6m) 밖이고 기압 허가 반경(16m) 안이다.
      fixture.standAt(12, 0);
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20, rawPeaksPerSample: 2);
      fixture.hold(atM: 4.5, seconds: 5);

      expect(fixture.confirmed, hasLength(1));
      final transition = fixture.confirmed.single;
      expect(transition.toFloorLabel, '3F');
      expect(transition.boardingNodeId, 'n-up-to3f');
      // 근거를 따로 적어 둔다 — 현장 로그에서 "근접으로 걸린 것"과 구분해야
      // 이 갈래가 실제로 얼마나 쓰이는지 셀 수 있다.
      expect(transition.boardingEvidence, 'altitudeArmed');
    });

    test('기압 부호와 반대인 탑승 노드는 고르지 않는다', () {
      // 위치만 보면 하행 노드가 더 가깝다(9m vs 12m). 올라가는 중이므로
      // 상행 노드가 아니면 아무것도 고르지 않아야 한다.
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standAt(12, 0);
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20, rawPeaksPerSample: 2);
      fixture.hold(atM: 4.5, seconds: 5);

      expect(fixture.confirmed.single.direction, EscalatorDirection.up);
      expect(fixture.confirmed.single.boardingNodeId, 'n-up-to3f');
    });

    test('두 뱅크가 함께 잡히면 아무것도 허가하지 않는다', () {
      // 어느 것을 탔는지 가릴 근거가 없다. 층을 잘못 바꾸는 비용이 못 바꾸는
      // 비용보다 크므로 여기서는 판정하지 않는다.
      final fixture = _Fixture(
        graph: FloorGraph(
          nodes: [
            _escalator('a-up-to3f', 'ES1-UP(TO3F)', 0, 0),
            _escalator('b-up-to3f', 'ES2-UP(TO3F)', 28, 0),
          ],
          edges: const [],
        ),
      );
      fixture.hold(atM: 0, seconds: 5);
      // 두 뱅크에서 각각 14m — 근접 허가 밖이고 기압 허가 안이다.
      fixture.standAt(14, 0);
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20, rawPeaksPerSample: 2);
      fixture.hold(atM: 4.5, seconds: 5);

      expect(fixture.started, isEmpty);
      expect(fixture.confirmed, isEmpty);
    });

    test('기압 허가 반경 밖이면 예전처럼 층을 바꾸지 않는다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standAt(20, 0);
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20, rawPeaksPerSample: 2);
      fixture.hold(atM: 4.5, seconds: 5);

      expect(fixture.started, isEmpty);
      expect(fixture.confirmed, isEmpty);
    });

    test('기기가 멈춰 있으면 기압만으로 허가하지 않는다', () {
      // 책상 위 폰의 기압 드리프트가 층을 바꾸면 안 된다. rawPeaks 없이 같은
      // 고도 변화를 준다.
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standAt(12, 0);
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);
      fixture.hold(atM: 4.5, seconds: 5);

      expect(fixture.started, isEmpty);
      expect(fixture.confirmed, isEmpty);
    });
  });

  group('오탐 방어', () {
    test('가까운 도착 노드가 같은 그룹의 먼 탑승 노드를 대신 허가하지 않는다', () {
      final fixture = _Fixture(
        graph: FloorGraph(
          nodes: [
            _escalator('arrival', 'ES2-UP(FR1F)', 0, 0),
            _escalator('far-boarding', 'ES2-UP(TO3F)', 15, 0),
          ],
          edges: const [],
        ),
      );
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding(x: 0, y: 0);
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);
      fixture.hold(atM: 4.5, seconds: 5);

      expect(fixture.confirmed, isEmpty);
      expect(fixture.detector.isArmed, isFalse);
    });

    test('붙어 있는 같은 방향 두 레인은 경로가 없으면 가장 가까운 것을 쓴다', () {
      final fixture = _Fixture(
        graph: FloorGraph(
          nodes: [
            _escalator('lane-a', 'ES2-UP(TO3F)', 0, 0),
            _escalator('lane-b', 'ES2-1-UP(TO3F)', 1, 0),
          ],
          edges: const [],
        ),
      );
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding(x: 0.5, y: 0);
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);
      fixture.hold(atM: 4.5, seconds: 5);

      expect(fixture.confirmed, hasLength(1));
      expect(fixture.confirmed.single.boardingNodeId, 'lane-a');
    });

    test('붙어 있는 레인에서는 활성 경로가 고른 정확한 탑승 노드를 우선한다', () {
      final fixture = _Fixture(
        graph: FloorGraph(
          nodes: [
            _escalator('lane-a', 'ES2-UP(TO3F)', 0, 0),
            _escalator('lane-b', 'ES2-1-UP(TO3F)', 1, 0),
          ],
          edges: const [],
        ),
      );
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding(x: 0.5, y: 0);
      fixture.detector.onEscalatorRouteApproach(
        positionM: const PdrLocalPoint(0.5, 0),
        routeEndM: const PdrLocalPoint(1, 0),
        expectedBoardingNodeId: 'lane-b',
        expectedArrivalNodeId: 'lane-b-arrival',
        steps: fixture.steps,
        timestampMs: fixture.nowMs,
      );
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);
      fixture.hold(atM: 4.5, seconds: 5);

      expect(fixture.confirmed, hasLength(1));
      expect(fixture.confirmed.single.boardingNodeId, 'lane-b');
      expect(fixture.confirmed.single.expectedArrivalNodeId, 'lane-b-arrival');
      expect(fixture.confirmed.single.boardingEvidence, 'routeAndObserved');
    });

    test('에스컬레이터에서 멀면 같은 상승에도 층을 바꾸지 않는다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standFarAway();
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);
      fixture.hold(atM: 4.5, seconds: 10);

      expect(fixture.confirmed, isEmpty);
    });

    test('활성 경로가 있어도 16m 밖이면 기압 변화만으로 허가하지 않는다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.detector.onEscalatorRouteApproach(
        positionM: const PdrLocalPoint(25, 0),
        routeEndM: const PdrLocalPoint(3, 0),
        expectedBoardingNodeId: 'n-dn-to1f',
        steps: fixture.steps,
        timestampMs: fixture.nowMs,
      );
      fixture.ramp(fromM: 0, toM: -5.5, seconds: 24);
      fixture.hold(atM: -5.5, seconds: 6);

      expect(fixture.confirmed, isEmpty);
    });

    test('층 안에 서서 기상 드리프트만 있으면 확정하지 않는다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      // 노드 근처에 계속 서 있어도(허가 상태) 5분에 걸친 3m 드리프트는
      // 에스컬레이터가 아니다 — baseline 추적과 안정 조건이 함께 막는다.
      for (var second = 0; second < 300; second++) {
        fixture.standNearBoarding();
        fixture.nowMs += 1000;
        fixture.feed(3.0 * second / 300);
      }
      expect(fixture.confirmed, isEmpty);
    });

    test('올라갔다 바로 돌아오면 reverted로 거부한다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      // 후보가 열릴 만큼(누적 2.5m 이상) 올라갔다가 되돌아온다.
      fixture.ramp(fromM: 0, toM: 3.5, seconds: 7);
      fixture.ramp(fromM: 3.5, toM: 0, seconds: 7);
      fixture.hold(atM: 0, seconds: 5);

      expect(fixture.confirmed, isEmpty);
      expect(fixture.rejectionReasons(), contains('reverted'));
      expect(fixture.cancelled, hasLength(1));
      expect(fixture.cancelled.single.toFloorLabel, '3F');
    });

    test('여러 층 이동은 층고를 추측하지 않고 거부한다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      // 엘리베이터로 2층 이상 이동한 경우.
      fixture.ramp(fromM: 0, toM: 10.0, seconds: 20);
      fixture.hold(atM: 10.0, seconds: 5);

      expect(fixture.confirmed, isEmpty);
      expect(fixture.rejectionReasons(), contains('multiFloorUnsupported'));
    });

    test('기압 방향과 반대인 에스컬레이터만 근처에 있으면 거부한다', () {
      // 하행 노드만 있는 층에서 고도가 올라갔다 = 에스컬레이터로 설명되지 않는다.
      final fixture = _Fixture(
        graph: FloorGraph(
          nodes: [
            _escalator('n-dn-to1f', 'ES1-DN(TO1F)', 0, 0),
            _escalator('n-dn-fr3f', 'ES1-DN(FR3F)', 1.5, 0),
          ],
          edges: const [],
        ),
      );
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);
      fixture.hold(atM: 4.5, seconds: 5);

      expect(fixture.confirmed, isEmpty);
      expect(fixture.rejectionReasons(), contains('noBoardingNode'));
    });

    test('이름 규칙이 없는 데이터에서는 판정 자체가 돌지 않는다', () {
      final fixture = _Fixture(
        graph: FloorGraph(
          nodes: [
            _escalator('n-a', '에스컬레이터', 0, 0),
            _escalator('n-b', null, 1.5, 0),
          ],
          edges: const [],
        ),
      );
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);
      fixture.hold(atM: 4.5, seconds: 5);

      expect(fixture.confirmed, isEmpty);
      expect(fixture.detector.isArmed, isFalse);
    });

    test('이름이 가리키는 층이 건물 층 목록에 없으면 거부한다', () {
      final fixture = _Fixture(floorLabels: const ['1F', '2F']);
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      fixture.ramp(fromM: 0, toM: 4.5, seconds: 20);
      fixture.hold(atM: 4.5, seconds: 5);

      expect(fixture.confirmed, isEmpty);
      expect(fixture.rejectionReasons(), contains('unknownTargetFloor'));
    });

    test('층을 수동으로 바꾸면 baseline과 허가를 버린다', () {
      final fixture = _Fixture();
      fixture.hold(atM: 0, seconds: 5);
      fixture.standNearBoarding();
      fixture.ramp(fromM: 0, toM: 2.0, seconds: 4);
      // 사용자가 층 선택기로 다른 층을 훑어본다.
      fixture.detector.updateContext(
        floorLabel: '5F',
        graph: _graphFor3F(),
        floorLabels: _floors,
      );
      expect(fixture.detector.isArmed, isFalse);
      expect(fixture.detector.baselineM, isNull);
      // 이어지는 상승은 새 baseline 기준이라 직전 2m를 이어받지 않는다.
      fixture.hold(atM: 2.0, seconds: 5);
      expect(fixture.confirmed, isEmpty);
    });
  });
}
