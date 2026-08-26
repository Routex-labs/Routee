/// 야외 지도의 **조정 값** — 거리 문턱, 줌 배율, 애니메이션 길이, 화면 여백.
///
/// 숫자는 대부분 실기기에서 재보고 정한 것이라 근거를 값 옆에 짧게 남긴다.
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart' as ll;
import 'package:routex_design_system/routex_design_system.dart';

import '../../map/camera/zoom_math.dart';
import 'entry/indoor_entry_zoom.dart' show indoorTilesMaxZoom;

/// 위치 조회 실패 시 대체 좌표(서울시청).
const fallbackLocation = ll.LatLng(37.5665, 126.9780);

/// 'GPS 신호 약함' 배지 임계값. 진입 판정([decisiveAccuracyMeters], 20 m)보다
/// 느슨하다 — 배지는 경고이고 판정은 결론이라 후자가 더 엄격한 것이 맞다.
const lowAccuracyThresholdMeters = 30.0;

/// 안내를 시작할 수 있는 경로로부터의 최대 거리(m).
///
/// **실측이 아니라 가정이다.** 도심 GPS 오차([lowAccuracyThresholdMeters], 30 m)와
/// 이면도로 한 블록을 덮되, 다른 동네에서 누르면 확실히 걸리는 값으로 잡았다.
/// [outdoorRouteMaxProjectionOffsetM](25 m)을 쓰지 않는 이유는 그 값이 "걸어온
/// 자취를 경로 위에 그려도 되는가"라 훨씬 엄격해서다 — 그 기준으로 막으면 출발선에
/// 선 사용자도 GPS가 한 번 튀면 시작하지 못한다. 현장에서 조정할 자리다.
const guidanceStartMaxOffsetM = 150.0;

/// 야외 완료선이 채택하는 최대 경로 이탈(m). 넘으면 건물 안이나 평행 도로를
/// 걸은 흔적이 계획 경로 위에 그려진다.
const outdoorRouteMaxProjectionOffsetM = 25.0;

/// 야외 사용자 선은 **단조 증가**다. GPS가 흔들려 진행점이 떨리는 것을 표시하지
/// 않되, 되돌아 걸어도 지나온 선은 완료 이력으로 남긴다.
const outdoorRouteRegressionToleranceM = 2.0;

/// 실내 ETA 계산용 평균 걷기 속도. 실내 화면 상수와 같아야 두 화면의 표시가
/// 어긋나지 않는다.
const indoorWalkingSpeedMetersPerSecond = 1.2;

/// 자동 진입 때 **입구** 좌표를 통행 그래프에 붙일 수 있는 최대 거리(m).
///
/// 손으로 찍는 경우([maxPdrAnchorSnapDistanceM])보다 좁다. 여기서 비교하는 둘은
/// 같은 백엔드가 내려준 값이라, 크게 벌어졌다면 손 떨림이 아니라 **데이터 정합이
/// 깨진 상태**다. 그때 억지로 스냅하면 건물 반대편에 위치를 찍는다.
const maxEntranceAnchorSnapDistanceM = 25.0;

/// 자동 진입 때 **GPS 좌표**를 통로에 붙일 수 있는 최대 거리(m). 문 폴백보다
/// 조인다 — 좌표는 오차 반경을 달고 오므로 멀면 매장 한가운데를 가리킨다.
const autoEntryGpsSnapDistanceM = 15.0;

/// PDR 앵커를 **손으로 찍을 때** 통로까지 허용하는 거리(m). 야외에서는 건물이
/// 작게 보여 탭이 20~25 m 빗나가는 일이 흔하다.
const maxPdrAnchorSnapDistanceM = 40.0;

/// 자동 앵커 확정 전에 센서 첫 보고를 기다리는 상한.
const sensorWarmupTimeout = Duration(seconds: 2);

/// GPS course를 믿을 수 있는 최소 속도(m/s). 이보다 느리면 플랫폼이 채우는 0°를
/// "정북으로 걸어 들어왔다"로 오독한다.
///
/// **진입이 버튼으로 바뀐 뒤로 이 갈래는 거의 안 걸린다** — 사람은 멈춰 서서
/// 누르기 때문이다. 그래서 복도 축 폴백이 사실상 본선이다.
const entryCourseMinSpeedMps = 0.5;

