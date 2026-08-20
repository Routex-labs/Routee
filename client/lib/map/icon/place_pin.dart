/// 실내 도면 위 출구 핀. 글씨를 비트맵에 굽는다.
///
/// 관찰 캡처와 근거는 `docs/client/kakao-map-indoor-observation.md`.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'destination_pin.dart';

/// 출구 핀 테두리 두께. 안이 비어 있으므로 이 선이 곧 핀의 형태다 —
/// 도착 핀 외곽선(7)보다 굵게 두지 않으면 축소했을 때 사라진다.
const _gateOutlineWidth = 9.0;

/// 출구 핀 글자 크기. 도착 핀("도착" 2글자, 44)보다 크다 — 여기 들어가는 것은
/// 방위 한두 글자라 같은 원 안에서 더 키울 수 있고, 키워야 축소 시 읽힌다.
const _gateLabelFontSize = 52.0;

/// 두 글자(예: `남동`)일 때의 글자 크기. 한 글자와 같은 크기로 두면 머리 원을
/// 넘는다.
const _gateLabelFontSizeWide = 38.0;

/// 물방울 실루엣. [destination_pin.dart]의 도형과 같은 좌표·곡률이다 —
/// 화면에 세 종류의 핀이 함께 뜨는데 실루엣이 조금씩 다르면 그것부터 눈에 띈다.
Path _teardropPath() {
  const cx = kPinCanvasWidth / 2;
  const cy = kPinHeadCenterY;
  const tipY = kPinCanvasHeight - _gateOutlineWidth / 2 - 1.0;
  const joinDx = 50.4;
  const joinDy = 19.35;

  return Path()
    ..moveTo(cx, tipY)
    ..cubicTo(
      cx - 11.25,
      cy + 76.5,
      cx - 42.75,
      cy + 45,
      cx - joinDx,
      cy + joinDy,
    )
    ..arcToPoint(
      const Offset(cx + joinDx, cy + joinDy),
      radius: const Radius.circular(kPinHeadRadius),
      largeArc: true,
    )
    ..cubicTo(cx + 42.75, cy + 45, cx + 11.25, cy + 76.5, cx, tipY)
    ..close();
}

Future<Uint8List> _bake(void Function(Canvas) paint) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    const Rect.fromLTWH(0, 0, kPinCanvasWidth, kPinCanvasHeight),
  );
  paint(canvas);
  final image = await recorder.endRecording().toImage(
    kPinCanvasWidth.toInt(),
    kPinCanvasHeight.toInt(),
  );
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

/// 출구 핀 — 흰색을 채우고 파란 테두리를 두른 뒤 [label]을 굽는다.
///
/// [label]은 방위 한두 글자다(`남`·`남동`). **숫자를 넣지 않는다** — 카카오는
/// `GATE2`라 부르지만 우리 원본은 다섯 개 모두 이름이 `출구`뿐이라 실제 간판
/// 번호를 모른다. 방위는 우리가 건물 중심에서 계산한 값이라 어긋날 수 없다
/// (`docs/client/kakao-map-indoor-observation.md` G절).
///
/// 글자색이 [AppColors.blue600]인 것은 **흰 배경 위 텍스트**라서다. `primary`는
/// 3.48:1로 본문 기준에 못 미친다.
Future<Uint8List> renderGatePinIcon(String label) => _bake((canvas) {
  final silhouette = _teardropPath();
  canvas.drawPath(silhouette, Paint()..color = const Color(0xFFFFFFFF));
  canvas.drawPath(
    silhouette,
    Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = _gateOutlineWidth
      ..strokeJoin = StrokeJoin.round,
  );

  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: TextStyle(
        color: AppColors.blue600,
        fontSize: label.characters.length > 1
            ? _gateLabelFontSizeWide
            : _gateLabelFontSize,
        fontWeight: FontWeight.w800,
        fontFamily: kPinLabelFontFamily,
        fontFamilyFallback: kPinLabelFontFallback,
        // 1.0이어야 painter.height의 절반이 글자 세로 중앙과 맞는다.
        height: 1.0,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(
    canvas,
    Offset(
      kPinCanvasWidth / 2 - painter.width / 2,
      kPinHeadCenterY - painter.height / 2,
    ),
  );
});
