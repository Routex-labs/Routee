import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/entry_floor_prompt_helper.dart';

import 'package:navigation_client/theme/app_theme.dart';
import 'package:routex_design_system/routex_design_system.dart';
import 'package:navigation_client/app.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/models/place/discovery_result.dart';
import 'package:navigation_client/models/place/poi_search_result.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:navigation_client/screens/outdoor_map/widgets/floor_selector.dart';

// 데모 건물 입구(37.5665, 126.9779)에서 약 185m 떨어진 좌표.
// 자동 건물 진입 감지(반경 50m)에 걸리지 않도록 충분히 멀리 둔다.
final _fakePosition = Position(
  latitude: 37.5665,
  longitude: 126.9800,
  timestamp: DateTime(2024, 1, 1),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

final _fakeLowAccuracyPosition = Position(
  latitude: 37.5665,
  longitude: 126.9800,
  timestamp: DateTime(2024, 1, 1),
  accuracy: 100,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

// 자동 진입 감지 테스트용 두 건. 판정은 **한 건으로 성립하지 않는다** —
// "신호가 멀쩡했을 때 입구 앞에 있었다"는 근거가 창 안에 있어야 하므로, 접근
// 표본(양호)과 진입 표본(저하)을 순서대로 흘려야 한다. 근거 없이 저하 한 건만
// 오는 경우는 판정하지 않는 것이 이 정책의 규칙이다.
final _fakePositionApproachingEntrance = Position(
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

// 데모 건물 입구와 정확히 같은 좌표 + 신호 저하. accuracy가 '무너졌다' 기준
// (30m)을 넘어야 진입으로 읽힌다.
final _fakePositionAtEntrance = Position(
  latitude: 37.5665,
  longitude: 126.9779,
  timestamp: DateTime(2024, 1, 1),
  accuracy: 45,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

void main() {
  final originalBuildingRepository = buildingRepository;
  final originalDestinationRepository = destinationRepository;
  final testBuildingRepository = MockBuildingRepository();

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    // debugModeController는 service_locator의 전역이라 이 파일의 모든 테스트가
    // 같은 인스턴스를 공유한다. mock을 비운 뒤 다시 읽어, 앞 테스트가 켜 둔
    // 디버그 모드가 뒤 테스트로 새지 않게 한다.
    await debugModeController.reload();
    // 실제 permission_handler/geolocator 플러그인 채널이 없는 테스트 환경에서
    // 멈추지 않도록 즉시 완료되는 가짜 함수로 교체한다.
    requestStartupPermissions = () async => {};
    watchPosition = () => Stream.value(_fakePosition);

    // 네트워크가 없는 테스트 환경에서는 HttpBuildingRepository(운영 기본값)
    // 대신 asset 기반 MockBuildingRepository로 교체해 결정적으로 검증한다.
    // 테스트마다 새로 만들지 않고 파일 전체에서 하나를 공유한다.
    buildingRepository = testBuildingRepository;
    destinationRepository = MockDestinationRepository(buildingRepository);

    // 야외 지도가 MapLibre로 이관된 뒤에는 배경 타일 fake provider가 필요 없다.
    // 위젯 테스트 환경(TargetPlatform.android)에서는 MapLibreMap이 PlatformView
    // 를 만들지만 실제 렌더링은 안 되고 네트워크 요청도 뜨지 않는다.
  });

  tearDown(() {
    requestStartupPermissions = defaultRequestStartupPermissions;
    watchPosition = defaultWatchPosition;
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
  });

  testWidgets('app opens directly into the outdoor (home) map shell', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const NavigationApp());
    // 지도 타일은 네트워크 이미지라 pumpAndSettle을 쓰면 무한정 기다릴 수 있으니
    // 위치 조회가 끝날 만큼만 프레임을 진행한다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    // 야외 시야로 시작했는지는 **층 선택기가 없다는 것**으로 확인한다. 예전에는
    // 하단 홈/실내 세그먼트로 봤는데, 실내가 별도 탭이 아니게 되면서 그 세그먼트
    // 자체가 사라졌다 — 건물에 들어가면 오버레이가 열리고 나오면 닫힌다.
    //
    // 상단 햄버거는 모드 신호가 아니다. 항상 보이는 앱 메뉴다.
    expect(find.byType(FloorSelector), findsNothing);
    expect(find.byTooltip('메뉴'), findsOneWidget);
  });

  testWidgets('outdoor map body renders map after position arrives', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const OutdoorMapBody()),
    );

    // OutdoorMapBody는 위치 신호를 기다리는 동안에도 지도를 그리며,
    // 로딩 스피너로 화면을 가리지 않는다. 첫 pump가 끝나면 fake 스트림이
    // 첫 위치를 흘려주므로 곧바로 위치 마커가 보여야 한다.
    await tester.pump();

    // MapLibre 이관 이후에는 현재 위치 마커가 지도 내부(CircleLayer)에 렌더돼
    // Flutter 위젯 트리에서 찾을 수 없다. 로딩 인디케이터가 사라지고
    // OutdoorMapBody가 body 상태로 넘어갔는지, 신호가 양호할 때 경고 배지가
    // 안 뜨는지로 정상 렌더링을 갈음한다.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(OutdoorMapBody), findsOneWidget);
    expect(find.text('GPS 신호 약함'), findsNothing);
  });

  testWidgets('outdoor map shows a low-accuracy warning badge', (
    WidgetTester tester,
  ) async {
    watchPosition = () => Stream.value(_fakeLowAccuracyPosition);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const OutdoorMapBody()),
    );
    await tester.pump();

    expect(find.text('GPS 신호 약함'), findsOneWidget);
  });

  // 포팅 가이드 단계 2 통과 기준: "GPS 약함은 낮은 강도의 Badge 또는 미표시이며
  // 경로 이탈보다 강하지 않다". 강도와 **행동 없음**을 여기서 못 박는다.
  testWidgets('GPS 약함은 누를 수 없는 낮은 강도의 배지다', (WidgetTester tester) async {
    watchPosition = () => Stream.value(_fakeLowAccuracyPosition);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const OutdoorMapBody()),
    );
    await tester.pump();

    final badge = tester.widget<RoutexBadge>(
      find.ancestor(
        of: find.text('GPS 신호 약함'),
        matching: find.byType(RoutexBadge),
      ),
    );
    expect(badge.tone, RoutexBadgeTone.warning);
    // 지도 위에 홀로 떠 있으므로 깊이는 갖는다(없으면 지도의 일부로 읽힌다).
    expect(badge.surface, RoutexBadgeSurface.onMap);

    // **누를 수 없다.** 사용자가 할 수 있는 일이 없는 상태라 행동을 붙이지
    // 않는다. 붙이면 건물 로드 실패 알림("다시 시도")과 구분되지 않는다.
    expect(
      find.ancestor(of: find.text('GPS 신호 약함'), matching: find.byType(InkWell)),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: find.text('GPS 신호 약함'),
        matching: find.byType(GestureDetector),
      ),
      findsNothing,
    );

    // 경로 이탈보다 약하다. 이탈은 error 색을 쓰고([EtaCard]의 wrong-way),
    // 이 배지는 같은 색이 아니라 **연한 warning 배경**을 쓴다.
    const colors = RoutexColorTokens.light;
    final box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(RoutexBadge),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.color, colors.statusWarningSubtle);
    expect(decoration.color, isNot(colors.statusError));
    expect(decoration.color, isNot(colors.statusWarning));
  });

  testWidgets(
    'map shell shows the indoor entry overlay when entrance is detected nearby',
    (WidgetTester tester) async {
      watchPosition = () => Stream.fromIterable([
        _fakePositionApproachingEntrance,
        _fakePositionAtEntrance,
      ]);

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
      );

      // 접근 표본 → 진입 표본 순으로 흘러야 판정이 서므로, 두 건이 모두 도착할
      // 때까지 프레임을 진행한다.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      // 자동 진입은 '건물 감지 중...'을 먼저 띄운 뒤, 입구 기준으로 실내 위치를
      // 잡는 작업이 끝나면 같은 자리에 결과를 덮어쓴다(진행 문구가 4초를 다
      // 채운 뒤에야 결과가 뜨면 이미 끝난 작업을 계속 보여주는 셈이다).
      // 이 fixture의 mock 층에는 navigation_graph가 없어 결과가 즉시 나오므로,
      // 여기서 보이는 것은 진행 문구가 아니라 수동 지정 안내다.
      //
      // 다만 그 작업은 **층을 답한 뒤에** 시작한다 — 자동 진입이 "몇 층에
      // 계신가요?"를 먼저 띄운다.
      await dismissEntryFloorPrompt(tester);
      expect(find.textContaining('위치 지정으로 직접 지정해주세요'), findsOneWidget);

      await tester.pumpAndSettle();
      // 실내 진입 오버레이가 켜지면 야외 지도 위에 세로 층 선택기(FloorSelector)
      // 가 나타난다. 상단 햄버거(앱 메뉴)는 모드와 무관하게 늘 그 자리에 있다.
      expect(find.byType(FloorSelector), findsOneWidget);
      expect(find.byTooltip('메뉴'), findsOneWidget);
    },
  );

  testWidgets(
    'map shell keeps the outdoor view when GPS signal stays strong near the entrance',
    (WidgetTester tester) async {
      // 건물 북쪽 벽에서 약 33 m 떨어진 인도 + 신호 양호(건물 앞을 지나가는
      // 상황). 좌표를 외곽선 **밖**으로 잡는 것이 이 테스트의 전제다 — 진입
      // 판정이 "믿을 수 있는 좌표가 건물 안"이라(judgeBuildingFromGps), 입구와
      // 같은 좌표(외곽선 안쪽 약 22 m)를 흘리면 지나가는 상황이 아니라 실제로
      // 들어온 상황이 된다.
      final passingByPosition = Position(
        latitude: 37.5670,
        longitude: 126.9780,
        timestamp: DateTime(2024, 1, 1),
        accuracy: 5,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
      watchPosition = () => Stream.value(passingByPosition);

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
      );
      await tester.pump();
      await tester.pump();

      // 오버레이가 켜지지 않았으므로 층 선택기는 없어야 한다. 햄버거(앱 메뉴)는
      // 오버레이 상태와 무관하게 남는다.
      expect(find.byType(FloorSelector), findsNothing);
      expect(find.byTooltip('메뉴'), findsOneWidget);
    },
  );

  testWidgets('outdoor map reacts to multiple position stream updates', (
    WidgetTester tester,
  ) async {
    final controller = StreamController<Position>();
    watchPosition = () => controller.stream;

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const OutdoorMapBody()),
    );

    controller.add(_fakePosition);
    // MapLibre 이관 후 _handlePosition이 비동기 _syncCurrentLayer / _updateRoute
    // 를 추가로 스케줄하는데, 이 마이크로태스크들이 완료돼 setState의 결과가
    // 위젯 트리에 반영되기까지 여러 프레임이 걸린다. 단일 pump()는 스트림
    // 리스너만 발동해서 화면 상태 assertion 이 안정적으로 실패한다 —
    // 짧게 pump해 큐를 비운다.
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('GPS 신호 약함'), findsNothing);

    controller.add(_fakeLowAccuracyPosition);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('GPS 신호 약함'), findsOneWidget);

    await controller.close();
  });

  testWidgets('outdoor map falls back to a default location on failure', (
    WidgetTester tester,
  ) async {
    watchPosition = () => Stream.error(Exception('위치를 가져올 수 없음'));

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const OutdoorMapBody()),
    );
    await tester.pump();

    // 위치 실패 시에도 지도 body는 폴백 좌표로 렌더되고 GPS 신호 약함 배지가
    // 뜬다. 위치 마커는 MapLibre native로 옮겨져 트리에서 찾지 않는다.
    expect(find.byType(OutdoorMapBody), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('GPS 신호 약함'), findsOneWidget);
  });

  testWidgets('실내 진입 오버레이는 저장소에서 받은 층을 chip으로 보여준다', (
    WidgetTester tester,
  ) async {
    final key = GlobalKey<OutdoorMapBodyState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: OutdoorMapBody(key: key),
      ),
    );
    await tester.pumpAndSettle();
    // ignore: invalid_use_of_visible_for_testing_member
    key.currentState!.enterIndoorForTest();
    await tester.pumpAndSettle();

    // 건물명을 중복 표시하지 않고 현재 층 chip만 남긴다.
    expect(find.text('1F'), findsOneWidget);
  });

  // 예전에는 여기서 실내 전용 화면의 도면 렌더링을 확인했다. 그 화면이 사라진
  // 뒤 도면은 MapLibre 레이어로 그려지고, 그 레이어는 위젯 트리에 없어 위젯
  // 테스트로 볼 수 없다. 레이어 등록 자체는 indoor_overlay_ids_test.dart가,
  // 지도 위 개발 도구가 없다는 것은 아래 디버그 모드 테스트가 계속 지킨다.

  testWidgets('debug mode keeps always-on PDR free of a manual start control', (
    WidgetTester tester,
  ) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'debug_mode.enabled': true});
    // setUp이 이미 빈 mock으로 로드해 둔 상태라, 여기서 다시 읽어야 방금 켠
    // 디버그 모드가 전역 컨트롤러에 반영된다.
    await debugModeController.reload();

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await tester.pumpAndSettle();

    // 디버그 모드를 켜 둬도 지도 자체에는 개발 도구가 나타나지 않는다.
    expect(find.byIcon(Icons.bug_report_outlined), findsNothing);
    expect(find.text('PDR 시작'), findsNothing);
    // 진단 공유 버튼도 실제 길안내 기록이 생긴 뒤에만 나타난다.
    expect(find.byTooltip('PDR 진단 JSON 공유'), findsNothing);

    // 유일한 진입점은 상단 바 햄버거 → 앱 메뉴다. 여기서만 지금 디버그 모드가
    // 켜져 있다는 사실이 드러나야 한다.
    await tester.tap(find.byTooltip('메뉴'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('app-menu-debug')), findsOneWidget);
    expect(find.byIcon(Icons.bug_report_outlined), findsOneWidget);
    expect(find.text('사용 중 · PDR 제어와 진단 레이어가 지도에 표시됩니다'), findsOneWidget);
  });

  testWidgets('실내 진입 오버레이에서 층 chip으로 층을 바꾼다', (WidgetTester tester) async {
    final mapKey = GlobalKey<OutdoorMapBodyState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: OutdoorMapBody(key: mapKey),
      ),
    );
    await tester.pumpAndSettle();
    // ignore: invalid_use_of_visible_for_testing_member
    mapKey.currentState!.enterIndoorForTest();
    await tester.pumpAndSettle();

    // 접힌 층 chip을 먼저 연 뒤 다른 층을 선택한다.
    await tester.tap(find.text('1F'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2F'));
    await tester.pumpAndSettle();

    // 도면 자체는 MapLibre 레이어라 위젯 트리에 없다. 층이 바뀐 사실은 선택기가
    // 말하고, 화면 상태는 currentFloor가 말한다.
    expect(mapKey.currentState!.currentFloor, '2F');
  });

  /// 새 검색 흐름: 상단 검색창에 그대로 친다. 아래에서 입력창이 하나 더 있는
  /// 시트가 올라오지 않고, 결과는 검색창 바로 밑 패널에 뜬다.
  Future<void> searchFromTopBar(WidgetTester tester, String query) async {
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), query);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
  }

  testWidgets('홈 탭에서도 매장 이름으로 검색 결과가 뜬다', (WidgetTester tester) async {
    // 회귀: 건물 안을 보고 있지 않으면 검색이 "건물 이름"만 뒤져서, 홈 화면에서
    // 매장명을 치면 무조건 "검색 결과가 없습니다"가 떴다.
    final repository = _FallbackDestinationRepository(
      lightResult: const PoiSearchResult(
        name: 'MLB',
        floor: 'B2',
        point: LatLng(37.52, 126.92),
        nodeId: 'FL-2:ND-9',
      ),
    );
    destinationRepository = repository;

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await tester.pumpAndSettle();
    await searchFromTopBar(tester, 'MLB');

    expect(repository.lightQueries, ['MLB']);
    expect(find.text('MLB'), findsWidgets);
    expect(find.text('B2'), findsOneWidget);
  });

  testWidgets('엔터로 확정하면 경량이 빈손일 때 의미 검색까지 자동으로 간다', (
    WidgetTester tester,
  ) async {
    // 사용자는 "일반 검색"과 "AI 검색"을 구분하지 않는다. 한 곳에 치면 된다.
    final repository = _FallbackDestinationRepository(
      aiResult: const PoiSearchResult(
        name: '요즘김밥',
        floor: 'B1',
        point: LatLng(37.52, 126.92),
        nodeId: 'FL-1:ND-1',
      ),
    );
    destinationRepository = repository;

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await tester.pumpAndSettle();
    await searchFromTopBar(tester, '밥 먹을 곳');

    // 경량 → 의미 순으로 같은 질의가 이어진다. 버튼을 누를 필요가 없다.
    expect(repository.lightQueries, ['밥 먹을 곳']);
    expect(repository.aiQueries, ['밥 먹을 곳']);
    expect(find.textContaining('요즘김밥'), findsOneWidget);
    // 왜 다른 이름이 나왔는지 알려 준다.
    expect(find.text('뜻이 비슷한 매장을 찾았어요'), findsOneWidget);
  });

  testWidgets('경량이 찾으면 의미 검색은 돌지 않는다', (WidgetTester tester) async {
    // 매장 이름은 일반 검색처럼 즉시 끝나야 한다.
    final repository = _FallbackDestinationRepository(
      lightResult: const PoiSearchResult(
        name: 'MLB',
        floor: 'B2',
        point: LatLng(37.52, 126.92),
        nodeId: 'FL-2:ND-9',
      ),
    );
    destinationRepository = repository;

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await tester.pumpAndSettle();
    await searchFromTopBar(tester, 'MLB');

    expect(repository.aiQueries, isEmpty);
    expect(find.text('뜻이 비슷한 매장을 찾았어요'), findsNothing);
  });

  testWidgets('엔터를 누르지 않아도 타이핑이 멎으면 의미 검색까지 간다', (WidgetTester tester) async {
    // 회귀: 예전에는 의미 검색이 onSubmitted(엔터)에만 붙어 있었다. 한글 IME에서
    // 첫 엔터가 조합 확정에 쓰이면 onSubmitted가 오지 않아 의미 검색이 아예
    // 시작되지 않았고, 화면에는 경량이 빈손이라는 이유만으로 "찾지 못했어요"가
    // 최종 결론처럼 떠 있었다. "신발"·"밥집"은 어떤 매장명과도 정확히 일치하지
    // 않으므로 타이핑만으로는 항상 그 화면이었다.
    //
    // 대신 비용은 디바운스 두 단(경량 300ms + 의미 400ms)으로 막는다. 중간
    // 글자로 모델을 태우지 않는지는 widgets_test.dart의 SearchPanel 그룹이
    // 타이머 단위로 확인한다.
    final repository = _FallbackDestinationRepository(
      aiResult: const PoiSearchResult(
        name: '요즘김밥',
        floor: 'B1',
        point: LatLng(37.52, 126.92),
        nodeId: 'FL-1:ND-1',
      ),
    );
    destinationRepository = repository;

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '밥 먹을');
    // receiveAction(엔터)을 일부러 보내지 않는다. 시간만 흘린다.
    // 먼저 부모 setState를 그려 SearchPanel이 debounce timer를 설치하게 한다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    // 경량 검색과 건물 목록은 서로 다른 await 구간이다. 둘 다 끝나야
    // 400ms 의미 검색 timer가 설치되므로 microtask를 한 프레임 더 비운다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    expect(repository.lightQueries, ['밥 먹을']);
    expect(repository.aiQueries, ['밥 먹을']);
    expect(find.textContaining('요즘김밥'), findsOneWidget);
  });

  testWidgets('검색창을 눌러도 두 번째 입력창이 생기지 않는다', (WidgetTester tester) async {
    // 회귀: 예전에는 상단 검색창을 누르면 아래에서 입력창이 하나 더 있는 시트가
    // 올라와, 방금 누른 창과 실제로 치는 창이 달랐다. 검색 중 화면에 있는
    // TextField는 상단 바의 것 하나뿐이어야 한다.
    destinationRepository = _FallbackDestinationRepository();

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    // 친 글자는 그대로 상단 검색창에 남는다.
    await tester.enterText(find.byType(TextField), 'MLB');
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'MLB',
    );
  });

  testWidgets('카테고리 열에 AI 검색 pill이 더는 없다', (WidgetTester tester) async {
    destinationRepository = _FallbackDestinationRepository();

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI 검색'), findsNothing);
  });

  testWidgets('건물 이름으로 검색하면 건물 줄이 뜬다', (WidgetTester tester) async {
    // 매장과 건물을 같은 결과 패널에 함께 얹는다.
    destinationRepository = _FallbackDestinationRepository();

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await tester.pumpAndSettle();
    await searchFromTopBar(tester, '데모');

    expect(find.textContaining('건물 ·'), findsOneWidget);
  });

  testWidgets('상단 검색은 실내에서 현재 층을 요청에 함께 보낸다', (WidgetTester tester) async {
    // "화장실"처럼 시설 질의가 건물 전체 정렬 순서상 우연히 걸리는 층이 아니라
    // 지금 보고 있는 층으로 확정되도록, 실내 탭에서는 현재 층(_activeIndoorFloor)을
    // 경량 요청에 실어 보낸다. 매장 이름을 아는 검색이 다른 층에 있어 이 때문에
    // 경량이 빈손이 되더라도 의미 검색은 층을 무시하고 건물 전체를 보므로 여전히
    // 찾아낸다(백엔드 query_search.match_ai_destination).
    final repository = _FallbackDestinationRepository(
      lightResult: const PoiSearchResult(
        name: 'MLB',
        floor: 'B2',
        point: LatLng(37.52, 126.92),
        nodeId: 'FL-2:ND-9',
      ),
    );
    destinationRepository = repository;

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await tester.pumpAndSettle();
    // 실내 오버레이가 켜져야 현재 층(_activeIndoorFloor)이 잡힌다.
    tester
        .state<OutdoorMapBodyState>(find.byType(OutdoorMapBody))
        // ignore: invalid_use_of_visible_for_testing_member
        .enterIndoorForTest();
    await tester.pumpAndSettle();
    await searchFromTopBar(tester, 'MLB');

    expect(repository.lightFloorScopes, isNot(contains(null)));
    expect(find.text('B2'), findsOneWidget);
  });
}

