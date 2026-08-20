# 대중교통 결과 화면 개편 + 길찾기 잔손질 설계

## 배경

`worktree-directions-route-options` 브랜치를 실기기에 올려 확인한 뒤 나온 다섯 건이다.
넷은 잔손질이고 하나(대중교통 결과 화면)는 화면을 갈아엎는다. 한 묶음으로 두는 이유는
**같은 세션의 같은 화면 확인에서 나왔고, 검증도 한 번의 설치로 함께 하기 때문**이다.

개편의 기준 이미지는 네이버지도 대중교통 결과 카드다. 사용자가 "정확히 이런 모양"이라고
지목했으나, 지금 앱 구조를 강제로 맞출 필요는 없다고 함께 밝혔다 — **레이아웃을 목표로
삼되 데이터가 없는 칸은 채우지 않는다.**

## 범위

### 포함

1. 자동차 경로 후보 라벨에서 중복 제거 — "추천 · 대안 · 대안" → "추천"
2. 계획 카드(`RoutexEtaCard`)의 headline을 도착 시각 → 소요 시간으로 교체
3. 안내 시작 시 GPS가 경로에서 멀면 카메라를 옮기지 않고 토스트로 알린다
4. 대중교통 경로를 고른 상태에서 뒤로가기를 눌러도 앱이 종료되지 않는다
5. 대중교통 결과 카드 재설계 + 수단 필터 탭

### 제외

- **실시간 버스 도착 정보, 혼잡도, 기후동행 배지.** 카카오 길찾기 응답에 없다. 채우려면
  서울시 버스도착정보 API를 새로 붙여야 하고, 정류장 ID 매칭·키 발급·백엔드 프록시가
  따라온다. 사용자가 "있는 것만 그린다"로 확정했다.
- **자전거 탭.** `models/route/route_plan_mode.dart`에 이미 적힌 결정을 유지한다 — TMAP·카카오
  모두 자전거 경로 API가 없어서 탭을 만들면 눌러도 아무 일이 없는 죽은 버튼이 된다.
- **출발 시각 설정.** 카카오 길찾기가 시각 인자를 받지 않는다. UI만 만들면 값이 결과에
  반영되지 않아 거짓말이 된다.
- **정렬 메뉴(최적 경로순 등).** 지금은 응답 순서를 그대로 쓴다. 필터가 먼저 들어가 보고
  필요하면 다음 단계에서 본다.
- **대중교통 별도 상세보기 라우트.** 카드 안에서 펼친다 — 아래 5절 참고.

## 항목별 설계

### 1. 자동차 후보 라벨 중복

**원인은 화면이 아니라 데이터다.** TMAP `searchOption` 2와 3이 둘 다
`DirectionsRouteOptionKind.alternative`로 매핑된다(둘의 정확한 의미를 확인하지 못해
뭉뚱그린 결정이고, 그 근거는 `models/route/directions_route.dart`의 enum 주석에 있다).
그 상태로 `mergeDirectionsRouteOptions`가 좌표열이 같은 후보를 합칠 때 kinds를 검사 없이
이어붙여 `[recommended, alternative, alternative]`가 만들어진다.

두 곳을 고친다.

- `domain/route/directions_route_merge.dart` — 이미 들어 있는 kind는 다시 넣지 않는다.
  같은 kind가 두 번 들어오는 것은 목록의 사실이 아니라 요청 방식의 부산물이다.
- `widgets/directions_route_options_panel.dart` — `kinds.map(...).join(' · ')` 대신
  `kinds.first.label`. 병합 순서가 추천 > 최단거리 > 대안이므로 `first`가 곧 "제일 앞"이다.

추천이 없는 줄은 "최단거리"로, 그것도 없으면 "대안"으로 나온다. 라벨이 사라지는 경우는
없다(`kinds`는 항상 1개 이상이라는 것이 `DirectionsRouteOption`의 계약이다).

