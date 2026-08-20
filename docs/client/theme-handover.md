# 전역 테마를 언제 Runtime Kit에 넘기나

포팅 [단계 8](https://github.com/Routex-labs/routex-design-system/blob/main/docs/navigation-app-porting-guide.md)의
마지막 항목은 "모든 제품 화면이 옮겨진 경우에만 전역 `RoutexTheme.light` 전환을 별도
검토한다"이다. 이 문서가 그 검토의 기록이고, **판정은 "아직 아니다"** 다.

조건과 남은 차이의 단일 출처는 문서가 아니라 테스트다 —
`client/test/theme/routex_theme_bridge_test.dart`의 "전역 전환 게이트". 목록이 비는 날
`AppTheme.light`를 `RoutexTheme.light`로 갈아 끼운다.

## 왜 지금이 아닌가 — 재 본 값

2026-08-17 이전 검토에서 `AppTheme.light`를 `RoutexTheme.light`로 바꾸고
전체 테스트를 돌린 결과는
**1,555개 중 실패 2개**였고, 그 둘은 "전환하지 않았음"을 지키던 브리지 테스트 자신이다.
나머지 1,553개는 그대로 통과한다.

**그래서 테스트 통과는 이 변경의 근거가 되지 못한다.** 우리 테스트는 색과 글자 크기를
거의 검사하지 않으므로, 화면이 전부 바뀌어도 초록이다. 계산된 `ThemeData`를 직접 견줘야
차이가 보인다.

| 축 | 앱 | Runtime Kit | 전환하면 |
|---|---|---|---|
| `colorScheme.primary` | `0xFF4A87F1` (하늘) | `0xFF0F5A46` (진초록) | 앱이 `AppColors.primary`를 직접 읽는 자리는 그대로라 **한 화면에 파랑과 초록**이 선다 |
| `colorScheme.secondary` | `0xFF6C9BF2` (실내 강조) | 회색 계열 | Kit이 secondary를 지정하지 않아 seed에서 파생된 중립색이 온다 |
| `textTheme.bodyMedium` | 14 · 행간 기본 | 16 · 행간 1.5 | 크기를 명시하지 않은 글자가 커지고 **줄 간격이 늘어 시트가 세로로 팽창**한다 |
| `disabledColor` | 검정 38% | 불투명 회색 | Material 컨트롤의 비활성 표현이 바뀐다 |
| `dividerColor` | 앱 구성표 파생 | `borderSubtle` | 구분선 10개 파일이 함께 바뀐다 |
| 컴포넌트 테마 | 앱이 소유 | 없음 | `inputDecoration`·`card`·`filledButton`·`textButton`·`listTile`·`divider`·`progressIndicator`·`appBar`가 **한꺼번에 Material 기본으로 떨어진다** |

`AppColors` 직접 참조는 22개 파일 110건이다. 그중 상당수는 지도 그래픽(경로선·마커·핀)이고
**그건 남는 것이 맞다** — 가이드가 단계 7에서 map visual을 제품 UI와 갈랐다. 전환을 막는
것은 참조 수가 아니라 **아직 앱이 그리는 Material 위젯**이다.

| 위젯 | 곳 | 읽는 값 |
|---|---|---|
| `TextField` | 1 제품 화면 | 메뉴 이름을 거르는 내부 입력. Runtime Kit에는 leading 없는 embedded field가 아직 없다 |
| `Card` | 0 제품 화면 | 지도 힌트까지 `RoutexSurface`로 이동 |
| `FilledButton` | 0 제품 화면 | 장소 액션과 경로 시작을 `RoutexPlaceActions`·`RoutexButton`으로 이동 |
| `TextButton` | 1 앱 전용 동작 | 절대 heading을 얻지 못한 PDR의 4방향 보정 dialog. Kit dialog의 단일 확인 계약으로는 표현할 수 없음 |
| `ListTile` | 0 제품 화면 | 검색·메뉴·저장·매장 목록을 `RoutexListCell`로 이동 |
| `Divider` | 0 제품 화면 | `RoutexDivider`로 이동 |
| `CircularProgressIndicator` | 1 제품 화면 | 상세 시트의 14px 비동기 갱신 표식. 목록 로딩은 `RoutexResultList`·skeleton으로 이동 |
| `AppBar` | 1 (PDR 디버그) | `appBarTheme` |

## 전환하려면 무엇이 먼저인가

순서가 있다. 색보다 **컴포넌트가 먼저**다 — 색만 바꾸면 두 출처가 한 화면에서 싸운다.

1. 위 표의 Material 위젯을 Runtime Kit 대응물로 옮긴다. 옮길 때마다 앱 테마에서 해당
   컴포넌트 테마를 지우고, 게이트 목록에서도 지운다.
2. `AppColors.primary`를 직접 읽는 제품 UI 자리를 `context.routexColors`로 옮긴다.
   지도 그래픽은 두고, 남는 `AppColors`는 map visual 전용으로 좁힌다.
3. `textTheme` 두 슬롯이 마지막이다. 크기·행간이 바뀌면 아직 안 옮긴 화면이 세로로
   넘치므로, 남은 화면이 없을 때 한다.
4. 게이트 목록이 비면 `AppTheme.light`를 `RoutexTheme.light`로 바꾸고 `_appOwned`를
   지운다.

## 2026-08-17 포팅 갱신

경로 계획·안내와 제품 시트의 공통 문법을 Runtime Kit으로 옮겼다. 상단은
`RoutexSearchBar`/`RoutexRoutePlanner`, 계획은 `RoutexEtaCard`, 시작 뒤에는
`RoutexManeuverBanner` + `RoutexTripProgress`, 도착은 `RoutexArrivalCard`가 맡는다.
목록·헤더·구분선·장소 액션도 각각 Kit 컴포넌트로 통일했다.

전역 테마 판정은 여전히 **아직 아니다**. 남은 이유는 컴포넌트 포팅의 큰 덩어리가 아니라,
지도 그래픽과 아직 앱이 소유하는 UI가 `AppColors` 및 Material theme 슬롯을 함께 읽는다는
점이다. 전역 테마를 먼저 바꾸면 지도 색은 유지되고 주변 앱 UI만 바뀌어 두 팔레트가 선다.

같은 날 Runtime Kit의 버튼·행·경로 패턴에서 누락된 `tap` semantics와
`RoutexListCell` 보조 동작 노드, 캐러셀 목록 교체, 긴 제목 상한도 공급처에서
함께 고쳤다. 즉 남은 판정은 공개 컴포넌트 누락이 아니라 **앱 전용 표현과
전역 테마 전환 시점**이다.

쇼케이스와 제품 화면이 각자 조립하던 장소 상세 첫 구획은
`RoutexPlaceOverview`로 올렸다. 장소 정보 → 출발·도착 → 사진 순서와 간격,
32dp 버튼 시각면/48dp 터치 영역을 이 패턴의 공개 계약으로 두었다. 대중교통
후보도 앱 전용 줄을 제거하고 `RoutexTransitItinerary`에 도메인 데이터만
변환해 넘기도록 통일했다.

상세의 X는 장소 이름 줄 끝에 두고, 공유·저장은 출발·도착 줄 오른쪽에 둔다.
앱은 별도 `SheetHeader`를 얹지 않고 이 공개 overview에 닫기·공유·저장 callback만
넘긴다.

최근 검색과 최근 경로는 `RoutexRecentList`가 같은 history 아이콘·전체 삭제
정렬선·48dp 행을 그린다. 경로 위치 편집은 `RoutexRoutePlanner`의 해당 행
안에서 직접 이뤄지며, 별도 검색 바나 “지도에서 선택” 지름길을 추가하지 않는다.
경로가 계산된 뒤의 계획·안내 진행·도착 표면은 화면 하단에 붙고, 홈
인디케이터 안전 영역은 흰 표면 내부에서 처리한다. 이 경로 작업 상태에서는
카테고리 칩과 위치 지정·보정 컨트롤을 접어 지도·주 행동과 겹치지 않게 한다.

## 이 검토에서 나온 공급처 수정

전환을 시도해 보지 않았으면 못 찾았을 결함이 하나 있었다.

`RoutexTheme.light`는 역할 슬롯 여덟만 채우는데 Material 슬롯은 열다섯이다. 남는 일곱
(`titleLarge`·`bodyLarge` 등)이 기본값으로 남아 **가족이 Roboto**였다. Roboto에는 한글이
없어 그 자리만 시스템 대체 글꼴로 떨어진다. `TextField`의 입력 글자가 `bodyLarge`라
검색창 하나 때문에 한 화면에 두 글꼴이 서는 식이다.

공급처에서 고쳤다(`ThemeData(fontFamily:, package:)`를 함께 준다). 크기·굵기는 Material
기본을 그대로 뒀다 — 남는 슬롯을 우리 역할에 매핑하는 것은 글꼴 결함과 별개 결정이다.

## 글꼴 두 벌은 유지한다

`Pretendard`가 앱 asset과 package asset에 한 벌씩, 합쳐 15.2MB 들어간다. 가이드는 한 벌로
줄일지를 단계 8에서 판단하라고 했고, **판정은 유지**다.

한 벌로 줄이려면 앱 선언을 지우고 앱 텍스트를 전부 package 가족으로 보내야 한다. 그러면
`DefaultTextStyle`을 거치지 않는 자리(`CustomPainter`의 `TextPainter`, 지도 마커 그리기)가
조용히 플랫폼 기본으로 떨어진다. 7.6MB는 앱 크기지 런타임 비용이 아니고, 지금은 데모
직전이다. 계약을 바꿀 이득이 위험보다 작다.

두 벌이 실제로 각각 쓰인다는 사실은 `client/test/core/pretendard_font_assets_test.dart`가
지킨다.
