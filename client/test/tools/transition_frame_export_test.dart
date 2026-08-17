import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/screens/outdoor_map/transition/indoor_transition_preview.dart';
import 'package:navigation_client/screens/outdoor_map/transition/indoor_transition_timeline.dart';

/// 연출을 **빌드 없이 눈으로 보려고** 프레임을 PNG로 뽑는 도구다.
///
///     TRANSITION_FRAME_OUT=<폴더> flutter test test/tools/transition_frame_export_test.dart
///
/// 환경 변수가 없으면 통째로 건너뛴다 — CI가 파일을 뱉지 않게 하려는 것이다.
/// 실기기에서 움직임을 보려면 `lib/indoor_transition_preview_main.dart`를 띄운다.

const _frameCount = 6;
const _frameSize = 260.0;
const _gap = 10.0;
const _labelBand = 26.0;

Future<void> _exportStrip(
  IndoorTransitionDirection direction,
  String path,
) async {
  final recorder = ui.PictureRecorder();
  final width = _frameCount * _frameSize + (_frameCount - 1) * _gap;
  final height = _frameSize + _labelBand;
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width, height),
    Paint()..color = const Color(0xFF10141A),
  );

  for (var i = 0; i < _frameCount; i++) {
    final t = i / (_frameCount - 1);
    final frame = indoorTransitionFrameAt(t, direction: direction);
    final left = i * (_frameSize + _gap);
    canvas.save();
    canvas.translate(left, 0);
    canvas.clipRect(const Rect.fromLTWH(0, 0, _frameSize, _frameSize));
    IndoorTransitionStagePainter(
      frame,
    ).paint(canvas, const Size(_frameSize, _frameSize));
    canvas.restore();

    // 진행률은 **글자 대신 막대**로 적는다. flutter_test의 기본 폰트에는 글리프가
    // 없어서 어떤 문자열을 써도 네모 상자로만 그려진다.
    const barTop = _frameSize + 10.0;
    canvas.drawRect(
      Rect.fromLTWH(left, barTop, _frameSize, 6),
      Paint()..color = Colors.white10,
    );
    canvas.drawRect(
      Rect.fromLTWH(left, barTop, _frameSize * t, 6),
      Paint()..color = Colors.tealAccent,
    );
  }

  final image = await recorder.endRecording().toImage(
    width.round(),
    height.round(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  await File(path).writeAsBytes(bytes!.buffer.asUint8List());
}

void main() {
  final outDir = Platform.environment['TRANSITION_FRAME_OUT'];

  testWidgets('전환 프레임을 PNG로 뽑는다', (tester) async {
    // **runAsync가 필수다.** `toImage`·`toByteData`는 진짜 이벤트 루프를 기다리는데
    // testWidgets 안은 가짜 시계라, 그냥 await하면 영원히 안 끝난다(파일이 0바이트로
    // 남는 것으로 나타난다).
    await tester.runAsync(() async {
      for (final direction in IndoorTransitionDirection.values) {
        await _exportStrip(
          direction,
          '$outDir/transition_${direction.name}.png',
        );
      }
    });
  }, skip: outDir == null);
}
