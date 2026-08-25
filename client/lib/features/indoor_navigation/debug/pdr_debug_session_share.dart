import 'dart:convert';
import 'dart:ui';

import 'package:share_plus/share_plus.dart';

/// 디버그 세션 JSON을 파일 첨부로 시스템 공유 시트에 넘긴다.
class PdrDebugSessionShare {
  const PdrDebugSessionShare();

  /// [filenamePrefix]로 산출물을 가른다. PDR 주행 세션과 층별 고도표는 분석하는
  /// 사람도 도구도 달라서, 받은 사람이 파일 이름만으로 구분할 수 있어야 한다.
  Future<void> share(
    Map<String, Object?> session, {
    Rect? sharePositionOrigin,
    String filenamePrefix = 'pdr-debug',
    String subject = 'PDR debug session',
    String text = 'PDR 실측 디버그 세션 JSON입니다.',
  }) async {
    final startedAt = session['started_at_utc']?.toString() ?? 'unknown';
    final filename = '$filenamePrefix-${_filenameTimestamp(startedAt)}.json';
    final json = const JsonEncoder.withIndent('  ').convert(session);
    await Share.shareXFiles(
      [
        XFile.fromData(
          utf8.encode(json),
          mimeType: 'application/json',
          name: filename,
        ),
      ],
      subject: subject,
      text: text,
      sharePositionOrigin: sharePositionOrigin,
      fileNameOverrides: [filename],
    );
  }

  static String _filenameTimestamp(String iso8601) => iso8601
      .replaceAll(':', '-')
      .replaceAll('.', '-')
      .replaceAll('Z', 'Z')
      .replaceAll(RegExp(r'[^0-9A-Za-z_-]'), '-');
}
