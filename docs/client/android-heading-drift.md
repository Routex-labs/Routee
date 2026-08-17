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
