import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'service_locator.dart';
import 'routing/app_routes.dart';
import 'routing/place_link.dart';
import 'theme/app_theme.dart';
import 'screens/map_shell/map_shell_screen.dart';

void defaultPdrBackgrounded() {
  unawaited(indoorNavigationDriver.onAppBackgrounded());
}

void defaultPdrForegrounded() {
  unawaited(indoorNavigationDriver.onAppForegrounded());
}

class NavigationApp extends StatefulWidget {
  const NavigationApp({
    super.key,
    this.onPdrBackgrounded = defaultPdrBackgrounded,
    this.onPdrForegrounded = defaultPdrForegrounded,
    this.home,
    this.linkStream,
    this.initialLink,
  });

  final VoidCallback onPdrBackgrounded;
  final VoidCallback onPdrForegrounded;
  final Widget? home;

  /// 공유 링크가 들어오는 문. 테스트에서는 가짜를 넣고, 앱에서는 플랫폼 채널을
  /// 타는 `AppLinks`를 쓴다. null이면 링크를 듣지 않는다 — 위젯 테스트가 플랫폼
  /// 채널을 건드리지 않고 돌 수 있어야 한다.
  final Stream<Uri>? linkStream;
  final Future<Uri?> Function()? initialLink;

  @override
  State<NavigationApp> createState() => _NavigationAppState();
}

class _NavigationAppState extends State<NavigationApp>
    with WidgetsBindingObserver {
  bool _pdrBackgrounded = false;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenForPlaceLinks();
  }

  @override
  void dispose() {
    unawaited(_linkSubscription?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 공유 링크를 듣는다. **두 경로가 있고 둘 다 필요하다** — 최초 URI는 앱이 꺼져
  /// 있을 때 눌린 링크(cold start)이고, stream은 실행 중이거나 백그라운드에 있을 때
  /// 눌린 링크다. 하나만 들으면 그 절반이 조용히 사라진다.
  ///
  /// 중복은 [PlaceLinkInbox]가 거른다 — 같은 URI가 두 경로로 연달아 오는 경우가 있고,
  /// 그대로 두면 시트가 두 번 열린다.
  void _listenForPlaceLinks() {
    // origin이 없으면 어떤 링크도 우리 것이 아니다. 그때는 채널을 아예 열지 않는다.
    if (!placeLinkEnabled()) return;
    final links = widget.linkStream == null && widget.initialLink == null
        ? AppLinks()
        : null;
    final initial = widget.initialLink ?? links?.getInitialLink;
    final stream = widget.linkStream ?? links?.uriLinkStream;

    if (initial != null) {
      unawaited(
        initial()
            .then((uri) {
              if (uri != null) placeLinkInbox.offer(uri);
            })
            .catchError((_) {}),
      );
    }
    _linkSubscription = stream?.listen(
      placeLinkInbox.offer,
      // 링크 채널이 죽어도 앱은 그대로 쓸 수 있어야 한다. 지도는 링크와 무관하다.
      onError: (_) {},
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_pdrBackgrounded) return;
      _pdrBackgrounded = false;
      widget.onPdrForegrounded();
      return;
    }
    // iOS의 inactive는 알림 센터·시스템 시트·권한 UI에서도 잠깐 발생한다.
    // 이 짧은 상태에서 센서를 stop하면 곧바로 오는 resumed의 start와 경합해
    // EventChannel 구독만 남고 native motion이 멈출 수 있다.
    if (state == AppLifecycleState.inactive) return;
    if (_pdrBackgrounded) return;
    _pdrBackgrounded = true;
    widget.onPdrBackgrounded();
  }

  @override
  Widget build(BuildContext context) {
    // 화면은 하나다. 지도 셸이 야외·실내를 한 화면 안에서 모두 그리므로
    // 이 앱에는 push할 다른 화면이 없다 — 목적지 선택·경로 안내·도착 화면은
    // 지도 셸의 시트와 오버레이로 흡수됐다.
    final routes = <String, WidgetBuilder>{
      AppRoutes.outdoorMap: (context) => const MapShellScreen(),
    };
    if (widget.home != null) {
      routes.remove(AppRoutes.outdoorMap);
    }
    return MaterialApp(
      title: 'Navigation Client',
      theme: AppTheme.light,
      // 로케일을 안 주면 MaterialLocalizations가 영어로 떨어져 시각이
      // '1:45 PM'으로 찍힌다. 한국어 앱에서 그 표기는 낯설고, 시각을 쓰는 곳이
      // 계획 카드·진행 바·대중교통 카드 셋이라 카드마다 문자열을 만들면
      // 세 벌이 따로 썩는다.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ko')],
      home: widget.home,
      initialRoute: widget.home == null ? AppRoutes.outdoorMap : null,
      routes: routes,
    );
  }
}
