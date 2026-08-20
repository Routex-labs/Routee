import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/routing/place_link.dart';
import 'package:navigation_client/routing/place_link_inbox.dart';

/// 링크가 화면에 닿기까지의 보관함.
///
/// 여기서 틀리면 두 방향으로 손해다 — 중복을 안 거르면 같은 시트가 두 번 열리고,
/// 화면이 세워지기 전에 온 링크를 버리면 사용자는 링크를 눌렀는데 지도만 본다.
void main() {
  const origin = 'https://example.test';
  late PlaceLinkInbox inbox;

  setUp(() => inbox = PlaceLinkInbox(origin: origin));
  tearDown(() => inbox.dispose());

  test('우리 링크를 받아 둔다', () {
    inbox.offer(Uri.parse('$origin/place/thehyundai-seoul/PO-1'));

    expect(
      inbox.value,
      const PlaceLink(buildingId: 'thehyundai-seoul', placeId: 'PO-1'),
    );
  });

  test('가져가면 비고, 다음 링크를 받을 수 있다', () {
    inbox.offer(Uri.parse('$origin/place/b/p1'));
    inbox.take();
    expect(inbox.value, isNull);

    inbox.offer(Uri.parse('$origin/place/b/p2'));

    expect(inbox.value, const PlaceLink(buildingId: 'b', placeId: 'p2'));
  });

  // 최초 URI와 stream이 같은 링크를 함께 흘리는 경우가 있다. 거르지 않으면 시트가
  // 두 번 열린다.
  test('같은 URI가 연달아 오면 한 번만 받는다', () {
    var notified = 0;
    inbox.addListener(() => notified++);

    final uri = Uri.parse('$origin/place/b/p');
    inbox
      ..offer(uri)
      ..offer(uri);

    expect(notified, 1);
  });

  // **중복 거르기에는 시간이 붙어 있어야 한다.** URI만으로 거르면, 시트를 닫은
  // 사용자가 메신저로 돌아가 같은 링크를 다시 눌렀을 때 앱만 앞으로 오고 시트도
  // 실패 안내도 뜨지 않는다 — 그 사람에게는 링크가 고장 난 것으로 보인다.
  test('시간이 지난 뒤 같은 URI를 다시 누르면 또 받는다', () {
    var clock = DateTime(2026, 8, 17, 10);
    final timed = PlaceLinkInbox(origin: origin, now: () => clock);
    addTearDown(timed.dispose);

    final uri = Uri.parse('$origin/place/b/p');
    timed.offer(uri);
    timed.take();

    clock = clock.add(const Duration(seconds: 5));
    timed.offer(uri);

    expect(timed.value, const PlaceLink(buildingId: 'b', placeId: 'p'));
  });

  // 같은 창 안에서는 여전히 한 번이다. cold start의 최초 URI와 stream이 프레임
  // 몇 개 사이로 같은 링크를 흘리는 그 한 벌이 막으려는 것이다.
  test('창 안에서 다시 오면 여전히 한 번만 받는다', () {
    var clock = DateTime(2026, 8, 17, 10);
    final timed = PlaceLinkInbox(origin: origin, now: () => clock);
    addTearDown(timed.dispose);

    var notified = 0;
    timed.addListener(() => notified++);

    final uri = Uri.parse('$origin/place/b/p');
    timed.offer(uri);
    clock = clock.add(const Duration(milliseconds: 200));
    timed.offer(uri);

    expect(notified, 1);
  });

  test('우리 링크가 아니면 들고 있던 것을 지우지 않는다', () {
    inbox.offer(Uri.parse('$origin/place/b/p'));

    inbox.offer(Uri.parse('https://evil.test/place/x/y'));

    expect(inbox.value, const PlaceLink(buildingId: 'b', placeId: 'p'));
  });

  // 이 앱은 컴파일 타임 origin으로 링크를 읽는다. 그 값이 없는 빌드에서는 어떤
  // 링크도 우리 것이 아니고, 공유 버튼도 뜨지 않는다.
  test('origin이 없으면 아무 링크도 받지 않는다', () {
    final closed = PlaceLinkInbox(origin: '');
    addTearDown(closed.dispose);

    closed.offer(Uri.parse('$origin/place/b/p'));

    expect(closed.value, isNull);
  });
}
