/// 위치 스트림의 **수명**을 소유한다 — 구독, 재연결, 침묵 감시, 조용한
/// 구간을 메우는 일회성 조회.
///
/// 좌표를 **어떻게 쓸지는 화면이 정한다** — 여기는 "좌표가 왔다"를 끊기지 않게
/// 배달하는 것까지다.
///
/// 한 곳에 모은 이유는 스트림이 **네 가지로 다르게 죽기** 때문이다(에러 닫힘·조용한
/// 닫힘·처음부터 벙어리·한 건 뒤 침묵). 근거와 실기기 로그는 `docs/client/gps-stream-policy.md`.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../../service_locator.dart';
import 'gps_freshness_policy.dart';

/// 좌표 한 건이 도착했을 때. [fromStream]이 false면 일회성 조회로 끌어온 것이다
/// (진단 칩이 이 둘을 구분해 보여준다).
typedef GpsFixHandler = void Function(Position position, {bool fromStream});

class GpsSession {
  GpsSession({
    required this.onFix,
    required this.isActive,
    required this.onStreamError,
    this.now = DateTime.now,
  });

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

  /// 지금 시각. **테스트만 갈아끼운다** — `fakeAsync`의 `elapse`는 `DateTime.now`
  /// 를 밀지 않아, 실제 시계를 그대로 쓰면 좌표의 낡음을 재는 갈래
  /// ([shouldRequestFreshFix])를 테스트에서 한 번도 돌릴 수 없다.
  final DateTime Function() now;

  StreamSubscription<Position>? _subscription;

  /// 닫힌 스트림을 다시 열기까지 기다리는 시간. 계산은 [nextStreamRetryDelay]가 한다.
  Duration _retryDelay = streamRetryMinDelay;
  Timer? _retryTimer;

  /// 스트림이 조용한지 지켜보는 타이머([streamSilenceTimeout]).
  Timer? _silenceTimer;

  /// 지금 열어 둔 구독이 좌표를 한 건이라도 줬는지. 구독을 새로 열 때 되돌린다.
  bool _deliveredFix = false;

  /// 마지막 스트림 좌표 **뒤에** 일회성 조회가 좌표를 받아 왔는지.
  ///
  /// 스트림 침묵의 원인을 가르는 값이다 — 기기는 좌표를 만드는데 스트림만
  /// 조용하다면 스트림이 깨진 것이고, 둘 다 조용하면 신호가 없는 것이다.
  bool _oneShotSinceStreamFix = false;

  /// 스트림이 조용한지 주기적으로 확인하는 타이머.
  Timer? _freshFixTimer;

  /// 일회성 위치 조회가 떠 있는 동안 true. 겹쳐 쏘는 것을 막는다.
  bool _freshFixInFlight = false;

  /// 마지막으로 좌표를 **받은** 시각. 기기가 찍은 시각이 아니다 —
  /// 낡음의 기준은 "화면이 얼마나 오래 옛 위치를 보여주고 있는가"다.
  DateTime? _lastFixReceivedAt;

