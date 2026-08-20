import 'package:latlong2/latlong.dart';

/// 대중교통 한 구간의 이동 수단.
///
/// TMAP은 문자열(`"WALK"`, `"SUBWAY"` …)로 주는데, 화면이 그 문자열을 그대로
/// 비교하면 서버가 새 수단을 추가했을 때 `switch`가 조용히 아무 가지에도 안
/// 걸린다. 열거형으로 좁혀 두고 모르는 값은 [unknown]으로 모은다 — 아이콘만
/// 일반형으로 나가고 나머지 정보(소요 시간·구간명)는 그대로 보인다.
enum TransitMode {
  walk,
  bus,
  subway,
  train,
  expressBus,
  airplane,
  ferry,
  unknown;

  static TransitMode fromTmap(Object? raw) {
    return switch (raw is String ? raw.trim().toUpperCase() : '') {
      'WALK' => TransitMode.walk,
      'BUS' => TransitMode.bus,
      'SUBWAY' => TransitMode.subway,
      'TRAIN' => TransitMode.train,
      'EXPRESSBUS' => TransitMode.expressBus,
      'AIRPLANE' => TransitMode.airplane,
      'FERRY' => TransitMode.ferry,
      _ => TransitMode.unknown,
    };
  }

  /// 카카오는 `BUS`·`SUBWAY`·`WALKING` 셋만 준다(도보가 `WALK`가 아니다).
  /// 기차·고속버스·항공·해운은 아예 나오지 않으므로 [unknown]으로 모인다 —
  /// 문서에 없는 값이 나중에 추가돼도 화면은 일반 아이콘으로 버틴다.
  static TransitMode fromKakao(Object? raw) {
    return switch (raw is String ? raw.trim().toUpperCase() : '') {
      'WALKING' => TransitMode.walk,
      'BUS' => TransitMode.bus,
      'SUBWAY' => TransitMode.subway,
      _ => TransitMode.unknown,
    };
  }

  /// 걷는 구간인지. 지도에서 실선(탈것) 대신 점선으로 그리고, 요약 줄에서도
  /// "도보 n분"으로 따로 세는 기준이다.
  bool get isWalk => this == TransitMode.walk;
}

/// 같은 구간을 함께 지나는 노선 하나. [name]은 번호(`5623`, `9호선`),
/// [type]은 종류(`지선`, `급행`)다. **번호는 있고 종류는 없을 수 있다** —
/// 정류장 번호(ID)는 응답에 아예 없으므로 여기에도 없다.
typedef TransitVehicle = ({String name, String? type});

/// 대중교통 경로의 한 구간(도보 한 토막, 버스 한 번, 지하철 한 번).
class TransitLeg {
  const TransitLeg({
    required this.mode,
    required this.sectionTimeSeconds,
    required this.distanceMeters,
    required this.points,
    this.routeName,
    this.routeColorHex,
    this.startName,
    this.endName,
    this.stationCount = 0,
    this.stopNames = const [],
    this.vehicles = const [],
  });

  /// TMAP `legs[]` 한 건.
  ///
  /// **경로선을 어디서 읽는지가 수단마다 다르다.** 탈것 구간은
  /// `passShape.linestring`에 전체 선이 들어 있고, 도보 구간은 그 필드가 없이
  /// `steps[].linestring`이 토막으로 쪼개져 있다. 한쪽만 읽으면 지도에 대중교통
  /// 선만 뜨고 정류장까지 걸어가는 구간이 통째로 비어, 사용자는 선이 끊긴
  /// 지점에서 어디로 가야 할지 알 수 없다.
  factory TransitLeg.fromTmapJson(Map<String, dynamic> json) {
    final start = _place(json['start']);
    final end = _place(json['end']);
    var points = _shapePoints(json);
    // 선을 못 읽었으면 시작·끝 두 점이라도 잇는다. 실제 도로 모양은 아니지만,
    // 여기서 비워 두면 지도 위 경로가 그 구간만 툭 끊긴다.
    if (points.length < 2) {
      points = [
        if (start?.point != null) start!.point!,
        if (end?.point != null) end!.point!,
      ];
    }
    return TransitLeg(
      mode: TransitMode.fromTmap(json['mode']),
      sectionTimeSeconds: _int(json['sectionTime']) ?? 0,
      distanceMeters: _number(json['distance']) ?? 0,
      points: points,
      routeName: _text(json['route']),
      routeColorHex: _colorHex(json['routeColor']),
      startName: start?.name,
      endName: end?.name,
      stationCount: _stationCount(json),
    );
  }

