import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/models/place/discovery_result.dart';
import 'package:navigation_client/models/place/outdoor_poi.dart';
import 'package:navigation_client/models/place/poi_search_result.dart';
import 'package:navigation_client/repositories/place/destination_repository.dart';
import 'package:navigation_client/repositories/building/mock_building_repository.dart';
import 'package:navigation_client/repositories/place/mock_destination_repository.dart';
import 'package:navigation_client/repositories/place/outdoor_poi_repository.dart';
import 'package:navigation_client/screens/map_shell/widgets/search/search_panel.dart';

/// 결과를 고정으로 돌려주는 야외 POI 리포지토리. 네트워크 없이 "바깥에서
/// 찾았다"는 상황만 만든다.
class _FakeOutdoorPoiRepository implements OutdoorPoiRepository {
  _FakeOutdoorPoiRepository(this.results);

  final List<OutdoorPoi> results;
  LatLng? lastCenter;
  int callCount = 0;

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
    return results;
  }
}

final _starbucks = OutdoorPoi(
  id: '1',
  name: '스타벅스 여의도점',
  point: const LatLng(37.5253, 126.9251),
  category: '커피전문점',
  address: '서울 영등포구 국제금융로 10',
  distanceMeters: 240,
);

void main() {
  final originalBuildingRepository = buildingRepository;
  final originalDestinationRepository = destinationRepository;
  final originalPoiRepository = outdoorPoiRepository;
  late _FakeOutdoorPoiRepository fakePoiRepository;

  setUp(() async {
    buildingRepository = MockBuildingRepository();
    destinationRepository = MockDestinationRepository(buildingRepository);
    fakePoiRepository = _FakeOutdoorPoiRepository([_starbucks]);
    outdoorPoiRepository = fakePoiRepository;
    // **에셋을 여기서 미리 읽어 둔다.** 목업 건물 저장소는 첫 호출에서
    // `rootBundle`을 타는데, 그 I/O는 위젯 테스트의 가짜 시계 안에서 끝나지
    // 않는다 — 미리 캐시를 채워 두면 테스트 본문에서는 메모리에서 답한다.
    await buildingRepository.getAllBuildings();
  });

  tearDown(() {
    buildingRepository = originalBuildingRepository;
    destinationRepository = originalDestinationRepository;
    outdoorPoiRepository = originalPoiRepository;
  });

  Future<void> pumpPanel(
    WidgetTester tester, {
    required String query,
    LatLng? center,
    bool indoorContextActive = false,
    ValueChanged<OutdoorPoi>? onPoiPicked,
    bool Function(LatLng point)? isInsideIndoorBuilding,
  }) async {
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
            // **이 값 하나가 결과의 출처를 가른다.** 거짓이면 TMAP만, 참이면
            // 우리 도면만 뒤진다(SearchPanel 주석).
            indoorContextActive: indoorContextActive,
            outdoorSearchCenter: center,
            onOutdoorPoiPicked: onPoiPicked ?? (_) {},
            // 좌표로 "우리 건물 것"을 가리는 신호. 안 넘기면 이름 신호만 남는다.
            isInsideIndoorBuilding: isInsideIndoorBuilding,
          ),
        ),
      ),
    );
    // 경량 검색 디바운스(300ms) + 의미 검색 대기(400ms)를 모두 지난다.
    await tester.pump(const Duration(milliseconds: 800));
    // **한 번으로는 모자란다.** 실외 경로는 TMAP 응답과 건물 목록(에셋 로드)을
    // 나란히 기다렸다가 한 번에 확정하므로, 그 사이에 마이크로태스크 몇 턴이
    // 낀다. 프레임을 몇 번 더 돌려 두 응답이 다 도착한 뒤를 본다.
    await tester.pumpAndSettle();
  }

  // 이 파일이 지키는 규칙 한 줄: **실외에서는 실외 결과만, 그것도 접지 않고.**
  // 예전에는 밖에서 검색해도 우리 도면을 먼저 뒤지고, 정작 주변 장소는
  // 「건물 밖 주변 N곳 보기」 버튼 뒤에 접혀 있었다 — 밖에 선 사람은 6층 매장
  // 한 줄과 버튼 하나를 답으로 받았다. 근거는 `search-result-list-ux.md` Y절.
  //
  // **예외는 하나뿐이고 맨 아래 그룹이 그것을 잰다** — 바깥 결과 자체가 우리
  // 건물을 가리킬 때. 그때는 우리 도면을 뒤지는 것이 아니라 이미 손에 있는 그
  // POI 한 줄을 우리 매장으로 바꿔 세우는 것이라, 위 규칙과 충돌하지 않는다.
  testWidgets('실외에서는 주변 장소를 접지 않고 바로 나열한다', (tester) async {
    await pumpPanel(
      tester,
      query: '스타벅스',
      center: const LatLng(37.5260, 126.9270),
    );

    expect(find.textContaining('스타벅스 여의도점'), findsOneWidget);
    // 층 대신 거리·주소로 어느 지점인지 가른다.
    expect(find.textContaining('약 240m'), findsOneWidget);
    expect(find.textContaining('국제금융로 10'), findsOneWidget);
    // 펼쳐 보라고 묻는 줄은 이제 없다.
    expect(find.byKey(const Key('show-outdoor')), findsNothing);
    expect(find.textContaining('보기'), findsNothing);
    expect(find.textContaining('찾지 못했어요'), findsNothing);
  });

  testWidgets('실외 목록은 출처(TMAP)와 개수를 머리말에 밝힌다', (tester) async {
    await pumpPanel(
      tester,
      query: '스타벅스',
      center: const LatLng(37.5260, 126.9270),
    );

    expect(find.text('주변 장소 1곳'), findsOneWidget);
    expect(find.text('TMAP'), findsOneWidget);
  });

  testWidgets('바깥 장소를 누르면 상위에 그 장소를 넘긴다', (tester) async {
    OutdoorPoi? picked;
    await pumpPanel(
      tester,
      query: '스타벅스',
      center: const LatLng(37.5260, 126.9270),
      onPoiPicked: (poi) => picked = poi,
    );

    await tester.tap(find.textContaining('스타벅스 여의도점'));
    await tester.pump();

    expect(picked?.name, '스타벅스 여의도점');
  });

  // **스크린샷으로 들어온 문제 그 자체.** 여의도 한복판에서 "강의실"을 쳤는데
  // 우리 도면의 `강의실 101 · 1F`가 첫 줄에 섰다 — 밖에 선 사람에게 건물 안
  // 1층 강의실은 답이 아니다.
  //
  // 승격 예외(맨 아래 그룹)가 이 줄을 무르지 않는다. 승격의 출발점은 **바깥
  // 결과**이고, 여기서 TMAP이 돌려준 것은 길 건너 스타벅스라 우리 건물을 가리키는
  // POI가 0건이다 — 사용자가 친 말로 우리 도면을 뒤지는 갈래는 여전히 없다.
  testWidgets('실외에서 친 말만으로는 우리 도면 매장이 서지 않는다', (tester) async {
    await pumpPanel(
      tester,
      query: '강의실',
      center: const LatLng(37.5260, 126.9270),
    );

    expect(find.textContaining('강의실 101'), findsNothing);
    expect(find.textContaining('강의실 201'), findsNothing);
    // 대신 주변 장소가 그 자리에 선다.
    expect(find.text('TMAP'), findsOneWidget);
  });

  testWidgets('실내에서는 우리 도면 매장이 선다', (tester) async {
    await pumpPanel(
      tester,
      query: '강의실',
      center: const LatLng(37.5260, 126.9270),
      indoorContextActive: true,
    );

    expect(find.textContaining('강의실 101'), findsOneWidget);
    expect(fakePoiRepository.callCount, 0);
  });

  // 짝이 되는 방향. 실내에서 TMAP을 부르면 "화장실"에 길 건너 편의점이 섞인다.
  testWidgets('실내에서는 바깥 검색을 아예 하지 않는다', (tester) async {
    await pumpPanel(
      tester,
      query: '스타벅스',
      center: const LatLng(37.5260, 126.9270),
      indoorContextActive: true,
    );

    expect(fakePoiRepository.callCount, 0);
    expect(find.textContaining('스타벅스 여의도점'), findsNothing);
    expect(find.text('TMAP'), findsNothing);
  });

  // **나갔다는 사실이 목록에 반영되는가.** GPS 판정·건물 밖 탭은 검색 패널이
  // 열려 있는 동안에도 실내/실외를 뒤집는데, 그때 재검색을 안 하면 밖으로 나온
  // 화면에 방금 전 실내 결과가 그대로 남는다 — "나간 걸 앱이 모른다"로 보인다.
  testWidgets('검색 중 건물을 나가면 그 자리에서 실외 결과로 갈아탄다', (tester) async {
    await pumpPanel(
      tester,
      query: '강의실',
      center: const LatLng(37.5260, 126.9270),
      indoorContextActive: true,
    );
    expect(
      find.textContaining('강의실 101'),
      findsOneWidget,
      reason: '테스트 전제(실내에서 우리 매장이 뜸)가 성립하지 않았다',
    );

    // 같은 검색어 그대로 실외로 나간다.
    await pumpPanel(
      tester,
      query: '강의실',
      center: const LatLng(37.5260, 126.9270),
    );

    expect(find.textContaining('강의실 101'), findsNothing);
    expect(find.text('TMAP'), findsOneWidget);
    expect(fakePoiRepository.callCount, 1);
  });

  testWidgets('검색 중 건물에 들어가면 그 자리에서 실내 결과로 갈아탄다', (tester) async {
    await pumpPanel(
      tester,
      query: '강의실',
      center: const LatLng(37.5260, 126.9270),
    );
    expect(
      find.text('TMAP'),
      findsOneWidget,
      reason: '테스트 전제(실외에서 주변 장소가 뜸)가 성립하지 않았다',
    );

    await pumpPanel(
      tester,
      query: '강의실',
      center: const LatLng(37.5260, 126.9270),
      indoorContextActive: true,
    );

    expect(find.textContaining('강의실 101'), findsOneWidget);
    expect(find.text('TMAP'), findsNothing);
  });

  testWidgets('기준점이 없으면 바깥 검색을 하지 않고 결론까지 낸다', (tester) async {
    await pumpPanel(tester, query: '없는말', center: null);

    expect(fakePoiRepository.callCount, 0);
    expect(find.text('TMAP'), findsNothing);
    // **스피너로 끝나면 안 된다.** 실외에서는 TMAP이 유일한 출처라, 못 부른
    // 것도 결론으로 옮겨 줘야 사용자가 다음 행동을 정할 수 있다.
    expect(find.textContaining('찾지 못했어요'), findsOneWidget);
  });

  testWidgets('검색 기준점을 그대로 리포지토리에 넘긴다', (tester) async {
    await pumpPanel(
      tester,
      query: '스타벅스',
      center: const LatLng(37.5260, 126.9270),
    );

    expect(fakePoiRepository.lastCenter, const LatLng(37.5260, 126.9270));
  });

  // **밖에서 안으로 잇는 유일한 예외.** 실외 목록은 원칙적으로 우리 도면을 안
  // 뒤지지만(바로 위 그룹), 바깥 결과 자체가 우리 건물을 가리키고 있으면 이야기가
  // 다르다 — 그 줄에는 층·노드가 없어 눌러도 실내 경로가 시작되지 않는다.
  // 규칙과 그 대가는 `search-result-list-ux.md` Y절 「예외」가 단일 출처다.
  group('우리 건물을 가리키는 바깥 결과만 우리 매장 줄로 선다', () {
    late _CountingDestinationRepository counting;

    setUp(() {
      counting = _CountingDestinationRepository([_reserveB2]);
      destinationRepository = counting;
    });

    testWidgets('건물 이름을 단 POI는 층·노드를 가진 우리 매장으로 바뀐다', (tester) async {
      fakePoiRepository = _FakeOutdoorPoiRepository([_starbucksAtDemo]);
      outdoorPoiRepository = fakePoiRepository;

      await pumpPanel(
        tester,
        query: '스타벅스',
        center: const LatLng(37.5665, 126.9779),
      );

      // 우리 줄이 서고, 같은 곳을 가리키던 TMAP 줄은 빠진다(X절 「우리 쪽으로」).
      expect(find.text('스타벅스 리저브', findRichText: true), findsOneWidget);
      expect(find.textContaining('스타벅스 데모건물점'), findsNothing);
      // 층이 붙어야 승격이 값을 한다 — 이 줄이 곧 실내 경로의 출처다.
      expect(find.textContaining('B2'), findsOneWidget);
      expect(counting.lightCalls, 1);
    });

    // **좁히는 조건이 규칙의 전부다.** 이게 없으면 글자마다 우리 도면에 왕복이
    // 나가고, Y절이 세운 「요청 자체를 안 보낸다」가 통째로 무너진다.
    testWidgets('우리 건물을 안 가리키는 POI뿐이면 도면에 묻지 않는다', (tester) async {
      // 길 건너 스타벅스다. 이름에 건물이 없고 좌표 판정 콜백도 없다.
      fakePoiRepository = _FakeOutdoorPoiRepository([_starbucks]);
      outdoorPoiRepository = fakePoiRepository;

      await pumpPanel(
        tester,
        query: '스타벅스',
        center: const LatLng(37.5665, 126.9779),
      );

      expect(counting.lightCalls, 0);
      expect(counting.semanticCalls, 0);
      expect(find.textContaining('스타벅스 여의도점'), findsOneWidget);
      expect(find.text('스타벅스 리저브', findRichText: true), findsNothing);
    });

    // 좌표 판정은 이름 신호의 짝이다(X절 「좌표와 이름을 OR로」). TMAP 지점명이
    // 건물 이름을 안 달고 있어도, 그 좌표가 우리 외곽선 안이면 우리 가게다.
    testWidgets('이름에 건물이 없어도 좌표가 우리 건물 안이면 승격한다', (tester) async {
      fakePoiRepository = _FakeOutdoorPoiRepository([_starbucks]);
      outdoorPoiRepository = fakePoiRepository;

      await pumpPanel(
        tester,
        query: '스타벅스',
        center: const LatLng(37.5665, 126.9779),
        isInsideIndoorBuilding: (_) => true,
      );

      expect(find.text('스타벅스 리저브', findRichText: true), findsOneWidget);
      expect(counting.lightCalls, 1);
    });

    // **안전장치를 낮추지 않는다.** 같은 브랜드가 층마다 있는데 지점명에 층
    // 힌트가 없으면 [matchIndoorStore]가 포기한다 — 잘못 고르면 사용자가 엉뚱한
    // 층에 도착한다. 그 경우 화면은 승격 전과 같은 TMAP 줄로 남는다.
    testWidgets('층을 가릴 수 없으면 승격하지 않고 바깥 줄로 남긴다', (tester) async {
      counting = _CountingDestinationRepository([_reserveB2, _reserve6F]);
      destinationRepository = counting;
      fakePoiRepository = _FakeOutdoorPoiRepository([_starbucksAtDemo]);
      outdoorPoiRepository = fakePoiRepository;

      await pumpPanel(
        tester,
        query: '스타벅스',
        center: const LatLng(37.5665, 126.9779),
      );

      expect(find.text('스타벅스 리저브', findRichText: true), findsNothing);
      expect(find.textContaining('스타벅스 데모건물점'), findsOneWidget);
    });

    // 머리말(`검색 결과 N · 층`)은 우리 매장만 센다. 승격된 줄이 둘 이상일 때
    // 그것이 TMAP 줄까지 포함한 목록 위에 서면 개수가 화면과 어긋난다 —
    // 실외에서 개수를 밝히는 자리는 섹션마다 따로 있다(`주변 장소 N곳`).
    testWidgets('승격된 줄이 둘이어도 실외 목록에 개수 머리말이 서지 않는다', (tester) async {
      counting = _CountingDestinationRepository([_reserveB2, _reserve6F]);
      destinationRepository = counting;
      // 같은 브랜드가 두 층에 있으므로 **양쪽 다 층 힌트가 있어야** 짝이 선다.
      fakePoiRepository = _FakeOutdoorPoiRepository([
        OutdoorPoi(
          id: '3',
          name: '스타벅스 데모건물점(B2)',
          point: const LatLng(37.5665, 126.9779),
        ),
        OutdoorPoi(
          id: '4',
          name: '스타벅스 데모건물점(6F)',
          point: const LatLng(37.5665, 126.9779),
        ),
      ]);
      outdoorPoiRepository = fakePoiRepository;

      await pumpPanel(
        tester,
        query: '스타벅스',
        center: const LatLng(37.5665, 126.9779),
      );

      // 전제부터 확인한다 — 한 줄만 승격되면 머리말은 어차피 안 서서
      // 이 테스트가 통과해도 아무것도 증명하지 못한다.
      expect(
        find.text('스타벅스 리저브', findRichText: true),
        findsNWidgets(2),
        reason: '테스트 전제(두 층이 모두 승격됨)가 성립하지 않았다',
      );
      expect(find.textContaining('검색 결과'), findsNothing);
    });

    // 노드가 없는 매장은 승격돼도 실내 경로를 못 그린다. 그런 매장을 목록에
    // 올리면 "도착"이 없는 줄만 남아, 사용자는 왜 안 되는지 모른 채 되돌아온다.
    testWidgets('노드가 없는 매장으로는 승격하지 않는다', (tester) async {
      counting = _CountingDestinationRepository([
        const PoiSearchResult(
          name: '스타벅스 리저브',
          floor: 'B2',
          point: LatLng(37.5665, 126.9779),
        ),
      ]);
      destinationRepository = counting;
      fakePoiRepository = _FakeOutdoorPoiRepository([_starbucksAtDemo]);
      outdoorPoiRepository = fakePoiRepository;

      await pumpPanel(
        tester,
        query: '스타벅스',
        center: const LatLng(37.5665, 126.9779),
      );

      expect(find.text('스타벅스 리저브', findRichText: true), findsNothing);
      expect(find.textContaining('스타벅스 데모건물점'), findsOneWidget);
    });
  });
}

