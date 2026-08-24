/// 지도(MapLibre) 심볼용 현재 위치 마커 비트맵 렌더러.
///
/// 두 화면에 같은 렌더 코드가 한 벌씩 있고 주석으로 "함께 맞춰야 한다"고 서로를
/// 가리키던 것을 코드로 옮긴 파일이다.
///
/// addImage 등록 이름은 등록하는 쪽 사정이라 화면마다 따로 둔다(웹은 같은 이름이
/// 있으면 새 비트맵을 버린다). 여기는 그림과 크기 상수만 소유한다.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 현재 위치 마커의 화면 크기(논리 px)와 색.
///
/// **지도 아이콘과 위젯이 같은 값을 봐야 한다.** 지도는 이 마커를 2배 캔버스에
/// 그려 넣고(`outdoor_map_screen.dart`), 층 전환 덮개는 같은 그림을 위젯으로
/// 그린다 — 두 벌로 두면 덮개가 마커를 "가져왔다"는 인상이 크기 차이 하나로
/// 깨진다. 코어 지름(16px)이 이 마커의 체감 크기를 정한다: 야외 GPS 도트(18px)
/// 보다 크고 정확도 원 테두리(44px)보다 작다.
const kLocationMarkerCoreRadiusPx = 8.0;
const kLocationMarkerRimRadiusPx = kLocationMarkerCoreRadiusPx + 2.5;
const kLocationMarkerColor = Color(0xFF1976D2);

/// 현재 위치 심볼을 그릴 때 쓰는 디자인 좌표계의 한 변 길이(px). 아래 렌더
/// 코드의 모든 반지름/오프셋은 이 좌표계 기준이다.
const kLocationMarkerIconDesignSize = 144.0;

/// 디자인 좌표계 대비 실제 비트맵 배율. 아이콘을 크게 키우면 MapLibre가
/// 비트맵을 화면 픽셀 수보다 적은 원본으로 늘려 그리게 되어 흰 테두리가
/// 뭉개진다(특히 devicePixelRatio 2~3인 폰). 비트맵만 이 배율로 크게 렌더하고
/// iconSize는 같은 배율로 나눠서, 화면상 크기는 그대로 두고 해상도만 올린다.
const kLocationMarkerIconPixelRatio = 2.0;

/// 심볼 레이어에 줄 iconSize. 디자인 좌표계 1px = 화면 1px이 되도록 고정한다
/// (비트맵은 [kLocationMarkerIconPixelRatio]배로 렌더하므로 그만큼 나눈다).
///
/// zoom 보간을 쓰지 않는 이유: 야외 GPS 마커는 `CircleLayer`의 상수
/// `circleRadius`로 그려져 zoom과 무관하게 같은 크기를 유지한다
/// (outdoor_map_screen.dart의 `outdoor-accuracy`/`outdoor-current-dot`).
/// 이 마커도 같은 크기로 보여야 하므로 zoom에 따라 커지면 안 된다.
const kLocationMarkerIconSize = 1.0 / kLocationMarkerIconPixelRatio;

/// 파란 코어 원의 반지름(디자인 단위 = 화면 px). 이 마커의 체감 크기를 정하는
/// 값이다(코어 지름 32px — 야외 GPS 도트 18px보다 크고 정확도 원 테두리
/// 44px보다 작다). 크기는 위젯 쪽 상수([kLocationMarkerCoreRadiusPx])에서
/// 파생시켜, 층 전환 덮개가 그리는 같은 그림의 점과 한 곳에서 조정되게 한다.
///
/// 비트맵 등록 이름에 이 값을 박아 두는 쪽(두 화면 모두)은 크기를 바꾸면
/// 이름도 함께 바뀌어, removeImage가 없는 웹에서도 새 비트맵이 등록된다.
const kLocationMarkerIconCoreRadius =
    kLocationMarkerCoreRadiusPx * kLocationMarkerIconPixelRatio;

/// 코어를 감싸는 흰 링의 반지름. 코어보다 5px 두껍게 잡아, 도면 바닥(#FFFFFF)
/// 에서는 묻히더라도 매장 fill이나 경로선 위에서는 코어가 배경과 분리돼
/// 보이게 한다.
const kLocationMarkerIconRimRadius =
    kLocationMarkerRimRadiusPx * kLocationMarkerIconPixelRatio;

/// 방향 삼각형의 치수 — 코어 반지름 대비 비율.
///
/// 광택 점과 같은 규칙으로 **코어 반지름에서 파생시킨다.** 코어 크기를 바꿔도
/// 삼각형이 따라 커지고 rim과의 간격 비율이 유지되어야 한다.
///
/// [_headingGapRatio]는 흰 rim **바깥**에서 띄우는 거리다. 0이면 삼각형이 rim에
/// 달라붙어 도트가 물방울처럼 보이고, 너무 크면 따로 떠 있는 점 두 개가 된다.
const _headingGapRatio = 0.16;

