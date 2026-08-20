/// PDR heading이 어느 기준 frame인지.
///
/// iOS는 `.xMagneticNorthZVertical`을 우선 쓰되 미가용 시
/// `.xArbitraryCorrectedZVertical`로 fallback한다. 후자는 yaw가 자북 기준이 아니라
/// 서버의 자북 정렬각을 적용하면 안 되고 수동 방향 보정이 필요하다(§4).
enum HeadingReference { magneticNorth, arbitraryCorrected }

/// native headingSource 문자열에서 reference를 판별한다.
HeadingReference headingReferenceFromSource(String? source) {
  if (source != null && source.contains('xMagneticNorthZVertical')) {
    return HeadingReference.magneticNorth;
  }
  // Android FusedOrientationProvider는 Play Services가 원시 센서에서 다시
  // 융합한 자세이고, heading은 자북 기준이다. 벤더 rotation vector와 같은
  // 이유로 gyro hold 중에도 기준 frame은 자북으로 남는다.
  if (source != null && source.contains('fused_orientation_provider')) {
    return HeadingReference.magneticNorth;
  }
  // Android TYPE_ROTATION_VECTOR는 자력계·자이로·가속도 융합으로 지자기 북을
  // 기준으로 한다. 자력 교란 때 잠시 gyro hold를 하더라도, 이 값은 마지막
  // rotation-vector frame에서 적분을 이어가므로 기준 frame 자체는 자북이다.
  // 품질 저하는 HeadingEvent.headingStable로 별도 전달된다. 반면
  // GAME_ROTATION_VECTOR/순수 gyro hold는 절대 기준이 아니므로 제외한다.
  if (source != null &&
      source.contains('rotation_vector') &&
      !source.contains('game_rotation_vector')) {
    return HeadingReference.magneticNorth;
  }
  if (source != null && source.contains('xArbitraryCorrectedZVertical')) {
    return HeadingReference.arbitraryCorrected;
  }
  // 아직 heading을 못 받았거나 알 수 없으면 보수적으로 자북으로 가정하지 않는다.
  return HeadingReference.arbitraryCorrected;
}

/// 이 방위를 **앵커에 구워 넣어도 되는** 오차 상한(도).
///
/// 두 값 사이에 끼워 잡았다.
///   - 위: 브리지가 gyro hold를 켜는 문턱이 35°다. hold를 켤 만큼 나쁜 방위가
///     앵커에 들어가면 안 되므로 그보다 낮아야 한다.
///   - 아래: 마커 원뿔의 반각이 31°다. 그보다 작은 오차는 원뿔 안에 들어가
///     화면에서 구분되지 않는다 — 거기까지 거부하면 얻는 것 없이 정상 세션만
///     흔든다.
const trustedHeadingErrorDeg = 30.0;

/// 센서가 **스스로 보고한** heading 오차로 "지금 이 방위를 믿어도 되는지".
///
/// [errorDeg]는 안드로이드 FusedOrientationProvider의 `headingErrorDegrees`이고,
/// FOP가 없으면 rotation vector의 `values[4]`다. **음수는 "모른다"는 뜻이라
/// 통과시킨다** — 벤더가 값을 안 채우는 기기(SM-G996N은 −1을 준다)에서 거부하면
/// 그 기기의 앵커가 통째로 막힌다. 나쁘다는 **증거가 있을 때만** 거부한다.
///
/// iOS에는 이 판정이 필요 없다. CoreMotion이 자력계 보정을 안에서 하고, 못 하면
/// reference frame 자체를 `xArbitraryCorrectedZVertical`로 낮춰 신고하므로
/// [headingReferenceFromSource]가 이미 걸러 낸다.
bool isHeadingErrorTrusted(
  double errorDeg, {
  double maxErrorDeg = trustedHeadingErrorDeg,
}) {
  if (errorDeg < 0) return true;
  return errorDeg <= maxErrorDeg;
}
