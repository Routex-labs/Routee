import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/widgets/startup_loading_overlay.dart';

void main() {
  testWidgets('마커와 routee 워드마크를 중앙에 페이드인한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const StartupLoadingOverlay()),
    );

    expect(find.byKey(const Key('startup-loading-marker')), findsOneWidget);
    expect(find.text('routee'), findsOneWidget);
    expect(
      tester.getCenter(find.byKey(const Key('startup-loading-marker'))).dx,
      closeTo(400, 1),
    );

    await tester.pumpAndSettle();
    expect(find.byKey(const Key('startup-loading-overlay')), findsOneWidget);
  });
}
