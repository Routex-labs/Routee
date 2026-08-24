import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/map/camera/scale_bar.dart';
import 'package:navigation_client/screens/map_shell/widgets/chrome/map_bottom_bar.dart';
import 'package:navigation_client/screens/map_shell/widgets/chrome/map_tab_bar.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_tuning.dart';
import 'package:navigation_client/screens/outdoor_map/widgets/map_scale_bar.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:routex_design_system/routex_design_system.dart';

/// **축척 막대가 "위치 보정"(GPS) 버튼을 덮으면 안 된다.**
///
/// 실측 증상: 막대를 상수 오프셋(112)으로 세워 두었더니, 하단에 탭 줄이 생겨
/// 버튼 줄이 그만큼 밀려 올라간 뒤 자의 아랫부분이 버튼 위에 걸쳤다. 상수는
/// 탭 줄·시설 시트를 못 따라간다 — 그래서 [aboveMapBottomBarPx]가 셸이 내려
/// 주는 높이로 그때그때 잰다.
///
/// 화면 전체 대신 **같은 오프셋으로 두 위젯만** 세운다(`parts/ui.dart`와 같은
/// 계산). 야외 지도를 통째로 띄우면 카메라·GPS처럼 자리와 무관한 것들이 함께
/// 깨진다 — `pdr_control_placement_test.dart`와 같은 이유다.
/// "위치 보정" 버튼. **아이콘이 아니라 버튼 전체**를 잡는다 — 아이콘만 재면
/// 버튼 여백만큼 후하게 통과해, 실제로 버튼 표면을 덮는 자리도 지나간다.
final _calibrateButton = find.ancestor(
  of: find.byIcon(Icons.my_location),
  matching: find.byType(RoutexMapControl),
);

void main() {
  /// 셸이 지도에 내려 주는 값. 안전영역은 빼고 준다(`_bottomOverlayLiftPx`).
  const overlayLift = kMapTabBarHeight;

  Widget host({required double safeBottom, double textScale = 1.0}) => MediaQuery(
    data: MediaQueryData(
      padding: EdgeInsets.only(bottom: safeBottom),
      textScaler: TextScaler.linear(textScale),
    ),
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Stack(
          children: [
            // 셸의 하단 바. 탭 줄 위에 앉고, 아래 안전영역은 그 줄이 먹는다.
            Positioned(
              left: 0,
              right: 0,
              bottom: overlayLift + safeBottom,
              child: MapBottomBar(
                bottomInset: false,
                onCalibrate: () {},
                onPlaceLocation: () {},
              ),
            ),
            Positioned(
              right: RoutexSpacing.componentPadding,
              bottom: aboveMapBottomBarPx(overlayLift),
              child: SafeArea(
                top: false,
                child: const MapScaleBar(
                  step: MapScaleStep(meters: 200, widthPx: 64),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  for (final safeBottom in const [0.0, 24.0, 48.0]) {
    testWidgets('안전영역 ${safeBottom}px에서 축척 막대가 위치 보정 버튼과 겹치지 않는다', (
      tester,
    ) async {
      await tester.pumpWidget(host(safeBottom: safeBottom));

      final scale = tester.getRect(find.byType(MapScaleBar));
      final calibrate = tester.getRect(_calibrateButton);

      expect(scale.overlaps(calibrate), isFalse);
      // 위에 뜨는지까지 본다 — 아래로 빠져나가도 "안 겹친다"는 참이 된다.
      expect(scale.bottom, lessThanOrEqualTo(calibrate.top));
    });
  }

  testWidgets('큰 글자 배율에서도 겹치지 않는다', (tester) async {
    // 막대 위 숫자는 글자 배율을 타고 커진다. 커지는 방향이 위쪽이라 버튼과는
    // 멀어지지만, 버튼 줄의 높이도 함께 바뀔 수 있어 같이 잰다.
    await tester.pumpWidget(host(safeBottom: 24, textScale: 2));

    final scale = tester.getRect(find.byType(MapScaleBar));
    final calibrate = tester.getRect(_calibrateButton);

    expect(scale.overlaps(calibrate), isFalse);
  });
}
