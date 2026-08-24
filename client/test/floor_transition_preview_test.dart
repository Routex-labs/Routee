// 층 전환 덮개를 **폰 없이 눈으로 보는** 미리보기. 검증이 아니라 확인용이라
// 평소에는 건너뛴다 — 골든 이미지는 렌더러가 기기마다 달라 CI에서 비교할 수 없다.
//
//   flutter test --dart-define=preview=true --update-goldens //     test/floor_transition_preview_test.dart
//
// PNG는 `test/preview/`에 떨어지고 git이 무시한다.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/floor/floor_concept_photo.dart';
import 'package:navigation_client/features/indoor_navigation/contract/floor_transition_ui_state.dart';
import 'package:navigation_client/screens/map_shell/widgets/chrome/floor_transition_overlay.dart';
import 'package:navigation_client/theme/app_theme.dart';

Future<void> _loadFonts() async {
  for (final entry in {
    'Pretendard': [
      'assets/fonts/Pretendard-Regular.otf',
      'assets/fonts/Pretendard-Medium.otf',
      'assets/fonts/Pretendard-SemiBold.otf',
      'assets/fonts/Pretendard-Bold.otf',
      'assets/fonts/Pretendard-ExtraBold.otf',
    ],
  }.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      loader.addFont(rootBundle.load(path));
    }
    await loader.load();
  }
}

Future<void> _decodeImages(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      final image = (element.widget as Image).image;
      await precacheImage(image, element);
    }
  });
  await tester.pumpAndSettle();
}

Widget _screen({
  required String from,
  required String to,
  required bool goingUp,
  required FloorTransitionStage stage,
}) => MediaQuery(
  data: const MediaQueryData(size: Size(390, 844), devicePixelRatio: 1),
  child: MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Color(0xFFDDE3EA))),
          Positioned.fill(
            child: FloorTransitionScrim(
              opacity: 1,
              fadeIn: Duration.zero,
              fadeOut: Duration.zero,
              photoAssets: floorConceptPhotos(to),
              state: FloorTransitionUiState(
                stage: stage,
                fromFloorLabel: from,
                toFloorLabel: to,
                goingUp: goingUp,
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);

/// 평소에는 건너뛴다. 위 명령으로만 돈다.
const _off = !bool.fromEnvironment('preview');

void main() {
  setUpAll(_loadFonts);

  testWidgets('preview', skip: _off, (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final shots = <String, Widget>{
      'up-b1-to-1f': _screen(
        from: 'B1',
        to: '1F',
        goingUp: true,
        stage: FloorTransitionStage.swapping,
      ),
      'down-1f-to-b1': _screen(
        from: '1F',
        to: 'B1',
        goingUp: false,
        stage: FloorTransitionStage.swapping,
      ),
      'up-4f-to-5f': _screen(
        from: '4F',
        to: '5F',
        goingUp: true,
        stage: FloorTransitionStage.swapping,
      ),
      'up-5f-to-6f': _screen(
        from: '5F',
        to: '6F',
        goingUp: true,
        stage: FloorTransitionStage.swapping,
      ),
      'down-b1-to-b2': _screen(
        from: 'B1',
        to: 'B2',
        goingUp: false,
        stage: FloorTransitionStage.swapping,
      ),
      'no-photo-b2-to-b3': _screen(
        from: 'B2',
        to: 'B3',
        goingUp: false,
        stage: FloorTransitionStage.swapping,
      ),
    };

    for (final shot in shots.entries) {
      await tester.pumpWidget(shot.value);
      await _decodeImages(tester);
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('preview/${shot.key}.png'),
      );
    }
  });

  testWidgets('preview-entry', skip: _off, (tester) async {
    // 등장 도중 한 컷 — 사진이 진행 방향에서 미끄러져 들어오는 중.
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _screen(
        from: 'B1',
        to: '1F',
        goingUp: true,
        stage: FloorTransitionStage.swapping,
      ),
    );
    await _decodeImages(tester);
    // 키를 바꿔 새로 마운트해야 등장 애니메이션이 처음부터 다시 돈다.
    await tester.pumpWidget(
      KeyedSubtree(
        key: const ValueKey('remount'),
        child: _screen(
          from: 'B1',
          to: '1F',
          goingUp: true,
          stage: FloorTransitionStage.swapping,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('preview/up-entering.png'),
    );
  });

  testWidgets('preview-second-photo', skip: _off, (tester) async {
    // 자동으로 두 번째 장까지 넘어간 뒤 한 컷.
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _screen(
        from: '5F',
        to: '6F',
        goingUp: true,
        stage: FloorTransitionStage.swapping,
      ),
    );
    await _decodeImages(tester);
    await tester.pump(const Duration(milliseconds: 2400));
    await tester.pump(const Duration(milliseconds: 600));
    // PageView는 넘어간 뒤에야 그 장을 만든다. 앱에서는 셸이 탑승 감지 때
    // 전부 미리 구워 두지만(map_shell_screen), 이 미리보기에는 그 단계가 없다.
    await _decodeImages(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('preview/up-second-photo.png'),
    );
  });

  testWidgets('preview-6f-pages', skip: _off, (tester) async {
    // 6F 다섯 장을 한 장씩 넘겨 가며 액자 안이 어떻게 잘리는지 본다.
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _screen(
        from: '5F',
        to: '6F',
        goingUp: true,
        stage: FloorTransitionStage.swapping,
      ),
    );
    await _decodeImages(tester);
    for (var i = 0; i < 5; i++) {
      if (i > 0) {
        await tester.drag(find.byType(PageView), const Offset(-400, 0));
        await tester.pumpAndSettle();
        await _decodeImages(tester);
      }
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('preview/6f-page-$i.png'),
      );
    }
  });
}
