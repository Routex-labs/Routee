# 경로 후보 표시와 안내 화면 개편 설계

## 배경

직전 작업(`2026-08-19-transit-screen-redesign-design.md`)을 실기기에 올려 확인한 뒤 나온
여섯 건이다. 성격이 제각각이라 한 묶음으로 두지 않고 **네 단계로 가른다.** 가르는 기준은
파일 수가 아니라 **혼자서 폰에 올려 확인되는 크기**다 — 한 단계를 설치하면 그 단계가 맞는지
그 자리에서 판정할 수 있어야 한다.

| 단계 | 무엇 | 폰에서 무엇을 보면 맞는가 |
|---|---|---|
| 1 | 자동차 회색 대안선 | 자동차 경로에서 고르지 않은 후보가 회색으로 함께 보인다 |
| 2 | 목록의 빠진 앞뒤 도보 + 카드 모양 | 목록 첫 줄에 "정문까지 도보"가 있고, 카드가 참조 캡처와 같다 |
| 3 | 안내 중 뒤로가기 + 이동 수단 줄 | 안내 중 뒤로가기로 후보 목록에 돌아온다. 수단 줄이 안 물든다 |
| 4 | 안내 중 세로 타임라인 + 경로 상세 화면 | 세 수단이 같은 모양의 타임라인을 쓰고, 지금 구간이 표시된다 |

단계 사이의 의존은 **3단계 E → 디자인시스템 PR** 하나뿐이다. 나머지는 서로를 기다리지
않는다(같은 파일을 건드리는 지점은 아래 「병렬 실행 지점」에 표로 적었다).

## 없는 데이터 — 그리지 않는다

네 단계 전체에 걸리는 규칙이라 앞에 한 번만 적는다. 참조 캡처에는 있지만 우리 API
(카카오 길찾기 + TMAP 보행자/자동차)가 주지 않는 것들이다.

실시간 버스 도착("곧 도착", "7분"), 혼잡도("여유"·"보통"·"혼잡"), 기후동행 배지,
정류장 고유번호(20166), 같은 정류장의 다른 노선 목록, "버스 도착정보 더보기", 도착지 사진.

**자리도 남기지 않는다.** 회색 플레이스홀더로 두면 사용자는 그것을 "지원 안 함"이 아니라
"고장"으로 읽는다 — `models/route/route_plan_mode.dart`가 자전거 탭을 두지 않은 것과 같은
이유다. 이 목록은 **4단계에서 특히 아프다**(4단계 F 절 참고).

---

## 1단계 — 자동차 회색 대안선

고르지 않은 자동차 후보를 지도에 회색으로 함께 그린다. 목록에서 고르면 그것만 파랑,
나머지는 회색이다.

### 포함하지 않는 것과 이유

- **도보 대안선.** TMAP 보행자 `searchOption 0·4·10`이 1.2 km 구간에서 **완전히 같은 선**을
  준다는 실측이 이미 있다(`docs/superpowers/specs/2026-08-18-directions-route-options-design.md`
  55행, 근거는 `feature-car-route-alternatives` 브랜치의 `docs/client/car-route-alternatives.md`).
  후보가 하나뿐이라 회색선이 나올 자리가 없다. 옵션을 늘려 물으면 TMAP 할당량만 쓴다.
- **대중교통 회색선.** **이미 구현돼 있다.** `_transitAlternatives`
  (`screens/outdoor_map/outdoor_map_screen.dart:470`) → `showTransitRoute(..., alternatives:)`
  (`parts/route.dart:1041`) → `_syncTransitLayer`(`parts/route_layers.dart:85`) →
  `syncTransitLayer(..., alternatives:)`(`layers/transit_map_layers.dart:148`). 호출부는
  `screens/map_shell/map_shell_screen.dart:1652` 근처다. **1단계는 자동차만 만든다.**

### 실패 조건 먼저

1. **후보 목록과 그려진 선이 어긋난다.** `showPlannedRoadRouteOptions`가 목록을 세운 뒤,
   `_retargetJourneyEntrance`·`extendRouteToDestination`이 `_route`만 갈아 끼우는 길이 있다
   (`parts/route.dart:298`, `outdoor_map_screen.dart:1210`). 그러면 "고른 후보"의 좌표열과
   실제로 그려진 파란 선이 달라져, 회색 후보 하나가 파란 선과 거의 겹쳐 보인다.
   → **좌표 비교가 아니라 인덱스로만 제외한다.** 좌표로 거르면 몇 미터 어긋난 순간 제외가
   풀려 파란 선 밑에 자기 회색 선이 한 겹 더 깔린다(대중교통 쪽이 `identical`로 거르는 것과
   같은 판단, `map_shell_screen.dart:1668` 근처 주석).
2. **수단을 바꿨는데 회색이 남는다.** 걷기 안내로 들어가면 `_directionsRouteOptions`가
   비워지지만(`outdoor_map_screen.dart:1192`), 비우는 자리와 그리는 자리가 다르면 언젠가
   어긋난다. → 그리는 조건에 `_routeIsDriving && _route != null`을 **함께** 건다. 조건이
   그리는 쪽에 있으면 지우는 자리를 새로 만들 필요가 없다.
3. **좌표가 2개 미만인 후보.** 빈 LineString은 MapLibre에서 조용히 사라지거나 던진다.
   → feature 자체를 만들지 않는다.
4. **레이어 순서를 잘못 끼운다.** 실내 도면 MVT가 `belowLayerId: kOutdoorRouteCasingLayerId`로
   삽입된다(`layers/indoor_overlay_layers.dart:384` 외 9곳). 회색선을 casing **보다 먼저**
   등록하면 도면이 회색선 위에 와서 건물 안에서 후보가 사라진다. casing **보다 뒤, 본선보다
   앞**이어야 하고, `kOutdoorRouteCasingLayerId`는 계속 "경로 묶음의 맨 아래"로 남아야 한다.
5. **후보가 1개면 아무것도 안 그린다.** 후보 패널도 `length > 1`에서만 뜬다
   (`parts/ui.dart:545`). 화면과 지도가 같은 기준을 쓴다.

### 설계

**새 상태를 만들지 않는다.** 후보와 선택 인덱스가 이미 상태에 있다 —
`_directionsRouteOptions`·`_selectedDirectionsOptionIndex`(`outdoor_map_screen.dart:397~398`).
여기에 `_routeAlternatives`를 따로 두면 같은 사실이 두 벌이 되고, 반드시 한쪽이 먼저 낡는다.

세 갈래를 놓고 골랐다.

