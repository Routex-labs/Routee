import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

/// 매장 정보·저장한 장소·카테고리 매장 목록 시트가 공유하는 헤더.
///
/// 왼쪽에 뒤로 가기, 가운데에 제목(옵션), 오른쪽에 X. 뒤로 가기는 그냥
/// 현재 시트만 닫아 부모 loop가 이전 시트를 다시 열게 하고, X는 [onCloseAll]
/// 콜백을 호출해 상위(MapShellScreen)에 chain 전체 종료 신호를 남긴 뒤
/// 현재 시트만 닫는다. 부모 loop들이 그 신호를 보고 다시 열지 않아서 결과
/// 적으로 chain의 모든 시트가 한 번에 닫힌 것처럼 보인다.
///
/// 두 버튼 모두 pop 전 [onIntentionalPop]을 먼저 호출해, 상위의 PopScope가
/// 이 pop을 "의도된 pop"으로 인식하고 barrier 탭과 구분할 수 있게 한다.
class SheetHeader extends StatelessWidget {
  const SheetHeader({
    super.key,
    this.title,
    this.leading,
    this.showBack = true,
    required this.onCloseAll,
    required this.onIntentionalPop,
  });

  final String? title;

  /// 이전 화면 호환용 제목 장식. 새 시트에서는 제목 자체로 충분하면 생략한다.
  final Widget? leading;
  final bool showBack;

  /// X 버튼이 눌렸을 때 호출. 상위(MapShellScreen)가 chain-close 플래그를
  /// set하는 함수를 넘긴다.
  final VoidCallback onCloseAll;

  /// 뒤로/X를 눌러 pop 하기 직전 호출. sheet state가 "이번 pop은 의도된 것"
  /// 이라는 플래그를 세팅해 PopScope가 이를 barrier 탭과 구분한다.
  final VoidCallback onIntentionalPop;

  @override
  Widget build(BuildContext context) {
    final header = RoutexSheetHeader(
      title: title,
      onBack: showBack
          ? () {
              onIntentionalPop();
              Navigator.of(context).maybePop();
            }
          : null,
      onClose: () {
        onIntentionalPop();
        onCloseAll();
        Navigator.of(context).maybePop();
      },
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RoutexSpacing.contentGap),
      child: leading == null
          ? header
          : Row(
              children: [
                leading!,
                const SizedBox(width: RoutexSpacing.controlGap),
                Expanded(child: header),
              ],
            ),
    );
  }
}
