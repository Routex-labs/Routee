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

  group('isMagneticFieldPlausible', () {
    test('지구 자기장 범위 안이면 통과한다', () {
      expect(isMagneticFieldPlausible(50), isTrue);
      expect(isMagneticFieldPlausible(25), isTrue);
      expect(isMagneticFieldPlausible(65), isTrue);
    });

    test('배수로 벌어진 세기는 거부한다', () {
      // 실측: SM-F711N이 책상 위에서 100.7 µT를 냈다. 같은 자리의 복각은
      // −25°로, 서울 기대값 +53°에서 78° 어긋나 있었다.
      expect(isMagneticFieldPlausible(100.7), isFalse);
      expect(isMagneticFieldPlausible(5), isFalse);
    });

    test('못 받은 값은 통과시킨다 — 나쁘다는 증거가 있을 때만 거부한다', () {
      expect(isMagneticFieldPlausible(null), isTrue);
      expect(isMagneticFieldPlausible(0), isTrue);
    });

    test('문턱은 지표 실측 범위(25~65)를 양쪽으로 감싼다', () {
      expect(minPlausibleFieldUt, lessThan(25));
      expect(maxPlausibleFieldUt, greaterThan(65));
      // 넓히면 잡으려던 두 배짜리 왜곡이 빠져나간다.
      expect(maxPlausibleFieldUt, lessThan(100));
    });
  });

  group('headingTrustworthy', () {
    PdrSession sessionWith({
      required double errorDeg,
      required double fieldUt,
    }) {
      final session = PdrSession()
        ..headingSource = 'sensor_manager/rotation_vector'
        ..rotationHeadingAccuracyDeg = errorDeg
        ..magneticFieldUt = fieldUt;
      return session;
    }

    test('신고 오차가 없어도 자기장 세기로 거부한다', () {
      // 이 조합이 실기기에서 나온 그대로다 — 기기는 아무 문제도 신고하지
      // 않는데(-1) 관측된 자기장이 지구 것이 아니다.
      expect(
        sessionWith(errorDeg: -1, fieldUt: 100.7).headingTrustworthy,
        isFalse,
      );
    });

    test('둘 다 멀쩡하면 통과한다', () {
      expect(
        sessionWith(errorDeg: -1, fieldUt: 50).headingTrustworthy,
        isTrue,
      );
    });

    test('자기장을 못 받으면 신고 오차만으로 가른다', () {
      expect(sessionWith(errorDeg: 12, fieldUt: 0).headingTrustworthy, isTrue);
      expect(sessionWith(errorDeg: 45, fieldUt: 0).headingTrustworthy, isFalse);
    });
  });
}
