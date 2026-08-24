# Navigation

> 실외에서 실내까지 이어지는 경로 안내를 위한 Flutter 클라이언트 데모입니다.

**백엔드는 이 저장소에 없습니다.** Spring Boot로 이식돼 [Routex-labs/backend](https://github.com/Routex-labs/backend)에 있고, 앱이 붙는 Cloud Run 서비스가 그것을 서빙합니다. 걷어낸 FastAPI 백엔드와 **원본 도면 데이터·시드/변환 파이프라인**은 [Routex-labs/fastapi](https://github.com/Routex-labs/fastapi)에 히스토리째 남아 있습니다.

처음 실행한다면 [로컬 개발 가이드](docs/guide/local-development-guide.md)부터 보세요. Windows, macOS, Android 에뮬레이터/실기기, iOS 시뮬레이터/실기기 실행 방법을 분리해서 정리해 두었습니다.

## 구성

```text
client/  Flutter 앱 (Android · iOS · macOS)
docs/    실행, 구조, 조사 문서
```

```text
Flutter 앱 ──HTTP──> Spring Boot ──> PostgreSQL   (별도 저장소: Routex-labs/backend)
                    │
                    └── 실내 지도 · 매장 · 그래프 API (경로 계산은 클라이언트 온디바이스)
```

## 빠른 시작

상세 실행법은 [로컬 개발 가이드](docs/guide/local-development-guide.md)를 따릅니다. **앱만 실행**할지, **백엔드까지 수정**할지에 따라 두 갈래입니다.

### 앱만 실행 — 배포된 백엔드에 붙기 (로컬 백엔드 불필요)

`main`에 올라간 백엔드는 Cloud Run에 자동 배포돼 있어, 로컬 서버를 띄우지 않고 앱만 실행할 수 있습니다. 실행 값(배포 URL·외부 API 키)은 git에 올리지 않는 `client/config.local.json` 하나에 모아 주입합니다.

```powershell
Set-Location client
[Console]::OutputEncoding = [Text.Encoding]::UTF8   # 한글 로그가 CP949로 깨지지 않게 UTF-8 고정
$OutputEncoding = [Text.Encoding]::UTF8
Copy-Item config.example.json config.local.json   # 최초 1회
# config.local.json의 API_BASE_URL에 배포 서비스 주소(→ docs/guide/gcp-instance.md),
# 나머지 항목에 외부 API 키를 채운다. 항목별 발급처는
# docs/guide/local-development-guide.md#api-키-주입 참고. 키는 비워도 앱은 뜬다.
flutter pub get
flutter run --dart-define-from-file=config.local.json
```

`config.local.json`은 `.gitignore`로 커밋되지 않으며, 형식은 커밋된 `client/config.example.json`을 따릅니다. 키를 비우면 각각 목업 경로 / OSM 배경지도로 자동 대체됩니다. 실기기·iOS·macOS 실행과 네트워크·HTTP 주의사항은 [로컬 개발 가이드](docs/guide/local-development-guide.md)를 따르세요.

### 백엔드까지 수정 — 로컬 Spring

백엔드는 [Routex-labs/backend](https://github.com/Routex-labs/backend)에 있습니다. 그 저장소에서
`./gradlew bootRun`(또는 IntelliJ Run)으로 띄우면 되고, 별도 WAS는 필요 없습니다 — 톰캣이 jar 안에
들어 있습니다. `config.local.json`의 `API_BASE_URL`을 로컬 주소로 두거나, 안드로이드 에뮬레이터는
비워 두면 기본값(`http://10.0.2.2:8001`)을 씁니다.

## 주요 API

| 용도 | 경로 |
|---|---|
| 상태 확인 | `GET /health` |
| 건물 목록 | `GET /buildings` |
| 층 지도 | `GET /buildings/{building_id}/floors/{floor_name}` (매장·POI·`navigation_graph` 포함) |
| 층 그래프 | `GET /buildings/{building_id}/floors/{floor_name}/graph` (한 층 내부 간선) |
| 건물 전체 그래프 | `GET /buildings/{building_id}/graph?vertical=auto\|elevator\|escalator` (전 층 + 수직 전이 간선, 층 간 경로용) |
| 목적지 경량 검색 | `POST /query/destination` |
| 위치·층 정보 검색 | `POST /query/info` |
| 탐색 질의(되묻기·패싯) | `POST /query/ai` |

최단 경로는 서버가 계산하지 않습니다. 클라이언트가 그래프(nodes·edges)로 온디바이스 Dijkstra(`client/lib/domain/dijkstra.dart`)를 실행합니다. **한 층 안 경로는 층 지도 응답의 `navigation_graph`**로, **층 간 경로는 건물 전체 그래프**(`/{id}/graph`, 수직 전이 간선 포함)로 계산합니다.

현재 앱의 기본 데모 건물은 `thehyundai-seoul`이며 Studio B6~6F 12개 층 데이터를 적재합니다. API 전체 계약은 백엔드 저장소의 `docs/api/contract.md`가 단일 출처입니다.

## 문서

**전체 목록은 [문서 색인](docs/README.md)에 있습니다.** 자주 보는 것만 아래에 둡니다.

- [로컬 개발 가이드](docs/guide/local-development-guide.md): 플랫폼별 실행, API 주소, 문제 해결
- [엔드포인트 계약](https://github.com/Routex-labs/backend/blob/main/docs/api/contract.md): 스프링 백엔드가 내는 응답의 단일 출처
- [대화형 매장 탐색·추천 설계](https://github.com/Routex-labs/fastapi/blob/main/docs/native/conversational-discovery.md): 검색 facet 원본, 복수 추천 계약, Flutter 질문·선택 흐름

## 데이터셋 작업

더현대서울 원천 데이터셋 추출·미리보기 작업은 앱 실행과 별개입니다. 관련 산출물과 스크립트는 [thehyundai_indoor_navigation_dataset/README.md](thehyundai_indoor_navigation_dataset/README.md)를 참고하세요.

## 개발 규칙

- API 계약은 Flutter 클라이언트가 소비하는 JSON 형태를 우선으로 유지합니다.
- 개발 DB 초기화와 시드는 서버 시작 시가 아니라 `python -m scripts.seed.reset_and_seed`로 실행합니다.
- 일상 개발·기능 검증은 로컬 Python을 사용하고, Docker는 배포 환경 호환성 확인에만 사용합니다.
- CI(테스트·린트)는 `.github/workflows/`에서, CD(Cloud Run 배포)는 `main` push에 반응하는 GCP Cloud Build 트리거에서 관리합니다.
