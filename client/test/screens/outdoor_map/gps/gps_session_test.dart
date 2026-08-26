/// 위치 스트림의 **수명**.
///
/// `GpsSession`의 문서는 스트림이 죽는 방식이 넷이라고 적는다 — 에러로 닫힘,
/// 에러 없이 닫힘, 처음부터 벙어리, 한 건 주고 침묵. **2·3·4번이 차례로 빠져
/// 있던 적이 있고**, 실기기에서 "위치 갱신 버튼은 되는데 화면은 안 움직인다"로
/// 나타났다.
///
/// 넷 다 화면에는 오류를 남기지 않는다. 좌표가 그냥 안 올 뿐이다. 그래서
/// 여기서 넷을 각각 못 박는다.
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/screens/outdoor_map/gps/gps_freshness_policy.dart';
import 'package:navigation_client/screens/outdoor_map/gps/gps_session.dart';

/// 한 건의 좌표. [takenAt]은 **기기가 찍은 시각**이고, 이 값이 좌표의 신원이다 —
/// 안드로이드 fused provider는 새 측위를 못 하면 마지막으로 알던 위치를 그대로
/// 돌려주므로, 시각이 안 움직이면 그건 새 좌표가 아니라 같은 좌표의 메아리다.
Position _fix({
  double lat = 37.5665,
  double lng = 126.98,
  DateTime? takenAt,
}) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: takenAt ?? DateTime(2024, 1, 1),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

/// 테스트가 직접 여닫는 위치 스트림.
///
/// 구독이 새로 열릴 때마다 **새 컨트롤러**를 만든다. 실제 geolocator도 그렇고,
/// 하나를 재사용하면 "다시 열었다"와 "안 닫혔다"를 구분할 수 없다.
class _FakeStreams {
  final controllers = <StreamController<Position>>[];

  StreamController<Position> get latest => controllers.last;
  int get openCount => controllers.length;

  Stream<Position> open() {
    final controller = StreamController<Position>();
    controllers.add(controller);
    return controller.stream;
  }

  void closeAll() {
    for (final c in controllers) {
      if (!c.isClosed) c.close();
    }
  }
}

/// `fakeAsync`의 시계. `elapse`는 `DateTime.now`를 밀지 않으므로, 좌표의 낡음을
/// 재는 갈래가 도는 테스트는 이 시계를 세션에 넣어야 한다.
DateTime Function() _clock(FakeAsync async) =>
    () => DateTime(2024, 1, 1).add(async.elapsed);

/// 일회성 조회가 좌표를 주는 상태 / 못 주는 상태 / **같은 좌표만 되돌려주는** 상태.
///
/// **이 셋이 침묵의 원인을 가른다.** 스트림이 조용할 때 일회성 조회가 새 좌표를
/// 주면 스트림이 깨진 것이고, 아무것도 못 주면 신호가 없는 것이고(실내·터널),
/// 같은 좌표만 되돌려주면 기기가 캐시를 읽어 준 것이라 둘째와 같은 상태다.
///
/// 새 좌표는 **시각이 움직인다.** 호출마다 1초씩 민다.
void _oneShotSucceeds() {
  var takenAt = DateTime(2024, 1, 1);
  currentPosition = () async {
    takenAt = takenAt.add(const Duration(seconds: 1));
    return _fix(takenAt: takenAt);
  };
}

void _oneShotFails() =>
    currentPosition = () async => throw Exception('no fix');

/// 새 측위에 실패해 **마지막으로 알던 좌표**를 그대로 돌려주는 기기.
void _oneShotEchoes(DateTime takenAt) =>
    currentPosition = () async => _fix(takenAt: takenAt);

/// 세션 하나와 그 관찰값을 한 묶음으로 만든다.
({
  GpsSession session,
  _FakeStreams streams,
  List<bool> deliveries,
  List<String> events,
})
_harness({bool Function()? isActive, DateTime Function()? now}) {
  final streams = _FakeStreams();
  final deliveries = <bool>[];
  final events = <String>[];
  watchPosition = streams.open;
  final session = GpsSession(
    onFix: (_, {bool fromStream = false}) => deliveries.add(fromStream),
    isActive: isActive ?? () => true,
    onStreamError: () => events.add('error'),
    now: now ?? DateTime.now,
  );
  return (
    session: session,
    streams: streams,
    deliveries: deliveries,
    events: events,
  );
}

