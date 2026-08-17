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

/// 자력계 정확도가 **절대 방위를 맡길 만한가**.
///
/// native가 주는 문자열은 high·medium·low·uncalibrated·unknown이다.
///
/// **"나쁘다는 증거"가 있을 때만 거부한다.** `unknown`(아직 정확도 콜백이 안 옴)
/// 까지 거부하면 세션 초반마다 방향 질문이 뜨고, iOS는 사용자가 폰을 흔들기 전까지
/// `uncalibrated`에 머무는 일이 잦아 정상 기기에서도 창이 반복된다. 잘못 걸리는
/// 비용(매번 모달)이 놓치는 비용보다 크고, 놓치는 쪽은 사용자가 지도를 직접 찍어
/// 언제든 고칠 수 있다(`confirmAnchorByPin`의 requireDirection).
bool isTrustedMagneticAccuracy(String accuracy) =>
    accuracy != 'low' && accuracy != 'uncalibrated';

/// 지금 heading의 **절대 방위를 앵커 확정에 맡겨도 되는가.**
///
/// [headingReferenceFromSource]와 **반드시 갈라 둔다.** 저쪽은 "이 값이 자북
/// frame인가"라는 성질이고, 이쪽은 "그 frame이 지금 맞는가"라는 상태다.
///
/// 둘을 한 함수로 합쳤던 적이 있고, 그것이 실내 방향을 90° 틀어 놓은 회귀였다 —
/// `gyro_hold`를 frame 판정에서 뺐더니(맞는 변경이다) 품질 판정까지 함께
/// 사라져, 자력계가 교란된 실내에서 보정 없이 방위가 확정됐다. 근거와 경위는
/// `docs/client/android-heading-drift.md` 6절.
bool isTrustedHeading({
  required String source,
  required String magneticAccuracy,
}) =>
    headingReferenceFromSource(source) == HeadingReference.magneticNorth &&
    isTrustedMagneticAccuracy(magneticAccuracy) &&
    // hold가 걸렸다는 것 자체가 "자력계를 지금 못 믿는다"는 판정 결과다.
    !source.contains('gyro_hold');
