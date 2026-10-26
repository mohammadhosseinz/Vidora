import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'cookies.dart';
import 'diagnostics.dart';
import 'site_profiles.dart';

enum Failure {
  invalid,
  invalidOptions,
  expired,
  geoBlocked,
  loginRequired,
  cookiesRequired,
  drm,
  rateLimited,
  formatUnavailable,
  forbidden,
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
      ? [
          const ConnectionOptions(mode: ConnectionMode.system),
          ConnectionOptions(mode: ConnectionMode.direct),
          if (proxy.isNotEmpty)
            ConnectionOptions(mode: ConnectionMode.custom, proxy: proxy),
        ]
      : [this];
}

class EngineException implements Exception {
  final Failure reason;
  final String? logId;
  EngineException(this.reason, {this.logId});
}

void validateLink(String link) {
  final uri = Uri.tryParse(link);
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      link.length > 16384 ||
      RegExp(r'[\x00-\x20\x7f]').hasMatch(link)) {
    throw EngineException(Failure.invalid);
  }
}

Failure classify(String message) {
  final s = message.toLowerCase();
  bool has(List<String> markers) => markers.any(s.contains);
  // Specific causes must precede broad messages such as "unable to download".
  if (has([
    'drm protected',
    'drm-protected',
    'digital rights management',
    'has drm',
  ]))
    return Failure.drm;
  if (has(['unable to connect to proxy', 'proxyerror', 'proxy connection']))
    return Failure.proxy;
  if (has([
    'not a bot',
    'captcha',
    'cloudflare',
    'confirm you’re not a bot',
    "confirm you're not a bot",
  ]))
    return Failure.bot;
  if (has(['http error 429', 'too many requests', 'rate limit']))
    return Failure.rateLimited;
  if (has([
    'not available in your country',
    'geo-restricted',
    'geo restricted',
    'geoblocked',
    'geographic restriction',
    'not available from your location',
  ]))
    return Failure.geoBlocked;
  if (has([
    'expired url',
    'url has expired',
    'link has expired',
    'signature has expired',
    'token has expired',
  ]))
    return Failure.expired;
  if (has([
    'cookies are required',
    'cookies required',
    'use --cookies',
    'pass --cookies',
    'cookies have expired',
    'cookies are no longer valid',
  ]))
    return Failure.cookiesRequired;
  if (has([
    'sign in',
    'log in',
    'login required',
    'logged-in',
    'http error 401',
    'members-only',
    'age-restricted',
  ]))
    return Failure.loginRequired;
  if (has(['requested format is not available', 'no video formats found']))
    return Failure.formatUnavailable;
  if (s.contains('unsupported url')) return Failure.unsupported;
  if (has([
    'private video',
    'video unavailable',
    'video is unavailable',
    'protected by a password',
    'http error 404',
    'http error 410',
  ]))
    return Failure.restricted;
  if (s.contains('http error 403')) return Failure.forbidden;
  if (has([
    'timed out',
    'unable to download',
    'connection',
    'name resolution',
    'network',
  ]))
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
  final DownloadOptions options;
  final bool impersonate;
  final bool requiresSession;
  final ConnectionOptions? fallbackConnection;
  Video(
    this.url,
    this.title,
    this.thumbnail,
    this.qualities, {
    this.connection = const ConnectionOptions(),
    this.cookies,
    this.thumbnailBytes,
    DownloadOptions? options,
    this.impersonate = false,
    this.requiresSession = false,
    this.fallbackConnection,
  }) : options = options ?? DownloadOptions();
}

class Progress {
  final double fraction;
  final String speed;
  final String phase;
  final int attempt;
  final int? height;
  final Quality? selectedQuality;
  Progress(
    this.fraction,
    this.speed, {
    this.phase = 'running',
    this.attempt = 1,
    this.height,
    this.selectedQuality,
  });
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
  DownloadOptions options = DownloadOptions();
  final Diagnostics diagnostics;
  final Set<String> _paused = {};
  bool? _impersonationAvailable;
  final _probes = <Process>{};
  ConnectionOptions connection = const ConnectionOptions();
  final String tools;
  final Map<String, Process> _running = {};
  final Set<String> _cancelled = {};
  Process? _inspection;
  String? _inspectionId;
  bool _closing = false;
  Future<void> _inspections = Future.value();
  DesktopEngine({String? toolsDirectory, Diagnostics? diagnostics})
    : diagnostics = diagnostics ?? Diagnostics(),
      tools =
          toolsDirectory ??
          p.join(p.dirname(Platform.resolvedExecutable), 'tools');
  String exe(String name) =>
      p.join(tools, '$name${Platform.isWindows ? '.exe' : ''}');
  Future<void> check() async {
    for (final name in ['yt-dlp', 'ffmpeg', 'ffprobe', 'deno']) {
      if (!await File(exe(name)).exists()) throw EngineException(Failure.tools);
    }
  }

