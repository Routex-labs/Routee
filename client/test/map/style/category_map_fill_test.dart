import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/map/style/palette.dart';
import 'package:navigation_client/map/icon/category_icon.dart';
import 'package:navigation_client/map/style/category_map_fill.dart';

/// 카테고리를 눌렀을 때 강조 매장을 대분류 색으로 칠하는 규칙의 회귀 테스트.
///
/// 화면으로만 확인하면 놓치는 것들을 여기서 잡는다. 지도 색은 "예뻐 보이는가"가
/// 아니라 **읽히는가**가 기준이고, 실패는 대개 조용하다 — 표현식 형태가 어긋나면
/// 예외 없이 매치 0건이 되고, 색이 짙어지면 그 위 매장명이 안 보일 뿐 아무것도
/// 깨지지 않는다.
void main() {
  Color parse(String hex) =>
      Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000);

  /// `#RRGGBB`의 HSL 채도(0~1). 파스텔에서 대비를 만드는 축이다.
  double saturation(String hex) => HSLColor.fromColor(parse(hex)).saturation;

  /// `#RRGGBB`를 상대 휘도(0~1)로. WCAG 정의를 그대로 쓴다.
  double luminance(String hex) {
    final rgb = int.parse(hex.substring(1), radix: 16);
    return Color.fromARGB(
      255,
      (rgb >> 16) & 0xFF,
      (rgb >> 8) & 0xFF,
      rgb & 0xFF,
    ).computeLuminance();
  }

  test('아이콘 표와 색 표의 대분류가 일치한다', () {
    // 한쪽에만 있으면 지도에서 아이콘은 붙는데 면은 회색인(또는 그 반대)
    // 대분류가 생긴다.
    expect(categoryPaletteCategories.toSet(), categoryIconCategories.toSet());
  });

  test('면 색은 매장명이 읽힐 만큼 밝다', () {
    // 라벨은 #444846(휘도 약 0.06)이다. 면이 이보다 충분히 밝아야 이름이 먼저
    // 읽힌다. 이 임계값을 낮추려면 실기기에서 이름 가독성부터 확인해야 한다.
    for (final category in categoryPaletteCategories) {
      final tint = categoryFillTintHex(category);
      expect(
        luminance(tint),
        greaterThan(0.7),
        reason: '$category 면($tint)이 너무 어두워 매장명이 묻힌다',
      );
    }
  });

  test('강조한 매장이 안 한 매장과 구분된다', () {
    // 이 파일에 없던 기준이다. 대분류 색이 파스텔로 바뀌었을 때 나머지 테스트는
    // 그대로 통과했는데 — 밝고, 선이 면보다 진하기는 했다 — 정작 기본 매장
    // (mapStoreFill 0.858 / mapStoreOutline)과의 차이가 0.001까지 좁아져
    // 강조를 걸어도 화면이 그대로였다. 강조는 자기 안에서가 아니라 **안 걸린
    // 매장에 대해** 달라야 한다.
    //
    // **면은 명도로, 선은 채도로 구분한다.** 선까지 명도로 벌면 색 계열을 잃고
    // 탁해진다(실기기에서 한 번 되돌렸다 — 채널 ×0.7). 기본 경계선은 거의
    // 회색이므로 채도만으로도 구분이 선다.
    final baseFill = luminance(mapStoreFill);
    final baseOutlineSaturation = saturation(mapStoreOutline);
    for (final category in categoryPaletteCategories) {
      expect(
        baseFill - luminance(categoryFillTintHex(category)),
        greaterThan(0.04),
        reason: '$category 강조 면이 기본 매장 면과 구분되지 않는다',
      );
      expect(
        saturation(categoryOutlineHex(category)) - baseOutlineSaturation,
        greaterThan(0.05),
        reason: '$category 강조 경계선이 기본 매장 경계선과 구분되지 않는다',
      );
    }
  });

  test('경계선은 면보다 확실히 진하다', () {
    // 면만 옅게 칠하고 테두리가 같이 옅어지면 매장 사이 구분이 사라진다.
    for (final category in categoryPaletteCategories) {
      final fill = luminance(categoryFillTintHex(category));
      final outline = luminance(categoryOutlineHex(category));
      expect(
        fill - outline,
        greaterThan(0.3),
        reason: '$category 면과 경계선의 명도 차가 부족하다',
      );
    }
  });

  test('리빙은 틸 계열 한 가지로 면·선이 함께 간다', () {
    // 사용자가 지목한 대분류다. 지도 경계선은 시트·chip 색(#87BEB8)을 같은
    // 계열에서 진하게 만든 값이라 **색상각이 같아야** "시트에서 본 틸 = 지도의
    // 틸"이 성립한다.
    final chip = HSLColor.fromColor(const Color(0xFF87BEB8));
    final outline = HSLColor.fromColor(parse(categoryOutlineHex('리빙')));
    expect(outline.hue, closeTo(chip.hue, 1.0));
    expect(outline.saturation, greaterThan(chip.saturation));
    expect(outline.lightness, lessThan(chip.lightness));
  });

  test('고른 매장 한 곳이 같은 카테고리의 나머지보다 진하다', () {
    // 선택 색이 파랑 하나이던 시절에는 이 위계 자체가 없었다 — 어느 매장을
    // 골라도 같은 파랑이라, 카테고리 강조를 켠 상태에서는 그 파란 면이 대분류
    // 색을 덮어 "무엇을 골랐는지"만 남고 "그게 무엇인지"가 사라졌다.
    //
    // **두 축 모두에서 앞선다.** 명도만 보면 진해진 것인지 탁해진 것인지
    // 구분할 수 없어, 한때 "진하게"를 명도 하락으로만 구현했다가 되돌렸다.
    for (final category in categoryPaletteCategories) {
      final selected = categorySelectedHex(category);
      final outline = categoryOutlineHex(category);
      expect(
        saturation(selected),
        greaterThan(saturation(outline)),
        reason: '$category 선택 잉크가 안 고른 같은 카테고리보다 또렷하지 않다',
      );
      expect(
        luminance(outline) - luminance(selected),
        greaterThan(0.02),
        reason: '$category 선택 잉크가 안 고른 같은 카테고리와 구분되지 않는다',
      );
      // 색상각은 유지된다 — 시트·chip에서 본 그 색이어야 한다.
      expect(
        HSLColor.fromColor(parse(selected)).hue,
        closeTo(HSLColor.fromColor(categoryColorFor(category)).hue, 1.0),
      );
    }
  });

  test('대분류가 없는 매장도 고르면 보인다', () {
    // 기본 매장 색으로 떨어뜨리면 눌렀는데 아무 일도 안 일어난 것처럼 보인다.
    expect(storeSelectionColorExpression().last, mapSelectionFallback);
    expect(
      luminance(mapSelectionFallback),
      lessThan(luminance(mapStoreOutline)),
    );
  });

  group('표현식', () {
    test('match + 문자열 label 형태다', () {
      final expr = storeCategoryHighlightFillColorExpression();
      // 배열을 label로 쓰는 형태는 GL Native에서 조용히 매치 0건이 된다.
      expect(expr[0], 'match');
      expect(expr[1], ['get', 'category']);
      for (var i = 2; i < expr.length - 1; i += 2) {
        expect(expr[i], isA<String>(), reason: 'label 자리에 배열이 들어갔다');
        expect(expr[i + 1], isA<String>());
      }
    });

    test('모든 대분류가 면·선 표현식에 들어 있다', () {
      final fill = storeCategoryHighlightFillColorExpression();
      final outline = storeCategoryHighlightOutlineExpression();
      for (final category in categoryPaletteCategories) {
        expect(fill, contains(category));
        expect(fill, contains(categoryFillTintHex(category)));
        expect(outline, contains(categoryOutlineHex(category)));
      }
    });

    test('모르는 대분류·category 없는 매장은 기본 매장 색으로 떨어진다', () {
      // 표현식의 마지막 원소가 default다. 여기가 바뀌면 대분류가 안 붙은
      // 매장들이 강조될 때 통째로 다른 색(최악은 검정)이 된다.
      expect(storeCategoryHighlightFillColorExpression().last, mapStoreFill);
      expect(storeCategoryHighlightOutlineExpression().last, mapStoreOutline);
    });
  });
}
