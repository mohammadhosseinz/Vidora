import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

enum CookieFailure { invalid, noMatchingCookies }

class CookieException implements Exception {
  final CookieFailure reason;
  CookieException(this.reason);
}

/// A domain-scoped snapshot in memory. Never stores the path of the user's jar.
class CookieSession {
  final String _contents;
  CookieSession._(this._contents);
  @override
  String toString() => 'CookieSession(redacted)';

  static Future<CookieSession> load(String path, String url) async {
    try {
      final file = File(path);
      if (await file.length() > 8 * 1024 * 1024)
        throw CookieException(CookieFailure.invalid);
      return parse(await file.readAsString(encoding: utf8), url);
    } on FileSystemException {
      throw CookieException(CookieFailure.invalid);
    } on FormatException {
      throw CookieException(CookieFailure.invalid);
    }
  }

  static CookieSession parse(String contents, String url, {DateTime? now}) {
    final lines = const LineSplitter().convert(
      contents.replaceFirst(RegExp(r'^\uFEFF'), ''),
    );
    if (lines.isEmpty ||
        ![
          '# Netscape HTTP Cookie File',
          '# HTTP Cookie File',
        ].contains(lines.first.trim())) {
      throw CookieException(CookieFailure.invalid);
    }
    final host = Uri.parse(url).host.toLowerCase();
    final youtube =
        host == 'youtube.com' ||
        host.endsWith('.youtube.com') ||
        host == 'youtu.be';
    final hosts = youtube
        ? [host, 'www.youtube.com', 'youtube.com', 'youtu.be']
        : [host];
    final seconds = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    final kept = <String>[];
    for (final raw in lines.skip(1)) {
      if (raw.trim().isEmpty ||
          (raw.startsWith('#') && !raw.startsWith('#HttpOnly_')))
        continue;
      final row = raw.startsWith('#HttpOnly_') ? raw.substring(10) : raw;
      final fields = row.split('\t');
      if (fields.length != 7 ||
          !['TRUE', 'FALSE'].contains(fields[1]) ||
          !['TRUE', 'FALSE'].contains(fields[3]) ||
          (fields[4].isNotEmpty && int.tryParse(fields[4]) == null) ||
          fields[5].isEmpty ||
          !fields[2].startsWith('/') ||
          row.contains('\u0000')) {
        throw CookieException(CookieFailure.invalid);
      }
      final domain = fields[0].replaceFirst(RegExp(r'^\.'), '').toLowerCase();
      if (domain.isEmpty || (!domain.contains('.') && domain != 'localhost'))
        continue;
      if (!hosts.any(
        (h) => h == domain || (fields[1] == 'TRUE' && h.endsWith('.$domain')),
      ))
        continue;
      final expiry = fields[4].isEmpty ? 0 : int.parse(fields[4]);
      if (expiry != 0 && expiry <= seconds) continue;
      fields[0] = fields[1] == 'TRUE' ? '.$domain' : domain;
      fields[4] = expiry.toString();
      kept.add(
        '${raw.startsWith('#HttpOnly_') ? '#HttpOnly_' : ''}${fields.join('\t')}',
      );
    }
    if (kept.isEmpty) throw CookieException(CookieFailure.noMatchingCookies);
    return CookieSession._('# Netscape HTTP Cookie File\n${kept.join('\n')}\n');
  }

  /// yt-dlp writes its cookie jar on exit, so it receives a private copy only.
  Future<CookieLease> stage() async {
    final directory = await Directory.systemTemp.createTemp(
      'local-video-auth-',
    );
    try {
      if (!Platform.isWindows) {
        final chmod = await Process.run('chmod', [
          '700',
          directory.path,
        ], runInShell: false);
        if (chmod.exitCode != 0) throw CookieException(CookieFailure.invalid);
      }
      final jar = File(p.join(directory.path, 'cookies.txt'));
      await jar.writeAsString(
        Platform.isWindows ? _contents.replaceAll('\n', '\r\n') : _contents,
        encoding: utf8,
        flush: true,
      );
      if (!Platform.isWindows) {
        final chmod = await Process.run('chmod', [
          '600',
          jar.path,
        ], runInShell: false);
        if (chmod.exitCode != 0) throw CookieException(CookieFailure.invalid);
      }
      return CookieLease._(directory, jar.path);
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
  }
}

class CookieLease {
  final Directory _directory;
  final String path;
  CookieLease._(this._directory, this.path);
  List<String> get arguments => ['--cookies', path];
  Future<void> dispose() async {
    if (await _directory.exists()) await _directory.delete(recursive: true);
  }
}
