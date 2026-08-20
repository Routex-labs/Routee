/// 도보 길찾기 갈래 판정.
///
/// 이 판정이 틀리면 화면에는 "경로를 계산할 수 없습니다"만 뜬다. 판정 누락인지
/// 데이터 문제인지 구분되지 않아, 실내→야외 갈래가 통째로 빠져 있던 기간이
/// 실제로 있었다. 여기서 다섯 갈래를 전부 못 박는다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/models/route/directions_candidate.dart';
import 'package:navigation_client/screens/map_shell/walk_route_kind.dart';

/// 건물 안 매장. 층과 노드를 **둘 다** 가진 후보만 실내로 친다.
DirectionsCandidate indoor({String floor = 'B2', String nodeId = 'n1'}) =>
    DirectionsCandidate(
      title: '스타벅스 리저브',
      subtitle: floor,
      point: const LatLng(37.5, 127.0),
      floor: floor,
      nodeId: nodeId,
    );

/// 지도에서 찍은 이름 없는 야외 좌표.
DirectionsCandidate outdoorPoint() => const DirectionsCandidate(
  title: '지도에서 선택한 지점',
  subtitle: '',
  point: LatLng(37.6, 127.1),
);

/// 층은 있는데 노드가 없는 반쪽짜리. 실내 라우팅이 시작 노드를 못 정한다.
DirectionsCandidate halfIndoor() => const DirectionsCandidate(
  title: '층만 아는 후보',
  subtitle: '3F',
  point: LatLng(37.5, 127.0),
  floor: '3F',
);

