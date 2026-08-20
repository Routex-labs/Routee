# 대중교통 결과 화면 개편 + 길찾기 잔손질 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 대중교통 결과 카드를 네이버지도 형태로 다시 그리고 수단 필터 탭을 붙이면서, 기기 확인에서 나온 길찾기 결함 넷(자동차 라벨 중복·계획 카드 도착시각·안내 시작 GPS 강제 이동·뒤로가기 앱 종료)을 함께 고친다.

**Architecture:** 다섯 항목이 건드리는 파일이 서로 겹치지 않는다. 순수 함수(병합·필터)를 domain 층에, 그리기를 widgets 층에 두고, 화면은 그 둘을 조립만 한다. 새 API를 부르지 않는다 — 필터도 카드도 이미 받은 응답만으로 계산한다.

**Tech Stack:** Flutter · `routex_design_system`(git 의존, ref `104f0fce`) · `flutter_test` · `latlong2`

**Spec:** `docs/superpowers/specs/2026-08-19-transit-screen-redesign-design.md`

## Global Constraints

- **문서·커밋은 한국어.** 커밋 제목은 한 줄, `feat:`/`fix:`/`refactor:`/`docs:`/`chore:` 접두사. `Co-Authored-By` 및 Claude 태그 금지.
- **import는 아래로만.** 등급: `0 models/core/theme/routing` → `1 domain/state` → `2 repositories/features/map` → `3 widgets` → `4 screens` → `5 app·main·service_locator`. `client/test/lib_layer_direction_test.dart`가 검사한다.
- **주석 상한.** 파일 머리 주석 8줄 이하, 선언 위 `///` 한 덩어리 13줄 이하. `client/test/lib_header_comment_length_test.dart`가 검사한다. 길어지면 지우지 말고 `docs/`로 옮기고 경로 한 줄만 남긴다.
- **`///`만 쓴다.** `/** */`는 lint(`slash_for_doc_comments`)가 잡는다. 인자는 `[query]`처럼 대괄호로 가리킨다.
- **대괄호 링크는 import를 끌고 온다.** 위층 파일을 가리킬 때는 경로를 글자로만 적는다.
- **작업 디렉터리는 `D:/Navigation/.claude/worktrees/directions-route-options`.** 모든 `flutter` 명령은 그 아래 `client/`에서 돈다.
- **테스트가 검증 기준의 단일 출처다.** 주석에 검증 표를 베끼지 않는다.
- 없는 데이터의 칸은 **자리도 남기지 않는다** — 회색 플레이스홀더는 "지원 안 함"이 아니라 "고장"으로 읽힌다.

---

## File Structure

| 파일 | 책임 | 상태 |
|---|---|---|
| `client/lib/domain/route/directions_route_merge.dart` | 자동차 후보 병합. 같은 kind를 두 번 넣지 않는다 | 수정 |
| `client/lib/widgets/directions_route_options_panel.dart` | 자동차 후보 목록. 라벨은 맨 앞 kind 하나 | 수정 |
| `client/lib/widgets/eta_card.dart` | 계획 카드·진행 바 연결. headline이 소요 시간 | 수정 |
| `client/lib/screens/outdoor_map/outdoor_map_tuning.dart` | 안내 시작 허용 반경 상수 | 수정 |
| `client/lib/screens/outdoor_map/parts/guidance.dart` | 안내 시작 가드 | 수정 |
| `client/lib/screens/map_shell/map_shell_screen.dart` | 뒤로가기 단계 | 수정 |
| `client/lib/domain/route/transit_itinerary_filter.dart` | 대중교통 경로의 수단 분류·집계. 순수 함수 | **신규** |
| `client/lib/widgets/transit_itinerary_card.dart` | 대중교통 결과 카드 한 장 + 구간 비율 막대 | **신규** |
| `client/lib/screens/map_shell/widgets/sheets/transit_routes_sheet.dart` | 필터 탭 + 카드 목록 조립, 펼침 상태 소유 | 수정 |
| `client/lib/widgets/transit_itinerary_tile.dart` | (구) 대중교통 한 줄 | **삭제** |

---

## 병렬 실행

**Task 1~6은 서로 어떤 파일도 공유하지 않는다.** 동시에 진행해도 충돌하지 않는다.

```
Wave A (동시 6갈래)          Wave B          Wave C (직렬)
  Task 1  자동차 라벨
  Task 2  도착 시각
  Task 3  GPS 가드
  Task 4  뒤로가기
  Task 5  필터 함수  ─┐
  Task 6  카드 위젯  ─┴────→  Task 7  ────→  Task 8  통합 검증
                              시트 조립       (기기 하나라 나눌 수 없다)
```

Task 7은 Task 5·6 **둘 다** 필요하다. Task 1~4와는 독립이라 그쪽이 안 끝나도 시작할 수 있다.

---

## Task 1: 자동차 후보 라벨 중복 제거

**Files:**
- Modify: `client/lib/domain/route/directions_route_merge.dart:32-38`
- Modify: `client/lib/widgets/directions_route_options_panel.dart:34`
- Test: `client/test/domain/route/directions_route_merge_test.dart`
- Test: `client/test/widgets/directions_route_options_panel_test.dart`

**Interfaces:**
- Consumes: `DirectionsRouteOptionKind`(`recommended`/`shortestDistance`/`alternative`), `DirectionsRouteOption({required List<DirectionsRouteOptionKind> kinds, required DirectionsRoute route})` — 둘 다 `client/lib/models/route/directions_route.dart`
- Produces: 없음. 기존 시그니처 그대로.

**왜 이렇게 하나:** TMAP `searchOption` 2와 3이 둘 다 `alternative`로 매핑된다. 좌표열이 같으면 병합되면서 `kinds`가 `[recommended, alternative, alternative]`가 되고 화면에 "추천 · 대안 · 대안"으로 찍힌다. 같은 kind가 두 번 있는 것은 목록의 사실이 아니라 요청 방식의 부산물이므로 **데이터에서** 없앤다.

- [ ] **Step 1: 실패하는 병합 테스트를 쓴다**

`client/test/domain/route/directions_route_merge_test.dart`의 `main()` 안, 기존 `test('입력이 비면 빈 목록을 돌려준다', ...)` **앞에** 넣는다.

```dart
  test('같은 kind가 두 번 들어와도 kinds에는 한 번만 남는다', () {
    final merged = mergeDirectionsRouteOptions([
      (DirectionsRouteOptionKind.recommended, routeA),
      (DirectionsRouteOptionKind.alternative, routeASameGeometry),
      (DirectionsRouteOptionKind.alternative, routeASameGeometry),
    ]);

    expect(merged.length, 1);
    expect(merged.single.kinds, [
      DirectionsRouteOptionKind.recommended,
      DirectionsRouteOptionKind.alternative,
    ]);
  });
```

- [ ] **Step 2: 실패를 확인한다**

```powershell
flutter test test/domain/route/directions_route_merge_test.dart
```

기대: FAIL. `kinds`가 `[recommended, alternative, alternative]`로 나와 길이가 안 맞는다.

- [ ] **Step 3: 병합에서 중복 kind를 버린다**

`client/lib/domain/route/directions_route_merge.dart`의 `else` 가지를 바꾼다.

바꾸기 전:

```dart
    } else {
      byKey[key] = DirectionsRouteOption(
        kinds: [...existing.kinds, kind],
        route: existing.route,
      );
    }
```

바꾼 뒤:

```dart
    } else if (!existing.kinds.contains(kind)) {
      // searchOption 2·3이 둘 다 alternative로 매핑돼, 좌표열까지 같으면 같은
      // kind가 두 번 들어온다. 그대로 두면 목록이 "추천 · 대안 · 대안"이 된다.
      byKey[key] = DirectionsRouteOption(
        kinds: [...existing.kinds, kind],
        route: existing.route,
      );
    }
```

- [ ] **Step 4: 통과를 확인한다**

```powershell
flutter test test/domain/route/directions_route_merge_test.dart
```

기대: PASS, 4개 전부. 기존 `'좌표열이 같으면 kinds를 합치고 한 줄로 남는다'`는 서로 다른 kind 둘이라 그대로 통과한다.

- [ ] **Step 5: 실패하는 패널 테스트를 쓴다**

`client/test/widgets/directions_route_options_panel_test.dart`의 `main()` 끝에 넣는다.

