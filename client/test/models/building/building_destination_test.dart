import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/models/building/building.dart';
import 'package:navigation_client/models/place/discovery_result.dart';
import 'package:navigation_client/models/place/outdoor_poi.dart';
import 'package:navigation_client/models/place/poi_search_result.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/repositories/place/outdoor_poi_repository.dart';
import 'package:navigation_client/screens/map_shell/widgets/search/search_panel.dart';

/// **밖에서 검색했을 때 목록에 무엇이 올라오는가**에 대한 테스트.
///
/// 규칙은 한 줄이다 — 밖에서도 건물 안 매장을 그대로 찾고, 건물 줄도 함께
/// 올린다. 무엇을 골랐느냐가 곧 어디까지 안내할지를 정하므로(매장이면 문을
/// 경유해 그 매장까지, 건물이면 입구까지) 화면이 의도를 되묻지 않는다.
///
/// 함께 고정하는 것: 건물을 가리킬 좌표([Building.outdoorAnchor])와, 같은 곳을
/// 두 번 보여주지 않기 위한 중복 제거.
void main() {
  group('Building.outdoorAnchor', () {
    test('출입구 좌표가 있으면 그것을 쓴다', () {
      const building = Building(
        id: 'b',
        name: '건물',
        floors: ['1F'],
        entrance: LatLng(37.5, 126.9),
        footprintWgs84: [
          LatLng(37.0, 126.0),
          LatLng(37.0, 127.0),
          LatLng(38.0, 127.0),
          LatLng(38.0, 126.0),
        ],
      );

      expect(building.outdoorAnchor, const LatLng(37.5, 126.9));
    });

    test('출입구가 없으면 외곽선 중심으로 떨어진다', () {
      // 백엔드가 출입구 좌표를 안 내려주는 지금 상태다. 폴백이 없으면 건물이
      // 길찾기 후보 목록에서 통째로 사라진다.
      const building = Building(
        id: 'b',
        name: '건물',
        floors: ['1F'],
        footprintWgs84: [
          LatLng(37.0, 126.0),
          LatLng(37.0, 127.0),
          LatLng(38.0, 127.0),
          LatLng(38.0, 126.0),
        ],
      );

      expect(building.outdoorAnchor, const LatLng(37.5, 126.5));
    });

    test('출입구도 외곽선도 없으면 null이다', () {
      const building = Building(id: 'b', name: '건물', floors: ['1F']);

      expect(building.outdoorAnchor, isNull);
    });
  });

  group('검색 결과 중복', () {
    final originalBuildingRepository = buildingRepository;
    final originalDestinationRepository = destinationRepository;
    final originalPoiRepository = outdoorPoiRepository;

    setUp(() async {
      buildingRepository = MockBuildingRepository();
      await buildingRepository.getAllBuildings();
      destinationRepository = MockDestinationRepository(buildingRepository);
    });

    tearDown(() {
      buildingRepository = originalBuildingRepository;
      destinationRepository = originalDestinationRepository;
      outdoorPoiRepository = originalPoiRepository;
    });

    Future<void> pumpPanel(WidgetTester tester, String query) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: Scaffold(
            body: SearchPanel(
              buildingId: 'thehyundai-seoul',
              query: query,
              submitTick: 0,
              onStorePicked: (_) {},
              onBuildingPicked: (_) {},
              onQueryPicked: (_) {},
              onSuggestionPicked: (_) {},
              indoorContextActive: false,
              outdoorSearchCenter: const LatLng(37.5665, 126.9779),
              onOutdoorPoiPicked: (_) {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 800));
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
    }

    testWidgets('건물 줄과 같은 곳을 가리키는 바깥 결과는 빠진다', (tester) async {
      // TMAP도 같은 건물을 POI 한 건으로 돌려준다. 두 줄이 나란히 뜨면 헷갈리는
      // 것으로 끝나지 않고, 아래쪽을 누른 사용자는 건물 안으로 못 들어간다.
      outdoorPoiRepository = _FakeOutdoorPoiRepository([
        OutdoorPoi(
          id: '1',
          // 띄어쓰기가 달라도 같은 곳으로 본다.
          name: '데모건물',
          point: const LatLng(37.5665, 126.9779),
        ),
      ]);

      await pumpPanel(tester, '데모 건물');

      // 이름은 검색어 강조 때문에 Text.rich로 그려지므로 findRichText가 필요하다.
      expect(find.text('데모 건물', findRichText: true), findsOneWidget);
      expect(find.text('데모건물', findRichText: true), findsNothing);
      // 남길 바깥 줄이 하나도 없으므로 머리말도 서지 않는다.
      expect(find.text('TMAP'), findsNothing);
    });

    testWidgets('이름이 다른 바깥 결과는 그대로 남는다', (tester) async {
      // 중복을 지우려다 "건물 이름을 앞에 단 진짜 매장"까지 지우면 훨씬 나쁘다.
      outdoorPoiRepository = _FakeOutdoorPoiRepository([
        OutdoorPoi(
          id: '1',
          name: '데모 건물 스타벅스',
          point: const LatLng(37.5665, 126.9779),
        ),
      ]);

      await pumpPanel(tester, '데모 건물');

      // 실외 목록은 접지 않는다 — 묻는 줄 없이 바로 선다.
      expect(find.text('주변 장소 1곳'), findsOneWidget);
      expect(find.textContaining('스타벅스', findRichText: true), findsOneWidget);
    });
  });

  // **한 번 뒤집힌 그룹이다.** 예전에는 "밖에서도 건물 안 매장을 찾는다"였다 —
  // 밖에서 "루이비통"을 치는 사람에게 층·노드까지 붙여 주자는 것이었다. 그런데
  // 그 결과가 실외 목록의 첫 줄을 차지하면서, 눈앞의 건물과 주변 가게가 「더
  // 보기」 뒤로 밀렸다(`search-result-list-ux.md` Y절).
  //
  // 밖에서 안으로 가는 길이 사라진 것은 아니다. 목적지를 고르는 자리는 길찾기
  // 도착지 칸으로 옮겼고, 그쪽은 여전히 실내·건물·바깥을 함께 뒤진다
  // (`directions_candidates.dart`).
  group('실외에서는 건물 안 매장을 뒤지지 않는다', () {
    final originalBuildingRepository = buildingRepository;
    final originalDestinationRepository = destinationRepository;
    final originalPoiRepository = outdoorPoiRepository;
    late _CountingDestinationRepository counting;

    setUp(() async {
      buildingRepository = MockBuildingRepository();
      // asset을 미리 읽어 캐시를 채운다. 안 하면 패널 안에서 도는 첫 조회가
      // 진짜 파일 I/O라 pump 몇 번으로는 안 끝나고, 화면이 스피너에 멈춘 채로
      // 단언에 걸린다 — 코드가 아니라 테스트가 못 기다린 것이다.
      await buildingRepository.getAllBuildings();
      counting = _CountingDestinationRepository(
        MockDestinationRepository(buildingRepository),
      );
      destinationRepository = counting;
      outdoorPoiRepository = _FakeOutdoorPoiRepository(const []);
    });

    tearDown(() {
      buildingRepository = originalBuildingRepository;
      destinationRepository = originalDestinationRepository;
      outdoorPoiRepository = originalPoiRepository;
    });

    testWidgets('밖에서 매장 이름을 쳐도 우리 도면에 묻지 않는다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: Scaffold(
            body: SearchPanel(
              buildingId: 'thehyundai-seoul',
              query: '강의실',
              submitTick: 0,
              onStorePicked: (_) {},
              onBuildingPicked: (_) {},
              onQueryPicked: (_) {},
              onSuggestionPicked: (_) {},
              indoorContextActive: false,
              // 밖을 보고 있다는 뜻(야외 기준점이 있고 층은 없다).
              outdoorSearchCenter: const LatLng(37.5665, 126.9779),
              onOutdoorPoiPicked: (_) {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 800));
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }

      // 화면에서 숨기는 게 아니라 **요청 자체를 안 보낸다.** 숨기기만 하면
      // 글자마다 쓸모없는 왕복이 남는다.
      expect(counting.lightCalls, 0);
      expect(counting.semanticCalls, 0);
      expect(find.text('강의실 101', findRichText: true), findsNothing);
    });
  });
}

