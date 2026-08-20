# 매장 상세 인터페이스 — Wave 실행 계획

작성일: 2026-07-30

상태: Wave 1~3.6 완료 · Wave 5 데이터 작업 진행 중 · Wave 4 미착수

| 단계 | 상태 |
|---|---|
| Wave 1 갈래 A (클라이언트 id 관통) | 완료 — `afd3768` |
| Wave 1 갈래 B (백엔드 계약) | 완료 — `60440be` |
| Wave 2 C1·C2·C4 (스키마·검증기·테스트) | 완료 — `bb4c463` |
| Wave 2 C3 (오버레이 내용 작성) | 진행 중 — Wave 5 F1/F3과 같은 작업이라 아래로 합침 |
| Wave 3 D1~D7 (클라이언트 렌더러) | 완료 |
| Wave 3.5 (가드레일 복구 — D2) | 완료 (아래 절) |
| **Wave 3.6 (소개 영상용 파일럿 확장 — D2″)** | **완료** (아래 절) |
| Wave 4 (건물 스케일) | 미착수 |
| Wave 5 F1·F3 (커버리지) | 진행 중 — 스타벅스 리저브·블루보틀 여의도·시그니처 공간 5곳 |
| Wave 5 F2·F4·F5 | 미착수 |

**커버리지 작업은 브랜드가 아니라 공간 쪽으로 방향을 틀었다.** 브랜드 공식
사이트에서 지점 소개문을 구할 수 있는 곳이 15곳 중 1곳뿐이었고, 대신 더현대 서울
자체의 시그니처 공간은 현대백화점이 직접 설명한다. 근거와 실패 목록은
[bluebottle-yeouido-detail.md](bluebottle-yeouido-detail.md)·
[thehyundai-landmarks-detail.md](thehyundai-landmarks-detail.md)에 있다.

**C3에 대한 아래 원칙은 유지된다.** 파일럿 1건은 사용자가 직접 확인해 작성했고, 그 출처를
[starbucks-detail-pilot.md](starbucks-detail-pilot.md)에 표로 남겼다. 에이전트는 내용을
쓰지 않고 **형식·출처 강제 장치만** 만든다.

**C3를 에이전트가 대신 쓰지 않는 이유**: 오버레이에 들어갈 내용은 실제 매장에 대한
사실 주장이다. 원본에 없는 정보를 모델이 지어내면 그 순간 F3(출처 없는 값이 거짓말을
한다)를 설계가 아니라 데이터로 위반하게 된다. 검증기가 형식은 잡아 주지만 "그럴듯한
거짓"은 잡지 못한다. 내용은 매장을 확인할 수 있는 사람이 쓰고, 검증기가 형식과
드리프트를 본다.

상위 문서: [place-detail-interface.md](place-detail-interface.md)(계약·실패 조건),
[wave0-coverage.md](wave0-coverage.md)(사전 조사·결정)

---

## 0. 분해 원칙

- **Wave = 검증 가능한 상태**, 작업량 묶음이 아니다. 각 Wave 끝에서 앱이 돌고 테스트가
  통과해야 한다.
- **갈래(A/B/…) = 파일이 겹치지 않는 병렬 작업 단위.** 같은 Wave 안의 갈래끼리는 서로의
  모듈을 import하지 않는다. 경계는 파일 경로와 함수 시그니처 문자열뿐이다.
- **T번호 = 커밋 1개.** `.github/CONTRIBUTING.md` 커밋 규칙대로 성격이 다른 변경을 섞지 않는다.
- 각 Wave의 **완료 기준**은 설계 문서 8절 체크리스트의 부분집합이다. 새 기준을 여기서
  만들지 않는다.

### 의존 관계

```
Wave 1 ─┬─ 갈래 A (client: id 관통)  ─┐
        └─ 갈래 B (backend: 계약)    ─┼─→ Wave 3 ─→ Wave 4 ─→ Wave 5
Wave 2 ─── 갈래 C (data: 오버레이)   ─┘
```

Wave 1과 2는 완전 병렬(파일 교집합 0). Wave 3은 A·B가 끝나야 시작하고, C가 없어도
"섹션 0개" 상태로 개발·검증이 가능하다.

