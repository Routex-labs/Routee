import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/models/place/place_detail.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/place_detail/place_detail_hours_section.dart';

import '../../../../../support/routex_test_host.dart';

/// 판정은 `test/domain/store/store_hours_test.dart`, 값을 줄로 옮기는 규칙은
/// `place_detail_hours_view_test.dart`가 본다. 여기서 보는 것은 **그 둘이
/// 붙었을 때 화면에 무엇이 남는가**와 접힘/펼침이다.
void main() {
  HoursSection hours({
    List<StoreHoursException> exceptions = const [],
    String confirmedAt = '2026-08-10',
  }) => HoursSection(
    weekly: const {
      'mon': [],
      'tue': [StoreHoursInterval(open: '10:30', close: '20:00')],
      'wed': [StoreHoursInterval(open: '10:30', close: '20:00')],
      'thu': [StoreHoursInterval(open: '10:30', close: '20:00')],
      'fri': [StoreHoursInterval(open: '10:30', close: '20:30')],
      'sat': [StoreHoursInterval(open: '10:30', close: '20:30')],
      'sun': [StoreHoursInterval(open: '10:30', close: '20:30')],
    },
    exceptions: exceptions,
    utcOffsetMinutes: 540,
    confirmedAt: confirmedAt,
  );

  /// 매장 현지(KST) 벽시계 → 기기 시각.
  DateTime kst(int year, int month, int day, int hour, [int minute = 0]) =>
      DateTime.utc(
        year,
        month,
        day,
        hour,
        minute,
      ).subtract(const Duration(minutes: 540));

  Future<void> pump(WidgetTester tester, HoursSection section, DateTime now) =>
      tester.pumpWidget(
        appThemedHost(
          SingleChildScrollView(
            child: PlaceHoursSection(hours: section, now: now),
          ),
        ),
      );

  testWidgets('영업 중이면 닫는 시각을 함께 말한다', (tester) async {
    await pump(tester, hours(), kst(2026, 8, 11, 14));

    expect(find.textContaining('영업 중'), findsOneWidget);
    expect(find.textContaining('20:00 종료'), findsOneWidget);
  });

  testWidgets('폐점 후에는 다음 개점 시각을 말한다', (tester) async {
    await pump(tester, hours(), kst(2026, 8, 11, 21));

    expect(find.textContaining('영업 종료'), findsOneWidget);
    expect(find.textContaining('내일 10:30 영업 시작'), findsOneWidget);
  });

  // 오늘 줄만 펴 두는 이유는 나머지 섹션이 화면 밖으로 밀리지 않게 하기 위해서다.
  testWidgets('접혀 있으면 오늘 줄만 보이고 펼치면 7일이 나온다', (tester) async {
    await pump(tester, hours(), kst(2026, 8, 11, 14));

    expect(find.text('화 · 10:30 - 20:00'), findsOneWidget);
    expect(find.text('수 · 10:30 - 20:00'), findsNothing);

    await tester.tap(find.textContaining('영업 중'));
    await tester.pumpAndSettle();

    expect(find.text('수 · 10:30 - 20:00'), findsOneWidget);
    // 다음 월요일까지 7일. 월요일은 휴무다.
    expect(find.text('월 · 휴무'), findsOneWidget);
  });

  testWidgets('휴무 요일은 휴무로 적는다', (tester) async {
    await pump(tester, hours(), kst(2026, 8, 10, 12));

    expect(find.text('월 · 휴무'), findsOneWidget);
  });

  // 예외 사유를 빼면 휴점일이 "그냥 닫힌 날"과 구분되지 않는다.
  testWidgets('예외 날짜에는 사유를 함께 적는다', (tester) async {
    await pump(
      tester,
      hours(
        exceptions: const [
          StoreHoursException(
            date: '2026-08-11',
            closed: true,
            intervals: [],
            note: '백화점 정기 휴점',
          ),
        ],
      ),
      kst(2026, 8, 11, 14),
    );

    expect(find.text('백화점 정기 휴점'), findsOneWidget);
    expect(find.text('화 · 휴무'), findsOneWidget);
  });

  // 낡은 데이터에서 "영업 종료"로 떨어뜨리면 열려 있는 매장을 돌려보낸다.
  testWidgets('확인일이 오래되면 판정 대신 안내를 보여 준다', (tester) async {
    await pump(tester, hours(confirmedAt: '2026-01-01'), kst(2026, 8, 11, 14));

    expect(find.textContaining('오래됐'), findsWidgets);
    expect(find.textContaining('영업 중'), findsNothing);
    // 판정만 거두고 요일 표는 남긴다 — 통째로 지우면 "정보가 없는 앱"이 된다.
    expect(find.text('화 · 10:30 - 20:00'), findsOneWidget);
  });

  testWidgets('최근 확인일은 본문 위계를 흐리지 않도록 숨긴다', (tester) async {
    await pump(tester, hours(), kst(2026, 8, 11, 14));

    expect(find.textContaining('2026-08-10'), findsNothing);
  });

  // 머리 줄의 "오래됐어요"는 주장이고 확인일은 그 근거다. 펼쳐야 근거가 나오면
  // 읽는 사람은 무엇을 보고 판단할지 알 수 없다.
  // 임계값을 넘기면 `영업 중` 판정은 여전히 거두지만, 확인일은 화면에 적지 않는다.
  // 날짜 한 줄이 멀쩡한 매장에도 경고처럼 읽혀서다.
  testWidgets('오래된 정보라도 확인일을 적지 않는다', (tester) async {
    await pump(tester, hours(confirmedAt: '2026-01-01'), kst(2026, 8, 11, 14));

    expect(find.textContaining('2026-01-01'), findsNothing);
    expect(find.textContaining('달라졌을 수 있어요'), findsNothing);
    // 접힘 상태는 그대로다.
    expect(find.text('수 · 10:30 - 20:00'), findsNothing);
  });
}