| 안 | 장점 | 단점 | 비용 |
|---|---|---|---|
| (가) 옛 커밋(`1968422e`)의 `_routeAlternatives` 상태를 그대로 되살린다 | 코드가 이미 있다 | 그때는 **"첫 번째가 항상 파랑"**이라 선택 개념이 없었다. 선택이 생긴 지금 상태가 두 벌이 된다 | 낮음, 위험 높음 |
| (나) 선택을 뺀 나머지를 **getter로** 뽑는다 | 새 상태 0. 선택이 바뀌면 `selectDirectionsOption`이 이미 `showPlannedRoadRoute`→`_syncRouteLayer`를 부르므로 레이어가 저절로 따라온다 | 매 sync마다 리스트를 한 번 만든다(후보 3~5개, 무시할 비용) | 낮음 |
| (다) 후보를 본선과 같은 소스에 넣고 속성으로 가른다 | 소스 하나 | 후보를 바꿀 때마다 색·굵기 표현식이 다시 계산돼 선 전체가 한 번 깜빡인다(`transit_map_layers.dart:16` 주석에 같은 사례) | 낮음, 화면 품질 나쁨 |

**(나)를 고른다.** (가)는 위험 대비 이득이 없고, (다)는 이미 대중교통에서 한 번 버린 길이다.
옛 커밋에서 가져올 가치가 있는 것은 **레이어 등록 블록**뿐이다(casing 위·본선 아래,
`kRouteCompletedColor`, width 3.5, opacity 0.75).

판정을 순수 함수로 내린다 — sync 함수는 `MapLibreMapController`를 붙잡고 있어 값 테스트를
못 한다. 뽑아 내리면 인덱스 경계를 값으로 지킬 수 있다.

```
// domain/route/directions_route_alternatives.dart (신규, 1층)
List<DirectionsRoute> unselectedDirectionsRoutes(
  List<DirectionsRouteOption> options,
  int selectedIndex,
)
```

`selectedIndex`가 범위 밖이어도 던지지 않는다 — 목록이 줄어든 직후 한 틱 동안 그 상태가
생긴다. 범위 밖이면 **전부** 후보로 본다(파란 선이 없는 상태이므로 겹칠 대상도 없다).

레이어 쪽은 `parts/route_layers.dart`의 `_syncRouteLayerNow` **첫 줄**에서
`_syncRouteAltLayer(controller)`를 부른다. 새 호출부를 만들지 않는 이유는 위 (나)와 같다 —
경로가 바뀌는 모든 길이 이미 `_syncRouteLayer`를 지난다.

### 파일

| 파일 | 책임 | 상태 |
|---|---|---|
| `client/lib/domain/route/directions_route_alternatives.dart` | 선택을 뺀 나머지 후보 | **신규** |
| `client/lib/screens/outdoor_map/layers/route_map_layers.dart` | `kOutdoorRouteAltSourceId` 소스·레이어 등록 | 수정 |
| `client/lib/screens/outdoor_map/parts/route_layers.dart` | `_syncRouteAltLayer` | 수정 |
| `client/lib/screens/outdoor_map/outdoor_map_screen.dart` | import 한 줄 | 수정 |

### 테스트 기준

테스트가 단일 출처다. 아래는 어느 파일이 무엇을 지키는지 가리키기만 한다.

| 무엇 | 테스트 |
|---|---|
| 선택 제외·인덱스 경계(음수·초과·빈 목록) | 새 `client/test/domain/route/directions_route_alternatives_test.dart` |
| 계층·주석 | `client/test/lib_layer_direction_test.dart`, `client/test/lib_header_comment_length_test.dart` |
| 회색이 실제로 깔리는지 | **자동 테스트로 못 잡는다.** 기기 캡처로 본다 |

---

## 2단계 — 빠진 앞뒤 도보(C) + 목록 카드 모양(D)

### C. 카카오가 안 주는 앞뒤 도보

카카오 대중교통 응답에는 **첫 승차 전·마지막 하차 후 도보가 없다**
(`models/route/transit_route.dart:288` 주석에 근거가 적혀 있다). 사용자가 "학마을한진아파트
정문까지 걸어가야 하는데 생략됐다"고 지적한 것이 이 증상이다.

채우는 함수(`domain/route/transit_walk_fill.dart`의 `fillTransitWalkLegs`)는 이미 있는데,
**경로를 고른 뒤에만** 돈다(`map_shell_screen.dart:1772` 근처의 `_withTransitWalkLegs`).
그래서 목록 단계에서는 비어 있다.

#### 실패 조건 먼저 — 여기서 제일 큰 것은 할당량이다

**TMAP 경로안내 그룹(자동차·보행자·타임머신)이 하루 1,000건을 공유한다.** 후보는 최대
15개까지 온다. 후보마다 앞뒤 두 번을 부르면 **검색 한 번에 30건**이다. 자동차 조회가 한 번에
4건(`searchOption 0,2,3,10`)이므로, 하루 30번쯤 길찾기를 하면 자동차까지 함께 죽는다.

완화 셋을 함께 건다.

1. **(출발점, 정류장) 쌍으로 메모이즈한다.** 후보들의 첫 승차 정류장은 서로 겹치는 경우가
   많다(같은 정류장에서 다른 노선을 타는 조합). 마지막 하차 정류장도 마찬가지다. 실호출 수는
   `서로 다른 승차 정류장 수 + 서로 다른 하차 정류장 수`로 줄어든다 — 실제로는 2~5건씩이다.
   좌표는 **소수 5자리(약 1 m)로 반올림해** 키를 만든다. 부동소수 끝자리가 달라 같은 정류장을
   두 번 부르는 일을 막는다.
2. **한 검색에서 부를 수 있는 실호출에 상한을 둔다**(기본 10). 넘는 것은 부르지 않고 직선으로
   떨어뜨린다 — `fillTransitWalkLegs`가 `head`/`tail`이 null이면 이미 그렇게 한다.
3. **부를 가치가 없으면 안 부른다.** 첫 구간이 이미 도보면(카카오가 환승 도보를 준 경우)
   `fillTransitWalkLegs`가 앞에 하나 더 붙이지 않으므로 호출 자체가 낭비다. 좌표가 빈 leg도
   같다. 두 조건은 지금 `_withTransitWalkLegs`에 이미 있다 — 목록 쪽도 같은 조건을 쓴다.

상한 10의 근거: 검색 한 번당 자동차 4 + 대중교통 10 = 최대 14건. 하루 1,000건이면 **70회
검색**까지 버틴다. 지금(고른 뒤 2건)은 검색당 6건이라 166회다. 데모 사용량에서는 둘 다
넉넉하고, 상한을 넘는 순간 목록이 죽는 것이 아니라 몇 줄의 도보가 직선이 될 뿐이다.

나머지 실패 조건:

