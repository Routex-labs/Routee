import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/route/transit_walk_fill.dart';
import 'package:navigation_client/models/route/directions_route.dart';
import 'package:navigation_client/models/route/transit_route.dart';

const _origin = LatLng(37.5259, 126.9280); // 더현대 서울
const _destination = LatLng(37.4979, 127.0276); // 강남역

const _boardAt = LatLng(37.5215, 126.9243); // 여의도역
const _alightAt = LatLng(37.5045, 127.0251); // 신논현역

/// 카카오가 주는 모양 — 이미 지하철에 타 있는 상태로 시작해 내리는 순간 끝난다.
TransitItinerary _kakaoShaped({
  LatLng boardAt = _boardAt,
  LatLng alightAt = _alightAt,
  bool noPoints = false,
}) {
  return TransitItinerary(
    totalTimeSeconds: 2022,
    totalWalkTimeSeconds: 1004,
    totalDistanceMeters: 11948,
    transferCount: 0,
    fare: 2350,
    legs: [
      TransitLeg(
        mode: TransitMode.subway,
        sectionTimeSeconds: 915,
        distanceMeters: 10100,
        points: noPoints ? const [] : [boardAt, alightAt],
        routeName: '급행:9호선',
        startName: '여의도',
        endName: '신논현',
      ),
    ],
  );
}

