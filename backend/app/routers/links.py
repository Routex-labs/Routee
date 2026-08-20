# 장소 공유 링크 라우터 — 앱을 여는 증명 파일 둘과, 앱이 없는 사람이 볼 페이지.
#
#   GET /.well-known/assetlinks.json              → Android App Links 검증
#   GET /.well-known/apple-app-site-association   → iOS Universal Links 검증
#   GET /place/{building_id}/{place_id}           → 미설치 fallback 페이지
#
# 두 증명 파일은 **OS가 직접 받아 간다.** 앱이 "이 주소는 내 것"이라고 주장하는 것만으로는
# 링크를 가로챌 수 없고, 그 주소가 앱을 인정해야 성립한다. 그래서 이 파일들은 앱을
# 배포하는 쪽이 아니라 도메인을 가진 쪽(여기)이 낸다.
#
# fallback 페이지가 필요한 이유는 같은 URL을 앱 없는 사람도 누르기 때문이다. 404를
# 주면 공유받은 사람 절반이 깨진 링크를 본다.

import html

from fastapi import APIRouter, Response
from fastapi.responses import HTMLResponse, JSONResponse

router = APIRouter(tags=["links"])

# 링크를 열 수 있는 앱. 지문이 하나뿐인 이유는 release가 아직 debug 키로 서명하기
# 때문이다(android/app/build.gradle.kts). 별도 release 키를 만드는 날 그 지문을
# 이 목록에 **더한다** — 갈아 끼우면 이미 깔린 앱이 링크를 잃는다.
_SERVICE_NAME = "Routex"
_ANDROID_PACKAGE = "com.navigation.navigation_client"
_ANDROID_SHA256_FINGERPRINTS = [
    "C3:0C:5F:05:50:BB:95:9E:80:AB:83:AD:01:F7:25:8E:F8:DB:66:79:19:9E:96:01:EA:15:10:31:CB:D7:3F:9F",
]

# iOS는 아직 서명 팀이 없다. 목록이 비면 Universal Links가 동작하지 않을 뿐이고,
# 파일 자체는 유효해야 OS가 조용히 재시도를 포기하지 않는다.
_IOS_APP_IDS: list[str] = []


@router.get("/.well-known/assetlinks.json", include_in_schema=False)
def android_assetlinks() -> Response:
    return JSONResponse(
        [
            {
                "relation": ["delegate_permission/common.handle_all_urls"],
                "target": {
                    "namespace": "android_app",
                    "package_name": _ANDROID_PACKAGE,
                    "sha256_cert_fingerprints": _ANDROID_SHA256_FINGERPRINTS,
                },
            }
        ]
    )


@router.get("/.well-known/apple-app-site-association", include_in_schema=False)
def apple_app_site_association() -> Response:
    # 확장자가 없고 Content-Type이 application/json이어야 iOS가 읽는다.
    return JSONResponse(
        {"applinks": {"details": [{"appIDs": _IOS_APP_IDS, "components": [{"/": "/place/*"}]}]}},
        media_type="application/json",
    )


@router.get("/place/{building_id}/{place_id}", include_in_schema=False)
def place_fallback(building_id: str, place_id: str) -> Response:
    # **여기서 매장을 조회하지 않는다.** 이 페이지는 앱이 없는 사람에게 "무엇을 받았는지"만
    # 알리는 자리이고, 이름·층은 앱이 서버에서 다시 구한다(링크에 표시 이름을 넣지
    # 않는다는 규칙과 같은 이유 — 링크의 글자를 신뢰 가능한 값으로 쓰지 않는다).
    # 조회를 붙이면 삭제된 매장에서 이 페이지가 500을 내며 공유 링크가 통째로 죽는다.
    #
    # **두 값은 반드시 이스케이프한다.** 경로 파라미터는 서버가 percent-decode한 뒤
    # 넘겨주므로 `%3Cimg src=x onerror=...%3E`가 살아 있는 마크업으로 들어온다. 이 주소는
    # 사람들이 메신저에 붙여 넣는 공개 페이지이고, 같은 출처가 assetlinks.json을 낸다.
    safe_building_id = html.escape(building_id)
    safe_place_id = html.escape(place_id)
    return HTMLResponse(
        f"""<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{_SERVICE_NAME}</title>
<style>
  body {{ font-family: system-ui, -apple-system, sans-serif; margin: 0;
         display: grid; place-items: center; min-height: 100vh; color: #17171B; }}
  main {{ padding: 24px; max-width: 24rem; text-align: center; }}
  code {{ background: #F3F4F6; padding: 2px 6px; border-radius: 6px;
          font-size: 0.85em; word-break: break-all; }}
</style>
</head>
<body>
<main>
  <h1>{_SERVICE_NAME}</h1>
  <p>앱에서 이 장소를 열 수 있습니다.</p>
  <p><code>{safe_building_id}</code> / <code>{safe_place_id}</code></p>
</main>
</body>
</html>"""
    )
