# PDR 경로 추종·층 전환 개선 계획

- 작성일: 2026-08-06
- 상태: Phase 1~5 구현 및 iOS 실기기 검증 완료 (Phase 0 fixture 분리·Android·A/B replay는 남음)
- 범위: Flutter 클라이언트 PDR·경로 진행·에스컬레이터 상태기·전환 UI

이 문서는 실측에서 확인된 다음 문제를 해결하기 위한 클라이언트 중심 구현 계획이다.

- 회전 지점보다 조금 일찍 또는 늦게 꺾으면 PDR 마커가 코너에서 멈추는 문제
- 간선 내부에서 연속적으로 이동하고 있는데도 회전 후보가 노드 통과 시점까지 열리지 않는 문제
- 실시간 preview가 pedometer batch 시점에 다시 묶여 느리거나 뒤로 가는 문제
- 가까운 평행 간선으로 대표 후보가 바뀌면서 불필요한 재탐색이 발생하는 문제
- 에스컬레이터 탑승 배너와 층 지도 전환이 같은 고도 임계값에서 동시에 시작하는 문제
- 에스컬레이터 하차 뒤 PDR 재개가 느리고, 탑승 중 live heading이 화면과 다음 간선 판정에
  충분히 활용되지 않는 문제
- 층 전환 배너와 veil이 상위 검색·카테고리 UI에 가려지는 문제

이번 계획은 navigation graph 전체를 다시 만들거나 모든 간선의 형상점을 보완하는 작업을 포함하지
않는다. 현재 graph에 존재하는 노드와 간선을 이용해 클라이언트의 시간 상태와 전환 허용 범위를
개선하는 데 집중한다.

경로 계산은 계속 Flutter 클라이언트의 Dijkstra가 담당한다. 서버로 PDR 위치 계산이나 재탐색
판정을 옮기지 않는다.

---

## 1. 이번 계획의 범위

### 1.1 포함

- 간선 내부 `double progress` 기반 연속 위치 유지
- confirmed와 optimistic preview cursor 분리
- accel peak 식별자를 이용한 배치 독립 preview
- 기존 graph node 주변의 `junction transition zone`
- 회전점보다 2~3m 빠르거나 늦은 회전 허용
- junction 안에서 제한적인 임시 2차원 위치 표시
- junction 통과 중 재탐색 억제와 후보 안정화
- 에스컬레이터 탑승·수직 이동·중간 전환·하차 상태 분리
- 위치에 적용하는 걸음과 하차 판정용 raw motion 분리
- 에스컬레이터 탑승 중 heading frame·snapshot·방향 원뿔 유지
- 하차 후 첫 1~2걸음으로 다음 간선 후보 선택
- 전환 배너와 veil을 `MapShellScreen` 최상위 UI로 이동
- 단위·replay·widget·실기기 검증

### 1.2 이번 구현에서 제외

- 모든 간선의 `geometry_local_m`을 사람이 새로 찍는 작업
- 지도 도면에서 복도 중심선을 자동 추출하는 작업
- PDR 로그 한 건으로 graph 형상을 자동 생성하는 작업
- graph에 존재하지 않는 갈림길이나 벽을 클라이언트가 추측하는 작업
- 백엔드 seed 전체 재작성
- `corridor_group_id` API와 데이터 구축

`corridor_group_id`는 가까운 평행 간선을 같은 복도로 취급하는 가장 안전한 장기 해법이지만, 사람이
검토한 데이터가 필요하다. 처음 요청도 구현이 아닌 의견 범위였으므로 이번 필수 구현에서는 제외하고
후속 결정 사항으로 남긴다.

### 1.3 알려진 한계

다음 데이터 오류는 클라이언트만으로 정확히 해결할 수 없다.

- 실제 복도는 휘었지만 graph는 긴 직선 간선 하나뿐인 경우
- 실제 갈림길이 graph node와 edge로 존재하지 않는 경우
- 연결 관계가 잘못돼 실제로 갈 수 있는 outgoing edge가 없는 경우
- 서로 다른 통로가 graph에서 잘못 연결된 경우

이 경우 tracker는 없는 topology를 생성하지 않는다. 실측에서 반복되면 진단 로그에
`graphMismatchSuspected`를 남겨 별도 데이터 작업 후보로 분류한다. 이 후보를 자동으로 graph에
반영하지 않는다.

---

## 2. 실패 조건부터 정의

다음 중 하나라도 발생하면 구현이 완료된 것으로 보지 않는다.

### 2.1 회전·위치

- confirmed 또는 preview 걸음이 계속 들어오는데 표시 위치가 한 보폭 이상 같은 자리에 머문다.
- 기존 graph node 기준 2~3m 일찍 또는 늦게 회전하면 연결된 outgoing 후보가 사라진다.
- 교차로에서 걸음 없이 휴대폰만 돌렸는데 다른 간선으로 위치가 전환된다.
- junction과 무관한 위치에서 가까운 평행 간선으로 순간이동한다.
- junction 임시 위치가 허용 반경 밖으로 무제한 이동한다.
- 안내 경로가 tracker 후보 점수에 들어가 실제 이탈을 파란 경로 위로 숨긴다.

### 2.2 실시간 preview

- 새 accel peak가 없고 pedometer batch만 들어온 프레임에서 preview 위치가 뒤로 간다.
- 같은 peak 시계열을 서로 다른 batch 크기로 나눴을 때 표시 위치 시계열이 달라진다.
- `fullLeadM` clamp가 이미 표시한 정상 preview 위치를 잘라낸다.
- confirmed batch가 같은 peak를 optimistic cursor에 두 번 적용한다.
- 오래된 preview cursor를 무조건 유지해 실제 유턴이나 대표 간선 변경을 반영하지 못한다.

### 2.3 재탐색·평행 간선

