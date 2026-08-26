// 제품 화면과 분리된 heading 진단 엔트리포인트.
//
// 제품 앱은 **실내에 진입해야** PDR 세션을 켜서, 건물 밖에서는 heading 로그가
// 전부 빈다. 기기가 방위를 어떻게 내는지 보려고 매번 백화점에 가야 하는 것을
// 막는 자리다. 센서만 곧바로 띄우고 제품과 같은 포매터로 같은 줄을 찍는다.
//
// `flutter run -t lib/heading_probe_main.dart --dart-define-from-file=config.local.json`
// 앵커·지도 토막은 비어 있다 — 그 둘은 제품 앱의 칩과 로그로 본다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:indoor_pdr_core/indoor_pdr_core.dart';

import 'features/indoor_navigation/application/indoor_navigation_controller.dart';
import 'features/indoor_navigation/platform/android_pdr_motion_source.dart';
import 'screens/outdoor_map/entry/heading_log.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: _HeadingProbe()));
}

class _HeadingProbe extends StatefulWidget {
  const _HeadingProbe();

  @override
  State<_HeadingProbe> createState() => _HeadingProbeState();
}

class _HeadingProbeState extends State<_HeadingProbe> {
  late final AndroidPdrMotionSource _source;
  late final IndoorNavigationDriver _driver;
  StreamSubscription<PdrSnapshot>? _sub;
  String _line = '센서 시작 중';
  DateTime _lastLog = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _source = AndroidPdrMotionSource();
    _driver = IndoorNavigationDriver(source: _source);
    _sub = _driver.snapshots.listen(_onSnapshot);
    unawaited(_driver.startGuidance(floorId: 'heading-probe-floor'));
  }

  void _onSnapshot(PdrSnapshot snapshot) {
    final now = DateTime.now();
    if (now.difference(_lastLog) < const Duration(seconds: 1)) return;
    _lastLog = now;
    final f = snapshot.quality.features;
    final line = describeHeadingLog(
      deviceBearingDeg: f.deviceHeadingDeg,
      gyroBearingDeg: f.gyroHeadingDeg,
      orientationBearingDeg: snapshot.orientationHeadingDeg,
      walkingBearingDeg: snapshot.walkingHeadingDeg,
      walkOffsetDeg: f.walkOffsetDeg,
      headingConverged: f.headingConverged,
      magneticFieldUt: f.magneticFieldUt,
      magneticInclinationDeg: f.magneticInclinationDeg,
      headingErrorDeg: f.rotationHeadingAccuracyDeg,
      magneticAccuracy: f.magneticAccuracy,
      headingSource: f.headingSource,
      anchorRotationDeg: null,
      calibrationPhase: _driver.currentCalibration.phase.name,
      headingTrustworthy: f.headingTrustworthy,
      markerBearingDeg: null,
      cameraBearingDeg: 0,
    );
    debugPrint(line);
    if (mounted) setState(() => _line = line);
  }

  @override
  void dispose() {
    _sub?.cancel();
    unawaited(_driver.stopGuidance());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Text(_line, style: const TextStyle(fontSize: 13)),
        ),
      ),
    ),
  );
}
