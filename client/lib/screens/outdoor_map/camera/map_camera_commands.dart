/// 카메라를 실제로 움직이는 명령들.
///
/// **무엇에 맞출지는 화면이 정하고** 배율·방위 **계산**은 한 겹 아래
/// (`building_orientation.dart`)에 있다. 여기는 그 사이의 얇은 층이다.
///
/// 화면 크기를 `BuildContext` 대신 [Size]로 받는다 — `MediaQuery`를 직접 보면 위젯
/// 트리 없이는 한 줄도 시험할 수 없다.
library;

import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart';

import 'building_orientation.dart';
import '../entry/indoor_entry_zoom.dart';
import '../../../map/camera/zoom_math.dart';

/// 도면을 화면에 맞출 때 실제로 채우는 비율.
///
/// 1.0이면 외곽선이 화면 가장자리에 딱 붙는다 — 도면이 답답해 보이고 가장자리
/// 매장 라벨이 잘린다. 0.86이면 사방에 7%씩 남아, 건물이 어디서 끝나는지가
/// 보이면서도 도면은 충분히 크다.
const _fitFillRatio = 0.86;

/// [box]를 **가려지지 않는 띠**에 맞춰 카메라를 움직인다.
///
/// 층 도면 fit과 경로 개요의 **공통 몸통**이다. 둘을 한 함수로 묶는 이유는
/// chrome 보정과 줌 하한이 한 곳에만 있어야 하기 때문이다 — 각자 갖게 두면
/// 한쪽만 고쳐져 도면을 맞춘 화면과 경로를 맞춘 화면에서 같은 지점이 다른
/// 높이에 온다.
///
/// 상자를 **어떻게 구하느냐**는 호출부가 정한다([minAreaBoxFor] / [routeBoxFor]).
/// 퇴화 입력 방어처럼 입력 종류마다 다른 규칙이 여기 섞이면, 이 함수가 층
/// 외곽선용인지 경로용인지 알 수 없게 된다.
///
/// [maxZoom]은 확대해 들어가는 상한이다. 경로 개요만 준다 — 층 외곽선은 커서
/// 그 배율까지 올라갈 일이 없다.
Future<void> animateCameraToFitBox(
  MapLibreMapController controller,
  BuildingBox box, {
  required Size viewport,
  required double topChromePx,
  required double bottomChromePx,
  required Duration duration,
  double maxZoom = double.infinity,
}) async {
  // 중심은 **상자가 준다.** 호출부가 따로 구한 중심을 받던 시절에는 배율은
  // 돌아간 상자로, 위치는 정북 정렬 bbox로 재서 둘이 어긋났다(근거는
  // [BuildingBox.center]).
  final center = box.center;
  final bearing = portraitBearingFor(
    longAxisAzimuthDeg: box.longAxisAzimuthDeg,
    currentBearing: controller.cameraPosition?.bearing,
  );
  // 위아래 chrome이 덮는 만큼을 뺀 **실제로 보이는 띠**에 맞춘다. 전체 높이로
  // 맞추면 도면 윗부분이 카테고리 줄 뒤로 들어간다.
  final bandHeightPx = math.max(
    1.0,
    viewport.height - topChromePx - bottomChromePx,
  );
  final fitZoom = zoomToFitRotatedBox(
    // 상자를 비율만큼 부풀려 맞추면 그만큼 사방에 여백이 남는다.
    widthMeters: box.shortSideM / _fitFillRatio,
    heightMeters: box.longSideM / _fitFillRatio,
    viewportWidthPx: viewport.width,
    viewportHeightPx: bandHeightPx,
    latitude: center.latitude,
  );
  // 하한은 **이탈 임계값** 기준이다. 예전에는 진입 임계값까지 끌어올렸는데,
  // 그러면 위에서 준 여백이 도로 먹혔다. 실내 상태는 이탈 임계값 위이기만
  // 하면 유지된다([indoorEntryTransitionForZoom]은 그 아래에서만 exit를 낸다).
  //
  // 경로가 길어 이 배율에 다 담기지 않는 경우가 있는데, **그걸 받아들인다.**
  // 억지로 담으려 더 물러서면 카메라 정지 판정이 이탈로 읽어 도면이 닫히고
  // 야외로 튕긴다 — 경로 끝이 조금 잘리는 쪽이 낫다.
  final zoom = math.min(
    math.max(fitZoom, indoorExitZoomThreshold + 0.3),
    maxZoom,
  );

  // 상자 한가운데를 화면 한가운데가 아니라 **가려지지 않는 띠의 한가운데**에
  // 놓는다. 카메라 목표점은 늘 화면 중앙에 그려지므로, 목표점을 화면 위쪽
  // (=지금 bearing 방향)으로 그만큼 밀면 상자가 그만큼 내려온다.
  final shiftPx = (topChromePx - bottomChromePx) / 2;
  final metersPerPx = visibleWidthMeters(
    zoom: zoom,
    availablePx: 1,
    latitude: center.latitude,
  );
  final target = offsetByMeters(
    center,
    azimuthDeg: bearing,
    meters: shiftPx * metersPerPx,
  );

  await _applyCameraUpdate(
    controller,
    CameraUpdate.newCameraPosition(
      CameraPosition(
        target: toGlLatLng(target),
        zoom: zoom,
        bearing: bearing,
        tilt: controller.cameraPosition?.tilt ?? 0,
      ),
    ),
    duration,
  );
}

