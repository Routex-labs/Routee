import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:routex_design_system/routex_design_system.dart';

import 'package:navigation_client/map/icon/category_icon.dart';
import 'package:navigation_client/map/icon/category_map_icon.dart';
import 'package:navigation_client/map/style/floor_facility_style.dart';

/// 지도 라벨에 붙는 대분류 아이콘의 규칙을 못 박는다.
///
/// 여기서 지키는 것은 셋이다.
///
/// 1. **아이콘이 두 개 뜨지 않는다.** 편의시설은 전용 아이콘 레이어가 이미
///    있으므로, 대분류 아이콘이 붙는 라벨 레이어에서 반드시 빠져야 한다.
/// 2. **이름이 아이콘 앞/뒤로 뒤집힌다.** `text-variable-anchor`가 두 값을
///    가져야 하고, 순서가 선호도다.
/// 3. **모든 대분류가 자기 아이콘을 갖는다.** 표현식에서 빠진 카테고리는 조용히
///    폴백 아이콘이 되어, 화면에서는 "분류가 없는 매장"과 구분되지 않는다.
void main() {
  /// `['==', ['get', 'name'], <값>]` 꼴에서 <값>만 뽑는다.
  List<String> nameOperands(List<Object> filter) => filter
      .skip(1) // 맨 앞의 'all'/'any'
      .cast<List<Object>>()
      .map((clause) => clause[2] as String)
      .toList();

  group('아이콘 표현식', () {
    test('모든 대분류가 자기 아이콘 이름을 갖는다', () {
      final expression = storeCategoryIconExpression();
      for (final category in categoryIconCategories) {
        expect(
          expression,
          contains(storeCategoryIconImageName(category)),
          reason:
              '$category가 표현식에서 빠지면 그 매장들이 폴백 아이콘으로 떨어진다. '
              '화면에서는 분류가 아예 없는 매장과 구분되지 않아 조용히 틀린다.',
        );
      }
    });

    test('match의 default는 폴백 아이콘이다', () {
      // match 표현식의 마지막 원소가 default. 분류가 없는 매장은 타일에
      // category 키 자체가 없어 여기로 떨어진다.
      expect(
        storeCategoryIconExpression().last,
        storeCategoryIconImageName(kStoreCategoryFallbackKey),
      );
    });

    test('match의 label 자리에는 문자열만 들어간다', () {
      // 배열을 label로 쓰는 형태는 MapLibre GL Native에서 조용히 매치 0건이 되는
      // 경로가 있다(category_map_filter.dart 주석). 이 규칙이 깨지면 실기기에서만
      // 아이콘이 전부 사라지고 웹에서는 멀쩡해 보인다.
      final expression = storeCategoryIconExpression();
      // [0] = 'match', [1] = ['get', 'category'], 이후 label/value 쌍, 마지막 default.
      for (var i = 2; i < expression.length - 1; i += 2) {
        expect(expression[i], isA<String>());
      }
    });

    test('선택 표현식은 같은 feature의 아이콘 이름만 바꾼다', () {
      const selectedId = 'store-osulloc';
      final expression = storeCategoryIconExpression(
        highlightedStoreId: selectedId,
      );
      expect(expression[0], 'case');
      expect(expression[1], [
        '==',
        ['get', 'id'],
        selectedId,
      ]);
      expect(
        expression.toString(),
        contains(selectedStoreCategoryIconImageName('카페')),
      );
      expect(expression.toString(), contains(storeCategoryIconImageName('카페')));
    });

    test('등록 대상에 폴백이 포함된다', () {
      // 폴백 비트맵을 등록하지 않으면 분류 없는 매장이 아이콘 없이 그려지고
      // 로그도 남지 않는다.
      expect(storeCategoryIconKeys, contains(kStoreCategoryFallbackKey));
      expect(
        storeCategoryIconKeys.toSet().length,
        storeCategoryIconKeys.length,
        reason: '이름이 중복되면 addImage가 뒤엣것을 버린다.',
      );
    });
  });

  group('이름이 아이콘 앞/뒤로 뒤집힌다', () {
    test('배지가 화장실 아이콘과 같은 크기다', () {
      // 피드백 그대로다 — 두 값이 갈라지면 같은 도면 위에서 마커가 다른 무게로
      // 읽힌다. 같은 함수를 쓰는지까지 잠가 둔다.
      for (final dpr in [1.0, 2.0, 2.625, 3.5]) {
        expect(storeCategoryIconSize(dpr), indoorMarkerIconSize(dpr));
      }
    });

    test('네이티브에서는 마커 크기가 화면 배율을 따라간다', () {
      // 회귀 대상이 이 저장소에서 실제로 났던 버그다. `icon-size`는 비트맵의
      // **물리 픽셀**에 곱해지고 `text-size`는 논리 픽셀이라, 배율을 안 곱하면
      // 고밀도 화면에서 아이콘만 배율만큼 작아진다.
      expect(
        indoorMarkerIconSize(3.0, isWeb: false),
        closeTo(indoorMarkerIconSize(1.0, isWeb: false) * 3, 1e-9),
      );
    });

    test('네이티브에서 논리 px로 환산하면 배율과 무관하게 같은 크기다', () {
      for (final dpr in [1.0, 2.0, 2.625, 3.5]) {
        final logical =
            indoorMarkerIconSize(dpr, isWeb: false) * kIconCanvasPx / dpr;
        expect(logical, closeTo(kIndoorMarkerLogicalPx, 1e-9));
      }
    });

    test('웹에서는 배율을 곱하지 않는다', () {
      // 웹 구현은 비트맵을 pixelRatio 1로 등록해서 `icon-size`가 곱해지는 대상이
      // 이미 논리(CSS) 픽셀이다. 네이티브와 같은 식을 쓰면 아이콘만 배율배로
      // 커진다 — Chrome 기기 에뮬레이션(배율 3)에서 12px 배지가 36px으로 떴다.
      for (final dpr in [1.0, 2.0, 3.0, 3.5]) {
        final logical = indoorMarkerIconSize(dpr, isWeb: true) * kIconCanvasPx;
        expect(logical, closeTo(kIndoorMarkerLogicalPx, 1e-9));
      }
    });

    test('배지가 색점으로만 읽힐 만큼 작지는 않다', () {
      // 예전 배지는 5.5 논리 px이라 글리프가 안 보이고 색점으로만 읽혔다.
      // 화장실 아이콘이 통과한 크기(약 11.5)가 하한의 근거다.
      expect(kIndoorMarkerLogicalPx, greaterThanOrEqualTo(10.0));
    });
  });

  group('라벨 필터 — 아이콘이 두 개 뜨지 않는다', () {
    test('수직이동 시설은 매장명 라벨에서 빠진다', () {
      final excluded = nameOperands(storeLabelWithCategoryIconFilter());
      for (final name in kVerticalTransportStoreNames) {
        expect(excluded, contains(name));
      }
    });

    test('편의시설도 매장명 라벨에서 빠진다', () {
      final excluded = nameOperands(storeLabelWithCategoryIconFilter());
      for (final name in kStoreFacilityStyleByName.keys) {
        expect(
          excluded,
          contains(name),
          reason:
              '$name은 전용 아이콘 레이어가 이미 아이콘을 그린다. 여기서 빼지 않으면 '
              '같은 폴리곤에 시설 아이콘과 대분류 아이콘이 둘 다 뜬다.',
        );
      }
    });

    test('편의시설 라벨 필터는 뺀 집합을 정확히 되받는다', () {
      // 한쪽만 고치면 시설 이름이 지도에서 통째로 사라지거나(빼기만 하고 되받지
      // 않음) 아이콘이 두 개가 된다(되받기만 하고 빼지 않음).
      expect(
        nameOperands(facilityStoreLabelFilter()).toSet(),
        kStoreFacilityStyleByName.keys.toSet(),
      );
    });

    test('두 필터는 겹치지 않는다', () {
      final labelled = nameOperands(storeLabelWithCategoryIconFilter()).toSet();
      final facility = nameOperands(facilityStoreLabelFilter()).toSet();
      // 매장명 라벨 필터는 `!=`의 all이라 여기 적힌 이름이 곧 제외 대상이다.
      // 편의시설 필터가 고르는 이름은 전부 그 제외 목록 안에 있어야 한다.
      expect(facility.difference(labelled), isEmpty);
    });

    test('필터 형태는 == / != 비교만 쓴다', () {
      for (final filter in [
        storeLabelWithCategoryIconFilter(),
        facilityStoreLabelFilter(),
      ]) {
        for (final clause in filter.skip(1).cast<List<Object>>()) {
          expect(clause[0], anyOf('==', '!='));
          expect(clause[1], ['get', 'name']);
        }
      }
    });
  });

  testWidgets('아이콘 비트맵이 PNG로 만들어진다', (tester) async {
    // **runAsync가 필수다.** testWidgets 본문은 FakeAsync 위에서 돌고,
    // `Picture.toImage`/`Image.toByteData`의 Future는 엔진이 실제 시간에
    // 완료시킨다. 가짜 시간에서 기다리면 절대 풀리지 않아 테스트가 통째로
    // 10분 타임아웃까지 매달린다(실패로 한 번 확인했다).
    final bytes = await tester.runAsync(() => renderStoreCategoryIconPng('패션'));
    expect(bytes, isNotNull);
    expect(bytes!, isNotEmpty);
    // PNG 시그니처. addImage가 받는 형식이 아니면 지도에서 조용히 무시된다.
    expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });

  testWidgets('선택 아이콘은 디자인시스템 포인트 색 비트맵을 갖는다', (tester) async {
    final centerColor = await tester.runAsync(() async {
      final bytes = await renderStoreCategoryIconPng('카페', selected: true);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final rgba = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      // 중앙은 흰 글리프가 덮을 수 있으므로 글리프 바깥의 색 면을 읽는다.
      final offset = ((24 * frame.image.width) + 24) * 4;
      return ui.Color.fromARGB(
        rgba!.getUint8(offset + 3),
        rgba.getUint8(offset),
        rgba.getUint8(offset + 1),
        rgba.getUint8(offset + 2),
      );
    });
    expect(centerColor, RoutexColorTokens.light.actionPrimary);
    expect(
      RoutexColorTokens.light.actionPrimary,
      isNot(categoryColorFor('카페')),
    );
    expect(
      selectedStoreCategoryIconImageName('카페'),
      isNot(storeCategoryIconImageName('카페')),
      reason: 'MapLibre는 등록된 PNG를 이름으로 고르므로 두 키가 달라야 한다',
    );
  });
}
