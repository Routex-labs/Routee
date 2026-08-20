# 안드로이드 heading이 gyro hold에 갇히던 문제

기기가 바라보는 방향과 화면의 방향이 어긋나던 증상의 원인과 그 수정을 적는다.
코드는 `client/android/app/src/main/kotlin/com/navigation/navigation_client/PdrMotionBridge.kt`
한 파일이다.

**iOS에는 이 문제가 없다.** `fusedHeadingDeg`가 언제나 CoreMotion attitude이고,
그쪽은 자력계 자기수정 루프를 안에 갖고 있어 아래 구조 자체가 생기지 않는다.
안드로이드만 rotation vector와 gyro 적분을 직접 골라 쓴다.

---

## 1. gyro hold가 무엇이고 왜 있나

`selectHeading()`은 매 IMU 표본마다 heading의 출처를 고른다.

- 평소에는 **rotation vector**(`TYPE_ROTATION_VECTOR`, 자력계를 포함한 9축 융합).
- 자기 교란이 의심되면 **gyro 적분값**(`gyroHeadingDeg`)으로 잠깐 갈아탄다. 이걸
  gyro hold라 부른다.

hold가 필요한 이유는 분명하다. 에스컬레이터·기둥·자동문 근처에서 rotation vector가
수십 도씩 튀는데, 그 값을 그대로 쓰면 화면의 화살표가 홱 돌아간다. 그 구간만
자이로로 버티고 지나가자는 것이다.

`useGyroHold`가 서는 조건은 다섯이다 — game rotation vector 사용, 자력계 정확도
낮음, 자기장 세기가 기준값에서 35% 이상 벗어남, **innovation이 큼**, rotation
vector가 스스로 보고한 오차가 35°를 넘음.

## 2. 무엇이 깨졌나 — 네 개가 한 방향으로 겹쳤다

### P1. innovation이 스스로를 키운다 (영구 래치)

hold의 해제 조건은 `innovation = |rawRotationHeading − gyroHeading| ≤ 35°` 였다.
그런데 이 식의 한쪽 항이 **드리프트하고 있는 gyroHeading 자신**이다.

```
hold 진입 → rotation vector를 안 씀 → gyroHeading이 자유롭게 드리프트
        → innovation이 커짐 → 해제 조건이 더 멀어짐 → hold 유지 → (반복)
```

한 번 35°를 넘으면 rotation vector가 정답을 줘도 조건이 영구히 참이다. 자이로
bias가 계속 쌓이므로 시간이 갈수록 벌어지기만 한다. **화면의 방향이 실제와
어긋난 채 돌아오지 않는 상태**가 이것이다.

### P2. gyroHeading을 세션당 한 번만 앵커링했다

`gyroHeadingInitialized`가 false일 때 한 번만 rotation vector 값을 복사하고, 그
뒤로는 각속도만 적분했다. 재앵커링이 없으니 잔류 bias가 무제한 누적된다. MEMS
자이로의 bias는 온도에 따라 표류하므로 이건 시간 문제일 뿐이다. **P1의 연료다.**

### P3. 자기장 기준값이 hold 중에 얼어붙는다

`magneticFieldBaseline` 갱신이 hold가 **아닐 때만** 돌았다. hold에 들어간 순간
기준값이 그 시점 값에 고정되므로, 자기장이 정상으로 돌아와도 `fieldDeviation`은
옛 기준과 비교돼 0.35 아래로 못 내려온다. P1과 똑같은 모양의 래치가 조건 하나에
더 있었던 셈이다.

### P4. 히스테리시스가 없다

진입과 해제 임계값이 둘 다 35°였다. 경계에서는 표본마다 hold가 뒤집혀 heading이
두 값 사이를 진동한다.

### P5. `headingStable`의 뜻이 플랫폼마다 달랐다 (부차적)

iOS는 **기기 기울기 게이트**다 — 전방 벡터의 수평 성분이 0.4 이하면(폰을 눕히면)
false. 안드로이드는 "출처가 rotation vector이고 hold가 아님"이라, 기울기로는
false가 될 수 없었다.

공용 코어가 이 값으로 smoothing 시정수를 0.6s / 0.1s로 가른다
(`packages/indoor_pdr_core/lib/src/application/pdr_session.dart`). 그래서 폰을
눕혀 heading이 얼어붙은 구간에서 **안드로이드만** 그 멈춘 값을 빠른 시정수로
따라갔다.

---

## 3. 무엇을 고쳤나

