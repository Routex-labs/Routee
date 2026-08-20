# backend

FastAPI 기반 실내 내비게이션 API 서버.

각 디렉터리는 자체 `README.md`에 상세 설명(역할·구성 파일·설계 근거·의존성·자주 하는 작업)을 담는다.
아래는 그 문서들을 모은 목차다.

## 문서 목차

| 계층 | 디렉터리 | 역할 |
|---|---|---|
| 앱 목차 | [`app/`](app/README.md) | FastAPI 애플리케이션 전체 계층 안내 |
| 진입점 | [`app/main.py`](app/main.py) | FastAPI 앱 팩토리 · 라우터 등록 · `/health` |
| 경계 | [`app/routers/`](app/routers/README.md) | HTTP 엔드포인트, 상태 코드 번역 |
| 계약 | [`app/dto/`](app/dto/README.md) | Pydantic 요청/응답 스키마 |
| 접근 | [`app/repositories/`](app/repositories/README.md) | DB 조회 + 응답 dict 조립 |
| 데이터 | [`app/models/`](app/models/README.md) | SQLAlchemy ORM 엔티티 (테이블) |
| 순수 로직 | [`app/geo/`](app/geo/README.md) | 좌표 변환 · 지도 타일 |
| 그래프 | [`app/graph/`](app/graph/README.md) | 그래프 무결성 검증 · 리비전 체크섬 |
| 인프라 | [`app/core/`](app/core/README.md) | 설정 · DB 엔진/세션 |
| 스크립트 목차 | [`scripts/`](scripts/README.md) | 시드 · 변환 · 검색 평가 · 모델 워밍 |
| 스크립트 | [`scripts/seed/`](scripts/seed/README.md) | DB 초기화 · 시드 (DB 접근) |
| 스크립트 | [`scripts/transform/`](scripts/transform/README.md) | 순수 변환 (파일→파일 / dict→dict) |
| 평가 | [`notebooks/`](notebooks/README.md) | FAISS·Kiwi 품질 분석 노트북 |
| 리소스 | [`resources/`](resources/README.md) | Studio 입력 · 글리프 · 검색 분류 사전 |
| 테스트 | [`tests/`](tests/README.md) | 합성/실데이터 픽스처 기반 단위·통합 테스트 |

## 처음 읽는 순서

처음 보는 사람은 아래 순서대로 읽는다. 각 문서 맨 아래의 **다음 읽기** 링크가 이 순서를
그대로 이어 주므로, 목차로 돌아오지 않아도 된다.

```text
backend README
→ app → core → models → dto → geo → graph → repositories → routers
→ scripts → transform → resources → studio → fonts → seed
→ notebooks → tests → fixtures → unit → integration
```

## 디렉터리 구조

```
backend/
├── app/                 # 애플리케이션 코드
│   ├── main.py          # FastAPI 진입점 · 라우터 등록
│   ├── core/            # 설정과 인프라 (config, database)
│   ├── models/          # SQLAlchemy ORM 모델 (DB 테이블)
│   ├── dto/             # Pydantic 요청/응답 스키마
│   ├── repositories/    # DB 쿼리 계층 (건물·타일 조회, 좌표 변환)
│   ├── geo/             # 지리 계산 (georeference, tiling)
│   ├── graph/           # 길찾기 그래프 도메인 (무결성 검증, 리비전 체크섬)
│   └── routers/         # HTTP 엔드포인트 (buildings, query, fonts)
├── scripts/             # 오프라인 실행용 스크립트
│   ├── eval/query_eval_set.json  # 평가 질의 세트(설계: docs/backend/native/search-eval-set.md)
│   ├── evaluate_query_hybrid.py  # 최종 AI 경로 실데이터 평가
│   ├── analyze_similarity_margin.py  # 의미 검색 채택 규칙 후보 비교
│   ├── warm_embedding_model.py   # 임베딩 모델을 로컬 HF 캐시에 선다운로드
│   ├── seed/            # DB 초기화·시드 (reset_and_seed 등)
│   ├── transform/       # 데이터 가공 (글리프 생성, 층 정렬 등)
│   └── tools/           # 보조 도구 (GCP 리전 선택 HTML 등)
├── notebooks/           # FAISS·Kiwi 품질 평가 (선택 개발 의존성)
├── resources/           # 정적 리소스
│   ├── fonts/           # MapLibre SDF 글리프 (Pretendard)
│   ├── studio/          # 스튜디오 원본 데이터
│   ├── query_synonyms.json             # 자연어 질의 별칭 → 표준어
│   ├── official_floor_guide.json      # 공식 층별안내 스냅샷 (분류의 원본)
│   ├── category_section_map.json      # 공식 섹션 → 우리 분류 매핑표·예외
│   ├── store_categories.json          # 매장 id → 카테고리 (생성물)
│   └── store_category_by_name.json    # 매장명 → 카테고리 (생성물, 폴백)
├── data/                # 런타임 SQLite DB (gitignore, 재생성 가능)
├── requirements.txt     # 서버·테스트 필수 의존성
├── requirements-dev.txt # 평가 노트북 전용 선택 의존성
└── tests/               # 테스트
    ├── unit/            # 단위 테스트 (좌표 변환·타일·시드)
    └── integration/     # 통합 테스트 (API·DB)
```

