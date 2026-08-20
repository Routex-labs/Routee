import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/screens/outdoor_map/layers/indoor_overlay_layers.dart';

/// 실내 오버레이 id 세대 규칙을 고정한다.
///
/// 층을 바꿀 때 소스·레이어 id가 **하나도 빠짐없이** 새 세대로 넘어가야 한다.
/// 하나라도 이전 세대 id로 남으면 그 레이어만 remove 대상에서 새고, 다음 등록이
/// "layer already exists"로 조용히 실패해 그 층만 아무것도 안 그려진다. 화면이
/// 필드 11개를 손으로 갱신하던 시절 실제로 나던 종류의 사고다.
void main() {
  test('같은 세대의 id는 전부 같은 접미사를 단다', () {
    const ids = IndoorOverlayIds(3);
    final all = [ids.source, ...ids.layersTopFirst];
    for (final id in all) {
      expect(id, endsWith('-g3'), reason: '$id가 세대 접미사를 안 달았다');
    }
  });

  test('세대를 넘기면 소스·레이어 id가 하나도 겹치지 않는다', () {
    const before = IndoorOverlayIds();
    final after = before.next();
    final beforeAll = {before.source, ...before.layersTopFirst};
    final afterAll = {after.source, ...after.layersTopFirst};

    expect(after.generation, before.generation + 1);
    expect(
      beforeAll.intersection(afterAll),
      isEmpty,
      reason: '겹치는 id가 있으면 native remove/add 경쟁이 되살아난다',
    );
  });

  test('한 세대 안에서 id가 서로 겹치지 않는다', () {
    const ids = IndoorOverlayIds();
    final all = [ids.source, ...ids.layersTopFirst];
    expect(all.toSet().length, all.length, reason: '같은 id를 두 레이어가 쓰면 하나가 덮인다');
  });

  test('레이어 목록은 위에서 아래 순서다', () {
    // removeLayer를 이 순서로 그대로 돌린다. 순서가 뒤집히면 아래 레이어를 먼저
    // 지우게 되는데, 그 자체는 동작하지만 등록 순서(=쌓임 순서)와 어긋나 다음에
    // 읽는 사람이 z-order를 반대로 이해한다.
    const ids = IndoorOverlayIds();
    expect(ids.layersTopFirst.first, ids.storeFacilityIcon);
    expect(ids.layersTopFirst.last, ids.footprint);
    expect(ids.layersTopFirst.length, 10);
  });

  test('못 걷는 면은 매장 fill 바로 위·카테고리 강조 바로 아래다', () {
    // 이 한 자리를 벗어나면 화면이 둘 중 하나로 깨진다 — 매장 fill 아래로
    // 내려가면 지하 주차칸 폴리곤에 기둥 면적의 40%가 가리고(그 위 흰 바닥까지
    // 내려가면 2026-08-15 되돌림 2번의 "픽셀 0"), 카테고리 강조 위로 올라가면
    // 강조·수직이동 색이 회색에 덮인다. 위 테스트는 목록의 첫·마지막만 보므로
    // 가운데가 바뀌어도 안 걸린다.
    const ids = IndoorOverlayIds();
    final order = ids.layersTopFirst;
    expect(
      order.indexOf(ids.storesFill),
      order.indexOf(ids.nonWalkableFill) + 1,
      reason: '매장 fill 바로 위가 아니다',
    );
    expect(
      order.indexOf(ids.nonWalkableFill),
      order.indexOf(ids.categoryHighlightFill) + 1,
      reason: '카테고리 강조 바로 아래가 아니다',
    );
  });

  test('베이스 이름은 kebab-case이고 밑줄로 시작하지 않는다', () {
    // 층 지도와 같은 명명 규칙이다. 어긋나면 스타일 디버깅에서 어느 화면이
    // 만든 레이어인지 구분이 안 된다.
    const ids = IndoorOverlayIds();
    for (final id in [ids.source, ...ids.layersTopFirst]) {
      expect(id, matches(RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$')), reason: id);
    }
  });
}
