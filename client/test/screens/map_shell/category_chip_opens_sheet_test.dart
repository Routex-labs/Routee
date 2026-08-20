import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/models/building/category_count.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/category_stores_sheet.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/place_detail_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 지도 위 대분류 chip을 누르면 **그 자리에서** 매장 목록 시트가 뜨는지 고정한다.
///
/// 예전에는 chip → 소분류 pill 줄 → 「목록」 버튼까지 세 번을 눌러야 이름을 볼
/// 수 있었다. 지도 강조는 "저 파란 칸이 뭔지"에 답하지 못하는데 정작 답이 있는
/// 목록이 가장 멀었다. 중간 단계가 다시 끼어들면 이 회귀가 그대로 돌아온다.
void main() {
  late BuildingRepository originalBuilding;
  late DestinationRepository originalDestination;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    originalBuilding = buildingRepository;
    originalDestination = destinationRepository;
    final repository = _CategorizedBuildingRepository();
    buildingRepository = repository;
    destinationRepository = MockDestinationRepository(repository);
    // asset 캐시를 미리 채운다. 위젯 테스트의 가짜 시계는 실제 파일 I/O를
    // 기다려 주지 않아, 캐시가 비어 있으면 칩 줄이 뜨지 않는다.
    await repository.getAllBuildings();
  });

  tearDown(() {
    buildingRepository = originalBuilding;
    destinationRepository = originalDestination;
  });

  testWidgets('카테고리 chip을 누르면 매장 목록 시트가 바로 뜬다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await tester.pumpAndSettle();
    // 카테고리 칩 줄은 셸이 그리고, 건물 안을 보고 있을 때만 뜬다. 예전에는
    // 하단 '실내' 세그먼트를 눌렀는데, 실내가 별도 탭이 아니게 되면서 진입
    // 자체가 오버레이를 켜는 일이 됐다.
    tester
        .state<OutdoorMapBodyState>(find.byType(OutdoorMapBody))
        // ignore: invalid_use_of_visible_for_testing_member
        .enterIndoorForTest();
    await tester.pumpAndSettle();

    expect(find.text('서비스'), findsOneWidget);
    await tester.tap(find.text('서비스'));
    await tester.pumpAndSettle();

    // 시트 고유의 표시 — 매장 이름.
    expect(find.text('우리은행 ATM'), findsOneWidget);
    // 시트 안 검색창은 없앴다. 상단 바에 이미 검색이 있는데 시트가 또 하나를
    // 들고 있으면 같은 일을 하는 입력이 화면에 둘이 된다(상단 바 것은 남는다).
    expect(
      find.descendant(
        of: find.byType(CategoryStoresSheet),
        matching: find.byType(TextField),
      ),
      findsNothing,
    );
    // 지도 위 「목록」 버튼은 사라졌다. 시트가 바로 뜨는데 한 단계를 더 두면
    // 같은 목적지로 가는 길이 두 개가 된다.
    expect(find.text('목록'), findsNothing);
  });

  testWidgets('검색이나 경로 위치를 입력하는 동안 지도 카테고리 칩을 숨긴다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await tester.pumpAndSettle();
    tester
        .state<OutdoorMapBodyState>(find.byType(OutdoorMapBody))
        // ignore: invalid_use_of_visible_for_testing_member
        .enterIndoorForTest();
    await tester.pumpAndSettle();

    expect(find.text('서비스'), findsOneWidget);
    await tester.tap(find.byTooltip('길찾기'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('route-draft-destination')), findsOneWidget);
    expect(find.text('서비스'), findsNothing);
  });

  // 목록이 떠 있는 동안 위쪽 지도를 만질 수 있어야 한다. barrier는 투명해도
  // opaque라 포인터를 전부 흡수하므로, 남아 있으면 "지도는 보이는데 끌리지도
  // 확대되지도 않는" 화면이 된다 — 상세 시트가 이미 겪고 고친 증상이다.
  // ([MapPassThroughSheetRoute])
  testWidgets('목록이 떠 있어도 위쪽 지도로 포인터가 지나간다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await tester.pumpAndSettle();
    tester
        .state<OutdoorMapBodyState>(find.byType(OutdoorMapBody))
        // ignore: invalid_use_of_visible_for_testing_member
        .enterIndoorForTest();
    await tester.pumpAndSettle();
    // 홈 페이지 라우트도 자기 barrier를 하나 갖는다(포인터를 막지 않는다).
    // 그래서 "0개"가 아니라 **시트를 열어도 늘지 않는 것**을 잰다.
    final before = find.byType(ModalBarrier).evaluate().length;

    await tester.tap(find.text('서비스'));
    await tester.pumpAndSettle();

    expect(find.byType(CategoryStoresSheet), findsOneWidget);
    expect(find.byType(ModalBarrier).evaluate().length, before);
  });

  // 예전에는 여기가 loop여서 상세를 닫으면 카테고리 목록이 다시 올라왔다.
  // 여러 매장을 훑는 흐름을 노린 것이었지만, 사용자에게는 매장 하나를 눌렀을
  // 뿐인데 시트가 겹겹이 쌓인 것으로 읽혔다. 상세는 그 매장 하나를 보는 자리이고,
  // 닫으면 지도로 끝난다.
  testWidgets('상세를 닫으면 카테고리 목록으로 돌아가지 않는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await tester.pumpAndSettle();
    // 위 테스트와 같은 이유로 세그먼트가 아니라 오버레이를 직접 켠다.
    tester
        .state<OutdoorMapBodyState>(find.byType(OutdoorMapBody))
        // ignore: invalid_use_of_visible_for_testing_member
        .enterIndoorForTest();
    await tester.pumpAndSettle();
    await tester.tap(find.text('서비스'));
    await tester.pumpAndSettle();

    // 목록에서 매장을 고르면 목록이 닫히고 상세가 뜬다.
    await tester.tap(find.text('우리은행 ATM'));
    await tester.pumpAndSettle();
    expect(find.byType(CategoryStoresSheet), findsNothing);
    expect(find.byType(PlaceDetailSheet), findsOneWidget);

    // 상세는 이제 이름 옆 X가 바로 전체 chain을 닫는 공용 계약이다.
    // 상세를 닫을 때 이전 카테고리 목록이 다시 올라오지 않아야 한다.
    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();

    expect(find.byType(PlaceDetailSheet), findsNothing);
    expect(find.byType(CategoryStoresSheet), findsNothing);
  });
}

