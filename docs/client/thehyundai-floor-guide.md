# 더현대 서울 층 키비주얼 — 원본과 수집 (2026-08-22)

층 전환 연출이 "지금 가는 층"을 사진 한 장으로 보여 주려면 **층당 대표 이미지 한
장**이 필요하다. 어디서 무엇을 받았고 왜 그 경로였는지를 남긴다. 행사 사진의 단일
출처는 [행사 원본 조사](thehyundai-event-source.md)이고, 이 문서는 층 이미지만 다룬다.

## 원본은 층별 안내 페이지 하나다

`thehyundaiseoul.ehyundai.com/store/floor-guide`. 층 탭 8개짜리 페이지이고, 값은
본문이 아니라 Next.js RSC 페이로드의 `floors` 배열에 들어 있다.

```json
{"code":"B1","floorCode":"B010B100","name":"Tasty Seoul",
 "imageSrc":"/images/floor-guide/floor_b1.png","imageAlt":"B1 - Tasty Seoul"}
```

**층 이름을 따로 받을 필요가 없다.** 컨셉 이름(`Tasty Seoul`)과 업종 구성
(`현대식품관 · 푸드 스트리트`)이 이미지 안에 인쇄되어 있다.

한때 `/iconic/sounds-forest`를 원본으로 봤는데, 그쪽은 **5층 하나만** 다루는 별도
마이크로사이트다(이야기 5개 + 식물 상세 46쪽). 여덟 층을 같은 규격으로 주는 곳은
`floor-guide`뿐이다.

| 층 | 컨셉 | 원본 호스트 |
|---|---|---|
| 6F | Dining & Art | www.ehyundai.com |
| 5F | Sounds Forest | www.ehyundai.com |
| 4F | Life & Balance | thehyundaiseoul |
| 3F | About Fashion | thehyundaiseoul |
| 2F | Modern Mood | thehyundaiseoul |
| 1F | Exclusive Label | www.ehyundai.com |
| B1 | Tasty Seoul | thehyundaiseoul |
| B2 | Creative Ground | thehyundaiseoul |

## 호스트가 둘로 갈리고 robots도 갈린다

- `thehyundaiseoul.ehyundai.com` — `Allow: /`, 막는 것은 `/api/`·`/styleguide`뿐.
- `www.ehyundai.com` — `User-agent: *`에 `/images/`·`/upload/`·`*.png`·`*.jpg`가
  전부 `Disallow`. **1F·5F·6F 원본이 여기 있다.**

그래서 원본 PNG를 직접 긁지 않고, **여덟 장 모두 `thehyundaiseoul`의 이미지 최적화
엔드포인트로 받았다** — `/_next/image?url={인코딩된 원본}&w=1080&q=75`. robots가 여는
경로이고, 층별 안내 페이지가 브라우저에 이미지를 내려 줄 때 쓰는 바로 그 경로다.
덤으로 규격이 통일된다: 응답이 전부 webp이고, 8장 합계가 **445KB**다(원본 PNG는
6MB).

```bash
# 예 — B1(같은 호스트의 상대 경로)
curl "https://thehyundaiseoul.ehyundai.com/_next/image?url=%2Fimages%2Ffloor-guide%2Ffloor_b1.png&w=1080&q=75"
# 예 — 5F(www 원본을 프록시로)
curl "https://thehyundaiseoul.ehyundai.com/_next/image?url=https%3A%2F%2Fwww.ehyundai.com%2Fimages%2Fwebhome2%2Fstore%2Fimg_the_hyundai_seoul_floor_5f.png&w=1080&q=75"
```

받은 것은 `client/assets/floors/{b2,b1,1f,2f,3f,4f,5f,6f}.webp`. 파일 이름을 층
라벨과 같게 두고, 같은 층의 두 번째 사진부터 `-2`를 붙인다(`5f-2.webp`).

## 층별 공간 사진 — 두 곳에서만 나온다

키비주얼 뒤에 이어 붙일 사진을 세 곳에서 재 봤다.

