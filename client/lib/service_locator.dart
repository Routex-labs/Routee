import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'core/api_config.dart';
import 'features/debug_mode/debug_mode_controller.dart';
import 'features/indoor_navigation/application/indoor_navigation_controller.dart';
import 'features/indoor_navigation/application/indoor_location_estimate.dart';
import 'features/indoor_navigation/contract/indoor_navigation_contract.dart';
import 'features/indoor_navigation/platform/android_pdr_motion_source.dart';
import 'features/indoor_navigation/platform/ios_pdr_motion_source.dart';
import 'features/indoor_navigation/platform/pdr_motion_source.dart';
import 'repositories/building/building_repository.dart';
import 'repositories/place/destination_repository.dart';
import 'repositories/routing/directions_repository.dart';
import 'repositories/building/http_building_repository.dart';
import 'repositories/place/http_destination_repository.dart';
import 'repositories/routing/mock_directions_repository.dart';
import 'repositories/place/http_place_detail_repository.dart';
import 'repositories/routing/kakao_transit_repository.dart';
import 'repositories/place/outdoor_poi_repository.dart';
import 'repositories/place/place_detail_repository.dart';
import 'repositories/routing/tmap_directions_repository.dart';
import 'repositories/place/tmap_poi_repository.dart';
import 'repositories/routing/transit_repository.dart';
import 'routing/place_link_inbox.dart';
import 'state/favorites_controller.dart';
import 'state/recent_route_points_controller.dart';
import 'state/recent_searches_controller.dart';

/// 앱 전체에서 공유하는 PDR 센서 소스와 세션 드라이버다. 화면이 바뀌어도
/// 센서 세션을 다시 만들지 않도록 singleton으로 유지한다.
PdrMotionSource createDefaultPdrMotionSource({
  TargetPlatform? platform,
  bool? isWeb,
}) {
  if (isWeb ?? kIsWeb) return const UnsupportedPdrMotionSource();
  return switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.iOS => IosPdrMotionSource(),
    TargetPlatform.android => AndroidPdrMotionSource(),
    _ => const UnsupportedPdrMotionSource(),
  };
}

final PdrMotionSource pdrMotionSource = createDefaultPdrMotionSource();

/// 타입이 구현체가 아니라 **계약**([IndoorNavigationController])이다 — 화면이
/// 드라이버 내부에 손을 뻗으면 떼어낼 때마다 구현체를 끌고 다녀야 한다.
///
/// final이다. 화면이 initState에서 스트림을 구독하므로 뒤에 인스턴스를 바꾸면
/// 옛 것만 계속 바라본다. 테스트는 native 채널을 모킹해 진짜 드라이버를 쓴다.
final IndoorNavigationController indoorNavigationDriver =
    IndoorNavigationDriver(source: pdrMotionSource);
final IndoorLocationEstimateController indoorLocationEstimateController =
    IndoorLocationEstimateController();

/// 디버그 모드 설정도 화면 간에 공유한다 — 각자 만들면 한쪽에서 켜도 다른 쪽은
/// 꺼진 값을 보여줘 같은 세션 안에서 PDR 진입점이 있다 없다 한다.
///
/// 위와 같은 이유로 final이다. 테스트에서 바꿔야 하면 인스턴스를 교체하지 말고
/// [DebugModeController.reload]를 쓴다.
final DebugModeController debugModeController = DebugModeController();

/// 실내 지도·목적지 검색·경로 안내가 전부 백엔드 그래프로 동작한다. 오프라인으로
/// 확인할 땐 이 한 줄만 `MockBuildingRepository()`로 되돌린다(테스트도 같은 방법).
BuildingRepository buildingRepository = HttpBuildingRepository();

/// 목적지 자연어 질의는 백엔드의 POST /query/destination(라우터 하나로
/// 최적 매장 1건을 반환)을 그대로 호출한다. 테스트나 백엔드가 아직
/// 없을 때만 [MockDestinationRepository](buildingRepository)로 되돌린다 —
/// 기본은 실제 API를 붙여야 상단 검색·길찾기 시트가 서버의 정규화/동의어
/// 사전을 함께 쓴다.
DestinationRepository destinationRepository = HttpDestinationRepository();

