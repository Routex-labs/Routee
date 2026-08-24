/// 시작 로고가 읽히기도 전에 다른 화면이 덮지 않게 하는 최소 노출 시간.
const startupLoadingMinimum = Duration(milliseconds: 1200);

/// 위치 서비스가 응답하지 않을 때도 앱을 쓸 수 있게 여는 마지막 출구.
const startupLoadingFailureTimeout = Duration(seconds: 10);

/// 준비된 지도나 층 선택 화면으로 넘어갈 때 시작 덮개가 빠지는 시간.
const startupLoadingFadeOut = Duration(milliseconds: 700);
