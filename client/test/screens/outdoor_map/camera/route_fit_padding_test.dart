import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/screens/outdoor_map/camera/map_camera_commands.dart';

/// 경로 개요 여백의 **검증 기준 표**.
///
/// 고정 여백(bottom 180)이 하단 ETA 카드에 맞춰져 있어, 화면의 55%를 덮는
/// 대중교통 후보 시트 아래에서는 경로가 시트 뒤에 잠겼다. 가려지는 높이는
/// 부르는 쪽만 아는 값이라 인자로 받는다.
void main() {
  // 아이폰 15 논리 크기. 세로가 커서 여백 자르기가 걸리지 않는 정상 화면이다.
  const phone = Size(393, 852);

  test('아무것도 안 주면 지금 값 그대로다 — 기존 호출부가 안 깨진다', () {
    final padding = routeFitPadding(
      viewport: phone,
      topInsetPx: routeFitTopInsetPx,
      bottomInsetPx: routeFitBottomInsetPx,
    );

    expect(padding.left, routeFitSideInsetPx);
    expect(padding.right, routeFitSideInsetPx);
    expect(padding.top, routeFitTopInsetPx);
    expect(padding.bottom, routeFitBottomInsetPx);
  });

  test('가려지는 높이가 기본값보다 크면 그만큼 아래를 비운다', () {
    // 후보 시트가 화면의 55%를 덮는다(kTransitRoutesSheetInitialSize).
    final sheetPx = phone.height * 0.55;

    final padding = routeFitPadding(
      viewport: phone,
      topInsetPx: routeFitTopInsetPx,
      bottomInsetPx: sheetPx,
    );

    expect(padding.bottom, sheetPx);
  });

  test('가려지는 높이가 기본값보다 작아도 하한까지는 비운다', () {
    final padding = routeFitPadding(
      viewport: phone,
      topInsetPx: 0,
      bottomInsetPx: 0,
    );

    expect(padding.top, routeFitTopInsetPx);
    expect(padding.bottom, routeFitBottomInsetPx);
  });

  test('여백 합이 화면을 넘으면 보이는 띠를 남기고 자른다', () {
    // 작은 화면 + 큰 글자 배율에서 실제로 일어난다. 안 자르면 MapLibre가
    // (화면 - 여백) <= 0 으로 줌을 계산해 카메라가 튄다.
    const tiny = Size(320, 480);

    final padding = routeFitPadding(
      viewport: tiny,
      topInsetPx: 200,
      bottomInsetPx: 900,
    );

    expect(padding.top + padding.bottom, tiny.height - routeFitMinBandPx);
    expect(padding.bottom, greaterThan(0));
    expect(padding.left + padding.right, lessThan(tiny.width));
  });
}
