import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/screens/map_shell/widgets/chrome/map_top_bar.dart';
import 'package:navigation_client/screens/map_shell/widgets/search/search_panel.dart';
import 'package:routex_design_system/routex_design_system.dart';

/// 설계와 검증 기준은 `docs/client/naver-map-ui-ux-analysis.md` I절이 단일 출처다.
///
/// **여기서 지키는 것은 숫자가 아니라 순서다.** 값 자체는 눈으로 보고 조정할 수
/// 있지만, "상단 바와 결과 패널이 같은 층위"로 되돌아가는 회귀는 화면을 봐도
/// 잘 안 보인다 — 예전에 셋 다 `elevation: 6`이었던 것이 정확히 그렇게 생긴
/// 일이다.

/// 위젯의 **가장 바깥** Material. 층위를 결정하는 것이 그 하나다.
Material _outerMaterial(WidgetTester tester, Type widgetType) {
  return tester.widget<Material>(
    find
        .descendant(
          of: find.byType(widgetType),
          matching: find.byType(Material),
        )
        .first,
  );
}

void main() {
  group('AppElevation — 층위 순서', () {
    test('지도에 붙은 것 < 상시 chrome < 임시 오버레이', () {
      expect(AppElevation.onMap, lessThan(AppElevation.chrome));
      expect(AppElevation.chrome, lessThan(AppElevation.overlay));
    });

    // 전부 낮추면 지도 위에 떠 있어야 할 오버레이가 지도에 묻힌다. 목적은
    // 낮추는 것이 아니라 위계를 만드는 것이다.
    test('가장 낮은 층위도 0이 아니다', () {
      expect(AppElevation.onMap, greaterThan(0));
    });
  });

  group('AppElevation — 실제 배선', () {
    testWidgets('상단 바는 chrome, 결과 패널은 overlay다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Column(
              children: [
                MapTopBar(
                  onMenuTap: () {},
                  controller: TextEditingController(),
                  focusNode: FocusNode(),
                  onChanged: (_) {},
                  onSubmitted: (_) {},
                  searchActive: false,
                  onCancelSearch: () {},
                  onDirectionsTap: () {},
                ),
                const Expanded(
                  child: SearchPanel(
                    buildingId: 'building-1',
                    query: '',
                    submitTick: 0,
                    onStorePicked: _noop,
                    onBuildingPicked: _noop,
                    onSuggestionPicked: _noop,
                    onQueryPicked: _noop,
                    // 야외로 두면 인덱스를 받지 않아 리포지토리가 필요 없다.
                    indoorContextActive: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      final topSurface = tester.widget<RoutexSurface>(
        find.descendant(
          of: find.byType(MapTopBar),
          matching: find.byType(RoutexSurface),
        ),
      );
      final topBar = _outerMaterial(tester, MapTopBar);
      final panel = _outerMaterial(tester, SearchPanel);

      expect(topSurface.role, RoutexSurfaceRole.onMap);
      expect(topBar.elevation, RoutexLayer.onMap);
      expect(panel.elevation, AppElevation.overlay);
      // 예전에는 둘 다 6이라 한 덩어리로 보였다.
      expect(panel.elevation, greaterThan(topBar.elevation));
    });

    testWidgets('상단 검색은 디자인시스템 onMap 표면을 쓴다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: MapTopBar(
              onMenuTap: () {},
              controller: TextEditingController(),
              focusNode: FocusNode(),
              onChanged: (_) {},
              onSubmitted: (_) {},
              searchActive: false,
              onCancelSearch: () {},
              onDirectionsTap: () {},
            ),
          ),
        ),
      );

      final surface = tester.widget<RoutexSurface>(
        find.descendant(
          of: find.byType(MapTopBar),
          matching: find.byType(RoutexSurface),
        ),
      );
      expect(surface.role, RoutexSurfaceRole.onMap);
      expect(surface.shape, RoutexSurfaceShape.field);
    });
  });
}

void _noop(Object? _) {}