void main() {
  group('실내 → 실내', () {
    test('도면을 보는 중이고 실내 위치가 잡혔으면 실내 경로다', () {
      expect(
        classifyWalkRoute(
          origin: null,
          destination: indoor(),
          indoorContextActive: true,
          indoorStartReady: true,
        ),
        WalkRouteKind.indoorToIndoor,
      );
    });

    test('출발지를 실내 매장으로 골랐으면 실내 위치가 없어도 실내 경로다', () {
      expect(
        classifyWalkRoute(
          origin: indoor(floor: '1F', nodeId: 'n9'),
          destination: indoor(),
          indoorContextActive: true,
          indoorStartReady: false,
        ),
        WalkRouteKind.indoorToIndoor,
      );
    });

    test('도면을 닫았으면 실내 위치가 있어도 실내 경로가 아니다', () {
      // 사용자의 위치는 GPS다. 실내로 보내면 화면에는 GPS 아이콘이 있는데
      // 경로만 예전에 찍어둔 건물 안 앵커에서 뻗어 나간다.
      expect(
        classifyWalkRoute(
          origin: null,
          destination: indoor(),
          indoorContextActive: false,
          indoorStartReady: true,
        ),
        WalkRouteKind.outdoorToIndoor,
      );
    });
  });

  group('야외 → 실내', () {
    test('도면이 켜져 있어도 실내 위치가 없으면 문을 경유한다', () {
      // 이 경우가 핵심이다. 도면은 건물을 확대하거나 탭하기만 해도 켜지므로,
      // **밖에 서 있는 사용자에게도 켜져 있다.** 여기서 실내로 보내면
      // "출발 위치를 먼저 지정해주세요"만 나오고 안내가 끝난다.
      expect(
        classifyWalkRoute(
          origin: null,
          destination: indoor(),
          indoorContextActive: true,
          indoorStartReady: false,
        ),
        WalkRouteKind.outdoorToIndoor,
      );
    });

    test('지도에서 찍은 야외 좌표에서 출발해도 문을 경유한다', () {
      expect(
        classifyWalkRoute(
          origin: outdoorPoint(),
          destination: indoor(),
          indoorContextActive: false,
          indoorStartReady: false,
        ),
        WalkRouteKind.outdoorToIndoor,
      );
    });

    // 건물 안 두 지점 사이의 이동이라 "밖에서 문으로 들어간다"는 전제가 성립하지
    // 않는다. **도면이 꺼져 있어도, 밖에 서 있어도 마찬가지다** — 두 끝점이 다
    // 건물 안 노드면 그릴 수 있는 경로이고, 그것이 "거기는 어떻게 되어 있지?" 하고
    // 미리 보는 길이다. 미리 보기와 실제 안내는 "안내 시작" 버튼이 가른다.
    test('출발지가 실내 매장이면 밖에 서 있어도 실내 경로다', () {
      expect(
        classifyWalkRoute(
          origin: indoor(floor: '1F', nodeId: 'n9'),
          destination: indoor(),
          indoorContextActive: false,
          indoorStartReady: false,
        ),
        WalkRouteKind.indoorToIndoor,
      );
    });
  });

  group('실내 → 야외', () {
    test('건물 안에서 바깥 목적지를 고르면 실내→야외다', () {
      // 이 갈래가 없던 동안에는 실내 경로 계산까지 흘러가 "도착지 노드 정보가
      // 없어 경로를 계산할 수 없습니다"만 뜨고 끝났다.
      expect(
        classifyWalkRoute(
          origin: null,
          destination: outdoorPoint(),
          indoorContextActive: true,
          indoorStartReady: true,
        ),
        WalkRouteKind.indoorToOutdoor,
      );
    });

    test('실내 매장을 출발지로 골라도 실내→야외다', () {
      // 한때 `origin == null`을 달아 이 경우를 막았다. 그 결과 실내 매장에서
      // 바깥으로 가려는 사용자가 indoorFallback으로 떨어져, 야외 목적지가 실내
      // 라우팅에 넘어가 "도착지 노드 정보가 없어..."만 봤다.
      expect(
        classifyWalkRoute(
          origin: indoor(floor: 'B2', nodeId: 'n7'),
          destination: outdoorPoint(),
          indoorContextActive: true,
          indoorStartReady: true,
        ),
        WalkRouteKind.indoorToOutdoor,
      );
    });

    test('실내 매장이 출발지면 PDR 앵커가 없어도 실내→야외다', () {
      // 출발 노드를 이미 알고 있으므로 앵커로 시작점을 추정할 이유가 없다.
      // 앵커를 요구하면 "위치 지정"을 안 한 사용자가 매장을 골라도 막힌다.
      expect(
        classifyWalkRoute(
          origin: indoor(floor: 'B2', nodeId: 'n7'),
          destination: outdoorPoint(),
          indoorContextActive: true,
          indoorStartReady: false,
        ),
        WalkRouteKind.indoorToOutdoor,
      );
    });

    test('도면이 꺼져 있어도 실내 매장이 출발지면 실내→야외다', () {
      // **1)과 판박이여야 한다는 것이 이 갈래의 규칙이다.** 출발 노드를 이미
      // 알고 있으면 지금 무엇을 보고 있는지는 갈래를 바꾸지 않는다. 도면을
      // 요구하면 야외 지도에서 실내 매장을 출발지로 고른 사용자가 outdoor로
      // 떨어져, 건물을 관통하는 TMAP 보행선을 보게 된다.
      expect(
        classifyWalkRoute(
          origin: indoor(floor: 'B2', nodeId: 'n7'),
          destination: outdoorPoint(),
          indoorContextActive: false,
          indoorStartReady: false,
        ),
        WalkRouteKind.indoorToOutdoor,
      );
    });

    test('출발지가 야외 좌표면 야외 걷기다', () {
      // 밖의 두 지점 사이 이동이다. 도면이 떠 있다는 것만으로 문을 경유시키면
      // 건물과 상관없는 경로에 실내 구간이 끼어든다.
      //
      // **한때 indoorFallback이었다.** 이 테스트가 못 박으려던 것은 "실내→야외가
      // 아니다"였고 그때의 폴백 값을 그대로 적었는데, 그 값이 요청을 실내
      // 라우팅에 넘겨 "도착지 노드 정보가 없어…"만 띄웠다(실기기: "서울창업허브
      // 공덕 → 공덕" 도보). 끝점 어느 쪽에도 실내 정보가 없으면 야외다.
      expect(
        classifyWalkRoute(
          origin: outdoorPoint(),
          destination: outdoorPoint(),
          indoorContextActive: true,
          indoorStartReady: true,
        ),
        WalkRouteKind.outdoor,
      );
    });

    test('출발지가 없고 실내 위치도 없으면 야외 걷기다', () {
      // 출발점을 정할 근거가 아무것도 없다. 노드도 앵커도 없다 — 실내 위치가
      // 없다는 것은 그 사람이 아직 밖이라는 뜻이고, 목적지도 밖이다.
      expect(
        classifyWalkRoute(
          origin: null,
          destination: outdoorPoint(),
          indoorContextActive: true,
          indoorStartReady: false,
        ),
        WalkRouteKind.outdoor,
      );
    });

    test('반쪽짜리 출발지(층만 있음)는 실내→야외가 아니다', () {
      // 노드가 없어 그래프 탐색을 시작할 수 없다. 실내 구간을 만들 수 없으니
      // 문을 경유하는 척하면 안 된다.
      expect(
        classifyWalkRoute(
          origin: halfIndoor(),
          destination: outdoorPoint(),
          indoorContextActive: true,
          indoorStartReady: false,
        ),
        WalkRouteKind.indoorFallback,
      );
    });
  });

  group('순수 야외', () {
    test('도면이 꺼져 있고 목적지가 야외면 TMAP 보행이다', () {
      expect(
        classifyWalkRoute(
          origin: null,
          destination: outdoorPoint(),
          indoorContextActive: false,
          indoorStartReady: false,
        ),
        WalkRouteKind.outdoor,
      );
    });
  });

  group('반쪽짜리 후보', () {
    test('층만 있고 노드가 없으면 실내로 치지 않는다', () {
      // 실내 라우팅이 시작 노드를 못 정해 조용히 끝나는 것보다, 야외 걷기
      // 경로로 흘려보내는 편이 낫다.
      expect(
        classifyWalkRoute(
          origin: null,
          destination: halfIndoor(),
          indoorContextActive: false,
          indoorStartReady: true,
        ),
        WalkRouteKind.outdoor,
      );
    });

    test('출발지가 반쪽짜리면 실내→실내로 가지 않는다', () {
      expect(
        classifyWalkRoute(
          origin: halfIndoor(),
          destination: indoor(),
          indoorContextActive: true,
          indoorStartReady: true,
        ),
        WalkRouteKind.indoorFallback,
      );
    });
  });

  // 이동 수단 줄(자동차·대중교통·도보)을 띄울지 정하는 판정. 위 갈래 판정과
  // **같은 모양이어야** 화면에 뜬 버튼과 실제 계산이 어긋나지 않는다.
  group('이동 수단 줄을 접는 조건', () {
    test('건물 안에서 건물 안으로 가면 접는다', () {
      // 수단이 도보 하나로 못박히는 여정이라 고를 것이 없다.
      expect(
        isIndoorOnlyWalk(
          origin: null,
          destination: indoor(),
          indoorContextActive: true,
        ),
        isTrue,
      );
      expect(
        isIndoorOnlyWalk(
          origin: indoor(nodeId: 'n0'),
          destination: indoor(),
          indoorContextActive: false,
        ),
        isTrue,
      );
    });

    // 실기기에서 "서울창업허브 → 샤브미담"으로 걸린 회귀다. 도착지만 보고
    // 접었더니 5km 떨어진 건물 안 매장을 찍는 길에서 대중교통이 사라졌다.
    test('멀리 있는 야외 출발지면 접지 않는다', () {
      expect(
        isIndoorOnlyWalk(
          origin: outdoorPoint(),
          destination: indoor(),
          indoorContextActive: false,
        ),
        isFalse,
      );
      // 건물 도면을 펴 놓은 채여도, 출발지를 밖으로 직접 골랐으면 야외 여정이다.
      expect(
        isIndoorOnlyWalk(
          origin: outdoorPoint(),
          destination: indoor(),
          indoorContextActive: true,
        ),
        isFalse,
      );
    });

    test('도착지가 실내가 아니면 접지 않는다', () {
      expect(
        isIndoorOnlyWalk(
          origin: indoor(),
          destination: outdoorPoint(),
          indoorContextActive: true,
        ),
        isFalse,
      );
      // 반쪽짜리 후보는 실내 라우팅이 못 태우므로 실내로 치지 않는다.
      expect(
        isIndoorOnlyWalk(
          origin: null,
          destination: halfIndoor(),
          indoorContextActive: true,
        ),
        isFalse,
      );
    });

    test('도착지가 아직 없으면 접지 않는다', () {
      expect(
        isIndoorOnlyWalk(
          origin: null,
          destination: null,
          indoorContextActive: true,
        ),
        isFalse,
      );
    });
  });
}