**버리는 정보를 밝힌다.** `[recommended, shortestDistance]`로 합쳐진 줄은 "추천"만 보이고
"이 경로가 최단거리이기도 하다"는 사실이 화면에서 사라진다. 사용자가 그것을 받아들였다 —
라벨이 길게 늘어지는 쪽이 더 나쁘다고 봤다.

### 2. 도착 시각의 자리

도착 시각은 두 곳에 나온다.

| 어디 | 무엇 | 이번 변경 |
|---|---|---|
| `RoutexEtaCard` (안내 시작 전 계획 카드) | headline — 제일 큰 글자 | **소요 시간으로 교체** |
| `RoutexTripProgress` (안내 중 진행 바) | 지표 3개 중 하나 | 그대로 |

`RoutexEtaCard.arrivalTime`은 **required이자 headline**이다. 빈 문자열을 넘기면 "도착 예정"
제목 아래 큰 글자 자리가 비어 카드에 구멍이 난다. 그래서 지우는 대신 그 자리에 소요
시간을 올린다.

```
RoutexEtaCard(
  title: label,               // '목적지까지' — 이미 이렇게 쓰고 있다. 그대로 둔다
  arrivalTime: '$minutes분',  // DS 파라미터 이름은 그대로, 내용만 바뀐다
  metrics: [거리, ?extraMetric],
)
```

**`title`은 건드리지 않는다.** 디자인시스템의 기본값은 `'도착 예정'`이지만 이 앱은 이미
`title: label`로 덮어써서 `'목적지까지'`·`'건물 입구까지'`를 넣고 있다. 여기에 `'소요'`를
넣으면 어디로 가는 경로인지가 화면에서 사라진다. 바뀌는 것은 headline 한 줄뿐이다.

**디자인시스템의 의도와 어긋나는 변경이다.** `routex_eta_card.dart` 주석은 도착 시각을
headline에 둔 이유를 적어 뒀다 — "소요 시간은 언제 나가야 하는지를 스스로 계산하게 만들지만
도착 시각은 약속과 바로 견줄 수 있다." 사용자가 그 트레이드오프를 알고 계획 카드에서 빼는
쪽을 골랐다. 공급 저장소를 고치지 않고 소비 앱에서 파라미터만 다르게 채우는 방식이라,
디자인시스템 업데이트와 충돌하지 않는다.

`metrics`가 3개에서 2개로 줄어드는 것이 아니다 — 소요가 headline으로 올라가면서 metrics는
거리 + `extraMetric`(통행료 또는 택시비) 둘이 된다. `RoutexEtaCard`의
`assert(metrics.length > 0 && metrics.length <= 3)`은 계속 만족한다. `extraMetric`이 null인
도보 경로에서는 metrics가 거리 하나만 남는데, 이것도 assert를 통과한다.

### 3. 안내 시작 GPS 가드

`screens/outdoor_map/parts/guidance.dart`의 `_startCurrentGuidance`가 지금 조건 없이
`startFollowingCurrentLocation()`을 불러 카메라를 실제 GPS로 끌고 간다. 경로가 다른 동네에
그려져 있어도 그렇게 한다 — 책상에서 확인할 때 화면이 통째로 날아가는 원인이다.

**실내 안내는 이미 같은 가드를 갖고 있다**(같은 파일 `_startIndoorGuidance`,
`'건물에 도착하면 안내를 시작할 수 있습니다'`). 야외에만 없다. 새 패턴을 만들지 않고 그
모양을 그대로 따른다.

거리는 새로 재지 않는다. `domain/guidance/geo_route_progress.dart`의
`computeGeoRouteProgress`에 `previousTraveledM`을 넘기지 않으면 검색 창(window) 제한 없이
경로 전체에서 가장 가까운 점을 찾아 `offsetM`을 준다. 경로 위 어디에 서 있든 통과하고,
완전히 다른 곳이면 걸린다.

```
final progress = computeGeoRouteProgress(routePoints: …, position: 지금 GPS);
if (progress == null || progress.offsetM > guidanceStartMaxOffsetM) {
  _showSnack('경로 근처에 있을 때 안내를 시작할 수 있습니다.');
  return;   // setState 없음 — 보던 경로와 카메라가 그대로 남는다
}
```