/// 장소 상세는 실패해도 길찾기 흐름을 막지 않는 별도 조회다. 위젯 테스트에서
/// HTTP를 피해야 할 때는 이 변수를 테스트가 만든 대역으로 교체한다.
PlaceDetailRepository placeDetailRepository = HttpPlaceDetailRepository();

/// --dart-define=TMAP_APP_KEY=... 로 키를 넘기면 자동으로 실제 API를 쓰고,
/// 안 넘기면(테스트·키 미발급 상태) 직선 경로로 동작하는 Mock을 쓴다.
final DirectionsRepository directionsRepository = tmapAppKey.isEmpty
    ? MockDirectionsRepository()
    : TmapDirectionsRepository();

/// 건물 **밖** 장소 검색(TMAP POI). 키가 없으면 꺼진 구현이 들어가고 "주변 장소"
/// 섹션이 아예 안 그려진다.
///
/// **Mock을 두지 않는다** — 직선 경로 Mock은 "대충 이 방향"이라도 맞지만, 없는
/// 가게를 지어내면 사용자를 실제로 그 좌표까지 걸어가게 만든다.
OutdoorPoiRepository outdoorPoiRepository = tmapAppKey.isEmpty
    ? const UnavailableOutdoorPoiRepository()
    : TmapPoiRepository();

/// 대중교통 경로(카카오맵). **여기만 카카오 키를 본다** — TMAP 대중교통 무료
/// 제공량이 하루 10건이라 데모 한 번에 소진돼 옮겼다.
///
/// 카카오 응답에는 첫 승차 앞·마지막 하차 뒤 도보가 없어 화면이
/// [directionsRepository]로 채운다 — 대중교통도 TMAP 키가 함께 있어야 완전하다.
TransitRepository transitRepository = kakaoRestApiKey.isEmpty
    ? const UnavailableTransitRepository()
    : KakaoTransitRepository();

/// 사용자가 "장소" 탭에 저장해둔 매장 목록. SharedPreferences로 앱 재실행
/// 뒤에도 유지된다. 테스트에서는 이 변수를 in-memory 컨트롤러로 교체한다.
FavoritesController favoritesController = FavoritesController();

/// 사용자가 최근에 검색한 말. 검색 패널의 빈 화면(idle)을 채운다. 즐겨찾기와
/// 같은 저장소를 쓰지만 **기기 밖으로 나가지 않는다** — 서버로 보내지 않는다.
RecentSearchesController recentSearchesController = RecentSearchesController();

/// 사용자가 길찾기에서 실제로 쓴 출발지·목적지. 길찾기 두 칸의 빈 화면을
/// 채운다. 최근 검색어와 **다른 목록**이다 — 이쪽은 노드·층까지 들고 있어
/// 누르면 바로 경로가 선다. 마찬가지로 기기 밖으로 나가지 않는다.
RecentRoutePointsController recentRoutePointsController =
    RecentRoutePointsController();

/// 걸음 센서(PDR)에 필요한 권한. iOS는 Motion & Fitness, Android는
/// ActivityRecognition이며 가속도·자력계 원시값은 권한이 필요 없다.
Permission get pedometerPermission =>
    defaultTargetPlatform == TargetPlatform.iOS
    ? Permission.sensors
    : Permission.activityRecognition;

/// 앱 시작 시 필요한 권한을 **하나씩 순서대로** 요청한다.
///
/// 목록을 한 번에 던지면 OS 다이얼로그가 겹쳐 떠 무엇을 허용했는지 모른 채
/// 넘기게 된다. 위치를 먼저 묻는 이유는 앱이 야외 지도로 시작하기 때문이다.
Future<Map<Permission, PermissionStatus>>
defaultRequestStartupPermissions() async {
  final statuses = <Permission, PermissionStatus>{};
  for (final permission in [
    Permission.locationWhenInUse,
    pedometerPermission,
  ]) {
    statuses[permission] = await permission.request();
  }
  return statuses;
}

/// 앱 시작 시 권한 요청. 플랫폼 채널이 없는 테스트 환경에서는
/// 이 변수를 즉시 완료되는 가짜 함수로 교체해 실제 플러그인 호출을 피한다.
Future<Map<Permission, PermissionStatus>> Function() requestStartupPermissions =
    defaultRequestStartupPermissions;