- junction 후보 비교 중인 짧은 시간에 간선 ID가 달라졌다는 이유만으로 재탐색한다.
- 대표 간선이 한 프레임 흔들린 것만으로 기존 경로를 교체한다.
- 실제로 다른 복도로 계속 걸었는데 junction 보호가 영구히 유지돼 재탐색하지 않는다.
- 같은 복도라는 데이터가 없는데 거리만 보고 두 평행 간선을 영구적으로 동등 취급한다.

### 2.4 에스컬레이터

- 배너와 목적 층 지도 전환이 모두 `|delta| >= 1.8m`에서 동시에 시작한다.
- 접근만 했는데 수직 이동 근거 없이 목적 층 지도가 열린다.
- 에스컬레이터 진동 peak가 하차 걸음으로 오인돼 이동 중간에 PDR이 재개된다.
- 정상 하차 뒤 iOS 저속 기압 샘플 두 개 이상을 항상 기다려 2초 이상 멈춘다.
- 탑승 중 heading sensor 또는 heading frame을 초기화한다.
- 목적 층 도면을 먼저 연 뒤 출발 층 axes로 heading을 그려 방향이 틀어진다.
- 취소·오류 경로 중 하나에서 PDR 걸음 적용이 pause 상태로 남는다.

### 2.5 UI

- 출발/도착 검색창과 카테고리 두 줄이 떠 있을 때 전환 배너가 가려진다.
- 층 교체 veil이 지도만 덮고 앱 UI 아래에 깔려 전환 사실이 보이지 않는다.
- 전환 중 가려진 검색·층 선택·하단 버튼이 뒤에서 눌린다.
- 지속적인 탑승 전체를 modal로 막아 사용자가 지도를 전혀 볼 수 없다.

---

## 3. 완료 판정 기준

| 영역 | 완료 기준 |
|---|---|
| 간선 내부 이동 | 간선 길이 전체에서 `double progress`로 연속 위치를 표시하며 노드에만 스냅하지 않는다. |
| 빠른·늦은 회전 | 기존 graph node 기준 -3m/0m/+3m 회전 입력에서 2~3걸음 안에 연결 간선으로 수렴한다. |
| 정지 방지 | 걸음이 들어오는 동안 표시 위치의 무이동 누적이 1.2m를 넘지 않는다. |
| 위치 연속성 | 정상 preview→confirmed 승격 시 화면 후퇴 0.3m 이하, 일반 갱신 점프 2m 이하이다. |
| 배치 독립성 | 같은 peak 입력은 batch 구성과 무관하게 같은 optimistic 위치 시계열을 만든다. |
| junction 안전 | 임시 자유 위치는 node 주변 제한 반경에만 존재하며 연결 edge만 후보로 사용한다. |
| 재탐색 | junction 보호는 짧은 상태로 끝나며 실제 이탈은 기존 evidence 뒤 재탐색한다. |
| 탑승 UI | 활성 경로의 탑승점 도달을 감지하면 지도 전환 문턱(`minDeltaM`)에 닿기 전에 배너가 보인다. |
| 층 전환 | 기존 고도·ramp 조건을 통과한 `midpointReached`에서만 목적 층 지도를 연다. |
| 하차 재개 | 정상 하차는 첫 유효 저속 고도 샘플 또는 약 1초 안에 PDR 적용을 재개한다. |
| heading | 탑승 중 의미 있는 2° 이상 변화가 500ms 안에 고정 마커 원뿔에 반영된다. |
| 오탐 복구 | 후보 취소 뒤 1초 안에 층·경로·표시 위치·걸음 적용을 복원한다. |
| UI 가시성 | 최악 높이의 상단 UI와 ETA 카드가 있어도 배너와 veil이 다른 UI에 가려지지 않는다. |

수치는 실측 replay를 통과하기 위한 시작 기준이다. 임계값을 바꿀 때는 해당 fixture와 근거를 함께
갱신한다.

---

## 4. 현재 구조와 원인

### 4.1 간선 위치는 이미 연속값이다

`CorridorPositionTracker`는 `currentEdgeProgressM`을 `double`로 보관하고
`_CorridorEdge.pointAt(distanceM)`으로 간선 위 임의 위치를 계산한다. 현재 문제는 노드 사이 위치를
찍지 못하는 것이 아니라, 회전 후보가 열리는 시점과 preview 상태가 지연되는 것이다.

관련 파일:

- `client/lib/features/indoor_navigation/application/corridor_position_tracker.dart`
- `client/lib/features/indoor_navigation/application/corridor_tracking_session.dart`

### 4.2 다른 간선 후보는 끝 노드를 넘은 뒤에만 열린다

현재 `_advance`는 보행 거리가 `distanceToEnd`를 넘은 뒤에 끝 노드의 연결 간선을 후보로 만든다.
사람은 graph node 좌표를 정확히 밟지 않고 코너 안쪽을 자르거나 바깥쪽으로 돌아갈 수 있으므로
실제 방향 전환과 후보 생성 시점이 어긋난다.

### 4.3 preview는 살아 있는 cursor가 아니다

현재 preview는 snapshot마다 confirmed 1등 가설에서 다시 만들고 `_previewLeadM` scalar로 이전
선행분을 흉내 낸다. `stabilizePreviewLeadM`이 마지막에 `fullLeadM`으로 clamp하므로 새 preview
tail이 짧아지는 batch 프레임에서 이미 표시한 선행분이 잘릴 수 있다.

clamp만 제거해서는 해결되지 않는다. `_previewPath` 자체가 `fullLeadM`까지만 존재하므로 숫자를
크게 유지해도 이후 위치를 그릴 수 없다. preview를 persistent optimistic cursor로 바꿔야 한다.

### 4.4 재탐색은 정확한 edge id를 본다

`RouteProgress.onRouteEdge`는 current edge id가 route edge 집합에 있는지로 계산된다. 정확한 판정은
유지해야 하지만 junction에서 후보가 갈리는 짧은 구간까지 즉시 이탈 증거로 쓰면 정상 회전 중
재탐색이 발생할 수 있다.

