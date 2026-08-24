import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../../../../../domain/store/store_hours.dart';
import '../../../../../models/place/place_detail.dart';
import 'place_detail_hours_view.dart';

/// 요일별 영업시간 섹션.
///
/// 이 위젯이 가진 것은 펼침 상태 하나다. **판정은 `domain/store/store_hours.dart`,
/// 표시는 `RoutexHours`가 맡는다.** 값을 줄과 문장으로 옮기는 규칙은
/// `place_detail_hours_view.dart`에 순수 함수로 있어 화면 없이 확인할 수 있다.
class PlaceHoursSection extends StatefulWidget {
  const PlaceHoursSection({super.key, required this.hours, required this.now});

  final HoursSection hours;

  /// 판정 기준 시각. 위젯이 [DateTime.now]를 직접 부르지 않고 받는 이유는
  /// 도메인 함수와 같다 — 시각에 의존하는 화면을 테스트로 고정할 수 있어야 한다.
  final DateTime now;

  @override
  State<PlaceHoursSection> createState() => _PlaceHoursSectionState();
}

class _PlaceHoursSectionState extends State<PlaceHoursSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final week = storeHoursWeek(widget.hours, widget.now);
    // 요일이 하나도 없으면 그릴 것이 없다. 빈 섹션 자리를 남기면 위아래 구분선만
    // 붙어 "정보를 못 받아 온 칸"처럼 읽힌다.
    if (week.isEmpty) return const SizedBox.shrink();

    final status = computeStoreHoursStatus(widget.hours, widget.now);

    return RoutexHours(
      state: routexHoursState(status.state),
      days: routexHoursDays(week),
      detail: routexHoursDetail(status, week.first.date),
      // 확인일 줄은 그리지 않는다. 임계값을 넘기면 판정(`영업 중`)은 여전히
      // 거두지만, 그 이유를 날짜로 적어 두면 멀쩡한 매장에도 경고처럼 읽힌다.
      expanded: _expanded,
      onExpanded: (value) => setState(() => _expanded = value),
    );
  }
}
