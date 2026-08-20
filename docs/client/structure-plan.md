# 클라이언트 구조 개편 계획

"함수 하나는 한 가지 일만", "테스트는 그 한 가지를 지킨다", "디렉터리는 그 성격을
드러낸다" — 이 셋을 위해 **무엇을 어디로 옮길지**를 측정값으로 정한 문서다.

[야외 지도 해체 계획](outdoor-map-decomposition.md)은 화면 하나를 다루고, 이 문서는
`client/lib` 전체를 다룬다. 겹치는 부분은 그쪽이 단일 출처다.

## 지금 값 (2026-08-14)

| 항목 | 값 |
|---|---|
| `lib/` | 52,812줄 / 204파일 |
| `test/` | 1,415개 통과 |
| 25줄 넘는 함수 | 288개 |

디렉터리별 크기.

| 디렉터리 | 줄 | 파일 |
|---|---|---|
| `lib/widgets` | 13,610 | 49 |
| `lib/screens/outdoor_map` | 11,355 | 24 |
| `lib/features/indoor_navigation/*` | 9,168 | 30 |
| `lib/domain` | 5,087 | 29 |
| `lib/screens/map_shell` | 3,233 | 2 |
| `lib/models` | 2,377 | 14 |
| 나머지 | 7,982 | 56 |

## 문제 1 — `lib/widgets/`가 잡동사니다

가장 큰 디렉터리인데 **성격이 넷 섞여 있다.**

| 성격 | 예 | 어디로 가야 하나 |
|---|---|---|
| 진짜 재사용 위젯 | `sheet_header` | `widgets/` 그대로 |
| **위젯이 아닌 순수 규칙·스타일** | `store_label_fit` `floor_facility_style` `category_map_*` `floor_camera_*` `store_label_anchor` | `core/map/` — 위젯 트리 없이 시험되는 코드다 |
| 특정 화면 전용 시트·바 | `search_panel` `map_top_bar` `outdoor_poi_sheet` `route_field_results` | 그 화면 밑(`screens/<화면>/widgets/`) |
| 갓 위젯 | `floor_plan_view`(3,229줄) | ~~해체~~ → **지웠다.** 앱에서 닿지 않았다(문제 4) |

**위젯 클래스가 하나도 없는 파일이 20개 / 2,794줄**이다. `widgets/`에 있다는 이유로
"UI 코드"로 읽히지만 실제로는 순수 함수라 위젯 없이 시험된다. 자리를 옮기면 그 사실이
이름에서 드러난다.

## 문제 2 — 한 함수가 여러 일을 한다

길이만 보면 긴 위젯 트리가 상위를 다 먹는다. 그래서 **책임의 종류**를 셌다 —
바깥 왕복(`await`), 화면 상태 변경(`setState`), 지도 쓰기, 사용자에게 말 걸기.
서로 다른 종류를 여럿 하고 있으면 쪼갤 후보다.

| 함수 | 줄 | await | setState | 지도쓰기 | 말 걸기 | 섞인 것 |
|---|---|---|---|---|---|---|
| ~~`_onStyleLoaded` (floor_plan_view)~~ | 371 | 51 | 0 | 31 | 0 | 52줄로 줄인 뒤, 파일째 삭제(문제 4) |
| ~~`_buildShell` (map_shell)~~ | 372 | 0 | 4 | 0 | 0 | 레이아웃 + 상태 전이 → **25줄 미만**(8단계) |
| ~~`_requestTransitRoute` (map_shell)~~ | 152 | 6 | 1 | 0 | 5 | 조회 + 파싱 + 상태 + 안내 문구 → **89줄**(8단계) |
| `_buildBody` (outdoor_map) | 432 | 0 | 0 | 0 | 0 | 오버레이 14종 조립 |
| ~~`_startRoute` (map_shell)~~ | 178 | 7 | 1 | 0 | 0 | 후보 확정 + 계산 + 표시 → **25줄 미만**(8단계) |
| `_search` (search_panel) | 163 | 4 | 4 | 0 | 0 | 경량 검색 + 의미 검색 + 상태 |
| ~~`onAltitude` (escalator detector)~~ | 331 | 0 | 0 | 0 | 0 | 판정 단계 6개가 한 함수 → **41줄**(7단계) |