이번 구현은 같은 복도를 자동 추론하지 않는다. junction state와 leader 안정화 시간에만 재탐색을
일시 유예한다.

### 4.5 에스컬레이터 첫 UI 이벤트가 이미 중간 고도다

`EscalatorTransitionDetector`는 경로와 node 근접을 내부 `armed`로 보관하지만, UI에 전달하는
`startedTransition`은 `|delta| >= minDeltaM`(당시 1.8m)와 ramp 조건 뒤에 생성한다. 화면은 이 이벤트로
배너, PDR pause, 목적 층 지도 교체를 연달아 수행한다.

### 4.6 heading은 살아 있지만 화면에서 가려진다

`pauseStepTracking`은 native source를 끄지 않고 위치에 적용하는 걸음만 차단한다. `PdrSession`도
걸음이 없는 동안 의미 있는 heading 변화를 snapshot으로 보낸다. 그러나 탑승 중 pending marker에는
heading 원뿔을 전달하지 않고 route progress도 중단한다.

하차 빠른 확정은 새 걸음과 저속 고도가 겹치면 한 샘플만 요구하지만, detector가 보는 값은 pause된
적용 걸음 수다. 탑승 중 증가하지 않기 때문에 이 빠른 경로가 동작하지 않고 저속 기압 샘플 두 개를
기다릴 수 있다.

### 4.7 배너의 z-order가 낮다

배너와 지도 veil은 `IndoorMapBody` 안에 있고 검색창·카테고리·하단 바는 부모 `MapShellScreen`이
나중에 그린다. 자식의 `top` 상수를 조정해도 부모 sibling 위로 올라갈 수 없다.

---

## 5. 확정 설계

### 5.1 persistent optimistic preview

confirmed와 preview를 하나의 beam 재구축 결과로 만들지 않는다.

```text
confirmed beam   = pedometer batch가 확정한 authoritative 위치
optimistic beam  = accel peak가 생긴 즉시 한 번만 전진한 화면 위치
```

preview peak가 나중에 batch에서 확인돼도 optimistic beam을 다시 전진시키거나 뒤로 보내지 않는다.
대표 간선이 실제로 달라졌을 때만 명시적인 reconcile을 한다.

### 5.2 junction transition zone

기존 graph node 중 방향 선택이 생기는 지점에만 제한된 전환 구간을 계산한다.

```text
incoming edge ─── [ junction transition zone ] ─── outgoing edge
```

- node까지 약 2~3m 이내에서 연결된 outgoing 후보를 미리 연다.
- node를 거리상 통과한 뒤에도 약 2~3m 동안 incoming 방향 증거를 잠시 유지한다.
- zone 안에서만 raw PDR 증분을 이용한 임시 2차원 marker 위치를 허용한다.
- 임시 위치는 node 중심 제한 반경 밖으로 나가지 못한다.
- permanent walked trail은 outgoing 후보 확정 뒤 graph 연결 path로 다시 만든다.
- 후보는 해당 node에 실제로 연결된 edge만 사용한다.
- zone 밖에서는 기존 edge progress와 graph 제약으로 즉시 돌아간다.

이 임시 위치는 geometry를 새로 추측하기 위한 것이 아니다. 사람이 넓은 코너 안쪽이나 바깥쪽에서
회전하는 짧은 구간 동안 marker가 node에 멈춰 보이지 않게 하는 표시·상태 완충 영역이다.

### 5.3 안내 경로와 tracker의 단방향 관계

tracker는 graph와 센서만 보고 위치를 계산한다. 안내 경로는 tracker 결과를 받아 진행률과 재탐색만
판단한다.

```text
센서 + graph → tracker → route progress → UI/재탐색
                           └─ tracker로 역주입 금지
```

junction state 동안 재탐색을 유예할 수는 있지만 route edge를 tracker 후보에서 우선하지 않는다.

### 5.4 에스컬레이터 다단계 상태

```text
boardingDetected
    ↓ 배너·표시 위치 안정화
verticalMotionDetected
    ↓ 위치에 적용하는 걸음 차단
midpointReached
    ↓ 목적 층 지도 전환
landed
    ↓ 새 anchor·PDR 즉시 재개
```

배너, 걸음 pause, 층 전환, 하차 재개가 서로 다른 근거와 시점을 사용한다.

### 5.5 live heading 유지

- native source와 heading frame을 층 전환 전체에서 유지한다.
- 목적 층 도면을 연 뒤에는 이전 rotation과 목적 층 axes로 같은 heading을 다시 투영한다.
- pending arrival marker에도 heading 원뿔을 표시한다.
- 하차 후 outgoing edge는 heading을 soft prior로, 첫 preview 걸음 방향을 강한 근거로 선택한다.

### 5.6 전환 UI 소유권

- detector는 pure phase와 근거를 application 계층에 제공한다.
- `IndoorMapBody`가 `FloorTransitionUiState`를 부모에게 전달한다.
- `MapShellScreen`이 배너를 root Stack 최상위에서 렌더링한다(전체 화면 veil은 Phase 5에서
  걷어냈다).
- UI는 detector 임계값을 다시 계산하지 않는다.

---

## 6. 구현 단계

### Phase 0 — 실측 실패 재현

> **상태**: 진단 schema만 확장했다(v13). 실측 세션 확보와 fixture 분리는 실기기
> 작업이라 남아 있다. 코드 변경 전 실패 재현은 합성 회귀 테스트로 대체했다 —
> 조기/정시/지연 회전, 배치 크기별 preview 시계열, 단계 분리, 원시 하차 근거가
> 각각 단위 테스트로 고정돼 있다.

#### 작업

1. 다음 실제 세션을 진단 JSON으로 확보한다.
   - 기존 node보다 일찍 회전
   - node 근처에서 회전
   - node보다 늦게 회전
   - 평행 간선 후보 교체 뒤 재탐색
   - 에스컬레이터 접근부터 하차 첫 걸음까지 포함한 상행·하행
