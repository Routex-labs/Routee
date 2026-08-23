# 시트는 한 번에 한 장

지도 위에 시트가 두 겹으로 쌓이던 문제를 어떻게 막았고, 왜 그 방식인지.
구현은 `client/lib/widgets/sheet_stack_guard.dart`, 고정하는 테스트는
`client/test/widgets/sheet_stack_guard_test.dart`와
`client/test/screens/map_shell/sheets_do_not_stack_test.dart`.

## 왜 겹치나

지도 위 시트는 **barrier가 없다**(`client/lib/widgets/map_pass_through_sheet_route.dart`).
시트를 놔둔 채 지도를 움직이라고 일부러 뺀 것이다. 그 대가로 시트가 떠 있는 동안에도
지도·상단 바·칩 줄이 그대로 눌린다 — 즉 **시트를 여는 모든 입구가 "이미 떠 있는 것 위에"
열릴 수 있다.**

## 입구는 열여섯 자리

| 시트 | 여는 계기 | 겹칠 수 있나 |
|---|---|---|
| BuildingInfoSheet | 건물 폴리곤 탭 | ✅ |
| PlaceDetailSheet | 검색·근처 매장·저장한 장소·지도 탭·링크 | ✅ |
| OutdoorPoiSheet | 건물 밖 장소 | ✅ |
| CategoryStoresSheet | 카테고리 칩 | ✅ |
| FavoritesSheet | 메뉴 → 저장한 장소 | ✅ |
| AppMenuSheet | 상단 바 햄버거 | ✅ |
| TransitRoutesSheet | 대중교통 경로 목록 | ✅ |
| DebugModeSettingsSheet | 메뉴 → 디버그 | ✅ |
| NearbyStoreSheet | **GPS 건물 진입 감지** | ✅ |
| StoreClusterSheet | 겹친 매장 탭 | ✅ |
| RouteStepsSheet | 경로 단계(안내 중) | ✅ |
| EntryFloorPrompt | GPS 진입 | ❌ 전체화면(`PageRouteBuilder`) |
| 사진 뷰어 | 상세 시트 안 | ❌ 의도적(`DialogRoute`) |
| PDR 보정 입력 | 디버그 | ❌ `DialogRoute` |

`NearbyStoreSheet`가 가장 위험하다. **탭이 아니라 GPS 진입 감지가 띄운다** — 사용자가
무엇을 하고 있든 끼어들 수 있어서, 겹치는 경우의 수가 가장 많고 재현 조건이 "가끔"이다.

## 버린 방식 — 입구마다 막기

실제로 두 번 이렇게 고쳤다. 상세 시트는 `_swapOpenPlaceDetail`이 제자리 교체로, 카테고리
목록은 `_onCategoryChipTapped`이 pop 후 await로 막았다. **둘 다 자기 짝만 막았다** —
건물↔메뉴, 카테고리↔건물, 상세↔메뉴는 그대로 뚫려 있었다.

겹칠 수 있는 입구가 열둘이라 순서쌍이 132개고, 시트를 하나 늘릴 때마다 스물넷이 붙는다.
입구를 세어 막는 방식은 **끝나지 않는다.**

## 버린 방식 — 조합 테스트

같은 이유로 132쌍을 테스트로 적는 것도 버렸다. 준비 상태(안내 중·경로 중·검색 중)까지
곱하면 관리할 수 없고, 새 시트를 넣는 사람이 조합 추가를 잊는 순간 그물이 뚫린다.

## 고른 방식 — Navigator에 불변식 하나

`SheetStackGuard`(`NavigatorObserver`)가 **"동시에 살아 있는 시트 라우트는 한 장"**만
지킨다. 입구가 몇이든, 누가 띄우든, 새로 생기든 여기서 걸린다.

### 왜 `ModalBottomSheetRoute`만 세나

의도적으로 겹치는 둘(사진 뷰어·PDR 입력)이 전부 `PageRoute`/`DialogRoute`라
**표시를 붙이지 않아도 자동으로 예외**가 된다. 규약을 모르는 사람이 새 시트를 만들어도
기본값이 "겹치지 않음"이고, 예외를 아는 사람만 다른 route 타입을 쓴다.

