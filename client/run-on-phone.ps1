# 기기 id는 `adb devices`로 확인해 바꾼다. 무선 ADB를 쓸 때는 `100.112.176.99:5555`처럼 주소:포트가 들어간다.
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8
Set-Location D:\Navigation\client
flutter run --dart-define-from-file=config.local.json -d R3CRB08TBZZ 2>&1 | ForEach-Object { $_; $_ | Out-File frontend.log -Append -Encoding utf8 }