---

## Wave 1 — 상세를 열 수 있게 만든다

**목표**: id가 시트까지 도달하고(A), 그 id로 코어를 반환하는 API가 선다(B).
이 Wave가 끝나면 **데이터가 하나도 없어도 상세 시트를 띄울 준비**가 끝난다.

### 갈래 A — 클라이언트 id 관통 (`client/` 만 건드림)

조사 B1이 확인한 8개 생성 지점을 관통시킨다. 이 갈래는 **화면 변화가 없다** — 필드만
흐르게 하는 리팩터링이라 회귀 위험이 낮고, 실패해도 롤백이 쉽다.

| # | 파일 | 작업 |
|---|---|---|
| A1 | `client/lib/models/place/poi_search_result.dart` | `final String? placeId` 추가. nullable인 이유를 주석으로 남긴다(저장한 장소 구버전 항목) |
| A2 | `client/lib/screens/indoor_map/indoor_map_screen.dart:1265`<br>`client/lib/screens/map_shell/map_shell_screen.dart:475,483,506,514`<br>`client/lib/screens/outdoor_map/outdoor_map_screen.dart:2832` | 지도 폴리곤 탭 경로에서 `StorePolygon.id`를 `placeId`로 전달 |
| A3 | `client/lib/repositories/place/http_destination_repository.dart:93` | 검색 응답의 `match['store_id']`를 `placeId`로 싣는다 (서버는 이미 내려주고 있다) |
| A4 | `client/lib/screens/map_shell/widgets/sheets/category_stores_sheet.dart:403` | 카테고리 목록 → 시트 변환에 id 전달 |
| A5 | `client/lib/models/place/favorite_place.dart` | `placeId` 필드 + JSON 직렬화. **기존 저장분 하위호환**: 키가 없으면 null로 읽고, `key` getter 규칙은 바꾸지 않는다(바꾸면 저장한 장소가 전부 중복 등록된다) |
| A6 | `client/lib/repositories/place/mock_destination_repository.dart:88,98` | mock에도 합성 id를 채워 개발 모드에서 상세 경로가 죽지 않게 한다 |

**완료 기준**
- [ ] 지도 탭·텍스트 검색·카테고리 목록 세 경로에서 `placeId != null`
- [ ] 저장한 장소: 구버전 저장분을 읽어도 크래시 없음, 중복 등록 없음
- [ ] `flutter analyze` 무경고, 기존 `client/test` 통과

**위험**: A5. `FavoritePlace.key`를 건드리면 사용자의 저장 목록이 깨진다. **key 규칙은
절대 바꾸지 않는다**가 이 작업의 제약이다.

### 갈래 B — 백엔드 계약 (`backend/` 만 건드림)

| # | 파일 | 작업 |
|---|---|---|
| B1 | `backend/app/dto/place_detail.py` (신규) | `PlaceDetail`·`PlaceLocation`·`PlaceAction`·`Provenance`·`DetailSection` 유니온. 설계 4절 그대로 |
| B2 | `backend/app/repositories/place_detail_queries.py` (신규) | `Store`/`Building`/`Floor` 조인으로 **코어만** 조립. `entrance_node_id`가 null이면 길찾기 액션을 넣지 않는다 |
| B3 | `backend/app/repositories/place_details.py` (신규) | 오버레이 로더. `backend/resources/store_details/`를 읽고 **디렉터리가 없으면 빈 dict**를 반환한다. Wave 2는 이 디렉터리에 파일만 넣는다 |
| B4 | `backend/app/routers/buildings.py` | `GET /buildings/{building_id}/places/{place_id}` + ETag(`cache_headers`/`etag_matches` 재사용). 라우터는 파싱·404만, 조회는 B2 |
| B5 | `backend/tests/integration/test_place_detail_api.py` (신규) | 아래 완료 기준을 테스트로 |

**경계**: B3의 시그니처 `load_overlays() -> dict[str, dict]`와 리소스 경로
`backend/resources/store_details/`가 갈래 C와의 유일한 접점이다. C는 B의 코드를 import하지
않고, B는 C의 파일 존재를 가정하지 않는다.

