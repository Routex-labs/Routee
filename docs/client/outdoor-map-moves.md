# 이동 대장 — 야외 지도 화면 해체

## 먼저: 지금 어느 파일을 열어야 하나

0단계에서 화면을 성격별 `part` 파일로 갈랐다(1f841f67). **찾는 코드가 본체에 없으면
아래에서 고른다.** 전부 같은 라이브러리라 심볼 이름은 그대로다.

| 찾는 것 | 파일 | 줄 |
|---|---|---|
| 상태 필드·생명주기·`build`·공개 API 19개 | `outdoor_map_screen.dart` | 1,967 |
| 경로 **계산**(TMAP·실내 그래프·pending 인계) | `parts/route.dart` | 1,148 |
| 실내 오버레이·건물 로드·카메라 맞춤 | `parts/indoor.dart` | 976 |
| PDR·앵커·보정 | `parts/pdr.dart` | 657 |
| 에스컬레이터 탑승·하차 판정 | `parts/escalator.dart` | 605 |
| 시트·배너·`_buildBody` | `parts/ui.dart` | 485 |
| 카메라·스타일 | `parts/map.dart` | 395 |
| **층 전환 크로스페이드**·세대 관리 | `parts/floor_switch.dart` | 328 |
| **안내 진행률·도착 판정**·기록 세션 | `parts/guidance.dart` | 298 |
| GPS·위치 | `parts/gps.dart` | 285 |
| **매장 탭 판정**(화면 좌표 → 매장) | `parts/store_tap.dart` | 204 |
| **경로·목적지를 지도에 쓰기**(sync 계열) | `parts/route_layers.dart` | 203 |

part가 아닌 이웃 파일 둘도 여기서 갈라져 나왔다.

| 찾는 것 | 파일 |
|---|---|
| 거리 문턱·줌 배율·애니메이션 길이·화면 여백 | `outdoor_map_tuning.dart` |
| "위치 지정" 안내 카드 | `widgets/placing_anchor_hint.dart` |

이름으로 나눈 것이라 **경계가 완벽하지 않다.** 못 찾으면 `grep -rn '심볼이름'
lib/screens/outdoor_map/` 이 가장 빠르다.

`outdoor_map_screen.dart`에서 무엇이 어디로 갔는지의 **단일 출처**다.
[해체 계획](outdoor-map-decomposition.md)의 규칙 3이 요구하는 문서다.

## part 파일 규약

위 표의 파일은 전부 `part of 'outdoor_map_screen.dart'`다. 파일 머리에는 "무엇을
담았나" 한 줄만 두고, 아래 세 가지는 여기에만 적는다 — 12개 파일에 같은 문단을
베껴 두면 한 곳을 고칠 때 나머지 열한 곳이 조용히 낡는다.

**왜 `// ignore_for_file: invalid_use_of_protected_member`인가.**
`setState`는 `OutdoorMapBodyState`가 `State`에서 물려받은 protected 멤버이고,
part 파일에서 부르는 것은 **같은 클래스의 코드**다 — 파일만 갈라져 있을 뿐 바깥에서
남의 protected 멤버를 건드리는 것이 아니다. 그런데 분석기는 extension을 "서브클래스가
아니다"로 보아 경고한다. 그래서 파일 단위로 끈다. 본체(생명주기·`build`)는 클래스
안에 있어 이 해제의 영향을 받지 않으므로, 진짜 위반이 본체에 생기면 여전히 잡힌다.

**왜 mixin이 아니라 extension인가.** 같은 라이브러리(part)라 private 멤버가 그대로
보이고 extension끼리도 서로 부를 수 있다. mixin은 서로의 private 멤버를 못 봐서
이렇게 얽힌 클래스에는 쓸 수 없다.

**본체에 남는 것.** 상태 필드, 생명주기(`initState`·`dispose`·`build`), 셸이 부르는
공개 API 19개. 한 파일이 7,500줄을 넘어 읽을 수 없어져 성격별로 갈랐고,
**옮기기만 했고 동작은 그대로다.**