  /// 카카오 `routes[].steps[]` 한 건.
  ///
  /// TMAP과 달리 값이 `properties`와 `path` 두 덩어리로 나뉘어 있고, 선 좌표는
  /// 문자열이 아니라 `[[경도, 위도], …]` 숫자 배열이다. 수단에 상관없이
  /// `path.points` 한 곳만 보면 되므로 TMAP처럼 도보·탈것을 나눠 읽지 않는다.
  factory TransitLeg.fromKakaoJson(Map<String, dynamic> json) {
    final properties = json['properties'];
    final props = properties is Map<String, dynamic>
        ? properties
        : const <String, dynamic>{};
    final mode = TransitMode.fromKakao(props['type']);
    final stops = _kakaoStopNames(props['stops']);
    // 도보에도 stops가 둘 붙어 오지만(예: "신논현" → "신논현역") 그건 걷는 구간의
    // 양 끝일 뿐 지나는 정류장이 아니다. 상세 화면에 찍히지 않게 여기서 잘라낸다.
    final passing = mode.isWalk ? const <String>[] : stops;
    final vehicles = _kakaoVehicles(props['vehicles']);

    var points = const <LatLng>[];
    final path = json['path'];
    if (path is Map<String, dynamic>) {
      points = parseKakaoPoints(path['points']);
    }

    return TransitLeg(
      mode: mode,
      sectionTimeSeconds: _int(props['time']) ?? 0,
      distanceMeters: _number(props['distance']) ?? 0,
      points: points,
      routeName: _kakaoRouteName(vehicles),
      // 카카오는 노선 고유색을 주지 않는다. null이면 화면이 수단별 기본색으로
      // 떨어지므로(widgets/transit_style.dart) 지하철 호선 색 구분만 사라진다.
      routeColorHex: null,
      // 구간 이름은 도보에도 필요하므로 잘라내기 전 목록에서 읽는다.
      startName: stops.isEmpty ? null : stops.first,
      endName: stops.length < 2 ? null : stops.last,
      stationCount: passing.length <= 1 ? 0 : passing.length - 1,
      stopNames: passing,
      vehicles: vehicles,
    );
  }

  final TransitMode mode;
  final int sectionTimeSeconds;
  final double distanceMeters;

  /// 지도에 그릴 이 구간의 좌표열.
  final List<LatLng> points;

  /// 노선 이름(예: `수도권4호선`, `간선:472`). 도보 구간에는 없다.
  final String? routeName;

  /// 노선 고유색(예: `#0068B7`). 없으면 화면이 수단별 기본색을 쓴다.
  final String? routeColorHex;

  final String? startName;
  final String? endName;

  /// 이 구간에서 지나는 정거장 수. 도보 구간은 0이다.
  final int stationCount;

  /// 승차지점부터 하차지점까지 지나는 정류장 이름, 순서대로. **카카오만 준다** —
  /// TMAP 경로와 도보 구간은 빈 목록이다([stationCount]는 그래도 채워진다).
  final List<String> stopNames;

  /// 이 구간을 함께 지나는 노선 전부. **카카오만 준다** — TMAP 경로와 도보
  /// 구간은 빈 목록이다. 목록 한 줄에는 [shortLabel]이 첫 노선만 쓰지만,
  /// 상세 화면은 이걸로 `5623`·`461`을 전부 늘어놓는다.
  final List<TransitVehicle> vehicles;

  /// 목록 한 줄에 적을 짧은 이름. 노선명이 있으면 그것을, 없으면 수단 이름을 쓴다.
  ///
  /// 버스 노선은 `간선:472`처럼 종류가 접두사로 붙어 오는데, 좁은 칩 안에서는
  /// 번호가 먼저 읽혀야 하므로 접두사를 떼어낸다.
  String get shortLabel {
    final route = routeName;
    if (route == null) return modeLabel;
    final colon = route.indexOf(':');
    if (colon < 0) return route;
    final tail = route.substring(colon + 1).trim();
    return tail.isEmpty ? route : tail;
  }