2. 기존 debug graph overlay로 보고된 회전 지점에 node와 연결 edge가 있는지만 확인한다.
3. 별도 graph 편집·검수 화면은 만들지 않는다.
4. 진단 schema에 다음 값을 추가한다.
   - preview peak id/timestamp와 confirmed acknowledgement 시각
   - confirmed/optimistic cursor의 edge와 progress
   - junction zone 진입·후보·확정·실패 사유
   - 에스컬레이터 공개 phase와 phase별 시각
   - raw motion activity와 실제 적용 걸음 수

#### 통과 조건

- 코드 변경 전 정지·후퇴·배너 지연·하차 지연을 replay가 재현한다.
- 회전 지점에 graph node가 없는 fixture는 `graphMismatchSuspected`로 분리한다.
- 클라이언트로 해결할 fixture와 데이터 한계를 수치로 구분한다.

---

### Phase 1 — 배치 독립 persistent optimistic preview

> **상태**: 완료. `stabilizePreviewLeadM`과 `fullLeadM` clamp를 제거하고
> `_optimisticBeam` + peak 식별자로 대체했다. 선행분은 별도 scalar가 아니라
> optimistic·confirmed 누적 거리의 차이로 정의된다.

#### 제거 대상

- `_previewLeadM` scalar를 유일한 실시간 위치 상태로 쓰는 방식
- 매 snapshot마다 confirmed 1등에서 preview를 처음부터 재구축하는 방식
- `stabilizePreviewLeadM(...).clamp(0, fullLeadM)`으로 선행분을 보존하는 방식

먼저 clamp만 지우는 중간 구현은 허용하지 않는다. 새 cursor와 replay가 준비된 뒤 기존 함수를
제거한다.

#### 입력 계약

`CorridorObservation`에 안정적인 preview peak 식별자를 포함한다.

```dart
class TimedPreviewStep {
  final int peakTimeMs;
  final PdrLocalPoint rawPoint;
}

class CorridorObservation {
  // 기존 필드...
  final List<TimedPreviewStep> previewSteps;
  final int? confirmedThroughMs;
}
```

- accepted peak timestamp를 우선 식별자로 사용한다.
- timestamp가 없으면 세션 내부 증가 sequence를 쓰고 진단 warning을 남긴다.
- graph·anchor·PDR session reset에서 두 beam과 식별자 상태를 함께 초기화한다.

#### 상태

```text
confirmed beam
optimistic beam
seen preview peak ids
confirmed/acknowledged peak ids
last published optimistic cursor
```

#### 갱신 순서

1. 최신 heading을 공통 sensor 상태에 반영한다.
2. 새 confirmed batch를 confirmed beam에 적용한다.
3. `confirmedThroughMs` 이하 peak를 acknowledged로 표시한다.
4. 아직 optimistic beam에 적용하지 않은 preview peak만 시간순으로 한 번 적용한다.
5. batch가 확인한 peak를 optimistic beam에 다시 적용하지 않는다.
6. 두 beam이 같은 graph 연속 경로이면 optimistic cursor를 그대로 유지한다.
7. confirmed leader가 충분한 margin으로 다른 간선을 선택한 경우에만 reconcile한다.

#### reconcile

- 같은 edge/direction 또는 기존 optimistic path의 연속 suffix면 표시 위치를 유지한다.
- junction zone 안의 후보 변경이면 zone 내부 path만 다시 만든다.
- 그래프로 도달할 수 없는 leader 변경이면 `leaderRelocated`를 기록하고 제한된 보정을 적용한다.
- 실제 유턴 heading과 걸음이 있으면 optimistic cursor의 후퇴를 허용한다.
- batch 수신 자체는 marker 이동 이벤트가 아니다.

#### 테스트

- preview p1,p2 → batch p1 → batch p2에서 marker cursor 불변
- preview에 없고 batch에만 나타난 걸음을 두 beam에 한 번 적용
- 중복 peak timestamp 무시
- 누락 timestamp fallback
- 1·4·10걸음 batch 구성별 동일 optimistic 시계열
- 회전 직전 preview와 회전 직후 confirmed의 후보가 다른 경우
- 유턴과 leader relocation

---

### Phase 2 — junction transition zone

> **상태**: 완료. 다만 **자유 2차원 임시 marker는 만들지 않았다.** 회전 가설이
> 실제 연결 간선 위 연속 progress로 움직이므로 "코너에서 멈춘다"는 증상은 그대로
> 해결되고, 그래프 제약을 벗어난 위치를 만들지 않는 쪽이 안전하다. zone 구간의
> 궤적은 복도를 따라 촘촘히 샘플해 이어 붙이고, 지나쳐서 되돌아온 경우에는 그
> 사이 꼬리를 지운다.
>
> `JunctionTransitionWindow`·`JunctionTransitionState`는 별도 타입 대신
> `CorridorTrackingResult`의 `junctionNodeId`·`junctionDistanceM`·
> `junctionCandidateEdgeIds`로 노출한다.

#### 모델

```dart
class JunctionTransitionWindow {
  final String nodeId;
  final String incomingEdgeId;
  final double radiusM;
  final List<String> connectedOutgoingEdgeIds;
}

class JunctionTransitionState {
  final JunctionTransitionWindow window;
  final PdrLocalPoint entryPoint;
  final PdrLocalPoint temporaryPosition;
  final List<String> candidateEdgeIds;
  final int enteredAtMs;
}
```

반경 초깃값은 2~3m로 두되 다음 값으로 상한을 제한한다.

- 현재·다음 edge 길이의 일정 비율
- 이웃 junction까지 거리의 절반
- 한 snapshot에서 설명 가능한 보행 거리

#### 빠른 회전

- incoming edge에서 node까지 남은 거리가 반경 안이면 connected outgoing 가설을 미리 만든다.
- 걸음별 방향 변화가 outgoing 접선 쪽으로 연속될 때만 점수를 낮춘다.
- 정확한 node 좌표를 거리상 밟지 않아도 zone 임시 위치는 계속 이동한다.
- 걸음 없는 heading 회전은 edge 전환 근거로 쓰지 않는다.