| # | 고침 | 없앤 문제 |
|---|---|---|
| 1 | rotation vector 표본마다 gyroHeading을 재앵커링(τ≈45s) | P2, 그리고 P1의 뿌리 |
| 2 | 진입 35° · 해제 15°로 문턱을 가름 | P4 |
| 3 | hold 8초 상한 — 넘으면 rotation vector로 강제 재잠금 | P1의 마지막 안전장치 |
| 4 | `magneticFieldBaseline` 갱신을 분기 **앞으로** 이동 | P3 |
| 5 | `headingStable`에 iOS와 같은 기울기 게이트 추가 | P5 |

### 1번이 핵심이다 — 나머지는 보험이다

`gyroHeadingDeg += k · shortestDelta(rawRotationHeading − gyroHeadingDeg)`를
**hold 여부와 무관하게** 매 rotation 표본마다 돌린다. `k = 1 − exp(−dt/τ)`.

이것 하나로 P1이 자기소멸한다. gyroHeading이 절대 북에서 무한히 멀어질 수 없으니
innovation도 무한히 커질 수 없고, 해제 조건이 저절로 다시 성립한다.

**τ가 커야 하는 이유**와 **작아도 되는 이유**가 팽팽하다.

- 작으면(τ≈1s) gyro hold가 의미를 잃는다. 교란된 rotation vector를 그대로
  따라가게 되니 hold를 두는 목적 자체가 사라진다.
- 크면 P1을 푸는 데 오래 걸린다.

45초를 고른 근거는 **hold의 상한 시간(8초)과의 관계**다. 최악의 경우(rotation
vector가 통째로 틀린 값을 주는 8초 구간) gyroHeading이 그 틀린 값 쪽으로 끌려가는
양은 `1 − exp(−8/45) ≈ 16%`다. 30° 틀린 값이면 5° 미만이고, 이는 걸음 회전의
잡음에 묻힌다. 반대로 정상 구간에서는 8초마다 16%씩 좁혀지므로 누적 bias가
수십 도까지 자랄 수 없다.

100 Hz 표본에서 한 표본의 `k`는 약 2.2e-4다. 즉 **한 표본이 옮기는 각도는 30°
차이에서도 0.007°** 라, 화면에서는 보이지 않는다.

### 3번에 game rotation vector는 빼 둔다

`TYPE_GAME_ROTATION_VECTOR`는 애초에 자력계를 쓰지 않는다. 재잠금할 절대 북이
없으므로 강제 재잠금이 성립하지 않고, 그쪽의 hold는 **고장이 아니라 설계**다.
빼지 않으면 8초마다 arbitrary reference로 재잠금하며 heading을 계속 흔든다.

### 4번은 순서만 바꾼 것이다

`selectHeading()` 맨 위로 옮겼다. 값도 계수(0.985/0.015)도 그대로다 — 고친 것은
"언제 갱신하는가" 하나뿐이고, 그 하나가 조건을 래치로 만들고 있었다.

---

## 4. 실기기에서 확인할 것

이 수정은 단위 테스트로 못 잡는다 — 입력이 실제 자기장과 자이로 bias다. 걸으면서
볼 것은 셋이다.

1. **에스컬레이터·기둥 옆을 지난 뒤 화살표가 제자리로 돌아오는가.** 예전에는
   한 번 틀어지면 앱을 다시 켜야 했다. 지금은 늦어도 8초 안에 돌아와야 한다.
2. **문턱 근처에서 화살표가 떨지 않는가**(P4). 떨면 해제 문턱(15°)을 더 내린다.
3. **폰을 눕혔다 세웠을 때** 화살표가 옛 방향으로 튀지 않는가(P5).

되돌릴 순서는 **3번(상한) → 2번(히스테리시스) → 1번(재앵커링)** 이다. 1번이 가장
근본이고 부작용이 가장 작으므로 마지막에 손댄다.

---

## 5. 위 수정과 **다른 문제** — 일정한 각도로 돌아가 있는 경우

위 P1~P5는 전부 **시간이 지나며 벌어지는** 어긋남이다. 화살표가 처음부터 늘 같은
각도(예: 반시계 90°)로 돌아가 있다면 그건 드리프트가 아니라 **각도 규약이 어긋난
것**이고, 고칠 자리가 완전히 다르다.

### 마커가 도는 길은 네 토막이다