/// 걸음 센서 권한이 지금 허용돼 있는지. **다이얼로그를 띄우지 않는다.**
/// 거부된 상태에서 매번 시작을 시도하면 `sensorStartFailed`가 반복해 쌓인다.
///
/// 모바일이 아니면 false, 모바일인데 권한 플러그인만 빠졌으면 **허용으로 본다**
/// (그 경우 시작 실패는 driver가 degraded warning으로 바꾼다).
Future<bool> defaultIsPedometerPermissionGranted() async {
  if (kIsWeb ||
      defaultTargetPlatform != TargetPlatform.iOS &&
          defaultTargetPlatform != TargetPlatform.android) {
    return false;
  }
  try {
    return (await pedometerPermission.status).isGranted;
  } on Object {
    return true;
  }
}

/// 자동 시작 게이트. 테스트에서는 교체해 플러그인 호출을 피한다.
Future<bool> Function() isPedometerPermissionGranted =
    defaultIsPedometerPermissionGranted;

/// 야외 위치 스트림을 얼마나 자주 받을지.
///
/// **간격을 명시하지 않으면 안드로이드는 5초 하한이 걸린다.** 그 기본값이 문서에도
/// 코드에도 안 드러나 "GPS가 원래 느린 것"처럼 보였다(근거와 실측:
/// `docs/client/gps-stream-policy.md` 3절).
LocationSettings positionStreamSettings() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
      intervalDuration: const Duration(seconds: 1),
    );
  }
  return const LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 0,
  );
}

Stream<Position> defaultWatchPosition() {
  return Geolocator.getPositionStream(
    locationSettings: positionStreamSettings(),
  );
}

/// 스트림이 조용할 때 좌표를 한 건 직접 끌어올 때 쓰는 설정.
///
/// **일회성이라도 간격을 준다** — 안드로이드는 요청 간격의 두 배까지 묵은 좌표를
/// "지금 것"으로 돌려주기 때문이다(gps-stream-policy.md 3절).
LocationSettings _oneShotFixSettings() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return AndroidSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
      intervalDuration: const Duration(seconds: 1),
    );
  }
  return const LocationSettings(accuracy: LocationAccuracy.best);
}

/// 야외 지도 화면의 실시간 위치 스트림. 걷는 동안 위치 마커·경로·건물 진입
/// 판정이 계속 갱신되도록 한다. 플랫폼 채널이 없는 테스트 환경에서는 이
/// 변수를 가짜 [Position] 스트림으로 교체한다.
Stream<Position> Function() watchPosition = defaultWatchPosition;

Future<Position> defaultCurrentPosition() {
  return Geolocator.getCurrentPosition(locationSettings: _oneShotFixSettings());
}

/// 좌표를 한 건 직접 끌어오는 일회성 조회. [watchPosition]과 같은 이유로 변수다
/// — 테스트에서 갈아끼우지 못하면 "스트림은 조용한데 기기는 좌표를 만든다"는
/// 상태를 재현할 수 없다(`docs/client/gps-stream-policy.md` 1절).
Future<Position> Function() currentPosition = defaultCurrentPosition;

/// 실내 화면을 직접 열었을 때 추정위치를 만들기 위한 GPS 1회 조회.
///
/// 자동 초기화가 권한 다이얼로그를 갑자기 띄우면 안 되므로 현재 권한이 이미
/// 허용된 경우에만 조회한다. 위치 서비스가 꺼졌거나 권한이 없거나 5초 안에
/// 좌표를 얻지 못하면 null로 끝내고 사용자의 수동 위치 지정을 남겨 둔다.
Future<Position?> defaultRequestIndoorEstimatePosition() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever ||
        permission == LocationPermission.unableToDetermine) {
      return null;
    }
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 5),
      ),
    );
  } on Object {
    return null;
  }
}

/// 테스트에서는 플랫폼 채널 없이 좌표/실패를 주입할 수 있도록 교체 가능하게 둔다.
Future<Position?> Function() requestIndoorEstimatePosition =
    defaultRequestIndoorEstimatePosition;

/// 링크로 받은 장소가 지도 셸에 닿을 때까지 머무는 자리.
///
/// singleton인 이유는 **보내는 쪽과 받는 쪽의 수명이 다르기 때문**이다. 링크는 앱
/// 루트가 받고 화면은 그보다 늦게 세워지며, 화면은 다시 만들어질 수 있다.
final placeLinkInbox = PlaceLinkInbox();