### 파일을 그 자리에서 또 가른 이유

처음 갈랐을 때 만든 파일 중 셋이 다시 커져서, 안에서 관심사를 한 번 더 뗐다.
기준은 하나다 — **고치는 이유가 다르면 파일을 나눈다.**

| 파일 | 어디서 나왔나 | 왜 |
|---|---|---|
| `_guidance` | `_route` | 경로를 **만드는** 코드는 목적지가 바뀔 때 돌고, **따라가는** 코드는 걸음이 들어올 때 돈다. 한 파일에 두면 진행률 버그를 고치려는 사람이 TMAP 호출까지 읽는다. |
| `_route_layers` | `_route` | 계산과 **지도에 쓰기**는 도는 이유가 다르다(알고리즘 ↔ 레이어 순서·MapLibre 동작). 여기 있는 건 상태를 읽어 소스에 밀어 넣는 얇은 껍데기뿐이고, GeoJSON 조립·레이어 등록은 화면 상태를 모르는 `route_map_layers.dart`·`marker_map_layers.dart`가 따로 시험된다. |
| `_floor_switch` | `_indoor` | 층 바꾸기는 실내 오버레이에서 가장 조심스러운 경로다 — 옛 층을 지우기 전에 새 층을 깔아야 깜빡임이 없고, 그 사이 사용자가 또 바꾸면 두 전환이 겹친다. 그 **순서와 세대(generation) 관리**가 한 덩어리다. |
| `_store_tap` | `_indoor` | "지금 누른 자리에 어떤 매장이 있나"는 화면 좌표 → 타일 feature → 도메인 모델을 거치는 별개의 문제다. 한 폴리곤을 여러 매장이 나눠 쓰는 자리에서는 가장 가까운 라벨까지 따져야 해서, 그 규칙이 오버레이 코드에 섞이면 읽히지 않는다. |

rebase 충돌은 대부분 "이 함수 어디 갔지"를 찾는 데 시간이 든다. `main` 쪽 변경이 여기
적힌 옛 심볼을 건드렸다면, 새 위치에 같은 변경을 적용하면 끝난다.

읽는 법: **옛 이름은 옮기기 전 `OutdoorMapBodyState`의 멤버**다. 새 이름이 옛 이름과 다르면
Dart의 파일 단위 프라이버시(`_`) 때문에 공개로 바꾼 것이고, 그 외 본문은 글자 그대로다.

| 옛 심볼 | 새 위치 | 커밋 |
|---|---|---|
| `emptyGeoJsonCollection` `geoJsonCollection` `geoJsonLineFeature` (private) | `map/geojson.dart` (동명 공개) | 53a962b |
| `_registerDebugPdrLayers` | `screens/outdoor_map/layers/pdr_debug_map_layers.dart:registerPdrDebugLayers` | 6082e6f |
| `_syncDebugPdrLayers`의 지도 쓰기 부분 | 〃 `syncPdrDebugLayers` | 6082e6f |
| `_setTrail` | 〃 `_setTrail`(파일 private) | 6082e6f |
| `_renderPdrLocationIcon` | `widgets/location_marker_icon.dart:renderLocationMarkerIcon` | a3d8b6d |
| `_pdrLocationIconPixelRatio` `_pdrLocationCoreRadius` `_pdrLocationRimRadius` | 〃 `kLocationMarkerIcon*` | a3d8b6d |
| `FloorPlanViewState._renderCurrentLocationIcon` | 〃 (같은 함수로 통합) | a3d8b6d |
| 대중교통 소스·레이어 등록 (`_onStyleLoaded` 안) | `screens/outdoor_map/layers/transit_map_layers.dart:registerTransitLayers` | 7683ba0 |
| `_syncTransitLayer`의 feature 변환·쓰기 | 〃 `syncTransitLayer` | 7683ba0 |
| `_badgeImageFor` | 〃 `_badgeImageFor`(파일 private) | 7683ba0 |
| 경로선 소스·레이어 등록 (`_onStyleLoaded` 안) | `screens/outdoor_map/layers/route_map_layers.dart:registerRouteLayers` / `registerTransferRouteLayer` | 2a327cd |
| `_routeSourceId` `_walkedRouteSourceId` `_transferRouteSourceId` `_routeCasingLayerId` | 〃 `kOutdoorRoute*` / `kOutdoorRouteCasingLayerId` | 2a327cd |
| `_searchDirectionsCandidates` (map_shell) | `screens/map_shell/directions_candidates.dart:searchDirectionsCandidates` | 0f71a80 |
| `_semanticDirectionsCandidates` `_mergeOutdoorResults` `_storeCandidate` `_outdoorRowCandidate` `_buildingDestinationPoint` (map_shell) | 〃 | 0f71a80 |