#### 늦은 회전

- graph node 도달 거리만으로 incoming 가설을 즉시 제거하지 않는다.
- zone 안에서 incoming 방향 증거와 outgoing 후보를 함께 유지한다.
- raw PDR 증분으로 temporary marker를 움직여 node 고정을 피한다.
- outgoing 방향의 실제 preview 걸음이 들어오면 해당 edge로 합류한다.

#### 위치와 trail

- temporary marker만 zone 안에서 제한적으로 2차원 이동한다.
- 임시 path를 영구 walked trail에 즉시 확정하지 않는다.
- outgoing edge가 확정되면 entry→node 주변→outgoing 합류점의 연결 path로 zone 구간을 정리한다.
- 보정 결과가 2m 이상 순간이동해야 하면 즉시 확정하지 않고 `uncertain`과 재획득 경로로 넘긴다.

#### 종료

- outgoing edge가 연속 걸음 근거로 확정됨
- 실제 유턴으로 incoming edge 반대 방향에 재합류
- timeout 또는 반경 이탈
- graph·anchor·route session reset

timeout/반경 이탈 뒤에도 연결 edge를 고르지 못하면 없는 길을 추측하지 않고 `uncertain`으로 전환한다.

#### 재탐색 보호

- zone 진입부터 확정/timeout까지 off-route evidence를 새로 누적하지 않는다.
- 기존 evidence를 영구 삭제하지 않고 zone 종료 결과에 따라 초기화 또는 이어 간다.
- zone 보호 최대 시간을 둬 실제 이탈을 숨기지 않는다.
- zone 밖의 평행 간선 leader 변경은 기존 strict edge 판정을 유지한다.

#### 테스트

- 45°·90° turn에서 -3m/0m/+3m 회전
- junction에서 직진
- junction 근처 제자리 휴대폰 회전
- 막다른 곳 유턴
- 짧은 edge 여러 개를 한 batch가 통과
- 연결된 outgoing 두 개의 모호 상태
- 연결되지 않은 평행 edge가 1~2m 옆에 있는 경우
- zone timeout 뒤 실제 이탈 재탐색

---

### Phase 3 — 에스컬레이터 다단계 상태기

> **상태**: 완료. 기존 `takeStartedTransition`/`takeCancelledTransition`/`onAltitude`
> 반환값은 그대로 두고 `takePhaseChanges()`를 더했다. 두 계약이 각각
> `midpointReached`/`cancelled`/`landed`와 같은 사건을 가리키므로 회귀 테스트가
> 그대로 살아 있다.

#### 공개 상태

```dart
enum EscalatorPhase {
  idle,
  boardingDetected,
  verticalMotionDetected,
  midpointReached,
  landed,
  cancelled,
  failed,
}
```

상태에는 `fromFloor`, `toFloor`, 정확한 boarding/arrival node id, group, direction, 근거, 시작 시각을
함께 담는다.

#### A. `boardingDetected` — 배너 시작

활성 다층 경로가 에스컬레이터 node를 정확히 가리킬 때 다음 근거를 사용한다.

- route progress상 탑승점 약 3m 이내
- 남은 거리가 서로 다른 optimistic 걸음 갱신 두 번 이상 연속 감소
- 현재 진행이 탑승점 방향과 크게 반대가 아님
- 예상 boarding/arrival node와 이동 방향을 graph에서 확정할 수 있음

동작:

- 배너를 즉시 표시한다.
- marker를 마지막 접근 edge 또는 boarding node에 안정적으로 붙인다.
- 이탈 재탐색과 일반 turn guidance를 잠시 억제한다.
- confirmed/optimistic tracker, heading, 기압은 계속 동작한다.
- 아직 PDR 걸음 적용을 pause하거나 층 지도를 바꾸지 않는다.

활성 경로가 없는 수동 탑승은 node 근접과 기압 근거가 생긴 뒤 시작한다. 잘못된 lane 선택 비용이
크므로 UI 조기 범위를 더 좁게 둔다.

#### B. `verticalMotionDetected` — PDR 걸음 적용 차단

- expected direction의 fast altitude slope가 연속 관측된다.
- 누적 고도가 지도 전환 문턱에 닿기 전이어도 된다.
- 단일 기압 튐은 허용하지 않는다.

동작:

- 위치에 반영되는 accel preview와 pedometer 걸음을 pause한다.
- raw motion activity, heading, 기압은 계속 관측한다.
- 배너를 `에스컬레이터로 이동 중`으로 바꾼다.
- 아직 출발 층 지도는 유지한다.

#### C. `midpointReached` — 목적 층 지도 전환

기존의 보수적인 조건을 유지한다.

- `|delta| >= minDeltaM` (현재 값은 `EscalatorDetectorConfig`가 단일 출처)
- expected direction과 같은 부호
- 최소 ramp rise와 방향 일관성
- 유효한 boarding/arrival node
- 다층 이동 거부선 미만

동작:

- 이 단계에서만 목적 층 도면과 경로를 연다.
- 목적 층 arrival node에 marker를 고정한다.
- PDR anchor는 아직 최종 확정하지 않는다.
- 취소를 위해 출발 층·anchor·경로 백업을 유지한다.

#### D. `landed` — anchor 확정과 PDR 재개

- 최소 확정 고도 변화와 ramp 시간이 충족됨
- fast altitude speed가 저속으로 감소
- raw landing motion이 함께 있으면 첫 저속 샘플에서 확정
- raw activity가 없으면 저속이 일정 시간 유지될 때 fallback(6.1)

동작 순서:

1. 목적 층 arrival node와 axes를 확인한다.
2. `applyVerticalTransfer`로 path origin만 rebase하고 heading rotation을 승계한다.
3. 걸음 적용을 즉시 resume한다.
4. pending marker를 해제한다.
5. 첫 1~2 optimistic 걸음 동안 arrival node의 연결 edge 후보를 유지한다.
6. 도착 배너를 노출한다(되돌리기 버튼은 두지 않는다 — Phase 5 참고).

