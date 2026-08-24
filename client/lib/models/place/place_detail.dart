/// 매장·건물 상세 API(`/buildings/{buildingId}/places/{placeId}`)의 응답 모델.
///
/// 서버가 새 섹션을 추가해도 구버전 앱의 길찾기 흐름이 깨지지 않도록, 알 수
/// 없는 섹션 type은 [fromJson] 단계에서 버린다.
enum PlaceKind { building, store, facility, excluded }

class PlaceDetail {
  const PlaceDetail({
    required this.kind,
    required this.id,
    required this.name,
    required this.subtitle,
    required this.category,
    required this.subcategory,
    required this.location,
    required this.actions,
    required this.sections,
    required this.provenance,
  });

  final PlaceKind kind;
  final String id;
  final String name;
  final String subtitle;
  final String? category;
  final String? subcategory;
  final PlaceLocation location;
  final List<PlaceAction> actions;
  final List<PlaceDetailSection> sections;
  final PlaceProvenance provenance;

  factory PlaceDetail.fromJson(Map<String, dynamic> json) {
    final rawSections = json['sections'];
    final sections = rawSections is List
        ? rawSections
              .whereType<Map<String, dynamic>>()
              .map(PlaceDetailSection.fromJson)
              .whereType<PlaceDetailSection>()
              .toList(growable: false)
        : const <PlaceDetailSection>[];
    final rawActions = json['actions'];

    return PlaceDetail(
      kind: PlaceKind.values.byName(json['kind'] as String),
      id: json['id'] as String,
      name: json['name'] as String,
      subtitle: json['subtitle'] as String,
      category: json['category'] as String?,
      subcategory: json['subcategory'] as String?,
      location: PlaceLocation.fromJson(
        json['location'] as Map<String, dynamic>,
      ),
      actions: rawActions is List
          ? rawActions
                .whereType<Map<String, dynamic>>()
                .map(PlaceAction.fromJson)
                .toList(growable: false)
          : const <PlaceAction>[],
      sections: sections,
      provenance: PlaceProvenance.fromJson(
        json['provenance'] as Map<String, dynamic>,
      ),
    );
  }
}

class PlaceLocation {
  const PlaceLocation({
    required this.buildingId,
    required this.floorLabel,
    required this.positionLocalM,
    required this.entranceNodeId,
  });

  final String buildingId;
  final String? floorLabel;
  final PlacePoint? positionLocalM;
  final String? entranceNodeId;

  factory PlaceLocation.fromJson(Map<String, dynamic> json) => PlaceLocation(
    buildingId: json['building_id'] as String,
    floorLabel: json['floor_label'] as String?,
    // Dart 3 pattern matching을 지원하지 않는 Flutter SDK에서도 동작하도록
    // 전통적인 타입 검사로 파싱한다.
    positionLocalM: json['position_local_m'] is Map<String, dynamic>
        ? PlacePoint.fromJson(json['position_local_m'] as Map<String, dynamic>)
        : null,
    entranceNodeId: json['entrance_node_id'] as String?,
  );
}

class PlacePoint {
  const PlacePoint({required this.x, required this.y});

  final double x;
  final double y;

  factory PlacePoint.fromJson(Map<String, dynamic> json) => PlacePoint(
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
  );
}

class PlaceAction {
  const PlaceAction({required this.type, required this.label});

  final String type;
  final String label;

  factory PlaceAction.fromJson(Map<String, dynamic> json) =>
      PlaceAction(type: json['type'] as String, label: json['label'] as String);
}

class PlaceProvenance {
  const PlaceProvenance({required this.source, required this.updatedAt});

  final String source;
  final String? updatedAt;

  factory PlaceProvenance.fromJson(Map<String, dynamic> json) =>
      PlaceProvenance(
        source: json['source'] as String,
        updatedAt: json['updated_at'] as String?,
      );
}

sealed class PlaceDetailSection {
  const PlaceDetailSection();

