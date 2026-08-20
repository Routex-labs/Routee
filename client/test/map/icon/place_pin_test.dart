import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/map/icon/place_pin.dart';

/// 출구 핀 비트맵이 **실제로 서로 다른 그림인지**를 본다.
///
/// 눈으로만 확인하면 놓치는 회귀가 둘 있다 — 방위마다 다른 이름으로 등록하는데
/// 그림이 같으면 모든 문에 같은 글자가 찍힌다. addImage 이름은 멀쩡해서
/// 로그로는 드러나지 않는다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // **번들 글꼴을 직접 올린다.** 테스트 바인딩은 기본 글꼴이 모든 글리프를 같은
  // 상자로 그려서, 이걸 안 하면 `남`과 `북`이 같은 바이트로 나오고 아래 두
  // 번째 테스트가 항상 실패한다. 실패가 아니라 **환경 때문에 못 재는 것**이라,
  // 재려면 앱이 쓰는 그 글꼴을 그대로 올려야 한다(destination_pin.dart의 두부
  // 상자 함정과 같은 뿌리다).
  setUpAll(() async {
    final loader = FontLoader('Pretendard')
      ..addFont(
        File(
          'assets/fonts/Pretendard-ExtraBold.otf',
        ).readAsBytes().then((bytes) => ByteData.view(bytes.buffer)),
      );
    await loader.load();
  });

  group('place_pin', () {
    test('방위가 다르면 다른 그림이다', () async {
      final south = await renderGatePinIcon('남');
      final north = await renderGatePinIcon('북');
      final southEast = await renderGatePinIcon('남동');

      expect(south, isNot(equals(north)));
      expect(south, isNot(equals(southEast)));
      expect(north, isNot(equals(southEast)));
    });

    test('같은 방위는 같은 그림이다 — 캐시 키가 이름 하나인 근거', () async {
      final a = await renderGatePinIcon('남');
      final b = await renderGatePinIcon('남');
      expect(a, equals(b));
    });

    test('두 글자 방위도 굽힌다 — 글자 크기 분기가 죽지 않았는지', () async {
      for (final direction in ['북', '북동', '동', '남동', '남', '남서', '서', '북서']) {
        expect(await renderGatePinIcon(direction), isNotEmpty);
      }
    });
  });
}
