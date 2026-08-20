import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/models/place/outdoor_poi.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/repositories/place/outdoor_poi_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 바깥 장소를 한 건 돌려주는 가짜 리포지토리. 네트워크 없이 "실내에서도 바깥이
/// 검색된다"는 상황만 만든다.
class _FakeOutdoorPoiRepository implements OutdoorPoiRepository {
  @override
  bool get isAvailable => true;

  @override
  Future<List<OutdoorPoi>> searchNearby(
    String keyword, {
    required LatLng center,
    int radiusMeters = 1000,
    int limit = 10,
  }) async => [_subwayStation];
}

final _subwayStation = OutdoorPoi(
  id: 'poi-1',
  name: '여의도역',
  point: const LatLng(37.5215, 126.9243),
  category: '지하철역',
  address: '서울 영등포구 여의나루로',
  distanceMeters: 300,
);

/// 건물에서 확실히 떨어진 좌표.
///
/// 한때 건물 안 좌표에 오차 60 m를 달아 "판정이 안 서는 표본"으로 썼는데,
/// **진입이 오차를 안 보게 된 뒤로 그 표본이 곧 자동 진입**이 됐다. 지금은
/// 거리로 밖을 만든다(`docs/client/indoor-entry-rules.md` 1절).
Position _outsideFix() => Position(
  latitude: 37.5680,
  longitude: 126.9800,
  timestamp: DateTime(2024, 1, 1),
  accuracy: 60,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

/// 길찾기 두 칸이 **실제로 계산되는 값과 같은 것을 말하는지**에 대한 회귀 테스트.
///
/// 이 두 칸은 라벨이 아니라 입력창이다. 그래서 상태(`_selectedOrigin`,
/// `_routeDraftDestination`)를 바꾸는 쪽이 칸의 글자까지 함께 책임져야 하는데,
/// 그 규칙이 깨졌을 때 나오는 증상이 화면만 봐서는 버그로 보이지 않는다는 것이
/// 문제다 — 사용자는 자기가 고른 두 지점이 적힌 화면을 보면서 전혀 다른 경로를
/// 받는다.
///
/// 실제로 두 가지가 그렇게 새어 나왔다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;
  late OutdoorPoiRepository originalPoiRepository;
  late Stream<Position> Function() originalWatchPosition;
  late StreamController<Position> positions;

  final repository = MockBuildingRepository();

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
    originalPoiRepository = outdoorPoiRepository;
    originalWatchPosition = watchPosition;
    buildingRepository = repository;
    destinationRepository = MockDestinationRepository(repository);
    outdoorPoiRepository = _FakeOutdoorPoiRepository();
    positions = StreamController<Position>.broadcast();
    watchPosition = () => positions.stream;
    requestStartupPermissions = () async => {};
    await repository.getAllBuildings();
  });

  tearDown(() {
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    outdoorPoiRepository = originalPoiRepository;
    watchPosition = originalWatchPosition;
    requestStartupPermissions = defaultRequestStartupPermissions;
    positions.close();
  });

  /// 건물 안을 보고 있는 상태를 만든다. 실내 오버레이는 이제 별도 탭이 아니라
  /// 야외 지도 위에 켜지는 것이라, 진입 자체가 그 오버레이를 켜는 일이다.
  Future<void> enterIndoor(WidgetTester tester) async {
    tester
        .state<OutdoorMapBodyState>(find.byType(OutdoorMapBody))
        // ignore: invalid_use_of_visible_for_testing_member
        .enterIndoorForTest();
    await drain(tester);
  }

  /// 상단 검색으로 mock 매장을 찾아 매장 정보 시트를 띄운다.
  Future<void> openStoreInfoBySearch(WidgetTester tester) async {
    await tester.tap(find.byType(TextField).first);
    await drain(tester);
    await tester.enterText(find.byType(TextField).first, '강의실');
    await drain(tester);

    final result = find.text('강의실 101');
    expect(
      result,
      findsWidgets,
      reason: '테스트 전제(검색 결과에 mock 매장이 나옴)가 성립하지 않았다',
    );
    await tester.tap(result.first);
    await drain(tester);
  }

  testWidgets('건물 안에서 위치 지정 전에 "도착"을 눌러도 길찾기 바가 뜬다', (
    WidgetTester tester,
  ) async {
    // 출발지가 없는 상태다. 건물 안을 보고 있는데 "위치 지정"을 아직 안 했으니
    // 현재 위치를 출발지로 쓸 수도 없다(_canRouteFromCurrentLocation = false).
    //
    // 예전에는 이 조합에서 도착 초안만 저장하고 **아무것도 하지 않았다.** 계산을
    // 미루는 것 자체는 맞다(계산해 봐야 실패 안내뿐이다). 문제는 그 갈래가
    // 길찾기 바를 열지 않아, 매장에서 "도착"을 눌러도 상단이 검색창인 채였다는
    // 것이다 — 사용자에게는 누른 적 없는 화면이고, 출발지를 채워 넣을 자리도
    // 화면에 없다.
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const MapShellScreen()));
    await drain(tester);
    await enterIndoor(tester);
    await openStoreInfoBySearch(tester);

    expect(
      find.text('도착'),
      findsOneWidget,
      reason: '테스트 전제(매장 정보 시트 열림)가 성립하지 않았다',
    );
    await tester.tap(find.text('도착'));
    await drain(tester);

    expect(
      find.byKey(const Key('route-planner')),
      findsOneWidget,
      reason: '도착을 눌렀는데 길찾기 바가 뜨지 않아 출발지를 채울 자리가 없다',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('route-planner')),
        matching: find.text('강의실 101'),
      ),
      findsOneWidget,
      reason: '길찾기 바는 떴는데 방금 고른 도착지가 안 적혀 있다',
    );
  });

  testWidgets('바깥 장소를 도착으로 골라도 길찾기 바가 뜬다', (WidgetTester tester) async {
    // 매장 시트와 **같은 조합**을 야외 POI 시트에서 만든다. 상단 검색은 건물
    // 안에서도 바깥 장소를 함께 돌려주므로(실내에서 지하철역을 찾는 흐름),
    // 두 시트 중 한쪽만 고치면 같은 증상이 다른 문으로 그대로 남는다.
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const MapShellScreen()));
    await drain(tester);
    // 바깥 검색에는 기준점이 필요하다. 건물 밖 좌표라 자동 진입이 걸리지 않고,
    // 실내 상태는 아래 [enterIndoor]가 직접 켠다.
    positions.add(_outsideFix());
    await drain(tester);
    await enterIndoor(tester);

    await tester.tap(find.byType(TextField).first);
    await drain(tester);
    // 검색어는 **결과 이름과 다른 글자**여야 한다. 같으면 find.text가 결과 행이
    // 아니라 검색 입력창 자체를 먼저 잡아, 아무것도 안 눌린 채 통과한다.
    await tester.enterText(find.byType(TextField).first, '여의도');
    await drain(tester);

    final row = find.text('여의도역');
    expect(
      row,
      findsWidgets,
      reason: '테스트 전제(실내에서도 바깥 장소가 검색됨)가 성립하지 않았다',
    );
    await tester.tap(row.first);
    await drain(tester);

    expect(
      find.text('도착'),
      findsOneWidget,
      reason: '테스트 전제(야외 장소 시트 열림)가 성립하지 않았다',
    );
    await tester.tap(find.text('도착'));
    await drain(tester);

    expect(
      find.byKey(const Key('route-planner')),
      findsOneWidget,
      reason: '바깥 목적지로 도착을 눌렀는데 길찾기 바가 뜨지 않았다',
    );
    expect(find.text('여의도역'), findsOneWidget);
  });

  testWidgets('야외로 나가면 실내 출발지가 칸에서도 사라진다', (WidgetTester tester) async {
    // 실내에서 매장을 출발지로 잡아 두면 그 값은 야외에서 쓸 수 없다(층·노드가
    // 있는 실내 지점이라 GPS 경로의 출발점이 못 된다). 그래서 야외로 나가는
    // 순간 상태에서 비우는데, **칸의 글자는 남아 있었다.**
    //
    // 그 결과가 이 테스트가 막으려는 증상이다: 화면에는 "강의실 101 → 다른 매장"이
    // 적혀 있는데 계산은 GPS 현재 위치에서 시작한다. 같은 건물 두 지점 사이
    // 경로가 20 km짜리 야외 경로로 나온 적이 있고, 화면만 봐서는 왜 그런지 알
    // 방법이 없었다.
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const MapShellScreen()));
    await drain(tester);
    await enterIndoor(tester);
    await openStoreInfoBySearch(tester);

    expect(
      find.text('출발'),
      findsOneWidget,
      reason: '테스트 전제(매장 시트에 출발 버튼이 있음)가 성립하지 않았다',
    );
    await tester.tap(find.text('출발'));
    await drain(tester);

    expect(
      find.descendant(
        of: find.byKey(const Key('route-planner')),
        matching: find.text('강의실 101'),
      ),
      findsOneWidget,
      reason: '테스트 전제(출발지 칸이 그 매장으로 채워짐)가 성립하지 않았다',
    );

    // 도면을 접고 야외로 돌아간다. 실제로는 GPS가 "건물 밖"으로 판정할 때도 같은
    // 경로를 탄다([_applyBuildingVerdict]) — 그쪽이 사용자가 아무것도 안 눌러도
    // 일어나는 갈래라 더 위험하다.
    await tester
        .state<OutdoorMapBodyState>(find.byType(OutdoorMapBody))
        .returnToOutdoorView();
    await drain(tester);

    expect(
      find.text('현재 위치'),
      findsOneWidget,
      reason: '야외에서는 쓸 수 없는 출발지가 칸에 남아, 화면과 계산이 어긋난다',
    );
  });
}