파일별로는 `floor_plan_view`(334점) · `map_shell_screen`(285) · `parts/route`(186)
· `search_panel`(167) 순이었다. 1위가 삭제됐으니 **지금 남은 최악은 `map_shell_screen`**이고,
그 다음이 한 함수에 판정 6단계가 들어 있는 `onAltitude`(에스컬레이터 검출기)다.

**에스컬레이터 판정(`onAltitude`)은 손대지 않는다** — 알고리즘 재작성이 예정돼 있다.

## 문제 3 — 테스트

### 해결됨: 루트가 둘이던 것

`tests/unit_test/`에 83개가 평면으로 쌓여 있고 `test/`가 따로 있었다. CI가 한때
`tests/`만 돌려 `test/` 아래 337개가 **한 번도 실행되지 않은** 적이 있다.
`test/` 하나로 합치고 `lib/` 구조를 미러하게 했다(fa4a1b2f).

앞으로 규칙은 하나다 — **`lib/a/b/c.dart`의 테스트는 `test/a/b/c_test.dart`.**
`lib/`에서 파일을 옮기면 테스트도 같은 자리로 옮긴다.

### 해결됨: 한 파일이 여러 대상을 시험하던 것

`widgets_test.dart` 하나가 `LocationMarker`·`UncertaintyCircle`·`StatusBadge`·
`EtaCard`·`SearchPanel` 다섯을 시험하고 있었다. 대상별로 갈랐다(d8f72dc4).
`widget_test.dart`는 map_shell이 아니라 **앱 전체 스모크**여서 `test/app_test.dart`로
옮겼다. 이때 케이스 수는 1,415개 그대로였다(지금은 죽은 화면 삭제로 1,397개).

### 남은 것 2: 직접 테스트가 없는 모듈

같은 이름의 테스트 파일이 없는 `lib` 파일이 118개다. **이게 곧 "미검증"은 아니다** —
화면 전체를 띄우는 행동 테스트가 대신 덮는 코드가 많다. 다만 그런 테스트는 무엇이
깨졌는지 짚어 주지 못한다.

직접 테스트가 없으면서 큰 것들.

| 파일 | 줄 |
|---|---|
| `features/indoor_navigation/application/corridor_position_tracker.dart` | 2,093 |
| `features/indoor_navigation/application/indoor_guidance_session.dart` | 876 |
| `features/indoor_navigation/application/floor_map_matcher.dart` | 705 |
| `models/route/transit_route.dart` | 462 |
| `map/style/floor_facility_style.dart` | 390 |
| `screens/map_shell/directions_candidates.dart` | 280 |

## 문제 4 — 앱에서 닿지 않는 화면이 있었다 (해결: 5,135줄 삭제)

5단계(`floor_plan_view._onStyleLoaded` 분해)를 하다 발견했다. **이 저장소에서 가장 큰
파일이 실행 중인 앱에서 한 번도 그려지지 않았다.**

근거는 셋이다.

1. `FloorPlanView`를 쓰는 화면은 `route_guide`와 `debug/floor_map_preview` 둘뿐이다.
2. `route_guide`로 가는 유일한 길은 `destination` 화면인데, **`AppRoutes.destination`을
   push하는 코드가 없다.** `floor_map_preview`·`pdr_svg_test`·`api_health`도 마찬가지로
   라우트 표에만 있고 부르는 곳이 없다.
3. 이름 없는 네비게이션(`Navigator.push`/`MaterialPageRoute`)이 **0건**이고,
   AndroidManifest에도 딥링크 intent-filter가 없다(LAUNCHER 하나뿐).

### 경계를 손으로 고르지 않았다

처음 손으로 센 것은 4,185줄이었는데 **실제로는 5,135줄이었다.** 화면을 지우면
그 화면만 쓰던 파일이 죽고, 그 파일만 보던 테스트가 죽는다. 그래서 import
그래프의 **고정점**을 구했다 — 더 이상 새로 죽는 게 없을 때까지 반복.

뿌리를 잘못 잡으면 크게 틀린다. `main.dart` 하나만 뿌리로 두면 테스트 30여 개가
쓰는 mock 리포지토리까지 "죽음"으로 나온다. 뿌리는 **실제 진입점 전부**여야 한다 —
`main.dart`, 자기 `main()`을 가진 실기기 하니스, 그리고 살아남는 테스트들.