/// 앵커 회전각을 가져올 복도를 이 거리 안에서 찾는다(m).
///
/// 손으로 찍는 상한([maxPdrAnchorSnapDistanceM], 40 m)보다 조인다. 저쪽은 "이
/// 자리를 통로에 붙인다"라 멀어도 답이 하나지만, 여기서는 멀리 있는 복도의
/// 각도를 가져다 **궤적 전체를 돌린다** — 먼 복도는 근거가 못 된다.
const anchorAxisSnapDistanceM = 20.0;

/// 복도 축의 앞뒤를 걸어 보고 확인하기까지 필요한 누적 이동(m).
///
/// 짧으면 두 가설(그대로·뒤집음)의 그래프 이탈 거리가 갈리지 않는다. 6 m는
/// 대략 여덟 걸음이고, 복도 하나를 벗어나기에는 충분히 짧다.
const anchorAxisProbeTravelM = 6.0;

/// 뒤집은 가설이 이만큼 더 가까워야 실제로 뒤집는다(m).
///
/// 0이면 잡음으로도 뒤집힌다. 한번 뒤집으면 궤적이 통째로 돌아 사용자가 보던
/// 화면을 잃으므로, 애매하면 그대로 두는 쪽이 낫다.
const anchorAxisProbeMarginM = 1.0;

/// 자동차 안내 시작 zoom. 다음 교차로가 화면에 들어오면서 실내 진입 임계값 위라
/// 건물 근처에서 눌러도 도면이 끼어들지 않는다.
const carGuidanceZoom = 17.5;

/// 검색 결과의 야외 장소로 옮길 때의 zoom. 진입 임계보다 낮아 위치 확인이 실내
/// 진입으로 읽히지 않는다.
const poiFocusZoom = 17.0;

/// TMAP POI가 이만큼 안이면 그 건물의 가게로 본다.
///
/// 폴리곤 판정으로는 안 된다 — TMAP 좌표는 대표점이 아니라 **도로 접근점**이라
/// 입점 매장도 건물 밖 인도에 찍힌다. 브랜드 이름까지 맞아야 합치므로 남의 가게를
/// 삼킬 여지는 좁다.
const poiBuildingProximityMeters = 40.0;

/// 건물 폴리곤 fill opacity. 기본은 존재만 알리고, 탭한 순간 반짝여 "인식됐다"를
/// 보인다.
const buildingFillOpacityDefault = 0.15;
const buildingFillOpacityPressed = 0.45;
const buildingPressedHoldMs = 220;

/// 건물을 탭해 실내로 들어갈 때 카메라 확대 시간. 400ms 이하면 갈아 낀 것과
/// 구분이 안 되고, 1.5초 이상이면 굼떠 두 번 누른다.
const indoorZoomInDuration = Duration(milliseconds: 900);

/// 층을 갈아탈 때 카메라 재정렬 시간. 진입보다 짧다 — 같은 건물 안에서 도면만
/// 갈아 끼우는 것이라 900ms면 층을 훑을 때마다 답답하다.
const floorSwitchZoomDuration = Duration(milliseconds: 500);

/// 안내 시작 시 경로 전체를 담으러 물러서는 시간. 진입보다 짧고 층 전환보다 길다.
const routeOverviewDuration = Duration(milliseconds: 700);

/// 이보다 짧은 경로는 개요 연출을 하지 않는다. 담을 것이 없어 출렁임만 남는다.
const routeOverviewMinDistanceM = 5.0;

/// 경로 상자의 변 길이 하한(m). **없으면 zoom이 발산한다** — 곧은 복도 경로는
/// 짧은 변이 0에 수렴하는데 [zoomToFitWidth]가 `log(가용폭 / 폭)`이다.
const routeFitMinSideM = 12.0;

/// 경로 개요 확대 상한. 하한만으로는 짧은 세그먼트에서 복도 하나만 꽉 찬 화면이
/// 된다 — **주변 매장 몇 개는 함께 보여야** 여기가 어디인지 읽힌다.
const routeFitMaxZoom = 18.1;

/// 편의시설 강조 상자의 변 하한(m). 경로보다 넉넉하다 — 시설 칸은 화장실 한
/// 칸처럼 작고, 상자를 그 크기에 딱 맞추면 **주변이 통째로 잘려** 그게 층
/// 어디쯤인지 읽히지 않는다.
const facilityFitMinSideM = 40.0;

/// 편의시설 강조 확대 상한. 한 곳만 있는 종류(엘리베이터 한 대)에서 화면이
/// 그 칸으로 가득 차는 것을 막는다 — **물러서려고 만든 동작이 되레 파고든다.**
const facilityFitMaxZoom = 18.0;