4. **요청 하나가 실패해도 목록은 뜬다 — 가드를 새로 달 필요가 없다.**
   `TmapDirectionsRepository._request`가 `on Object { return null; }`로 네트워크 예외까지
   전부 잡아 null을 돌려준다. 그 자리 주석이 이유를 적어 뒀다 — "여기서 던지면 화면이
   통째로 죽으므로, 다른 실패와 같은 자리로 모아 호출부가 한 가지 안내만 하게 한다."
   그래서 `Future.wait`이 던질 일이 없고, null은 `fillTransitWalkLegs`가 직선으로 잇는다.
   후보 수를 늘려도 이 계약은 그대로다. **다만 목업 저장소는 다를 수 있으니** 테스트에서
   한 후보만 null이 되는 경우를 함께 덮는다.
5. **시트가 뜨는 시각이 늦어진다.** 지금은 조회 직후 바로 시트가 뜬다.
   - (가) 도보를 다 채우고 시트를 연다 — 왕복 한 번(약 0.3~0.8초)이 붙는다. **채택.**
   - (나) 시트를 먼저 열고 채워지면 갱신 — 지연은 0이지만, 사용자가 누르는 순간 목록이
     다시 그려져 카드 높이가 튄다. **엉뚱한 후보를 고르게 된다.**
   - (다) 지금처럼 고른 뒤에만 채운다 — 증상 그대로다.
   (가)를 고른 이유: 대중교통 조회 자체가 이미 1~2초짜리라, 그 뒤에 붙는 한 왕복은 사용자가
   "느려졌다"고 느끼는 문턱을 넘지 않는다. (나)의 오조작은 되돌리기가 훨씬 비싸다.
6. **총 소요는 바뀌지 않는다.** 카카오 `totalTime`에 이 도보가 **이미** 들어 있다(실측: steps
   합보다 786초 큼, 약 807 m). 우리가 더하면 이중 계산이다. 다만 **막대 비율은 조금 달라진다** —
   지금은 구간 합이 총계보다 작아 막대가 총계를 다 못 채우고, 채운 뒤에는 TMAP 도보 시간이
   카카오가 속에 넣어 둔 값과 달라 합이 총계를 넘을 수도 있다. `Expanded`의 flex가 정규화하므로
   레이아웃은 깨지지 않지만, 막대 칸의 비율과 총 소요가 완전히 일치하지는 않는다. 이 어긋남을
   없애려면 총 소요를 우리가 다시 계산해야 하는데 그것이 더 나쁘다(카카오 총계가 더 정확하다).
7. **고른 뒤 다시 부른다.** 선택 후 tail은 **문 좌표 기준으로 다시** 불러야 한다(`walkTarget`이
   하차 지점 기준으로 골라지므로 목록 단계의 tail과 끝점이 다르다). head는 (출발점, 정류장)이
   같아 **캐시 적중**이라 실호출이 1건 준다. 캐시를 조회 한 번의 수명으로 살려 둔다.

#### 설계

gap을 뽑는 일은 순수 계산이라 domain에 둔다. **파일을 새로 만들지 않고
`domain/route/transit_walk_fill.dart`에 더한다** — 고치는 이유가 같다("빠진 앞뒤 도보").

```
class TransitWalkGap { final LatLng from; final LatLng to; /* == / hashCode */ }

/// 목록 전체에서 채워야 할 도보 구간을 중복 없이 뽑는다. [maxGaps]를 넘으면
/// 앞에서부터 자른다 — 잘린 구간은 직선으로 떨어지고 목록은 그대로 뜬다.
List<TransitWalkGap> transitWalkGaps(
  List<TransitItinerary> itineraries, {
  required LatLng origin,
  required LatLng destination,
  int maxGaps = 10,
})
```

화면(`map_shell_screen.dart`)이 하는 일은 셋이다 — gap 목록을 받아 병렬 조회하고,
`Map<TransitWalkGap, DirectionsRoute?>`를 만들고, 후보마다 `fillTransitWalkLegs(head:, tail:)`로
채운다. `_withTransitWalkLegs`는 그 맵을 먼저 보고 없을 때만 부르도록 바꾼다.

#### 버린 안

**"카카오 총계에서 steps 합을 뺀 값(`missingWalk`)으로 도보 시간을 지어낸다."** 호출이 0건이라
할당량 걱정이 없고, 그 값은 이미 `TransitItinerary.fromKakaoJson`이 계산하고 있다. 버리는 이유는
둘이다 — 한 숫자를 앞뒤로 어떻게 나눌지 근거가 없고, **선이 없다.** 사용자가 지적한 것은 시간이
아니라 "정문까지 걸어가야 한다"는 사실 자체이므로 지도에 선이 나와야 한다. 사용자가 실호출
쪽을 확정했다.

### D. 목록 카드 모양

참조 캡처와 **완전히 같게** 맞춘다. 사용자 말: "우리 박스가 너무 많이 들어가있음".

| 어디 | 지금 | 바꾼 뒤 |
|---|---|---|
| `최적` | `RoutexBadge`(배지 박스) | 배지 없이 **파란 글자만** |
| 헤더 | `19분` + `오후 12:14 도착` + `1,500원` | `1시간 5분 │ 2,800원`. **도착 시각을 뺀다** |
| 막대 | 칸마다 배경색, 높이 20 | 연한 회색 **트랙 하나** 위에 탈것만 색 pill(아이콘+시간), 도보는 배경 없는 회색 글자. 높이 14~16 |
| 노선 줄 | `RoutexBadge` + 정류장명 + 노선번호 | 배지 없이 `아이콘 + 색 노선번호`(왼쪽) + `정류장명`(오른쪽) 한 줄 |
| 하차 | `○ 하차 <이름>` | **그대로** |
| 상세보기 | 카드 아래 `RoutexDisclosure` 줄 | **없앤다.** 카드를 누르면 상세 화면이 열린다(4단계 F) |

#### 실패 조건 먼저

1. **막대 안 글자가 통째로 사라진다 — 가장 큰 위험.** `RoutexTypography.caption`은
   `fontSize: 12, height: 1.5`라 **라인박스가 18 px**이다. 트랙 높이를 14로 낮추면 12 pt 글자가
   들어가지 못하고, `_FittedDuration`이 "안 들어가면 통째로 뺀다"로 짜여 있어 **숫자가 전부
   사라진다.** 완화 둘 중 하나를 기기에서 고른다 — `height: 1.0`으로 눌러 담거나(글리프 12 px가
   14 px 안에 상하 1 px씩 남기고 들어간다) 트랙을 16으로 올린다. 사용자가 말한 "14 근처"에 둘 다
   든다.
2. **`최적`의 파랑을 `colors.actionPrimary`로 쓰면 초록이 된다.** DS의 `actionPrimary`는
   `RoutexPalette.teal600`이다(`theme/routex_color_tokens.dart:46`) — 3단계 E에서 사용자가
   "초록색으로 색이 물드는건 별로네"라고 한 바로 그 색이다.
   → `map/style/route_style.dart`의 `kRouteLineColor`(`#4A87F1`)를 쓴다. 지도에 그려지는 본선과
   **같은 파랑**이라 "이 후보가 지도의 그 선"이 색으로 이어진다. `widgets`(3층)가 `map`(2층)을
   읽는 것은 계층 규칙에 맞는 방향이다.