그렇게 해도 자동으로 안 끊기는 고리가 있었다. `FloorPlanView`와 그 테스트가
**서로를 살려주고 있었다** — 테스트가 파일을 import하니 파일이 "닿는다"로 세어지고,
그 파일을 쓰는 게 그 테스트뿐이니 테스트도 "살아 있다"로 세어진다. 여기서
기준은 사람이 정한다: **제품 코드에서 부르는 곳이 없으면 죽은 것이다. 테스트가
있다는 건 커버리지의 증거지 사용의 증거가 아니다.**

| 지운 것 | 줄 |
|---|---|
| `widgets/floor_plan_view.dart` | 2,772 |
| `core/map/floor_plan_layers.dart` | 508 |
| `screens/debug/pdr_svg_test_screen.dart` | 468 |
| `screens/route_guide/route_guide_screen.dart` | 335 |
| `screens/debug/floor_map_preview_screen.dart` | 266 |
| `screens/destination/destination_screen.dart` | 156 |
| `screens/arrival/arrival_screen.dart` | 115 |
| `screens/debug/api_health_check_screen.dart` | 73 |
| `core/floor_switch_timing.dart` | 68 |
| `widgets/uncertainty_circle.dart` | 24 |
| `repositories/mock_place_detail_repository.dart` | 12 |
| 테스트 3개 + `app_test.dart`의 7블록 | 274 |

### 살려 둔 것 — 자동 판정이 틀렸던 셋

| 파일 | 왜 살렸나 |
|---|---|
| `repositories/mock_*_repository.dart` | 테스트 30여 개가 쓰는 대역이다 |
| `features/indoor_navigation/debug/pdr_device_harness*` | 자기 `main()`을 가진 실기기 하니스 |
| `repositories/routing/tmap_transit_repository.dart` | 카카오 키가 소진되면 되돌릴 대체 구현이라고 코드가 명시한다 |

### 남은 것

라우트가 **하나**가 됐다(`/` → `MapShellScreen`). `AppRoutes`에 상수 하나만
남긴 이유는 `initialRoute`와 `routes`가 같은 문자열을 봐야 하기 때문이다.

교훈 한 줄: **push가 없는 라우트는 죽은 코드다.** 화면 여섯 개가 라우트 표에만
등록된 채 5,135줄을 붙들고 있었고, 그중 하나는 저장소에서 가장 큰 파일이었다.

## 목표 구조

이미 잘 돼 있는 곳이 하나 있다 — `features/indoor_navigation/`이 `contract/`(계약) ·
`application/`(headless 로직) · `platform/`(채널) · `debug/`로 갈려 있다.
**그 모양을 나머지에 퍼뜨린다.**

```
lib/
  core/            앱 전역 설정·서비스 로케이터
    map/           지도 규칙·스타일 (위젯 아닌 것들이 여기로)
  domain/          순수 계산 (다익스트라·경로 안내·좌표) — 지금도 이대로 좋다
  models/          직렬화 값 타입
  repositories/    바깥 세계(HTTP)
  features/
    indoor_navigation/  contract · application · platform · debug  ← 본보기
  screens/
    outdoor_map/   화면 + 그 화면 전용 조각
    map_shell/     〃
  widgets/         **여러 화면이 실제로 함께 쓰는 위젯만**
```

## 순서

앞이 끝나야 뒤가 깨끗하다.

