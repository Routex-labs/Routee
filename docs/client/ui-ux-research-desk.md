# UI/UX 리서치 데스크 — 참고 사이트와 우리 앱의 적용 지점

색·톤을 다시 고르고, 기다림과 터치 횟수를 줄이기 위해 **어디를 보고 무엇을 가져올지**
모은 문서다. 링크만 늘어놓지 않고, 사이트마다 **우리 앱의 어느 미해결 항목에서 여는지**를
붙였다. 어디서도 안 열리는 링크는 넣지 않았다.

- 설명·주석·커밋은 한국어, 코드·식별자는 영어 (AGENTS.md 규칙).
- 다른 UI 문서와 같은 형식을 따른다 — **무엇을 왜 바꾸는지**와 **무엇이 충족되면 맞다고
  볼지**를 담고, 정상 동작보다 **실패 조건을 먼저** 적는다.

---

## 이 문서의 자리

클라이언트 UI 문서가 이미 셋이라, 겹치면 반드시 한쪽이 먼저 썩는다. 경계를 먼저 긋는다.

<table>
<thead>
<tr><th>문서</th><th>다루는 것</th><th>여기서 다루지 <em>않는</em> 것</th></tr>
</thead>
<tbody>
<tr>
  <td><a href="map-ui-redesign-plan.md">지도·상세 UI 개선 계획 (v1)</a></td>
  <td><strong>지도 렌더링</strong> — 폰트·팔레트·마커·경로선</td>
  <td>—</td>
</tr>
<tr>
  <td><a href="naver-map-ui-ux-analysis.md">네이버지도 UI/UX 분석 (v2)</a></td>
  <td><strong>정보 구조와 목록·시트 UX</strong> — 실제 캡처 6장 기반, 도출 작업 A~J</td>
  <td>—</td>
</tr>
<tr>
  <td><a href="map-style-rules.md">지도 스타일 규칙</a></td>
  <td>도면 색·라벨·아이콘의 <strong>확정된 규칙</strong>과 MapLibre 함정</td>
  <td>—</td>
</tr>
<tr>
  <td><strong>이 문서</strong></td>
  <td><strong>재료와 도구</strong> — 어디를 보고, 무엇으로 만들어 보고, 색을 무엇으로 검증하나</td>
  <td>화면별 확정 명세. 그건 위 셋이 단일 출처다</td>
</tr>
</tbody>
</table>

**진행 상태·확정 수치를 이 문서에 적지 않는다.** 여기는 "무엇을 참고했나"만 남기고,
결정이 내려지면 위 세 문서 중 해당하는 곳으로 옮긴다.

---

## 0. HTML을 넣었다 — 어디서 어떻게 보이나

요청대로 표·접기·색 견본을 HTML로 넣었다. **다만 GitHub에서는 일부가 안 보인다.**
쓰기 전에 알아야 나중에 "왜 색이 안 나오냐"로 시간을 버리지 않는다.

<table>
<thead>
<tr><th>요소</th><th>GitHub 웹</th><th>VS Code 미리보기 · Obsidian</th></tr>
</thead>
<tbody>
<tr><td><code>&lt;table&gt;</code> · <code>&lt;details&gt;</code> · <code>&lt;a&gt;</code> · <code>&lt;code&gt;</code></td><td>✅ 그대로</td><td>✅ 그대로</td></tr>
<tr><td><code>style="…"</code> 속성 (색 견본 네모)</td><td>❌ <strong>제거된다</strong></td><td>✅ 보인다</td></tr>
<tr><td><code>&lt;div align="center"&gt;</code></td><td>✅</td><td>✅</td></tr>
</tbody>
</table>

GitHub은 마크다운 안의 HTML을 sanitize하면서 `style`·`class`·`onclick`을 통째로 지운다.
그래서 **색 견본 옆에는 반드시 hex 문자열을 함께 적었다** — 견본이 사라져도 정보가
사라지지 않게. 색을 눈으로 비교해야 할 때는 VS Code 미리보기(<kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>V</kbd>)로 연다.

---

## 1. 지도 앱 전용 패턴 — 가장 먼저 볼 곳

일반 UI 갤러리에는 **지도 위 UI가 거의 없다.** 지도는 배경이 계속 변하고, 콘텐츠와 조작이
같은 평면에 겹치며, 층·줌·현재 위치라는 상태를 동시에 들고 있어야 한다. 그래서 이 한 줄이
아래 모든 갤러리보다 우리에게 값이 크다.

<table>
<thead><tr><th>사이트</th><th>무엇인가</th><th>우리 앱의 어디서 여나</th></tr></thead>
<tbody>
<tr>
  <td><a href="https://mapuipatterns.com/">Map UI Patterns</a></td>
  <td>지도 앱 <strong>전용</strong> 패턴 카탈로그 7장. Michael Gaigg의 책
      <em>Designing Map Interfaces</em>의 온라인판. 무료·로그인 없음 <sub>(확인함)</sub></td>
  <td>아래 표 참조 — 우리 미해결 항목과 거의 1:1로 붙는다</td>
</tr>
</tbody>
</table>

**깊이를 의심해서 본문을 열어 봤다.** 목차만 그럴듯한 책 홍보 페이지일 수 있어서다.
`Floor selector` 한 장이 **1,200~1,500 단어**에 예시 3장(ArcGIS Indoors, Google Maps
대영박물관)과 배치·개수·기본값 규칙을 담고 있다. 홍보물이 아니다.

**그 규칙을 우리 `floor_selector.dart`에 대 봤다.**

<table>
<thead><tr><th>Map UI Patterns의 규칙</th><th>우리 구현</th><th></th></tr></thead>
<tbody>
<tr>
  <td>"버튼 수를 <strong>5개</strong> 정도로 제한하라"</td>
  <td><code>_maxVisibleCells = 5</code></td>
  <td>✅ 우연히 같다</td>
