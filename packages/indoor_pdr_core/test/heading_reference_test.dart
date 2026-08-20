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
}
