import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/category/category_taxonomy.dart';

/// 테스트 입력을 실제 데이터 모양(대분류 + 소분류 쌍)으로 쓰기 위한 헬퍼.
(String?, String?) store(String? category, String? subcategory) =>
    (category, subcategory);

void main() {
  group('subcategoryOptionsFor', () {
    test('주차·교통과 시설 시트가 맡은 셋은 pill에서 빠진다', () {
      final options = subcategoryOptionsFor('편의시설', [
        store('편의시설', '주차'),
        store('편의시설', 'escalator'),
        store('편의시설', 'elevator'),
        store('편의시설', 'restroom'),
        store('편의시설', '교통'),
        store('편의시설', '락커'),
      ]);

      expect(options.map((o) => o.value), ['락커']);
    });

    test('영어 원본값은 한글 label로 보여주되 value는 원본을 유지한다', () {
      final options = subcategoryOptionsFor('편의시설', [
        store('편의시설', 'facility'),
      ]);

      expect(options, hasLength(1));
      expect(options.single.value, 'facility');
      expect(options.single.label, '생활편의');
    });

    test('다른 대분류의 소분류는 섞이지 않는다', () {
      final options = subcategoryOptionsFor('식음료', [
        store('식음료', '레스토랑'),
        store('식음료', '카페·베이커리'),
        store('패션', '명품'),
        store('리빙', '가구·인테리어'),
        store(null, '분류없음'),
      ]);

      expect(options.map((o) => o.value), ['레스토랑', '카페·베이커리']);
    });

    test('null·빈 문자열·공백뿐인 subcategory는 걸러진다', () {
      final options = subcategoryOptionsFor('식음료', [
        store('식음료', null),
        store('식음료', ''),
        store('식음료', '   '),
        store('식음료', '레스토랑'),
      ]);

      expect(options.map((o) => o.value), ['레스토랑']);
    });

    test('중복 제거는 원본값 기준이라 label이 같아도 값이 다르면 남는다', () {
      final options = subcategoryOptionsFor('식음료', [
        store('식음료', '레스토랑'),
        store('식음료', '레스토랑'),
        store('식음료', '레스토랑'),
        // 서로 다른 원본값이지만 표시 label은 둘 다 '레스토랑'이다.
        // 필터는 원본값으로 걸리므로 합치면 한쪽이 통째로 사라진다.
        store('식음료', 'restaurant'),
      ]);

      expect(options.map((o) => o.value), ['restaurant', '레스토랑']);
      expect(options.map((o) => o.label), ['레스토랑', '레스토랑']);
    });

    test('정렬은 원본값이 아니라 표시 label 기준이다', () {
      final options = subcategoryOptionsFor('식음료', [
        store('식음료', 'restaurant'), // 레스토랑
        store('식음료', 'cafe'), // 카페·베이커리
        store('식음료', '델리'),
      ]);

      // 원본값 순이면 cafe·restaurant·델리지만, label 가나다 순은
      // 델리 → 레스토랑 → 카페·베이커리다.
      expect(options.map((o) => o.label), ['델리', '레스토랑', '카페·베이커리']);
    });

    test('전체 옵션은 붙이지 않는다', () {
      final options = subcategoryOptionsFor('식음료', [
        store('식음료', '레스토랑'),
        store('식음료', '카페·베이커리'),
      ]);

      expect(options.map((o) => o.label), isNot(contains('전체')));
    });

    test('해당 대분류에 매장이 없으면 빈 목록', () {
      expect(subcategoryOptionsFor('키즈', const []), isEmpty);
      expect(subcategoryOptionsFor('키즈', [store('패션', '명품')]), isEmpty);
    });
  });

  group('hasMeaningfulSubcategories', () {
    test('뷰티처럼 소분류가 하나뿐이면 pill 줄을 띄우지 않는다', () {
      final options = subcategoryOptionsFor('뷰티', [
        store('뷰티', '화장품·향수'),
        store('뷰티', '화장품·향수'),
      ]);

      expect(options, hasLength(1));
      expect(hasMeaningfulSubcategories(options), isFalse);
    });

    test('노출 대상이 하나도 없어도 false', () {
      final options = subcategoryOptionsFor('편의시설', [store('편의시설', '주차')]);

      expect(hasMeaningfulSubcategories(options), isFalse);
    });

    test('소분류가 둘 이상이면 true', () {
      final options = subcategoryOptionsFor('식음료', [
        store('식음료', '레스토랑'),
        store('식음료', '카페·베이커리'),
      ]);

      expect(hasMeaningfulSubcategories(options), isTrue);
    });
  });

  group('kHiddenSubcategoryValues', () {
    test('시설 시트가 맡은 셋의 영어·한글 표기를 모두 담는다', () {
      // 한 표기만 넣으면 배포 시차로 다른 표기가 들어온 날 그 시설이 카테고리
      // 목록에 되살아나, 같은 답에 이르는 길이 둘이 된다.
      expect(
        kHiddenSubcategoryValues,
        containsAll(<String>['escalator', 'elevator', 'restroom']),
      );
      expect(
        kHiddenSubcategoryValues,
        containsAll(<String>['에스컬레이터', '엘리베이터', '화장실']),
      );
    });

    test('훑을 값이 있는 나머지는 그대로 둔다', () {
      // 주차·교통은 훑을 값이 없어서, 화장실 셋은 문이 따로 생겨서 빠졌다.
      // 그 두 기준 어느 쪽도 아닌 시설까지 쓸어 담으면 편의시설 칩이 빈다.
      expect(kHiddenSubcategoryValues, containsAll(<String>['주차', '교통']));
      expect(kHiddenSubcategoryValues, isNot(contains('facility')));
      expect(kHiddenSubcategoryValues, isNot(contains('락커')));
    });
  });
}
