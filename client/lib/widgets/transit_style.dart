import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../models/route/transit_route.dart';

/// 대중교통 화면(경로 목록 시트·요약 카드·지도 경로선)이 공유하는 표현 규칙.
///
/// 한곳에 모으는 이유는 **같은 노선이 세 군데에 동시에 보이기 때문**이다.
/// 시트의 칩, 하단 요약 카드, 지도 위 선이 서로 다른 색이면 사용자는 그것이
/// 같은 구간인지 알 수 없다.

/// 수단별 기본색. 노선 고유색이 없을 때만 쓴다.
///
/// 서울 기준 관습색을 따른다 — 버스는 파랑(간선), 지하철은 남색 계열. 어떤
/// 노선인지 모를 때도 "탈것"과 "도보"가 한눈에 갈리는 게 목적이다.
Color transitModeColor(TransitMode mode) => switch (mode) {
  TransitMode.walk => const Color(0xFF7A8794),
  TransitMode.bus => const Color(0xFF0068B7),
  TransitMode.subway => const Color(0xFF3A5DAE),
  TransitMode.train => const Color(0xFF4B6A2E),
  TransitMode.expressBus => const Color(0xFF8A5A2B),
  TransitMode.airplane => const Color(0xFF2E7D8F),
  TransitMode.ferry => const Color(0xFF1B7A6B),
  TransitMode.unknown => const Color(0xFF5F6B76),
};

/// 노선 이름·종류로 찾은 표준색. **못 찾으면 null** — 표에 없는 노선에 비슷한
/// 색을 억지로 배정하면 화면 색이 안내판과 달라진다.
///
/// [routeName]은 `TransitLeg.routeName` 그대로 넣는다(`간선:472`, `급행:9호선`,
/// `수도권4호선`). `:` 앞은 종류, 뒤는 번호다. **수단을 먼저 가른다** — 철도는
/// 이름으로, 버스는 종류로만 찾는다(버스 `급행97`과 지하철 `9호선` 충돌).
///
/// 색상값의 출처와 못 덮은 노선은 `docs/client/transit-route-colors.md`,
/// 이름 매칭의 검증 기준은 `test/widgets/transit_style_test.dart`가 단일 출처다.
Color? standardTransitColor(TransitMode mode, String? routeName) {
  if (routeName == null) return null;
  final colon = routeName.indexOf(':');
  final type = colon < 0 ? null : routeName.substring(0, colon).trim();
  final name = colon < 0 ? routeName : routeName.substring(colon + 1);
  final rgb = switch (mode) {
    TransitMode.bus => _busTypeColors[type],
    TransitMode.subway || TransitMode.train => _railColors[_railKey(name)],
    _ => null,
  };
  return rgb == null ? null : Color(rgb);
}

/// 이 구간을 그릴 색. 제공자가 준 노선 고유색 → 표준색 → 수단 기본색 순이다.
/// 사용자가 역 안내판에서 보는 색과 같아야 "그 파란 버스"가 맞는지 안다.
Color transitLegColor(TransitLeg leg) {
  final hex = leg.routeColorHex;
  final value = hex == null ? null : int.tryParse(hex.substring(1), radix: 16);
  if (value != null) return Color(0xFF000000 | value);
  return standardTransitColor(leg.mode, leg.routeName) ??
      transitModeColor(leg.mode);
}

