import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/route/vertical_preference.dart';

/// 층 간 길찾기에서 무엇을 타고 싶은지([VerticalPreference])를 보관·영속화한다.
///
/// 앱을 다시 켜도 남아야 하는 **사용자 선택**이라 이 계층에 둔다(`README.md`의
/// "새 전역 상태를 추가할 때"). 저장 방식은 다른 컨트롤러와 같은
/// `SharedPreferences` 한 칸이며, 목록이 아니라 값 하나라 JSON을 쓰지 않는다.
///
/// **실패해도 조용히 degrade한다** — 읽기·쓰기가 실패하면 [VerticalPreference.auto]
/// 로 동작한다. 그 값이 곧 이 기능이 없던 시절의 동작이라 사용자가 잃는 것이 없다.
class VerticalPreferenceController extends ChangeNotifier {
  // ignore: prefer_initializing_formals -- _prefs는 lazy-init으로 채워야 해서 mutable이어야 함.
  VerticalPreferenceController({SharedPreferences? prefs}) : _prefs = prefs {
    _loadFuture = _load();
  }

  /// 저장 포맷이 바뀌면 키에 붙은 버전을 올려 예전 값과 섞이지 않게 한다.
  static const _storageKey = 'vertical_preference_v1';

  SharedPreferences? _prefs;
  late final Future<void> _loadFuture;
  VerticalPreference _value = VerticalPreference.auto;
  bool _loaded = false;
  bool _disposed = false;

  /// 지금 선호. 로드 전이거나 저장소가 실패하면 [VerticalPreference.auto]다.
  VerticalPreference get value => _value;

  /// 최초 로드가 끝났는지. 로드 전의 `auto`를 "사용자가 자동을 골랐다"로
  /// 오해하지 않으려면 이 값을 함께 본다.
  bool get isLoaded => _loaded;

  /// 최초 로드 완료를 기다리는 future. 테스트가 로드 시점을 고정할 때 쓴다.
  Future<void> get ready => _loadFuture;

  Future<void> _load() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      _value = VerticalPreference.fromWireValue(_prefs!.getString(_storageKey));
    } on Object {
      _value = VerticalPreference.auto;
    } finally {
      _loaded = true;
      _notify();
    }
  }

  /// 선호를 바꾼다. 같은 값이면 아무것도 하지 않는다 — 듣는 쪽이 경로를 다시
  /// 계산하므로, 안 거르면 같은 칸을 두 번 눌렀을 때 계산이 한 번 더 돈다.
  Future<void> set(VerticalPreference preference) async {
    // **로드가 끝났으면 기다리지 않는다.** 이미 완료된 future라도 await하면
    // 한 틱을 넘기는데, 그 future는 화면이 서기 전에 만들어진 것이라
    // `testWidgets`의 가짜 시계 안에서는 깨어나지 않는다
    // ([RecentRoutePointsController.add]가 같은 이유로 같은 가드를 쓴다).
    if (!_loaded) await _loadFuture;
    if (_value == preference) return;
    _value = preference;
    _notify();
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setString(_storageKey, preference.wireValue);
    } on Object {
      // 쓰기 실패가 이번 세션의 선택까지 되돌리지는 않는다. 메모리 값은 그대로
      // 두고, 다음 실행에서 저장된(=예전) 값으로 돌아가게 둔다.
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