**완료 기준** (설계 8절 백엔드 항목)
- [ ] 오버레이 0건 상태에서 임의 매장 → 200 + `sections: []` + 코어 전부
- [ ] `entrance_node_id`가 null인 매장 → 길찾기 액션 없음
- [ ] 주차·에스컬레이터·엘리베이터(1,007건)는 404가 아니라 **코어만** 반환 (시트를 열지
      말지는 클라이언트가 `kind`로 판단)
- [ ] 없는 `place_id` → 404
- [ ] 층 지도 응답(`FloorMapResponse`) 필드·크기 무변화 — F6 회귀 테스트
- [ ] 같은 요청 2회 → 두 번째 304
- [ ] **DB 스키마 변경 없음** (`models/place.py` 무수정)

---

## Wave 2 — 오버레이 데이터 (Wave 1과 병렬)

**목표**: 사람이 쓴 내용이 스키마 검증을 통과한 채로 리소스에 들어간다.
코드 변경은 검증 스크립트뿐이다.

### 갈래 C — 데이터 + 검증

| # | 파일 | 작업 |
|---|---|---|
| C1 | `backend/resources/store_details/_schema.json` (신규) | 허용 섹션 타입(`summary`/`keyValue`/`tags`/`notice`/`childList`/`map`)과 필드 선언. `hero`는 **선언하되 데이터 금지**(결정 D1) |
| C2 | `backend/scripts/validate_store_details.py` (신규) | 4가지 검사: ① 스키마 위반 ② Studio에 없는 id ③ `name` 불일치 ④ `notice` 만료일 경과. **하나라도 걸리면 비정상 종료** |
| C3 | `backend/resources/store_details/b1-food.json` (신규) | 파일럿. B1 식음료 124건 중 **먼저 20건**만 작성해 스키마가 현실에 맞는지 확인한 뒤 나머지를 채운다 |
| C4 | `backend/tests/unit/test_place_details.py` (신규) | 로더·검증기 단위 테스트. 깨진 오버레이 픽스처로 4가지 검사가 실제로 실패하는지 확인 |
| C5 | `backend/scripts/seed/reset_and_seed.py` | 시드 마지막에 C2를 호출. 검증 실패 시 시드도 실패 |

**왜 파일럿 20건을 먼저 쓰나**: 124건을 다 쓴 뒤 "`keyValue`에 넣을 게 없더라"를 알게 되면
124건을 다시 고친다. 스키마가 현실을 못 담는 걸 20건에서 알아채는 게 싸다.

**완료 기준** (설계 8절 데이터 항목)
- [ ] 전 오버레이 파일이 `_schema.json` 통과
- [ ] Studio에 없는 id 0건, 이름 불일치 0건
- [ ] 일부러 깨뜨린 픽스처 4종이 전부 검증에서 잡힘
- [ ] `python -m scripts.seed.reset_and_seed`가 검증까지 수행

**위험**: C3의 내용 품질. 출처 없는 사실(영업시간·전화·평점)을 쓰지 않는다는 규칙(F3)을
리뷰에서 강제한다. 리뷰 단위를 작게 유지하려고 파일을 층·카테고리로 쪼갠다.

---

## Wave 3 — 클라이언트 렌더러

**목표**: 사용자가 실제로 상세를 본다. Wave 1·2가 끝나야 시작한다(단 C 없이도 "섹션 0개"
상태로 착수 가능).

