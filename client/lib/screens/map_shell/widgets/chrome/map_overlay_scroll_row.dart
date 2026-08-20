import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

/// 지도 위에 얹은 가로 스크롤 오버레이 열(장소 pill + 카테고리 chip)의 껍데기.
///
/// 이 위젯이 존재하는 이유는 두 가지 모두 **지도가 Flutter 위젯이 아니라
/// MapLibre 플랫폼 뷰**라는 데서 나온다. 위젯 트리에서는 이 열이 지도 위에
/// 있지만, 실제 포인터 입력은 지도 쪽에도 그대로 도착한다.
///
/// 1. **지도 잠금** — 이 열 위에서 휠을 굴리면 그 휠이 지도까지 내려가 지도가
///    확대/축소된다("카테고리 열을 스크롤했는데 지도 배율이 같이 변한다"). 시트를
///    열 때 쓰던 것과 같은 잠금([MapShellScreen._withMapsLocked])을 포인터가 이
///    열 위에 있는 동안에도 걸어 지도 제스처 자체를 꺼 둔다.
/// 2. **세로 휠 → 가로 스크롤** — Flutter의 가로 스크롤 뷰는 세로 휠 delta를
///    0으로 계산해 아예 소비하지 않는다. 그래서 휠을 굴려도 열은 그대로고 지도만
///    움직였다. 세로 delta를 가로 오프셋으로 직접 옮겨 준다.
class MapOverlayScrollRow extends StatefulWidget {
  const MapOverlayScrollRow({
    super.key,
    required this.onPointerOverChanged,
    required this.onPointerDownChanged,
    required this.children,
  });

  /// 마우스 포인터가 이 열 위로 들어오거나 나갈 때.
  final ValueChanged<bool> onPointerOverChanged;

  /// 이 열 위에서 손가락/버튼이 눌리거나 떼어질 때. hover가 없는 터치 환경을
  /// 위한 경로라 hover와 별개로 통지한다.
  final ValueChanged<bool> onPointerDownChanged;

  final List<Widget> children;

  @override
  State<MapOverlayScrollRow> createState() => _MapOverlayScrollRowState();
}

class _MapOverlayScrollRowState extends State<MapOverlayScrollRow> {
  final _controller = ScrollController();
  bool _pointerOver = false;
  bool _pointerDown = false;

  @override
  void dispose() {
    // 잠금을 쥔 채로 사라지면(검색이 켜져 이 열이 트리에서 빠지는 경우 등)
    // 지도가 영영 잠긴 상태로 남는다. 나가면서 반드시 반납한다.
    //
    // **다음 프레임으로 미루는 것이 중요하다.** 반납은 지도 위젯의 setState로
    // 이어지는데, dispose는 상위 rebuild 도중에 실행될 수 있어 그 자리에서 부르면
    // "setState() called during build"로 터진다. 반납은 멱등이라 (MouseRegion이
    // 제거되며 보내는 onExit와 겹쳐) 두 번 불려도 문제없다.
    final releaseHover = _pointerOver ? widget.onPointerOverChanged : null;
    final releaseTouch = _pointerDown ? widget.onPointerDownChanged : null;
    if (releaseHover != null || releaseTouch != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        releaseHover?.call(false);
        releaseTouch?.call(false);
      });
    }
    _controller.dispose();
    super.dispose();
  }

  void _setPointerOver(bool value) {
    if (_pointerOver == value) return;
    _pointerOver = value;
    widget.onPointerOverChanged(value);
  }

  void _setPointerDown(bool value) {
    if (_pointerDown == value) return;
    _pointerDown = value;
    widget.onPointerDownChanged(value);
  }

  /// 세로 휠을 가로 오프셋으로 옮긴다. 트랙패드 가로 스크롤(dx)도 그대로 받도록
  /// dy가 0일 때는 dx를 쓴다.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final delta = event.scrollDelta.dy != 0
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == position.pixels) return;
    _controller.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: RoutexSpacing.screenGutter,
      ),
      // 잠금·휠 처리는 뷰포트 전체가 아니라 chip이 실제로 그려진 영역에만 건다.
      // 뷰포트는 화면 폭 전체라, 바깥까지 잠그면 chip 오른쪽 빈 곳에 마우스를
      // 올려 둔 것만으로 지도 휠 줌이 죽는다.
      child: MouseRegion(
        onEnter: (_) => _setPointerOver(true),
        onExit: (_) => _setPointerOver(false),
        child: Listener(
          onPointerSignal: _onPointerSignal,
          onPointerDown: (_) => _setPointerDown(true),
          onPointerUp: (_) => _setPointerDown(false),
          onPointerCancel: (_) => _setPointerDown(false),
          child: Row(mainAxisSize: MainAxisSize.min, children: widget.children),
        ),
      ),
    );
  }
}