**`RoutexToast`가 아니라 `_showSnack`이다.** 야외 지도 화면은 `screens/outdoor_map/parts/ui.dart`의
`_showSnack`(SnackBar 기반)을 쓴다 — `RoutexToast`는 `map_shell`·장소 상세 쪽 표면이다. 실내
가드도 같은 `_showSnack`을 쓰므로 표면이 갈리지 않는다.

이 선택에는 덤이 하나 있다. `_showSnackGuarded`가 **같은 문구가 이미 떠 있으면 다시 띄우지
않는다.** 안내 시작 버튼을 연타해도 안내가 매번 처음부터 다시 시작돼 영영 안 사라지는 일이
없다 — 그 파일 주석에 적힌, GPS 틱이 같은 안내를 반복 호출해서 생겼던 문제와 같은 사례다.

**임계값 `guidanceStartMaxOffsetM = 150.0`은 실측이 아니라 가정이다.**
`screens/outdoor_map/outdoor_map_tuning.dart`에 상수로 두고 근거를 함께 적는다 — 도심 GPS
오차(같은 파일의 `lowAccuracyThresholdMeters` 30 m)와 이면도로 한 블록을 덮되, 다른 동네에서
누르면 확실히 걸리는 값이다. 현장에서 조정할 자리다.

기존 `outdoorRouteMaxProjectionOffsetM`(25 m)을 재사용하지 않는 이유: 그 값은 "걸어온 자취를
계획 경로 위에 그려도 되는가"를 판정하는 값이라 훨씬 엄격하다. 그 기준으로 안내 시작을
막으면 정상적으로 출발선에 선 사용자도 GPS가 한 번 튀는 순간 시작하지 못한다.

**위치를 못 받는 경우**(`progress == null`, 좌표가 2개 미만이거나 GPS 없음)도 막는 쪽으로
둔다. 위치를 모르는 채 카메라만 옮기면 사용자는 자기가 어디 있는지 모르는 화면을 보게 된다.

`_routeIsDriving`이 아닌 경로(도보)는 지금도 `startFollowingCurrentLocation()`을 부르지
않는다. 가드는 **부르기 직전이 아니라 `_startCurrentGuidance` 진입부**에 둔다 — 도보도
안내 상태로 넘어가면 진행 판정이 돌기 시작하므로, 엉뚱한 위치에서 시작하는 것은 도보도
같은 문제다.

### 4. 뒤로가기

`screens/map_shell/map_shell_screen.dart`의 루트 `PopScope`가 `canPop: !_searchActive`
하나뿐이다. 대중교통 경로를 고르면 시트가 닫히고 지도에 요약 카드만 남는데, 이때
`_searchActive`는 false라 뒤로가기가 루트 라우트를 pop해 **앱이 종료된다.**

상태를 안쪽부터 한 겹씩 벗긴다.

| 지금 상태 | 뒤로가기 |
|---|---|
| 검색 열림 | 검색만 닫는다 (지금 동작) |
| 경로가 그려져 있음 | 경로를 지우고 목록/계획 상태로 되돌린다 |
| 그 외 | 앱 종료 (기본 동작) |

`canPop`은 위 둘 중 아무것도 아닐 때만 true다. 경로가 그려져 있는지는 이미 `build`가 읽는
`_outdoorRouteVisible`로 판정한다 — 새 상태 플래그를 만들지 않는다.

**안내 중(`guidanceStarted`)에도 같은 규칙이다.** 안내를 뒤로가기로 끄는 것은 "경로를
지운다"와 같은 전이이고, 이미 `_dismissIndoorRouteFromEtaCard`/`onClose` 경로가 그 정리를
한다. 뒤로가기가 그 경로를 부르게 한다 — 종료 동작을 두 벌로 만들지 않는다.

### 5. 대중교통 결과 화면

#### 무엇이 채워지고 무엇이 비는가

