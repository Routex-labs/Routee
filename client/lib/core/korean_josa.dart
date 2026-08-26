/// 한글 받침에 따라 조사를 고르는 계산.
///
/// 화면 문구가 데이터(건물명·매장명)를 받아 조사를 붙일 때 쓴다. UI도 지도도
/// 모르는 순수 계산이라 여기 둔다.
library;

/// 한글 음절의 시작·끝 코드포인트와 종성 개수. 유니코드 한글 음절은
/// `0xAC00 + (초성 × 21 + 중성) × 28 + 종성` 한 줄로 정의돼 있다.
const _hangulSyllableStart = 0xAC00;
const _hangulSyllableEnd = 0xD7A3;
const _jongseongCount = 28;

/// 종성 'ㄹ'의 번호. **이 예외가 이 함수의 존재 이유다** — 받침이 있으면
/// '으로'라는 규칙만 쓰면 「서울」이 `서울으로`가 된다.
const _jongseongRieul = 8;

/// [word] 뒤에 붙일 방향 조사 — `'로'` 또는 `'으로'`.
///
/// 받침이 없거나 받침이 'ㄹ'이면 `'로'`, 그 밖에는 `'으로'`다.
/// 한글로 끝나지 않으면(영문 매장명·숫자·기호) `'로'`를 돌려준다 — 어느 쪽도
/// 확실하지 않을 때 더 자연스럽게 읽히는 쪽이다.
///
/// 빈 문자열이면 `'로'`다. 호출부가 이름을 못 받은 경우인데, 조사만 남는 문구는
/// 어차피 화면에 띄우지 않는다.
String directionJosa(String word) {
  final trimmed = word.trimRight();
  if (trimmed.isEmpty) return '로';
  final code = trimmed.codeUnitAt(trimmed.length - 1);
  if (code < _hangulSyllableStart || code > _hangulSyllableEnd) return '로';
  final jongseong = (code - _hangulSyllableStart) % _jongseongCount;
  if (jongseong == 0 || jongseong == _jongseongRieul) return '로';
  return '으로';
}

/// [word]에 방향 조사를 붙인 문자열. 예) `더현대 서울` → `더현대 서울로`.
String withDirectionJosa(String word) => '$word${directionJosa(word)}';
