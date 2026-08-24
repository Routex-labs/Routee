import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/features/indoor_navigation/contract/altitude_sample.dart';
import 'package:navigation_client/features/indoor_navigation/debug/elevator_altitude_probe.dart';

/// 이 도구의 계약은 **"재는 것이지 판단하는 것이 아니다"** 이다.
///
/// 층별 고도표를 만드는 것이 목적이므로, 값을 미리 소화해 버리면 나중에 보정
/// 방식을 바꿀 때 다시 재야 한다. 그래서 원시 샘플을 통째로 남기고, 움직이는
/// 중에 찍힌 점은 표에서 빼되 **지우지는 않는다**.
void main() {
  /// 고도(m)를 만들어 내는 기압. ISA 식의 역이라 정확할 필요는 없고, 층 간격이
  /// 실제 층고(4~6m)만큼 벌어지기만 하면 된다.
  double hpaForAltitude(double altitudeM) =>
      1013.25 * math.pow(1 - altitudeM / 44330.0, 1 / 0.190295);

  AltitudeSample sampleAt(int tMs, double altitudeM) => AltitudeSample(
    timestampMs: tMs,
    pressureHpa: hpaForAltitude(altitudeM),
    source: 'android_pressure',
  );

  /// [altitudeM]에 가만히 서 있는 구간. 평활 창(3초)과 속도 밑변(700ms)을
  /// 채우려면 여러 샘플이 필요하다.
  void standStill(
    ElevatorAltitudeProbe probe, {
    required int fromMs,
    required double altitudeM,
    int durationMs = 5000,
  }) {
    for (var t = fromMs; t <= fromMs + durationMs; t += 200) {
      probe.onSample(sampleAt(t, altitudeM));
    }
  }

  test('멈춰 서서 찍은 점만 층별 표에 들어간다', () {
    final probe = ElevatorAltitudeProbe()..start();

    standStill(probe, fromMs: 0, altitudeM: 0);
    probe.mark('1F');

    // 타는 중 — 0.8 m/s로 오르는 구간에서 찍었다.
    for (var t = 6000; t <= 9000; t += 200) {
      probe.onSample(sampleAt(t, (t - 6000) / 1000 * 0.8));
    }
    probe.mark('2F');

    standStill(probe, fromMs: 10000, altitudeM: 5.4);
    probe.mark('2F');

    expect(probe.marks.length, 3, reason: '이동 중 점도 기록은 남긴다');
    final rows = probe.floorSummary;
    expect(rows.map((r) => r.floorLabel), ['1F', '2F']);
    // 2F는 두 번 찍혔지만 멈춰서 찍은 것은 하나뿐이다.
    expect(rows.firstWhere((r) => r.floorLabel == '2F').count, 1);
  });

  test('층별 표는 고도 순이고 인접 층 차이가 실측 층고로 나온다', () {
    final probe = ElevatorAltitudeProbe()..start();

    // 일부러 순서를 뒤섞어 찍는다 — 실제 측정도 엘리베이터가 서는 순서를 따른다.
    standStill(probe, fromMs: 0, altitudeM: 5.4);
    probe.mark('2F');
    standStill(probe, fromMs: 6000, altitudeM: -6.2);
    probe.mark('B1');
    standStill(probe, fromMs: 12000, altitudeM: 0);
    probe.mark('1F');

    final rows = probe.floorSummary;
    expect(rows.map((r) => r.floorLabel), ['B1', '1F', '2F']);
    expect(
      rows[1].meanAltitudeM - rows[0].meanAltitudeM,
      closeTo(6.2, 0.1),
      reason: 'B1→1F 실측 층고',
    );
    expect(rows[2].meanAltitudeM - rows[1].meanAltitudeM, closeTo(5.4, 0.1));
  });

  test('같은 층을 다시 찍으면 그 벌어짐이 드리프트로 드러난다', () {
    // 해면기압이 시간당 1~2 hPa 움직인다. 같은 1F인데 나중에 잰 값이 2m 높게
    // 나오면 그 세션의 표는 그만큼 못 믿는다는 뜻이고, 그걸 화면이 말해야 한다.
    final probe = ElevatorAltitudeProbe()..start();

    standStill(probe, fromMs: 0, altitudeM: 0);
    probe.mark('1F');
    standStill(probe, fromMs: 600000, altitudeM: 2.0);
    probe.mark('1F');

    final row = probe.floorSummary.single;
    expect(row.count, 2);
    expect(row.spreadM, closeTo(2.0, 0.1));
  });

  test('녹화 중이 아니면 샘플을 버린다', () {
    final probe = ElevatorAltitudeProbe();
    standStill(probe, fromMs: 0, altitudeM: 0);

    expect(probe.sampleCount, 0);
    expect(probe.mark('1F'), isNull, reason: '값이 없으면 찍히지 않는다');

    probe.start();
    standStill(probe, fromMs: 0, altitudeM: 0);
    expect(probe.sampleCount, greaterThan(0));
  });

  test('내보낸 JSON에 원시 샘플이 통째로 남는다', () {
    // 이 도구의 존재 이유다 — 지금 고른 평활·문턱이 틀린 것으로 밝혀져도
    // 같은 파일로 다시 계산할 수 있어야 한다.
    final probe = ElevatorAltitudeProbe()..start();
    standStill(probe, fromMs: 0, altitudeM: 0);
    probe.mark('1F');

    final json = probe.buildJson(
      buildingId: 'thehyundai-seoul',
      altimeter: const AltimeterStatus(
        available: true,
        source: 'android_pressure',
      ),
    );

    expect(json['schema'], 'elevator_altitude_probe_v1');
    expect(json['building_id'], 'thehyundai-seoul');
    expect((json['marks']! as List).length, 1);
    expect(
      (json['samples']! as List).length,
      probe.sampleCount,
      reason: '샘플을 솎아내면 사후 재계산이 막힌다',
    );
  });

  test('초기화하면 점도 샘플도 남지 않는다', () {
    final probe = ElevatorAltitudeProbe()..start();
    standStill(probe, fromMs: 0, altitudeM: 0);
    probe.mark('1F');

    probe.reset();

    expect(probe.marks, isEmpty);
    expect(probe.sampleCount, 0);
    expect(probe.isRecording, isFalse);
  });
}