| 이미지의 칸 | 데이터 | 출처 |
|---|---|---|
| `최적` 배지 | 목록 첫 줄 | 기존 `fastest` 플래그 |
| `19분` | `totalTimeSeconds` | ✓ |
| `오후 12:14 도착` | 지금 + `totalTimeSeconds` | ✓ (계산) |
| `1,500원` | `fare` | ✓ (null 가능 — 짧은 버스 경로에서 실제로 빠져 온다) |
| 구간 비율 막대 `1분 / 11분 / 4분` | `legs[].sectionTimeSeconds` 비율 + `transitModeColor` | ✓ |
| `지선` / `간선` 배지 | `routeName`의 `간선:472` 접두사 | ✓ (TMAP). 카카오는 접두사가 없어 수단 이름으로 떨어진다 |
| 승차 정류장 `삼부아파트` | 첫 탈것 leg의 `startName` | ✓ |
| 노선 번호 `7613` | `leg.shortLabel` | ✓ |
| `2정류장` | `leg.stationCount` | ✓ (도보는 0으로 못박혀 있다) |
| 하차 `공덕역2번출구` | 마지막 탈것 leg의 `endName` | ✓ |
| ~~`7분` / `26분` 실시간 도착~~ | — | ✗ 그리지 않는다 |
| ~~`여유` 혼잡도~~ | — | ✗ |
| ~~`기후동행` 배지~~ | — | ✗ |
| ~~`도착정보` 버튼~~ | — | ✗ |

없는 칸은 **자리도 남기지 않는다.** 회색 플레이스홀더로 두면 사용자는 그것을 "지원 안 함"이
아니라 "고장"으로 읽는다 — `route_plan_mode.dart`가 자전거 탭을 두지 않은 것과 같은 이유다.

#### 파일

- **`widgets/transit_itinerary_card.dart` (새)** — 카드 한 장. 구간 비율 막대는 이 파일 안의
  private 위젯으로 둔다. 디자인시스템에 비율 막대가 없어 새로 그리되, 색·간격·타이포는 전부
  DS 토큰(`context.routexColors`, `RoutexSpacing`, `RoutexTypography`)과
  `widgets/transit_style.dart`의 `transitModeColor`를 쓴다.
- **`domain/route/transit_itinerary_filter.dart` (새)** — 필터 분류와 집계. 순수 함수라 위젯
  없이 테스트한다. 새 API를 부르지 않는다.
- **`screens/map_shell/widgets/sheets/transit_routes_sheet.dart` (수정)** — 상단에
  `RoutexTabs`, 아래는 필터가 걸린 목록.
- **`widgets/transit_itinerary_tile.dart` (삭제)** — 쓰는 곳이 위 시트 하나뿐이다. 파일 주석은
  "길찾기 화면의 전체 목록과 예전 바텀시트가 같은 줄을 써야 한다"고 적었지만 **낡았다** —
  두 번째 사용처는 이미 없다. 갈아끼운 뒤 남겨 두지 않는다.

`RoutexTransitItinerary`(디자인시스템 패턴)를 쓰지 않는 이유: 그 패턴은 소요 + 사실 목록 +
배지 스트립 구조라 비율 막대와 승·하차 블록을 표현할 자리가 없다. 공급 저장소를 고치는 것은
이번 범위 밖이라 앱 쪽에 새로 그린다.

#### 필터 탭

`전체 / 버스 n / 지하철 n / 버스+지하철 n`. 받은 경로만으로 계산하므로 새 요청이 없다.

분류는 각 itinerary의 **도보를 뺀 mode 집합**으로 한다.

| mode 집합 | 분류 |
|---|---|
| `{bus}` | 버스 |
| `{subway}` | 지하철 |
| `{bus, subway}` | 버스+지하철 |
| 그 외 (기차·고속버스·`unknown` 포함) | 전체에만 |

탭 라벨의 숫자는 그 분류에 속한 경로 수다. **0건인 탭은 그리지 않는다** — 눌러도 빈 목록만
나오는 탭은 고장으로 읽힌다. `전체`는 항상 있다.

