import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/screens/outdoor_map/gps/gps_freshness_policy.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 야외 GPS 마커가 **깜빡이지 않는다**.
///
/// 실기기에서 "마커가 아주 잠깐 사라졌다 다시 나온다"가 올라왔다. 스트림이
/// 에러로 닫히는 순간 마지막 좌표를 그 자리에서 버리고 있었는데, 재구독은
/// [streamRetryMinDelay](2초) 뒤에 돌고 일회성 조회는 그동안에도 1초마다
/// 나가므로 대개 몇 초 안에 좌표가 다시 온다 — 사용자에게는 그 사이가
/// 깜빡임으로만 보인다.
///
/// 지키는 계약은 둘이다.
///   - 에러 한 번으로는 마커를 지우지 않는다.
///   - 그렇다고 영영 들고 있지도 않는다(권한 회수·위치 서비스 종료).
void main() {
  late BuildingRepository originalBuildingRepository;
  late Stream<Position> Function() originalWatchPosition;
  late Future<Position> Function() originalCurrentPosition;
  late List<StreamController<Position>> controllers;

  Position fixAt(double lat, double lng) => Position(
    latitude: lat,
    longitude: lng,
    timestamp: DateTime.now(),
    accuracy: 8,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await debugModeController.reload();
    originalBuildingRepository = buildingRepository;
    originalWatchPosition = watchPosition;
    originalCurrentPosition = currentPosition;
    buildingRepository = MockBuildingRepository();
    // 일회성 조회는 영영 안 끝나게 둔다 — 이 테스트가 보는 것은 스트림 에러
    // 하나로 마커가 사라지는지뿐이라, 조회가 좌표를 채워 주면 그 갈래가 가려진다.
    currentPosition = () => Completer<Position>().future;
    requestStartupPermissions = () async => {};
    controllers = [];
    watchPosition = () {
      final controller = StreamController<Position>();
      controllers.add(controller);
      return controller.stream;
    };
  });

  tearDown(() {
    buildingRepository = originalBuildingRepository;
    watchPosition = originalWatchPosition;
    currentPosition = originalCurrentPosition;
    requestStartupPermissions = defaultRequestStartupPermissions;
    for (final controller in controllers) {
      controller.close();
    }
  });

  final key = GlobalKey<OutdoorMapBodyState>();

  Future<void> pumpMap(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: OutdoorMapBody(key: key)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> disposeMap(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const SizedBox()),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('스트림 에러 한 번으로는 마커를 지우지 않는다', (WidgetTester tester) async {
    await pumpMap(tester);
    controllers.first.add(fixAt(37.5259, 126.9285));
    await tester.pump(const Duration(milliseconds: 100));
    final drawn = key.currentState!.outdoorMarkerPointForTest;
    expect(drawn, isNotNull, reason: '테스트 전제(좌표 한 건이면 마커가 뜬다)가 성립하지 않았다');

    controllers.first.addError(Exception('stream broke'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      key.currentState!.outdoorMarkerPointForTest,
      drawn,
      reason: '에러는 "스트림이 끊겼다"이지 "이 사람이 사라졌다"가 아니다',
    );

    await disposeMap(tester);
  });

  testWidgets('그래도 좌표가 영영 안 오면 마지막 자리를 버린다', (WidgetTester tester) async {
    await pumpMap(tester);
    controllers.first.add(fixAt(37.5259, 126.9285));
    await tester.pump(const Duration(milliseconds: 100));
    expect(key.currentState!.outdoorMarkerPointForTest, isNotNull);

    controllers.first.addError(Exception('stream broke'));
    await tester.pump(streamSilenceTimeout + const Duration(milliseconds: 100));

    expect(
      key.currentState!.outdoorMarkerPointForTest,
      isNull,
      reason: '권한이 회수된 뒤에도 옛 자리를 그리면 사용자가 거기 있다고 읽는다',
    );

    await disposeMap(tester);
  });
}
