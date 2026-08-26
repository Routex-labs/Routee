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

/// 잰 chrome 아래 끝과 경로 사이에 남기는 틈(논리 px).
///
/// 0이면 경로선이 카드 밑변에 딱 붙어, 잘린 것인지 거기서 끝나는 것인지
/// 구분되지 않는다.
const routeFitChromeGapPx = 12.0;

/// 끝점 핀이 잘리지 않게 위아래로 더 비우는 높이(논리 px).
///
/// 카메라는 **좌표**를 담지, 그 좌표 위에 세우는 핀의 크기는 모른다. 출발·도착
/// 핀은 좌표에서 위로 솟아 있어서 좌표에 딱 맞게 담으면 경로 양 끝의 핀이
/// 잘린다 — 하필 사용자가 제일 먼저 찾는 두 점이다.
const routeFitPinAllowancePx = 44.0;

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
///
/// **bearing·tilt는 항상 정북·평면으로 되돌린다.** 야외 GPS 따라가기 전용
/// 함수라, 직전에 실내 나침반 추종([_moveFollowCamera])이 남겨 둔 회전이
/// 그대로 야외 화면까지 새어 나오는 것을 막는다 — 야외는 방향 없이 보여주던
/// 화면으로 돌아가는 것이 맞다.
///
/// **[duration]을 주면 물러섰다 다가가는 호를 그린다.** maplibre_gl의
/// `animateCamera`는 시간이 붙으면 양쪽 플랫폼 모두 flyTo로 내려간다(Android는
/// `MapLibreMap.animateCamera`, iOS는 `MLNMapView.fly(to:withDuration:)`).
/// 먼 자리로 갈수록 중간에 더 크게 축소되는 그 호가, 목적지 매장을 확대해 보던
/// 화면에서 안내 시작을 눌렀을 때 "축소되며 출발지로 내려앉는" 그림이다 —
/// 축소와 이동을 두 애니메이션으로 쪼개면 도리어 겹쳐서 떤다
/// (`docs/client/camera-choreography-plan.md` 4.14). 시간을 빼거나
/// `moveCamera`로 바꾸면 그 호가 사라지고 화면이 순간이동한다.
Future<void> animateCameraToPoint(
  MapLibreMapController controller,
  ll.LatLng point, {
  double? zoom,
  Duration? duration,
}) async {
  final camera = controller.cameraPosition;
  await controller.animateCamera(
    CameraUpdate.newCameraPosition(
      CameraPosition(
        target: toGlLatLng(point),
        zoom: zoom ?? camera?.zoom ?? 0,
        bearing: 0,
        tilt: 0,
      ),
    ),
    duration: duration,
  );
}

/// 보고 있는 자리는 그대로 두고 **방향만 정북·평면으로 되돌린다.** [zoom]을
/// 주면 배율도 함께 정한다.
///
/// **야외로 돌아가는 모든 문에 필요하다.** 실내로 들어가면 카메라는 사용자가
/// 바라보는 쪽이 화면 위가 되도록 돌아간다(`_centerOnIndoorMarker`). 도면을
/// 접고 나가는 길 중 좌표를 옮기는 것들은 [animateCameraToPoint]가 방위까지
/// 되돌려 주지만, 배율만 건드리거나 카메라를 아예 안 만지는 길
/// (`returnToOutdoorView`·`_exitIndoorByOutsideTap`)은 그 회전을 그대로
/// 남긴다. 그러면 사용자는 **정북이 아닌 야외 지도** 위에서 걷게 된다 — 마커는
/// 옳은 좌표에 찍히는데 화면에서 움직이는 쪽이 회전한 만큼 어긋나, 실기기에서
/// "동서와 남북이 서로 바뀐 것 같다"로 올라온 화면이 이것이다.
///
/// 이미 정북·평면이고 배율도 안 바꾼다면 아무것도 하지 않는다 — 뜻 없는
/// 애니메이션 한 번이 진행 중인 다른 카메라 이동을 끊는다.
Future<void> resetCameraToNorthUp(
  MapLibreMapController controller, {
  double? zoom,
}) async {
  final camera = controller.cameraPosition;
  if (camera == null) return;
  if (camera.bearing == 0 && camera.tilt == 0 && zoom == null) return;
  await controller.animateCamera(
    CameraUpdate.newCameraPosition(
      CameraPosition(
        target: camera.target,
        zoom: zoom ?? camera.zoom,
        bearing: 0,
        tilt: 0,
      ),
    ),
  );
}

/// [point]로 돌아간다. [keepBearing]이 true면 지금 방향·기울기를 유지하고,
/// false면 정북·평면으로 되돌린다.
///
/// **실내는 유지, 야외는 되돌린다.** 실내는 개요 연출이 경로 축에 맞춰 세워 둔
/// 방향이 있어 여기서 정북으로 돌아가면 화면 위쪽이 갈 방향과 어긋난다. 야외는
/// 그런 방향이 없으므로(따라가기도 늘 정북, [animateCameraToPoint]) 남아 있는
/// bearing은 실내 나침반 추종이 새어 나온 값일 뿐이다 — 정북으로 되돌리는 것이
/// "방향 없이 보여주던" 원래 화면이다.
///
/// 배율은 [minZoom]까지만 당기고 그보다 확대돼 있으면 그대로 둔다 — 무언가를
/// 들여다보려 당겨 둔 배율을 버튼 한 번에 되돌리면, 위치로 돌아가는 대신 방금
/// 보던 것을 잃는다.
///
/// [topChromePx]·[bottomChromePx]는 [animateCameraToFitBox]와 같은 보정을
/// 준다 — 안 주면(기본값 0) 화면 **기하학적** 한가운데에 놓이는데, 아래
/// chrome(탭 바·안내 카드)이 위쪽 chrome(검색창)보다 대개 더 높아서 실제로
/// 보이는 자리는 중앙보다 위로 치우친다(실기기 확인).
Future<void> recenterKeepingBearing(
  MapLibreMapController controller,
  ll.LatLng point, {
  required double minZoom,
  required Duration duration,
  bool keepBearing = true,
  double topChromePx = 0,
  double bottomChromePx = 0,
}) async {
  final camera = controller.cameraPosition;
  final zoom = math.max(camera?.zoom ?? minZoom, minZoom);
  final bearing = keepBearing ? (camera?.bearing ?? 0) : 0.0;
  // 같은 원리: 목표점을 화면 위쪽으로 그만큼 밀면, 실제 좌표([point])는 그만큼
  // 아래로 내려와 가려지지 않는 띠의 한가운데에 온다.
  final shiftPx = (topChromePx - bottomChromePx) / 2;
  final target = shiftPx == 0
      ? point
      : offsetByMeters(
          point,
          azimuthDeg: bearing,
          meters:
              shiftPx *
              visibleWidthMeters(
                zoom: zoom,
                availablePx: 1,
                latitude: point.latitude,
              ),
        );
  await controller.animateCamera(
    CameraUpdate.newCameraPosition(
      CameraPosition(
        target: toGlLatLng(target),
        zoom: zoom,
        bearing: bearing,
        tilt: keepBearing ? (camera?.tilt ?? 0) : 0,
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
