import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/features/debug_mode/pdr_map_control.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_tuning.dart';
import 'package:navigation_client/screens/outdoor_map/widgets/indoor_arrival_card.dart';
import 'package:navigation_client/theme/app_theme.dart';

/// **도착해도 진단 JSON을 꺼낼 수 있어야 한다.**
///
/// 실측 증상: 안내가 끝나는 순간 뜨는 도착 카드([IndoorArrivalCard])가 오른쪽
/// 아래에 있던 공유 버튼을 덮어 세션 JSON을 내보내지 못했다. 실기기 실측 직후가
/// 그 파일이 가장 필요한 순간이다.
///
/// 여기서는 `parts/ui.dart`가 쓰는 것과 같은 Stack 순서(카드가 버튼보다 뒤 =
/// 위에 그려짐)와 같은 오프셋 상수([pdrControlTopPx])로 두 위젯만 세운다.
/// 화면 전체를 도착 상태까지 몰고 가려면 안내 세션과 PDR 스냅샷이 필요해
/// 자리 문제와 무관한 것들이 함께 깨진다.
void main() {
  final shareKey = GlobalKey();

  Widget host({required bool arrived, double textScale = 1.0}) => MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Stack(
          children: [
            Positioned(
              top: pdrControlTopPx,
              right: 16,
              child: PdrMapControl(
                canExport: true,
                exporting: false,
                onExport: () => _exported = true,
                shareButtonKey: shareKey,
              ),
            ),
            if (arrived)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IndoorArrivalCard(
                  destinationName: '포인트 오브 뷰 성수 플래그십 스토어',
                  destinationFloor: 'B2',
                  onConfirm: () {},
                  onShowDetail: () {},
                ),
              ),
          ],
        ),
      ),
    ),
  );

  setUp(() => _exported = false);

  testWidgets('도착 카드가 떠 있어도 공유 버튼이 눌린다', (tester) async {
    await tester.pumpWidget(host(arrived: true));

    // warnIfMissed가 기본값(true)이라, 카드가 가려서 탭이 버튼에 닿지 않으면
    // 이 호출 자체가 실패한다. 콜백까지 보는 것은 눌린 것이 공유 버튼인지까지
    // 가리기 위해서다.
    await tester.tap(find.byKey(shareKey));

    expect(_exported, isTrue);
  });

  testWidgets('큰 글자 배율로 카드가 높아져도 버튼과 겹치지 않는다', (tester) async {
    // 카드 높이는 글자 배율을 타고 커진다. 버튼을 하단 오프셋으로 올려 두면
    // "어떤 배율에서만 안 눌리는" 자리가 되는데, 위에서 내린 오프셋은 그 영향을
    // 받지 않는다.
    await tester.pumpWidget(host(arrived: true, textScale: 2));

    final button = tester.getRect(find.byKey(shareKey));
    final card = tester.getRect(find.byType(IndoorArrivalCard));

    expect(button.overlaps(card), isFalse);
  });

  testWidgets('도착 카드가 없을 때와 같은 자리다', (tester) async {
    await tester.pumpWidget(host(arrived: false));
    final withoutCard = tester.getRect(find.byKey(shareKey));

    await tester.pumpWidget(host(arrived: true));
    final withCard = tester.getRect(find.byKey(shareKey));

    // 조건부로 옮기면 상태마다 자리가 달라져, 실측 중에 버튼을 눈으로 찾아야 한다.
    expect(withCard, withoutCard);
  });
}

bool _exported = false;