3. **요금이 없으면 구분선까지 함께 뺀다.** 안 그러면 헤더가 `1시간 5분 │`로 끝난다. `fare`는
   짧은 버스 경로에서 실제로 null로 온다.
4. **탈것이 하나도 없는 경로(도보만).** 노선 줄·하차 줄을 그리지 않는다. 막대에는 회색 글자만
   남는다.
5. **`totalTimeSeconds == 0`.** 비율을 낼 수 없으므로 막대를 그리지 않는다(0으로 나누지 않는다).
   지금 코드에 이미 있는 가드다.
6. **정류장명이 길다.** 노선 줄이 `아이콘 + 노선번호`(왼쪽)와 `정류장명`(오른쪽) 한 줄이 되므로
   긴 이름이 노선번호를 밀어낸다. 정류장명 쪽에 `Expanded` + `TextOverflow.ellipsis`를 건다 —
   **노선번호를 자르면 안 된다**(잘린 번호는 다른 노선으로 읽힌다. 막대 글자를 자르지 않는 것과
   같은 이유가 `_LegBar` 주석에 적혀 있다).
#### 접기는 만들었다가 걷어냈다

한때 우측 상단에 접기 화살표를 두고 `Set<int> _collapsed`로 접힌 줄을 기억했다. **기기에서
보고 걷어냈다** — 접으면 정보가 줄어들 뿐이고, 사용자가 원한 것은 그 반대(눌러서 **더**
자세히)였기 때문이다.

지금은 **카드 한 장이 통째로 상세 화면을 여는 손잡이**다. 화살표를 따로 두면 같은 자리를 두
번 차지한다. 그래서 `expanded`/`onExpanded`도 없고, 카드는 늘 같은 모양 하나다.

#### 사라지는 것을 밝힌다

`상세보기` 줄이 없어지면서 **구간별 목록(`_StepRow`)이 카드에서 사라진다.** 참조 캡처에 그
자리가 없고 사용자가 없애는 쪽을 확정했다. 그 정보는 **4단계 F(경로 상세 화면)가 받는다** —
2단계와 4단계 사이에서는 구간별 시간을 목록에서 못 본다. 대신 카드를 눌러 지도에 그린 뒤
하단 요약 카드에서 본다. 이 공백을 알고 넘어가는 것이다.

### 파일 (2단계)

| 파일 | 책임 | 상태 |
|---|---|---|
| `client/lib/domain/route/transit_walk_fill.dart` | `TransitWalkGap`, `transitWalkGaps` 추가 | 수정 |
| `client/lib/screens/map_shell/map_shell_screen.dart` | 목록 단계 도보 채우기 + 캐시 | 수정 |
| `client/lib/widgets/transit_itinerary_card.dart` | 카드 모양(사실상 재작성) | 수정 |
| `client/lib/screens/map_shell/widgets/sheets/transit_routes_sheet.dart` | 카드 탭을 상세 화면으로 잇는다 | 수정 |

### 테스트 기준 (2단계)

| 무엇 | 테스트 |
|---|---|
| gap 중복 제거·상한·도보로 시작하는 경로 제외 | `client/test/domain/route/transit_walk_fill_test.dart` (추가) |
| 도보 조회가 실패해도 목록이 뜬다 / 실호출 수가 상한 이하 | `client/test/screens/map_shell/transit_walk_handoff_test.dart` (추가) |
| 요금 null·탈것 없음·0초·긴 정류장명 | `client/test/widgets/transit_itinerary_card_test.dart` (수정) |
| 카드에 접기 화살표가 없다(같은 자리를 두 번 차지하지 않는다) | `client/test/widgets/transit_itinerary_card_test.dart` |
| 막대 글자가 실제로 보이는지 | **자동 테스트로 못 잡는다.** 기기 캡처로 본다 |

---

## 3단계 — 안내 중 뒤로가기(A) + 이동 수단 줄(E)

### A. 안내 중 뒤로가기

지금 루트 `PopScope`는 두 겹이다(`map_shell_screen.dart:2263`).

| 지금 상태 | 지금 동작 |
|---|---|
| 검색 열림 | 검색만 닫는다 |
| 경로가 그려져 있음 | `_clearRouteDraft()` — 경로·핀·길찾기 상태를 **전부** 지운다 |
| 그 외 | 앱 종료 |

안내 중에도 두 번째 줄이 걸려서, 뒤로가기를 누르면 안내가 끝나면서 **후보 목록으로 못
돌아간다.** 한 겹을 더 넣는다.

| 상태 | 뒤로가기 |
|---|---|
| 검색 열림 | 검색만 닫는다 |
| **안내 중** | **안내만 끈다.** 경로·후보는 남는다 |
| 경로가 그려져 있음 | 경로를 지운다(지금 동작) |
| 그 외 | 앱 종료 |

#### "후보 목록으로 돌아간다"의 뜻이 수단마다 다르다 — 여기가 이 절의 핵심

- **자동차.** 안내를 끄면 계획 카드(`EtaCard`, `guidanceStarted: false`)가 돌아오고, 그 안에
  `DirectionsRouteOptionsPanel`이 이미 붙어 있다(`parts/ui.dart:545`). **추가 작업이 없다.**
- **도보.** 후보가 하나라 패널이 없다. 계획 카드로 돌아가는 것이 전부다.
- **대중교통.** 후보 목록은 modal sheet였고 고르는 순간 이미 pop됐다. 안내를 끄면
  `TransitSummaryCard`의 계획 상태(안내 시작 버튼)로 갈 뿐 **목록은 안 돌아온다.**

대중교통을 어떻게 할지 세 갈래.

| 안 | 장점 | 단점 | 비용 |
|---|---|---|---|
| (가) 안내만 끄고 계획 카드로 | 가장 작다. 새 상태 0 | 사용자 요구를 절반만 푼다 — "목록으로 돌아가고 싶다"인데 본 적 없는 중간 화면에 떨어진다 | 낮음 |
| (나) 안내를 끄고 **목록 시트를 다시 연다** | 사용자가 말한 그대로다. 대중교통에서 "안내 중"의 바로 이전 상태가 목록이다 | 뒤로가기 한 번이 두 겹을 움직인다. 마지막 조회 결과를 화면이 들고 있어야 한다 | 중간 |
| (다) 대중교통도 후보 패널을 하단 카드에 상시로 붙인다 | 세 수단이 같은 모양이 된다 | 하단 카드 구조를 크게 바꾼다. **4단계와 정면으로 겹친다** | 높음 |