| # | 토막 | 무엇을 하나 | 코드 |
|---|---|---|---|
| 1 | 센서 | 기기가 향한 나침반 방위를 만든다 | `PdrMotionBridge.updateRotation` |
| 2 | 코어 | 그 값을 smoothing한다 | `PdrSession._updateFusedHeading` |
| 3 | 앵커 | `rotationDeg`를 더해 보정한다 | `_pdrCurrentHeadingDeg` |
| 4 | 지도 | 카메라 회전을 빼고 화면에 그린다 | `iconRotate` + `iconRotationAlignment: map` |

**넷 다 화면에서는 똑같이 "돌아가 있다"로 보인다.** 그래서 값을 나란히 놓기 전에는
어느 토막인지 고를 수 없다. 코드를 다 읽어도 갈리지 않았다 — 네 토막이 서로
일관되고, 1·2는 iOS와 문자 그대로 같은 식이다.

### 그래서 칩으로 잰다

`describeMarkerHeading`이 디버그 모드에서 셋째 칩에 한 줄을 띄운다.

```
기기 271° · 마커 271° · 카메라 180° · 화면 91° · rot 0° · magneticNorth
```

| 자리 | 뜻 |
|---|---|
| `기기` | 센서가 준 나침반 방위(토막 1·2의 결과) |
| `마커` | 마커에 실제로 넘긴 값(토막 3의 결과) |
| `카메라` | 지도가 돌아가 있는 각도 |
| `화면` | `마커 − 카메라`. **눈에 보여야 하는 각도**다 |
| `rot` | 앵커 보정각. 자북 기기라면 0이어야 한다 |
| 끝 | heading 기준 frame |

### 읽는 법 — 세 갈래로 갈린다

1. **`기기`가 실제와 다르다** → 토막 1·2. 폰을 북쪽으로 향하고 `기기`가 0 근처인지
   본다. 90° 어긋나면 센서 축을 잘못 고른 것이다.
2. **`기기` ≠ `마커`, 그리고 `rot` ≠ 0** → 토막 3. 자북 기기인데 `rot`이 0이 아니면
   수동 방향 보정(`confirmAnchorByFloorDirection`)이 끼어든 것이다. **그 함수는
   `walkingHeadingDeg`로 보정각을 구하는데 마커는 `orientationHeadingDeg`에
   적용한다** — 폰을 든 방향과 걷는 방향이 다르면 그 차이가 그대로 상수 오차가
   된다. 하단 「위치 보정」을 짝수 번 누르면 이 경로가 돈다.
3. **`화면` 값은 맞는데 눈에는 다르게 보인다** → 토막 4. `iconRotationAlignment`가
   먹지 않아 지도 회전이 안 빠진 것이고, 그때 오차는 정확히 `카메라` 값과 같다.
   이 앱은 카메라를 **정북에 두지 않는다** — `portraitBearingFor`가 건물 긴 축을
   화면 세로로 세우므로 `카메라`가 수십~수백 도다. 그래서 이 갈래의 오차는 늘
   크게 나타난다.

### 실기기 측정 결과 (2026-08-17, 더현대 서울 1F)

```
기기 229° · 마커 229° · 카메라 325° · 화면 264° · rot 0° · magneticNorth
```

화면에 보인 것도 정확히 264°(위에서 반시계 96°, 즉 왼쪽)였다. **이 한 줄이 갈래
3과 갈래 2를 동시에 지웠다.**

- `마커 − 카메라 = 화면`이 성립하고 눈에 보인 것과 같다 → **토막 4는 정상이다.**
  지도 회전은 제대로 빠지고 있다.
- `rot 0°` → 앵커는 아무 보정도 안 했다. 즉 **마커 각도 = 센서 각도**다.

남는 것은 하나뿐이다 — **센서가 준 229°가 실제와 96° 다르다.**

### 그런데 브리지 계산은 맞다

세 가지 자세를 손으로 넣어 확인했다(Android 회전행렬 R은 device→world,
열 j가 기기축 j의 world 표현).

| 자세 | 기대 | 계산 결과 |
|---|---|---|
| 평평, 위쪽이 북 | 0° | `atan2(0, 1)` = 0° ✓ |
| 평평, 위쪽이 동 | 90° | `atan2(1, 0)` = 90° ✓ |
| 세움, 뒷면이 북 | 0° | `atan2(0, 1)` = 0° ✓ |

iOS와도 문자 그대로 같은 식이다(축 이름만 ENU ↔ NWU로 다르다). 즉 **코드가
아니라 입력이 틀렸다** — 철골 건물 안에서 자력계가 끌려가 rotation vector의 절대
yaw가 통째로 돌아간 것이다. 백화점 실내에서 90° 단위 오차는 흔하다.