경로 재계산, 도착 배너 animation, 카메라 이동은 PDR resume의 선행조건으로 두지 않는다.

#### 취소·오류

다음 조건이면 `cancelled` 또는 `failed`로 간다.

- 제한 시간 안에 expected direction 고도 변화가 없음
- 탑승점에서 다시 멀어짐
- 고도가 baseline 쪽으로 돌아가거나 부호가 뒤집힘
- 활성 경로가 바뀜
- 사용자가 층을 수동 선택
- 목적 층이나 arrival node를 찾을 수 없음

모든 출구는 하나의 공통 cleanup을 지나 걸음 적용, UI, 카메라, 경로 백업을 정리한다.

#### 테스트

- 접근만 하고 지나가면 배너 취소, 층 유지
- 배너는 지도 전환 문턱 이전, 층 전환은 midpoint 이후
- 상승·하강 방향과 node 이름 불일치 거부
- 고도 상승 후 복귀 취소
- 여러 층 변화 거부
- 지도 로드·arrival node 실패 cleanup
- 사용자의 수동 층 선택 우선

---

### Phase 4 — raw 하차 활동과 live heading

> **상태**: 완료. `RawMotionActivity`는 `accelPeakCount` 대신 **증분**
> (`accelPeakDelta`)을 싣는다 — native 카운터는 누적값이라 차분을 한 곳에서만
> 내는 편이 세션 재시작 처리까지 한 자리에 모인다.

#### raw motion 분리

detector가 현재 받는 `steps`는 PDR 위치에 실제 적용된 걸음 수다. 탑승 중 pause하면 증가하지 않으므로
하차 빠른 판정에 쓸 수 없다. 위치 적용과 무관한 계약을 추가한다.

```dart
class RawMotionActivity {
  final int timestampMs;
  final int accelPeakCount;
  final int? nativeStepDelta;
}
```

- native bridge는 기존 accel peak와 pedometer 이벤트를 계속 보낸다.
- PDR core는 pause 중 위치와 preview path에 이를 적용하지 않는다.
- application controller는 activity 시각과 양만 detector에 전달한다.
- detector는 수직 속도가 충분히 낮을 때만 landing 보조 근거로 사용한다.
- 수직 속도가 큰 에스컬레이터 중간에서는 peak가 많아도 재개하지 않는다.

#### heading 유지

- `pauseStepTracking`은 native source를 중지하지 않는다.
- 기존 quiet heading snapshot 정책을 유지한다.
- pending transfer marker가 있어도 `currentHeadingDegrees`를 null로 만들지 않는다.
- 목적 층 전환 전에는 출발 층 axes, 전환 후에는 목적 층 axes를 사용한다.
- 이전 anchor rotation과 heading reference를 그대로 승계한다.

#### 하차 후 다음 edge

- arrival node에 연결된 유효 edge를 모두 초기 후보로 둔다.
- live heading은 soft prior로만 사용한다.
- 첫 preview 걸음 벡터와 연속 두 걸음 방향을 더 강한 근거로 사용한다.
- 첫 걸음 전에는 사용자가 바라보는 방향만으로 edge를 확정하지 않는다.
- 약 1~2m 이동 후 일반 beam 정책으로 돌아간다.

#### 테스트

- pause 중 heading 90° 회전이 snapshot과 UI state에 전달됨
- 서로 다른 floor axes에서도 목적 층 원뿔 방향이 맞음
- 고속 수직 이동 + vibration peak에서 resume하지 않음
- 저속 전환 + 첫 raw landing peak에서 한 샘플로 resume
- raw activity가 없으면 저속이 일정 시간 유지될 때 fallback(6.1)
- 하차 후 직진·좌회전·우회전이 첫 2걸음 안에 올바른 후보로 수렴

---

### Phase 5 — 전환 UI와 z-order

> **상태**: 완료. **배너는 지도의 안내 자리(`GuidanceBanner`)가**, 전체 화면 veil은 셸
> root Stack 마지막 레이어가 그린다. veil은 계획대로 도면 교체 구간만 덮되 길이가 약 3.2초로
> 늘었다. 덮개 뒤에서 도면 크로스페이드와 마커 활강이 돌아, 걷힐 때 새 층과 하차 지점이 이미
> 자리를 잡고 있다(임계값·문구·연출은
> `client/lib/features/indoor_navigation/application/README.md`가 단일 출처).

#### 상태 소유

- detector/application이 `FloorTransitionUiState`를 만든다.
- `IndoorMapBody`는 상태를 `MapShellScreen`에 전달한다.
- veil은 root Stack이, 배너는 지도의 안내 자리가 소유한다.
- UI는 phase를 문구와 animation으로만 변환한다.

#### 배너

문구는 `FloorTransitionUiState`가 단일 출처다(`headline`·`detail`).

**배너는 따로 띄우지 않는다.** 안내 배너와 **같은 자리·같은 표면**을 쓰고, 층 전환이 도는 동안
그 자리를 가져간다(`GuidanceBanner`). 예전에는 셸이 상단 Column에 흰 알약으로 따로 띄워, 안내
중에는 초록 배너 위에 알약이 한 겹 더 겹쳤다 — 한 사건이 두 개의 안내로 보였다.

우선순위: 층 전환 → 도착 → 이탈 → 다음 행동. 층 전환이 맨 앞인 이유는 타는 동안 걸음이 멈춰 있어
다음 행동의 남은거리가 갱신되지 않기 때문이다.

**완료 단계는 없다.** 하차가 확정되면 배너가 그대로 사라진다. `N층으로 이동했습니다`를 몇 초 더
띄워 봐야, 그때 화면은 이미 새 층 도면과 새 경로를 그리고 있어 방금 끝난 일을 한 번 더 말할 뿐이다.
`도면을 갈아 끼우는 중`도 같은 이유로 없앴다 — 지도가 전환된다는 것은 앱의 사정이고, 그 사람에게
일어나는 일은 층 이동 하나다.