  String get modeLabel => switch (mode) {
    TransitMode.walk => '도보',
    TransitMode.bus => '버스',
    TransitMode.subway => '지하철',
    TransitMode.train => '기차',
    TransitMode.expressBus => '고속버스',
    TransitMode.airplane => '항공',
    TransitMode.ferry => '해운',
    TransitMode.unknown => '이동',
  };

  static ({String? name, LatLng? point})? _place(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final lat = _number(raw['lat']);
    final lon = _number(raw['lon']);
    return (
      name: _text(raw['name']),
      point: (lat == null || lon == null) ? null : LatLng(lat, lon),
    );
  }

  static List<LatLng> _shapePoints(Map<String, dynamic> json) {
    final shape = json['passShape'];
    if (shape is Map<String, dynamic>) {
      final points = parseTransitLinestring(shape['linestring']);
      if (points.length >= 2) return points;
    }
    final steps = json['steps'];
    if (steps is! List) return const [];
    final points = <LatLng>[];
    for (final step in steps) {
      if (step is! Map<String, dynamic>) continue;
      points.addAll(parseTransitLinestring(step['linestring']));
    }
    return points;
  }

  static int _stationCount(Map<String, dynamic> json) {
    final passStopList = json['passStopList'];
    if (passStopList is! Map<String, dynamic>) return 0;
    final stations = passStopList['stationList'];
    if (stations is! List) return 0;
    // 정류장 목록에는 승차·하차 지점이 모두 들어 있다. 사용자가 세는 것은
    // "몇 정거장 가는지"이므로 간격 수(= 개수 - 1)로 바꾼다.
    return stations.length <= 1 ? 0 : stations.length - 1;
  }

  static List<String> _kakaoStopNames(Object? raw) {
    if (raw is! List) return const [];
    final names = <String>[];
    for (final stop in raw) {
      if (stop is! Map<String, dynamic>) continue;
      final name = _text(stop['name']);
      if (name != null) names.add(name);
    }
    return names;
  }

  /// 카카오 `vehicles[]`를 노선 목록으로. **같은 구간을 지나는 노선이 전부
  /// 온다** — 여의도 앞 한 정거장에 `지선 5623`, `간선 461` … 7개가 함께 왔다.
  /// 번호(`name`) 없는 항목은 화면에 찍을 것이 없으므로 버린다.
  static List<TransitVehicle> _kakaoVehicles(Object? raw) {
    if (raw is! List) return const [];
    final vehicles = <TransitVehicle>[];
    for (final vehicle in raw) {
      if (vehicle is! Map<String, dynamic>) continue;
      final name = _text(vehicle['name']);
      if (name == null) continue;
      vehicles.add((name: name, type: _text(vehicle['type'])));
    }
    return vehicles;
  }

  /// 노선 목록을 TMAP과 같은 `종류:번호` 한 줄로 접는다.
  ///
  /// 목록 칩에 7개를 늘어놓을 수는 없으니 첫 노선만 쓰고 나머지는 "외 N대"로
  /// 접는다(전부 필요하면 [vehicles]를 직접 읽는다). 접두사를 `:`로 붙이는
  /// 것은 TMAP이 `간선:472`로 주던 규칙과 맞춘 것이다 — [shortLabel]이 이
  /// 접두사를 떼어내므로 좁은 칩에서는 번호가 먼저 읽힌다.
  static String? _kakaoRouteName(List<TransitVehicle> vehicles) {
    if (vehicles.isEmpty) return null;
    final first = vehicles.first;
    final label = vehicles.length > 1
        ? '${first.name}외 ${vehicles.length - 1}대'
        : first.name;
    return first.type == null ? label : '${first.type}:$label';
  }

  static String? _colorHex(Object? raw) {
    final value = _text(raw);
    if (value == null) return null;
    final normalized = value.startsWith('#') ? value.substring(1) : value;
    if (normalized.length != 6) return null;
    if (int.tryParse(normalized, radix: 16) == null) return null;
    return '#${normalized.toUpperCase()}';
  }
}

/// 출발지 → 도착지 대중교통 경로 한 가지(환승 조합 하나).
class TransitItinerary {
  const TransitItinerary({
    required this.totalTimeSeconds,
    required this.totalWalkTimeSeconds,
    required this.totalDistanceMeters,
    required this.transferCount,
    required this.legs,
    this.fare,
  });

