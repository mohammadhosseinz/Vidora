import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'cookies.dart';

enum Failure {
  invalid,
  incompatibleFormat,
  unsupported,
  network,
  proxy,
  invalidProxy,
  bot,
  restricted,
  extraction,
  tools,
  storage,
  invalidCookies,
  noMatchingCookies,
}

enum ConnectionMode { automatic, system, direct, custom }

class ConnectionOptions {
  final ConnectionMode mode;
  final String proxy;
  const ConnectionOptions({
    this.mode = ConnectionMode.automatic,
    this.proxy = '',
  });
  List<String> arguments() {
    if (mode == ConnectionMode.system || mode == ConnectionMode.automatic)
      return [];
    if (mode == ConnectionMode.direct) return ['--proxy', ''];
    final uri = Uri.tryParse(proxy);
    if (uri == null ||
        !['http', 'https', 'socks5'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/'))
      throw EngineException(Failure.invalidProxy);
    return ['--proxy', proxy];
  }

  List<ConnectionOptions> get attempts => mode == ConnectionMode.automatic
      ? const [
          ConnectionOptions(mode: ConnectionMode.system),
          ConnectionOptions(mode: ConnectionMode.direct),
        ]
      : [this];
}

class EngineException implements Exception {
  final Failure reason;
  EngineException(this.reason);
}

void validateLink(String link) {
  final uri = Uri.tryParse(link);
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      link.contains('\n')) {
    throw EngineException(Failure.invalid);
  }
}

Failure classify(String message) {
  final s = message.toLowerCase();
  if ([
    'unable to connect to proxy',
    'proxyerror',
    'proxy connection',
  ].any(s.contains))
    return Failure.proxy;
  if ([
    'not a bot',
    'confirm you’re not a bot',
    'confirm you\'re not a bot',
  ].any(s.contains))
    return Failure.bot;
  if ([
    'private video',
    'video unavailable',
    'video is unavailable',
    'sign in',
    'members-only',
    'age-restricted',
    'logged-in',
    'login required',
    'protected by a password',
    'http error 401',
    'not available in your country',
  ].any(s.contains))
    return Failure.restricted;
  if (s.contains('unsupported url')) return Failure.unsupported;
  if ([
    'timed out',
    'unable to download',
    'connection',
    'name resolution',
    'network',
  ].any(s.contains))
    return Failure.network;
  return Failure.extraction;
}

String safeName(String title) {
  var s = title.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f%]'), '_').trim();
  s = s.replaceAll(RegExp(r'[. ]+$'), '');
  if (s.isEmpty) s = 'video';
  if (RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])($|[.])',
    caseSensitive: false,
  ).hasMatch(s))
    s = '_$s';
  return String.fromCharCodes(s.runes.take(70));
}

class Quality {
  final String id, ext;
  final int height;
  final bool audio;
  final int? bytes;
  final bool approximate;
  final String? videoCodec, audioCodec, audioId;
  Quality(
    this.id,
    this.ext,
    this.height,
    this.audio, {
    this.bytes,
    this.approximate = false,
    this.videoCodec,
    this.audioCodec,
    this.audioId,
  });

  bool get needsMerge => !audio && audioId != null;
  String get selector => needsMerge ? '$id+$audioId' : id;

  bool get supportsWebm {
    // An existing WebM stream can stay WebM even when its codecs are unknown.
    // Separate audio must have a known compatible codec before merging.
    final videoCompatible =
        (videoCodec == null && ext == 'webm') ||
        ['vp8', 'vp9', 'vp09', 'av1', 'av01'].any(
          (codec) =>
              videoCodec == codec || videoCodec?.startsWith('$codec.') == true,
        );
    final audioCompatible =
        (!audio && !needsMerge) ||
        ['opus', 'vorbis'].contains(audioCodec) ||
        (audioCodec == null && ext == 'webm' && !needsMerge);
    return videoCompatible && audioCompatible;
  }

  List<String> get containers => ['mkv', 'mp4', if (supportsWebm) 'webm'];
}