  List<String> get common => commonFor(options);
  List<String> commonFor(DownloadOptions selected) => [
    '--ignore-config',
    '--no-plugin-dirs',
    if (selected.extractor == ExtractorMode.automatic &&
        Directory(p.join(tools, 'plugins')).existsSync()) ...[
      '--plugin-dirs',
      p.join(tools, 'plugins'),
    ],
    '--no-color',
    '--verbose',
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
  Future<ProcessResult> _probe(List<String> arguments) async {
    if (_closing) throw EngineException(Failure.tools);
    final process = await Process.start(
      exe('yt-dlp'),
      arguments,
      runInShell: false,
      environment: const {'PYTHONDONTWRITEBYTECODE': '1'},
    );
    _probes.add(process);
    final output = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    final error = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    try {
      if (_closing) await _killTree(process);
      final code = await process.exitCode.timeout(const Duration(seconds: 30));
      return ProcessResult(process.pid, code, await output, await error);
    } on TimeoutException {
      await _killTree(process);
      throw EngineException(Failure.tools);
    } finally {
      _probes.remove(process);
    }
  }

  Future<String> runtimeVersion() async {
    final result = await _probe([
      '--ignore-config',
      '--no-plugin-dirs',
      '--no-update',
      '--version',
    ]);
    if (result.exitCode != 0) throw EngineException(Failure.tools);
    return '${result.stdout}'.trim();
  }

  Future<bool> supportsImpersonation() async {
    if (_impersonationAvailable != null) return _impersonationAvailable!;
    try {
      final result = await _probe([
        '--ignore-config',
        '--no-plugin-dirs',
        '--no-update',
        '--list-impersonate-targets',
      ]);
      _impersonationAvailable =
          result.exitCode == 0 &&
          RegExp(
            r'^\s*(?:chrome|safari|edge|firefox)[-\s]',
            caseSensitive: false,
            multiLine: true,
          ).hasMatch('${result.stdout}');
    } catch (_) {
      return false;
    }
    return _impersonationAvailable!;
  }

  @override
  Future<Video> inspect(String url) async {
    try {
      validateLink(url);
      return await inspectWith(
        url,
        connection,
        options,
        cookieFile: cookieFile,
      );
    } on ProcessException {
      throw EngineException(Failure.tools, logId: 'inspection');
    } on EngineException catch (e) {
      diagnostics.add('inspection', 'Inspection failed: ${e.reason.name}');
      throw EngineException(e.reason, logId: 'inspection');
    } finally {
      await diagnostics.flush('inspection');
    }
  }

  Future<Video> inspectWith(
    String url,
    ConnectionOptions selected,
    DownloadOptions settings, {
    String? cookieFile,
    CookieSession? session,
    String logId = 'inspection',
    bool impersonate = false,
  }) {
    final completer = Completer<Video>();
    _inspections = _inspections.then((_) async {
      try {
        if (_closing) throw EngineException(Failure.extraction);
        completer.complete(
          await _inspectWith(
            url,
            selected,
            settings,
            cookieFile: cookieFile,
            session: session,
            logId: logId,
            impersonate: impersonate,
          ),
        );
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  Future<Video> _inspectWith(
    String url,
    ConnectionOptions selected,
    DownloadOptions settings, {
    String? cookieFile,
    CookieSession? session,
    String logId = 'inspection',
    bool impersonate = false,
  }) async {
    validateLink(url);
    try {
      settings.validate();
    } on FormatException {
      throw EngineException(Failure.invalidOptions);
    }
    diagnostics.protect([
      ...settings.headers.values,
      settings.userAgent,
      settings.referer,
    ]);
    if (cookieFile != null) {
      try {
        session = await CookieSession.load(cookieFile, url);
      } on CookieException catch (e) {
        throw EngineException(
          e.reason == CookieFailure.invalid
              ? Failure.invalidCookies
              : Failure.noMatchingCookies,
        );
      }
    }
    final sessionBound = session != null || settings.hasSessionHeaders;
    final attempts = sessionBound
        ? [selected.attempts.first]
        : selected.attempts;
    for (var index = 0; index < attempts.length; index++) {
      var useImpersonation = impersonate;
      while (true) {
        if (_closing || _paused.contains(logId) || _cancelled.contains(logId))
          throw EngineException(Failure.extraction);
        diagnostics.add(
          logId,
          'Inspect ${SiteProfile.forUrl(url).id}: ${attempts[index].mode.name}, impersonation=$useImpersonation',
        );
        try {
          final result = await _inspect(
            url,
            attempts[index],
            settings: settings,
            session: session,
            logId: logId,
            impersonate: useImpersonation,
            timeout: Duration(
              seconds: selected.mode == ConnectionMode.automatic
                  ? (index == 0 ? 30 : 60)
                  : 90,
            ),
          );
          return _copyVideo(result, fallbackConnection: selected);
        } on EngineException catch (e) {
          if (_closing || _paused.contains(logId) || _cancelled.contains(logId))
            rethrow;
          if (!sessionBound &&
              !useImpersonation &&
              settings.allowImpersonation &&
              SiteProfile.forUrl(url).impersonation &&
              [Failure.bot, Failure.forbidden].contains(e.reason) &&
              await supportsImpersonation()) {
            useImpersonation = true;
            continue;
          }
          if (index == attempts.length - 1 ||
              ![Failure.proxy, Failure.network].contains(e.reason))
            rethrow;
          break;
        }
      }
    }
    throw EngineException(Failure.network);
  }

  Future<Video> _inspect(
    String url,
    ConnectionOptions selectedConnection, {
    required Duration timeout,
    required DownloadOptions settings,
    required String logId,
    bool impersonate = false,
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
        settings: settings,
        logId: logId,
        impersonate: impersonate,
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
        options: video.options,
        impersonate: video.impersonate,
        requiresSession: true,
      );
    } on CookieException {
      throw EngineException(Failure.invalidCookies);
    } on FileSystemException {
      throw EngineException(Failure.storage);
    } finally {
      _inspectionId = null;
      await lease?.dispose();
    }
  }

  Future<Video> _inspectProcess(
    String url,
    ConnectionOptions selectedConnection, {
    required Duration timeout,
    required List<String> cookieArgs,
    required DownloadOptions settings,
    required String logId,
    bool impersonate = false,
    CookieSession? session,
  }) async {
    final connectionArgs = selectedConnection.arguments();
    await check();
    if (_closing) throw EngineException(Failure.extraction);
    final proc = await Process.start(
      exe('yt-dlp'),
      [
        ...commonFor(settings),
        ...settings.arguments(SiteProfile.forUrl(url)),
        if (impersonate) ...['--impersonate', 'chrome'],
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
    _inspectionId = logId;
    final out = proc.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    final err = _captureErrors(proc, logId);
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
      if (q.isEmpty) {
        final formats = data['formats'] as List? ?? [];
        throw EngineException(
          formats.any((f) => f['has_drm'] == true)
              ? Failure.drm
              : Failure.formatUnavailable,
        );
      }
      final thumb = data['thumbnail'] as String?;
      final image = thumb == null
          ? null
          : await _loadThumbnail(
              data,
              connectionArgs,
              cookieArgs,
              settings,
              impersonate,
              logId,
            );
      return Video(
        url,
        data['title'] as String? ?? 'video',
        thumb != null && Uri.tryParse(thumb)?.scheme == 'https' ? thumb : null,
        q,
        connection: selectedConnection,
        cookies: session,
        thumbnailBytes: image,
        options: settings,
        impersonate: impersonate,
        requiresSession: session != null,
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
    DownloadOptions settings,
    bool impersonate,
    String logId,
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
          ...commonFor(settings),
          ...settings.arguments(
            SiteProfile.forUrl(data['webpage_url'] as String? ?? ''),
          ),
          if (impersonate) ...['--impersonate', 'chrome'],
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
      final stderrDone = _captureErrors(process, logId);
      if (_closing) await _killTree(process);
      final code = await process.exitCode.timeout(const Duration(seconds: 30));
      await Future.wait([stdoutDone, stderrDone]);
      if (code != 0) {
        diagnostics.add(logId, 'Thumbnail exit code: $code');
        return null;
      }
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
    } catch (error) {
      diagnostics.add(logId, 'Thumbnail failed: $error');
      if (process != null) await _killTree(process);
    } finally {
      _inspection = null;
      await dir.delete(recursive: true);
    }
    return null;
  }

  Future<String> _captureErrors(Process process, String id) async {
    final tail = StringBuffer();
    await for (final line
        in process.stderr
            .transform(const Utf8Decoder(allowMalformed: true))
            .transform(const LineSplitter())) {
      diagnostics.add(id, line);
      tail.writeln(line);
      if (tail.length > 65536) {
        final last = tail.toString();
        tail.clear();
        tail.write(last.substring(last.length - 32768));
      }
    }
    return tail.toString();
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
    diagnostics.protect([
      ...video.options.headers.values,
      video.options.userAgent,
      video.options.referer,
    ]);
    var current = video.connection.mode == ConnectionMode.automatic
        ? _copyVideo(video, connection: video.connection.attempts.first)
        : video;
    var selectedQuality = quality;
    var impersonationTried = video.impersonate;
    var refreshed = false;
    var connectionIndex = 0;
    final initial = video.connection.mode == ConnectionMode.automatic
        ? video.connection.attempts.first
        : video.connection;
    final connections = <ConnectionOptions>[
      initial,
      if (video.cookies == null && !video.options.hasSessionHeaders)
        ...(video.fallbackConnection ?? video.connection).attempts.where(
          (c) => c.mode != initial.mode || c.proxy != initial.proxy,
        ),
    ];
    _paused.remove(id);
    try {
      for (var attempt = 1; attempt <= 4; attempt++) {
        if (_closing || _paused.contains(id) || _cancelled.contains(id))
          throw EngineException(Failure.extraction);
        diagnostics.add(
          id,
          'Download attempt $attempt: ${SiteProfile.forUrl(video.url).id}, ${current.connection.mode.name}, ${selectedQuality.height}p',
        );
        try {
          progress(
            Progress(
              0,
              '',
              attempt: attempt,
              height: selectedQuality.height,
              selectedQuality: selectedQuality,
            ),
          );
          return await _downloadOnce(
            current,
            selectedQuality,
            container,
            folder,
            id,
            (p) => progress(
              Progress(
                p.fraction,
                p.speed,
                attempt: attempt,
                height: selectedQuality.height,
                selectedQuality: selectedQuality,
              ),
            ),
          );
        } on EngineException catch (e) {
          diagnostics.add(id, 'Attempt failed: ${e.reason.name}');
          if (attempt == 4 ||
              _closing ||
              _cancelled.contains(id) ||
              _paused.contains(id))
            rethrow;
          if ([Failure.network, Failure.proxy].contains(e.reason)) {
            if (connectionIndex + 1 < connections.length) {
              connectionIndex++;
              current = _copyVideo(
                current,
                connection: connections[connectionIndex],
              );
            }
          } else if ([Failure.bot, Failure.forbidden].contains(e.reason) &&
              !impersonationTried &&
              video.cookies == null &&
              !video.options.hasSessionHeaders &&
              video.options.allowImpersonation &&
              SiteProfile.forUrl(video.url).impersonation &&
              await supportsImpersonation()) {
            impersonationTried = true;
            current = _copyVideo(current, impersonate: true);
          } else if ([
                Failure.expired,
                Failure.formatUnavailable,
              ].contains(e.reason) &&
              !refreshed) {
            refreshed = true;
            progress(Progress(0, '', phase: 'retrying', attempt: attempt + 1));
            final newer = await inspectWith(
              video.url,
              current.connection,
              video.options,
              session: video.cookies,
              logId: id,
              impersonate: current.impersonate,
            );
            final same = newer.qualities.where(
              (q) =>
                  q.id == quality.id &&
                  q.audioId == quality.audioId &&
                  q.containers.contains(container),
            );
            if (same.isNotEmpty) {
              selectedQuality = same.first;
            } else {
              if (!video.options.allowFormatFallback ||
                  video.options.format.isNotEmpty)
                rethrow;
              final alternatives = newer.qualities.where(
                (q) =>
                    q.height <= quality.height &&
                    q.containers.contains(container),
              );
              if (alternatives.isEmpty) rethrow;
              selectedQuality = alternatives.first;
              diagnostics.add(
                id,
                'Format fallback selected: ${selectedQuality.height}p',
              );
            }
            current = newer;
          } else {
            rethrow;
          }
          progress(
            Progress(
              0,
              '',
              phase: 'retrying',
              attempt: attempt + 1,
              height: selectedQuality.height,
              selectedQuality: selectedQuality,
            ),
          );
          await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
        }
      }
      throw EngineException(Failure.extraction);
    } on ProcessException {
      throw EngineException(Failure.tools, logId: id);
    } on FileSystemException {
      throw EngineException(Failure.storage, logId: id);
    } on EngineException catch (e) {
      throw EngineException(e.reason, logId: id);
    } finally {
      _running.remove(id);
      final cancelled = _cancelled.remove(id);
      _paused.remove(id);
      if (cancelled) await discardPartial(folder, id);
      await diagnostics.flush(id);
    }
  }

  Video _copyVideo(
    Video video, {
    ConnectionOptions? connection,
    ConnectionOptions? fallbackConnection,
    bool? impersonate,
  }) => Video(
    video.url,
    video.title,
    video.thumbnail,
    video.qualities,
    connection: connection ?? video.connection,
    thumbnailBytes: video.thumbnailBytes,
    cookies: video.cookies,
    options: video.options,
    impersonate: impersonate ?? video.impersonate,
    requiresSession: video.requiresSession,
    fallbackConnection: fallbackConnection ?? video.fallbackConnection,
  );

  void prepareRetry(String id) {
    _paused.remove(id);
    _cancelled.remove(id);
  }

  Future<void> pause(String id) async {
    _paused.add(id);
    final process = _running[id];
    if (process != null) await _killTree(process);
    if (_inspectionId == id && _inspection != null)
      await _killTree(_inspection!);
  }

  Future<void> discardPartial(String folder, String id) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id))
      throw EngineException(Failure.invalid);
    final dir = Directory(p.join(folder, '.local-video-$id'));
    if (await FileSystemEntity.type(dir.path, followLinks: false) ==
        FileSystemEntityType.directory) {
      await dir.delete(recursive: true);
    }
  }

  Future<String> _downloadOnce(
    Video video,
    Quality quality,
    String container,
    String folder,
    String id,
    void Function(Progress) progress,
  ) async {
    validateLink(video.url);
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id))
      throw EngineException(Failure.invalid);
    try {
      video.options.validate();
    } on FormatException {
      throw EngineException(Failure.invalidOptions);
    }
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
    final temp = Directory(p.join(destination.path, '.local-video-$id'));
    if (await FileSystemEntity.type(temp.path, followLinks: false) ==
        FileSystemEntityType.link)
      throw EngineException(Failure.storage);
    await temp.create();
    if (!Platform.isWindows) await Process.run('chmod', ['700', temp.path]);
    final marker = File(p.join(temp.path, 'job.json'));
    final identity = jsonEncode([
      video.url,
      quality.selector,
      container,
      video.options.format,
    ]);
    if (await marker.exists() && await marker.readAsString() != identity) {
      // A fallback can select different streams; never append to incompatible parts.
      await temp.delete(recursive: true);
      await temp.create();
    }
    await marker.writeAsString(identity, flush: true);
    if (!Platform.isWindows) await Process.run('chmod', ['700', temp.path]);
    var succeeded = false;
    String? result;
    CookieLease? cookieLease;
    try {
      cookieLease = await video.cookies?.stage();
      if (_cancelled.contains(id) || _paused.contains(id) || _closing)
        throw EngineException(Failure.extraction);
      final proc = await Process.start(
        exe('yt-dlp'),
        [
          ...commonFor(video.options),
          ...video.options.arguments(SiteProfile.forUrl(video.url)),
          if (video.impersonate) ...['--impersonate', 'chrome'],
          '--continue',
          '--part',
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
          video.options.format.isEmpty
              ? quality.selector
              : video.options.format,
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
      final stderr = _captureErrors(proc, id);
      if (_closing || _cancelled.contains(id) || _paused.contains(id))
        await _killTree(proc);
      await for (final line
          in proc.stdout
              .transform(const Utf8Decoder(allowMalformed: true))
              .transform(const LineSplitter())) {
        diagnostics.add(id, line);
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
      if (_cancelled.contains(id) || _paused.contains(id) || _closing)
        throw EngineException(Failure.extraction);
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
      succeeded = true;
      return finalPath;
    } on CookieException {
      throw EngineException(Failure.invalidCookies);
    } on FileSystemException {
      throw EngineException(Failure.storage);
    } finally {
      _running.remove(id);
      try {
        await cookieLease?.dispose();
      } finally {
        if ((succeeded || _cancelled.contains(id)) && await temp.exists())
          await temp.delete(recursive: true);
      }
    }
  }

  @override
  Future<void> cancel(String id) async {
    _cancelled.add(id);
    final proc = _running[id];
    if (proc != null) await _killTree(proc);
    if (_inspectionId == id && _inspection != null)
      await _killTree(_inspection!);
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
    for (final process in _probes.toList()) {
      await _killTree(process);
    }
    if (_inspection != null) await _killTree(_inspection!);
    for (final id in _running.keys.toList()) {
      await pause(id);
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