  /// 마지막으로 배달한 좌표를 **기기가 찍은** 시각. 위 값과 짝을 이루지만 하는
  /// 일이 다르다 — 이쪽은 "같은 좌표를 또 받았는가"를 가린다([_deliver]).
  DateTime? _lastFixTakenAt;

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
    _silenceTimer?.cancel();
    _silenceTimer = null;
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
    _oneShotSinceStreamFix = false;
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
    // 걸리지 않는다 — 자세한 사정은 [streamSilenceTimeout] 주석에 있다.
    _armSilenceWatchdog();
  }

  /// 침묵 감시를 새로 건다. 구독을 열 때와 **스트림 좌표가 올 때마다** 부른다.
  ///
  /// 터졌을 때 다시 여는 조건은 [_shouldReopenOnSilence]가 정한다. 조건이 아니면
  /// 감시만 다시 걸어, 신호가 없는 구간에서 채널을 두드리지 않는다.
  void _armSilenceWatchdog() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(streamSilenceTimeout, () {
      _silenceTimer = null;
      if (!isActive()) return;
      if (!_shouldReopenOnSilence()) {
        _armSilenceWatchdog();
        return;
      }
      // 진단 칩은 화면에만 뜨고 로그에는 안 남는다. 사후에 "스트림이 조용했다"를
      // 확인할 수 있는 유일한 단서라, 재구독이 드문 만큼 남겨 둔다.
      debugPrint('[gps] 스트림이 ${streamSilenceTimeout.inSeconds}초 조용해 다시 연다');
      _handleClosed();
    });
  }

  /// 조용한 스트림을 끊고 다시 열지. **침묵의 원인이 스트림일 때만 참이다.**
  ///
  /// 한 건도 못 준 구독은 포그라운드 서비스 바인딩 경합에 진 것이라 무조건 다시
  /// 연다. 주다가 조용해진 구독은 같은 시간에 **일회성 조회가 좌표를 받아 왔을
  /// 때만** 끊는다 — 그때만 "기기는 만드는데 스트림만 조용하다"가 성립한다.
  /// 둘 다 조용하면 신호가 없는 것이고(실내·터널), 다시 열어도 얻는 것이 없다.
  bool _shouldReopenOnSilence() => !_deliveredFix || _oneShotSinceStreamFix;

  /// 일회성 조회가 **이미 배달한 좌표를 또 준 것**인지.
  ///
  /// 안드로이드 fused provider는 새 측위를 못 하면 마지막으로 알던 위치를 그대로
  /// 돌려준다. 그 한 건을 "지금 위치"로 받아들이면 두 가지가 동시에 망가진다 —
  /// 마커가 걸어온 만큼 뒤처진 자리에 그대로 서 있고, [_lastFixReceivedAt]이
  /// 갱신돼 **새 좌표를 요청할 이유가 사라진다.** 걷는 동안 매초 같은 좌표가
  /// 도착하면서 앱은 위치가 신선하다고 믿는다.
  ///
  /// 스트림 좌표에는 적용하지 않는다. 스트림은 기기의 현재 의견을 실시간으로
  /// 밀어 주는 쪽이고, 여기서까지 걸렀다가 시각이 한 번 튀는 기기를 만나면
  /// 그 뒤로 모든 좌표를 버려 위치가 통째로 죽는다.
  bool _isStaleEcho(Position position, {required bool fromStream}) {
    if (fromStream) return false;
    final lastTakenAt = _lastFixTakenAt;
    if (lastTakenAt == null) return false;
    return !position.timestamp.isAfter(lastTakenAt);
  }

  void _deliver(Position position, {required bool fromStream}) {
    if (_isStaleEcho(position, fromStream: fromStream)) {
      // **받은 시각을 갱신하지 않고 끝낸다.** 갱신하면 다음 주기가 조용해져,
      // 정작 새 좌표가 필요한 구간에서 조회가 멎는다.
      return;
    }
    _lastFixFromStream = fromStream;
    // 좌표가 들어오면 스트림은 살아 있다. 침묵 감시를 **다시 걸고**(걷어 버리면
    // 한 건만 주고 조용해지는 스트림을 못 잡는다), 재연결 간격도 되돌려 다음에
    // 끊겼을 때 30초를 기다리지 않게 한다.
    if (fromStream) {
      _deliveredFix = true;
      _oneShotSinceStreamFix = false;
      _armSilenceWatchdog();
      _retryDelay = streamRetryMinDelay;
    } else {
      _oneShotSinceStreamFix = true;
    }
    // 추적이 꺼지기 직전에 이미 큐에 들어간 이벤트가 뒤늦게 도착할 수 있다.
    // 구독은 끊겼어도 이 한 건이 새어들어오면 위치 마커가 다시 켜지므로 막는다.
    if (!isActive()) return;
    // 낡음 판정은 **받은 시각** 기준이다. 기기가 찍은 시각을 쓰면, 기기 시계가
    // 앱 시계와 다른 기준일 때 좌표가 늘 낡은 것으로 보여 요청이 멈추지 않는다.
    // 같은 좌표를 되받는 경우는 위 [_isStaleEcho]가 이미 걸렀다.
    _lastFixReceivedAt = now();
    _lastFixTakenAt = position.timestamp;
    onFix(position, fromStream: fromStream);
  }

  /// 스트림이 어떤 방식으로든 끝났을 때. 세 갈래(에러·정상 종료·침묵)가 전부
  /// 여기로 모여 **같은 재시도 경로**를 탄다.
  void _handleClosed() {
    if (_subscription == null) return;
    _silenceTimer?.cancel();
    _silenceTimer = null;
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

  /// 스트림이 약속한 간격을 안 지키는 기기에서 위치를 직접 끌어온다.
  ///
  /// 실측에서 1초를 요청했는데 15~36초에 한 건이 왔고, 같은 순간 "위치 갱신"
  /// 버튼의 일회성 조회는 즉시 응답했다. 그 경로를 앱이 대신 눌러 준다.
  Future<void> _maybeRequestFreshFix() async {
    if (!isActive()) return;
    if (!shouldRequestFreshFix(
      lastFixReceivedAt: _lastFixReceivedAt,
      now: now(),
      requestInFlight: _freshFixInFlight,
    )) {
      return;
    }
    _freshFixInFlight = true;
    try {
      final position = await currentPosition();
      _deliver(position, fromStream: false);
    } catch (error) {
      // 조용히 넘긴다. 다음 주기에 다시 시도하고, 실패해도 스트림은 그대로다.
      debugPrint('one-shot fix failed: $error');
    } finally {
      _freshFixInFlight = false;
    }
  }
}