/// "내 위치로"가 되돌아가는 배율의 **하한**. 이미 더 확대해 둔 사용자에게는
/// 적용하지 않는다 — 들여다보려 당겨 둔 배율을 버튼 한 번에 뺏지 않는다.
const walkingViewZoom = indoorTilesMaxZoom;

/// `안내 시작`을 누른 직후 내려앉는 배율.
///
/// [walkingViewZoom](18)보다 한 단계 더 당긴다. 18은 세로 화면 폭에 약 85 m가
/// 담기는데, 첫 걸음을 어느 쪽으로 떼는지 보려는 사람에게는 자기 아이콘이 너무
/// 작다. 19면 약 43 m — 지금 선 복도와 다음 갈림길이 함께 들어온다.
///
/// **실내 타일은 [indoorTilesMaxZoom]를 넘으면 z=18을 over-scale한다.** 그건
/// 그 상수가 이미 의도한 동작이라(indoor_entry_zoom.dart) 도면이 흐려질 뿐
/// 뒤틀리지 않는다.
const guidanceStartZoom = 19.0;

/// "내 위치로" 이동 시간. 직접 누른 조작이라 과정을 보여 줄 이유가 없다.
const recenterDuration = Duration(milliseconds: 300);

/// 실내 안내 중 카메라가 사용자를 따라갈 때의 배율.
///
/// **실내 타일 maxzoom(18, [indoorTilesMaxZoom])을 넘는 값이다.** MapLibre가 18
/// 타일을 늘려 그리는 overzoom 구간이라 라벨과 선이 약간 뭉갠다. 그걸 알고도 19를
/// 고른 이유는 18이 "건물 안에서 안내를 받는" 화면이 아니라 조감도로 읽혔기
/// 때문이다 — [walkingViewZoom](=18)은 위치를 **확인**하는 배율이고 이건 길을
/// **따라가는** 배율이다. 뭉개짐이 문제가 되면 여기만 18.5로 내리면 된다.
const indoorFollowZoom = 19.0;

/// 팔로우 카메라 bearing이 목표를 따라잡는 시정수.
///
/// 카메라는 이제 명령을 띄엄띄엄 보내지 않고 **매 프레임** 이 시정수로 목표를
/// 따라간다(`glidedFollowBearingDeg`). 예전에는 400ms마다 320ms짜리
/// animateCamera를 걸었는데, 애니메이션마다 가속·감속이 붙어 있어 이어 붙이면
/// 화면이 돌다 서다를 반복했다 — 현장에서 "돌 때 뚝뚝 끊긴다"로 올라온 화면이다.
///
/// 처음 240ms로 잡았다가 실기기에서 "되게 늦게 따라온다"고 나와 120ms로 내렸다
/// (2026-08-24). 데드밴드가 낸 각 계단은 이제 vsync 보간이 지우므로, 시정수까지
/// 길게 잡아 두 겹으로 늦출 이유가 없었다. 90° 코너가 약 0.35초다.
const followCameraBearingTimeConstant = Duration(milliseconds: 120);

/// 팔로우 카메라가 도는 **최대 각속도**(도/초).
///
/// 목표각은 초당 두어 번, 한 번에 수십 도씩 뛰어서 온다(PDR 스냅샷 주기 —
/// `pdr_session.dart`의 heading emit 조건). 속도를 안 자르면 도착 직후 300°/s로
/// 후려치고 다음 목표까지 멈춰 서서, 초당 두세 번 "확 돌고 멈춤"이 반복된다.
///
/// **안전판이다.** 방향 신호가 33Hz로 촘촘해진 뒤로 보통 회전에서는 걸리지
/// 않는다 — 층 fit이나 하차 조준 뒤 팔로우가 돌아올 때처럼 각이 통째로 벌어진
/// 경우에만 걸려서, 180°가 반 바퀴 도는 데 0.5초를 쓰게 한다.
///
/// 한동안 90°로 낮춰 두었다가 되돌렸다(2026-08-24). 그때는 목표각이 초당 두어
/// 번밖에 안 와서 도약을 등속 램프로 펴는 데 썼는데, 그 대가로 **몸이 멈춘 뒤에도
/// 화면이 계속 돌아** 어지럽다는 반응이 나왔다. 신호를 촘촘히 받는 쪽으로
/// 고치고 나서는 그럴 이유가 없다.
const followCameraBearingMaxRateDegPerSec = 360.0;