  /// TMAP `metaData.plan.itineraries[]` 한 건. 구간이 하나도 안 잡히면 null —
  /// 그린 것도 안내할 것도 없는 경로를 목록에 남기지 않는다.
  static TransitItinerary? fromTmapJson(Map<String, dynamic> json) {
    final rawLegs = json['legs'];
    if (rawLegs is! List) return null;
    final legs = <TransitLeg>[];
    for (final leg in rawLegs) {
      if (leg is Map<String, dynamic>) legs.add(TransitLeg.fromTmapJson(leg));
    }
    if (legs.isEmpty) return null;
    return TransitItinerary(
      totalTimeSeconds: _int(json['totalTime']) ?? 0,
      totalWalkTimeSeconds: _int(json['totalWalkTime']) ?? 0,
      totalDistanceMeters: _number(json['totalDistance']) ?? 0,
      transferCount: _int(json['transferCount']) ?? 0,
      legs: legs,
      fare: _fare(json),
    );
  }

  /// 카카오 `routes[]` 한 건.
  ///
  /// **응답에는 첫 승차지점 앞과 마지막 하차지점 뒤의 도보가 빠져 있다.**
  /// 카카오가 "대중교통 이용 경로"만 답하기 때문이고, 그 두 구간은 화면이
  /// `DirectionsRepository.getWalkingRoute()`로 따로 채운다.
  ///
  /// 다만 **`totalTime`·`totalDistance`에는 그 도보가 이미 들어 있다.** 실호출로
  /// 확인한 값이다 — 9호선+신분당선 경로에서 steps 시간 합 1236초, `totalTime`
  /// 2022초로 786초가 더 컸고 거리 차이는 807m였다(약 1m/1초, 보행 속도와 맞다).
  /// 그래서 목록에 찍는 총 소요시간은 도보를 못 받아도 정확하고, 우리가 따로
  /// 추정해 더하면 오히려 이중 계산이 된다.
  static TransitItinerary? fromKakaoJson(Map<String, dynamic> json) {
    final rawSteps = json['steps'];
    if (rawSteps is! List) return null;
    final legs = <TransitLeg>[];
    for (final step in rawSteps) {
      if (step is Map<String, dynamic>) legs.add(TransitLeg.fromKakaoJson(step));
    }
    if (legs.isEmpty) return null;

    final properties = json['properties'];
    final props = properties is Map<String, dynamic>
        ? properties
        : const <String, dynamic>{};
    final totalTime = _int(props['totalTime']) ?? 0;

    // 카카오는 totalWalkTime을 따로 주지 않는다. 받은 도보 구간(환승 도보)에,
    // "총계에는 있는데 steps에는 없는" 시간 = 빠진 앞뒤 도보를 더해 복원한다.
    var stepSeconds = 0;
    var walkSeconds = 0;
    for (final leg in legs) {
      stepSeconds += leg.sectionTimeSeconds;
      if (leg.mode.isWalk) walkSeconds += leg.sectionTimeSeconds;
    }
    final missingWalk = totalTime - stepSeconds;

    return TransitItinerary(
      totalTimeSeconds: totalTime,
      totalWalkTimeSeconds: walkSeconds + (missingWalk > 0 ? missingWalk : 0),
      totalDistanceMeters: _number(props['totalDistance']) ?? 0,
      transferCount: _int(props['transfers']) ?? 0,
      legs: legs,
      fare: _kakaoFare(props['fare']),
    );
  }

  final int totalTimeSeconds;
  final int totalWalkTimeSeconds;
  final double totalDistanceMeters;
  final int transferCount;

  /// 성인 카드 기준 총 요금(원). 요금 정보가 없는 경로(도보만 등)는 null이다.
  final int? fare;

  final List<TransitLeg> legs;

  /// 지도에 그릴 전체 좌표열. 구간별로 색을 나눠 그릴 때는 [legs]를 직접 쓰고,
  /// 카메라를 경로 전체에 맞출 때는 이 값을 쓴다.
  List<LatLng> get points => [for (final leg in legs) ...leg.points];

  /// 탈것 구간만. 요약 줄에 "지하철 → 버스"처럼 적을 때 도보를 빼고 쓴다.
  List<TransitLeg> get rideLegs =>
      legs.where((leg) => !leg.mode.isWalk).toList(growable: false);