  static PlaceDetailSection? fromJson(Map<String, dynamic> json) {
    return switch (json['type']) {
      'summary' => SummarySection(text: json['text'] as String),
      'hero' => HeroSection.fromJson(json),
      'keyValue' => KeyValueSection.fromJson(json),
      'tags' => TagsSection.fromJson(json),
      'notice' => NoticeSection.fromJson(json),
      'menu' => MenuSection.fromJson(json),
      'businessInfo' => BusinessInfoSection.fromJson(json),
      'demoInfo' => DemoInfoSection.fromJson(json),
      'links' => LinksSection.fromJson(json),
      'hours' => HoursSection.fromJson(json),
      'contact' => ContactSection.fromJson(json),
      _ => null,
    };
  }
}

class SummarySection extends PlaceDetailSection {
  const SummarySection({required this.text});

  final String text;
}

class HeroSection extends PlaceDetailSection {
  const HeroSection({required this.items});

  final List<HeroItem> items;

  factory HeroSection.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return HeroSection(
      items: rawItems is List
          ? rawItems
                .whereType<Map<String, dynamic>>()
                .map(HeroItem.fromJson)
                .toList(growable: false)
          : const <HeroItem>[],
    );
  }
}

class HeroItem {
  const HeroItem({required this.localAsset});

  final String localAsset;

  factory HeroItem.fromJson(Map<String, dynamic> json) =>
      HeroItem(localAsset: json['local_asset'] as String);
}

class KeyValueSection extends PlaceDetailSection {
  const KeyValueSection({required this.items});

  final List<KeyValueItem> items;

  factory KeyValueSection.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return KeyValueSection(
      items: rawItems is List
          ? rawItems
                .whereType<Map<String, dynamic>>()
                .map(KeyValueItem.fromJson)
                .toList(growable: false)
          : const <KeyValueItem>[],
    );
  }
}

class KeyValueItem {
  const KeyValueItem({required this.label, required this.value});

  final String label;
  final String value;

  factory KeyValueItem.fromJson(Map<String, dynamic> json) => KeyValueItem(
    label: json['label'] as String,
    value: json['value'] as String,
  );
}

class TagsSection extends PlaceDetailSection {
  const TagsSection({required this.tags});

  final List<String> tags;

  factory TagsSection.fromJson(Map<String, dynamic> json) => TagsSection(
    tags:
        (json['tags'] as List?)?.whereType<String>().toList(growable: false) ??
        const <String>[],
  );
}

class NoticeSection extends PlaceDetailSection {
  const NoticeSection({required this.text, required this.until});

  final String text;
  final String? until;

  factory NoticeSection.fromJson(Map<String, dynamic> json) => NoticeSection(
    text: json['text'] as String,
    until: json['until'] as String?,
  );
}

class MenuSection extends PlaceDetailSection {
  const MenuSection({required this.items});

  final List<MenuItem> items;

  factory MenuSection.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return MenuSection(
      items: rawItems is List
          ? rawItems
                .whereType<Map<String, dynamic>>()
                .map(MenuItem.fromJson)
                .toList(growable: false)
          : const <MenuItem>[],
    );
  }
}

/// 메뉴 한 건. 이름과 사진만 반드시 있고 나머지는 전부 없을 수 있다.
///
/// 가격이 선택인 이유는 출처마다 가진 것이 다르기 때문이다 — 스타벅스 코리아 공식
/// 사이트는 가격을 공개하지 않는 대신 용량·칼로리·카페인을 주고, 푸드에는 영양정보가
/// 아예 없다. 서버는 없는 값을 빈 문자열로 채워 보내지 않고 키 자체를 뺀다(계약 4-2
/// 규칙 1). 그래서 여기서도 `''`가 아니라 `null`이며, 무엇이 비었는지에 따라 카드가
/// 무엇을 보여줄지는 위젯이 정한다.
class MenuItem {
  const MenuItem({
    required this.name,
    required this.imageAsset,
    this.group,
    this.category,
    this.nameEn,
    this.description,
    this.price,
    this.volume,
    this.calories,
    this.caffeine,
    this.allergens,
    this.badges = const <String>[],
  });