#### 층 지도 교체 veil

- root Stack의 마지막 레이어에 둔다.
- 지도·검색·카테고리·하단 바를 포함해 덮고, 그동안 뒤쪽 입력을 막는다.
- 중앙에 `B1 → 1F`를 세로로 세우고 점이 그 사이를 오간다.
- **덮는 구간은 도면 swap 앞뒤 약 4.7초**다(2026-08-13 실측 피드백으로 유지 연장). 하차까지
  덮어 보니 내리기 전에 새 층과 다음 경로를 볼 시간이 없었고, 예전 1.6초는 크로스페이드보다
  먼저 걷혀 교체 과정이 보였다.
- 덮개 뒤에서 도면 크로스페이드와 마커 활강이 그대로 돈다. 현재 값과 자세한 근거는
  application README의 "단계 분리"가 단일 출처다.

#### widget test

- 검색 한 줄 + 카테고리 한 줄
- 출발/도착 두 줄 + 카테고리 한 줄
- 출발/도착 두 줄 + 대분류·소분류·개수 안내
- ETA 카드 + 하단 바 + 층 선택기
- 작은 iPhone 화면과 큰 글자 배율
- 배너→veil→도착 배너
- 전환 중 뒤쪽 hit test 차단

---

### Phase 6 — 통합 검증

> **상태**: 자동 검증과 iOS 상·하행 실기기 확인은 통과했다. Android 센서 주기
> 차이는 판정 문턱을 시간 기준으로 바꿔 해소했고(아래 6.1), 실기기 확인과
> A/B replay 검증은 남아 있다.

#### 6.1 센서 주기 차이 — 판정 문턱을 시간으로 적는다

기압 샘플 주기는 iOS `CMAltimeter` 약 1069ms, Android `TYPE_PRESSURE` 약 180ms로
5~6배 다르다. 그런데 하차·수직 이동 판정이 **연속 샘플 수**로 적혀 있어, 같은
문턱이 iOS에서는 2.1초를 Android에서는 0.36초를 뜻했다. 그 결과 Android에서만
타는 도중에 하차가 확정되고, baseline이 중간 높이로 다시 잡혀 남은 반 층이 또
하나의 층 이동이 됐다 — **한 층을 내려가는데 층이 두 번 바뀌는** 증상이다.

바꾼 것은 셋이다.

- 빠른 EMA 계수를 **시정수**로 적고 매 샘플 `1 - exp(-dt/tau)`로 만든다.
- 수직 속도를 직전 샘플이 아니라 **700ms 이상 떨어진 값**과 비교해 잰다. 기압
  분해능(흔히 0.01 hPa ≈ 8.4cm)이 한 샘플의 실제 변화(180ms에 5cm)보다 커서
  연속 샘플이 같은 값으로 나오는 구간을 이 밑변이 넘어선다.
- 하차·수직 이동·램프 일관성의 "연속 샘플 수"를 전부 **지속 시간**과
  **구간(stride) 수**로 바꾼다.

문턱값은 iOS 실측 타이밍을 그대로 재현하도록 골랐다. 즉 이 변경은 통과 중인
iOS 동작을 보존하면서 Android만 제자리로 돌린다.

#### 자동 검증

```bash
flutter test test/features/indoor_navigation/corridor_position_tracker_test.dart
flutter test test/features/indoor_navigation/corridor_replay_test.dart
flutter test test/features/indoor_navigation/escalator_transition_detector_test.dart
flutter test test/features/indoor_navigation/contract_test.dart
flutter test test/domain/route_progress_test.dart
flutter test test/screens/map_shell/widgets/chrome/floor_transition_overlay_test.dart
flutter analyze
```

#### 실기기 시나리오

각 시나리오는 화면 녹화와 진단 JSON을 함께 남긴다.

1. 기존 90° node보다 3m 일찍 회전
2. node 근처에서 회전
3. node보다 3m 늦게 회전
4. junction에서 직진
5. junction에서 제자리 방향 전환
6. junction 주변 평행 edge 옆을 지나기
7. 에스컬레이터 접근 후 타지 않고 지나가기
8. 상행 탑승→중간 층 전환→직진 하차
9. 하행 탑승→중간 층 전환→좌·우회전 하차
10. 탑승 중 휴대폰 방향을 돌려 목적 층 marker 원뿔 확인
11. 에스컬레이터 중간에서 걷거나 진동이 큰 상황
12. 자동 전환이 틀렸을 때 층 선택기로 직접 되돌아가기

#### 롤아웃

- 임계값은 한 곳의 immutable config로 모은다.
- 진단 필드를 추가하면 schema version을 올린다.
- 기존 tracker와 새 tracker의 A/B replay를 유지한다.
- junction zone은 실제 node가 확인된 fixture부터 검증한다.
- 에스컬레이터 조기 UI가 오탐이어도 실제 층은 midpoint 전까지 바뀌지 않는다.
- 새 상태기 실패 시 기존 strict edge/replay 결과로 되돌릴 수 있는 경계를 유지한다.

---

## 7. 예상 변경 파일

### Flutter PDR·경로

- `client/lib/features/indoor_navigation/application/corridor_position_tracker.dart`
- `client/lib/features/indoor_navigation/application/corridor_tracking_session.dart`
- `client/lib/features/indoor_navigation/application/escalator_transition_detector.dart`
- `client/lib/features/indoor_navigation/application/indoor_navigation_controller.dart`
- `client/lib/features/indoor_navigation/contract/indoor_navigation_intents.dart`
- `client/lib/features/indoor_navigation/contract/indoor_navigation_view.dart`
- `client/lib/domain/guidance/route_progress.dart`

### Flutter UI

- `client/lib/screens/indoor_map/indoor_map_screen.dart`
- `client/lib/screens/map_shell/map_shell_screen.dart`
- `client/lib/widgets/eta_card.dart`
- 새 `FloorTransitionUiState` 계약과 전환 배너 위젯

