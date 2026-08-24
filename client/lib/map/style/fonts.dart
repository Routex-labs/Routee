/// MapLibre 심볼 레이어가 요청하는 fontstack 이름.
///
/// **`resources/fonts/` 아래 디렉터리 이름과 정확히 같아야 한다.** 어긋나면
/// glyph를 못 찾아 심볼 레이아웃이 끝나지 않고, 같은 타일의 fill까지 안 그려진다.
/// 앱 UI 글꼴(`AppTheme.light`)과 같은 가족으로 맞춘다.
library;

const mapFontStackRegular = 'Pretendard Regular';
