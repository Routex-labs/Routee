# 자동차 경로 다중 후보 + 턴바이턴 상세보기 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 자동차 길찾기가 TMAP `searchOption` 4종을 물어 여러 경로 후보를 목록에서 고르게 하고, 자동차·도보 모두 고른(또는 유일한) 경로의 턴바이턴 상세보기를 보여준다.

**Architecture:** `feature-car-route-alternatives` 브랜치(미병합)가 이미 만든 다중 후보 조회·중복 제거 로직을 새 코드로 옮겨 오되, 그 브랜치의 "지도에 회색선 동시 표시" 대신 디자인시스템의 기존 `RoutexEtaCard.routeOptions` 슬롯(지금 앱은 안 씀)에 선택 목록을 넣는다. 턴바이턴 문구는 TMAP이 텍스트를 안 주므로 좌표 방위각으로 직접 계산한다.

**Tech Stack:** Flutter/Dart, `routex_design_system`(git 의존성, `RoutexEtaCard`/`RoutexRouteOption`/`RoutexStepList`), TMAP(SK Open API) REST, `latlong2`.

**Spec:** `docs/superpowers/specs/2026-08-18-directions-route-options-design.md`

## Global Constraints

- TMAP `searchOption` 값은 `0`(추천), `2`(대안), `3`(대안), `10`(최단거리) 4개만 쓴다 — `2`·`3`의 정확한 의미는 미확인이라 "대안"으로만 표기한다(추측 이름 금지).
- 도보는 다중 옵션을 만들지 않는다 — 실측(옵션 0·4·10이 완전히 같은 선)으로 이미 기각됐다.
- 턴바이턴 문구는 TMAP 텍스트가 아니라 좌표 방위각 계산이다 — 도로명 없이 "직진"/"좌회전"/"우회전"/"출발"/"도착"만 나온다.
- `fuelCostWon`은 추가하지 않는다 — TMAP 응답에 그 필드가 없다.
- 대중교통 상세보기·지도 위 회색 대안선·자전거·자동차 혼잡도 색상은 이번 범위 밖이다.
- `client/test/lib_layer_direction_test.dart`가 지키는 계층 방향(0 models → 1 domain → 2 repositories → 3 widgets → 4 screens)을 모든 새 파일이 지킨다.

---

## 파일 구조

- `client/lib/models/route/directions_route.dart` (기존, layer 0) — `DirectionsRouteStep`/`DirectionsTurn`/`classifyTurn`/`DirectionsRouteOptionKind`/`DirectionsRouteOption`/`DirectionsRouteOptionsStatus`/`DirectionsRouteOptions` 추가, `DirectionsRoute.steps` 필드 추가.
- `client/lib/domain/route/directions_route_merge.dart` (신규, layer 1) — 순수 병합 함수 하나.
- `client/lib/repositories/routing/directions_repository.dart`/`tmap_directions_repository.dart`/`mock_directions_repository.dart` (기존, layer 2) — `getDrivingRouteOptions()` 추가, 턴바이턴 스텝 계산 추가.
- `client/lib/widgets/eta_card.dart` (기존, layer 3) — `routeOptions`/`extraMetric` 파라미터 추가.
- `client/lib/widgets/directions_route_options_panel.dart` (신규, layer 3) — 후보 목록 위젯.
- `client/lib/screens/outdoor_map/widgets/directions_route_detail_sheet.dart` (신규, layer 4) — 상세보기 시트.
- `client/lib/screens/outdoor_map/outdoor_map_screen.dart` + `parts/route.dart` + `parts/ui.dart` (기존, layer 4, 같은 State를 나누는 `part` 파일들) — 후보 상태 보관·선택 재조회·EtaCard 연결.
- `client/lib/screens/map_shell/map_shell_screen.dart` (기존, layer 4) — `_startCarRoute`가 다중 후보를 조회해 넘긴다.

---

### Task 1: 턴바이턴 스텝 모델 + 방위각 판정

**Files:**
- Modify: `client/lib/models/route/directions_route.dart`
- Test: `client/test/models/route/directions_route_test.dart` (신규)

**Interfaces:**
- Produces: `class DirectionsRouteStep { instruction, distanceMeters, point }`, `enum DirectionsTurn { straight, turnLeft, turnRight }`, `DirectionsTurn classifyTurn({required double bearingBeforeDeg, required double bearingAfterDeg})`, `DirectionsRoute.steps`(기본값 `const []`).

- [ ] **Step 1: 실패하는 테스트 작성**

`client/test/models/route/directions_route_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/route/directions_route.dart';

void main() {
  group('classifyTurn', () {
    test('20도 미만이면 직진', () {
      expect(
        classifyTurn(bearingBeforeDeg: 10, bearingAfterDeg: 25),
        DirectionsTurn.straight,
      );
    });

    test('북쪽에서 동쪽으로 90도 틀면 우회전', () {
      expect(
        classifyTurn(bearingBeforeDeg: 0, bearingAfterDeg: 90),
        DirectionsTurn.turnRight,
      );
    });

    test('동쪽에서 북쪽으로 90도 틀면 좌회전', () {
      expect(
        classifyTurn(bearingBeforeDeg: 90, bearingAfterDeg: 0),
        DirectionsTurn.turnLeft,
      );
    });

    test('0/360 경계를 정규화해서 우회전으로 본다', () {
      expect(
        classifyTurn(bearingBeforeDeg: 350, bearingAfterDeg: 10),
        DirectionsTurn.turnRight,
      );
    });
  });

  test('DirectionsRoute.steps 기본값은 빈 리스트다', () {
    const route = DirectionsRoute(
      points: [LatLng(0, 0), LatLng(1, 1)],
      distanceMeters: 100,
      durationSeconds: 60,
    );
    expect(route.steps, isEmpty);
  });

  test('DirectionsRouteStep은 문구·거리·좌표를 그대로 갖는다', () {
    const step = DirectionsRouteStep(
      instruction: '우회전',
      distanceMeters: 200,
      point: LatLng(0.002, 0),
    );
    expect(step.instruction, '우회전');
    expect(step.distanceMeters, 200);
    expect(step.point, const LatLng(0.002, 0));
  });
}
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `cd client && flutter test test/models/route/directions_route_test.dart`
Expected: FAIL — `classifyTurn`/`DirectionsRouteStep`/`DirectionsTurn`이 정의되지 않았다는 컴파일 오류.

- [ ] **Step 3: 최소 구현 작성**

`client/lib/models/route/directions_route.dart`에 추가(파일 맨 위 `import` 다음, `DirectionsRoute` 클래스 앞):

```dart
/// 자동차·도보 경로의 안내 한 지점. 정적 미리보기용이다 — 실시간 안내
/// (domain/guidance/route_guidance.dart의 RouteStep)와는 다른 개념이라
/// 섞지 않는다.
///
/// [instruction]은 TMAP 응답 문구가 아니라 좌표로 직접 계산한 값이다 —
/// TMAP 보행자 응답 픽스처에 안내 문구 필드가 없다. 도로명 없이
/// "출발"/"좌회전"/"우회전"/"직진"/"도착"만 나온다.
class DirectionsRouteStep {
  const DirectionsRouteStep({
    required this.instruction,
    required this.distanceMeters,
    required this.point,
  });

  final String instruction;
  final double distanceMeters;
  final LatLng point;
}

enum DirectionsTurn { straight, turnLeft, turnRight }

