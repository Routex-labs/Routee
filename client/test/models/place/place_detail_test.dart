import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/models/place/place_detail.dart';

void main() {
  test('알 수 없는 섹션은 버리고 알려진 섹션은 파싱한다', () {
    final detail = PlaceDetail.fromJson({
      'kind': 'store',
      'id': 'store-1',
      'name': '테스트 매장',
      'subtitle': '1F · 패션',
      'category': '패션',
      'subcategory': '여성패션',
      'location': {
        'building_id': 'building-1',
        'floor_label': '1F',
        'position_local_m': {'x': 12.5, 'y': 4},
        'entrance_node_id': 'node-1',
      },
      'actions': [
        {'type': 'directions', 'label': '길찾기'},
      ],
      'sections': [
        {'type': 'summary', 'text': '한 줄 소개'},
        {'type': 'futureSection', 'value': '구버전은 무시'},
        {
          'type': 'keyValue',
          'items': [
            {'label': '위치', 'value': '1F 동편'},
          ],
        },
      ],
      'provenance': {'source': 'studio', 'updated_at': null},
    });

    expect(detail.kind, PlaceKind.store);
    expect(detail.location.positionLocalM?.x, 12.5);
    expect(detail.sections, hasLength(2));
    expect(detail.sections.first, isA<SummarySection>());
    expect(detail.sections.last, isA<KeyValueSection>());
  });

  test('확장된 매장 상세 섹션을 파싱한다', () {
    final detail = PlaceDetail.fromJson({
      'kind': 'store',
      'id': 'store-1',
      'name': '더현대서울(B2)R',
      'subtitle': 'B2 · 카페',
      'category': '식음료',
      'subcategory': '카페',
      'location': {'building_id': 'building-1'},
      'actions': <Object?>[],
      'sections': [
        {
          'type': 'hero',
          'items': [
            {'local_asset': 'assets/place_details/starbucks_store_01.jpg'},
          ],
        },
        {
          'type': 'menu',
          'items': [
            {
              'name': '카페 아메리카노',
              'price': '4,700원',
              'description': '진하고 풍부한 에스프레소 샷에 물을 더한 커피',
              'image_asset': 'assets/place_details/starbucks_menu_94.jpg',
            },
          ],
        },
        {
          'type': 'demoInfo',
          'items': [
            {
              'label': '영업시간',
              'value': '화~목 10:30-20:00',
              'source': 'https://www.starbucks.co.kr/store/store_map.do',
              'confirmed_at': '2026-08-10',
            },
          ],
        },
        {
          'type': 'businessInfo',
          'items': [
            {'label': '대표번호', 'value': '1522-3232'},
          ],
        },
        {'type': 'futureSection'},
      ],
      'provenance': {'source': 'manual', 'updated_at': '2026-07-30'},
    });

    final hero = detail.sections[0] as HeroSection;
    final menu = detail.sections[1] as MenuSection;
    final demoInfo = detail.sections[2] as DemoInfoSection;
    final businessInfo = detail.sections[3] as BusinessInfoSection;

    expect(detail.sections, hasLength(4));
    expect(hero.items.single.localAsset, 'assets/place_details/starbucks_store_01.jpg');
    expect(menu.items.single.name, '카페 아메리카노');
    expect(menu.items.single.price, '4,700원');
    expect(menu.items.single.description, '진하고 풍부한 에스프레소 샷에 물을 더한 커피');
    expect(menu.items.single.imageAsset, 'assets/place_details/starbucks_menu_94.jpg');
    expect(demoInfo.items.single.label, '영업시간');
    expect(demoInfo.items.single.confirmedAt, '2026-08-10');
    expect(businessInfo.items.single.label, '대표번호');
    expect(businessInfo.items.single.value, '1522-3232');
  });

  // 서버는 값이 없는 선택 키를 빈 문자열로 채우지 않고 키 자체를 뺀다(계약 4-2 규칙 1).
  // 이 테스트가 없으면 `price`를 필수로 되돌려도 아무 데서도 실패하지 않고, 가격을
  // 공개하지 않는 매장에서 상세 시트가 통째로 죽는다.
  test('가격 없는 메뉴를 파싱한다', () {
    final detail = PlaceDetail.fromJson({
      'kind': 'store',
      'id': 'store-1',
      'name': '더현대서울(B2)R',
      'subtitle': 'B2 · 카페',
      'location': {'building_id': 'building-1'},
      'actions': <Object?>[],
      'sections': [
        {
          'type': 'menu',
          'items': [
            {
              'name': '리저브 콜드 브루',
              'image_asset': 'assets/place_details/starbucks_menu_9200000002093.jpg',
              'category': '리저브',
              'name_en': 'Reserve Cold Brew',
              'volume': '355ml',
              'calories': '5kcal',
              'caffeine': '190mg',
            },
          ],
        },
      ],
      'provenance': {'source': 'manual', 'updated_at': '2026-08-10'},
    });

    final item = (detail.sections.single as MenuSection).items.single;

    expect(item.price, isNull);
    expect(item.description, isNull);
    expect(item.category, '리저브');
    expect(item.nameEn, 'Reserve Cold Brew');
    expect(item.volume, '355ml');
    expect(item.calories, '5kcal');
    expect(item.caffeine, '190mg');
    // 알레르기·배지도 같은 규칙이다. 배지만 빈 목록인 이유는 화면이 이 값을 "0개
    // 이상 그린다"로만 쓰기 때문이고, 그래서 null 검사가 위젯에 생기지 않는다.
    expect(item.allergens, isNull);
    expect(item.badges, isEmpty);
  });

  // 알레르기·배지는 메뉴 316종을 채우면서 연 필드다. 서버는 값이 있을 때만 키를
  // 실으므로, 있는 경우와 없는 경우를 한 응답 안에서 같이 본다.
  test('알레르기와 배지를 파싱한다', () {
    final detail = PlaceDetail.fromJson({
      'kind': 'store',
      'id': 'store-1',
      'name': '더현대서울(B2)R',
      'subtitle': 'B2 · 카페',
      'location': {'building_id': 'building-1'},
      'actions': <Object?>[],
      'sections': [
        {
          'type': 'menu',
          'items': [
            {
              'name': '씨솔트 카라멜 콜드 브루',
              'image_asset': 'assets/place_details/starbucks_menu_9200000004544.jpg',
              'allergens': '우유',
              'badges': ['NEW', '시즌 한정'],
            },
            {
              'name': '블루베리 베이글',
              'image_asset': 'assets/place_details/starbucks_menu_9300000004823.jpg',
            },
          ],
        },
      ],
      'provenance': {'source': 'manual', 'updated_at': '2026-08-11'},
    });

    final items = (detail.sections.single as MenuSection).items;

    expect(items.first.allergens, '우유');
    expect(items.first.badges, ['NEW', '시즌 한정']);
    expect(items.last.allergens, isNull);
    expect(items.last.badges, isEmpty);
  });

  // 배지 키에 배열이 아닌 값이 오면 그 항목만 배지가 없는 것으로 읽는다.
  //
  // `as List` 캐스트로 받으면 파싱이 통째로 던지고, 배지 한 건 때문에 메뉴 316종이
  // 상세 시트에서 사라진다. 서버 검증기가 형식을 막고 있지만 구버전·다른 배포가
  // 섞이는 경우까지 클라이언트가 죽을 이유는 없다.
  test('배지가 배열이 아니어도 메뉴를 잃지 않는다', () {
    final detail = PlaceDetail.fromJson({
      'kind': 'store',
      'id': 'store-1',
      'name': '더현대서울(B2)R',
      'subtitle': 'B2 · 카페',
      'location': {'building_id': 'building-1'},
      'actions': <Object?>[],
      'sections': [
        {
          'type': 'menu',
          'items': [
            {
              'name': '씨솔트 카라멜 콜드 브루',
              'image_asset': 'assets/place_details/starbucks_menu_9200000004544.jpg',
              'badges': 'NEW',
            },
          ],
        },
      ],
      'provenance': {'source': 'manual', 'updated_at': '2026-08-11'},
    });

    final item = (detail.sections.single as MenuSection).items.single;

    expect(item.name, '씨솔트 카라멜 콜드 브루');
    expect(item.badges, isEmpty);
  });

  // 영업시간만 값이 그리는 것이 아니라 **계산 대상**이다. 구조가 하나라도 어긋나면
  // 판정이 조용히 틀리므로, 요일 7개·구간 배열·예외·오프셋이 그대로 들어오는지 본다.
  test('영업시간 섹션을 구조 그대로 파싱한다', () {
    final detail = PlaceDetail.fromJson({
      'kind': 'store',
      'id': 'store-1',
      'name': '더현대서울(B2)R',
      'subtitle': 'B2 · 카페',
      'location': {'building_id': 'building-1'},
      'actions': <Object?>[],
      'sections': [
        {
          'type': 'hours',
          'weekly': {
            'mon': <Object?>[],
            'tue': [
              {'open': '11:00', 'close': '14:00'},
              {'open': '17:00', 'close': '21:00'},
            ],
            'wed': [
              {'open': '10:30', 'close': '20:00'},
            ],
            'thu': <Object?>[],
            'fri': <Object?>[],
            'sat': <Object?>[],
            'sun': <Object?>[],
          },
          'exceptions': [
            {
              'date': '2026-09-17',
              'closed': true,
              'intervals': <Object?>[],
              'note': '백화점 정기 휴점',
            },
          ],
          'utc_offset_minutes': 540,
          'confirmed_at': '2026-08-10',
        },
      ],
      'provenance': {'source': 'manual', 'updated_at': '2026-08-10'},
    });

    final hours = detail.sections.single as HoursSection;

    expect(hours.weekly.keys.toSet(), {
      'mon',
      'tue',
      'wed',
      'thu',
      'fri',
      'sat',
      'sun',
    });
    // 브레이크 타임. 요일당 구간이 하나라고 가정하면 여기서 한 구간이 사라진다.
    expect(hours.weekly['tue']!.length, 2);
    expect(hours.weekly['tue']!.last.open, '17:00');
    expect(hours.weekly['mon'], isEmpty);
    expect(hours.exceptions.single.date, '2026-09-17');
    expect(hours.exceptions.single.closed, isTrue);
    expect(hours.exceptions.single.note, '백화점 정기 휴점');
    expect(hours.utcOffsetMinutes, 540);
    expect(hours.confirmedAt, '2026-08-10');
  });

  test('연락처 섹션은 번호와 함께 출처·확인일을 갖는다', () {
    final detail = PlaceDetail.fromJson({
      'kind': 'store',
      'id': 'store-1',
      'name': '보테가 베네타',
      'subtitle': '1F · 패션',
      'location': {'building_id': 'building-1'},
      'actions': <Object?>[],
      'sections': [
        {
          'type': 'contact',
          'tel': '02-3277-0132',
          'confirmed_at': '2026-08-22',
          'source': 'https://thehyundaiseoul.ehyundai.com/store/floor-guide',
        },
      ],
      'provenance': {'source': 'manual', 'updated_at': '2026-08-22'},
    });

    final contact = detail.sections.single as ContactSection;

    // 서버가 표기를 다듬지 않는다. 숫자만 남기는 것은 화면 몫이라, 모델이 여기서
    // 손대면 "출처 페이지에 적힌 값"이라는 말이 깨진다.
    expect(contact.tel, '02-3277-0132');
    expect(contact.confirmedAt, '2026-08-22');
    expect(contact.source, contains('thehyundaiseoul'));
  });
}