### 1단계 — 레이어 쓰기 모듈화

| 옛 심볼 | 새 위치 | 커밋 |
|---|---|---|
| `_currentSourceId` `_destSourceId` `_indoorDestSourceId` | `screens/outdoor_map/layers/marker_map_layers.dart:kOutdoorCurrentSourceId` / `kOutdoorDestSourceId` / `kOutdoorIndoorDestSourceId` | 0a50df2e |
| `_accuracyLayerId` `_currentDotLayerId` `_destLayerId` `_destinationPinImageName` `_destinationPinIconSizeZ16/Z20` | 〃 (파일 private) | 0a50df2e |
| `_indoorDestLayerId` | 〃 `kOutdoorIndoorDestLayerId` | 0a50df2e |
| 현재 위치·목적지 소스/레이어 등록 (`_onStyleLoaded` 안) | 〃 `registerCurrentLocationLayers` / `registerDestinationLayer` | 0a50df2e |
| 실내 도착 핀 비트맵·소스 등록 (`_onStyleLoaded` 안) | 〃 `registerIndoorDestinationLayers` | 0a50df2e |
| `_addIndoorDestinationPinLayer` | 〃 `addIndoorDestinationPinLayer` | 0a50df2e |
| `_pointFeature` | 〃 `pointFeature` | 0a50df2e |
| `_syncCurrentLayer` `_syncDestinationLayer` `_syncIndoorDestinationLayer`의 쓰기 부분 | 〃 `syncPointSource`(셋이 공유) | 0a50df2e |
| `_buildingSourceId` `_dimScrimSourceId` `_floorOutlineSourceId` | `screens/outdoor_map/layers/shape_map_layers.dart:kOutdoorBuilding/DimScrim/FloorOutlineSourceId` | 0a50df2e |
| `_buildingFillLayerId` `_dimScrimFillLayerId` | 〃 `kOutdoorBuildingFillLayerId` / `kOutdoorDimScrimFillLayerId` | 0a50df2e |
| `_floorOutlineLayerId` | 〃 (파일 private) | 0a50df2e |
| 건물·스크림·외곽선 등록 (`_onStyleLoaded` 안) | 〃 `registerBuildingAndScrimLayers` / `registerFloorOutlineLayer` | 0a50df2e |
| `_closedRing` | 〃 `closedRing` | 0a50df2e |
| `_syncBuildingLayer` `_syncFloorOutlineLayer`의 쓰기 부분 | 〃 `syncPolygonSource`(둘이 공유) | 0a50df2e |
| `_syncDimScrimLayer`의 geometry 쓰기 부분 | 〃 `syncDimScrimSource` (opacity 판단은 화면에 남음) | 0a50df2e |
| `_pdrCurrentSourceId` | `screens/outdoor_map/layers/marker_map_layers.dart:kOutdoorPdrCurrentSourceId` | 0a50df2e |
| `_pdrCurrentLayerId` `_pdrLocationImageName` `_pdrLocationDotImageName` | 〃 (파일 private) | 0a50df2e |
| PDR 마커 비트맵·소스·레이어 등록 (`_onStyleLoaded` 안) | 〃 `registerPdrLocationImages` / `registerPdrLocationLayer` | 0a50df2e |
| `_syncPdrCurrentLayer`의 feature 조립 | 〃 `pdrLocationData` (쓰기 큐·revision 판단은 화면에 남음) | 0a50df2e |

