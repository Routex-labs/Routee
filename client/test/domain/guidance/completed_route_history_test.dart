import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/domain/guidance/completed_route_history.dart';

void main() {
  const a = LatLng(37.0, 127.0);
  const b = LatLng(37.0, 127.0001);
  const c = LatLng(37.0, 127.0002);

  test('같은 층에서 이어지는 완료 구간은 하나의 회색선으로 합친다', () {
    final history = CompletedRouteHistory();

    history.append(scopeId: '1F', points: const [a, b]);
    history.append(scopeId: '1F', points: const [b, c]);

    expect(history.segmentsFor('1F'), const [
      <LatLng>[a, b, c],
    ]);
  });

  test('서로 다른 층과 멀리 떨어진 재탐색 구간은 직선으로 잇지 않는다', () {
    final history = CompletedRouteHistory();
    const far = LatLng(37.001, 127.001);
    const farEnd = LatLng(37.001, 127.0011);

    history.append(scopeId: '1F', points: const [a, b]);
    history.append(scopeId: '2F', points: const [a, c]);
    history.append(scopeId: '1F', points: const [far, farEnd]);

    expect(history.segmentsFor('1F'), hasLength(2));
    expect(history.segmentsFor('2F'), const [
      <LatLng>[a, c],
    ]);
  });

  test('반환된 선을 바꿔도 저장된 이력은 바뀌지 않는다', () {
    final history = CompletedRouteHistory();
    history.append(
      scopeId: CompletedRouteHistory.outdoorScope,
      points: const [a, b],
    );

    final copy = history.segmentsFor(CompletedRouteHistory.outdoorScope);
    expect(() => copy.first.add(c), throwsUnsupportedError);

    expect(history.segmentsFor(CompletedRouteHistory.outdoorScope), const [
      <LatLng>[a, b],
    ]);
  });

  group('advance — 회색선은 앞으로만 자란다', () {
    // 확정 위치가 뒤로 튀거나 경로를 벗어나 진행률이 잠깐 사라지면, 그 틱의
    // 완료 구간이 짧아지거나 비어 버린다. 그대로 그리면 지나온 길이 사라지고
    // 마커만 떠 있는 화면이 된다.

    test('짧아진 완료 구간은 직전 값을 유지한다', () {
      final history = CompletedRouteHistory();

      expect(
        history.advance(
          scopeId: '1F',
          generation: 1,
          completed: const [a, b, c],
        ),
        const [a, b, c],
      );
      expect(
        history.advance(scopeId: '1F', generation: 1, completed: const [a, b]),
        const [a, b, c],
      );
    });

    test('진행률이 사라진 틱에도 지나온 길은 남는다', () {
      final history = CompletedRouteHistory();
      history.advance(scopeId: '1F', generation: 1, completed: const [a, b, c]);

      expect(
        history.advance(scopeId: '1F', generation: 1, completed: const []),
        const [a, b, c],
      );
    });

    test('층마다 따로 센다', () {
      final history = CompletedRouteHistory();
      history.advance(scopeId: '1F', generation: 1, completed: const [a, b, c]);

      expect(
        history.advance(scopeId: '2F', generation: 1, completed: const [a, b]),
        const [a, b],
      );
    });

    test('세대가 바뀌면 수위를 버린다', () {
      // 새 경로는 지나온 구간도 새로 센다. 옛 구간은 그때 append로 넘어간다 —
      // 안 버리면 재탐색 직후 새 경로 위에 옛 회색선이 그대로 붙어 있다.
      final history = CompletedRouteHistory();
      history.advance(scopeId: '1F', generation: 1, completed: const [a, b, c]);

      expect(
        history.advance(scopeId: '1F', generation: 2, completed: const [a, b]),
        const [a, b],
      );
    });

    test('clear는 수위까지 지운다', () {
      final history = CompletedRouteHistory();
      history.advance(scopeId: '1F', generation: 1, completed: const [a, b, c]);
      history.clear();

      expect(
        history.advance(scopeId: '1F', generation: 1, completed: const []),
        isEmpty,
      );
    });
  });
}
