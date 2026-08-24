# `lib/widgets` — 여러 화면이 함께 쓰는 위젯

**여기 남는 기준은 하나다 — 두 화면 이상이 실제로 쓴다.** 한 화면만 쓰면 그 화면
밑으로, 위젯이 아니면(순수 규칙·값) 성격에 맞는 자리로 간다. 예전에는 49개가 여기
쌓여 있었고 그중 20개는 위젯 클래스조차 없었다.

## 구성

| 파일 | 역할 |
|---|---|
| [`eta_card.dart`](eta_card.dart) | 목적지까지 거리·시간 배너 |
| [`transit_style.dart`](transit_style.dart), [`transit_itinerary_tile.dart`](transit_itinerary_tile.dart) | 대중교통 색·아이콘·시간 표기와 한 줄 타일 |
| [`sheet_header.dart`](sheet_header.dart) | 시트 머리 |
| [`map_overlay_guard.dart`](map_overlay_guard.dart), [`map_pass_through_sheet_route.dart`](map_pass_through_sheet_route.dart) | 시트가 열린 동안 지도 조작을 다루는 규칙 |

## 여기 없는 것은 어디 있나

| 찾는 것 | 자리 |
|---|---|
| 지도 렌더링 **규칙**(라벨 맞춤·아이콘·색·카메라 계산) | [`../map/`](../map/) |
| 카테고리 분류·정렬, 도달 라벨 | [`../domain/`](../domain/) |
| 길찾기 후보·경로 모드 같은 값 타입 | [`../models/`](../models/) |
| 지도 셸 전용(검색 패널·상단바·시트·장소 상세) | [`../screens/map_shell/widgets/`](../screens/map_shell/widgets/) |
| 야외 지도 전용(층 선택기·배지·경로 단계 시트) | [`../screens/outdoor_map/widgets/`](../screens/outdoor_map/widgets/) |

## 검색은 한 곳, 두 단계

검색은 [`map_top_bar.dart`](../screens/map_shell/widgets/chrome/map_top_bar.dart)의 검색창에서 **그 자리에서** 이뤄지고,
결과는 바로 아래에 붙는 [`search_panel.dart`](../screens/map_shell/widgets/search/search_panel.dart)가 보여준다. 한동안은
검색창을 탭하면 입력창이 하나 더 있는 시트가 올라왔는데, 방금 누른 창과 실제로 치는
창이 달라 검색창이 두 개인 것처럼 보였다. **다만 결과를 놓을 자리는 반드시 있어야
한다** — 결과 표시 없이 상단에서만 검색하면 그보다 더 예전처럼 스낵바로만 알리게 되어
"쳤는데 아무것도 안 나온다"가 된다.

사용자는 "일반 검색"과 "AI 검색"을 구분하지 않는다 — 매장 이름을 치든 자연어를 치든
같은 입력창에 치고, 어느 경로로 찾을지는 패널이 정한다.

- **타이핑이 300ms 멎으면**(`query` 변경): 경량 매칭(`/query/destination`). 형태소
  정규화(Kiwi)가 이 경로에 있어 매장 이름은 즉시 걸린다.
- **경량이 빈손이면**: 400ms를 더 기다렸다가 의미 검색(`/query/ai`)까지 자동으로 이어
  붙인다.
- **엔터로 확정**(`submitTick` 증가): 위 두 대기를 건너뛰고 같은 경로를 즉시 탄다.

의미 검색을 엔터에만 걸어 두지 않는 이유는 두 가지다. 한글 IME에서 첫 엔터가 조합
확정에 쓰이면 `onSubmitted`가 오지 않아 의미 검색이 아예 시작되지 않고, 그때까지 화면에는
경량이 빈손이라는 이유만으로 "찾지 못했어요"가 최종 결론처럼 떠 있게 된다. 최종 없음
문구는 의미 검색까지 끝난 `_SearchPhase.noMatch`에서만 나온다. 대신 비용은 디바운스를
두 단으로 나눠 막는다 — 경량은 예전처럼 빠르게 두고 비싼 의미 검색만 늦춘다.

두 요청 모두 실내 지도가 열려 있으면 `currentFloorId`를 함께 보낸다. "화장실"처럼 층
시설을 가리키는 질의가 건물 전체 정렬 순서상 우연히 걸리는 층(예: B6)이 아니라 지금
보고 있는 층으로 확정되게 하기 위해서다. 매장 이름을 아는 검색이 다른 층에 있어 1차가
이 때문에 빈손이 되더라도, 2차 의미 검색(`/query/ai`)은 층을 무시하고 건물 전체를 보므로
(`query_search.match_ai_destination`) 그 매장을 그대로 찾아낸다 — 사용자에게는 "뜻으로
찾았다" 배너가 붙어 나오는 차이만 있다.
층 스코프(`currentFloorId`)를 쓰는 건 이제 `search_panel.dart` 외에도
상단 길찾기 후보(`map_shell_screen.dart`의 `_searchDirectionsCandidates`)와
카테고리 매장 시트가 있다.

