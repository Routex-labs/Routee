import 'package:flutter_test/flutter_test.dart';
// 자기장 세기 판정 자체는 코어의 heading_reference에 있고 거기서 검증한다
// (`packages/indoor_pdr_core/test/heading_reference_test.dart`). 여기서는 그
// 판정을 사람이 읽는 문구로 옮기는 자리만 본다.

import 'package:navigation_client/screens/outdoor_map/entry/heading_log.dart';

void main() {
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
      double? magneticInclinationDeg = 53,
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
      magneticInclinationDeg: magneticInclinationDeg,
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

    test('복각은 서울 값에서 벗어나면 의심으로 적는다', () {
      // 세기와 복각이 **함께** 벗어나야 국소 왜곡이다. 세기만 틀리면 눈금
      // 문제일 수 있어 이 자리가 둘을 가른다.
      expect(line(magneticInclinationDeg: 53), contains('복각=53°(정상)'));
      expect(line(magneticInclinationDeg: 62), contains('복각=62°(정상)'));
      expect(line(magneticInclinationDeg: 80), contains('복각=80°(의심)'));
      expect(line(magneticInclinationDeg: 10), contains('복각=10°(의심)'));
    });

    test('복각 허용 폭은 자세 잡음보다 넓고 왜곡보다 좁다', () {
      expect(inclinationToleranceDeg, greaterThan(5));
      expect(inclinationToleranceDeg, lessThan(30));
    });

    test('값을 못 받은 자리는 빈칸이 아니라 표시가 남는다', () {
      final text = line(
        magneticFieldUt: null,
        magneticInclinationDeg: null,
        headingErrorDeg: -1,
        markerBearingDeg: null,
        headingTrustworthy: null,
      );
      expect(text, contains('자기장=모름'));
      expect(text, contains('복각=모름'));
      expect(text, contains('오차=모름'));
      expect(text, contains('마커=—'));
      expect(text, contains('신뢰=—'));
      expect(text, contains('화면=—'));
    });
  });
}
