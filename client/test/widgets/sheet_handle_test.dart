import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/core/api_config.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/models/place/favorite_place.dart';
import 'package:navigation_client/models/place/outdoor_poi.dart';
import 'package:navigation_client/repositories/building/building_repository.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/app_menu_sheet.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/building_info_sheet.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/category_stores_sheet.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/favorites_sheet.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/outdoor_poi_sheet.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/place_detail_sheet.dart';
import 'package:routex_design_system/routex_design_system.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 손잡이가 **끌 수 있는 시트에만** 있는지 시트마다 열어 확인한다.
///
/// 손잡이는 장식이 아니라 "끌어서 크기를 바꿀 수 있다"는 약속이다. 없으면 목록이
/// 잘려 있어도 위로 끌 수 있다는 걸 모르고, 있는데 끌리지 않으면 눌러도 아무 일이
/// 없는 표시가 된다. 둘 다 화면만 봐서는 멀쩡해 보이는 실패라 여기서 못 박는다.
///
/// **기대가 한 번 뒤집혔다.** 예전에는 시트마다 손잡이를 두고 "빠지지 않는지"만 봤다.
/// 저장한 장소·앱 메뉴·매장 무리 시트는 실제로는 끌 수 없어(각 파일의 주석 참고) 약속만
/// 남아 있었다. 판정 기준은 포팅 가이드 단계 3 — 실제 min/max extent 사이를 끌 수 있는
/// 시트에만 하나 둔다.
///
/// 이 파일은 `lib/`의 한 파일을 비추지 않는다. 손잡이 계약이 시트 여덟에 걸쳐 있어서다.
void main() {
  late BuildingRepository originalBuildingRepository;
  late DestinationRepository originalDestinationRepository;

  final repository = MockBuildingRepository();

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    originalBuildingRepository = buildingRepository;
    originalDestinationRepository = destinationRepository;
    buildingRepository = repository;
    destinationRepository = MockDestinationRepository(repository);
    // asset 캐시를 미리 채운다. 위젯 테스트의 가짜 시계는 실제 파일 I/O를
    // 기다려 주지 않아, 캐시가 비어 있으면 시트가 로딩 상태에 머문다.
    await repository.getAllBuildings();
  });

  tearDown(() {
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
  });

  final grabHandle = find.byType(RoutexSheetHandle);

  /// [open]이 여는 시트를 띄운다.
  Future<void> openSheet(
    WidgetTester tester,
    void Function(BuildContext context) open,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => open(context),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  void openPlaceDetail(BuildContext context) => PlaceDetailSheet.show(
    context,
    target: ValueNotifier(
      // 상세를 부르지 않는 경로(구버전 저장 항목)로 열어 손잡이만 본다.
      const PlaceDetailTarget(title: 'MLB', subtitle: 'B2', placeId: null),
    ),
    buildingId: demoBuildingId,
    onCloseAll: () {},
  );

  group('끌 수 있는 시트에는 손잡이가 하나 있다', () {
    testWidgets('매장 상세', (WidgetTester tester) async {
      await openSheet(tester, openPlaceDetail);

      expect(grabHandle, findsOneWidget);
    });

    testWidgets('카테고리 매장 목록', (WidgetTester tester) async {
      await openSheet(
        tester,
        (context) => CategoryStoresSheet.show(
          context,
          buildingId: demoBuildingId,
          category: '패션',
          onCloseAll: () {},
        ),
      );

      expect(grabHandle, findsOneWidget);
    });

    testWidgets('건물 정보', (WidgetTester tester) async {
      final building = (await repository.getAllBuildings()).first;
      await openSheet(
        tester,
        (context) => BuildingInfoSheet.show(
          context,
          building: building,
          onCloseAll: () {},
        ),
      );

      expect(grabHandle, findsOneWidget);
    });

    testWidgets('야외 장소', (WidgetTester tester) async {
      await openSheet(
        tester,
        (context) => OutdoorPoiSheet.show(
          context,
          poi: const OutdoorPoi(
            id: 'poi-1',
            name: '여의도역',
            point: LatLng(37.521, 126.924),
          ),
          onCloseAll: () {},
        ),
      );

      expect(grabHandle, findsOneWidget);
    });

    testWidgets('손잡이는 시트 콘텐츠보다 위에 그려진다', (WidgetTester tester) async {
      // 자리를 안 지키면(예: 헤더 아래) 표시의 의미가 사라진다. 매장 상세 시트를
      // 기준으로 세로 위치를 고정한다.
      await openSheet(tester, openPlaceDetail);

      final handleBottom = tester.getRect(grabHandle).bottom;
      final titleTop = tester.getRect(find.text('MLB')).top;
      expect(
        handleBottom,
        lessThanOrEqualTo(titleTop),
        reason: '손잡이와 첫 콘텐츠는 붙을 수는 있어도 겹치면 안 된다',
      );
    });
  });

  group('끌 수 없는 시트에는 손잡이가 없다', () {
    testWidgets('저장한 장소', (WidgetTester tester) async {
      await openSheet(
        tester,
        (context) => FavoritesSheet.show(context, onCloseAll: () {}),
      );

      expect(find.text('저장한 장소'), findsOneWidget, reason: '시트는 떴다');
      expect(grabHandle, findsNothing);
    });

    // 비어 있을 때만 확인하면 "목록이 생기면 손잡이도 같이 돌아오는" 회귀를 못 잡는다.
    testWidgets('저장한 장소 — 항목이 있어도 생기지 않는다', (WidgetTester tester) async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await favoritesController.add(
        const FavoritePlace(
          name: 'MLB',
          floor: 'B2',
          buildingId: demoBuildingId,
          lat: 37.52,
          lng: 126.92,
        ),
      );

      await openSheet(
        tester,
        (context) => FavoritesSheet.show(context, onCloseAll: () {}),
      );

      expect(find.text('MLB'), findsOneWidget, reason: '목록이 그려졌다');
      expect(grabHandle, findsNothing);
    });

    testWidgets('앱 메뉴', (WidgetTester tester) async {
      await openSheet(
        tester,
        (context) => AppMenuSheet.show(
          context,
          showPlaceLocation: true,
          debugEnabled: false,
        ),
      );

      expect(find.text('메뉴'), findsOneWidget, reason: '시트는 떴다');
      expect(grabHandle, findsNothing);
    });
  });
}