비싼 쪽만 늦추는 이 두 단 디바운스는 지워선 안 된다. 백엔드가 임베딩 모델을 로드하면
첫 호출이 20초대까지 가므로, 글자마다 던지면 "밥"·"밥 먹"이 전부 모델을 태운다.
**이 조건을 지우면 검색이 느려지는 게 아니라 멈춘 것처럼 보인다.**

### 길찾기 후보도 같은 두 단계다

상단 길찾기 두 칸의 출발/도착 후보도 같은 흐름을 쓴다. 예전에는 이쪽만 경량 한 번으로
끝나서 "밥 먹을 곳"처럼 이름이 아닌 말은 **항상** "검색 결과가 없습니다"였다 —
사용자에게는 상단에서는 찾아 주는 말이 길찾기에서는 안 되는, 자리에 따라 다른
검색이었다. 두 단계는 모두 `map_shell_screen.dart`가 돌리고
([`route_field_results.dart`](../screens/map_shell/widgets/search/route_field_results.dart)는 결과만 그린다), 의미 검색은
건물 안을 보고 있을 때만 이어 붙인다 — `/query/ai`는 건물 안의 매장을 찾는 계약이라
밖에서 건물을 고르는 자리에서 승격시키면 눌러도 갈 수 없는 목록이 된다.

- 콜백이 **null이면 승격하지 않는다.** 야외(건물 입구를 고르는) 모드가 그렇다 —
  `/query/ai`는 건물 안의 매장을 찾는 계약이라, 건물을 고르는 자리에서 매장을 추천하면
  눌러도 갈 수 없는 목록이 된다.
- 빈 입력은 어느 단계도 태우지 않고 안내 문구를 띄운다(`_SearchPhase.idle`). 예전에는
  이 자리에도 "검색 결과가 없습니다"가 떠서, 아무것도 치지 않았는데 못 찾았다고 말했다.
- 경량과 마찬가지로 층은 넘기지 않는다 — 길찾기는 항상 건물 전체를 뒤진다(위 `ce6fa1f`
  결정과 같은 이유).

동작은 [`../../test/widgets/route_field_candidates_test.dart`](../../test/widgets/route_field_candidates_test.dart)가
고정한다 — 승격이 빠지는 회귀와 항상 승격하는 회귀 둘 다 잡는다.

예전에는 별도 경로 안내 화면의 FAB가 `ai_search_sheet.dart`라는 대화형 검색 시트를
열었다. 검색 진입점을 상단 검색 하나로 일원화하기로 하면서 그 시트와 FAB를
제거했다(W12) — 그 화면은 상단 검색 인프라(포커스 상태·지도 잠금 배선)를 갖고
있지 않아, 검색을 다시 붙이는 대신 진입점 자체를 없앴다. 화면 자체도 뒤에 지웠다.

## 햄버거는 앱 메뉴다 — 개발 도구가 들어가는 유일한 문

[`app_menu_sheet.dart`](../screens/map_shell/widgets/sheets/app_menu_sheet.dart)는 상단 바 왼쪽 햄버거가 여는 목록이다.
한동안 이 버튼은 실내 모드에서만 뜨는 "건물 선택 (테스트)" 시트였다. 건물을 바꿀 일이
없어져 그 시트는 지웠고, 자리는 화면 구석에 흩어져 있던 진입점을 모으는 데 쓴다 —
저장한 장소·길찾기·위치 지정/보정·**디버그 설정**.

디버그 설정이 여기 있는 것이 핵심이다. 예전에는 지도 왼쪽 아래에 원형 벌레 아이콘
버튼이 떠 있었다. 일반 사용자가 볼 이유가 없는 개발 도구가 메인 지도를 차지했고,
야외에서는 실내 진입 오버레이 상태에 따라 나타났다 사라져 "어디서 켜는지"조차 상태에
얽혀 있었다. 메뉴 항목으로 내리면 지도에는 운영 화면만 남고, 진입 경로는 모드와
무관하게 고정된다. 그래서 햄버거는 이제 **모드와 상관없이 항상 보인다** — 야외에서
숨기면 야외 화면에서만 닿지 않는 항목이 생긴다.

시트는 스스로 아무것도 실행하지 않고 고른 [`AppMenuAction`](../screens/map_shell/widgets/sheets/app_menu_sheet.dart)만
돌려준다. 실제 동작은 지도 상태를 쥔 `map_shell_screen.dart`가 시트가 닫힌 뒤 수행한다
— 시트가 콜백을 직접 들고 있으면 이미 닫힌 시트의 `context`로 다음 시트를 띄우게 되고,
그 사이 모드가 바뀌면 옛 상태에 대고 동작한다.