**1단계 완료(0a50df2e).** 화면 파일의 레이어 id 상수 0개, 8,569 → 8,188줄.

### 2단계 — 카메라 명령 분리

화면에 남은 `_fitCameraTo*` / `_recenterOn*`는 **무엇에 맞출지 고르는 껍데기**가 됐다.
실제 카메라 호출은 전부 아래로 내려갔다.

| 옛 심볼 | 새 위치 | 커밋 |
|---|---|---|
| `_animateCameraToFitBox`의 계산·호출 부분 | `screens/outdoor_map/camera/map_camera_commands.dart:animateCameraToFitBox` | 21ba4a7f |
| `_fitCameraToPoints`의 bbox 계산·호출 | 〃 `animateCameraToPoints` | 21ba4a7f |
| `_moveCameraToUser`의 호출 부분 | 〃 `animateCameraToPoint` | 21ba4a7f |
| `_recenterOnCurrentPosition`의 호출 부분 | 〃 `recenterKeepingBearing` | 21ba4a7f |
| `_toGl` | 〃 `toGlLatLng` | 21ba4a7f |
| `_floorFitFillRatio` | 〃 `_fitFillRatio`(파일 private) | 21ba4a7f |

화면 크기를 `BuildContext`가 아니라 `Size`로 받는다 — 카메라 명령이 `MediaQuery`를 직접
보면 위젯 트리 없이는 한 줄도 시험할 수 없는데, 실제로 필요한 것은 폭·높이 두 숫자뿐이다.

### 3단계 — GPS 세션 추출 (필드 이동 시작)

옮기기 **전에** 특성 테스트를 먼저 썼다(`test/screens/outdoor_map/gps_stream_lifecycle_test.dart`,
커밋 64aa38ad). 이동 전후 모두 통과하는 것이 이 단계의 증거다.

| 옛 심볼 | 새 위치 | 커밋 |
|---|---|---|
| `_positionSubscription` `_streamRetryDelay` `_streamRetryTimer` `_streamDeliveredFix` `_streamFirstFixTimer` `_freshFixTimer` `_freshFixInFlight` `_lastFixReceivedAt` | `screens/outdoor_map/gps/gps_session.dart:GpsSession`(전부 private 필드) | 655d940e |
| `_streamRestartCount` `_lastFixFromStream` | 〃 `restartCount` / `lastFixFromStream` 게터 | 655d940e |
| `_subscribeToPositions` | 〃 `_subscribe` | 655d940e |
| `_handlePositionStreamClosed` | 〃 `_handleClosed` | 655d940e |
| `_syncFreshFixTimer` `_maybeRequestFreshFix` | 〃 (같은 이름, private) | 655d940e |
| `_handlePosition`의 스트림 상태 갱신 부분 | 〃 `_deliver` | 655d940e |

화면에 남은 것: `_position`(그릴 값), `_lastFixAt`(진단), `_gpsEntryArmed`(진입 판정),
`_handlePosition`의 판정·렌더링 부분, `_syncGpsSubscription`(켤지 말지 결정).

**대조로 잡은 차이 3건**(옮기기만 했다면 조용히 달라졌을 것들):
스트림 좌표 수신 시 재연결 간격 되돌리기 누락, `lastFixReceivedAt`을 게이트 앞에서 찍던
것, `onError`일 때 마지막 좌표를 버리던 동작(→ `onStreamError` 콜백으로 살림).

### 4단계 — PDR 세션 수명 추출

