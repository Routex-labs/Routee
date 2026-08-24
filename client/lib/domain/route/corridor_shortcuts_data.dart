// 생성된 파일이다. 손으로 고치지 마라.
// 생성: Routex-labs/fastapi의 scripts/transform/build_corridor_shortcuts.py
// 입력(원본 도면)도 그 저장소에 있다 — resources/studio/thehyundai-seoul-dabeeo/.
// 이 저장소만으로는 다시 만들 수 없다.
//
// 채택 19개 · 검수대기 18개(기본 꺼짐). 층별 표와 B2·B3를 건너뛴 이유,
// '새 노드 0개'를 풀면 안 되는 근거는 docs/client/corridor-graph-detour.md.

import 'corridor_shortcuts.dart';

/// 지금 적용하는 지름길. 복도를 따라가는 대각선 컷이라 위험이 낮다.
const kCorridorShortcuts = CorridorShortcutTable(
  buildingId: 'thehyundai-seoul',
  byFloorName: {
    '1F': [
      // 17.0m 절약(우회비 2.93), 여유폭 2.14m, 차수 2+2, local_m (163.3,125.3)-(169.5,131.6)
      CorridorShortcut(
        fromNodeId: 'FL-soem999bnha10599:ND-J3ORkjQav4710',
        toNodeId: 'FL-soem999bnha10599:ND-xEVy9AVEk9636',
        lengthM: 8.798981,
      ),
      // 14.2m 절약(우회비 3.17), 여유폭 2.72m, 차수 2+2, local_m (184.3,128.7)-(184.4,135.2)
      CorridorShortcut(
        fromNodeId: 'FL-soem999bnha10599:ND-1nCirZhzw2550',
        toNodeId: 'FL-soem999bnha10599:ND-o9XljztO36310',
        lengthM: 6.531546,
      ),
      // 13.4m 절약(우회비 2.03), 여유폭 1.58m, 차수 3+1, local_m (156.2,125.1)-(155.7,112.1)
      CorridorShortcut(
        fromNodeId: 'FL-soem999bnha10599:ND-SuuMk45wT4846',
        toNodeId: 'FL-soem999bnha10599:ND-v81XAOpoZ7406',
        lengthM: 13.019133,
      ),
      // 13.3m 절약(우회비 2.16), 여유폭 1.81m, 차수 2+2, local_m (104.5,136.6)-(113.2,129.1)
      CorridorShortcut(
        fromNodeId: 'FL-soem999bnha10599:ND-5eq_NYZU-9577',
        toNodeId: 'FL-soem999bnha10599:ND-6SlOSPK_Z2753',
        lengthM: 11.438096,
      ),
      // 11.5m 절약(우회비 2.81), 여유폭 2.60m, 차수 2+2, local_m (91.8,135.1)-(97.2,138.4)
      CorridorShortcut(
        fromNodeId: 'FL-soem999bnha10599:ND-8Pt2zyMNg8851',
        toNodeId: 'FL-soem999bnha10599:ND-msMa6nlgr2344',
        lengthM: 6.336925,
      ),
      // 10.4m 절약(우회비 2.17), 여유폭 2.27m, 차수 3+2, local_m (174.0,126.5)-(166.4,131.2)
      CorridorShortcut(
        fromNodeId: 'FL-soem999bnha10599:ND-Ogj7-mAZb6206',
        toNodeId: 'FL-soem999bnha10599:ND-y_dnsjCyP1519',
        lengthM: 8.925577,
      ),
      // 10.4m 절약(우회비 2.72), 여유폭 1.73m, 차수 3+2, local_m (97.4,164.2)-(95.7,158.4)
      CorridorShortcut(
        fromNodeId: 'FL-soem999bnha10599:ND-HqQVZXVvT9332',
        toNodeId: 'FL-soem999bnha10599:ND-LOWf9kinV6223',
        lengthM: 6.034444,
      ),
      // 8.4m 절약(우회비 2.37), 여유폭 1.98m, 차수 3+2, local_m (123.7,170.6)-(122.6,164.5)
      CorridorShortcut(
        fromNodeId: 'FL-soem999bnha10599:ND-mjWf6RrkT4823',
        toNodeId: 'FL-soem999bnha10599:ND-M0vbjijvj8200',
        lengthM: 6.172361,
      ),
    ],
    '2F': [
      // 7.7m 절약(우회비 2.41), 여유폭 1.64m, 차수 3+2, local_m (149.0,159.7)-(146.2,164.4)
      CorridorShortcut(
        fromNodeId: 'FL-qxirle6jha9l0574:ND-RJs1pdNex1031',
        toNodeId: 'FL-qxirle6jha9l0574:ND-d69HyQFd19295',
        lengthM: 5.463504,
      ),
      // 6.3m 절약(우회비 2.59), 여유폭 1.91m, 차수 2+4, local_m (87.2,157.5)-(89.0,153.9)
      CorridorShortcut(
        fromNodeId: 'FL-qxirle6jha9l0574:ND-cV--rce-a0959',
        toNodeId: 'FL-qxirle6jha9l0574:ND-8claRvzmm3350',
        lengthM: 3.995566,
      ),
      // 5.8m 절약(우회비 2.88), 여유폭 1.78m, 차수 2+2, local_m (82.3,140.6)-(85.3,140.0)
      CorridorShortcut(
        fromNodeId: 'FL-qxirle6jha9l0574:ND-ZASHWkNcv9135',
        toNodeId: 'FL-qxirle6jha9l0574:ND-cCTXGqthw4302',
        lengthM: 3.086833,
      ),
    ],
    '4F': [
      // 14.6m 절약(우회비 2.53), 여유폭 2.13m, 차수 2+3, local_m (198.7,121.6)-(208.2,121.3)
      CorridorShortcut(
        fromNodeId: 'FL-urk3dfu89rg50546:ND-8fSq-3dSd3033',
        toNodeId: 'FL-urk3dfu89rg50546:ND-NDVX2L3T17813',
        lengthM: 9.581160,
      ),
    ],
    '5F': [
      // 5.6m 절약(우회비 2.15), 여유폭 1.45m, 차수 2+2, local_m (93.9,127.4)-(91.5,131.7)
      CorridorShortcut(
        fromNodeId: 'FL-1iuvfnt4i456g0534:ND-kPx2zMqF49774',
        toNodeId: 'FL-1iuvfnt4i456g0534:ND-h0vgvP0RJ4780',
        lengthM: 4.905052,
      ),
    ],
    'B1': [
      // 95.8m 절약(우회비 15.08), 여유폭 2.45m, 차수 1+2, local_m (164.6,191.1)-(163.6,197.8)
      CorridorShortcut(
        fromNodeId: 'FL-u855ha63yjxe0585:ND-fVjHDePWJ5576',
        toNodeId: 'FL-u855ha63yjxe0585:ND-uiL1gYv5Z0885',
        lengthM: 6.803894,
      ),
      // 74.7m 절약(우회비 5.41), 여유폭 2.18m, 차수 2+2, local_m (153.4,197.7)-(167.2,187.9)
      CorridorShortcut(
        fromNodeId: 'FL-u855ha63yjxe0585:ND-4EF_f9pzM9298',
        toNodeId: 'FL-u855ha63yjxe0585:ND-CcqgC6dAq4258',
        lengthM: 16.960306,
      ),
    ],
    'B5': [
      // 172.2m 절약(우회비 9.71), 여유폭 3.86m, 차수 1+2, local_m (226.3,208.9)-(238.3,193.2)
      CorridorShortcut(
        fromNodeId: 'FL-1ies91kjdirfn0649:ND-qGgKlQFwr4724',
        toNodeId: 'FL-1ies91kjdirfn0649:ND-d4ReUcpqI3269',
        lengthM: 19.766026,
      ),
    ],
    'B6': [
      // 69.7m 절약(우회비 5.05), 여유폭 2.95m, 차수 1+2, local_m (77.8,130.3)-(94.4,134.8)
      CorridorShortcut(
        fromNodeId: 'FL-rl7x0hl40i0m0673:ND-1w1q92_o26478',
        toNodeId: 'FL-rl7x0hl40i0m0673:ND-ZRskkvS1E9800',
        lengthM: 17.200632,
      ),
      // 19.4m 절약(우회비 2.10), 여유폭 2.74m, 차수 3+2, local_m (119.8,167.7)-(102.5,164.0)
      CorridorShortcut(
        fromNodeId: 'FL-rl7x0hl40i0m0673:ND-3vK72BG9O1568',
        toNodeId: 'FL-rl7x0hl40i0m0673:ND-S9n9yJvxl5902',
        lengthM: 17.730051,
      ),
      // 10.6m 절약(우회비 2.28), 여유폭 2.81m, 차수 2+1, local_m (94.4,146.8)-(100.8,141.6)
      CorridorShortcut(
        fromNodeId: 'FL-rl7x0hl40i0m0673:ND-hOMgQaMbG9391',
        toNodeId: 'FL-rl7x0hl40i0m0673:ND-97GTY2rcB10942',
        lengthM: 8.261827,
      ),
    ],
  },
);

