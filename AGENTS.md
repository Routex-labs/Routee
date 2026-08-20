# 작업 규칙

## 판단력 — 새 기능을 만들 때

- **AI 결과를 내 말로 풀어서 설명한다.** 생성된 코드/설계를 그대로 받아들이지 않고, 사용자가 자기 말로 이해하고 설명할 수 있도록 근거와 동작을 풀어 준다.
- **정상 동작보다 실패 조건을 먼저 생각한다.** 어디서 깨지는지, 어떤 입력·상태에서 실패하는지를 먼저 짚는다.
- **AI보다 먼저 검증 기준을 정한다.** "무엇이 충족되면 맞다고 볼지"를 먼저 합의하고 그 기준으로 결과를 확인한다.

이 셋이 가장 값을 한다. 실패 조건을 먼저 적어 잡은 것들: 요금이 null인 경로, 0으로 나누는
소요시간, 좌표가 빈 후보, 필터로 좁힌 뒤의 인덱스 어긋남. 리팩터링에서는 검증 기준을
**"테스트를 한 개도 안 고쳐야 한다"**로 잡아, 옮기기에 수정이 섞이는 것을 막았다.

## 계층 — import는 아래로만 간다

```
5  app.dart · main.dart · service_locator.dart
4  screens/
3  widgets/
2  repositories/  features/  map/
1  domain/  state/
0  models/  core/  theme/  routing/
```

`client/test/lib_layer_direction_test.dart`가 검사한다. 예외는 조립 루트
(`service_locator.dart`) 하나뿐이다.

- **거슬러 올라가고 싶어지면 대개 값이 잘못된 층에 있는 것이다.** 타입·상수를 아래로
  내리거나, 큰 객체 대신 실제로 읽는 값만 인자로 받는다.
- 새 디렉터리를 만들면 등급표에 추가한다. 등급표를 고치는 것은 마지막 수단이고, 고칠 때는
  **왜 그 순서인지** 함께 적는다.

폴더를 가르는 기준은 파일 수가 아니라 **고치는 이유**다. 경로를 만드는 코드
(`domain/route/`)와 따라가는 코드(`domain/guidance/`)를 나눈 것이 그 예다.

## 같은 사실은 한 곳에

같은 사실을 코드와 문서 양쪽에 적으면 반드시 한쪽이 먼저 썩는다. **한쪽을 단일 출처로
정하고 나머지는 경로로 가리킨다.** 검증 기준의 단일 출처는 테스트다 — 주석에 표를
베끼지 말고 테스트 파일 경로를 적는다.

금지가 아니라 선택의 문제다. 실측 로그·벤치 숫자처럼 **남길 값이 있는 것은 반드시 어딘가에
남긴다.** 코드에 둘지 `docs/`에 둘지만 정하면 된다.

## 커밋·PR에서 하나만

**`Co-Authored-By` 및 협업자 Claude 태그는 붙이지 않는다**(커밋·PR 모두).

나머지 커밋·PR 규칙은 [.github/CONTRIBUTING.md](.github/CONTRIBUTING.md).

## 나머지는 어디에 있나

| 무엇 | 어디 |
|---|---|
| 앱 띄우기·UTF-8 창·백엔드 경계 | [docs/guide/session-rules.md](docs/guide/session-rules.md) |
| 주석을 어디에 쓰나 (상한 8줄·20줄) | [docs/client/comment-placement.md](docs/client/comment-placement.md) |
| 커밋 메시지·PR 5섹션·뒷정리 | [.github/CONTRIBUTING.md](.github/CONTRIBUTING.md) |
| 로컬 백엔드·배포 | [docs/guide/local-development-guide.md](docs/guide/local-development-guide.md) · [docs/guide/gcp-instance.md](docs/guide/gcp-instance.md) |