/// 안내 지점 앞뒤 구간의 방위각 차이로 회전 방향을 정한다. 임계각(20도)
/// 미만이면 직진으로 본다 — 도로가 살짝 휘는 것까지 "회전"으로 부르면
/// 문구가 과민 반응한다.
DirectionsTurn classifyTurn({
  required double bearingBeforeDeg,
  required double bearingAfterDeg,
}) {
  var delta = bearingAfterDeg - bearingBeforeDeg;
  delta = ((delta + 180) % 360) - 180; // -180..180으로 정규화
  if (delta.abs() < 20) return DirectionsTurn.straight;
  return delta > 0 ? DirectionsTurn.turnRight : DirectionsTurn.turnLeft;
}
```

`DirectionsRoute` 생성자와 필드에 `steps` 추가:

```dart
class DirectionsRoute {
  const DirectionsRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    this.tollFareWon,
    this.taxiFareWon,
    this.steps = const [],
  });

  final List<LatLng> points;
  final double distanceMeters;
  final int durationSeconds;
  final int? tollFareWon;
  final int? taxiFareWon;

  /// 턴바이턴 미리보기. TMAP 응답이 없으면(또는 아직 계산 안 했으면) 빈
  /// 리스트다 — null이 아니라 빈 리스트인 이유는 호출부가 매번
  /// `steps ?? const []`를 반복하지 않게 하려는 것이다.
  final List<DirectionsRouteStep> steps;
}
```

- [ ] **Step 4: 테스트 실행해서 통과 확인**

Run: `cd client && flutter test test/models/route/directions_route_test.dart`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
cd client
git add lib/models/route/directions_route.dart test/models/route/directions_route_test.dart
git commit -m "feat: 경로 턴바이턴 스텝 모델과 방위각 회전 판정을 추가한다"
```

---

### Task 2: 다중 후보 모델

**Files:**
- Modify: `client/lib/models/route/directions_route.dart`
- Test: `client/test/models/route/directions_route_test.dart`

**Interfaces:**
- Consumes: `DirectionsRoute`(Task 1).
- Produces: `enum DirectionsRouteOptionKind { recommended, shortestDistance, alternative }`(`.label`), `class DirectionsRouteOption { kinds, route }`, `enum DirectionsRouteOptionsStatus { ok, failed }`, `class DirectionsRouteOptions { status, options }`(`.ok(...)`, `.failure(...)`, `.hasRoutes`).

- [ ] **Step 1: 실패하는 테스트 작성**

`directions_route_test.dart`에 추가:
```dart
test('자동차 옵션 라벨은 확인된 이름만 붙인다', () {
  expect(DirectionsRouteOptionKind.recommended.label, '추천');
  expect(DirectionsRouteOptionKind.shortestDistance.label, '최단거리');
  expect(DirectionsRouteOptionKind.alternative.label, '대안');
});

test('hasRoutes는 ok 상태이고 옵션이 있을 때만 true다', () {
  const route = DirectionsRoute(
    points: [LatLng(0, 0), LatLng(1, 1)],
    distanceMeters: 100,
    durationSeconds: 60,
  );
  const withRoutes = DirectionsRouteOptions.ok([
    DirectionsRouteOption(
      kinds: [DirectionsRouteOptionKind.recommended],
      route: route,
    ),
  ]);
  expect(withRoutes.hasRoutes, isTrue);

  const empty = DirectionsRouteOptions.ok([]);
  expect(empty.hasRoutes, isFalse);

  const failed = DirectionsRouteOptions.failure();
  expect(failed.hasRoutes, isFalse);
  expect(failed.options, isEmpty);
});
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `cd client && flutter test test/models/route/directions_route_test.dart`
Expected: FAIL — 새 타입들이 정의되지 않았다는 컴파일 오류.

- [ ] **Step 3: 최소 구현 작성**

`directions_route.dart`에 `DirectionsRoute` 클래스 뒤에 추가:

```dart
/// 자동차 옵션 종류. `feature-car-route-alternatives` 브랜치가 실측으로
/// 고른 TMAP `searchOption` 4개(`0,2,3,10`) 중 의미가 확인된 둘만 이름이
/// 있다. `2`·`3`은 [alternative]로 뭉뚱그린다 — 확인 못 한 의미를 지어내
/// "무료우선"처럼 틀린 이름을 붙이는 것보다 낫다. 도보용 kind는 없다.
enum DirectionsRouteOptionKind {
  /// TMAP `searchOption=0`. 교통최적+추천.
  recommended,

  /// TMAP `searchOption=10`. 최단거리.
  shortestDistance,

  /// TMAP `searchOption=2` 또는 `3`. 정확한 의미 미확인.
  alternative;

  String get label => switch (this) {
    DirectionsRouteOptionKind.recommended => '추천',
    DirectionsRouteOptionKind.shortestDistance => '최단거리',
    DirectionsRouteOptionKind.alternative => '대안',
  };
}

/// 경로 후보 한 줄. 좌표열이 같은 후보는 kinds를 합쳐 한 줄로 보여준다
/// (합치는 로직은 domain/route/directions_route_merge.dart).
class DirectionsRouteOption {
  const DirectionsRouteOption({required this.kinds, required this.route});

  /// 항상 1개 이상. 순서 = 목록에 보일 순서.
  final List<DirectionsRouteOptionKind> kinds;
  final DirectionsRoute route;
}

/// `getDrivingRoute`(단일)가 이미 성공/null 둘로만 구분하듯, TMAP 요청은
/// 네트워크 실패든 "경로 없음"이든 구분 없이 null만 준다 — 그 이상을
/// 구분하는 상태값은 지금 신호가 없다.
enum DirectionsRouteOptionsStatus { ok, failed }

class DirectionsRouteOptions {
  const DirectionsRouteOptions({required this.status, this.options = const []});

  const DirectionsRouteOptions.ok(this.options)
    : status = DirectionsRouteOptionsStatus.ok;

  const DirectionsRouteOptions.failure()
    : status = DirectionsRouteOptionsStatus.failed,
      options = const [];

  final DirectionsRouteOptionsStatus status;
  final List<DirectionsRouteOption> options;

  bool get hasRoutes =>
      status == DirectionsRouteOptionsStatus.ok && options.isNotEmpty;
}
```

- [ ] **Step 4: 테스트 실행해서 통과 확인**

Run: `cd client && flutter test test/models/route/directions_route_test.dart`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
cd client
git add lib/models/route/directions_route.dart test/models/route/directions_route_test.dart
git commit -m "feat: 자동차 경로 다중 후보 모델을 추가한다"
```

---

### Task 3: 후보 병합(중복 제거) 순수 함수

**Files:**
- Create: `client/lib/domain/route/directions_route_merge.dart`
- Test: `client/test/domain/route/directions_route_merge_test.dart`

**Interfaces:**
- Consumes: `DirectionsRoute`/`DirectionsRouteOptionKind`/`DirectionsRouteOption`(Task 1, 2).
- Produces: `List<DirectionsRouteOption> mergeDirectionsRouteOptions(List<(DirectionsRouteOptionKind, DirectionsRoute)> candidates)`.

- [ ] **Step 1: 실패하는 테스트 작성**