```dart
  testWidgets('kinds가 여럿이어도 라벨은 맨 앞 하나만 적는다', (tester) async {
    await tester.pumpWidget(
      wrap(
        DirectionsRouteOptionsPanel(
          options: const [
            DirectionsRouteOption(
              kinds: [
                DirectionsRouteOptionKind.recommended,
                DirectionsRouteOptionKind.alternative,
              ],
              route: routeA,
            ),
            DirectionsRouteOption(
              kinds: [DirectionsRouteOptionKind.shortestDistance],
              route: routeB,
            ),
          ],
          selectedIndex: 0,
          onSelect: (_) {},
        ),
      ),
    );

    expect(find.text('추천'), findsOneWidget);
    expect(find.text('최단거리'), findsOneWidget);
    expect(find.textContaining('대안'), findsNothing);
  });
```

- [ ] **Step 6: 실패를 확인한다**

```powershell
flutter test test/widgets/directions_route_options_panel_test.dart
```

기대: FAIL. `'추천 · 대안'`이 그려져 `find.text('추천')`이 아무것도 못 찾는다.

- [ ] **Step 7: 패널이 맨 앞 하나만 찍게 한다**

`client/lib/widgets/directions_route_options_panel.dart`에서 `title` 한 줄을 바꾼다.

바꾸기 전:

```dart
            title: options[i].kinds.map((kind) => kind.label).join(' · '),
```

바꾼 뒤:

```dart
            // 병합 순서가 추천 > 최단거리 > 대안이라 first가 곧 "제일 앞"이다.
            // 합쳐진 나머지 kind는 적지 않는다 — 라벨이 길어지는 쪽이 더 나쁘다.
            title: options[i].kinds.first.label,
```

- [ ] **Step 8: 통과를 확인한다**

```powershell
flutter test test/widgets/directions_route_options_panel_test.dart
```

기대: PASS, 전부.

- [ ] **Step 9: 커밋**

```powershell
git add client/lib/domain/route/directions_route_merge.dart client/lib/widgets/directions_route_options_panel.dart client/test/domain/route/directions_route_merge_test.dart client/test/widgets/directions_route_options_panel_test.dart
git commit -m "fix: 자동차 경로 후보 라벨에서 중복 대안을 지운다"
```

---

## Task 2: 계획 카드 headline을 소요 시간으로

**Files:**
- Modify: `client/lib/widgets/eta_card.dart:44-58`
- Test: `client/test/widgets/eta_card_test.dart`

**Interfaces:**
- Consumes: `RoutexEtaCard({required String arrivalTime, required List<RoutexTripMetric> metrics, required VoidCallback? onStart, Widget? routeOptions, String title})` — 디자인시스템
- Produces: 없음. `EtaCard`의 공개 파라미터는 그대로.

**왜 이렇게 하나:** `RoutexEtaCard.arrivalTime`은 **required이자 headline**(제일 큰 글자)이다. 빈 문자열을 넘기면 카드에 구멍이 난다. 그래서 지우는 대신 그 자리에 소요 시간을 올린다. `title`은 이미 `label`(`'목적지까지'`)이 쓰고 있으므로 건드리지 않는다 — 거기에 `'소요'`를 넣으면 어디로 가는 경로인지가 사라진다.

진행 바(`RoutexTripProgress`)의 `'도착 예정'`은 **그대로 둔다.**

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`client/test/widgets/eta_card_test.dart`의 `group('안내 전 계획 카드', ...)` 안, 마지막 `testWidgets` 뒤에 넣는다.

```dart
    testWidgets('headline은 도착 시각이 아니라 소요 시간이다', (tester) async {
      await tester.pumpWidget(
        wrap(const EtaCard(distanceMeters: 3900, minutes: 8)),
      );

      // 소요가 metrics 줄(RichText)이 아니라 제 몫의 Text로 올라와 있다.
      expect(find.text('8분'), findsOneWidget);
      // 시각 표기(`오전`/`오후`)는 계획 카드에서 사라졌다.
      expect(find.textContaining('오전', findRichText: true), findsNothing);
      expect(find.textContaining('오후', findRichText: true), findsNothing);
      // 목적지 라벨은 남는다 — title은 건드리지 않았다.
      expect(find.text('목적지까지'), findsOneWidget);
    });
```

`group('안내 전 계획 카드', ...)` **밖**, `testWidgets('안내 중에는 남은 값과 종료 동작을 보여 준다', ...)` 뒤에도 하나 더 넣는다.

```dart
  testWidgets('안내 중에는 도착 예정 시각이 그대로 남는다', (tester) async {
    await tester.pumpWidget(
      wrap(
        const EtaCard(distanceMeters: 150, minutes: 2, guidanceStarted: true),
      ),
    );

    expect(find.text('도착 예정'), findsOneWidget);
  });
```

- [ ] **Step 2: 실패를 확인한다**

```powershell
flutter test test/widgets/eta_card_test.dart
```

기대: `'headline은 도착 시각이 아니라 소요 시간이다'`가 FAIL — `find.textContaining('오전'|'오후')`가 headline을 찾아낸다. `'안내 중에는 도착 예정 시각이 그대로 남는다'`는 이미 PASS(회귀 방지용이다).

- [ ] **Step 3: headline을 바꾼다**

`client/lib/widgets/eta_card.dart`의 `build`를 바꾼다.

바꾸기 전:

```dart
  @override
  Widget build(BuildContext context) {
    final arrivalTime = TimeOfDay.fromDateTime(
      DateTime.now().add(Duration(minutes: minutes)),
    ).format(context);
    if (!guidanceStarted) {
      return RoutexEtaCard(
        title: label,
        arrivalTime: arrivalTime,
        metrics: [
          RoutexTripMetric(value: '$minutes분', label: '소요'),
          RoutexTripMetric(value: formatDistance(distanceMeters), label: '거리'),
          ?extraMetric,
        ],
        routeOptions: routeOptions,
        onStart: onStartGuidance,
      );
    }
```

바꾼 뒤:

```dart
  @override
  Widget build(BuildContext context) {
    final arrivalTime = TimeOfDay.fromDateTime(
      DateTime.now().add(Duration(minutes: minutes)),
    ).format(context);
    if (!guidanceStarted) {
      return RoutexEtaCard(
        title: label,
        // 이 자리가 카드의 headline이다. 도착 시각은 안내를 시작한 뒤 진행 바에서
        // 본다 — 출발 전에 두 화면이 같은 값을 두 벌로 말할 필요가 없다.
        arrivalTime: '$minutes분',
        metrics: [
          RoutexTripMetric(value: formatDistance(distanceMeters), label: '거리'),
          ?extraMetric,
        ],
        routeOptions: routeOptions,
        onStart: onStartGuidance,
      );
    }
```

`arrivalTime` 지역 변수는 아래 `RoutexTripProgress`가 계속 쓰므로 **지우지 않는다.**

- [ ] **Step 4: 통과를 확인한다**

```powershell
flutter test test/widgets/eta_card_test.dart test/widgets/eta_card_start_guidance_test.dart
```

기대: PASS, 전부. 기존 `'무엇을 향하는지와 소요·거리를 함께 적는다'`도 통과한다 — `'7분'`은 headline으로, `'480m'`은 metrics로 여전히 하나씩 있다.

- [ ] **Step 5: 커밋**

```powershell
git add client/lib/widgets/eta_card.dart client/test/widgets/eta_card_test.dart
git commit -m "fix: 계획 카드는 도착 시각 대신 소요 시간을 크게 적는다"
```

---

## Task 3: 안내 시작 GPS 가드

**Files:**
- Modify: `client/lib/screens/outdoor_map/outdoor_map_tuning.dart` (상수 추가)
- Modify: `client/lib/screens/outdoor_map/parts/guidance.dart:214-225` (`_startCurrentGuidance`)
- Test: `client/test/domain/guidance/guidance_start_reach_test.dart` (신규)

**Interfaces:**
- Consumes: `computeGeoRouteProgress({required List<LatLng> routePoints, required LatLng position, double? previousTraveledM, double searchWindowM})` → `GeoRouteProgress?` (`offsetM` 필드) — `client/lib/domain/guidance/geo_route_progress.dart`
- Produces: `bool canStartGuidanceFrom({required List<LatLng> routePoints, required LatLng? position, required double maxOffsetM})` — `client/lib/domain/guidance/guidance_start_reach.dart` (신규). Task 3 안에서만 쓰인다.

**왜 이렇게 하나:** `_startCurrentGuidance`가 지금 조건 없이 `startFollowingCurrentLocation()`을 불러 카메라를 실제 GPS로 끌고 간다. 경로가 다른 동네에 그려져 있어도 그렇게 해서, 보던 경로가 화면에서 통째로 사라진다.

**판정을 순수 함수로 떼는 이유:** `_startCurrentGuidance`는 `OutdoorMapBodyState`의 `part`라 위젯 테스트 없이는 못 부른다. 판정만 `domain/`으로 내리면 경계값을 값 테스트로 지킬 수 있다. 그리기·카메라는 Task 8의 기기 확인이 맡는다.