| # | 할 일 | 크기 | 상태 |
|---|---|---|---|
| 1 | 테스트 루트 통합 | 83파일 | **완료** (fa4a1b2f) |
| 2 | `widgets/`의 위젯 아닌 17개를 성격별로 | 2,794줄 | **완료** (951a25db) |
| 3 | 화면 전용 위젯 25개를 그 화면 밑으로 | 8,000줄 | **완료** (951a25db) |
| 4 | 여러 대상을 시험하던 테스트 분해 | 2파일 | **완료** (d8f72dc4) |
| 5 | `floor_plan_view._onStyleLoaded` 분해 | 371 → 52줄 | **완료** (2c5e1028) |
| 6 | 앱에서 닿지 않는 화면 삭제 | 5,135줄 | **완료** (b33a77ae, 5d3e400d) |
| 7 | `escalator_transition_detector`의 큰 함수 분해 | 331 → 41줄 | **완료** (60594381) |
| 8 | `map_shell_screen` 분해 | 2,953 → 2,553줄 | **완료** (8aaf5aae) |
| 9 | 테스트가 비어 있는 모듈에 테스트 | 3파일 · 36케이스 | **완료** (f043def8) |
| 10 | 야외 지도 파일을 관심사별로 더 가르기 | 본체 2,250 → 1,967줄 | **완료** (25e559e2) |
| 11 | 주석의 자리 나누기 | 머리 주석 1,122 → 463줄 | **완료** (3e5fd616, 5f923913, cf8dc928) |
| 12 | 계층 방향 세우기 + 주제별 폴더 | 위반 6 → 0 | **완료** (9cc96de0, e3d58095) |
| 13 | 주석 2차 압축 + 상한 조이기 | 12,239 → 9,649줄 | **완료** (db721efe, 258a6ea1, 1d3eba6f) |
| 14 | 폴더 안에서 한 겹 더 묶기 | 5개 디렉터리 · 147파일 | **완료** (57a4f81d, 2ae5e34f) |
| 15 | `map_shell_screen`을 `parts/`로 다시 가르기 | 본체 2,946 → 986줄 | **완료** |

### 15단계 — 다시 커진 `map_shell_screen`을 `parts/`로

8단계가 이 파일을 2,953 → 2,553줄로 줄였지만 **2,946줄로 돌아왔다.** 한 파일이라
막을 장치가 없었기 때문이다. 야외 지도가 쓰는 `part` 방식을 그대로 옮겨,
본체에는 상태 필드·생명주기·`build`만 남긴다.

| 파일 | 줄 | 담은 것 |
|---|---|---|
| `map_shell_screen.dart` | 986 | 필드 전부 · `initState`/`dispose` · 지도 잠금 · `build`·`_build*` |
| `parts/route_plan.dart` | 487 | 길찾기 두 칸 — 후보 조회·바꾸기·지도에서 고르기 |
| `parts/sheets.dart` | 470 | 시트 chain · 건물/매장/POI 정보 시트 · 공유 링크 |
| `parts/transit.dart` | 428 | 대중교통 조회·후보 선택·앞뒤 도보 채우기 |
| `parts/route_start.dart` | 242 | 이동 수단 결정 · 도보/자동차 경로 시작 |
| `parts/search.dart` | 157 | 검색창·검색 패널의 입력과 선택 |
| `parts/bottom_bar.dart` | 130 | 하단 바 버튼 다섯(메뉴·즐겨찾기·보정·위치 지정) |
| `parts/category.dart` | 122 | 카테고리 pill·목록 시트·층별 개수 |

part 규약(왜 extension인가, 왜 `ignore_for_file`인가)은
[야외 지도 이동 대장](outdoor-map-moves.md)이 단일 출처다. 여기서도 같다.

**본문은 한 글자도 바꾸지 않았다.** 옮기기만 했고 테스트는 하나도 고치지 않았다
(`test/screens/map_shell/` + 계층·머리 주석 검사 364개 통과). 선언 자리만 어쩔 수 없이
움직인 것이 둘 있다.

| 무엇 | 어떻게 | 왜 |
|---|---|---|
| `_buildingId` `_mapLock*` | 클래스 `static const` → 최상위 `const` | extension은 확장 대상의 static을 이름 없이 못 읽는다. 호출부를 15곳 고치는 대신 선언을 올렸다 |
| `_onSearchFocusChanged` `_onRouteOriginFocusChanged` `_onRouteDestinationFocusChanged` `_onPlaceLinkChanged` | part로 안 옮기고 본체에 남김 | 아래 참고 |

**extension 메서드의 tearoff는 매번 새 클로저다.** 인스턴스 메서드 tearoff는 같은
객체·같은 메서드면 `==`가 참인데 extension은 아니라서, `addListener`로 건 것을
`removeListener`가 못 지운다. 옮겼더니 죽은 화면이 링크 수신함을 계속 듣고 다음
화면의 링크를 가로챘다 — `place_link_cold_start_test.dart`가 잡았다. 그래서
`addListener`/`removeListener` 짝을 이루는 넷은 본체에 남는다.

### 14단계 — 폴더 안에서 한 겹 더 묶었다