/// 경로 전체를 담을 때 화면 가장자리에서 비워 두는 여백(논리 px).
///
/// 아래 기본값은 **하단 카드 하한**이다 — 후보가 하나인 계획 카드를 실측하면
/// 124px이고, 그보다 높아지는 화면(자동차 후보 3줄=392, 대중교통 요약=262,
/// 후보 시트=화면의 55%)은 부르는 쪽이 **잰 값**을 넘긴다. 위 기본값은 길찾기
/// 플래너 실측(117px)에 여유를 얹은 값이고, 상태 표시줄 높이는 부르는 쪽이
/// `MediaQuery.paddingOf`로 더한다 — 기기마다 다르다.
/// 좌우는 **줌을 정하는 변**이라 좁게 잡는다. 대중교통 경로는 납작하다 —
/// 실측 예: 가로 17 km × 세로 6 km. 세로로 긴 화면에서는 가로가 먼저 차서
/// 줌이 거기서 정해지고, 좌우 여백을 키운 만큼 경로가 통째로 작아진다.
/// 40이면 세로에 빈 공간이 크게 남아 "축소된 것처럼" 보였다.
const routeFitSideInsetPx = 16.0;
const routeFitTopInsetPx = 120.0;
const routeFitBottomInsetPx = 180.0;

/// 여백을 다 빼고도 남겨야 하는 세로 띠(논리 px). 여백 합이 화면을 넘으면
/// MapLibre가 `화면 - 여백`(<= 0)으로 줌을 계산해 카메라가 튄다.
const routeFitMinBandPx = 120.0;

/// 경로 개요에 쓸 여백(논리 px). **화면마다 가려지는 높이가 다르다** — 하단
/// 카드 하나뿐인 화면과 시트가 55%를 덮는 화면이 같은 여백을 쓸 수 없다.
///
/// 다만 규칙 자체는 여기 하나다. 인자는 "무엇이 얼마나 덮고 있나"만 말하고,
/// 하한과 자르기는 여기서 정한다 — 값이 갈리면 안내를 바꿀 때마다 경로가
/// 화면에서 다른 크기로 잡힌다. 검증 기준은
/// `test/screens/outdoor_map/camera/route_fit_padding_test.dart`.
({double left, double top, double right, double bottom}) routeFitPadding({
  required Size viewport,
  required double topInsetPx,
  required double bottomInsetPx,
}) {
  // 잰 값이 하한보다 작아도 여기까지는 비운다. 카드가 아직 안 그려졌거나
  // 못 잰 프레임에서 0이 들어와도 경로가 카드 뒤로 들어가지 않게 한다.
  final wantTop = math.max(topInsetPx, routeFitTopInsetPx);
  final wantBottom = math.max(bottomInsetPx, routeFitBottomInsetPx);
  // 위아래를 다 빼고도 이만큼은 남긴다. 작은 폰 + 큰 글자 배율에서 실제로
  // 넘길 수 있고, 넘기면 MapLibre가 0 이하 크기로 줌을 계산한다.
  final roomV = math.max(0.0, viewport.height - routeFitMinBandPx);
  final top = math.min(wantTop, roomV);
  final bottom = math.min(wantBottom, roomV - top);
  final side = math.min(
    routeFitSideInsetPx,
    math.max(0.0, (viewport.width - routeFitMinBandPx) / 2),
  );
  return (left: side, top: top, right: side, bottom: bottom);
}

