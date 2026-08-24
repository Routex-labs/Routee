import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/search/store_suggestions.dart';
import 'package:navigation_client/models/place/store_index_entry.dart';

/// 실제 매장 이름으로만 fixture를 만든다.
///
/// 출처는 `resources/studio/thehyundai-seoul-dabeeo/stores_*.json`(Routex-labs/fastapi)
/// (더현대 서울, 상호 659종). 가짜 이름으로 테스트하면 `A.P.C.`의 마침표나
/// `프라다`·`프라다 뷰티`·`프라다(남)` 같은 실제 접두 충돌을 못 만난다.
const _fixtureNames = <(String, String)>[
  // 라틴 상호 — 자모 분해 대상이 아닌 쪽
  ('MLB', 'B2'),
  ('AAPE', 'B2'),
  ('A.P.C.', '3F'),
  ('A.P.C 골프', '4F'),
  ('ARKET', '2F'),
  ('ARKET CAFE', '2F'),
  ('MAC', '1F'),
  ('DKNY', '3F'),
  // `이` 로 시작하는 상호 — 짧은 질의 회귀 방어
  ('이솝', '1F'),
  ('이미스', 'B2'),
  ('이비엠', '4F'),
  ('이탈리', 'B1'),
  ('이자벨마랑 (남/여)', '2F'),
  // 층마다 반복되는 시설 — 중복 제거 대상
  ('화장실', '1F'),
  ('화장실', '2F'),
  ('화장실', '3F'),
  ('장애인화장실', '1F'),
  ('에스컬레이터', '1F'),
  ('에스컬레이터', '2F'),
  ('엘리베이터', '1F'),
  // 표기만 다른 같은 이름
  ('물품 보관함', 'B1'),
  ('물품보관함', '1F'),
  // 초성·접두 후보가 여럿인 계열
  ('나이키 라이즈', 'B2'),
  ('나이키 골프', '4F'),
  ('나이키스윔', '4F'),
  ('나이스웨더', 'B2'),
  ('샤넬 뷰티', '1F'),
  ('구찌', '1F'),
  ('구찌 뷰티', '1F'),
  ('구찌 선글라스', '2F'),
  ('프라다', '1F'),
  ('프라다 뷰티', '1F'),
  ('프라다(남)', '2F'),
  ('룰루레몬', '3F'),
  ('뉴발란스', 'B2'),
  ('뉴발란스 키즈', '5F'),
  ('크록스', 'B2'),
  ('스타벅스 리저브', 'B2'),
  ('젠틀몬스터', '1F'),
  ('발렌시아가', '1F'),
  ('버버리', '1F'),
  ('설화수', '1F'),
  ('로에베', '1F'),
  ('톰브라운', '2F'),
  ('아크네 스튜디오', '2F'),
  ('파리크라상', 'B1'),
  ('몽클레르', '2F'),
  ('티파니앤코', '1F'),
  ('에르메스 뷰티', '1F'),
  ('타임', '3F'),
  ('타임 닥터', '2F'),
  ('타임옴므', '3F'),
  ('타임파리', '2F'),
  ('마리떼프랑소와저버/ LMC', 'B2'),
  ('언더커버', '2F'),
  ('아디다스 스타디움', '4F'),
  ('아크 테릭스', '4F'),
  ('오설록', 'B1'),
  ('안다르', '3F'),
];