필터를 바꿔도 지도에 그려진 경로는 건드리지 않는다. 필터는 목록을 좁히는 것이지 선택을
바꾸는 것이 아니다. 지금 선택된 경로가 필터에서 빠지면 목록에서 사라지지만 지도에는
남는다 — 필터를 `전체`로 되돌리면 다시 보인다.

#### 상세보기

카드 안에서 펼친다(`RoutexDisclosure`). 별도 라우트를 만들지 않는 이유가 둘이다.

- 구간별 데이터(`legs`의 시간·정류장 수·시작/끝 이름)가 이미 카드에 다 들어와 있다. 화면만
  얹으면 되고 새 조회가 없다.
- 라우트를 하나 더 쌓으면 4번의 뒤로가기 단계가 한 겹 늘어난다. 같은 PR에서 뒤로가기를
  고치면서 뒤로가기 대상을 늘리는 것은 앞뒤가 맞지 않는다.

`RoutexDisclosure`는 `expanded`와 `onExpanded`를 받는 **제어형**이라 펼침 상태를 누군가
들고 있어야 한다. **시트가 "지금 펼쳐진 줄"을 하나 들고**, 카드는 계속 stateless로 둔다 —
카드마다 상태를 두면 여러 줄이 동시에 펼쳐져 목록이 화면 밖으로 밀린다.

## 에러 처리

- `fare == null` — 요금 칸을 그리지 않는다. 0원으로 찍지 않는다(무료와 미상은 다르다).
- 탈것 leg가 하나도 없는 경로(도보만) — 승·하차 블록을 그리지 않고 막대와 소요만 남긴다.
- `startName`/`endName`이 null — 그 줄만 뺀다. 카드 전체를 버리지 않는다.
- `totalTimeSeconds == 0` — 비율 막대를 그릴 수 없다. 막대를 빼고 나머지를 그린다
  (0으로 나누지 않는다).
- 3번 안내는 `_showSnack`이다. 근거는 위 3절.

## 테스트 기준

테스트가 단일 출처다. 아래는 어느 파일이 무엇을 지키는지 가리키기만 한다.

| 항목 | 테스트 |
|---|---|
| 1 | `test/domain/route/directions_route_merge_test.dart` — 같은 kind가 두 번 들어와도 kinds에 한 번만 남는다 |
| 1 | `test/widgets/directions_route_options_panel_test.dart` — kinds가 여럿이어도 라벨은 맨 앞 하나 |
| 2 | `test/widgets/eta_card_test.dart` — 계획 카드에 시각 표기가 없고 소요가 headline, 진행 바에는 시각이 남는다 |
| 3 | 새 `test/screens/outdoor_map/guidance_start_gps_guard_test.dart` — 멀면 상태 불변 + 토스트, 가까우면 시작 |
| 4 | `test/screens/map_shell/route_mode_test.dart` — 경로가 그려진 상태에서 back이 pop하지 않고 경로만 지운다 |
| 5 | 새 `test/domain/route/transit_itinerary_filter_test.dart` — 분류 경계(도보만·환승·`unknown` 포함) |
| 5 | 새 `test/widgets/transit_itinerary_card_test.dart` — 없는 데이터의 칸이 그려지지 않는다, 0초에 나눗셈이 없다 |
| 계층 | `test/lib_layer_direction_test.dart` — 새 파일이 등급표를 지킨다 (domain 1, widgets 3) |
| 주석 | `test/lib_header_comment_length_test.dart` — 새 파일의 머리 주석 8줄 이하 |

**기기 검증.** 위 테스트가 다 통과한 뒤 릴리스 APK를 만들어 Tailscale로 설치하고
`adb screencap`으로 캡처를 저장해 기준 이미지와 나란히 놓고 본다. 자동 테스트가 잡지 못하는
것 — 막대 비율이 눈에 맞는지, 배지 색이 노선과 어긋나지 않는지, 카드가 한 화면에 들어오는지 —
이 여기서만 보인다.

## 병렬 실행 지점

