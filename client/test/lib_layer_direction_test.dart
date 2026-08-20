import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `lib/`의 계층 순서. **숫자가 클수록 위**이고, import는 위에서 아래로만 간다.
///
/// 이름이 아니라 화살표가 계층을 정한다. 아래 값은 지어낸 것이 아니라 실제 import
/// 그래프를 재서 나온 순서다.
const _rank = <String, int>{
  // 바닥 — 아무것도 import하지 않는다.
  'models': 0, // 백엔드 응답과 앱 자료구조
  'theme': 0, // 색·타이포
  'routing': 0, // 화면 경로 이름
  'core': 0, // 실행 설정(api_config·tile_url)과 범용 유틸
  // 규칙 — 화면도 HTTP도 모르는 계산
  'domain': 1,
  'state': 1,
  // 자료를 가져오거나 센서를 돌리거나 지도에 그릴 값을 만드는 층
  'repositories': 2,
  'features': 2,
  'map': 2, // 도면 색·라벨·아이콘·레이어 표현식
  // 공용 위젯
  'widgets': 3,
  // 화면
  'screens': 4,
};

/// `lib/` 바로 아래 파일들의 등급.
///
/// [_serviceLocator]만 예외다 — **조립 루트라 어디서든 읽는다.** 자기 자신은 최상단
/// (repositories·features·state를 조립하므로)이지만, 그걸 읽는 쪽은 층을 가리지
/// 않는다. 이 한 파일을 특별 취급하는 대신 규칙을 느슨하게 하면 검사가 의미를 잃는다.
const _rootFileRank = <String, int>{
  'app.dart': 5,
  'main.dart': 5,
  'pdr_device_harness_main.dart': 5,
  _serviceLocator: 5,
};

const _serviceLocator = 'service_locator.dart';

/// 이 검사가 있는 이유.
///
/// 한때 거꾸로 가는 화살표가 여섯 있었고, 그중 하나는 **주석에 건 대괄호 링크**
/// 때문에 생겼다(`domain/geo_transform.dart` → features). 계층은 이름을 붙이는 것만
/// 으로는 서지 않는다 — 아무것도 막지 않으면 다음 사람이 같은 자리에 다시 만든다.
///
/// 컴파일러로 막으려면 pub 패키지로 쪼개야 하는데, 그건 경계가 굳은 뒤의 일이다.
/// 그전까지는 이 테스트가 그 자리를 대신한다.
void main() {
  test('lib/의 import는 위 계층에서 아래 계층으로만 간다', () {
    final files = _dartFilesUnder('lib');
    final violations = <String>[];

    for (final entry in files.entries) {
      final from = entry.key;
      final fromRank = _rankOf(from);
      for (final target in _relativeDirectives(entry.value)) {
        final to = _resolve(from, target);
        if (!files.containsKey(to)) continue; // dart:/package: 또는 해석 실패
        // 조립 루트는 어디서든 읽을 수 있다. 위 주석 참고.
        if (to == _serviceLocator) continue;
        final toRank = _rankOf(to);
        if (toRank > fromRank) {
          violations.add('  $from (등급 $fromRank)  ->  $to (등급 $toRank)');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          '계층을 거슬러 올라가는 import가 있다.\n'
          '${violations.join('\n')}\n\n'
          '고치는 방법은 셋 중 하나다.\n'
          '  1. 쓰는 쪽이 아니라 **쓰이는 값**을 아래로 내린다(타입·상수만 옮기면\n'
          '     되는 경우가 대부분이다).\n'
          '  2. 큰 객체를 통째로 받지 말고 실제로 읽는 값만 인자로 받는다.\n'
          '  3. 주석 링크 때문이면 대괄호를 떼고 경로를 글자로 적는다.\n'
          '등급표를 고치는 것은 마지막 수단이고, 고칠 때는 왜 그 순서인지 함께 적는다.',
    );
  });

  test('등급표가 실제 디렉터리와 어긋나지 않는다', () {
    final dirs = Directory('lib')
        .listSync()
        .whereType<Directory>()
        .map((d) => d.path.split(Platform.pathSeparator).last)
        .toSet();
    expect(
      dirs.difference(_rank.keys.toSet()),
      isEmpty,
      reason: 'lib/에 새 디렉터리가 생겼는데 등급이 없다. _rank에 추가한다.',
    );
    expect(
      _rank.keys.toSet().difference(dirs),
      isEmpty,
      reason: '등급표에 없어진 디렉터리가 남아 있다.',
    );

    final rootFiles = Directory('lib')
        .listSync()
        .whereType<File>()
        .map((f) => f.path.split(Platform.pathSeparator).last)
        .where((f) => f.endsWith('.dart'))
        .toSet();
    expect(
      rootFiles,
      _rootFileRank.keys.toSet(),
      reason: 'lib/ 바로 아래 파일이 바뀌었다. _rootFileRank를 맞춘다.',
    );
  });
}

int _rankOf(String rel) {
  if (!rel.contains('/')) {
    final rank = _rootFileRank[rel];
    if (rank == null) fail('lib/$rel 의 등급이 없다.');
    return rank;
  }
  final head = rel.split('/').first;
  final rank = _rank[head];
  if (rank == null) fail('lib/$head/ 의 등급이 없다.');
  return rank;
}

/// `import`·`export`의 **상대 경로**만 돌려준다. `part`는 같은 라이브러리라
/// 계층을 넘지 않는다.
Iterable<String> _relativeDirectives(String source) sync* {
  final pattern = RegExp(r"^\s*(?:import|export)\s+'([^']+)'", multiLine: true);
  for (final match in pattern.allMatches(source)) {
    final target = match.group(1)!;
    if (target.startsWith('dart:') || target.startsWith('package:')) continue;
    yield target;
  }
}

String _resolve(String from, String target) {
  final parts = from.split('/')..removeLast();
  for (final segment in target.split('/')) {
    if (segment == '.') continue;
    if (segment == '..') {
      if (parts.isNotEmpty) parts.removeLast();
      continue;
    }
    parts.add(segment);
  }
  return parts.join('/');
}

Map<String, String> _dartFilesUnder(String relativePath) {
  final root = Directory(relativePath);
  if (!root.existsSync()) {
    fail('$relativePath 를 찾지 못했다. 이 테스트는 client/ 에서 돌아야 한다.');
  }
  return {
    for (final entity in root.listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.dart'))
        entity.path
            .substring(relativePath.length + 1)
            .replaceAll(Platform.pathSeparator, '/'): entity
            .readAsStringSync(),
  };
}