({int? bytes, bool approximate}) formatSize(
  Map<String, dynamic> f,
  num? duration,
) {
  for (final key in ['filesize', 'filesize_approx']) {
    final n = f[key];
    if (n is num && n.isFinite && n > 0)
      return (bytes: n.round(), approximate: key != 'filesize');
  }
  final rate = f['tbr'];
  if (rate is num &&
      rate.isFinite &&
      rate > 0 &&
      duration != null &&
      duration.isFinite &&
      duration > 0) {
    return (bytes: (rate * 1000 * duration / 8).round(), approximate: true);
  }
  return (bytes: null, approximate: true);
}

List<Quality> parseQualities(Map<String, dynamic> data) {
  final formats = (data['formats'] as List? ?? []).cast<Map<String, dynamic>>();
  final audio = formats
      .where(
        (f) =>
            f['vcodec'] == 'none' &&
            f['acodec'] != 'none' &&
            f['has_drm'] != true &&
            RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch('${f['format_id']}'),
      )
      .toList();
  final bestAudio = audio.isEmpty ? null : audio.last;
  final audioSize = bestAudio == null
      ? (bytes: null, approximate: true)
      : formatSize(bestAudio, data['duration'] as num?);
  final result = <Quality>[];
  for (final f in formats) {
    if (f['vcodec'] == 'none' ||
        (f['vcodec'] == null &&
            (f['video_ext'] == null || f['video_ext'] == 'none')) ||
        f['has_drm'] == true ||
        !RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch('${f['format_id']}'))
      continue;
    final hasAudio = f['acodec'] != 'none';
    final needsMerge = !hasAudio && bestAudio != null;
    final size = formatSize(f, data['duration'] as num?);
    final bytes = size.bytes == null || (needsMerge && audioSize.bytes == null)
        ? null
        : size.bytes! + (needsMerge ? audioSize.bytes! : 0);
    result.add(
      Quality(
        '${f['format_id']}',
        '${f['ext']}',
        (f['height'] as num? ?? 0).toInt(),
        hasAudio,
        bytes: bytes,
        approximate: size.approximate || (needsMerge && audioSize.approximate),
        videoCodec: f['vcodec'] as String?,
        audioCodec: (needsMerge ? bestAudio['acodec'] : f['acodec']) as String?,
        audioId: needsMerge ? '${bestAudio['format_id']}' : null,
      ),
    );
  }
  result.sort((a, b) => b.height.compareTo(a.height));
  return result;
}

class Video {
  final String url, title;
  final String? thumbnail;
  final Uint8List? thumbnailBytes;
  final List<Quality> qualities;
  final ConnectionOptions connection;
  final CookieSession? cookies;
  Video(
    this.url,
    this.title,
    this.thumbnail,
    this.qualities, {
    this.connection = const ConnectionOptions(),
    this.cookies,
    this.thumbnailBytes,
  });
}

class Progress {
  final double fraction;
  final String speed;
  Progress(this.fraction, this.speed);
}

abstract class DownloadEngine {
  Future<Video> inspect(String url);
  Future<String> download(
    Video video,
    Quality quality,
    String container,
    String folder,
    String id,
    void Function(Progress) progress,
  );
  Future<void> cancel(String id);
  Future<void> openFolder(String folder);
}

class DesktopEngine implements DownloadEngine {
  String? cookieFile;
  ConnectionOptions connection = const ConnectionOptions();
  final String tools;
  final Map<String, Process> _running = {};
  final Set<String> _cancelled = {};
  Process? _inspection;
  bool _closing = false;
  DesktopEngine({String? toolsDirectory})
    : tools =
          toolsDirectory ??
          p.join(p.dirname(Platform.resolvedExecutable), 'tools');
  String exe(String name) =>
      p.join(tools, '$name${Platform.isWindows ? '.exe' : ''}');
  Future<void> check() async {
    for (final name in ['yt-dlp', 'ffmpeg', 'ffprobe', 'deno']) {
      if (!await File(exe(name)).exists()) throw EngineException(Failure.tools);
    }
  }