**(나)로 만들었다가 기기에서 되돌렸다.** 목록 시트는 modal이라, 안내를 끄자마자 그 위에 덮으면
**수단 줄이 보이는데 눌리지 않는다**(barrier가 포인터를 먹는다. 테스트가 `RenderAbsorbPointer`로
잡았다). 사용자가 "안내 완전 종료가 아니라 다시 자동차·대중교통·걷기로 돌아올 것"이라고 한
것이 이 증상이다.

**지금은 뒤로가기가 계획 화면까지만 벗긴다.** 목록은 거기서 `대중교통` 칩을 다시 누르면
보관해 둔 결과로 열린다(재조회 없음). 앞선 요구(목록으로 복귀)와 이번 요구(수단 재선택)를
**한 번의 뒤로가기로는 둘 다 줄 수 없어서** 갈랐다 — 뒤로가기는 벗기기만 하고, 여는 것은
사용자의 탭이다.

세 수단이 같은 자리(계획 화면)에 떨어지는 것도 이 쪽이다. (나)는 대중교통만 다른 곳에
내려놓았다.

#### 실패 조건 먼저

1. **목적지가 바뀌었는데 옛 목록이 남는다.** 마지막 조회 결과를 화면이 들고 있으므로,
   `_clearRouteDraft`/`_forgetRouteDraft`에서 **함께 비운다.** 안 비우면 다른 곳으로 가는 안내
   중에 뒤로가기를 눌러 예전 목적지의 후보 목록이 뜬다.
2. **시트가 두 번 열린다.** 뒤로가기를 연타하거나 이미 시트가 떠 있는 상태에서 부르면 겹친다.
   → 시트 열기는 기존 `_runSheetChain`/`_withMapsLocked`를 그대로 탄다. `_transitRequest`와 같은
   중복 가드 패턴이 이미 있다.
3. **안내를 끄지 않고 시트만 열면 카메라가 사용자를 계속 쫓는다.** 시트에 가린 지도가 계속
   움직여 어느 후보가 어느 선인지 대조할 수 없다. → **안내를 먼저 끄고**(따라가기 해제) 연다.
4. **안내를 끄는 것이 "종료"로 새어 나간다.** `onGuidanceDismissed`는 상단 길찾기 상태까지
   비우는 신호다(`map_shell_screen.dart:2317`). 여기서는 경로가 남으므로 길찾기 바도 남아야
   한다. → **부르지 않는다.**
5. **완료(회색) 이력이 남는다.** 안내 중 걸어온 자취가 회색으로 남아 있는데 안내만 끄면,
   계획 화면에 절반이 회색인 경로가 뜬다. → 안내를 끌 때 `_clearCompletedRouteHistory()`를 함께
   부른다.
6. **안드로이드 예측 뒤로가기(predictive back).** `canPop`이 false인 동안에는 시스템 애니메이션이
   안 나온다. 지금도 그러므로 새로 생기는 문제는 아니다.

#### 설계

`OutdoorMapBodyState`에 **경로를 남기고 안내만 끄는** 전이를 하나 만든다.

```
// parts/guidance.dart
/// 안내만 끈다 — 경로선·후보·목적지는 남는다. 뒤로가기가 부른다.
/// `_dismissUserDestinationFromEtaCard`와 다르다: 그쪽은 경로까지 지우고
/// onGuidanceDismissed로 상단 길찾기 상태까지 비운다.
void stopGuidanceKeepingRoute()
```

하는 일 넷 — `_guidanceStarted = false`, `_stopFollowingUser()`,
`_clearCompletedRouteHistory()`, `_notifyRouteStateIfChanged()`. 카메라를 경로 전체로 되돌리는
것은 계획 화면의 약속이므로 함께 한다.

`map_shell`은 마지막 대중교통 조회를 들고 있는다(`TransitRoutes` + 목적지). 뒤로가기가
안내 중이면 `stopGuidanceKeepingRoute()`를 부르고, 들고 있는 조회가 있으면 그 시트를 다시
연다. 고른 뒤의 흐름은 기존 선택 경로를 그대로 재사용한다 — 두 벌로 만들지 않는다.

### E. 이동 수단 줄이 초록으로 물든다

사용자 말: "초록색으로 색이 물드는건 별로네". 선택 표시를 **"채운 초록 배경 + 흰 글자"**에서
**"아이콘과 글자만 색으로 강조"**로 바꾼다.

#### 확인해 보니 다른 점

브리핑은 `RoutexTravelModeBar`가 색을 하드코딩한다고 했다. 맞다 —
`patterns/routex_travel_mode_bar.dart`의 `_TravelModeItem`이
`fill = selected ? colors.actionPrimary : …`, `foreground = selected ? colors.contentInverse : …`로
박아 두었고, `actionPrimary`는 `RoutexPalette.teal600`이다.

**다만 이 앱은 그 위젯을 직접 쓰지 않는다.** `screens/map_shell/widgets/chrome/map_top_bar.dart:105`가
`RoutexRoutePlanner(travelModes: …)`에 넘기고, 그 패턴이 안에서
`RoutexTravelModeBar`를 만든다(`patterns/routex_route_planner.dart:110`). 따라서 **디자인시스템
PR은 두 곳을 뚫어야 한다** — `RoutexTravelModeBar`에 옵션을 더하고,
`RoutexRoutePlanner`가 그것을 통과시켜야 한다. 한쪽만 고치면 앱에서 여전히 못 바꾼다.

#### 설계 (디자인시스템 저장소, 별도 PR)

```
enum RoutexTravelModeEmphasis { filled, tinted }
RoutexTravelModeBar({ …, this.emphasis = RoutexTravelModeEmphasis.filled })
RoutexRoutePlanner({ …, this.travelModeEmphasis = RoutexTravelModeEmphasis.filled })
```

`tinted`일 때 `_TravelModeItem`은 `foreground = selected ? colors.actionPrimary : colors.contentSecondary`,
`fill`은 선택돼도 투명(누른 동안만 `actionPrimarySubtle`).

**기본값은 `filled`여야 한다** — 디자인시스템의 다른 소비자가 조용히 바뀌면 안 된다.

#### 실패 조건 먼저

1. **선택 표시가 색 하나에만 걸린다.** 채움을 없애면 색맹 사용자에게 구분이 사라진다.
   → 글자 무게를 함께 올린다(선택된 칸만 강조 굵기). `Semantics(selected:)`는 이미 붙어 있다.
   이것은 접근성 기본이라 "나중에"로 미루지 않는다.
2. **대비.** `actionPrimary`(teal600) 글자가 트랙 바탕(`surfaceCanvas`) 위에서 4.5:1을 넘는지
   디자인시스템 쪽에서 확인한다. 못 넘으면 `tinted`에서 트랙을 투명으로 두는 쪽을 함께 본다.
