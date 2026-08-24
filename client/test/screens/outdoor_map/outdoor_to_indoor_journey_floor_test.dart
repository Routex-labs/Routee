import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:navigation_client/models/place/poi_search_result.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:navigation_client/screens/outdoor_map/widgets/floor_selector.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **밖에서 다른 층 매장을 목적지로 잡았을 때 활성 층이 지상으로 돌아오는지**에
/// 대한 회귀 테스트.
///
/// 지키려는 증상: **경로는 지상 출입구에서 시작하는데 화면만 목적지 층에 서는 것.**
///
/// 실내 도면은 `_indoorEntered`가 아니라 **배율**로 페이드인한다. 그래서 밖에 선
/// 사용자의 활성 층이 목적지 층에 남아 있으면, 문 경유 안내가 경로에 카메라를
/// 맞추는 순간 그 배율이 페이드 구간의 끝이라 지상 출구에서 끝나는 야외선 밑에
/// **목적지 층 도면**이 깔린다 — 이어지는 것이 하나도 없는 화면이 된다.
///
/// 규칙과 실기기 화면은 `docs/client/indoor-entry-rules.md` 6절.
///
/// **폴백 갈래에서도 지켜져야 한다.** 목업 리포지토리는 층 간 그래프를 주지
/// 않으므로([MockBuildingRepository.getBuildingGraph]가 null) 이 테스트는 실내
/// 구간을 못 푸는 갈래를 탄다 — 층을 되돌리는 자리가 정상 갈래에만 있으면 여기서
/// 걸린다.
///
/// 층은 [OutdoorMapBodyState.currentFloor]로 읽는다. 도면·층 그래프·경로 레이어가
/// 전부 그 값을 보므로, 화면이 무슨 층을 그리는지가 곧 이 값이다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  final testBuildingRepository = MockBuildingRepository();

  // 데모 건물 footprint는 위도 37.5663~37.5667, 경도 126.9777~126.9783 사각형이다.
  const insideBuilding = ll.LatLng(37.5665, 126.9780);
  const outsideBuilding = ll.LatLng(37.5660, 126.9780);

  // 목업 건물은 1F·2F뿐이라 지하 대신 2F로 같은 흐름을 시험한다 — 가르는 것은
  // 층 이름이 아니라 "목적지 층에 눌러앉은 화면이 출입구 층으로 돌아오는가"다.
  const storeOn2F = PoiSearchResult(
    name: '강의실 201',
    floor: '2F',
    point: ll.LatLng(37.5665, 126.9782),
    nodeId: 'FL-2:ND-1',
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
    // 건물 asset을 미리 읽어 캐시를 채운다. 위젯 테스트의 가짜 시계는 실제 파일
    // I/O를 기다려 주지 않아, 캐시가 비면 footprint가 도착하지 않는다.
    await testBuildingRepository.getAllBuildings();
  });

  tearDown(() {
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    requestStartupPermissions = defaultRequestStartupPermissions;
  });

  testWidgets('밖에서 다른 층 매장을 목적지로 잡으면 활성 층이 출입구 층으로 돌아온다', (
    WidgetTester tester,
  ) async {
    final key = GlobalKey<OutdoorMapBodyState>();
    // Scaffold로 감싼다 — 실내 구간을 못 풀면 스낵바가 뜨고, 하위에
    // ScaffoldMessenger가 없으면 그 자리에서 예외로 끊긴다.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: OutdoorMapBody(key: key)),
      ),
    );
    await drain(tester);

    final state = key.currentState!;
    expect(state.currentFloor, '1F', reason: '테스트 전제: 처음에는 기본 층이다');

    // 건물을 탭해 도면을 펴고 2F로 훑는다. **GPS 자동 진입이 아니라 화면 조작이라
    // 실내 위치(PDR 앵커)는 안 잡힌다** — 사용자는 아직 밖에 서 있다. 밖에서 다른
    // 층 매장을 검색·탭했을 때와 같은 상태로, 남는 값도 활성 층 하나다.
    // ignore: invalid_use_of_visible_for_testing_member
    await state.handleMapClickForTest(insideBuilding);
    await drain(tester);
    tester.widget<FloorSelector>(find.byType(FloorSelector)).onSelectFloor('2F');
    await drain(tester);
    expect(
      state.currentFloor,
      '2F',
      reason: '테스트 전제(도면 층이 목적지 층으로 갈린 상태)가 성립하지 않았다',
    );

    await state.showOutdoorToIndoorRouteTo(storeOn2F, origin: outsideBuilding);
    await drain(tester);

    expect(
      state.currentFloor,
      '1F',
      reason:
          '이 여정의 실내 구간은 지상 출입구에서 시작한다. '
          '활성 층이 목적지 층에 남으면 배율만으로 그 층 도면이 깔려 야외선과 이어지지 않는다',
    );
  });
}