</tr>
<tr>
  <td>"건물의 수직 순서를 흉내 내도록 <strong>화면 아래쪽 모서리</strong>에 두라"</td>
  <td>좌측 하단, 세로 배열</td>
  <td>✅ 맞다</td>
</tr>
<tr>
  <td>"<strong>검색·질의로 특정 층이 지정된 경우가 아니면</strong> 지상층을 기본 선택하라"</td>
  <td><strong>확인 필요</strong> — <code>selectedFloor</code>를 밖에서 받는다</td>
  <td>❓ 호출부를 봐야 안다</td>
</tr>
<tr>
  <td>"대안은 드롭다운. 공간을 덜 먹고 긴 라벨을 담지만 <strong>클릭이 하나 늘고</strong> 선택지가 안 보인다"</td>
  <td>버튼 방식 유지</td>
  <td>✅ 터치를 줄이는 게 목표라 버튼이 맞다</td>
</tr>
</tbody>
</table>

세 줄이 이미 맞다는 건 **이 사이트가 우리 설계를 뒤집지 않는다**는 뜻이기도 하다.
가치는 미해결 항목(아래 표의 `Filters`·`Partial map`)에 있지, 이미 한 곳에 있지 않다.

<details>
<summary><strong>이 사이트의 어느 항목이 우리 어느 문서와 붙나 (펼치기)</strong></summary>

<table>
<thead><tr><th>Map UI Patterns 항목</th><th>우리 쪽</th><th>상태</th></tr></thead>
<tbody>
<tr><td><code>Floor selector</code> (5장)</td><td><code>floor_selector.dart</code></td><td>구현됨. <strong>네이버에 없어 베낄 대상이 없다고 v2가 적어 둔 바로 그 항목</strong> — 여기엔 있다</td></tr>
<tr><td><code>Partial map</code> / <code>Full map</code> (2장)</td><td>v2 <strong>E</strong> — SearchPanel을 바텀시트로</td><td>미착수. 지도와 목록의 면적 배분 문제</td></tr>
<tr><td><code>List and details</code> (6장)</td><td>v2 <strong>F·G</strong> — 결과 행 출발·도착, 목록↔핀 연동</td><td>F의 <code>도착</code>은 완료. G는 E가 선행</td></tr>
<tr><td><code>Filters</code> (4장)</td><td>v2 <strong>H</strong> — 카테고리 필터 위치 <em>(팀 결정 대기)</em></td><td><strong>여기서 결정 근거를 얻을 수 있다</strong></td></tr>
<tr><td><code>Cluster markers</code> (4장)</td><td>v2 G의 실패 조건 — 핀 30개가 한 층에 몰림</td><td>미해결</td></tr>
<tr><td><code>Blue dot</code> · <code>Locate me</code> (5장)</td><td><code>location_marker.dart</code>, PDR 앵커</td><td>구현됨. 정확도 원 표현 재검토용</td></tr>
<tr><td><code>Route directions</code> (6장)</td><td><a href="camera-choreography-plan.md">카메라 연출</a></td><td>진행 중</td></tr>
<tr><td><code>Desert fog</code> (7장)</td><td>결과가 화면 밖에 있는데 지도가 안 움직이는 상태</td><td>v2 G가 다루는 것과 같은 병</td></tr>
</tbody>
</table>

**특히 4장 `Filters`.** v2의 H 항목은 "지도 위 강조를 살릴 것인가, 시트 안 목록으로 갈
것인가"에서 멈춰 팀 결정을 기다리고 있다. 이 장이 정확히 그 선택지를 다룬다.

</details>

---

## 2. 실제 앱 화면 레퍼런스 — "남들은 이 화면을 어떻게 짰나"

v2 문서 마지막에 **"아직 못 본 화면 — 모바일 앱 또는 모바일 웹"**이 남아 있다.
네이버·카카오 도메인은 계정 안전 정책으로 에이전트가 직접 브라우징할 수 없어 캡처를
사람이 떠 왔는데, 아래 사이트들은 **그 캡처가 이미 쌓여 있는 곳**이다.

<table>
<thead><tr><th>사이트</th><th>성격</th><th>비용</th><th>우리에게 쓸모</th></tr></thead>
<tbody>
<tr>
  <td><a href="https://mobbin.com/">Mobbin</a></td>
  <td>실제 앱 스크린샷 60만+ 장. <strong>패턴·플로우·UI 요소별로 검색</strong></td>
  <td>무료 티어 있음 / Pro $10월</td>
  <td>가장 넓다. <code>bottom sheet</code>, <code>search</code>, <code>map</code>으로 검색해 v2 E·F·G의 실제 사례를 본다</td>
</tr>
<tr>
  <td><a href="https://pageflows.com/">Page Flows</a></td>
  <td><strong>동영상</strong>으로 사용자 여정 전체를 녹화. Screenlane이 2024년 합병 후 이 이름</td>
  <td>$99년~</td>
  <td>정지 화면으로는 안 보이는 것 — <strong>전환 애니메이션과 로딩 사이의 빈 시간</strong>. 기다림을 줄이려면 이쪽이다</td>
</tr>
<tr>
  <td><a href="https://mobbin.com/glossary/bottom-sheet">Mobbin — Bottom Sheet 글로서리</a></td>
  <td>바텀시트 변형·detent·모범 사례 정리</td>
  <td>무료로 보이나 <strong>미확인</strong></td>
  <td>v2 <strong>E</strong>의 직접 재료. <strong>단, 아래 주의 참조</strong></td>
