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

/// 상단 초안 바에서 출발지·도착지를 정하면 **곧바로** 경로가 보이는지에 대한
/// 회귀 테스트.
///
/// 끝점을 정하는 것과 경로가 보이는 것 사이에 버튼을 한 번 더 두면(예: "길안내를
/// 끝내고 길찾기를 누르게 하기") 쓰기 불편해진다. 끝점이 정해지는 즉시 결과가
/// 보여야 한다.
///
/// 검증은 **도착지 이름이 ETA 카드에 반영됐는지**로 한다. 카드가 떠 있는지만 보면
/// 부족하다 — 새로 계산하지 않고 이전 경로를 그대로 두는 경우에도 카드는 그대로
/// 있기 때문이다. 이름이 바뀌어야 정말 다시 계산한 것이다.
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

  /// 야외 지도에 실제로 경로가 그려진 상태를 만든다. 야외 걷기 경로는 GPS가
  /// 있어야 계산되므로 위치를 하나 흘려 넣는다.
  Future<void> planRoute(WidgetTester tester) async {
    // broadcast여야 한다. 화면이 상황에 따라 위치를 다시 구독하는데, 단일 구독
    // 스트림은 취소 뒤 재구독하면 'already been listened to'로 터진다.
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

    expect(
      find.byType(EtaCard),
      findsOneWidget,
      reason: '테스트 전제(도착을 누르면 경로가 그려짐)가 성립하지 않았다',
    );
    expect(
      find.descendant(of: find.byType(EtaCard), matching: find.text('강의실 101')),
      findsOneWidget,
      reason: '테스트 전제(ETA 카드가 지금 도착지를 가리킴)가 성립하지 않았다',
    );
  }

  testWidgets('계획 중 도착지를 바꾸면 곧바로 그 도착지로 경로가 바뀐다', (WidgetTester tester) async {
    await planRoute(tester);

    // 상단 도착 행 → 길찾기 화면. 도착지 칸이 활성인 채로 열리므로 검색어만
    // 새로 넣고 후보를 고르면 그 자리에서 경로 계산으로 이어진다. 그 화면의
    // 입력창은 [출발지, 도착지] 순서다(길찾기 화면이 상단 바를 대신한다).
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('route-planner')),
        matching: find.text('강의실 101'),
      ),
    );
    await drain(tester);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('route-draft-destination')),
        matching: find.byType(TextField),
      ),
      '데모',
    );
    await drain(tester);
    await tester.tap(find.text('데모 건물').first);
    await drain(tester);

    // 도보는 안내를 시작하지 않고 경로만 그린 뒤 화면을 닫는다. 즉 버튼을 한 번
    // 더 누를 필요 없이 지도 위 카드가 곧바로 새 경로를 이어받아야 한다.
    expect(
      find.byType(EtaCard),
      findsOneWidget,
      reason: '끝점을 바꿨으면 경로를 끊지 말고 곧바로 다시 그려야 한다',
    );
    // 상단 초안 바에도 같은 이름이 적히므로 카드 안으로 좁힌다.
    expect(
      find.descendant(of: find.byType(EtaCard), matching: find.text('데모 건물')),
      findsOneWidget,
      reason: '바꾼 도착지가 경로에 반영되지 않았다',
    );
  });
}
