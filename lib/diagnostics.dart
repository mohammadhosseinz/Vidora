import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// Retain engine output, with bounded memory and secrets removed before storage.
class Diagnostics {
  final Directory? directory;
  final _logs = LinkedHashMap<String, String>();
  final _secrets = <String>{};
  static const maxCharacters = 1024 * 1024;
  Diagnostics({this.directory});

  void protect(Iterable<String> values) {
    _secrets.addAll(values.where((v) => v.isNotEmpty));
  }

  String redact(String source) {
    var text = source;
    final secrets = _secrets.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final value in secrets) {
      text = text.replaceAll(value, '[redacted]');
    }
    text = text.replaceAll(
      RegExp(r'(?:https?|socks5)://[^\s\x22\x27<>]+'),
      '[URL redacted]',
    );
    text = text.replaceAll(
      RegExp(
        r'^.*(?:cookie|authorization|password|token|--add-headers|--user-agent|--referer).*$',
        caseSensitive: false,
        multiLine: true,
      ),
      '[sensitive line redacted]',
    );
    return text;
  }

  void add(String id, String source) {
    final value = '${_logs[id] ?? ''}${redact(source)}\n';
    _logs[id] = value.length <= maxCharacters
        ? value
        : '[earlier output omitted]\n${value.substring(value.length - maxCharacters)}';
    while (_logs.length > 100) {
      _logs.remove(_logs.keys.first);
    }
  }

  String text(String id) => _logs[id] ?? '';

  Future<String> read(String id) async {
    if (_logs.containsKey(id)) return text(id);
    if (directory == null || !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id))
      return '';
    try {
      final file = File(p.join(directory!.path, '$id.log'));
      if (await file.length() > 4 * maxCharacters) return '';
      return redact(await file.readAsString());
    } on FileSystemException {
      return '';
    }
  }

  Future<void> flush(String id) async {
    if (directory == null || !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) return;
    try {
      await directory!.create(recursive: true);
      if (!Platform.isWindows)
        await Process.run('chmod', ['700', directory!.path]);
      final file = File(p.join(directory!.path, '$id.log'));
      await file.writeAsString(text(id), encoding: utf8, flush: true);
      if (!Platform.isWindows) await Process.run('chmod', ['600', file.path]);
      final logs = await directory!
          .list()
          .where((f) => f is File && f.path.endsWith('.log'))
          .cast<File>()
          .toList();
      if (logs.length > 100) {
        logs.sort(
          (a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()),
        );
        for (final old in logs.take(logs.length - 100)) {
          await old.delete();
        }
      }
    } on FileSystemException {
      /* Diagnostics must not break a download. */
    } on ProcessException {
      /* chmod unavailable; keep in-memory output. */
    }
  }
}
