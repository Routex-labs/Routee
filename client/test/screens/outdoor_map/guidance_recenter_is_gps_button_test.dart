import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:navigation_client/models/place/poi_search_result.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **내 자리로 돌아가는 버튼은 안내 중에도 GPS 버튼 하나다.**
///
/// 안내가 시작되면 셸의 하단 바가 통째로 접힌다. 한동안 그 자리에 화살표
/// (`Icons.near_me`) 버튼을 대신 띄웠는데, 하는 일("내 자리로 돌아간다")이 접히기
/// 전의 "위치 보정"과 같으면서 모양만 달라 **안내를 시작하는 순간 버튼이 바뀐
/// 것처럼** 보였다. 지금은 같은 아이콘·같은 자리로 그 버튼만 남긴다.
///
/// 카메라는 여기서 확인하지 않는다(MapLibre 플랫폼 뷰가 위젯 테스트에 없다).
/// 재는 것은 **무엇이 화면에 서 있는가** 하나다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  final testBuildingRepository = MockBuildingRepository();

  /// 데모 건물 남쪽 벽에서 약 33 m 밖 — GPS 판정이 `outside`로 확정되는 자리다
  /// (`outdoor_to_indoor_guidance_start_test`와 같은 좌표).
  const outsideBuilding = ll.LatLng(37.5660, 126.9780);

  const destinationStore = PoiSearchResult(
    name: '강의실 102',
    floor: '1F',
    point: ll.LatLng(37.5665, 126.9782),
    nodeId: 'FL-1:ND-2',
  );

  final recenter = find.byKey(const Key('guidance-recenter'));

  Position outsideFix() => Position(
    latitude: outsideBuilding.latitude,
    longitude: outsideBuilding.longitude,
    timestamp: DateTime(2024, 1, 1),
    accuracy: 5,
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
    // 캐시를 미리 채우는 이유는 `outdoor_to_indoor_guidance_start_test`와 같다.
    await testBuildingRepository.getAllBuildings();
  });

  tearDown(() {
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    requestStartupPermissions = defaultRequestStartupPermissions;
    watchPosition = defaultWatchPosition;
  });

  testWidgets('안내를 시작하면 같은 GPS 버튼이 그 자리에 선다', (WidgetTester tester) async {
    final positions = StreamController<Position>.broadcast();
    addTearDown(positions.close);
    watchPosition = () => positions.stream;

    final key = GlobalKey<OutdoorMapBodyState>();
    var guidanceActive = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: OutdoorMapBody(
            key: key,
            onGuidanceActiveChanged: (active) => guidanceActive = active,
          ),
        ),
      ),
    );
    await drain(tester);
    positions.add(outsideFix());
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);

    // 안내 전에는 이 버튼이 없다 — 그 자리는 셸의 하단 바가 쓰고 있다.
    expect(recenter, findsNothing);

    final state = key.currentState!;
    await state.showOutdoorToIndoorRouteTo(
      destinationStore,
      origin: outsideBuilding,
    );
    await drain(tester);
    await state.startGuidanceForPickedRoute();
    await drain(tester);
    expect(guidanceActive, isTrue, reason: '테스트 전제(안내 시작)가 성립하지 않았다');

    expect(recenter, findsOneWidget);
    expect(
      find.descendant(of: recenter, matching: find.byIcon(Icons.my_location)),
      findsOneWidget,
      reason: '접히기 전의 "위치 보정"과 같은 아이콘이어야 같은 버튼으로 읽힌다',
    );
    // 화살표는 돌아오지 않는다. 하는 일이 같은 버튼을 둘로 가르던 자국이다.
    expect(find.byIcon(Icons.near_me), findsNothing);
  });
}
