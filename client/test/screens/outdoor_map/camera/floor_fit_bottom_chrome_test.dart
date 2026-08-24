import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/screens/outdoor_map/outdoor_map_tuning.dart';

/// 층 도면 fit이 **아래에서 비우는 높이**의 검증 기준.
///
/// 증상: 편의시설 시트를 연 채 그 아래 층 선택기를 누르면, 층은 바뀌는데
/// 배율이 이전 층 그대로인 것처럼 보였다. 층 fit이 하단 바만 센 상수
/// ([floorFitBottomChromePx])로 도면을 화면 **전체**에 맞춰, 아래 절반이 화면의
/// 40%를 덮는 시트 뒤로 들어간 것이다.
void main() {
  // 아이폰 15 논리 크기 기준 시설 시트 높이(kFacilitySheetHeightFraction 0.42).
  const facilitySheetPx = 852 * 0.42;

  test('아래에 판이 없으면 하단 바 어림값 그대로다', () {
    expect(floorFitBottomChromeFor(0), floorFitBottomChromePx);
  });

  test('판이 하단 바보다 낮아도 어림값 아래로는 안 내려간다', () {
    // 탭 줄(56)만 있는 평상시. 하단 바는 그보다 높으므로 상수가 이긴다.
    expect(floorFitBottomChromeFor(56), floorFitBottomChromePx);
  });

  test('시설 시트가 떠 있으면 그 높이만큼 비운다', () {
    expect(floorFitBottomChromeFor(facilitySheetPx), facilitySheetPx);
  });
}
