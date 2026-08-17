/// 마커 heading 진단 한 줄.
///
/// 이 칩의 존재 이유는 **"돌아가 있다"가 네 가지 다른 고장의 같은 증상**이라는
/// 것이다. 화면만 보고는 센서가 틀린 것인지, 앵커 보정이 틀린 것인지, 지도 회전을
/// 안 뺀 것인지 구분할 수 없다. 여기서 각 자리의 값이 무엇을 뜻하는지 못 박는다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/screens/outdoor_map/entry/heading_debug.dart';

void main() {
  group('describeMarkerHeading', () {
    test('지도가 안 돌아가 있으면 마커 각도가 곧 화면 각도다', () {
      expect(
        describeMarkerHeading(
          deviceBearingDeg: 271,
          markerBearingDeg: 271,
          cameraBearingDeg: 0,
          anchorRotationDeg: 0,
          headingSource: 'magneticNorth',
        ),
        '기기 271° · 마커 271° · 카메라 0° · 화면 271° · rot 0° · magneticNorth',
      );
    });

    test('지도가 돌아가 있으면 화면 각도는 그만큼 빠진다', () {
      // **이 뺄셈이 정상 동작이다.** 마커가 북쪽(0°)을 가리키는데 지도가 90°
      // 돌아가 있으면, 화면에서 그 원뿔은 위가 아니라 왼쪽(270°)을 향해야 맞다.
      // 현장에서 "반시계 90도로 보인다"가 정상인지 고장인지를 가르는 값이다.
      expect(
        describeMarkerHeading(
          deviceBearingDeg: 0,
          markerBearingDeg: 0,
          cameraBearingDeg: 90,
          anchorRotationDeg: 0,
          headingSource: 'magneticNorth',
        ),
        contains('화면 270°'),
      );
    });

    test('앵커 보정각이 붙으면 기기 각도와 마커 각도가 갈린다', () {
      // 둘이 갈렸다는 것은 rot이 방위를 옮겼다는 뜻이다. 자북 기기에서 rot이
      // 0이 아니면 수동 방향 보정이 끼어든 것이고, 그게 어긋남의 원인이다.
      final line = describeMarkerHeading(
        deviceBearingDeg: 10,
        markerBearingDeg: 100,
        cameraBearingDeg: 0,
        anchorRotationDeg: 90,
        headingSource: 'arbitraryCorrected',
      );
      expect(line, contains('기기 10°'));
      expect(line, contains('마커 100°'));
      expect(line, contains('rot 90°'));
    });

    test('각도를 0~360으로 접어 읽기 쉽게 만든다', () {
      expect(
        describeMarkerHeading(
          deviceBearingDeg: -90,
          markerBearingDeg: 450,
          cameraBearingDeg: 0,
          anchorRotationDeg: -45,
          headingSource: null,
        ),
        '기기 270° · 마커 90° · 카메라 0° · 화면 90° · rot 315° · 출처 없음',
      );
    });

    test('아직 방향을 모르면 빈칸으로 두고 자리는 남긴다', () {
      // 값이 없는 것과 0인 것은 완전히 다른 상태다. 0으로 채우면 "북쪽을
      // 가리킨다"로 읽혀, 방향을 못 잡은 구간을 정상으로 착각하게 된다.
      final line = describeMarkerHeading(
        deviceBearingDeg: null,
        markerBearingDeg: null,
        cameraBearingDeg: 0,
        anchorRotationDeg: null,
        headingSource: null,
      );
      expect(line, contains('기기 —'));
      expect(line, contains('마커 —'));
      expect(line, contains('화면 —'));
      expect(line, contains('rot —'));
    });
  });
}
