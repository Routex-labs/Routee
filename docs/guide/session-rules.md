# 프로젝트 세션 규칙

앱을 띄우고 고칠 때 지키는 것들. 작업 규칙 전반은 저장소 루트 [AGENTS.md](../../AGENTS.md).

Flutter 클라이언트 데모다. 백엔드는 이 저장소에 없다 — Spring Boot이고 Routex-labs/backend에 있다. 개발자는 Windows(PowerShell)와
macOS 양쪽에 있다.

## 백엔드는 배포된 Cloud Run에 붙고, 로컬에선 클라이언트만 띄운다

백엔드를 직접 고치지 않는 한 로컬 서버는 실행하지 않는다.

최초 1회 `client/config.example.json`을 `config.local.json`으로 복사하고 배포 백엔드 주소
(`API_BASE_URL`)·키를 채운다. `.gitignore`라 커밋되지 않으므로 워크스페이스마다 복사해야 한다.

`client/`에서 실행한다. 창은 foreground로 띄우고, 명령은 체이닝하지 말고 한 줄씩 실행한다
(쉘 버전에 따라 `&&`·`;`가 깨질 수 있음).

```powershell
# Windows — 이 두 줄이 없으면 한글 로그가 CP949로 디코딩돼 중국어처럼 깨진다.
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8
flutter run --dart-define-from-file=config.local.json 2>&1 | ForEach-Object { $_; $_ | Out-File frontend.log -Append -Encoding utf8 }
```

```bash
# macOS — 터미널이 기본 UTF-8이라 프렐류드 불필요
flutter run --dart-define-from-file=config.local.json 2>&1 | tee frontend.log
```

사용자는 창에서 실시간 로그를, 에이전트는 `frontend.log`(`.gitignore`)를 읽어 추적한다.
주입 값은 **컴파일 타임에 박히므로** URL·키를 바꾸면 hot reload가 아니라 `flutter run`을
재시작한다.

백엔드를 직접 고쳐야 할 때만 [Routex-labs/backend](https://github.com/Routex-labs/backend)를
받아 `./gradlew bootRun`으로 띄운다(별도 WAS 불필요, 포트 8080) —
[로컬 개발 가이드](local-development-guide.md), [GCP 배포 문서](gcp-instance.md).

## 경계

- **경로 계산은 클라이언트 온디바이스**(Dijkstra, `client/lib/domain/route/`)가 담당한다.
  서버는 그래프(nodes·edges)만 준다. 최단 경로 로직을 서버로 옮기지 않는다.
- **API 계약(JSON)은 Flutter 클라이언트가 소비하는 형태를 우선**한다. 백엔드 응답 스키마를
  바꾸면 클라이언트의 모델·파싱도 함께 확인한다. 계약의 단일 출처는 백엔드 저장소의
  `docs/api/contract.md`이고, 키 표기는 snake_case다(스프링이 `SNAKE_CASE` 전략으로 변환한다).
- **문서·주석·커밋·PR은 한국어로 쓴다.** 코드·식별자는 영어다.
