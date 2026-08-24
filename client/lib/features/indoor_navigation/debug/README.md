# `indoor_navigation/debug` — PDR 실기기 진단과 기록

센서 세션이 실제 기기에서 시작·정지되는지 확인하고, PDR 품질·보정·맵 매칭 상태를
재현 가능한 JSON으로 기록·공유한다. 운영 측위 계산을 변경하지 않는 관찰 계층이다.

## 구성 파일

| 파일 | 역할 | 주요 항목 |
|---|---|---|
| [`pdr_device_harness.dart`](pdr_device_harness.dart) | 센서 시작·스냅샷·정지 후 안정성을 확인하는 실기기 화면 | `PdrDeviceHarness`, receipt JSON |
| [`pdr_debug_session_recorder.dart`](pdr_debug_session_recorder.dart) | snapshot·품질·anchor·복도 보정 상태·경로 진행률을 제한된 크기로 수집 | `PdrDebugSessionRecorder`, schema v12 |
| [`pdr_debug_device_info.dart`](pdr_debug_device_info.dart) | OS·기기·앱 버전 메타데이터 수집 | `PdrDebugDeviceInfo` |
| [`pdr_debug_session_share.dart`](pdr_debug_session_share.dart) | 진단 JSON을 임시 파일로 만들어 공유 시트에 전달 | `PdrDebugSessionShare` |

## 진단 흐름

```mermaid
flowchart LR
    SOURCE["PdrMotionSource"]
    DRIVER["IndoorNavigationDriver"]
    HARNESS["PdrDeviceHarness"]
    RECEIPT["pdr-device-harness-result.json"]

    SNAPSHOT["snapshot · calibration · runtime"]
    GRAPH["FloorGraph"]
    RECORDER["PdrDebugSessionRecorder"]
    DEVICE["PdrDebugDeviceInfo"]
    JSON["schema v12 JSON"]
    SHARE["PdrDebugSessionShare"]

    SOURCE --> DRIVER --> HARNESS --> RECEIPT
    DRIVER --> SNAPSHOT --> RECORDER
    GRAPH --> RECORDER
    DEVICE --> RECORDER
    RECORDER --> JSON --> SHARE
```

## Device harness

실기기 센서 세션을 시작하고 이벤트 수신을 관찰한 뒤 stop 이후 경로가 더 늘어나지 않는지
확인한다. 결과는 성공/실패 detail과 함께 receipt 파일로 남겨 integration test가 읽을 수 있게 한다.

## Session recorder

- JSON `schemaVersion`의 단일 출처는 `pdr_debug_session_recorder.dart`다. 판별 이력은
  docs/pdr/pdr-dev-integration.md의 스키마 이력 표에 있다.
- 품질 표본은 최대 900개로 제한해 장시간 세션에서도 파일 크기가 무한히 늘지 않게 한다.
- PDR 원본/확정 경로, 보정 상태, runtime warning, 그래프 맵 매칭 결과를 함께 기록한다.
- `FloorGraph`가 있으면 `FloorMapMatcher`를 사용해 기록 경로를 네트워크에 맞춘 결과도 포함한다.
- v11부터 **길찾기 경로 기준 계측**을 남긴다. `route_context`(목적지·판정 기준 간선 목록),
  `route_progress_samples`(진행·남은·이탈거리와 on-route 여부), `route_progress_summary`
  (on-route 비율·재획득 횟수·최대 이탈거리). 길찾기 없이 걸은 세션에서는 세 값이 모두
  null·빈 배열이며, 그 파일로는 경로 기준 판단을 할 수 없다는 뜻이다.
- `route_progress_summary.on_route_ratio`는 **샘플 수 기준**이다. 샘플이 상태 변화마다
  추가되므로 이탈이 잦은 주행에서 이탈 쪽이 과대 대표될 수 있어, 주행 간 비교가 아니라
  한 주행 안의 눈대중 값으로만 쓴다.
- v12부터 **기압계와 층 전이 판정**을 남긴다. `altimeter`(가용 여부·센서 이름·표본 수),
  `altimeter_samples`(기압·환산 고도·평활·baseline·Δ·허가/후보 여부), 1Hz 품질 표본의
  `altimeter` 블록, `floor_transition_events`(허가·후보·확정·거부).
- **거부 이벤트도 남긴다.** 확정만 남기면 미탐이 파일에서 보이지 않고, 임계값(Δ·상승속도·
  허가 반경·유지 시간)은 전부 초안값이라 거부 이유 없이는 조정할 근거가 없다.
- `altimeter.available`이 false면 그 기기에는 기압계가 없어 층 추종이 애초에 돌지 않은
  세션이다. "조건이 안 맞아 안 걸린 것"과 구분해서 읽어야 한다.

## 실패 지점

- recorder가 센서나 controller 수명주기를 소유하면 진단 on/off가 운영 세션을 바꾼다.
- schema를 바꾸고 버전을 올리지 않으면 이전 분석 도구가 새 JSON을 잘못 해석한다.
- 표본 상한 없이 매 snapshot을 저장하면 긴 안내에서 메모리와 공유 파일이 커진다.
- iPad/iOS 공유 시 `sharePositionOrigin`이 없으면 popover 표시가 실패할 수 있다.
- receipt를 쓰기 전에 driver를 dispose하면 마지막 정지 검증 결과가 사라질 수 있다.

## 검증

- harness 위젯: [`../../../../test/features/indoor_navigation/pdr_device_harness_test.dart`](../../../../test/features/indoor_navigation/pdr_device_harness_test.dart)
- recorder: [`../../../../test/features/indoor_navigation/pdr_debug_session_recorder_test.dart`](../../../../test/features/indoor_navigation/pdr_debug_session_recorder_test.dart)
- 실기기 smoke: [`../../../../integration_test/pdr_device_smoke_test.dart`](../../../../integration_test/pdr_device_smoke_test.dart)

---

> **다음 읽기:** [`features/debug_mode` — 지도·PDR 개발 진단](../../debug_mode/README.md)
