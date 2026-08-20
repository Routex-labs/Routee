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

/// 상단 초안 바의 X가 **길찾기를 끝내는지**에 대한 회귀 테스트.
///
/// 예전에는 이 버튼이 출발/도착 값만 비웠다. 화면에서는 초안 바만 사라지고
/// 경로선·도착 핀·안내 카드는 그대로 남아, 안내를 실제로 끄려면 하단 카드의
/// "안내 종료"를 한 번 더 눌러야 했다 — 사용자에게는 X가 먹지 않은 것으로 보인다.
///
/// MapLibre 레이어는 위젯 트리에 없어 경로선을 직접 볼 수 없다. 대신 그 선과
/// 생사를 같이하는 **ETA 카드**로 검증한다(카드는 경로가 있을 때만 뜬다).
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  final repository = MockBuildingRepository();

  // 건물 밖 좌표(외곽선에서 약 185 m 동쪽). 건물 안이면 GPS가 실내 진입을
  // 발동시켜 야외 도보 안내 대신 실내 안내로 갈라진다 — 여기서 보려는 것은
  // 야외 흐름이다.
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

  testWidgets('상단 초안 바의 X를 누르면 그려진 경로까지 함께 사라진다', (
    WidgetTester tester,
  ) async {
    // broadcast여야 한다. 화면이 상황에 따라 위치를 다시 구독하는데, 단일 구독
    // 스트림은 취소 뒤 재구독하면 'already been listened to'로 터진다.
    final positions = StreamController<Position>.broadcast();
    addTearDown(positions.close);
    watchPosition = () => positions.stream;

    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const MapShellScreen()));
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

    expect(
      find.byType(EtaCard),
      findsOneWidget,
      reason: '테스트 전제(도착을 누르면 경로가 그려짐)가 성립하지 않았다',
    );

    await tester.tap(find.byTooltip('경로 계획 닫기'));
    await drain(tester);

    expect(
      find.byType(EtaCard),
      findsNothing,
      reason: 'X를 눌렀는데 안내 카드가 남아 있으면 경로도 그대로다',
    );
    // 초안 바 자체도 사라져야 한다 — 도착지를 비웠으므로 그릴 것이 없다.
    expect(find.byKey(const Key('route-draft-destination')), findsNothing);
  });
}