  final String name;
  final String? imageAsset;

  /// 화면 위쪽 갈래(음료·푸드). 그 안의 탭이 [category]다. 둘 다 순서는 서버가
  /// 보낸 등장 순서다(계약 4-2 규칙 3).
  final String? group;
  final String? category;
  final String? nameEn;
  final String? description;
  final String? price;
  final String? volume;
  final String? calories;
  final String? caffeine;

  /// 알레르기 유발 성분. 공식 사이트 문구 그대로인 한 줄이다(`대두 / 우유`).
  final String? allergens;

  /// NEW·시즌 한정 같은 표시. 둘이 함께 붙는 항목이 있어 배열이다.
  ///
  /// 위 선택 필드들과 달리 `null`이 아니라 빈 목록인 이유는 화면이 이 값을 "0개
  /// 이상 그린다"로만 쓰기 때문이다. 없음과 비어 있음을 나눠 봐야 그리는 결과가
  /// 같아서, 구분을 만들면 위젯에 쓰이지 않는 분기만 하나 는다.
  final List<String> badges;

  factory MenuItem.fromJson(Map<String, dynamic> json) => MenuItem(
    name: json['name'] as String,
    imageAsset: json['image_asset'] as String?,
    group: json['group'] as String?,
    category: json['category'] as String?,
    nameEn: json['name_en'] as String?,
    description: json['description'] as String?,
    price: json['price'] as String?,
    volume: json['volume'] as String?,
    calories: json['calories'] as String?,
    caffeine: json['caffeine'] as String?,
    allergens: json['allergens'] as String?,
    // 서버는 값이 없으면 키를 빼고 보낸다(계약 4-2 규칙 1). 구버전 서버는
    // 이 키 자체를 모르므로 `as List` 캐스트로 받지 않는다 — 없는 키에 캐스트를
    // 걸면 파싱이 통째로 던지고, 배지 하나 때문에 메뉴 316종이 사라진다.
    badges: switch (json['badges']) {
      final List<dynamic> raw => raw.whereType<String>().toList(
        growable: false,
      ),
      _ => const <String>[],
    },
  );
}

class BusinessInfoSection extends PlaceDetailSection {
  const BusinessInfoSection({required this.items});

  final List<BusinessInfoItem> items;

  factory BusinessInfoSection.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return BusinessInfoSection(
      items: rawItems is List
          ? rawItems
                .whereType<Map<String, dynamic>>()
                .map(BusinessInfoItem.fromJson)
                .toList(growable: false)
          : const <BusinessInfoItem>[],
    );
  }
}

class BusinessInfoItem {
  const BusinessInfoItem({required this.label, required this.value});

  final String label;
  final String value;

  factory BusinessInfoItem.fromJson(Map<String, dynamic> json) =>
      BusinessInfoItem(
        label: json['label'] as String,
        value: json['value'] as String,
      );
}

/// 공식 채널 링크. 누르면 외부 브라우저로 열린다.
///
/// 값이 사람이 읽는 문장이 아니라 **주소**라 다른 섹션과 성격이 다르다. 낡으면 거짓이
/// 되는 것이 아니라 아예 열리지 않는다.
class LinksSection extends PlaceDetailSection {
  const LinksSection({required this.items});

  final List<PlaceLink> items;

  factory LinksSection.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return LinksSection(
      items: rawItems is List
          ? rawItems
                .whereType<Map<String, dynamic>>()
                .map(PlaceLink.fromJson)
                .toList(growable: false)
          : const <PlaceLink>[],
    );
  }
}

class PlaceLink {
  const PlaceLink({required this.label, required this.url, this.iconAsset});

  final String label;
  final String url;

  /// 번들에 든 브랜드 아이콘. 없으면 `null`이고, 그때 화면은 라벨로 고른 Material
  /// 아이콘을 쓴다. 구버전 서버는 이 키를 모르므로 없을 때 파싱이 깨지면 안 된다.
  final String? iconAsset;

