import 'package:routex_design_system/routex_design_system.dart';

import '../../../../../domain/store/store_hours.dart';

/// 영업시간 판정 결과를 Runtime Kit이 그리는 값으로 바꾼다.
///
/// **판정은 여기서 하지 않는다.** `domain/store/store_hours.dart`의 순수 함수가
/// 계산한 결과를 문장과 줄로 옮기기만 한다. 폐점 정각·자정 넘김 같은 경계는
/// `test/domain/store/store_hours_test.dart`가 단일 출처다.
///
/// 위젯이 아니라 함수로 두는 이유는 화면을 띄우지 않고 확인하기 위해서다.

/// [StoreOpenState]를 같은 뜻의 표시 상태로 옮긴다.
///
/// `unknown`을 `closed`로 떨어뜨리지 않는다. 모르는 것을 닫혔다고 말하면 열려
/// 있는 매장을 돌려보낸다.
RoutexHoursState routexHoursState(StoreOpenState state) => switch (state) {
  StoreOpenState.open => RoutexHoursState.open,
  StoreOpenState.closed => RoutexHoursState.closed,
  StoreOpenState.unknown => RoutexHoursState.unknown,
};

/// 오늘부터 이레를 요일 줄로 바꾼다. 첫 줄이 오늘이다.
///
/// 라벨에 날짜를 섞지 않는다. 매주 반복되는 규칙에 `(8/11)`을 붙이면 읽는 사람이
/// 그 날짜에만 해당하는 시간으로 읽는다. 그날만 다른 이유는 [RoutexHoursDay.note]가
/// 말한다.
List<RoutexHoursDay> routexHoursDays(List<StoreHoursDay> week) => [
  for (final day in week)
    RoutexHoursDay(
      label: weekdayLabelOf(day.date),
      // 브레이크 타임이 있는 날은 구간을 **줄로 나눈다**. 한 줄에 이어 붙이면
      // `10:30 - 15:00 · 17:00 - 22:00`이 되는데, 가운뎃점이 시각 사이의 짧은
      // 줄표에 묻혀 네 시각이 한 덩어리로 읽힌다 — 언제 닫았다 다시 여는지가
      // 사라진다.
      value: day.intervals.isEmpty
          ? '휴무'
          : day.intervals
                .map((interval) => '${interval.open} - ${interval.close}')
                .join('\n'),
      note: day.note,
      closed: day.intervals.isEmpty,
    ),
];

/// `20:00 종료` / `내일 10:30 영업 시작`. 말할 것이 없으면 null.
String? routexHoursDetail(StoreHoursStatus status, DateTime today) {
  final next = status.nextChangeAt;
  if (status.state == StoreOpenState.unknown) return null;
  if (next == null) {
    // 영업 중인데 바뀌는 시각이 없으면 종일 영업이고, 닫혀 있는데 없으면 앞으로
    // 여는 날이 없다는 뜻이다. 둘은 전혀 다른 말이라 같은 문구를 쓰지 않는다.
    return status.state == StoreOpenState.open ? '24시간 영업' : null;
  }
  final suffix = status.state == StoreOpenState.open ? '종료' : '영업 시작';
  return '${_whenText(next, today)} $suffix';
}

/// 월~일 한 글자 라벨.
String weekdayLabelOf(DateTime date) =>
    const ['월', '화', '수', '목', '금', '토', '일'][(date.weekday - 1) % 7];

/// 전환 시각을 `20:00` / `내일 10:30` / `금 10:30`으로 적는다.
///
/// 날짜를 그대로 적지 않는 이유는 대부분의 전환이 오늘·내일 안에서 일어나기
/// 때문이다. `8월 12일 10:30`은 읽는 사람이 오늘 날짜를 떠올려야 뜻이 선다.
String _whenText(DateTime next, DateTime today) {
  final time =
      '${next.hour.toString().padLeft(2, '0')}:'
      '${next.minute.toString().padLeft(2, '0')}';
  final days = DateTime.utc(
    next.year,
    next.month,
    next.day,
  ).difference(today).inDays;
  return switch (days) {
    0 => time,
    1 => '내일 $time',
    _ => '${weekdayLabelOf(next)} $time',
  };
}
