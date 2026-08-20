/// 대중교통 표현 규칙 — 색·아이콘·시간·거리·요금 표기.
///
/// 같은 노선이 **세 군데에 동시에 보인다**(시트의 칩, 하단 요약 카드, 지도 위
/// 선). 셋이 어긋나면 사용자는 그것이 같은 구간인지 알 수 없다. 그래서 값이
/// 아니라 **규칙**을 못 박는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/route/transit_route.dart';
import 'package:navigation_client/widgets/transit_style.dart';

TransitLeg _leg(
  TransitMode mode, {
  String? colorHex,
  String? routeName,
  int seconds = 600,
}) => TransitLeg(
  mode: mode,
  sectionTimeSeconds: seconds,
  distanceMeters: 1000,
  points: const [LatLng(37.5, 127.0)],
  routeName: routeName,
  routeColorHex: colorHex,
);

/// 대비비(WCAG). 1(같은 색) ~ 21(검정 대 흰색).
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('수단 구분 — 문서가 말하는 목적', () {
    test('모든 수단이 서로 다른 색이다', () {
      // "어떤 노선인지 모를 때도 탈것과 도보가 한눈에 갈리는 게 목적"이다.
      // 두 수단이 같은 색이면 그 목적이 깨진다.
      final colors = TransitMode.values.map(transitModeColor).toList();
      expect(colors.toSet().length, TransitMode.values.length);
    });

    test('모든 수단이 서로 다른 아이콘이다', () {
      final icons = TransitMode.values.map(transitModeIcon).toList();
      expect(icons.toSet().length, TransitMode.values.length);
    });
  });

  group('구간 색', () {
    test('노선 고유색이 있으면 그것을 쓴다', () {
      // 사용자가 역 안내판에서 보는 색과 같아야 "그 파란 버스"가 맞는지 안다.
      final leg = _leg(TransitMode.bus, colorHex: '#FF6600');
      expect(transitLegColor(leg).toARGB32(), 0xFFFF6600);
      expect(transitLegColorHex(leg), '#FF6600');
    });

    test('노선 고유색이 없으면 수단 기본색으로 떨어진다', () {
      final leg = _leg(TransitMode.subway);
      expect(transitLegColor(leg), transitModeColor(TransitMode.subway));
    });

    test('색 문자열이 깨져 있어도 터지지 않고 기본색으로 떨어진다', () {
      // 백엔드가 주는 값이라 형식을 보장할 수 없다. 여기서 던지면 경로 목록이
      // 통째로 안 뜬다.
      final broken = _leg(TransitMode.bus, colorHex: '#XYZXYZ');
      expect(transitLegColor(broken), transitModeColor(TransitMode.bus));
    });

    test('hex 문자열과 Color가 같은 색을 가리킨다', () {
      // 지도는 문자열을, 시트는 Color를 쓴다. 둘이 갈라지면 같은 구간이
      // 화면마다 다른 색이 된다.
      for (final mode in TransitMode.values) {
        final leg = _leg(mode);
        final fromHex = int.parse(
          transitLegColorHex(leg).substring(1),
          radix: 16,
        );
        expect(
          transitLegColor(leg).toARGB32() & 0xFFFFFF,
          fromHex,
          reason: '$mode에서 두 표현이 어긋난다',
        );
      }
    });
  });

  group('노선 표준색 — 수단을 먼저 보고 가른다', () {
    test('지하철은 이름으로 찾는다', () {
      // 색상값의 출처·근거는 docs/client/transit-route-colors.md.
      expect(
        standardTransitColor(TransitMode.subway, '2호선')?.toARGB32(),
        0xFF00A84D,
      );
      expect(
        standardTransitColor(TransitMode.subway, '9호선')?.toARGB32(),
        0xFFBDB092,
      );
      expect(
        standardTransitColor(TransitMode.subway, '공항철도')?.toARGB32(),
        0xFF0090D2,
      );
    });

    test('버스는 이름이 아니라 종류로 찾는다', () {
      // 카카오는 `지선:5623외 6대`처럼 종류를 접두사로 접어 준다.
      expect(
        standardTransitColor(TransitMode.bus, '지선:5623외 6대')?.toARGB32(),
        0xFF53B332,
      );
      expect(
        standardTransitColor(TransitMode.bus, '간선:472')?.toARGB32(),
        0xFF0068B7,
      );
      expect(
        standardTransitColor(TransitMode.bus, '광역:9401')?.toARGB32(),
        0xFFE60012,
      );
    });

    test('버스 급행97과 지하철 9호선이 서로를 잡아먹지 않는다', () {
      // 이 작업에서 제일 틀리기 쉬운 자리다. 이름 표 하나로 합치면 급행97이
      // 9호선 금색이 되거나 그 반대가 된다.
      expect(standardTransitColor(TransitMode.bus, '급행:급행97'), isNull);
      expect(
        standardTransitColor(TransitMode.subway, '급행:9호선')?.toARGB32(),
        0xFFBDB092,
      );
    });

    test('지하철 이름에 종류 접두사가 붙어도 찾는다', () {
      // 카카오 실기기 캡처: `급행 9호선`, `일반 공항철도`.
      expect(
        standardTransitColor(TransitMode.subway, '일반:공항철도')?.toARGB32(),
        0xFF0090D2,
      );
    });

    test('제공자마다 다른 이름 표기를 같은 색으로 모은다', () {
      // TMAP은 `수도권9호선`, 카카오는 `9호선`, 안내판은 `서울 9호선`.
      const gold = 0xFFBDB092;
      for (final name in ['9호선', '수도권9호선', '서울 9호선', '서울9호선']) {
        expect(
          standardTransitColor(TransitMode.subway, name)?.toARGB32(),
          gold,
          reason: '$name이 다른 색이 된다',
        );
      }
      for (final name in ['경의중앙선', '경의·중앙선', '경의 중앙선']) {
        expect(
          standardTransitColor(TransitMode.subway, name)?.toARGB32(),
          0xFF77C4A3,
          reason: '$name이 다른 색이 된다',
        );
      }
    });

    test('인천 1·2호선은 서울 1·2호선과 다른 색이다', () {
      // `인천`을 안 보면 접두사만 떼다가 서울 호선색으로 빨려 들어간다.
      expect(
        standardTransitColor(TransitMode.subway, '인천1호선')?.toARGB32(),
        0xFF7CA8D5,
      );
      expect(
        standardTransitColor(TransitMode.subway, '인천 2호선')?.toARGB32(),
        0xFFED8B00,
      );
      expect(
        standardTransitColor(TransitMode.subway, '1호선')?.toARGB32(),
        isNot(0xFF7CA8D5),
      );
    });

    test('모르는 노선·모르는 종류는 null이다 — 억지로 배정하지 않는다', () {
      expect(standardTransitColor(TransitMode.subway, '13호선'), isNull);
      expect(standardTransitColor(TransitMode.subway, null), isNull);
      expect(standardTransitColor(TransitMode.bus, '5623'), isNull);
      expect(standardTransitColor(TransitMode.bus, null), isNull);
      expect(standardTransitColor(TransitMode.walk, '2호선'), isNull);
    });
  });

  group('구간 색 — 표준색이 끼어드는 자리', () {
    test('노선 고유색이 표준색보다 앞선다', () {
      // TMAP은 노선색을 직접 준다. 우리 표보다 제공자 값이 최신이다.
      final leg = _leg(
        TransitMode.subway,
        colorHex: '#FF6600',
        routeName: '수도권2호선',
      );
      expect(transitLegColor(leg).toARGB32(), 0xFFFF6600);
    });

    test('고유색이 없으면 표준색으로 간다 — 카카오 경로가 이 길이다', () {
      final leg = _leg(TransitMode.subway, routeName: '급행:9호선');
      expect(transitLegColor(leg).toARGB32(), 0xFFBDB092);
      expect(transitLegColorHex(leg), '#BDB092');
    });

    test('표준색도 없으면 수단 기본색으로 떨어진다', () {
      final leg = _leg(TransitMode.bus, routeName: '급행:급행97');
      expect(transitLegColor(leg), transitModeColor(TransitMode.bus));
    });

    test('지도와 카드가 같은 색이다 — 표준색 구간에서도', () {
      // 이 파일이 존재하는 이유. 갈라지면 같은 구간이 화면마다 다른 색이 된다.
      for (final name in ['2호선', '공항철도', '지선:5623외 6대', '순환:01A']) {
        for (final mode in [TransitMode.subway, TransitMode.bus]) {
          final leg = _leg(mode, routeName: name);
          final fromHex = int.parse(
            transitLegColorHex(leg).substring(1),
            radix: 16,
          );
          expect(
            transitLegColor(leg).toARGB32() & 0xFFFFFF,
            fromHex,
            reason: '$mode/$name에서 두 표현이 어긋난다',
          );
        }
      }
    });
  });

  group('접근성 — 밝은 표준색 위의 글자', () {
    // 색을 어둡게 고치지 않는다(지도 선이 안내판과 달라진다). 글자 쪽을 바꾼다.
    const bright = ['9호선', '3호선', '수인분당선', '경의중앙선'];

    test('꽉 찬 색 위 글자는 어떤 표준색에서도 4.5:1을 넘는다', () {
      for (final name in [...bright, '1호선', '신분당선', '우이신설선']) {
        final color = standardTransitColor(TransitMode.subway, name)!;
        expect(
          _contrast(color, transitInkOn(color)),
          greaterThanOrEqualTo(4.5),
          reason: '$name 막대 위 글자가 안 읽힌다',
        );
      }
      for (final type in ['간선', '지선', '순환', '광역']) {
        final color = standardTransitColor(TransitMode.bus, '$type:1')!;
        expect(
          _contrast(color, transitInkOn(color)),
          greaterThanOrEqualTo(4.5),
          reason: '$type 막대 위 글자가 안 읽힌다',
        );
      }
    });

    test('밝은 색에서는 흰색이 아니라 검정을 고른다', () {
      final gold = standardTransitColor(TransitMode.subway, '9호선')!;
      final navy = standardTransitColor(TransitMode.subway, '1호선')!;
      expect(transitInkOn(gold).toARGB32(), 0xFF000000);
      expect(transitInkOn(navy).toARGB32(), 0xFFFFFFFF);
    });

    test('옅은 틴트 배지의 글자색도 흰 배경 위에서 4.5:1을 넘는다', () {
      // RoutexBadgeAccent는 14% 틴트 위에 같은 색 글자를 얹는다. 원색 그대로면
      // 9호선 금색은 흰 배경 위 2:1도 안 된다.
      for (final name in bright) {
        final leg = _leg(TransitMode.subway, routeName: name);
        final accent = routexTransitLeg(leg).accent!;
        expect(
          _contrast(accent.ink, const Color(0xFFFFFFFF)),
          greaterThanOrEqualTo(4.5),
          reason: '$name 배지 글자가 안 읽힌다',
        );
      }
    });

    test('어두운 표준색의 배지 글자색은 원색 그대로다', () {
      // 이미 읽히는 색까지 건드리면 안내판 색과 멀어진다.
      final leg = _leg(TransitMode.subway, routeName: '신분당선');
      expect(routexTransitLeg(leg).accent!.ink.toARGB32(), 0xFFD4003B);
    });
  });

  group('소요 시간', () {
    test('0초라도 1분으로 올린다', () {
      // "0분"은 "안 걸린다"가 아니라 "계산이 안 됐다"로 읽힌다.
      expect(formatTransitDuration(0), '1분');
      expect(formatTransitDuration(1), '1분');
    });

    test('올림이다 — 61초는 2분이다', () {
      expect(formatTransitDuration(60), '1분');
      expect(formatTransitDuration(61), '2분');
      expect(formatTransitDuration(1440), '24분');
    });

    test('한 시간을 넘으면 시간과 분으로 나눈다', () {
      expect(formatTransitDuration(3600), '1시간');
      expect(formatTransitDuration(3660), '1시간 1분');
      expect(formatTransitDuration(4320), '1시간 12분');
    });

    test('하루를 넘겨도 하루에서 멈춘다', () {
      // 상한이 없으면 파싱 오류로 온 거대한 값이 그대로 화면에 찍힌다.
      expect(formatTransitDuration(60 * 60 * 24), '24시간');
      expect(formatTransitDuration(60 * 60 * 999), '24시간');
    });
  });

  // 거리 표기는 더 이상 대중교통 전용이 아니다. 검증 기준은
  // `test/domain/geo/distance_format_test.dart`가 단일 출처다.

  group('요금', () {
    test('천 단위마다 쉼표를 넣는다', () {
      expect(formatTransitFare(0), '0원');
      expect(formatTransitFare(500), '500원');
      expect(formatTransitFare(1500), '1,500원');
      expect(formatTransitFare(12345), '12,345원');
      expect(formatTransitFare(1234567), '1,234,567원');
    });

    test('세 자리 경계에서 쉼표가 앞에 붙지 않는다', () {
      // 1000이 ",1,000"이 되는 실수가 흔한 자리다.
      expect(formatTransitFare(1000), '1,000원');
      expect(formatTransitFare(100), '100원');
    });
  });
}
