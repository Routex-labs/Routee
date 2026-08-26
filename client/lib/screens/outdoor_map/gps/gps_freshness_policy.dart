/// 야외 위치가 낡았을 때 **직접 한 건 요청할지**를 정하는 정책.
///
/// 스트림은 1초를 약속하고도 실기기에서 15~36초에 한 건을 줬다. 그래서 스트림을
/// 믿되 조용한 구간만 일회성 조회로 메운다 — 스트림이 정상으로 돌아오면
/// [gpsFixMaxAge]에 걸리지 않아 **저절로 조용해지는 것이 정상 상태다.**
///
/// 실측 로그, 벙어리 스트림의 원인, 각 상수의 근거는
/// `docs/client/gps-stream-policy.md`.
library;

/// 마지막 좌표가 이보다 오래되면 직접 한 건 요청한다.
///
/// 스트림 주기(1초)보다 넉넉해야 한다 — 정상 기기에서 추가 요청이 나가면
/// 배터리만 쓰고 얻는 것이 없다.
const gpsFixMaxAge = Duration(seconds: 3);

/// 떠 있는 일회성 조회를 이 시간까지만 기다린다.
///
/// **상한이 없으면 실내에서 위치가 통째로 멎는다.** 스트림이 조용한 구간을
/// 떠받치는 것이 이 조회 하나인데, `getCurrentPosition`은 좌표가 생길 때까지
/// 무한정 기다릴 수 있다. 겹침 방지 플래그를 그동안 세워 두면 **다음 주기가
/// 아예 안 나가고**, 신호가 가장 나쁜 구간에서 유일한 생명줄이 멈춘다.
///
/// 요청을 취소하지는 않는다 — 늦게 도착한 좌표는 배달구의 메아리·튐 거르기가
/// 받아 준다. 여기서 푸는 것은 "다음 요청을 막고 있다"는 것 하나다.
///
/// 6초는 실측 응답 간격(3~9초)의 가운데다. 더 짧으면 정상 응답을 기다리는 중에
/// 요청이 겹치고, 더 길면 멎은 구간이 그만큼 길어진다.
const oneShotFixMaxWait = Duration(seconds: 6);

/// [startedAt]에 쏜 조회가 아직 다음 요청을 막아야 하는지.
///
/// null이면 떠 있는 요청이 없다는 뜻이다.
bool isFreshFixRequestBlocking({
  required DateTime? startedAt,
  required DateTime now,
  Duration maxWait = oneShotFixMaxWait,
}) {
  if (startedAt == null) return false;
  return now.difference(startedAt) < maxWait;
}

/// 지금 일회성 위치 조회를 보내야 하는지.
///
/// [lastFixReceivedAt]은 좌표를 **받은** 시각이다(기기가 찍은 시각이 아니다).
/// null이면(아직 한 건도 못 받았으면) 즉시 요청한다. [requestInFlight]로 요청이
/// 겹치는 것을 막고, 실내에서 아예 돌리지 않는 판단은 호출자가 한다.
bool shouldRequestFreshFix({
  required DateTime? lastFixReceivedAt,
  required DateTime now,
  required bool requestInFlight,
  Duration maxAge = gpsFixMaxAge,
}) {
  if (requestInFlight) return false;
  if (lastFixReceivedAt == null) return true;
  return now.difference(lastFixReceivedAt) >= maxAge;
}

/// 닫힌 위치 스트림을 다시 열기까지 기다리는 첫 간격.
const streamRetryMinDelay = Duration(seconds: 2);

/// 재연결 간격의 상한.
const streamRetryMaxDelay = Duration(seconds: 30);

/// 스트림이 이 시간 동안 좌표를 한 건도 안 주면 **죽은 것으로 본다.**
///
/// geolocator 안드로이드는 포그라운드 서비스 바인딩 전에 구독하면 위치 요청을
/// 걸지 않고 그냥 돌아선다 — 에러도 종료도 가지 않아 `onDone`으로는 못 잡는다.
/// 이 감시가 **유일한 탈출구**다.
///
/// **첫 좌표가 아니라 마지막 좌표에서 다시 잰다.** 한 건만 주고 조용해지는
/// 스트림이 실기기에서 나왔는데, 첫 좌표에서 감시를 걷으면 아무도 못 잡는다.
const streamSilenceTimeout = Duration(seconds: 12);

/// 다음 재연결까지 기다릴 시간. 실패가 이어지면 배로 늘리고 [streamRetryMaxDelay]
/// 에서 멈춘다.
///
/// 늘리는 이유는 **영구 실패**(권한 거부·위치 서비스 꺼짐) 때문이고, 상한이
/// 필요한 이유는 잠깐 끊겼다 돌아오는 기기 때문이다.
Duration nextStreamRetryDelay(Duration current) {
  final doubled = current * 2;
  return doubled > streamRetryMaxDelay ? streamRetryMaxDelay : doubled;
}
