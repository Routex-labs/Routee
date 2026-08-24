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
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:navigation_client/widgets/eta_card.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/place_detail_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **검색은 길을 찾지 않는다**는 규칙에 대한 회귀 테스트.
///
/// 예전에는 검색 결과의 건물 줄을 누르는 순간 그 입구까지 경로를 그렸다. 검색은
/// "저기가 어디지"를 묻는 조작이지 "저기로 데려다 줘"가 아닌데, 위치만 확인하려던
/// 사용자에게 안내가 시작되고 그만두려면 안내 종료를 눌러야 했다.
///
/// 지금은 고른 장소로 지도를 옮기고, 보여 줄 정보가 있으면 그것까지 띄운다.
/// 길찾기는 상단 길찾기 버튼에서 시작한다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  final repository = MockBuildingRepository();

  // 건물 밖 좌표. 건물 안이면 GPS가 실내 진입을 발동시켜 흐름이 갈라진다.
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

  /// [indoor]면 먼저 도면 안으로 들어간다. 우리 매장 줄은 실내에서만 서기
  /// 때문이다(`search-result-list-ux.md` Y절) — 건물 줄은 실외에서도 선다.
  Future<void> search(
    WidgetTester tester,
    String query, {
    bool indoor = false,
  }) async {
    final positions = StreamController<Position>.broadcast();
    addTearDown(positions.close);
    watchPosition = () => positions.stream;

    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const MapShellScreen()));
    await drain(tester);
    positions.add(fix());
    await drain(tester);

    if (indoor) {
      tester
          .state<OutdoorMapBodyState>(find.byType(OutdoorMapBody))
          // ignore: invalid_use_of_visible_for_testing_member
          .enterIndoorForTest();
      await drain(tester);
    }

    await tester.tap(find.byType(TextField).first);
    await drain(tester);
    await tester.enterText(find.byType(TextField).first, query);
    await drain(tester);
  }

  testWidgets('건물을 고르면 길을 찾지 않고 그 건물 이름만 띄운다', (
    WidgetTester tester,
  ) async {
    await search(tester, '데모');
    await tester.tap(find.text('데모 건물').first);
    await drain(tester);

    // 경로도, 길찾기 바도 없다. 건물을 고른 것은 "저기가 어디인지 보자"이지
    // "저기로 가자"가 아니다.
    expect(find.byType(EtaCard), findsNothing);
    expect(find.byKey(const Key('route-draft-destination')), findsNothing);
    // 예전에는 지도 위에 "ⓘ 건물 이름" 카드가 남는 것까지 확인했다. 그 카드는
    // 지도 위 chrome을 줄이면서 빠졌고(층 수 같은 세부는 화면 맨 아래 내비게이션
    // 자리로 간다), 지금 사용자가 받는 피드백은 카드가 아니라 **카메라가 그
    // 건물로 옮겨 가는 것**이다. 그 이동은 MapLibre 컨트롤러가 하는 일이라
    // 위젯 테스트에서는 잡히지 않으므로, 여기서는 "길찾기로 새지 않는다"만
    // 지킨다.
    expect(find.text('검색 결과'), findsNothing);
  });

  testWidgets('매장을 고르면 그 매장 정보 시트가 올라온다', (WidgetTester tester) async {
    await search(tester, '강의실', indoor: true);
    await tester.tap(find.text('강의실 101').first);
    await drain(tester);

    expect(find.byType(PlaceDetailSheet), findsOneWidget);
    // 시트가 떴을 뿐 안내는 시작되지 않는다. 길찾기는 시트의 "도착"이나 상단
    // 길찾기 버튼에서 시작한다.
    expect(find.byType(EtaCard), findsNothing);
  });

  testWidgets('시트가 떠 있을 때 다시 검색해도 시트는 하나다', (WidgetTester tester) async {
    // **두 겹으로 쌓이면 화면으로는 안 보인다.** 같은 자리에 같은 모양이
    // 겹치기 때문이다. 실기기에서는 뒤로가기를 눌러도 화면이 그대로인 것으로만
    // 드러났다 — 그래서 눈이 아니라 위젯 수로 잠근다.
    await search(tester, '강의실', indoor: true);
    await tester.tap(find.text('강의실 101').first);
    await drain(tester);
    expect(find.byType(PlaceDetailSheet), findsOneWidget);

    await search(tester, '강의실', indoor: true);
    await tester.tap(find.text('강의실 101').first);
    await drain(tester);

    expect(find.byType(PlaceDetailSheet), findsOneWidget);
  });
}
