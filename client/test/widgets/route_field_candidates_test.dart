import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/route/dijkstra.dart';
import 'package:navigation_client/domain/search/store_suggestions.dart';
import 'package:navigation_client/models/place/store_index_entry.dart';
import 'package:navigation_client/models/route/directions_candidate.dart';
import 'package:navigation_client/screens/map_shell/widgets/search/route_field_results.dart';
import 'package:navigation_client/models/route/route_plan_mode.dart';

/// 상단 길찾기 바의 **후보 목록**이 무엇을 보여 주는지 고정하는 테스트.
///
/// 이 규칙들은 한동안 길찾기 시트가 들고 있었다(`directions_sheet.dart`).
/// 길찾기가 상단 바 두 칸으로 돌아오면서 그 시트를 걷어냈으므로, 시트가 지키던
/// 계약을 여기서 이어받는다 — 규칙이 화면을 옮겼을 뿐 없어진 것이 아니다.
///
/// 출발↔도착 교체는 여기서 보지 않는다. 그 규칙은 화면이 아니라 도메인
/// (`route_endpoint_swap.dart`)에 있고, 두 칸 흐름까지 함께 태우는 검증은
/// `route_endpoint_swap_test`가 맡는다.
void main() {
  group('후보 목록이 보여 주는 것', () {
    const point = LatLng(37.5, 127.0);

    Future<void> pumpResults(
      WidgetTester tester, {
      List<DirectionsCandidate> results = const [],
      List<StoreSuggestion> suggestions = const [],
      Map<String, NodeReach>? reachByNodeId,
      RoutePlanField field = RoutePlanField.destination,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: RouteFieldResults(
              field: field,
              results: results,
              suggestions: suggestions,
              onSuggestionPicked: (_) {},
              reachByNodeId: reachByNodeId,
              searching: false,
              onPicked: (_) {},
              onCurrentLocation: () {},
            ),
          ),
        ),
      );
    }

    testWidgets('거리를 알면 후보 줄에 "몇 m · 도보 몇 분"이 붙는다', (tester) async {
      await pumpResults(
        tester,
        results: const [
          DirectionsCandidate(
            title: 'MLB',
            subtitle: 'B2',
            point: point,
            nodeId: 'n-1',
            floor: 'B2',
          ),
        ],
        reachByNodeId: const {'n-1': NodeReach(distanceM: 120, costM: 120)},
      );

      expect(find.textContaining('120m'), findsOneWidget);
    });

    testWidgets('거리를 모르면 그 줄을 아예 그리지 않는다', (tester) async {
      // 줄마다 "거리 알 수 없음"을 반복하면 목록이 읽히지 않는다. 상단 검색
      // 결과와 같은 규칙이다.
      await pumpResults(
        tester,
        results: const [
          DirectionsCandidate(
            title: 'MLB',
            subtitle: 'B2',
            point: point,
            nodeId: 'n-1',
            floor: 'B2',
          ),
        ],
      );

      expect(find.textContaining('도보'), findsNothing);
      expect(find.text('B2'), findsOneWidget);
    });

    testWidgets('노드가 없는 실내 후보는 경로 안내 불가라고 미리 알린다', (tester) async {
      // 고를 수는 있게 둔다 — 위치는 지도에 보여줄 수 있다. 대신 눌러도 경로가
      // 안 나오는 이유를 목록에서 먼저 읽을 수 있어야 한다.
      await pumpResults(
        tester,
        results: const [
          DirectionsCandidate(
            title: '창고',
            subtitle: 'B2',
            point: point,
            floor: 'B2',
          ),
        ],
      );

      expect(find.textContaining('경로 안내 불가'), findsOneWidget);
    });

    testWidgets('추천 이유가 있으면 층 대신 그 문장을 보여준다', (tester) async {
      // 의미 검색이 준 후보다. "왜 이 매장이 나왔는지"가 층 라벨보다 중요하다.
      await pumpResults(
        tester,
        results: const [
          DirectionsCandidate(
            title: '한식당',
            subtitle: '5F',
            point: point,
            nodeId: 'n-2',
            floor: '5F',
            reason: '따뜻한 국물 요리를 파는 곳이에요',
          ),
        ],
      );

      expect(find.text('따뜻한 국물 요리를 파는 곳이에요'), findsOneWidget);
      expect(find.text('5F'), findsNothing);
    });

    testWidgets('온디바이스 후보는 서버 결과보다 위에 붙는다', (tester) async {
      // 서버를 기다리지 않고 0ms에 나오는 값이라, 사용자가 치는 동안 이 자리가
      // 먼저 찬다.
      const entry = StoreIndexEntry(
        id: 'store-1',
        name: '스타벅스',
        floorId: 'B2',
        floorName: 'B2',
        entranceNodeId: 'n-3',
      );
      await pumpResults(
        tester,
        suggestions: const [
          (kind: SuggestionKind.prefix, stores: [entry]),
        ],
        results: const [
          DirectionsCandidate(
            title: '서버가 찾은 곳',
            subtitle: '1F',
            point: point,
            nodeId: 'n-4',
            floor: '1F',
          ),
        ],
      );

      final suggestionY = tester
          .getTopLeft(find.byKey(const Key('route-field-suggestion-store-1')))
          .dy;
      final serverY = tester.getTopLeft(find.text('서버가 찾은 곳')).dy;
      expect(suggestionY, lessThan(serverY));
    });
  });
}
