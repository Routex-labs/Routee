# `backend/resources` — 서버 정적·입력 데이터

DB를 재생성할 수 있는 Studio 입력, MapLibre 글리프, 자연어 검색 사전과 매장 분류를
보관한다. `data/navigation.db`와 달리 재생성의 근거이므로 Git에서 추적한다.

## 문서 목차

| 경로 | 역할 | 소비자 |
|---|---|---|
| [`studio/`](studio/README.md) | 층별 그래프·매장·좌표 입력 | `scripts/seed/studio_adapter.py` |
| [`fonts/`](fonts/README.md) | MapLibre SDF glyph 범위와 라이선스 | `app/routers/fonts.py` |
| [`calibration/`](calibration/README.md) | 건물 좌표 정합 GCP 관측치 | `scripts/transform/refit_building_wgs84.py` |
| [`store_search_facets/`](store_search_facets/) | 패싯 검색 사전·의도·카테고리(`_intents.json`, `_vocabulary.json`, `fashion.json`, `restaurants.json`, `shoes.json`) | `repositories/store_facets.py` |
| [`query_synonyms.json`](query_synonyms.json) | 사용자 표현 → 표준 검색어 | `repositories/query_search.py`, `query_morph.py` |
| [`official_floor_guide.json`](official_floor_guide.json) | 더현대 서울 공식 층별안내 스냅샷 (분류의 원본) | `scripts/transform/build_store_categories.py` |
| [`category_section_map.json`](category_section_map.json) | 공식 섹션 → 우리 대분류·소분류 매핑표와 예외 | `scripts/transform/build_store_categories.py` |
| [`store_categories.json`](store_categories.json) | 매장 ID 기반 카테고리 보정 **(생성물)** | `scripts/seed/studio_adapter.py` |
| [`store_category_by_name.json`](store_category_by_name.json) | 매장명 기반 카테고리 fallback **(생성물)** | `scripts/seed/studio_adapter.py` |

## 소비 관계

```mermaid
flowchart LR
    STUDIO["studio/"]
    CATEGORY["store_categories*.json"]
    SYN["query_synonyms.json"]
    FONT["fonts/"]
    SEED["scripts/seed"]
    DB[("SQLite")]
    QUERY["repositories/query_search"]
    ROUTER["routers/fonts"]
    CLIENT["Flutter MapLibre"]

    STUDIO --> SEED
    CATEGORY --> SEED --> DB
    SYN --> QUERY
    DB --> QUERY
    FONT --> ROUTER --> CLIENT
```

## 변경 규칙

- JSON은 UTF-8로 저장한다.
- Studio 파일을 수정한 뒤 DB를 다시 시드하고 참조 무결성 테스트를 실행한다.
- 동의어는 표준어와 별칭 방향을 확인하고 `test_query_search.py`로 회귀를 고정한다.
- 카테고리 보정은 ID 우선, 이름 fallback이며 같은 이름의 다른 매장 영향을 확인한다.
- **카테고리 두 파일은 손으로 고치지 않는다.** `category_section_map.json`을 고치고
  `python scripts/transform/build_store_categories.py`로 다시 만든다 — 근거와 판단 기록은
  [매장 카테고리 전수 재조사](../../docs/backend/store-category-resurvey.md).
- 폰트 파일을 교체할 때 `OFL.txt` 등 배포 라이선스를 함께 유지한다.

## 실패 지점

- 생성 DB만 수정하면 다음 `reset_and_seed`에서 변경이 사라진다.
- Studio node/edge ID를 바꾸고 store의 `entrance_node_id`를 갱신하지 않으면 길찾기가 끊긴다.
- 동의어 JSON 오류는 서버 첫 import 또는 첫 질의 시 검색 전체를 막을 수 있다.
- 원본과 변환 산출물을 구분하지 않으면 같은 변환을 두 번 적용할 수 있다.

---

> **다음 읽기:** [`resources/studio` — 층별 내비게이션 원본](studio/README.md)