| 원본 | 해상도 | 판정 |
|---|---|---|
| [포토스팟](https://thehyundaiseoul.ehyundai.com/iconic/photo-spot) (Hasisi Park 15장) | 1634×2898 세로 | **1장만 채택** |
| [ALT.1 공간](https://thehyundaiseoul.ehyundai.com/culture/alt1/venue) 4장 | 3000×2000 | **4장 채택**(아래 잘라냄) |
| [벤치마킹 투어](https://thehyundaiseoul.ehyundai.com/iconic/benchmarking-tour) 12장 | 480×320 | **버렸다** |

- **포토스팟 대부분은 층 사진이 아니라 건물 사진이다.** 보이드를 가로질러 찍어
  한 장에 1~6층이 함께 담긴다(`플로어 1·2`, `스카이트리 1~3`, `워터폴`). 그걸
  특정 층의 얼굴로 쓰면 거짓말이 된다. 채택한 것은 `사운즈포레스트 1` 한 장으로,
  5F 펄골라와 온실이 주인공이고 아래층은 배경으로만 걸린다.
- **원본의 `alt` 라벨을 믿으면 안 된다.** `사운즈포레스트 1·2·3` 중 뒤의 둘은
  실제로 **워터폴 가든을 위에서 내려다본 사진**이었다(4층 침구 매장과 1층 매장
  간판이 함께 담긴다). 라벨만 보고 5F에 넣었다가 화면에서 눈에 띄어 걷어냈다
  (2026-08-22). 이름표가 아니라 **사진을 열어 봐야 한다.**
- **ALT.1 사진 넷 중 셋은 홍보 문구가 사진에 인쇄되어 있었다**(`WHY ALT.1 ?` 등).
  정사각 액자에 넣으면 문장이 좌우로 잘려 깨진 화면으로 읽힌다. 원본이 3000×2000
  이라 **문구 위쪽만 잘라 쓴다** — `w=1920`으로 받아 `crop=870:870:525:0`
  (넷째 장만 `x=720`, 벽에 붙은 인용문이 잘려 나가게). 자른 뒤에도 870px라
  화면(1026px)에 1.18배로만 늘어난다.
- **벤치마킹 투어는 해상도가 480×320이 상한이다.** 화면 폭에 맞추면 2.1배로
  늘어나 옆에 선 키비주얼(832px)과 선명도가 눈에 띄게 갈린다.

그래서 장수가 층마다 다르다 — 6F 다섯, 5F 둘, 나머지 하나. 원본이 층에 묶어
주는 사진이 그만큼뿐이고, **모자란 층을 건물 사진으로 채우지 않는다.**

**장수가 덮개 시간도 정한다.** 한 장뿐인 층을 여러 장 기준으로 붙잡으면 볼 것이
없는데 화면만 잡혀 있다. 규칙과 상한은
`client/lib/features/indoor_navigation/contract/floor_transition_ui_state.dart`의
`floorTransitionScrimHold`에 있고, 검증은
`client/test/features/indoor_navigation/escalator_arrival_test.dart`가 한다.

## 화면 설계에 걸리는 값 셋

여덟 장을 눈으로 다 확인하고 잰 값이다.

- **정사각이다.** 832×832가 여섯, 832×833이 둘(1F·5F), 832×817이 하나(6F).
  세로 화면을 `cover`로 채우면 가운데 46%만 남아 아래 워드마크가 잘린다
  (`TAST…SEO`). 포스터에서 이미 정한 규칙과 같이 **폭만 맞추고 세로는 채우지
  않는다**([행사 원본 조사](thehyundai-event-source.md)의 "사진 — 750이 상한이다").
  높이가 층마다 1~2% 다른데, 덮개는 **정사각 액자로 고정하고 남는 쪽을 덮는다**
  — 잘리는 폭이 한 변에 1% 미만이라 층마다 액자 높이가 흔들리는 것보다 낫다.
- **아래 워드마크 자리는 투명하다.** 여덟 장 모두 알파 채널이 있고(webp `VP8X
  alpha`, 원본 PNG `colortype 6`), 컨셉 글자가 놓인 아래 3분의 1이 비어 있다.
  뷰어마다 검정으로도 흰색으로도 보이는 것은 합성 배경 차이일 뿐이다. **앱에서는
  글자가 앱 배경 위에 그대로 얹혀** 사진과 화면이 이어진 것처럼 보인다 — 이음매를
  걱정할 필요가 없는 대신, 글자가 어두워서 **어두운 배경 위에서는 사라진다**.
- **왼쪽 위 업종 태그는 덤으로 친다.** 832폭을 390pt 화면에 맞추면 0.47배로 줄어
  글자가 아주 작아진다. 읽히면 좋고, 읽히는 것을 전제로 설계하지는 않는다.
- **액자는 정사각 하나로 고정하고 사진만 갈아 끼운다.** 원본 비율이 섞여 있다
  (키비주얼 1:1 · 포토스팟 9:16 · ALT.1 1:1로 잘라 맞춤). 사진마다 액자 높이가
  달라지면 그 아래 층 라벨과 점이 매번 밀려, 넘어가는 것이 사진인지 화면인지
  알 수 없다.

## 스냅샷이다

**자동 갱신이 없다.** 2026-08-22에 받은 값이고, 층 개편이 있으면 원본과 어긋난다.
같은 URL로 다시 받아 덮어쓰면 된다. 저작권은 행사 사진 66장과 같은 취급이다 —
현대백화점 제작물이고, 출처와 수집일을 여기 남긴 채 데모 범위로 쓴다.
