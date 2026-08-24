/// 진입 직후 **위치 마커가 통째로 사라지던 구간**의 검증 기준.
///
/// 증상: 진입 판정은 맞는데(정확도 6m · 안쪽 7.6m · inside) 화면에 위치가 하나도
/// 없다. 야외 GPS 마커는 `_indoorEntered`가 켜지는 순간 꺼지는데 실내 마커는
/// 앵커를 찍고 보정이 수렴해야 나와서, 두 마커의 수명이 겹치지 않고 벌어져 있었다
/// (실측 25초).
///
/// 여기서 확인하는 것 둘:
///   - [indoorMarkerAt]이 그 공백을 GPS 좌표로 메우고, 실내 위치가 생기는 순간
///     즉시 밀려난다. 점을 **하나만** 돌려주므로 둘이 동시에 뜰 수 없다.
///   - 레코더가 그 공백의 길이를 남긴다(`indoor_position_gaps`).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:navigation_client/features/indoor_navigation/debug/pdr_debug_session_recorder.dart';
import 'package:navigation_client/screens/outdoor_map/layers/marker_map_layers.dart';

const _indoor = ll.LatLng(37.5001, 126.9001);
const _lastKnown = ll.LatLng(37.5002, 126.9002);
const _gps = ll.LatLng(37.5003, 126.9003);