/// 좌표열 전체가 [viewport]에 들어오도록 맞춘다. 여백 규칙은 [routeFitPadding]
/// 하나이고, [topInsetPx]·[bottomInsetPx]로 **가려지는 높이만** 알려 준다.
///
/// 점이 2개 미만이거나 경계 상자가 한 점으로 수렴하면(모든 좌표가 같음) 줌
/// 계산이 발산하므로 아무것도 하지 않는다.
Future<void> animateCameraToPoints(
  MapLibreMapController controller,
  List<ll.LatLng> points, {
  required Size viewport,
  double topInsetPx = routeFitTopInsetPx,
  double bottomInsetPx = routeFitBottomInsetPx,
}) async {
  if (points.length < 2) return;
  var minLat = double.infinity;
  var maxLat = double.negativeInfinity;
  var minLng = double.infinity;
  var maxLng = double.negativeInfinity;
  for (final p in points) {
    minLat = p.latitude < minLat ? p.latitude : minLat;
    maxLat = p.latitude > maxLat ? p.latitude : maxLat;
    minLng = p.longitude < minLng ? p.longitude : minLng;
    maxLng = p.longitude > maxLng ? p.longitude : maxLng;
  }
  if (maxLat - minLat < 1e-7 && maxLng - minLng < 1e-7) return;
  final padding = routeFitPadding(
    viewport: viewport,
    topInsetPx: topInsetPx,
    bottomInsetPx: bottomInsetPx,
  );
  await controller.animateCamera(
    CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      ),
      left: padding.left,
      top: padding.top,
      right: padding.right,
      bottom: padding.bottom,
    ),
  );
}

/// [point]로 카메라를 옮긴다. [zoom]을 주면 배율까지 함께 정한다.
Future<void> animateCameraToPoint(
  MapLibreMapController controller,
  ll.LatLng point, {
  double? zoom,
}) async {
  final target = toGlLatLng(point);
  await controller.animateCamera(
    zoom == null
        ? CameraUpdate.newLatLng(target)
        : CameraUpdate.newLatLngZoom(target, zoom),
  );
}

/// 지금 방향·기울기를 유지한 채 [point]로 돌아간다.
///
/// **bearing과 tilt는 건드리지 않는다.** 개요 연출이 경로 축에 맞춰 세워 둔
/// 방향이 여기서 정북으로 돌아가면, 돌아온 화면의 위쪽이 갈 방향과 어긋난다.
/// 배율도 [minZoom]까지만 당기고 그보다 확대돼 있으면 그대로 둔다 — 무언가를
/// 들여다보려 당겨 둔 배율을 버튼 한 번에 되돌리면, 위치로 돌아가는 대신 방금
/// 보던 것을 잃는다.
Future<void> recenterKeepingBearing(
  MapLibreMapController controller,
  ll.LatLng point, {
  required double minZoom,
  required Duration duration,
}) async {
  final camera = controller.cameraPosition;
  await controller.animateCamera(
    CameraUpdate.newCameraPosition(
      CameraPosition(
        target: toGlLatLng(point),
        zoom: math.max(camera?.zoom ?? minZoom, minZoom),
        bearing: camera?.bearing ?? 0,
        tilt: camera?.tilt ?? 0,
      ),
    ),
    duration: duration,
  );
}

/// latlong2 → MapLibre 타입 브릿지.
LatLng toGlLatLng(ll.LatLng p) => LatLng(p.latitude, p.longitude);

/// 즉시 이동은 moveCamera로 간다. animateCamera에 Duration.zero를 주면 Android
/// MapLibre가 "Null duration"으로 예외를 던진다 — 층 전환 큐 안에서 터지면
/// 전환 전체가 실패 복구로 빠진다.
Future<void> _applyCameraUpdate(
  MapLibreMapController controller,
  CameraUpdate update,
  Duration duration,
) async {
  if (duration <= Duration.zero) {
    await controller.moveCamera(update);
  } else {
    await controller.animateCamera(update, duration: duration);
  }
}
