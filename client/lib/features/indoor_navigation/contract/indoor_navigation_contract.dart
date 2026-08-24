/// 실내 내비게이션 UI 연동 계약 (Phase 1.5).
///
/// UI가 의존하는 공개 표면 — 여기 있는 것만 import하고, 구현체끼리 서로의 내부를
/// 보지 않는다. 읽기는 [IndoorNavigationView], 쓰기는 [IndoorNavigationIntents],
/// 좌표 변환은 [FloorCoordinateTransform]이다.
///
/// 코어 타입(PdrSnapshot 등)은 indoor_pdr_core를 그대로 재노출한다.
library;

export 'package:indoor_pdr_core/indoor_pdr_core.dart'
    show
        PdrSnapshot,
        PdrPreview,
        PdrQuality,
        PdrQualityState,
        PdrQualityFeatures,
        PdrLocalPoint,
        HeadingReference;

export 'altitude_sample.dart';
export 'calibration_state.dart';
export 'indoor_navigation_intents.dart';
export 'indoor_navigation_view.dart';
export 'pdr_anchor.dart';
export 'pdr_heading_sample.dart';
export 'pdr_runtime_status.dart';
export 'raw_motion_activity.dart';

import 'indoor_navigation_intents.dart';
import 'indoor_navigation_view.dart';

/// 관찰(View) + 명령(Intents)을 함께 제공하는 컨트롤러 계약.
/// 구현체는 Phase 2에서 headless 로직으로 만든다.
abstract interface class IndoorNavigationController
    implements IndoorNavigationView, IndoorNavigationIntents {}