3. **버전 고정이 이번 브랜치 전체에 걸린다.** `client/pubspec.yaml`의 git `ref`는 지금
   `104f0fce…`에 고정돼 있다(앞선 PR "디자인시스템 의존성을 검증 커밋에 고정"의 결과다).
   ref를 올리면 **이 앱이 쓰는 모든 DS 위젯이 새 커밋을 쓴다.** → DS PR이 머지된 뒤에만 올리고,
   올린 커밋은 골든·위젯 테스트 전체를 다시 돌린 뒤에 남긴다.
4. **3단계 E는 외부 의존 때문에 막힐 수 있다.** 이 스펙 전체에서 **유일한 외부 의존**이다.
   막히면 3단계 A만 먼저 내고 E는 뒤로 미룬다 — 둘은 파일이 안 겹친다.

### 파일 (3단계)

| 파일 | 책임 | 상태 |
|---|---|---|
| `client/lib/screens/outdoor_map/parts/guidance.dart` | `stopGuidanceKeepingRoute` | 수정 |
| `client/lib/screens/map_shell/map_shell_screen.dart` | PopScope 한 겹 추가, 마지막 대중교통 조회 보관·비우기 | 수정 |
| `routex-design-system` 저장소 | `RoutexTravelModeEmphasis` (별도 PR) | **외부** |
| `client/pubspec.yaml` | DS `ref` 올림 | 수정 |
| `client/lib/screens/map_shell/widgets/chrome/map_top_bar.dart` | 새 인자 전달 | 수정 |

### 테스트 기준 (3단계)

| 무엇 | 테스트 |
|---|---|
| 안내 중 back이 안내만 끄고 경로는 남긴다 / 안내가 아니면 지금처럼 경로를 지운다 | `client/test/screens/map_shell/back_steps_out_of_route_test.dart` (추가) |
| 대중교통 안내 중 back이 목록 시트를 다시 연다 | 같은 파일 (추가) |
| 목적지를 지우면 보관한 조회도 비워진다 | 같은 파일 (추가) |
| 수단 줄이 선택 색으로 배경을 안 칠한다 | `client/test/screens/map_shell/widgets/chrome/map_top_bar_test.dart` (추가) |

---

## 4단계 — 안내 중 세로 타임라인(B) + 경로 상세 화면(F)

### 정직하게 — 참조 화면의 절반이 없는 데이터다

F(경로 상세)의 참조 캡처에서 칸을 세면 **절반 가까이**가 위 「없는 데이터」 목록에 걸린다.
정류장 고유번호, 실시간 도착 두 대, 혼잡도, 같은 정류장의 다른 노선, "도착정보 더보기",
도착지 사진. 이것들을 빼고 나면 남는 것은 아래뿐이다.

| 남는 것 | 출처 |
|---|---|
| 출발 → 승차 → (환승) → 하차 → 도착의 세로 흐름 | `TransitLeg` 순서 |
| 구간별 소요 시간 | `sectionTimeSeconds` |
| 노선 번호·수단 | `shortLabel`, `mode` |
| 승·하차 정류장 이름 | `startName`, `endName` |
| 정류장 수 | `stationCount` |
| 총 소요·요금·도착 시각 | `totalTimeSeconds`, `fare`, 지금 + 총 소요 |
| 자동차·도보의 턴바이턴 | `DirectionsRoute.steps` |

**그래서 4단계는 "참조 캡처를 재현하는 일"이 아니라 "세로 타임라인 하나로 세 수단을 통일하는
일"이다.** 이 점을 확정하지 않고 시작하면 구현자가 없는 칸을 채우려다 시간을 버린다.

### 새로 그리지 않는다 — `RoutexStepList`가 이미 세로 타임라인이다

디자인시스템의 `patterns/routex_step_list.dart`가 **정확히 이 모양**이다.

- 아이콘 열 + 단계 사이를 잇는 세로 연결선
- `currentIndex` — 지금 단계를 `actionPrimarySubtle` 배경과 강조색으로 표시
- 지나온 단계는 `contentDisabled`로 무게를 낮춤
- 행마다 `instruction` / `detail` / `distance`

앱은 이미 두 곳에서 쓰고 있다 —
`screens/outdoor_map/widgets/route_steps_sheet.dart`(실내 안내 단계),
`screens/outdoor_map/widgets/directions_route_detail_sheet.dart`(자동차·도보 턴바이턴).
**둘 다 `currentIndex`를 안 넘긴다**(항상 "아직 출발 전"). 4단계가 채우는 것이 바로 그 인자다.

한계 하나: `RoutexStep`은 **색을 안 받는다.** 대중교통 타임라인에서 노선색이 표현되지 않는다.
→ 「열린 결정」 1번.

### B. 안내 중 화면 — 지금 어느 구간인지

수단마다 판정 규칙이 다르다. 같은 함수(`computeGeoRouteProgress`)를 쓰지만 **입력이 다르다.**

**대중교통** — 구간마다 선이 따로 있고(환승역에서 끊긴다), 카카오의 구간 거리 합과 총 거리가
맞지 않는다. 그래서 구간마다 `computeGeoRouteProgress(routePoints: leg.points, position: gps)`를
돌려 **`offsetM`이 최소인 구간**을 현재로 잡는다. (사용자 확정안 그대로다.)

**자동차·도보** — 선이 하나이고 스텝은 그 선 위의 **점**이라 위 규칙을 쓸 수 없다(점 하나로는
투영할 선이 없다). 대신 경로 전체에 `computeGeoRouteProgress`를 **한 번** 돌려 `traveledM`을
얻고, 스텝의 누적 거리와 견준다. `DirectionsRouteStep.distanceMeters`는 **직전 구간의 길이**다
(`repositories/routing/tmap_directions_repository.dart:213` — `beforeLine`의 `distance`를 넣는다).
따라서 스텝 i까지의 누적 = `distanceMeters` 합이고, `traveledM`이 그 값을 넘은 마지막 스텝이
지나온 스텝이다. **여전히 GPS 판정이고 같은 함수다.**

`previousTraveledM`은 **넘기지 않는다.** 넘기면 검색 창(30 m)이 걸려, 지하철에서 GPS가 끊겼다가
다시 잡히는 순간 엉뚱한 구간에 붙는다.

#### 실패 조건 먼저

1. **경로가 자기 자신과 겹친다.** 왕복 버스, 환승역에서 되돌아 나오는 지하철.
   `offsetM`만으로는 앞뒤 구간을 못 가른다. → **동률(또는 오차 안)이면 앞선 구간을 고른다.**
   뒤를 고르면 목적지 근처 구간으로 튀어 "거의 다 왔다"고 거짓말한다. 되돌리기 어려운 오독이라
   여기만은 보수적으로 간다.
