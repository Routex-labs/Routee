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