/// 실내 검색이 실제로 나갔는지 세는 껍데기. "화면에 안 보인다"와 "요청을 안
/// 보냈다"는 다른 이야기라, 후자를 직접 확인한다.
class _CountingDestinationRepository implements DestinationRepository {
  _CountingDestinationRepository(this.inner);

  final DestinationRepository inner;
  int lightCalls = 0;
  int semanticCalls = 0;

  @override
  Future<List<PoiSearchResult>> searchDestinations(
    String buildingId,
    String query, {
    String? currentFloorId,
  }) {
    lightCalls++;
    return inner.searchDestinations(
      buildingId,
      query,
      currentFloorId: currentFloorId,
    );
  }

  @override
  Future<DiscoveryResult> searchDestinationsAi(
    String buildingId,
    String query, {
    String? currentFloorId,
    Map<String, List<String>>? selectedFacets,
    bool showAll = false,
  }) {
    semanticCalls++;
    return inner.searchDestinationsAi(
      buildingId,
      query,
      currentFloorId: currentFloorId,
      selectedFacets: selectedFacets,
      showAll: showAll,
    );
  }
}

/// 결과를 고정으로 돌려주는 야외 POI 리포지토리.
class _FakeOutdoorPoiRepository implements OutdoorPoiRepository {
  _FakeOutdoorPoiRepository(this.results);

  final List<OutdoorPoi> results;

  @override
  bool get isAvailable => true;

  @override
  Future<List<OutdoorPoi>> searchNearby(
    String keyword, {
    required LatLng center,
    int radiusMeters = 1000,
    int limit = 10,
  }) async => results;
}
