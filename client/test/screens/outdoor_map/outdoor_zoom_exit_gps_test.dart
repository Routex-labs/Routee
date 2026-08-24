import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:navigation_client/screens/outdoor_map/widgets/floor_selector.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 축소로 실내를 벗어난 뒤 **GPS가 다시 끌고 들어가지 않는지**에 대한 회귀 테스트.
///
/// 건물 밖 탭 이탈(`_exitIndoorByOutsideTap`)은 GPS 자동 진입까지 함께 껐지만
/// 축소 이탈에는 그 한 줄이 없었다. 그래서 건물 안에 서서 축소해 나온 사람은
/// 오차 20 m 이하 좌표 한 건에 곧바로 되끌려 들어갔다 — 상단 검색도 실내 모드로
/// 돌아가 방금 받은 실외 결과가 사라졌다.
///
/// 줌 제스처 자체는 위젯 테스트로 만들 수 없다(MapLibre 플랫폼 뷰 콜백이라
/// 컨트롤러가 없다). 그래서 실기기가 지나는 것과 같은 함수를
/// [OutdoorMapBodyState.exitIndoorByZoomOutForTest]로 직접 부른다. 임계값
/// 판정 자체는 `indoorEntryTransitionForZoom`의 단위 테스트 몫이다.
///
/// 실내 여부는 층 선택기([FloorSelector]) 노출로 잰다 — 실내 오버레이가 켜졌을
/// 때만 뜨는 위젯이다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  final testBuildingRepository = MockBuildingRepository();

  // 데모 건물(assets/mock/sample_building.json) footprint는 위도
  // 37.5663~37.5667, 경도 126.9777~126.9783 사각형이다. 아래 좌표는 그 한가운데라
  // 부풀린 외곽선 기준으로도 안쪽 20 m가 넘는다(진입 기준 5 m).
  const insideBuilding = ll.LatLng(37.5665, 126.9780);
  // 건물 입구. 안쪽이지만 서쪽 벽에 가깝다.
  const entrance = ll.LatLng(37.5665, 126.9779);
  // 건물 동쪽으로 약 176 m. 이탈 기준(부풀린 외곽선 밖 8 m)을 한참 넘는다.
  const farFromBuilding = ll.LatLng(37.5665, 126.9800);

  Position fix(ll.LatLng point, double accuracy) => Position(
    latitude: point.latitude,
    longitude: point.longitude,
    timestamp: DateTime(2024, 1, 1),
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

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

  /// 야외 지도를 띄우고 좌표를 흘려 넣을 통로를 함께 돌려준다.
  ///
  /// 스트림은 broadcast여야 한다 — 실내로 들어가면 구독을 끊고 나오면 다시 붙는데,
  /// 단일 구독 스트림은 재구독에서 'already been listened to'로 터진다.
  ///
  /// Scaffold가 필수다. 자동 실내 진입이 '건물 감지 중...' 스낵바를 띄우는데,
  /// ScaffoldMessenger가 없으면 그 자리에서 예외가 나 진입이 끊긴다.
  Future<(GlobalKey<OutdoorMapBodyState>, StreamController<Position>)> pumpMap(
    WidgetTester tester,
  ) async {
    final key = GlobalKey<OutdoorMapBodyState>();
    final positions = StreamController<Position>.broadcast();
    watchPosition = () => positions.stream;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: OutdoorMapBody(key: key)),
      ),
    );
    await drain(tester);
    // 첫 좌표는 건물에서 떨어진 곳이어야 한다 — 판정에 쓰는 외곽선은 asset 로드
    // 뒤에 채워지므로, 건물 안을 첫 이벤트로 흘리면 아직 외곽선을 몰라 진입이
    // 일어나지 않는다.
    positions.add(fix(farFromBuilding, 40));
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);
    return (key, positions);
  }

  Future<void> send(
    WidgetTester tester,
    StreamController<Position> positions,
    ll.LatLng point,
    double accuracy,
  ) async {
    positions.add(fix(point, accuracy));
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);
  }

  testWidgets('축소로 나온 뒤에는 건물 안 좌표가 와도 되끌려 들어가지 않는다', (
    WidgetTester tester,
  ) async {
    final (key, positions) = await pumpMap(tester);

    await send(tester, positions, entrance, 10);
    expect(
      find.byType(FloorSelector),
      findsOneWidget,
      reason: '테스트 전제(GPS 자동 실내 진입)가 성립하지 않았다',
    );

    // ignore: invalid_use_of_visible_for_testing_member
    key.currentState!.exitIndoorByZoomOutForTest();
    await drain(tester);
    expect(find.byType(FloorSelector), findsNothing);

    // 사용자는 여전히 건물 안에 서 있다. 예전에는 이 한 건이 실내로 되끌었다.
    await send(tester, positions, insideBuilding, 10);
    expect(
      find.byType(FloorSelector),
      findsNothing,
      reason: '축소로 나왔는데 GPS 한 건이 다시 끌고 들어갔다',
    );
  });

  testWidgets('축소로 나온 뒤 정말 밖으로 걸어 나오면 자동 진입이 다시 켜진다', (
    WidgetTester tester,
  ) async {
    // 대칭이 깨지면 '한 번 축소하면 자동 진입이 영원히 죽는' 더 나쁜 버그가 된다.
    final (key, positions) = await pumpMap(tester);

    await send(tester, positions, entrance, 10);
    expect(find.byType(FloorSelector), findsOneWidget);

    // ignore: invalid_use_of_visible_for_testing_member
    key.currentState!.exitIndoorByZoomOutForTest();
    await drain(tester);
    expect(find.byType(FloorSelector), findsNothing);

    // 건물 밖 176 m, 오차 8 m — '밖' 판정이 서는 좌표다. 여기서 재무장한다.
    await send(tester, positions, farFromBuilding, 8);
    expect(find.byType(FloorSelector), findsNothing);

    // 다시 들어가면 자동 진입이 정상 동작한다.
    await send(tester, positions, insideBuilding, 10);
    expect(
      find.byType(FloorSelector),
      findsOneWidget,
      reason: '밖으로 나온 뒤에도 자동 진입이 죽어 있다',
    );
  });

  testWidgets('"밖에서 찾아보기"로 나온 뒤에도 GPS가 되끌지 않는다', (
    WidgetTester tester,
  ) async {
    // 검색의 "밖에서 찾아보기"는 축소가 아니라 [returnToOutdoorView]로 나간다.
    // 그 함수는 실내 상태를 먼저 끄고 카메라를 줄이므로, 뒤따르는 축소 이탈
    // 갈래는 `_indoorEntered`가 이미 false라 GPS 무장을 끄지 못한다 — 그래서
    // 그 함수 자체가 껐다. 이 테스트가 두 수정 사이의 그 이음매를 잡는다.
    final (key, positions) = await pumpMap(tester);

    await send(tester, positions, entrance, 10);
    expect(find.byType(FloorSelector), findsOneWidget);

    await key.currentState!.returnToOutdoorView();
    await drain(tester);
    expect(find.byType(FloorSelector), findsNothing);

    await send(tester, positions, insideBuilding, 10);
    expect(
      find.byType(FloorSelector),
      findsNothing,
      reason: '"밖에서 찾아보기"로 나왔는데 GPS 한 건이 다시 끌고 들어갔다',
    );
  });

  testWidgets('야외에서 축소만 한 것은 자동 진입을 끄지 않는다', (WidgetTester tester) async {
    // 축소 이탈 갈래는 실내가 아니어도 카메라가 멈출 때마다 불린다. 거기서 GPS
    // 무장을 무조건 끄면, 지도를 넓게 보며 건물로 걸어가는 사람의 자동 진입이
    // 조용히 죽는다.
    final (key, positions) = await pumpMap(tester);
    expect(find.byType(FloorSelector), findsNothing);

    // ignore: invalid_use_of_visible_for_testing_member
    key.currentState!.exitIndoorByZoomOutForTest();
    await drain(tester);

    await send(tester, positions, entrance, 10);
    expect(
      find.byType(FloorSelector),
      findsOneWidget,
      reason: '실내가 아닐 때의 축소가 GPS 자동 진입을 끊었다',
    );
  });
}
