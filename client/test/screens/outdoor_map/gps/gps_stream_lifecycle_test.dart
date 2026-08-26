import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:geolocator/geolocator.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/screens/outdoor_map/gps/gps_freshness_policy.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 위치 스트림 **수명**에 대한 특성 테스트(characterization test).
///
/// 이 파일은 새 기능을 지키지 않는다. 지금 동작을 있는 그대로 못 박아,
/// 화면에서 GPS 세션을 떼어내는 리팩터가 **동작을 바꾸지 않았다는 증거**로 쓰려고
/// 먼저 쓴 것이다([해체 계획](../../../docs/client/outdoor-map-decomposition.md)의
/// 검증 게이트).
///
/// 지키는 것은 하나다: **스트림이 죽으면 화면이 스스로 다시 연다.** 실기기에서
/// 이게 안 돼서 "위치 갱신 버튼은 되는데 화면은 안 움직인다"는 상태가 나온 적이
/// 있고, 그 복구 경로가 이 리팩터에서 조용히 사라지면 같은 증상이 돌아온다.
///
/// 관측 지점은 `watchPosition` 팩토리가 **몇 번 불렸는가**다. 구독 자체가 화면
/// 안쪽 상태라 밖에서 셀 수 없지만, 스트림을 새로 여는 순간 이 팩토리를 반드시
/// 다시 부른다 — 그것이 "다시 열었다"의 유일한 외부 증거다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late Stream<Position> Function() originalWatchPosition;
  late Future<Position> Function() originalCurrentPosition;

  /// 스트림을 연 횟수. 화면이 재구독하면 늘어난다.
  late int subscribeCount;
  late List<StreamController<Position>> controllers;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await debugModeController.reload();
    originalBuildingRepository = buildingRepository;
    originalWatchPosition = watchPosition;
    originalCurrentPosition = currentPosition;
    buildingRepository = MockBuildingRepository();
    // 일회성 조회 seam도 갈아 끼운다. 안 끼우면 진짜 플러그인을 부르고, 그쪽이
    // 거는 timeLimit 타이머가 fakeAsync에 남아 테스트가 "pending timer"로 깨진다.
    // 이 테스트가 보는 것은 스트림 재구독 횟수뿐이라 조회는 영영 안 끝나면 된다.
    currentPosition = () => Completer<Position>().future;
    requestStartupPermissions = () async => {};
    subscribeCount = 0;
    controllers = [];
    watchPosition = () {
      subscribeCount++;
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

  Future<void> pumpMap(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: Scaffold(body: OutdoorMapBody())),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('스트림이 닫히면 재시도 간격 뒤에 다시 연다', (WidgetTester tester) async {
    await pumpMap(tester);
    expect(
      subscribeCount,
      1,
      reason: '테스트 전제(화면이 뜨면 위치 스트림을 연다)가 성립하지 않았다',
    );

    // 네이티브가 EventChannel을 해제하면 **에러 없이** 닫힌다. 이 경우가
    // 위험한 이유는 onError가 안 걸려서, onDone을 안 보면 앱이 영영 모른다는
    // 것이다.
    await controllers.first.close();
    await tester.pump(const Duration(milliseconds: 100));

    // 아직 재시도 간격 전이라 열지 않았어야 한다 — 즉시 다시 열면 권한이
    // 거부된 기기에서 채널을 쉼 없이 두드린다.
    expect(
      subscribeCount,
      1,
      reason: '닫히자마자 곧바로 다시 열면 영구 실패 상태에서 배터리만 태운다',
    );

    await tester.pump(streamRetryMinDelay + const Duration(milliseconds: 100));
    expect(
      subscribeCount,
      2,
      reason: '스트림이 닫혔는데 다시 열지 않았다 — 화면이 영영 멈춘다',
    );

    // 타이머가 남아 있으면 테스트가 pending timer로 실패한다. 화면을 내려
    // 정리 경로까지 함께 태운다.
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const SizedBox()));
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('열어 둔 스트림이 첫 좌표를 안 주면 죽은 것으로 보고 다시 연다', (
    WidgetTester tester,
  ) async {
    // geolocator 안드로이드는 포그라운드 서비스 바인딩이 늦으면 위치 요청을
    // 걸지 않고 그냥 돌아선다 — 에러도 종료도 오지 않아 스트림이 열린 채로
    // 벙어리가 된다. 실기기에서 실제로 관측된 상태다.
    await pumpMap(tester);
    expect(subscribeCount, 1);

    // 감시 타이머가 터져도 곧바로 다시 열지는 않는다. 닫힌 스트림과 **같은
    // 재시도 경로**를 태우기 때문이다(_handlePositionStreamClosed) — 벙어리
    // 스트림이 영구 실패인 경우까지 감안한 설계다.
    await tester.pump(streamSilenceTimeout + const Duration(milliseconds: 100));
    expect(
      subscribeCount,
      1,
      reason: '벙어리 감지가 재시도 간격을 건너뛰면 영구 실패에서 채널을 쉼 없이 두드린다',
    );

    await tester.pump(streamRetryMinDelay + const Duration(milliseconds: 100));
    expect(
      subscribeCount,
      2,
      reason: '열린 채 벙어리인 스트림을 감지하지 못하면 위치가 영영 안 온다',
    );

    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const SizedBox()));
    await tester.pump(const Duration(milliseconds: 100));
  });
}
