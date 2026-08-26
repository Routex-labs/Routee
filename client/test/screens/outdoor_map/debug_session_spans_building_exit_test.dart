import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:navigation_client/screens/outdoor_map/widgets/floor_selector.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/entry_floor_prompt_helper.dart';

/// **실내→실외→실내 한 주행이 JSON 하나로 남는다(디버그 모드).**
///
/// 실측 시나리오: B2 매장에서 출발해 에스컬레이터로 올라와 문 밖으로 나갔다가
/// 다시 들어온다. 15~20분짜리 한 번의 주행이라 파일도 하나여야 하는데, 예전에는
/// GPS 이탈이 PDR 세션을 끄고([_dropIndoorPosition]) 재진입 뒤 새 길찾기가
/// 레코더를 통째로 갈아 끼워([_beginRouteRecordingSession]) 나갈 때 걸은 구간이
/// 사라졌다.
///
/// 가르는 것은 **레코더 인스턴스가 같은가**다. 경계 문자열만 보면 새 레코더가
/// 우연히 같은 값을 갖는 경우를 못 잡는다.
///
/// 일반 사용자(디버그 꺼짐)에게는 예전 동작 그대로여야 하므로 그쪽도 함께 건다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  final testBuildingRepository = MockBuildingRepository();

  Position at(double longitude) => Position(
    latitude: 37.5665,
    longitude: longitude,
    timestamp: DateTime(2024, 1, 1),
    accuracy: 10,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  // 건물 외곽선 안쪽. reentry_floor_reset_test와 같은 좌표다.
  Position atEntrance() => at(126.9779);

  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await debugModeController.reload();
    originalBuildingRepository = buildingRepository;
    originalDestinationRepository = destinationRepository;
    buildingRepository = testBuildingRepository;
    destinationRepository = MockDestinationRepository(testBuildingRepository);
    requestStartupPermissions = () async => {};
    await testBuildingRepository.getAllBuildings();
  });

  tearDown(() async {
    await debugModeController.setEnabled(false);
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    requestStartupPermissions = defaultRequestStartupPermissions;
    watchPosition = defaultWatchPosition;
  });

  /// 앱을 건물 안에서 켜서 실내로 들어가고, 진단 세션을 연다.
  ///
  /// 밖 좌표를 안 주는 것이 요점이다 — 좌표가 화면을 실내로 바꾸는 남은 유일한
  /// 갈래다(`indoor-entry-rules.md` 6절). 나가고 다시 들어오는 것은 아래 각
  /// 테스트가 **버튼이 부르는 함수**로 직접 한다.
  Future<OutdoorMapBodyState> launchInsideAndRecord(WidgetTester tester) async {
    final positions = StreamController<Position>.broadcast();
    addTearDown(positions.close);
    watchPosition = () => positions.stream;
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await drain(tester);
    positions.add(atEntrance());
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);
    await dismissEntryFloorPrompt(tester);
    await drain(tester);
    expect(
      find.byType(FloorSelector),
      findsOneWidget,
      reason: '테스트 전제(실내에서 앱을 켠 진입)가 성립하지 않았다',
    );
    final state = tester.state<OutdoorMapBodyState>(
      find.byType(OutdoorMapBody),
    );
    // ignore: invalid_use_of_visible_for_testing_member
    state.beginRouteRecordingSessionForTest();
    return state;
  }

  /// 「밖으로 나가기」와 건물 탭이 부르는 것과 같은 함수를 직접 굴린다.
  Future<void> leaveAndReEnter(
    WidgetTester tester,
    OutdoorMapBodyState state, {
    required Future<void> Function() between,
  }) async {
    state.exitIndoorFromGuidance();
    await drain(tester);
    await between();
    // ignore: invalid_use_of_visible_for_testing_member
    state.enterIndoorForTest();
    await drain(tester);
  }

  testWidgets('디버그 모드: 나갔다 들어와도 같은 레코더가 이어진다', (tester) async {
    await debugModeController.setEnabled(true);
    final state = await launchInsideAndRecord(tester);
    // ignore: invalid_use_of_visible_for_testing_member
    final opened = state.debugRecorderForTest!;

    await leaveAndReEnter(
      tester,
      state,
      between: () async {
        // ignore: invalid_use_of_visible_for_testing_member
        expect(identical(state.debugRecorderForTest, opened), isTrue);
        expect(opened.spansBuildingExit, isTrue);
      },
    );

    // 재진입 뒤 새 길찾기를 시작해도 갈아 끼우지 않는다 — 여기가 예전에 나갈 때
    // 걸은 구간을 통째로 잃던 자리다.
    // ignore: invalid_use_of_visible_for_testing_member
    state.beginRouteRecordingSessionForTest();
    // ignore: invalid_use_of_visible_for_testing_member
    expect(identical(state.debugRecorderForTest, opened), isTrue);

    final boundaries =
        (opened.buildJson(
                  buildingId: 'b',
                  selectedFloor: state.currentFloor,
                  mapCalibrationVersion: 'v1',
                  graph: null,
                  device: const {},
                )['session_boundaries']!
                as List<Object?>)
            .cast<Map<String, Object?>>()
            .map((b) => b['boundary'])
            .toList();
    expect(boundaries, contains('leftBuilding'));
    expect(boundaries, contains('reEntered'));
    expect(boundaries.last, 'routeStartedAfterReEntry');
  });

  testWidgets('디버그가 꺼져 있으면 예전대로 새 세션으로 갈아 끼운다', (tester) async {
    final state = await launchInsideAndRecord(tester);
    // ignore: invalid_use_of_visible_for_testing_member
    final opened = state.debugRecorderForTest!;

    await leaveAndReEnter(
      tester,
      state,
      between: () async => expect(opened.spansBuildingExit, isFalse),
    );

    // ignore: invalid_use_of_visible_for_testing_member
    state.beginRouteRecordingSessionForTest();
    // ignore: invalid_use_of_visible_for_testing_member
    expect(identical(state.debugRecorderForTest, opened), isFalse);
  });
}