## 계층 흐름

요청은 바깥(HTTP)에서 안(DB)으로 흐르고, 결과는 `dto`로 직렬화되어 돌아간다.
`geo`는 프레임워크를 모르는 순수 계산 모듈이고, `core`는 모두가 딛는 기반이다.
최단 경로 계산은 서버에 없다 — 층 지도 응답의 `navigation_graph`를 받아 **클라이언트가 온디바이스 Dijkstra**(`client/lib/domain/dijkstra.dart`)로 수행한다.

```
        HTTP 요청
           │
           ▼
   ┌───────────────┐   response_model
   │   routers/    │───────────────► dto/        (계약: 나가는 모양)
   └───────┬───────┘
           │  조회
           ▼
   ┌───────────────┐        ┌──────────────┐
   │ repositories/ │───사용─►│    geo/      │  (순수 로직, 부작용 없음)
   └───────┬───────┘        └──────────────┘
           │
           ▼
   ┌───────────────┐
   │    models/    │
   │   (ORM/DB)    │
   └───────┬───────┘
           ▼
        SQLite

   core/ (config·database) ── 위 모든 계층이 Session/설정을 여기서 얻음
```

의존 규칙: 바깥이 안을 호출하고, 안은 바깥을 모른다. `models`/`geo`는 상위 계층에 의존하지 않으며, `dto`는 `models`를 import하지 않는다(저장되는 모양 ≠ 나가는 모양).

## 실행

### 로컬 실행 (권장)

`backend/`에서:

```text
# 최초 1회 또는 의존성 변경 시
python -m venv .venv
# Windows: .\.venv\Scripts\Activate.ps1
# macOS: source .venv/bin/activate
python -m pip install -r requirements.txt

# 검증할 때마다 DB 적재
python -m scripts.seed.reset_and_seed
# 테스트
python -m pytest
```

서버는 보이는 창에서 실행하며, 같은 출력을 `backend-local.log`에 남긴다. 상세 로그가
필요하면 `NAV_LOG_LEVEL=DEBUG`를 앞에 붙인다.

```powershell
# Windows PowerShell
python -m uvicorn app.main:app --reload --reload-dir app --host 0.0.0.0 --port 8001 2>&1 | ForEach-Object { $_; $_ | Out-File ..\backend-local.log -Append -Encoding utf8 }
```

```bash
# macOS
python -m uvicorn app.main:app --reload --reload-dir app --host 0.0.0.0 --port 8001 2>&1 | tee ../backend-local.log
```

DB 위치·종류는 환경변수 `NAV_DATABASE_URL`로 바꾼다(기본: `backend/data/navigation.db`,
Compose는 컨테이너의 `/app/data/navigation.db`). 자세한 건 [`app/core/README.md`](app/core/README.md).

### Docker Compose (배포 환경 확인용)

Docker는 일상 개발 실행에 쓰지 않는다. 배포 이미지·컨테이너 환경 호환성을 명시적으로 확인할
때만 저장소 루트에서 `docker compose up --build backend`를 사용한다. 실제 Cloud Run 배포 절차는
[`../docs/guide/gcp-instance.md`](../docs/guide/gcp-instance.md)를 따른다.

---

> **다음 읽기:** [`backend/app` — FastAPI 애플리케이션](app/README.md)
