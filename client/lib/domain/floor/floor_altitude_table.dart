/// 건물의 **층별 기압고도표**. 어떤 값을 어떻게 쟀는지는
/// `docs/client/elevator-altitude-probe.md`가 단일 출처다.
library;

/// 층 하나가 기준 층에서 얼마나 떨어져 있나(m). 값의 절대 크기는 뜻이 없고
/// **층 사이의 차이만** 쓴다 — 해면기압이 날마다 바뀌므로 절대 고도로는 못 쓴다.
typedef FloorAltitudeTable = Map<String, double>;

/// 더현대 서울 실측(2026-08-24, SM-S918N). 기준은 B2 = 0.
///
/// 지하가 지상의 절반 남짓이다(3.23~4.83 m 대 5.33~7.11 m). 이 불균일이 곧
/// "층고 상수 하나로는 못 센다"의 근거이며, 표를 두는 이유다.
const _thehyundaiSeoul = <String, double>{
  'B6': -15.38,
  'B5': -10.55,
  'B4': -6.77,
  'B3': -3.54,
  'B2': 0.00,
  'B1': 5.83,
  '1F': 12.94,
  '2F': 18.50,
  '3F': 23.89,
  '4F': 29.23,
  '5F': 34.56,
  '6F': 39.93,
};

/// 건물별 표. **없는 건물은 null이다** — 모르는 건물에 남의 층고를 갖다 쓰면
/// 조용히 틀린 층으로 옮겨 놓는다. 표가 없으면 층을 자동으로 안 바꾸는 편이 낫다.
const _tables = <String, FloorAltitudeTable>{
  'thehyundai-seoul': _thehyundaiSeoul,
};

FloorAltitudeTable? floorAltitudeTableFor(String? buildingId) =>
    buildingId == null ? null : _tables[buildingId];

/// [fromFloor]에서 [deltaM]만큼 오르내렸을 때 닿은 층. 못 고르면 null.
///
/// 두 가지로 거른다. **2등과의 여유**([minMarginM])와 **1등까지의 거리**
/// ([maxErrorM])다. 어느 쪽이 걸려도 층을 안 바꾼다 — 반 층 어중간한 자리에서
/// 억지로 고르면 한 층 틀린 도면을 확신에 차서 띄우게 된다.
///
/// 여유 규칙을 푼 값: 이웃 두 층 간격이 G이고 목표가 가까운 층에서 d만큼
/// 떨어져 있으면 통과 조건은 `G - 2d >= minMarginM`, 곧 `d <= (G-m)/2`다.
/// 최소 간격 B4→B3의 3.23 m에서 1.0을 넣으면 1.11 m까지 허용되고, 센서
/// 노이즈 ±0.1~0.3 m의 3.7배다. 지상(5.33 m)에서는 2.16 m까지 늘어난다.
///
/// [maxErrorM]이 없으면 **후보가 하나뿐일 때** 2등이 없어 어떤 Δ든 통과한다
/// ([servedFloors]로 좁히면 실제로 생긴다). 그 구멍을 막는 절대 상한이다.
///
/// [servedFloors]를 주면 그 층들만 후보로 본다. 엘리베이터는 호기마다 서는 층이
/// 달라서(더현대 EV6은 5F·지하 3~6층에 안 선다), 못 서는 층을 후보에서 빼면
/// 남의 층에 선 것을 도착으로 오인할 여지가 줄어든다.
String? floorAtDelta({
  required FloorAltitudeTable table,
  required String fromFloor,
  required double deltaM,
  Iterable<String>? servedFloors,
  double minMarginM = 1.0,
  double maxErrorM = 2.0,
}) {
  final from = table[fromFloor];
  if (from == null) return null;
  final target = from + deltaM;
  final allowed = servedFloors?.toSet();

  String? best;
  var bestGap = double.infinity;
  var runnerUpGap = double.infinity;
  for (final entry in table.entries) {
    if (allowed != null && !allowed.contains(entry.key)) continue;
    final gap = (entry.value - target).abs();
    if (gap < bestGap) {
      runnerUpGap = bestGap;
      bestGap = gap;
      best = entry.key;
    } else if (gap < runnerUpGap) {
      runnerUpGap = gap;
    }
  }
  if (best == null) return null;
  if (bestGap > maxErrorM) return null;
  if (runnerUpGap.isFinite && runnerUpGap - bestGap < minMarginM) return null;
  return best;
}

/// [from]에서 [to]까지의 고도차(m). 둘 중 하나라도 표에 없으면 null.
double? floorGapM({
  required FloorAltitudeTable table,
  required String from,
  required String to,
}) {
  final a = table[from];
  final b = table[to];
  return (a == null || b == null) ? null : b - a;
}

/// [floor]에서 **가장 가까운 다른 층**까지의 거리(m). 그 층에서의 "한 층"이다.
///
/// 층고가 층마다 다르므로(3.23~7.11 m) "반 층 이내인가"를 물으려면 상수가 아니라
/// 이 값이 필요하다. 표에 층이 하나뿐이거나 없으면 null.
double? nearestFloorGapM({
  required FloorAltitudeTable table,
  required String floor,
}) {
  final here = table[floor];
  if (here == null) return null;
  var nearest = double.infinity;
  for (final entry in table.entries) {
    if (entry.key == floor) continue;
    final gap = (entry.value - here).abs();
    if (gap < nearest) nearest = gap;
  }
  return nearest.isFinite ? nearest : null;
}