  List<String> get common => [
    '--ignore-config',
    '--no-plugin-dirs',
    if (Directory(p.join(tools, 'plugins')).existsSync()) ...[
      '--plugin-dirs',
      p.join(tools, 'plugins'),
    ],
    '--no-playlist',
    '--no-update',
    '--no-remote-components',
    '--no-js-runtimes',
    '--encoding',
    'utf-8',
    '--socket-timeout',
    '20',
    '--retries',
    '2',
    '--extractor-retries',
    '1',
    '--js-runtimes',
    'deno:${exe('deno')}',
    '--ffmpeg-location',
    tools,
  ];
  @override
  Future<Video> inspect(String url) async {
    validateLink(url);
    CookieSession? session;
    try {
      if (cookieFile != null)
        session = await CookieSession.load(cookieFile!, url);
    } on CookieException catch (e) {
      throw EngineException(
        e.reason == CookieFailure.invalid
            ? Failure.invalidCookies
            : Failure.noMatchingCookies,
      );
    }
    final options = connection;
    final attempts = options.attempts;
    for (var index = 0; index < attempts.length; index++) {
      try {
        return await _inspect(
          url,
          attempts[index],
          session: session,
          timeout: options.mode == ConnectionMode.automatic
              ? Duration(seconds: index == 0 ? 30 : 60)
              : const Duration(seconds: 90),
        );
      } on EngineException catch (e) {
        if (index == attempts.length - 1 ||
            ![Failure.proxy, Failure.network].contains(e.reason))
          rethrow;
      }
    }
    throw EngineException(Failure.network);
  }

  Future<Video> _inspect(
    String url,
    ConnectionOptions selectedConnection, {
    required Duration timeout,
    CookieSession? session,
  }) async {
    CookieLease? lease;
    try {
      lease = await session?.stage();
      final video = await _inspectProcess(
        url,
        selectedConnection,
        timeout: timeout,
        session: session,
        cookieArgs: lease?.arguments ?? [],
      );
      if (lease == null) return video;
      final refreshed = await CookieSession.load(lease.path, url);
      return Video(
        video.url,
        video.title,
        video.thumbnail,
        video.qualities,
        connection: video.connection,
        cookies: refreshed,
        thumbnailBytes: video.thumbnailBytes,
      );
    } on CookieException {
      throw EngineException(Failure.invalidCookies);
    } on FileSystemException {
      throw EngineException(Failure.storage);
    } finally {
      await lease?.dispose();
    }
  }

  Future<Video> _inspectProcess(
    String url,
    ConnectionOptions selectedConnection, {
    required Duration timeout,
    required List<String> cookieArgs,
    CookieSession? session,
  }) async {
    final connectionArgs = selectedConnection.arguments();
    await check();
    if (_closing) throw EngineException(Failure.extraction);
    final proc = await Process.start(
      exe('yt-dlp'),
      [
        ...common,
        ...connectionArgs,
        ...cookieArgs,
        '--dump-single-json',
        '--retries',
        '1',
        '--extractor-retries',
        '0',
        '--skip-download',
        '--',
        url,
      ],
      runInShell: false,
      environment: const {'PYTHONDONTWRITEBYTECODE': '1'},
    );
    _inspection = proc;
    final out = proc.stdout.transform(utf8.decoder).join();
    final err = proc.stderr.transform(utf8.decoder).join();
    if (_closing) await _killTree(proc);
    int code;
    try {
      code = await proc.exitCode.timeout(timeout);
    } on TimeoutException {
      await _killTree(proc);
      _inspection = null;
      throw EngineException(Failure.network);
    }
    final error = await err;
    _inspection = null;
    if (code != 0) throw EngineException(classify(error));
    try {
      final data = jsonDecode(await out) as Map<String, dynamic>;
      final q = parseQualities(data);
      if (q.isEmpty) throw EngineException(Failure.extraction);
      final thumb = data['thumbnail'] as String?;
      final image = thumb == null
          ? null
          : await _loadThumbnail(data, connectionArgs, cookieArgs);
      return Video(
        url,
        data['title'] as String? ?? 'video',
        thumb != null && Uri.tryParse(thumb)?.scheme == 'https' ? thumb : null,
        q,
        connection: selectedConnection,
        cookies: session,
        thumbnailBytes: image,
      );
    } on EngineException {
      rethrow;
    } catch (_) {
      throw EngineException(Failure.extraction);
    }
  }

