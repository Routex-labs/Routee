import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/theme/app_theme.dart';
import 'package:navigation_client/domain/guidance/escalator_ride.dart';
import 'package:navigation_client/features/indoor_navigation/contract/floor_transition_ui_state.dart';
import 'package:navigation_client/screens/map_shell/widgets/chrome/floor_transition_overlay.dart';

FloorTransitionUiState _state(
  FloorTransitionStage stage, {
  String from = 'B1',
  String to = '1F',
  bool goingUp = true,
}) => FloorTransitionUiState(
  stage: stage,
  fromFloorLabel: from,
  toFloorLabel: to,
  goingUp: goingUp,
);

Widget _host(Widget child, {double textScale = 1.0, Size? size}) => MediaQuery(
  data: MediaQueryData(
    textScaler: TextScaler.linear(textScale),
    size: size ?? const Size(390, 844),
  ),
  child: MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  group('FloorTransitionScrim', () {
    testWidgets('전환 중에는 뒤쪽 입력을 막는다', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => tapped = true,
                  ),
                ),
                Positioned.fill(
                  child: FloorTransitionScrim(
                    opacity: 1,
                    fadeIn: Duration.zero,
                    fadeOut: Duration.zero,
                    state: _state(FloorTransitionStage.swapping),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.byType(Scaffold), warnIfMissed: false);
      await tester.pump();
      expect(tapped, isFalse);
      expect(find.text('B1'), findsOneWidget);
      expect(find.text('1F'), findsOneWidget);
    });

    testWidgets('덮개가 옅어지는 동안에는 입력이 통과한다', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => tapped = true,
                  ),
                ),
                Positioned.fill(
                  child: FloorTransitionScrim(
                    opacity: 0.5,
                    fadeIn: Duration.zero,
                    fadeOut: Duration.zero,
                    state: _state(FloorTransitionStage.swapping),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.byType(Scaffold), warnIfMissed: false);
      await tester.pump();
      expect(tapped, isTrue, reason: '절반쯤 걷힌 화면을 계속 막아 두면 전환이 끝나도 먹통으로 느껴진다');
      expect(
        find.text('에스컬레이터로 이동 중'),
        findsOneWidget,
        reason: '도면을 갈아 끼우는 것은 앱의 사정이다 — 그 사람은 층을 이동하는 중이다',
      );
    });

    testWidgets('스크림이 걷히면 뒤쪽 입력이 다시 통과한다', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => tapped = true,
                  ),
                ),
                const Positioned.fill(
                  child: FloorTransitionScrim(
                    opacity: 0,
                    fadeIn: Duration.zero,
                    fadeOut: Duration.zero,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.byType(Scaffold), warnIfMissed: false);
      await tester.pump();
      expect(
        tapped,
        isTrue,
        reason: '투명한 스크림이 화면 전체 입력을 계속 먹으면 전환 뒤 앱이 먹통이 된다',
      );
    });
  });
  group('층 전환 연출 — 두 층을 세로로 잇는다', () {
    // 층 이동은 수직 사건이다. 가로로 `B1 → B2`라고 적으면, 지하로 내려가는데
    // 화면에서는 오른쪽으로 가는 그림이라 방향 감각이 한 번 꼬인다.

    /// 화면에 그려진 [label] 텍스트의 세로 중심.
    double centerYOf(WidgetTester tester, String label) =>
        tester.getCenter(find.text(label)).dy;

    testWidgets('내려갈 때는 출발 층이 위, 도착 층이 아래다', (tester) async {
      await tester.pumpWidget(
        _host(
          const FloorTransitionScrim(
            opacity: 1,
            fadeIn: Duration.zero,
            fadeOut: Duration.zero,
            state: null,
          ),
        ),
      );
      await tester.pumpWidget(
        _host(
          FloorTransitionScrim(
            opacity: 1,
            fadeIn: Duration.zero,
            fadeOut: Duration.zero,
            state: _state(
              FloorTransitionStage.moving,
              from: 'B1',
              to: 'B2',
              goingUp: false,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        centerYOf(tester, 'B1'),
        lessThan(centerYOf(tester, 'B2')),
        reason: '지하로 내려가는데 도착 층이 위에 있으면 방향이 거꾸로 읽힌다',
      );
    });

    testWidgets('올라갈 때는 출발 층이 아래, 도착 층이 위다', (tester) async {
      await tester.pumpWidget(
        _host(
          FloorTransitionScrim(
            opacity: 1,
            fadeIn: Duration.zero,
            fadeOut: Duration.zero,
            state: _state(
              FloorTransitionStage.moving,
              from: 'B1',
              to: '1F',
              goingUp: true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(centerYOf(tester, '1F'), lessThan(centerYOf(tester, 'B1')));
    });

    testWidgets('두 층 라벨과 단계 문구를 함께 보여 준다', (tester) async {
      await tester.pumpWidget(
        _host(
          FloorTransitionScrim(
            opacity: 1,
            fadeIn: Duration.zero,
            fadeOut: Duration.zero,
            state: _state(
              FloorTransitionStage.moving,
              from: 'B1',
              to: 'B2',
              goingUp: false,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('B1'), findsOneWidget);
      expect(find.text('B2'), findsOneWidget);
      expect(find.textContaining('이동 중'), findsOneWidget);
    });

    testWidgets('점은 한 번의 스위프로 도착 쪽까지 완주한다', (tester) async {
      // 실제 탑승 진행률을 얹으면 덮개가 보이는 몇 초 동안 점이 거의 움직이지
      // 않아 멈춘 것으로 읽힌다(2026-08-13 실측). 카드는 자체 시계로 전체를
      // 한 번 재생하는 상징이다.
      await tester.pumpWidget(
        _host(
          FloorTransitionScrim(
            opacity: 1,
            fadeIn: Duration.zero,
            fadeOut: Duration.zero,
            state: _state(
              FloorTransitionStage.moving,
              from: 'B1',
              to: 'B2',
              goingUp: false,
            ),
          ),
        ),
      );
      await tester.pump();
      final dot = find.byKey(const Key('floor-transition-dot'));
      final startY = tester.getCenter(dot).dy;

      await tester.pump(escalatorGlideDuration ~/ 2);
      final midY = tester.getCenter(dot).dy;
      expect(midY, greaterThan(startY), reason: '내려가는 전환이면 점도 아래로 내려가야 한다');

      await tester.pumpAndSettle();
      final endY = tester.getCenter(dot).dy;
      expect(endY, greaterThan(midY), reason: '스위프가 끝까지 가야 한다');

      // 완주 뒤에는 도착 쪽에 머문다 — 반복하면 같은 장면이 두 번 보인다.
      await tester.pump(const Duration(seconds: 1));
      expect(tester.getCenter(dot).dy, endY);
    });

    testWidgets('캡션은 가는 방향 쪽에 붙는다', (tester) async {
      await tester.pumpWidget(
        _host(
          FloorTransitionScrim(
            opacity: 1,
            fadeIn: Duration.zero,
            fadeOut: Duration.zero,
            state: _state(
              FloorTransitionStage.moving,
              from: 'B1',
              to: 'B2',
              goingUp: false,
            ),
          ),
        ),
      );
      await tester.pump();
      // 내려갈 때는 캡션이 아래 라벨보다 아래에 있다.
      expect(
        tester.getCenter(find.textContaining('이동 중')).dy,
        greaterThan(tester.getCenter(find.text('B2')).dy),
      );

      await tester.pumpWidget(
        _host(
          FloorTransitionScrim(
            opacity: 1,
            fadeIn: Duration.zero,
            fadeOut: Duration.zero,
            state: _state(
              FloorTransitionStage.moving,
              from: 'B1',
              to: '1F',
              goingUp: true,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.getCenter(find.textContaining('이동 중')).dy,
        lessThan(tester.getCenter(find.text('1F')).dy),
      );
    });

    testWidgets('스크림이 걷히면 반복 애니메이션도 멈춘다', (tester) async {
      // 보이지도 않는 위젯이 매 프레임 rebuild를 요청하면 안 된다.
      await tester.pumpWidget(
        _host(
          FloorTransitionScrim(
            opacity: 0,
            fadeIn: Duration.zero,
            fadeOut: Duration.zero,
            state: _state(FloorTransitionStage.moving, goingUp: false),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      // 애니메이션이 계속 돌면 pumpAndSettle이 타임아웃으로 실패한다.
      await tester.pumpAndSettle();
    });
  });

  group('도착 층 사진', () {
    // 사진은 도착 층 라벨 쪽에 붙는다. 지금 가는 곳과 그곳의 사진이 화면 반대편에
    // 있으면 둘이 한 사건으로 안 읽힌다.
    const photo = ['assets/floors/b2.webp'];

    Finder photoFinder() => find.byType(Image);

    testWidgets('내려갈 때는 도착 층 라벨 아래에 붙는다', (tester) async {
      await tester.pumpWidget(
        _host(
          FloorTransitionScrim(
            opacity: 1,
            fadeIn: Duration.zero,
            fadeOut: Duration.zero,
            photoAssets: photo,
            state: _state(
              FloorTransitionStage.moving,
              from: 'B1',
              to: 'B2',
              goingUp: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getCenter(photoFinder()).dy,
        greaterThan(tester.getCenter(find.text('B2')).dy),
      );
    });

    testWidgets('올라갈 때는 도착 층 라벨 위에 붙는다', (tester) async {
      await tester.pumpWidget(
        _host(
          FloorTransitionScrim(
            opacity: 1,
            fadeIn: Duration.zero,
            fadeOut: Duration.zero,
            photoAssets: photo,
            state: _state(
              FloorTransitionStage.moving,
              from: 'B1',
              to: '1F',
              goingUp: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getCenter(photoFinder()).dy,
        lessThan(tester.getCenter(find.text('1F')).dy),
      );
    });

    testWidgets('사진이 없는 층이면 액자도 없다', (tester) async {
      // 주차층에는 원본이 키비주얼을 주지 않는다. 회색 상자를 채워 넣으면
      // "불러오지 못했다"로 읽힌다.
      await tester.pumpWidget(
        _host(
          FloorTransitionScrim(
            opacity: 1,
            fadeIn: Duration.zero,
            fadeOut: Duration.zero,
            state: _state(FloorTransitionStage.moving, goingUp: false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(photoFinder(), findsNothing);
      expect(find.text('B1'), findsOneWidget, reason: '나머지 연출은 그대로다');
    });

    testWidgets('덮개가 짙어진 뒤에 들어온다', (tester) async {
      // 페이드 밑에서 미끄러지면 두 연출이 겹쳐 둘 다 뭉갠다.
      await tester.pumpWidget(
        _host(
          FloorTransitionScrim(
            opacity: 1,
            fadeIn: Duration.zero,
            fadeOut: Duration.zero,
            photoAssets: photo,
            state: _state(
              FloorTransitionStage.moving,
              from: 'B1',
              to: 'B2',
              goingUp: false,
            ),
          ),
        ),
      );
      await tester.pump();

      double opacityNow() => tester
          .widget<Opacity>(
            find.ancestor(of: photoFinder(), matching: find.byType(Opacity)),
          )
          .opacity;

      expect(opacityNow(), 0, reason: '덮개가 짙어지는 동안에는 아직 없다');

      await tester.pump(floorTransitionScrimFadeIn ~/ 2);
      expect(opacityNow(), 0);

      await tester.pumpAndSettle();
      expect(opacityNow(), 1);
    });
  });

  group('사진이 여러 장인 층', () {
    const photos = [
      'assets/floors/6f.webp',
      'assets/floors/6f-2.webp',
      'assets/floors/6f-3.webp',
    ];

    Widget host(WidgetTester tester) => _host(
      const FloorTransitionScrim(
        opacity: 1,
        fadeIn: Duration.zero,
        fadeOut: Duration.zero,
        photoAssets: photos,
        state: FloorTransitionUiState(
          stage: FloorTransitionStage.swapping,
          fromFloorLabel: '5F',
          toFloorLabel: '6F',
          goingUp: true,
        ),
      ),
    );

    /// 지금 몇 번째 장인지. 강조된 점의 자리로 읽는다 — 화면이 실제로 그리는
    /// 값이라, 컨트롤러만 움직이고 표시가 안 따라오는 반쪽 성공을 잡아낸다.
    int shownIndex(WidgetTester tester) {
      for (var i = 0; i < photos.length; i++) {
        final dot = tester.widget<Container>(
          find.byKey(Key('floor-photo-dot-$i')),
        );
        final color = (dot.decoration! as BoxDecoration).color;
        if (color == AppColors.primary) return i;
      }
      return -1;
    }

    testWidgets('장수만큼 점이 서고 첫 장이 강조된다', (tester) async {
      await tester.pumpWidget(host(tester));
      await tester.pump();
      expect(find.byKey(const Key('floor-photo-dot-2')), findsOneWidget);
      expect(find.byKey(const Key('floor-photo-dot-3')), findsNothing);
      expect(shownIndex(tester), 0);
    });

    testWidgets('첫 장도 다른 장과 같은 시간을 받는다', (tester) async {
      // 덮개가 짙어지고 사진이 미끄러져 들어오는 동안은 아직 보고 있는 시간이
      // 아니다. 그만큼을 안 빼면 첫 장만 1.3초 만에 지나가, 실기기에서 "첫 장을
      // 아예 안 보여 준다"로 보였다(2026-08-22).
      await tester.pumpWidget(host(tester));
      await tester.pump();
      await tester.pump(floorPhotoDwellFor(photos.length));
      await tester.pump(const Duration(milliseconds: 600));
      expect(shownIndex(tester), 0, reason: '등장이 끝나기 전부터 세면 안 된다');

      await tester.pump(floorPhotoSettled);
      await tester.pump(const Duration(milliseconds: 600));
      expect(shownIndex(tester), 1);
    });

    testWidgets('가만히 둬도 다음 장으로 넘어간다', (tester) async {
      await tester.pumpWidget(host(tester));
      await tester.pump();
      await tester.pump(floorPhotoSettled + floorPhotoDwellFor(photos.length));
      await tester.pump(const Duration(milliseconds: 600));
      expect(shownIndex(tester), 1);
    });

    testWidgets('마지막 장에서 처음으로 되감지 않는다', (tester) async {
      // 되감으면 덮개가 걷히기 직전에 같은 사진이 두 번 지나가, 몇 장이었는지가
      // 흐려진다.
      await tester.pumpWidget(host(tester));
      await tester.pump();
      await tester.pump(floorPhotoSettled);
      for (var i = 0; i < 5; i++) {
        await tester.pump(floorPhotoDwellFor(photos.length));
        await tester.pump(const Duration(milliseconds: 600));
      }
      expect(shownIndex(tester), photos.length - 1);
    });

    testWidgets('사람이 넘기면 자동 넘김을 놓는다', (tester) async {
      // 보고 있는 사진을 앱이 뺏어 가면 돌아오는 방법이 없다.
      await tester.pumpWidget(host(tester));
      await tester.pump();
      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(shownIndex(tester), 1);

      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(shownIndex(tester), 1, reason: '손으로 넘긴 뒤에는 앱이 더 넘기지 않는다');
    });

    testWidgets('사진이 한 장이면 점을 그리지 않는다', (tester) async {
      await tester.pumpWidget(
        _host(
          const FloorTransitionScrim(
            opacity: 1,
            fadeIn: Duration.zero,
            fadeOut: Duration.zero,
            photoAssets: ['assets/floors/b2.webp'],
            state: FloorTransitionUiState(
              stage: FloorTransitionStage.swapping,
              fromFloorLabel: 'B1',
              toFloorLabel: 'B2',
              goingUp: false,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('floor-photo-dot-0')), findsNothing);
    });

    testWidgets('마지막 장까지 저절로 닿는다', (tester) async {
      // 상한에 걸린 층에서 고정 주기를 쓰면 마지막 장이 뜨기 전에 덮개가 걷힌다.
      const five = [
        'assets/floors/6f.webp',
        'assets/floors/6f-2.webp',
        'assets/floors/6f-3.webp',
        'assets/floors/6f-4.webp',
        'assets/floors/6f-5.webp',
      ];
      await tester.pumpWidget(
        _host(
          const FloorTransitionScrim(
            opacity: 1,
            fadeIn: Duration.zero,
            fadeOut: Duration.zero,
            photoAssets: five,
            state: FloorTransitionUiState(
              stage: FloorTransitionStage.swapping,
              fromFloorLabel: '5F',
              toFloorLabel: '6F',
              goingUp: true,
            ),
          ),
        ),
      );
      await tester.pump();
      // 덮개가 걷히기 시작하는 시각까지 한 장 몫씩 흘린다. 한 번에 뛰면
      // 주기 타이머가 그 안에서 여러 번 돌지 않는다(테스트 시계의 사정이다).
      await tester.pump(floorPhotoSettled);
      var elapsed = floorPhotoSettled;
      final dwell = floorPhotoDwellFor(five.length);
      while (elapsed < floorTransitionScrimHold(five.length)) {
        await tester.pump(dwell);
        await tester.pump(const Duration(milliseconds: 500));
        elapsed += dwell + const Duration(milliseconds: 500);
      }
      // 마지막 넘김의 슬라이드가 끝나야 점이 따라온다.
      await tester.pumpAndSettle();

      final last = tester.widget<Container>(
        find.byKey(const Key('floor-photo-dot-4')),
      );
      expect(
        (last.decoration! as BoxDecoration).color,
        AppColors.primary,
        reason: '덮개가 걷히기 전에 마지막 장까지 닿아야 한다',
      );
    });

    testWidgets('새 전환이면 첫 장으로 되돌아간다', (tester) async {
      // 이 위젯은 층 전환 사이에 살아남는다. 앞 전환에서 넘어간 자리에 남아
      // 있으면 다음 전환이 두 번째 장부터 시작한다.
      await tester.pumpWidget(host(tester));
      await tester.pump();
      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(shownIndex(tester), 1, reason: '테스트 전제(넘김)가 성립하지 않았다');

      // 덮개가 걷혔다가 다시 올라온다 = 새 전환.
      await tester.pumpWidget(
        _host(
          const FloorTransitionScrim(
            opacity: 0,
            fadeIn: Duration.zero,
            fadeOut: Duration.zero,
            photoAssets: photos,
            state: FloorTransitionUiState(
              stage: FloorTransitionStage.swapping,
              fromFloorLabel: '5F',
              toFloorLabel: '6F',
              goingUp: true,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(host(tester));
      await tester.pumpAndSettle();

      expect(shownIndex(tester), 0);
    });
  });
}