/// 경량(`/query/destination`)과 AI(`/query/ai`)를 따로 흉내내, 폴백이 실제로
/// 갈리는지 본다. 어떤 질의가 어느 경로로 갔는지도 기록한다.
class _FallbackDestinationRepository implements DestinationRepository {
  _FallbackDestinationRepository({this.lightResult, this.aiResult});

  final PoiSearchResult? lightResult;
  final PoiSearchResult? aiResult;
  final lightQueries = <String>[];
  final aiQueries = <String>[];

  /// 검색이 층으로 좁혔는지 확인하려고 넘어온 값을 그대로 모아 둔다.
  final lightFloorScopes = <String?>[];
  final aiFloorScopes = <String?>[];

  @override
  Future<List<PoiSearchResult>> searchDestinations(
    String buildingId,
    String query, {
    String? currentFloorId,
  }) async {
    lightQueries.add(query);
    lightFloorScopes.add(currentFloorId);
    return lightResult == null ? const [] : [lightResult!];
  }

  @override
  Future<DiscoveryResult> searchDestinationsAi(
    String buildingId,
    String query, {
    String? currentFloorId,
    Map<String, List<String>>? selectedFacets,
    bool showAll = false,
  }) async {
    aiQueries.add(query);
    aiFloorScopes.add(currentFloorId);
    if (aiResult == null) {
      return DiscoveryResult(mode: DiscoveryMode.noMatch, query: query);
    }
    final result = aiResult!;
    return DiscoveryResult(
      mode: DiscoveryMode.direct,
      query: query,
      matches: [
        DiscoveryMatch(
          storeId: '${result.floor}:${result.name}',
          name: result.name,
          category: result.category,
          subcategory: result.subcategory,
          floorId: result.floor,
          floorName: result.floor,
          entranceNodeId: result.nodeId,
          point: result.point,
          matchedFacets: const {},
          reason: null,
        ),
      ],
    );
  }
}
