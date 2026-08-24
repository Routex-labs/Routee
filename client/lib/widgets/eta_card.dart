import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../domain/geo/distance_format.dart';
import '../domain/guidance/route_guidance.dart';
import '../features/indoor_navigation/contract/floor_transition_ui_state.dart';
import 'transit_style.dart' show formatTransitDuration;

/// 앱의 경로 값을 Runtime Kit의 계획·안내 패턴에 연결한다.
///
/// [guidanceStarted]가 false면 출발 전 계획, true면 하단 진행 정보다. 다음 행동은
/// 지도 위쪽의 [GuidanceBanner]가 맡아 Runtime Kit의 안내 구조를 보존한다.
class EtaCard extends StatelessWidget {
  const EtaCard({
    super.key,
    required this.distanceMeters,
    required this.minutes,
    this.label = '목적지까지',
    this.guidanceStarted = false,
    this.onClose,
    this.onStartGuidance,
    this.onClosePointerDown,
    this.routeOptions,
    this.extraMetric,
  });

  final double distanceMeters;
  final int minutes;
  final String label;
  final bool guidanceStarted;
  final VoidCallback? onClose;
  final VoidCallback? onStartGuidance;
  final ValueChanged<Offset>? onClosePointerDown;

  /// 복수 경로 후보를 고를 수 있을 때 요약 위에 놓는 선택 영역. 출발 전
  /// 계획 카드에서만 쓰인다 — 안내 중에는 경로를 바꿀 수 없다.
  final Widget? routeOptions;

  /// 소요·거리 옆에 하나 더 적을 값(통행료 등). `RoutexEtaCard`가 지표를
  /// 3개까지만 받아 통행료·택시비를 동시에 넣을 자리가 없다 — 부르는
  /// 쪽이 어느 쪽을 보여줄지 미리 고른다.
  final RoutexTripMetric? extraMetric;

  @override
  Widget build(BuildContext context) {
    final arrivalTime = TimeOfDay.fromDateTime(
      DateTime.now().add(Duration(minutes: minutes)),
    ).format(context);
    if (!guidanceStarted) {
      return RoutexEtaCard(
        title: label,
        // 이 자리가 카드의 headline이다. 도착 시각은 안내를 시작한 뒤 진행 바에서
        // 본다 — 출발 전에 두 화면이 같은 값을 두 벌로 말할 필요가 없다.
        // 60분을 넘으면 "272분"이 아니라 "4시간 32분"으로 적는다 — 분만 적으면
        // 사용자가 머릿속에서 나눗셈을 해야 한다. 도보가 실제로 그렇게 길다.
        arrivalTime: formatTransitDuration(minutes * 60),
        metrics: [
          RoutexTripMetric(value: formatDistance(distanceMeters), label: '거리'),
          ?extraMetric,
        ],
        routeOptions: routeOptions,
        onStart: onStartGuidance,
      );
    }

    return Listener(
      onPointerDown: (event) => onClosePointerDown?.call(event.position),
      child: RoutexTripProgress(
        metrics: [
          RoutexTripMetric(value: arrivalTime, label: '도착 예정'),
          RoutexTripMetric(
            value: formatTransitDuration(minutes * 60),
            label: '남은 시간',
          ),
          RoutexTripMetric(
            value: formatDistance(distanceMeters),
            label: '남은 거리',
          ),
        ],
        onStop: onClose,
      ),
    );
  }
}

/// 지도 위쪽 **안내 한 자리**. 아래 네 상태 중 하나만 그린다.
///
/// 우선순위는 층 전환 → 도착 → 이탈 → 다음 행동이다. 층 전환이 맨 앞인 이유는
/// 타는 동안 걸음이 멈춰 있어 [instruction]의 남은거리가 갱신되지 않기 때문이다
/// — 그대로 두면 "6.8m 뒤 좌회전"이 에스컬레이터를 타는 내내 붙어 있다.
///
/// **자리를 하나로 묶은 것이 이 위젯의 존재 이유다.** 예전에는 층 전환만 셸이
/// 흰 알약으로 따로 띄워, 같은 자리에 초록 배너와 알약이 겹쳤다.
class GuidanceBanner extends StatelessWidget {
  const GuidanceBanner({
    super.key,
    this.instruction,
    this.floorTransition,
    this.arrivalAt,
  });

  final RouteGuidanceInstruction? instruction;

  /// 층 전환이 도는 중이면 그 단계. null이면 전환 중이 아니다.
  final FloorTransitionUiState? floorTransition;

  /// 도착 배너에 적을 `이름 · 층`. null이면 아직 도착이 아니다.
  final String? arrivalAt;

  /// 그릴 것이 하나도 없는지. 호출부가 자리를 통째로 비울지 판단한다.
  bool get isEmpty =>
      instruction == null && floorTransition == null && arrivalAt == null;

  @override
  Widget build(BuildContext context) {
    final transition = floorTransition;
    if (transition != null) {
      return RoutexManeuverBanner(
        distance: transition.headline,
        detail: transition.detail,
        // 아이콘 표는 [routeGuidanceIcon] 하나다. 여기서 글리프를 직접 고르면
        // 같은 이동이 배너와 단계 목록에서 다른 그림으로 나온다.
        icon: routeGuidanceIcon(switch (transition.vehicle) {
          FloorTransitionVehicle.escalator => RouteGuidanceAction.escalator,
          FloorTransitionVehicle.elevator => RouteGuidanceAction.elevator,
        }),
      );
    }
    final arrival = arrivalAt;
    if (arrival != null) {
      return RoutexStatusBanner(
        title: '목적지에 도착했습니다',
        detail: arrival,
        icon: RoutexIcons.arrived,
        tone: RoutexStatusBannerTone.success,
      );
    }
    final guidance = instruction;
    if (guidance == null) return const SizedBox.shrink();
    if (guidance.action == RouteGuidanceAction.wrongWay) {
      return const RoutexStatusBanner(
        title: '경로를 벗어났습니다',
        detail: '새 경로를 자동으로 찾고 있습니다',
        icon: RoutexIcons.error,
        tone: RoutexStatusBannerTone.error,
      );
    }
    return RoutexManeuverBanner(
      distance: _distanceLabel(guidance.distanceToActionM),
      detail: guidance.primaryText,
      icon: routeGuidanceIcon(guidance.action),
    );
  }
}

String _distanceLabel(double meters) {
  if (!meters.isFinite || meters < 0) return '';
  if (meters < 10) return '${meters.toStringAsFixed(1)}m';
  return formatDistance(meters);
}

/// 안내 배너와 전체 단계 목록이 같은 행동 글리프를 사용한다.
IconData routeGuidanceIcon(RouteGuidanceAction action) => switch (action) {
  RouteGuidanceAction.wrongWay => RoutexIcons.wrongWay,
  RouteGuidanceAction.turnLeft => RoutexIcons.turnLeft,
  RouteGuidanceAction.turnRight => RoutexIcons.turnRight,
  RouteGuidanceAction.escalator => RoutexIcons.escalator,
  RouteGuidanceAction.elevator => RoutexIcons.elevator,
  RouteGuidanceAction.arrived => RoutexIcons.arrived,
  RouteGuidanceAction.straight => RoutexIcons.straight,
};