/// 2026-08-20 실기기에서 "방향 나타내는 크기가 좀 작다"는 지적으로 1.5배 키웠다
/// (높이 0.72 → 1.10, 밑변 반폭 0.58 → 0.86). 코어 반지름 8px 기준으로 높이가
/// 5.8px였는데, 걸으면서 흘깃 보는 크기로는 방향이 안 읽혔다.
///
/// 더 키우려면 캔버스를 먼저 본다 — 꼭짓점이 중심에서
/// `코어 × (rimToCore + gap + height)`만큼 떨어지고, 그 값이 캔버스 반폭
/// ([kLocationMarkerIconDesignSize] / 2)을 넘으면 삼각형 끝이 잘린다.
const _headingHeightRatio = 1.10;
const _headingHalfBaseRatio = 0.86;

/// rim 반지름 / 코어 반지름. 두 값을 각각 배율에 곱하지 않고 비로 두는 이유는,
/// 삼각형이 **어느 캔버스 배율에서도** 코어 반지름 하나로 결정되게 하기 위해서다.
const _rimToCoreRatio =
    kLocationMarkerRimRadiusPx / kLocationMarkerCoreRadiusPx;

/// 진행 방향 삼각형의 세 꼭짓점(꼭짓점, 밑변 왼쪽, 밑변 오른쪽).
///
/// **캔버스 기준 위(-y)를 향한다.** MapLibre는 이 비트맵 **전체**를 heading만큼
/// 시계 방향으로 돌리므로, 여기서 위를 향해 그려야 회전 뒤 진행 방향과 맞는다.
///
/// 밑변은 흰 rim 바깥에서 시작한다 — 참고한 상용 지도처럼 도트 가장자리에 붙은
/// 별도 도형이지, 도트를 대체하는 화살표가 아니다. 검증 기준은
/// `test/map/icon/location_marker_icon_test.dart`.
List<Offset> locationMarkerHeadingTriangle({
  required Offset center,
  required double coreRadius,
}) {
  final baseY = center.dy - coreRadius * (_rimToCoreRatio + _headingGapRatio);
  final halfBase = coreRadius * _headingHalfBaseRatio;
  return [
    Offset(center.dx, baseY - coreRadius * _headingHeightRatio),
    Offset(center.dx - halfBase, baseY),
    Offset(center.dx + halfBase, baseY),
  ];
}

/// 상용 지도 앱처럼 흰 테두리의 파란 현재 위치 점 가장자리에 진행 방향
/// 삼각형이 붙은 하나의 심볼을 렌더링한다. MapLibre가 이 비트맵 전체를 회전하므로
/// 확대/축소해도 점과 삼각형의 비율·간격이 흐트러지지 않는다.
///
/// [showHeading]이 true면 도트에 방향 삼각형이 붙고, false면 도트만 있는 이미지가
/// 나온다. MapLibre SymbolLayer는 미리 addImage로 등록된 비트맵만 참조할 수 있어
/// 이렇게 캔버스 렌더가 필요하다.
Future<Uint8List> renderLocationMarkerIcon({required bool showHeading}) async {
  const canvasSize = kLocationMarkerIconDesignSize;
  const center = Offset(canvasSize / 2, canvasSize / 2);
  const pixelSize = canvasSize * kLocationMarkerIconPixelRatio;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    const Rect.fromLTWH(0, 0, pixelSize, pixelSize),
  );
  canvas.scale(kLocationMarkerIconPixelRatio);

  canvas.drawCircle(
    center + const Offset(0, 2),
    kLocationMarkerIconRimRadius + 3,
    Paint()
      ..color = const Color(0x33000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
  );
  canvas.drawCircle(
    center,
    kLocationMarkerIconRimRadius,
    Paint()..color = Colors.white,
  );

  canvas.drawCircle(
    center,
    kLocationMarkerIconCoreRadius,
    Paint()..color = kLocationMarkerColor,
  );
  // 코어 왼쪽 위의 광택 점. 코어 크기를 바꿔도 비율이 유지되도록 코어 반지름에서
  // 파생시킨다(원본 디자인의 코어 18 / offset 5 / 반지름 4.5 비율).
  const glossOffset = kLocationMarkerIconCoreRadius * 0.28;
  canvas.drawCircle(
    center - const Offset(glossOffset, glossOffset),
    kLocationMarkerIconCoreRadius * 0.25,
    Paint()..color = const Color(0x66FFFFFF),
  );

  if (showHeading) {
    final vertices = locationMarkerHeadingTriangle(
      center: center,
      coreRadius: kLocationMarkerIconCoreRadius,
    );
    canvas.drawPath(
      Path()
        ..moveTo(vertices[0].dx, vertices[0].dy)
        ..lineTo(vertices[1].dx, vertices[1].dy)
        ..lineTo(vertices[2].dx, vertices[2].dy)
        ..close(),
      Paint()..color = kLocationMarkerColor,
    );
  }

  final image = await recorder.endRecording().toImage(
    pixelSize.toInt(),
    pixelSize.toInt(),
  );
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}
