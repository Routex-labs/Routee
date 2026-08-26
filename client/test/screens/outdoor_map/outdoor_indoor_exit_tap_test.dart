import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:navigation_client/screens/outdoor_map/widgets/floor_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 실내 모드에서 건물 밖을 탭하면 야외로 나가는지에 대한 회귀 테스트.
///
/// 예전에는 건물 밖 탭이 그냥 무시돼(`if (!_isInsideBuilding) return;`) 실내
/// 오버레이를 벗어나는 유일한 길이 "이탈 임계값 아래로 축소"였다. 그런데 그
/// 임계값은 zoom 15.6이라 사용자가 두세 단계를 축소해야 했고, 그래서 "실내에서
/// 나갈 수가 없다"고 느껴졌다.
///
/// MapLibre 플랫폼 뷰는 위젯 테스트에 없어 `onMapClick`이 발화하지 않으므로,
/// 실제 콜백과 같은 함수를 [OutdoorMapBodyState.handleMapClickForTest]로 직접
/// 부른다. 실내 여부는 층 선택기([FloorSelector]) 노출로 판정한다 — 실내
/// 오버레이가 켜졌을 때만 뜨는 위젯이다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  final testBuildingRepository = MockBuildingRepository();

  // 데모 건물(assets/mock/sample_building.json) footprint는 위도
  // 37.5663~37.5667, 경도 126.9777~126.9783 사각형이다.
  const insideBuilding = ll.LatLng(37.5665, 126.9780);
  // 건물 북쪽으로 약 220 m. footprint 밖이며 근접 톨러런스(80 m)도 넘는다.
  const outsideBuilding = ll.LatLng(37.5687, 126.9780);


  // 같은 자리에서 신호가 무너진 상태. 위 접근 표본과 짝을 이뤄 자동 실내 진입
  // 조건을 만족한다.
  Position atEntrance() => Position(
    latitude: 37.5665,
    longitude: 126.9779,
    timestamp: DateTime(2024, 1, 1),
    accuracy: 60,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  // 입구에서 멀리 떨어진 좌표. 자동 진입 반경 밖이라 야외를 유지한다.
  Position farAway() => Position(
    latitude: 37.5665,
    longitude: 126.9800,
    timestamp: DateTime(2024, 1, 1),
    accuracy: 40,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  // 실내 진입 오버레이는 건물 asset 로드와 여러 비동기 sync를 거쳐 뜬다.
  // pumpAndSettle은 지도 오버레이의 반복 애니메이션 때문에 정착하지 않으므로
  // 정해진 횟수만큼 프레임을 진행해 큐를 비운다.
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
    destinationRepository = MockDestinationRepository(buildingRepository);
    requestStartupPermissions = () async => {};
    // 건물 asset을 미리 읽어 캐시를 채운다. 위젯 테스트의 가짜 시계는 실제 파일
    // I/O를 기다려 주지 않아, 캐시가 비면 footprint가 도착하지 않는다.
    await testBuildingRepository.getAllBuildings();
  });

  tearDown(() {
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    requestStartupPermissions = defaultRequestStartupPermissions;
    watchPosition = defaultWatchPosition;
  });

  /// 자동 실내 진입까지 끌고 간 뒤 상태 키를 돌려준다.
  ///
  /// [outerOverlay]를 주면 지도 위에 상위 화면(MapShellScreen)의 오버레이를
  /// 흉내 낸 위젯을 함께 얹는다. 그때만 Stack으로 감싸며, 지도가 화면 전체를
  /// 그대로 차지하도록 [StackFit.expand]를 쓴다 — 지도 크기가 달라지면 층
  /// 선택기 위치도 함께 움직여 좌표 기반 검증이 무의미해진다.
  Future<GlobalKey<OutdoorMapBodyState>> enterIndoor(
    WidgetTester tester, {
    List<GlobalKey> outerOverlayKeys = const [],
    Widget? outerOverlay,
  }) async {
    final key = GlobalKey<OutdoorMapBodyState>();
    // broadcast여야 한다. 야외로 나가면 화면이 GPS를 **다시 구독**하는데,
    // 단일 구독 스트림은 취소된 뒤 재구독하면 'already been listened to'로
    // 터진다. 실제 앱의 watchPosition은 호출마다 새 스트림을 준다.
    final positions = StreamController<Position>.broadcast();
    watchPosition = () => positions.stream;

    // Scaffold로 감싸는 것이 필수다. 자동 실내 진입은 '건물 감지 중...' 스낵바를
    // 띄우는데, 하위에 Scaffold가 없으면 ScaffoldMessenger가 예외를 던져 진입
    // 코드가 그 자리에서 끊긴다(오버레이가 안 켜진 것처럼 보인다).
    final map = OutdoorMapBody(key: key, outerOverlayKeys: outerOverlayKeys);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: Scaffold(
          body: outerOverlay == null
              ? map
              : Stack(fit: StackFit.expand, children: [map, outerOverlay]),
        ),
      ),
    );
    await drain(tester);
    // 좌표는 흘려 둔다 — 이탈 탭이 카메라를 사용자 위치로 되돌리는 갈래가 있어
    // 위치가 아예 없으면 그 코드가 안 지나간다. 진입 자체는 좌표로 하지 않는다:
    // GPS 자동 진입은 없어졌고, 지금 이 화면을 여는 것은 건물 탭·확대·버튼이다.
    positions.add(farAway());
    await tester.pump(const Duration(milliseconds: 50));
    positions.add(atEntrance());
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);
    // ignore: invalid_use_of_visible_for_testing_member
    key.currentState!.enterIndoorForTest();
    await drain(tester);

    expect(
      find.byType(FloorSelector),
      findsOneWidget,
      reason: '테스트 전제(실내 진입)가 성립하지 않았다',
    );
    return key;
  }

  testWidgets('실내 모드에서 건물 밖을 탭하면 야외로 나간다', (WidgetTester tester) async {
    final key = await enterIndoor(tester);

    // ignore: invalid_use_of_visible_for_testing_member
    await key.currentState!.handleMapClickForTest(outsideBuilding);
    await drain(tester);

    expect(find.byType(FloorSelector), findsNothing);
  });

  testWidgets('실내 모드에서 건물 안을 탭하면 실내에 남는다', (WidgetTester tester) async {
    // 건물 밖 탭을 이탈로 해석하면서 건물 안 탭까지 함께 삼키면, 실내에서 복도를
    // 한 번 눌렀을 때 야외로 튕겨 나간다.
    final key = await enterIndoor(tester);

    // ignore: invalid_use_of_visible_for_testing_member
    await key.currentState!.handleMapClickForTest(insideBuilding);
    await drain(tester);

    expect(find.byType(FloorSelector), findsOneWidget);
  });

  testWidgets('건물 밖 탭으로 나온 뒤 건물을 다시 탭하면 실내로 돌아온다', (WidgetTester tester) async {
    // 가장 깨지기 쉬운 지점. 진입 히스테리시스 플래그(_autoIndoorEntryArmed)는
    // 진입할 때 false가 되고 이탈 임계값 아래로 축소할 때만 다시 true가 된다.
    // 명시적 건물 탭까지 그 플래그로 막으면, 탭으로 나온 사용자는 zoom을 크게
    // 낮추기 전까지 다시 들어갈 수 없다.
    final key = await enterIndoor(tester);

    // ignore: invalid_use_of_visible_for_testing_member
    await key.currentState!.handleMapClickForTest(outsideBuilding);
    await drain(tester);
    expect(find.byType(FloorSelector), findsNothing);

    // ignore: invalid_use_of_visible_for_testing_member
    await key.currentState!.handleMapClickForTest(insideBuilding);
    await drain(tester);

    expect(find.byType(FloorSelector), findsOneWidget);
  });

  testWidgets('층 선택기를 누른 탭은 건물 밖 좌표여도 야외로 나가지 않는다', (
    WidgetTester tester,
  ) async {
    // MapLibre 플랫폼 뷰는 Flutter gesture arena를 우회해서, 지도 위에 얹은
    // 층 chip을 누르면 그 탭이 지도에도 함께 도착한다. chip은 좌측 하단에
    // 있으므로 지도를 조금만 축소해 건물이 화면 가운데 일부만 차지하게 되면
    // 그 좌표가 건물 밖으로 풀린다 — 층을 바꿨을 뿐인데 야외로 튕겨 나갔다.
    // (확대해 두면 chip 자리도 건물 안이라 증상이 숨는다.)
    final key = await enterIndoor(tester);
    final selectorCenter = tester.getCenter(find.byType(FloorSelector));

    // ignore: invalid_use_of_visible_for_testing_member
    await key.currentState!.handleMapClickForTest(
      outsideBuilding,
      screenPoint: selectorCenter,
    );
    await drain(tester);

    expect(find.byType(FloorSelector), findsOneWidget);
  });

  testWidgets('상위 화면 오버레이를 누른 탭도 야외 이탈로 해석하지 않는다', (WidgetTester tester) async {
    // 하단 공용 바("위치 지정" 등)는 상위 MapShellScreen이 지도 위에 얹으므로
    // 야외 지도가 스스로 알 수 없다. 좌표를 넘겨받지 못하면 하단 바를 누른
    // 탭이 그대로 지도 탭이 되어 실내 오버레이가 닫힌다.
    final bottomBarKey = GlobalKey();
    final key = await enterIndoor(
      tester,
      outerOverlayKeys: [bottomBarKey],
      outerOverlay: Align(
        alignment: Alignment.bottomCenter,
        child: Container(key: bottomBarKey, height: 60, color: Colors.white),
      ),
    );

    // ignore: invalid_use_of_visible_for_testing_member
    await key.currentState!.handleMapClickForTest(
      outsideBuilding,
      screenPoint: tester.getCenter(find.byKey(bottomBarKey)),
    );
    await drain(tester);

    expect(find.byType(FloorSelector), findsOneWidget);
  });

  testWidgets('야외 상태에서 건물 밖을 탭해도 아무 일도 없다', (WidgetTester tester) async {
    final key = GlobalKey<OutdoorMapBodyState>();
    watchPosition = () => Stream.value(farAway());

    // Scaffold로 감싸는 것이 필수다. 자동 실내 진입은 '건물 감지 중...' 스낵바를
    // 띄우는데, 하위에 Scaffold가 없으면 ScaffoldMessenger가 예외를 던져 진입
    // 코드가 그 자리에서 끊긴다(오버레이가 안 켜진 것처럼 보인다).
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: Scaffold(body: OutdoorMapBody(key: key)),
      ),
    );
    await drain(tester);
    expect(find.byType(FloorSelector), findsNothing);

    // ignore: invalid_use_of_visible_for_testing_member
    await key.currentState!.handleMapClickForTest(outsideBuilding);
    await drain(tester);

    expect(find.byType(FloorSelector), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
