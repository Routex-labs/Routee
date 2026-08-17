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

  group('gyro hold 중에는 절대 방위를 맡기지 않는다 — 회귀 방지', () {
    // **이 한 줄이 실내 방향을 90° 틀어 놓았던 회귀다.**
    //
    // 예전에는 `headingReferenceFromSource`가 gyro hold를 arbitrary로 분류했고,
    // 그래서 실내에 들어가면(=자력계 교란으로 hold) 앵커가 방향 보정을 요구했다.
    // "hold 중에도 frame 자체는 자북"이라는 이유로 그 조건을 뺀 뒤부터, 교란된
    // 자기 방위가 **보정 없이(rot 0)** 그대로 마커에 실렸다.
    //
    // frame 판정은 그때 바뀐 것이 맞다 — 서버 자북 정렬각은 hold 중에도 유효하다.
    // 놓친 것은 **품질**이었고, 그 자리가 여기다. 두 판정을 한 함수로 되돌리면
    // 같은 회귀가 다시 난다.
    test('frame은 자북이라고 답한다', () {
      expect(
        headingReferenceFromSource('sensor_manager/rotation_vector+gyro_hold'),
        HeadingReference.magneticNorth,
      );
    });

    test('그래도 그 방위를 믿어서는 안 된다', () {
      // hold가 걸렸다는 것 자체가 "자력계를 지금 못 믿는다"는 판정 결과다.
      expect(
        isTrustedHeading(
          source: 'sensor_manager/rotation_vector+gyro_hold',
          magneticAccuracy: 'high',
        ),
        isFalse,
        reason: 'hold 중인데 자북 보정 없이 확정하면 실내 방향이 통째로 틀어진다',
      );
    });

    test('hold가 풀린 정상 rotation vector는 믿는다', () {
      expect(
        isTrustedHeading(
          source: 'sensor_manager/rotation_vector',
          magneticAccuracy: 'high',
        ),
        isTrue,
      );
    });

    test('절대 기준이 아닌 출처는 품질과 무관하게 못 믿는다', () {
      expect(
        isTrustedHeading(
          source: 'sensor_manager/game_rotation_vector',
          magneticAccuracy: 'high',
        ),
        isFalse,
      );
    });
  });

  group('isTrustedMagneticAccuracy', () {
    test('나쁘다고 보고된 값만 거부한다', () {
      // 이 함수가 "자북 frame인가"(위 group)와 갈리는 지점이다. frame은 맞는데
      // 그 frame이 지금 틀어져 있을 수 있고, 둘을 겸하면 건물 안에서 방위가
      // 90° 어긋난 채 고칠 방법이 없어진다.
      expect(isTrustedMagneticAccuracy('low'), isFalse);
      expect(isTrustedMagneticAccuracy('uncalibrated'), isFalse);
    });

    test('아직 모르는 상태는 거부하지 않는다', () {
      // **거부하면 정상 기기에서도 매번 방향 질문이 뜬다.** 정확도 콜백이 오기
      // 전(unknown)과, iOS가 폰을 흔들기 전까지 머무는 구간이 여기 걸린다.
      // 놓치는 쪽은 사용자가 지도를 직접 찍어 언제든 고칠 수 있다.
      expect(isTrustedMagneticAccuracy('unknown'), isTrue);
      expect(isTrustedMagneticAccuracy('high'), isTrue);
      expect(isTrustedMagneticAccuracy('medium'), isTrue);
    });
  });
}
