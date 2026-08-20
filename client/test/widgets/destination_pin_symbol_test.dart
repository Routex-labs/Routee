import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/map/icon/destination_pin.dart';
import 'package:navigation_client/screens/outdoor_map/layers/marker_map_layers.dart';

/// 도착 핀 심볼 레이어 규칙을 못 박는다.
///
/// 이 테스트가 있는 이유: "도착" 글씨를 심볼 레이어의 `textField`로 얹었더니
/// **웹에서는 보이고 실기기에서는 사라졌다.** `textOffset`은 em(=dp) 단위인데
/// 아이콘 크기는 비트맵의 자연 크기에 비례하고, 그 자연 크기가 플랫폼마다 다르다
/// — 웹은 픽셀비 1로 등록하지만 네이티브 `addImage`는 화면 밀도를 반영한다.
/// 그래서 웹 기준으로 맞춘 오프셋이 실기기에서는 핀 높이의 몇 배를 위로 올려,
/// 흰 글씨가 흰 도면 위 허공에 그려졌다.
///
/// 지금은 글씨를 비트맵에 굽는다. 심볼 레이어에 텍스트 속성이 **다시 생기면**
/// 같은 함정으로 돌아가므로 여기서 막는다.
void main() {
  final props = destinationPinSymbolProps(
    imageName: 'test-pin',
    iconSizeZ16: 0.18,
    iconSizeZ20: 0.38,
  ).toJson();

  group('destinationPinSymbolProps', () {
    test('심볼 레이어에 텍스트 속성을 두지 않는다', () {
      // 하나라도 살아나면 글씨가 다시 그림과 다른 단위로 움직인다.
      for (final key in [
        'text-field',
        'text-size',
        'text-offset',
        'text-anchor',
        'text-font',
        'text-color',
      ]) {
        expect(props.containsKey(key), isFalse, reason: '$key가 되살아났다');
      }
    });

    test('핀 바닥이 실제 좌표에 오도록 iconAnchor는 bottom이다', () {
      // top이나 center가 되면 핀이 도착 지점 위/가운데에 떠서 어디를 가리키는지
      // 어긋난다.
      expect(props['icon-anchor'], 'bottom');
    });

    test('핀은 겹쳐도 항상 보인다', () {
      // 매장 라벨과 충돌한다고 도착 핀이 숨으면, 정작 목적지가 화면에서 사라진다.
      expect(props['icon-allow-overlap'], isTrue);
      expect(props['icon-ignore-placement'], isTrue);
    });

    test('zoom 보간 구간을 그대로 싣는다', () {
      expect(props['icon-size'], [
        'interpolate',
        ['linear'],
        ['zoom'],
        16,
        0.18,
        20,
        0.38,
      ]);
    });

    test('화면마다 다른 것은 등록 키와 크기뿐이다', () {
      // 웹 addImage는 같은 이름이 이미 있으면 새 비트맵을 버린다. 화면별로
      // 다른 키를 쓸 수 있어야 한다.
      final indoor = destinationPinSymbolProps(
        imageName: 'marker-destination-pin-v3',
        iconSizeZ16: 0.115,
        iconSizeZ20: 0.25,
      ).toJson();

      expect(indoor['icon-image'], 'marker-destination-pin-v3');
      expect(props['icon-image'], 'test-pin');
      expect(indoor['icon-anchor'], props['icon-anchor']);
    });
  });

  group('라벨 상수', () {
    test('글꼴 이름을 비워 두지 않는다', () {
      // 오프스크린 캔버스는 폰트 폴백이 빈약해서, 이름이 없으면 한글이 두부
      // 박스로 뭉개진다(웹 CanvasKit에서 특히).
      expect(kPinLabelFontFamily, 'Pretendard');
      expect(kPinLabelText, '도착');
    });

    test('두 글자가 머리 원 안에 들어간다', () {
      // 폭은 대략 글자수 × fontSize. 머리 지름(2 × 반지름)을 넘으면 원 밖으로
      // 삐져나온다.
      final approxWidth = kPinLabelText.length * kPinLabelFontSize;
      expect(approxWidth, lessThan(kPinHeadRadius * 2));
    });
  });

  test('실내 도착 핀은 현재 위치보다 눈에 띄는 크기를 쓴다', () {
    expect(kDestinationPinIconSizeZ16, greaterThanOrEqualTo(0.24));
    expect(kDestinationPinIconSizeZ20, greaterThanOrEqualTo(0.50));
  });
}
