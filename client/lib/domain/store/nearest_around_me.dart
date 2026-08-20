/// **내가 지금 서 있는 자리 주변**에서 가까운 것부터 고르는 규칙.
///
/// 방향을 가리지 않는 360°이고 거리는 직선으로 잰다. 걷는 거리를 묻는
/// [nearby_stores.dart]와 **일부러 다르며**, 그 이유와 검증 기준은
/// `docs/client/indoor-entry-rules.md` 5절.
///
/// 좌표는 층 로컬 미터다. 모델이 아니라 id와 좌표만 받아 매장·노드·시설
/// 어느 쪽에도 묶이지 않는다.
library;

import 'dart:math' as math;

/// 후보 하나와 [nearestAroundMe]가 잰 직선거리.
typedef NearestPoint = ({String id, double distanceM});

/// [fromX]·[fromY]에서 가까운 순으로 최대 [limit]개.
///
/// 같은 거리면 id로 가른다 — 안 그러면 같은 화면을 두 번 열었을 때 순서가
/// 뒤집혀 "방금 두 번째였던 줄"이 첫 줄에 온다.
///
/// [limit]이 0 이하면 빈 목록이다.
List<NearestPoint> nearestAroundMe({
  required double fromX,
  required double fromY,
  required Iterable<({String id, double x, double y})> points,
  int limit = 12,
}) {
  if (limit <= 0) return const [];
  final measured =
      points
          .map(
            (p) => (
              id: p.id,
              distanceM: math.sqrt(
                (p.x - fromX) * (p.x - fromX) + (p.y - fromY) * (p.y - fromY),
              ),
            ),
          )
          .toList()
        ..sort((a, b) {
          final byDistance = a.distanceM.compareTo(b.distanceM);
          return byDistance != 0 ? byDistance : a.id.compareTo(b.id);
        });
  return measured.length <= limit ? measured : measured.sublist(0, limit);
}
