import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/event/building_events.dart';

/// 이 검사가 지키는 것 — 목록이 "오늘 열려 있는 것만, 먼저 끝나는 것부터"인가.
/// 날짜 경계(시작일·종료일 당일)와 깨진 파일 판정이 실패 조건이다.
void main() {
  const json = '''
  {"captured_on":"2026-08-21","events":[
    {"title":"상설 전시","start":"2026-07-16","end":"2026-11-02",
     "place":"6층 ALT.1","floor":"6F","store_id":"PO-alt1"},
    {"title":"이번 주 팝업","start":"2026-08-20","end":"2026-08-26",
     "place":"지하2층 POP-UP@ICONIC","floor":"B2","store_id":"PO-icon"},
    {"title":"좌표 없는 행사","start":"2026-08-20","end":"2026-08-26",
     "place":"지하1층 중앙 에스컬레이터 옆","floor":null,"store_id":null},
    {"title":"지난 행사","start":"2026-08-01","end":"2026-08-10",
     "place":"1층","floor":"1F","store_id":"PO-gate"}
  ]}''';

  test('열려 있는 것만 남고, 먼저 끝나는 것이 위로 온다', () {
    final open = parseBuildingEvents(json).openOn('2026-08-24');

    expect(open.map((e) => e.title), [
      // 같은 날 끝나는 둘은 안내가 되는 쪽이 먼저다.
      '이번 주 팝업',
      '좌표 없는 행사',
      '상설 전시',
    ]);
    expect(open.first.navigable, isTrue);
    // 좌표가 없어도 목록에서 빠지지 않는다 — 장소 문구는 남아 있다.
    expect(open[1].navigable, isFalse);
    expect(open[1].place, isNotEmpty);
  });

  test('시작일·종료일 당일도 열려 있는 것으로 센다', () {
    final events = parseBuildingEvents(json);
    expect(
      events.openOn('2026-08-20').map((e) => e.title),
      contains('이번 주 팝업'),
    );
    expect(
      events.openOn('2026-08-26').map((e) => e.title),
      contains('이번 주 팝업'),
    );
    expect(
      events.openOn('2026-08-27').map((e) => e.title),
      isNot(contains('이번 주 팝업')),
    );
  });

  test('본문 블록은 순서 그대로 오고, 모르는 종류는 목록을 깨지 않는다', () {
    const withDetails = '''
    {"events":[{"title":"팝업","start":"2026-08-20","end":"2026-08-26",
      "place":"B2","floor":"B2","store_id":"PO-x","details":[
        {"t":"h","text":"SPECIAL PROMOTION"},
        {"t":"p","text":"본문"},
        {"t":"prod","lines":["1만원 이상","띠부씰 증정"],"image":"assets/events/a.jpg"},
        {"t":"notice","items":["한정 수량"]},
        {"t":"신종류","text":"모르는 것"}
      ]}]}''';
    final e = parseBuildingEvents(withDetails).events.single;

    expect(e.details.map((b) => b.kind), ['h', 'p', 'prod', 'notice', '신종류']);
    expect(e.details[2].lines, ['1만원 이상', '띠부씰 증정']);
    expect(e.details[2].image, 'assets/events/a.jpg');
    expect(e.details[3].items, ['한정 수량']);
    // 모르는 종류도 버리지 않는다 — 화면이 건너뛸 뿐이다.
    expect(e.details.last.text, '모르는 것');
  });

  test('빈 목록은 성공이 아니라 실패다', () {
    expect(() => parseBuildingEvents('{"events":[]}'), throwsFormatException);
    expect(() => parseBuildingEvents('[]'), throwsFormatException);
  });

  const mixed = '''
    {"events":[
      {"title":"쇼핑","start":"2026-08-18","end":"2026-09-13","diary":"shopping",
       "place":"2층 해당 매장","floor":"2F","store_id":"PO-s"},
      {"title":"늦게 끝나는 팝업","start":"2026-08-20","end":"2026-09-02","diary":"popup",
       "place":"지하2층 ATTAG!","floor":"B2","store_id":"PO-a"},
      {"title":"먼저 끝나는 팝업","start":"2026-08-20","end":"2026-08-26","diary":"popup",
       "place":"지하2층 POP-UP@ICONIC","floor":"B2","store_id":"PO-i"},
      {"title":"다이닝","start":"2026-08-21","end":"2026-08-27","diary":"tasty",
       "place":"지하1층 식품행사장","floor":"B1","store_id":"PO-f"},
      {"title":"쪽이 새로 생겼다","start":"2026-08-20","end":"2026-08-26","diary":"culture",
       "place":"6층","floor":"6F","store_id":"PO-c"}
    ]}''';

  group('갈래', () {
    test('갈래로 좁히면 그 쪽에서 온 것만 남는다', () {
      final events = parseBuildingEvents(mixed);
      expect(
        events
            .openOn('2026-08-24', diary: EventDiary.popup)
            .map((e) => e.title),
        ['먼저 끝나는 팝업', '늦게 끝나는 팝업'],
      );
      expect(
        events
            .openOn('2026-08-24', diary: EventDiary.tasty)
            .map((e) => e.title),
        ['다이닝'],
      );
    });

    test('갈래 순서로 이어 붙이고, 갈래 안은 먼저 끝나는 것부터다', () {
      expect(
        parseBuildingEvents(
          mixed,
        ).openOnByDiary('2026-08-24').map((e) => e.title),
        [
          '먼저 끝나는 팝업',
          '늦게 끝나는 팝업',
          '다이닝',
          '쇼핑',
          // 모르는 쪽은 버리지 않고 맨 뒤에 붙는다.
          '쪽이 새로 생겼다',
        ],
      );
    });

    test('모르는 쪽·빠진 쪽은 other로 떨어지고 배지를 그리지 않는다', () {
      final open = parseBuildingEvents(mixed).openOn('2026-08-24');
      final unknown = open.firstWhere((e) => e.title == '쪽이 새로 생겼다');
      expect(unknown.diary, EventDiary.other);
      expect(unknown.diary.label, isEmpty);
      expect(EventDiary.parse(null), EventDiary.other);
    });
  });

  group('쪽', () {
    const withPages = '''
    {"diaries":[
      {"key":"popup","title":"WEEKLY POP-UP","image":"assets/events/diary_popup.png"},
      {"key":"tasty","title":"TASTY SEOUL","image":"assets/events/diary_tasty.png"},
      {"key":"shopping","title":"SHOPPING NEWS","image":"assets/events/diary_shopping.png"}
     ],
     "events":[
      {"title":"팝업 하나","start":"2026-08-20","end":"2026-08-26","diary":"popup",
       "place":"지하2층","floor":"B2","store_id":"PO-i"},
      {"title":"팝업 둘","start":"2026-08-20","end":"2026-09-02","diary":"popup",
       "place":"지하2층","floor":"B2","store_id":"PO-a"},
      {"title":"지난 다이닝","start":"2026-08-01","end":"2026-08-10","diary":"tasty",
       "place":"지하1층","floor":"B1","store_id":"PO-f"}
     ]}''';

    test('오늘 자식이 있는 쪽만 남고, 건수가 함께 온다', () {
      final pages = parseBuildingEvents(withPages).diariesOpenOn('2026-08-24');

      // 다이닝은 오늘 열리는 것이 없고 쇼핑은 자식이 아예 없다 — 눌러서 빈
      // 목록이 나오는 카드를 만들지 않는다.
      expect(pages.map((p) => p.page.diary), [EventDiary.popup]);
      expect(pages.single.count, 2);
      expect(pages.single.page.title, 'WEEKLY POP-UP');
    });

    test('쪽이 없는 파일도 그대로 읽힌다', () {
      final events = parseBuildingEvents(mixed);
      expect(events.diaries, isEmpty);
      expect(events.diariesOpenOn('2026-08-24'), isEmpty);
      // 쪽이 없다고 행사까지 사라지지는 않는다.
      expect(events.openOn('2026-08-24'), isNotEmpty);
    });
  });
}
