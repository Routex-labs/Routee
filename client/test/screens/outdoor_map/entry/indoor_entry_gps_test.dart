import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/screens/outdoor_map/entry/indoor_entry_gps.dart';

/// 판정 자체는 실기기를 들고 건물을 드나들어야 확인할 수 있지만, **어떤 숫자가
/// 어떤 결론을 만드는지**는 여기서 끝난다. 실기기 실험은 "이 좌표가 정말 그
/// 좌표인가"만 확인하면 된다.
///
/// 좌표는 중심 [_center]에서 동서남북 100 m씩 뻗은 정사각형이다. 실제 데모
/// 건물(폭 약 180 m)과 비슷한 규모라 임계값(안쪽 5 m·바깥 8 m)이 건물 크기에
/// 묻히지 않는다.
const _center = LatLng(37.525862, 126.928540);
const _halfWidthMeters = 100.0;
const _metersPerDegreeLat = 111320.0;

/// [_center]에서 북쪽으로 [north] m, 동쪽으로 [east] m 떨어진 좌표.
LatLng _offset({double north = 0, double east = 0}) {
  final mPerDegLng =
      _metersPerDegreeLat * math.cos(_center.latitude * math.pi / 180);
  return LatLng(
    _center.latitude + north / _metersPerDegreeLat,
    _center.longitude + east / mPerDegLng,
  );
}

List<LatLng> _square() => [
  _offset(north: _halfWidthMeters, east: -_halfWidthMeters),
  _offset(north: _halfWidthMeters, east: _halfWidthMeters),
  _offset(north: -_halfWidthMeters, east: _halfWidthMeters),
  _offset(north: -_halfWidthMeters, east: -_halfWidthMeters),
];

GpsBuildingJudgement _judge({
  required LatLng point,
  required double accuracy,
  List<LatLng>? footprint,
}) => judgeBuildingFromGps(
  fix: GpsFix(point: point, accuracyMeters: accuracy),
  footprint: footprint ?? _square(),
);

