/// 건물에 들어온 것은 GPS가 알지만 **몇 층인지는 모른다.** 그 한 가지를 묻는 화면.
///
/// 안 물으면 층이 조용히 `default_floor`(1F)로 굳는다 — 사용자는 B2에 서 있는데
/// 위치도 경로도 1층에 찍힌다. 검증 기준은
/// `client/test/screens/outdoor_map/entry_floor_prompt_test.dart`.
library;

import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

/// 층을 고르게 하고 고른 층을 돌려준다.
///
/// 이 질문은 건물 안에서 앱을 처음 켠 사람이 지금 어느 건물에 있는지와 층을
/// 함께 확인하는 전면 단계다. route는 지도 lifecycle을 유지하도록 투명하게
/// 남기되, 전환 배경과 화면 본문은 항상 불투명하게 칠해 아래 지도가 보이지 않는다.
Future<String?> showEntryFloorPrompt(
  BuildContext context, {
  required String buildingName,
  required String? buildingAddress,
  required List<String> floors,
  required String fallbackFloor,
}) {
  return Navigator.of(context).push<String>(
    PageRouteBuilder<String>(
      opaque: false,
      barrierDismissible: false,
      transitionDuration: RoutexMotion.transition,
      reverseTransitionDuration: RoutexMotion.transition,
      pageBuilder: (_, _, _) => EntryFloorPrompt(
        buildingName: buildingName,
        buildingAddress: buildingAddress,
        floors: floors,
        fallbackFloor: fallbackFloor,
      ),
      transitionsBuilder: (context, animation, _, child) => ColoredBox(
        key: const Key('entry-floor-transition-background'),
        color: context.routexColors.surfaceBase,
        child: FadeTransition(opacity: animation, child: child),
      ),
    ),
  );
}

/// [showEntryFloorPrompt]가 띄우는 화면. 라우트 없이도 시험할 수 있게 분리한다.
class EntryFloorPrompt extends StatefulWidget {
  const EntryFloorPrompt({
    super.key,
    required this.buildingName,
    required this.buildingAddress,
    required this.floors,
    required this.fallbackFloor,
  });

  final String buildingName;

  /// 주소가 없는 건물은 억지로 추측하지 않는다. 이름 아래 줄도 함께 뺀다.
  final String? buildingAddress;

  /// 엘리베이터 버튼판 순서(위층 → 아래층) 그대로다. 여기서 다시 정렬하지
  /// 않는다 — 층 선택기와 순서가 다르면 같은 건물이 화면마다 다르게 보인다.
  final List<String> floors;

  /// 층을 모를 때도 어느 층 지도로 이어지는지 감추지 않는다. 이 값은 출입구
  /// 근거 또는 건물의 기본 층으로, 호출자가 이미 고른 안전한 기본값이다.
  final String fallbackFloor;

  @override
  State<EntryFloorPrompt> createState() => _EntryFloorPromptState();
}

class _EntryFloorPromptState extends State<EntryFloorPrompt> {
  String? _selectedFloor;

  @override
  Widget build(BuildContext context) {
    final colors = context.routexColors;
    final address = widget.buildingAddress;
    // **Scaffold를 쓰지 않는다.** ScaffoldMessenger는 가장 나중에 등록된
    // Scaffold에 스낵바를 옮겨 붙인다 — 실내 위치를 잡느라 띄운 '건물 감지 중...'이
    // 이 화면 하단으로 따라 올라와 "나중에 고르기"를 덮었다.
    return Material(
      color: colors.surfaceBase,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: RoutexSpacing.sectionGap,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 36),
              Text(
                '현재 계신 건물',
                textAlign: TextAlign.center,
                style: RoutexTypography.caption.copyWith(
                  color: colors.contentSecondary,
                ),
              ),
              const SizedBox(height: RoutexSpacing.controlGap),
              Text(
                widget.buildingName,
                textAlign: TextAlign.center,
                style: RoutexTypography.display.copyWith(
                  color: colors.contentPrimary,
                ),
              ),
              if (address != null) ...[
                const SizedBox(height: RoutexSpacing.inlineGap),
                Text(
                  address,
                  textAlign: TextAlign.center,
                  style: RoutexTypography.bodySmall.copyWith(
                    color: colors.contentSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 44),
              Text(
                '어느 층에 계신가요?',
                textAlign: TextAlign.center,
                style: RoutexTypography.headline.copyWith(
                  color: colors.contentPrimary,
                ),
              ),
              const SizedBox(height: RoutexSpacing.sectionGap),
              Expanded(
                child: GridView.builder(
                  itemCount: widget.floors.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: RoutexSpacing.contentGap,
                    mainAxisSpacing: RoutexSpacing.contentGap,
                    // 층 수가 많은 건물도 한 화면에서 훑을 수 있도록 48dp보다
                    // 큰 최소 터치 높이만 남기고, 버튼을 세로로 과하게 키우지
                    // 않는다.
                    childAspectRatio: 1.65,
                  ),
                  itemBuilder: (_, index) {
                    final floor = widget.floors[index];
                    return _EntryFloorTile(
                      key: ValueKey('entry-floor-$floor'),
                      floor: floor,
                      selected: floor == _selectedFloor,
                      onPressed: () => setState(() => _selectedFloor = floor),
                    );
                  },
                ),
              ),
              const SizedBox(height: RoutexSpacing.contentGap),
              SizedBox(
                width: double.infinity,
                child: RoutexButton(
                  key: const Key('entry-floor-skip'),
                  label: '층을 모르겠어요 · ${widget.fallbackFloor}로 계속',
                  variant: RoutexButtonVariant.quiet,
                  // **건너뛸 수 있어야 한다.** 층을 모르는 채 들어온 사람도 있고,
                  // 판정이 틀려 밖에 있는데 이 화면을 본 사람도 있다. 다만
                  // `나중에`라고만 하면 어떤 지도로 이어지는지 숨긴다.
                  onPressed: () =>
                      Navigator.of(context).pop(widget.fallbackFloor),
                ),
              ),
              const SizedBox(height: RoutexSpacing.controlGap),
              SizedBox(
                width: double.infinity,
                child: RoutexButton(
                  key: const Key('entry-floor-confirm'),
                  label: _selectedFloor == null
                      ? '층을 선택해 주세요'
                      : '$_selectedFloor에서 시작하기',
                  onPressed: _selectedFloor == null
                      ? null
                      : () => Navigator.of(context).pop(_selectedFloor),
                ),
              ),
              const SizedBox(height: RoutexSpacing.sectionGap),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryFloorTile extends StatelessWidget {
  const _EntryFloorTile({
    super.key,
    required this.floor,
    required this.selected,
    required this.onPressed,
  });

  final String floor;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.routexColors;
    final foreground = selected ? colors.actionPrimary : colors.contentPrimary;
    return Semantics(
      button: true,
      selected: selected,
      label: '$floor 층',
      child: Material(
        color: selected ? colors.actionPrimarySubtle : colors.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? colors.actionPrimary : colors.borderSubtle,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: Center(
            child: Text(
              floor,
              style: RoutexTypography.title.copyWith(color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}
