import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 내비게이션 앱의 진단 기능을 한곳에서 관리하는 설정 컨트롤러.
///
/// 제품 UI는 [enabled]만 확인하면 PDR 진입점을 완전히 숨길 수 있고, 지도
/// 렌더러는 나머지 플래그만 받아서 각 진단 레이어를 독립적으로 켜고 끈다.
/// 설정은 앱 재실행 뒤에도 같은 테스트 구성을 이어갈 수 있도록 로컬에 저장한다.
class DebugModeController extends ChangeNotifier {
  factory DebugModeController({SharedPreferences? preferences}) =>
      DebugModeController._(preferences);

  DebugModeController._(SharedPreferences? preferences)
    : _preferences = preferences,
      _hasInjectedPreferences = preferences != null {
    _loadFuture = _load();
  }

  static const _enabledKey = 'debug_mode.enabled';
  static const _showGraphNodesKey = 'debug_mode.show_graph_nodes';
  static const _showGraphEdgesKey = 'debug_mode.show_graph_edges';
  static const _showRawPdrPathKey = 'debug_mode.show_raw_pdr_path';
  static const _showConfirmedPdrPathKey = 'debug_mode.show_confirmed_pdr_path';
  static const _showMapMatchedPdrPathKey =
      'debug_mode.show_map_matched_pdr_path';
  static const _showRoninPdrPathKey = 'debug_mode.show_ronin_pdr_path';
  static const _showCardinalCrossKey = 'debug_mode.show_cardinal_cross';
  static const _headingOffsetKey = 'debug_mode.heading_offset_deg';

  /// 현장에서 돌리는 heading 보정 노브(도, 시계방향 +).
  ///
  /// 자편각 상수(features/indoor_navigation/contract/pdr_anchor.dart)로 다
  /// 안 맞는 나머지 — 층 좌표 축 피팅 오차나 기기별 자기 편향 — 를 실기기 앞에서
  /// 맞춰 보는 값이다. **디버그 모드 전용**이라 일반 사용자에게는 적용되지 않고,
  /// 맞춘 값은 PDR 세션 JSON의 anchor 블록에 함께 기록된다.
  static const headingOffsetLimitDeg = 45.0;

  SharedPreferences? _preferences;
  final bool _hasInjectedPreferences;
  late final Future<void> _loadFuture;
  bool _disposed = false;
  bool _isLoaded = false;
  bool _enabled = false;
  bool _showGraphNodes = true;
  bool _showGraphEdges = true;
  bool _showRawPdrPath = true;
  bool _showConfirmedPdrPath = true;
  bool _showMapMatchedPdrPath = true;
  bool _showRoninPdrPath = true;
  bool _showCardinalCross = true;

  double _headingOffsetRawDeg = 0;

  /// **실제로 적용되는** 보정각. 컨트롤러 전체를 다시 그리지 않고 이 값만 듣는
  /// 쪽(PDR 드라이버)이 있어 별도 notifier로 노출한다.
  ///
  /// 디버그 모드를 끄면 저장된 값은 남기고 0을 흘린다 — 일반 사용자에게는
  /// 자편각 상수만 적용돼야 하기 때문이다.
  final ValueNotifier<double> headingOffsetDeg = ValueNotifier<double>(0);

  bool get isLoaded => _isLoaded;
  Future<void> get ready => _loadFuture;
  bool get enabled => _enabled;
  bool get showGraphNodes => _showGraphNodes;
  bool get showGraphEdges => _showGraphEdges;
  bool get showRawPdrPath => _showRawPdrPath;
  bool get showConfirmedPdrPath => _showConfirmedPdrPath;
  bool get showMapMatchedPdrPath => _showMapMatchedPdrPath;
  bool get showRoninPdrPath => _showRoninPdrPath;
  bool get showCardinalCross => _showCardinalCross;

  Future<void> _load() async {
    try {
      _preferences ??= await SharedPreferences.getInstance();
      final preferences = _preferences!;
      _enabled = preferences.getBool(_enabledKey) ?? false;
      _showGraphNodes = preferences.getBool(_showGraphNodesKey) ?? true;
      _showGraphEdges = preferences.getBool(_showGraphEdgesKey) ?? true;
      _showRawPdrPath = preferences.getBool(_showRawPdrPathKey) ?? true;
      _showConfirmedPdrPath =
          preferences.getBool(_showConfirmedPdrPathKey) ?? true;
      _showMapMatchedPdrPath =
          preferences.getBool(_showMapMatchedPdrPathKey) ?? true;
      _showRoninPdrPath = preferences.getBool(_showRoninPdrPathKey) ?? true;
      _showCardinalCross = preferences.getBool(_showCardinalCrossKey) ?? true;
      _headingOffsetRawDeg = _clampHeadingOffset(
        preferences.getDouble(_headingOffsetKey) ?? 0,
      );
    } on Object {
      // 플랫폼 저장소가 없는 테스트/개발 환경에서는 기본값으로 동작한다.
    } finally {
      _syncHeadingOffset();
      _isLoaded = true;
      if (!_disposed) notifyListeners();
    }
  }

