/// 실내에서 **출입구를 걸어서 통과했는지** 판정하는 정책.
///
/// GPS를 한 줄도 보지 않는다 — 이탈 판정의 두 번째 입력이고, 첫 번째(GPS)가
/// 가장 느린 구간을 그대로 메우는 것이 존재 이유다.
///
/// 임계값 셋의 근거와 버린 대안은 `docs/client/indoor-entry-rules.md` 5절.
library;

import '../../../features/indoor_navigation/contract/indoor_navigation_contract.dart';

/// 문 노드에서 **안쪽으로** 이 거리 안에 있어야 "이 문 앞에 섰다"고 보고
/// 무장한다(m).
const walkoutArmInsideMeters = 8.0;

/// 무장한 문의 축을 따라 **바깥쪽으로** 이만큼 나아가면 나간 것으로 본다(m).
///
/// 문 안쪽 노드에서 문 바깥 좌표까지가 7~12 m라(`domain/route/
/// building_entrances.dart`의 BuildingEntrance), 5 m는 그 절반쯤 — 문턱을
/// 확실히 넘어선 지점이면서 인도까지 나가기를 기다리지는 않는 거리다.
const walkoutAdvanceMeters = 5.0;

/// 문 축에서 옆으로 이만큼 벗어나면 그 문을 지난 것으로 보지 않는다(m).
///
/// 이 게이트가 없으면 문 앞을 **스쳐 지나가는** 사람이 나간 것으로 읽힌다 —
/// 벽을 따라 걷는 동선은 축과 나란해서 전진 거리만으로는 통과와 구분되지 않는다.
const walkoutHalfWidthMeters = 6.0;

/// 문 하나의 "안 → 밖" 축.
class EntranceAxis {
  const EntranceAxis({
    required this.nodeId,
    required this.nodeM,
    required this.outward,
  });

  /// 이 문의 실내 그래프 노드 id. 무장 대상을 가리키는 값이다.
  final String nodeId;

  /// 문 **안쪽** 노드의 층 좌표(m).
  final PdrLocalPoint nodeM;

  /// 안쪽에서 바깥쪽을 가리키는 **단위** 벡터.
  final PdrLocalPoint outward;
}

/// 문 안쪽 노드 [nodeM]과 문 바깥 좌표 [doorM]으로 축 하나를 만든다.
///
/// 두 점이 1 m 안으로 붙어 있으면 null이다 — 문 좌표가 안 찍혔거나 좌표 변환이
/// 퇴화한 경우인데, 방향을 모르는 축으로 판정하면 "전진"과 "후퇴"가 뒤집혀
/// 건물 안으로 걸어 들어가는 사람을 내보낸다.
EntranceAxis? entranceAxisFrom({
  required String nodeId,
  required PdrLocalPoint nodeM,
  required PdrLocalPoint doorM,
}) {
  final delta = doorM - nodeM;
  final length = delta.distance;
  if (length < 1) return null;
  return EntranceAxis(
    nodeId: nodeId,
    nodeM: nodeM,
    outward: PdrLocalPoint(delta.eastM / length, delta.northM / length),
  );
}

/// 위치 한 건을 문 축에 투영한 결과.
class WalkoutProjection {
  const WalkoutProjection({required this.forwardM, required this.lateralM});

  /// 문 노드 기준 **바깥쪽** 거리(m). 건물 안쪽이면 음수다.
  final double forwardM;

  /// 축에서 옆으로 벗어난 거리(m). 부호를 버리므로 항상 0 이상이다.
  final double lateralM;
}

/// [positionM]을 [axis] 위에 투영한다. 층 좌표계는 이미 미터 평면이라 위경도
/// 보정이 필요 없다.
WalkoutProjection projectOnEntranceAxis(
  EntranceAxis axis,
  PdrLocalPoint positionM,
) {
  final delta = positionM - axis.nodeM;
  final forward =
      delta.eastM * axis.outward.eastM + delta.northM * axis.outward.northM;
  final lateral =
      (delta.eastM * axis.outward.northM - delta.northM * axis.outward.eastM)
          .abs();
  return WalkoutProjection(forwardM: forward, lateralM: lateral);
}

/// "문 앞에 섰다 → 문 밖으로 걸어 나갔다"를 문마다 따라가는 상태기.
///
/// **무장 없이 거리만 보면 안 된다.** 앵커가 어긋난 채 시작하면 위치가 처음부터
/// 문 바깥에 놓일 수 있고, 그때 곧바로 발화하면 사용자는 건물 한가운데에서
/// 야외 지도로 튕겨 나간다. 안쪽에서 다가섰던 문만 나갈 수 있게 한다.
class EntranceWalkoutDetector {
  String? _armedNodeId;

  /// 지금 무장 중인 문의 노드 id. 진단과 테스트가 읽는다.
  String? get armedNodeId => _armedNodeId;

  /// 위치 한 건을 넣는다. 문을 통과했으면 그 문의 노드 id, 아니면 null.
  ///
  /// [positionM]은 **복도 보정 전 좌표**여야 한다. 보정된 위치는 통행 그래프에
  /// 붙어 있어서, 그래프가 끝나는 문 바깥으로는 애초에 나가지 못한다.
  ///
  /// 발화하면 스스로 무장을 푼다 — 화면이 이탈을 처리하는 동안 같은 위치가 다시
  /// 들어와도 두 번 부르지 않는다.
  String? update({
    required List<EntranceAxis> axes,
    required PdrLocalPoint positionM,
  }) {
    for (final axis in axes) {
      final projection = projectOnEntranceAxis(axis, positionM);
      if (projection.lateralM > walkoutHalfWidthMeters) continue;
      if (axis.nodeId == _armedNodeId &&
          projection.forwardM >= walkoutAdvanceMeters) {
        _armedNodeId = null;
        return axis.nodeId;
      }
      // 무장은 **안쪽에서만** 된다. 바깥에서 무장하면 다음 한 걸음이 곧바로
      // 발화 조건을 채워, 다가선 적 없는 문으로 나가게 된다.
      if (projection.forwardM <= 0 &&
          projection.forwardM >= -walkoutArmInsideMeters) {
        _armedNodeId = axis.nodeId;
      }
    }
    return null;
  }

  /// 앵커를 다시 찍었거나 층·건물이 바뀌었을 때. 무장은 이전 좌표계에서 쌓은
  /// 근거라 그대로 들고 가면 안 된다.
  void reset() => _armedNodeId = null;
}