12단계가 `domain/`을 여섯으로 가른 뒤, 남은 다섯 디렉터리도 파일이 15~30개씩이라
목록을 훑어야 원하는 파일을 찾을 수 있었다. 같은 기준(**함께 바뀌는가**)으로 한 겹
더 묶는다.

| 디렉터리 | 나눈 것 |
|---|---|
| `models/` | `building/` `place/` `route/` |
| `repositories/` | `building/` `place/` `routing/` — models와 같은 이름 |
| `map/` | `style/` `label/` `icon/` `camera/` |
| `screens/map_shell/widgets/` | `search/` `sheets/` `chrome/` |
| `screens/outdoor_map/` | `parts/` `entry/` `gps/` `layers/` `camera/` |

**본문은 한 글자도 바꾸지 않았다.** 바뀐 줄은 전부 import 경로이고,
`git mv`라 이력도 따라온다. 검증은 매 단계 `flutter analyze` 0건 + 테스트 1,458개다.

`parts/`에서는 `outdoor_map_screen_` 접두사를 뗐다 — 폴더가 그 일을 대신하므로 이름에
두 번 적을 이유가 없다(`map/`에서 `map_` 접두사를 뗀 것과 같다). `part of`는
`'../outdoor_map_screen.dart'`로 한 단계 올라간다.

**등급표는 손대지 않았다.** `lib_layer_direction_test.dart`는 경로의 **첫 조각**만 보고
등급을 매기므로, 최상위 디렉터리가 그대로인 한 하위 폴더는 검사에 영향이 없다. 이건
운이 아니라 그 테스트가 처음부터 그렇게 쓰였기 때문이다.

**함께 고친 것** — 경로를 글자로 박아 둔 테스트 하나(`pretendard_font_assets_test`),
디렉터리 README 넷의 파일 표, 문서 25곳의 경로 문자열. 깨진 링크는 이 작업 전후 모두
8건이고 전부 이 작업과 무관한 옛 파일이다(VERSION.md · issues/ · PR 템플릿).

### 12단계 — 계층은 이미 있었고, 이름과 강제가 없었다

"파일에 계층이 없어 보인다"는 지적으로 시작했는데, **204개 파일의 import를 전부 따라가
보니 방향은 거의 다 맞았다.** 거꾸로 가는 화살표가 여섯이었다.

| 어긋난 곳 | 원인 | 고침 |
|---|---|---|
| `domain/geo_transform` → features | `PdrToFloorAxes`를 쓰는데 정의가 위층에 있었다 | 타입을 domain으로 내림(그 타입을 **계산하는** 함수가 원래 domain에 있었다) |
| `domain/route_checkpoint`·`route_movement` → features | tracker의 30필드 결과 객체를 통째로 받았다 | 실제로 읽는 두 값만 인자로 받도록 좁힘 |
| `core/map/store_label_fit` → screens | 라벨 크기 계산이 화면의 zoom 상수를 봤다 | zoom↔미터 산수를 `map/zoom_math`로 내림 |
| `domain/category_taxonomy` → core/map | 표시 문구 함수가 아이콘 표에 얹혀 있었다 | `domain/category/subcategory_label`로 내림 |
| `core/service_locator` → features·repositories | 조립 루트가 "설정" 폴더에 있었다 | `lib/` 최상단으로 올림 |
| `map/location_marker_icon` → widgets | 마커 치수 상수가 위젯에 있었다 | 상수를 `map/`으로 내림 |

**진짜 문제는 `core/`였다.** 그 폴더의 README는 스스로 "앱 설정과 전역 배선"이라
선언하고 구성 파일로 둘만 적어 두었는데, 실제로는 지도 스타일 18개가 들어와 있었다.
한 폴더에 최상층(조립 루트)과 최하층(설정)이 같이 있으니 어느 방향으로 화살표를
그려도 순환이 났다 — `core`라는 이름이 계층이 아니라 **"어디에 둘지 모르겠는 것"**을
뜻하고 있었던 것이다.

지금 등급표(숫자가 클수록 위, import는 아래로만).

```
5  app.dart · main.dart · service_locator.dart
4  screens/
3  widgets/
2  repositories/  features/  map/
1  domain/  state/
0  models/  core/  theme/  routing/
```

