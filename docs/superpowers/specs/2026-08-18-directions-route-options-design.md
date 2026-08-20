# 야외 경로 다중 후보 + 상세보기 설계

## 배경

지금 자동차·도보 길찾기는 TMAP에서 경로를 **1개만** 받아 검색 즉시 지도에
그린다(`getDrivingRoute`/`getWalkingRoute`). 대중교통(`getTransitRoutes`)은
이미 여러 후보를 `TransitRoutesSheet` 목록으로 보여주고 고르게 한다. 이번
작업은 자동차도 대중교통과 같은 "여러 후보 중에서 고른다" 경험을 갖게 하고,
고른 경로의 **턴바이턴 상세보기**를 자동차·도보 모두에 추가한다.

네이버 지도 스크린샷(브레인스토밍 대화의 이미지 #1~#8)을 참고 자료로 삼되,
그대로 베끼지 않고 이 앱의 기존 패턴(대중교통 목록·색상 규칙)을 따른다.

### 기존 미병합 브랜치와의 관계

`feature-car-route-alternatives`(main에서 안 갈라진 상태, tip `6cdf884c`,
2026-08-17)에 자동차 경로 다중 후보가 **이미 구현·실측되어 있다.** 이
스펙은 그 브랜치를 처음부터 다시 만들지 않고 **가져다 쓰고, UX만 바꾼다**:

- **가져다 쓰는 것**: `searchOption` 값 `0, 2, 3, 10`(실측으로 고른 조합),
  좌표열 전체를 잇는 문자열을 키로 쓰는 중복 제거(`_geometryKey`), TMAP
  요청 4건을 동시에 보내는 방식.
- **바꾸는 것**: 그 브랜치는 후보를 **지도에 동시에** 그린다(파랑 1 +
  회색 2, 목록 없음). 이번 스펙은 브레인스토밍에서 확인한 방향대로
  **목록 시트에서 고르고, 고른 것만 그린다**(대중교통과 같은 패턴). 지도
  위 회색 대안선은 이 스펙에서 뺀다 — 목록과 회색선 두 가지 "대안 보여주기"
  방식을 동시에 유지할 이유가 없다.
- **버리는 것**: `_drivingRouteLimit = 3`(지도 위 선이 겹쳐 보이는 문제를
  막으려던 상한). 목록은 줄이 겹쳐 보이지 않으므로 이 상한이 필요 없다 —
  중복 제거 후 남는 만큼(최대 4개) 그대로 보여준다.
- **도보는 다중 옵션을 만들지 않는다.** 그 브랜치의 실측(1.2km 구간에서
  `searchOption 0·4·10`이 완전히 같은 선)과 판단("계단회피는 대안이 아니라
  조건이 다른 경로")을 그대로 따른다. 아래 범위 참고.

TMAP 무료 쿼터(경로안내 그룹 하루 1,000건, 자동차·보행자·타임머신이 공유)는
공식 요금 페이지로 2026-08-18에 직접 확인했다 — 낮아서 폐기한다는 근거는
없다. 낮은 쿼터(하루 10건)는 대중교통 API 얘기였고 그건 이미
2026-08-10에 카카오로 옮겨져 있다(관련 없음).

## 범위

### 포함

- 자동차: `searchOption 0, 2, 3, 10`으로 물어 좌표열 중복 제거한 후보를
  목록으로 보여준다. 라벨은 **의미가 확인된 것만 이름을 붙인다** — `0`은
  "추천"(교통최적+추천), `10`은 "최단거리". `2`·`3`은 TMAP 문서에서 정확한
  의미를 확인 못 했으므로(아래 "저장소 계층" 참고) "대안"으로 뭉뚱그려
  표기한다. 잘못된 이름("무료우선" 등)을 붙이는 것보다 정직하다.
- 좌표열이 같은 옵션은 한 줄로 합치고 라벨만 이어붙인다(예: "추천 · 대안").
- 목록 한 줄에 시간·거리, 있으면(자동차) 택시비·통행료도 함께.
- 고른 경로의 "상세보기" — 구간별 안내 문구 + 거리(텍스트만, 방향 아이콘 없음)를 정적 목록으로 보여준다. **자동차·도보 둘 다 적용**(도보는 다중 옵션 없이 지금의 단일 경로에 상세보기만 붙는다).

### 제외 (이번 스펙 밖)

- **도보 다중 옵션.** `feature-car-route-alternatives`의 실측(1.2km 구간에서 `searchOption 0·4·10`이 완전히 같은 선)을 근거로, 도보는 지금처럼 경로 1개만 받는다. 상세보기(턴바이턴)만 추가한다.
- **대중교통 상세보기.** 대중교통은 지금처럼 목록에서 고르면 바로 지도에 그려지는 흐름을 유지한다. (브레인스토밍에서 사용자가 "자동차·도보만"으로 확정.)
- **지도 위 회색 대안선.** 기존 브랜치의 "파랑 1 + 회색 2 동시 표시" 방식은 목록 UX로 대체한다(위 "기존 미병합 브랜치와의 관계" 참고).
- **자전거.** `route_plan_mode.dart`의 기존 결정("TMAP에 자전거 API 없음")을 유지한다. 이번 스펙에서 건드리지 않는다.
- **자동차 혼잡도 색상.** 사용자가 명시적으로 "경로만 적용, 혼잡 색상은 안 함"이라고 확정했다.
- **GPS 이동 중 재탐색 루프**(`outdoor_map/parts/route.dart`의 `_updateRoute`, `fromPositionStream: true` 호출) 및 **도보 중 실내 관련 갈래**(`WalkRouteKind.indoorToIndoor`/`outdoorToIndoor`/`indoorToOutdoor`/`indoorFallback`). 무변경.
- 턴바이턴 문구에 **도로명을 넣지 않는다**("마포대교 방면으로 우회전"이 아니라 "우회전"). 아래 "현재 상태" 항목 참고 — TMAP 응답에 그 텍스트가 없다는 것을 실제 픽스처로 확인했다. (방향 아이콘은 뺀 것이 아니라 넣는다 — 디자인 시스템에 이미 있는 `RoutexIcons.turnLeft/turnRight/straight`를 그대로 쓴다. 실내 안내(`eta_card.dart`의 `routeGuidanceIcon`)와 같은 아이콘이라 새로 만들 것이 없다.)

## 현재 상태 (탐색으로 확인한 사실)

- `DirectionsRoute`(`client/lib/models/route/directions_route.dart`)는 이미 `tollFareWon`/`taxiFareWon`을 갖고 있다. `fuelCostWon`은 없다.
- **main 브랜치**의 `TmapDirectionsRepository`는 자동차 요청에 `searchOption: '0'`을 고정해 보낸다(`_request` 메서드, `extra` 인자). 응답은 LineString 좌표만 모으고 Point 피처는 버린다. **`feature-car-route-alternatives` 브랜치**(main엔 없음, tip `6cdf884c`)는 이미 `getDrivingRoutes()`로 `searchOption 0,2,3,10`을 병렬 조회해 좌표열 중복 제거까지 구현해 뒀다 — 이 스펙은 그 구현을 가져오고 UX만 바꾼다(위 "기존 미병합 브랜치와의 관계" 참고).
- TMAP `searchOption` 값의 의미는 공식 문서에서 `0`(교통최적+추천)·`10`(최단거리)만 확인됐다. `2`·`3`은 그 브랜치의 실측 문서(`docs/client/car-route-alternatives.md`)에도 "표에서 갈라지는 조합"으로만 적혀 있고 의미가 적혀 있지 않다 — 구현 시 다시 문서를 확인해도 못 찾으면 "대안"으로 남긴다(추측으로 이름 붙이지 않는다).
- **TMAP 응답에는 안내 문구 텍스트가 없다.** `client/test/repositories/routing/tmap_directions_repository_test.dart`의 실제 캡처 픽스처(주석: "실제 TMAP 보행자 경로 API 응답을 그대로 캡처")를 보면 Point 피처의 `properties`에 `pointType`(`SP`=시작/`GP`=안내지점/`EP`=끝)만 있고 `description`/`turnType` 같은 문구 필드가 없다. 따라서 이번 스펙의 턴바이턴 문구는 **TMAP 텍스트를 파싱하는 것이 아니라, 인접 구간(LineString)의 방위각 변화를 우리가 직접 계산**해서 좌회전/우회전/직진으로 분류한다.
- `DirectionsRepository` 인터페이스(`directions_repository.dart`)는 `getWalkingRoute`/`getDrivingRoute` 두 메서드만 있다. 호출부는 세 갈래다:
  1. `map_shell_screen.dart:_startCarRoute`(약 1768행) — 사용자가 자동차 모드로 검색했을 때의 **유일한 진입점**. 이번 스펙이 바꾸는 지점.
  2. `map_shell_screen.dart:_withTransitWalkLegs`(약 1723행) — 대중교통 앞뒤 도보 구간을 채우는 내부 배관. 목록 개념이 필요 없다. **무변경.**
  3. `outdoor_map/parts/route.dart:_updateRoute`(약 261행) — 사용자가 목적지를 고른 뒤 최초 1회 + **GPS 위치가 갱신될 때마다(`fromPositionStream: true`)** 반복 호출되는 재탐색 루프. **무변경.**
- 도보 검색의 사용자 진입점은 `map_shell_screen.dart:_startWalkRoute`(약 2033행)이며, `classifyWalkRoute`(`walk_route_kind.dart`)가 갈래를 정한다. 순수 야외(`WalkRouteKind.outdoor`)만 `map?.showRouteTo(...)`를 부르고, 이 호출이 결국 위 3번 `_updateRoute`의 최초 1회 호출로 이어진다.
- 지도 경로선 스타일(`map/style/route_style.dart`, `screens/outdoor_map/layers/route_map_layers.dart`)은 이미 `style: 'drive'`(실선)/`'walk'`(점선) 속성으로 구분되어 있다. **변경 불필요** — 고른 후보의 `DirectionsRoute`를 기존 `showPlannedRoadRoute`/`showRouteTo`에 그대로 넘기면 된다.
- 대중교통은 `TransitRoutesSheet` + `TransitItineraryTile` + `TransitRoutes`/`TransitItinerary` 모델로 이미 "여러 후보 목록 → 고르기" 패턴이 구현되어 있다. 이번 자동차·도보 기능은 이 패턴을 그대로 따라간다(이름과 구조를 대응시킨다).

## 데이터 모델

파일: `client/lib/models/route/directions_route.dart`

```dart
/// 자동차·도보 경로의 안내 한 지점. 정적 미리보기용이다 — 실시간 안내
/// (domain/guidance/route_guidance.dart의 RouteStep)와는 다른 개념이라
/// 섞지 않는다.
///
/// [instruction]은 TMAP 응답 문구가 아니라 **좌표로 우리가 계산한 값**이다
/// (TMAP은 안내 문구 텍스트를 주지 않는다 — 위 "현재 상태" 참고). 도로명은
/// 없고 "우회전"/"좌회전"/"직진"만 나온다.
class DirectionsRouteStep {
  const DirectionsRouteStep({
    required this.instruction,
    required this.distanceMeters,
    required this.point,
  });

  final String instruction;
  final double distanceMeters;
  final LatLng point;
}

enum DirectionsTurn { straight, turnLeft, turnRight }

/// TMAP guide point(`pointType: "GP"`) 앞뒤 구간의 방위각 차이로 회전 방향을
/// 정한다. 임계각 미만이면 직진으로 본다(도로가 살짝 휘는 것까지 "회전"으로
/// 부르면 문구가 과민 반응한다). 정확한 임계값은 Task에서 실제 픽스처로
/// 튜닝한다 — 시작값은 20도.
DirectionsTurn classifyTurn({
  required double bearingBeforeDeg,
  required double bearingAfterDeg,
}) {
  var delta = bearingAfterDeg - bearingBeforeDeg;
  delta = ((delta + 180) % 360) - 180; // -180..180으로 정규화
  if (delta.abs() < 20) return DirectionsTurn.straight;
  return delta > 0 ? DirectionsTurn.turnRight : DirectionsTurn.turnLeft;
}

/// 자동차 옵션 종류. `feature-car-route-alternatives` 브랜치가 실측으로
/// 고른 TMAP `searchOption` 4개(`0,2,3,10`) 중 **의미가 확인된 둘만**
/// 이름이 있다. `2`·`3`은 [alternative]로 뭉뚱그린다 — 확인 못 한 의미를
/// 지어내 "무료우선"처럼 틀린 이름을 붙이는 것보다 낫다. 도보용 kind는
/// 없다(도보는 다중 옵션을 만들지 않는다 — 위 "제외" 참고).
enum DirectionsRouteOptionKind {
  /// TMAP `searchOption=0`. 교통최적+추천.
  recommended,

  /// TMAP `searchOption=10`. 최단거리.
  shortestDistance,

  /// TMAP `searchOption=2` 또는 `3`. 정확한 의미 미확인.
  alternative;

  String get label => switch (this) {
    DirectionsRouteOptionKind.recommended => '추천',
    DirectionsRouteOptionKind.shortestDistance => '최단거리',
    DirectionsRouteOptionKind.alternative => '대안',
  };
}

/// 경로 후보 한 줄. 좌표열이 같은 후보는 kinds를 합쳐 한 줄로 보여준다.
class DirectionsRouteOption {
  const DirectionsRouteOption({required this.kinds, required this.route});

  /// 항상 1개 이상. 정렬 순서 = 목록에 보일 순서(recommended가 먼저 오도록
  /// 병합 로직이 정렬한다).
  final List<DirectionsRouteOptionKind> kinds;
  final DirectionsRoute route;
}

/// `getDrivingRoute`(단일)가 이미 성공/null 둘로만 구분하듯, `_request()`는
/// 네트워크 실패든 "경로 없음"이든 구분 없이 null만 준다 — 그 이상을
/// 구분하는 상태값(예: `noRoute`/`unavailable`)은 지금 신호가 없어 만들어도
/// 항상 `failed`와 똑같이 처리된다.
enum DirectionsRouteOptionsStatus { ok, failed }

class DirectionsRouteOptions {
  const DirectionsRouteOptions({required this.status, this.options = const []});

  const DirectionsRouteOptions.ok(this.options)
    : status = DirectionsRouteOptionsStatus.ok;

  const DirectionsRouteOptions.failure()
    : status = DirectionsRouteOptionsStatus.failed,
      options = const [];

  final DirectionsRouteOptionsStatus status;
  final List<DirectionsRouteOption> options;

  bool get hasRoutes =>
      status == DirectionsRouteOptionsStatus.ok && options.isNotEmpty;
}
```

`DirectionsRoute`에 필드 1개 추가(기본값 있어 기존 생성 코드 안 깨짐):

```dart
final List<DirectionsRouteStep> steps; // 기본값 const []
```

**연료비(`fuelCostWon`)는 추가하지 않는다.** 실제 TMAP 자동차 응답 픽스처
(`tmap_directions_repository_test.dart`)에 `totalFare`(통행료)·`taxiFare`
(택시비)만 있고 연료비 필드가 없다 — 사용자 요청 자체가 "있으면 받아오고
없으면 거리·시간만"이었으므로, 없는 필드를 위한 자리를 미리 만들지 않는다.
나중에 실제로 필드가 확인되면 그때 `tollFareWon`과 같은 자리에 추가한다.

## 저장소 계층

파일: `client/lib/repositories/routing/directions_repository.dart`,
`tmap_directions_repository.dart`, `mock_directions_repository.dart`

인터페이스에 메서드 1개 추가(기존 `getWalkingRoute`/`getDrivingRoute`는
시그니처 그대로 유지 — 도보는 다중 옵션이 없으므로 대응 메서드도 없다):

```dart
abstract class DirectionsRepository {
  // ...기존 메서드 그대로...

  /// 자동차 경로 후보 여러 개. `feature-car-route-alternatives` 브랜치의
  /// `getDrivingRoutes()`를 그대로 가져와 반환 타입만 [DirectionsRouteOptions]
  /// (라벨 있는 목록 봉투)로 바꾼 것이다.
  Future<DirectionsRouteOptions> getDrivingRouteOptions({
    required LatLng origin,
    required LatLng destination,
  });
}
```

`TmapDirectionsRepository` 구현 방침:

- 기존 `_request()`를 재사용하되, **턴바이턴 스텝 계산을 추가**한다 —
  `pointType: "GP"`인 Point 피처마다, 그 앞 LineString 구간의 마지막
  방위각과 뒤 LineString 구간의 첫 방위각을 `classifyTurn()`에 넣어
  좌회전/우회전/직진을 정하고, 그 구간의 `distance`를 붙여
  `DirectionsRouteStep` 리스트를 만든다. `getWalkingRoute`/
  `getDrivingRoute`(기존 단일 메서드)도 이 계산을 함께 타지만, 호출부가
  `steps`를 안 쓰면 그냥 버려지므로 기존 동작에 영향 없다.
- `getDrivingRouteOptions`: `feature-car-route-alternatives`의
  `_drivingSearchOptions = ['0', '2', '3', '10']`과 `_geometryKey()`
  (좌표열 전체를 이어 붙인 문자열 키로 중복 판정)를 그대로 옮겨 온다.
  옵션값 → [DirectionsRouteOptionKind] 대응은 `'0'→recommended`,
  `'10'→shortestDistance`, `'2'/'3'→alternative`. **`_drivingRouteLimit`
  (상위 3개 제한)는 옮기지 않는다** — 그건 지도 위 회색선이 겹쳐 보이는
  문제를 막던 상한이고, 목록 UX엔 그 문제가 없다. 중복 제거 후 남는 만큼
  (최대 4개) 그대로 [DirectionsRouteOptions]에 담는다.
- 병합(중복 제거) 로직은 순수 함수로 분리(`tmap_directions_repository.dart`
  근처 또는 도메인 계층) — 입력 `List<(DirectionsRouteOptionKind,
  DirectionsRoute)>`, 출력 `List<DirectionsRouteOption>`(좌표열이 같으면
  kinds를 합치고, 순서는 `recommended > shortestDistance > alternative`).
- 4개 요청이 전부 null(실패)이면 `DirectionsRouteOptionsStatus.failed`,
  1개라도 성공하면 `ok`. TMAP 키 자체가 없는 경우는 이 계층에 안 온다 —
  대중교통과 달리 `service_locator.dart`가 키 없으면 통째로
  `MockDirectionsRepository`를 대신 꽂아 준다(기존 방식 그대로).

`MockDirectionsRepository`: `getDrivingRouteOptions`에 2~3개짜리 고정
옵션 목록을 반환하도록 확장(테스트·목업 화면용).

## 화면/위젯

**모달 시트를 새로 만들지 않는다.** 디자인시스템의 `RoutexEtaCard`에
이미 `routeOptions: Widget?` 슬롯("복수 경로를 고를 수 있을 때 도착 요약
위에 놓는 선택 영역")과 그 자리에 넣는 `RoutexRouteOption`(title/detail/
meta/selected/onPressed 한 줄) 위젯이 있는데, 지금 앱은 이 슬롯을 쓰지
않는다(`client/lib/widgets/eta_card.dart`의 `EtaCard`가 `RoutexEtaCard`를
감싸지만 `routeOptions`를 안 넘긴다). 자동차·도보 경로가 뜨는 자리가
정확히 이 `EtaCard`이므로(`outdoor_map/parts/ui.dart`의 `else if (route
!= null)` 분기, 약 439행), 후보 목록도 그 카드 안에 넣는다 — 새 모달을
띄우지 않고, 목록에서 고르는 순간 바로 그 자리에서 ETA가 바뀐다.

새 파일:

- `client/lib/widgets/directions_route_options_panel.dart` — `List<
  DirectionsRouteOption>`과 선택된 인덱스·콜백을 받아 `RoutexRouteOption`
  행을 세로로 쌓은 위젯. `title`엔 kinds 라벨(예: "추천 · 대안"), `detail`엔
  거리, `meta`엔 시간. 옵션이 1개뿐이면(도보, 또는 자동차인데 다 겹쳐서
  1개로 합쳐진 경우) 이 패널 자체를 그리지 않는다 — 고를 게 없는데 카드만
  하나 있으면 "이게 왜 있지" 하는 UI가 된다.
- `client/lib/screens/outdoor_map/widgets/directions_route_detail_sheet.dart` —
  상세보기. `DirectionsRouteStep` 리스트를 정적으로 나열(문구 + 거리 +
  `RoutexIcons.turnLeft/turnRight/straight`). `route_steps_sheet.dart`
  (실시간 안내 중 화면)와 **재사용하지 않고 분리** — 그 파일 자체가
  "출발 전 미리보기 vs 걷는 중 배너"를 의도적으로 나눈 선례를 따른다.

수정 파일:

- `client/lib/widgets/eta_card.dart`의 `EtaCard`: `routeOptions: Widget?`와
  `extraMetric: RoutexTripMetric?` 두 파라미터를 추가하고
  `!guidanceStarted` 분기에서 `RoutexEtaCard(routeOptions: routeOptions,
  metrics: [...기존 2개, if (extraMetric != null) extraMetric!], ...)`로
  넘긴다(`RoutexEtaCard`는 `metrics`를 최대 3개까지 받는다 — 기존 2개 +
  1개로 꽉 채운다). "상세보기"는 새 파라미터가 아니라 **`routeOptions`
  슬롯 안에 우리가 만든 위젯을 얹어** 넣는다(아래 참고). 실내 ETA 호출
  (`ui.dart` 403행)은 둘 다 안 넘겨 지금처럼 동작한다 — 기본값 `null`이라
  기존 호출부는 손대지 않아도 깨지지 않는다. `extraMetric`은 자동차
  경로의 `tollFareWon`(있으면, 0원은 "무료")·없으면 `taxiFareWon`으로
  채운다 — 디자인시스템 카드가 지표 3개까지만 받아 통행료·택시비를
  동시에 넣을 자리가 없다.
- `client/lib/screens/outdoor_map/parts/ui.dart`(439행 분기): `EtaCard`
  호출에 `routeOptions`(자동차일 때만, `DirectionsRouteOptionsPanel`)와
  `onShowDetail`(자동차·도보 둘 다, `DirectionsRouteDetailSheet.show(...)`
  여는 콜백)을 추가로 넘긴다.
- `client/lib/screens/map_shell/map_shell_screen.dart`의 `_startCarRoute`
  (약 1768행): `getDrivingRoute` 호출을 `getDrivingRouteOptions`로
  교체하고, 실패 상태 안내는 `_announceTransitFailure`와 같은 패턴(상태별
  메시지). 받은 옵션 목록과 "선택 바뀜" 콜백을 outdoor map 쪽으로 넘겨
  `showPlannedRoadRoute(...)`를 다시 부르게 한다(선택이 바뀌면 그 경로로
  다시 그린다). `_startWalkRoute`는 옵션 관련 변경 없음(도보는 옵션이
  없다 — 위 "제외" 참고), 상세보기 콜백만 함께 넘긴다.

## 지도 연동

변경 없음. `DirectionsRoute.points`를 기존 `showPlannedRoadRoute`/
`showRouteTo` 계열에 그대로 넘기면 `style: 'drive'|'walk'` 속성에 따라
실선/점선이 자동으로 그려진다(`route_map_layers.dart`).

## 에러 처리

- 옵션 요청 4개가 전부 실패 → `DirectionsRouteOptionsStatus.failed`,
  "자동차 경로를 불러오지 못했습니다. 잠시 후 다시 시도해주세요." 안내
  (지금 `_startCarRoute`가 `route == null`일 때 쓰는 문구 그대로).
- 일부 옵션만 실패 → 성공한 것만 병합해서 보여준다(전체 실패로 취급하지
  않는다).
- 옵션이 전부 좌표열까지 같아서 1개로 합쳐지는 경우 → 정상 상태. 패널
  자체를 안 그린다(위 "화면/위젯" 참고).

## 테스트 기준

- 병합 순수 함수: 좌표열이 같은 2개 입력 → kinds가 합쳐진 1개 출력.
  좌표열이 다른 입력 → 2개 그대로. `recommended`가 항상 첫 줄.
- `MockDirectionsRepository`의 다중 옵션 목업으로 `DirectionsRouteOptionsPanel`
  위젯 테스트(행 렌더링, 탭하면 선택 콜백 호출, 옵션 1개면 아무것도
  그리지 않음).
- `classifyTurn()`: 방위각 차이별 좌회전/우회전/직진 판정(경계값 포함).
- `TmapDirectionsRepository`의 스텝 계산: 고정된 샘플 JSON(Point +
  LineString 섞인 FeatureCollection, `tmap_directions_repository_test.dart`
  기존 픽스처 재사용)에서 `steps` 리스트가 순서대로 나오는지.
- `client/test/lib_layer_direction_test.dart`가 이번 변경으로도 계속
  통과하는지 확인(신규 파일들이 계층표를 지키는지: 모델 0, 저장소 2,
  위젯 3, 화면 4).

## 구현 시 결정 필요 (플랜 단계에서 확정)

- `searchOption 2`·`3`의 정확한 의미 — 못 찾으면 `alternative`(대안)로
  남긴다(이미 방침 결정, 위 "데이터 모델" 참고).
- 도보/자동차 공용 "계획 카드"(출발 전 요약 카드)의 정확한 위젯 파일 —
  플랜 작성 시 `guidance.dart`/`map_shell_screen.dart`를 읽어 확인한다.
