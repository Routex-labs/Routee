import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/routing/place_link.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 공유 링크는 **화면이 세워지기 전에** 도착한다(cold start). 그래서 지도 셸은
/// `initState`에서 수신함을 한 번 비운다.
///
/// 그 자리에서 실패를 알리면 안 된다는 것이 이 파일의 계약이다. 실패 안내는
/// 토스트고, 토스트는 Overlay에 얹히는데 — 첫 프레임 전에 얹으려 하면 build 중
/// markNeedsBuild가 되어 프레임이 통째로 깨진다. 다른 건물을 가리키는 링크는
/// 네트워크를 한 번도 타지 않고 **동기로** 그 실패 경로에 닿으므로 정확히 그
/// 조건을 만든다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  final repository = MockBuildingRepository();

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
    placeLinkInbox.take();
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    requestStartupPermissions = defaultRequestStartupPermissions;
  });

  /// 화면이 서기 전에 링크가 수신함에 들어와 있는 상태를 만든다. 이 앱은 건물이
  /// 하나뿐이라 다른 buildingId는 조작된 링크이지만, 그렇다고 앱이 죽어서는 안 된다.
  Future<void> pumpWithPendingLink(WidgetTester tester) async {
    placeLinkInbox.value = const PlaceLink(
      buildingId: 'not-this-building',
      placeId: 'PO-whatever',
    );

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await tester.pump();
  }

  testWidgets('세우기 전에 도착한 다른 건물 링크가 첫 프레임을 깨지 않는다', (tester) async {
    await pumpWithPendingLink(tester);

    expect(tester.takeException(), isNull);

    // 토스트가 스스로 걷힐 때까지 시계를 돌린다. 남겨 두면 테스트가 "타이머가
    // 살아 있다"로 실패해, 정작 보려던 첫 프레임 계약이 가려진다.
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('열지 못했다는 사실을 조용히 삼키지 않는다', (tester) async {
    await pumpWithPendingLink(tester);

    // 아무것도 안 뜨면 사용자는 링크를 눌렀는데 지도만 보고 이유를 모른다.
    expect(find.text('장소를 찾을 수 없습니다'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('그 링크는 소비되어 수신함에 남지 않는다', (tester) async {
    await pumpWithPendingLink(tester);

    // 남겨 두면 다음에 화면이 다시 세워질 때 같은 실패를 또 알린다.
    expect(placeLinkInbox.value, isNull);

    await tester.pump(const Duration(seconds: 2));
  });
}
