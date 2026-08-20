import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../../../../core/api_config.dart';
import '../../../../widgets/map_overlay_guard.dart';

/// 앱 메뉴에서 고를 수 있는 동작. 시트는 **고른 것만 돌려주고 아무것도 직접
/// 실행하지 않는다** — 실제 동작은 전부 지도 상태를 들고 있는
/// `MapShellScreen`이 수행해야 하기 때문이다.
enum AppMenuAction {
  favorites,
  directions,
  placeLocation,
  calibrate,
  debugSettings,
}

/// 상단 바 햄버거 버튼이 여는 앱 메뉴 시트.
///
/// 예전에는 이 버튼이 곧장 "건물 선택 (테스트)" 시트를 열었다. 건물을 바꿀 일이
/// 없어진 지금은, 화면 구석구석에 흩어져 있던 진입점을 **한 목록으로 모으는**
/// 자리로 쓴다. 특히 디버그 설정은 예전에 지도 왼쪽 아래에 떠 있는 벌레 아이콘
/// 버튼이었는데, 일반 사용자에게 보일 이유가 없는 개발 도구가 메인 화면을
/// 차지하고 있었다. 여기 "개발자" 구획으로 내리면 메인 지도에서는 사라지고,
/// 필요할 때는 메뉴 → 디버그 설정 두 번이면 닿는다.
///
/// **실패 조건.** 시트가 떠 있는 동안 지도 모드가 바뀌면 [showPlaceLocation]
/// 판정이 낡은 값이 된다. 그래서 호출부는 시트를 여는 동안 지도를 잠그고
/// (`_withMapsLocked`), 고른 동작은 시트가 닫힌 뒤 **그 시점의 상태로** 다시
/// 실행한다 — 여기서 콜백을 직접 들고 있으면 닫힌 시트가 옛 상태를 붙잡는다.
class AppMenuSheet extends StatelessWidget {
  const AppMenuSheet({
    super.key,
    required this.showPlaceLocation,
    required this.debugEnabled,
  });

  /// "지도에서 내 위치 지정"을 노출할지. 하단 바의 같은 버튼과 같은 조건이다 —
  /// 건물 안(실내 탭이거나 야외에서 실내 진입 오버레이가 켜진 상태)이 아니면
  /// 지정할 층이 없어 눌러도 의미가 없다.
  final bool showPlaceLocation;

  /// 디버그 모드가 켜져 있는지. 항목을 감추는 데 쓰지 않고 **부제로만** 알린다 —
  /// 켜 둔 걸 잊은 채 지도에 진단 레이어가 겹쳐 보이는 상태를 여기서 알아채야
  /// 한다.
  final bool debugEnabled;

