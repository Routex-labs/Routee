import 'package:latlong2/latlong.dart';

class Building {
  const Building({
    required this.id,
    required this.name,
    required this.floors,
    this.address,
    this.defaultFloor,
    this.entrance,
    this.footprintWgs84,
    this.tileRevision,
  });

  final String id;
  final String name;

  /// 건물의 도로명 주소. 목록 API가 아직 이 값을 주지 않는 배포본도 있어 nullable로
  /// 둔다.
  final String? address;

  /// 진입 화면에 보일 주소. 서버가 주소를 주면 그것이 우선이고, 현재 앱에 내장된
  /// 유일한 실내 데모 건물은 구버전 응답에서도 주소를 감추지 않도록 둔다.
  ///
  /// 다른 건물은 추측으로 주소를 만들지 않는다. 주소가 없으면 null을 돌려 UI가
  /// 그 줄 자체를 빼야 한다.
  String? get displayAddress {
    final responseAddress = address?.trim();
    if (responseAddress != null && responseAddress.isNotEmpty) {
      return responseAddress;
    }
    return switch (id) {
      'thehyundai-seoul' => '서울 영등포구 여의대로 108',
      _ => null,
    };
  }

  /// 엘리베이터 버튼판 순서(위층 → 아래층). 표시 순서일 뿐 기본 층이 아니다 —
  /// 지하층이 있는 건물은 첫 항목이 최상층이다.
  final List<String> floors;

  /// 앱이 처음 열 층(보통 출입구가 있는 1F). 백엔드가 목록 순서와 분리해
  /// 내려준다. 응답에 없는 구버전 백엔드면 null이고, [initialFloor]가 폴백한다.
  final String? defaultFloor;

  /// 건물 출입구의 야외(GPS) 좌표. 백엔드 응답에 없으면 null
  /// (야외 길찾기가 붙기 전 이전 스키마와의 호환을 위해 optional로 둔다).
  final LatLng? entrance;

  /// 건물 외곽선(위경도). 야외 지도에서 폴리곤을 그리고 탭 인터랙션의
  /// 히트박스로 쓴다. 실측 앵커가 없어 백엔드가 계산할 수 없는 건물이면 null.
  /// 폴리곤의 마지막 점이 첫 점과 같지 않아도 되며(자동으로 닫힘 처리),
  /// 백엔드가 [{lat, lng}, ...] 형식으로 내려준다.
  final List<LatLng>? footprintWgs84;

  /// 벡터 타일 URL에 `?v=`로 붙일 버전 토큰. 시드가 바뀌면 값이 바뀐다.
  ///
  /// 이걸 붙이면 서버가 타일에 `immutable`을 줘서 **재검증(304)조차 나가지
  /// 않는다.** 층을 오갈 때마다 수십 건이 서버까지 닿던 왕복이 사라진다.
  /// 응답에 없는 구버전 백엔드면 null이고, 그때는 URL을 그대로 써서 지금까지와
  /// 같은 짧은 캐시 + 재검증으로 동작한다.
  final String? tileRevision;

  /// 야외에서 이 건물을 가리킬 때 쓸 좌표. 출입구가 있으면 그것을, 없으면
  /// 외곽선의 중심을 쓴다. 둘 다 없으면 null.
  ///
  /// **폴백이 없으면 건물이 화면에서 통째로 사라진다.** 길찾기 후보 목록은
  /// `entrance != null`로 건물을 걸러 왔는데, 백엔드 건물 응답에 출입구 좌표가
  /// 없어서 그 조건을 통과하는 건물이 하나도 없었다 — 밖에서 길찾기를 열고
  /// "더현대"를 쳐도 후보가 비었다. 외곽선은 벡터 타일과 함께 항상 내려오므로
  /// 그 중심이 실질적인 대체 좌표다.
  ///
  /// 중심은 "여기까지 걸어가라"의 끝점으로는 거칠다(건물 한가운데라 TMAP이
  /// 외벽 아무 곳으로나 스냅한다). 실제 안내에 쓸 때는 지상 출입구를 먼저
  /// 고르고([OutdoorMapBodyState.nearestBuildingEntrancePoint]) 이 값은 그것도
  /// 없을 때의 마지막 폴백으로만 쓴다.
  LatLng? get outdoorAnchor {
    final door = entrance;
    if (door != null) return door;
    final ring = footprintWgs84;
    if (ring == null || ring.isEmpty) return null;
    var minLat = double.infinity, maxLat = double.negativeInfinity;
    var minLng = double.infinity, maxLng = double.negativeInfinity;
    for (final p in ring) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
  }

  /// 지도를 열 때 선택할 층. default_floor가 오면 그것을, 아니면 목록의 첫
  /// 항목을 쓴다. 층이 하나도 없으면 null.
  String? get initialFloor {
    if (defaultFloor != null && floors.contains(defaultFloor)) {
      return defaultFloor;
    }
    return floors.isEmpty ? null : floors.first;
  }

  factory Building.fromJson(Map<String, dynamic> json) {
    final entrance = json['entrance'] as Map<String, dynamic>?;
    final footprint = json['footprint_wgs84'] as List<dynamic>?;
    return Building(
      id: json['id'] as String,
      name: json['name'] as String,
      floors: (json['floors'] as List<dynamic>).cast<String>(),
      address: json['address'] as String?,
      defaultFloor: json['default_floor'] as String?,
      entrance: entrance == null
          ? null
          : LatLng(
              (entrance['lat'] as num).toDouble(),
              (entrance['lng'] as num).toDouble(),
            ),
      tileRevision: json['tile_revision'] as String?,
      footprintWgs84: footprint == null
          ? null
          : [
              for (final p in footprint.cast<Map<String, dynamic>>())
                LatLng(
                  (p['lat'] as num).toDouble(),
                  (p['lng'] as num).toDouble(),
                ),
            ],
    );
  }
}
