/// 위치 스트림의 **수명**을 소유한다 — 구독, 재연결, 벙어리 감시, 조용한
/// 구간을 메우는 일회성 조회.
///
/// 좌표를 **어떻게 쓸지는 화면이 정한다** — 여기는 "좌표가 왔다"를 끊기지 않게
/// 배달하는 것까지다.
///
/// 한 곳에 모은 이유는 스트림이 **세 가지로 다르게 죽기** 때문이다(에러 닫힘·조용한
/// 닫힘·열린 채 벙어리). 근거와 실기기 로그는 `docs/client/gps-stream-policy.md`.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../../service_locator.dart';
import 'gps_freshness_policy.dart';

/// 좌표 한 건이 도착했을 때. [fromStream]이 false면 일회성 조회로 끌어온 것이다
/// (진단 칩이 이 둘을 구분해 보여준다).
typedef GpsFixHandler = void Function(Position position, {bool fromStream});
typedef GpsPositionRequester = Future<Position> Function();

class GpsSession {
  GpsSession({
    required this.onFix,
    required this.isActive,
    required this.onStreamError,
    GpsPositionRequester? requestPosition,
  }) : _requestPosition =
           requestPosition ??
           (() => Geolocator.getCurrentPosition(
             locationSettings: oneShotFixSettings(),
           ));

  /// 좌표 배달구. 스트림으로 온 것과 일회성 조회로 끌어온 것이 **같은 문**을
  /// 지난다 — 따로 처리하면 손으로 끌어온 좌표만 판정을 건너뛰게 된다.
  final GpsFixHandler onFix;

  /// 지금도 배달해도 되는지(화면이 살아 있고 추적을 원하는지). 타이머·비동기
  /// 응답이 화면보다 늦게 도착할 수 있어, 매번 이걸 다시 묻는다.
  final bool Function() isActive;

  /// 스트림이 **에러로** 닫혔을 때. 정상 종료(onDone)·벙어리와 달리 이때만
  /// 화면이 마지막 좌표를 버린다 — 에러는 "지금 위치를 모른다"는 뜻이라,
  /// 옛 좌표를 계속 그려 두면 사용자가 그 자리에 있다고 읽는다.
  final VoidCallback onStreamError;
  final GpsPositionRequester _requestPosition;

  StreamSubscription<Position>? _subscription;

  /// 닫힌 스트림을 다시 열기까지 기다리는 시간. 계산은 [nextStreamRetryDelay]가 한다.
  Duration _retryDelay = streamRetryMinDelay;
  Timer? _retryTimer;

  /// 지금 열어 둔 스트림이 좌표를 한 건이라도 줬는지. 구독을 새로 열 때마다
  /// false로 되돌린다.
  bool _deliveredFix = false;

  /// 새로 연 스트림이 벙어리인지 지켜보는 타이머([streamFirstFixTimeout]).
  Timer? _firstFixTimer;

  /// 스트림이 조용한지 주기적으로 확인하는 타이머.
  Timer? _freshFixTimer;

  /// 일회성 위치 조회가 떠 있는 동안 true. 겹쳐 쏘는 것을 막는다.
  bool _freshFixInFlight = false;

  /// 마지막으로 좌표를 **받은** 시각. 기기가 찍은 시각이 아니다 —
  /// 낡음의 기준은 "화면이 얼마나 오래 옛 위치를 보여주고 있는가"다.
  DateTime? _lastFixReceivedAt;

  /// 위치 스트림을 지금까지 몇 번 열었는지. **진단 전용이다.**
  ///
  /// 정상이라면 화면이 사는 동안 1이어야 한다. 이 값이 올라간다면 스트림이 죽고
  /// 있다는 뜻이고, 1에 머무는데도 좌표가 드물다면 스트림은 살아 있고 기기가
  /// 좌표를 늦게 주는 것이다. **둘은 완전히 다른 문제라, 이 값 없이는 화면만
  /// 보고 구분할 수 없다.**
  int get restartCount => _restartCount;
  int _restartCount = 0;

  /// 마지막 좌표가 스트림에서 왔는지(true) 일회성 조회에서 왔는지(false).
  /// 진단 칩에만 쓰인다 — 스트림이 조용한 채 일회성 조회만 화면을 떠받치고
  /// 있는 상태를 눈으로 구분하기 위한 것이다.
  bool get lastFixFromStream => _lastFixFromStream;
  bool _lastFixFromStream = false;

  bool get isSubscribed => _subscription != null;

  /// 스트림을 열고 신선도 감시를 켠다. 이미 열려 있으면 아무것도 하지 않는다.
  void start() {
    _syncFreshFixTimer(wanted: true);
    if (_subscription != null) return;
    _subscribe();
  }

  /// 구독·타이머를 전부 정리한다. 재시도 간격도 처음으로 되돌린다.
  void stop() {
    _syncFreshFixTimer(wanted: false);
    _retryTimer?.cancel();
    _retryTimer = null;
    _firstFixTimer?.cancel();
    _firstFixTimer = null;
    _retryDelay = streamRetryMinDelay;
    final subscription = _subscription;
    if (subscription == null) return;
    unawaited(subscription.cancel());
    _subscription = null;
  }