**실패 지점.** 목록이 길어지면 기본 시트 높이 상한(화면의 9/16)에 아래쪽 항목부터
조용히 잘린다. 스크롤 되는 줄 모르는 사용자에게는 "메뉴에 디버그 설정이 없다"가 되므로
`isScrollControlled: true`로 띄운다. 항목 구성과 반환값은
[`../../test/screens/map_shell/widgets/app_menu_sheet_test.dart`](../../test/screens/map_shell/widgets/sheets/app_menu_sheet_test.dart)가
고정한다.

## 카테고리는 chip 한 번이면 목록이다

지도 위 대분류 chip을 누르면 강조가 걸리는 **동시에**
[`category_stores_sheet.dart`](../screens/map_shell/widgets/sheets/category_stores_sheet.dart)가 열린다. 소분류 pill도 그 시트
안에 있고, 목록만이 아니라 지도 강조까지 함께 바꾼다(`onSubcategoryChanged`).

- **지도 위에는 대분류 줄만 둔다.** 시트가 곧바로 뜨는데 같은 pill 줄을 지도에도 그리면
  화면에 같은 조작이 두 벌 남는다. 예전의 「목록」 버튼과 "1F에는 없습니다 · 다른 층 28곳"
  안내도 같은 이유로 없앴다 — 층·개수는 시트의 묶음 머리글이 답한다.
- **목록은 현재 층 묶음이 먼저**, 굵은 구분선 뒤에 다른 층이 온다. 현재 층에 없으면 그
  사실을 적고 넘어간다(강조 방식이라 "이 층에 없음"과 "필터 고장"이 지도에서 똑같이 보인다).
- **카테고리를 고르면 지도가 그 매장으로 옮겨 가되 배율은 그대로다.** 시트가 맨 위
  매장을 상위로 올리면(`onFirstStoreChanged`) 지도가 카테고리 줄과 시트 사이에 남는 띠
  한가운데로 카메라를 옮긴다. 층은 옮기지 않으므로 현재 층 매장만 올라온다.
  **확대는 하지 않는다**(`focusKeepZoom`) — 카테고리는 "저 업종이 어디 있나"를 훑는
  행동이라 화면이 당겨지면 층 전체의 배치를 잃는다. 배율을 바꾸는 것은 매장을 콕
  집었을 때(검색 결과·목록 항목 탭)뿐이다.

## 지도는 여기 없다

실내 도면을 그리던 `floor_plan_view.dart`가 오래 이 디렉터리에서 가장 큰 파일
(2,772줄)이었지만 지웠다. 그것은 **실내 전용 전체화면**의 지도였고, 그 화면으로
가는 길이 앱에서 사라진 뒤로 한 번도 그려지지 않았다.

지금 실내 도면은 야외 지도 위에 겹치는 오버레이가 그린다
([`../screens/outdoor_map/layers/indoor_overlay_layers.dart`](../screens/outdoor_map/layers/indoor_overlay_layers.dart)).
그 아래에서 색·라벨·아이콘·경로선 스타일 같은 공유 값은
[`../map/`](../map/)에 있다 — 지도가 하나가 된 지금도 레이어는 여럿이라
값의 원본은 한 곳이어야 한다.

## 콜백 규칙

- 시트는 검색·선택 결과를 콜백으로 돌려주고 route를 직접 바꾸지 않는다.
- 리포지토리를 쓰는 상태형 시트는 `service_locator`에서 주입된 인터페이스를 사용한다.
- 지도 위젯이 받은 모델을 수정하지 않는다. 상태 변경은 소유한 화면으로 올린다.

## 실패 지점

- `LatLng` 순서는 `(latitude, longitude)`, GeoJSON 좌표는 `[longitude, latitude]`다.
- `local_m`, WGS84, 화면 pixel을 섞으면 마커와 경로가 같은 지도를 가리키지 않는다.
- MapLibre controller가 준비되기 전에 source/layer를 갱신하면 초기 렌더가 누락될 수 있다.
- 시트 안에서 직접 전역 상태를 바꾸면 닫힘·재열림 시 선택 상태가 어긋나기 쉽다.

## 자주 하는 작업

| 하고 싶은 것 | 위치 |
|---|---|
| 지도 레이어·마커 변경 | [`../screens/outdoor_map/layers/indoor_overlay_layers.dart`](../screens/outdoor_map/layers/indoor_overlay_layers.dart)와 [`../map/`](../map/) |
| 경로 모양 변경 | `domain/route_guidance.dart`(`RoutePolylineSplit`)와 `models/route/indoor_route.dart` |
| 길찾기 출발/도착 입력 변경 | `map_top_bar.dart`(두 칸)와 `route_field_results.dart`(후보 목록) |
| 공통 색·간격 변경 | [`../theme/README.md`](../theme/README.md) |

---

> **다음 읽기:** [`lib/screens` — 사용자 흐름을 조립하는 화면](../screens/README.md)