2. **GPS가 없다(지하철 안, 실내).** 모든 구간의 `offsetM`이 크다. → **마지막으로 잡은 값을
   유지한다.** 매 틱 새로 계산해 튀면 목록이 위아래로 뛴다. 위치를 아예 못 받으면
   `currentIndex: null`(= "아직 출발하지 않았다"라는 `RoutexStepList`의 계약과 같은 뜻).
3. **구간 좌표가 2개 미만.** `computeGeoRouteProgress`가 null을 준다. → 건너뛴다.
4. **비용.** 대중교통 경로는 좌표가 수천 개다. GPS 틱마다 전 구간을 훑으면 배터리와 프레임을
   먹는다. → 틱마다 돌리지 않고 **일정 간격(초 또는 이동 거리)으로** 다시 계산한다. 상수 자리가
   필요하고 값은 실측이 없다 — 「열린 결정」 4번.
5. **안내 중인데 타임라인이 지도를 다 덮는다.** 안내 중 화면의 본질은 지도다.
   → 「열린 결정」 2번.
6. **같은 사실을 두 벌로 말한다.** 상단 `GuidanceBanner`(다음 한 수)와 타임라인(전체 흐름)이
   함께 뜨면 사용자가 어느 쪽을 봐야 하는지 모른다. `route_steps_sheet.dart`의 파일 주석이
   이미 "걸으면서 보는 화면에서 목록은 지도를 덮는 짐"이라고 적어 두었다.
   → 「열린 결정」 3번.

판정을 순수 함수로 내린다.

```
// domain/guidance/route_leg_progress.dart (신규, 1층)
int? currentTransitLegIndex(List<List<LatLng>> legPoints, LatLng? position, {double maxOffsetM});
int? currentDirectionsStepIndex(List<LatLng> routePoints, List<double> stepDistancesM, LatLng? position);
```

### F. 경로 상세 화면

경로를 고른 뒤 안내 시작 **전에** 보는 화면이다. 세로 타임라인 + 하단에 소요·도착시각 +
`안내시작`.

**새 라우트를 쌓지 않고 시트로 둔다.** 직전 스펙이 같은 판단을 했고(라우트를 하나 더 쌓으면
뒤로가기 단계가 한 겹 늘어난다), **3단계 A가 뒤로가기를 또 고치는 PR이라** 여기서 뒤로가기
대상을 늘리는 것은 앞뒤가 맞지 않는다.

**새 파일을 만들지 않고 `directions_route_detail_sheet.dart`를 확장한다.** 그 파일이 이미
`RoutexStepList` + `RoutexBottomSheet` + 높이 상한을 하고 있다. 더할 것은 셋 —
대중교통 입력도 받고, 하단에 소요·도착·`안내시작`을 붙이고, 높이를 상세 화면답게 올린다.
이름이 실제와 어긋나게 되므로 파일을 옮긴다(`route_detail_sheet.dart`). **이름 변경은 별도
커밋이다**(`.github/CONTRIBUTING.md` 커밋 규칙).

### 파일 (4단계)

| 파일 | 책임 | 상태 |
|---|---|---|
| `client/lib/domain/guidance/route_leg_progress.dart` | 지금 구간·지금 스텝 판정(순수) | **신규** |
| `client/lib/widgets/route_timeline.dart` | 세 수단을 `RoutexStep` 목록으로 바꾸는 어댑터 | **신규** |
| `client/lib/screens/outdoor_map/widgets/directions_route_detail_sheet.dart` → `route_detail_sheet.dart` | 상세 화면(세 수단) + 하단 요약 + 안내시작 | 수정·이름 변경 |
| `client/lib/screens/outdoor_map/parts/ui.dart` | 안내 중 하단을 타임라인으로 | 수정 |
| `client/lib/screens/outdoor_map/widgets/transit_summary_card.dart` | 타임라인이 대체하면 **삭제 후보** | 검토 |
| `client/lib/widgets/eta_card.dart` | `RoutexTripProgress` 분기가 타임라인으로 옮겨가면 축소 | 수정 |

`transit_summary_card.dart`와 `eta_card.dart`의 안내 중 분기가 타임라인으로 대체되면
**같은 PR에서 지운다** — `AGENTS.md`의 "방치된 코드도 적어 두지 말고 그 PR에서 지운다".

### 테스트 기준 (4단계)

| 무엇 | 테스트 |
|---|---|
| 겹치는 경로에서 앞선 구간을 고른다 / 위치 없으면 null / 짧은 구간 건너뜀 | 새 `client/test/domain/guidance/route_leg_progress_test.dart` |
| 자동차 스텝 누적 거리 판정의 경계(첫 스텝·마지막 스텝·경로 밖) | 같은 파일 |
| 세 수단이 같은 위젯을 쓰고, 없는 데이터의 줄이 안 그려진다 | 새 `client/test/widgets/route_timeline_test.dart` |
| 상세 화면이 요금 null·탈것 없음에서 안 던진다 | 새 `client/test/screens/outdoor_map/route_detail_sheet_test.dart` |

---

## 계층 규칙

`import`는 아래로만 간다(`AGENTS.md`의 등급표). 이 스펙이 만드는 파일은 전부 그 방향이다.

| 새 파일 | 층 | 읽는 것 | 어긋남 |
|---|---|---|---|
| `domain/route/directions_route_alternatives.dart` | 1 | `models/route/`(0) | 없음 |
| `domain/route/transit_walk_fill.dart` (수정) | 1 | `models/route/`(0) | 없음 |
| `domain/guidance/route_leg_progress.dart` | 1 | `domain/guidance/`(1), `latlong2` | 같은 층은 허용 |
| `widgets/route_timeline.dart` | 3 | `models/`(0), `widgets/transit_style.dart`(3), DS | 없음 |
| `widgets/transit_itinerary_card.dart` (수정) | 3 | `map/style/route_style.dart`(2) **추가** | 3 → 2, 아래로 간다 |
| `screens/…` 전부 | 4 | 1~3층 | 없음 |

**주석의 대괄호 링크가 import를 끌고 온다.** 위층 파일을 가리킬 때는 경로를 글자로만 적는다 —
이 스펙에서 특히 위험한 곳은 `domain/guidance/route_leg_progress.dart`가 `parts/ui.dart`를
설명하고 싶어지는 자리다.

머리 주석 8줄·선언 주석 13줄 상한은 `client/test/lib_header_comment_length_test.dart`가 지킨다.
길어지면 지우지 말고 이 문서로 옮기고 경로 한 줄만 남긴다.

---

## 병렬 실행 지점

같은 파일을 건드리는 갈래는 **같은 물결에 두지 않는다.** 아래 표에서 파일이 겹치지 않는 것끼리는
동시에 진행해도 충돌하지 않는다.

### 1단계 — 두 갈래 동시