</tr>
<tr>
  <td><a href="https://refero.design/">Refero</a></td>
  <td>웹 위주 레퍼런스. Mobbin보다 좁지만 무료 폭이 넓다</td>
  <td>무료 티어</td>
  <td>보조</td>
</tr>
<tr>
  <td><a href="https://www.uplabs.com/">UpLabs</a> · <a href="https://dribbble.com/">Dribbble</a></td>
  <td>디자인 시안 (실제 제품 아님)</td>
  <td>무료</td>
  <td><strong>주의</strong> — 아래 「함정」 참조</td>
</tr>
</tbody>
</table>

> **주의 — Mobbin은 에이전트가 못 읽는다.** `mobbin.com/glossary/bottom-sheet`은
> 자동 조회에 **HTTP 403**을 준다(2026-08-15 확인). 사람 브라우저에서는 열릴 수
> 있으나 확인하지 못했다. **v2 문서의 네이버 절과 같은 상황이다** — 사람이 열어 캡처를
> 전달하는 방식이어야 하고, 그만큼 착수가 사람 손에 묶인다.
>
> 그래서 **바텀시트의 1차 근거는 Mobbin이 아니라 아래 두 원전으로 잡는다.** 둘 다 무료·
> 공개이고 detent(정지 높이) 개념의 출처다.
>
> - <a href="https://developer.apple.com/design/human-interface-guidelines/sheets">Apple HIG — Sheets</a>
> - <a href="https://m3.material.io/components/bottom-sheets/guidelines">Material 3 — Bottom sheets</a>
>   <sub>(JS 렌더링이라 에이전트는 본문을 못 읽는다. 사람이 연다)</sub>
>
> Mobbin은 원전이 정한 형태를 **실제 앱들이 어떻게 쓰는지** 보는 보조로 내린다.

> **함정 — Dribbble류를 그대로 가져오면 깨진다.** 거기 올라오는 지도 앱 시안은 대부분
> 데이터가 5개고, 이름이 짧고, 층이 하나다. 우리는 매장이 수백 개, 이름이
> `마리떼프랑소와저버/LMC`처럼 길고(v2 A의 검증 기준에 그대로 있다), 층이 8개다.
> **레이아웃은 최악의 데이터로 검증하기 전엔 채택하지 않는다.**

---

## 3. 색 — 도구보다 먼저, 지금 팔레트의 실측 대비

색 도구를 열기 전에 **지금 값부터 재는 게 순서다.** 새 팔레트를 고른들 같은 실수를 반복하면
의미가 없다. `client/lib/theme/app_theme.dart`의 값을 WCAG 2.x 대비식으로 직접 계산했다.

> **아래 실측은 2026-08-14 시점이고, 그 뒤 디자인 시스템 포팅이 표의 컴포넌트 일부를
> 걷어 갔다.** `StatusBadge`는 Runtime Kit `RoutexBadge`로 옮기며 지웠고(`status_badge.dart`
> 없음), `AppColors.warning`(`#FBBC04`)도 소비처를 잃어 함께 지웠다. 파일:줄 표기도 그
> 시점 기준이라 지금과 어긋난다. **수치는 남긴다** — 어떤 색이 왜 미달이었는지가 팔레트를
> 다시 고를 때의 근거고, 컴포넌트가 바뀌었다고 그 사실이 달라지지 않는다. 지금 어떤
> 토큰을 쓰는지는 [전역 테마 넘기기](theme-handover.md)가 단일 출처다.

### 3-1. 진단 — 세 곳이 기준 미달이다

<table>
<thead>
<tr><th>쓰이는 곳</th><th>배경</th><th>글자·선</th><th>대비</th><th>필요</th><th>판정</th></tr>
</thead>
<tbody>
<tr>
  <td><code>_FloorChip</code> 선택됨<br><sub><code>floor_selector.dart:202</code></sub></td>
  <td><span style="display:inline-block;width:12px;height:12px;border-radius:3px;background:#6C9BF2;border:1px solid #0003;vertical-align:middle"></span> <code>#6C9BF2</code> <sub>indoor</sub></td>
  <td>흰색 w700</td>
  <td><strong>2.76 : 1</strong></td>
  <td>4.5 : 1</td>
  <td>❌ <strong>미달</strong></td>
</tr>
<tr>
  <td><code>_FloorChip</code> 선택 안 됨<br><sub><code>floor_selector.dart:215</code></sub></td>
  <td>투명 → 흰 카드</td>
  <td>검정 55% <code>≈ #858585</code></td>
  <td><strong>3.69 : 1</strong></td>
  <td>4.5 : 1</td>
  <td>❌ 미달</td>
</tr>
<tr>
  <td><code>FilledButton</code><br><sub><code>app_theme.dart:104-113</code></sub></td>
  <td><span style="display:inline-block;width:12px;height:12px;border-radius:3px;background:#4A87F1;border:1px solid #0003;vertical-align:middle"></span> <code>#4A87F1</code> <sub>primary</sub></td>
  <td>흰색 15px w700</td>
  <td><strong>3.48 : 1</strong></td>
  <td>4.5 : 1</td>
  <td>❌ 미달</td>
</tr>
<tr>
  <td><code>progressIndicator</code><br><sub><code>app_theme.dart:151-153</code></sub></td>
  <td>흰 카드</td>
  <td><span style="display:inline-block;width:12px;height:12px;border-radius:3px;background:#6C9BF2;border:1px solid #0003;vertical-align:middle"></span> <code>#6C9BF2</code></td>
  <td><strong>2.76 : 1</strong></td>
  <td>3 : 1 <sub>(비텍스트)</sub></td>
  <td>❌ 아슬하게 미달</td>
