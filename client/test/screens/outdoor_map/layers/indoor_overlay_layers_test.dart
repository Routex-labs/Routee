import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'package:navigation_client/screens/outdoor_map/layers/indoor_overlay_layers.dart';
import 'package:navigation_client/map/icon/category_map_icon.dart';
import 'package:navigation_client/map/style/category_map_filter.dart';
import 'package:navigation_client/map/style/floor_facility_style.dart';
import 'package:navigation_client/map/style/label_style.dart';
import 'package:navigation_client/map/style/palette.dart';

/// `#RRGGBB`의 상대 밝기. 팔레트가 회색조 한 계열이라 채널 평균으로 충분하다 —
/// 여기서 가리는 것은 "어느 쪽이 더 밝은가" 하나다.
int _luminance(String hex) {
  final value = int.parse(hex.substring(1), radix: 16);
  return ((value >> 16 & 0xFF) + (value >> 8 & 0xFF) + (value & 0xFF)) ~/ 3;
}

/// 실기기에서 건물이 **불투명한 검정 덩어리**로 덮이던 회귀를 막는 테스트.
///
/// 원인은 `MapLibreMapController.setLayerProperties`가 patch가 아니라 전체
/// 교체라는 점이었다. 넘긴 객체를 `toJson(skipNulls: false)`로 직렬화하므로
/// 설정하지 않은 속성이 전부 `null`로 함께 전송되고, Android 네이티브는 그
/// null을 그대로 적용해 스펙 기본값으로 되돌린다. `fill-color`의 기본값이
/// `#000000`이라 흰색 footprint가 검정으로 바뀌었다.
///
/// 웹에서는 증상이 안 보이므로 Chrome 확인만으로는 절대 못 잡는다. 그래서
/// "레이어 속성 묶음은 항상 완전해야 한다"를 여기서 못 박는다.
void main() {
  // 진입 후 어느 zoom에서든 쓰이는 대표 페이드 표현식.
  final fadeExpr = <Object>[
    'interpolate',
    ['linear'],
    ['zoom'],
    15.6,
    0,
    16.0,
    1,
  ];

  /// setLayerProperties가 실제로 보내는 형태 그대로 검사한다.
  Map<String, dynamic> wireJson(LayerProperties props) =>
      props.toJson(skipNulls: false);

  group('fill 레이어는 색을 항상 함께 보낸다', () {
    final cases = <String, FillLayerProperties>{
      '실내 footprint': indoorFootprintProps(fadeExpr),
      '실내 매장 fill': indoorStoresFillProps(fadeExpr),
      '못 걷는 면': indoorNonWalkableProps(fadeExpr),
      '수직이동 구조물': indoorVerticalTransportProps(fadeExpr),
      '건물 폴리곤': buildingFillProps(0.15),
      'dim scrim': dimScrimProps(0),
    };

    cases.forEach((name, props) {
      test('$name — fill-color가 null이 아니다', () {
        final json = wireJson(props);
        expect(
          json['fill-color'],
          isNotNull,
          reason:
              '$name의 fill-color가 null로 전송되면 Android에서 스펙 기본값 #000000(검정)으로 '
              '되돌아간다. opacity만 넘기는 부분 업데이트를 되살리지 말 것.',
        );
        expect(json['fill-opacity'], isNotNull);
      });
    });

    test('실내 footprint는 흰색이다', () {
      expect(wireJson(indoorFootprintProps(fadeExpr))['fill-color'], '#FFFFFF');
    });

    test('못 걷는 면은 통로와 매장 사이 밝기이고 경계선을 갖는다', () {
      // **값이 아니라 순서를 못 박는다.** 팔레트에 hex를 베껴 두면 한쪽만
      // 고쳐지는 날이 온다. 지켜야 하는 것은 "통로 > 못 걷는 면 > 매장" 순서와
      // "구분은 경계선이 만든다"는 규칙이다(`docs/client/map-style-rules.md`).
      final json = wireJson(indoorNonWalkableProps(fadeExpr));
      expect(json['fill-color'], mapNonWalkableFill);
      expect(json['fill-outline-color'], isNotNull);
      expect(json['fill-outline-color'], isNot(json['fill-color']));
      // 매장과 같아지면 걸을 수 없는 곳이 매장처럼 읽힌다.
      expect(json['fill-color'], isNot(mapStoreFill));
      expect(
        _luminance(mapFootprintFill),
        greaterThan(_luminance(mapNonWalkableFill)),
        reason: '통로가 가장 밝아야 한다 — 밝을수록 걷는 곳',
      );
      expect(
        _luminance(mapNonWalkableFill),
        greaterThan(_luminance(mapStoreFill)),
        reason: '배경이 매장보다 진하면 빈 공간이 먼저 눈에 들어온다',
      );
      // 경계선은 매장 경계선보다 옅다 — 배경이 매장보다 또렷하면 안 된다.
      expect(
        _luminance(mapNonWalkableOutline),
        greaterThan(_luminance(mapStoreOutline)),
      );
    });

    test('건물 폴리곤은 검정이 아닌 테마 색이다', () {
      final color = wireJson(buildingFillProps(0.15))['fill-color'] as String;
      expect(color, isNot('#000000'));
      expect(color, matches(RegExp(r'^#[0-9A-F]{6}$')));
    });
  });

  group('symbol 레이어는 layout 속성을 항상 함께 보낸다', () {
    test('매장 라벨 — text-field/text-font/text-color가 살아 있다', () {
      final json = wireJson(indoorStoresLabelProps(fadeExpr, null, 1));
      // text-field가 null로 가면 라벨이 통째로 사라진다.
      expect(json['text-field'], isNotNull);
      expect(json['text-font'], isNotNull);
      expect(json['text-color'], isNotNull);
      expect(json['text-opacity'], isNotNull);
    });

    test('매장 라벨 — 대분류 아이콘 속성이 함께 살아 있다', () {
      final json = wireJson(indoorStoresLabelProps(fadeExpr, null, 1));
      // 라벨과 아이콘이 같은 심볼이라, 이 중 하나라도 null로 가면 아이콘이
      // 사라지거나(icon-image) 글자가 아이콘 위에 겹쳐 찍힌다(anchor·offset).
      expect(json['icon-image'], isNotNull);
      expect(json['icon-size'], isNotNull);
      expect(json['icon-opacity'], isNotNull);
      // 이름을 아이콘 아래로 내리는 두 속성. 예전에는 좌/우로 뒤집는
      // `text-variable-anchor`·`text-radial-offset`이 그 자리였는데, 같은 화면에
      // 매장마다 이름이 다른 쪽에 붙어 규칙이 읽히지 않아 아래 고정으로 바꿨다.
      expect(json['text-anchor'], isNotNull);
      expect(json['text-offset'], isNotNull);
    });

    test('매장 라벨 — 아이콘과 이름은 함께 숨고 함께 나타난다', () {
      final json = wireJson(indoorStoresLabelProps(fadeExpr, null, 1));
      expect(json['text-optional'], isFalse);
      expect(json['icon-optional'], isFalse);
      expect(json['icon-allow-overlap'], isFalse);
    });

    test('선택 매장은 크기 대신 기존 아이콘의 색만 바꾼다', () {
      const selectedId = 'store-osulloc';
      final json = wireJson(
        indoorStoresLabelProps(
          fadeExpr,
          null,
          1,
          highlightedStoreId: selectedId,
        ),
      );

      expect(json['text-size'], mapLabelFixedTextSize);
      expect(json['icon-size'], indoorMarkerIconSize(1));
      final iconImage = json['icon-image'] as List<Object?>;
      expect(iconImage[0], 'case');
      expect(iconImage[1], [
        '==',
        ['get', 'id'],
        selectedId,
      ]);
      expect(
        iconImage.toString(),
        contains(selectedStoreCategoryIconImageName('카페')),
      );
      expect(iconImage.toString(), contains(storeCategoryIconImageName('카페')));
      expect(iconImage, isNot(contains(mapLabelFixedTextSize * 1.35)));
    });

    test('카테고리를 골라도 text-field는 살아 있다', () {
      // 선택이 걸리면 이름이 조건부가 되는데, 그 조건 표현식이 통째로 빠지거나
      // null이 되면 라벨이 전부 사라진다.
      final json = wireJson(
        indoorStoresLabelProps(
          fadeExpr,
          const CategorySelection(category: '식음료'),
          1,
        ),
      );

      expect(json['text-field'], isNotNull);
      expect((json['text-field'] as List).first, 'case');
      // 선택된 매장은 같은 심볼 안에서 아이콘과 이름을 함께 그린다.
      expect(json['icon-image'], isNotNull);
    });

    test('매장 라벨 — text-allow-overlap은 false다', () {
      // variable-anchor는 충돌 판정 위에서만 동작한다. true가 되면 앵커가 항상
      // 첫 번째 값으로 굳어 이름 뒤집기가 조용히 죽는다.
      expect(
        wireJson(
          indoorStoresLabelProps(fadeExpr, null, 1),
        )['text-allow-overlap'],
        isFalse,
      );
    });

    test('편의시설 라벨 — 텍스트 속성이 살아 있다', () {
      final json = wireJson(indoorFacilityLabelProps(fadeExpr, null));
      expect(json['text-field'], isNotNull);
      expect(json['text-font'], isNotNull);
      expect(json['text-color'], isNotNull);
      expect(json['text-opacity'], isNotNull);
      // 아이콘이 centroid를 차지하므로 이름은 아래로 내려가 있어야 한다.
      expect(json['text-offset'], isNotNull);
      // 이 레이어는 아이콘을 그리지 않는다 — 그리면 시설 아이콘과 겹친다.
      expect(json['icon-image'], isNull);
    });

    test('POI·시설 아이콘 — icon-image/icon-size가 살아 있다', () {
      for (final props in [
        indoorPoiIconProps(fadeExpr, 1),
        indoorFacilityIconProps(fadeExpr, 1),
      ]) {
        final json = wireJson(props);
        // icon-image가 null로 가면 아이콘이 통째로 사라진다.
        expect(json['icon-image'], isNotNull);
        expect(json['icon-size'], isNotNull);
        expect(json['icon-opacity'], isNotNull);
      }
    });
  });

  group('층 외곽선', () {
    test('색·굵기·opacity를 항상 함께 보낸다', () {
      final json = wireJson(floorOutlineProps(fadeExpr));
      // line-color가 null로 가면 스펙 기본값 #000000으로 되돌아간다(fill과 같은
      // 이유 — 파일 상단 주석 참고).
      expect(json['line-color'], isNotNull);
      expect(json['line-width'], isNotNull);
      expect(json['line-opacity'], isNotNull);
    });

    test('얇게 긋는다', () {
      // 실내 도면 위에 얹히는 선이라 굵어지면 가장자리 매장을 덮는다.
      expect(wireJson(floorOutlineProps(fadeExpr))['line-width'], 1);
    });
  });

  test('페이드 표현식은 그대로 실려 나간다', () {
    // opacity를 zoom 표현식으로 주는 구조 자체는 유지되어야 한다 —
    // 이 값이 상수로 바뀌면 오버레이 페이드인이 죽는다.
    expect(wireJson(indoorFootprintProps(fadeExpr))['fill-opacity'], fadeExpr);
  });
}
