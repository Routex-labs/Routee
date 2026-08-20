import 'package:indoor_pdr_core/indoor_pdr_core.dart';
import 'package:test/test.dart';

void main() {
  group('headingReferenceFromSource', () {
    test('9-axis rotation vector의 짧은 gyro hold도 자북 frame을 유지한다', () {
      expect(
        headingReferenceFromSource('sensor_manager/rotation_vector+gyro_hold'),
        HeadingReference.magneticNorth,
      );
    });

    test('FusedOrientationProvider는 gyro hold 중에도 자북 frame이다', () {
      expect(
        headingReferenceFromSource('fused_orientation_provider'),
        HeadingReference.magneticNorth,
      );
      expect(
        headingReferenceFromSource('fused_orientation_provider+gyro_hold'),
        HeadingReference.magneticNorth,
      );
    });

    test('game rotation vector와 순수 gyro hold는 수동 보정 대상이다', () {
      expect(
        headingReferenceFromSource('sensor_manager/game_rotation_vector'),
        HeadingReference.arbitraryCorrected,
      );
      expect(
        headingReferenceFromSource('sensor_manager/gyro_hold'),
        HeadingReference.arbitraryCorrected,
      );
    });
  });

  group('isHeadingErrorTrusted', () {
    test('센서가 스스로 큰 오차를 보고하면 그 방위는 앵커에 못 쓴다', () {
      // 철골 건물 안에서 관측된 증상이 이것이다 — frame은 자북인데 절대 yaw가
      // 통째로 돌아가 있고, FOP가 그 사실을 숫자로 신고한다.
      expect(isHeadingErrorTrusted(45), isFalse);
      expect(isHeadingErrorTrusted(90), isFalse);
    });

    test('문턱 이하는 그대로 쓴다', () {
      expect(isHeadingErrorTrusted(0), isTrue);
      expect(isHeadingErrorTrusted(12), isTrue);
      expect(isHeadingErrorTrusted(trustedHeadingErrorDeg), isTrue);
    });

    test('값을 안 주는 기기(-1)는 통과시킨다', () {
      // SM-G996N은 rotation vector의 values[4]를 -1로 준다. 여기서 거부하면
      // 그 기기의 앵커가 통째로 막힌다 — 나쁘다는 증거가 있을 때만 거부한다.
      expect(isHeadingErrorTrusted(-1), isTrue);
    });

    test('문턱은 gyro hold(35°)보다 낮고 마커 원뿔 반각(31°)보다 낮지 않다', () {
      // hold를 켤 만큼 나쁜 방위가 앵커에 들어가면 안 되고, 원뿔 안에 묻히는
      // 오차까지 거부하면 얻는 것 없이 정상 세션만 흔든다.
      expect(trustedHeadingErrorDeg, lessThan(35));
      expect(trustedHeadingErrorDeg, greaterThanOrEqualTo(31 - 1));
    });
  });

  group('두 판정은 따로 남아야 한다', () {
    test('gyro hold는 frame으로는 자북이지만 방위로는 못 믿는다', () {
      // 이 둘을 한 함수로 합쳤다가 "frame은 자북이다"가 곧 "보정 불필요"로
      // 읽혀, 교란된 방위를 보정 없이 앵커에 구워 넣던 회귀가 있었다
      // (docs/client/android-heading-drift.md 6절).
      const source = 'fused_orientation_provider+gyro_hold';
      expect(headingReferenceFromSource(source), HeadingReference.magneticNorth);
      expect(isHeadingErrorTrusted(60), isFalse);
    });
  });
}