파일이 겹치지 않는 단위로 갈라 두었다. **Wave A의 여섯 갈래는 서로 어떤 파일도 공유하지
않는다** — 동시에 진행해도 충돌하지 않는다.

### Wave A — 여섯 갈래 동시

| 갈래 | 항목 | 건드리는 파일 |
|---|---|---|
| A1 | 자동차 라벨 | `domain/route/directions_route_merge.dart`, `widgets/directions_route_options_panel.dart` + 두 테스트 |
| A2 | 도착 시각 | `widgets/eta_card.dart` + `test/widgets/eta_card_test.dart` |
| A3 | GPS 가드 | `screens/outdoor_map/outdoor_map_tuning.dart`, `screens/outdoor_map/parts/guidance.dart` + 새 테스트 |
| A4 | 뒤로가기 | `screens/map_shell/map_shell_screen.dart` + `test/screens/map_shell/route_mode_test.dart` |
| A5a | 필터 순수 함수 | `domain/route/transit_itinerary_filter.dart` (새) + 새 테스트 |
| A5b | 카드 위젯 | `widgets/transit_itinerary_card.dart` (새) + 새 테스트 |

A5a와 A5b를 가른 이유: 하나는 분류 규칙이고 하나는 그리기다. 고치는 이유가 달라서
(`AGENTS.md`의 폴더 기준과 같은 판단) 따로 두면 둘을 동시에 만들 수 있고, 필터 규칙이
바뀌어도 카드를 다시 그리지 않는다.

### Wave B — 조립 (A5a + A5b 완료 후)

| 갈래 | 무엇 | 건드리는 파일 |
|---|---|---|
| B1 | 시트에 탭과 새 카드 연결, 낡은 타일 삭제 | `screens/map_shell/widgets/sheets/transit_routes_sheet.dart`, `widgets/transit_itinerary_tile.dart` (삭제) + 시트 테스트 |

B1은 A5a·A5b **둘 다** 필요하다(탭이 필터 함수를, 목록이 카드를 쓴다). A1~A4와는 여전히
독립이라, A1~A4가 아직 안 끝나도 B1은 시작할 수 있다.

### Wave C — 통합 검증 (전부 완료 후)

순서를 지켜야 한다. 앞이 실패하면 뒤로 가지 않는다.

1. `flutter analyze` + `flutter test` — 계층·주석 테스트 포함 전체
2. `flutter build apk --release --dart-define-from-file=config.local.json`
3. Tailscale `adb install -r`
4. `adb screencap` — 대중교통 결과 목록, 필터 탭 전환, 자동차 후보 패널, 계획 카드
5. 기준 이미지 대조

**직렬일 수밖에 없는 지점은 Wave C뿐이다.** 빌드·설치·캡처는 기기가 하나라 나눌 수 없다.

### 커밋 가름

`.github/CONTRIBUTING.md`의 커밋 규칙대로 성격이 다른 변경을 섞지 않는다. 갈래 하나가 커밋 하나에
대응한다 — A1~A5b 여섯, B1 하나(코드)와 삭제 하나, 그리고 이 문서. 삭제를 B1 코드와 같은
커밋에 넣지 않는 이유는 규칙에 적혀 있다(제거는 별도 커밋).

## 남은 불확실성

- **3번 임계값 150 m는 근거 없는 가정이다.** 현장에서 재 보고 조정한다. 상수 한 곳에
  있으므로 값만 바꾸면 된다.
- **카카오 응답의 `지선`/`간선` 구분.** TMAP은 `routeName`에 `간선:472`처럼 접두사를 주지만
  카카오는 주지 않는다. 어느 저장소가 실제로 쓰이는지에 따라 배지가 수단 이름
  (`버스`)으로 떨어질 수 있다. 기기 캡처에서 확인한다.
- **비율 막대의 최소 폭.** 1분짜리 도보 구간이 전체 40분 중 하나면 막대가 1픽셀이 된다.
  최소 폭을 두면 비율이 거짓이 되고, 안 두면 안 보인다. 구현하며 실제 값으로 정한다.
