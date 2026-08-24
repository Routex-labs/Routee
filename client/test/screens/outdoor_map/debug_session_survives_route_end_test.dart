import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/features/indoor_navigation/debug/pdr_debug_session_recorder.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **안내가 끝나도(routeEnded) 실측 세션은 안 닫힌다(디버그 모드).**
///
/// 실측이 잘리던 자리다. 문 앞에서 안내가 끝나면 `routeEnded`가 찍히고, 밖에서
/// 다시 길을 잡는 순간 새 레코더가 열려 그 앞이 통째로 사라졌다 — 정작 보려던
/// 것(문 밖 GPS 표류, 길 건너에서 시작하는 경로, 재진입 뒤 마커)은 전부 그
/// 다음에 일어난다.
///
/// 가르는 것은 [debug_session_spans_building_exit_test]와 같다 — **레코더
/// 인스턴스가 같은가.** 경계 문자열만 보면 새 레코더가 우연히 같은 값을 갖는
/// 경우를 못 잡는다.
///
/// 닫는 것은 내보내기 하나뿐이라, 그쪽도 함께 건다. 디버그가 꺼진 일반
/// 사용자는 예전대로 **길안내 한 건이 세션 하나**여야 한다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  final testBuildingRepository = MockBuildingRepository();

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
  });

  /// 화면을 띄우고 진단 세션을 하나 연다. 여기서는 GPS로 실내에 들어갈 필요가
  /// 없다 — 세션 경계 판정은 실내 상태를 보지 않는다.
  Future<OutdoorMapBodyState> openSession(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final state = tester.state<OutdoorMapBodyState>(
      find.byType(OutdoorMapBody),
    );
    // ignore: invalid_use_of_visible_for_testing_member
    state.beginRouteRecordingSessionForTest();
    return state;
  }

  List<Object?> boundariesOf(
    OutdoorMapBodyState state,
    PdrDebugSessionRecorder recorder,
  ) => (recorder.buildJson(
            buildingId: 'b',
            selectedFloor: state.currentFloor,
            mapCalibrationVersion: 'v1',
            graph: null,
            device: const <String, Object?>{},
          )['session_boundaries']!
          as List<Object?>)
      .cast<Map<String, Object?>>()
      .map((b) => b['boundary'])
      .toList();

  testWidgets('디버그 모드: routeEnded 뒤 새 길찾기도 같은 레코더에 이어진다', (
    tester,
  ) async {
    await debugModeController.setEnabled(true);
    final state = await openSession(tester);
    // ignore: invalid_use_of_visible_for_testing_member
    final opened = state.debugRecorderForTest;
    expect(opened, isNotNull, reason: '테스트 전제(진단 세션 열림)가 성립하지 않았다');

    // ignore: invalid_use_of_visible_for_testing_member
    state.endRouteRecordingSessionForTest();
    // ignore: invalid_use_of_visible_for_testing_member
    state.beginRouteRecordingSessionForTest();

    // ignore: invalid_use_of_visible_for_testing_member
    expect(identical(state.debugRecorderForTest, opened), isTrue);
    // 경계는 그대로 남는다 — 사후에 구간을 가르는 유일한 근거다.
    expect(boundariesOf(state, opened!), ['routeEnded', 'routeStarted']);
  });

  testWidgets('디버그 모드: 내보내기가 세션을 닫고 새 세션을 연다', (tester) async {
    await debugModeController.setEnabled(true);
    final state = await openSession(tester);
    // ignore: invalid_use_of_visible_for_testing_member
    final opened = state.debugRecorderForTest;

    // ignore: invalid_use_of_visible_for_testing_member
    state.rotateRecordingSessionAfterExport();
    await tester.pump();

    // ignore: invalid_use_of_visible_for_testing_member
    expect(identical(state.debugRecorderForTest, opened), isFalse);
    // 새 세션이 열렸다는 것이 사용자에게 읽혀야 한다. 안 말하면 방금 내보낸
    // 파일에 다음 걸음이 이어 붙는 줄 알고 계속 걷는다.
    expect(find.textContaining('새 세션'), findsOneWidget);
  });

  testWidgets('디버그가 꺼져 있으면 routeEnded가 예전대로 세션을 닫는다', (tester) async {
    final state = await openSession(tester);
    // ignore: invalid_use_of_visible_for_testing_member
    final opened = state.debugRecorderForTest;
    expect(opened, isNotNull, reason: '테스트 전제(진단 세션 열림)가 성립하지 않았다');

    // ignore: invalid_use_of_visible_for_testing_member
    state.endRouteRecordingSessionForTest();
    // ignore: invalid_use_of_visible_for_testing_member
    state.beginRouteRecordingSessionForTest();

    // ignore: invalid_use_of_visible_for_testing_member
    expect(identical(state.debugRecorderForTest, opened), isFalse);
  });
}
