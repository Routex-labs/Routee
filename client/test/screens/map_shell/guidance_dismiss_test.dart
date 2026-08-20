import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:geolocator/geolocator.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:navigation_client/widgets/eta_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "안내 종료"가 **상단 길찾기 바까지 닫는지**에 대한 회귀 테스트.
///
/// 예전에는 하단 카드의 안내 종료가 지도의 경로만 지웠다. 출발/도착 두 칸은
/// 상위 화면이 들고 있어서 그대로 남았고, 사용자는 안내를 껐는데 화면은 아직
/// 길찾기 중인 상태를 봤다. 그 칸을 없애려면 X를 한 번 더 눌러야 했다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  final repository = MockBuildingRepository();

  // 건물 밖 좌표(외곽선에서 약 185 m 동쪽). 건물 안이면 GPS가 실내 진입을
  // 발동시켜 야외 도보 안내 대신 실내 안내로 갈라진다.
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

  testWidgets('안내 종료를 누르면 상단 출발/도착 칸도 함께 사라진다', (WidgetTester tester) async {
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
    expect(find.byKey(const Key('route-planner')), findsNothing);

    await tester.tap(find.text('안내 종료'));
    await drain(tester);

    expect(find.byType(EtaCard), findsNothing);
    expect(
      find.byKey(const Key('route-draft-destination')),
      findsNothing,
      reason: '안내를 껐는데 출발/도착 칸이 남으면 아직 길찾기 중인 화면이 된다',
    );
  });
}