void main() {
  group('indoorMarkerAt', () {
    test('실내 위치가 있으면 그것만 쓰고 흐리게 그리지 않는다', () {
      final marker = indoorMarkerAt(
        indoorPoint: _indoor,
        offFloorPoint: _lastKnown,
        gpsFallback: _gps,
      );
      expect(marker?.point, _indoor);
      expect(marker?.offFloor, isFalse);
    });

    test('실내 위치가 없고 앵커가 다른 층이면 그 층 마지막 자리를 흐리게', () {
      final marker = indoorMarkerAt(offFloorPoint: _lastKnown, gpsFallback: _gps);
      expect(marker?.point, _lastKnown);
      expect(marker?.offFloor, isTrue);
    });

    test('진입 직후 공백 — 둘 다 없으면 GPS가 자리를 지킨다', () {
      final marker = indoorMarkerAt(gpsFallback: _gps);
      expect(marker?.point, _gps);
      // 건물 밖에서 찍힌 좌표라 도면 위 자리는 틀릴 수 있다. 흐리게 그려야
      // 사용자가 이것을 실내 위치로 읽지 않는다.
      expect(marker?.offFloor, isTrue);
    });

    test('실내 위치가 생기는 순간 GPS 폴백은 밀려난다', () {
      final before = indoorMarkerAt(gpsFallback: _gps);
      final after = indoorMarkerAt(indoorPoint: _indoor, gpsFallback: _gps);
      expect(before?.point, _gps);
      expect(after?.point, _indoor);
    });

    test('아무 근거도 없으면 null — 야외에서는 이 소스가 비어 있어야 한다', () {
      expect(indoorMarkerAt(), isNull);
    });
  });

  group('indoor_position_gaps', () {
    test('진입부터 첫 position_source까지의 공백을 ms로 남긴다', () {
      final recorder = PdrDebugSessionRecorder(
        startedAt: DateTime.utc(2026, 8, 20, 9),
      );
      recorder.recordIndoorStateChange(
        entered: true,
        source: 'gps',
        floorId: '1F',
        at: DateTime.utc(2026, 8, 20, 9, 0, 10),
      );
      // 진입 직후 몇 초는 실내 위치가 없다 — 화면이 비어 있던 그 구간이다.
      recorder.recordGpsPositionDelta(
        distanceM: null,
        gpsAccuracyM: 6,
        metersOutsideM: -7.6,
        positionSource: null,
        verdict: 'inside',
        floorId: '1F',
        indoorEntered: true,
        at: DateTime.utc(2026, 8, 20, 9, 0, 20),
      );
      recorder.recordGpsPositionDelta(
        distanceM: 4,
        gpsAccuracyM: 6,
        metersOutsideM: -7.6,
        positionSource: 'anchorOnly',
        verdict: 'inside',
        floorId: '1F',
        indoorEntered: true,
        at: DateTime.utc(2026, 8, 20, 9, 0, 35),
      );

      final gaps = _gaps(recorder);
      expect(gaps, hasLength(1));
      expect(gaps.single['gap_ms'], 25000);
      expect(gaps.single['floor_id'], '1F');
    });

    test('위치가 이어지는 동안에는 더 쌓지 않는다 — 진입 한 번에 한 건', () {
      final recorder = PdrDebugSessionRecorder(
        startedAt: DateTime.utc(2026, 8, 20, 9),
      );
      recorder.recordIndoorStateChange(
        entered: true,
        source: 'gps',
        at: DateTime.utc(2026, 8, 20, 9, 0, 10),
      );
      for (var i = 1; i <= 3; i++) {
        recorder.recordGpsPositionDelta(
          distanceM: 4,
          gpsAccuracyM: 6,
          metersOutsideM: -7.6,
          positionSource: 'tracked',
          verdict: 'inside',
          floorId: '1F',
          indoorEntered: true,
          at: DateTime.utc(2026, 8, 20, 9, 0, 10 + i),
        );
      }
      expect(_gaps(recorder), hasLength(1));
    });

    test('나갔다 다시 들어오면 공백을 새로 잰다', () {
      final recorder = PdrDebugSessionRecorder(
        startedAt: DateTime.utc(2026, 8, 20, 9),
      );
      recorder.recordIndoorStateChange(
        entered: true,
        source: 'gps',
        at: DateTime.utc(2026, 8, 20, 9, 0, 0),
      );
      recorder.recordGpsPositionDelta(
        distanceM: 4,
        gpsAccuracyM: 6,
        metersOutsideM: -7.6,
        positionSource: 'tracked',
        verdict: 'inside',
        floorId: '1F',
        indoorEntered: true,
        at: DateTime.utc(2026, 8, 20, 9, 0, 5),
      );
      recorder.recordIndoorStateChange(
        entered: false,
        source: 'gps',
        at: DateTime.utc(2026, 8, 20, 9, 1, 0),
      );
      recorder.recordIndoorStateChange(
        entered: true,
        source: 'gps',
        at: DateTime.utc(2026, 8, 20, 9, 2, 0),
      );
      recorder.recordGpsPositionDelta(
        distanceM: 4,
        gpsAccuracyM: 6,
        metersOutsideM: -7.6,
        positionSource: 'tracked',
        verdict: 'inside',
        floorId: '2F',
        indoorEntered: true,
        at: DateTime.utc(2026, 8, 20, 9, 2, 8),
      );

      final gaps = _gaps(recorder);
      expect(gaps.map((g) => g['gap_ms']), [5000, 8000]);
    });

    test('나간 뒤의 좌표는 공백을 열지 않는다 — 실외 구간을 삼키면 안 된다', () {
      final recorder = PdrDebugSessionRecorder(
        startedAt: DateTime.utc(2026, 8, 20, 9),
      );
      recorder.recordIndoorStateChange(
        entered: false,
        source: 'gps',
        at: DateTime.utc(2026, 8, 20, 9, 0, 0),
      );
      recorder.recordGpsPositionDelta(
        distanceM: null,
        gpsAccuracyM: 6,
        metersOutsideM: 12,
        positionSource: 'tracked',
        verdict: 'outside',
        floorId: null,
        indoorEntered: false,
        at: DateTime.utc(2026, 8, 20, 9, 0, 30),
      );
      expect(_gaps(recorder), isEmpty);
    });
  });
}

List<Map<String, Object?>> _gaps(PdrDebugSessionRecorder recorder) {
  final json = recorder.buildJson(
    buildingId: 'thehyundai-seoul',
    selectedFloor: '1F',
    mapCalibrationVersion: 'test',
    graph: null,
    device: const {'device_name': 'Test device'},
    exportedAt: DateTime.utc(2026, 8, 20, 9, 5),
  );
  return (json['indoor_position_gaps']! as List<Object?>)
      .cast<Map<String, Object?>>();
}