void main() {
  group('judgeBuildingFromGps — 결론', () {
    test('외곽선을 모르면 판정하지 않는다', () {
      final judgement = _judge(
        point: _center,
        accuracy: 5,
        footprint: const [],
      );
      expect(judgement.verdict, GpsBuildingVerdict.unclear);
      expect(judgement.hasFootprint, isFalse);
    });

    test('외곽선이 폴리곤이 아니면 판정하지 않는다', () {
      // 점이 둘뿐이면 "안"이라는 개념 자체가 없다. 빈 목록만 막으면 이 경우가
      // 면적 0인 폴리곤으로 계산돼 건물 한가운데가 "바깥"으로 읽힌다.
      final judgement = _judge(
        point: _center,
        accuracy: 5,
        footprint: [_offset(north: -_halfWidthMeters), _offset(north: _halfWidthMeters)],
      );
      expect(judgement.verdict, GpsBuildingVerdict.unclear);
      expect(judgement.hasFootprint, isFalse);
    });

    test('오차가 아무리 커도 안쪽 문턱을 넘었으면 진입이다', () {
      // 실내에서 신호가 무너진 구간이 정확히 오차가 큰 구간이다. 여기에 오차
      // 문턱을 두면 이미 건물 안인 사용자가 한참 뒤에야 들어간다.
      final judgement = _judge(point: _center, accuracy: 120);
      expect(judgement.verdict, GpsBuildingVerdict.inside);
    });

    test('좌표가 안쪽 문턱을 넘으면 진입이다', () {
      final judgement = _judge(
        point: _offset(north: _halfWidthMeters - 6),
        accuracy: 12,
      );
      expect(judgement.verdict, GpsBuildingVerdict.inside);
    });

    test('안쪽 문턱을 못 넘으면 아직 진입이 아니다', () {
      final judgement = _judge(
        point: _offset(north: _halfWidthMeters - 3),
        accuracy: 5,
      );
      expect(judgement.verdict, GpsBuildingVerdict.unclear);
    });

    test('외곽선 바로 바깥은 진입이 아니다', () {
      // 정합을 배경 지도 건물 꼭지점으로 다시 잡은 뒤 부풀리기가 0이 됐다
      // ([footprintOutwardToleranceMeters]). 6 m를 그대로 뒀다면 이 좌표가
      // "안쪽 6 m"로 읽혀 벽 밖에 선 사람에게 도면이 떴다.
      final judgement = _judge(
        point: _offset(north: _halfWidthMeters + 1),
        accuracy: 5,
      );
      expect(judgement.verdict, GpsBuildingVerdict.unclear);
    });

    test('벽 바깥 완충 구간에서는 이탈로 보지 않는다', () {
      final judgement = _judge(
        point: _offset(
          north: _halfWidthMeters + outdoorExitMarginMeters - 3,
        ),
        accuracy: 5,
      );
      expect(judgement.verdict, GpsBuildingVerdict.unclear);
    });

    test('바깥 여유를 넘으면 이탈이다', () {
      final judgement = _judge(
        point: _offset(north: _halfWidthMeters + 30),
        accuracy: 5,
      );
      expect(judgement.verdict, GpsBuildingVerdict.outside);
    });
  });

  group('judgeBuildingFromGps — 히스테리시스', () {
    test('안팎 임계값 사이에 완충 구간이 있다', () {
      // 이 구간이 없으면 벽에 붙어 선 사람의 좌표가 흔들릴 때마다 진입과 이탈이
      // 번갈아 성립해 화면이 실내와 야외를 오간다.
      expect(outdoorExitMarginMeters, greaterThan(indoorEnterInsetMeters));
      // 거리는 전부 **부풀린** 외곽선 기준이라, 실제 벽에서 잰 값으로 옮기려면
      // tolerance만큼 바깥으로 밀어야 한다.
      for (var m = -outdoorExitMarginMeters + 1; m < indoorEnterInsetMeters; m += 1) {
        // m > 0이면 부풀린 선 안쪽, m < 0이면 바깥쪽이다.
        final judgement = _judge(
          point: _offset(
            north: _halfWidthMeters + footprintOutwardToleranceMeters - m,
          ),
          accuracy: 5,
        );
        expect(
          judgement.verdict,
          GpsBuildingVerdict.unclear,
          reason: '벽에서 ${m}m 지점은 완충 구간이어야 한다',
        );
      }
    });

    test('나가는 쪽이 더 엄격하다', () {
      // 잘못 들어가는 비용(밖인데 도면이 뜸)보다 잘못 나오는 비용(안인데 PDR
      // 추적이 끊김)이 크다.
      //
      // **실제 벽에서 잰 거리로 비교한다.** 상수끼리 비교하면 부풀리기
      // (tolerance)가 빠져 두 값의 뜻이 달라진다 — 진입은 부풀린 만큼
      // 앞당겨지고 이탈은 그만큼 미뤄지므로, 같은 6 m가 한쪽은 빼고 한쪽은
      // 더한다.
      const enterFromWall =
          indoorEnterInsetMeters - footprintOutwardToleranceMeters;
      const exitFromWall =
          outdoorExitMarginMeters + footprintOutwardToleranceMeters;
      expect(exitFromWall, greaterThan(enterFromWall));
    });

    test('이탈은 오차가 큰 좌표도 근거로 쓴다', () {
      // 건물에서 막 나온 순간이 정확히 오차가 큰 구간이다. 그 구간을 버리면
      // 전환이 한참 늦는다.
      final judgement = _judge(
        point: _offset(north: _halfWidthMeters + 30),
        accuracy: outdoorExitAccuracyMeters - 5,
      );
      expect(judgement.verdict, GpsBuildingVerdict.outside);
    });

    test('이탈만 오차 문턱을 갖는다', () {
      final judgement = _judge(
        point: _offset(north: _halfWidthMeters + 30),
        accuracy: outdoorExitAccuracyMeters + 5,
      );
      expect(judgement.verdict, GpsBuildingVerdict.unclear);
    });
  });

  group('shouldRearmGpsEntry', () {
    test('바깥 문턱을 넘으면 오차가 아무리 나빠도 빗장을 푼다', () {
      // 이 케이스가 이 함수의 존재 이유다. 유리 외벽 건물 앞은 오차가 30 m
      // 아래로 안 내려오는 일이 흔한데, 이탈 문턱을 그대로 쓰면 걸어 나감이
      // 끈 빗장을 아무도 못 풀어 자동 진입이 영구히 죽는다.
      final judgement = _judge(
        point: _offset(north: _halfWidthMeters + 30),
        accuracy: outdoorExitAccuracyMeters + 20,
      );
      expect(judgement.verdict, GpsBuildingVerdict.unclear);
      expect(shouldRearmGpsEntry(judgement), isTrue);
    });

    test('이탈 판정은 여전히 오차를 본다', () {
      // 재무장을 느슨하게 한 것이 이탈까지 느슨하게 만들면 안 된다 — 실내에서
      // 튄 좌표 한 건이 건물 안에 있는 사용자의 도면과 위치를 지운다.
      final judgement = _judge(
        point: _offset(north: _halfWidthMeters + 30),
        accuracy: outdoorExitAccuracyMeters + 20,
      );
      expect(judgement.verdict, isNot(GpsBuildingVerdict.outside));
    });

    test('문 앞 완충 구간에서는 빗장을 풀지 않는다', () {
      // 여기서 풀면 걸어 나간 직후의 옛 좌표가 사용자를 도로 끌고 들어간다.
      final judgement = _judge(
        point: _offset(north: _halfWidthMeters + outdoorExitMarginMeters - 3),
        accuracy: 5,
      );
      expect(shouldRearmGpsEntry(judgement), isFalse);
    });

    test('건물 안 좌표로는 빗장을 풀지 않는다', () {
      final judgement = _judge(point: _center, accuracy: 5);
      expect(shouldRearmGpsEntry(judgement), isFalse);
    });

    test('외곽선을 모르면 빗장을 풀지 않는다', () {
      // 거리가 0이라 "바깥 0 m"로 읽히는데, 그건 밖이라는 근거가 아니라
      // 잴 외곽선이 없다는 뜻이다.
      final judgement = _judge(
        point: _center,
        accuracy: 5,
        footprint: const [],
      );
      expect(judgement.metersOutside, 0);
      expect(shouldRearmGpsEntry(judgement), isFalse);
    });

    test('이탈 판정이면 재무장도 반드시 성립한다', () {
      // 두 조건이 어긋나면 "나갔다고 판정했는데 자동 진입은 여전히 꺼진" 상태가
      // 생긴다. 재무장을 switch 밖으로 뺀 근거가 이 포함 관계다.
      final judgement = _judge(
        point: _offset(north: _halfWidthMeters + 30),
        accuracy: 5,
      );
      expect(judgement.verdict, GpsBuildingVerdict.outside);
      expect(shouldRearmGpsEntry(judgement), isTrue);
    });
  });

  group('judgeBuildingFromGps — 근거', () {
    test('결론을 못 낸 좌표도 거리를 그대로 남긴다', () {
      // 이 케이스가 이 기능의 존재 이유다. 거리를 안 재고 0으로 두면 "벽 근처
      // 완충 구간이었다"가 "건물 밖이었다"와 같은 화면으로 보인다.
      final judgement = _judge(
        point: _offset(north: _halfWidthMeters - 3),
        accuracy: 34,
      );
      expect(judgement.verdict, GpsBuildingVerdict.unclear);
      // 판정이 실제로 쓴 값을 그대로 돌려준다 — 벽 안쪽 3m는 부풀린 선
      // 기준으로 3m + tolerance다.
      expect(
        judgement.metersInside,
        closeTo(3 + footprintOutwardToleranceMeters, 0.5),
      );
      expect(judgement.metersOutside, 0);
    });

    test('밖에 있으면 안쪽 거리가 0이다', () {
      final judgement = _judge(
        point: _offset(north: _halfWidthMeters + 30),
        accuracy: 5,
      );
      expect(judgement.metersInside, 0);
      expect(
        judgement.metersOutside,
        closeTo(30 - footprintOutwardToleranceMeters, 0.5),
      );
    });

    test('오차는 판정과 무관하게 그대로 실린다', () {
      final judgement = _judge(point: _center, accuracy: 7.4);
      expect(judgement.accuracyMeters, 7.4);
    });
  });

  group('describeGpsBuildingJudgement', () {
    test('안쪽이면 안쪽 거리로 읽힌다', () {
      final judgement = _judge(
        point: _offset(north: _halfWidthMeters - 3),
        accuracy: 5,
      );
      expect(
        describeGpsBuildingJudgement(judgement, armed: true),
        '정확도 5m · 안쪽 3.0m · unclear · 무장O',
      );
    });

    test('바깥이면 바깥 거리로 읽힌다', () {
      final judgement = _judge(
        point: _offset(north: _halfWidthMeters + 30),
        accuracy: 5,
      );
      expect(
        describeGpsBuildingJudgement(judgement, armed: true),
        '정확도 5m · 바깥 30.0m · outside · 무장O',
      );
    });

    test('외곽선을 모르면 거리 대신 그 사실을 띄운다', () {
      final judgement = _judge(
        point: _center,
        accuracy: 12,
        footprint: const [],
      );
      expect(
        describeGpsBuildingJudgement(judgement, armed: true),
        '정확도 12m · 외곽선 없음 · unclear · 무장O',
      );
    });

    test('좌표 간격을 주면 뒤에 붙는다', () {
      // "판정 규칙이 틀렸다"와 "좌표가 늦게 온다"를 화면에서 가르는 값이다.
      final judgement = _judge(point: _center, accuracy: 5);
      expect(
        describeGpsBuildingJudgement(
          judgement,
          armed: true,
          sinceLastFix: const Duration(milliseconds: 5000),
        ),
        endsWith('· +5.0s'),
      );
    });

    test('첫 좌표는 비교 대상이 없어 간격을 붙이지 않는다', () {
      final judgement = _judge(point: _center, accuracy: 5);
      expect(
        describeGpsBuildingJudgement(judgement, armed: true),
        isNot(contains('+')),
      );
    });

    test('자동 진입이 꺼져 있으면 무장X로 보인다', () {
      // "안이라고 판정했는데 왜 안 들어가지"의 흔한 원인이라 한 줄에 함께 둔다.
      final judgement = _judge(
        point: _offset(north: _halfWidthMeters - 6),
        accuracy: 12,
      );
      expect(
        describeGpsBuildingJudgement(judgement, armed: false),
        '정확도 12m · 안쪽 6.0m · inside · 무장X',
      );
    });

    test('좌표 출처와 재시작 횟수를 뒤에 붙인다', () {
      // 간격이 벌어졌을 때 "스트림이 느리다"와 "스트림이 죽고 일회성 조회만
      // 남았다"는 완전히 다른 문제인데, 이 두 값 없이는 화면에서 구분되지 않는다.
      final judgement = _judge(point: _center, accuracy: 5);
      expect(
        describeGpsBuildingJudgement(
          judgement,
          armed: true,
          sinceLastFix: const Duration(seconds: 36),
          fromStream: false,
          streamRestarts: 4,
        ),
        endsWith('· +36.0s · 직접 · 재시작4'),
      );
    });

    test('스트림에서 온 좌표는 스트림으로 보인다', () {
      final judgement = _judge(point: _center, accuracy: 5);
      expect(
        describeGpsBuildingJudgement(
          judgement,
          armed: true,
          fromStream: true,
          streamRestarts: 1,
        ),
        endsWith('· 스트림 · 재시작1'),
      );
    });

    test('진단값을 안 주면 예전 문구 그대로다', () {
      // 이 함수는 디버그 모드에서만 쓰이지만, 인자를 안 넘긴 호출부가 남아도
      // 문구가 깨지지 않아야 한다.
      final judgement = _judge(point: _center, accuracy: 5);
      final line = describeGpsBuildingJudgement(judgement, armed: true);
      expect(line, isNot(contains('재시작')));
      expect(line, isNot(contains('스트림')));
      expect(line, isNot(contains('직접')));
    });
  });
}
