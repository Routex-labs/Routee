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

/// `안내 시작`의 갈림길이 **"지금 시작할 구간이 실내인가"**를 묻는지에 대한
/// 회귀 테스트.
///
/// 지키려는 증상: 야외 구간을 그려 놓고 `안내 시작`을 눌렀는데
/// **"건물에 도착하면 안내를 시작할 수 있습니다."만 뜨고 아무 일도 안 일어나는 것.**
///
/// 갈림길이 묻던 것은 `_indoorRoutePreviewOrigin`(실내 미리 보기 출발지)이 남아
/// 있는가였다. 남아 있으면 무조건 실내 시작으로 새고, 그쪽 가드는 "GPS가 밖이라고
/// 하면 거부"다. 그런데 문 경유 안내(실외 → 건물 안 매장)는 **정의상 밖에서
/// 시작한다** — 밖이라는 이유로 거부하면 그 여정은 영영 못 시작한다.
///
/// 그 플래그는 밖에서도 선다(출발지를 직접 고른 실내 → 실내 미리 보기는
/// `indoorContextActive`를 안 본다). 비우는 자리는 `_clearIndoorRoute` 하나뿐인데
/// `showOutdoorToIndoorRouteTo`는 `returnToOutdoorView`를 통해서만 그걸 부르고, 그
/// 함수는 도면이 안 펴져 있으면 먼저 빠져나간다 — 그래서 낡은 채로 살아남는다.
///
/// **두 쪽을 다 못박는다.** 비우는 자리를 하나 더 만드는 수정으로는 1)이 통과하지
/// 않고, 갈림길을 통째로 걷어내는 수정으로는 2)가 통과하지 않는다.
///
///   1) 실내 구간만 살아 있으면 밖에서 시작할 수 없다 — 예전 동작 그대로.
///   2) 야외 구간이 그려지면 같은 플래그가 남아 있어도 시작된다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  final testBuildingRepository = MockBuildingRepository();

  const outsideMessage = '건물에 도착하면 안내를 시작할 수 있습니다.';

  // 데모 건물 footprint는 위도 37.5663~37.5667, 경도 126.9777~126.9783 사각형이다.
  // 아래 좌표는 남쪽 벽에서 약 33 m 밖이라 GPS 판정이 `outside`로 확정된다.
  const outsideBuilding = ll.LatLng(37.5660, 126.9780);

  // **두 끝점을 같은 층에 둔다.** 층이 갈리면 층 간 경로 갈래로 가는데, 목업은
  // 층 간 그래프를 안 줘서 그 실패가 `_clearIndoorRoute`로 미리 보기 상태를 통째로
  // 지운다 — 이 테스트가 만들려는 "낡은 플래그가 남은 상태"가 성립하지 않는다.
  // 같은 층 갈래는 층 그래프가 없으면 안내만 띄우고 상태를 남긴다.
  const originStore = PoiSearchResult(
    name: '강의실 101',
    floor: '1F',
    point: ll.LatLng(37.5665, 126.9779),
    nodeId: 'FL-1:ND-1',
  );
  const destinationStore = PoiSearchResult(
    name: '강의실 102',
    floor: '1F',
    point: ll.LatLng(37.5665, 126.9782),
    nodeId: 'FL-1:ND-2',
  );

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

  /// 떠 있는 스낵바가 스스로 걷힐 때까지 진행한다. 다음 단계의 판정이 앞 단계의
  /// 스낵바를 보고 성립하면 안 된다.
  Future<void> letSnackBarsExpire(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 8));
    await drain(tester);
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
    // 건물 asset을 미리 읽어 캐시를 채운다. 위젯 테스트의 가짜 시계는 실제 파일
    // I/O를 기다려 주지 않아, 캐시가 비면 footprint가 도착하지 않는다.
    await testBuildingRepository.getAllBuildings();
  });

  tearDown(() {
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    requestStartupPermissions = defaultRequestStartupPermissions;
    watchPosition = defaultWatchPosition;
  });

  testWidgets('실내 미리 보기 출발지가 남아 있어도 문 경유 안내는 밖에서 시작된다', (
    WidgetTester tester,
  ) async {
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

    final state = key.currentState!;

    // 밖에서 매장 → 매장을 미리 본다. 여기서 미리 보기 출발지가 선다.
    await state.showIndoorRouteTo(
      destinationStore,
      origin: originStore,
      preview: true,
    );
    await drain(tester);
    // 미리 보기 계산이 띄운 안내를 먼저 걷는다. 스낵바는 큐라, 안 걷으면 아래에서
    // 띄우는 문구가 그 뒤에 서서 이 시간 안에는 화면에 나타나지 않는다.
    await letSnackBarsExpire(tester);

    // 1) 아직은 실내 구간뿐이다. 이 여정은 건물 안에서 시작하므로 밖에서 눌러도
    //    시작되지 않는 것이 **맞다.** 이 단계가 성립해야 아래 2)가 무언가를 증명한다.
    await state.startGuidanceForPickedRoute();
    await drain(tester);
    expect(
      find.text(outsideMessage),
      findsOneWidget,
      reason: '테스트 전제(낡은 미리 보기 출발지가 남아 실내 갈래로 간다)가 성립하지 않았다',
    );
    expect(guidanceActive, isFalse, reason: '실내 미리 보기는 밖에서 시작되면 안 된다');
    await letSnackBarsExpire(tester);

    // 같은 화면에서 "현재 위치 → 건물 안 매장"으로 갈아탄다. 야외 구간이 선다.
    await state.showOutdoorToIndoorRouteTo(
      destinationStore,
      origin: outsideBuilding,
    );
    await drain(tester);
    await letSnackBarsExpire(tester);

    // 2) 하단 카드의 `안내 시작`과 **같은 함수**를 태운다.
    await state.startGuidanceForPickedRoute();
    await drain(tester);

    expect(
      find.text(outsideMessage),
      findsNothing,
      reason: '실외 → 건물 안 매장은 밖에서 시작하는 안내다. 밖이라고 거부하면 영영 못 시작한다',
    );
    expect(
      guidanceActive,
      isTrue,
      reason: '스낵바가 안 떠도 안내가 시작되지 않으면 사용자에게는 아무 일도 안 일어난 화면이다',
    );
  });
}
