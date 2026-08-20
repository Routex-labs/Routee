import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:navigation_client/map/camera/floor_camera_bounds.dart';

/// 더현대 서울 1F를 흉내낸 사각 도면.
const _footprint = [
  ll.LatLng(37.0, 127.0),
  ll.LatLng(37.2, 127.0),
  ll.LatLng(37.2, 127.4),
  ll.LatLng(37.0, 127.4),
];

void main() {
  _focusZoomTests();

  group('shouldApplyCameraCorrection', () {
    const current = ll.LatLng(37.0, 127.0);

    test('화면에서 10px보다 작은 차이는 보정하지 않는다', () {
      expect(
        shouldApplyCameraCorrection(
          current: current,
          corrected: const ll.LatLng(37.000005, 127.000005),
          halfSpanLat: 0.001,
          halfSpanLng: 0.001,
          viewportWidthPx: 400,
          viewportHeightPx: 800,
        ),
        isFalse,
      );
    });

    test('눈에 띄게 벗어난 경우에는 정확한 경계 보정을 허용한다', () {
      expect(
        shouldApplyCameraCorrection(
          current: current,
          corrected: const ll.LatLng(37.00005, 127.00005),
          halfSpanLat: 0.001,
          halfSpanLng: 0.001,
          viewportWidthPx: 400,
          viewportHeightPx: 800,
        ),
        isTrue,
      );
    });

    test('화면 범위를 구하지 못하면 실제 이탈을 방치하지 않는다', () {
      expect(
        shouldApplyCameraCorrection(
          current: current,
          corrected: const ll.LatLng(37.000001, 127.000001),
          halfSpanLat: 0,
          halfSpanLng: 0,
          viewportWidthPx: 400,
          viewportHeightPx: 800,
        ),
        isTrue,
      );
    });
  });

  group('clampToFootprint', () {
    // 가만히 둔 지도가 매 idle마다 animateCamera로 미세하게 떨리면 안 된다.
    test('이미 도면 안이면 아무것도 하지 않는다', () {
      expect(
        clampToFootprint(const ll.LatLng(37.1, 127.2), _footprint),
        isNull,
      );
    });

    test('경계 위도 정확히 위에 있으면 그대로 둔다', () {
      expect(
        clampToFootprint(const ll.LatLng(37.0, 127.0), _footprint),
        isNull,
      );
      expect(
        clampToFootprint(const ll.LatLng(37.2, 127.4), _footprint),
        isNull,
      );
    });

    test('밖으로 나간 축만 가장자리로 당긴다', () {
      final clamped = clampToFootprint(
        const ll.LatLng(37.9, 127.2),
        _footprint,
      )!;

      expect(clamped.latitude, closeTo(37.2, 1e-9));
      // 안에 있던 경도는 건드리지 않는다.
      expect(clamped.longitude, closeTo(127.2, 1e-9));
    });

    test('두 축 모두 나가면 모서리로 당긴다', () {
      final clamped = clampToFootprint(
        const ll.LatLng(36.0, 128.5),
        _footprint,
      )!;

      expect(clamped.latitude, closeTo(37.0, 1e-9));
      expect(clamped.longitude, closeTo(127.4, 1e-9));
    });

    // 기준이 없는데 되돌리면 엉뚱한 데로 끌고 간다. 무한히 밀리는 것보다 나쁘다.
    test('wgs84 footprint가 없으면 되돌리지 않는다', () {
      expect(clampToFootprint(const ll.LatLng(0, 0), const []), isNull);
      expect(
        clampToFootprint(const ll.LatLng(0, 0), const [ll.LatLng(37.0, 127.0)]),
        isNull,
      );
    });

    test('한 축이 퇴화한 도면도 되돌리지 않는다', () {
      expect(
        clampToFootprint(const ll.LatLng(38.0, 127.0), const [
          ll.LatLng(37.0, 127.0),
          ll.LatLng(37.2, 127.0),
        ]),
        isNull,
      );
    });
  });

  group('clampToFootprint — 화면 크기만큼 깎기', () {
    // 중심만 bbox 안에 가두면 중심이 모서리에 있는 상태가 합법이라, 그 순간
    // 화면의 절반 이상이 건물 밖 빈 공간이 된다. 다만 화면 절반을 통째로 깎으면
    // 미는 느낌이 지나치게 빡빡해서, [kFootprintDeflateRatio]만큼만 깎는다.
    test('모서리는 화면 절반의 일부만큼 안쪽으로 밀린다', () {
      final clamped = clampToFootprint(
        const ll.LatLng(37.2, 127.4),
        _footprint,
        halfSpanLat: 0.05,
        halfSpanLng: 0.1,
      )!;

      expect(
        clamped.latitude,
        closeTo(37.2 - 0.05 * kFootprintDeflateRatio, 1e-9),
      );
      expect(
        clamped.longitude,
        closeTo(127.4 - 0.1 * kFootprintDeflateRatio, 1e-9),
      );
    });

    test('깎고 남은 영역 안이면 그대로 둔다', () {
      expect(
        clampToFootprint(
          const ll.LatLng(37.1, 127.2),
          _footprint,
          halfSpanLat: 0.05,
          halfSpanLng: 0.1,
        ),
        isNull,
      );
    });

    // 뒤집힌 범위를 그대로 clamp에 넘기면 ArgumentError가 난다.
    test('화면이 건물보다 크면 그 축은 중점으로 붕괴한다', () {
      final clamped = clampToFootprint(
        const ll.LatLng(37.0, 127.0),
        _footprint,
        halfSpanLat: 5,
        halfSpanLng: 5,
      )!;

      expect(clamped.latitude, closeTo(37.1, 1e-9));
      expect(clamped.longitude, closeTo(127.2, 1e-9));
    });

    test('한 축만 화면이 더 크면 그 축만 붕괴한다', () {
      final clamped = clampToFootprint(
        // bbox 동쪽 끝. 깎기가 느슨해져서 127.35는 이제 허용 범위 안이라,
        // 경도 축이 실제로 당겨지는지 보려면 가장자리에서 시작해야 한다.
        const ll.LatLng(37.0, 127.4),
        _footprint,
        halfSpanLat: 5,
        halfSpanLng: 0.05,
      )!;

      expect(clamped.latitude, closeTo(37.1, 1e-9));
      // 경도는 아직 깎을 여유가 있어 가장자리로만 당긴다.
      expect(
        clamped.longitude,
        closeTo(127.4 - 0.05 * kFootprintDeflateRatio, 1e-9),
      );
    });

    // 되돌림은 animateCamera이고 그게 다시 onCameraIdle을 부른다.
    test('붕괴한 중점에 이미 서 있으면 되돌리지 않는다', () {
      expect(
        clampToFootprint(
          const ll.LatLng(37.1, 127.2),
          _footprint,
          halfSpanLat: 5,
          halfSpanLng: 5,
        ),
        isNull,
      );
    });

    test('화면 크기를 못 구해 0이 들어오면 예전대로 bbox만 본다', () {
      expect(
        clampToFootprint(
          const ll.LatLng(37.2, 127.4),
          _footprint,
          halfSpanLat: 0,
          halfSpanLng: 0,
        ),
        isNull,
      );
    });
  });

  group('clampToFootprint — 내 위치 근방 제한', () {
    // 반경이 화면 절반이라는 건 "내 위치가 항상 화면 안에 남는다"와 같은 말이다.
    test('내 위치에서 화면 절반보다 멀면 그 경계로 당긴다', () {
      final clamped = clampToFootprint(
        const ll.LatLng(37.1, 127.35),
        _footprint,
        halfSpanLat: 0.01,
        halfSpanLng: 0.02,
        userLocation: const ll.LatLng(37.1, 127.2),
      )!;

      expect(clamped.latitude, closeTo(37.1, 1e-9));
      expect(clamped.longitude, closeTo(127.22, 1e-9));
    });

    test('화면 절반 이내면 그대로 둔다', () {
      expect(
        clampToFootprint(
          const ll.LatLng(37.105, 127.21),
          _footprint,
          halfSpanLat: 0.01,
          halfSpanLng: 0.02,
          userLocation: const ll.LatLng(37.1, 127.2),
        ),
        isNull,
      );
    });

    test('위치가 없으면 도면 제한만 걸린다', () {
      expect(
        clampToFootprint(
          const ll.LatLng(37.1, 127.35),
          _footprint,
          halfSpanLat: 0.01,
          halfSpanLng: 0.02,
        ),
        isNull,
      );
    });

    // 반경이 화면 절반으로 정의돼 있으니, 화면 크기를 모르면 반경도 없다.
    test('화면 크기를 모르면 위치 제한도 걸지 않는다', () {
      expect(
        clampToFootprint(
          const ll.LatLng(37.1, 127.35),
          _footprint,
          userLocation: const ll.LatLng(37.1, 127.2),
        ),
        isNull,
      );
    });

    test('도면 제한이 더 좁으면 그쪽이 이긴다', () {
      final clamped = clampToFootprint(
        const ll.LatLng(37.2, 127.2),
        _footprint,
        halfSpanLat: 0.05,
        halfSpanLng: 0.02,
        userLocation: const ll.LatLng(37.19, 127.2),
      )!;

      // 위치 기준으로는 37.24까지 허용되지만 도면 깎기가 먼저 막는다.
      expect(
        clamped.latitude,
        closeTo(37.2 - 0.05 * kFootprintDeflateRatio, 1e-9),
      );
    });

    // PDR이 도면 밖으로 흘렀을 때. 빈 공간을 피하자고 사용자를 화면 밖에 두면
    // 자기가 어디 있는지 못 본다.
    test('교집합이 비면 위치 쪽을 남긴다', () {
      final clamped = clampToFootprint(
        const ll.LatLng(37.1, 127.2),
        _footprint,
        halfSpanLat: 0.01,
        halfSpanLng: 0.02,
        userLocation: const ll.LatLng(36.5, 127.2),
      )!;

      // 도면(37.01~37.19)과 위치 근방(36.49~36.51)이 안 겹친다 → 위치 근방.
      expect(clamped.latitude, closeTo(36.51, 1e-9));
    });
  });

  group('clampToFootprint — 얼마나 넉넉한가', () {
    test('화면의 1/4까지는 도면 밖 여백을 허용한다', () {
      // "중앙으로 당겨오는 게 너무 빡세다"는 피드백으로 넓힌 값이다. 1.0으로
      // 되돌리면(=빈 공간 0) 여기서 걸린다.
      expect(kFootprintDeflateRatio, lessThan(1.0));
      expect(
        kFootprintDeflateRatio,
        greaterThan(0.0),
        reason: '0이면 건물 가장자리가 화면 정중앙까지 와서 화면 절반이 빈다',
      );
    });

    test('깎기가 느슨해진 만큼 더 멀리 밀 수 있다', () {
      // 예전(비율 1.0)이면 되돌려졌을 자리가 이제는 허용돼야 한다.
      const halfSpan = 0.05;
      final justOutsideOldLimit = ll.LatLng(37.2 - halfSpan + 1e-4, 127.2);

      expect(
        clampToFootprint(
          justOutsideOldLimit,
          _footprint,
          halfSpanLat: halfSpan,
          halfSpanLng: 0.02,
        ),
        isNull,
        reason: '예전 제한(화면 절반 전체 깎기) 바깥이지만 지금은 그대로 둬야 한다',
      );
    });
  });

  group('shouldRecenterFollow', () {
    // 데드밴드가 없으면 PDR이 한 걸음 낼 때마다 카메라가 끌려간다 — 걷는 내내
    // 지도가 흔들려 도면을 읽을 수 없다.
    test('화면 절반의 데드밴드 안이면 카메라를 두고 본다', () {
      expect(
        shouldRecenterFollow(
          camera: const ll.LatLng(37.1, 127.2),
          user: ll.LatLng(37.1 + 0.05 * kFollowDeadbandRatio * 0.9, 127.2),
          halfSpanLat: 0.05,
          halfSpanLng: 0.05,
        ),
        isFalse,
      );
    });

    test('데드밴드를 벗어나면 따라간다', () {
      expect(
        shouldRecenterFollow(
          camera: const ll.LatLng(37.1, 127.2),
          user: ll.LatLng(37.1 + 0.05 * kFollowDeadbandRatio * 1.1, 127.2),
          halfSpanLat: 0.05,
          halfSpanLng: 0.05,
        ),
        isTrue,
      );
    });

    test('한 축만 벗어나도 따라간다', () {
      expect(
        shouldRecenterFollow(
          camera: const ll.LatLng(37.1, 127.2),
          user: ll.LatLng(37.1, 127.2 + 0.05 * kFollowDeadbandRatio * 1.1),
          halfSpanLat: 0.05,
          halfSpanLng: 0.05,
        ),
        isTrue,
      );
    });

    // 기준이 없으면 데드밴드가 정의되지 않는다. 그때 안 따라가는 쪽을 고르면
    // 마커가 화면 밖으로 나가도 카메라가 영영 오지 않는다.
    test('화면 크기를 모르면 항상 따라간다', () {
      expect(
        shouldRecenterFollow(
          camera: const ll.LatLng(37.1, 127.2),
          user: const ll.LatLng(37.1, 127.2),
        ),
        isTrue,
      );
    });

    test('데드밴드는 화면을 벗어날 만큼 넓지 않다', () {
      // 마커가 화면 밖으로 나가기 전에 반드시 따라잡아야 한다. 비율이 1을
      // 넘으면 그 보장이 깨진다.
      expect(kFollowDeadbandRatio, greaterThan(0));
      expect(kFollowDeadbandRatio, lessThan(1));
    });
  });
}