/// 목업 asset 건물에 대분류가 붙은 매장을 얹는다.
/// `assets/mock/sample_building.json`에는 category가 달린 매장이 하나도 없어
/// 그대로 쓰면 칩 줄 자체가 뜨지 않는다.
class _CategorizedBuildingRepository extends MockBuildingRepository {
  static const _storesByFloor = {
    '1F': ['우리은행 ATM'],
    '2F': ['신한은행 ATM'],
  };

  @override
  Future<List<CategoryCount>?> getCategoryCounts(String buildingId) async => [
    for (final entry in _storesByFloor.entries)
      CategoryCount(
        floor: entry.key,
        category: '서비스',
        subcategory: 'ATM',
        count: entry.value.length,
      ),
  ];

  @override
  Future<Map<String, dynamic>?> getFloorGeoJson(
    String buildingId,
    String floor,
  ) async {
    final names = _storesByFloor[floor] ?? const <String>[];
    return {
      'footprint_wgs84': <dynamic>[],
      'stores': [
        for (var i = 0; i < names.length; i++)
          {
            'id': '$floor-$i',
            'name': names[i],
            'category': '서비스',
            'subcategory': 'ATM',
            'centroid_wgs84': {'lat': 37.5665, 'lng': 126.978},
          },
      ],
      'pois': <dynamic>[],
    };
  }
}