/// L절 검증 기준인 **실제 오타 사례 20건**.
///
/// 왼쪽은 사람이 낼 법한 오타(모음 ㅐ/ㅔ 혼동, 된소리 누락·과잉, ㅓ/ㅏ 혼동,
/// 받침 ㄴ/ㅇ 혼동, 라틴 인접 키), 오른쪽은 fixture에 실재하는 상호다.
/// 20건 전부가 fixture 기준으로도, 상호 659종 전체 기준으로도 1위에 뜬다.
const _typoCases = <(String, String)>[
  ('샤낼 뷰티', '샤넬 뷰티'), // ㅔ → ㅐ (설계 문서 L절의 대표 예시)
  ('구지 뷰티', '구찌 뷰티'), // 된소리 누락
  ('프라타', '프라다'), // ㄷ → ㅌ
  ('룰루래몬', '룰루레몬'), // ㅔ → ㅐ
  ('뉴발란수', '뉴발란스'), // ㅡ → ㅜ
  ('크록쓰', '크록스'), // 된소리 과잉
  ('스타박스', '스타벅스 리저브'), // ㅓ → ㅏ, 상호 뒷부분 생략
  ('젠틀몬스타', '젠틀몬스터'), // ㅓ → ㅏ
  ('발렌시아까', '발렌시아가'), // 된소리 과잉
  ('버바리', '버버리'), // ㅓ → ㅏ
  ('설화쑤', '설화수'), // 된소리 과잉
  ('로에배', '로에베'), // ㅔ → ㅐ
  ('톰브라온', '톰브라운'), // ㅜ → ㅗ
  ('아크내', '아크네 스튜디오'), // ㅔ → ㅐ, 상호 뒷부분 생략
  ('이자밸마랑', '이자벨마랑 (남/여)'), // ㅔ → ㅐ
  ('파리크라산', '파리크라상'), // 받침 ㅇ → ㄴ
  ('몽클래르', '몽클레르'), // ㅔ → ㅐ
  ('티파니엔코', '티파니앤코'), // ㅐ → ㅔ
  ('aapa', 'AAPE'), // 라틴 — 자모 분해 없이 일반 편집거리
  ('dkni', 'DKNY'), // 라틴 — 인접 키
];

StoreIndexEntry _store(String name, String floor) => StoreIndexEntry(
  id: 'PO-$name-$floor',
  name: name,
  floorId: 'FL-$floor',
  floorName: floor,
  entranceNodeId: 'ND-$name-$floor',
);

List<StoreIndexEntry> get _stores => [
  for (final (name, floor) in _fixtureNames) _store(name, floor),
];

List<StoreSuggestion> _suggest(String query, {int limit = 8}) =>
    suggestStores(stores: _stores, query: query, limit: limit);

List<String> _names(String query, {int limit = 8}) => [
  for (final s in _suggest(query, limit: limit)) s.stores.first.name,
];

