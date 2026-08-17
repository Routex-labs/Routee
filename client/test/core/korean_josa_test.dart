import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/core/korean_josa.dart';

/// 건물명은 데이터라 조사를 코드가 골라야 한다. 이 표가 그 규칙의 단일 출처다.
void main() {
  group('directionJosa', () {
    test('받침이 없으면 로', () {
      // 「코엑스」의 '스'는 받침이 없다.
      expect(directionJosa('코엑스'), '로');
      expect(directionJosa('롯데월드타워'), '로');
    });

    test('ㄹ 받침이면 로', () {
      // **이 케이스가 이 함수의 존재 이유다.** "받침 있으면 으로"만 쓰면
      // 「서울」이 `서울으로`가 된다.
      expect(directionJosa('더현대 서울'), '로');
      expect(directionJosa('신촌 밀'), '로');
    });

    test('ㄹ이 아닌 받침이면 으로', () {
      expect(directionJosa('스타필드 하남'), '으로');
      expect(directionJosa('본관'), '으로');
      expect(directionJosa('강남역'), '으로');
    });

    test('한글로 끝나지 않으면 로', () {
      // 영문 매장명·숫자·기호. 어느 쪽도 확실하지 않을 때 더 자연스러운 쪽이다.
      expect(directionJosa('IFC Mall'), '로');
      expect(directionJosa('제2터미널 B'), '로');
      expect(directionJosa('타워 1'), '로');
    });

    test('빈 이름이어도 터지지 않는다', () {
      // 건물을 아직 못 받은 경우다. 조사만 남는 문구는 화면에 안 띄우지만,
      // 여기서 던지면 문구를 만드는 build가 통째로 죽는다.
      expect(directionJosa(''), '로');
      expect(directionJosa('   '), '로');
    });

    test('뒤쪽 공백은 무시한다', () {
      // 시드 데이터에 꼬리 공백이 섞여 있으면 마지막 글자가 공백이 되어
      // 한글 판정이 통째로 빗나간다.
      expect(directionJosa('더현대 서울 '), '로');
      expect(directionJosa('본관  '), '으로');
    });
  });

  test('withDirectionJosa는 이름에 조사를 붙인다', () {
    expect(withDirectionJosa('더현대 서울'), '더현대 서울로');
    expect(withDirectionJosa('스타필드 하남'), '스타필드 하남으로');
  });
}
