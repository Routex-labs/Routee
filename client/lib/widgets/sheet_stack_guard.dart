import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 지도 위 시트를 **한 번에 한 장**으로 유지한다 — 두 장째가 뜨면 앞의 것을 걷는다.
///
/// 세는 대상은 `ModalBottomSheetRoute`뿐이라, 의도적으로 겹치는 것(대중교통
/// 상세·사진 뷰어·PDR 입력)은 route 타입이 달라 **표시 없이 예외**가 된다.
///
/// 왜 입구마다 막지 않고 여기서 막는지, 왜 `pop`이 아니라 `removeRoute`인지는
/// `docs/client/sheet-exclusivity.md`.
class SheetStackGuard extends NavigatorObserver {
  final _open = <ModalBottomSheetRoute<dynamic>>[];

  /// 지금 살아 있는 시트 라우트 수. 불변식대로면 늘 0 또는 1이다.
  int get openCount => _open.length;

  /// 같은 값을 **듣고 있을 수 있게** 내보낸다.
  ///
  /// 지도 화면 아래에는 라우트가 아닌 표면(이슈 다이어리 판)도 있다. 그것은
  /// 이 관찰자가 세는 대상이 아니라 시트가 떠도 그대로 남아, 시트보다 짧으면
  /// 위쪽이 삐져나와 **두 장이 겹친 것처럼 보인다.** 라우트를 걷어내는 것과
  /// 같은 신호로 그 표면도 물러나게 하려면 값이 밖으로 나가야 한다.
  ValueListenable<int> get openSheets => _openSheets;
  final _openSheets = ValueNotifier<int>(0);

  void _publish() => _openSheets.value = _open.length;

  /// **겹친 것을 실제로 걷어낸 횟수.** 테스트가 "정말 일했나"를 재는 데 쓴다 —
  /// 0이면 겹친 적이 없었다는 뜻이지, 막았다는 뜻이 아니다.
  int get caughtStackings => _caught;
  int _caught = 0;

  /// 지금 떠 있는 시트를 **전부 걷는다.** 걷은 장수를 돌려준다.
  ///
  /// 시트가 아닌 라우트(전체화면·다이얼로그)는 애초에 세지 않으므로 건드리지
  /// 않는다 — 예외의 기준이 [didPush]와 같은 한 곳에 있다.
  ///
  /// 상단 패널(검색·길찾기 후보)이 켜질 때 셸이 부른다. 그 패널은 라우트가 아닌
  /// 화면 위쪽 표면이라 이 관찰자가 세지 못하는데, 시트는 아래쪽에 그대로 남아
  /// **두 표면이 한 화면에 겹친다**(실기기 확인 — 매장 상세를 열어 둔 채 검색하면
  /// 결과 목록과 상세가 함께 떴다).
  ///
  /// `pop`이 아니라 `removeRoute`인 이유는 겹침을 걷을 때와 같다 — `PopScope`를
  /// 깨우면 "사용자가 끌어내려 닫았다"는 신호가 되어 chain 전체가 접힌다.
  int closeOpenSheets() {
    if (_open.isEmpty) return 0;
    final closing = _open.toList();
    _open.clear();
    _publish();
    for (final route in closing) {
      route.navigator?.removeRoute(route);
    }
    return closing.length;
  }

  /// 테스트가 앱을 새로 띄울 때 부른다 — 앞 테스트가 두고 간 라우트는 이미
  /// 버려진 Navigator의 것이라 세면 안 된다.
  @visibleForTesting
  void resetForTest() {
    _open.clear();
    _caught = 0;
    _publish();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! ModalBottomSheetRoute) return;
    final stale = _open.toList();
    _open
      ..clear()
      ..add(route);
    if (stale.isEmpty) {
      _publish();
      return;
    }
    _caught += stale.length;
    // 지금은 push 처리 한복판이다. 그 자리에서 Navigator의 목록을 건드리지 않고
    // 마이크로태스크로 미룬다 — 프레임을 그리기 전에 실행되므로 두 장이 함께
    // 보이는 프레임은 생기지 않는다.
    _publish();
    scheduleMicrotask(() {
      for (final other in stale) {
        other.navigator?.removeRoute(other);
      }
    });
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _open.remove(route);
    _publish();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _open.remove(route);
    _publish();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _open.remove(oldRoute);
    if (newRoute is ModalBottomSheetRoute) _open.add(newRoute);
    _publish();
  }
}

/// 앱에 하나뿐인 관찰자. `MaterialApp`의 `navigatorObservers`에 넣는다.
///
/// 전역인 이유는 Navigator가 하나뿐이어서다 — 이 앱에는 push할 다른 화면이 없고
/// (`app.dart`), 시트·오버레이가 전부 그 하나 위에 얹힌다.
final sheetStackGuard = SheetStackGuard();