/// 지도 소스에 실어 보낼 `#RRGGBB` 문자열. MapLibre 표현식이 문자열만 받는다.
/// [transitLegColor]에서 뽑아 쓰므로 지도와 카드가 갈라질 수 없다.
String transitLegColorHex(TransitLeg leg) {
  final rgb = transitLegColor(leg).toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// [background]를 꽉 채운 위에 올릴 글자색 — 흰색 아니면 검정.
///
/// 경계 0.18은 WCAG 대비식에서 나온다(근거는 위 문서). 중간톤 회색을 쓰면 흰색도
/// 검정도 4.5:1을 못 넘는 휘도 구간이 생기므로 두 극단만 쓴다.
Color transitInkOn(Color background) => background.computeLuminance() > 0.18
    ? const Color(0xFF000000)
    : const Color(0xFFFFFFFF);

/// 옅은 틴트 위에 같은 색으로 얹을 글자색. 색상(hue)은 두고 밝기만 내려서 흰
/// 배경 대비 4.5:1을 확보한다 — 9호선 금색은 원색 그대로면 2:1도 안 된다.
Color _tintInk(Color color) {
  var hsl = HSLColor.fromColor(color);
  while (hsl.toColor().computeLuminance() > 0.18 && hsl.lightness > 0.05) {
    hsl = hsl.withLightness(hsl.lightness - 0.05);
  }
  return hsl.toColor();
}

/// 서울 시내버스 유형색. 지선·마을·맞춤은 출처에서도 같은 초록이다.
const _busTypeColors = <String, int>{
  '간선': 0xFF0068B7,
  '지선': 0xFF53B332,
  '마을': 0xFF53B332,
  '맞춤': 0xFF53B332,
  '순환': 0xFFF2B70A,
  '광역': 0xFFE60012,
  '심야': 0xFF3D5BAB,
};

/// 수도권 도시철도 노선색. 키는 [_railKey]로 정규화한 이름이다.
const _railColors = <String, int>{
  '1호선': 0xFF0052A4,
  '2호선': 0xFF00A84D,
  '3호선': 0xFFEF7C1C,
  '4호선': 0xFF00A5DE,
  '5호선': 0xFF996CAC,
  '6호선': 0xFFCD7C2F,
  '7호선': 0xFF747F00,
  '8호선': 0xFFE6186C,
  '9호선': 0xFFBDB092,
  '인천1호선': 0xFF7CA8D5,
  '인천2호선': 0xFFED8B00,
  '공항철도': 0xFF0090D2,
  '인천공항철도': 0xFF0090D2,
  '공항철도1호선': 0xFF0090D2,
  '신분당선': 0xFFD4003B,
  '경의중앙선': 0xFF77C4A3,
  '수인분당선': 0xFFF5A200,
  '경춘선': 0xFF0C8E72,
  '우이신설선': 0xFFB0CE18,
  '김포골드라인': 0xFFA17800,
  '서해선': 0xFF81A914,
  '신림선': 0xFF6789CA,
  '경강선': 0xFF003DA5,
  '의정부경전철': 0xFFFDA600,
  '용인에버라인': 0xFF509F22,
  '에버라인': 0xFF509F22,
  'GTXA': 0xFF9A6292,
};

final _railTail = RegExp(r'외\s*\d+대$');
final _railNoise = RegExp(r'[\s·・.\-_()]');
final _railPrefix = RegExp(r'^(수도권|서울)(?=.)');

/// 제공자마다 다른 표기(`수도권9호선`·`서울 9호선`·`경의·중앙선`)를 한 키로 모은다.
String _railKey(String name) => name
    .trim()
    .replaceFirst(_railTail, '')
    .replaceAll(_railNoise, '')
    .replaceFirst(_railPrefix, '')
    .toUpperCase();

IconData transitModeIcon(TransitMode mode) => switch (mode) {
  TransitMode.walk => Icons.directions_walk_rounded,
  TransitMode.bus => Icons.directions_bus_rounded,
  TransitMode.subway => Icons.subway_rounded,
  TransitMode.train => Icons.train_rounded,
  TransitMode.expressBus => Icons.airport_shuttle_rounded,
  TransitMode.airplane => Icons.flight_rounded,
  TransitMode.ferry => Icons.directions_boat_rounded,
  TransitMode.unknown => Icons.alt_route_rounded,
};

/// 초 → "1시간 12분" / "24분".
///
/// 0분으로 내려가지 않게 최소 1분으로 올린다. "0분"은 사용자에게 "안 걸린다"가
/// 아니라 "계산이 안 됐다"로 읽힌다.
String formatTransitDuration(int seconds) {
  final minutes = (seconds / 60).ceil().clamp(1, 24 * 60);
  if (minutes < 60) return '$minutes분';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours시간' : '$hours시간 $rest분';
}

/// 요금 → "1,500원". 천 단위 구분자를 직접 넣는다(intl 의존 없이).
String formatTransitFare(int fare) {
  final digits = fare.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '$buffer원';
}

/// `오후 3:25`. intl 의존 없이 적는다.
String formatTransitClockTime(DateTime time) {
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  return '${time.hour < 12 ? '오전' : '오후'} $hour:'
      '${time.minute.toString().padLeft(2, '0')}';
}

/// [departure]에 총 소요를 더한 도착 예정 시각. **총 소요가 0이면 null**이다.
///
/// 모르는 것을 지어내지 않는다 — 지금 시각을 도착이라고 적으면 사용자는 그것을
/// "다 왔다"로 읽는다.
DateTime? transitArrivalTime(DateTime departure, TransitItinerary itinerary) =>
    itinerary.totalTimeSeconds <= 0
    ? null
    : departure.add(Duration(seconds: itinerary.totalTimeSeconds));

/// 앱의 대중교통 모델을 Runtime Kit 구간 표현으로 바꾼다.
RoutexTransitLeg routexTransitLeg(TransitLeg leg) {
  final color = transitLegColor(leg);
  return RoutexTransitLeg(
    label: leg.mode.isWalk
        ? '도보 ${formatTransitDuration(leg.sectionTimeSeconds)}'
        : leg.shortLabel,
    icon: transitModeIcon(leg.mode),
    accent: leg.mode.isWalk
        ? null
        : RoutexBadgeAccent(
            surface: color.withValues(alpha: 0.14),
            ink: _tintInk(color),
          ),
  );
}