`client/test/domain/route/directions_route_merge_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/route/directions_route_merge.dart';
import 'package:navigation_client/models/route/directions_route.dart';

void main() {
  const routeA = DirectionsRoute(
    points: [LatLng(0, 0), LatLng(1, 1)],
    distanceMeters: 100,
    durationSeconds: 60,
  );
  const routeASameGeometry = DirectionsRoute(
    points: [LatLng(0, 0), LatLng(1, 1)],
    distanceMeters: 100,
    durationSeconds: 60,
  );
  const routeB = DirectionsRoute(
    points: [LatLng(0, 0), LatLng(2, 2)],
    distanceMeters: 200,
    durationSeconds: 90,
  );

  test('좌표열이 같으면 kinds를 합치고 한 줄로 남는다', () {
    final merged = mergeDirectionsRouteOptions([
      (DirectionsRouteOptionKind.recommended, routeA),
      (DirectionsRouteOptionKind.alternative, routeASameGeometry),
    ]);

    expect(merged.length, 1);
    expect(merged.single.kinds, [
      DirectionsRouteOptionKind.recommended,
      DirectionsRouteOptionKind.alternative,
    ]);
  });

  test('좌표열이 다르면 따로 두고 추천이 최단거리보다 먼저 온다', () {
    final merged = mergeDirectionsRouteOptions([
      (DirectionsRouteOptionKind.shortestDistance, routeB),
      (DirectionsRouteOptionKind.recommended, routeA),
    ]);

    expect(merged.length, 2);
    expect(merged[0].kinds, [DirectionsRouteOptionKind.recommended]);
    expect(merged[0].route, routeA);
    expect(merged[1].kinds, [DirectionsRouteOptionKind.shortestDistance]);
  });

  test('입력이 비면 빈 목록을 돌려준다', () {
    expect(mergeDirectionsRouteOptions([]), isEmpty);
  });
}
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `cd client && flutter test test/domain/route/directions_route_merge_test.dart`
Expected: FAIL — 파일이 없어 import 오류.

- [ ] **Step 3: 최소 구현 작성**

`client/lib/domain/route/directions_route_merge.dart`:
```dart
/// 자동차 경로 후보(kind, DirectionsRoute) 묶음을 화면에 보일 목록으로
/// 합친다.
///
/// 좌표열이 같은 후보는 한 줄로 합치고, 순서는 추천 > 최단거리 > 대안이다.
/// `feature-car-route-alternatives` 브랜치의 `_geometryKey()`를 그대로
/// 가져왔다 — 총거리·시간이 아니라 좌표열로 비교하는 이유는
/// `docs/client/car-route-alternatives.md`에 있다.
library;

import '../../models/route/directions_route.dart';

const _kindPriority = [
  DirectionsRouteOptionKind.recommended,
  DirectionsRouteOptionKind.shortestDistance,
  DirectionsRouteOptionKind.alternative,
];

/// [candidates]를 kind 우선순위로 정렬하고 좌표열이 같은 것을 합친다.
List<DirectionsRouteOption> mergeDirectionsRouteOptions(
  List<(DirectionsRouteOptionKind, DirectionsRoute)> candidates,
) {
  final sorted = [...candidates]..sort(
    (a, b) =>
        _kindPriority.indexOf(a.$1).compareTo(_kindPriority.indexOf(b.$1)),
  );
  final order = <String>[];
  final byKey = <String, DirectionsRouteOption>{};
  for (final (kind, route) in sorted) {
    final key = _geometryKey(route);
    final existing = byKey[key];
    if (existing == null) {
      order.add(key);
      byKey[key] = DirectionsRouteOption(kinds: [kind], route: route);
    } else {
      byKey[key] = DirectionsRouteOption(
        kinds: [...existing.kinds, kind],
        route: existing.route,
      );
    }
  }
  return [for (final key in order) byKey[key]!];
}

String _geometryKey(DirectionsRoute route) =>
    route.points.map((p) => '${p.latitude},${p.longitude}').join(';');
```

- [ ] **Step 4: 테스트 실행해서 통과 확인**

Run: `cd client && flutter test test/domain/route/directions_route_merge_test.dart`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
cd client
git add lib/domain/route/directions_route_merge.dart test/domain/route/directions_route_merge_test.dart
git commit -m "feat: 좌표열이 같은 자동차 경로 후보를 한 줄로 합친다"
```

---

### Task 4: TMAP 응답에서 턴바이턴 스텝 계산

**Files:**
- Modify: `client/lib/repositories/routing/tmap_directions_repository.dart`
- Test: `client/test/repositories/routing/tmap_directions_repository_test.dart`

**Interfaces:**
- Consumes: `DirectionsRouteStep`/`DirectionsTurn`/`classifyTurn`(Task 1).
- Produces: `TmapDirectionsRepository._request()`가 반환하는 `DirectionsRoute.steps`가 채워진다(기존 `getWalkingRoute`/`getDrivingRoute` 호출부는 그대로, `steps`를 안 쓰면 영향 없음).

- [ ] **Step 1: 실패하는 테스트 작성**

`tmap_directions_repository_test.dart` 맨 위 기존 fixture 상수들 옆에 추가:

```dart
// 합성 픽스처(실측 아님) — 방위각 계산을 검증하려고 손으로 만든 직각 경로.
// 북쪽(0,0)->(0,0.002)으로 가다 안내지점에서 동쪽(0.002,0.002)으로 90도
// 꺾인다. 손으로 방위각을 계산해 검증한 값이라 기대값이 정확하다.
const _turnSampleResponseBody = '''
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "geometry": { "type": "Point", "coordinates": [0, 0] },
      "properties": { "totalDistance": 380, "totalTime": 290, "pointType": "SP" }
    },
    {
      "type": "Feature",
      "geometry": { "type": "LineString", "coordinates": [[0, 0], [0, 0.002]] },
      "properties": { "distance": 200, "time": 150 }
    },
    {
      "type": "Feature",
      "geometry": { "type": "Point", "coordinates": [0, 0.002] },
      "properties": { "pointType": "GP" }
    },
    {
      "type": "Feature",
      "geometry": { "type": "LineString", "coordinates": [[0, 0.002], [0.002, 0.002]] },
      "properties": { "distance": 180, "time": 140 }
    },
    {
      "type": "Feature",
      "geometry": { "type": "Point", "coordinates": [0.002, 0.002] },
      "properties": { "pointType": "EP" }
    }
  ]
}
''';
```

