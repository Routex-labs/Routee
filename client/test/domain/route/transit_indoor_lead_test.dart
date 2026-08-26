/// 대중교통 후보 앞에 붙는 **실내 구간**.
///
/// 실기기에서 3층에 선 채로 "최적 1시간 2분"을 봤다 — 그건 건물 문에서 출발하는
/// 시간이었다. 근거는 `docs/client/indoor-leg-in-outdoor-journey.md`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/route/transit_indoor_lead.dart';
import 'package:navigation_client/models/route/transit_route.dart';

const _boardAt = LatLng(37.5215, 126.9243);
const _alightAt = LatLng(37.5045, 127.0251);

TransitItinerary _itinerary() => const TransitItinerary(
  totalTimeSeconds: 3720,
  totalWalkTimeSeconds: 600,
  totalDistanceMeters: 11948,
  transferCount: 1,
  fare: 2350,
  legs: [
    TransitLeg(
      mode: TransitMode.subway,
      sectionTimeSeconds: 915,
      distanceMeters: 10100,
      points: [_boardAt, _alightAt],
      routeName: '급행:9호선',
      startName: '여의도',
      endName: '신논현',
    ),
  ],
);

void main() {
  test('맨 앞에 도보 구간이 붙고 총계가 그만큼 오른다', () {
    final filled = prependIndoorWalkLeg(
      _itinerary(),
      seconds: 120,
      meters: 116,
      exitName: '남서쪽 출구',
    );

    expect(filled.legs.first.mode, TransitMode.walk);
    expect(filled.legs.first.sectionTimeSeconds, 120);
    expect(filled.legs.first.distanceMeters, 116);
    expect(filled.legs.first.endName, '남서쪽 출구');
    expect(filled.legs.length, 2, reason: '원본 구간은 그대로 뒤에 남는다');

    // **카카오 총계에는 실내 구간이 없다** — 우리 복도도 엘리베이터도 모른다.
    // 그래서 여기서는 더한다(야외 앞뒤 도보를 채우는 쪽과 반대다).
    expect(filled.totalTimeSeconds, 3720 + 120);
    expect(filled.totalWalkTimeSeconds, 600 + 120);
    expect(filled.totalDistanceMeters, 11948 + 116);
  });

  test('요금·환승 횟수는 그대로다', () {
    final filled = prependIndoorWalkLeg(
      _itinerary(),
      seconds: 120,
      meters: 116,
      exitName: '남서쪽 출구',
    );
    expect(filled.fare, 2350);
    expect(filled.transferCount, 1);
  });

  test('좌표는 담지 않는다 — 실내 선은 실내 레이어가 층별로 그린다', () {
    final filled = prependIndoorWalkLeg(
      _itinerary(),
      seconds: 120,
      meters: 116,
      exitName: '남서쪽 출구',
    );
    expect(filled.legs.first.points, isEmpty);
    // 카메라를 경로 전체에 맞출 때 쓰는 값이 늘어나면 안 된다.
    expect(filled.points, _itinerary().points);
  });

  test('붙일 시간이 없으면 원본 그대로다', () {
    final original = _itinerary();
    final filled = prependIndoorWalkLeg(
      original,
      seconds: 0,
      meters: 0,
      exitName: '남서쪽 출구',
    );
    expect(identical(filled, original), isTrue);
  });

  test('떼었다 다시 붙이면 숫자가 제자리로 온다', () {
    // 고른 뒤 바깥 도보를 문 기준으로 다시 그리려면 실내 구간을 잠깐 떼어야
    // 한다(`trimLeadingWalkLeg`가 그것을 대신 자르지 않도록). 그 왕복에서
    // 총계가 틀어지면 목록과 요약 카드가 서로 다른 시간을 말한다.
    final original = _itinerary();
    final filled = prependIndoorWalkLeg(
      original,
      seconds: 120,
      meters: 116,
      exitName: '남서쪽 출구',
    );

    final (lead: lead, rest: rest) = takeIndoorWalkLead(filled);
    expect(lead?.seconds, 120);
    expect(lead?.meters, 116);
    expect(lead?.exitName, '남서쪽 출구');
    expect(rest.totalTimeSeconds, original.totalTimeSeconds);
    expect(rest.totalDistanceMeters, original.totalDistanceMeters);
    expect(rest.legs.first.mode, TransitMode.subway, reason: '카카오의 첫 구간이 다시 앞이다');

    final restored = prependIndoorWalkLeg(
      rest,
      seconds: lead!.seconds,
      meters: lead.meters,
      exitName: lead.exitName,
    );
    expect(restored.totalTimeSeconds, filled.totalTimeSeconds);
    expect(restored.totalWalkTimeSeconds, filled.totalWalkTimeSeconds);
    expect(restored.totalDistanceMeters, filled.totalDistanceMeters);
  });

  test('좌표가 있는 도보는 우리 실내 구간이 아니다', () {
    // 카카오·TMAP이 준 도보와 `fillTransitWalkLegs`가 채운 도보는 전부 좌표를
    // 갖는다. 그것을 떼어 내면 정류장까지 걸어가는 구간이 통째로 사라진다.
    final withOutdoorWalk = TransitItinerary(
      totalTimeSeconds: 3720,
      totalWalkTimeSeconds: 600,
      totalDistanceMeters: 11948,
      transferCount: 1,
      fare: 2350,
      legs: [
        const TransitLeg(
          mode: TransitMode.walk,
          sectionTimeSeconds: 300,
          distanceMeters: 250,
          points: [LatLng(37.5259, 126.9280), _boardAt],
        ),
        ..._itinerary().legs,
      ],
    );
    final taken = takeIndoorWalkLead(withOutdoorWalk);
    expect(taken.lead, isNull);
    expect(identical(taken.rest, withOutdoorWalk), isTrue);
  });
}