| # | 파일 | 작업 |
|---|---|---|
| D1 | `client/lib/models/place/place_detail.dart` (신규) | 응답 파싱. **모르는 섹션 타입은 조용히 버린다** — 설계 4-2 규칙 2를 파싱 단계에서 구현 |
| D2 | `client/lib/repositories/place/place_detail_repository.dart` (신규)<br>+ http/mock 구현 | `service_locator`에 등록. 실패 시 예외를 던지지 않고 null 반환(부가 정보 실패가 주 기능을 막으면 안 된다) |
| D3 | `client/lib/screens/map_shell/widgets/sheets/place_detail/` (신규) | 섹션별 렌더러 위젯. `summary`/`keyValue`/`tags`/`notice`/`map`. `hero`·`childList`는 이 Wave에서 만들지 않는다 |
| D4 | `client/lib/screens/map_shell/widgets/sheets/place_detail_sheet.dart` (신규) | 시트 본체. `StoreInfoSheet`의 chain 규약 코드(`_intentionalPop`·`PopScope`·`onCloseAll`·`GestureDetector` 2단)를 **그대로 이식**하고 본문만 교체. 로딩·에러·빈 상태 3종 |
| D5 | `client/lib/screens/map_shell/map_shell_screen.dart:280` | `_showStoreInfo`가 새 시트를 열도록 교체. `StoreInfoAction` 반환 계약(출발/도착/카테고리)은 유지 |
| D6 | `client/lib/widgets/store_info_sheet.dart` | 삭제 (D5 이후 참조 0건 확인하고 별도 커밋) |
| D7 | `client/test/screens/map_shell/widgets/sheets/place_detail_sheet_test.dart` (신규) | 아래 완료 기준을 위젯 테스트로 |

**핵심 제약 — 코어 먼저 그린다.** 이름·층·카테고리·출발/도착 버튼은 `PoiSearchResult`로
이미 알고 있으므로 **네트워크를 기다리지 않고 즉시** 그린다. 섹션 영역만 스켈레톤이다.
상세 요청이 3초 걸려도 그동안 길찾기를 누를 수 있어야 한다(F5).

**완료 기준** (설계 8절 클라이언트 항목)
- [ ] 섹션 0개 매장에서 시트가 정상 렌더 (지금보다 나쁘지 않다)
- [ ] chain 규약 회귀 3종: back=이전 시트 / 바깥 탭=전체 닫기 / X=전체 닫기
- [ ] 로딩 중에도 출발·도착 버튼 동작
- [ ] 상세 요청 실패(500·타임아웃·오프라인)에도 출발·도착 버튼 동작, 에러 다이얼로그 없음
- [ ] `placeId == null`(구버전 저장한 장소) → 요청을 보내지 않고 코어만 렌더
- [ ] 알 수 없는 섹션 타입이 섞인 응답 → 무시하고 나머지 렌더
- [ ] 주차구역·에스컬레이터(`kind` 제외 대상) 탭 → 기존 동작 유지, 상세 시트 안 뜸

---

## Wave 3.5 — 가드레일 복구와 화면 정리 (완료)

**발단**: Wave 3 구현 검증 중에 `businessInfo`가 `forbidden_labels` 가드레일을 우회하는
것이 드러났다. 검증기·시드·테스트 380건이 전부 통과한 상태에서 출처 없는
`영업시간`·`대표번호`가 응답에 실려 나갔다. **가드레일이 새 필드를 따라오지 못한 것**이라,
커버리지가 늘어나는 Wave 5 전에 닫아야 했다.

**중간에 방향이 한 번 바뀌었다.** 처음에는 "출처를 붙이면 허용"(D2′)으로 열었다가, 영업시간·
주차·오시는 길·위생등급을 화면에서 빼기로 하면서 전제가 사라져 **원래 D2로 되돌렸다.**
경위와 사유는 설계 9-1에 있다.

| # | 결과 |
|---|---|
| G1 | `_schema.json` — `forbidden_labels`에 `대표번호`·`문의` 보강. `businessInfo.item_keys`는 `label`·`value`로 원복 |
| G2 | `place_details.py` — `_validate_business_info` 신설. `forbidden_labels`를 **조건 없이** 적용 |
| G3 | `test_place_details.py` — 금지 라벨 검출·정상 통과 2건으로 회귀 고정 |
| G4 | 오버레이 — `tags` 제거, `businessInfo`는 `주소`만 남김 |
| G5 | `place_detail_rich_sections.dart` — 매장 정보에서 테두리·배경 제거, 구분선만 |
| G6 | `place_detail_sheet.dart` — 출처 줄 제거. 길찾기 버튼을 이름 옆으로 옮기고, 스크롤 시 하단 액션 바 추가 |
| G7 | 위젯 테스트 — `excluded` 본문 미표시, 하단 액션 바 등장, businessInfo 렌더 |

