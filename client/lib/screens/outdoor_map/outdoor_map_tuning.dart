/// 야외 지도의 **조정 값** — 거리 문턱, 줌 배율, 애니메이션 길이, 화면 여백.
///
/// 숫자는 대부분 실기기에서 재보고 정한 것이라 근거를 값 옆에 짧게 남긴다.
library;

import 'package:latlong2/latlong.dart' as ll;

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
const entryCourseMinSpeedMps = 0.5;

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
const routeFitMaxZoom = 17.5;

/// "내 위치로"가 되돌아가는 배율의 **하한**. 이미 더 확대해 둔 사용자에게는
/// 적용하지 않는다 — 들여다보려 당겨 둔 배율을 버튼 한 번에 뺏지 않는다.
const walkingViewZoom = indoorTilesMaxZoom;

/// "내 위치로" 이동 시간. 직접 누른 조작이라 과정을 보여 줄 이유가 없다.
const recenterDuration = Duration(milliseconds: 300);

/// 도면을 맞출 때 위·아래에서 비워 두는 chrome 높이(논리 px). 안 빼면 도면
/// 윗부분이 검색창·카테고리 칩에 가린다.
const floorFitTopChromePx = placingHintTopPx;
const floorFitBottomChromePx = mapShellBottomChromePx;

/// 안내 중 chrome 높이. **층 도면용 값을 그대로 쓰면 안 된다** — 안내가 시작되면
/// 칩 줄이 접히고 상단 바도 한 줄로 줄어, 없는 줄만큼 비우면 경로가 아래로 눌린다.
const guidanceFitTopChromePx = 92.0;
const guidanceFitBottomChromePx = bottomBarLiftPx;

/// `MapBottomBar`의 안쪽 아래 여백. 층 선택기 baseline 계산에 쓴다.
const bottomBarInnerBottomPaddingPx = 14.0;

/// pill 하단을 하단 바 맨 아랫줄과 같은 baseline에 앉힌다. 실내 화면과 같은
/// 계산이어야 두 화면에서 pill 위치가 어긋나지 않는다.
const floorSelectorBottomOffset = bottomBarInnerBottomPaddingPx;

/// ETA 카드가 뜨면 하단 바가 이만큼 올라간다. `_etaBarLiftHeight`와 같아야 한다.
const bottomBarLiftPx = 92.0;

/// 홈/실내 세그먼트 왼쪽에 PDR 제어를 붙이는 right inset. 실내 탭과 야외 오버레이
/// 에서 버튼이 같은 자리에 놓이려면 실내 화면 상수와 같아야 한다.
const pdrControlRightInsetPx = 184.0;

/// PDR 토스트를 하단 바(+ETA 카드) 위로 띄우는 오프셋.
const mapShellBottomChromePx = 112.0;

/// 위치 지정 안내를 상단 chrome 아래에 놓는 오프셋.
///
/// 이 오버레이는 칩 열과 **다른 Stack**이라 Positioned만으로는 겹침을 피할 수
/// 없다 — SafeArea로 감싸 노치 기기의 밀림까지 따라가야 한다. 실내 화면의 동명
/// 상수(184)와 **일부러 다르다**: 홈은 상단이 pill 한 줄, 실내는 3단이다.
const placingHintTopPx = 132.0;