`previousTraveledM`을 넘기지 않는 것이 핵심이다 — 넘기면 검색 창(`searchWindowM`)이 걸려 멀리 있는 위치에서 엉뚱한 값이 나온다. 안 넘기면 경로 전체에서 가장 가까운 점을 찾는다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`client/test/domain/guidance/guidance_start_reach_test.dart`를 새로 만든다.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/guidance/guidance_start_reach.dart';

/// 안내를 시작해도 되는 위치인지 판정한다. 경계값은
/// `docs/superpowers/specs/2026-08-19-transit-screen-redesign-design.md` 3절.
void main() {
  // 서울시청 앞에서 동쪽으로 뻗은 짧은 선. 위도 1도 ≈ 111 km라
  // 경도 0.001도 ≈ 88 m(위도 37.5에서)다.
  const route = [LatLng(37.5665, 126.9780), LatLng(37.5665, 126.9880)];

  test('경로 위에 서 있으면 시작할 수 있다', () {
    expect(
      canStartGuidanceFrom(
        routePoints: route,
        position: const LatLng(37.5665, 126.9800),
        maxOffsetM: 150,
      ),
      isTrue,
    );
  });

  test('경로에서 한참 떨어져 있으면 시작할 수 없다', () {
    // 위도 +0.01도 ≈ 1.1 km 북쪽.
    expect(
      canStartGuidanceFrom(
        routePoints: route,
        position: const LatLng(37.5765, 126.9800),
        maxOffsetM: 150,
      ),
      isFalse,
    );
  });

  test('위치를 모르면 시작할 수 없다', () {
    expect(
      canStartGuidanceFrom(
        routePoints: route,
        position: null,
        maxOffsetM: 150,
      ),
      isFalse,
    );
  });

  test('경로가 선을 이루지 못하면 시작할 수 없다', () {
    expect(
      canStartGuidanceFrom(
        routePoints: const [LatLng(37.5665, 126.9780)],
        position: const LatLng(37.5665, 126.9780),
        maxOffsetM: 150,
      ),
      isFalse,
    );
  });
}
```

- [ ] **Step 2: 실패를 확인한다**

```powershell
flutter test test/domain/guidance/guidance_start_reach_test.dart
```

기대: FAIL — `guidance_start_reach.dart`가 없어 컴파일이 안 된다.

- [ ] **Step 3: 판정 함수를 만든다**

`client/lib/domain/guidance/guidance_start_reach.dart`를 새로 만든다.

```dart
import 'package:latlong2/latlong.dart';

import 'geo_route_progress.dart';

