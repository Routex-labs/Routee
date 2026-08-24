import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:navigation_client/screens/outdoor_map/widgets/floor_selector.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/entry_floor_prompt_helper.dart';

/// **GPS는 건물 안이라는 것까지만 말한다.** 층은 말하지 않는다.
///
/// 그대로 두면 활성 층이 건물의 `default_floor`(1F)로 굳어, B2에 서 있는 사람의
/// 위치와 경로가 1층에 찍힌다 — 화면에는 "그럴듯한 1층 지도"로만 보여서 틀렸다는
/// 신호가 어디에도 없다.
///
/// **묻는 것은 앱을 건물 안에서 켰을 때뿐이다.** 걸어 들어온 사람에게는 문을
/// 통과한 층이 곧 답이고, 그 순간에는 전환 연출이 뜬다 — 거기에 시트까지 겹치면
/// 덮개 위로 모달이 올라온다(`docs/client/indoor-transition-choreography.md` 6절).
///
/// 지금 층은 층 선택기([FloorSelector.selectedFloor])로 읽는다 — 화면이 실제로
/// 그리는 값이라, 내부 상태만 바뀌고 도면은 그대로인 반쪽 성공을 잡아낸다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  final testBuildingRepository = MockBuildingRepository();

  // 데모 건물 입구(37.5665, 126.9779) 위 + 신호 양호. 외곽선 안쪽 5m를 넘어야
  // '들어왔다'가 되므로(indoorEnterInsetMeters) 이 좌표가 진입 근거다.
  Position atEntrance() => Position(
    latitude: 37.5665,
    longitude: 126.9779,
    timestamp: DateTime(2024, 1, 1),
    accuracy: 10,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  // 외곽선에서 확실히 밖. 첫 좌표는 반드시 밖이어야 한다 — 건물 외곽선은 asset
  // 로드가 끝난 뒤에야 채워지므로, 안쪽 좌표를 첫 이벤트로 흘리면 판정할 도형이
  // 아직 없어 진입이 일어나지 않는다.
  Position farAway() => Position(
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

  tearDown(() {
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    requestStartupPermissions = defaultRequestStartupPermissions;
    watchPosition = defaultWatchPosition;
  });

  /// **앱을 건물 안에서 켠다.** 밖 좌표를 한 번도 주지 않는 것이 요점이다 —
  /// 그것이 "처음부터 안에 있었다"의 근거다([_sawOutsideSinceLaunch]).
  /// 층 질문이 뜬 채로 돌아온다.
  Future<StreamController<Position>> launchInside(WidgetTester tester) async {
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
    return positions;
  }

  /// 밖 → 안 순서로 좌표를 흘려 **걸어 들어온** 진입을 만든다. 이쪽은 묻지 않는다.
  Future<StreamController<Position>> walkIn(WidgetTester tester) async {
    final positions = StreamController<Position>.broadcast();
    addTearDown(positions.close);
    watchPosition = () => positions.stream;
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await drain(tester);
    positions.add(farAway());
    await tester.pump(const Duration(milliseconds: 50));
    positions.add(atEntrance());
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);
    await tester.pump();
    return positions;
  }

  /// 시작 덮개는 **최소 1.2초**를 채운다. 그 전에 층 질문이 올라오면 로고가
  /// 한 프레임 번쩍이고 사라진다.
  testWidgets('시작 후 1.2초 전에는 층 질문이 로고를 덮지 않는다', (tester) async {
    final positions = StreamController<Position>.broadcast();
    addTearDown(positions.close);
    watchPosition = () => positions.stream;
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await drain(tester);

    positions.add(atEntrance());
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const Key('startup-loading-overlay')), findsOneWidget);
    expect(find.text('몇 층에 계신가요?'), findsNothing);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.text('몇 층에 계신가요?'), findsOneWidget);
    expect(
      find.byKey(const Key('entry-floor-transition-background')),
      findsOneWidget,
    );
  });

  testWidgets('앱을 건물 안에서 켜면 몇 층인지 묻는다', (tester) async {
    await launchInside(tester);

    expect(find.text('몇 층에 계신가요?'), findsOneWidget);
    // 기본 지도는 아직 준비 과정이므로 질문 화면 뒤에서 시작 덮개가 계속 가린다.
    expect(find.byKey(const Key('startup-loading-overlay')), findsOneWidget);
    expect(find.text('건물 감지 중...'), findsNothing);
    // 층은 엘리베이터 버튼판 순서 그대로 전부 고를 수 있어야 한다.
    expect(find.byKey(const ValueKey('entry-floor-2F')), findsOneWidget);
    expect(find.byKey(const ValueKey('entry-floor-1F')), findsOneWidget);
  });

  testWidgets('고른 층이 곧 지금 보고 있는 층이 된다', (tester) async {
    await launchInside(tester);
    // 묻기 전 기본값은 건물의 default_floor(1F)다. 이 값이 바뀌지 않는 것이
    // 원래 증상이었다.
    expect(
      tester.widget<FloorSelector>(find.byType(FloorSelector)).selectedFloor,
      '1F',
    );

    await answerEntryFloorPrompt(tester, '2F');
    await drain(tester);

    expect(
      tester.widget<FloorSelector>(find.byType(FloorSelector)).selectedFloor,
      '2F',
    );
    expect(find.byKey(const Key('startup-loading-overlay')), findsNothing);
  });

  testWidgets('위치를 끝내 받지 못해도 시작 덮개에 갇히지 않는다', (tester) async {
    watchPosition = () => const Stream<Position>.empty();
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );

    expect(find.byKey(const Key('startup-loading-overlay')), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('startup-loading-overlay')), findsNothing);
  });

  testWidgets('건너뛰면 기본 층 그대로 두고 지도로 돌아간다', (tester) async {
    await launchInside(tester);

    await dismissEntryFloorPrompt(tester);
    await drain(tester);

    expect(find.text('몇 층에 계신가요?'), findsNothing);
    expect(
      tester.widget<FloorSelector>(find.byType(FloorSelector)).selectedFloor,
      '1F',
    );
  });

  // 벽 근처에서는 판정이 안팎을 오간다. 진입마다 물으면 이 화면이 되풀이해 떠
  // 지도에 닿을 수가 없다.
  testWidgets('건물을 나가지 않는 한 다시 묻지 않는다', (tester) async {
    final positions = await launchInside(tester);
    await dismissEntryFloorPrompt(tester);
    await drain(tester);
    expect(find.text('몇 층에 계신가요?'), findsNothing);

    // 같은 자리에서 좌표가 한 번 더 온다.
    positions.add(atEntrance());
    await drain(tester);

    expect(find.text('몇 층에 계신가요?'), findsNothing);
  });

  // 걸어 들어온 사람에게는 묻지 않는다. 문을 통과한 층이 곧 답이고, 그 순간에는
  // 전환 연출(문+문구)이 화면을 덮고 있어 시트가 그 위로 올라온다.
  testWidgets('걸어 들어오면 묻지 않는다', (tester) async {
    await walkIn(tester);

    expect(find.text('몇 층에 계신가요?'), findsNothing);
  });
}