## 6. 진짜 원인 — 한 줄짜리 회귀였다

### 범인

**`81b4d570 fix: retain Android absolute heading during gyro hold` (2026-07-17)**

```diff
   if (source != null &&
       source.contains('rotation_vector') &&
-      !source.contains('game_rotation_vector') &&
-      !source.contains('gyro_hold')) {
+      !source.contains('game_rotation_vector')) {
     return HeadingReference.magneticNorth;
   }
```

같은 커밋이 Kotlin 쪽 문자열도 `"sensor_manager/gyro_hold"`에서
`"sensor_manager/rotation_vector+gyro_hold"`로 바꿨다.

### 왜 이게 방향을 90° 틀어 놓나

앵커를 확정할 때 갈래가 하나뿐이다.

```
if (headingReference == magneticNorth) → rotationDeg = 0 (보정 없음)
else                                   → awaitingHeading (방향을 받는다)
```

**철골 건물 안에서는 gyro hold가 사실상 상시 걸린다** — `poorMagnetic`,
`fieldDeviation > 0.35`, `innovation > 35°` 중 하나는 늘 성립한다.

| | 실내에서의 `headingSource` | 분류 | 앵커 | 결과 |
|---|---|---|---|---|
| 회귀 전 | `sensor_manager/gyro_hold` | arbitrary | `awaitingHeading` | GPS course나 화면 방향으로 **보정각을 받아** 확정 → 방향이 맞았다 |
| 회귀 후 | `sensor_manager/rotation_vector+gyro_hold` | magneticNorth | `rot = 0` | **교란된 자기 방위를 보정 없이 그대로** 씀 → 90° 틀어짐 |

즉 예전에 잘 됐던 이유는 자력계가 정확해서가 아니라, **실내에 들어가면 앱이
스스로 "이 방위는 못 믿는다"고 분류해 다른 근거(GPS course)로 갈아탔기**
때문이다. 그 분류가 사라지면서 갈아탈 기회 자체가 없어졌다.

칩의 `rot 0° · magneticNorth`가 정확히 회귀 후 상태를 찍은 것이다.

### 그 커밋이 틀렸던 것은 아니다 — 절반만 맞았다

frame 판정은 그 커밋 말이 맞다. hold 중에도 마지막 rotation-vector frame에서
적분을 이어가므로 **기준 frame은 여전히 자북**이고, 서버 자북 정렬각은 그대로
유효하다. 커밋 메시지도 "품질 저하는 `headingStable`로 별도 전달된다"고 적었다.

문제는 **그 품질 신호를 아무도 읽지 않았다는 것**이다. 앵커 확정은 frame 판정
하나만 봤다. 그래서 "frame은 맞다"가 곧 "보정 불필요"로 읽혔다.

### 고침 — 판정을 둘로 가른다

| 함수 | 묻는 것 | hold 중 답 |
|---|---|---|
| `headingReferenceFromSource` | 이 값이 자북 frame인가 | **자북이다**(81b4d570 유지) |
| `isTrustedHeading` | 그 frame을 지금 맡겨도 되는가 | **아니다** |

앵커 확정은 이제 뒤엣것을 본다. 실내에서는 다시 `awaitingHeading`으로 가고,
**자동 진입 경로가 GPS course로 스스로 보정한다** — 사용자에게 묻지 않는다
(`_entryFloorDirection`). 회귀 전에 실제로 돌던 경로가 이것이고, 회귀 이후로는
Android에서 한 번도 도달하지 못한 죽은 코드였다.

두 판정을 다시 한 함수로 합치면 같은 회귀가 난다. 그래서 회귀 방지 테스트를
`heading_reference_test.dart`에 못 박아 뒀다 — "frame은 자북이라고 답한다"와
"그래도 그 방위를 믿어서는 안 된다"가 **함께** 성립해야 한다.

### 사용자에게 묻는 창은 마지막 수단이다

GPS course는 **건물에 걸어 들어가는 순간**에만 있다. 지도를 눌러 위치를 직접
찍거나 길찾기 출발지를 고른 경우에는 그 근거가 없어서, 그때만 방향을 묻는다.
자동 진입으로 들어온 사용자는 이 창을 보지 않는다.

### 고침 셋

