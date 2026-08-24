# GCP 배포 (Cloud Run)

> **서비스 설정의 단일 출처는 이 문서가 아니다.** 배포 절차·환경변수·되돌릴 이미지 태그는
> 백엔드 저장소의 [`docs/migration/배포.md`](https://github.com/Routex-labs/backend/blob/main/docs/migration/%EB%B0%B0%ED%8F%AC.md)에 있다.
> 여기에는 **클라이언트가 알아야 할 것**만 남긴다.

## 지금 무엇이 떠 있나

**`navigation-api`는 Spring Boot를 서빙한다.** 2026-08-21 컷오버로 이미지가 FastAPI에서
스프링으로 바뀌었고, `main` push마다 백엔드 저장소의 `cloudbuild.yaml`이 재배포한다.

| 항목 | 값 |
|---|---|
| 서비스 | `navigation-api` (프로젝트 `navigation-demo-2026`, `asia-northeast3`) |
| DB | Supabase PostgreSQL (Seoul) — 예전의 휘발성 SQLite가 아니다 |
| 인증 | 없음(`--allow-unauthenticated`, 데모 공개) |

`NAV_SEED_ON_START`·`NAV_WARM_EMBEDDING` 같은 예전 환경변수는 스프링이 읽지 않는다.
DB가 영속이라 기동 시 시드라는 개념 자체가 없다.

## 주소를 바꾸면 안 된다

**딥링크 호스트가 클라이언트 매니페스트에 박혀 있다** —
`client/android/app/src/main/AndroidManifest.xml`의 `android:host`. 주소가 바뀌면 이미 설치된
앱의 공유 링크가 통째로 깨지고, 그 서버가 내는 `/.well-known/assetlinks.json` 검증도 함께
끊긴다. 컷오버를 새 서비스가 아니라 **같은 서비스의 이미지 교체**로 한 이유가 이것이다.

바꿔야만 한다면 세 곳이 함께 움직여야 한다: `client/config.local.json`,
위 `AndroidManifest.xml`, 그리고 Cloud Run 서비스 이름.

## 상태 확인

```powershell
$svc = "https://navigation-api-465890645804.asia-northeast3.run.app"
Invoke-RestMethod "$svc/health/ready"   # status/database/embedding_model
Invoke-RestMethod "$svc/buildings"      # 12개 층이 보이면 실데이터가 붙어 있다
```

`embedding_model`은 항상 `"unknown"`이다 — 스프링은 임베딩 모델을 담지 않는다. 준비 여부를
막지 않으므로 정상이다.

## Flutter 클라이언트 연결

배포 URL과 외부 API 키를 매번 치지 않도록, git에 올리지 않는 `client/config.local.json`에 모아
한 번에 주입한다(항목 목록은 `client/config.example.json`, 항목별 발급처는
[로컬 개발 가이드](local-development-guide.md#api-키-주입)).

```powershell
Set-Location client
[Console]::OutputEncoding = [Text.Encoding]::UTF8   # 한글 로그가 CP949로 깨지지 않게 UTF-8 고정
$OutputEncoding = [Text.Encoding]::UTF8
# config.example.json을 config.local.json으로 복사한 뒤 API_BASE_URL에 위 서비스 URL,
# 나머지 항목에 외부 API 키를 채운다.
flutter run --dart-define-from-file=config.local.json
```

`API_BASE_URL`을 배포 URL로 채우면 로컬 백엔드를 띄우지 않아도 된다. 키를 비워 두면 각각 목업 경로 /
OSM 배경지도로 자동 대체된다. (단건으로 넘기려면 `--dart-define=API_BASE_URL=<서비스 URL>`도 여전히 동작.)

## 비용 관리

`--min-instances 0`이라 유휴 시 과금이 없다(첫 요청만 콜드 스타트로 몇 초 느리다). 최대
인스턴스는 5로 잡혀 있는데, 이건 비용이 아니라 **Supabase Session pooler의 클라이언트 15개
상한** 때문이다(인스턴스 5 x 풀 2 = 10, 배포 중에는 구·신 revision이 겹쳐 두 배가 된다).
근거는 백엔드 저장소의 배포 문서 「연결 수」 절.

```powershell
gcloud run services delete navigation-api --region asia-northeast3   # 서비스 완전 삭제
```

## gcloud CLI 참고

- 설치 위치: `C:\Users\HANSUNG\AppData\Local\Google\Cloud SDK`
- 결제 계정 연결: `gcloud billing projects link navigation-demo-2026 --billing-account=<ACCOUNT_ID>`
- 필요한 API: `run.googleapis.com`, `cloudbuild.googleapis.com`, `artifactregistry.googleapis.com`