  /// 저장소에서 설정을 다시 읽는다.
  ///
  /// 앱 실행 중에는 쓸 일이 없다 — 설정 변경은 [setEnabled] 등이 메모리와
  /// 저장소를 함께 갱신하기 때문이다. 필요한 쪽은 테스트다. 이 컨트롤러는
  /// service_locator의 전역이라 한 테스트 파일의 모든 테스트가 같은 인스턴스를
  /// 공유하는데, 로드는 생성자에서 한 번만 일어난다. 그래서 SharedPreferences
  /// mock을 갈아끼워도 **가장 먼저 컨트롤러를 건드린 테스트가 읽은 값이 그대로
  /// 남아**, 뒤 테스트가 디버그 모드를 켜도 UI에 반영되지 않는다.
  ///
  /// 생성자로 [SharedPreferences]를 직접 주입받은 경우에는 그 인스턴스를
  /// 그대로 쓰고, 아니면 캐시를 버려 새로 받아온다 —
  /// `setMockInitialValues`가 저장소와 함께 getInstance 캐시도 리셋하므로,
  /// 캐시를 버려야 새 mock 값이 보인다.
  Future<void> reload() {
    if (!_hasInjectedPreferences) _preferences = null;
    return _load();
  }

  Future<void> setEnabled(bool value) async {
    await _setBool(
      _enabledKey,
      value,
      () => _enabled,
      (next) => _enabled = next,
    );
    _syncHeadingOffset();
  }

  Future<void> setShowGraphNodes(bool value) => _setBool(
    _showGraphNodesKey,
    value,
    () => _showGraphNodes,
    (next) => _showGraphNodes = next,
  );

  Future<void> setShowGraphEdges(bool value) => _setBool(
    _showGraphEdgesKey,
    value,
    () => _showGraphEdges,
    (next) => _showGraphEdges = next,
  );

  Future<void> setShowRawPdrPath(bool value) => _setBool(
    _showRawPdrPathKey,
    value,
    () => _showRawPdrPath,
    (next) => _showRawPdrPath = next,
  );

  Future<void> setShowConfirmedPdrPath(bool value) => _setBool(
    _showConfirmedPdrPathKey,
    value,
    () => _showConfirmedPdrPath,
    (next) => _showConfirmedPdrPath = next,
  );

  Future<void> setShowMapMatchedPdrPath(bool value) => _setBool(
    _showMapMatchedPdrPathKey,
    value,
    () => _showMapMatchedPdrPath,
    (next) => _showMapMatchedPdrPath = next,
  );

  Future<void> setShowRoninPdrPath(bool value) => _setBool(
    _showRoninPdrPathKey,
    value,
    () => _showRoninPdrPath,
    (next) => _showRoninPdrPath = next,
  );

  Future<void> setShowCardinalCross(bool value) => _setBool(
    _showCardinalCrossKey,
    value,
    () => _showCardinalCross,
    (next) => _showCardinalCross = next,
  );

  /// 노브를 [headingOffsetLimitDeg] 안으로 자르고 저장한다.
  ///
  /// 디버그 모드를 꺼도 값은 남는다 — 실제 적용 여부는 드라이버에 이 notifier를
  /// 연결하는 조립 루트가 정한다.
  Future<void> setHeadingOffsetDeg(double value) async {
    final next = _clampHeadingOffset(value);
    if (_headingOffsetRawDeg == next) return;
    _headingOffsetRawDeg = next;
    _syncHeadingOffset();
    if (!_disposed) notifyListeners();
    try {
      _preferences ??= await SharedPreferences.getInstance();
      await _preferences!.setDouble(_headingOffsetKey, next);
    } on Object {
      // _setBool과 같은 이유로 영속화 실패는 삼킨다.
    }
  }

  void _syncHeadingOffset() =>
      headingOffsetDeg.value = _enabled ? _headingOffsetRawDeg : 0;

  static double _clampHeadingOffset(double value) => value.isFinite
      ? value.clamp(-headingOffsetLimitDeg, headingOffsetLimitDeg)
      : 0;

  Future<void> _setBool(
    String key,
    bool value,
    bool Function() read,
    ValueChanged<bool> write,
  ) async {
    if (read() == value) return;
    write(value);
    if (!_disposed) notifyListeners();
    try {
      _preferences ??= await SharedPreferences.getInstance();
      await _preferences!.setBool(key, value);
    } on Object {
      // 영속화 실패가 지도/PDR 테스트 자체를 막아서는 안 된다. 현재 세션의
      // 설정은 유지하고 다음 실행에서 기본값으로 돌아가도록 둔다.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    headingOffsetDeg.dispose();
    super.dispose();
  }
}
