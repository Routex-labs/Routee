/// 축척 막대가 **딱 떨어지는 값**만 말하는지에 대한 테스트.
///
/// 축척은 눈대중으로 읽는 도구다. `137m`처럼 임의의 숫자가 뜨면 읽는 사람이
/// 그 값을 다시 계산해야 하고, 그러면 자로서 쓸모가 없다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/map/camera/scale_bar.dart';

void main() {
  group('딱 떨어지는 값만 고른다', () {
    test('상한 안에 들어오는 가장 큰 1·2·5 × 10ⁿ을 고른다', () {
      // 상한 100px × 1.37m/px = 137m 안에 드는 가장 큰 값은 100m다.
      final step = mapScaleStepFor(metersPerPixel: 1.37, maxWidthPx: 100)!;
      expect(step.meters, 100);
      // 그 거리를 그릴 폭은 상한보다 짧다 — 값이 내려간 만큼 막대도 짧아진다.
      expect(step.widthPx, closeTo(100 / 1.37, 0.01));
      expect(step.widthPx, lessThan(100));
    });

    test('2와 5도 쓴다 — 10의 거듭제곱만 쓰면 막대가 반토막 난다', () {
      // 상한이 260m면 200m가 들어간다. 100m로 내리면 자가 절반 길이가 된다.
      expect(mapScaleStepFor(metersPerPixel: 2.6, maxWidthPx: 100)!.meters, 200);
      // 상한이 640m면 500m.
      expect(mapScaleStepFor(metersPerPixel: 6.4, maxWidthPx: 100)!.meters, 500);
    });

    test('실내 배율에서도 값이 선다', () {
      // 0.12m/px × 72px ≈ 8.6m → 5m.
      expect(mapScaleStepFor(metersPerPixel: 0.12, maxWidthPx: 72)!.meters, 5);
    });

    // 실내 도면을 최대로 당겨도 1m는 눈에 보이는 길이다. 그 아래는 축척이
    // 아니라 잡음이라 내려가지 않는다.
    test('1m 아래로는 내려가지 않는다', () {
      final step = mapScaleStepFor(metersPerPixel: 0.001, maxWidthPx: 72)!;
      expect(step.meters, 1);
    });
  });

  group('글자', () {
    test('1000m 미만은 m로 적는다', () {
      expect(const MapScaleStep(meters: 50, widthPx: 40).label, '50m');
      expect(const MapScaleStep(meters: 500, widthPx: 40).label, '500m');
    });

    // m로만 적으면 시내 배율에서 `10000m`이 된다. 자릿수를 세어야 읽히는
    // 숫자는 축척으로 쓸모가 없다.
    test('1000m부터는 km로 적는다', () {
      expect(const MapScaleStep(meters: 1000, widthPx: 40).label, '1km');
      expect(const MapScaleStep(meters: 2000, widthPx: 40).label, '2km');
      expect(const MapScaleStep(meters: 500000, widthPx: 40).label, '500km');
    });
  });

  // 카메라가 아직 준비되지 않은 프레임에서 이 값들이 온다. 막대 없이 지나가는
  // 편이 0 나눗셈으로 터지는 것보다 낫다.
  group('값을 정할 수 없으면 null', () {
    test('픽셀당 미터가 0이거나 음수거나 무한이면 null', () {
      expect(mapScaleStepFor(metersPerPixel: 0, maxWidthPx: 72), isNull);
      expect(mapScaleStepFor(metersPerPixel: -1, maxWidthPx: 72), isNull);
      expect(
        mapScaleStepFor(metersPerPixel: double.infinity, maxWidthPx: 72),
        isNull,
      );
      expect(mapScaleStepFor(metersPerPixel: double.nan, maxWidthPx: 72), isNull);
    });

    test('상한이 0이면 null', () {
      expect(mapScaleStepFor(metersPerPixel: 1, maxWidthPx: 0), isNull);
    });
  });

  // 축척과 "이 화면에 몇 m가 담기는가"가 다른 식을 쓰면 조용히 어긋난다.
  test('픽셀당 미터는 zoom_math와 같은 식이다', () {
    // MapLibre는 512 타일 규약이라 zoom 0 적도에서 78271.517 m/px다.
    expect(metersPerPixelAt(zoom: 0, latitude: 0), closeTo(78271.517, 0.001));
    // zoom이 1 오르면 절반.
    expect(
      metersPerPixelAt(zoom: 18, latitude: 37.5),
      closeTo(metersPerPixelAt(zoom: 17, latitude: 37.5) / 2, 1e-9),
    );
  });
}
