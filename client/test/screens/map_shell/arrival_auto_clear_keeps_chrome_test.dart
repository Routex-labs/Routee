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
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/widgets/eta_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 도착 자동 지움이 **안내 세션까지 끝내지는 않는지**에 대한 회귀 테스트.
///
/// 증상은 상단에서 났다 — 도착하고 5초 뒤 경로가 지워지는 순간 접어 뒀던
/// 길찾기 두 칸이 되살아나, 지도에는 없는 경로의 이동 수단(대중교통으로 왔으면
/// 대중교통)이 선택된 채로 떴다. 원인은 자동 지움이 `_clearIndoorRoute`를 그대로
/// 불러 `_guidanceStarted`까지 내린 것이다. 세션을 끝내는 것은 도착 카드의
/// `안내 종료`뿐이어야 한다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  final repository = MockBuildingRepository();

  /// 건물 **밖** 좌표(외곽선에서 약 185 m 동쪽). 안이면 GPS가 실내 진입을
  /// 발동시켜 야외 도보 안내로 가지 못한다(guidance_chrome_folds_test와 같다).
  Position fix() => Position(
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

  testWidgets('도착해서 경로를 자동으로 지워도 길찾기 chrome은 접힌 채로 남는다', (
    WidgetTester tester,
  ) async {
    final positions = StreamController<Position>.broadcast();
    addTearDown(positions.close);
    watchPosition = () => positions.stream;

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await drain(tester);
    positions.add(fix());
    await drain(tester);

    await tester.tap(find.byType(TextField).first);
    await drain(tester);
    await tester.enterText(find.byType(TextField).first, '강의실');
    await drain(tester);
    await tester.tap(find.text('강의실 101').first);
    await drain(tester);
    await tester.tap(find.text('도착'));
    await drain(tester);
    await tester.tap(find.text('안내 시작'));
    await drain(tester);

    expect(
      find.byType(EtaCard),
      findsOneWidget,
      reason: '테스트 전제(도착을 누르면 경로가 그려짐)가 성립하지 않았다',
    );
    expect(
      find.byKey(const Key('route-planner')),
      findsNothing,
      reason: '테스트 전제(안내 중에는 길찾기 두 칸이 접힌다)가 성립하지 않았다',
    );

    // 도착 5초 뒤 타이머가 부르는 바로 그 자리. PDR 없이 이 순간만 재현한다.
    tester
        .state<OutdoorMapBodyState>(find.byType(OutdoorMapBody))
        .clearRouteAfterArrival();
    await drain(tester);

    expect(
      find.byKey(const Key('route-planner')),
      findsNothing,
      reason: '도착해서 경로를 지웠는데 길찾기 바가 펴지면, 지도에 없는 경로의 이동 수단이 선택된 채로 뜬다',
    );
  });
}
