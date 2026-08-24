/// 건물에 들어온 것은 GPS가 알지만 **몇 층인지는 모른다.** 그 한 가지를 묻는 화면.
///
/// 안 물으면 층이 조용히 `default_floor`(1F)로 굳는다 — 사용자는 B2에 서 있는데
/// 위치도 경로도 1층에 찍힌다. 검증 기준은
/// `client/test/screens/outdoor_map/entry_floor_prompt_test.dart`.
library;

import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

/// 층을 고르게 하고 고른 층을 돌려준다. 건너뛰거나 뒤로 가면 null.
///
/// 경로는 투명하게 두어 아래 지도의 렌더링을 유지하되, 전환 중에도 흰 배경은
/// 항상 불투명하게 칠한다. 화면 전체를 함께 fade하면 첫 프레임의 투명도 사이로
/// MapLibre가 한 번 비쳐, 시작 화면과 층 질문 사이에 지도가 깜빡인다.
Future<String?> showEntryFloorPrompt(
  BuildContext context, {
  required String buildingName,
  required List<String> floors,
}) {
  return Navigator.of(context).push<String>(
    PageRouteBuilder<String>(
      opaque: false,
      barrierDismissible: false,
      transitionDuration: RoutexMotion.transition,
      reverseTransitionDuration: RoutexMotion.transition,
      pageBuilder: (_, _, _) =>
          EntryFloorPrompt(buildingName: buildingName, floors: floors),
      transitionsBuilder: (context, animation, _, child) => ColoredBox(
        key: const Key('entry-floor-transition-background'),
        color: context.routexColors.surfaceBase,
        child: FadeTransition(opacity: animation, child: child),
      ),
    ),
  );
}

/// [showEntryFloorPrompt]가 띄우는 화면. 라우트 없이도 시험할 수 있게 분리한다.
class EntryFloorPrompt extends StatelessWidget {
  const EntryFloorPrompt({
    super.key,
    required this.buildingName,
    required this.floors,
  });

  final String buildingName;

  /// 엘리베이터 버튼판 순서(위층 → 아래층) 그대로다. 여기서 다시 정렬하지
  /// 않는다 — 층 선택기와 순서가 다르면 같은 건물이 화면마다 다르게 보인다.
  final List<String> floors;

  @override
  Widget build(BuildContext context) {
    final colors = context.routexColors;
    // **Scaffold를 쓰지 않는다.** ScaffoldMessenger는 가장 나중에 등록된
    // Scaffold에 스낵바를 옮겨 붙인다 — 실내 위치를 잡느라 띄운 '건물 감지 중...'이
    // 이 화면 하단으로 따라 올라와 "나중에 고르기"를 덮었다.
    return Material(
      color: colors.surfaceBase,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: RoutexSpacing.screenGutter,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: RoutexSpacing.sectionGap),
              Text('몇 층에 계신가요?', style: RoutexTypography.headline),
              const SizedBox(height: RoutexSpacing.inlineGap),
              Text(
                '$buildingName 안에 계신 것까지는 알았지만, 층은 GPS로 알 수 없습니다.\n'
                '고른 층을 기준으로 위치와 경로를 그립니다.',
                style: RoutexTypography.body.copyWith(
                  color: colors.contentSecondary,
                ),
              ),
              const SizedBox(height: RoutexSpacing.contentGap),
              Expanded(
                child: ListView.separated(
                  itemCount: floors.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: RoutexSpacing.inlineGap),
                  itemBuilder: (_, index) {
                    final floor = floors[index];
                    return RoutexListCell(
                      key: ValueKey('entry-floor-$floor'),
                      title: floor,
                      leadingIcon: RoutexIcons.floors,
                      onPressed: () => Navigator.of(context).pop(floor),
                    );
                  },
                ),
              ),
              const SizedBox(height: RoutexSpacing.contentGap),
              // **건너뛸 수 있어야 한다.** 층을 모르는 채 들어온 사람도 있고,
              // 판정이 틀려 밖에 있는데 이 화면을 본 사람도 있다. 막아 두면 그
              // 둘 다 지도에 닿을 방법이 없다.
              RoutexButton(
                key: const Key('entry-floor-skip'),
                label: '나중에 고르기',
                variant: RoutexButtonVariant.quiet,
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: RoutexSpacing.contentGap),
            ],
          ),
        ),
      ),
    );
  }
}
