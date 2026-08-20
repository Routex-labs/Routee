/// 위치 스트림의 **수명**.
///
/// `GpsSession`의 문서는 스트림이 죽는 방식이 셋이고 셋 다 다르게 죽는다고
/// 적는다 — 에러로 닫힘, 에러 없이 닫힘, 열린 채 벙어리. 그리고 **2번과 3번이
/// 차례로 빠져 있던 적이 있고**, 실기기에서 "위치 갱신 버튼은 되는데 화면은
/// 안 움직인다"로 나타났다.
///
/// 셋 다 화면에는 오류를 남기지 않는다. 좌표가 그냥 안 올 뿐이다. 그래서
/// 여기서 셋을 각각 못 박는다.
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:navigation_client/service_locator.dart';
import 'package:navigation_client/screens/outdoor_map/gps/gps_freshness_policy.dart';
import 'package:navigation_client/screens/outdoor_map/gps/gps_session.dart';

Position _fix({double lat = 37.5665, double lng = 126.98}) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: DateTime(2024, 1, 1),
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

/// 세션 하나와 그 관찰값을 한 묶음으로 만든다.
({
  GpsSession session,
  _FakeStreams streams,
  List<bool> deliveries,
  List<String> events,
})
_harness({bool Function()? isActive, GpsPositionRequester? requestPosition}) {
  final streams = _FakeStreams();
  final deliveries = <bool>[];
  final events = <String>[];
  watchPosition = streams.open;
  final session = GpsSession(
    onFix: (_, {bool fromStream = false}) => deliveries.add(fromStream),
    isActive: isActive ?? () => true,
    onStreamError: () => events.add('error'),
    // 수명 테스트에서 주기 감시가 실제 플랫폼 채널을 부르지 않게 한다. 직접
    // 조회 자체를 검증하는 테스트만 아래에서 완료되는 Future를 따로 넣는다.
    requestPosition: requestPosition ?? () => Completer<Position>().future,
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
  tearDown(() => watchPosition = original);

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
        async.elapse(streamFirstFixTimeout - const Duration(seconds: 1));
        expect(h.streams.openCount, 1);

        async.elapse(const Duration(seconds: 1) + streamRetryMinDelay);
        expect(h.streams.openCount, 2);
        h.session.stop();
      });
    });

    test('좌표가 한 건이라도 오면 벙어리 감시를 걷는다', () {
      fakeAsync((async) {
        final h = _harness();
        h.session.start();
        h.streams.latest.add(_fix());
        async.flushMicrotasks();

        async.elapse(streamFirstFixTimeout * 2);
        // 살아 있는 스트림을 벙어리로 오인해 끊으면 안 된다.
        expect(h.streams.openCount, 1);
        expect(h.deliveries, [true]);
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
        async.elapse(streamFirstFixTimeout + streamRetryMinDelay);
        expect(h.streams.openCount, 2);
        async.elapse(streamFirstFixTimeout + streamRetryMinDelay * 2);
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

  group('즉시 새 좌표 요청', () {
    test('진입 후보가 생기면 3초 감시를 기다리지 않고 직접 좌표를 배달한다', () async {
      var requests = 0;
      final h = _harness(
        requestPosition: () async {
          requests++;
          return _fix();
        },
      );

      await h.session.requestFreshFix();

      expect(requests, 1);
      expect(h.deliveries, [false]);
      h.session.stop();
    });

    test('직접 조회가 진행 중이면 요청을 겹쳐 보내지 않는다', () async {
      final completer = Completer<Position>();
      var requests = 0;
      final h = _harness(
        requestPosition: () {
          requests++;
          return completer.future;
        },
      );

      final first = h.session.requestFreshFix();
      final second = h.session.requestFreshFix();
      expect(requests, 1);

      completer.complete(_fix());
      await Future.wait([first, second]);
      expect(h.deliveries, [false]);
      h.session.stop();
    });

    test('추적이 꺼져 있으면 직접 조회하지 않는다', () async {
      var requests = 0;
      final h = _harness(
        isActive: () => false,
        requestPosition: () async {
          requests++;
          return _fix();
        },
      );

      await h.session.requestFreshFix();

      expect(requests, 0);
      expect(h.deliveries, isEmpty);
      h.session.stop();
    });
  });
}
