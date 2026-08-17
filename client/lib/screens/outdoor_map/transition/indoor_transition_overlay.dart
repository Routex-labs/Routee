/// 실내 진입·이탈 순간 지도 위를 덮는 **전환 연출 오버레이** — 흰 덮개, 문 한 짝,
/// 진행 문구.
///
/// 값은 전부 [indoorTransitionFrameAt]이 만든다. 이 파일은 그리기만 한다.
///
/// 색·구간·흰 덮개의 위험은 `docs/client/indoor-transition-choreography.md`.
library;

import 'package:flutter/material.dart';

import '../../../core/korean_josa.dart';
import '../../../theme/app_theme.dart';
import 'indoor_transition_timeline.dart';

/// 문틀 크기(논리 px). 문구와 **나란히 서는** 크기라 작다 — 크게 하면 연출이
/// 화면을 잡아먹고, 이 오버레이는 1초 남짓 떠 있다 사라지는 것이다.
const _doorWidth = 50.0;
const _doorHeight = 70.0;

/// 문틀·문짝의 테두리 두께.
const _frameBorder = 2.0;
const _leafBorder = 1.0;

/// 원근 계수. 1/210 px 쯤이라 문짝이 열릴 때 깊이가 보인다. 0으로 두면 문짝이
/// 그냥 가로로 납작해져 "열린다"가 아니라 "줄어든다"로 읽힌다.
const _perspective = 0.0045;

/// 문이 열리는 최대 각도(라디안).
///
/// **진입이 이탈보다 크다.** 이탈은 문짝이 화면 뒤쪽으로 가므로 각도를 키우면
/// 얇아져 사라진다 — 56도가 판으로 남는 한계였다. 진입은 앞으로 나오므로 커져도
/// 계속 보인다.
const _enterSwing = 68 * 3.1415926535 / 180;
const _exitSwing = 56 * 3.1415926535 / 180;

/// 전환 연출 오버레이.
///
/// [progress]는 0~1이고, 0이면 아무것도 그리지 않는다(트리에 있어도 투명).
/// [buildingName]은 진입 문구에 들어갈 이름이고, 비어 있으면 이름 없이
/// "들어가는 중..."만 띄운다 — 건물을 아직 못 받은 경우다.
///
/// 지도 조작을 막지 않는다([IgnorePointer]). 덮개가 떠 있는 1초 남짓 동안 탭이
/// 먹지 않으면 사용자는 앱이 멈춘 것으로 읽는다.
class IndoorTransitionOverlay extends StatelessWidget {
  const IndoorTransitionOverlay({
    super.key,
    required this.progress,
    required this.direction,
    this.buildingName,
  });

  final double progress;
  final IndoorTransitionDirection direction;
  final String? buildingName;

  /// 문구 한 줄. 진입은 건물명 + 방향 조사, 이탈은 고정이다.
  ///
  /// 조사는 받침을 세어 고른다([directionJosa]) — 「서울」이 `서울으로`가 되지
  /// 않게 하는 것이 그 함수의 존재 이유다.
  String get _caption {
    if (direction == IndoorTransitionDirection.exit) return '밖으로 나가는 중...';
    final name = buildingName?.trim() ?? '';
    if (name.isEmpty) return '들어가는 중...';
    return '${withDirectionJosa(name)} 들어가는 중...';
  }

  @override
  Widget build(BuildContext context) {
    final frame = indoorTransitionFrameAt(progress);
    if (frame.veilOpacity <= 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: Opacity(
        opacity: frame.veilOpacity.clamp(0.0, 1.0),
        child: ColoredBox(
          // 흰 덮개다. **실기기에서 확인이 필요하다** — 층 전환에서 같은 흰 베일이
          // 캡처 플래시처럼 번쩍여 걷어낸 적이 있다(parts/ui.dart의 층 전환 모티프
          // 주석). 여기는 등장 구간이 그때보다 길고 문·문구가 시선을 잡지만,
          // 번쩍이면 먼저 손볼 값은 이 색이 아니라 [indoorTransitionVeilIn]이다.
          color: AppColors.surface,
          child: Center(
            child: Padding(
              // 화면 폭이 좁을 때 문구가 테두리에 닿지 않게 한다.
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                // 문구 **바닥선**을 문 바닥에 맞춘다. 가운데 정렬하면 문이 문구보다
                // 커서 문구가 공중에 뜬 것처럼 보인다.
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _Door(open: frame.doorOpen, direction: direction),
                  const SizedBox(width: 12),
                  // **Flexible이 없으면 말줄임이 안 걸린다.** Row 안의 Text는
                  // 제한 없는 폭을 요구해서, 긴 건물명은 잘리는 대신 오버플로로
                  // 터진다(프레임 추출기에서 실제로 그렇게 났다).
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Opacity(
                        opacity: frame.captionOpacity.clamp(0.0, 1.0),
                        child: Text(
                          _caption,
                          maxLines: 1,
                          // 건물명이 길면 뒤쪽부터 잘린다. 앞쪽 이름이 남는 것이
                          // 맞다 — 어느 건물인지가 이 문구의 정보다.
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 문 한 짝. 경첩은 **양쪽 방향 모두 왼쪽**이고, 열리는 쪽만 반대다.
class _Door extends StatelessWidget {
  const _Door({required this.open, required this.direction});

  final double open;
  final IndoorTransitionDirection direction;

  @override
  Widget build(BuildContext context) {
    // 진입은 앞으로(당김), 이탈은 뒤로(밀기).
    //
    // **부호는 눈으로 못 고른다.** 정지 화면에서 깊이 방향이 안 읽혀서 계산으로
    // 정했다: 자유단(경첩에서 폭 w)은 회전 후 `z' = −w·sinθ`이고 원근 나눗셈이
    // `1 + p·z'`이므로, θ>0이면 분모가 1보다 작아져 **확대**된다 = 관찰자 쪽으로
    // 온다. 그래서 당기는 진입이 양수다. CSS와는 부호가 반대다(같은 식에서 +z가
    // 관찰자 쪽이라, 미리보기 하네스를 CSS로 먼저 만들었다면 뒤집어야 한다).
    final swing = direction == IndoorTransitionDirection.enter
        ? _enterSwing
        : -_exitSwing;
    return SizedBox(
      width: _doorWidth,
      height: _doorHeight,
      child: Stack(
        children: [
          // 문 뒤 — 열린 틈으로 보이는 밝은 면.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.blue50,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          // 문틀. **문짝보다 먼저 그린다** — 뒤에 두면 열린 문짝 위로 테두리가
          // 얹혀, 문짝이 반투명한 것처럼 보인다(실제로 그렇게 보였다).
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: AppColors.blue200,
                  width: _frameBorder,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          Positioned(
            left: _frameBorder,
            top: _frameBorder,
            right: _frameBorder,
            bottom: _frameBorder,
            child: Transform(
              alignment: Alignment.centerLeft,
              transform: Matrix4.identity()
                ..setEntry(3, 2, _perspective)
                ..rotateY(swing * open.clamp(0.0, 1.0)),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.blue100,
                  border: Border.all(
                    color: AppColors.blue200,
                    width: _leafBorder,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Align(
                  // 손잡이는 경첩 반대쪽(오른쪽)이다.
                  alignment: const Alignment(0.72, 0),
                  child: Container(
                    width: 2,
                    height: 11,
                    decoration: BoxDecoration(
                      color: AppColors.indoor,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
