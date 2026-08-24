import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:navigation_client/features/indoor_navigation/contract/indoor_navigation_contract.dart';
import 'package:navigation_client/screens/outdoor_map/entry/manual_transition_gate.dart';

/// 실내↔야외 전환 버튼이 **언제 눌리는지**의 검증 기준.
///
/// 이 게이트는 화면 상태를 바꾸지 않는다 — 틀려도 버튼 색이 틀릴 뿐이다. 그래서
/// 예전 자동 판정과 달리 오차 문턱이 없고, 임계값도 훨씬 넉넉하다. 근거는
/// `docs/client/indoor-entry-rules.md` 6절.
void main() {
  const metersPerDegreeLat = 111320.0;

  /// 위도 37.5663~37.5667, 경도 126.9777~126.9783인 직사각형. 북쪽 변이
  /// 37.5667이라 거기서 북쪽으로 잰 거리로 게이트를 흔든다.
  const footprint = [
    ll.LatLng(37.5663, 126.9777),
    ll.LatLng(37.5667, 126.9777),
    ll.LatLng(37.5667, 126.9783),
    ll.LatLng(37.5663, 126.9783),
  ];

  /// 북쪽 변에서 [meters]만큼 **바깥**으로 나간 좌표.
  ll.LatLng northOf(double meters) =>
      ll.LatLng(37.5667 + meters / metersPerDegreeLat, 126.9780);

  group('manualIndoorEntryGate', () {
    test('반경 안이면 켜고, 잰 거리를 함께 돌려준다', () {
      final gate = manualIndoorEntryGate(
        fix: northOf(manualIndoorEntryRadiusMeters - 10),
        footprint: footprint,
      );
      expect(gate.enabled, isTrue);
      expect(
        gate.distanceM,
        closeTo(manualIndoorEntryRadiusMeters - 10, 1),
        reason: '진단 칩이 이 값을 그대로 적는다 — 다시 계산하면 동작과 어긋난다',
      );
    });

    test('반경 밖이면 끈다', () {
      final gate = manualIndoorEntryGate(
        fix: northOf(manualIndoorEntryRadiusMeters + 10),
        footprint: footprint,
      );
      expect(gate.enabled, isFalse);
      expect(gate.distanceM, isNotNull);
    });

    test('건물 안 좌표는 거리 0이라 당연히 켜진다', () {
      // 실내에서 앱을 켠 사람도 버튼 하나로 들어갈 수 있어야 한다. 여기서
      // 거리를 음수로 만들면 진단 칩이 `진입 -3.0m`처럼 읽을 수 없게 나온다.
      final gate = manualIndoorEntryGate(
        fix: const ll.LatLng(37.5665, 126.9780),
        footprint: footprint,
      );
      expect(gate.enabled, isTrue);
      expect(gate.distanceM, 0);
    });

    test('오차는 보지 않는다 — 켜져 있어도 누르지 않으면 아무 일도 없다', () {
      // 게이트는 GpsFix가 아니라 좌표만 받는다. 오차를 넘길 자리 자체가 없다는
      // 것이 이 계약이고, 이 테스트가 그 서명을 붙들어 둔다.
      final gate = manualIndoorEntryGate(fix: northOf(5), footprint: footprint);
      expect(gate.enabled, isTrue);
    });

    test('좌표나 외곽선을 모르면 근거 없이 끈다', () {
      expect(
        manualIndoorEntryGate(fix: null, footprint: footprint).distanceM,
        isNull,
      );
      expect(
        manualIndoorEntryGate(fix: northOf(1), footprint: null).enabled,
        isFalse,
      );
      // 점이 3개 미만이면 폴리곤이 아니다. 거리 0으로 읽혀 "건물 안"이 되면
      // 외곽선을 아직 못 받은 동안 버튼이 통째로 켜진다.
      expect(
        manualIndoorEntryGate(
          fix: northOf(1),
          footprint: const [ll.LatLng(37.5663, 126.9777)],
        ).enabled,
        isFalse,
      );
    });
  });

  group('manualOutdoorExitGate', () {
    const doorA = PdrLocalPoint(18, 22);
    const doorB = PdrLocalPoint(80, 22);

    test('어느 문이든 반경 안이면 켠다', () {
      // **경로가 정한 문만 세지 않는 것이 요점이다.** 실내 재탐색은 목적지
      // 노드를 바꾸지 않아, 다른 문으로 걸어간 사용자는 그쪽만 세면 갇힌다.
      final gate = manualOutdoorExitGate(
        positionM: const PdrLocalPoint(80, 30),
        entranceNodesM: const [doorA, doorB],
      );
      expect(gate.enabled, isTrue);
      expect(gate.distanceM, closeTo(8, 0.01), reason: 'doorB까지의 거리여야 한다');
    });

    test('가장 가까운 문까지의 거리로 판정한다', () {
      final gate = manualOutdoorExitGate(
        positionM: const PdrLocalPoint(49, 22),
        entranceNodesM: const [doorA, doorB],
      );
      expect(gate.distanceM, closeTo(31, 0.01));
      expect(gate.enabled, isFalse);
    });

    test('반경 밖이면 끈다', () {
      final gate = manualOutdoorExitGate(
        positionM: PdrLocalPoint(18, 22 + manualOutdoorExitRadiusMeters + 5),
        entranceNodesM: const [doorA],
      );
      expect(gate.enabled, isFalse);
    });

    test('문 목록이 비면 근거 없이 끈다', () {
      // 부르는 쪽이 **출입구 층이 아닐 때** 빈 목록을 넘긴다. 같은 local m
      // 숫자가 층마다 다른 자리라, 여기서 켜면 지하 3층에서 나가기가 눌린다.
      final gate = manualOutdoorExitGate(
        positionM: doorA,
        entranceNodesM: const [],
      );
      expect(gate.enabled, isFalse);
      expect(gate.distanceM, isNull);
    });

    test('실내 위치가 없으면 근거 없이 끈다', () {
      final gate = manualOutdoorExitGate(
        positionM: null,
        entranceNodesM: const [doorA],
      );
      expect(gate.enabled, isFalse);
      expect(gate.distanceM, isNull);
    });
  });

  group('describeManualTransitionGate', () {
    test('잰 거리와 임계값을 함께 적는다', () {
      expect(
        describeManualTransitionGate(
          const ManualTransitionGate(enabled: true, distanceM: 12.44),
          label: '진입',
          radiusMeters: 30,
        ),
        '진입 12.4m/30m · 켬',
      );
    });

    test('근거가 없으면 거리를 지어내지 않는다', () {
      // `진입 0.0m/30m · 끔`으로 적으면 "문 앞인데 왜 안 켜지지"로 읽힌다.
      // 실제로는 잴 외곽선이 없다는 뜻이라 원인이 완전히 다르다.
      expect(
        describeManualTransitionGate(
          ManualTransitionGate.unknown,
          label: '나가기',
          radiusMeters: 15,
        ),
        '나가기 근거없음',
      );
    });
  });

  /// 나온 문에 못박아 둔 야외 구간을 GPS에 넘겨주는 판정.
  ///
  /// 두 실패가 서로 반대다 — 너무 일찍 넘기면 건물이 가려 오차가 큰 첫 좌표가
  /// 방금 문에 맞춰 놓은 선을 뒤엎고, 안 넘기면 걷는 내내 선이 문에 붙어 있다.
  group('shouldHandOffOutdoorLegToGps', () {
    const door = ll.LatLng(37.5667, 126.9780);

    ll.LatLng northOf(double meters) =>
        ll.LatLng(door.latitude + meters / metersPerDegreeLat, door.longitude);

    test('문 앞에 서 있는 동안은 안 넘긴다', () {
      // 나가기 게이트가 15 m를 보므로, 그 안에서 떠는 좌표로 넘어가면 못박는
      // 일 자체가 헛돈다.
      expect(
        shouldHandOffOutdoorLegToGps(doorPoint: door, here: northOf(14)),
        isFalse,
      );
    });

    test('문턱만큼 멀어지면 넘긴다', () {
      expect(
        shouldHandOffOutdoorLegToGps(
          doorPoint: door,
          here: northOf(outdoorLegHandoffMeters + 1),
        ),
        isTrue,
      );
    });

    test('경계에서 넘긴다 — 같으면 이미 파사드를 벗어났다', () {
      expect(
        shouldHandOffOutdoorLegToGps(
          doorPoint: door,
          here: northOf(outdoorLegHandoffMeters),
        ),
        isTrue,
      );
    });

    test('못박은 적이 없으면 넘길 것도 없다', () {
      // 앵커가 없어 나온 문을 못 고른 경우다. 부르는 쪽이 래치를 내리고 평소대로
      // 현재 위치에서 다시 그린다.
      expect(
        shouldHandOffOutdoorLegToGps(doorPoint: null, here: northOf(1)),
        isTrue,
      );
    });

    test('문턱은 나가기 반경보다 넉넉하다', () {
      // 두 상수가 뒤집히면 위 첫 테스트가 침묵하며 통과한다.
      expect(
        outdoorLegHandoffMeters,
        greaterThan(manualOutdoorExitRadiusMeters),
      );
    });
  });
}
