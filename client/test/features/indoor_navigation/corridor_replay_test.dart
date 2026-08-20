import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import 'corridor_replay_harness.dart';

/// 2026-07-27 실측 두 세션을 재생해 복도 보정의 회귀를 막는다.
///
/// 두 로그 모두 B2에서 시작점 근처로 되돌아온 왕복이다. 실측에서는 보정 경로가
/// 무너졌고(아이폰 정지, 안드로이드 한 복도 미끄러짐), 이 테스트는 그 실패가
/// 되살아나지 않는지 본다.
void main() {
  group('아이폰 B2 서쪽 왕복 재생', () {
    // 실측: T자 교차점(157.7, 131.3)에서 28.1초 멈춘 뒤 북쪽 간선을 잘못 타고
    // 다시 멈췄다. 106.67m를 걸었는데 보정은 22.86m만 그렸다(비율 0.21).
    late CorridorReplayRun run;

    setUpAll(() {
      run = CorridorReplay.load('pdr_v10_ios_b2_west.json').run();
    });

    test('걸은 거리의 대부분이 보정 경로에 남는다', () {
      // 실측 0.21 -> 1.00. 보정 경로는 1등 가설 자신의 이력이라 걸은 거리와
      // 같아야 정상이다. 모자라면 이동을 버린 것이고, 넘치면 이질적인 조각을
      // 이어 붙인 것이다.
      expect(
        run.distanceRetention,
        greaterThan(0.95),
        reason:
            '실측 0.21. 미해결 구간의 이동이 버려지면 마커는 영원히 뒤처진다. '
            '실제 유지율 ${run.distanceRetention.toStringAsFixed(2)}',
      );
    });

    test('보정 경로가 매장을 가로질러 순간이동하지 않는다', () {
      // 서로 다른 가설의 조각을 이어 붙이면 이음매가 지도를 가로지르는
      // 직선이 된다. 실측에서 29점 중 21구간이 2m 초과 점프였고 합계 102.5m —
      // 화면에 보이던 "건물 뚫고 가는 보라선"이 이것이었다.
      expect(
        run.correctedTeleports,
        isEmpty,
        reason:
            '${run.correctedTeleports.length}구간, 최대 '
            '${run.correctedTeleports.isEmpty ? 0 : run.correctedTeleports.reduce((a, b) => a > b ? a : b).toStringAsFixed(1)}m',
      );
    });

    test('걷는 동안 확정 위치가 오래 멈추지 않는다', () {
      // 실측 28.1초 -> 5.1초. 남은 5초는 확정 걸음이 배치로 몰려 오는 구간의
      // 입력 공백이라 tracker가 아니라 pedometer 쪽 지연이다.
      expect(
        run.longestStallSeconds,
        lessThan(6.0),
        reason:
            '실측 28.1초 정지. 실제 ${run.longestStallSeconds.toStringAsFixed(1)}초',
      );
    });

    test('서쪽 우회 복도를 실제로 지나간다', () {
      // 그래프상 서진은 T자에서 남 4.7m -> 서 11.9m(y=126.6) -> 북 4.6m 로
      // 꺾어야 한다. 사용자는 이 구간을 대각선으로 질렀다.
      final bounds = run.correctedBounds;
      expect(
        bounds.minEast,
        lessThan(150),
        reason:
            '원본은 east 122까지 갔다. 보정이 157.7에서 막히면 서쪽 우회를 '
            '전혀 못 탄 것. 실제 최소 east ${bounds.minEast.toStringAsFixed(1)}',
      );
    });

    test('교차점에서 28초씩 얼어붙지 않는다', () {
      // 실측 실패의 핵심은 "북쪽으로 갔다"가 아니라 "T자 교차점(157.7,131.3)에
      // 도달한 뒤 28초 동안 그 자리에 있었다"였다. 지금은 그 지점을 지나
      // 서쪽 우회로로 진입한다.
      final atJunction = run.samples.where(
        (sample) =>
            (sample.result.correctedPosition -
                    const PdrLocalPoint(157.707, 131.263))
                .distance <
            0.5,
      );
      expect(
        atJunction.length,
        lessThan(run.samples.length ~/ 4),
        reason:
            'T자 교차점에 머문 샘플 ${atJunction.length}/${run.samples.length}',
      );
    });

    test('배치 도착 때만 preview가 튀지 않는다', () {
      // 실측: 배치 도착 시 평균 5.17m / 3m 초과 21건, 그 외 평균 1.29m.
      // 재생성이 사라지면 두 분포가 비슷해져야 한다.
      final onBatch = run.previewJumpsOnBatch;
      final elsewhere = run.previewJumpsElsewhere;
      final batchMean = onBatch.reduce((a, b) => a + b) / onBatch.length;
      final elseMean =
          elsewhere.reduce((a, b) => a + b) / elsewhere.length;
      // 비율로 재지 않는다. 확정 배치는 한 번에 5걸음(약 3.5m)을 밀어 주므로
      // preview도 그만큼 **앞으로** 나가는 것이 정상이고, 배치 사이 평균은
      // 모호 구간 정지 때문에 0에 가깝다. 문제는 방향과 크기였다 — 실측에서는
      // 배치가 올 때마다 평균 5.17m씩 **뒤로** 재계산됐다.
      expect(
        batchMean,
        lessThan(2.5),
        reason:
            '배치 도착 평균 ${batchMean.toStringAsFixed(2)}m '
            '(실측 5.17m), 그 외 ${elseMean.toStringAsFixed(2)}m',
      );
    });

    test('마커가 보라선에서 멀리 떨어지지 않는다', () {
      // 화면 마커는 preview 위치다. 모호 구간에서 preview를 얼려 뒀더니
      // 실측에서 214프레임 중 189프레임이 같은 좌표에 남아, 마커가 실제
      // 위치에서 40m 떨어진 지점에 머물렀다. 선행분은 주황이 앞선 걸음만큼만
      // 나가야 한다.
      expect(
        run.maxPreviewLeadM,
        lessThan(15),
        reason: '최대 ${run.maxPreviewLeadM.toStringAsFixed(1)}m',
      );
    });
  });

  group('갤럭시 B2 동쪽 왕복 재생', () {
    // 실측: 거리 유지율은 0.84로 나쁘지 않았지만 모양이 완전히 틀렸다.
    // 원본은 north 107.5~131.9를 오갔는데 보정은 north 131.3 한 줄에 머물렀다.
    late CorridorReplayRun run;

    setUpAll(() {
      run = CorridorReplay.load('pdr_v10_android_b2_east.json').run();
    });

    test('동서 복도를 벗어나 멀리 헤매지 않는다', () {
      // 주의: 이 세션의 원본은 복도 대비 약 28도 회전해 있었다(원본은 north
      // 107.5까지 내려갔지만 사용자는 동서 복도를 왕복했다). 즉 지상 진실은
      // "north 131.3 복도"이고, 원본의 남하는 heading 오차다. 원본을 진실로
      // 삼아 남쪽으로 따라 내려가면 오히려 틀린다.
      final bounds = run.correctedBounds;
      expect(
        bounds.maxNorth - bounds.minNorth,
        lessThan(15),
        reason:
            '복도 폭을 크게 벗어나면 회전 오차를 실제 이동으로 오인한 것. '
            'north ${bounds.minNorth.toStringAsFixed(1)}~'
            '${bounds.maxNorth.toStringAsFixed(1)}',
      );
    });

    test('동서 복도 전 구간을 왕복한다', () {
      final bounds = run.correctedBounds;
      expect(bounds.minEast, lessThan(176));
      expect(bounds.maxEast, greaterThan(205));
    });

    test('보정 경로가 매장을 가로질러 순간이동하지 않는다', () {
      expect(run.correctedTeleports, isEmpty);
    });

    test('한 간선에만 붙어 있지 않다', () {
      expect(
        run.visitedEdgeIds.toSet().length,
        greaterThan(3),
        reason: '실제 방문 간선 ${run.visitedEdgeIds.toSet().length}개',
      );
    });

    test('걷는 동안 확정 위치가 오래 멈추지 않는다', () {
      expect(
        run.longestStallSeconds,
        lessThan(3.0),
        reason:
            '실측 14.7초 정지. 실제 ${run.longestStallSeconds.toStringAsFixed(1)}초',
      );
    });

    test('걸은 거리의 대부분이 보정 경로에 남는다', () {
      // 1등이 바뀌면 최근 구간이 다시 그려지지만, 그것도 그래프를 따라가는
      // 한 가설의 이력이므로 길이는 걸은 거리와 같아야 한다.
      expect(run.distanceRetention, greaterThan(0.95));
      expect(
        run.distanceRetention,
        lessThan(1.05),
        reason: '실제 유지율 ${run.distanceRetention.toStringAsFixed(2)}',
      );
    });
  });

  group('아이폰 B2 에스컬레이터 레인 붙기 재생', () {
    // 2026-08-20 실측. 에스컬레이터 앞에서 경로가 반대 레인으로 뒤집혀 사용자가
    // 탑승을 포기한 세션이다. 30초 동안 경로가 4번 갈아치워졌다.
    //
    // 나란한 두 레인을 잇는 짧은 간선(B2에 8개, 1.3~4.0m, 전부 동서 방향)이
    // 원인이었다. 원본 위치가 9m 떨어져 있어도 서쪽으로 걷는 heading에 잘 맞아
    // 1등이 그리로 넘어갔고, 마커가 (157.7,147.9) -> (151.7,141.5)로 튄 뒤
    // 되돌려지며 optimistic lead 11.1m가 통째로 사라졌다.
    //
    // **아직 안 고친 것이 남아 있다.** 되돌리기(_rebaseOptimistic) 자체가 lead를
    // 0으로 만드는 문제는 이 세션에 3번 더 있고, 평범한 복도에서도 마커가 최대
    // 9.5m 뒤로 튄다. 그건 레인 연결선과 무관한 별개 결함이라 여기서 재지 않는다.
    late CorridorReplayRun run;

    setUpAll(() {
      run = CorridorReplay.load('pdr_v14_ios_b2_escalator_flip.json').run();
    });

    test('레인 사이 연결선에는 올라타지 않는다', () {
      final graph = CorridorReplay.loadGraph();
      final nodeTypes = {
        for (final node in graph.nodes) node.id: node.type.toLowerCase(),
      };
      const laneLinkTypes = {'escalator', 'elevator', 'stairs'};
      final laneLinkEdgeIds = {
        for (final edge in graph.edges)
          if (laneLinkTypes.contains(nodeTypes[edge.fromNodeId]) &&
              laneLinkTypes.contains(nodeTypes[edge.toNodeId]))
            edge.id,
      };
      expect(laneLinkEdgeIds, hasLength(8), reason: 'B2 실측 8개');

      final occupied = <String>{};
      for (final sample in run.samples) {
        for (final id in [
          sample.result.currentEdgeId,
          sample.result.optimisticEdgeId,
        ]) {
          if (id != null && laneLinkEdgeIds.contains(id)) occupied.add(id);
        }
      }

      expect(
        occupied,
        isEmpty,
        reason:
            '레인 연결선은 사람이 지나다니는 길이 아니라 짧은 동서 방향 자석이다. '
            '수정 전 실측은 A0OzR8GMIZ에, 재생은 rJOyOouyz에 올라탔다 — 어느 쪽이든 '
            '그 직후 되돌려지며 lead가 증발한다.',
      );
    });

  });
}