/// 우리 건물(데모 건물) 안 스타벅스. 노드가 있어야 실내 경로가 그려진다.
const _reserveB2 = PoiSearchResult(
  name: '스타벅스 리저브',
  floor: 'B2',
  point: LatLng(37.5665, 126.9779),
  nodeId: 'node-b2-starbucks',
);

/// 같은 브랜드가 다른 층에도 있는 경우. 층 힌트가 없으면 짝을 못 고른다.
const _reserve6F = PoiSearchResult(
  name: '스타벅스 리저브',
  floor: '6F',
  point: LatLng(37.5665, 126.9779),
  nodeId: 'node-6f-starbucks',
);

/// 지점명에 건물 이름이 그대로 들어 있는 POI. `mentionsBuilding`이 잡는 신호다.
final _starbucksAtDemo = OutdoorPoi(
  id: '2',
  name: '스타벅스 데모건물점',
  point: const LatLng(37.5665, 126.9779),
  category: '커피전문점',
  address: '서울 중구 세종대로 110',
  distanceMeters: 30,
);

/// 이름으로 되묻는 요청이 실제로 나갔는지 세는 껍데기. 목록에 안 보이는 것과
/// 요청을 안 보낸 것은 다른 이야기라, 후자를 직접 확인한다.
class _CountingDestinationRepository implements DestinationRepository {
  _CountingDestinationRepository(this.stores);

  final List<PoiSearchResult> stores;
  int lightCalls = 0;
  int semanticCalls = 0;

  @override
  Future<List<PoiSearchResult>> searchDestinations(
    String buildingId,
    String query, {
    String? currentFloorId,
  }) async {
    lightCalls++;
    final needle = query.trim().toLowerCase();
    return stores
        .where((store) => store.name.toLowerCase().contains(needle))
        .toList();
  }

  @override
  Future<DiscoveryResult> searchDestinationsAi(
    String buildingId,
    String query, {
    String? currentFloorId,
    Map<String, List<String>>? selectedFacets,
    bool showAll = false,
  }) async {
    semanticCalls++;
    return DiscoveryResult(mode: DiscoveryMode.noMatch, query: query);
  }
}
