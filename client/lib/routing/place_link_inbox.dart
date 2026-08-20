import 'package:flutter/foundation.dart';

import 'place_link.dart';

/// 링크로 받은 장소를 지도 셸이 가져갈 때까지 들고 있는 자리.
///
/// **한 개만 들고 있다.** 링크는 앱이 아직 화면을 세우기 전에도 도착한다(cold
/// start). 그때 곧바로 시트를 열려고 하면 열 `BuildContext`가 없어 아무 일도
/// 일어나지 않고, 사용자는 링크를 눌렀는데 지도만 보게 된다. 그래서 도착한 것을
/// 여기 두고, 화면이 준비된 뒤 가져가게 한다.
///
/// **같은 링크를 두 번 처리하지 않는다.** 하나의 URI가 최초 URI와 stream 양쪽으로
/// 연달아 오는 경우가 있고, 그대로 두면 시트가 두 번 열린다.
class PlaceLinkInbox extends ValueNotifier<PlaceLink?> {
  PlaceLinkInbox({this.origin = placeLinkOrigin, DateTime Function()? now})
    : _now = now ?? DateTime.now,
      super(null);

  /// 우리 링크로 인정할 주소. 기본은 빌드에 박힌 값이고, 테스트만 바꿔 넣는다.
  final String origin;

  final DateTime Function() _now;

  /// 이 안에 다시 온 같은 URI만 중복으로 본다.
  ///
  /// 막으려는 것은 cold start의 최초 URI와 stream이 **같은 순간에** 흘리는 한 벌뿐이다.
  /// 그 둘은 프레임 몇 개 사이로 붙어 오므로 1초면 넉넉하다.
  static const repeatWindow = Duration(seconds: 1);

  Uri? _lastSeen;
  DateTime? _lastSeenAt;

  /// 받은 URI를 해석해 보관한다. 우리 링크가 아니거나 방금 본 것이면 무시한다.
  ///
  /// **"방금"에 시간이 붙어 있는 것이 핵심이다.** URI만으로 거르면 사용자가 시트를
  /// 닫은 뒤 같은 링크를 다시 눌러도 아무 일도 일어나지 않는다 — 앱만 앞으로 오고
  /// 시트도 실패 안내도 없다. 반대로 [take] 때 표식을 지우면, 리스너가 동기로 돌아
  /// stream 중복이 도착하기 전에 지워지므로 같은 시트가 두 번 열린다.
  void offer(Uri uri) {
    final now = _now();
    final lastAt = _lastSeenAt;
    if (uri == _lastSeen &&
        lastAt != null &&
        now.difference(lastAt) < repeatWindow) {
      return;
    }
    _lastSeen = uri;
    _lastSeenAt = now;
    final link = parsePlaceLink(uri, origin: origin);
    if (link == null) return;
    value = link;
  }

  /// 화면이 가져갔다. 다음 링크를 받을 준비를 한다.
  void take() => value = null;
}
