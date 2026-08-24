/// 사용자에게 표시하는 카테고리 label의 정렬 규칙.
///
/// Dart의 [String.compareTo]는 유니코드 코드포인트 순으로 비교하며, 완성형
/// 한글 음절도 `가`부터 `힣`까지 가나다 순서로 배치되어 있어 현재 카테고리
/// label 정렬에 그대로 사용할 수 있다. 영문 label은 앞뒤 공백과 대소문자만
/// 보조 정규화하고, 화면에 표시하는 원문은 바꾸지 않는다.
int categoryLabelCompare(String a, String b) {
  final normalizedA = a.trim().toLowerCase();
  final normalizedB = b.trim().toLowerCase();
  final normalizedOrder = normalizedA.compareTo(normalizedB);
  return normalizedOrder != 0 ? normalizedOrder : a.compareTo(b);
}

/// 대분류 chip을 늘어놓는 순서. **가나다도 매장 수도 아니고, 찾는 빈도순이다.**
///
/// 매장 수로 두면 `패션`(262)이 1번인데 패션을 카테고리로 찾는 질의는 14건뿐이다 —
/// 브랜드명을 아는 매장은 이름으로 찾고 **모르는 것만 카테고리로 찾는다.**
/// `편의시설`은 질의가 가장 많지만 맨 뒤다. 시설은 이미 지도에 아이콘으로 그려져
/// chip 없이 보이고, chip을 누르면 주차 787건이 따라온다.
/// 질의 수 표와 세트의 한계는 `docs/store-category-resurvey.md`.
///
/// 매장 수 내림차순이 아니라 **표로 박아 두는** 이유는, 매장 수는 재분류할 때마다
/// 바뀌어서 chip 위치가 같이 움직이기 때문이다(이번 재조사에서 실제로 크게 바뀌었다).
/// 순서표에 없는 값은 뒤에 가나다로 붙어, 배포 시차로 백엔드가 아직
/// `서비스`·`식음료`를 주는 동안에도 chip이 사라지지 않는다.
const kCategoryDisplayOrder = <String>[
  '음식점',
  '카페',
  '패션',
  '뷰티',
  '식품관',
  '키즈',
  '리빙',
  '편의시설',
];

/// 중복 label을 제거하고 [kCategoryDisplayOrder] 순서로 정렬한다.
///
/// [leadingLabels]에 포함된 값이 실제 목록에 있으면 지정 순서대로 맨 앞에
/// 유지한다. 기본값인 `전체`가 원본에 없으면 새로 만들지는 않는다.
/// 순서표에 없는 label은 그 뒤에 가나다로 붙는다.
List<String> sortedCategoryLabels(
  Iterable<String?> labels, {
  List<String> leadingLabels = const ['전체'],
}) {
  final unique = <String>{};
  for (final label in labels) {
    if (label == null || label.trim().isEmpty) continue;
    unique.add(label);
  }

  final leading = <String>[];
  for (final label in leadingLabels) {
    if (unique.remove(label)) leading.add(label);
  }

  final known = [
    for (final label in kCategoryDisplayOrder)
      if (unique.remove(label)) label,
  ];
  final rest = unique.toList()..sort(categoryLabelCompare);
  return [...leading, ...known, ...rest];
}