void main() {
  test('앞뒤에 도보 구간을 붙여 출발지·목적지까지 선을 잇는다', () {
    final filled = fillTransitWalkLegs(
      _kakaoShaped(),
      origin: _origin,
      destination: _destination,
      head: const DirectionsRoute(
        points: [_origin, LatLng(37.5240, 126.9260), _boardAt],
        distanceMeters: 620,
        durationSeconds: 540,
      ),
      tail: const DirectionsRoute(
        points: [_alightAt, LatLng(37.5010, 127.0260), _destination],
        distanceMeters: 780,
        durationSeconds: 660,
      ),
    );

    expect(filled.legs, hasLength(3));
    expect(filled.legs.first.mode, TransitMode.walk);
    expect(filled.legs.last.mode, TransitMode.walk);

    // 선이 사용자가 서 있는 자리에서 시작해 목적지에서 끝나야 한다.
    expect(filled.points.first, _origin);
    expect(filled.points.last, _destination);

    // 붙인 도보는 TMAP이 준 실제 보도 모양이다(직선 두 점이 아니다).
    expect(filled.legs.first.points, hasLength(3));
    expect(filled.legs.first.sectionTimeSeconds, 540);
    expect(filled.legs.first.endName, '여의도');
    expect(filled.legs.last.startName, '신논현');
  });

  test('총 시간·거리·요금은 그대로 둔다 — 카카오 총계에 도보가 이미 들어 있다', () {
    final original = _kakaoShaped();
    final filled = fillTransitWalkLegs(
      original,
      origin: _origin,
      destination: _destination,
      head: const DirectionsRoute(
        points: [_origin, _boardAt],
        distanceMeters: 620,
        durationSeconds: 540,
      ),
      tail: null,
    );

    expect(filled.totalTimeSeconds, original.totalTimeSeconds);
    expect(filled.totalWalkTimeSeconds, original.totalWalkTimeSeconds);
    expect(filled.totalDistanceMeters, original.totalDistanceMeters);
    expect(filled.fare, original.fare);
    expect(filled.transferCount, original.transferCount);
  });

  test('도보 경로를 못 받으면 직선으로 잇는다 — 비워 두면 지도에서 선이 끊긴다', () {
    final filled = fillTransitWalkLegs(
      _kakaoShaped(),
      origin: _origin,
      destination: _destination,
      head: null,
      tail: null,
    );

    expect(filled.legs, hasLength(3));
    expect(filled.legs.first.points, [_origin, _boardAt]);
    expect(filled.legs.last.points, [_alightAt, _destination]);
    // 직선일 때 시간·거리를 지어내지 않는다. 총계와 달리 검증할 근거가 없다.
    expect(filled.legs.first.sectionTimeSeconds, 0);
    expect(filled.legs.first.distanceMeters, 0);
  });

  test('이미 도보로 시작·끝나면 덧붙이지 않는다', () {
    const walkOnly = TransitItinerary(
      totalTimeSeconds: 600,
      totalWalkTimeSeconds: 600,
      totalDistanceMeters: 800,
      transferCount: 0,
      legs: [
        TransitLeg(
          mode: TransitMode.walk,
          sectionTimeSeconds: 600,
          distanceMeters: 800,
          points: [_origin, _destination],
        ),
      ],
    );

    final filled = fillTransitWalkLegs(
      walkOnly,
      origin: _origin,
      destination: _destination,
    );

    // 도보 → 도보 → 도보가 되면 목록에 같은 수단이 연달아 찍힌다.
    expect(filled.legs, hasLength(1));
  });

  test('구간이 하나도 없으면 그대로 돌려준다', () {
    const empty = TransitItinerary(
      totalTimeSeconds: 0,
      totalWalkTimeSeconds: 0,
      totalDistanceMeters: 0,
      transferCount: 0,
      legs: [],
    );

    expect(
      fillTransitWalkLegs(
        empty,
        origin: _origin,
        destination: _destination,
      ).legs,
      isEmpty,
    );
  });

  group('transitWalkGaps', () {
    test('여러 후보가 같은 정류장을 쓰면 한 쌍만 남는다 — 순서는 후보 순서 그대로', () {
      final gaps = transitWalkGaps(
        [_kakaoShaped(), _kakaoShaped()],
        origin: _origin,
        destination: _destination,
      );

      expect(gaps, hasLength(2));
      expect(gaps[0].from, _origin);
      expect(gaps[0].to, _boardAt);
      expect(gaps[1].from, _alightAt);
      expect(gaps[1].to, _destination);
    });

    test('소수 6자리만 다른 정류장은 같은 쌍으로 본다 — 1m 안쪽이다', () {
      final gaps = transitWalkGaps(
        [
          _kakaoShaped(),
          _kakaoShaped(
            boardAt: const LatLng(37.5215004, 126.9242996),
            alightAt: const LatLng(37.5044999, 127.0251001),
          ),
        ],
        origin: _origin,
        destination: _destination,
      );

      expect(gaps, hasLength(2));
    });

    test('부를 가치가 없는 구간은 빼고, 실제 좌표는 반올림해서 돌려준다', () {
      final gaps = transitWalkGaps(
        [
          // 이미 도보로 시작 → 앞 도보는 붙지 않으니 부를 이유가 없다.
          const TransitItinerary(
            totalTimeSeconds: 1000,
            totalWalkTimeSeconds: 300,
            totalDistanceMeters: 5000,
            transferCount: 0,
            legs: [
              TransitLeg(
                mode: TransitMode.walk,
                sectionTimeSeconds: 300,
                distanceMeters: 300,
                points: [_origin, _boardAt],
              ),
              TransitLeg(
                mode: TransitMode.subway,
                sectionTimeSeconds: 700,
                distanceMeters: 4700,
                points: [_boardAt, _alightAt],
              ),
            ],
          ),
          // 좌표가 빈 leg → 어디로 걸어야 하는지 알 수 없다.
          _kakaoShaped(noPoints: true),
        ],
        origin: _origin,
        destination: _destination,
      );

      expect(gaps, hasLength(1));
      expect(gaps.single.from, _alightAt);
      expect(gaps.single.to, _destination);
    });

    test('상한을 넘으면 앞 후보 것을 남긴다 — 잘린 구간은 직선으로 떨어진다', () {
      final gaps = transitWalkGaps(
        [
          _kakaoShaped(),
          _kakaoShaped(
            boardAt: const LatLng(37.5400, 126.9500),
            alightAt: const LatLng(37.5100, 127.0300),
          ),
        ],
        origin: _origin,
        destination: _destination,
        maxGaps: 3,
      );

      expect(gaps, hasLength(3));
      // 첫 후보는 앞뒤가 다 채워지고, 잘리는 것은 마지막 후보의 뒤 도보다.
      expect(gaps[0].to, _boardAt);
      expect(gaps[1].from, _alightAt);
      expect(gaps[2].to, const LatLng(37.5400, 126.9500));
    });

    test('후보가 없거나 구간이 비면 부를 것도 없다', () {
      expect(
        transitWalkGaps(const [], origin: _origin, destination: _destination),
        isEmpty,
      );
      expect(
        transitWalkGaps(
          const [
            TransitItinerary(
              totalTimeSeconds: 0,
              totalWalkTimeSeconds: 0,
              totalDistanceMeters: 0,
              transferCount: 0,
              legs: [],
            ),
          ],
          origin: _origin,
          destination: _destination,
        ),
        isEmpty,
      );
      expect(
        transitWalkGaps(
          [_kakaoShaped()],
          origin: _origin,
          destination: _destination,
          maxGaps: 0,
        ),
        isEmpty,
      );
    });

    test('같은 쌍은 캐시에서 맞물린다 — 반올림 전 좌표로 만들어도 같은 키다', () {
      final gaps = transitWalkGaps(
        [_kakaoShaped()],
        origin: _origin,
        destination: _destination,
      );
      final lookup = <TransitWalkGap, int>{for (final gap in gaps) gap: 1};

      expect(
        lookup[TransitWalkGap(
          from: _origin,
          to: const LatLng(37.5215002, 126.9242998),
        )],
        1,
      );
    });
  });
}
