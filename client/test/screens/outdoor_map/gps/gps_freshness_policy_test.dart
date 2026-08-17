import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/screens/outdoor_map/gps/gps_freshness_policy.dart';

void main() {
  final now = DateTime.utc(2026, 8, 13, 13, 41);

  group('shouldRequestFreshFix', () {
    test('아직 한 건도 못 받았으면 즉시 요청한다', () {
      expect(
        shouldRequestFreshFix(
          lastFixReceivedAt: null,
          now: now,
          requestInFlight: false,
        ),
        isTrue,
      );
    });

    test('요청이 떠 있으면 겹쳐 쏘지 않는다', () {
      expect(
        shouldRequestFreshFix(
          lastFixReceivedAt: null,
          now: now,
          requestInFlight: true,
        ),
        isFalse,
      );
    });

    test('스트림이 1초마다 주는 기기에서는 발화하지 않는다', () {
      // 이게 깨지면 정상 기기에서까지 배터리를 태운다.
      expect(
        shouldRequestFreshFix(
          lastFixReceivedAt: now.subtract(const Duration(seconds: 1)),
          now: now,
          requestInFlight: false,
        ),
        isFalse,
      );
    });

    test('실측에서 관측된 15~36초 공백은 반드시 잡는다', () {
      for (final gap in [15.5, 23.3, 36.2, 36.4]) {
        expect(
          shouldRequestFreshFix(
            lastFixReceivedAt: now.subtract(
              Duration(milliseconds: (gap * 1000).round()),
            ),
            now: now,
            requestInFlight: false,
          ),
          isTrue,
          reason: '$gap초 공백이 안 잡혔다',
        );
      }
    });

    test('경계(3초)에서는 요청한다', () {
      expect(
        shouldRequestFreshFix(
          lastFixReceivedAt: now.subtract(gpsFixMaxAge),
          now: now,
          requestInFlight: false,
        ),
        isTrue,
      );
    });
  });

  group('streamSilenceTimeout', () {
    test('실측에서 기기가 좌표를 만든 최대 간격보다 넉넉히 길다', () {
      // 이 값이 짧으면 **느릴 뿐 살아 있는 스트림**을 끊는다. 그러면 재등록이
      // 겹치며 오히려 더 느려진다. 실기기(더현대 앞, 2026-08-13)에서 일회성
      // 조회가 좌표를 받아 낸 간격의 최댓값이 9.0초였다.
      expect(streamSilenceTimeout, greaterThan(const Duration(seconds: 9)));
    });

    test('시작 직후 벙어리 구간이 하염없이 길지는 않다', () {
      // 그동안 화면은 일회성 조회가 떠받치지만, 스트림 없이 오래 가면 그만큼
      // 배터리를 일회성 조회로 태운다.
      expect(streamSilenceTimeout, lessThanOrEqualTo(const Duration(seconds: 20)));
    });
  });

  group('nextStreamRetryDelay', () {
    test('실패가 이어지면 간격이 배로 늘어난다', () {
      expect(nextStreamRetryDelay(streamRetryMinDelay), const Duration(seconds: 4));
      expect(nextStreamRetryDelay(const Duration(seconds: 4)), const Duration(seconds: 8));
    });

    test('상한에서 멈춘다', () {
      // 상한이 없으면 잠깐 끊겼다 돌아오는 기기에서 간격이 분 단위로 벌어져,
      // 신호가 멀쩡해진 뒤에도 화면이 한참 멈춰 있다.
      expect(nextStreamRetryDelay(const Duration(seconds: 20)), streamRetryMaxDelay);
      expect(nextStreamRetryDelay(streamRetryMaxDelay), streamRetryMaxDelay);
    });

    test('첫 간격은 화면이 멈춘 티가 안 날 만큼 짧다', () {
      // 스트림은 순간적으로 닫혔다 돌아오는 경우가 대부분이다. 첫 대기가 길면
      // 그 흔한 경우에서 매번 화면이 멈춘다.
      expect(streamRetryMinDelay, lessThanOrEqualTo(const Duration(seconds: 3)));
    });
  });
}