**완료 기준**
- [x] `forbidden_labels`가 `businessInfo`에도 적용된다 (조건 없음)
- [x] `businessInfo`에 `영업시간`을 넣으면 검증이 실패한다
- [x] `kind: "excluded"`에서 상세 섹션이 뜨지 않는다
- [x] 스크롤로 이름 옆 버튼이 가려지면 하단 액션 바가 뜬다
- [x] 백엔드 단위 16건 · 클라이언트 71건 · `flutter analyze` 무경고

**남은 결정**: `businessInfo`에 유일하게 남은 `주소`가 건물 주소라 전 매장이 동일하다.
뺄지 여부는 설계 문서 10절 "남겨 둔 과제"에 있다.

---

## Wave 3.6 — 소개 영상용 파일럿 확장 (완료)

**발단**: 소개 영상에 스타벅스 리저브 상세가 나오는데, 메뉴 4종에 영업시간도 없는 화면은
보여 줄 것이 없었다. **한 매장의 데이터를 두껍게 채우는 것이 목적이고, 그 과정에서 스키마가
견디지 못한 곳만 고쳤다.**

| # | 결과 |
|---|---|
| H1 | `_schema.json` v2 — `item_keys` → `required_keys`/`optional_keys`. `menu`의 필수는 `name`·`image_asset`뿐이고 `category`·`price`·`volume` 등 7개는 선택 |
| H2 | `_schema.json` — `demoInfo` 필드와 `demo_allowlist` 신설 (D2″) |
| H3 | `place_details.py` — 키 목록을 **스키마에서 읽는다**. 선언하지 않은 키는 오타로 보고 실패시킨다. `_validate_demo_info` 신설 |
| H4 | `place_detail_queries.py` — 선택 키는 값이 있을 때만 싣는다(빈 문자열로 채우지 않는다). `demoInfo` 섹션을 `businessInfo` 위에 놓는다 |
| H5 | 오버레이 — 메뉴 30종·6카테고리, hero 5장, `demoInfo` 5항목 (이후 전량 316종·16카테고리로 확장 — [파일럿 문서](starbucks-detail-pilot.md#메뉴)) |
| H6 | `place_detail.dart` — `MenuItem.price`를 선택으로. `DemoInfoSection` 추가 |
| H7 | `place_detail_rich_sections.dart` — 메뉴 카테고리 탭, 가격 없을 때 용량·칼로리·카페인 대체, `PlaceDemoInfoSection` |
| H8 | `pubspec.yaml` — 매장 상세 이미지를 파일 목록이 아니라 디렉터리 단위로 등록 |

**완료 기준**
- [x] 가격 없는 메뉴가 크래시 없이 파싱되고, 카드가 용량·칼로리·카페인을 대신 보여 준다
- [x] 셋 다 없는 항목(푸드)은 그 줄을 아예 그리지 않는다
- [x] 카테고리 탭이 서버 등장 순서대로 뜨고, 한 항목이라도 카테고리가 없으면 탭을 안 만든다
- [x] `demo_allowlist`에 없는 매장이 `demoInfo`를 쓰면 검증이 실패한다
- [x] `demoInfo` 항목의 `source`가 http(s)가 아니거나 `confirmed_at`이 `YYYY-MM-DD`가 아니면 실패한다
- [x] 선언하지 않은 키(`calorie` 같은 오타)가 있으면 실패한다
- [x] 백엔드 590건 · 클라이언트 631건 · ruff format/check · mypy · `flutter analyze` 무경고
- [x] 스키마 v2가 기존 오버레이 11건을 그대로 통과시킨다 (필수 키를 줄인 변경이라
      기존 데이터가 깨지지 않는다)

**남은 결정**: 확인일 만료 기준이 없다. `demo_allowlist`에 매장을 더할 때의 절차와 함께
설계 문서 10절 "남겨 둔 과제"에 있다.

---

## Wave 4 — 건물 스케일

**목표**: 같은 렌더러로 건물 홈(참고 화면 1~2)이 뜬다.

| # | 파일 | 작업 |
|---|---|---|
| E1 | `backend/app/repositories/place_detail_queries.py` | `kind: "building"` 분기. `childList` 섹션에 카테고리별 카운트를 넣는다. **이미 조사에서 센 값**(패션 266·식음료 134·…)이 그대로 화면 숫자가 된다 |
| E2 | `client/lib/screens/map_shell/widgets/sheets/place_detail/child_list_section.dart` (신규) | 자식 목록 렌더러. 항목 탭 → 그 매장의 상세로(같은 시트 재귀) |
| E3 | `client/lib/screens/map_shell/map_shell_screen.dart:263` | 건물 선택 시 `_placeInfo` 제목/부제 대신 상세 시트 |
| E4 | 테스트 | 건물 상세 응답 + 자식 목록 탭 → 매장 상세 전이 |

**완료 기준**
- [ ] 더현대 서울 홈이 이름·카테고리·층 수·내부시설 카운트를 갖고 뜬다
- [ ] 내부시설 목록에서 매장을 고르면 매장 상세로 이어지고, back으로 건물 홈에 돌아온다
- [ ] 카운트가 `/buildings/{id}/stores` 실제 건수와 일치

**주의**: 재귀 시트는 chain 규약을 가장 쉽게 깨뜨리는 지점이다. Wave 3의 회귀 테스트 3종을
건물→매장 경로에서 다시 돌린다.

---

## Wave 5 — 커버리지·마감

| # | 작업 |
|---|---|
| F1 | 1차 커버리지 291건 완성 (B1 124 · 4F 85 · 3F 82) |
| F2 | 위치 안내형 92건 파생 규칙 구현 (좌표·층 → "B2 서편, 엘리베이터 옆" 형태). 사람이 쓰지 않는다 |
| F3 | 2차 커버리지 248건 (B2 68 · 2F 64 · 1F 63 · 5F 33 · 6F 18) |
| F4 | 성능 측정: 상세 응답 p95 < 150ms(로컬 캐시 미스), 시트 첫 프레임 대기 없음 |
| F5 | 문서 갱신 — 설계 문서 상태를 Planning → Done, 실제 커버리지 숫자 기록 |

F1~F3은 **데이터 작업이라 언제든 중단·재개 가능**하다. 코드가 이미 "없으면 안 보여준다"로
동작하므로, 어느 시점에 멈춰도 앱은 정상이다. 이것이 설계 F1을 설계 단계에서 방어한 이유다.

---

## 검증 실행 방법

`docs/guide/session-rules.md`대로 창 2개를 띄우고 로그를 tee한다. 명령은 체이닝하지 않고 한 줄씩.

```powershell
py -3.12 -m venv .venv
```

```powershell
python -m scripts.seed.reset_and_seed
```

```powershell
python -m uvicorn app.main:app --reload --reload-dir app --host 0.0.0.0 --port 8001 2>&1 | ForEach-Object { $_; $_ | Out-File ..\backend-local.log -Append -Encoding utf8 }
```

```powershell
flutter run -d chrome 2>&1 | ForEach-Object { $_; $_ | Out-File frontend.log -Append -Encoding utf8 }
```

Wave별로 확인할 것:

- **Wave 1 B**: `backend/app/sql/queries.sql`에서 상세 조회가 N+1을 내지 않는지
- **Wave 2**: 시드 로그에 검증 통과/실패 줄이 남는지
- **Wave 3**: `frontend.log`에 상세 요청 실패 시 예외가 아니라 경고로 남는지

---

## Wave별 롤백 단위

| Wave | 되돌리는 방법 | 되돌렸을 때 상태 |
|---|---|---|
| 1-A | 커밋 revert | 화면 변화가 없던 리팩터링이라 무해 |
| 1-B | 라우터 등록 1줄 제거 | 엔드포인트만 사라짐, 기존 API 무영향 |
| 2 | 오버레이 파일 삭제 | 로더가 빈 dict를 반환해 코어만 남음 |
| 3 | `store_info_sheet.dart` 복구 + 호출부 되돌리기 | D6을 별도 커밋으로 두는 이유 |
| 4 | 진입점 커밋만 revert | 매장 상세는 그대로 동작 |
| 5 | 데이터 파일 단위 | 부분 롤백 가능 |