`void main()` 안, 기존 마지막 test 다음에 추가:
```dart
test('안내 지점을 좌회전/우회전/직진으로 계산해 스텝을 만든다', () async {
  final client = MockClient((request) async {
    return http.Response(
      _turnSampleResponseBody,
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
  final repository = TmapDirectionsRepository(client: client);

  final route = await repository.getWalkingRoute(
    origin: const LatLng(0, 0),
    destination: const LatLng(0.002, 0.002),
  );

  expect(route!.steps.length, 3);
  expect(route.steps[0].instruction, '출발');
  expect(route.steps[0].distanceMeters, 0);
  expect(route.steps[1].instruction, '우회전');
  expect(route.steps[1].distanceMeters, 200);
  expect(route.steps[2].instruction, '도착');
  expect(route.steps[2].distanceMeters, 180);
});
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `cd client && flutter test test/repositories/routing/tmap_directions_repository_test.dart`
Expected: FAIL — `route.steps`가 빈 리스트라 `route.steps.length`가 0.

- [ ] **Step 3: 최소 구현 작성**

`tmap_directions_repository.dart` 맨 위에 `import 'dart:math' as math;` 추가.

`_request()`의 `return DirectionsRoute(...)` 앞에 `steps: _computeSteps(features),` 를 추가하고, 클래스 안에 헬퍼 3개를 추가:

```dart
  static List<DirectionsRouteStep> _computeSteps(
    List<Map<String, dynamic>> features,
  ) {
    final points = <Map<String, dynamic>>[];
    final lines = <Map<String, dynamic>>[];
    for (final feature in features) {
      final geometry = feature['geometry'] as Map<String, dynamic>?;
      switch (geometry?['type']) {
        case 'Point':
          points.add(feature);
        case 'LineString':
          lines.add(feature);
      }
    }
    // 안내지점 개수는 항상 구간 개수 + 1이어야 한다(SP, GP..., EP 사이사이에
    // 구간이 하나씩 낀다). 어긋나면 응답이 예상 모양이 아니라는 뜻이라, 억지로
    // 읽지 않고 빈 목록으로 물러난다 — `_request()`의 다른 실패(네트워크 오류,
    // 200이 아닌 응답, JSON 파싱 실패)가 전부 조용히 null/빈 값으로 떨어지는
    // 것과 같은 원칙이다. 여기서 예외를 던지면 이 메서드만 "절대 안 던진다"는
    // 계약을 깨고, Task 5의 `Future.wait` 안에서 다른 옵션 응답까지 끌고 죽는다.
    if (points.isEmpty || lines.length != points.length - 1) return const [];

    final steps = <DirectionsRouteStep>[];
    for (var i = 0; i < points.length; i++) {
      final coordinate =
          (points[i]['geometry'] as Map<String, dynamic>)['coordinates']
              as List<dynamic>;
      final point = _toLatLng(coordinate);

      if (i == 0) {
        steps.add(
          DirectionsRouteStep(instruction: '출발', distanceMeters: 0, point: point),
        );
        continue;
      }

      final beforeLine = lines[i - 1];
      final beforeDistance =
          _number(beforeLine['properties']?['distance']) ?? 0;

      if (i == points.length - 1) {
        steps.add(
          DirectionsRouteStep(
            instruction: '도착',
            distanceMeters: beforeDistance,
            point: point,
          ),
        );
        continue;
      }

      final afterLine = lines[i];
      final bearingBefore = _lineBearing(beforeLine, atStart: false);
      final bearingAfter = _lineBearing(afterLine, atStart: true);
      final turn = classifyTurn(
        bearingBeforeDeg: bearingBefore,
        bearingAfterDeg: bearingAfter,
      );
      steps.add(
        DirectionsRouteStep(
          instruction: switch (turn) {
            DirectionsTurn.straight => '직진',
            DirectionsTurn.turnLeft => '좌회전',
            DirectionsTurn.turnRight => '우회전',
          },
          distanceMeters: beforeDistance,
          point: point,
        ),
      );
    }
    return steps;
  }

  /// [atStart]가 true면 선의 첫 두 점(진입 방위), false면 마지막 두 점
  /// (진출 방위)으로 방위각을 잰다.
  static double _lineBearing(
    Map<String, dynamic> lineFeature, {
    required bool atStart,
  }) {
    final coordinates =
        ((lineFeature['geometry'] as Map<String, dynamic>)['coordinates']
                as List<dynamic>)
            .cast<List<dynamic>>();
    final a = atStart
        ? coordinates.first
        : coordinates[coordinates.length - 2];
    final b = atStart ? coordinates[1] : coordinates.last;
    return _bearingDeg(_toLatLng(a), _toLatLng(b));
  }

  static LatLng _toLatLng(List<dynamic> pair) =>
      LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble());

  static double _bearingDeg(LatLng from, LatLng to) {
    final dLon = to.longitude - from.longitude;
    final dLat = to.latitude - from.latitude;
    final deg = math.atan2(dLon, dLat) * 180 / math.pi;
    return deg < 0 ? deg + 360 : deg;
  }
```

- [ ] **Step 4: 테스트 실행해서 통과 확인**

Run: `cd client && flutter test test/repositories/routing/tmap_directions_repository_test.dart`
Expected: PASS(기존 테스트 4개 + 새 테스트 1개, 총 5개)

- [ ] **Step 5: 커밋**

```bash
cd client
git add lib/repositories/routing/tmap_directions_repository.dart test/repositories/routing/tmap_directions_repository_test.dart
git commit -m "feat: TMAP 응답 좌표로 턴바이턴 스텝을 계산한다"
```

---

### Task 5: 자동차 다중 후보 조회

**Files:**
- Modify: `client/lib/repositories/routing/directions_repository.dart`
- Modify: `client/lib/repositories/routing/tmap_directions_repository.dart`
- Modify: `client/lib/repositories/routing/mock_directions_repository.dart`
- Test: `client/test/repositories/routing/tmap_directions_repository_test.dart`
- Test: `client/test/repositories/routing/mock_directions_repository_test.dart`

**Interfaces:**
- Consumes: `mergeDirectionsRouteOptions`(Task 3), `DirectionsRouteOptions`(Task 2).
- Produces: `DirectionsRepository.getDrivingRouteOptions({required LatLng origin, required LatLng destination}) → Future<DirectionsRouteOptions>` — Task 10이 `map_shell_screen.dart`에서 이걸 호출한다.

- [ ] **Step 1: 실패하는 테스트 작성**

`directions_repository.dart`에 메서드 시그니처를 먼저 추가하지 않으면 아래 테스트가 컴파일조차 안 되므로, Step 1과 Step 3을 함께 진행한다(인터페이스 변경은 구현 없이 테스트만 못 돌린다) — 대신 **인터페이스 추가 → 실패하는 구현 테스트** 순서로 좁힌다.

`directions_repository.dart`에 추가:
```dart
  /// 자동차 경로 후보 여러 개. `feature-car-route-alternatives` 브랜치의
  /// `getDrivingRoutes()`를 반환 타입만 [DirectionsRouteOptions](라벨 있는
  /// 목록 봉투)로 바꿔 옮긴 것이다.
  Future<DirectionsRouteOptions> getDrivingRouteOptions({
    required LatLng origin,
    required LatLng destination,
  });
```

`tmap_directions_repository_test.dart`에 추가(기존 `_drivingResponseBody` 아래):
```dart
// searchOption '10'(최단거리) 전용 응답. 좌표가 달라야 병합에서 따로 남는다.
const _shortestDistanceResponseBody = '''
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "geometry": { "type": "Point", "coordinates": [126.7, 37.63] },
      "properties": {
        "totalDistance": 28000,
        "totalTime": 1900,
        "totalFare": 0,
        "taxiFare": 28000,
        "pointType": "S"
      }
    },
    {
      "type": "Feature",
      "geometry": {
        "type": "LineString",
        "coordinates": [[126.7, 37.63], [126.80, 37.58], [126.92, 37.53]]
      },
      "properties": { "distance": 28000, "time": 1900 }
    }
  ]
}
''';