void main() {
  group('K. 자동완성 — 후보 종류와 순서', () {
    test('이름 prefix 일치가 가장 위다', () {
      final result = _suggest('나이');

      expect(result.first.stores.first.name, '나이키 골프');
      expect(result.every((s) => s.kind == SuggestionKind.prefix), isTrue);
      expect(_names('나이'), containsAll(['나이키 라이즈', '나이스웨더']));
    });

    // 같은 접두를 공유하면 짧은 이름이 위다. `타임`을 쳤는데 `타임파리`가
    // 먼저 나오면 사용자가 목록을 훑어야 한다.
    test('같은 종류 안에서는 짧은 이름이 먼저다', () {
      expect(_names('타임'), ['타임', '타임 닥터', '타임옴므', '타임파리']);
    });

    test('초성 질의는 초성으로 맞춘다', () {
      final result = _suggest('ㄴㅇㅋ');

      expect(_names('ㄴㅇㅋ'), ['나이키 골프', '나이키스윔', '나이키 라이즈']);
      expect(result.every((s) => s.kind == SuggestionKind.initials), isTrue);
      // 나이스웨더(ㄴㅇㅅㅇㄷ)는 초성이 다르므로 안 걸린다.
      expect(_names('ㄴㅇㅋ'), isNot(contains('나이스웨더')));
    });

    test('이름 가운데 일치는 부분 일치로 분류된다', () {
      final result = _suggest('라이즈');

      expect(result.single.stores.first.name, '나이키 라이즈');
      expect(result.single.kind, SuggestionKind.partial);
    });

    // prefix > 초성 > 부분 일치. 화장실은 접두, 장애인화장실은 가운데다.
    test('접두 일치가 부분 일치보다 위다', () {
      final result = _suggest('화장실');

      expect(result[0].stores.first.name, '화장실');
      expect(result[0].kind, SuggestionKind.prefix);
      expect(result[1].stores.first.name, '장애인화장실');
      expect(result[1].kind, SuggestionKind.partial);
    });

    test('같은 입력이면 순서가 매번 같다', () {
      // List.sort는 안정 정렬이 아니라, 동점을 명시적으로 깨지 않으면 호출마다
      // 순서가 달라질 수 있다.
      expect(_names('이'), _names('이'));
      expect(_names('ㅇ'), _names('ㅇ'));
    });
  });

  group('K. 실패 조건', () {
    // `ㄱ` 한 글자면 수백 건이 걸린다. 상한 없이 그리면 패널이 폭발한다.
    test('후보는 상한(기본 8건)을 넘지 않는다', () {
      // fixture에 ㅇ 초성 상호는 13종이다.
      expect(_suggest('ㅇ').length, maxStoreSuggestions);
      expect(maxStoreSuggestions, 8);
    });

    test('상한은 호출부가 줄일 수 있다', () {
      expect(_suggest('ㅇ', limit: 3).length, 3);
      expect(_suggest('ㅇ', limit: 0), isEmpty);
    });

    // 화장실·엘리베이터는 층마다 있어 같은 이름이 12건씩 나온다.
    test('같은 이름 시설은 한 줄로 묶고 개수를 남긴다', () {
      final result = _suggest('화장실');

      expect(result.where((s) => s.stores.first.name == '화장실').length, 1);
      expect(result.first.stores.length, 3);
      // 대표는 처음 나온 것 — 층 정보가 살아 있어야 화면이 뭔가 적을 수 있다.
      expect(result.first.stores.first.floorName, '1F');
    });

    test('표기만 다른 같은 이름도 묶인다', () {
      final result = _suggest('물품보관함');

      expect(result.single.stores.first.name, '물품 보관함');
      expect(result.single.stores.length, 2);
    });

    test('중복이 없으면 개수는 1이다', () {
      expect(_suggest('크록스').single.stores.length, 1);
    });

    // 질의 쪽만 정규화한다는 원칙은 표시용 원본에 대한 것이다. 매칭 키에서는
    // 양쪽의 구두점을 지워야 `apc`가 `A.P.C.`를 찾는다.
    test('구두점 상호는 어떻게 쳐도 찾히고 원본 이름은 그대로다', () {
      for (final query in ['apc', 'a.p.c', 'A.P.C.', 'APC']) {
        final result = _suggest(query);
        expect(result.first.stores.first.name, 'A.P.C.', reason: query);
        expect(result.map((s) => s.stores.first.name), contains('A.P.C 골프'));
      }
      // `/`도 마찬가지다.
      expect(_names('마리떼프랑소와저버lmc'), ['마리떼프랑소와저버/ LMC']);
    });

    test('띄어쓰기를 빼먹어도 찾힌다', () {
      expect(_names('나이키라'), ['나이키 라이즈']);
      expect(_names('스타벅스리저브'), ['스타벅스 리저브']);
    });

    // 조합 중 자모를 무시하면 초성 검색이 아예 동작하지 않는다.
    test('IME 조합 중 낱자 한 자도 후보를 만든다', () {
      final result = _suggest('ㅅ');

      expect(result, isNotEmpty);
      expect(result.every((s) => s.kind == SuggestionKind.initials), isTrue);
      expect(_names('ㅅ'), contains('샤넬 뷰티'));
    });

    test('IME 조합 중간 음절도 접두로 받는다', () {
      // `나이` 뒤에 ㅋ을 친 상태를 IME는 `나잌`(U+C78C = ㅇ+ㅣ+ㅋ)으로 낸다.
      // 음절로 비교하면 아무것도 못 찾지만 자모로 펴면 `나이키`의 접두사다.
      final composing = '나${String.fromCharCode(0xC78C)}';

      expect(_names(composing), ['나이키 골프', '나이키스윔', '나이키 라이즈']);
    });

    test('빈 질의·공백·구두점만 있는 질의는 후보가 없다', () {
      expect(_suggest(''), isEmpty);
      expect(_suggest('   '), isEmpty);
      expect(_suggest('...'), isEmpty);
    });

    test('매장 목록이 비면 조용히 빈 목록이다', () {
      expect(suggestStores(stores: const [], query: '나이키'), isEmpty);
    });

    test('어디에도 안 걸리는 질의는 빈 목록이다', () {
      expect(_suggest('asdfqwerzxcv'), isEmpty);
    });
  });

  group('L. 오타 교정 — 실제 오타 20건', () {
    // 검증 기준: 20건 목록 자체가 산출물이고, 교정률을 기록한다.
    for (final (typo, expected) in _typoCases) {
      test('$typo → $expected', () {
        final result = _suggest(typo);

        expect(result, isNotEmpty, reason: '$typo가 아무것도 못 찾았다');
        expect(result.first.stores.first.name, expected);
        expect(result.first.kind, SuggestionKind.correction);
      });
    }

    test('교정률 20/20', () {
      final corrected = _typoCases.where((c) {
        final result = _suggest(c.$1);
        return result.isNotEmpty &&
            result.first.stores.first.name == c.$2 &&
            result.first.kind == SuggestionKind.correction;
      });

      expect(corrected.length, _typoCases.length);
    });

    // 사용자가 "내가 오타를 냈구나"를 알 수 있어야 한다 — 화면이 읽을 표식.
    test('교정 후보는 스스로를 교정이라고 밝힌다', () {
      final result = _suggest('룰루래몬');

      expect(result.single.kind.isCorrection, isTrue);
      expect(SuggestionKind.prefix.isCorrection, isFalse);
      expect(SuggestionKind.partial.isCorrection, isFalse);
    });
  });

  group('L. 실패 조건 — 회귀 방어', () {
    // 정상 결과가 있으면 교정 후보를 위로 올리지 않는다. 여기서는 아예 만들지
    // 않는다 — 그래야 순서를 뒤집을 여지 자체가 없다.
    test('정상 후보가 있으면 교정 후보를 섞지 않는다', () {
      final result = _suggest('프라다');

      expect(_names('프라다'), ['프라다', '프라다(남)', '프라다 뷰티']);
      expect(result.any((s) => s.kind.isCorrection), isFalse);
    });

    test('교정이 붙어도 정상 질의 결과는 그대로다', () {
      // 세 질의 모두 교정 경로를 타지 않는다.
      expect(_names('나이키'), ['나이키 골프', '나이키스윔', '나이키 라이즈']);
      expect(_names('크록스'), ['크록스']);
      expect(_names('타임파리'), ['타임파리']);
    });

    // query.md의 `"이"` → 이솝 케이스. Wave 4에서 이미 한 번 다친 곳이다.
    test('`이` 는 이솝을 1위로 그대로 돌려준다', () {
      final result = _suggest('이');

      expect(result.first.stores.first.name, '이솝');
      expect(result.first.kind, SuggestionKind.prefix);
      expect(result.any((s) => s.kind.isCorrection), isFalse);
    });

    test('`MLB` 는 대소문자와 무관하게 정확히 걸린다', () {
      expect(_names('MLB'), ['MLB']);
      expect(_names('mlb'), ['MLB']);
      expect(_suggest('MLB').single.kind, SuggestionKind.prefix);
    });

    test('`화장실` 은 교정 없이 접두 일치로 잡힌다', () {
      expect(_suggest('화장실').first.kind, SuggestionKind.prefix);
      expect(_suggest('화장실').any((s) => s.kind.isCorrection), isFalse);
    });

    // 2글자 이하에서 편집거리 1을 허용하면 짧은 정상 질의가 다른 매장으로
    // 바뀐다. `구지`는 `구찌`와 자모 거리 1이지만 교정하지 않는다.
    test('2글자 질의에서는 교정이 동작하지 않는다', () {
      expect(_suggest('구지'), isEmpty);
      expect(_suggest('타암'), isEmpty);
      expect(minCorrectionQueryLength, 3);
    });

    // 초성 질의는 자모열 자체가 완성 글자와 다르다. 거리를 재면 아무 뜻이 없다.
    test('초성 질의에서는 교정을 시도하지 않는다', () {
      expect(_suggest('ㄱㄴㄷㄹㅁ'), isEmpty);
    });

    // 거리 2를 열면 둘 다 실재할 수 있는 이름이 서로를 부른다.
    test('자모 편집거리 2는 교정하지 않는다', () {
      // `크륵시`는 `크록스`와 자모 거리 2다.
      expect(_suggest('크륵시'), isEmpty);
      expect(maxCorrectionJamoDistance, 1);
    });
  });
}
