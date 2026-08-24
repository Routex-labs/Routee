# 로컬 개발 가이드

필요한 항목만 바로 확인하세요.

- [백엔드 실행](#백엔드-실행)
- [Flutter 실행](#flutter-실행)
- [실행 대상별 API 주소](#실행-대상별-api-주소)
- [API 키 주입](#api-키-주입)
- [문제 해결](#문제-해결)

## 백엔드 실행

**백엔드는 이 저장소에 없다.** 일상 개발에서는 아예 띄우지 않는다 — 배포된 Cloud Run
(`https://navigation-api-...run.app`)에 붙는다. 그 주소를 `config.local.json`의
`API_BASE_URL`에 넣으면 끝이고, 아래 [Flutter 실행](#flutter-실행)으로 바로 간다.

서버를 고쳐야 할 때만 [Routex-labs/backend](https://github.com/Routex-labs/backend)를 받는다.

```bash
git clone https://github.com/Routex-labs/backend.git
cd backend
./gradlew bootRun          # IntelliJ의 Run 버튼도 같은 것이다
```

**별도 WAS는 필요 없다** — 톰캣이 jar 안에 들어 있다. PostgreSQL도 따로 안 띄워도 된다:
Docker Desktop만 켜져 있으면 `spring-boot-docker-compose`가 컨테이너를 올리고 접속 정보를
주입한다. 남의 DB(Supabase 등)에 붙으려면 그 저장소의 `.env.example`을 `.env`로 복사한다.

```bash
curl localhost:8080/health
curl localhost:8080/buildings
```

> **포트가 8080이다.** 클라이언트 기본값은 아직 8001(`api_config.dart`)이라, 로컬 백엔드에
> 붙일 때는 `API_BASE_URL`을 `http://localhost:8080`으로 명시하거나 스프링 쪽
> `application.yml`에 `server.port: ${PORT:8001}`을 둔다. 컨테이너는 진입점이 `--server.port`를
> 명령행으로 넘기므로 그 한 줄에 영향받지 않는다.

원본 도면 데이터와 시드·변환 파이프라인이 필요하면(지름길 상수 재생성 등)
[Routex-labs/fastapi](https://github.com/Routex-labs/fastapi)에 있다.

## Flutter 실행

`client/`에서 실행한다. 실행 값(배포 URL·API 키)은 [API 키 주입](#api-키-주입)의 `config.local.json`으로 넣는다.

```powershell
Set-Location client
# 콘솔 인코딩을 UTF-8로 고정한다. 안 하면 flutter의 한글 출력이 기본 코드페이지(CP949)로 디코딩돼 로그가 중국어처럼 깨진다.
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8
flutter pub get
# 콘솔엔 전부, frontend.log엔 UTF-8로 남긴다(PS 5.1 Tee-Object는 파일을 UTF-16으로 쓰므로 패스스루로 tee).
flutter run --dart-define-from-file=config.local.json 2>&1 | ForEach-Object { $_; $_ | Out-File frontend.log -Append -Encoding utf8 }
```

macOS 터미널은 기본 UTF-8이라 프렐류드가 필요 없다.

```bash
cd client
flutter pub get
flutter run --dart-define-from-file=config.local.json 2>&1 | tee frontend.log
```

특정 기기를 지정하려면 다음을 사용한다.

```powershell
flutter devices
flutter run -d <device-id> --dart-define-from-file=config.local.json
```

## 실행 대상별 API 주소

**평소에는 배포된 Cloud Run 주소 하나만 쓴다.** `config.local.json`의 `API_BASE_URL`에 넣으면
에뮬레이터·실기기·데스크톱이 전부 같은 값을 본다(주소는 [GCP 배포](gcp-instance.md)).

아래 표는 **로컬 스프링에 붙일 때만** 필요하다. 스프링 기본 포트는 8080이다.

| 실행 대상 | `API_BASE_URL` |
|---|---|
| Android 에뮬레이터 | `http://10.0.2.2:8080` (호스트의 localhost를 10.0.2.2로 가리켜야 붙는다) |
| Android 실기기 | `http://<개발-PC-LAN-IP>:8080` |
| iOS 시뮬레이터 / macOS 앱 | `http://127.0.0.1:8080` |
| iPhone 실기기 | `http://<Mac-LAN-IP>:8080` |

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.0.10:8080
```

`api_config.dart`의 폴백은 아직 8001이라(FastAPI 시절 값), 로컬 스프링에 붙을 때는 **비워 두지
말고 명시한다.** 실기기는 개발 PC와 같은 Wi-Fi에 두고, 안 붙으면 PC 방화벽에서 TCP 8080의
개인 네트워크 수신을 허용한다. 외부 공개 환경에서는 HTTP 대신 HTTPS를 쓴다.

## API 키 주입

키·URL은 소스에 넣지 않고 실행 시 주입한다. 매번 길게 치지 않도록 git에 올리지 않는
`client/config.local.json` 하나에 모아 `--dart-define-from-file`로 넣는 방식을 권장한다.

```powershell
Set-Location client
# 최초 1회: 템플릿 복사 후 값 채우기 (config.local.json은 .gitignore로 커밋되지 않는다)
Copy-Item config.example.json config.local.json
# config.local.json의 항목을 채운 뒤(항목 목록은 아래 표):
flutter run --dart-define-from-file=config.local.json
```

**항목 목록의 단일 출처는 [`client/config.example.json`](../../client/config.example.json)이다.** 여기서는
각 항목을 어디서 발급받고 비우면 어떻게 되는지만 적는다.

| 항목 | 발급처 | 쓰는 곳 | 비워 두면 |
|---|---|---|---|
| `API_BASE_URL` | 배포 서비스 URL([GCP 배포](gcp-instance.md)) | 백엔드 전체 | 플랫폼별 로컬 폴백(`localhost:8001`, 안드로이드 에뮬레이터는 `10.0.2.2:8001`) — FastAPI 시절 값이라 로컬 스프링(8080)에는 안 맞는다 |
| `TMAP_APP_KEY` | [openapi.sk.com](https://openapi.sk.com) 앱 등록 | 보행자 경로, POI 통합검색 | 경로는 직선 목업, 건물 밖 장소 검색은 꺼짐 |
| `KAKAO_REST_KEY` | [developers.kakao.com](https://developers.kakao.com) → [앱 키]의 **REST API 키** | 대중교통 경로 | 대중교통 버튼이 사라짐 |
| `VWORLD_API_KEY` | [vworld.kr/dev](https://www.vworld.kr/dev) 도메인 등록 | 배경지도 타일 | OSM 타일로 대체 |

카카오 키는 발급 후 **[제품 설정] > [카카오맵]에서 사용 설정을 켜야** 한다. 안 켜면 키가 맞아도
401이다. 그리고 앱을 "테스트앱"으로 만들면 월 쿼터와 별개로 소량의 일 쿼터가 걸려 금방
`code -10`(API limit has been exceeded)이 난다.

무료 제공량은 대중교통 경로 조회 하루 1,000건인데, **개발자 계정에서 첫 번째로 활성화한
앱에만** 붙는다. 계정에 앱이 여럿이면 어느 앱의 키를 넣었는지 확인한다. TMAP 대중교통을
쓰지 않는 이유도 쿼터다 — 무료 제공량이 하루 10건이라 데모 한 번에 소진됐다.

대중교통은 **카카오 키만으로는 완전하지 않다.** 카카오가 첫 승차지점 앞·마지막 하차지점 뒤
도보를 주지 않아 그 두 구간은 TMAP 보행자 경로로 채우기 때문에, 대중교통 안내를 제대로 보려면
`TMAP_APP_KEY`도 함께 있어야 한다.

키를 하나만 즉석에서 넘길 땐 단건 방식도 그대로 동작한다.

```powershell
Copy-Item client\config.example.json client\config.local.json
```

> **주입 값은 컴파일 타임에 박힌다.** 키·URL을 바꾸면 hot reload로는 안 먹으므로 `flutter run`을 재시작한다.

JSON이라 주석은 쓸 수 없고, 키 이름은 `api_config.dart`의 `String.fromEnvironment` 이름과
정확히 같아야 한다. `API_BASE_URL`을 Cloud Run 주소로 채우면 로컬 백엔드를 띄우지 않고도
붙는다.

## 문제 해결

| 증상 | 먼저 확인할 것 |
|---|---|
| 콘솔·`*.log`의 한글이 중국어처럼 깨짐 | 출력 주체와 콘솔 인코딩 불일치. flutter(항상 UTF-8 출력)는 콘솔을 UTF-8로 고정(`[Console]::OutputEncoding`), python은 여기에 `$env:PYTHONUTF8=1`까지 줘서 양쪽을 UTF-8로 맞춘다. 위 실행 블록의 프렐류드를 빠뜨리지 않았는지 확인한다 |
| 앱에서 API 연결 실패 | Uvicorn 실행 여부, `/health`, 포트 `8001`, `API_BASE_URL` |
| Android 에뮬레이터가 `localhost`를 못 찾음 | `localhost` 대신 기본값 `10.0.2.2` 사용 |
| Android 실기기에서 연결 실패 | 같은 Wi-Fi, PC LAN IP, 방화벽, HTTP cleartext 정책 |
| `ModuleNotFoundError` 또는 명령을 못 찾음 | `.venv` 활성화 여부, `python -m pip install -r requirements.txt` |