</tr>
<tr>
  <td><code>bodySmall</code> · muted</td>
  <td>흰 카드</td>
  <td><code>#757575</code></td>
  <td>4.60 : 1</td>
  <td>4.5 : 1</td>
  <td>✅ 통과 <sub>(여유 없음)</sub></td>
</tr>
<tr>
  <td><code>bodyMedium</code> 본문</td>
  <td>흰 카드</td>
  <td><code>#212121</code></td>
  <td>16.1 : 1</td>
  <td>4.5 : 1</td>
  <td>✅ 넉넉</td>
</tr>
<tr>
  <td><code>StatusBadge</code><br><sub><code>status_badge.dart:45</code></sub></td>
  <td><span style="display:inline-block;width:12px;height:12px;border-radius:3px;background:#FBBC04;border:1px solid #0003;vertical-align:middle"></span> <code>#FBBC04</code> <sub>warning</sub></td>
  <td>검정 75%</td>
  <td>7.59 : 1</td>
  <td>4.5 : 1</td>
  <td>✅ <strong>여기만 제대로 돼 있다</strong></td>
</tr>
</tbody>
</table>

**가장 아픈 건 첫 두 줄이다.** 층 선택기는 실내 지도 앱에서 *"지금 몇 층인가"*를 알려주는
유일한 장치고, v2 문서가 **"네이버에 없어 우리가 설계해야 한다"**고 못박은 곳이다.
그런데 선택 상태와 비선택 상태가 **둘 다** 기준 미달이다.

> **배경을 확인하고 쟀다.** 층 pill 통은 `Color(0xF2FFFFFF)`(흰색 95%)라 위 계산의
> 흰 배경 가정이 맞다. **다만 `floor_selector.dart`의 헤더 주석은 "어두운
> stadium(약통) 형태"라고 적고 있다 — 코드와 어긋난다.** 언젠가 밝게 바꾸면서 주석을
> 안 고친 것으로 보인다. 이 위젯을 손대는 PR에서 함께 고친다.

### 3-2. 왜 깨졌나 — 12단계로 보면 한 줄로 설명된다

