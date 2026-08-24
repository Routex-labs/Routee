import 'package:indoor_pdr_core/indoor_pdr_core.dart';
// AccelPreviewTrack은 공개 API가 아니라 src에서 직접 가져온다.
import 'package:indoor_pdr_core/src/application/accel_preview_track.dart';
import 'package:test/test.dart';

/// 상태형 preview가 "초록에 실제 대응된 수만큼의 주황 걸음"만 소비하려면,
/// 코어가 (a) 실제 반영된 peak의 시각을 path와 정렬하고 (b) 누적 소비 번호를
/// 배치와 함께 내보내야 한다. 이 파일은 그 계약을 고정한다.
///
/// 네이티브 `stepPeakTimes` 원본을 그대로 쓰면 안 된다는 점이 핵심이다.
/// AccelPreviewTrack이 간격·cadence·lead cap으로 버린 peak는 주황 경로에
/// 점을 만들지 않으므로, 그 원본으로 소비 위치를 계산하면 어긋난다.
void main() {
  group('AccelPreviewTrack.acceptedPeakTimesMs', () {
    ({AccelPreviewTrack track, int lastPeakMs}) feed({
      required int peakCount,
      required int confirmedSteps,
      required double confirmedDistanceM,
      int maxPoints = 800,
      int stepMs = 530,
    }) {
      final track = AccelPreviewTrack(maxPoints: maxPoints);
      var peakMs = 1000;
      for (var i = 1; i <= peakCount; i += 1) {
        peakMs += stepMs;
        track.applyRealtimePeaks(
          AccelPeakEvent(count: i, latestPeakMs: peakMs),
          tracking: true,
          hasHeading: true,
          effectiveStrideMeters: 0.75,
          fallbackStrideMeters: 0.75,
          confirmedSteps: confirmedSteps,
          confirmedDistanceM: confirmedDistanceM,
          pedometerCadenceHz: 1.9,
          headingAt: (_) => null,
          fallbackHeadingDeg: 0,
        );
      }
      return (track: track, lastPeakMs: peakMs);
    }

    test('path와 길이가 같고 원점만 null이다', () {
      final track = feed(
        peakCount: 8,
        confirmedSteps: 100,
        confirmedDistanceM: 100,
      ).track;

      // 첫 peak는 카운터 baseline이라 걸음이 되지 않는다(peakCount - 1).
      expect(track.steps, 7);
      expect(track.acceptedPeakTimesMs.length, track.path.length);
      expect(track.acceptedPeakTimesMs.first, isNull);
      expect(track.acceptedPeakTimesMs.skip(1), everyElement(isNotNull));
      // 시각은 단조 증가해야 한다. 뒤집히면 확정 소비가 엉뚱한 지점을 자른다.
      final times = track.acceptedPeakTimesMs.skip(1).cast<int>().toList();
      for (var i = 1; i < times.length; i += 1) {
        expect(times[i], greaterThan(times[i - 1]));
      }
    });

    test('거부된 peak는 경로에도 시각 배열에도 남지 않는다', () {
      // confirmed 0 → maxInitialStepLead(30)에서 멈춘다. 40개를 먹여도 30걸음.
      final track = feed(
        peakCount: 40,
        confirmedSteps: 0,
        confirmedDistanceM: 0,
      ).track;

      expect(
        track.rejectReasons[AccelPreviewTrack.stepLeadCap],
        greaterThan(0),
      );
      expect(track.steps, AccelPreviewTrack.maxInitialStepLead);
      // 핵심: 거부분이 시각 배열에 새지 않는다.
      expect(track.acceptedPeakTimesMs.length, track.path.length);
      expect(track.acceptedPeakTimesMs.length, track.steps + 1);
    });

    test('delta > 1이면 같은 시각을 반복 저장해 인덱스 정렬을 지킨다', () {
      final track = AccelPreviewTrack();
      void peak(int count, int peakMs) => track.applyRealtimePeaks(
        AccelPeakEvent(count: count, latestPeakMs: peakMs),
        tracking: true,
        hasHeading: true,
        effectiveStrideMeters: 0.75,
        fallbackStrideMeters: 0.75,
        confirmedSteps: 100,
        confirmedDistanceM: 100,
        pedometerCadenceHz: 1.9,
        headingAt: (_) => null,
        fallbackHeadingDeg: 0,
      );

      peak(1, 1000); // baseline
      peak(2, 1530); // delta 1
      peak(5, 3120); // delta 3 — 한 이벤트가 peak 3개를 싣고 왔다

      expect(track.steps, 4);
      expect(track.acceptedPeakTimesMs.length, track.path.length);
      // 코어가 아는 시각은 latestPeakMs 하나뿐이라 3개가 같은 값을 갖는다.
      expect(track.acceptedPeakTimesMs, [null, 1530, 3120, 3120, 3120]);
    });

    test('path가 trim되면 시각 배열도 같은 만큼 잘린다', () {
      final result = feed(
        peakCount: 20,
        confirmedSteps: 100,
        confirmedDistanceM: 100,
        maxPoints: 6,
      );
      final track = result.track;

      expect(track.path.length, 6);
      expect(track.acceptedPeakTimesMs.length, 6);
      // 앞이 잘렸으므로 원점 null은 사라지고 마지막은 최신 peak 시각이다.
      expect(track.acceptedPeakTimesMs.last, result.lastPeakMs);
      expect(track.acceptedPeakTimesMs, everyElement(isNotNull));
    });

    test('reset은 원점 상태로 되돌린다', () {
      final track = feed(
        peakCount: 5,
        confirmedSteps: 100,
        confirmedDistanceM: 100,
      ).track;
      track.reset();

      expect(track.acceptedPeakTimesMs, [null]);
      expect(track.acceptedPeakTimesMs.length, track.path.length);
    });

    test('경로 재기준화는 native peak baseline을 보존해 다음 한 걸음을 즉시 받는다', () {
      final track = AccelPreviewTrack();
      bool peak(int count, int peakMs) => track.applyRealtimePeaks(
        AccelPeakEvent(count: count, latestPeakMs: peakMs),
        tracking: true,
        hasHeading: true,
        effectiveStrideMeters: 0.7,
        fallbackStrideMeters: 0.7,
        confirmedSteps: 100,
        confirmedDistanceM: 70,
        pedometerCadenceHz: null,
        headingAt: (_) => null,
        fallbackHeadingDeg: 0,
      );

      expect(peak(1, 1000), isFalse); // 최초 센서 baseline
      expect(peak(2, 1500), isTrue);
      track.reset(preserveNativePeakBaseline: true);

      expect(track.steps, 0);
      expect(peak(3, 2000), isTrue);
      expect(track.steps, 1);
      expect(track.path, hasLength(2));
    });
  });

  group('PdrSnapshot.lastAppliedBatch', () {
    PdrSession seededSession() {
      final s = PdrSession(config: PdrSessionConfig(nowMs: () => 0));
      s.onHeading(
        const HeadingEvent(
          motionTimestampMs: 1000,
          fusedHeadingDeg: 0,
          headingStable: true,
          headingSource: 'device_motion/xMagneticNorthZVertical',
        ),
      );
      return s;
    }

    test('배치를 반영하기 전에는 null이다', () {
      expect(seededSession().snapshot.lastAppliedBatch, isNull);
    });

    test('반영된 배치의 시간창·걸음·거리를 그대로 싣는다', () {
      final s = seededSession();
      s.onPedometerBatch(
        const PedometerBatchEvent(
          steps: 10,
          stepSessionId: 1,
          sessionStartMs: 900,
          timestampMs: 2000,
          distanceM: 7.0,
          distanceAvailable: true,
          stepPeakTimes: [1100, 1300, 1500, 1700, 1900],
        ),
      );

      final batch = s.snapshot.lastAppliedBatch;
      expect(batch, isNotNull);
      expect(batch!.appliedSteps, 10);
      expect(batch.appliedDistanceM, closeTo(7.0, 1e-9));
      expect(batch.spanStartMs, 900);
      expect(batch.spanEndMs, 2000);
    });

    test('batchId가 배치마다 증가해 중복 소비를 막을 수 있다', () {
      final s = seededSession();
      s.onPedometerBatch(
        const PedometerBatchEvent(
          steps: 10,
          stepSessionId: 1,
          sessionStartMs: 900,
          timestampMs: 2000,
          distanceM: 7.0,
          distanceAvailable: true,
          stepPeakTimes: [1100, 1500, 1900],
        ),
      );
      final first = s.snapshot.lastAppliedBatch!.batchId;

      // snapshot은 motion 이벤트마다 다시 방출된다. 같은 배치를 두 번 소비하면
      // 안 되므로 batchId가 그대로여야 한다.
      s.onHeading(
        const HeadingEvent(
          motionTimestampMs: 2200,
          fusedHeadingDeg: 5,
          headingStable: true,
          headingSource: 'device_motion/xMagneticNorthZVertical',
        ),
      );
      expect(s.snapshot.lastAppliedBatch!.batchId, first);

      s.onPedometerBatch(
        const PedometerBatchEvent(
          steps: 18,
          stepSessionId: 1,
          sessionStartMs: 900,
          timestampMs: 4000,
          distanceM: 12.6,
          distanceAvailable: true,
          stepPeakTimes: [2300, 2900, 3500],
        ),
      );
      final second = s.snapshot.lastAppliedBatch!;
      expect(second.batchId, greaterThan(first));
      expect(second.appliedSteps, 8);
    });

    test('reset하면 batchId가 1로 되돌아가므로 lastAppliedBatch도 비운다', () {
      final s = seededSession();
      s.onPedometerBatch(
        const PedometerBatchEvent(
          steps: 10,
          stepSessionId: 1,
          sessionStartMs: 900,
          timestampMs: 2000,
          distanceM: 7.0,
          distanceAvailable: true,
          stepPeakTimes: [1100, 1500, 1900],
        ),
      );
      expect(s.snapshot.lastAppliedBatch, isNotNull);

      s.reset(newStepSessionId: 2);
      // 남겨두면 새 세션의 batchId=1을 "이미 소비함"으로 오판한다.
      expect(s.snapshot.lastAppliedBatch, isNull);
    });

    test('경로 재기준화는 heading과 native 누적 baseline을 유지한다', () {
      final s = seededSession();
      s.onAccelPeak(const AccelPeakEvent(count: 1, latestPeakMs: 1100));
      s.onAccelPeak(const AccelPeakEvent(count: 2, latestPeakMs: 1600));
      s.onPedometerBatch(
        const PedometerBatchEvent(
          steps: 4,
          stepSessionId: 1,
          sessionStartMs: 900,
          timestampMs: 2000,
          distanceM: 2.8,
          distanceAvailable: true,
          stepPeakTimes: [1100, 1400, 1700, 1900],
        ),
      );
      expect(s.snapshot.steps, 4);

      s.rebasePath(atMs: 2500);
      expect(s.snapshot.hasHeading, isTrue);
      expect(s.snapshot.steps, 0);
      expect(s.snapshot.preview.steps, 0);
      expect(s.snapshot.path, [PdrLocalPoint.zero]);

      // native count를 0으로 되돌리지 않았으므로 다음 count=3이 곧 한 걸음이다.
      s.onAccelPeak(const AccelPeakEvent(count: 3, latestPeakMs: 3000));
      expect(s.snapshot.preview.steps, 1);

      // 누적 steps=8 중 이전 4걸음은 baseline으로 보존되고, 새 delta 4걸음 중
      // 재기준화 경계(2500ms) 이후 peak 3개만 새 경로에 들어간다.
      s.onPedometerBatch(
        const PedometerBatchEvent(
          steps: 8,
          stepSessionId: 1,
          sessionStartMs: 900,
          timestampMs: 3500,
          distanceM: 5.6,
          distanceAvailable: true,
          stepPeakTimes: [2200, 2700, 3000, 3300],
        ),
      );
      expect(s.snapshot.steps, 3);
      expect(s.snapshot.distanceM, closeTo(2.1, 1e-9));
    });
  });

  group('실제 적용 걸음 수 기준 preview 소비', () {
    test('적용 걸음과 시간창 peak 수가 같으면 미래 peak만 남는다', () {
      final s = PdrSession(config: PdrSessionConfig(nowMs: () => 0));
      s.onHeading(
        const HeadingEvent(
          motionTimestampMs: 1000,
          fusedHeadingDeg: 0,
          headingStable: true,
          headingSource: 'device_motion/xMagneticNorthZVertical',
        ),
      );
      // 첫 peak(1000)는 baseline이라 걸음이 되지 않는다. 이후 6개가 주황 걸음.
      var count = 0;
      for (final peakMs in [1000, 1500, 2000, 2500, 3000, 3500, 4000]) {
        count += 1;
        s.onAccelPeak(AccelPeakEvent(count: count, latestPeakMs: peakMs));
      }
      // 초록 배치는 2600까지만 덮는다.
      s.onPedometerBatch(
        const PedometerBatchEvent(
          steps: 3,
          stepSessionId: 1,
          sessionStartMs: 900,
          timestampMs: 2600,
          distanceM: 2.1,
          distanceAvailable: true,
          stepPeakTimes: [1500, 2000, 2500],
        ),
      );

      final snapshot = s.snapshot;
      final spanEndMs = snapshot.lastAppliedBatch!.spanEndMs!;
      final times = snapshot.preview.acceptedPeakTimesMs;
      expect(times.length, snapshot.preview.path.length);

      final consumed = times.where((t) => t != null && t <= spanEndMs).length;
      final pending = times.where((t) => t != null && t > spanEndMs).length;
      // 확정 시간창 안의 주황 걸음 3개만 소비되고, 이후 3개는 선행분으로 남는다.
      expect(consumed, 3);
      expect(pending, 3);
      expect(snapshot.lastAppliedBatch!.consumedPreviewSteps, 3);
      expect(snapshot.lastAppliedBatch!.acknowledgedPreviewSteps, 3);
      expect(snapshot.preview.steps, 6);
      expect(snapshot.steps, 3);
      // 표시 경로는 초록 3걸음 끝에서 미래 주황 3걸음만 다시 이어진다.
      expect(snapshot.reconciledPreviewPath.length, snapshot.path.length + 3);
      expect(
        snapshot.reconciledPreviewPath[snapshot.path.length - 1],
        snapshot.position,
      );
      expect(
        snapshot.reconciledPreviewPosition.northM,
        greaterThan(snapshot.position.northM),
      );
    });

    test('초록 1걸음의 시간창에 peak가 2개여도 주황은 1개만 소비한다', () {
      final s = PdrSession(config: PdrSessionConfig(nowMs: () => 0));
      s.onHeading(
        const HeadingEvent(
          motionTimestampMs: 1000,
          fusedHeadingDeg: 0,
          headingStable: true,
          headingSource: 'device_motion/xMagneticNorthZVertical',
        ),
      );
      s.onAccelPeak(const AccelPeakEvent(count: 1, latestPeakMs: 1000));
      s.onAccelPeak(const AccelPeakEvent(count: 2, latestPeakMs: 1500));
      s.onHeading(
        const HeadingEvent(
          motionTimestampMs: 1750,
          fusedHeadingDeg: 90,
          headingStable: true,
          headingSource: 'device_motion/xMagneticNorthZVertical',
        ),
      );
      for (final (count, peakMs) in [(3, 2000), (4, 2500), (5, 3000)]) {
        s.onAccelPeak(AccelPeakEvent(count: count, latestPeakMs: peakMs));
      }
      final orangeBefore = s.snapshot.preview.path;

      s.onPedometerBatch(
        const PedometerBatchEvent(
          steps: 1,
          stepSessionId: 1,
          sessionStartMs: 900,
          timestampMs: 2100,
          distanceM: 0.7,
          distanceAvailable: true,
          stepPeakTimes: [1500],
        ),
      );

      final snapshot = s.snapshot;
      expect(snapshot.lastAppliedBatch!.appliedSteps, 1);
      expect(snapshot.lastAppliedBatch!.consumedPreviewSteps, 1);
      expect(snapshot.lastAppliedBatch!.acknowledgedPreviewSteps, 1);
      expect(
        snapshot.reconciledPreviewPath.length,
        orangeBefore.length,
        reason: '시간창 안의 두 번째 주황 걸음은 초록에 대응되지 않았으므로 남아야 한다',
      );
      expect(
        snapshot.reconciledPreviewPosition.northM,
        closeTo(orangeBefore.last.northM, 1e-9),
      );
      expect(
        snapshot.reconciledPreviewPosition.eastM,
        closeTo(orangeBefore.last.eastM, 1e-9),
        reason: '초록 한 걸음도 대응된 첫 주황 peak 시각의 heading을 써야 회전각이 보존된다',
      );
    });

    test('확정 배치가 늦어도 유예 창 안이면 12걸음 캡을 재지 않는다', () {
      final track = AccelPreviewTrack();
      var peakMs = 1000;
      // 확정은 1530ms에 멈춰 있고 7.4초 동안 14걸음을 걷는다. 예전 구조는 여기서
      // 12걸음 캡에 걸려 두 걸음을 버렸다 — 걷는 중에 마커가 서던 동작이다.
      for (var count = 1; count <= 14; count++) {
        peakMs += 530;
        track.applyRealtimePeaks(
          AccelPeakEvent(count: count, latestPeakMs: peakMs),
          tracking: true,
          hasHeading: true,
          effectiveStrideMeters: 0.75,
          fallbackStrideMeters: 0.75,
          confirmedSteps: 1,
          confirmedDistanceM: 0.75,
          confirmedThroughMs: 1530,
          pedometerCadenceHz: 1.9,
          headingAt: (_) => null,
          fallbackHeadingDeg: 0,
        );
      }
      expect(peakMs - 1530, lessThan(AccelPreviewTrack.confirmedLagGraceMs));
      // 첫 호출은 native 누적 peak baseline을 잡는 데 쓰이므로 13걸음이다.
      expect(track.steps, 13);
      expect(track.deferredPeaks, 0);
      expect(track.rejectReasons[AccelPreviewTrack.stepLeadCap], 0);
    });

    test('확정이 유예 창을 넘겨 멈추면 캡이 걸리되 걸음은 버리지 않고 보류한다', () {
      final track = AccelPreviewTrack();
      var peakMs = 1000;
      // 확정이 1530ms에서 멈춘 채 20걸음(10.6초)을 걷는다. 유예를 넘긴 뒤부터
      // 캡이 걸린다.
      for (var count = 1; count <= 20; count++) {
        peakMs += 530;
        track.applyRealtimePeaks(
          AccelPeakEvent(count: count, latestPeakMs: peakMs),
          tracking: true,
          hasHeading: true,
          effectiveStrideMeters: 0.75,
          fallbackStrideMeters: 0.75,
          confirmedSteps: 1,
          confirmedDistanceM: 0.75,
          confirmedThroughMs: 1530,
          pedometerCadenceHz: 1.9,
          headingAt: (_) => null,
          fallbackHeadingDeg: 0,
        );
      }
      expect(peakMs - 1530, greaterThan(AccelPreviewTrack.confirmedLagGraceMs));
      final cappedSteps = track.steps;
      expect(cappedSteps, lessThan(19));
      // 버린 게 아니라 들고 있어야 한다.
      expect(track.deferredPeaks, 19 - cappedSteps);
      expect(track.rejectReasons[AccelPreviewTrack.deferOverflow], 0);

      // 다음 confirmed 배치가 한 걸음을 적용하면 preview도 정확히 한 걸음만
      // 대응시킨다. 시간창 안의 deferred 전체를 지우면 실제로 적용되지 않은
      // 주황 이동이 사라진다.
      peakMs += 530;
      final deferredBeforeConfirm = track.deferredPeaks;
      final acknowledged = track.acknowledgeConfirmedBatch(
        appliedSteps: 1,
        spanEndMs: peakMs - 530,
      );
      final changed = track.applyRealtimePeaks(
        AccelPeakEvent(count: 21, latestPeakMs: peakMs),
        tracking: true,
        hasHeading: true,
        effectiveStrideMeters: 0.75,
        fallbackStrideMeters: 0.75,
        confirmedSteps: 2,
        confirmedDistanceM: 1.5,
        confirmedThroughMs: peakMs - 530,
        pedometerCadenceHz: 1.9,
        headingAt: (_) => null,
        fallbackHeadingDeg: 0,
      );

      expect(changed, isTrue);
      expect(acknowledged.accepted + acknowledged.deferred, 1);
      expect(track.deferredPeaks, deferredBeforeConfirm);
      expect(deferredBeforeConfirm, greaterThan(0));
      expect(track.steps, cappedSteps + 1);
    });
  });
}