  Future<Uint8List?> _loadThumbnail(
    Map<String, dynamic> data,
    List<String> connectionArgs,
    List<String> cookieArgs,
  ) async {
    final dir = await Directory.systemTemp.createTemp('local-video-preview-');
    Process? process;
    try {
      if (!Platform.isWindows)
        await Process.run('chmod', ['700', dir.path], runInShell: false);
      final info = File(p.join(dir.path, 'metadata.json'));
      await info.writeAsString(jsonEncode(data));
      if (_closing) return null;
      process = await Process.start(
        exe('yt-dlp'),
        [
          ...common,
          ...connectionArgs,
          ...cookieArgs,
          '--socket-timeout',
          '8',
          '--retries',
          '0',
          '--skip-download',
          '--write-thumbnail',
          '--load-info-json',
          info.path,
          '-o',
          p.join(dir.path, 'preview.%(ext)s'),
        ],
        runInShell: false,
        environment: const {'PYTHONDONTWRITEBYTECODE': '1'},
      );
      _inspection = process;
      final stdoutDone = process.stdout.drain<void>();
      final stderrDone = process.stderr.drain<void>();
      if (_closing) await _killTree(process);
      final code = await process.exitCode.timeout(const Duration(seconds: 12));
      await Future.wait([stdoutDone, stderrDone]);
      if (code != 0) return null;
      for (final file in dir.listSync().whereType<File>()) {
        if (p.basename(file.path).startsWith('preview.') &&
            [
              '.jpg',
              '.jpeg',
              '.png',
              '.webp',
            ].contains(p.extension(file.path).toLowerCase()) &&
            await file.length() <= 10 * 1024 * 1024)
          return await file.readAsBytes();
      }
    } catch (_) {
      if (process != null) await _killTree(process);
    } finally {
      _inspection = null;
      await dir.delete(recursive: true);
    }
    return null;
  }

  @override
  Future<String> download(
    Video video,
    Quality quality,
    String container,
    String folder,
    String id,
    void Function(Progress) progress,
  ) async {
    validateLink(video.url);
    final connectionArgs = video.connection.arguments();
    if (!['mp4', 'mkv', 'webm'].contains(container) ||
        !RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(quality.id) ||
        (quality.audioId != null &&
            !RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(quality.audioId!)))
      throw EngineException(Failure.invalid);
    if (!quality.containers.contains(container))
      throw EngineException(Failure.incompatibleFormat);
    await check();
    if (_closing) throw EngineException(Failure.extraction);
    final destination = Directory(folder);
    if (!await destination.exists()) throw EngineException(Failure.storage);
    final temp = await destination.createTemp('.local-video-');
    String? result;
    CookieLease? cookieLease;
    try {
      cookieLease = await video.cookies?.stage();
      if (_cancelled.remove(id)) throw EngineException(Failure.extraction);
      final proc = await Process.start(
        exe('yt-dlp'),
        [
          ...common,
          ...connectionArgs,
          ...?cookieLease?.arguments,
          '--newline',
          '--no-color',
          '--progress',
          '--progress-template',
          'download:PROGRESS:%(progress._percent_str)s|%(progress._speed_str)s',
          '--print',
          'after_move:FILE:%(filepath)s',
          '--no-simulate',
          '--windows-filenames',
          '--no-overwrites',
          '-f',
          quality.selector,
          '--merge-output-format',
          container,
          '--remux-video',
          container,
          '-o',
          p.join(
            temp.path.replaceAll('%', '%%'),
            '${safeName(video.title)}.%(ext)s',
          ),
          '--',
          video.url,
        ],
        runInShell: false,
        environment: const {'PYTHONDONTWRITEBYTECODE': '1'},
      );
      _running[id] = proc;
      final stderr = proc.stderr.transform(utf8.decoder).join();
      if (_closing || _cancelled.contains(id)) await cancel(id);
      await for (final line
          in proc.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (line.startsWith('FILE:')) result = line.substring(5).trim();
        if (line.startsWith('PROGRESS:')) {
          final parts = line.substring(9).split('|');
          final percent =
              double.tryParse(parts.first.replaceAll('%', '').trim()) ?? 0;
          final speed = parts.length > 1 ? parts[1].trim() : '';
          progress(
            Progress(
              (percent / 100).clamp(0, 1),
              speed.contains('Unknown') ? '—' : speed,
            ),
          );
        }
      }
      final code = await proc.exitCode;
      final error = await stderr;
      if (_cancelled.contains(id)) throw EngineException(Failure.extraction);
      if (code != 0 || result == null) throw EngineException(classify(error));
      if (!p.isWithin(temp.absolute.path, p.absolute(result)))
        throw EngineException(Failure.storage);
      final finalPath = p.join(
        folder,
        '${safeName(video.title)}_$id.$container',
      );
      if (await File(finalPath).exists())
        throw EngineException(Failure.storage);
      await File(result).rename(finalPath);
      return finalPath;
    } on CookieException {
      throw EngineException(Failure.invalidCookies);
    } on FileSystemException {
      throw EngineException(Failure.storage);
    } finally {
      _running.remove(id);
      _cancelled.remove(id);
      try {
        await cookieLease?.dispose();
      } finally {
        if (await temp.exists()) await temp.delete(recursive: true);
      }
    }
  }

