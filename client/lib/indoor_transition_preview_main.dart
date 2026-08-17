/// 실내 전환 연출 미리보기 엔트리포인트.
///
///     flutter run -t lib/indoor_transition_preview_main.dart
///
/// 지도·GPS·센서를 하나도 안 쓰므로 `--dart-define-from-file` 없이 데스크톱에서도
/// 돈다. 곡선을 고치려고 건물을 드나들 수 없어서 만든 자리다.
library;

import 'package:flutter/material.dart';

import 'screens/outdoor_map/transition/indoor_transition_preview.dart';

void main() {
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: IndoorTransitionPreview(),
    ),
  );
}
