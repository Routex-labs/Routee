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

/// 자동 실내 진입의 **재활성화**에 대한 회귀 테스트.
///
/// 예전에는 자동 진입이 되돌릴 수 없는 1회성이었다. 입구 앞을 지나가다 한 번
/// 잘못 발동하면, 사용자가 건물 밖을 탭해 나온 뒤 진짜로 들어가도 자동 진입이
/// 다시는 동작하지 않았다 — 오탐 한 번이 그 화면의 기능 자체를 죽였다.
///
/// 지금은 "신뢰할 수 있는 좌표가 입구에서 충분히 떨어진 곳에서 잡힘"으로만 다시
/// 켜진다. **건물 밖을 탭한 것만으로는 켜지지 않는 것이 핵심이다** — 그건 "바깥
/// 지도를 보여줘"라는 화면 조작이지 "내가 밖에 있다"가 아니라서, 그걸로 켜면
/// 실내에 그대로 있는 사용자가 곧바로 되끌려 들어간다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;
  final testBuildingRepository = MockBuildingRepository();

  const entrance = ll.LatLng(37.5665, 126.9779);
  // 데모 건물에서 한참 떨어진 좌표(약 185m 동쪽). 재활성화 거리(40m) 밖이다.
  const farFromEntrance = ll.LatLng(37.5665, 126.9800);

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
    // 건물 asset을 미리 읽어 캐시를 채운다. 캐시가 비어 있으면 위젯 테스트의
    // 가짜 시계가 파일 I/O를 기다려 주지 않아 입구 좌표가 도착하지 않는다.
    await testBuildingRepository.getAllBuildings();
  });

  tearDown(() {
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    requestStartupPermissions = defaultRequestStartupPermissions;
    watchPosition = defaultWatchPosition;
  });

  testWidgets('밖으로 나온 것이 확인되면 자동 진입이 다시 동작한다', (WidgetTester tester) async {
    // 실내로 들어가면 구독이 끊기고 나오면 다시 붙으므로 broadcast여야 한다.
    final positions = StreamController<Position>.broadcast();
    watchPosition = () => positions.stream;
    final key = GlobalKey<OutdoorMapBodyState>();

    // 자동 진입 안내가 스낵바라 ScaffoldMessenger의 Scaffold 조상이 필요하다.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: OutdoorMapBody(key: key)),
      ),
    );
    await drain(tester);

    // 1) 입구 앞(양호) → 신호 저하 → 자동 진입.
    positions.add(fix(entrance, 10));
    await tester.pump(const Duration(milliseconds: 50));
    positions.add(fix(entrance, 60));
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);
    expect(find.byType(FloorSelector), findsOneWidget);

    // 2) 건물 밖을 탭해 야외로 돌아온다. 이것만으로는 재활성화되지 않는다.
    // ignore: invalid_use_of_visible_for_testing_member
    await key.currentState!.handleMapClickForTest(farFromEntrance);
    await drain(tester);
    expect(find.byType(FloorSelector), findsNothing);

    // 3) 아직 무장 전 — 입구 앞에서 같은 저하가 다시 와도 들어가지 않는다.
    positions.add(fix(entrance, 10));
    await tester.pump(const Duration(milliseconds: 50));
    positions.add(fix(entrance, 60));
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);
    expect(
      find.byType(FloorSelector),
      findsNothing,
      reason: '밖을 탭한 것은 화면 조작일 뿐, 사용자가 실제로 나갔다는 근거가 아니다',
    );

    // 4) 입구에서 멀리 떨어진 곳에서 신뢰 좌표가 잡히면 그때 다시 켜진다.
    positions.add(fix(farFromEntrance, 8));
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);
    expect(find.byType(FloorSelector), findsNothing);

    // 5) 다시 들어가면 자동 진입이 정상 동작한다. 예전에는 여기가 죽어 있었다.
    positions.add(fix(entrance, 10));
    await tester.pump(const Duration(milliseconds: 50));
    positions.add(fix(entrance, 60));
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);
    expect(find.byType(FloorSelector), findsOneWidget);
  });

  testWidgets('보통 정확도 inside는 서로 다른 두 표본에서 진입한다', (WidgetTester tester) async {
    final positions = StreamController<Position>.broadcast();
    addTearDown(positions.close);
    watchPosition = () => positions.stream;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: OutdoorMapBody()),
      ),
    );
    await drain(tester);

    Position at(DateTime timestamp) => Position(
      latitude: entrance.latitude,
      longitude: entrance.longitude,
      timestamp: timestamp,
      accuracy: 15,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

    final firstAt = DateTime.utc(2026, 8, 20, 6);
    positions.add(at(firstAt));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(FloorSelector), findsNothing);

    positions.add(at(firstAt.add(const Duration(seconds: 1))));
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);
    expect(find.byType(FloorSelector), findsOneWidget);
  });

  testWidgets('입구 근처에서 잡힌 신뢰 좌표로는 재활성화하지 않는다', (WidgetTester tester) async {
    final positions = StreamController<Position>.broadcast();
    watchPosition = () => positions.stream;
    final key = GlobalKey<OutdoorMapBodyState>();

    // 자동 진입 안내가 스낵바라 ScaffoldMessenger의 Scaffold 조상이 필요하다.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: OutdoorMapBody(key: key)),
      ),
    );
    await drain(tester);

    positions.add(fix(entrance, 10));
    await tester.pump(const Duration(milliseconds: 50));
    positions.add(fix(entrance, 60));
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);
    expect(find.byType(FloorSelector), findsOneWidget);

    // ignore: invalid_use_of_visible_for_testing_member
    await key.currentState!.handleMapClickForTest(farFromEntrance);
    await drain(tester);

    // 입구 바로 앞에서 신호가 좋아진 경우. 진입 반경과 재활성화 거리 사이의
    // 완충 구간이라 아직 "나갔다"고 보지 않는다 — 여기서 켜 버리면 곧바로 진입이
    // 다시 성립해 오버레이가 켜졌다 꺼졌다 한다.
    positions.add(fix(entrance, 8));
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);

    positions.add(fix(entrance, 60));
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);
    expect(find.byType(FloorSelector), findsNothing);
  });
}
