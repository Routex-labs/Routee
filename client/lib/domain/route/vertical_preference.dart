/// 층을 옮길 때 **무엇을 타고 싶은가**. 서버 `GET /buildings/{id}/graph?vertical=`
/// 가 이 값에 맞춰 수직 전이 간선을 걸러 내려 준다.
///
/// **클라이언트 가중치로 "몇 층 이상이면 엘리베이터"를 만들지 않는다.** 그 방향은
/// 한 번 검토되어 기각됐다 — 근거는 `multi_floor_router.dart`의 `_selectPath`
/// 주석에 있다(층수에 따른 수단 선택은 백엔드 비용 상수의 소관이고, 경로 선택
/// 가중치가 뒤집을 문제가 아니다). 그래서 사용자가 직접 고르는 선호로 두고,
/// 실제 필터링은 이미 그 상수를 아는 서버에 맡긴다.
enum VerticalPreference {
  /// 서버 비용 상수가 알아서 고른다. **오늘 동작이 이것이다.**
  auto('auto', '자동'),
  escalator('escalator', '에스컬레이터'),
  elevator('elevator', '엘리베이터');

  const VerticalPreference(this.wireValue, this.label);

  /// 서버 질의 파라미터로 나가는 값. 화면에 문자열 리터럴을 흩뿌리지 않으려고
  /// 매핑을 이 한 곳에 둔다.
  final String wireValue;

  /// 사용자에게 보이는 이름.
  final String label;

  /// 저장소·서버에서 읽은 값을 되돌린다. **모르는 값은 [auto]다** — 구버전이
  /// 남긴 값이나 서버가 새로 만든 정책 때문에 길찾기가 통째로 멈추면 안 된다.
  static VerticalPreference fromWireValue(String? value) {
    for (final preference in VerticalPreference.values) {
      if (preference.wireValue == value) return preference;
    }
    return VerticalPreference.auto;
  }
}
