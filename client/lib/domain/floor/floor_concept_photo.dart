/// 층 라벨 하나가 가리키는 **그 층의 사진들**.
///
/// 첫 장은 층별 안내(`/store/floor-guide`)의 키비주얼이다 — 컨셉 이름
/// (`TASTY SEOUL`)과 업종 줄이 사진 안에 인쇄되어 있어 **글자를 따로 들고 있지
/// 않는다**. 뒤따르는 것은 그 층의 공간 사진이고, 수집 경로·규격·robots 판단은
/// `docs/client/thehyundai-floor-guide.md`가 단일 출처다.
library;

/// 층 라벨(`B1`·`1F`)에 붙는 사진들. 없는 층이면 빈 목록.
///
/// **판매층 여덟에만 있다.** 주차층(B3~B6)은 원본이 주지 않는다. 그때는 빈
/// 목록을 돌려주고, 덮개는 사진 없이 층 라벨·점만 그린다 — 빈 액자를 그리면
/// "사진을 못 불러왔다"로 읽힌다.
List<String> floorConceptPhotos(String floorLabel) =>
    _photosByFloor[_normalize(floorLabel)] ?? const [];

/// 라벨 표기가 갈리는 것을 한 자리에서 흡수한다. `B2F`·`b2`·`2`·`2F`가 모두 같은
/// 층을 가리킨다 — 층 이름은 도면·검색·판정기가 각자 만들어 온다.
String _normalize(String label) =>
    label.trim().toUpperCase().replaceAll('F', '');

/// 파일 이름은 층 라벨을 따르고, 두 번째부터 `-2`가 붙는다. 표를 손으로 적어 두는
/// 이유는, 경로를 조립하면 없는 층·없는 장수도 그럴듯한 경로가 만들어져 실행
/// 중에야 깨지기 때문이다.
///
/// **장수가 층마다 다르고, 그대로 둔다.** 원본이 층에 묶어 주는 사진이 그만큼뿐
/// 이다. 포토스팟 사진 대부분은 보이드를 가로질러 여러 층이 한 장에 담긴 **건물**
/// 사진이라, 특정 층의 얼굴로 쓰면 거짓말이 된다. 채운 것은 5F(사운즈 포레스트)와
/// 6F(ALT.1 공간)처럼 그 층에 있는 장소가 주인공인 사진뿐이다.
///
/// **원본의 이름표를 믿지 말고 눈으로 봐야 한다.** 포토스팟 세 장이 `사운즈포레스트
/// 1·2·3`으로 이름 붙어 있었는데, 둘은 실제로 워터폴 가든을 위에서 내려다본
/// 사진이었다(4층 침구 매장과 1층 매장 간판이 함께 담긴다). 라벨만 보고 넣었다가
/// 걷어냈다(2026-08-22).
const _photosByFloor = <String, List<String>>{
  'B2': ['assets/floors/b2.webp'],
  'B1': ['assets/floors/b1.webp'],
  '1': ['assets/floors/1f.webp'],
  '2': ['assets/floors/2f.webp'],
  '3': ['assets/floors/3f.webp'],
  '4': ['assets/floors/4f.webp'],
  '5': ['assets/floors/5f.webp', 'assets/floors/5f-2.webp'],
  '6': [
    'assets/floors/6f.webp',
    'assets/floors/6f-2.webp',
    'assets/floors/6f-3.webp',
    'assets/floors/6f-4.webp',
    'assets/floors/6f-5.webp',
  ],
};
