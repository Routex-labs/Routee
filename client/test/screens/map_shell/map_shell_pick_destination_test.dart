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
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/entry_floor_prompt_helper.dart';

/// 경로 입력 중 지도 탭이 별도 모드 버튼 없이 같은 입력으로 이어지는지 본다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;
  final repository = MockBuildingRepository();

  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  setUp(() async {
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

  testWidgets('길찾기를 열면 도착지 행과 지도 탭이 함께 활성화된다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await drain(tester);

    await tester.tap(find.byTooltip('길찾기'));
    await drain(tester);

    expect(find.text('지도에서 선택'), findsNothing);
    expect(find.byKey(const Key('route-draft-destination')), findsOneWidget);
    expect(
      tester.widget<OutdoorMapBody>(find.byType(OutdoorMapBody)).pickingOnMap,
      isTrue,
      reason: '편집 중인 행이 그대로 지도 탭의 대상이다',
    );
  });

  testWidgets('도면을 보고 있어도 지도 선택 지름길 행을 추가하지 않는다', (tester) async {
    final positions = StreamController<Position>.broadcast();
    addTearDown(positions.close);
    watchPosition = () => positions.stream;
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await drain(tester);
    positions.add(
      Position(
        latitude: 37.5665,
        longitude: 126.9780,
        timestamp: DateTime(2024),
        accuracy: 10,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      ),
    );
    await drain(tester);
    // 자동 진입이 띄운 "몇 층에 계신가요?"가 지도를 덮는다. 상단 바를 누르려면
    // 먼저 걷어야 한다.
    await dismissEntryFloorPrompt(tester);
    await tester.tap(find.byTooltip('길찾기'));
    await drain(tester);

    expect(find.byKey(const Key('route-field-pick-on-map')), findsNothing);
    expect(find.byKey(const Key('route-planner')), findsOneWidget);
  });
}