### 왜 `pop`이 아니라 `removeRoute`인가

`pop`은 시트의 `PopScope`를 깨워 `onCloseAll`을 쏜다. 그것은 **"사용자가 끌어내려 닫았으니
시트 chain 전체를 접어라"**는 뜻이다. 자리를 비우려고 닫은 것을 그렇게 읽으면 —
카테고리 목록에서 매장을 골라도 상세가 뜨지 않는 2차 버그가 생긴다(추적해서 확인했다).

`removeRoute`는 `PopScope`를 거치지 않아 그 신호를 만들지 않는다. 내려가는 260ms를
재생하지 않는 것도 같은 판단이다 — 그 자리에 곧바로 새 시트가 뜨므로 내려갈 이유가 없다
(`place_detail_sheet.dart`의 `removePlaceDetailRouteImmediately`가 먼저 내린 결론).

### 왜 마이크로태스크로 미루나

`didPush`는 push 처리 한복판이다. 그 자리에서 Navigator의 목록을 건드리지 않는다.
마이크로태스크는 다음 프레임을 그리기 전에 실행되므로, **두 장이 함께 보이는 프레임은
생기지 않는다.**

## 테스트에서 조심할 것

### 헛도는 순회

입구를 표에 두고 순서쌍을 도는 테스트를 처음 썼을 때 초록이었지만 **2/3이 헛돌고
있었다** — 실내 진입 후엔 건물 탭이 시트를 열지 않고, 기본 목업에는 카테고리 칩이 없어
탭이 허공을 때렸다. 그래서 각 입구가 `Future<bool> 열렸나`를 돌려주게 하고, **한 번도
시트를 열지 못한 입구가 있으면 테스트를 무너뜨린다.**

### Element 재사용

같은 모양으로 `pumpWidget`을 다시 부르면 Element가 재사용돼 **NavigatorState가 살아남고,
앞 쌍에서 열어 둔 시트가 그대로 얹힌 채** 다음 쌍이 시작한다. 순회 사이에
`pumpWidget(const SizedBox.shrink())`으로 트리를 확실히 헐어야 재는 것이 이 쌍의 결과가
된다. 이걸 몰라 "removeRoute가 안 먹는다"고 한참 헤맸다.

### 상태마다 유효한 입구가 다르다

실내에서 다른 건물을 누를 수 없고 야외에는 카테고리 칩 줄이 없다. 조합만 늘리면 실제로는
아무 일도 안 하고 통과하는 줄이 생긴다.

## 남은 것

- `EntryFloorPrompt`는 전체화면 `PageRouteBuilder`라 이 불변식 밖이다. 시트가 뜬 채로 그
  위를 덮을 수 있고, 닫으면 옛 시트로 돌아온다.
- 근처 매장 질문이 다른 시트에 밀려 걷히면 그 질문은 버려진다. 되돌리는 자리는 하단 바의
  "가까운 매장으로 위치 지정" 버튼이다(`map_bottom_bar.dart`의 `pick-nearby-store`).

## 라우트가 아닌 표면도 물러난다

지도 화면 아래에는 시트가 아닌 표면이 하나 더 있다 — **이슈 다이어리 판**
(`.../widgets/chrome/issue_diary_panel.dart`). 이것은 라우트가 아니라 하단 chrome이라
이 관찰자가 세지 않는다. 세지 않는다고 겹쳐도 되는 것은 아니다: 매장 상세 시트가 판보다
짧으면 판의 윗머리가 시트 위로 삐져나와, 사용자 눈에는 **두 장이 겹친 그림**이 된다.

그래서 관찰자가 열린 시트 수를 `openSheets`(`ValueListenable<int>`)로 내보내고, 셸이
그것을 듣는다. 시트가 한 장이라도 있으면 판을 그리지 않고, 닫히면 접힌 자리로 돌아온다.
**판을 여는 입구마다 막지 않는 이유는 시트를 걷어내는 이유와 같다** — 입구는 계속
늘어나고 한 곳이라도 빠지면 증상은 그대로다.
