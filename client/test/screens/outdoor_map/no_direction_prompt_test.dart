import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 「바라보는 방향 맞추기」 모달이 **되살아나지 않는지** 지킨다.
///
/// 아무 조작 없이 튀어나오는 창이었고, 화면 위/오른쪽 같은 보기로 실제 방위를
/// 고르게 하는 것이라 사용자가 답을 알기도 어려웠다. 지금은 묻는 대신 자동
/// 진입과 같은 추정으로 채운다(`parts/pdr.dart`의 `_confirmPdrAnchor`).
///
/// **화면을 띄워 확인할 수 없는 종류의 회귀다** — 이 모달은 heading frame이
/// 자북이 아닌 기기에서만 떠서, 위젯 테스트의 가짜 센서로는 그 조건을 만들 수
/// 없다. 그래서 소스에 그 호출이 없다는 것으로 대신 못 박는다.
void main() {
  test('방향을 묻는 모달을 띄우지 않는다', () {
    final source = File(
      'lib/screens/outdoor_map/parts/pdr.dart',
    ).readAsStringSync();
    expect(
      source.contains('_askScreenDirection'),
      isFalse,
      reason: '방향 묻는 모달이 돌아왔다. 되살릴 거면 이 테스트의 근거부터 다시 쓴다.',
    );
    expect(
      source.contains('AlertDialog'),
      isFalse,
      reason: '위치 지정 경로에 모달이 생겼다. 이 화면은 묻지 않는 것이 규칙이다.',
    );
  });

  test('방향을 못 정하면 앵커를 확정하지 않는다', () {
    // 지어낸 각도로 확정하면 궤적이 통째로 돌아간다. 추정이 실패했을 때는
    // 위치가 안 잡힌 상태로 두고 사용자가 다시 찍게 한다.
    final source = File(
      'lib/screens/outdoor_map/parts/pdr.dart',
    ).readAsStringSync();
    expect(
      source.contains('방향을 잡지 못했습니다'),
      isTrue,
      reason: '추정 실패 갈래가 사라졌다 — 방향 없이 확정하고 있지 않은지 본다.',
    );
  });
}
