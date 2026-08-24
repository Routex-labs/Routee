import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/place/outdoor_poi.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/repositories/place/outdoor_poi_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_screen.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **실내에서 이 건물에 없는 이름을 쳤을 때 화면이 막다른 길이 아닌가.**
///
/// 지키려는 증상: 실내 도면을 보는 중에 `계양도서관`을 치면 상단 검색은 TMAP을
/// 부르지 않으므로(`search-result-list-ux.md` Y절) 영원히 0건이다. 그리고 실내에서
/// 나오는 길은 줌아웃뿐인데, 검색 패널이 떠 있는 동안은 지도 제스처가 잠겨 있어
/// 그마저 막혀 있다 — 사용자가 할 수 있는 일이 검색을 닫는 것밖에 없었다.
///
/// 그래서 "찾지 못했어요" 화면에 나가는 버튼 하나를 뒀다. 이 파일이 그 버튼이
/// **실내에서만 서고, 누르면 실제로 밖에서 같은 말로 다시 찾는지**를 잰다.
void main() {
  final originalBuildingRepository = buildingRepository;
  final originalDestinationRepository = destinationRepository;
  final originalPoiRepository = outdoorPoiRepository;
  late _RecordingPoiRepository recording;

  /// 데모 건물에서 조금 떨어진 좌표. 여기서 GPS가 실내를 판정하면 이 테스트가
  /// 재려는 것(버튼이 뒤집는 상태)과 GPS가 뒤집는 상태를 구분할 수 없다.
  Position fix() => Position(
    latitude: 37.5665,
    longitude: 126.9800,
    timestamp: DateTime(2024, 1, 1),
    accuracy: 10,
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
    requestStartupPermissions = () async => {};
    watchPosition = () => Stream.value(fix());
    buildingRepository = MockBuildingRepository();
    await buildingRepository.getAllBuildings();
    destinationRepository = MockDestinationRepository(buildingRepository);
    recording = _RecordingPoiRepository();
    outdoorPoiRepository = recording;
  });

  tearDown(() {
    requestStartupPermissions = defaultRequestStartupPermissions;
    watchPosition = defaultWatchPosition;
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    outdoorPoiRepository = originalPoiRepository;
  });

  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpShell(WidgetTester tester, {required bool indoor}) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MapShellScreen()),
    );
    await drain(tester);
    if (indoor) {
      tester
          .state<OutdoorMapBodyState>(find.byType(OutdoorMapBody))
          // ignore: invalid_use_of_visible_for_testing_member
          .enterIndoorForTest();
      await drain(tester);
    }
  }

  Future<void> type(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField).first, query);
    await tester.pump();
    await drain(tester);
  }

  testWidgets('실내에서 못 찾으면 밖으로 나가는 버튼이 선다', (tester) async {
    await pumpShell(tester, indoor: true);
    await type(tester, '계양도서관');

    expect(
      find.textContaining('찾지 못했어요'),
      findsOneWidget,
      reason: '테스트 전제(실내에서 이 이름을 못 찾음)가 성립하지 않았다',
    );
    expect(recording.callCount, 0, reason: '실내에서 TMAP을 불렀다');
    expect(find.byKey(const Key('search-outside')), findsOneWidget);
  });

  // **실외에는 나갈 곳이 없다.** 그 화면의 "찾지 못했어요"는 TMAP까지 뒤진 뒤의
  // 결론이라, 같은 버튼을 두면 아무 일도 안 일어나는 버튼이 된다.
  testWidgets('이미 실외면 그 버튼이 서지 않는다', (tester) async {
    await pumpShell(tester, indoor: false);
    // 밖에서도 빈손인 말을 친다. TMAP까지 뒤지고 못 찾은 화면이라야
    // "그래도 버튼은 없다"가 무언가를 증명한다.
    await type(tester, '없는말');

    expect(
      find.textContaining('찾지 못했어요'),
      findsOneWidget,
      reason: '테스트 전제(실외에서도 못 찾음)가 성립하지 않았다',
    );
    expect(find.byKey(const Key('search-outside')), findsNothing);
  });

  // **버튼의 값은 여기에 있다.** 나가기만 하고 검색어를 잃으면 사용자가 다시
  // 쳐야 하고, 그러면 줌아웃과 다를 것이 없다.
  testWidgets('누르면 밖으로 나가 같은 검색어로 다시 찾는다', (tester) async {
    await pumpShell(tester, indoor: true);
    await type(tester, '계양도서관');
    expect(recording.callCount, 0);

    await tester.tap(find.byKey(const Key('search-outside')));
    await drain(tester);

    // 버튼이 사라진 것이 곧 실내 상태가 풀렸다는 뜻이다 — 이 버튼은
    // `indoorContextActive`가 참일 때만 그려진다.
    expect(find.byKey(const Key('search-outside')), findsNothing);
    // 검색어를 그대로 들고 실외 검색이 실제로 나갔다.
    expect(recording.lastKeyword, '계양도서관');
    expect(find.text('계양도서관 본관', findRichText: true), findsOneWidget);
    // 그리고 그 줄은 눌러서 갈 수 있는 줄이다.
    expect(find.text('TMAP'), findsOneWidget);
  });

  // **찾았을 때는 서면 안 된다.** 이 버튼은 "찾지 못했어요" 화면의 조각이라,
  // 결과가 있는데도 뜨면 사용자에게 "여기 있는 것도 진짜가 아닌가" 하는 줄이 된다.
  testWidgets('실내에서 찾았으면 그 버튼이 서지 않는다', (tester) async {
    await pumpShell(tester, indoor: true);
    await type(tester, '강의실');

    expect(
      find.textContaining('강의실 101'),
      findsOneWidget,
      reason: '테스트 전제(실내에서 우리 매장이 뜸)가 성립하지 않았다',
    );
    expect(find.byKey(const Key('search-outside')), findsNothing);
  });
}

/// 검색어를 기록하고 건물 밖 장소 한 건을 돌려준다. "밖에는 답이 있다"는 상황만
/// 만든다 — 실내에서는 이 값이 화면에 서면 안 된다.
class _RecordingPoiRepository implements OutdoorPoiRepository {
  int callCount = 0;
  String? lastKeyword;

  @override
  bool get isAvailable => true;

  @override
  Future<List<OutdoorPoi>> searchNearby(
    String keyword, {
    required LatLng center,
    int radiusMeters = 1000,
    int limit = 10,
  }) async {
    callCount++;
    lastKeyword = keyword;
    // **검색어를 그대로 흘려보내지 않는다.** 무슨 말을 쳐도 한 건이 나오면
    // "밖에서도 못 찾은 화면"을 만들 수 없다.
    if (keyword != '계양도서관') return const [];
    return const [
      OutdoorPoi(
        id: 'lib-1',
        name: '계양도서관 본관',
        point: LatLng(37.5400, 126.7300),
        category: '도서관',
      ),
    ];
  }
}
