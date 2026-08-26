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

/// 지구 자기장으로 설명되는 세기의 하한·상한(µT).
///
/// 지표 실측은 어디서나 25~65다. 양쪽에 여유를 둔 이유는 이 판정으로 **거부**를
/// 하기 때문이다 — 센서 bias나 약한 실내 왜곡까지 잡으면 얻는 것 없이 정상
/// 세션만 흔든다. 잡으려는 것은 배수로 벌어지는 값이다.
///
/// **위도와 무관하다.** 그래서 이 판정만 코어에 있다. 자기 복각도 같은 왜곡을
/// 더 예민하게 잡지만 기대값이 위도로 정해져, 위치를 모르는 이 층에서는 문턱을
/// 세울 수 없다(진단으로만 띄운다).
const minPlausibleFieldUt = 20.0;
const maxPlausibleFieldUt = 80.0;

/// 이 자기장 **세기**가 지구 자기장으로 설명되는가.
///
/// [isHeadingErrorTrusted]와 하는 일이 같고 근거가 다르다. 저쪽은 기기가 스스로
/// 신고한 값을 읽고, 이쪽은 **관측값**을 읽는다. 그 차이가 결정적인 기기가 있다 —
/// 실측에서 SM-F711N은 heading 오차를 −1로, 자력계 정확도를 `unknown`으로 줘서
/// 신고 기반 판정이 전부 통과하는데, 그 자리의 세기는 100.7 µT(지구의 2.0배)에
/// 복각은 −25°였다(서울 기대값 +53°). 나침반이 지구가 아닌 것을 보고 있었다.
///
/// 값을 못 받았으면(null·0 이하) 참이다 — 나쁘다는 증거가 있을 때만 거부한다는
/// 규칙은 여기서도 같다.
///
/// **남는 구멍.** 하드아이언 오프셋이 작아 세기가 범위 안에 머물면서 방향만
/// 틀어지는 경우는 못 잡는다. 이 판정은 배수로 벌어진 것만 잡는다.
bool isMagneticFieldPlausible(double? fieldUt) {
  if (fieldUt == null || fieldUt <= 0) return true;
  return fieldUt >= minPlausibleFieldUt && fieldUt <= maxPlausibleFieldUt;
}