  static Future<AppMenuAction?> show(
    BuildContext context, {
    required bool showPlaceLocation,
    required bool debugEnabled,
  }) {
    return showModalBottomSheet<AppMenuAction>(
      context: context,
      // 기본 높이 상한(화면의 9/16)에 맞추면 항목 두어 개가 잘려, 스크롤 되는 줄
      // 모르는 사용자에게는 "메뉴에 디버그 설정이 없다"가 된다. 목록이 길어질수록
      // 아래쪽 항목부터 조용히 사라지는 실패라 상한을 풀고 내용 높이로 띄운다.
      isScrollControlled: true,
      // 표면은 시트 본문이 그린다([RoutexBottomSheet]). 라우트까지 배경을 칠하면
      // 같은 표면이 두 겹이 된다.
      backgroundColor: Colors.transparent,
      builder: (context) => MapOverlayGuard(
        child: AppMenuSheet(
          showPlaceLocation: showPlaceLocation,
          debugEnabled: debugEnabled,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 표면이 SafeArea 바깥이다. 안에 두면 배경이 홈 인디케이터 위에서 끊긴다.
    return RoutexBottomSheet(
      contentInset: RoutexBottomSheetContentInset.content,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 손잡이가 있던 자리다. 이 시트는 내용 높이로 뜨고 끌어서 크기를
              // 바꿀 수 없어, 손잡이를 두면 할 수 없는 조작을 약속하게 된다.
              // 여백은 손잡이가 차지하던 값과 같다.
              const SizedBox(height: RoutexSpacing.componentPadding),
              const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: RoutexSpacing.contentGap,
                ),
                child: RoutexSheetHeader(title: '메뉴'),
              ),

              const _MenuSectionLabel('찾기'),
              _MenuTile(
                itemKey: const Key('app-menu-favorites'),
                icon: Icons.bookmark_outline,
                title: '저장한 장소',
                subtitle: '저장해 둔 매장을 목록에서 고릅니다',
                action: AppMenuAction.favorites,
              ),
              _MenuTile(
                itemKey: const Key('app-menu-directions'),
                icon: Icons.directions_outlined,
                title: '길찾기',
                subtitle: '출발지·도착지를 골라 경로를 그립니다',
                action: AppMenuAction.directions,
              ),

              const RoutexDivider(role: RoutexDividerRole.section),
              const _MenuSectionLabel('내 위치'),
              if (showPlaceLocation)
                _MenuTile(
                  itemKey: const Key('app-menu-place-location'),
                  icon: Icons.pin_drop_outlined,
                  title: '지도에서 내 위치 지정',
                  subtitle: '도면 위 한 점을 탭해 현재 위치를 직접 찍습니다',
                  action: AppMenuAction.placeLocation,
                ),
              _MenuTile(
                itemKey: const Key('app-menu-calibrate'),
                icon: Icons.explore_outlined,
                title: '위치 보정',
                subtitle: '방위와 현재 위치를 다시 맞춥니다',
                action: AppMenuAction.calibrate,
              ),

              const RoutexDivider(role: RoutexDividerRole.section),
              const _MenuSectionLabel('개발자'),
              _MenuTile(
                itemKey: const Key('app-menu-debug'),
                icon: Icons.bug_report_outlined,
                title: '디버그 설정',
                subtitle: debugEnabled
                    ? '사용 중 · PDR 제어와 진단 레이어가 지도에 표시됩니다'
                    : '꺼짐 · PDR 제어와 진단 레이어를 켤 수 있습니다',
                action: AppMenuAction.debugSettings,
                highlighted: debugEnabled,
              ),
              const _BuildInfoLine(),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuSectionLabel extends StatelessWidget {
  const _MenuSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RoutexSpacing.contentGap),
      child: RoutexSectionHeader(
        title: label,
        level: RoutexSectionHeaderLevel.group,
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.itemKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.action,
    this.highlighted = false,
  });

  /// 항목 자체에 붙는 키. `super.key`로 받으면 상위 Column의 자식 식별에
  /// 쓰여도 테스트가 `find.byKey`로 탭 대상을 잡는 데 문제는 없지만, 여기서는
  /// 실제로 탭이 걸리는 목록 행에 직접 달아 둔다.
  final Key itemKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final AppMenuAction action;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return RoutexListCell(
      key: itemKey,
      title: title,
      subtitle: subtitle,
      leadingIcon: icon,
      selected: highlighted,
      onPressed: () => Navigator.of(context).pop(action),
    );
  }
}

/// 디버그의 가장 밑바닥 정보 — **지금 어느 서버에 붙어 있고 어떤 빌드인지**.
///
/// 진단 레이어를 아무리 켜도 이 두 줄이 틀리면 보고 있는 화면 전체가 다른
/// 이야기다. 실기기에서 "왜 데이터가 안 맞지"의 첫 확인이 대개 여기라, 토글이
/// 아니라 항상 보이는 텍스트로 둔다.
class _BuildInfoLine extends StatelessWidget {
  const _BuildInfoLine();

  static String get _buildMode {
    if (kReleaseMode) return '릴리스';
    if (kProfileMode) return '프로파일';
    return '디버그';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.routexColors;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        RoutexSpacing.contentGap,
        RoutexSpacing.inlineGap,
        RoutexSpacing.contentGap,
        RoutexSpacing.controlGap,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '서버 · $apiBaseUrl',
            style: RoutexTypography.caption.copyWith(
              color: colors.contentSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '빌드 · $_buildMode',
            style: RoutexTypography.caption.copyWith(
              color: colors.contentSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