/// **켜져 있지 않다.** 양 끝 기존 간선 모두와 60도 넘게 벌어진 = 두 복도를
/// 잇는 수직 링크다. CorridorNetwork.isForwardReachable이 연결된 간선만 보는
/// 것이 평행 복도 혼동을 막는 지금의 유일한 방어인데 이 링크가 정확히 그 둘을
/// 잇는다. 하나라도 가짜면 마커가 옆 복도로 건너뛴다 - 지금 없는 종류의 버그다.
/// **도면에서 실제로 뚫린 통로인지 눈으로 확인한 것만** 위 [kCorridorShortcuts]로
/// 옮긴다. 좌표는 각 항목 주석의 local_m에 있다.
const kCorridorShortcutsNeedingReview = CorridorShortcutTable(
  buildingId: 'thehyundai-seoul',
  byFloorName: {
    '1F': [
      // 21.8m 절약(우회비 5.23), 여유폭 2.78m, 차수 2+2, local_m (167.5,171.5)-(166.7,166.5)
      CorridorShortcut(
        fromNodeId: 'FL-soem999bnha10599:ND-XdYNzc8jt7260',
        toNodeId: 'FL-soem999bnha10599:ND-j6Sit4I3R5375',
        lengthM: 5.139168,
      ),
      // 15.9m 절약(우회비 2.34), 여유폭 1.73m, 차수 2+2, local_m (156.4,151.8)-(144.5,150.6)
      CorridorShortcut(
        fromNodeId: 'FL-soem999bnha10599:ND-J1ww7CrVS4131',
        toNodeId: 'FL-soem999bnha10599:ND-pLiGzopE_1163',
        lengthM: 11.898344,
      ),
      // 15.1m 절약(우회비 3.70), 여유폭 1.96m, 차수 2+2, local_m (111.6,168.1)-(111.4,162.5)
      CorridorShortcut(
        fromNodeId: 'FL-soem999bnha10599:ND-2xspp1VeW1599',
        toNodeId: 'FL-soem999bnha10599:ND--9qoaNWhd9455',
        lengthM: 5.591359,
      ),
      // 14.0m 절약(우회비 3.40), 여유폭 2.14m, 차수 2+2, local_m (104.8,130.9)-(108.1,135.8)
      CorridorShortcut(
        fromNodeId: 'FL-soem999bnha10599:ND-np4qQSEjM2412',
        toNodeId: 'FL-soem999bnha10599:ND-qVtyHsxck8257',
        lengthM: 5.818820,
      ),
    ],
    '2F': [
      // 15.7m 절약(우회비 3.33), 여유폭 1.70m, 차수 2+2, local_m (82.3,151.2)-(89.0,151.5)
      CorridorShortcut(
        fromNodeId: 'FL-qxirle6jha9l0574:ND-0mB2GAbfj0527',
        toNodeId: 'FL-qxirle6jha9l0574:ND-jlTEZ60hv9297',
        lengthM: 6.762319,
      ),
    ],
    '3F': [
      // 9.5m 절약(우회비 3.07), 여유폭 1.12m, 차수 2+2, local_m (82.1,135.4)-(86.6,134.2)
      CorridorShortcut(
        fromNodeId: 'FL-t4f3r0t8nnlf0560:ND-UFpJZgbwj4498',
        toNodeId: 'FL-t4f3r0t8nnlf0560:ND-BI8dYKVvJQ9851',
        lengthM: 4.618182,
      ),
    ],
    '4F': [
      // 12.9m 절약(우회비 2.61), 여유폭 1.80m, 차수 2+2, local_m (192.7,118.5)-(188.7,125.5)
      CorridorShortcut(
        fromNodeId: 'FL-urk3dfu89rg50546:ND-d8tinw3zWM0012',
        toNodeId: 'FL-urk3dfu89rg50546:ND-aPKGG4cmu5178',
        lengthM: 8.012348,
      ),
    ],
    '5F': [
      // 16.2m 절약(우회비 2.18), 여유폭 3.21m, 차수 2+2, local_m (210.8,149.8)-(224.5,148.5)
      CorridorShortcut(
        fromNodeId: 'FL-1iuvfnt4i456g0534:ND-9K1pn-wOE9926',
        toNodeId: 'FL-1iuvfnt4i456g0534:ND-mCpR8ZbljY2982',
        lengthM: 13.755075,
      ),
    ],
    '6F': [
      // 10.1m 절약(우회비 3.48), 여유폭 1.80m, 차수 2+2, local_m (82.2,170.2)-(86.3,170.0)
      CorridorShortcut(
        fromNodeId: 'FL-t89mxdj9mxcy0524:ND-hhKM7d-eF6497',
        toNodeId: 'FL-t89mxdj9mxcy0524:ND-YXT4ilEby7722',
        lengthM: 4.085488,
      ),
    ],
    'B1': [
      // 5.7m 절약(우회비 2.18), 여유폭 1.72m, 차수 2+2, local_m (129.7,133.3)-(131.9,137.7)
      CorridorShortcut(
        fromNodeId: 'FL-u855ha63yjxe0585:ND-8yUqQi3xV4226',
        toNodeId: 'FL-u855ha63yjxe0585:ND-FUCJF7Hmb3368',
        lengthM: 4.860339,
      ),
    ],
    'B5': [
      // 39.9m 절약(우회비 3.45), 여유폭 3.52m, 차수 2+2, local_m (179.7,189.2)-(196.0,188.8)
      CorridorShortcut(
        fromNodeId: 'FL-1ies91kjdirfn0649:ND-QIzzSbAtn0002',
        toNodeId: 'FL-1ies91kjdirfn0649:ND-QA2m4G3DF5404',
        lengthM: 16.297957,
      ),
      // 39.7m 절약(우회비 3.40), 여유폭 3.22m, 차수 2+2, local_m (137.6,188.9)-(154.2,189.1)
      CorridorShortcut(
        fromNodeId: 'FL-1ies91kjdirfn0649:ND-Qc1PYuEU08667',
        toNodeId: 'FL-1ies91kjdirfn0649:ND-4qBeHGjeN3021',
        lengthM: 16.582667,
      ),
      // 24.7m 절약(우회비 2.38), 여유폭 2.55m, 차수 2+1, local_m (166.6,124.5)-(168.0,142.3)
      CorridorShortcut(
        fromNodeId: 'FL-1ies91kjdirfn0649:ND-3_13dDkDYY9050',
        toNodeId: 'FL-1ies91kjdirfn0649:ND-rHXKwT6pov2838',
        lengthM: 17.919223,
      ),
      // 23.4m 절약(우회비 2.41), 여유폭 2.85m, 차수 2+2, local_m (137.6,197.1)-(154.2,197.4)
      CorridorShortcut(
        fromNodeId: 'FL-1ies91kjdirfn0649:ND-p8ITNuDhq7739',
        toNodeId: 'FL-1ies91kjdirfn0649:ND-w9e0ZfLGA4740',
        lengthM: 16.584700,
      ),
      // 23.0m 절약(우회비 2.41), 여유폭 2.49m, 차수 2+2, local_m (179.7,197.2)-(196.0,197.6)
      CorridorShortcut(
        fromNodeId: 'FL-1ies91kjdirfn0649:ND-PtmFhghxQ8980',
        toNodeId: 'FL-1ies91kjdirfn0649:ND-NggKq5Pul8550',
        lengthM: 16.296097,
      ),
    ],
    'B6': [
      // 43.7m 절약(우회비 3.53), 여유폭 3.00m, 차수 2+2, local_m (136.4,188.6)-(153.7,188.1)
      CorridorShortcut(
        fromNodeId: 'FL-rl7x0hl40i0m0673:ND-OJs-X1fbx7920',
        toNodeId: 'FL-rl7x0hl40i0m0673:ND-U4mypJIAG1822',
        lengthM: 17.242277,
      ),
      // 42.6m 절약(우회비 3.67), 여유폭 3.48m, 차수 2+2, local_m (180.1,189.0)-(196.1,188.8)
      CorridorShortcut(
        fromNodeId: 'FL-rl7x0hl40i0m0673:ND-jo3ZN84zKq3678',
        toNodeId: 'FL-rl7x0hl40i0m0673:ND-oax7UwDA17152',
        lengthM: 15.974827,
      ),
      // 27.0m 절약(우회비 2.57), 여유폭 2.97m, 차수 2+2, local_m (136.4,196.8)-(153.7,196.6)
      CorridorShortcut(
        fromNodeId: 'FL-rl7x0hl40i0m0673:ND-hmj45aXC00945',
        toNodeId: 'FL-rl7x0hl40i0m0673:ND-jSfEaTepk2759',
        lengthM: 17.265357,
      ),
    ],
  },
);
