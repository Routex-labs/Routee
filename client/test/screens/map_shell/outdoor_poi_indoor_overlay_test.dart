import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/models/place/outdoor_poi.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/repositories/place/outdoor_poi_repository.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 호출 여부만 기록하는 스텁.
class _RecordingPoiRepository implements OutdoorPoiRepository {
  int callCount = 0;
  LatLng? lastCenter;

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
    lastCenter = center;
    return const [];
  }
}

// 데모 건물 입구 좌표 + 신호 저하. 이 두 건이 순서대로 흘러야 자동 실내 진입이
// 판정된다(widget_test.dart의 같은 픽스처와 규칙이 같다).
final _approaching = Position(
  latitude: 37.5665,
  longitude: 126.9779,
  timestamp: DateTime(2024, 1, 1),
  accuracy: 10,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

final _atEntrance = Position(
  latitude: 37.5665,
  longitude: 126.9779,
  timestamp: DateTime(2024, 1, 1),
  accuracy: 45,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

void main() {
  final originalBuildingRepository = buildingRepository;
  final originalDestinationRepository = destinationRepository;
  final originalPoiRepository = outdoorPoiRepository;
  late _RecordingPoiRepository recording;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await debugModeController.reload();
    requestStartupPermissions = () async => {};
    buildingRepository = MockBuildingRepository();
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

  // **이 테스트는 한 번 뒤집힌 규칙이다.** 원래는 반대를 지켰다: "실내 도면을
  // 보는 중이면 바깥 검색을 끈다"를 넣었더니 실기기에서 TMAP POI 검색이 한 번도
  // 실행되지 않았다. 폰에서는 실내 진입 임계 zoom이 화면 폭에 맞춰 내려가고
  // (indoor_entry_zoom.dart) 건물 근처에서는 GPS로도 자동 진입하므로, 그 조건이
  // 거의 항상 참이었기 때문이다. 그래서 한동안 실내에서도 바깥을 함께 찾았다.
  //
  // 지금은 다시 끈다. 섞어 놓으니 반대쪽이 깨졌다 — 밖에 서서 검색해도 건물 안
  // 매장이 먼저 서고 주변 장소는 버튼 뒤에 접혔다(`search-result-list-ux.md` Y절).
  // **대신 위 실패가 그대로 돌아오지 않게 하려면 밖으로 나오는 길이 있어야 한다.**
  // 지금은 줌아웃뿐이고, 그것이 이 규칙의 남은 비용이다(같은 절 「남은 비용」).
  testWidgets('실내 진입 오버레이가 켜져 있으면 건물 밖 검색을 하지 않는다', (tester) async {
    watchPosition = () => Stream.fromIterable([_approaching, _atEntrance]);

    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const MapShellScreen()));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    // 상단 검색창에 입력해 검색을 활성화한다. **목업 도면에 실제로 있는 이름**을
    // 친다 — 아무 말이나 치면 "검색이 안 돌아서 0"과 "실내만 뒤져서 0"이 같은
    // 결과가 되어, 이 테스트가 통과해도 아무것도 증명하지 못한다.
    await tester.enterText(find.byType(TextField).first, '강의실');
    // **두 번 나눠 pump한다.** 첫 pump에서 비로소 SearchPanel이 트리에 들어오고
    // 그때 디바운스 타이머가 걸리므로, 같은 pump의 남은 시간으로는 그 타이머가
    // 안 지나간다. 두 번째 pump가 300ms 디바운스를 넘긴다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 검색이 실제로 돌았고(우리 도면에서 찾았고), TMAP은 안 불렀다.
    expect(find.textContaining('강의실 101'), findsOneWidget);
    expect(
      recording.callCount,
      0,
      reason: '실내 오버레이 상태에서는 결과를 우리 도면에서만 찾아야 한다',
    );
  });
}
