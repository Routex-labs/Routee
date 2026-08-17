/// 실행 설정. 값은 전부 `--dart-define`으로 주입한다.
///
/// 키 발급 절차·무료 쿼터·안 켜면 401 나는 설정 같은 운영 사정은
/// `docs/guide/local-development-guide.md`가 단일 출처다.
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

const _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');

/// 백엔드 주소. dart-define이 최우선이고, 없으면 플랫폼별 기본값이다 —
/// 안드로이드 에뮬레이터는 호스트 localhost를 `10.0.2.2`로 가리켜야 붙는다.
String get apiBaseUrl {
  if (_apiBaseUrlOverride.isNotEmpty) return _apiBaseUrlOverride;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8001';
  }
  return 'http://localhost:8001';
}

/// Studio 1F만 적재하는 기본 개발 DB와 맞춘 데모 건물 ID.
const demoBuildingId = 'thehyundai-seoul';

/// 검색·경로 HTTP 한 건이 응답을 기다리는 상한.
///
/// **timeout이 없으면 화면이 영원히 「찾는 중」에 머무를 수 있다.** 소켓이 끊기지
/// 않고 멎으면 `http` 패키지는 스스로 포기하지 않는다 — 응답도 오류도 오지
/// 않으니 `await`가 영영 안 풀리고, 그 뒤에 있는 스피너도 안 내려간다. 실제로
/// 길찾기 칸의 후보 목록이 그렇게 멈춘 적이 있다.
///
/// 8초는 "느린 셀룰러에서 한 번은 성공할 만큼 길고, 사용자가 고장으로 읽기
/// 전에는 끝나는" 자리다. 넘기면 실패로 다루므로 화면은 결론을 얻는다.
const searchRequestTimeout = Duration(seconds: 8);

/// TMAP 보행자 경로·POI 통합검색. 비면 `MockDirectionsRepository`로 떨어진다.
const tmapAppKey = String.fromEnvironment('TMAP_APP_KEY');
const tmapBaseUrl = 'https://apis.openapi.sk.com/tmap';

/// 대중교통만 base path가 `/transit`이다(`/tmap/routes/transit`은 404).
///
/// **지금은 쓰지 않는다** — 무료 제공량이 하루 10건이라 카카오로 옮겼다.
/// `TmapTransitRepository`는 되돌릴 여지로 남겨 둔다.
const tmapTransitBaseUrl = 'https://apis.openapi.sk.com/transit';

/// 카카오맵 대중교통. **REST API 키**다(JavaScript 키가 아니다). 비면 기능이
/// 꺼진 `UnavailableTransitRepository`를 쓴다.
const kakaoRestApiKey = String.fromEnvironment('KAKAO_REST_KEY');
const kakaoTransitBaseUrl = 'https://dapi.kakao.com/v2/routing';

/// VWorld 배경지도 타일. 비면 OSM 타일로 대체한다.
const vworldApiKey = String.fromEnvironment('VWORLD_API_KEY');
