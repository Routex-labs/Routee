import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/route/vertical_preference.dart';

/// 선호 ↔ 서버 질의 값 매핑을 고정한다.
///
/// 이 값은 `GET /buildings/{id}/graph?vertical=`로 그대로 나가고, HTTP 리포지토리
/// 캐시 키의 일부이기도 하다. 철자가 하나 틀리면 서버는 조용히 기본 정책을
/// 돌려주고 화면은 "고른 대로 됐다"고 믿는다 — 어디서도 예외가 안 난다.
void main() {
  test('서버로 나가는 값은 auto·escalator·elevator다', () {
    expect(
      VerticalPreference.values.map((p) => p.wireValue),
      ['auto', 'escalator', 'elevator'],
    );
  });

  test('보내는 값과 읽는 값이 서로 맞물린다', () {
    for (final preference in VerticalPreference.values) {
      expect(
        VerticalPreference.fromWireValue(preference.wireValue),
        preference,
      );
    }
  });

  test('모르는 값과 null은 auto로 떨어진다', () {
    // 구버전이 남긴 값이나 서버가 새로 만든 정책 때문에 길찾기가 통째로
    // 멈추면 안 된다. 오늘 동작이 곧 auto라 사용자가 잃는 것도 없다.
    expect(VerticalPreference.fromWireValue(null), VerticalPreference.auto);
    expect(VerticalPreference.fromWireValue(''), VerticalPreference.auto);
    expect(
      VerticalPreference.fromWireValue('stairs'),
      VerticalPreference.auto,
    );
  });

  test('첫 값이 auto다 — 아무것도 안 고른 사용자의 기본값', () {
    expect(VerticalPreference.values.first, VerticalPreference.auto);
  });
}
