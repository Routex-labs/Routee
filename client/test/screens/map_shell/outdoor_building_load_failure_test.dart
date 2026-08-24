import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:routex_design_system/routex_design_system.dart';
import 'package:navigation_client/models/building/category_count.dart';
import 'package:navigation_client/models/place/store_index_entry.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/models/building/building.dart';
import 'package:navigation_client/models/building/building_graph.dart';
import 'package:navigation_client/models/route/indoor_route.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 건물 로드 실패가 조용히 지나가지 않는지에 대한 회귀 테스트.
///
/// 지키려는 증상: 백엔드에 못 붙으면 `getBuilding`이 던지는데, 야외 지도는
/// 그 예외를 await도 catch도 하지 않아 `_building`이 null로 남았다. 층 선택기·
/// 위치 지정·실내 진입·실내 도면이 전부 이 값에 걸려 있어서 **아무 표시 없이**
/// 통째로 사라졌고, 화면에는 원인을 짚을 단서가 하나도 없었다. 실제로 이 상태를
/// 두고 "VWorld 타일로 바꾸니 실내 기능이 사라졌다"고 원인을 잘못 짚은 적이 있다.
///
/// 야외 지도 자체는 건물 없이도 쓸 수 있으므로 화면을 에러로 덮지 않는다.
/// 대신 재시도가 달린 배지가 뜨고, 눌러서 복구되는지를 여기서 고정한다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  final inner = MockBuildingRepository();

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
    requestStartupPermissions = () async => {};
    // asset 캐시를 미리 채운다. 위젯 테스트의 가짜 시계는 실제 파일 I/O를
    // 기다려 주지 않아, 캐시가 비어 있으면 아무리 pump해도 건물이 도착하지 않는다.
    await inner.getAllBuildings();
  });

  tearDown(() {
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    requestStartupPermissions = defaultRequestStartupPermissions;
  });

  void useRepository(BuildingRepository repository) {
    buildingRepository = repository;
    destinationRepository = MockDestinationRepository(repository);
  }

  testWidgets('건물 로드가 실패하면 다시 시도할 수 있는 알림을 띄운다', (WidgetTester tester) async {
    final failing = _FlakyBuildingRepository(inner)..failing = true;
    useRepository(failing);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await drain(tester);

    // 실패가 화면에 남는다. 이게 없으면 사용자는 "실내 기능이 왜 없는지" 알 길이
    // 없고, 예외는 unhandled async error로만 흘러간다.
    expect(find.textContaining('건물 정보를 불러오지 못했습니다'), findsOneWidget);
    // **행동이 붙어 있어야 한다.** 사용자가 할 일이 있는 상태라 배지가 아니다 —
    // 읽기만 하는 GPS 배지와 같은 모양으로 그리면 둘이 구분되지 않는다.
    expect(find.byType(RoutexInlineNotice), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
  });

  testWidgets('다시 시도를 누르면 다시 불러와 복구된다', (WidgetTester tester) async {
    final failing = _FlakyBuildingRepository(inner)..failing = true;
    useRepository(failing);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await drain(tester);
    expect(find.textContaining('건물 정보를 불러오지 못했습니다'), findsOneWidget);

    // 백엔드가 살아난 뒤 재시도. **문장이 아니라 행동을 누른다** — 예전에는
    // 알림 전체가 탭 대상이라 문장을 눌러도 통과했고, 그래서 이 테스트는 자동
    // 재시도와 구분되지 않았다.
    failing.failing = false;
    await tester.tap(find.text('다시 시도'));
    await drain(tester);

    expect(find.textContaining('건물 정보를 불러오지 못했습니다'), findsNothing);
    // 첫 로드가 실패해도 재시도 한 번으로 실제 데이터까지 도달한다.
    expect(failing.getBuildingCalls, greaterThanOrEqualTo(2));
  });

  testWidgets('백엔드가 살아나면 누르지 않아도 스스로 복구된다', (WidgetTester tester) async {
    // 실제로 겪은 상황: `uvicorn --reload`가 백엔드 코드를 고칠 때마다 서버를
    // 잠깐 내리는데, 하필 그 순간 화면이 열려 있으면 이 로드만 실패하고
    // 실내 기능 전체가 죽은 채로 남았다. 로드는 initState에서 한 번만 돌아
    // 클라이언트를 hot reload해도 되살아나지 않는다.
    final failing = _FlakyBuildingRepository(inner)..failing = true;
    useRepository(failing);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await drain(tester);
    expect(find.textContaining('건물 정보를 불러오지 못했습니다'), findsOneWidget);

    // 백엔드가 돌아왔다. 사용자는 아무것도 누르지 않는다.
    failing.failing = false;
    await tester.pump(const Duration(seconds: 2));
    await drain(tester);

    expect(find.textContaining('건물 정보를 불러오지 못했습니다'), findsNothing);
  });

  testWidgets('백엔드가 계속 죽어 있어도 재시도를 무한히 반복하지 않는다', (WidgetTester tester) async {
    // 서버 없이 실행하는 환경에서 영원히 요청을 날리면 배터리와 로그만 태운다.
    // 사다리를 다 쓰면 멈추고 배지의 "다시 시도"에 맡긴다.
    final failing = _FlakyBuildingRepository(inner)..failing = true;
    useRepository(failing);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await drain(tester);

    // 사다리 총합(1+2+4+8+16+30 = 61초)을 훌쩍 넘겨 진행시킨다.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(seconds: 20));
    }
    final afterLadder = failing.getBuildingCalls;

    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(seconds: 20));
    }

    expect(failing.getBuildingCalls, afterLadder);
    // 배지는 그대로 남아 사용자가 직접 재시도할 수 있다.
    expect(find.textContaining('건물 정보를 불러오지 못했습니다'), findsOneWidget);
    // 호출 수 자체도 상식적인 범위여야 한다. 이 카운터는 야외 지도만 세는 게
    // 아니라 카테고리 열·실내 화면이 각자 한 번씩 부르는 것까지 함께 센다.
    expect(afterLadder, lessThan(20));
  });

  testWidgets('정상 로드에서는 알림이 뜨지 않는다', (WidgetTester tester) async {
    // 배지가 항상 떠 있으면(=조건이 뒤집혔으면) 위 두 테스트는 그대로 통과한다.
    useRepository(_FlakyBuildingRepository(inner));

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await drain(tester);

    expect(find.textContaining('건물 정보를 불러오지 못했습니다'), findsNothing);
  });
}

