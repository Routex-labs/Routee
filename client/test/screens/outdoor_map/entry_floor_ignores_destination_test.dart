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

import '../../support/entry_floor_prompt_helper.dart';

/// **목적지 층은 앵커 층을 정하지 않는다.**
///
/// 실측 증상: 야외에서 B2 매장(스타벅스 리저브)을 목적지로 찍으면 도면이 B2로
/// 갈리고, 그대로 지상 1F 입구로 걸어 들어오면 앵커가 B2에 찍혔다. 화면이 1F로
/// 돌아오는 순간 `IndoorGuidanceSession.position`이 층이 안 맞아 null이 되어 파란
/// 위치 마커가 통째로 사라졌다 — 로그에도 안 남는 화면이었다.
///
/// 목업 건물은 1F·2F뿐이라 지하 대신 2F로 같은 흐름을 시험한다. 가르는 것은 층
/// 이름이 아니라 **"보고 있는 층"이 앵커 층을 정하는가**다.
///
/// 앵커 층은 [OutdoorMapBodyState.currentFloor]로 읽는다 —
/// `_startIndoorTracking`이 앵커를 찍을 때 쓰는 값이 그 층이다.
///
/// 좌표가 화면을 실내로 바꾸는 갈래는 이제 **앱을 건물 안에서 켠 경우 하나뿐**
/// 이다(`indoor-entry-rules.md` 6절). 그 갈래도 층을 물으므로, 답하지 않았을 때
/// 무엇이 층을 정하는지가 그대로 이 파일의 질문이다 — 걸어 들어와 버튼을 누른
/// 쪽은 출입구 층으로 못 박혀([enterIndoorFromGuidance]) 물을 것이 없다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  final testBuildingRepository = MockBuildingRepository();

  // 데모 건물 footprint는 위도 37.5663~37.5667, 경도 126.9777~126.9783이다.
  const insideBuilding = ll.LatLng(37.5665, 126.9780);

  Position positionAt(double latitude, double longitude) => Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: DateTime(2024, 1, 1),
    accuracy: 10,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  Position atEntrance() => positionAt(37.5665, 126.9779);

  // 지도 오버레이의 반복 애니메이션 때문에 pumpAndSettle이 정착하지 않으므로,
  // 정해진 횟수만큼 프레임을 진행해 큐를 비운다.
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
    destinationRepository = MockDestinationRepository(testBuildingRepository);
    requestStartupPermissions = () async => {};
    // 건물 asset을 미리 읽어 캐시를 채운다. 위젯 테스트의 가짜 시계는 실제 파일
    // I/O를 기다려 주지 않아, 캐시가 비면 외곽선이 도착하지 않는다.
    await testBuildingRepository.getAllBuildings();
  });

  tearDown(() {
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    requestStartupPermissions = defaultRequestStartupPermissions;
    watchPosition = defaultWatchPosition;
  });

  testWidgets('다른 층 도면을 펴 놓고 건물 안에서 앱을 켜면 앵커 층은 진입 근거가 정한다', (
    tester,
  ) async {
    final positions = StreamController<Position>.broadcast();
    addTearDown(positions.close);
    watchPosition = () => positions.stream;

    final key = GlobalKey<OutdoorMapBodyState>();
    // Scaffold로 감싼다 — 진입 경로가 스낵바를 띄우고, 하위에 ScaffoldMessenger가
    // 없으면 그 자리에서 예외로 끊긴다.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: OutdoorMapBody(key: key)),
      ),
    );
    // **좌표를 아직 주지 않는다.** 밖 좌표를 한 번이라도 보면 "걸어 들어왔다"로
    // 갈려([_sawOutsideSinceLaunch]) 이 갈래가 통째로 닫힌다.
    await drain(tester);

    final state = key.currentState!;
    // 검색 결과로 2F 매장을 고른 것과 같은 경로다. 도면만 그 층으로 갈리고
    // 사용자는 아직 밖에 서 있다.
    //
    // **기다리지 않는다** — 위젯 테스트에는 지도 스타일이 올라오지 않아
    // [OutdoorMapBodyState.focusStore]가 그 뒤 카메라 단계에서 영영 대기한다.
    // 이 테스트가 필요한 층 교체는 그 대기보다 앞에서 끝난다.
    unawaited(
      state.focusStore(
        const PoiSearchResult(
          name: '스타벅스 리저브',
          floor: '2F',
          point: insideBuilding,
          nodeId: 'FL-2:ND-1',
        ),
        enterBuildingIfNeeded: true,
      ),
    );
    await drain(tester);
    expect(
      state.currentFloor,
      '2F',
      reason: '테스트 전제(목적지 층으로 도면이 갈린 상태)가 성립하지 않았다',
    );

    positions.add(atEntrance());
    await tester.pump(const Duration(milliseconds: 50));
    await drain(tester);
    // 층을 물어도 답하지 않는다. 답이 없는 상태가 실기기에서 문제가 된 그 상태다.
    await dismissEntryFloorPrompt(tester);
    await drain(tester);

    expect(
      state.currentFloor,
      '1F',
      reason: '보고 있는 층에 앵커를 찍으면 1F에 선 사람이 2F 그래프에 못 박혀 마커가 사라진다',
    );
  });
}