우리 스케일은 `blue50`부터 `blue500`까지 **6칸**이다. [Radix Colors](https://www.radix-ui.com/colors)의
12단계 체계에 얹어 보면 문제가 즉시 보인다. Radix는 **단계마다 용도가 정해져 있다.**

<table>
<thead><tr><th>Radix 단계</th><th>정해진 용도</th><th>우리 스케일</th></tr></thead>
<tbody>
<tr><td><strong>1–2</strong></td><td>앱·카드 배경</td><td><code>blue50</code> <sub>#EEF4FE</sub></td></tr>
<tr><td><strong>3–5</strong></td><td>컴포넌트 배경 (기본 / hover / 선택됨)</td><td><code>blue100</code> <code>blue200</code></td></tr>
<tr><td><strong>6–8</strong></td><td><strong>테두리</strong> (은은한 / 조작 가능 / 강한·포커스 링)</td><td><code>blue300</code> <code>blue400</code> <code>blue500</code></td></tr>
<tr><td><strong>9–10</strong></td><td><strong>단색 배경</strong> — 흰 글자를 얹는 자리 (기본 / hover)</td><td>❌ <strong>없다</strong></td></tr>
<tr><td><strong>11–12</strong></td><td><strong>글자</strong> — 저대비 / 고대비. APCA Lc 60·90 보장</td><td>❌ <strong>없다</strong></td></tr>
</tbody>
</table>

**우리 스케일은 8단계에서 끝난다.** 그런데 `FilledButton`과 `_FloorChip`은 흰 글자를
얹는 **9단계 자리**다. 즉 **테두리용 색을 단색 배경으로 쓰고 있다.** 3-1의 세 실패가
전부 이 한 문장이다 — 개별 실수가 아니라 **스케일에 칸이 비어 있는 것**이다.

**`StatusBadge`만 통과한 이유도 여기서 설명된다.** Radix는 *"대부분의 9단계 색은 흰
글자를 전제하지만 **Sky·Mint·Lime·Yellow·Amber는 어두운 글자를 전제한다**"*고 적는다.
`#FBBC04`는 amber다. 그리고 그 배지는 어두운 글자(검정 75%)를 얹고 있었다 —
**규칙을 몰랐는데 우연히 맞춘 유일한 컴포넌트였다.** (지금은 `RoutexBadge`가 그 자리를
맡고 대비는 Kit의 contrast test가 지킨다.)

그래서 손볼 방향은 둘 중 하나이고, 색마다 다르다.

| 방식 | 어떤 색에 | 우리 적용 |
|---|---|---|
| **배경을 9단계까지 어둡게 + 흰 글자** | 파랑·빨강처럼 어두워질 수 있는 색 | `primary` · `indoor` |
| **밝은 배경 유지 + 어두운 글자** | amber·yellow처럼 어두워지면 색이 죽는 색 | `warning` — **이미 이렇게 돼 있다. 건드리지 않는다** |

### 3-3. 손볼 순서 — 팔레트를 갈아엎지 않는다

파스텔 파랑이라는 방향 자체는 v1·v2가 이미 정한 결정이다. 뒤집지 않고
**어두운 칸 두 개를 스케일에 추가**하는 것으로 끝난다.

<table>
<thead><tr><th>토큰</th><th>지금</th><th>제안</th><th>흰 글자 대비</th><th>쓸 곳</th></tr></thead>
<tbody>
<tr>
  <td><code>blue600</code> <em>(신규)</em></td>
  <td>—</td>
  <td><span style="display:inline-block;width:12px;height:12px;border-radius:3px;background:#3068D4;border:1px solid #0003;vertical-align:middle"></span> <code>#3068D4</code></td>
  <td><strong>5.18 : 1</strong> ✅</td>
  <td><code>FilledButton</code>, <code>_FloorChip</code> 선택됨 — <strong>흰 글자를 얹는 모든 면</strong></td>
</tr>
<tr>
  <td><code>primary</code></td>
  <td><code>#4A87F1</code></td>
  <td>그대로</td>
  <td>3.48 : 1</td>
  <td>선·아이콘·강조 <strong>테두리</strong>는 3:1이면 되므로 지금 값으로 충분하다</td>
</tr>
<tr>
  <td><code>indoor</code></td>
  <td><code>#6C9BF2</code></td>
  <td>그대로</td>
  <td>2.76 : 1</td>
  <td><strong>면(面) 채우기 전용.</strong> 위에 글자를 얹지 않는다</td>
</tr>
<tr>
  <td><code>muted</code></td>
  <td><code>#757575</code></td>
  <td><code>#6B6B6B</code> 검토</td>
  <td>—</td>
  <td>4.60은 통과지만 여유가 0.1이다. 폰트가 한 번만 얇아져도 넘어간다</td>
</tr>
</tbody>
</table>

**최소 합격선은 `#3571E0`(4.57:1)이다.** 그보다 밝으면 무조건 미달이므로, 나중에 누가
"조금만 밝게" 하고 싶어지면 이 값이 벽이다. 여유를 두려고 `#3068D4`를 제안한다.

**실패 조건.**

- `indoor`를 어둡게 바꾸면 **`location_marker.dart`의 실내 파란 점과 지도 위 강조가
  같이 어두워진다.** 지도 그래픽은 UI와 대비 기준이 다르다(WCAG 1.4.11, 3:1). 토큰을
  하나 고쳐 두 곳을 동시에 바꾸지 말고, **면 색과 글자 배경 색을 분리**한다.
- `progressIndicator`를 `primary`로 올리면 3.48:1이라 비텍스트 기준(3:1)은 넘는다.
  다만 **로딩 인디케이터를 잘 보이게 만드는 것보다 안 보이게 만드는 게 낫다** — 7절 참조.
- 지도 도면 색은 <a href="map-style-rules.md">지도 스타일 규칙</a>이 단일 출처다.
  **거기 값을 이 문서에서 바꾸지 않는다.**

### 3-4. 색 도구 — 무엇을 언제 여나

**Radix는 이 표에서 뺐다.** 도구가 아니라 위 3-2의 **진단 틀**로 이미 썼기 때문이다.
읽을 페이지는 <a href="https://www.radix-ui.com/colors/docs/palette-composition/understanding-the-scale">Understanding the scale</a>
한 장이면 충분하다.

**3-1·3-3의 대비 수치는 내가 WCAG 2.x 식으로 직접 계산한 값이다.** 토큰을 확정하기 전에
아래 WebAIM으로 한 번 더 재고, `#6C9BF2`처럼 반투명이 얹힌 색은 합성 결과를 재야 한다.

<table>
<thead><tr><th>도구</th><th>강점</th><th>언제 여나</th></tr></thead>
<tbody>
<tr>
  <td><a href="https://www.figma.com/community/plugin/1034969338659738588/material-theme-builder">Material Theme Builder</a></td>
  <td>씨앗 색 하나로 M3 <code>ColorScheme</code> 전체 생성. <strong>Flutter 코드로 바로 내보낸다</strong></td>
  <td><code>ColorScheme.fromSeed</code>를 이미 쓰고 있다(<code>app_theme.dart:65</code>). 우리가 손으로 덮어쓴 4개가 자동 생성분과 얼마나 어긋났는지 확인</td>
</tr>
<tr>
  <td><a href="https://www.myndex.com/APCA/">APCA Contrast Calculator</a></td>
  <td>WCAG 2.x보다 사람 눈에 가까운 대비 계산. WCAG 3.0 초안</td>
  <td>위 3-1 수치의 <strong>교차 검증.</strong> WCAG 2.x는 특히 파랑 계열을 실제보다 후하게 준다</td>
</tr>
<tr>
  <td><a href="https://webaim.org/resources/contrastchecker/">WebAIM Contrast Checker</a></td>
  <td>hex 두 개 넣으면 AA/AAA 즉답</td>
  <td>가장 빠른 확인. <strong>PR 올리기 전 체크용</strong></td>
</tr>
<tr>
  <td><a href="https://www.realtimecolors.com/">Realtime Colors</a></td>
  <td>고른 색을 <strong>실제 페이지 위에 즉시 입혀서</strong> 보여준다</td>
  <td>표에서 숫자가 통과해도 화면에서 답답할 수 있다. 톤 전체를 눈으로 볼 때</td>
</tr>
<tr>
  <td><a href="https://huemint.com/">Huemint</a></td>
  <td>색마다 <strong>역할</strong>(배경/전경/강조)을 지정하면 조합을 생성</td>
  <td>파랑 말고 다른 방향도 보고 싶을 때. <em>탐색용이지 채택용이 아니다</em></td>
</tr>
<tr>
  <td><a href="https://coolors.co/">Coolors</a> · <a href="https://color.adobe.com/">Adobe Color</a></td>
  <td>범용 팔레트 생성</td>
  <td>보조. 접근성 검증이 약해 위 도구로 다시 재야 한다</td>
</tr>
</tbody>
</table>

---

## 4. 직접 만들어 보는 도구 — 화면을 말로 그려 보기

v2의 H 항목처럼 **"두 안 중 무엇이 나은지 화면을 봐야 정해지는"** 결정이 지금 최소 두 개
막혀 있다. 코드로 두 벌 만들지 않고 먼저 그려 보는 도구들이다.

<table>
<thead><tr><th>도구</th><th>무엇</th><th>비용</th><th>우리 쪽 용도</th></tr></thead>
<tbody>
<tr>
  <td><a href="https://stitch.withgoogle.com/">Google Stitch</a></td>
  <td>Gemini 기반 UI 생성. 말이나 이미지로 화면을 만들고 <strong>Annotate</strong>로 고쳐 나간다. 2026-03 갱신으로 여러 방향을 동시에 뽑는 캔버스가 됐고, <strong>MCP 서버·Claude Code 연동</strong>이 붙었다</td>
  <td>무료 <sub>(Labs, 월 생성 한도)</sub></td>
  <td><strong>1순위.</strong> v2 <strong>H</strong>의 두 안을 각각 그려 놓고 비교한다. 코드까지 안 가도 답이 나온다</td>
</tr>
<tr>
  <td><a href="https://www.figma.com/make/">Figma Make</a></td>
  <td>Figma 안에서 말로 프로토타입 생성</td>
  <td>유료 플랜</td>
  <td>Figma를 이미 쓴다면. 아니면 건너뛴다</td>
</tr>
<tr>
  <td><a href="https://v0.app/">v0</a></td>
  <td>말 → React/Tailwind 코드</td>
  <td>무료 티어</td>
  <td><strong>주의</strong> — 우리는 Flutter다. 나온 코드는 못 쓰고 <em>레이아웃 감</em>만 가져온다</td>
</tr>
<tr>
  <td><a href="https://excalidraw.com/">Excalidraw</a></td>
  <td>손그림 와이어프레임</td>
  <td>무료</td>
  <td><strong>과소평가된 선택지.</strong> 층 선택기·시트 detent처럼 <em>배치</em>만 문제일 때는 AI보다 빠르다</td>
</tr>
</tbody>
</table>

> **Stitch 결과물을 그대로 옮기지 않는다.** 생성기는 우리 제약을 모른다 —
> `forbidden_labels`(영업시간·전화·평점·리뷰)를 화면에 태연히 그려 넣고, 층이라는 축을
> 아예 다루지 않는다. **배치와 위계만 가져오고 내용은 우리 계약으로 다시 채운다.**
> 금지 목록은 <a href="naver-map-ui-ux-analysis.md">v2 문서</a>의 「벤치마크 경계」가
> 단일 출처다.

---

## 5. 원전 — 결정을 근거로 뒷받침할 때

갤러리는 "남들이 이렇게 했다"이고, 아래는 "왜 그래야 하는가"다. PR에서 근거를 대야 할 때
링크할 곳.

<table>
<thead><tr><th>문서</th><th>우리 쪽 연결</th></tr></thead>
<tbody>
<tr>
  <td><a href="https://m3.material.io/">Material Design 3</a></td>
  <td>우리가 실제로 쓰는 체계 (<code>useMaterial3: true</code>). <strong>elevation·상태 레이어·터치 타깃</strong>의 근거</td>
</tr>
<tr>
  <td><a href="https://docs.flutter.dev/ui/design/material">Flutter — Material 문서</a></td>
  <td>M3 문서와 Flutter 구현의 <strong>차이</strong>가 적혀 있다. M3 Expressive는 아직 Flutter에 없다 — 그 컴포넌트를 전제로 설계하면 구현에서 막힌다</td>
</tr>
<tr>
  <td><a href="https://developer.apple.com/design/human-interface-guidelines/maps">Apple HIG — Maps</a></td>
  <td>iOS 빌드가 목표라면. <strong>지도 전용 절이 따로 있다</strong></td>
</tr>
<tr>
  <td><a href="https://developer.apple.com/design/human-interface-guidelines/sheets">Apple HIG — Sheets</a></td>
  <td>v2 <strong>E</strong>의 근거. detent(정지 높이) 개념의 원전</td>
</tr>
<tr>
  <td><a href="https://www.w3.org/WAI/WCAG22/quickref/">WCAG 2.2 Quick Reference</a></td>
  <td>3-1 표의 기준선. 특히 <strong>1.4.3</strong>(텍스트 4.5:1)과 <strong>1.4.11</strong>(비텍스트 3:1)</td>
</tr>
<tr>
  <td><a href="https://lawsofux.com/">Laws of UX</a></td>
  <td>7절에서 쓰는 Doherty·Fitts·Hick 원문 요약</td>
</tr>
<tr>
  <td><a href="https://toss.tech/article/toss-design-system">Toss — 디자인 시스템</a></td>
  <td>한국어 사례. <strong>TDS 자체는 비공개</strong>라 컴포넌트는 못 가져오고 <em>운영 방식</em>만 참고</td>
</tr>
</tbody>
</table>

---

## 6. 지도 4사 관찰 — 무엇을 취하고 무엇을 버리나

**출처 한계를 먼저 적는다.** 아래는 **2차 자료(공개 분석 글·패턴 정리) 기반**이다.
v2 문서의 네이버 절은 사람이 직접 조작하며 캡처한 1차 관찰이지만, 이 표는 그렇지 않다.
**여기서 본 것을 확정으로 옮기려면 실기기 캡처를 먼저 뜬다.**

<table>
<thead>
<tr><th></th><th>결과 목록</th><th>필터</th><th>실내 층</th><th>우리가 취할 것</th></tr>
</thead>
<tbody>
<tr>
  <td><strong>네이버지도</strong></td>
  <td>탭한 자리 <strong>바로 아래</strong>로 펼침 — 시선 이동이 짧다</td>
  <td>업종 기준. 층 필터 없음</td>
  <td><strong>없음</strong> — 매장을 평면 POI로 다룸</td>
  <td>결과 행 정보 구조(v2 <strong>A</strong>, 완료), 시선 이동 최소화</td>
</tr>
<tr>
  <td><strong>카카오맵</strong></td>
  <td>화면 <strong>맨 아래</strong> 고정 탭 — 손이 짧다</td>
  <td>하단 고정</td>
  <td>제한적</td>
  <td><strong>제스처 반응성.</strong> 길찾기 전환에서 <em>로딩보다 움직임이 먼저 보인다</em> — 7절의 핵심</td>
</tr>
<tr>
  <td><strong>Google Maps</strong></td>
  <td><strong>상시</strong> 바텀시트 — 닫히지 않고 접히기만</td>
  <td>시트 안</td>
  <td><strong>있음</strong> — 층 전환 시 <strong>POI 라벨이 함께 바뀐다</strong></td>
  <td>층 선택기 동작. <strong>우리에게 가장 가까운 참고</strong></td>
</tr>
<tr>
  <td><strong>Apple Maps</strong></td>
  <td>검색·제안 <strong>전체</strong>가 시트 안. 최하단에서는 <strong>떠 있는 카드</strong>(모서리 둥글고 아래에 틈)</td>
  <td>시트 안</td>
  <td>제한적</td>
  <td><strong>detent에 따라 모서리·틈이 변한다</strong> — "지금 이게 주인공인가"를 형태로 말한다</td>
</tr>
</tbody>
</table>

**세 가지가 이 표에서 곧장 우리 결정으로 이어진다.**

1. **바텀시트를 상시로 둘 것인가(Google) 걷어낼 수 있게 할 것인가(Apple).** v2 **E**가
   아직 안 정한 지점이다. **우리 답은 Apple 쪽이 맞다** — 지도 자체가 목적지인 실내
   앱이라, 지도를 통째로 볼 수 있어야 한다.
2. **Apple의 detent별 모서리 변화는 우리 `AppElevation` 3단계와 같은 생각이다.**
   그림자 대신 형태로 위계를 말한다. 시트를 넣을 때 `overlay`(8) 한 값으로 끝내지 말고
   **detent에 따라 `chrome`↔`overlay`로 옮기는 것**을 검토한다.
3. **Google의 "층 바뀌면 라벨도 바뀐다"는 우리에게 이미 필요한 동작이다.** v2 **G**의
   실패 조건 — *결과가 여러 층에 걸치면 지금 층에 없는 핀은 못 그린다* — 와 같은 문제고,
   `category_stores_sheet.dart`가 이미 비슷한 처리를 갖고 있다.

**버릴 것.** 네 앱 모두 영업시간·평점·리뷰를 1급 정보로 쓴다. **우리는 코드로 금지돼
있다**(`forbidden_labels`). 그 자리를 우리는 **층·거리·도보시간**으로 채운다 — 그래프에서
직접 계산하므로 출처 문제가 없고, 실내에서는 더 쓸모 있는 값이다.

---

## 7. 기다림과 터치를 줄이는 근거

### 7-1. 시간 기준선 — 숫자부터 정한다

<table>
<thead><tr><th>구간</th><th>사람이 느끼는 것</th><th>해야 할 것</th></tr></thead>
<tbody>
<tr><td><strong>~100 ms</strong></td><td>즉시</td><td>누른 티(press state)는 무조건 이 안에</td></tr>
<tr><td><strong>~400 ms</strong></td><td><strong>Doherty 임계</strong> — 여기 안이면 생각의 흐름이 안 끊긴다</td><td>대부분의 조작이 넘지 말아야 할 선</td></tr>
<tr><td><strong>~1 s</strong></td><td>흐름은 유지되나 <em>기다렸다</em>고 인식</td><td>스켈레톤·낙관적 UI로 자리를 먼저 그린다</td></tr>
<tr><td><strong>~10 s</strong></td><td>주의가 떠난다</td><td>진행률과 <strong>취소</strong>가 필요</td></tr>
</tbody>
</table>

**스피너와 스켈레톤은 쓰임이 다르다.** 스피너는 *"얼마나 남았는지 모른다"*를 말하므로
불확실을 키운다. 스켈레톤은 *"이 자리에 이런 게 온다"*를 미리 말해 기다림을 짧게 느끼게
한다. **자리를 아는 곳엔 스켈레톤, 모르는 곳엔 스피너**가 갈림선이다.

### 7-2. 우리 앱에서 실제로 기다리는 곳

<table>
<thead><tr><th>대기 지점</th><th>지금</th><th>제안</th></tr></thead>
<tbody>
<tr>
  <td>검색 → 결과</td>
  <td>서버 <code>/query</code> (FAISS·KIWI). 네트워크가 실린다</td>
  <td><strong>결과 행 스켈레톤 3줄.</strong> 행 구조가 v2 A로 확정돼 있어 자리를 정확히 그릴 수 있다</td>
</tr>
<tr>
  <td>층 전환</td>
  <td>층 도면 로드</td>
  <td><strong>선택 자체는 0 ms에 반영한다.</strong> chip 강조를 먼저 옮기고 도면은 뒤따르게 — 카카오맵의 <em>"로딩보다 움직임이 먼저"</em></td>
</tr>
<tr>
  <td>경로 계산</td>
  <td><strong>온디바이스 Dijkstra</strong> (<code>domain/dijkstra.dart</code>)</td>
  <td><strong>손대지 않는다.</strong> 네트워크가 없어 이미 400 ms 안이다. <em>여기에 스피너를 붙이면 없던 기다림이 생긴다</em></td>
</tr>
<tr>
  <td>그래프 로드</td>
  <td>서버에서 nodes·edges</td>
  <td>결과 목록의 거리 계산이 여기 묶여 있다(v2 A-2). <strong>거리 줄만 늦게 채우고 목록은 먼저 그린다</strong></td>
</tr>
</tbody>
</table>

> **가장 중요한 줄은 셋째 줄이다.** 경로 계산이 온디바이스라 이미 빠른데, "무거운
> 작업이니 로딩을 붙이자"는 판단이 들어가면 **없던 기다림을 만든다.** 로딩 UI를 붙이기
> 전에 **실제 소요를 먼저 잰다** — 400 ms 아래면 아무것도 붙이지 않는 게 정답이다.

### 7-3. 터치 횟수

- **`_FloorChip` 터치 타깃이 작다 — 재 봤다.** `floor_selector.dart`의
  `_cellHeight = 36`, `_pillWidth = 44`인데, `_FloorChip`이 다시
  `EdgeInsets.symmetric(horizontal: 4, vertical: 2)`를 두른다. 그래서 `InkWell`이
  실제로 받는 영역은 **32 × 36 dp**다.

<table>
<thead><tr><th></th><th>지금</th><th>권장 최소</th><th>판정</th></tr></thead>
<tbody>
<tr><td>세로</td><td><strong>32 dp</strong></td><td>44~48 dp</td><td>❌ 미달</td></tr>
<tr><td>가로</td><td><strong>36 dp</strong></td><td>44~48 dp</td><td>❌ 미달</td></tr>
</tbody>
</table>

  층이 8개라 세로로 좁히고 싶은 압력이 크고, 가장 먼저 희생된 게 이 값이다.
  **시각 크기는 그대로 두고 터치 영역만 넓힌다** — Flutter는 둘을 분리할 수 있다
  (`InkWell`을 `SizedBox`로 감싸는 대신 `MaterialTapTargetSize` 또는 투명 여백을
  `InkWell` *안쪽*에 둔다). 3-1의 대비 문제와 **같은 위젯**이므로 한 PR에서 함께 간다.
- **엄지 영역.** 화면 아래 1/3이 편하고, **위쪽 두 모서리가 가장 멀다.** 우리 검색창은
  상단이다 — 검색은 **입력하러 갈 때 한 번만 닿으면 되므로** 그대로 둔다. 반면 층
  선택기와 결과 목록은 **이동 중에 반복해서** 닿으므로 아래쪽·측면이 맞다.
- **~~가장 큰 절감은 이미 문서에 있다.~~ 했다(2026-08-21).** v2 **F**의 `도착`이
  결과 줄과 후보 줄에 붙어 검색 → 안내가 4탭에서 3탭이 됐다. `출발`은 Kit 제약으로
  남았다(v2 F 항목).
- **다음 절감 후보**는 카테고리 목록에서 **두 번째** 매장을 보는 길이다 — 상세를 닫아도
  목록으로 안 돌아오고, 칩을 다시 누르면 먼저 해제돼서 매장 하나당 네 탭이 더 든다.

---

## 8. 실패 조건 — 이 문서 자체의

- **링크가 죽는다.** 특히 4절의 AI 도구는 수명이 짧다. **링크가 열리지 않으면 그 줄을
  지운다.** 죽은 링크를 남기면 다음 사람이 그것부터 확인하느라 시간을 쓴다.
- **3-1의 대비 수치는 코드가 바뀌면 곧바로 틀린다.** 토큰을 고치는 PR에서 이 표를 함께
  고친다. 자동으로 지키려면 `test/theme/` 아래에 대비 테스트를 두는 편이 낫고, 그때는
  **테스트가 단일 출처가 되고 이 표는 지운다**(AGENTS.md — 검증 기준 표는 테스트가 단일 출처).
- **6절은 2차 자료다.** 1차 캡처로 확인하기 전에는 여기 있는 것을 근거로 코드를 바꾸지
  않는다.
- **이 문서는 결정을 담지 않는다.** 무언가 정해지면 v1·v2·지도 스타일 규칙 중 맞는 곳으로
  옮기고 여기서는 지운다. 두 곳에 남기면 한쪽이 먼저 썩는다.

## 9. 다음 작업

순서에 근거가 있는 것만 적는다.

1. **스케일에 9·11단계를 추가한다.** 3-2의 진단이 개별 버그가 아니라 **빈 칸** 하나를
   가리키므로, 이게 나머지 전부의 선행이다. `blue600`(#3068D4) 추가 —
   Radix로 치면 9단계다. 읽을 것은
   <a href="https://www.radix-ui.com/colors/docs/palette-composition/understanding-the-scale">Understanding the scale</a>
   한 장.
2. **`floor_selector.dart` 하나를 고친다 — 대비·터치 타깃·낡은 주석을 함께.**
   실내 앱에서 가장 중요한 표시가 **가장 안 읽히고**(2.76:1 / 3.69:1)
   **가장 누르기 어렵다**(32×36 dp). 여기에 헤더 주석의 "어두운 stadium"이 실제
   `0xF2FFFFFF`와 어긋난다. 셋 다 같은 파일이라 한 PR이다.
3. **`FilledButton`을 `blue600`으로.** 1번 토큰을 그대로 쓴다.
4. **검색 결과 스켈레톤.** 행 구조가 v2 A로 확정돼 있어 지금 할 수 있다.
5. **v2 H를 결정한다** — <a href="https://mapuipatterns.com/">Map UI Patterns</a>
   4장 `Filters`. 팀 결정 대기로 멈춰 있는 유일한 항목이다. 다만 `Floor selector`를
   대 보니 우리 설계와 이미 세 줄이 맞았으므로, **판을 뒤집기보다 결정을 확인해 주는
   쪽**일 가능성을 염두에 둔다.
6. **v2 E(바텀시트)를 설계한다.** 근거는 Apple HIG Sheets → Material 3 순으로 읽고,
   Mobbin은 **사람이 열어 캡처를 떠 와야** 쓸 수 있다(403). E는 v1 7번과 함께 설계해야
   하므로 이 중 가장 무겁다 — 그래서 마지막이다.
