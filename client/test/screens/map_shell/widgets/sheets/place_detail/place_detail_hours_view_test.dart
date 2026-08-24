import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/store/store_hours.dart';
import 'package:navigation_client/models/place/place_detail.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/place_detail/place_detail_hours_view.dart';
import 'package:routex_design_system/routex_design_system.dart';

/// 판정 자체는 `test/domain/store/store_hours_test.dart`가 본다. 여기서 보는 것은
/// **그 결과가 어떤 줄과 문장이 되는가**다. 화면을 띄우지 않고 확인한다.
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

  group('상태', () {
    test('세 상태를 같은 뜻으로 옮긴다', () {
      expect(routexHoursState(StoreOpenState.open), RoutexHoursState.open);
      expect(routexHoursState(StoreOpenState.closed), RoutexHoursState.closed);
      // 모르는 것을 닫혔다고 말하면 열려 있는 매장을 돌려보낸다.
      expect(
        routexHoursState(StoreOpenState.unknown),
        RoutexHoursState.unknown,
      );
    });
  });

  group('다음 전환 문장', () {
    String? detailAt(DateTime now, {String confirmedAt = '2026-08-10'}) {
      final section = hours(confirmedAt: confirmedAt);
      final week = storeHoursWeek(section, now);
      return routexHoursDetail(
        computeStoreHoursStatus(section, now),
        week.first.date,
      );
    }

    test('영업 중이면 닫는 시각을 말한다', () {
      expect(detailAt(kst(2026, 8, 11, 14)), '20:00 종료');
    });

    test('폐점 후에는 다음 개점 시각을 말한다', () {
      expect(detailAt(kst(2026, 8, 11, 21)), '내일 10:30 영업 시작');
    });

    // 이틀 이상 뒤는 "내일"로 뭉뚱그릴 수 없다. 월요일이 휴무라 일요일 폐점 뒤의
    // 다음 개점은 화요일이다.
    test('이틀 이상 뒤면 요일로 말한다', () {
      expect(detailAt(kst(2026, 8, 16, 21)), '화 10:30 영업 시작');
    });

    // 판정을 거둔 상태에서 전환 시각을 말하면, 거두지 않은 것과 같아진다.
    test('판정을 거두면 전환을 말하지 않는다', () {
      expect(detailAt(kst(2026, 8, 11, 14), confirmedAt: '2026-01-01'), isNull);
    });
  });

  group('요일 줄', () {
    test('라벨에 날짜를 섞지 않는다', () {
      final week = storeHoursWeek(hours(), kst(2026, 8, 11, 14));

      final days = routexHoursDays(week);

      expect(days.first.label, '화');
      expect(days.first.value, '10:30 - 20:00');
      expect(days.first.closed, isFalse);
    });

    test('구간이 없으면 휴무로 적고 무게를 낮춘다', () {
      final week = storeHoursWeek(hours(), kst(2026, 8, 10, 12));

      final today = routexHoursDays(week).first;

      expect(today.label, '월');
      expect(today.value, '휴무');
      expect(today.closed, isTrue);
    });

    // 예외 사유를 빼면 휴점일이 "그냥 닫힌 날"과 구분되지 않는다.
    test('예외의 사유는 그대로 옮긴다', () {
      final week = storeHoursWeek(
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

      final today = routexHoursDays(week).first;

      expect(today.note, '백화점 정기 휴점');
      expect(today.value, '휴무');
    });

    // 브레이크 타임은 줄로 나눈다. 한 줄에 이으면 가운뎃점이 시각 사이의 줄표에
    // 묻혀 네 시각이 한 덩어리로 읽힌다.
    test('구간이 여럿이면 순서를 지켜 줄로 나눈다', () {
      const section = HoursSection(
        weekly: {
          'tue': [
            StoreHoursInterval(open: '10:30', close: '14:00'),
            StoreHoursInterval(open: '17:00', close: '20:00'),
          ],
        },
        exceptions: [],
        utcOffsetMinutes: 540,
        confirmedAt: '2026-08-10',
      );

      final week = storeHoursWeek(section, kst(2026, 8, 11, 12));

      expect(
        routexHoursDays(week).first.value,
        '10:30 - 14:00\n17:00 - 20:00',
      );
    });
  });
}