  @override
  Future<void> cancel(String id) async {
    _cancelled.add(id);
    final proc = _running[id];
    if (proc == null) return;
    await _killTree(proc);
  }

  Future<void> _killTree(Process proc) async {
    if (Platform.isWindows) {
      await Process.run('taskkill', [
        '/PID',
        '${proc.pid}',
        '/T',
        '/F',
      ], runInShell: false);
    } else {
      // Snapshot the whole tree before the parent exits and children are
      // reparented. Force-stop leaves first so inherited pipes also close.
      final snapshot = await Process.run('ps', [
        '-axo',
        'pid=,ppid=',
      ], runInShell: false);
      if (snapshot.exitCode != 0) {
        proc.kill(ProcessSignal.sigkill);
        throw EngineException(Failure.extraction);
      }
      final children = <int, List<int>>{};
      for (final line in const LineSplitter().convert(
        snapshot.stdout as String,
      )) {
        final fields = line.trim().split(RegExp(r'\s+'));
        if (fields.length != 2) continue;
        final pid = int.tryParse(fields[0]), parent = int.tryParse(fields[1]);
        if (pid != null && parent != null)
          children.putIfAbsent(parent, () => []).add(pid);
      }
      final tree = <int>[proc.pid];
      final seen = <int>{proc.pid};
      for (var index = 0; index < tree.length; index++) {
        for (final child in children[tree[index]] ?? <int>[]) {
          if (seen.add(child)) tree.add(child);
        }
      }
      for (final pid in tree.skip(1).toList().reversed) {
        Process.killPid(pid, ProcessSignal.sigkill);
      }
      proc.kill(ProcessSignal.sigkill);
    }
    try {
      await proc.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      proc.kill(ProcessSignal.sigkill);
      await proc.exitCode.timeout(const Duration(seconds: 5));
    }
  }

  Future<void> shutdown() async {
    _closing = true;
    if (_inspection != null) await _killTree(_inspection!);
    for (final id in _running.keys.toList()) {
      await cancel(id);
    }
  }

  @override
  Future<void> openFolder(String folder) async {
    final executable = Platform.isWindows
        ? 'explorer.exe'
        : Platform.isMacOS
        ? 'open'
        : 'xdg-open';
    await Process.start(executable, [p.absolute(folder)], runInShell: false);
  }
}