/// [failing]인 동안 `getBuilding`만 던지는 위임 리포지토리.
///
/// 네트워크 실패를 재현하는 자리이므로 404(=null 반환)와 구분해야 한다. 404는
/// "그런 건물이 없다"라 재시도해도 소용없지만, 여기서 재현하려는 것은 "서버에
/// 못 붙었다"라 재시도가 의미 있는 경우다.
class _FlakyBuildingRepository implements BuildingRepository {
  // 카테고리 pill은 이 테스트들의 관심사가 아니다. 빈 목록이면 pill 줄이 아예
  // 뜨지 않아 검증 대상 화면이 그대로 유지된다.
  @override
  Future<List<CategoryCount>?> getCategoryCounts(String buildingId) async =>
      const [];

  // 자동완성 원본. 이 테스트들은 후보를 보지 않으므로 빈 목록으로 둔다 —
  // 패널은 목록이 비면 후보를 그리지 않고 서버 검색만 돈다.
  @override
  Future<Map<String, dynamic>?> getBuildingEvents(String buildingId) async =>
      null;

  @override
  Future<List<StoreIndexEntry>?> getStoreIndex(String buildingId) async =>
      const [];
  _FlakyBuildingRepository(this._inner);

  final BuildingRepository _inner;
  bool failing = false;
  int getBuildingCalls = 0;

  @override
  Future<Building?> getBuilding(String buildingId) async {
    getBuildingCalls++;
    if (failing) throw Exception('connection refused');
    return _inner.getBuilding(buildingId);
  }

  @override
  Future<List<Building>> getAllBuildings() => _inner.getAllBuildings();

  @override
  Future<Map<String, dynamic>?> getFloorGeoJson(
    String buildingId,
    String floor,
  ) => _inner.getFloorGeoJson(buildingId, floor);

  @override
  Future<IndoorRoute?> getShortestRoute(
    String buildingId,
    String floor,
    String startNodeId,
    String endNodeId,
  ) => _inner.getShortestRoute(buildingId, floor, startNodeId, endNodeId);

  @override
  Future<BuildingGraph?> getBuildingGraph(
    String buildingId, {
    String vertical = 'auto',
  }) => _inner.getBuildingGraph(buildingId, vertical: vertical);
}