`domain/`은 32개가 평면으로 쌓여 있던 것을 여섯으로 나눴다 — `route`(경로를 만든다) ·
`guidance`(따라간다) · `store` · `search` · `category` · `geo`. **가르는 기준은 파일
수가 아니라 고치는 이유**이고, 그건 10단계에서 야외 지도를 가를 때 쓴 것과 같은 기준이다.

`map/`은 19개를 평면으로 둔다. 안이 전부 "지도 표현" 한 주제라 더 나눌 축이 없다 —
`domain/`이 문제였던 건 개수가 아니라 **관련 없는 주제 다섯이 섞여 있어서**였다.

### 왜 pub 패키지로 쪼개지 않았나

컴파일러가 방향을 강제한다는 점에서 그게 제일 세다. 비용도 재 봤는데 **작았다** —
빈 path 의존 패키지 4개를 물려 봤더니 `pub get` 2.2초·`analyze` 9.0초로 차이가 없었다
(path 의존은 요약으로 해석되고, 코드를 옮기면 그만큼 원래 패키지가 줄어든다).

그런데 **지금은 쪼갤 수가 없었다.** pub은 순환 의존을 거부하므로 위 여섯을 먼저
고쳐야 했고, 즉 패키지 분리의 1단계가 이 단계다. 경계가 굳은 뒤에 다시 판단한다.

그때까지는 `test/lib_layer_direction_test.dart`가 그 자리를 대신한다. 등급은 지어낸
것이 아니라 실제 그래프를 재서 나온 순서이고, 예외는 조립 루트 하나뿐이다.

### 11단계 — 주석은 총량이 아니라 자리가 문제였다

파일 머리에 설계 서사가 쌓여 있었다(최장 52줄 — 그 파일은 전체가 72줄이라 코드보다
주석이 앞에 더 많았다). 같은 것을 Flutter SDK에서 재면 `material` 198파일에 10줄 넘는
머리 주석이 **0개**다.

**총량은 문제가 아니었다.** 우리 비율 28%는 Flutter material(28.8%)·widgets(43.7%)과
같은 대역이고, 선언당 주석 길이는 오히려 우리가 더 짧다(15.5줄 ↔ 22.8줄). 문제는 파일을
열 때 코드 첫 줄까지 넘겨야 하는 벽이었다. 규칙은 [주석 자리](comment-placement.md)에 있고
상한은 `test/lib_header_comment_length_test.dart`가 지킨다.

### 10단계 — 파일 분할과 결합도는 별개 축이다

9단계를 마치고 "결합이 그대로라 더 할 게 없다"고 적었는데 **그건 두 축을
뭉갠 것이다.** 결합을 낮추지 않고도 파일은 더 가를 수 있다.

| 뗀 것 | 줄 | 왜 |
|---|---|---|
| `outdoor_map_tuning.dart` | 221 | 조정 상수 35개. 값 하나 만지려고 2,200줄을 스크롤할 이유가 없다 |
| `widgets/placing_anchor_hint.dart` | 100 | 화면 파일 끝에 붙어 있던 사설 위젯 |
| `_guidance.dart` | 298 | 안내 진행률·도착 판정 |
| `_route_layers.dart` | 203 | 경로·목적지를 지도에 쓰기 |
| `_floor_switch.dart` | 328 | 층 전환 크로스페이드·세대 관리 |
| `_store_tap.dart` | 204 | 화면 좌표 → 타일 feature → 매장 |

**1,000줄 넘는 part가 하나(`_route.dart` 1,148)만 남았다.**

가른 기준은 크기가 아니라 **고치는 이유**다. 경로를 만드는 코드는 목적지가
바뀔 때 돌고, 따라가는 코드는 걸음이 들어올 때 돌고, 그리는 코드는 레이어
순서가 바뀔 때 돈다.

**본체 1,967줄은 여기가 바닥이다** — 상태 필드 150개(extension은 필드를 못
만든다), 공개 API 19개(계약면), 생명주기(`@override`는 extension에서 못 쓴다).
더 줄이려면 상태를 나눠야 하고, 그건 결합도 작업이다.

### 분할이 문서 문제 둘을 드러냈다

상수를 공개로 바꾸다 이름 충돌 검사에서 나왔다.