| 갈래 | 무엇 | 건드리는 파일 |
|---|---|---|
| 1A | 후보 고르기 순수 함수 | `domain/route/directions_route_alternatives.dart`(신규) + 새 테스트 |
| 1B | 레이어 등록 | `screens/outdoor_map/layers/route_map_layers.dart` |
| 1C | 조립 (**1A·1B 뒤**) | `screens/outdoor_map/parts/route_layers.dart`, `outdoor_map_screen.dart` |

### 2단계 — 두 줄이 끝까지 나란히 간다

| 갈래 | 무엇 | 건드리는 파일 |
|---|---|---|
| 2A | gap 뽑기 순수 함수 | `domain/route/transit_walk_fill.dart` + 테스트 |
| 2B | 카드 모양 | `widgets/transit_itinerary_card.dart` + 테스트 |
| 2C | 목록 단계 채우기 (**2A 뒤**) | `screens/map_shell/map_shell_screen.dart` + 테스트 |
| 2D | 시트가 카드 탭을 받는다 (**2B 뒤**) | `screens/map_shell/widgets/sheets/transit_routes_sheet.dart` + 테스트 |

2A와 2B는 파일이 하나도 안 겹친다. 2C와 2D도 서로 안 겹친다 — **2A→2C와 2B→2D 두 줄이
끝까지 나란히 간다.**

### 3단계 — 두 갈래 동시, 하나는 외부

| 갈래 | 무엇 | 건드리는 파일 |
|---|---|---|
| 3A | 뒤로가기 | `screens/outdoor_map/parts/guidance.dart`, `screens/map_shell/map_shell_screen.dart` + 테스트 |
| 3B | 디자인시스템 옵션 (**별도 저장소·별도 PR**) | `routex_travel_mode_bar.dart`, `routex_route_planner.dart` |
| 3C | 앱 반영 (**3B 머지 뒤**) | `client/pubspec.yaml`, `screens/map_shell/widgets/chrome/map_top_bar.dart` + 테스트 |

**3A는 2C와 같은 파일(`map_shell_screen.dart`)을 건드린다.** 단계가 순서대로 가면 문제가 없지만,
2단계를 안 끝내고 3단계를 당겨 시작하면 충돌한다.

### 4단계 — 두 갈래 동시, 둘은 조립

| 갈래 | 무엇 | 건드리는 파일 |
|---|---|---|
| 4A | 진행 판정 순수 함수 | `domain/guidance/route_leg_progress.dart`(신규) + 테스트 |
| 4B | 타임라인 어댑터 | `widgets/route_timeline.dart`(신규) + 테스트 |
| 4C | 상세 화면 (**4B 뒤**) | `screens/outdoor_map/widgets/route_detail_sheet.dart` |
| 4D | 안내 중 조립 (**4A·4B 뒤**) | `screens/outdoor_map/parts/ui.dart`, `widgets/eta_card.dart`, `transit_summary_card.dart`(삭제) |

### 직렬일 수밖에 없는 곳

**단계마다의 기기 검증.** `flutter analyze` → `flutter test` → 릴리스 APK →
Tailscale `adb install -r` → `adb screencap` → 기준 이미지 대조. 기기가 하나라 나눌 수 없다.
자동 테스트가 못 잡는 것 — 회색선이 파란 선을 지우지 않는지(1), 막대 안 숫자가 보이는지(2),
수단 줄의 선택이 색맹에게도 읽히는지(3), 타임라인의 현재 구간이 실제 위치와 맞는지(4) —
이 여기서만 보인다.

### 커밋 가름

갈래 하나가 커밋 하나에 대응한다. 성격이 다른 변경을 섞지 않는다 — 삭제
(`transit_summary_card.dart`, `transit_itinerary_card.dart`의 `_StepRow`)와 이름 변경
(`route_detail_sheet.dart`)은 코드 커밋과 분리한다.

---

## 열린 결정 — 4단계

없는 것을 있는 척 설계하는 것보다 낫다고 보아 남겨 둔다. **4단계에 들어가기 전에 사용자가
답해야 한다.**

1. **대중교통 타임라인에 노선색을 넣나.** `RoutexStep`은 색을 안 받는다.
   (가) 색 없이 DS 그대로 — 가장 작다. (나) DS에 `accent`를 뚫는다 — 3단계 E의 DS PR에 얹으면
   PR이 하나로 끝난다. (다) 앱에 새 타임라인 위젯 — DS와 두 벌이 된다.
   → **3단계 E의 PR을 내기 전에 정해야** (나)를 같이 넣을 수 있다.
2. **안내 중 타임라인이 하단 시트인가 전체 화면인가.** 안내 중 화면의 본질은 지도다. 지도를
   얼마나 가려도 되는지가 정해져야 높이·초기 크기를 정할 수 있다.
3. **타임라인이 뜨면 상단 `GuidanceBanner`를 남기나.** 둘 다 두면 같은 사실을 두 벌로 말한다.
   (가) 타임라인이 접혀 있을 때만 배너 (나) 배너를 없애고 타임라인 첫 줄이 그 몫 (다) 둘 다.
4. **현재 구간 재계산 주기.** 실측이 없다. 초 단위인가 이동 거리 단위인가, 값은 얼마인가.
   상수 한 곳에 두고 현장에서 조정하는 자리다.
5. **F의 `안내시작`을 누르면.** 시트를 닫고 지도로 가나, 시트가 그 자리에서 안내 중
   타임라인으로 바뀌나. 후자면 B와 F가 한 화면의 두 상태가 되어 코드가 줄지만, 지도가 계속
   가려진다.
6. **지하철 구간에서 GPS가 없을 때 무엇을 보여주나.** 마지막 값을 유지하나, "위치 확인 중"을
   말하나. 유지하면 조용히 틀린 구간을 가리키고, 말하면 매 지하 구간마다 문구가 뜬다.

## 남은 불확실성 — 1~3단계

- **막대 트랙 높이.** `caption`이 12/1.5(라인 18 px)라 14 px 트랙에 안 들어간다. `height: 1.0`으로
  누르거나 16으로 올린다. 기기에서 고른다(2단계 D 실패 조건 1).
- **`최적`의 파랑.** `kRouteLineColor`(`#4A87F1`)를 쓰기로 했지만, 카드 배경 위 대비를 기기에서
  확인한다. DS의 `actionPrimary`는 teal이라 쓸 수 없다.
- **도보 채우기 상한 10.** 실측이 아니라 할당량 나눗셈에서 나온 값이다(검색당 14건 → 하루 70회).
  실제 후보의 정류장 중복률이 높으면 상한에 닿을 일이 없고, 낮으면 낮춰야 한다. 첫 기기 확인에서
  실호출 수를 로그로 남겨 확인한다.
- **`RoutexRoutePlanner`가 옵션을 통과시켜야 한다.** 디자인시스템 PR이 `RoutexTravelModeBar`만
  고치면 앱에서 여전히 못 바꾼다(3단계 E).