### PDR core·platform

- `packages/indoor_pdr_core/lib/src/application/pdr_session.dart`
- 필요 시 native raw activity payload와 Dart parser

### 테스트

- `client/test/features/indoor_navigation/corridor_position_tracker_test.dart`
- `client/test/features/indoor_navigation/corridor_replay_test.dart`
- `client/test/features/indoor_navigation/escalator_transition_detector_test.dart`
- `client/test/domain/route_progress_test.dart`
- map shell/전환 배너 widget test

이번 계획에는 backend schema, seed, Studio 원본, graph geometry 수정 파일이 포함되지 않는다. 클라이언트
검증은 기본적으로 배포된 Cloud Run API를 사용하며 로컬 백엔드를 실행하지 않는다.

---

## 8. 후속 결정 사항

### 8.1 graph 데이터 보완

클라이언트 개선 뒤에도 같은 위치에서 `graphMismatchSuspected`가 여러 독립 세션에 반복될 때만 별도
작업을 연다.

우선순위는 다음과 같다.

1. 원본 지도 업체 polyline 유실 여부 확인
2. 신뢰할 수 있는 통행 가능 영역·복도 중심선 데이터 확인
3. 둘 다 없으면 반복 문제 간선만 사람이 검토

PDR 한 세션의 heading과 drift를 graph 형상으로 자동 저장하지 않는다.

### 8.2 평행 복도 그룹

다음 조건을 판별할 신뢰 가능한 데이터가 생기면 nullable `corridor_group_id`를 별도 설계한다.

- 같은 실제 보행 공간
- 벽·난간·통행 제한 없음
- 진입·이탈 topology가 동등함
- 주요 회전과 수직 이동 접근성이 같음

그 전에는 거리와 방향만으로 같은 복도를 자동 추론하지 않는다. 이번 구현에서는 junction 상태 중
짧은 재탐색 유예와 기존 evidence 누적으로만 오탐을 완화한다.

---

## 9. 커밋 분리안

1. `test: PDR 회전과 층 전환 실측 회귀 고정`
2. `fix: PDR preview를 배치 독립 cursor로 전환`
3. `fix: 교차점 전후 회전 허용 구간 적용`
4. `feat: 에스컬레이터 탑승과 층 전환 상태 분리`
5. `fix: 에스컬레이터 하차 즉시 PDR 재개`
6. `fix: 탑승 중 방향 표시와 하차 간선 선택 개선`
7. `fix: 층 전환 UI를 최상위 레이어로 이동`
8. `docs: PDR 경로 추종과 층 전환 문서 갱신`

기능·UI·문서 변경을 한 커밋에 섞지 않는다.

---

## 10. 최종 체크리스트

### preview

- [x] optimistic beam은 preview peak를 한 번만 적용한다.
- [x] batch acknowledgement가 marker를 뒤로 보내지 않는다.
- [x] batch 크기별 optimistic 위치 시계열이 같다.
- [x] `stabilizePreviewLeadM`과 `fullLeadM` clamp 의존이 제거됐다.
- [x] 실제 유턴과 leader relocation은 반영한다.

### junction

- [x] 기존 node 기준 빠른·정확한·늦은 회전 replay가 통과한다.
- [x] 간선 내부 위치는 계속 연속 progress다.
- [~] 자유 2차원 temporary marker는 만들지 않았다 — 회전 가설이 연결 간선 위에서만
      움직이므로 반경 제약이 구조적으로 성립한다(Phase 2 상태 메모 참고).
- [x] connected outgoing edge만 후보로 사용한다.
- [x] 걸음 없는 heading 회전으로 edge가 바뀌지 않는다.
- [x] zone timeout 뒤 실제 이탈 재탐색이 가능하다.
- [ ] graph에 node가 없는 실패는 데이터 한계로 분리한다. (실측 fixture 필요)

### 에스컬레이터

- [x] 탑승 배너가 지도 전환 문턱 이전에 뜬다.
- [x] PDR 걸음 pause와 층 지도 전환 시점이 분리됐다.
- [x] 목적 층 지도는 midpoint 근거 전에는 바뀌지 않는다.
- [x] raw activity와 위치 적용 걸음이 분리됐다.
- [x] 이동 중 vibration peak로 PDR이 재개되지 않는다.
- [x] 하차 첫 유효 근거에서 약 1초 안에 재개된다.
- [x] 탑승 중 heading frame과 marker 원뿔이 유지된다.
- [x] 하차 후 첫 1~2걸음으로 다음 edge를 선택한다.
- [x] 모든 취소·오류 경로가 공통 cleanup을 지난다.

### UI

- [x] 배너는 `MapShellScreen`이 소유한다.
- [x] 도면 교체 앞뒤를 veil이 덮고 그동안 뒤쪽 입력을 막는다.
- [x] 덮개 뒤에서 도면이 크로스페이드되고 마커가 끊기지 않고 흐른다.
- [x] 최대 높이 상단 UI와 겹치지 않는다.
- [x] 판정기가 스스로 취소하면 직전 층·anchor·경로를 복원한다(사용자에게 묻는 버튼은 없다).

### 범위

- [x] backend geometry 보완이 구현 선행조건에 포함되지 않았다.
- [x] `corridor_group_id`가 필수 구현에 포함되지 않았다.
- [x] 없는 graph topology를 PDR 로그로 자동 생성하지 않는다.
- [x] 클라이언트로 해결할 문제와 데이터 한계를 진단 코드로 구분한다.

### 검증

- [x] pure Dart 단위 테스트 통과
- [x] replay 테스트 통과
- [x] widget 테스트 통과
- [x] `flutter analyze` 통과
- [x] iOS 상행·하행 실기기 검증
- [x] Android 센서 주기 차이 — 판정 문턱을 시간 기준으로 전환(6.1), 실기기 확인은 남음
- [x] 진단 JSON에 phase·cursor·junction·raw activity 근거가 남는다.