/// 카테고리를 훑는 조작과 매장을 콕 집는 조작은 **같은 카메라 이동이라도 배율
/// 규칙이 다르다.** 실내 도면과 야외의 실내 오버레이가 이 함수를 공유하므로,
/// 여기가 두 화면의 단일 출처다.
void _focusZoomTests() {
  group('focusZoomFor', () {
    test('keepZoom이면 지금 배율을 그대로 둔다', () {
      // 카테고리를 고르는 것은 층 전체를 훑는 행동이라 당기면 맥락을 잃는다.
      expect(focusZoomFor(currentZoom: 16.0, keepZoom: true), 16.0);
      expect(focusZoomFor(currentZoom: 20.5, keepZoom: true), 20.5);
    });

    test('매장을 집으면 기준 배율까지 당긴다', () {
      expect(focusZoomFor(currentZoom: 16.0, keepZoom: false), 19.0);
    });

    // 목록에서 골랐다고 사용자가 맞춰 둔 확대를 되돌리면 방금 보던 맥락을 잃는다.
    test('이미 더 가까우면 그 배율을 유지한다', () {
      expect(focusZoomFor(currentZoom: 20.5, keepZoom: false), 20.5);
    });

    test('기준과 같으면 그대로다', () {
      expect(focusZoomFor(currentZoom: 19.0, keepZoom: false), 19.0);
    });

    // 매장 폴리곤을 실제로 잰 배율이면 "이미 더 가까우면 유지"가 반대로 해롭다.
    // 크게 당겨 놓고 앵커 매장을 누르면 한 귀퉁이만 보인 채로 남는다.
    test('폴리곤을 잰 배율이면 더 가까이 있어도 물러선다', () {
      expect(
        focusZoomFor(
          currentZoom: 20.5,
          keepZoom: false,
          storeFocusZoom: 18.2,
          storeFitsViewport: true,
        ),
        18.2,
      );
    });

    test('폴리곤을 잰 배율이어도 keepZoom이 이긴다', () {
      // 카테고리를 훑는 중이면 매장 크기와 무관하게 화면을 흔들지 않는다.
      expect(
        focusZoomFor(
          currentZoom: 20.5,
          keepZoom: true,
          storeFocusZoom: 18.2,
          storeFitsViewport: true,
        ),
        20.5,
      );
    });
  });
}