/// 마커 소스를 다시 쓰는 최소 간격.
///
/// 카메라는 **프레임마다** 놓지만 마커는 이 간격으로만 쓴다 — 마커 쓰기는
/// GeoJSON 인코딩과 네이티브 파싱까지 딸려 있어, 둘을 같이 보내면 채널이 차서
/// 카메라 명령이 밀린다(회전이 계단으로 보이던 몫).
const markerSourceWriteInterval = Duration(milliseconds: 33);

/// 이 시간 넘게 카메라를 안 잡고 있었으면 **지금 카메라 각을 다시 읽어** 거기서
/// 이어 간다(ms).
///
/// 유예([`_holdFollowCamera`])나 층 fit처럼 다른 주인이 카메라를 돌린 뒤라,
/// 마지막으로 우리가 그린 각에서 이어 가면 화면이 그 각으로 한 번 튄다.
const followCameraResumeGapMs = 200;

/// 이 각도 안에서는 **화면이 따라가지 않는다**(도).
///
/// 실내 나침반은 서 있어도 몇 도씩 흔들린다. 그걸 그대로 따르면 지도가 계속
/// 잘게 진동해 읽을 수가 없다.
///
/// 예전에는 이 값으로 **목표각**을 붙들었다. 그러면 목표가 5~8°씩 계단으로
/// 뛰고, 그 계단이 그대로 회전에 보인다. 지금은 목표를 계속 따라가되 **남은 각이
/// 이보다 작으면 안 도는** 데드존이다([glidedFollowBearingDeg]) — 흔들림은 똑같이
/// 걸러지고 계단은 사라진다. 화면이 최대 이만큼 틀어져 있을 수 있지만, 5°는
/// 복도 방향을 읽는 데 지장이 없다.
const followCameraBearingDeadZoneDeg = 5.0;

/// 걷는 방향 쪽으로 끌어당기는 비율(0=나침반만, 1=걷는 방향만).
///
/// 0.5를 넘겨 걷는 방향에 무게를 싣되, 1로 두지는 않는다 — 근거는
/// `map/camera/follow_camera.dart`의 `blendedFollowBearingDeg`.
const followCameraWalkingPullWeight = 0.6;

/// 팔로우 중 내 위치를 화면 **아래쪽**으로 내리는 정도(화면 높이 대비 비율).
///
/// 가운데 두면 화면의 뒤쪽 절반이 이미 지나온 길로 낭비된다. 이만큼 내리면 내
/// 위치가 화면의 약 2/3 지점에 오고 갈 길이 그만큼 넓게 보인다. 카메라 목표점을
/// 진행 방향으로 미는 방식이라, 되돌아오는 "내 위치" 버튼과 층 도면 fit은
/// 영향을 받지 않는다(그쪽은 여전히 정중앙이다).
const followCameraForwardLiftRatio = 0.18;

/// 마지막 걸음이 이 시간 안이면 "걷는 중"으로 본다.
///
/// 걸음 하나하나가 아니라 **최근에 걸었는가**를 봐야 한다 — 스냅샷은 걸음보다
/// 훨씬 자주 오므로 "이번 스냅샷에 걸음이 늘었나"로 물으면 대부분의 틱에서
/// false가 되어 걷는 내내 혼합 비율이 깜빡인다. 느린 걸음(0.5 Hz)도 놓치지
/// 않으면서 멈춤은 두 걸음 안에 알아채는 길이.
const followCameraWalkingStepWindowMs = 1800;

/// 도면을 맞출 때 위·아래에서 비워 두는 chrome 높이(논리 px). 안 빼면 도면
/// 윗부분이 검색창·카테고리 칩에 가린다.
const floorFitTopChromePx = placingHintTopPx;
const floorFitBottomChromePx = mapShellBottomChromePx;

/// 층 도면을 맞출 때 **아래에서 실제로 비울 높이.**
///
/// [floorFitBottomChromePx]는 하단 바만 센 어림값이라, 지도 아래에 판이 붙는
/// 상태(시설 시트)에서는 모자란다. 그대로 쓰면 도면이 화면 전체 기준으로
/// 맞춰져 아래 절반이 시트 뒤로 들어가고, **층을 바꿔도 배율이 그대로인 것처럼**
/// 보인다(시설 시트를 연 채 층 선택기를 누르면 그랬다).
///
/// [bottomOverlayLiftPx]는 셸이 내려 주는 그 판의 높이다
/// ([OutdoorMapBody.bottomOverlayLiftPx]) — 시설 강조 fit이 쓰는 것과 같은 값이라,
/// 두 fit이 같은 바닥을 본다.
double floorFitBottomChromeFor(double bottomOverlayLiftPx) =>
    math.max(floorFitBottomChromePx, bottomOverlayLiftPx);