void main() {
  final original = watchPosition;
  final originalCurrentPosition = currentPosition;
  setUp(_oneShotFails);
  tearDown(() {
    watchPosition = original;
    currentPosition = originalCurrentPosition;
  });

  group('열고 닫기', () {
    test('start를 두 번 불러도 스트림은 하나만 연다', () {
      fakeAsync((async) {
        final h = _harness();
        h.session.start();
        h.session.start();
        expect(h.streams.openCount, 1);
        expect(h.session.restartCount, 1);
        h.session.stop();
      });
    });

    test('stop은 구독을 끊고 재시도 간격을 처음으로 되돌린다', () {
      fakeAsync((async) {
        final h = _harness();
        h.session.start();
        expect(h.session.isSubscribed, isTrue);
        h.session.stop();
        expect(h.session.isSubscribed, isFalse);

        // 되돌아갔는지는 다시 열어 최소 간격으로 붙는 것으로 확인한다.
        h.session.start();
        h.streams.latest.close();
        async.elapse(streamRetryMinDelay);
        expect(h.streams.openCount, 3);
        h.session.stop();
      });
    });

    test('stop 뒤 늦게 도착한 좌표는 배달되지 않는다', () {
      // 추적이 꺼지기 직전에 큐에 들어간 이벤트가 뒤늦게 오면, 이 한 건으로
      // 위치 마커가 다시 켜진다.
      fakeAsync((async) {
        var active = true;
        final h = _harness(isActive: () => active);
        h.session.start();
        final stream = h.streams.latest;
        active = false;
        stream.add(_fix());
        async.flushMicrotasks();
        expect(h.deliveries, isEmpty);
        h.session.stop();
      });
    });
  });

  group('죽는 방식 셋 — 전부 같은 재연결로 모여야 한다', () {
    test('1) 에러로 닫히면 화면에 알리고 다시 연다', () {
      fakeAsync((async) {
        final h = _harness();
        h.session.start();
        h.streams.latest.addError(Exception('gps down'));
        async.flushMicrotasks();

        // 에러일 때만 화면이 마지막 좌표를 버린다.
        expect(h.events, ['error']);
        async.elapse(streamRetryMinDelay);
        expect(h.streams.openCount, 2);
        h.session.stop();
      });
    });

    test('2) 에러 없이 닫혀도 다시 연다', () {
      // **한때 빠져 있던 경로다.** onError만 보고 있으면 구독 객체가 null이
      // 아닌 채 남아 "이미 구독 중"으로 판단하고 영영 다시 열지 않는다.
      fakeAsync((async) {
        final h = _harness();
        h.session.start();
        h.streams.latest.close();
        async.flushMicrotasks();

        // 정상 종료는 에러가 아니므로 마지막 좌표를 버리지 않는다.
        expect(h.events, isEmpty);
        async.elapse(streamRetryMinDelay);
        expect(h.streams.openCount, 2);
        expect(h.session.restartCount, 2);
        h.session.stop();
      });
    });

    test('3) 열린 채 벙어리면 감시 시간 뒤에 다시 연다', () {
      // **onDone도 onError도 안 걸리는 경우다.** geolocator 안드로이드가
      // 포그라운드 서비스 바인딩 전에 구독하면 위치 요청을 걸지 않고 돌아선다.
      fakeAsync((async) {
        final h = _harness();
        h.session.start();

        // 감시 시간 직전까지는 아직 살아 있다고 본다.
        async.elapse(streamSilenceTimeout - const Duration(seconds: 1));
        expect(h.streams.openCount, 1);

        async.elapse(const Duration(seconds: 1) + streamRetryMinDelay);
        expect(h.streams.openCount, 2);
        h.session.stop();
      });
    });

    test('좌표가 오면 감시 시간을 처음부터 다시 잰다', () {
      // 느릴 뿐 살아 있는 스트림을 끊으면 재등록이 겹쳐 오히려 더 느려진다.
      fakeAsync((async) {
        final h = _harness();
        h.session.start();

        // 감시가 터지기 직전에 좌표가 한 건 온다.
        async.elapse(streamSilenceTimeout - const Duration(seconds: 1));
        h.streams.latest.add(_fix());
        async.flushMicrotasks();

        // 다시 재지 않았다면 여기서 이미 끊겼을 시각이다.
        async.elapse(const Duration(seconds: 2) + streamRetryMinDelay);
        expect(h.streams.openCount, 1, reason: '살아 있는 스트림을 끊었다');
        expect(h.deliveries, [true]);
        h.session.stop();
      });
    });

    test('3-b) 한 건만 주고 조용해지면, 기기가 좌표를 만드는 동안 다시 연다', () {
      // **한때 빠져 있던 경로다.** 첫 좌표에서 감시를 영구히 걷어 버려, 그 뒤로
      // 조용해진 스트림은 onDone·onError·감시 어디에도 안 걸렸다. 실기기에서
      // 진단 칩이 `재시작1`인 채 좌표가 전부 `직접`으로만 찍힌 것이 이 상태이고,
      // 그동안 좌표는 일회성 조회가 3~9초에 한 건씩 떠받쳤다.
      fakeAsync((async) {
        _oneShotSucceeds();
        final h = _harness(now: _clock(async));
        h.session.start();
        h.streams.latest.add(_fix());
        async.flushMicrotasks();

        async.elapse(streamSilenceTimeout + streamRetryMinDelay);
        expect(
          h.streams.openCount,
          2,
          reason: '한 건 뒤 조용해진 스트림을 아무도 못 잡는다',
        );
        h.session.stop();
      });
    });

    test('3-c) 기기도 좌표를 못 만들면(실내·터널) 다시 열지 않는다', () {
      // 스트림도 일회성 조회도 조용하면 **신호가 없는 것이지 스트림이 깨진 것이
      // 아니다.** 안 가르면 실내에 서 있는 내내 구독을 여닫는다 — 실내에서
      // 구독을 유지한다는 약속(`outdoor_indoor_gps_test.dart`)이 여기서 깨진다.
      fakeAsync((async) {
        final h = _harness(now: _clock(async));
        h.session.start();
        h.streams.latest.add(_fix());
        async.flushMicrotasks();

        async.elapse((streamSilenceTimeout + streamRetryMinDelay) * 3);
        expect(
          h.streams.openCount,
          1,
          reason: '신호가 없을 뿐인데 채널을 계속 두드린다',
        );
        h.session.stop();
      });
    });
  });

  group('같은 좌표를 되받는 경우 — 캐시 메아리', () {
    test('일회성 조회가 같은 좌표를 되돌려주면 배달하지 않는다', () {
      // **이게 "마커가 실제 위치와 안 맞는다"의 정체였다.** 걷는 동안 스트림이
      // 조용해지면 매초 일회성 조회가 나가는데, 기기가 새 측위를 못 하면
      // 마지막으로 알던 좌표를 그대로 돌려준다. 그 한 건을 "지금 위치"로 받으면
      // 마커는 걸어온 만큼 뒤처진 자리에 그대로 서 있게 된다.
      fakeAsync((async) {
        final takenAt = DateTime(2024, 1, 1);
        _oneShotEchoes(takenAt);
        final h = _harness(now: _clock(async));
        h.session.start();
        h.streams.latest.add(_fix(takenAt: takenAt));
        async.flushMicrotasks();
        expect(h.deliveries, [true]);

        // 메아리가 여러 번 와도 배달은 늘지 않는다.
        async.elapse(gpsFixMaxAge * 4);
        expect(h.deliveries, [true], reason: '같은 좌표를 새 위치로 배달했다');
        h.session.stop();
      });
    });

    test('메아리는 신선도 시계를 되감지 않는다', () {
      // 배달만 막고 받은 시각을 갱신해 버리면 더 나쁘다 — 다음 주기가 조용해져
      // **정작 새 좌표가 필요한 구간에서 조회가 멎는다.** 조회가 계속 나가는지로
      // 확인한다.
      fakeAsync((async) {
        final takenAt = DateTime(2024, 1, 1);
        var lookups = 0;
        currentPosition = () async {
          lookups++;
          return _fix(takenAt: takenAt);
        };
        final h = _harness(now: _clock(async));
        h.session.start();
        h.streams.latest.add(_fix(takenAt: takenAt));
        async.flushMicrotasks();

        async.elapse(gpsFixMaxAge * 3);
        expect(lookups, greaterThan(1), reason: '메아리 한 건에 조회가 멎었다');
        h.session.stop();
      });
    });

    test('메아리만 오는 것은 "기기가 좌표를 만든다"는 근거가 아니다', () {
      // 스트림을 다시 여는 조건은 "기기는 만드는데 스트림만 조용하다"이다.
      // 메아리를 성공으로 세면 신호가 없는 실내에서도 그 조건이 서서, 서 있는
      // 내내 구독을 여닫게 된다.
      fakeAsync((async) {
        final takenAt = DateTime(2024, 1, 1);
        _oneShotEchoes(takenAt);
        final h = _harness(now: _clock(async));
        h.session.start();
        h.streams.latest.add(_fix(takenAt: takenAt));
        async.flushMicrotasks();

        async.elapse((streamSilenceTimeout + streamRetryMinDelay) * 2);
        expect(h.streams.openCount, 1, reason: '메아리를 새 좌표로 착각했다');
        h.session.stop();
      });
    });

    test('스트림 좌표는 시각이 안 움직여도 그대로 배달한다', () {
      // 스트림은 기기의 현재 의견을 실시간으로 밀어 주는 쪽이다. 여기서까지
      // 걸렀다가 시각이 한 번 튀는 기기를 만나면 그 뒤로 모든 좌표를 버려
      // **위치가 통째로 죽는다.** 그 실패는 되돌릴 방법이 화면에 없다.
      fakeAsync((async) {
        final takenAt = DateTime(2024, 1, 1);
        final h = _harness(now: _clock(async));
        h.session.start();
        h.streams.latest.add(_fix(takenAt: takenAt));
        h.streams.latest.add(_fix(takenAt: takenAt));
        h.streams.latest.add(_fix(takenAt: takenAt.subtract(const Duration(minutes: 5))));
        async.flushMicrotasks();
        expect(h.deliveries, [true, true, true]);
        h.session.stop();
      });
    });
  });

  group('재연결 간격', () {
    test('연달아 끊기면 간격이 배로 늘어난다', () {
      // 권한이 거부됐거나 위치 서비스가 꺼져 있으면 스트림은 열자마자 닫힌다.
      // 고정 간격이면 그 상태에서 2초마다 채널을 두드리며 배터리만 태운다.
      fakeAsync((async) {
        final h = _harness();
        h.session.start();

        h.streams.latest.close();
        async.flushMicrotasks();
        async.elapse(streamRetryMinDelay);
        expect(h.streams.openCount, 2);

        // 두 번째는 최소 간격으로 안 붙는다 — 이미 배로 늘었다.
        h.streams.latest.close();
        async.flushMicrotasks();
        async.elapse(streamRetryMinDelay);
        expect(h.streams.openCount, 2, reason: '간격이 안 늘어났다');

        // 딱 두 배 지점에서 붙는다.
        async.elapse(streamRetryMinDelay);
        expect(h.streams.openCount, 3);
        h.session.stop();
      });
    });

    test('좌표를 받으면 간격이 처음으로 되돌아간다', () {
      // 되돌리지 않으면, 한 번 30초까지 벌어진 뒤로는 잠깐 끊길 때마다
      // 30초씩 화면이 멎는다.
      fakeAsync((async) {
        final h = _harness();
        h.session.start();

        // 두 번 끊어 간격을 4초까지 벌린다.
        h.streams.latest.close();
        async.flushMicrotasks();
        async.elapse(streamRetryMinDelay);
        h.streams.latest.close();
        async.flushMicrotasks();
        async.elapse(streamRetryMinDelay * 2);
        expect(h.streams.openCount, 3);

        // 좌표 한 건이 오면 살아 있는 스트림이다.
        h.streams.latest.add(_fix());
        async.flushMicrotasks();

        h.streams.latest.close();
        async.flushMicrotasks();
        async.elapse(streamRetryMinDelay);
        expect(h.streams.openCount, 4, reason: '간격이 안 되돌아갔다');
        h.session.stop();
      });
    });

    test('벙어리 스트림은 감시 시간 + 재연결 간격 주기로 다시 열린다', () {
      // 백오프(2초부터 배증)보다 벙어리 감시(12초)가 길기 때문에, 영영 조용한
      // 스트림에서는 감시 쪽이 주기를 정한다. 그래서 간격이 30초까지 벌어져도
      // 재연결이 멎지 않는다.
      fakeAsync((async) {
        final h = _harness();
        h.session.start();
        async.elapse(streamSilenceTimeout + streamRetryMinDelay);
        expect(h.streams.openCount, 2);
        async.elapse(streamSilenceTimeout + streamRetryMinDelay * 2);
        expect(h.streams.openCount, 3);
        h.session.stop();
      });
    });
  });

  group('추적이 꺼져 있으면', () {
    test('스트림이 끊겨도 다시 열지 않는다', () {
      fakeAsync((async) {
        var active = true;
        final h = _harness(isActive: () => active);
        h.session.start();
        active = false;
        h.streams.latest.close();
        async.flushMicrotasks();
        async.elapse(streamRetryMaxDelay * 2);
        expect(h.streams.openCount, 1);
        h.session.stop();
      });
    });
  });
}
