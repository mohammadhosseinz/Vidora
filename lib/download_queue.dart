import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'engine.dart';
import 'site_profiles.dart';

class Job {
  static final _random = Random.secure();
  final String id, folder, format;
  Video video;
  Quality quality;
  String state = 'waiting', speed = '';
  Failure? error;
  double progress = 0;
  int attempt = 1;
  int? actualHeight;
  bool cancelled = false, paused = false, restored = false;
  Job(this.video, this.quality, this.format, this.folder, {String? id})
    : id =
          id ??
          '${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 32).toRadixString(16)}${_random.nextInt(1 << 32).toRadixString(16)}';

  Map<String, Object?> toJson() => {
    'id': id, 'url': video.url, 'title': video.title, 'folder': folder,
    'format': format,
    'state': state,
    'progress': progress,
    'height': actualHeight,
    'error': error?.name,
    'requiresSession': video.requiresSession || video.cookies != null,
    // Never serialize cookies or headers. Restored jobs explicitly re-inspect.
    'connection': (video.fallbackConnection ?? video.connection).mode.name,
    'proxy': (video.fallbackConnection ?? video.connection).proxy,
    'options': {
      'format': video.options.format,
      'extractor': video.options.extractor.name,
      'impersonation': video.options.allowImpersonation,
      'fallback': video.options.allowFormatFallback,
    },
    'quality': {
      'id': quality.id,
      'ext': quality.ext,
      'height': quality.height,
      'audio': quality.audio,
      'audioId': quality.audioId,
      'videoCodec': quality.videoCodec,
      'audioCodec': quality.audioCodec,
    },
  };

  static Job fromJson(Map<String, dynamic> data) {
    final url = data['url'] as String;
    validateLink(url);
    final id = data['id'] as String;
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id) ||
        !['mp4', 'mkv', 'webm'].contains(data['format'])) {
      throw const FormatException('Invalid job');
    }
    final q = data['quality'] as Map;
    final quality = Quality(
      q['id'] as String,
      q['ext'] as String,
      q['height'] as int,
      q['audio'] as bool,
      audioId: q['audioId'] as String?,
      videoCodec: q['videoCodec'] as String?,
      audioCodec: q['audioCodec'] as String?,
    );
    final options = data['options'] as Map? ?? {};
    final job = Job(
      Video(
        url,
        data['title'] as String,
        null,
        [quality],
        requiresSession: data['requiresSession'] == true,
        connection: ConnectionOptions(
          mode: ConnectionMode.values.byName(data['connection'] as String),
          proxy: data['proxy'] as String? ?? '',
        ),
        options: DownloadOptions(
          format: options['format'] as String? ?? '',
          extractor: ExtractorMode.values.byName(
            options['extractor'] as String? ?? 'automatic',
          ),
          allowImpersonation: options['impersonation'] != false,
          allowFormatFallback: options['fallback'] == true,
        ),
      ),
      quality,
      data['format'] as String,
      data['folder'] as String,
      id: id,
    );
    final state = data['state'] as String;
    job.state = ['done', 'cancelled', 'failed'].contains(state)
        ? state
        : 'paused';
    job.paused = job.state == 'paused';
    job.restored = true;
    job.progress = ((data['progress'] as num?)?.toDouble() ?? 0).clamp(0, 1);
    job.actualHeight = data['height'] as int?;
    job.error = Failure.values
        .where((e) => e.name == data['error'])
        .firstOrNull;
    return job;
  }
}

class QueueStore {
  final File file;
  Future<void> _pending = Future.value();
  QueueStore(this.file);

  Future<List<Job>> load() async =>
      await _loadFile(file) ?? await _loadFile(File('${file.path}.bak')) ?? [];

  Future<List<Job>?> _loadFile(File source) async {
    try {
      if (await source.length() > 8 * 1024 * 1024) return null;
      final data = jsonDecode(await source.readAsString()) as Map;
      if (data['version'] != 1) return null;
      final jobs = <Job>[];
      final ids = <String>{};
      for (final row in (data['jobs'] as List).take(1000)) {
        try {
          final job = Job.fromJson(Map<String, dynamic>.from(row as Map));
          if (ids.add(job.id)) jobs.add(job);
        } catch (_) {
          /* One malformed entry must not hide the other jobs. */
        }
      }
      return jobs;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> save(List<Job> jobs) {
    final contents = jsonEncode({
      'version': 1,
      'jobs': jobs.map((j) => j.toJson()).toList(),
    });
    final next = _pending.catchError((Object _) {}).then((_) async {
      await file.parent.create(recursive: true);
      if (!Platform.isWindows)
        await Process.run('chmod', ['700', file.parent.path]);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(contents, flush: true);
      if (!Platform.isWindows)
        await Process.run('chmod', ['600', temporary.path]);
      if (await _loadFile(file) != null) {
        final backup = await file.copy('${file.path}.bak.tmp');
        if (!Platform.isWindows)
          await Process.run('chmod', ['600', backup.path]);
        await backup.rename('${file.path}.bak');
      }
      await temporary.rename(file.path);
    });
    _pending = next;
    return next;
  }
}