- **같은 이름 다른 값이 둘 있었다.** `maxIndoorGpsSnapDistanceM`이
  `indoor_location_estimate.dart`에 12.0, 야외 지도에 15.0. 다른 코드 경로인데
  이름만 같아서 한쪽만 고치고 둘 다 고쳤다고 믿기 딱 좋다. 쓰이는 자리를 이름에
  박아 `autoEntryGpsSnapDistanceM`으로 바꿨다(**값은 그대로**).
- **없는 심볼을 가리키는 문서 링크.** `floor_selector.dart`가
  `[floorSelectorBottomOffset]도 함께 노출한다`고 적는데 그런 심볼이 없다.

### 9단계 — 대상을 고르다 계획서가 틀린 것을 찾았다

이 표에는 원래 "**직접 테스트 없는 큰 모듈**: `corridor_position_tracker`(2,093),
`indoor_guidance_session`(876), `floor_map_matcher`(705)"라고 적혀 있었다.
**셋 다 틀렸다** — 각각 28·36·11 케이스가 이미 있다.

줄 수로 "테스트가 없다"고 말하면 이렇게 틀린다. 그래서 다시 쟀다: 테스트가
**이름조차 언급하지 않는** lib 파일을 찾고, `part` 파일(부모를 통해 시험된다)과
위젯을 걸러냈다. 남은 것이 아래 셋이다.

| 파일 | 줄 | 왜 이것부터인가 | 케이스 |
|---|---|---|---|
| `features/debug_mode/landmark_cardinal_calibration.dart` | 170 | 실내 **북쪽**을 정한다. 틀리면 도면 전체가 돌아간 채로 그려지는데 화면에는 오류가 없다 — 각도는 언제나 하나 나온다 | 11 |
| `screens/outdoor_map/gps/gps_session.dart` | 224 | 스트림이 죽는 방식이 셋인데 **2번·3번이 차례로 빠져 있던 적이 있다.** 인계 문서에 "재시작이 잦다"가 미해결로 남아 있었다 | 11 |
| `widgets/transit_style.dart` | 129 | 전부 순수 함수라 붙이는 비용이 거의 0인데 비어 있었다 | 14 |

### 차이만 재는 테스트는 상수 오차를 못 본다

랜드마크 맞춤에 먼저 쓴 것은 불변성 아홉 개였다 — 옮겨도 그대로, 확대해도
그대로, 돌리면 그만큼. **그 아홉 개가 오타 둘을 그대로 통과했다.** `atan2`
인자를 뒤바꾸면 모든 경우에 90°가 똑같이 더해지는데, 차이를 재는 테스트에는
그게 보이지 않는다.

고친 방법은 **답을 아는 입력**이다. 레퍼런스 캡처가 북고정이므로 그 픽셀
좌표를 그대로 도면으로 쓰면 북쪽은 0°여야 한다. 이제 세 가지 오타(atan2 인자,
반전 부등호, 회전 행렬 부호)가 전부 잡힌다.

**모든 새 테스트는 코드를 일부러 깨서 확인했다.** 열두 가지 오타를 넣었고 열두
번 다 실패했다.

### 8단계에서 한 것

| 함수 | 전 | 후 |
|---|---|---|
| `_buildShell` | 372 | **25줄 미만** — Stack 다섯 층 목록으로 읽힌다 |
| `_startRoute` | 178 | **25줄 미만** |
| `_requestTransitRoute` | 152 | **89** |

**두 조각은 순수 함수로 떼어 테스트를 붙였다.** 여기가 8단계의 핵심이다 —
크기를 줄인 것보다 **지도 없이 시험할 수 있게 된 것**이 값이다.

| 새 파일 | 무엇 | 테스트 |
|---|---|---|
| `walk_route_kind.dart` | 도보 길찾기 다섯 갈래 판정 | 15개 |
| `transit_walk_handoff.dart` | 내린 자리 찾기 + 마지막 도보 잘라내기 | 9개 |

둘 다 **과거에 실제로 사고를 낸 코드**다. 전자는 실내→야외 갈래가 통째로 빠져
있던 기간이 있었고, 후자는 하차 지점 바로 옆 문을 두고 건물을 빙 돌아 반대편
문으로 안내했다. 둘 다 화면에는 원인을 알 수 없는 실패로만 보였다.

**두 사고를 각각 코드에 다시 심어 보고 테스트가 실패하는지 확인했다.**
실내→야외 갈래 삭제 → 1개 실패. `legs.last`로 되돌리기 → 1개 실패.

