"""장소 공유 링크가 앱을 열 수 있게 하는 파일 둘과, 앱이 없는 사람이 볼 페이지.

이 셋이 없으면 공유 버튼은 **깨진 링크를 뿌린다.** OS는 앱의 주장이 아니라 도메인이
낸 증명 파일을 보고 링크를 앱으로 넘길지 정하고, 앱이 없는 사람은 같은 URL을 브라우저로
연다. 그래서 이 라우터의 계약은 "200을 준다"가 전부가 아니라 **OS가 읽을 수 있는
모양인가**다.
"""


# Android는 이 파일에 적힌 패키지·서명 지문이 설치된 앱과 맞아야 링크를 넘긴다.
def test_안드로이드_증명_파일이_패키지와_지문을_담는다(api_client):
    response = api_client.get("/.well-known/assetlinks.json")

    assert response.status_code == 200
    entries = response.json()
    assert isinstance(entries, list) and entries

    target = entries[0]["target"]
    assert entries[0]["relation"] == ["delegate_permission/common.handle_all_urls"]
    assert target["namespace"] == "android_app"
    assert target["package_name"] == "com.navigation.navigation_client"
    # 지문은 대문자 16진수 32바이트를 콜론으로 이은 형태다. 형식이 어긋나면 OS가
    # 조용히 검증에 실패하고, 링크는 브라우저로 새며 아무 오류도 남지 않는다.
    for fingerprint in target["sha256_cert_fingerprints"]:
        octets = fingerprint.split(":")
        assert len(octets) == 32
        assert all(len(octet) == 2 for octet in octets)
        assert fingerprint == fingerprint.upper()


# iOS는 확장자 없는 이 경로를 application/json으로 받아야 읽는다.
def test_iOS_증명_파일이_place_경로를_앱에_넘긴다(api_client):
    response = api_client.get("/.well-known/apple-app-site-association")

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("application/json")
    details = response.json()["applinks"]["details"]
    assert details[0]["components"] == [{"/": "/place/*"}]


# 공유받은 사람 절반은 앱이 없다. 404를 주면 그 절반이 깨진 링크를 본다.
def test_앱이_없는_사람에게_페이지를_준다(api_client):
    response = api_client.get("/place/thehyundai-seoul/PO-HU40njvml1512")

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/html")
    assert "PO-HU40njvml1512" in response.text


# **매장을 조회하지 않는다.** 조회를 붙이면 삭제된 매장에서 이 페이지가 500을 내며
# 공유 링크가 통째로 죽는다. 없는 id로도 페이지는 서야 한다.
def test_없는_매장_링크도_페이지는_선다(api_client):
    response = api_client.get("/place/no-such-building/no-such-place")

    assert response.status_code == 200


# 이 주소는 사람들이 메신저에 붙여 넣는 **공개 페이지**이고, 같은 출처가 assetlinks.json을
# 낸다. 경로 파라미터는 서버가 percent-decode한 뒤 넘겨주므로 `%3Cimg ...%3E`가 살아 있는
# 마크업으로 들어온다. "id가 본문에 있다"만 보면 이스케이프를 걷어내도 통과하므로,
# **꺾쇠가 실체로 남지 않는 것**을 직접 확인한다.
def test_링크의_글자가_마크업으로_살아나지_않는다(api_client):
    response = api_client.get("/place/b/%3Cimg%20src=x%20onerror=alert(1)%3E")

    assert response.status_code == 200
    body = response.text
    assert "<img" not in body
    assert "onerror" not in body or "&lt;img" in body
    assert "&lt;img" in body
