import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/screens/outdoor_map/entry/heading_log.dart';

void main() {
  group('isMagneticFieldPlausible', () {
    test('지구 자기장 범위 안이면 통과한다', () {
      expect(isMagneticFieldPlausible(50), isTrue);
      expect(isMagneticFieldPlausible(25), isTrue);
      expect(isMagneticFieldPlausible(65), isTrue);
    });

    test('배수로 벌어진 세기는 거부한다', () {
      // 실측: SM-F711N이 책상 위에서 107~113 µT를 냈다. 지구 자기장의 두 배다.
      expect(isMagneticFieldPlausible(108), isFalse);
      expect(isMagneticFieldPlausible(5), isFalse);
    });

    test('못 받은 값은 통과시킨다 — 나쁘다는 증거가 있을 때만 거부한다', () {
      expect(isMagneticFieldPlausible(null), isTrue);
      expect(isMagneticFieldPlausible(0), isTrue);
      expect(isMagneticFieldPlausible(-1), isTrue);
    });

    test('문턱은 지표 실측 범위(25~65)를 양쪽으로 감싼다', () {
      // 좁히면 센서 bias와 약한 실내 왜곡까지 걸려 정상 세션만 흔든다.
      expect(minPlausibleFieldUt, lessThan(25));
      expect(maxPlausibleFieldUt, greaterThan(65));
      // 넓히면 잡으려던 두 배짜리 왜곡이 빠져나간다.
      expect(maxPlausibleFieldUt, lessThan(107));
    });
  });

  group('describeMagneticField', () {
    test('세기와 배수와 결론을 함께 쓴다', () {
      expect(describeMagneticField(108.3), '108.3µT(2.2배·의심)');
      expect(describeMagneticField(50), '50.0µT(1.0배·정상)');
    });

    test('값이 없으면 모름이다', () {
      expect(describeMagneticField(null), '모름');
    });
  });

  group('describeHeadingLog', () {
    String line({
      double? magneticFieldUt = 50,
      double? headingErrorDeg = 12,
      double? markerBearingDeg = 200,
      double cameraBearingDeg = 30,
      bool? headingTrustworthy = true,
    }) => describeHeadingLog(
      deviceBearingDeg: 161.8,
      gyroBearingDeg: 161.7,
      orientationBearingDeg: 161.8,
      walkingBearingDeg: 163,
      walkOffsetDeg: 1.2,
      headingConverged: true,
      magneticFieldUt: magneticFieldUt,
      headingErrorDeg: headingErrorDeg,
      magneticAccuracy: 'unknown',
      headingSource: 'sensor_manager/rotation_vector',
      anchorRotationDeg: 0,
      calibrationPhase: 'calibrated',
      headingTrustworthy: headingTrustworthy,
      markerBearingDeg: markerBearingDeg,
      cameraBearingDeg: cameraBearingDeg,
    );

    test('네 토막이 모두 한 줄에 들어간다', () {
      final text = line();
      expect(text, startsWith('HEADING 센서'));
      expect(text, contains('· 코어'));
      expect(text, contains('· 앵커'));
      expect(text, contains('· 지도'));
    });

    test('화면 각도는 마커에서 카메라를 뺀 값이다', () {
      // 이 자리가 칩의 「화면」과 같은 식이어야 둘을 나란히 놓고 읽을 수 있다.
      expect(line(), contains('화면=170.0'));
    });

    test('화면 각도는 음수로 돌지 않는다', () {
      expect(
        line(markerBearingDeg: 10, cameraBearingDeg: 300),
        contains('화면=70.0'),
      );
    });

    test('값을 못 받은 자리는 빈칸이 아니라 표시가 남는다', () {
      final text = line(
        magneticFieldUt: null,
        headingErrorDeg: -1,
        markerBearingDeg: null,
        headingTrustworthy: null,
      );
      expect(text, contains('자기장=모름'));
      expect(text, contains('오차=모름'));
      expect(text, contains('마커=—'));
      expect(text, contains('신뢰=—'));
      expect(text, contains('화면=—'));
    });
  });
}