**같은 갈래가 두 번째로 사고를 냈다.** 판정을 떼어낸 뒤에도 조건 3)에
`origin == null`이 달려 있어서, 실내 매장을 **출발지로 고른** 사용자는 그
갈래에 못 들어가고 `indoorFallback`으로 떨어졌다. 야외 목적지가 실내 라우팅에
넘어가 화면에는 또 "도착지 노드 정보가 없어…"만 떴다. 지금은 조건 1)과 같은
모양(`origin == null ? indoorStartReady : origin.isIndoorPoint`)이다 — **대칭인
두 갈래는 조건도 대칭이어야 한다**는 것이 이 사고가 남긴 규칙이다.

사설 위젯 3종(`MapOverlayScrollRow`·`CategoryChipsRow`·`MapPickHintCard`)은
`widgets/`로 옮겼다. 그 자리는 이미 이 화면의 위젯 디렉터리였고, 화면 파일
끝에만 남아 있던 것이다.

### 7단계에서 한 것

`onAltitude` 한 함수에 판정 6단계가 눌려 있었다. 임계값 하나를 고치려 해도
331줄을 전부 훑어야 했다.

| 함수 | 전 | 후 |
|---|---|---|
| `onAltitude` | 331 | **41** |
| `_advanceCandidate` | (신설 131) | **26** |
| `_updateVerticalMotion` | 106 | **60** |
| `_openCandidate` | (신설 96) | **79** |

이 파일에 **100줄 넘는 함수가 없다.**

**상태 필드는 나누지 않았다.** 값 객체로 뽑으면 각 조각을 따로 시험할 수 있지만
그건 축자 이동이 아니고, 이 파일 첫 줄이 "오탐 비용이 미탐 비용보다 훨씬 크다"고
선언하는 코드에서 무회귀를 증명할 수 없다. 함수를 가르는 것까지가 이번 범위다.

**그물이 진짜인지 확인했다.** 단계 1(걸음 근거 읽기)이 단계 3(EMA 갱신)보다
앞서야 하는 이유는 단계 2(시계열 단절)가 EMA 상태를 지우기 때문이다. 그 순서를
일부러 뒤집으니 테스트 2개가 실패했다 — 통과만 보고 넘어가면 이런 이음매는
소리 없이 깨진다.

### 1~4를 마친 결과

| 디렉터리 | 전 | 후 |
|---|---|---|
| `lib/widgets` | 13,610줄 / 49개 | **4,232줄 / 11개** |
| `lib/core/map` | — | 2,340줄 / 12개 (12단계에서 `lib/map/`으로) |
| `lib/screens/map_shell/widgets` | — | 5,789줄 / 12개 (+ `place_detail/` 5개) |
| `lib/screens/outdoor_map/widgets` | — | 974줄 / 9개 |
| 테스트 루트 | `test/` + `tests/unit_test/` | `test/` 하나 |

**`lib/widgets/`에 남은 11개는 전부 두 화면 이상이 실제로 쓴다.** 그 기준을
README 맨 위에 적어 두었다 — 기준이 없으면 다시 쌓인다.

5부터는 야외 지도와 같은 방식(테스트 먼저 → 옮기고
→ 원본과 대조 → 실기기 확인)을 쓴다.

## 이 개편이 건드리는 다른 곳

파일을 옮기면 **같이 고쳐야 하는 것**이 넷이다. 빠뜨리면 문서가 먼저 썩는다.

| 대상 | 무엇을 |
|---|---|
| `client/test/` | `lib/` 구조를 미러하므로 **같은 자리로 함께 옮긴다** |
| `client/lib/widgets/README.md` | 위젯 목록을 문서화하고 있다. 옮긴 파일은 여기서 지운다 |
| `docs/client/*.md` | 파일 경로를 본문에 적어 둔 문서가 여럿이다(`grep -rn 'lib/widgets/' docs/`) |
| `.github/workflows/ci.yml` | 지금은 `test/`·`integration_test/`만 가리켜 경로 고정이 없다 — 이 개편으로는 바뀌지 않는다 |

**백엔드는 영향이 없다.** API 계약(JSON)이 바뀌지 않고, 경로 계산은 그대로 클라이언트
온디바이스다. 클라이언트 디렉터리 이름은 백엔드가 알지 못한다.
