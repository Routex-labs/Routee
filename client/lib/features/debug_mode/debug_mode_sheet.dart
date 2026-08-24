import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'debug_mode_controller.dart';

/// 디버그 설정 시트. **유일한 진입점은 앱 메뉴(상단 바 햄버거 → 개발자 → 디버그
/// 설정)** 다.
///
/// 한동안은 지도 왼쪽 아래에 떠 있는 원형 벌레 아이콘 버튼(`DebugModeSettingsButton`)
/// 이 이 시트를 열었다. 일반 사용자에게 보일 이유가 없는 개발 도구가 메인 지도의
/// 자리를 차지했고, 야외에서는 실내 진입 오버레이 상태에 따라 나타났다 사라져
/// "어디서 켜는 건지" 자체가 상태에 얽혀 있었다. 메뉴 항목 하나로 옮기면 지도는
/// 운영 화면만 남고 진입 경로는 모드와 무관하게 고정된다.
///
/// 실제 PDR 버튼과 진단 레이어는 여기서 [DebugModeController.enabled]를 켰을
/// 때만 지도에 나타난다.
Future<void> showDebugModeSettingsSheet(
  BuildContext context,
  DebugModeController controller,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _DebugModeSettingsSheet(controller: controller),
  );
}

class _DebugModeSettingsSheet extends StatelessWidget {
  const _DebugModeSettingsSheet({required this.controller});

  final DebugModeController controller;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  contentPadding: EdgeInsets.symmetric(horizontal: 4),
                  leading: Icon(Icons.bug_report_outlined),
                  title: Text(
                    '디버그 모드',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text('PDR 측정 도구와 지도 진단 레이어를 별도로 표시합니다.'),
                ),
                SwitchListTile.adaptive(
                  key: const ValueKey('debug-mode-enabled'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: const Text('디버그 모드 사용'),
                  subtitle: const Text('끄면 PDR 제어와 모든 진단 표시가 숨겨집니다.'),
                  value: controller.enabled,
                  onChanged: (value) => unawaited(controller.setEnabled(value)),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  child: controller.enabled
                      ? _AdvancedDebugOptions(controller: controller)
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AdvancedDebugOptions extends StatelessWidget {
  const _AdvancedDebugOptions({required this.controller});

  final DebugModeController controller;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      key: const PageStorageKey('debug-mode-advanced-options'),
      initiallyExpanded: true,
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      childrenPadding: const EdgeInsets.only(left: 8, bottom: 8),
      title: const Text(
        '고급 표시 옵션',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: const Text('방위·노드·간선 및 PDR 경로별 표시를 선택합니다.'),
      children: [
        _DebugSwitch(
          key: const ValueKey('debug-show-cardinal-cross'),
          title: '전체 화면 방위 격자',
          subtitle: '지도 위에 얇은 N–S/E–W 십자선 표시',
          color: const Color(0xFFD32F2F),
          value: controller.showCardinalCross,
          onChanged: controller.setShowCardinalCross,
        ),
        const Divider(height: 20),
        _DebugSwitch(
          key: const ValueKey('debug-show-graph-nodes'),
          title: '지도 노드 점',
          subtitle: '노드 위치를 점으로 표시',
          value: controller.showGraphNodes,
          onChanged: controller.setShowGraphNodes,
        ),
        _DebugSwitch(
          key: const ValueKey('debug-show-graph-edges'),
          title: '지도 간선 선',
          subtitle: '간선 위치와 현재 매칭 간선을 표시',
          value: controller.showGraphEdges,
          onChanged: controller.setShowGraphEdges,
        ),
        const Divider(height: 20),
        _DebugSwitch(
          key: const ValueKey('debug-show-raw-pdr-path'),
          title: 'Raw 근접 경로',
          subtitle: '주황 점선 · 아직 확정되지 않은 preview 값',
          color: const Color(0xFFF57C00),
          value: controller.showRawPdrPath,
          onChanged: controller.setShowRawPdrPath,
        ),
        _DebugSwitch(
          key: const ValueKey('debug-show-confirmed-pdr-path'),
          title: '확정 PDR 경로',
          subtitle: '초록 실선 · PDR 자체 확정값',
          color: const Color(0xFF2E7D32),
          value: controller.showConfirmedPdrPath,
          onChanged: controller.setShowConfirmedPdrPath,
        ),
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
          _DebugSwitch(
            key: const ValueKey('debug-show-ronin-pdr-path'),
            title: 'RoNIN 보폭 경로',
            subtitle: '분홍 파선 · Android ML 자동보폭 실험값',
            color: const Color(0xFFD81B60),
            value: controller.showRoninPdrPath,
            onChanged: controller.setShowRoninPdrPath,
          ),
        _DebugSwitch(
          key: const ValueKey('debug-show-map-matched-pdr-path'),
          title: '지도 부착 경로',
          subtitle: '보라 실선=초록 확정 · 점선=주황 기반 임시 추적',
          color: const Color(0xFF7E57C2),
          value: controller.showMapMatchedPdrPath,
          onChanged: controller.setShowMapMatchedPdrPath,
        ),
        const Divider(height: 20),
        _HeadingOffsetKnob(controller: controller),
      ],
    );
  }
}

/// 실기기 앞에서 heading을 몇 도 더 돌릴지 맞추는 노브.
///
/// 자편각은 이미 상수로 들어가 있다(features/indoor_navigation/contract/
/// pdr_anchor.dart). 여기서 돌리는 값은 **그 위에 얹는 나머지**다. 값을 바꾸면
/// 지금 서 있는 anchor의 회전각이 바로 따라 돌아, 지도를 보며 맞출 수 있다.
class _HeadingOffsetKnob extends StatelessWidget {
  const _HeadingOffsetKnob({required this.controller});

  final DebugModeController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: controller.headingOffsetDeg,
      builder: (context, offset, _) {
        final label = '${offset > 0 ? '+' : ''}${offset.toStringAsFixed(0)}°';
        return Padding(
          padding: const EdgeInsets.only(left: 8, right: 8, bottom: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'heading 보정 노브',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('debug-heading-offset-minus'),
                    tooltip: '1도 반시계',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () =>
                        unawaited(controller.setHeadingOffsetDeg(offset - 1)),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(
                      label,
                      key: const ValueKey('debug-heading-offset-value'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('debug-heading-offset-plus'),
                    tooltip: '1도 시계',
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () =>
                        unawaited(controller.setHeadingOffsetDeg(offset + 1)),
                  ),
                ],
              ),
              Text(
                '자편각 위에 더 얹는 각도(시계방향 +). 세션 JSON에 함께 남는다.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Slider(
                key: const ValueKey('debug-heading-offset-slider'),
                min: -DebugModeController.headingOffsetLimitDeg,
                max: DebugModeController.headingOffsetLimitDeg,
                divisions: (DebugModeController.headingOffsetLimitDeg * 2)
                    .round(),
                value: offset,
                label: label,
                onChanged: (next) =>
                    unawaited(controller.setHeadingOffsetDeg(next)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DebugSwitch extends StatelessWidget {
  const _DebugSwitch({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.color,
  });

  final String title;
  final String subtitle;
  final bool value;
  final Future<void> Function(bool) onChanged;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 8),
      secondary: color == null
          ? null
          : Container(
              width: 22,
              height: 5,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: (next) => unawaited(onChanged(next)),
    );
  }
}