/// 지금 위치에서 안내를 시작해도 되는지.
///
/// [position]이 null이거나 [routePoints]가 선을 이루지 못하면 false다. 위치를
/// 모르는 채 카메라만 옮기면 사용자는 자기가 어디 있는지 모르는 화면을 본다.
///
/// [computeGeoRouteProgress]에 `previousTraveledM`을 넘기지 않는 것이 핵심이다.
/// 넘기면 검색 창이 걸려 멀리 있는 위치에서 엉뚱한 구간에 붙는다.
bool canStartGuidanceFrom({
  required List<LatLng> routePoints,
  required LatLng? position,
  required double maxOffsetM,
}) {
  if (position == null) return false;
  final progress = computeGeoRouteProgress(
    routePoints: routePoints,
    position: position,
  );
  if (progress == null) return false;
  return progress.offsetM <= maxOffsetM;
}
```

- [ ] **Step 4: 통과를 확인한다**

```powershell
flutter test test/domain/guidance/guidance_start_reach_test.dart
```

기대: PASS, 4개.

- [ ] **Step 5: 상수를 추가한다**

`client/lib/screens/outdoor_map/outdoor_map_tuning.dart`의 `lowAccuracyThresholdMeters` 선언 **바로 뒤**에 넣는다.

```dart
/// 안내를 시작할 수 있는 경로로부터의 최대 거리(m).
///
/// **실측이 아니라 가정이다.** 도심 GPS 오차([lowAccuracyThresholdMeters], 30 m)와
/// 이면도로 한 블록을 덮되, 다른 동네에서 누르면 확실히 걸리는 값으로 잡았다.
/// [outdoorRouteMaxProjectionOffsetM](25 m)을 쓰지 않는 이유는 그 값이 "걸어온
/// 자취를 경로 위에 그려도 되는가"라 훨씬 엄격해서다 — 그 기준으로 막으면 출발선에
/// 선 사용자도 GPS가 한 번 튀면 시작하지 못한다. 현장에서 조정할 자리다.
const guidanceStartMaxOffsetM = 150.0;
```

- [ ] **Step 6: 가드를 단다**

`client/lib/screens/outdoor_map/parts/guidance.dart`의 `_startCurrentGuidance`를 바꾼다.

바꾸기 전:

```dart
  /// 계획 카드의 `안내 시작`을 모든 이동수단에서 같은 상태 전이로 처리한다.
  Future<void> _startCurrentGuidance() async {
    if (_indoorRoutePreviewOrigin != null) {
      await _startIndoorGuidance();
      return;
    }
    if (_guidanceStarted || !_hasAnyRouteVisible) return;
    setState(() {
      _guidanceStarted = true;
    });
```

바꾼 뒤:

```dart
  /// 계획 카드의 `안내 시작`을 모든 이동수단에서 같은 상태 전이로 처리한다.
  ///
  /// **경로에서 멀면 아무것도 바꾸지 않는다.** 실내가 건물 밖에서 그렇게 하는
  /// 것과 같은 이유다([_startIndoorGuidance]) — 카메라를 GPS로 끌고 가 봐야
  /// 보던 경로가 화면에서 사라질 뿐이다. 도보도 함께 막는다. 카메라를 안 옮겨도
  /// 안내 상태로 들어가면 엉뚱한 위치에서 진행 판정이 돌기 시작한다.
  Future<void> _startCurrentGuidance() async {
    if (_indoorRoutePreviewOrigin != null) {
      await _startIndoorGuidance();
      return;
    }
    if (_guidanceStarted || !_hasAnyRouteVisible) return;
    // 좌표를 못 얻는 경로(실내 구간만 살아 있는 경우)에는 가드를 걸지 않는다.
    // 잴 수 없는 것을 막으면 지금 되던 흐름이 조용히 죽는다.
    final points = _guidanceStartRoutePoints;
    if (points.length >= 2 &&
        !canStartGuidanceFrom(
          routePoints: points,
          position: _positionPoint,
          maxOffsetM: guidanceStartMaxOffsetM,
        )) {
      _showSnack('경로 근처에 있을 때 안내를 시작할 수 있습니다.');
      return;
    }
    setState(() {
      _guidanceStarted = true;
    });
```

- [ ] **Step 7: 좌표를 꺼내는 getter 둘을 더한다**

`_startCurrentGuidance` **바로 위**에 넣는다. 필드 이름은 확인해 둔 것이다 —
`DirectionsRoute? _route`(`outdoor_map_screen.dart:392`, `.points`를 가진다),
`TransitItinerary? _transitItinerary`(`:463`), `Position? _position`(`:384`).

```dart
  /// 안내 시작 판정에 쓸, 지금 지도에 그려진 야외 경로의 좌표열.
  ///
  /// 실내 경로만 살아 있으면 빈 목록이다 — 실내는 [_startIndoorGuidance]가
  /// 자기 가드를 이미 갖고 있어서 여기서 다시 막지 않는다.
  List<ll.LatLng> get _guidanceStartRoutePoints {
    final route = _route;
    if (route != null) return route.points;
    final transit = _transitItinerary;
    if (transit == null) return const [];
    return [for (final leg in transit.legs) ...leg.points];
  }

  /// 마지막으로 받은 GPS를 위경도로. 아직 못 받았으면 null이다.
  ll.LatLng? get _positionPoint {
    final position = _position;
    if (position == null) return null;
    return ll.LatLng(position.latitude, position.longitude);
  }
```

`parts/guidance.dart`는 `part of '../outdoor_map_screen.dart'`이므로 **import는 그 파일에 넣는다.**

```dart
import '../../domain/guidance/guidance_start_reach.dart';
```

`outdoor_map_screen.dart`의 기존 `domain/guidance/` import 옆에 둔다. `ll`은 그 파일이 이미 쓰는 `latlong2` 별칭이다.

- [ ] **Step 8: 분석과 전체 테스트**

```powershell
flutter analyze
flutter test
```

기대: 오류 0. 계층 테스트(`lib_layer_direction_test.dart`)도 통과한다 — `domain/`(1층)이 `domain/`을 부르고, `screens/`(4층)가 `domain/`을 부르는 방향이다.

- [ ] **Step 9: 커밋**

```powershell
git add client/lib/domain/guidance/guidance_start_reach.dart client/test/domain/guidance/guidance_start_reach_test.dart client/lib/screens/outdoor_map/outdoor_map_tuning.dart client/lib/screens/outdoor_map/parts/guidance.dart
git commit -m "fix: 경로에서 멀면 안내를 시작하지 않고 이유를 알린다"
```

---

## Task 4: 뒤로가기가 앱을 끄지 않는다

**Files:**
- Modify: `client/lib/screens/map_shell/map_shell_screen.dart:2256-2266`
- Test: `client/test/screens/map_shell/back_steps_out_of_route_test.dart` (신규)

**Interfaces:**
- Consumes: `_searchActive`(bool), `_outdoorRouteVisible`(bool), `_closeSearch()`, `_clearRouteDraft()` — 전부 같은 파일에 이미 있다
- Produces: 없음.

**왜 이렇게 하나:** 루트 `PopScope`가 `canPop: !_searchActive` 하나뿐이다. 대중교통 경로를 고르면 시트가 닫히고 지도에 요약 카드만 남는데, 이때 `_searchActive`는 false라 뒤로가기가 루트 라우트를 pop해 **앱이 종료된다.**

`_clearRouteDraft()`는 상단 길찾기 바의 X가 부르는 것과 같다 — 지도 경로·핀·길찾기 상태를 한 번에 정리한다. 뒤로가기가 같은 것을 부르게 해서 정리 경로를 두 벌로 만들지 않는다.

한 번 누르면 한 겹만 벗긴다. 검색과 경로가 둘 다 살아 있으면 검색이 먼저다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`client/test/screens/map_shell/back_steps_out_of_route_test.dart`를 새로 만든다. **`route_mode_test.dart`의 하네스를 그대로 베낀다** — `setUp`/`tearDown`의 저장소 교체, `fix()`, `drain()`이 없으면 `MapShellScreen`이 뜨지 않는다.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/screens/map_shell/map_shell_screen.dart';

/// 뒤로가기가 상태를 한 겹씩 벗기는지. 경로가 그려진 채 누르면 앱이 꺼지던
/// 회귀를 막는다.
void main() {
  // TODO(실행자): route_mode_test.dart의 main() 앞부분(변수 선언·fix()·drain()·
  // setUp·tearDown)을 그대로 복사해 여기에 붙인다. 그 하네스 없이는 화면이 뜨지
  // 않는다. 아래 testWidgets만 새로 쓰는 부분이다.

  testWidgets('경로가 그려져 있으면 뒤로가기가 앱을 끄지 않고 경로만 지운다', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: MapShellScreen()));
    await drain(tester);

    final state = tester.state<State<MapShellScreen>>(
      find.byType(MapShellScreen),
    );
    // 경로가 그려진 상태를 만든다. 실제 길찾기를 태우는 대신 화면이 읽는
    // 플래그만 세운다 — 이 테스트가 확인하는 것은 pop 분기이지 경로 조회가 아니다.
    // ignore: invalid_use_of_protected_member
    state.setState(() {});
    final popScope = tester.widget<PopScope<Object?>>(
      find.byType(PopScope<Object?>).first,
    );

    expect(popScope.canPop, isFalse);
  });
}
```

- [ ] **Step 2: 테스트를 실제 상태에 맞춘다**

Step 1의 `setState(() {})`는 자리 표시다. `_outdoorRouteVisible`은 private이라 밖에서 못 만진다. 화면이 그 값을 어떻게 받는지 따라간다.

```powershell
Select-String -Path lib/screens/map_shell/map_shell_screen.dart -Pattern "_outdoorRouteVisible = visible" -Context 6,2
```

2304행 근처에서 `OutdoorMapBody`의 콜백이 세운다. 테스트에서는 그 콜백을 직접 부를 수 없으므로 **둘 중 하나**를 고른다.

- **(a) 권장** — `route_mode_test.dart`가 이미 하는 방식대로 목적지를 골라 실제로 경로를 그리게 한 뒤 뒤로가기를 누른다. 그 파일의 `'목적지를 고르면 경로가 그려진다'` 계열 테스트를 찾아 그 앞부분을 그대로 쓴다.
- **(b)** 경로를 못 그리면, `canPop` 대신 **뒤로가기를 실제로 눌러** 앱이 살아 있는지 본다:

```dart
    await tester.binding.handlePopRoute();
    await drain(tester);
    expect(find.byType(MapShellScreen), findsOneWidget);
```

(a)로 되면 (a)를 쓴다. 실제 사용자 경로를 그대로 밟는 쪽이 회귀를 더 잘 잡는다.

- [ ] **Step 3: 실패를 확인한다**

```powershell
flutter test test/screens/map_shell/back_steps_out_of_route_test.dart
```

기대: FAIL. `canPop`이 true이거나(a: 경로가 그려졌는데도) 화면이 사라진다(b).

- [ ] **Step 4: PopScope를 고친다**

`client/lib/screens/map_shell/map_shell_screen.dart`의 `build`를 바꾼다.

바꾸기 전:

```dart
  @override
  Widget build(BuildContext context) {
    final routeVisible = _outdoorRouteVisible;
    // 시트였을 때는 뒤로가기가 시트만 닫았다. 패널로 바뀌었다고 뒤로가기가
    // 앱을 종료해 버리면 안 되므로, 검색 중에는 pop을 가로채 검색만 닫는다.
    return PopScope(
      canPop: !_searchActive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeSearch();
      },
      child: _buildShell(context, routeVisible),
    );
  }
```

바꾼 뒤:

```dart
  @override
  Widget build(BuildContext context) {
    final routeVisible = _outdoorRouteVisible;
    // 시트였을 때는 뒤로가기가 시트만 닫았다. 패널로 바뀌었다고 뒤로가기가
    // 앱을 종료해 버리면 안 되므로, 열려 있는 것을 한 겹씩 벗긴다. 경로가
    // 그려진 채로 pop시키면 앱이 통째로 종료된다 — 대중교통 경로를 고른 뒤
    // 뒤로가기를 눌러 앱이 꺼지던 것이 그 경우다.
    return PopScope(
      canPop: !_searchActive && !routeVisible,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // 검색이 먼저다. 둘 다 살아 있으면 한 번에 한 겹만 벗긴다.
        if (_searchActive) {
          _closeSearch();
          return;
        }
        // 상단 길찾기 바의 X와 같은 정리다. 종료 동작을 두 벌로 만들지 않는다.
        if (routeVisible) _clearRouteDraft();
      },
      child: _buildShell(context, routeVisible),
    );
  }
```

- [ ] **Step 5: 통과를 확인한다**

```powershell
flutter test test/screens/map_shell/back_steps_out_of_route_test.dart test/screens/map_shell/route_mode_test.dart test/screens/map_shell/route_draft_clear_test.dart
```

기대: PASS, 전부.

- [ ] **Step 6: 커밋**

```powershell
git add client/lib/screens/map_shell/map_shell_screen.dart client/test/screens/map_shell/back_steps_out_of_route_test.dart
git commit -m "fix: 경로가 그려진 채 뒤로가기를 눌러도 앱이 꺼지지 않는다"
```

---

## Task 5: 대중교통 수단 필터

**Files:**
- Create: `client/lib/domain/route/transit_itinerary_filter.dart`
- Test: `client/test/domain/route/transit_itinerary_filter_test.dart`

**Interfaces:**
- Consumes: `TransitItinerary`(`legs` 필드), `TransitLeg`(`mode` 필드), `TransitMode`(`walk`/`bus`/`subway`/`train`/`expressBus`/`airplane`/`ferry`/`unknown`, `isWalk` getter) — `client/lib/models/route/transit_route.dart`
- Produces:
  - `enum TransitFilter { all, bus, subway, busAndSubway }` — `label` getter(`'전체'`/`'버스'`/`'지하철'`/`'버스+지하철'`)
  - `TransitFilter classifyItinerary(TransitItinerary itinerary)` — `all`은 "어디에도 안 맞음"을 뜻한다
  - `List<TransitFilter> availableTransitFilters(List<TransitItinerary> itineraries)` — 항상 `all`로 시작, 0건인 갈래는 빠진다
  - `int transitFilterCount(List<TransitItinerary> itineraries, TransitFilter filter)`
  - `List<TransitItinerary> applyTransitFilter(List<TransitItinerary> itineraries, TransitFilter filter)`

**왜 이렇게 하나:** 받은 경로만으로 계산하므로 새 요청이 없다. 순수 함수라 위젯 없이 경계값을 지킬 수 있다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`client/test/domain/route/transit_itinerary_filter_test.dart`를 새로 만든다.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/route/transit_itinerary_filter.dart';
import 'package:navigation_client/models/route/transit_route.dart';

void main() {
  TransitLeg leg(TransitMode mode) => TransitLeg(
    mode: mode,
    sectionTimeSeconds: 600,
    distanceMeters: 500,
    points: const [],
  );

  TransitItinerary itinerary(List<TransitMode> modes) => TransitItinerary(
    totalTimeSeconds: 1200,
    totalWalkTimeSeconds: 300,
    totalDistanceMeters: 3000,
    transferCount: modes.where((m) => !m.isWalk).length - 1,
    legs: [for (final mode in modes) leg(mode)],
  );

  final busOnly = itinerary([
    TransitMode.walk,
    TransitMode.bus,
    TransitMode.walk,
  ]);
  final subwayOnly = itinerary([TransitMode.walk, TransitMode.subway]);
  final mixed = itinerary([
    TransitMode.bus,
    TransitMode.subway,
    TransitMode.walk,
  ]);
  final train = itinerary([TransitMode.walk, TransitMode.train]);
  final walkOnly = itinerary([TransitMode.walk]);

  group('분류', () {
    test('도보를 빼고 버스만 남으면 버스다', () {
      expect(classifyItinerary(busOnly), TransitFilter.bus);
    });

    test('도보를 빼고 지하철만 남으면 지하철이다', () {
      expect(classifyItinerary(subwayOnly), TransitFilter.subway);
    });

    test('버스와 지하철을 함께 타면 버스+지하철이다', () {
      expect(classifyItinerary(mixed), TransitFilter.busAndSubway);
    });

    test('기차처럼 갈래가 없는 수단은 전체에만 남는다', () {
      expect(classifyItinerary(train), TransitFilter.all);
    });

    test('탈것이 하나도 없으면 전체에만 남는다', () {
      expect(classifyItinerary(walkOnly), TransitFilter.all);
    });
  });

  group('탭 목록', () {
    test('전체가 항상 맨 앞이고 0건인 갈래는 빠진다', () {
      expect(availableTransitFilters([busOnly, busOnly, mixed]), [
        TransitFilter.all,
        TransitFilter.bus,
        TransitFilter.busAndSubway,
      ]);
    });

    test('경로가 없으면 전체만 남는다', () {
      expect(availableTransitFilters([]), [TransitFilter.all]);
    });
  });

  group('집계와 적용', () {
    test('전체는 전부를 센다', () {
      expect(
        transitFilterCount([busOnly, subwayOnly, train], TransitFilter.all),
        3,
      );
    });

    test('갈래는 그 갈래만 센다', () {
      expect(
        transitFilterCount([busOnly, subwayOnly, train], TransitFilter.bus),
        1,
      );
    });

    test('전체는 순서를 바꾸지 않고 그대로 돌려준다', () {
      final input = [busOnly, subwayOnly, train];
      expect(applyTransitFilter(input, TransitFilter.all), input);
    });

    test('갈래는 그 갈래만 남긴다', () {
      expect(
        applyTransitFilter([busOnly, subwayOnly, train], TransitFilter.subway),
        [subwayOnly],
      );
    });
  });
}
```

- [ ] **Step 2: 실패를 확인한다**

```powershell
flutter test test/domain/route/transit_itinerary_filter_test.dart
```

기대: FAIL — `transit_itinerary_filter.dart`가 없어 컴파일이 안 된다.

- [ ] **Step 3: 필터를 만든다**

`client/lib/domain/route/transit_itinerary_filter.dart`를 새로 만든다.

```dart
/// 대중교통 결과 목록의 수단 갈래. 받은 경로만으로 계산하며 새 요청이 없다.
library;

import '../../models/route/transit_route.dart';

/// 결과 목록 위의 탭 한 칸.
///
/// [all]은 두 가지 뜻을 겸한다 — 탭으로는 "전부 보기"이고, 분류 결과로는
/// "버스·지하철 어느 갈래에도 안 맞음"이다. 기차·고속버스처럼 갈래가 없는
/// 수단에 탭을 새로 파지 않으려는 것이다.
enum TransitFilter {
  all,
  bus,
  subway,
  busAndSubway;

  String get label => switch (this) {
    TransitFilter.all => '전체',
    TransitFilter.bus => '버스',
    TransitFilter.subway => '지하철',
    TransitFilter.busAndSubway => '버스+지하철',
  };
}

/// [itinerary]가 어느 갈래인지. 도보 구간은 세지 않는다 — 어느 경로든 도보가
/// 붙어 있어서, 넣고 세면 모든 경로가 같은 갈래가 된다.
TransitFilter classifyItinerary(TransitItinerary itinerary) {
  final modes = {
    for (final leg in itinerary.legs)
      if (!leg.mode.isWalk) leg.mode,
  };
  if (modes.length == 1 && modes.first == TransitMode.bus) {
    return TransitFilter.bus;
  }
  if (modes.length == 1 && modes.first == TransitMode.subway) {
    return TransitFilter.subway;
  }
  if (modes.length == 2 &&
      modes.contains(TransitMode.bus) &&
      modes.contains(TransitMode.subway)) {
    return TransitFilter.busAndSubway;
  }
  return TransitFilter.all;
}

/// 그릴 탭 목록. [TransitFilter.all]이 항상 맨 앞이고, 0건인 갈래는 뺀다 —
/// 눌러도 빈 목록만 나오는 탭은 사용자에게 고장으로 읽힌다.
List<TransitFilter> availableTransitFilters(
  List<TransitItinerary> itineraries,
) {
  final present = itineraries.map(classifyItinerary).toSet();
  return [
    TransitFilter.all,
    for (final filter in const [
      TransitFilter.bus,
      TransitFilter.subway,
      TransitFilter.busAndSubway,
    ])
      if (present.contains(filter)) filter,
  ];
}

/// 탭 라벨에 붙일 개수.
int transitFilterCount(
  List<TransitItinerary> itineraries,
  TransitFilter filter,
) => filter == TransitFilter.all
    ? itineraries.length
    : itineraries.where((it) => classifyItinerary(it) == filter).length;

/// 목록을 좁힌다. 순서는 바꾸지 않는다 — 정렬은 응답이 준 그대로가 단일 출처다.
List<TransitItinerary> applyTransitFilter(
  List<TransitItinerary> itineraries,
  TransitFilter filter,
) => filter == TransitFilter.all
    ? itineraries
    : [for (final it in itineraries) if (classifyItinerary(it) == filter) it];
```

- [ ] **Step 4: 통과를 확인한다**

```powershell
flutter test test/domain/route/transit_itinerary_filter_test.dart
```

기대: PASS, 11개.

- [ ] **Step 5: 커밋**

```powershell
git add client/lib/domain/route/transit_itinerary_filter.dart client/test/domain/route/transit_itinerary_filter_test.dart
git commit -m "feat: 대중교통 결과를 수단별로 가르는 필터를 추가한다"
```

---

## Task 6: 대중교통 결과 카드

**Files:**
- Create: `client/lib/widgets/transit_itinerary_card.dart`
- Test: `client/test/widgets/transit_itinerary_card_test.dart`

**Interfaces:**
- Consumes: `TransitItinerary`(`totalTimeSeconds`/`fare`/`legs`), `TransitLeg`(`mode`/`sectionTimeSeconds`/`routeName`/`shortLabel`/`startName`/`endName`/`stationCount`) — `client/lib/models/route/transit_route.dart`. `transitLegColor(TransitLeg)`, `transitModeIcon(TransitMode)`, `formatTransitDuration(int)`, `formatTransitFare(int)` — `client/lib/widgets/transit_style.dart`
- Produces: `TransitItineraryCard({required TransitItinerary itinerary, required bool fastest, required bool expanded, required ValueChanged<bool> onExpanded, required VoidCallback onTap, bool selected})` — Task 7이 쓴다. **stateless다** — 펼침 상태는 시트가 들고 있다.

**왜 이렇게 하나:** 디자인시스템의 `RoutexTransitItinerary`는 소요 + 사실 목록 + 배지 스트립 구조라 비율 막대와 승·하차 블록을 놓을 자리가 없다. 공급 저장소를 고치는 것은 이번 범위 밖이라 앱 쪽에 새로 그린다. 색·간격·타이포는 전부 DS 토큰을 쓴다.

실시간 도착·혼잡도·기후동행은 **그리지 않는다.** 카카오 응답에 없다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`client/test/widgets/transit_itinerary_card_test.dart`를 새로 만든다.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/models/route/transit_route.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/widgets/transit_itinerary_card.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  TransitLeg leg({
    required TransitMode mode,
    int seconds = 600,
    String? routeName,
    String? startName,
    String? endName,
    int stationCount = 0,
  }) => TransitLeg(
    mode: mode,
    sectionTimeSeconds: seconds,
    distanceMeters: 500,
    points: const [],
    routeName: routeName,
    startName: startName,
    endName: endName,
    stationCount: stationCount,
  );

  final ride = TransitItinerary(
    totalTimeSeconds: 1140,
    totalWalkTimeSeconds: 300,
    totalDistanceMeters: 3000,
    transferCount: 0,
    fare: 1500,
    legs: [
      leg(mode: TransitMode.walk, seconds: 60),
      leg(
        mode: TransitMode.bus,
        seconds: 660,
        routeName: '지선:7613',
        startName: '삼부아파트',
        endName: '공덕역2번출구',
        stationCount: 2,
      ),
      leg(mode: TransitMode.walk, seconds: 240),
    ],
  );

  Widget card(TransitItinerary itinerary, {bool expanded = false}) =>
      wrap(
        TransitItineraryCard(
          itinerary: itinerary,
          fastest: true,
          expanded: expanded,
          onExpanded: (_) {},
          onTap: () {},
        ),
      );

  testWidgets('소요·요금·노선·정류장 수를 적는다', (tester) async {
    await tester.pumpWidget(card(ride));

    expect(find.text('19분'), findsOneWidget);
    expect(find.text('1,500원'), findsOneWidget);
    expect(find.text('7613'), findsOneWidget);
    expect(find.text('삼부아파트'), findsOneWidget);
    expect(find.text('공덕역2번출구'), findsOneWidget);
    expect(find.textContaining('2정류장'), findsOneWidget);
  });

  testWidgets('첫 줄이면 최적 배지를 단다', (tester) async {
    await tester.pumpWidget(card(ride));

    expect(find.text('최적'), findsOneWidget);
  });

  testWidgets('도착 시각을 함께 적는다', (tester) async {
    await tester.pumpWidget(card(ride));

    expect(find.textContaining('도착'), findsWidgets);
  });

  testWidgets('요금이 없으면 요금 칸을 그리지 않는다', (tester) async {
    final noFare = TransitItinerary(
      totalTimeSeconds: 1140,
      totalWalkTimeSeconds: 300,
      totalDistanceMeters: 3000,
      transferCount: 0,
      legs: ride.legs,
    );
    await tester.pumpWidget(card(noFare));

    expect(find.textContaining('원'), findsNothing);
  });

  testWidgets('탈것이 없으면 승하차 줄을 그리지 않는다', (tester) async {
    final walkOnly = TransitItinerary(
      totalTimeSeconds: 600,
      totalWalkTimeSeconds: 600,
      totalDistanceMeters: 700,
      transferCount: 0,
      legs: [leg(mode: TransitMode.walk, seconds: 600)],
    );
    await tester.pumpWidget(card(walkOnly));

    expect(find.text('하차'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('총 소요가 0이어도 던지지 않는다', (tester) async {
    final zero = TransitItinerary(
      totalTimeSeconds: 0,
      totalWalkTimeSeconds: 0,
      totalDistanceMeters: 0,
      transferCount: 0,
      legs: [leg(mode: TransitMode.walk, seconds: 0)],
    );
    await tester.pumpWidget(card(zero));

    expect(tester.takeException(), isNull);
  });

  testWidgets('펼치면 구간별 줄이 나온다', (tester) async {
    await tester.pumpWidget(card(ride, expanded: true));

    expect(find.text('상세보기'), findsOneWidget);
    // 접혀 있을 때는 없던 도보 구간 시간이 펼치면 보인다.
    expect(find.textContaining('도보'), findsWidgets);
  });
}
```

- [ ] **Step 2: 실패를 확인한다**

```powershell
flutter test test/widgets/transit_itinerary_card_test.dart
```

기대: FAIL — `transit_itinerary_card.dart`가 없어 컴파일이 안 된다.

- [ ] **Step 3: 카드를 만든다**

`client/lib/widgets/transit_itinerary_card.dart`를 새로 만든다.

```dart
import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../models/route/transit_route.dart';
import 'transit_style.dart';

/// 대중교통 경로 후보 한 장.
///
/// 실시간 도착·혼잡도·기후동행은 그리지 않는다 — 카카오 응답에 없다. 없는 칸은
/// 자리도 남기지 않는다. 근거는
/// `docs/superpowers/specs/2026-08-19-transit-screen-redesign-design.md`.
class TransitItineraryCard extends StatelessWidget {
  const TransitItineraryCard({
    super.key,
    required this.itinerary,
    required this.fastest,
    required this.expanded,
    required this.onExpanded,
    required this.onTap,
    this.selected = false,
  });

  final TransitItinerary itinerary;

  /// 목록 첫 줄인지. 맞으면 `최적` 배지를 단다 — 정렬의 뜻을 밝히지 않으면
  /// 사용자가 첫 줄이 왜 첫 줄인지 추측해야 한다.
  final bool fastest;

  /// 상세보기가 펼쳐져 있는지. **상태는 목록이 들고 있다** — 카드마다 두면
  /// 여러 줄이 동시에 펼쳐져 목록이 화면 밖으로 밀린다.
  final bool expanded;

  final ValueChanged<bool> onExpanded;
  final VoidCallback onTap;
  final bool selected;

  /// 탈것 구간만. 승·하차 줄과 노선 배지가 읽는 값이다.
  List<TransitLeg> get _rides =>
      [for (final leg in itinerary.legs) if (!leg.mode.isWalk) leg];

  @override
  Widget build(BuildContext context) {
    final colors = context.routexColors;
    final fare = itinerary.fare;
    final rides = _rides;
    final arrival = TimeOfDay.fromDateTime(
      DateTime.now().add(Duration(seconds: itinerary.totalTimeSeconds)),
    ).format(context);

    return Material(
      color: selected ? colors.actionPrimarySubtle : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(RoutexSpacing.contentGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (fastest) ...[
                const RoutexBadge(label: '최적', tone: RoutexBadgeTone.info),
                const SizedBox(height: RoutexSpacing.inlineGap),
              ],
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: RoutexSpacing.controlGap,
                runSpacing: RoutexSpacing.inlineGap,
                children: [
                  Text(
                    formatTransitDuration(itinerary.totalTimeSeconds),
                    style: RoutexTypography.tabular(RoutexTypography.headline),
                  ),
                  Text(
                    '$arrival 도착',
                    style: RoutexTypography.bodySmall.copyWith(
                      color: colors.contentSecondary,
                    ),
                  ),
                  if (fare != null && fare > 0)
                    Text(
                      formatTransitFare(fare),
                      style: RoutexTypography.bodySmall.copyWith(
                        color: colors.contentSecondary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: RoutexSpacing.contentGap),
              _LegBar(itinerary: itinerary),
              if (rides.isNotEmpty) ...[
                const SizedBox(height: RoutexSpacing.contentGap),
                for (final ride in rides) _RideRow(leg: ride),
                if (rides.last.endName case final drop?) ...[
                  const SizedBox(height: RoutexSpacing.inlineGap),
                  _LabeledRow(label: '하차', value: drop),
                ],
              ],
              const SizedBox(height: RoutexSpacing.inlineGap),
              RoutexDisclosure(
                // header는 String이 아니라 Widget이다.
                header: const Text('상세보기', style: RoutexTypography.bodySmall),
                expanded: expanded,
                onExpanded: onExpanded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final leg in itinerary.legs) _StepRow(leg: leg),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 구간을 소요 시간 비율대로 이은 막대.
///
/// 총 소요가 0이면 그리지 않는다 — 비율을 낼 수 없다. 짧은 구간이 사라지지
/// 않도록 [Expanded]의 flex를 최소 1로 올린다. 비율이 그만큼 거짓이 되지만,
/// 1픽셀짜리 칸은 있으나 마나다.
class _LegBar extends StatelessWidget {
  const _LegBar({required this.itinerary});

  final TransitItinerary itinerary;

  @override
  Widget build(BuildContext context) {
    final total = itinerary.totalTimeSeconds;
    if (total <= 0 || itinerary.legs.isEmpty) return const SizedBox.shrink();
    final colors = context.routexColors;

    return SizedBox(
      height: 20,
      child: Row(
        children: [
          for (final leg in itinerary.legs)
            Expanded(
              flex: (leg.sectionTimeSeconds * 100 / total).round().clamp(
                1,
                100,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: leg.mode.isWalk
                        ? colors.contentSecondary.withValues(alpha: 0.25)
                        : transitLegColor(leg),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      formatTransitDuration(leg.sectionTimeSeconds),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: RoutexTypography.caption.copyWith(
                        color: leg.mode.isWalk
                            ? colors.contentSecondary
                            : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 탈것 한 줄 — 수단 배지 + 승차 정류장 + 노선 번호 + 정류장 수.
class _RideRow extends StatelessWidget {
  const _RideRow({required this.leg});

  final TransitLeg leg;

  /// `간선:472`의 앞머리. 카카오는 접두사를 안 주므로 수단 이름으로 떨어진다.
  String get _kind {
    final route = leg.routeName;
    if (route == null) return leg.modeLabel;
    final colon = route.indexOf(':');
    if (colon <= 0) return leg.modeLabel;
    return route.substring(0, colon);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.routexColors;
    final color = transitLegColor(leg);

    return Padding(
      padding: const EdgeInsets.only(bottom: RoutexSpacing.inlineGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RoutexBadge(
            label: _kind,
            icon: transitModeIcon(leg.mode),
            accent: RoutexBadgeAccent(
              surface: color.withValues(alpha: 0.14),
              ink: color,
            ),
          ),
          const SizedBox(width: RoutexSpacing.controlGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (leg.startName case final board?)
                  Text(board, style: RoutexTypography.body),
                const SizedBox(height: RoutexSpacing.inlineGap),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: RoutexSpacing.controlGap,
                  children: [
                    Text(
                      leg.shortLabel,
                      style: RoutexTypography.tabular(
                        RoutexTypography.body,
                      ).copyWith(color: color),
                    ),
                    if (leg.stationCount > 0)
                      Text(
                        '${leg.stationCount}정류장',
                        style: RoutexTypography.bodySmall.copyWith(
                          color: colors.contentSecondary,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LabeledRow extends StatelessWidget {
  const _LabeledRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.routexColors;
    return Row(
      children: [
        Text(
          label,
          style: RoutexTypography.bodySmall.copyWith(
            color: colors.contentSecondary,
          ),
        ),
        const SizedBox(width: RoutexSpacing.controlGap),
        Expanded(child: Text(value, style: RoutexTypography.body)),
      ],
    );
  }
}

/// 상세보기 안의 구간 한 줄. 도보까지 전부 적는다.
class _StepRow extends StatelessWidget {
  const _StepRow({required this.leg});

  final TransitLeg leg;

  @override
  Widget build(BuildContext context) {
    final colors = context.routexColors;
    final where = leg.startName;
    return Padding(
      padding: const EdgeInsets.only(bottom: RoutexSpacing.inlineGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            transitModeIcon(leg.mode),
            size: RoutexMetrics.iconSmall,
            color: leg.mode.isWalk
                ? colors.contentSecondary
                : transitLegColor(leg),
          ),
          const SizedBox(width: RoutexSpacing.controlGap),
          Expanded(
            child: Text(
              leg.mode.isWalk
                  ? '도보 ${formatTransitDuration(leg.sectionTimeSeconds)}'
                  : '${leg.shortLabel} · ${formatTransitDuration(leg.sectionTimeSeconds)}'
                        '${where == null ? '' : ' · $where 승차'}',
              style: RoutexTypography.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: 토큰 이름을 확인하고 맞춘다**

`RoutexSpacing.contentGap`·`inlineGap`·`controlGap`, `RoutexTypography.headline`·`body`·`bodySmall`·`caption`·`tabular()`, `RoutexMetrics.iconSmall`, `RoutexBadgeTone.info`, `RoutexBadgeAccent({surface, ink})`, `colors.contentSecondary`·`actionPrimarySubtle`는 기존 코드가 쓰는 이름이다. 그래도 컴파일로 확인한다.

```powershell
flutter analyze lib/widgets/transit_itinerary_card.dart
```

오류가 나면 `lib/widgets/transit_style.dart`와 `lib/widgets/transit_itinerary_tile.dart`에서 실제로 쓰는 이름을 찾아 맞춘다.

- [ ] **Step 5: 통과를 확인한다**

```powershell
flutter test test/widgets/transit_itinerary_card_test.dart
```

기대: PASS, 7개.

`'19분'`이 나오는 근거: `formatTransitDuration(1140)` = `(1140/60).ceil()` = 19.

- [ ] **Step 6: 커밋**

```powershell
git add client/lib/widgets/transit_itinerary_card.dart client/test/widgets/transit_itinerary_card_test.dart
git commit -m "feat: 대중교통 결과 카드에 구간 막대와 승하차 정보를 그린다"
```

---

## Task 7: 시트 조립 (Task 5·6 이후)

**Files:**
- Modify: `client/lib/screens/map_shell/widgets/sheets/transit_routes_sheet.dart`
- Delete: `client/lib/widgets/transit_itinerary_tile.dart`
- Test: `client/test/screens/map_shell/transit_routes_sheet_filter_test.dart` (신규)

**Interfaces:**
- Consumes: Task 5의 `TransitFilter`·`availableTransitFilters`·`transitFilterCount`·`applyTransitFilter`, Task 6의 `TransitItineraryCard`
- Produces: 없음. `TransitRoutesSheet`의 공개 파라미터는 그대로.

**왜 이렇게 하나:** 시트가 두 가지 상태를 든다 — 지금 고른 필터와 지금 펼쳐진 줄. 카드는 stateless로 남는다.

필터를 바꿔도 지도에 그려진 경로는 건드리지 않는다. 필터는 목록을 좁히는 것이지 선택을 바꾸는 것이 아니다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`client/test/screens/map_shell/transit_routes_sheet_filter_test.dart`를 새로 만든다.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/models/route/transit_route.dart';
import 'package:navigation_client/screens/map_shell/widgets/sheets/transit_routes_sheet.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/widgets/transit_itinerary_card.dart';

void main() {
  TransitLeg leg(TransitMode mode) => TransitLeg(
    mode: mode,
    sectionTimeSeconds: 600,
    distanceMeters: 500,
    points: const [],
    startName: '어딘가',
    endName: '어딘가2',
    stationCount: 2,
  );

  TransitItinerary itinerary(List<TransitMode> modes) => TransitItinerary(
    totalTimeSeconds: 1200,
    totalWalkTimeSeconds: 300,
    totalDistanceMeters: 3000,
    transferCount: 0,
    fare: 1500,
    legs: [for (final mode in modes) leg(mode)],
  );

  final routes = TransitRoutes(
    itineraries: [
      itinerary([TransitMode.walk, TransitMode.bus]),
      itinerary([TransitMode.walk, TransitMode.subway]),
      itinerary([TransitMode.walk, TransitMode.bus]),
    ],
  );

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: TransitRoutesSheet(
            routes: routes,
            destinationLabel: '목적지',
            onCloseAll: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('있는 갈래만 탭으로 세운다', (tester) async {
    await pumpSheet(tester);

    expect(find.textContaining('전체'), findsOneWidget);
    expect(find.textContaining('버스 2'), findsOneWidget);
    expect(find.textContaining('지하철 1'), findsOneWidget);
    // 버스+지하철 경로는 없으므로 탭도 없다.
    expect(find.textContaining('버스+지하철'), findsNothing);
  });

  testWidgets('탭을 고르면 목록이 좁혀진다', (tester) async {
    await pumpSheet(tester);

    expect(find.byType(TransitItineraryCard), findsNWidgets(3));

    await tester.tap(find.textContaining('지하철 1'));
    await tester.pumpAndSettle();

    expect(find.byType(TransitItineraryCard), findsOneWidget);
  });
}
```

`TransitRoutes`의 생성자 인자가 다르면 `lib/models/route/transit_route.dart`에서 실제 이름을 확인해 맞춘다.

- [ ] **Step 2: 실패를 확인한다**

```powershell
flutter test test/screens/map_shell/transit_routes_sheet_filter_test.dart
```

기대: FAIL — 탭이 없고 `TransitItineraryCard`도 안 쓰인다.

- [ ] **Step 3: 시트를 고친다**

`client/lib/screens/map_shell/widgets/sheets/transit_routes_sheet.dart`에서 import를 바꾼다.

바꾸기 전:

```dart
import '../../../../widgets/transit_itinerary_tile.dart';
```

바꾼 뒤:

```dart
import '../../../../domain/route/transit_itinerary_filter.dart';
import '../../../../widgets/transit_itinerary_card.dart';
```

`_TransitRoutesSheetState`에 상태 둘을 더한다.

```dart
  bool _intentionalPop = false;
  // 필터는 목록을 좁힐 뿐 지도에 그려진 경로를 바꾸지 않는다.
  TransitFilter _filter = TransitFilter.all;
  // 펼침은 한 번에 하나다. 카드마다 들면 여러 줄이 동시에 펼쳐진다.
  int? _expandedIndex;
```

`build`의 `final itineraries = widget.routes.itineraries;`를 바꾼다.

```dart
    final all = widget.routes.itineraries;
    final filters = availableTransitFilters(all);
    // 목록이 바뀌어 지금 필터가 사라졌으면 전체로 되돌린다. 그러지 않으면
    // 아무 탭도 안 눌린 채 빈 목록만 남는다.
    final filter = filters.contains(_filter) ? _filter : TransitFilter.all;
    final itineraries = applyTransitFilter(all, filter);
```

`SheetHeader`와 `RoutexDivider` **사이**에 탭을 넣는다.

```dart
                  const RoutexDivider(role: RoutexDividerRole.section),
                  RoutexTabs(
                    labels: [
                      for (final item in filters)
                        item == TransitFilter.all
                            ? item.label
                            : '${item.label} ${transitFilterCount(all, item)}',
                    ],
                    selectedIndex: filters.indexOf(filter),
                    onSelected: (index) => setState(() {
                      _filter = filters[index];
                      _expandedIndex = null;
                    }),
                  ),
```

`itemBuilder`를 바꾼다.

바꾸기 전:

```dart
                      itemBuilder: (context, index) => TransitItineraryTile(
                        itinerary: itineraries[index],
                        // 첫 줄은 정렬상 가장 빠른 경로다. 그 사실을 배지로
                        // 밝히지 않으면 사용자는 순서의 의미를 추측해야 한다.
                        fastest: index == 0 && itineraries.length > 1,
                        onTap: () => _pick(itineraries[index]),
                      ),
```

바꾼 뒤:

```dart
                      itemBuilder: (context, index) => TransitItineraryCard(
                        itinerary: itineraries[index],
                        // 첫 줄은 정렬상 가장 빠른 경로다. 그 사실을 배지로
                        // 밝히지 않으면 사용자는 순서의 의미를 추측해야 한다.
                        fastest: index == 0 && itineraries.length > 1,
                        expanded: _expandedIndex == index,
                        onExpanded: (open) =>
                            setState(() => _expandedIndex = open ? index : null),
                        onTap: () => _pick(itineraries[index]),
                      ),
```

- [ ] **Step 4: 통과를 확인한다**

```powershell
flutter test test/screens/map_shell/transit_routes_sheet_filter_test.dart
```

기대: PASS, 2개.

- [ ] **Step 5: 커밋**

```powershell
git add client/lib/screens/map_shell/widgets/sheets/transit_routes_sheet.dart client/test/screens/map_shell/transit_routes_sheet_filter_test.dart
git commit -m "feat: 대중교통 목록에 수단 필터 탭과 새 결과 카드를 붙인다"
```

- [ ] **Step 6: 낡은 타일을 지운다**

쓰는 곳이 없어졌는지 먼저 확인한다.

```powershell
Select-String -Path lib,test -Pattern "TransitItineraryTile" -Recurse
```

기대: 아무것도 안 나온다. 나오면 그곳을 먼저 고친다.

```powershell
git rm client/lib/widgets/transit_itinerary_tile.dart
flutter analyze
flutter test
```

- [ ] **Step 7: 삭제를 따로 커밋한다**

```powershell
git commit -m "chore: 쓰이지 않게 된 대중교통 타일 위젯을 지운다"
```

---

## Task 8: 통합 검증 (전부 이후)

**Files:** 없음 — 확인만 한다. 고칠 것이 나오면 해당 Task로 돌아간다.

**직렬이다.** 기기가 하나라 나눌 수 없다.

- [ ] **Step 1: 전체 분석과 테스트**

```powershell
flutter analyze
flutter test
```

기대: 오류 0, 실패 0. **계층 테스트와 주석 길이 테스트가 여기 포함된다** — 새 파일 셋(`guidance_start_reach.dart`, `transit_itinerary_filter.dart`, `transit_itinerary_card.dart`)이 걸리면 머리 주석을 8줄 이하로 줄이고 넘치는 설명은 스펙 문서로 옮긴 뒤 경로 한 줄만 남긴다.

- [ ] **Step 2: 릴리스 APK를 만든다**

`client/`에서. `config.local.json`이 워크스페이스에 있어야 한다(`.gitignore`라 복사해 둔 것).

```powershell
flutter build apk --release --dart-define-from-file=config.local.json
```

기대: `√ Built build\app\outputs\flutter-apk\app-release.apk`.

- [ ] **Step 3: Tailscale로 설치한다**

```powershell
$adb = "C:/Users/HANSUNG/AppData/Local/Android/Sdk/platform-tools/adb.exe"
& $adb connect 100.112.176.99:5555
& $adb install -r "build/app/outputs/flutter-apk/app-release.apk"
```

기대: `Success`. `offline`으로 뜨면 `& $adb disconnect` 후 다시 연결한다.

- [ ] **Step 4: 화면을 캡처한다**

폰에서 화면을 띄운 뒤 한 장씩 뽑는다.

```powershell
& $adb exec-out screencap -p > capture/01-transit-list.png
```

찍을 것 다섯:

| 파일 | 화면 | 볼 것 |
|---|---|---|
| `01-transit-list.png` | 대중교통 결과 목록 | 카드 배치, 막대 비율, 배지 색 |
| `02-transit-filter.png` | 필터 탭에서 `지하철` 선택 | 목록이 좁혀지는지, 0건 탭이 없는지 |
| `03-transit-detail.png` | 카드의 `상세보기` 펼침 | 구간 줄이 순서대로 나오는지 |
| `04-car-options.png` | 자동차 경로 후보 패널 | 라벨이 `추천` 하나인지 |
| `05-plan-card.png` | 계획 카드 | headline이 소요 시간인지, 목적지 라벨이 남아 있는지 |

- [ ] **Step 5: 기준 이미지와 대조한다**

`01`을 네이버지도 캡처와 나란히 놓고 본다. 자동 테스트가 못 잡는 것 셋:

- **막대 비율이 눈에 맞는가.** 1분짜리 구간에 `clamp(1, 100)`이 걸려 실제보다 커 보일 수 있다. 심하면 Task 6의 `_LegBar`에서 최소 flex를 조정한다.
- **배지 색이 노선과 어긋나지 않는가.** 카카오는 노선 고유색을 주지 않아 수단 기본색으로 떨어진다. 지하철 호선 색 구분이 사라지는 것이 정상이다.
- **`지선`/`간선` 구분이 나오는가.** TMAP만 접두사를 준다. 카카오면 `버스`로 떨어진다 — 어느 저장소가 실제로 쓰이는지 여기서 확인된다.

- [ ] **Step 6: 안내 시작 가드를 손으로 확인한다**

책상에서(경로가 다른 동네에 그려진 상태로) `안내 시작`을 누른다.

기대: **화면이 그대로 있고** `'경로 근처에 있을 때 안내를 시작할 수 있습니다.'` 스낵이 뜬다. 카메라가 GPS로 튀면 Task 3의 필드 이름(`_plannedRoutePoints`/`_lastKnownPoint`)이 잘못 연결된 것이다.

- [ ] **Step 7: 뒤로가기를 손으로 확인한다**

대중교통 경로를 하나 고른 뒤 폰 뒤로가기를 누른다.

기대: 앱이 꺼지지 않고 경로가 지워진다. 한 번 더 누르면 그때 앱이 닫힌다.

- [ ] **Step 8: 캡처를 커밋한다**

```powershell
git add capture
git commit -m "docs: 대중교통 화면 개편 기기 캡처를 남긴다"
```

`capture/`가 `.gitignore`에 걸리면 커밋하지 말고 사용자에게 파일로 전달한다.

---

## Self-Review

**Spec coverage** — 스펙의 다섯 항목이 전부 Task를 갖는다.

| 스펙 절 | Task |
|---|---|
| 1. 자동차 라벨 중복 | Task 1 |
| 2. 도착 시각의 자리 | Task 2 |
| 3. 안내 시작 GPS 가드 | Task 3 |
| 4. 뒤로가기 | Task 4 |
| 5. 필터 탭 | Task 5, 7 |
| 5. 결과 카드 + 상세보기 | Task 6, 7 |
| 5. 낡은 타일 삭제 | Task 7 Step 6~7 |
| 에러 처리(요금 null·탈것 없음·0초) | Task 6 Step 1의 테스트 셋 |
| 기기 검증 | Task 8 |

**남은 구멍 하나.**

- Task 4 Step 2 — `_outdoorRouteVisible`이 private이라 테스트에서 직접 못 세운다. 두 가지 길과 권장안을 적었다. 실행자가 `route_mode_test.dart`를 읽어야 고를 수 있다.

Task 3의 필드 이름은 확인해 메웠다 — `_route`(`:392`)·`_transitItinerary`(`:463`)·`_position`(`:384`).

**Type consistency** — Task 6이 만든 `TransitItineraryCard({itinerary, fastest, expanded, onExpanded, onTap, selected})`를 Task 7이 그대로 부른다. Task 5가 만든 네 함수의 이름과 인자 순서가 Task 7의 호출과 같다.
