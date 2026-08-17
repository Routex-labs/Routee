import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/screens/outdoor_map/transition/indoor_transition_overlay.dart';
import 'package:navigation_client/screens/outdoor_map/transition/indoor_transition_preview.dart';
import 'package:navigation_client/screens/outdoor_map/transition/indoor_transition_timeline.dart';

/// 연출을 **실기기 없이 눈으로 보려고** 프레임을 PNG로 뽑는 도구다.
///
///     TRANSITION_FRAME_OUT=<폴더> flutter test test/tools/transition_frame_export_test.dart
///
/// 환경 변수가 없으면 통째로 건너뛴다 — CI가 파일을 뱉지 않게 하려는 것이다.
/// 움직임을 보려면 `lib/indoor_transition_preview_main.dart`를 띄운다.
///
/// **문이 열리는 방향은 이 도구로만 확인된다.** Flutter의 `rotateY`는 CSS와 부호가
/// 반대라, 위젯 테스트로는 "당겨서 열리는지"를 잡을 수 없다.

const _frameCount = 6;
const _frameSize = 260.0;
const _gap = 10.0;
const _barBand = 16.0;

void main() {
  final outDir = Platform.environment['TRANSITION_FRAME_OUT'];

  testWidgets('전환 프레임을 PNG로 뽑는다', (tester) async {
    tester.view.physicalSize = const Size(_frameSize, _frameSize);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final direction in IndoorTransitionDirection.values) {
      final shots = <ui.Image>[];
      for (var i = 0; i < _frameCount; i++) {
        final t = i / (_frameCount - 1);
        final swapped = t >= indoorTransitionVeilIn.end;
        final indoor = direction == IndoorTransitionDirection.enter
            ? swapped
            : !swapped;
        await tester.pumpWidget(
          MaterialApp(
            home: RepaintBoundary(
              key: ValueKey('$direction-$i'),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: FakeMapPainter(indoor: indoor),
                    ),
                  ),
                  Positioned.fill(
                    child: IndoorTransitionOverlay(
                      progress: t,
                      direction: direction,
                      buildingName: '더현대 서울',
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(ValueKey('$direction-$i')),
        );
        // **runAsync가 필수다.** `toImage`는 진짜 이벤트 루프를 기다리는데
        // testWidgets 안은 가짜 시계라, 그냥 await하면 영원히 안 끝난다.
        final image = await tester.runAsync(() => boundary.toImage());
        shots.add(image!);
      }
      await tester.runAsync(
        () => _writeStrip(shots, '$outDir/transition_${direction.name}.png'),
      );
    }
  }, skip: outDir == null);
}

/// 프레임들을 한 줄로 이어 붙이고 아래에 진행률 막대를 그린다.
///
/// 진행률은 **글자 대신 막대**로 적는다. flutter_test의 기본 폰트에는 글리프가
/// 없어서 어떤 문자열을 써도 네모 상자로만 그려진다.
Future<void> _writeStrip(List<ui.Image> shots, String path) async {
  final recorder = ui.PictureRecorder();
  final width = shots.length * _frameSize + (shots.length - 1) * _gap;
  final height = _frameSize + _barBand;
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width, height),
    Paint()..color = const Color(0xFF10141A),
  );
  for (var i = 0; i < shots.length; i++) {
    final left = i * (_frameSize + _gap);
    canvas.drawImage(shots[i], Offset(left, 0), Paint());
    final t = i / (shots.length - 1);
    canvas.drawRect(
      Rect.fromLTWH(left, _frameSize + 6, _frameSize, 5),
      Paint()..color = const Color(0x22FFFFFF),
    );
    canvas.drawRect(
      Rect.fromLTWH(left, _frameSize + 6, _frameSize * t, 5),
      Paint()..color = const Color(0xFF4A87F1),
    );
  }
  final image = await recorder.endRecording().toImage(
    width.round(),
    height.round(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  await File(path).writeAsBytes(bytes!.buffer.asUint8List());
}
