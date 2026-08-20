import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/category/category_label_order.dart';

void main() {
  test('Dart 문자열 비교는 실제 한글 카테고리를 가나다 순으로 정렬한다', () {
    final labels = ['패션', '가구', '편의시설', '레스토랑'];

    labels.sort(categoryLabelCompare);

    expect(labels, ['가구', '레스토랑', '패션', '편의시설']);
  });

  test('전체는 앞에 고정하고 같은 표시 label은 하나만 남긴다', () {
    final labels = sortedCategoryLabels([
      '패션',
      '편의시설',
      '전체',
      '카페',
      '패션',
    ]);

    expect(labels, ['전체', '카페', '패션', '편의시설']);
  });

  test('매장이 많은 순이 아니라 카테고리로 찾는 빈도순이다', () {
    // 매장 수는 패션(262) > 리빙(53) > 카페(46) > 음식점(59)인데, 카테고리로
    // 찾는 질의는 음식점·카페가 패션보다 많다. 매장 수로 정렬하면 이 기대가 깨진다.
    final labels = sortedCategoryLabels(['패션', '리빙', '카페', '음식점']);

    expect(labels, ['음식점', '카페', '패션', '리빙']);
  });

  test('대분류는 가나다가 아니라 고정 순서로 나온다', () {
    // 입력을 일부러 가나다 역순으로 준다. 가나다로 정렬하면
    // `리빙`이 맨 앞, `패션`이 뒤에서 두 번째가 되어 이 기대를 깬다.
    final labels = sortedCategoryLabels(kCategoryDisplayOrder.reversed);

    expect(labels, kCategoryDisplayOrder);
  });

  test('순서표에 없는 대분류는 사라지지 않고 뒤에 가나다로 붙는다', () {
    // 배포 시차 — 백엔드가 아직 옛 어휘를 주는 동안에도 chip이 보여야 한다.
    final labels = sortedCategoryLabels(['서비스', '패션', '식음료', '카페']);

    expect(labels, ['카페', '패션', '서비스', '식음료']);
  });

  test('영문 보조 정렬은 앞뒤 공백과 대소문자를 무시한다', () {
    final labels = sortedCategoryLabels(['fashion', ' Bakery ', 'apparel']);

    expect(labels, ['apparel', ' Bakery ', 'fashion']);
  });
}
