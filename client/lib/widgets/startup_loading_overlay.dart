import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

/// 첫 위치 판정과 지도 카메라 준비를 가리는 앱 시작 화면.
class StartupLoadingOverlay extends StatelessWidget {
  const StartupLoadingOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.routexColors;
    return ColoredBox(
      key: const Key('startup-loading-overlay'),
      color: colors.surfaceBase,
      child: SafeArea(
        child: Center(
          child: Semantics(
            label: 'routee 시작 중',
            liveRegion: true,
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 520),
              curve: Curves.easeOutCubic,
              tween: Tween(begin: 0, end: 1),
              builder: (context, opacity, child) =>
                  Opacity(opacity: opacity, child: child),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/branding/routee_marker.png',
                    key: const Key('startup-loading-marker'),
                    width: 126,
                    height: 126,
                    filterQuality: FilterQuality.high,
                  ),
                  const SizedBox(height: RoutexSpacing.inlineGap),
                  Text(
                    'routee',
                    key: const Key('startup-loading-wordmark'),
                    style: RoutexTypography.headline.copyWith(
                      color: colors.contentPrimary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
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