test('자동차 후보 4개를 조회해 좌표로 중복 제거한다', () async {
  final client = MockClient((request) async {
    final option = request.bodyFields['searchOption'];
    final body = option == '10'
        ? _shortestDistanceResponseBody
        : _drivingResponseBody; // '0','2','3'은 같은 응답 -> 하나로 합쳐짐
    return http.Response(
      body,
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
  final repository = TmapDirectionsRepository(client: client);

  final options = await repository.getDrivingRouteOptions(
    origin: const LatLng(37.63, 126.7),
    destination: const LatLng(37.53, 126.92),
  );

  expect(options.status, DirectionsRouteOptionsStatus.ok);
  expect(options.options.length, 2);
  expect(options.options[0].kinds, [
    DirectionsRouteOptionKind.recommended,
    DirectionsRouteOptionKind.alternative,
    DirectionsRouteOptionKind.alternative,
  ]);
  expect(options.options[1].kinds, [DirectionsRouteOptionKind.shortestDistance]);
});

test('전부 실패하면 failed 상태를 돌려준다', () async {
  final client = MockClient((request) async => http.Response('', 500));
  final repository = TmapDirectionsRepository(client: client);

  final options = await repository.getDrivingRouteOptions(
    origin: const LatLng(37.63, 126.7),
    destination: const LatLng(37.53, 126.92),
  );

  expect(options.status, DirectionsRouteOptionsStatus.failed);
  expect(options.options, isEmpty);
});
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `cd client && flutter test test/repositories/routing/tmap_directions_repository_test.dart`
Expected: FAIL — `getDrivingRouteOptions`이 없어(추상 메서드 미구현) 컴파일 오류.

- [ ] **Step 3: 최소 구현 작성**

`tmap_directions_repository.dart`에 `import '../../domain/route/directions_route_merge.dart';` 추가, 클래스 안에 추가:

```dart
  /// 자동차 후보를 만들려고 물어보는 `searchOption` 값들. **순서가 곧
  /// kind 대응 순서다.** TMAP에는 대안 경로를 한 번에 주는 엔드포인트가
  /// 없어, 값을 바꿔 여러 번 묻고 우리가 비교해 후보를 만든다. 근거는
  /// `docs/client/car-route-alternatives.md`.
  static const _drivingSearchOptions = [
    ('0', DirectionsRouteOptionKind.recommended),
    ('2', DirectionsRouteOptionKind.alternative),
    ('3', DirectionsRouteOptionKind.alternative),
    ('10', DirectionsRouteOptionKind.shortestDistance),
  ];

  @override
  Future<DirectionsRouteOptions> getDrivingRouteOptions({
    required LatLng origin,
    required LatLng destination,
  }) async {
    // 동시에 보낸다 — 순서대로 기다리면 옵션 수만큼 왕복 시간이 곱해진다.
    final responses = await Future.wait([
      for (final (option, kind) in _drivingSearchOptions)
        _request(
          Uri.parse('$tmapBaseUrl/routes?version=1'),
          origin: origin,
          destination: destination,
          extra: {'searchOption': option, 'trafficInfo': 'N'},
        ).then((route) => (kind, route)),
    ]);

    final candidates = [
      for (final (kind, route) in responses)
        if (route != null) (kind, route),
    ];
    if (candidates.isEmpty) {
      return const DirectionsRouteOptions.failure();
    }
    return DirectionsRouteOptions.ok(mergeDirectionsRouteOptions(candidates));
  }
```

`mock_directions_repository.dart`에 추가(`import 'package:latlong2/latlong.dart';`는 이미 있음):
```dart
  @override
  Future<DirectionsRouteOptions> getDrivingRouteOptions({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final direct = await getDrivingRoute(origin: origin, destination: destination);
    if (direct == null) {
      return const DirectionsRouteOptions.failure();
    }
    // 대안 후보: 중점을 살짝 밀어 올린 경유점을 하나 끼운 두 번째 선. 실제
    // API처럼 값이 달라야 목록이 둘로 보인다 — 완전히 같으면
    // mergeDirectionsRouteOptions가 하나로 합쳐 버린다.
    final midpoint = LatLng(
      (origin.latitude + destination.latitude) / 2 + 0.002,
      (origin.longitude + destination.longitude) / 2,
    );
    final viaDistance =
        const Distance().as(LengthUnit.Meter, origin, midpoint) +
        const Distance().as(LengthUnit.Meter, midpoint, destination);
    final alternative = DirectionsRoute(
      points: [origin, midpoint, destination],
      distanceMeters: viaDistance,
      durationSeconds: (viaDistance / _drivingSpeedMetersPerSecond).round(),
    );
    return DirectionsRouteOptions.ok([
      DirectionsRouteOption(
        kinds: const [DirectionsRouteOptionKind.recommended],
        route: direct,
      ),
      DirectionsRouteOption(
        kinds: const [DirectionsRouteOptionKind.shortestDistance],
        route: alternative,
      ),
    ]);
  }
```

`mock_directions_repository_test.dart`에 추가:
```dart
test('자동차 후보 2개(추천/최단거리)를 돌려준다', () async {
  final repository = MockDirectionsRepository();

  final options = await repository.getDrivingRouteOptions(
    origin: const LatLng(37.5665, 126.9780),
    destination: const LatLng(37.5665, 126.9790),
  );

  expect(options.hasRoutes, isTrue);
  expect(options.options.length, 2);
  expect(
    options.options[0].kinds,
    [DirectionsRouteOptionKind.recommended],
  );
  expect(
    options.options[1].kinds,
    [DirectionsRouteOptionKind.shortestDistance],
  );
});
```

- [ ] **Step 4: 테스트 실행해서 통과 확인**

Run: `cd client && flutter test test/repositories/routing/tmap_directions_repository_test.dart test/repositories/routing/mock_directions_repository_test.dart`
Expected: PASS(전부)

- [ ] **Step 5: 커밋**

```bash
cd client
git add lib/repositories/routing/directions_repository.dart lib/repositories/routing/tmap_directions_repository.dart lib/repositories/routing/mock_directions_repository.dart test/repositories/routing/tmap_directions_repository_test.dart test/repositories/routing/mock_directions_repository_test.dart
git commit -m "feat: 자동차 경로 다중 후보 조회를 추가한다"
```

---

### Task 6: EtaCard에 후보 패널·요금 지표 슬롯 추가

**Files:**
- Modify: `client/lib/widgets/eta_card.dart`
- Test: `client/test/widgets/eta_card_test.dart`

**Interfaces:**
- Produces: `EtaCard.routeOptions: Widget?`, `EtaCard.extraMetric: RoutexTripMetric?`(둘 다 기본값 `null`, 기존 4개 호출부는 안 건드려도 그대로 동작).

- [ ] **Step 1: 실패하는 테스트 작성**

`eta_card_test.dart`의 `안내 전 계획 카드` 그룹에 추가:
```dart
    testWidgets('routeOptions을 건네면 요약 위에 그린다', (tester) async {
      await tester.pumpWidget(
        wrap(
          const EtaCard(
            distanceMeters: 3900,
            minutes: 8,
            label: '목적지까지',
            routeOptions: Text('옵션 영역'),
          ),
        ),
      );

      expect(find.text('옵션 영역'), findsOneWidget);
    });

    testWidgets('extraMetric을 건네면 소요·거리 옆에 함께 적는다', (tester) async {
      await tester.pumpWidget(
        wrap(
          EtaCard(
            distanceMeters: 3900,
            minutes: 8,
            label: '목적지까지',
            extraMetric: const RoutexTripMetric(value: '무료', label: '통행료'),
          ),
        ),
      );

      expect(find.text('무료'), findsOneWidget);
      expect(find.text('통행료'), findsOneWidget);
    });
```

파일 상단에 `import 'package:routex_design_system/routex_design_system.dart';`가 이미 있는지 확인(없으면 추가).

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `cd client && flutter test test/widgets/eta_card_test.dart`
Expected: FAIL — `routeOptions`/`extraMetric` 파라미터가 없어 컴파일 오류.

- [ ] **Step 3: 최소 구현 작성**

`eta_card.dart`의 `EtaCard`:
```dart
class EtaCard extends StatelessWidget {
  const EtaCard({
    super.key,
    required this.distanceMeters,
    required this.minutes,
    this.label = '목적지까지',
    this.guidanceStarted = false,
    this.onClose,
    this.onStartGuidance,
    this.onClosePointerDown,
    this.routeOptions,
    this.extraMetric,
  });

  final double distanceMeters;
  final int minutes;
  final String label;
  final bool guidanceStarted;
  final VoidCallback? onClose;
  final VoidCallback? onStartGuidance;
  final ValueChanged<Offset>? onClosePointerDown;

  /// 복수 경로 후보를 고를 수 있을 때 요약 위에 놓는 선택 영역. 출발 전
  /// 계획 카드에서만 쓰인다 — 안내 중에는 경로를 바꿀 수 없다.
  final Widget? routeOptions;

  /// 소요·거리 옆에 하나 더 적을 값(통행료 등). `RoutexEtaCard`가 지표를
  /// 3개까지만 받아 통행료·택시비를 동시에 넣을 자리가 없다 — 부르는
  /// 쪽이 어느 쪽을 보여줄지 미리 고른다.
  final RoutexTripMetric? extraMetric;

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
          if (extraMetric != null) extraMetric!,
        ],
        routeOptions: routeOptions,
        onStart: onStartGuidance,
      );
    }

    return Listener(
      onPointerDown: (event) => onClosePointerDown?.call(event.position),
      child: RoutexTripProgress(
        metrics: [
          RoutexTripMetric(value: arrivalTime, label: '도착 예정'),
          RoutexTripMetric(value: '$minutes분', label: '남은 시간'),
          RoutexTripMetric(
            value: formatDistance(distanceMeters),
            label: '남은 거리',
          ),
        ],
        onStop: onClose,
      ),
    );
  }
}
```

- [ ] **Step 4: 테스트 실행해서 통과 확인**

Run: `cd client && flutter test test/widgets/eta_card_test.dart`
Expected: PASS(기존 4개 + 새 2개, 총 6개)

- [ ] **Step 5: 커밋**

```bash
cd client
git add lib/widgets/eta_card.dart test/widgets/eta_card_test.dart
git commit -m "feat: EtaCard에 경로 후보 패널과 세 번째 지표 슬롯을 연결한다"
```

---

### Task 7: 후보 목록 패널 위젯

**Files:**
- Create: `client/lib/widgets/directions_route_options_panel.dart`
- Test: `client/test/widgets/directions_route_options_panel_test.dart`

**Interfaces:**
- Consumes: `DirectionsRouteOption`(Task 2), `RoutexRouteOption`/`RoutexStack`(디자인시스템), `formatDistance`(`domain/geo/distance_format.dart`), `formatTransitDuration`(`widgets/transit_style.dart`).
- Produces: `class DirectionsRouteOptionsPanel extends StatelessWidget { options, selectedIndex, onSelect }` — Task 9가 `ui.dart`에서 이 위젯을 만든다.

- [ ] **Step 1: 실패하는 테스트 작성**

`client/test/widgets/directions_route_options_panel_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/models/route/directions_route.dart';
import 'package:navigation_client/widgets/directions_route_options_panel.dart';
import 'package:routex_design_system/routex_design_system.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: Center(child: child)),
  );

  const routeA = DirectionsRoute(
    points: [LatLng(0, 0), LatLng(1, 1)],
    distanceMeters: 3900,
    durationSeconds: 480,
  );
  const routeB = DirectionsRoute(
    points: [LatLng(0, 0), LatLng(2, 2)],
    distanceMeters: 5100,
    durationSeconds: 1500,
  );

  testWidgets('후보를 한 줄씩 그리고 탭하면 선택을 알린다', (tester) async {
    int? picked;
    await tester.pumpWidget(
      wrap(
        DirectionsRouteOptionsPanel(
          options: const [
            DirectionsRouteOption(
              kinds: [DirectionsRouteOptionKind.recommended],
              route: routeA,
            ),
            DirectionsRouteOption(
              kinds: [DirectionsRouteOptionKind.shortestDistance],
              route: routeB,
            ),
          ],
          selectedIndex: 0,
          onSelect: (index) => picked = index,
        ),
      ),
    );

    expect(find.text('추천'), findsOneWidget);
    expect(find.text('최단거리'), findsOneWidget);

    await tester.tap(find.text('최단거리'));
    expect(picked, 1);
  });

  testWidgets('후보가 1개면 아무것도 그리지 않는다', (tester) async {
    await tester.pumpWidget(
      wrap(
        DirectionsRouteOptionsPanel(
          options: const [
            DirectionsRouteOption(
              kinds: [DirectionsRouteOptionKind.recommended],
              route: routeA,
            ),
          ],
          selectedIndex: 0,
          onSelect: (_) {},
        ),
      ),
    );

    expect(find.byType(RoutexRouteOption), findsNothing);
  });
}
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `cd client && flutter test test/widgets/directions_route_options_panel_test.dart`
Expected: FAIL — 파일이 없어 import 오류.

- [ ] **Step 3: 최소 구현 작성**

`client/lib/widgets/directions_route_options_panel.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../domain/geo/distance_format.dart';
import '../models/route/directions_route.dart';
import 'transit_style.dart' show formatTransitDuration;

/// 자동차 경로 후보 목록. 좌표열이 겹치는 후보를 이미 합친
/// [DirectionsRouteOption] 리스트를 그대로 받아 한 줄씩 그린다.
///
/// 옵션이 1개면 아무것도 그리지 않는다 — 고를 게 없는데 카드만 하나
/// 있으면 "이게 왜 있지" 하는 UI가 된다.
class DirectionsRouteOptionsPanel extends StatelessWidget {
  const DirectionsRouteOptionsPanel({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<DirectionsRouteOption> options;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    if (options.length < 2) return const SizedBox.shrink();
    return RoutexStack(
      gap: RoutexStackGap.inline,
      children: [
        for (var i = 0; i < options.length; i++)
          RoutexRouteOption(
            title: options[i].kinds.map((kind) => kind.label).join(' · '),
            detail: formatDistance(options[i].route.distanceMeters),
            meta: formatTransitDuration(options[i].route.durationSeconds),
            selected: i == selectedIndex,
            onPressed: () => onSelect(i),
          ),
      ],
    );
  }
}
```

- [ ] **Step 4: 테스트 실행해서 통과 확인**

Run: `cd client && flutter test test/widgets/directions_route_options_panel_test.dart`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
cd client
git add lib/widgets/directions_route_options_panel.dart test/widgets/directions_route_options_panel_test.dart
git commit -m "feat: 자동차 경로 후보 선택 패널 위젯을 추가한다"
```

---

### Task 8: 턴바이턴 상세보기 시트

**Files:**
- Create: `client/lib/screens/outdoor_map/widgets/directions_route_detail_sheet.dart`
- Test: `client/test/screens/outdoor_map/widgets/directions_route_detail_sheet_test.dart`

**Interfaces:**
- Consumes: `DirectionsRoute`/`DirectionsRouteStep`(Task 1), `RoutexStepList`/`RoutexStep`/`RoutexIcons`(디자인시스템), `formatDistance`.
- Produces: `void showDirectionsRouteDetailSheet(BuildContext context, {required DirectionsRoute route, required String destinationLabel})` — Task 9가 `ui.dart`에서 이 함수를 부른다.

- [ ] **Step 1: 실패하는 테스트 작성**

`client/test/screens/outdoor_map/widgets/directions_route_detail_sheet_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/models/route/directions_route.dart';
import 'package:navigation_client/screens/outdoor_map/widgets/directions_route_detail_sheet.dart';

void main() {
  testWidgets('경로 단계를 순서대로 문구·거리와 함께 보여준다', (tester) async {
    const route = DirectionsRoute(
      points: [LatLng(0, 0), LatLng(0.002, 0), LatLng(0.002, 0.002)],
      distanceMeters: 380,
      durationSeconds: 290,
      steps: [
        DirectionsRouteStep(
          instruction: '출발',
          distanceMeters: 0,
          point: LatLng(0, 0),
        ),
        DirectionsRouteStep(
          instruction: '우회전',
          distanceMeters: 200,
          point: LatLng(0.002, 0),
        ),
        DirectionsRouteStep(
          instruction: '도착',
          distanceMeters: 180,
          point: LatLng(0.002, 0.002),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDirectionsRouteDetailSheet(
                context,
                route: route,
                destinationLabel: '서울창업허브',
              ),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    expect(find.text('서울창업허브까지'), findsOneWidget);
    expect(find.text('출발'), findsOneWidget);
    expect(find.text('우회전'), findsOneWidget);
    expect(find.text('도착'), findsOneWidget);
    expect(find.text('200m'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `cd client && flutter test test/screens/outdoor_map/widgets/directions_route_detail_sheet_test.dart`
Expected: FAIL — 파일이 없어 import 오류.

- [ ] **Step 3: 최소 구현 작성**

`client/lib/screens/outdoor_map/widgets/directions_route_detail_sheet.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../../../domain/geo/distance_format.dart';
import '../../../models/route/directions_route.dart';

/// 자동차·도보 경로의 턴바이턴 미리보기.
///
/// 실시간 안내 중 화면(route_steps_sheet.dart)과 재사용하지 않고 분리한다
/// — 그 파일 주석대로 "출발 전 미리보기"와 "걷는 중 배너"는 답하는 질문이
/// 다르다. 이쪽은 진행 중 단계 표시가 없다(아직 출발 전이라 항상 null).
void showDirectionsRouteDetailSheet(
  BuildContext context, {
  required DirectionsRoute route,
  required String destinationLabel,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.5,
    ),
    builder: (context) => _DirectionsRouteDetailSheet(
      route: route,
      destinationLabel: destinationLabel,
    ),
  );
}

class _DirectionsRouteDetailSheet extends StatelessWidget {
  const _DirectionsRouteDetailSheet({
    required this.route,
    required this.destinationLabel,
  });

  final DirectionsRoute route;
  final String destinationLabel;

  @override
  Widget build(BuildContext context) => RoutexBottomSheet(
    showHandle: true,
    header: RoutexSheetHeader(
      title: '$destinationLabel까지',
      onClose: () => Navigator.of(context).pop(),
    ),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight:
            MediaQuery.sizeOf(context).height * 0.5 -
            RoutexMetrics.minimumTouchTarget -
            RoutexSpacing.sectionGap * 2 -
            RoutexSpacing.controlGap,
      ),
      child: SingleChildScrollView(
        child: RoutexStepList(
          steps: [
            for (final step in route.steps)
              RoutexStep(
                instruction: step.instruction,
                icon: _stepIcon(step.instruction),
                distance: step.distanceMeters > 0
                    ? formatDistance(step.distanceMeters)
                    : null,
              ),
          ],
        ),
      ),
    ),
  );
}

/// [step.instruction]은 이 파일이 만든 값(출발/좌회전/우회전/직진/도착)만
/// 들어온다 — 우리가 만든 닫힌 문자열 집합이라 매칭이 안전하다.
IconData _stepIcon(String instruction) => switch (instruction) {
  '좌회전' => RoutexIcons.turnLeft,
  '우회전' => RoutexIcons.turnRight,
  '도착' => RoutexIcons.arrived,
  _ => RoutexIcons.straight,
};
```

- [ ] **Step 4: 테스트 실행해서 통과 확인**

Run: `cd client && flutter test test/screens/outdoor_map/widgets/directions_route_detail_sheet_test.dart`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
cd client
git add lib/screens/outdoor_map/widgets/directions_route_detail_sheet.dart test/screens/outdoor_map/widgets/directions_route_detail_sheet_test.dart
git commit -m "feat: 자동차·도보 경로 턴바이턴 상세보기 시트를 추가한다"
```

---

### Task 9: 야외 지도에 후보 선택·상세보기 연결

**Files:**
- Modify: `client/lib/screens/outdoor_map/outdoor_map_screen.dart`
- Modify: `client/lib/screens/outdoor_map/parts/route.dart`
- Modify: `client/lib/screens/outdoor_map/parts/ui.dart`

**Interfaces:**
- Consumes: `DirectionsRouteOption`(Task 2), `DirectionsRouteOptionsPanel`(Task 7), `showDirectionsRouteDetailSheet`(Task 8), 기존 `showPlannedRoadRoute`(변경 없음).
- Produces: `OutdoorMapBodyState.showPlannedRoadRouteOptions(List<DirectionsRouteOption> options, {required LatLng origin, required LatLng destination, required String label})`, `OutdoorMapBodyState.selectDirectionsOption(int index)` — Task 10이 `map_shell_screen.dart`에서 이 둘을 부른다.

이 계층은 `maplibre_gl` 컨트롤러에 강하게 묶여 있어 단위 테스트로 직접 겨냥하기 어렵다 — 이 Task의 검증은 Task 10의 위젯 테스트(전체 화면을 pump해 실제로 목록이 뜨고 탭하면 바뀌는지)가 맡는다. 그래서 이 Task는 **구현만** 하고 커밋 전 `flutter analyze`로 컴파일·타입 오류만 확인한다.

- [ ] **Step 1: `outdoor_map_screen.dart`에 상태 필드 추가**

`DirectionsRoute? _route;`(약 376행) 바로 아래에 추가:
```dart
  /// 자동차 경로 후보 목록. 1개 이하면 고를 게 없다는 뜻이라 패널을
  /// 그리지 않는다([DirectionsRouteOptionsPanel] 참고).
  List<DirectionsRouteOption> _directionsRouteOptions = const [];
  int _selectedDirectionsOptionIndex = 0;
```

파일 상단 import 블록에 추가(이미 있으면 생략):
```dart
import '../../widgets/directions_route_options_panel.dart';
import 'widgets/directions_route_detail_sheet.dart';
```

- [ ] **Step 2: `parts/route.dart`에 후보 표시·선택 메서드 추가**

`showPlannedRoadRoute` 메서드(약 451행) 바로 뒤에 추가:
```dart
  /// 자동차 후보 목록을 받아 첫 번째(추천)를 그린다. 이후
  /// [selectDirectionsOption]으로 다른 후보를 고르면 다시 그린다.
  Future<void> showPlannedRoadRouteOptions(
    List<DirectionsRouteOption> options, {
    required ll.LatLng origin,
    required ll.LatLng destination,
    required String label,
  }) async {
    _directionsRouteOptions = options;
    _selectedDirectionsOptionIndex = 0;
    await showPlannedRoadRoute(
      options.first.route,
      origin: origin,
      destination: destination,
      label: label,
      driving: true,
    );
  }

  /// 목록에서 다른 자동차 후보를 골랐을 때. 출발·도착·라벨은 그대로다 —
  /// 바뀌는 것은 경로 선뿐이다.
  Future<void> selectDirectionsOption(int index) async {
    if (index == _selectedDirectionsOptionIndex) return;
    final origin = _fixedRouteOrigin;
    final destination = _userDestination;
    final label = _userDestinationLabel;
    if (origin == null || destination == null || label == null) return;
    setState(() => _selectedDirectionsOptionIndex = index);
    await showPlannedRoadRoute(
      _directionsRouteOptions[index].route,
      origin: origin,
      destination: destination,
      label: label,
      driving: true,
    );
  }
```

- [ ] **Step 3: `parts/ui.dart`의 EtaCard 호출에 패널·상세보기·요금 지표 연결**

`else if (route != null)`(약 439행) 분기를 다음으로 교체:
```dart
        else if (route != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: EtaCard(
              key: _etaCardKey,
              distanceMeters: _outdoorEta(route).distanceM,
              minutes: _outdoorEta(route).minutes,
              label: userDestination != null
                  ? (_userDestinationLabel ?? '목적지까지')
                  : '건물 입구까지',
              guidanceStarted: _guidanceStarted,
              routeOptions: _directionsRouteExtras(context, route),
              extraMetric: _directionsFareMetric(route),
              onClose: userDestination != null
                  ? _dismissUserDestinationFromEtaCard
                  : null,
              onStartGuidance: userDestination != null && !_guidanceStarted
                  ? () => unawaited(_startCurrentGuidance())
                  : null,
              onClosePointerDown: userDestination != null
                  ? (position) => _etaClosePointerDown = position
                  : null,
            ),
          ),
```

같은 파일(`ui.dart`)의 `build` 메서드 밖, 클래스 확장 안에 헬퍼 2개 추가:
```dart
  /// 후보 패널과 상세보기 버튼을 묶어 [EtaCard.routeOptions]에 얹는다.
  /// 디자인시스템 카드에 상세보기 전용 슬롯이 없어 우리가 직접 붙인다.
  Widget? _directionsRouteExtras(BuildContext context, DirectionsRoute route) {
    final panel = _directionsRouteOptions.length > 1
        ? DirectionsRouteOptionsPanel(
            options: _directionsRouteOptions,
            selectedIndex: _selectedDirectionsOptionIndex,
            onSelect: (index) => unawaited(selectDirectionsOption(index)),
          )
        : null;
    final detailButton = route.steps.isEmpty
        ? null
        : Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: () => showDirectionsRouteDetailSheet(
                context,
                route: route,
                destinationLabel: _userDestinationLabel ?? '목적지',
              ),
              child: const Text('상세보기'),
            ),
          );
    if (panel == null && detailButton == null) return null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [if (panel != null) panel, if (detailButton != null) detailButton],
    );
  }

  /// 통행료가 있으면(0원 포함) 그것을, 없으면 택시비를 세 번째 지표로
  /// 쓴다. 도보 경로는 둘 다 null이라 아무것도 안 붙는다.
  RoutexTripMetric? _directionsFareMetric(DirectionsRoute route) {
    final toll = route.tollFareWon;
    if (toll != null) {
      return RoutexTripMetric(
        value: toll == 0 ? '무료' : formatTransitFare(toll),
        label: '통행료',
      );
    }
    final taxi = route.taxiFareWon;
    if (taxi != null) {
      return RoutexTripMetric(value: formatTransitFare(taxi), label: '택시비');
    }
    return null;
  }
```

**주의:** `ui.dart`는 `part of '../outdoor_map_screen.dart';`로 시작하는 part 파일이라 자신의 `import` 지시문을 가질 수 없다 — Dart는 실행할 때 import를 소유 라이브러리 파일에서만 읽는다. 그래서 이 import는 **`outdoor_map_screen.dart`**(Step 1에서 이미 손댄 그 파일) 맨 위 import 블록에 추가한다: `import '../../widgets/transit_style.dart' show formatTransitFare;`(`import '../../models/route/directions_route.dart';`와 같은 깊이).

- [ ] **Step 4: 정적 분석으로 컴파일 확인**

Run: `cd client && flutter analyze lib/screens/outdoor_map/`
Expected: 새로 추가한 코드에 오류 없음(기존에 있던 경고는 무시).

- [ ] **Step 5: 커밋**

```bash
cd client
git add lib/screens/outdoor_map/outdoor_map_screen.dart lib/screens/outdoor_map/parts/route.dart lib/screens/outdoor_map/parts/ui.dart
git commit -m "feat: 야외 지도에 자동차 경로 후보 선택과 상세보기를 연결한다"
```

---

### Task 10: 자동차 길찾기가 다중 후보를 조회하게 배선

**Files:**
- Modify: `client/lib/screens/map_shell/map_shell_screen.dart`
- Test: `client/test/screens/map_shell/route_mode_test.dart`

**Interfaces:**
- Consumes: `getDrivingRouteOptions`(Task 5), `showPlannedRoadRouteOptions`(Task 9).

- [ ] **Step 1: 실패하는 테스트 작성**

`route_mode_test.dart`의 `void main()` 안, 기존 테스트들 사이에 추가:
```dart
  testWidgets('자동차 모드에서 후보가 여러 개면 목록에서 고를 수 있다', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);
    await tester.tap(find.byTooltip('길찾기'));
    await drain(tester);
    await tester.enterText(destinationField(), '강의실');
    await drain(tester);
    await tester.tap(find.text('강의실 101').first);
    await drain(tester);

    await tester.tap(find.text('자동차'));
    await drain(tester);

    expect(find.byType(EtaCard), findsOneWidget);
    expect(find.text('추천'), findsOneWidget);
    expect(find.text('최단거리'), findsOneWidget);

    await tester.tap(find.text('최단거리'));
    await drain(tester);

    expect(find.byType(EtaCard), findsOneWidget);
    expect(find.text('최단거리'), findsOneWidget);
  });
```

(`MockDirectionsRepository`가 테스트 환경 기본값이므로 Task 5에서 만든 2개짜리 목업 후보가 그대로 쓰인다 — `import`는 이미 파일 상단에 있는 것들로 충분하다.)

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `cd client && flutter test test/screens/map_shell/route_mode_test.dart`
Expected: FAIL — `_startCarRoute`가 아직 단일 경로만 그려 "최단거리" 텍스트가 없음.

- [ ] **Step 3: 최소 구현 작성**

`map_shell_screen.dart`의 `_startCarRoute`(약 1768행)를 다음으로 교체:
```dart
  Future<void> _startCarRoute(
    DirectionsCandidate? origin,
    DirectionsCandidate destination,
  ) async {
    final outdoor = _outdoorKey.currentState;
    final from = origin == null
        ? outdoor?.routeOriginPoint
        : (outdoor?.entranceIfInsideBuilding(origin.point) ?? origin.point);
    if (outdoor == null || from == null) {
      _showSnack('현재 위치를 아직 못 잡았습니다. GPS 신호를 확인하거나 출발지를 직접 지정해주세요.');
      return;
    }
    final to =
        outdoor.entranceIfInsideBuilding(destination.point) ??
        destination.point;
    final options = await directionsRepository.getDrivingRouteOptions(
      origin: from,
      destination: to,
    );
    if (!mounted) return;
    if (!options.hasRoutes) {
      _showSnack('자동차 경로를 불러오지 못했습니다. 잠시 후 다시 시도해주세요.');
      return;
    }
    await outdoor.showPlannedRoadRouteOptions(
      options.options,
      origin: from,
      destination: to,
      label: destination.title,
    );
  }
```

- [ ] **Step 4: 테스트 실행해서 통과 확인**

Run: `cd client && flutter test test/screens/map_shell/route_mode_test.dart`
Expected: PASS(기존 테스트들 포함 전부)

- [ ] **Step 5: 전체 회귀 확인 후 커밋**

Run: `cd client && flutter analyze && flutter test`
Expected: 분석·테스트 전부 통과(기존 `_startCarRoute` 관련 다른 테스트가 있다면 함께 확인).

```bash
cd client
git add lib/screens/map_shell/map_shell_screen.dart test/screens/map_shell/route_mode_test.dart
git commit -m "feat: 자동차 길찾기가 여러 경로 후보를 조회해 목록으로 보여준다"
```

---

## Self-Review

**스펙 커버리지:**
- 자동차 다중 후보(searchOption 0,2,3,10, 중복 제거, 라벨 정직성) → Task 1,2,3,5.
- 턴바이턴 상세보기(자동차·도보 공통, 방위각 계산, 아이콘 재사용) → Task 1,4,8.
- 목록 UX(`RoutexEtaCard.routeOptions` 재사용, 모달 신설 안 함) → Task 6,7,9.
- 요금 표시(통행료 있으면, 없으면 택시비, 둘 다 없으면 생략) → Task 6,9.
- `_startCarRoute` 배선 → Task 10.
- 도보 다중 옵션 제외·대중교통 상세보기 제외·자전거 제외·회색 대안선 제외 → 어느 Task도 건드리지 않음(의도대로 무변경).

**플레이스홀더 스캔:** "TBD"/"나중에"류 문구 없음. 모든 코드 스텝에 실제 구현이 있다. Task 9만 예외적으로 "구현만, 검증은 Task 10이 맡는다"고 명시했는데, 이는 회피가 아니라 maplibre_gl 의존성 때문에 이 계층 자체가 단위 테스트 대상이 아니라는(기존 코드베이스도 이 파일들을 직접 단위 테스트하지 않는다) 사실을 그대로 반영한 것이다.

**타입 일관성:** `DirectionsRouteOptions`(Task 2) → `getDrivingRouteOptions` 반환 타입(Task 5) → `showPlannedRoadRouteOptions` 인자(Task 9) → `_startCarRoute` 호출(Task 10)까지 `List<DirectionsRouteOption>` 이름이 그대로 이어진다. `DirectionsRouteOptionKind.label`(Task 2)을 `DirectionsRouteOptionsPanel`(Task 7)과 통합 테스트(Task 10)가 그대로 쓴다. `_geometryKey`(Task 3)는 도메인 계층에만 있고 리포지토리(Task 5)는 그 함수를 부르기만 한다 — 중복 구현 없음.

---

Plan complete and saved to `docs/superpowers/plans/2026-08-19-directions-route-options.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
