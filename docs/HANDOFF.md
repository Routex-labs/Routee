# 인계 — 2026-08-14 시점

다른 세션이 이 작업을 이어받을 때 **먼저 읽는 문서**다. 여기는 "지금 어디까지 왔고 다음에
무엇을 하나"만 적는다. 계획·기록의 내용은 각 문서가 단일 출처이므로 링크로 넘긴다.

> **이 문서는 야외 지도 해체 브랜치(`refactor/outdoor-map-decomposition`) 이야기다.**
> 지금 별도로 진행 중인 **디자인 시스템 포팅**(`feat/badge-chip-semantics`)은 여기 없다 —
> 그쪽의 단일 출처는 공급 저장소의
> [포팅 가이드](https://github.com/Routex-labs/routex-design-system/blob/main/docs/navigation-app-porting-guide.md)이고,
> 단계 번호(0~8)는 전부 그 문서를 가리킨다. 전역 테마 전환 판정은
> [전역 테마 넘기기](client/theme-handover.md)에 있고, **폰에서 확인이 남은 것**은
> 아래 [디자인 시스템 브랜치](#디자인-시스템-브랜치--폰에서-확인이-남았다)에 있다.

## 한 줄 요약

야외 지도 갓클래스를 해체하는 중이고, **2026-08-17(월) 현장 검증이 다음 관문**이다.
실내 렌더링은 `starbucks` 검색으로 책상에서 눈으로 확인하며 진행한다(아래 함정 참고) —
현장이 꼭 필요한 것은 GPS 판정·PDR·에스컬레이터뿐이다.

**앱에서 닿지 않던 화면 6개와 실내 전용 도면을 지웠다(5,135줄).** 라우트가 `/` 하나만
남았다. 근거와 판정 방법은 [구조 개편 계획](client/structure-plan.md)의 "문제 4"에 있다.

**계층을 세웠다.** `lib/`의 import 방향을 재 보니 거의 다 맞았고 거꾸로 가는 화살표가
여섯이었다 — 지금은 0이다. `core/`에 쌓여 있던 지도 스타일 18개를 `lib/map/`으로 떼고,
`domain/` 32개를 여섯 갈래(route·guidance·store·search·category·geo)로 묶고, 조립 루트를
`lib/` 최상단으로 올렸다. 방향은 `client/test/lib_layer_direction_test.dart`가 지킨다.
자세한 것은 [구조 개편 계획](client/structure-plan.md)의 12단계.

**주석의 자리를 나눴다.** 파일 머리에 쌓여 있던 설계 서사를 `docs/`로 옮기고 코드에는
요약·계약·링크만 남겼다(머리 주석 10줄 이상 57개 1,122줄 → 38개 463줄, 최장 52 → 19줄).
규칙은 [AGENTS.md](../AGENTS.md)의 "주석 — 어디에 무엇을 쓰나"에 있고 상한은
`client/test/lib_header_comment_length_test.dart`가 지킨다. **주석 총량은 원래 문제가
아니었다** — 우리 비율 28%는 Flutter SDK(material 28.8% · widgets 43.7%)와 같은
대역이고, 문제는 파일을 열 때 코드 첫 줄까지 넘겨야 하는 벽이었다.

## 브랜치는 하나다

```
main
 └─ refactor/outdoor-map-decomposition   (+50)  버그 수정 3 · 갓클래스 해체 · 구조 개편
```

한때 앞 브랜치(`claude/msa-solid-structure-review-ci8j9p*`)가 따로 있었고 병합 순서를
지켜야 했다. 그 커밋들은 지금 이 브랜치 안에 그대로 들어 있고, 앞 브랜치는 로컬·원격
모두 지웠다. **PR은 하나다.**

## 폰에 무엇을 올려 두나

개발 중에는 **이 브랜치**를 폰에 올려 부팅과 로그를 확인한다. 하지만 **월요일 현장
검증은 버그 수정만 들어간 기준선으로 해야 한다** — 검증 대상이 "버그 수정이 실제로
먹었나"이지 해체가 아니고, 해체까지 올린 채로 나가면 문제가 났을 때 원인이 수정인지
해체인지 구분할 수 없다.

그래서 그때 깔려 있던 APK를 그대로 뽑아 두었다.

```
C:\Users\HANSUNG\apk-baseline\field-baseline-msa-branch-1.5.1.apk
```

현장에 나가기 전에 이걸 되돌린다. 빌드가 아니라 **그때 그 바이너리**라 다시 만들 필요가
없다.

```bash
adb install -r "C:/Users/HANSUNG/apk-baseline/field-baseline-msa-branch-1.5.1.apk"
```

## 월요일에 할 일

[현장 검증 체크리스트](client/field-verification-thehyundai.md)가 단일 출처다. 사용자가
폰으로 볼 수 있게 같은 내용을 웹 페이지로도 발행해 두었다(세션 로그의 artifact 링크).

우선순위 둘:

- **03 에스컬레이터** — "1회 탑승에 2층 점프"가 재현되는지와 그때 기압 변화(hPa).
  판정 알고리즘 재작성의 입력이 될 값이라, **고치지 말고 수치만 기록**한다.
- **08 마커 크기** — 층 전환 덮개의 점과 지도 마커가 같은 크기인지. 주석은 "같다"고
  단언하는데 상수를 따라가면 지도 쪽이 2배로 읽힌다. 눈으로 정해야 한다.

## main 최신을 병합했다 (PR #100)

`origin/main`이 [PR #100](https://github.com/Routex-labs/Navigation/pull/100)으로
앞서 나가 있어 병합했다. **rebase가 아니라 merge다** — 우리 브랜치는 공통 조상에서
104 커밋인데 그 사이 147파일을 옮기고 주석을 다시 써서, replay하면 매 커밋이 없는
경로에 부딪힌다. merge는 해결 패스가 한 번이다(충돌 9건).

| 결정 | 근거 |
|---|---|
| `floor_plan_view.dart` **삭제 유지** | 우리가 실내 전용 화면을 없애며 지웠고 참조 0건. main의 189줄 개선은 우리 쪽에 붙을 자리가 없다 |
| 에스컬레이터 모티프 **유지** | main에선 미사용이라 지웠지만 우리는 `parts/ui.dart`가 그린다 |
| place_detail 시간·근처 **main 채택** | 우리 쪽은 경로·포맷만 바뀌었고 main이 UI를 개선했다 |
| 크로스페이드 상수 **main 값** | 300→320 · 600→520 · 6→8단계 |

**받은 새 기능 넷** — 매장 포커스 카메라 단일 이동(520ms), 층 외곽선·scrim 동시
페이드, 카메라 보정 데드밴드 10px, 매장 라벨 우선순위(`map/label/store_label_priority.dart`).

> **한 번 잘못 짚었다.** 처음엔 "main은 고정 시간 이징, 우리는 타일 도착 신호"라고
> 봤는데, 타일 폴링(`querySourceFeatures`)은 **공통 조상에 이미 있었고** main도 그대로
> 쓴다. 비교할 두 아키텍처가 없었다 — main이 한 것은 같은 뼈대 위의 개선이다.
> 브랜치가 크게 갈렸을 때는 "누가 무엇을 새로 만들었나"보다 **공통 조상에 무엇이
> 있었나**를 먼저 봐야 한다.

**아직 실기기에서 못 봤다.** 카메라·전환 연출이 바뀌었으므로 8/17 현장에서 보는
화면은 [baseline APK](#월요일에-할-일)와 다르다. 지금 브랜치를 설치할지는 그때 정한다.

## 방금 끝난 것 — 주석 2차 압축과 폴더 묶기

사용자 지시 둘이었고 **둘 다 끝났다.**

### 1. 주석 2차 압축

| | 시작 | 지금 |
|---|---|---|
| `lib/` 주석 | 12,239줄 (28%) | **9,649줄 (23.6%)** |
| 가장 긴 주석 덩어리 | 39줄 | **13줄** |
| 가장 긴 파일 머리 | 52줄 | **8줄** |

**지운 근거는 없다.** 실측 로그·버린 대안은 전부 문서로 옮기고 코드에는 경로만
남겼다. 새로 만든 문서는 [에스컬레이터 임계값](client/escalator-thresholds.md)
하나이고, 나머지는 기존 문서에 절을 붙였다 — 검색 입력 보조 W절, 검색 결과 목록
X절, 지도 스타일 0·5·7절, 카메라 연출 4.12·4.13, GPS 스트림 3절.

**상한을 조여 뒀다.** `client/test/lib_header_comment_length_test.dart`가 파일 머리
8줄·한 덩어리 13줄을 검사한다. 두 값 모두 **지금 최대치 바로 위**다 — 상한이 실제보다
높으면 그 사이만큼 다시 자란다. 걸리면 지우지 말고 `docs/`로 옮긴다.

> **붙어 버린 주석이 지금까지 일곱 나왔다.** A 선언의 doc이 B 선언 위에 얹힌 자리다
> (`outdoor_map_tuning`의 `carGuidanceZoom`, `outdoor_map_screen.dart`의
> `_pendingFloorFit`, `parts/indoor.dart`의 `_fitCameraToActiveFloor`·
> `_dropIndoorPosition`·`_indoorPositionPlaced`, `map_shell_screen`의 `_startRoute`·
> `_openFavorites`). 마지막 것은 낡기까지 해서 아래 문단과 **서로 반대되는 말**을
> 하고 있었다. 요약 문단이 두 개인 블록을 보면 의심한다.

### 2. 폴더 묶기

다섯 디렉터리를 주제별로 한 겹 더 나눴다. 자세한 것은
[구조 개편 계획 14단계](client/structure-plan.md).

```
models/                      building/ place/ route/
repositories/                building/ place/ routing/     ← models와 같은 이름
map/                         style/ label/ icon/ camera/
screens/map_shell/widgets/   search/ sheets/ chrome/
screens/outdoor_map/         parts/ entry/ gps/ layers/ camera/
```

**본문은 한 글자도 안 바꿨다** — 다섯 커밋에서 바뀐 줄은 전부 import 경로다.
`parts/`에서는 `outdoor_map_screen_` 접두사를 뗐다.

> **다음에 파일을 옮길 때 함께 볼 것.**
> - `lib_layer_direction_test.dart`의 등급표는 경로 **첫 조각**만 본다 — 최상위
>   디렉터리를 바꿀 때만 손대면 된다.
> - **경로를 글자로 박아 둔 테스트**가 있다(`pretendard_font_assets_test`). analyze는
>   통과하고 테스트만 깨지므로 `flutter test`까지 돌려야 보인다.
> - 디렉터리 README의 파일 표와 `docs/`의 경로 문자열이 함께 썩는다. 링크 검사로
>   훑으면 한 번에 잡힌다(이 작업 전후 모두 깨진 링크 8건, 전부 무관한 옛 파일).

> **`dart format`을 전체에 돌리지 말 것.** 이 환경의 포맷터 버전이 저장소와 달라
> 무관한 파일 65개를 쓸고 그중 하나는 lint를 깼다(`if (cond)` 줄바꿈). 건드린
> 파일만 지정해서 돌린다.

## 이어서 할 일

**[구조 개편 계획](client/structure-plan.md)의 12단계까지 끝났다.**
([해체 계획](client/outdoor-map-decomposition.md)은 야외 지도 클래스 내부용으로
따로 남아 있다.)

**남은 것은 결합도 하나다.** 파일은 더 가를 수 있는 데까지 갔다 — 본체 1,967줄에
남은 셋(상태 필드 150개·공개 API 19개·생명주기)은 전부 옮길 수 없는 것들이다
(이유는 아래 "화면 파일이 열두 개로 갈렸다"에).

결합을 낮추려면 **상태를 나눠야 한다.** 필드 150개를 성격별 소유자
(경로 상태 · 실내 오버레이 상태 · PDR 상태)로 갈라 각각을 객체로 만드는 일이고,
그건 옮기기가 아니라 **다시 쓰기**라 축자 이동으로 증명할 수 없다.

**그래서 월요일 현장 데이터가 먼저다.** 지금 상태를 재설계했다가 현장에서
증상이 나오면 원인이 재설계인지 원래 버그인지 구분할 수 없다.

### 대상을 고를 때 — 줄 수로 고르지 말 것

9단계에서 계획서가 틀린 것을 찾았다. "직접 테스트 없는 큰 모듈"로 적어 둔 셋이
전부 이미 테스트를 갖고 있었다(28·36·11 케이스). **줄 수는 테스트 유무를
말해 주지 않는다.**

다시 잰 기준은 "테스트가 **이름조차 언급하지 않는가**"였고, `part` 파일과
위젯을 걸러내니 셋이 남았다. 셋 다 **틀렸을 때 화면에 오류가 안 나는** 코드다 —
실내 북쪽 맞춤, GPS 스트림 수명, 대중교통 표기.

단계마다 쓰는 방식은 같다.

1. **테스트를 먼저 쓴다.** 그리고 **틀린 코드에서 실패하는지 반드시 확인한다** —
   4단계에서 이걸 건너뛰었다가 무력한 테스트를 만들었다(아래 함정).
2. 클래스를 만들고 옮긴다. 옮기면서 고치지 않는다.
3. **원본과 한 줄씩 대조한다.** 3단계에서 이 대조로 조용한 차이 3건을 잡았다 — 테스트로는
   안 잡히는 종류였다.
4. 게이트(계획서)를 통과하면 커밋하고 [이동 대장](client/outdoor-map-moves.md)에 한 줄.

## 화면 파일이 열두 개로 갈렸다

`outdoor_map_screen.dart`(7,567줄)를 성격별 `part` 파일로 갈랐다. **본체 1,967줄,
1,000줄 넘는 part는 하나뿐이다.** 코드는 한 글자도 안 바뀌었다. 어느 파일에
무엇이 있는지는 [이동 대장](client/outdoor-map-moves.md) 맨 위 표에 있고, 못
찾으면 이게 가장 빠르다.

```bash
grep -rn '심볼이름' client/lib/screens/outdoor_map/
```

가르는 기준은 크기가 아니라 **고치는 이유**다. 경로를 만드는 코드는 목적지가
바뀔 때, 따라가는 코드는 걸음이 들어올 때, 그리는 코드는 레이어 순서가 바뀔 때
돈다. 한 파일에 두면 진행률 버그를 고치려는 사람이 TMAP 호출 코드까지 읽는다.

**결합은 그대로다.** 여전히 한 클래스에 필드 150개다 — 읽기 쉬워졌을 뿐이니
"분리가 끝났다"고 읽지 않는다. **파일 분할과 결합도는 별개 축이고, 지금 끝난
것은 앞쪽뿐이다.**

### 본체 1,967줄이 더 안 줄어드는 이유

세 가지가 남아 있고 셋 다 옮길 수 없다.

- **상태 필드 150개** — extension은 필드를 선언하지 못한다. part로 나눠도 필드는
  본체에 남아야 한다.
- **공개 API 19개** — 셸이 `_outdoorKey.currentState?.showRouteTo(...)`처럼 부른다.
  extension으로 옮기면 계약면이 파일 여럿에 흩어지고, `?.` 호출 경로도 위험해진다.
  한곳에 모아 두는 편이 낫다.
- **생명주기·`build`** — `@override`는 extension에서 못 쓴다.

여기서 더 줄이려면 **상태를 나눠야 한다** — 그건 파일 분할이 아니라 결합도 작업이다.

## 이 세션에서 배운 함정

새 세션이 모르면 반드시 한 번은 밟는 것들이다.

**책상에서는 실내 기능을 검증할 수 없다.** GPS 픽스가 들어올 때마다 "건물 안인가"를
판정하는데, 집·사무실 좌표는 `outside`가 확실하므로 실내 오버레이를 끄고 수동 지정한
위치를 버리고 카메라를 GPS로 옮긴다. 화면에서는 "위치가 갑자기 집으로 순간이동"으로
보인다. 버그가 아니다. 사용자가 실내 관련 증상을 보고하면 **어디서 테스트했는지 먼저 묻는다.**

**`flutter run`이 무선 ADB에서 자주 깨진다.** 디버그 서비스 포트 연결이 거부되거나 스트림이
끊긴다. 대신 이렇게 한다.

```bash
flutter build apk --debug --dart-define-from-file=config.local.json
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am force-stop com.navigation.navigation_client
adb shell monkey -p com.navigation.navigation_client -c android.intent.category.LAUNCHER 1
adb logcat -v time flutter:V FlutterError:V AndroidRuntime:E '*:S'   # 로그는 이걸로
```

폰 연결은 Tailscale이다(`adb connect 100.112.176.99:5555`, 포트 고정). 링크가 끊기면
`adb devices`가 offline으로 뜨므로 disconnect 후 재연결한다.

**`config.local.json`은 `D:/Navigation/client/`에 있다.** (사용자는 "e드라이브"라고 말했지만
실제로는 D다.) `.gitignore`라 워크스페이스마다 복사해야 하고, **다른 워크스페이스에서
복사할 때 키가 빠질 수 있다** — 실제로 `KAKAO_REST_KEY`가 없는 사본을 써서 대중교통 버튼이
통째로 사라진 적이 있다. 복사 후 키 4개(`API_BASE_URL` `TMAP_APP_KEY` `KAKAO_REST_KEY`
`VWORLD_API_KEY`)가 다 있는지 확인한다.

**~~에스컬레이터·층 전환 코드는 손대지 않는다.~~ 2026-08-14에 풀렸다.** 사용자가 클라이언트
쪽 층 전이 코드도 건드려도 된다고 정했다. 다만 **백엔드**의 수직 전이 생성
(`scripts/transform/vertical_transfers.py`)은 여전히 재작성 예정이라 그대로 둔다 —
원래 이 금지는 그쪽 얘기였다.

**실내 도면은 책상에서도 눈으로 확인할 수 있다 — `starbucks`를 친다.** `adb shell input
text`는 한글을 못 보내지만 검색이 로마자를 한글로 맞춰 주므로, `starbucks`를 치면
"스타벅스 리저브 · 더현대 서울 · B2"가 1위로 뜬다. 그 줄을 누르면 카메라가 **B2로 층까지
전환**되며 실내 오버레이가 그려진다. 등록·층 전환·강조·라벨·아이콘이 한 번에 눈에 걸리는
가장 싼 검증이다. 절차는 [해체 계획](client/outdoor-map-decomposition.md)에 명령까지 적어 뒀다.

이걸 모르면 "실내는 현장에서만 확인된다"고 착각해 단계마다 검증 없이 넘어가게 된다.
**현장이 꼭 필요한 것은 GPS 판정·PDR·에스컬레이터뿐이다.**

**모의 MethodChannel 핸들러 안의 지연은 가짜 시계를 쓰지 않는다.** `tester.pump`로
앞당길 수 없는 **실제 시계**라, 핸들러에 `Future.delayed`를 넣어 "native가 느리게
응답하는" 상황을 만들 수 없다. 4단계에서 세션 정지 경합을 이 방법으로 재현하려다,
검증하려던 코드를 통째로 지워도 통과하는 테스트를 만들었다. 시간이 걸리는 native 응답에
기대는 동작은 위젯 테스트 말고 **그 조각을 직접 부르는 단위 테스트**로 잡는다
(본보기: `client/test/screens/outdoor_map/pdr_session_lifecycle_test.dart`).

그리고 그 사고의 교훈은 더 일반적이다 — **테스트가 통과하는 것만 보고 넘어가지 않는다.
고치려는 코드를 잠시 망가뜨려 그 테스트가 실패하는지 확인한다.**

## 열려 있는 것

| 항목 | 상태 |
|---|---|
| 출발↔도착 맞바꾸기(⇅)가 안 눌림 | **가설 단계.** `_canSwapRouteEndpoints`가 거짓이면 버튼이 비활성이 되는데, 야외에서 실내 출발지가 비워지고 `_reachByNodeId`도 없으면 그 상태가 된다. 현장에서 "버튼이 흐린지"만 보면 확정된다 |
| 안내 시작 시 위치가 집으로 순간이동 | **설계된 동작**으로 결론. 위 함정 참고. 건물 안에서도 일어나면 별개 버그다 |
| 마커 vs 층 전환 덮개 크기 | 현장 항목 08 |
| 레이어 등록 순서 보장 | `MapLibreMapController`를 흉내 내는 테스트 하네스가 없어 **등록 호출 순서 자체는** 여전히 주석뿐이다. 다만 화면이 깨지는 자리 하나(못 걷는 면이 매장 fill 위·카테고리 강조 아래)는 `indoor_overlay_ids_test.dart`가 목록 순서로 못 박았다 — 근거는 [카카오맵 실내 도면 관찰](client/kakao-map-indoor-observation.md) 3절 |
| GPS 스트림 재시작이 잦다 | 폰 진단 칩에서 3분 만에 `재시작2`가 찍혔다. **부분적으로 설명됐다** — 테스트를 쓰다 보니 벙어리 감시(12초)가 백오프 초기값(2초)보다 길어서, 스트림이 조용하면 감시 쪽이 재연결 주기를 정한다(`gps_session_test.dart`). 즉 "스트림이 죽는다"가 아니라 "좌표가 12초 넘게 안 온다"일 수 있다. **남은 질문은 왜 안 오는가**이고 그건 현장에서 봐야 한다 |

## 검증 명령 (CI와 같은 것)

```powershell
cd client
flutter analyze                                            # 0건이어야 한다
flutter test test/                                         # 1,560개
flutter test integration_test/app_test.dart -d windows     # 부팅 테스트(CI는 linux)
flutter test integration_test/pdr_device_smoke_test.dart -d windows
```

**통합 테스트는 파일마다 따로 준다.** `flutter test integration_test/`처럼 폴더를 주면
두 번째 앱 실행이 `Error waiting for a debug connection`으로 죽는다 — 데스크톱
디바이스가 앱을 연속으로 다시 띄우지 못한다(linux·windows 양쪽에서 재현). CI도 같은
이유로 glob 반복문을 돈다.

> **Windows에서 경로가 길면 통합 테스트가 빌드부터 실패한다** (`MSB3491 ... 260자`).
> `subst X: <워크트리>` 로 짧은 드라이브에 걸고 `X:\client`에서 돌리면 된다.

테스트는 `test/` 한 곳에 있고 **`lib/`의 디렉터리 구조를 그대로 미러한다.** 예전에는
`tests/unit_test/`에 83개가 평면으로 쌓여 있었는데, CI가 그쪽만 돌려서 `test/` 아래
337개가 한 번도 실행되지 않은 적이 있다. **같은 사고가 통합 테스트에도 있었다** —
`client/integration_test/pdr_device_smoke_test.dart`는 CI가 `tests/integration_test/`만
돌려서 main에서 한 번도 실행되지 않았다.

해체 브랜치에서는 여기에 **공개 API 19개 불변** 확인이 더 붙는다(계획서의 게이트).

## 디자인 시스템 브랜치 — 폰에서 확인이 남았다

`feat/badge-chip-semantics`의 **공유 링크 수정 둘은 커밋됐지만, 고친 뒤 실기기에서
보지 못했다**(2026-08-17, 사용자가 야외라 설치할 수 없었다). analyze 무결·1,557개
통과·부팅 테스트 통과까지는 확인했다.

**원인은 로그로 확정했다.** 고치기 전 cold start에서 이렇게 찍혔다.

```
[focus store] 포기: controller=false styleReady=false
[first fix] 첫 좌표로 카메라를 옮긴다        ← 1.7초 뒤
```

공유 링크는 **지도보다 먼저 도착한다.** `focusStore`가 컨트롤러 없이 조용히 포기해,
층 도면과 상세 시트는 매장을 가리키는데 카메라만 첫 GPS 좌표로 갔다.

### 확인 절차

로컬 백엔드를 띄우고([로컬 개발 가이드](guide/local-development-guide.md)) `client/`의
`config.local.json`에서 `API_BASE_URL`을 PC의 Tailscale 주소(`http://100.121.75.43:8001`)로
바꾼 뒤 빌드·설치한다. `PLACE_LINK_ORIGIN`은 **https라야 하고 manifest의 intent-filter
host와 같아야 하므로 Cloud Run 주소 그대로 둔다.**

```bash
ORIGIN=https://navigation-api-465890645804.asia-northeast3.run.app
adb shell am force-stop com.navigation.navigation_client
adb logcat -c
adb shell am start -a android.intent.action.VIEW -c android.intent.category.BROWSABLE \
  -d "$ORIGIN/place/thehyundai-seoul/PO-HU40njvml1512" com.navigation.navigation_client
adb logcat -d -v time flutter:V '*:S' | grep -E "focus store|first fix"
```

**합격 기준: `[first fix]`가 찍히지 않고**, 카메라가 스타벅스 리저브(B2)에 선다.
`PO-HU40njvml1512`가 스타벅스 리저브, `PO--Aksc58lQ1986`이 에르메스 뷰티(1F)다.

### 이미 눈으로 본 것

| 항목 | 결과 |
|---|---|
| 같은 층 매장 링크 | 열림 |
| 실내 진입 후 타 층 | 열림 (B2로 층 전환) |
| 없는 placeId | 다른 매장 안 열고 `장소를 찾을 수 없습니다` |
| 백엔드 증명 파일 둘·fallback 페이지 | 200 |

### 배포 없이는 볼 수 없는 것

OS가 `assetlinks.json`을 받아 가 **링크를 앱에 자동으로 넘기는지**는 Cloud Run에
`links` 라우터를 올려야 판정된다. 지금까지는 `am start`로 intent를 직접 쏘아 앱 쪽
경로만 확인했다 — 카톡에 붙인 링크를 눌러서 앱이 뜨는지는 아직 모른다.