  factory PlaceLink.fromJson(Map<String, dynamic> json) => PlaceLink(
    label: json['label'] as String,
    url: json['url'] as String,
    iconAsset: json['icon_asset'] as String?,
  );
}

/// 소개 영상 촬영용 매장에만 붙는 운영 정보다.
///
/// [BusinessInfoSection]과 모양이 거의 같은데 섹션을 나눈 이유는 **다루는 값의 수명이
/// 다르기** 때문이다. 이쪽에는 영업시간·대표번호처럼 시간이 지나면 저절로 거짓이 되는
/// 값이 들어오고, 서버가 항목마다 확인일을 필수로 받아 함께 내려보낸다. 화면이 그
/// 확인일을 보여 줄 수 있어야 해서 별도 타입으로 둔다.
class DemoInfoSection extends PlaceDetailSection {
  const DemoInfoSection({required this.items});

  final List<DemoInfoItem> items;

  factory DemoInfoSection.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return DemoInfoSection(
      items: rawItems is List
          ? rawItems
                .whereType<Map<String, dynamic>>()
                .map(DemoInfoItem.fromJson)
                .toList(growable: false)
          : const <DemoInfoItem>[],
    );
  }
}

/// 요일별 영업시간. **이 섹션만 값이 그리는 것이 아니라 계산 대상이다.**
///
/// 다른 섹션은 서버가 보낸 문자열을 그대로 그리면 끝인데, 영업시간은 "지금 영업
/// 중인지"를 화면이 [DateTime.now]와 비교해 계산한다. 서버가 판정 문자열을
/// 저장하지 않는 이유가 그것이다 — 저장하는 순간 그 값은 저장 시점부터 틀리기
/// 시작하고, 응답에 ETag 캐시가 걸려 있어 더 오래 살아남는다.
///
/// 판정 로직은 위젯이 아니라 `domain/store_hours.dart`의 순수 함수에 있다.
class HoursSection extends PlaceDetailSection {
  const HoursSection({
    required this.weekly,
    required this.exceptions,
    required this.utcOffsetMinutes,
    required this.confirmedAt,
  });

  /// 요일(mon~sun) → 그날의 영업 구간. 서버가 7개 키를 모두 채워 보낸다.
  /// 빈 배열은 "그 요일 휴무"라는 명시다 — 키가 빠진 상태와 구분되어야 해서,
  /// 서버는 요일이 하나라도 없으면 섹션 자체를 만들지 않는다.
  final Map<String, List<StoreHoursInterval>> weekly;

  /// 요일 규칙을 특정 날짜에만 덮어쓰는 예외(백화점 휴점일·명절).
  final List<StoreHoursException> exceptions;

  /// 매장 현지 시각의 UTC 오프셋(분). 기기 시계가 다른 시간대일 수 있어서
  /// (여행 중이거나 설정이 틀린 기기) 판정은 이 값으로 만든 현지 시각으로 한다.
  final int utcOffsetMinutes;

  /// 이 규칙을 실제로 확인한 날. 임계값을 넘기면 판정을 거둔다
  /// (`domain/store_hours.dart`의 `kStoreHoursStaleAfter`).
  final String confirmedAt;

  factory HoursSection.fromJson(Map<String, dynamic> json) {
    final rawWeekly = json['weekly'];
    final weekly = <String, List<StoreHoursInterval>>{};
    if (rawWeekly is Map) {
      for (final entry in rawWeekly.entries) {
        weekly[entry.key.toString()] = StoreHoursInterval.listFrom(entry.value);
      }
    }
    final rawExceptions = json['exceptions'];
    return HoursSection(
      weekly: weekly,
      exceptions: rawExceptions is List
          ? rawExceptions
                .whereType<Map<String, dynamic>>()
                .map(StoreHoursException.fromJson)
                .toList(growable: false)
          : const <StoreHoursException>[],
      // 서버가 항상 실어 보내는 값이라 기본값을 여기에 또 두지 않는다. 양쪽이
      // 각자 기본값을 들면 어느 날 둘이 갈라진다.
      utcOffsetMinutes: (json['utc_offset_minutes'] as num?)?.toInt() ?? 0,
      confirmedAt: json['confirmed_at'] as String? ?? '',
    );
  }
}

