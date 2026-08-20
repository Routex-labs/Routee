/// 지도 축척 막대가 **얼마를 얼마 길이로** 그릴지 정하는 산수.
///
/// 정책이 아니라 계산이라 [zoom_math.dart] 옆에 둔다. 어디에 그릴지·어떻게
/// 생겼는지는 화면이 갖는다.
library;

import 'dart:math' as math;

import 'zoom_math.dart';

/// 막대가 나타낼 거리와 그 거리가 화면에서 차지하는 폭.
class MapScaleStep {
  const MapScaleStep({required this.meters, required this.widthPx});

  /// 막대 하나가 뜻하는 실제 거리(m). 항상 1·2·5 × 10ⁿ 중 하나다.
  final double meters;

  /// 그 거리를 그릴 논리 픽셀 폭.
  final double widthPx;

  /// 막대 옆에 적을 글자.
  ///
  /// **1 km부터는 km로 적는다.** m로만 적으면 시내 배율에서 `10000m`이 되는데,
  /// 자릿수를 세어야 읽히는 숫자는 축척으로 쓸모가 없다. 실내 배율은 10~100 m
  /// 대라 사실상 늘 m다.
  String get label {
    if (meters >= 1000) {
      final km = meters / 1000;
      final text = km == km.roundToDouble()
          ? km.round().toString()
          : km.toStringAsFixed(1);
      return '${text}km';
    }
    return '${meters.round()}m';
  }
}

/// 후보 유효숫자. 큰 것부터 본다 — [maxWidthPx]를 넘지 않는 **가장 큰** 값이
/// 막대를 가장 길게 만들고, 긴 막대일수록 눈대중 오차가 작다.
const _niceFactors = <double>[5, 2, 1];

/// 축척 막대 한 칸을 정한다. 값을 정할 수 없으면 null.
///
/// [metersPerPixel]이 0·음수·무한이면 null이다 — 카메라가 아직 준비되지 않은
/// 프레임에서 그 값이 온다. 막대 없이 지나가는 편이 0 나눗셈으로 터지는 것보다 낫다.
///
/// [maxWidthPx]는 막대가 커질 수 있는 상한이고, 실제 폭은 그보다 짧다(딱 떨어지는
/// 값으로 내리므로). 1 m 아래로는 내려가지 않는다 — 실내 도면을 최대로 당겨도
/// 1 m가 눈에 보이는 길이라, 그 아래는 축척이 아니라 잡음이다.
MapScaleStep? mapScaleStepFor({
  required double metersPerPixel,
  required double maxWidthPx,
}) {
  if (!metersPerPixel.isFinite || metersPerPixel <= 0) return null;
  if (!maxWidthPx.isFinite || maxWidthPx <= 0) return null;

  final span = metersPerPixel * maxWidthPx;
  if (!span.isFinite || span <= 0) return null;

  final magnitude = math.pow(10, (math.log(span) / math.ln10).floor()).toDouble();
  var meters = magnitude;
  for (final factor in _niceFactors) {
    final candidate = magnitude * factor;
    if (candidate <= span) {
      meters = candidate;
      break;
    }
  }
  meters = math.max(1, meters);
  return MapScaleStep(meters: meters, widthPx: meters / metersPerPixel);
}

/// [zoom]·[latitude]에서의 픽셀당 미터. [visibleWidthMeters]와 같은 식이라
/// 두 값이 어긋날 수 없다.
double metersPerPixelAt({required double zoom, required double latitude}) =>
    visibleWidthMeters(zoom: zoom, availablePx: 1, latitude: latitude);