  /// 카카오 `properties.fare.value`. **요금이 통째로 안 올 수 있다** — 실호출에서
  /// 짧은 버스 경로 하나가 fare 없이 왔다. 화면은 이미 null을 요금 미표시로
  /// 처리하므로 0으로 채우지 않는다(0원은 "공짜"라는 다른 뜻이 된다).
  static int? _kakaoFare(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    return _int(raw['value']);
  }

  static int? _fare(Map<String, dynamic> json) {
    final fare = json['fare'];
    if (fare is! Map<String, dynamic>) return null;
    final regular = fare['regular'];
    if (regular is! Map<String, dynamic>) return null;
    return _int(regular['totalFare']);
  }
}

/// 대중교통 조회의 결말.
///
/// 성공/실패 두 갈래로 뭉치지 않는 이유는 **사용자가 할 행동이 다르기
/// 때문**이다. "너무 가까워서 경로가 없다"는 걸어가면 되는 상황이고,
/// "네트워크가 끊겼다"는 다시 시도해야 하는 상황이며, "키가 없다"는 사용자가
/// 할 수 있는 게 없다. 하나로 합치면 화면이 셋 다 "경로를 찾지 못했습니다"로
/// 말하게 되고, 700m 앞 목적지를 두고 사용자가 계속 재시도한다.
enum TransitRoutesStatus {
  ok,

  /// 출발지와 도착지가 700m 이내라 TMAP이 경로를 만들지 않는다(응답 status 11).
  tooClose,

  /// 서비스 지역 밖이거나 주변에 대중교통 정보가 없다.
  noRoute,

  /// TMAP 키가 주입되지 않아 기능 자체가 꺼져 있다.
  unavailable,

  /// 네트워크·서버 오류. 재시도가 의미 있는 유일한 상태다.
  failed,
}

/// 대중교통 조회 결과 묶음.
class TransitRoutes {
  const TransitRoutes({required this.status, this.itineraries = const []});

  const TransitRoutes.ok(this.itineraries) : status = TransitRoutesStatus.ok;

  const TransitRoutes.failure(this.status) : itineraries = const [];

  final TransitRoutesStatus status;
  final List<TransitItinerary> itineraries;

  bool get hasRoutes =>
      status == TransitRoutesStatus.ok && itineraries.isNotEmpty;
}

/// TMAP이 경로선을 담는 `"경도,위도 경도,위도 …"` 문자열을 좌표열로 바꾼다.
///
/// **경도가 먼저 온다.** GeoJSON과 같은 순서이고 우리 [LatLng]와는 반대라, 이
/// 순서를 뒤집으면 경로가 서해 한가운데로 날아간다. 파싱을 여기 한 곳에 모아
/// 도보 `steps`와 탈것 `passShape`가 같은 규칙을 쓰게 한다.
List<LatLng> parseTransitLinestring(Object? raw) {
  if (raw is! String) return const [];
  final points = <LatLng>[];
  for (final pair in raw.split(' ')) {
    if (pair.isEmpty) continue;
    final parts = pair.split(',');
    if (parts.length != 2) continue;
    final lon = double.tryParse(parts[0]);
    final lat = double.tryParse(parts[1]);
    if (lon == null || lat == null) continue;
    points.add(LatLng(lat, lon));
  }
  return points;
}

/// 카카오가 경로선을 담는 `[[경도, 위도], …]` 배열을 좌표열로 바꾼다.
///
/// TMAP과 담는 그릇만 다를 뿐(문자열 vs 숫자 배열) **경도가 먼저 오는 것은
/// 같다.** 이 순서를 뒤집으면 경로가 서해 한가운데로 날아간다.
List<LatLng> parseKakaoPoints(Object? raw) {
  if (raw is! List) return const [];
  final points = <LatLng>[];
  for (final pair in raw) {
    if (pair is! List || pair.length < 2) continue;
    final lon = _number(pair[0]);
    final lat = _number(pair[1]);
    if (lon == null || lat == null) continue;
    points.add(LatLng(lat, lon));
  }
  return points;
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) {
    final parsed = num.tryParse(value.trim());
    return parsed?.round();
  }
  return null;
}

double? _number(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
