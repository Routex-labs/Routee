# 백엔드 리팩터링 작업 단위

출처: `Navigation 저장소 리팩터링 감사 및 실행 계획.pdf` (기준 커밋 `3b2a5cb`, main 대비 6개 커밋 앞선 시점 감사).
원문서는 백엔드·클라이언트(Flutter)·네이티브를 모두 다루지만, 이 폴더는 **백엔드(FastAPI/SQLAlchemy/SQLite,
Studio 시드 파이프라인, Docker/운영)에 해당하는 항목만** 추려 브랜치 단위 작업 문서로 분리한 것이다.

클라이언트 전용 항목(Flutter 테스트 CI 통합, 화면 컨트롤러 분리, 비동기 경쟁 조건, PDR 핫패스, 라우트 캐시 등)은
제외했다. 다만 **02번(수직 전이 계약)** 은 클라이언트의 이름 기반 재해석 로직 제거와 짝을 이루는 작업이므로,
클라이언트 쪽 후속 작업이 별도로 필요하다는 점만 각 문서에 명시해 두었다.

## 작업 목록과 병합 순서

원문서의 권장 순서(테스트 게이트 → 수직 전이 단일화 → 그래프 무결성 → 나머지)를 백엔드 범위로 옮기면 다음과
같다. **각 항목은 별도 브랜치에서 작업하고, 순서대로 `main`에 머지한다.** 뒤 항목이 앞 항목의 타입/모델 변경에
의존하므로 순서를 건너뛰지 않는다.

| 순서 | 문서 | 브랜치(제안) | 요약 |
| --- | --- | --- | --- |
| 1 | [01-backend-test-gate.md](01-backend-test-gate.md) | `chore/backend-ci-gate` | ruff/mypy/pytest/pip-audit CI 게이트 복구, 기준선 확보 |
| 2 | [02-vertical-transfer-contract.md](02-vertical-transfer-contract.md) | `feat/vertical-transfer-contract` | 수직 전이(에스컬레이터/엘리베이터) 결과를 백엔드가 단일 원천으로 확정해 응답에 명시 |
| 3 | [03-graph-integrity-constraints.md](03-graph-integrity-constraints.md) | `feat/graph-integrity-constraints` | DB CheckConstraint, graph validator, PRAGMA, NaN/Infinity 거부 |
| 4 | [04-vertical-edge-generation-determinism.md](04-vertical-edge-generation-determinism.md) | `fix/vertical-edge-generation-determinism` | 에스컬레이터/엘리베이터 간선 생성 알고리즘의 입력 순서 의존성 제거 |
| 5 | [05-store-entrance-snap-limit.md](05-store-entrance-snap-limit.md) | `fix/store-entrance-snap-limit` | 매장 입구 스냅 최대 거리 제한과 unresolved 보고 |
| 6 | [06-tile-cache-bounded.md](06-tile-cache-bounded.md) | `perf/tile-cache-bounded` | MVT 타일 캐시 bounded LRU + single-flight |
| 7 | [07-ops-docker-seed-cleanup.md](07-ops-docker-seed-cleanup.md) | `chore/ops-docker-seed-cleanup` | Dockerfile 단일화, 운영 seed 분리, readiness/liveness, CORS |
| 8 | [08-dependency-model-supply-chain.md](08-dependency-model-supply-chain.md) | `chore/dependency-supply-chain` | requirements 분리, HF model revision 고정, 이미지 digest 고정, API 키 보호 |

## 검토 노트

- [09-load-and-scaling.md](09-load-and-scaling.md) — 부하·동시성·로깅 검토. 단일 작업 단위가 아니라
  실행 모델과 병목 우선순위를 정리한 근거 문서다. 파일 기반 진단 로깅을 stdout 로깅으로 교체한
  변경 내역도 여기에 기록한다.

## 공통 규칙

- 각 브랜치는 위 표의 순서대로 `main`에서 분기하고, 이전 항목이 머지된 뒤 다음 브랜치를 새로 판다(리베이스 충돌 최소화).
- 커밋/PR 규칙은 [.github/CONTRIBUTING.md](../../../.github/CONTRIBUTING.md)를 따른다(한글 커밋, `Co-Authored-By` 금지, PR 5섹션 템플릿).
- 각 문서의 "완료 기준"은 PR 설명의 테스트 계획에 그대로 옮겨 쓴다.
- 실제 동작 확인은 `AGENTS.md`의 로컬 실행 절차(백엔드 venv, uvicorn stdout 로그)를 사용한다. 파일 기반 진단 캡처(옛 `NAV_SQL_ECHO`/`NAV_HTTP_CAPTURE`)는 제거됐고, 상세 로그가 필요하면 `NAV_LOG_LEVEL=DEBUG`로 실행한다.
