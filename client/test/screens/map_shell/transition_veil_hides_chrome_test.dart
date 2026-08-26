import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:navigation_client/screens/map_shell/widgets/chrome/map_tab_bar.dart';
import 'package:navigation_client/screens/map_shell/widgets/chrome/map_top_bar.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:navigation_client/screens/outdoor_map/transition/indoor_transition_overlay.dart';
import 'package:navigation_client/screens/outdoor_map/transition/indoor_transition_timeline.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 실내↔야외 전환 덮개가 **화면의 맨 위**여야 한다는 계약.
///
/// 덮개는 지도 안에서 그리는데 셸 chrome(검색창·길찾기 바·탭 줄)은 그 지도의
/// 형제다. z축으로는 이길 수 없어서, 실기기에서 「밖으로 나가기」를 누르면 덮개
/// 위에 출발지/도착지 칸이 그대로 떠 있었다 — 화면이 갈리는 순간을 가리는 것이
/// 이 연출의 존재 이유인데 정작 가려야 할 것이 위에 있었다.
///
/// 그래서 **덮는 대신 그리지 않는다**. 지도가 덮개 불투명도를 셸에 알리고
/// (`OutdoorMapBody.onIndoorTransitionVeilChanged`) 셸이 그동안 chrome을 트리에서
/// 뺀다. 층 전환 스크림과 같은 구조다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  final repository = MockBuildingRepository();

  /// 건물 **밖** 좌표. 안이면 "앱을 실내에서 켰다"로 읽혀 화면이 스스로 실내로
  /// 들어가고, 층 질문 시트가 이 테스트의 chrome 판정에 끼어든다.
  Position outside() => Position(
    latitude: 37.5665,
    longitude: 126.9800,
    timestamp: DateTime(2024, 1, 1),
    accuracy: 10,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// 지금 덮개가 얼마나 짙은지. 위젯은 늘 트리에 있고 진행률 0에서 스스로 빈
  /// 위젯이 되므로, 존재 여부로는 연출 중인지 알 수 없다.
  double veilOpacityOf(WidgetTester tester) => indoorTransitionFrameAt(
    tester
        .widget<IndoorTransitionOverlay>(find.byType(IndoorTransitionOverlay))
        .progress,
  ).veilOpacity;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await debugModeController.reload();
    originalBuildingRepository = buildingRepository;
    originalDestinationRepository = destinationRepository;
    buildingRepository = repository;
    destinationRepository = MockDestinationRepository(repository);
    requestStartupPermissions = () async => {};
    await repository.getAllBuildings();
  });

  tearDown(() {
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    requestStartupPermissions = defaultRequestStartupPermissions;
    watchPosition = defaultWatchPosition;
  });

  /// 도면을 편 셸. 실내로 들어가는 것 자체는 이 파일의 관심이 아니라, 나가기가
  /// 부르는 함수와 같은 자리를 쓰는 테스트 훅으로 켠다.
  Future<OutdoorMapBodyState> pumpIndoorShell(WidgetTester tester) async {
    final positions = StreamController<Position>.broadcast();
    addTearDown(positions.close);
    watchPosition = () => positions.stream;
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await drain(tester);
    positions.add(outside());
    await drain(tester);

    final state = tester.state<OutdoorMapBodyState>(
      find.byType(OutdoorMapBody),
    );
    // ignore: invalid_use_of_visible_for_testing_member
    state.enterIndoorForTest();
    await drain(tester);
    return state;
  }

  testWidgets('나가기 연출이 덮는 동안 셸 chrome은 트리에 없다', (tester) async {
    final state = await pumpIndoorShell(tester);
    expect(
      find.byType(MapTopBar),
      findsOneWidget,
      reason: '테스트 전제(연출 전에는 검색창이 있다)가 성립하지 않았다',
    );

    state.exitIndoorFromGuidance();
    // **첫 pump는 ticker를 세우는 프레임이다**(진행률 0). 두 번째 pump부터
    // 시계가 흐른다 — 한 번만 부르면 덮개가 아직 투명해 이 테스트가 늘 실패한다.
    await tester.pump();
    // 덮개는 연출 앞머리에서 오른다([indoorTransitionVeilIn]) — 1.8초 연출의
    // 14%라 250ms면 이미 짙다.
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      veilOpacityOf(tester),
      greaterThan(0),
      reason: '테스트 전제(덮개가 짙어졌다)가 성립하지 않았다',
    );
    expect(
      find.byType(MapTopBar),
      findsNothing,
      reason: '검색창·길찾기 바가 덮개 위에 남으면 가리려던 것이 그대로 보인다',
    );
    expect(find.byType(MapTabBar), findsNothing);

    // 연출이 끝나면 되돌아온다. 안 되돌아오면 나간 사용자가 검색도 못 한다.
    await tester.pump(const Duration(seconds: 2));
    await drain(tester);
    expect(find.byType(MapTopBar), findsOneWidget);
    expect(find.byType(MapTabBar), findsOneWidget);
  });

  testWidgets('연출이 없으면 chrome을 건드리지 않는다', (tester) async {
    // 도면만 접는 조작(홈 버튼)은 전환이 아니라 연출이 없다. 여기서 chrome이
    // 사라지면 "왜 검색창이 깜빡이지"가 된다.
    final state = await pumpIndoorShell(tester);

    await state.returnToOutdoorView();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(veilOpacityOf(tester), 0);
    expect(find.byType(MapTopBar), findsOneWidget);
    expect(find.byType(MapTabBar), findsOneWidget);
  });
}