계획의 "PDR 앵커 세션"(필드 16) 중 **수명 부분만** 뗐다. 앵커 배치는 스낵바·다이얼로그·
지도 탭과 엮여 있어 5단계로 넘겼다([계획서](outdoor-map-decomposition.md)의 이유 참고).

| 옛 심볼 | 새 위치 | 커밋 |
|---|---|---|
| `_pdrStopInFlight` | `screens/outdoor_map/pdr_session_lifecycle.dart:PdrSessionLifecycle._stopInFlight` | f11b7546 |
| `_awaitPdrStop` | 〃 `awaitStop` | f11b7546 |
| `_startPdrIfIdle`의 게이트 사다리 | 〃 `startIfIdle` (층은 클로저 둘로 읽는다) | f11b7546 |
| `_dropIndoorPosition`의 정지 발사 부분 | 〃 `stopWithoutWaiting` | f11b7546 |

화면에 남은 것: `_startPdrIfIdle`(층·그래프를 읽어 넘기는 껍데기), `_dropIndoorPosition`의
궤적·경로 정리, `_bindPdrSessionToFloor`(setState와 층 결속이 섞여 있어 5단계 몫).

곁들여 `indoorNavigationDriver`의 타입을 구현체에서 계약(`IndoorNavigationController`)으로
좁히고, 계약에 빠져 있던 `onAppBackgrounded`·`onAppForegrounded`를 올렸다(f11b7546).

### 5단계 — 실내 오버레이 (진행 중)

| 옛 심볼 | 새 위치 | 커밋 |
|---|---|---|
| `_indoorIdGeneration` `_indoorTilesSourceId` `_indoorFootprintLayerId` `_indoorStoresFillLayerId` `_indoorCategoryHighlightFillLayerId` `_indoorVerticalTransportFillLayerId` `_indoorStoresLabelLayerId` `_indoorSharedStoresLabelLayerId` `_indoorFacilityLabelLayerId` `_indoorPoiIconLayerId` `_indoorStoreFacilityIconLayerId` | `screens/outdoor_map/layers/indoor_overlay_layers.dart:IndoorOverlayIds`의 게터 | 26c6e461 |
| `_idFor` `_bumpIndoorIds` | 〃 `_idFor` / `next()` | 26c6e461 |
| `_indoorOverlayLayerIds` | 〃 `layersTopFirst` | 26c6e461 |
| `_indoor*LayerIdBase` 상수 10개 | 〃 게터 안으로 인라인 | 26c6e461 |
| `_ensureIndoorTilesRegistered`의 등록·정리 부분 | 〃 `registerIndoorOverlayLayers` | 26c6e461 |
| `_syncIndoorOverlayFade`의 쓰기 목록 | 〃 `syncIndoorOverlayProps` | (이 커밋) |
| `_applyCategoryFilter`의 라벨 쓰기 목록 | 〃 `syncIndoorOverlayProps(scope: labels)` | 〃 |
| `_applyOverlayFillFadeFactor`의 fill 쓰기 목록 | 〃 `syncIndoorOverlayProps(scope: fills)` | 〃 |

같은 레이어 목록이 **세 벌** 흩어져 있었다(전체·라벨만·fill만). 한 함수에 범위
enum으로 모았다 — 레이어가 늘 때 세 곳을 같이 고쳐야 하던 것이 한 곳이 된다.

화면에 남은 것: 등록 게이트(컨트롤러·스타일·건물·층), 타일 URL 계산,
`_indoorTilesRegistered` 플래그, `_overlayFadeExpr`(진입 상태·크로스페이드 계수를
읽는 판단).

## 아직 옮기지 않은 것

- **에스컬레이터·층 전환 전부** — 알고리즘 재작성 예정이라 손대지 않는다.
- 공개 API 19개 — 해체가 끝나도 같은 자리에 남는다([계획서](outdoor-map-decomposition.md)).
