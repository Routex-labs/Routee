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
