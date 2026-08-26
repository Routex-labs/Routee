# 문서 색인

**작업을 이어받는 사람은 [인계 문서](HANDOFF.md)부터 읽는다** — 지금 어디까지 왔고 다음에
무엇을 하는지, 그리고 모르면 한 번은 밟는 함정들이 거기 있다.

이 저장소의 문서 전부를 영역별로 건다. **새 문서를 추가하면 여기에도 한 줄 추가한다** —
색인이 없어서 어디에서도 링크되지 않는 문서가 네 건 생긴 적이 있고, 링크되지 않는 문서는
낡아도 아무도 모른다.

문서 안의 진행 상태·수치는 **각 문서가 단일 출처**다. 이 색인은 "무엇이 어디 있는지"만
말하고 내용을 요약하지 않는다 — 요약을 두면 그 요약이 먼저 썩는다.

## 실행·배포

| 문서 | 내용 |
|---|---|
| [로컬 개발 가이드](guide/local-development-guide.md) | 플랫폼별 실행, API 주소, 문제 해결 |
| [GCP 배포](guide/gcp-instance.md) | Cloud Run 배포, `main` push 자동 배포 |

## 백엔드 — 이 저장소에 없다

서버는 Spring Boot로 이식돼 [Routex-labs/backend](https://github.com/Routex-labs/backend)에 있고,
엔드포인트 계약의 단일 출처는 그 저장소의 `docs/api/contract.md`다.

걷어낸 FastAPI 서버와 그 문서 43건, **원본 도면 데이터와 시드·변환 파이프라인**은
[Routex-labs/fastapi](https://github.com/Routex-labs/fastapi)에 히스토리째 남아 있다. B2 현장 실측,
매장 상세 조사, facet 검수(P2 슈즈 · P3 패션) 같은 실측 기록도 그쪽 `docs/`에 있다 — 설명하는
코드와 데이터 옆에 두는 편이 링크가 안 죽는다.

**이 저장소의 문서에서 `app/` · `scripts/` · `resources/` · `tests/`로 시작하는 경로는 그 저장소
기준이다.** 경로마다 저장소 이름을 붙이지 않고 여기 한 줄로 적는다.

## 클라이언트 UI

| 문서 | 내용 |
|---|---|
| [지도·상세 UI 개선 계획 (v1)](client/map-ui-redesign-plan.md) | 지도 렌더링 — 폰트·팔레트·마커·경로선 |
| [네이버지도 UI/UX 분석 (v2)](client/naver-map-ui-ux-analysis.md) | 정보 구조와 목록·시트 UX |
| [UI/UX 리서치 데스크](client/ui-ux-research-desk.md) | 참고 사이트·도구, 팔레트 대비 실측, 지도 4사 관찰 |
| [카카오맵 실내 도면 관찰](client/kakao-map-indoor-observation.md) | 마커 위계, 출구·보이드·폭포정원 도출 작업과 데이터 판정 |
| [검색 입력 보조](client/search-input-assist.md) | 자동완성·오타 교정 |
| [검색 결과 목록 UX](client/search-result-list-ux.md) | 결과 행 구조와 정렬 |
| [카메라 연출](client/camera-choreography-plan.md) | 안내 시작·층 전환 카메라, 카메라 가둠 |
| [지도 스타일 규칙](client/map-style-rules.md) | 도면 색·라벨·아이콘의 근거와 MapLibre 함정 |
| [전역 테마 넘기기](client/theme-handover.md) | Runtime Kit 전환의 조건·재 본 값·남은 순서 |
| [실내 진입·이탈 판정 규칙](client/indoor-entry-rules.md) | GPS·zoom·근접 세 축의 임계값 근거 |
| [실내 구간이 앞에 붙는 여정](client/indoor-leg-in-outdoor-journey.md) | 실내→야외·대중교통·자동차의 총 소요·카드·선호 줄 |
| [GPS 스트림 정책](client/gps-stream-policy.md) | 스트림 수명·신선도·경로 재계산 주기 |
| [안드로이드 heading 드리프트](client/android-heading-drift.md) | gyro hold가 영구 래치가 되던 구조와 그 수정 |
| [에스컬레이터 층 판정 임계값](client/escalator-thresholds.md) | 상수마다의 실측 근거와 실측에서 나온 함정 |
| [현장 검증 체크리스트](client/field-verification-thehyundai.md) | 더현대 서울에서만 확인되는 항목과 기록 방법 |
| [클라이언트 구조 개편 계획](client/structure-plan.md) | `lib/` 전체 — 디렉터리 성격, 쪼갤 함수, 테스트 규칙 |
| [야외 지도 화면 해체 계획](client/outdoor-map-decomposition.md) | 장기 브랜치의 목표·순서·rebase 규칙 |
| [이동 대장](client/outdoor-map-moves.md) | 옛 심볼 → 새 위치 (rebase 충돌 해결용) |
| [디버그 강제 층 전환 버튼 배치](client/debug-floor-toggle-button.md) | 버튼 위치·노출 조건의 근거 |

## 리팩터 과제

[개요와 순서는 refactor/README.md](https://github.com/Routex-labs/fastapi/blob/main/docs/refactor/README.md)에 있다.

| 문서 | 내용 |
|---|---|
| [01 백엔드 테스트 게이트](https://github.com/Routex-labs/fastapi/blob/main/docs/refactor/01-backend-test-gate.md) | CI 게이트 |
| [02 수직 전이 계약](https://github.com/Routex-labs/fastapi/blob/main/docs/refactor/02-vertical-transfer-contract.md) | 층간 이동 계약 정리 |
| [03 그래프 무결성 제약](https://github.com/Routex-labs/fastapi/blob/main/docs/refactor/03-graph-integrity-constraints.md) | 시드 단계 검증 |
| [04 수직 간선 생성 결정성](https://github.com/Routex-labs/fastapi/blob/main/docs/refactor/04-vertical-edge-generation-determinism.md) | 재현 가능한 간선 생성 |
| [05 매장 입구 스냅 한계](https://github.com/Routex-labs/fastapi/blob/main/docs/refactor/05-store-entrance-snap-limit.md) | 스냅 거리 초과 처리 |
| [06 타일 캐시 상한](https://github.com/Routex-labs/fastapi/blob/main/docs/refactor/06-tile-cache-bounded.md) | 메모리 상한 |
| [07 운영 — Docker·시드 정리](https://github.com/Routex-labs/fastapi/blob/main/docs/refactor/07-ops-docker-seed-cleanup.md) | 배포 이미지·시드 절차 |
| [08 의존성·모델 공급망](https://github.com/Routex-labs/fastapi/blob/main/docs/refactor/08-dependency-model-supply-chain.md) | 모델 파일 공급 경로 |
| [09 부하와 스케일링](https://github.com/Routex-labs/fastapi/blob/main/docs/refactor/09-load-and-scaling.md) | 부하 특성 |

## PDR (실내 측위)

| 문서 | 내용 |
|---|---|
| [마이그레이션 계획](pdr/pdr-migration-plan.md) | PDR 도입 단계 |
| [개발 통합](pdr/pdr-dev-integration.md) | 앱에 붙이는 방법 |
| [노드 체크포인트 개선 계획](pdr/pdr-node-checkpoint-improvement-plan.md) | 보정 지점 설계 |
| [경로·층 전환 개선 계획](pdr/pdr-route-and-floor-transition-improvement-plan.md) | 층 전환 시 측위 |
