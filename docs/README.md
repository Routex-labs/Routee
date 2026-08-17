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

## 백엔드 구조

| 문서 | 내용 |
|---|---|
| [FastAPI 요청 흐름](backend/fastapi-request-flow.md) | Router → Query → SQLite 구조 |
| [더현대 B2 현장 조사](backend/thehyundai-b2f-field-survey.md) | B2 층 실측 기록 |

## 검색·탐색 (native)

| 문서 | 내용 |
|---|---|
| [대화형 매장 탐색·추천 설계](backend/native/conversational-discovery.md) | 검색 facet 원본, 복수 추천 계약, 질문·선택 흐름 |
| [질의 파이프라인](backend/native/query.md) | `/query` 계약과 매칭 단계 |
| [FAISS](backend/native/FAISS.md) | 임베딩 색인·의미 검색 |
| [KIWI](backend/native/KIWI.md) | 형태소 분석·정규화 |
| [facet LLM 태깅](backend/native/facet-llm-tagging.md) | 태깅 파이프라인과 판단 기준 |
| [facet 리뷰 P2 — 신발](backend/native/facet-review-p2-shoes.md) | 사람 검수 기록 |
| [facet 리뷰 P3 — 패션](backend/native/facet-review-p3-fashion.md) | 사람 검수 기록 |
| [검색 평가셋](backend/native/search-eval-set.md) | 기준선과 평가 방법 |
| [검색 QA 수정 라운드](backend/native/search-qa-fix-wave.md) | 결함 목록과 처리 |
| [클라이언트 인계](backend/native/client-handoff.md) | 검색 계약의 클라이언트 쪽 접점 |

## 길찾기 (navigate)

| 문서 | 내용 |
|---|---|
| [수직 전이 경로](backend/navigate/vertical-transfer-routing.md) | 층간 이동 간선과 정책 |
| [에스컬레이터 폴리곤 보정](backend/navigate/escalator-polygon-backfill.md) | 폴리곤 누락분 채우기 |
| [클라이언트 인계](backend/navigate/client-handoff.md) | 그래프 계약의 클라이언트 쪽 접점 |

## 매장 상세 (place-detail)

| 문서 | 내용 |
|---|---|
| [매장 상세 인터페이스](backend/place-detail/place-detail-interface.md) | 계약·실패 조건·화면 명세 (설계 단일 출처) |
| [Wave 실행 계획](backend/place-detail/wave-plan.md) | 작업 분해와 **진행 상태 표** |
| [Wave 0 커버리지 조사](backend/place-detail/wave0-coverage.md) | 사전 조사와 당시 결정 |
| [스타벅스 리저브 파일럿](backend/place-detail/starbucks-detail-pilot.md) | 파일럿 데이터·출처 |
| [블루보틀 여의도](backend/place-detail/bluebottle-yeouido-detail.md) | 두 번째 매장 조사 |
| [더현대 시그니처 공간](backend/place-detail/thehyundai-landmarks-detail.md) | 공간 단위 커버리지 |
| [다음 작업 순서](backend/place-detail/next-steps.md) | 후속 항목과 참고 화면 |

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
| [GPS 스트림 정책](client/gps-stream-policy.md) | 스트림 수명·신선도·경로 재계산 주기 |
| [안드로이드 heading 드리프트](client/android-heading-drift.md) | gyro hold가 영구 래치가 되던 구조와 그 수정 |
| [에스컬레이터 층 판정 임계값](client/escalator-thresholds.md) | 상수마다의 실측 근거와 실측에서 나온 함정 |
| [현장 검증 체크리스트](client/field-verification-thehyundai.md) | 더현대 서울에서만 확인되는 항목과 기록 방법 |
| [클라이언트 구조 개편 계획](client/structure-plan.md) | `lib/` 전체 — 디렉터리 성격, 쪼갤 함수, 테스트 규칙 |
| [야외 지도 화면 해체 계획](client/outdoor-map-decomposition.md) | 장기 브랜치의 목표·순서·rebase 규칙 |
| [이동 대장](client/outdoor-map-moves.md) | 옛 심볼 → 새 위치 (rebase 충돌 해결용) |

## 리팩터 과제

[개요와 순서는 refactor/README.md](backend/refactor/README.md)에 있다.

| 문서 | 내용 |
|---|---|
| [01 백엔드 테스트 게이트](backend/refactor/01-backend-test-gate.md) | CI 게이트 |
| [02 수직 전이 계약](backend/refactor/02-vertical-transfer-contract.md) | 층간 이동 계약 정리 |
| [03 그래프 무결성 제약](backend/refactor/03-graph-integrity-constraints.md) | 시드 단계 검증 |
| [04 수직 간선 생성 결정성](backend/refactor/04-vertical-edge-generation-determinism.md) | 재현 가능한 간선 생성 |
| [05 매장 입구 스냅 한계](backend/refactor/05-store-entrance-snap-limit.md) | 스냅 거리 초과 처리 |
| [06 타일 캐시 상한](backend/refactor/06-tile-cache-bounded.md) | 메모리 상한 |
| [07 운영 — Docker·시드 정리](backend/refactor/07-ops-docker-seed-cleanup.md) | 배포 이미지·시드 절차 |
| [08 의존성·모델 공급망](backend/refactor/08-dependency-model-supply-chain.md) | 모델 파일 공급 경로 |
| [09 부하와 스케일링](backend/refactor/09-load-and-scaling.md) | 부하 특성 |

## PDR (실내 측위)

| 문서 | 내용 |
|---|---|
| [마이그레이션 계획](pdr/pdr-migration-plan.md) | PDR 도입 단계 |
| [개발 통합](pdr/pdr-dev-integration.md) | 앱에 붙이는 방법 |
| [노드 체크포인트 개선 계획](pdr/pdr-node-checkpoint-improvement-plan.md) | 보정 지점 설계 |
| [경로·층 전환 개선 계획](pdr/pdr-route-and-floor-transition-improvement-plan.md) | 층 전환 시 측위 |