| # | 고침 |
|---|---|
| 1 | `headingTrustworthy`를 새로 둔다 — frame이 자북이고, 자력계가 나쁘다고 보고하지 않았고, gyro hold 중도 아닐 때만 참 |
| 2 | **사용자가 지도를 직접 찍으면 자북을 믿을 만해도 방향을 묻는다**(`requireDirection`) |
| 3 | 보정각을 `walkingHeading`이 아니라 `fusedHeading`에서 뺀다(아래) |

**2번이 실질적인 해결책이다.** 1번의 자동 판정만으로는 부족하다 — 자력계는 국소
교란을 모른 채 "정확도 높음"을 계속 보고할 수 있고, 그러면 1번이 안 걸린다.
사용자가 「위치 지정」으로 지도를 찍는 것은 곧 "지금 잡힌 게 틀렸다"는 뜻이라,
그 자리에서 방향까지 묻는 것이 자연스럽고 **항상 열려 있는 출구**가 된다.

반대로 1번을 넓게 잡으면 안 된다. 정확도 `unknown`까지 거부하면 정상 기기에서도
세션마다 모달이 뜬다 — 잘못 걸리는 비용이 놓치는 비용보다 크고, 놓치는 쪽은
2번이 받아 준다. 그래서 **나쁘다는 증거(low·uncalibrated)가 있을 때만** 거부한다
(`isTrustedMagneticAccuracy`).

### 3번 — 보정각을 재는 기준이 어긋나 있었다

```
rotationDeg = target − walkingHeadingDeg      // 예전
```

`walkingHeading = fusedHeading + walkOffset`이고, `walkOffset`은 **폰을 든 각도와
걷는 방향의 차이**(±60°까지)다. 그런데 마커는 `fusedHeading + rotationDeg`로
그린다. 그래서 「위쪽/오른쪽/…」처럼 **바라보는 쪽**을 물어 놓고 걷는 쪽 값에서
빼면, `walkOffset`이 그대로 마커의 상수 오차로 남는다.

이제 그 방향이 무엇을 가리키는지에 따라 뺄 값을 고른다
(`confirmAnchorByFloorDirection`의 `describesFacing`) — 화면 방향 질문은
`fusedHeading`, GPS course는 `walkingHeading`.

### 갈래 3을 1분 만에 가르는 법

하단 **「위치 보정」을 두 번** 누른다. 짝수 번째 탭은 카메라 bearing을 마커
heading과 같게 맞추므로(`_recalibrateIndoor`), **원뿔이 화면에서 정확히 위를
가리켜야 한다.**

- 위를 가리키면 → 토막 4는 정상이다. 남은 것은 갈래 1·2이고, 지도 자체가 실제와
  틀어진 것이다.
- 여전히 옆을 가리키면 → **토막 4다.** 지도 회전이 안 빠지고 있다.

## 방향은 묻지 않는다

「바라보는 방향 맞추기」 모달은 없앴다. 아무 조작 없이 튀어나오는 창이었고, 「화면
위쪽」·「오른쪽」 같은 보기로 실제 방위를 고르게 하는 것이라 **사용자가 답을 알기도
어려웠다.**

그냥 지우면 안 되는 자리다 — `CalibrationPhase.awaitingHeading`은 `canRenderPosition`
이 false라, 물음을 없애는 순간 **위치 마커가 통째로 사라진다.** 그래서 묻는 대신 자동
진입과 **같은 추정**으로 채운다(`_entryFloorDirection`: GPS course → 층 그래프 중심).

추정까지 실패하면(그래프가 없거나 찍은 점이 그래프 중심과 겹침) 앵커를 확정하지 않고
사용자에게 다시 찍으라고 알린다. **지어낸 각도로 확정하면 궤적이 통째로 돌아간다.**

검증 기준은 `client/test/screens/outdoor_map/no_direction_prompt_test.dart`. 이 회귀는
화면으로 확인할 수 없다 — 모달이 heading frame이 자북이 아닌 기기에서만 떠서, 위젯
테스트의 가짜 센서로는 그 조건을 못 만든다. 그래서 소스에 호출이 없다는 것으로 지킨다.

> **잃은 것도 적어 둔다.** 자력계가 "정확도 높음"을 보고하면서 건물 철골 때문에
> 국소적으로 틀어지는 경우, 그 모달이 유일한 출구였다. 지금은 사용자가 「위치 지정」
> 으로 다시 찍는 것 말고는 방위를 고칠 길이 없다. 현장에서 마커가 일정하게 틀어져
> 보이면 이 자리를 의심한다.