  void dispose() => stop();

  /// 위치 스트림을 새로 연다. **[start]와 재연결만 이 함수를 부른다** — 구독을
  /// 만드는 곳이 흩어지면 [onDone] 처리를 빠뜨린 경로가 다시 생긴다.
  void _subscribe() {
    _restartCount++;
    _deliveredFix = false;
    _subscription = watchPosition().listen(
      (position) => _deliver(position, fromStream: true),
      onError: (Object _) {
        // 에러 자체는 화면에 띄우지 않는다. 권한 거부·서비스 꺼짐이 대부분이고
        // 사용자가 할 수 있는 일은 재시도뿐이다. 다만 마지막 좌표는 버린다.
        if (isActive()) onStreamError();
        _handleClosed();
      },
      onDone: _handleClosed,
    );
    // **닫히지 않고 벙어리가 되는 경우**를 잡는다. 위 onDone/onError는 둘 다
    // 걸리지 않는다 — 자세한 사정은 [streamFirstFixTimeout] 주석에 있다.
    _firstFixTimer?.cancel();
    _firstFixTimer = Timer(streamFirstFixTimeout, () {
      _firstFixTimer = null;
      if (!isActive() || _deliveredFix) return;
      _handleClosed();
    });
  }

  void _deliver(Position position, {required bool fromStream}) {
    _lastFixFromStream = fromStream;
    // 좌표가 한 건이라도 들어오면 스트림은 살아 있다. 벙어리 감시를 걷고,
    // 재연결 간격도 되돌려 다음에 끊겼을 때 30초를 기다리지 않게 한다.
    if (fromStream) {
      _deliveredFix = true;
      _firstFixTimer?.cancel();
      _firstFixTimer = null;
      _retryDelay = streamRetryMinDelay;
    }
    // 추적이 꺼지기 직전에 이미 큐에 들어간 이벤트가 뒤늦게 도착할 수 있다.
    // 구독은 끊겼어도 이 한 건이 새어들어오면 위치 마커가 다시 켜지므로 막는다.
    if (!isActive()) return;
    // 낡음 판정은 **받은 시각** 기준이다. 기기가 찍은 시각을 쓰면, 같은 좌표를
    // 반복해서 받는 동안에도 계속 낡은 것으로 보여 요청이 멈추지 않는다.
    _lastFixReceivedAt = DateTime.now();
    onFix(position, fromStream: fromStream);
  }

  /// 스트림이 어떤 방식으로든 끝났을 때. 세 갈래(에러·정상 종료·벙어리)가 전부
  /// 여기로 모여 **같은 재시도 경로**를 탄다.
  void _handleClosed() {
    if (_subscription == null) return;
    _firstFixTimer?.cancel();
    _firstFixTimer = null;
    unawaited(_subscription!.cancel());
    _subscription = null;
    if (!isActive()) return;
    if (_retryTimer != null) return;
    _retryTimer = Timer(_retryDelay, () {
      _retryTimer = null;
      _retryDelay = nextStreamRetryDelay(_retryDelay);
      if (!isActive()) return;
      if (_subscription != null) return;
      _subscribe();
    });
  }

  void _syncFreshFixTimer({required bool wanted}) {
    if (!wanted) {
      _freshFixTimer?.cancel();
      _freshFixTimer = null;
      return;
    }
    if (_freshFixTimer != null) return;
    _freshFixTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_maybeRequestFreshFix()),
    );
  }

  /// 진입 후보처럼 다음 좌표를 지금 확인할 이유가 생겼을 때 즉시 한 건을 요청한다.
  /// 주기 감시와 같은 in-flight 게이트를 써 중복 플랫폼 요청은 만들지 않는다.
  Future<void> requestFreshFix() => _requestFreshFix(force: true);

  /// 스트림이 약속한 간격을 안 지키는 기기에서 위치를 직접 끌어온다.
  ///
  /// 실측에서 1초를 요청했는데 15~36초에 한 건이 왔고, 같은 순간 "위치 갱신"
  /// 버튼의 일회성 조회는 즉시 응답했다. 그 경로를 앱이 대신 눌러 준다.
  Future<void> _maybeRequestFreshFix() async {
    await _requestFreshFix(force: false);
  }

  Future<void> _requestFreshFix({required bool force}) async {
    if (!isActive() || _freshFixInFlight) return;
    if (!force &&
        !shouldRequestFreshFix(
          lastFixReceivedAt: _lastFixReceivedAt,
          now: DateTime.now(),
          requestInFlight: _freshFixInFlight,
        )) {
      return;
    }
    _freshFixInFlight = true;
    try {
      final position = await _requestPosition();
      _deliver(position, fromStream: false);
    } catch (error) {
      // 조용히 넘긴다. 다음 주기에 다시 시도하고, 실패해도 스트림은 그대로다.
      debugPrint('one-shot fix failed: $error');
    } finally {
      _freshFixInFlight = false;
    }
  }
}