/// 매장 전화번호.
///
/// 자유 문자열 `keyValue`가 아니라 따로 오는 이유는 서버 쪽 규칙이다 — 오버레이
/// 스키마가 "전화번호" 라벨을 금지하고, 대신 출처와 확인일을 붙인 구조체만 받는다
/// (백엔드 `store_details/_schema.json`의 `contact`).
///
/// 세 값이 다 있어야 서버가 섹션을 만들기 때문에 여기서 빈 값을 걱정하지 않는다.
/// 그래도 기본값을 두는 것은 그 계약이 여기까지 오는 길에 끊겼을 때 파싱이
/// 죽지 않게 하기 위해서다.
class ContactSection extends PlaceDetailSection {
  const ContactSection({
    required this.tel,
    required this.confirmedAt,
    required this.source,
  });

  /// 출처 페이지에 적힌 표기 그대로(`02-3277-0132`·`1522-3232`). 걸기 좋은 형태로
  /// 바꾸는 것은 화면 몫이라 서버가 다듬지 않는다.
  final String tel;

  /// 이 번호를 실제로 확인한 날(`YYYY-MM-DD`).
  final String confirmedAt;

  /// 번호가 적혀 있던 페이지. 다시 열어 확인할 수 있어야 [confirmedAt]이 뜻을 갖는다.
  final String source;

  factory ContactSection.fromJson(Map<String, dynamic> json) => ContactSection(
    tel: json['tel'] as String? ?? '',
    confirmedAt: json['confirmed_at'] as String? ?? '',
    source: json['source'] as String? ?? '',
  );
}

/// 하루 안의 영업 구간 하나. `"HH:MM"` 24시간 표기.
class StoreHoursInterval {
  const StoreHoursInterval({required this.open, required this.close});

  final String open;

  /// [close]가 [open]보다 **작거나 같으면 자정을 넘긴다**(22:00–02:00).
  /// 종일 영업은 `00:00`–`24:00`이다.
  final String close;

  factory StoreHoursInterval.fromJson(Map<String, dynamic> json) =>
      StoreHoursInterval(
        open: json['open'] as String,
        close: json['close'] as String,
      );

  static List<StoreHoursInterval> listFrom(Object? raw) => raw is List
      ? raw
            .whereType<Map<String, dynamic>>()
            .map(StoreHoursInterval.fromJson)
            .toList(growable: false)
      : const <StoreHoursInterval>[];
}

/// 특정 날짜에만 요일 규칙을 덮어쓰는 예외.
class StoreHoursException {
  const StoreHoursException({
    required this.date,
    required this.closed,
    required this.intervals,
    required this.note,
  });

  /// YYYY-MM-DD. **매장 현지 날짜**다.
  final String date;
  final bool closed;
  final List<StoreHoursInterval> intervals;
  final String? note;

  factory StoreHoursException.fromJson(Map<String, dynamic> json) =>
      StoreHoursException(
        date: json['date'] as String,
        closed: json['closed'] == true,
        intervals: StoreHoursInterval.listFrom(json['intervals']),
        note: json['note'] as String?,
      );
}

class DemoInfoItem {
  const DemoInfoItem({
    required this.label,
    required this.value,
    required this.confirmedAt,
  });

  final String label;
  final String value;
  final String confirmedAt;

  // `source`는 받아 두고 화면에 그리지 않는다. 다시 열어 볼 수 있는 주소는 데이터를
  // 고치는 사람에게 필요한 것이고, 사용자에게 필요한 것은 "언제 확인한 값인가"다
  // (설계 7-A-3).
  factory DemoInfoItem.fromJson(Map<String, dynamic> json) => DemoInfoItem(
    label: json['label'] as String,
    value: json['value'] as String,
    confirmedAt: json['confirmed_at'] as String,
  );
}
