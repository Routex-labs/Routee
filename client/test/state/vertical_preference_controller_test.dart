import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/route/vertical_preference.dart';
import 'package:navigation_client/state/vertical_preference_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 수직 이동 선호가 앱을 다시 켜도 남는지, 그리고 저장이 안 되는 환경에서도
/// 길찾기가 그대로 동작하는지 고정한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<VerticalPreferenceController> createController() async {
    final controller = VerticalPreferenceController(
      prefs: await SharedPreferences.getInstance(),
    );
    await controller.ready;
    return controller;
  }

  test('첫 실행은 자동이다 — 이 기능이 없던 시절과 같은 화면', () async {
    final controller = await createController();

    expect(controller.value, VerticalPreference.auto);
    expect(controller.isLoaded, isTrue);
  });

  test('고른 값이 다음 실행에서 되살아난다', () async {
    final controller = await createController();
    await controller.set(VerticalPreference.elevator);

    // 같은 저장소를 보는 새 컨트롤러 = 앱 재실행.
    final reopened = await createController();
    expect(reopened.value, VerticalPreference.elevator);
  });

  test('바뀔 때만 알린다 — 같은 칸을 두 번 눌러 경로가 두 번 계산되면 안 된다', () async {
    final controller = await createController();
    var notifications = 0;
    controller.addListener(() => notifications++);

    await controller.set(VerticalPreference.escalator);
    await controller.set(VerticalPreference.escalator);

    expect(notifications, 1);
    expect(controller.value, VerticalPreference.escalator);
  });

  test('저장된 값이 손상돼 있어도 자동으로 시작한다', () async {
    SharedPreferences.setMockInitialValues({
      'vertical_preference_v1': 'moving-walkway',
    });
    final controller = await createController();

    expect(controller.value, VerticalPreference.auto);
  });
}