/// 안내 중 chrome 높이. **층 도면용 값을 그대로 쓰면 안 된다** — 안내가 시작되면
/// 칩 줄이 접히고 상단 바도 한 줄로 줄어, 없는 줄만큼 비우면 경로가 아래로 눌린다.
const guidanceFitTopChromePx = 92.0;
const guidanceFitBottomChromePx = bottomBarLiftPx;

/// `MapBottomBar`의 안쪽 아래 여백. 층 선택기 baseline 계산에 쓴다.
const bottomBarInnerBottomPaddingPx = 14.0;

/// pill 하단을 하단 바 맨 아랫줄과 같은 baseline에 앉힌다. 실내 화면과 같은
/// 계산이어야 두 화면에서 pill 위치가 어긋나지 않는다.
const floorSelectorBottomOffset = bottomBarInnerBottomPaddingPx;

/// 하단 바(`MapBottomBar`) **버튼 줄 바로 위**의 자리. 화면 아래에서 잰
/// 논리 px이고 **안전영역은 빼고 준다** — 얹는 쪽이 제 [SafeArea]로 이미
/// 그만큼 올라와 있다(안 감싸는 곳은 스스로 더한다).
///
/// 상수로 둘 수 없다. 하단 바는 탭 줄·시설 시트·이슈 다이어리 위에 얹혀
/// 상태마다 다른 높이에 뜨고, 그 높이는 셸만 안다
/// ([OutdoorMapBody.bottomOverlayLiftPx]가 그 값이다). 상수(112)로 두었던
/// 축척 막대가 탭 줄이 생긴 뒤 "위치 보정" 버튼 위로 걸친 것이 그 이유다.
///
/// 검증은 `client/test/screens/outdoor_map/widgets/scale_bar_placement_test.dart`.
double aboveMapBottomBarPx(double bottomOverlayLiftPx) =>
    bottomOverlayLiftPx +
    bottomBarInnerBottomPaddingPx +
    RoutexMetrics.minimumTouchTarget +
    RoutexSpacing.controlGap;

/// ETA 카드가 뜨면 하단 바가 이만큼 올라간다. `_etaBarLiftHeight`와 같아야 한다.
const bottomBarLiftPx = 92.0;

/// PDR 진단 공유 버튼을 화면 **위에서** 내리는 오프셋.
///
/// 아래가 아니라 위인 이유: 도착 카드·ETA 카드는 화면 바닥에 붙는 표면이라
/// (`bottom: 0`) 하단에 둔 버튼을 상태에 따라 덮는다. 조건부로 올리면 "어떤
/// 상태에서만 안 눌리는" 자리가 되므로 아예 위로 뺀다. 값은 디버그 칩 열과 같은
/// 줄([placingHintTopPx] + 44) — 그 열은 IgnorePointer라 탭을 다투지 않는다.
/// 검증은 `test/screens/outdoor_map/widgets/pdr_control_placement_test.dart`.
const pdrControlTopPx = placingHintTopPx + 44;

/// 하단 바가 먹는 높이의 **어림값**. 도면을 맞출 때 아래에서 비우는 데만 쓴다
/// ([floorFitBottomChromePx]).
///
/// 화면에 얹는 것(축척 막대·스낵바)은 이 상수를 쓰지 않는다 — 하단 바는 탭
/// 줄·시설 시트에 따라 다른 높이에 뜨는데 상수는 그것을 못 따라가, 탭 줄이
/// 생긴 뒤 축척 막대가 "위치 보정" 버튼 위로 걸쳤다. 그쪽은 셸이 내려 주는
/// 값으로 그때그때 잰다(`parts/ui.dart`의 `_aboveBottomBarPx`). 카메라 fit은
/// 몇 px 어긋나도 도면이 조금 더/덜 여유롭게 잡힐 뿐이라 어림으로 충분하다.
const mapShellBottomChromePx = 112.0;

/// 위치 지정 안내를 상단 chrome 아래에 놓는 오프셋.
///
/// 이 오버레이는 칩 열과 **다른 Stack**이라 Positioned만으로는 겹침을 피할 수
/// 없다 — SafeArea로 감싸 노치 기기의 밀림까지 따라가야 한다. 실내 화면의 동명
/// 상수(184)와 **일부러 다르다**: 홈은 상단이 pill 한 줄, 실내는 3단이다.
const placingHintTopPx = 132.0;
