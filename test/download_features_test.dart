import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_video/cookies.dart';
import 'package:local_video/diagnostics.dart';
import 'package:local_video/download_queue.dart';
import 'package:local_video/engine.dart';
import 'package:local_video/engine_health.dart';
import 'package:local_video/site_profiles.dart';
import 'package:path/path.dart' as p;
import 'download_regression_test.dart' show fakeTools, waitForPids;

final sampleQuality = Quality('video', 'mp4', 720, true);
Video sampleVideo({DownloadOptions? options, ConnectionOptions? connection}) =>
    Video(
      'https://www.instagram.com/reel/fixture',
      'fixture',
      null,
      [sampleQuality],
      options: options,
      connection:
          connection ?? const ConnectionOptions(mode: ConnectionMode.direct),
    );

void main() {
  test(
    'classify specific causes before broad network wording and uncertain 403',
    () {
      final cases = {
        'Unable to download: DRM protected': Failure.drm,
        'Unable to download: not available in your country': Failure.geoBlocked,
        'URL has expired': Failure.expired,
        'Please sign in to continue': Failure.loginRequired,
        'Use --cookies for authentication': Failure.cookiesRequired,
        "Sign in to confirm you're not a bot": Failure.bot,
        'Unsupported URL: fixture': Failure.unsupported,
        'Requested format is not available': Failure.formatUnavailable,
        'HTTP Error 429: Too many requests': Failure.rateLimited,
        'HTTP Error 403: Forbidden': Failure.forbidden,
      };
      for (final entry in cases.entries) {
        expect(classify(entry.key), entry.value);
      }
    },
  );

  test(
    'profile matching checks domain boundaries and preserves upstream defaults',
    () {
      expect(
        SiteProfile.forUrl('https://m.youtube.com/watch?v=x').id,
        'youtube',
      );
      expect(SiteProfile.forUrl('https://youtu.be/x').id, 'youtube');
      expect(SiteProfile.forUrl('https://notyoutube.com/x').id, 'generic');
      expect(
        SiteProfile.forUrl('https://youtube.com.evil.test/x').id,
        'generic',
      );
      expect(SiteProfile.all.length, 7);
      final options = DownloadOptions(
        headers: {'X-Test': 'one:two'},
        userAgent: 'fixture UA',
      );
      expect(options.arguments(SiteProfile.forUrl('https://aparat.com/v/x')), [
        '--user-agent',
        'fixture UA',
        '--referer',
        'https://www.aparat.com/',
        '--add-headers',
        'X-Test:one:two',
      ]);
      expect(
        () => DownloadOptions(
          headers: {'X-Test': 'value\r\nCookie: x'},
        ).validate(),
        throwsFormatException,
      );
      expect(
        () => DownloadOptions(headers: {'bad key': 'value'}).validate(),
        throwsFormatException,
      );
      expect(
        () => DownloadOptions.parseHeaders('not a header'),
        throwsFormatException,
      );
      final headers = {'X-Test': 'original'};
      final snapshot = DownloadOptions(headers: headers);
      headers['X-Test'] = 'changed';
      expect(snapshot.headers['X-Test'], 'original');
    },
  );

  test(
    'diagnostics redact before persistence and survive a new app session',
    () async {
      final dir = await Directory.systemTemp.createTemp('vidora-logs-');
      try {
        final log = Diagnostics(directory: dir)..protect(['secret-session']);
        log.add(
          'job',
          '[debug] request https://host.test/file?signature=private',
        );
        log.add('job', 'Authorization: Bearer private');
        log.add(
          'job',
          '[debug] Command-line config: --cookies /private/auth/cookies.txt',
        );
        log.add('job', 'Value: secret-session');
        log.add('job', 'ERROR: HTTP Error 403: Forbidden');
        await log.flush('job');
        final text = await Diagnostics(directory: dir).read('job');
        for (final value in [
          'signature=',
          'Bearer',
          'secret-session',
          '/private/auth',
        ]) {
          expect(text, isNot(contains(value)));
        }
        expect(text, contains('HTTP Error 403'));
        log.add('huge', 'a' * (Diagnostics.maxCharacters + 500));
        expect(
          log.text('huge').length,
          lessThan(Diagnostics.maxCharacters + 100),
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'queue survives restart, isolates malformed entries and never stores auth',
    () async {
      final dir = await Directory.systemTemp.createTemp('vidora-queue-');
      try {
        final session = CookieSession.parse(
          '# Netscape HTTP Cookie File\n.instagram.com\tTRUE\t/\tTRUE\t0\tsession\tprivate-cookie\n',
          'https://instagram.com/',
        );
        final video = Video(
          'https://instagram.com/reel/fixture',
          'title',
          null,
          [sampleQuality],
          cookies: session,
          options: DownloadOptions(
            headers: {'Authorization': 'private-header'},
            userAgent: 'private-UA',
          ),
        );
        final active = Job(video, sampleQuality, 'mp4', dir.path, id: 'active')
          ..state = 'running';
        final done = Job(video, sampleQuality, 'mp4', dir.path, id: 'done')
          ..state = 'done';
        final store = QueueStore(File(p.join(dir.path, 'queue.json')));
        await Future.wait([
          store.save([active]),
          store.save([active, done]),
        ]);
        final contents = await store.file.readAsString();
        expect(contents, isNot(contains('private-cookie')));
        expect(contents, isNot(contains('private-header')));
        expect(contents, isNot(contains('private-UA')));
        final restored = await QueueStore(store.file).load();
        expect(restored.map((j) => j.state), ['paused', 'done']);
        expect(restored.first.video.requiresSession, true);
        expect(restored.first.video.cookies, isNull);
        final data = jsonDecode(contents) as Map;
        (data['jobs'] as List).insert(0, {'bad': true});
        (data['jobs'] as List).add(active.toJson());
        await store.file.writeAsString(jsonEncode(data));
        expect((await store.load()).map((j) => j.id), ['active', 'done']);
        await store.file.writeAsString('{truncated');
        expect((await store.load()).map((j) => j.id), ['active']);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test('engine age warning works offline and compares release dates', () {
    expect(
      const EngineHealth('2026.01.01').outdatedAt(DateTime(2026, 10, 25)),
      true,
    );
    expect(
      const EngineHealth('2026.10.01').outdatedAt(DateTime(2026, 10, 25)),
      false,
    );
    expect(
      const EngineHealth(
        '2026.10.01',
        latest: '2026.10.20',
      ).outdatedAt(DateTime(2026, 10, 25)),
      true,
    );
  });

  test(
    'network fallback preserves partial bytes and retains job identity',
    () async {
      final tools = await fakeTools(r'''#!/bin/sh
base=$(dirname "$0")
proxy=system
while [ "$#" -gt 0 ]; do
  case "$1" in
    --proxy) shift; proxy="$1" ;;
    -o) shift; output="$1" ;;
  esac
  shift
done
output="${output%.*}.mp4"
printf '%s\n' "$proxy" >> "$base/attempts"
if [ "$proxy" = system ]; then
  printf 'first-' > "$output.part"
  printf 'ERROR: Connection reset by peer\n' >&2
  exit 1
fi
if [ ! -f "$output.part" ]; then exit 3; fi
cat "$output.part" > "$output"
printf 'second' >> "$output"
printf 'FILE:%s\n' "$output"
''');
      final dir = await Directory.systemTemp.createTemp('vidora-resume-');
      final engine = DesktopEngine(toolsDirectory: tools.path);
      try {
        final phases = <String>[];
        final output = await engine.download(
          sampleVideo(connection: const ConnectionOptions()),
          sampleQuality,
          'mp4',
          dir.path,
          'same-id',
          (p) => phases.add(p.phase),
        );
        expect(await File(output).readAsString(), 'first-second');
        expect(await File(p.join(tools.path, 'attempts')).readAsLines(), [
          'system',
          '',
        ]);
        expect(phases, contains('retrying'));
        expect(dir.listSync().whereType<Directory>(), isEmpty);
      } finally {
        await engine.shutdown();
        await dir.delete(recursive: true);
        await tools.delete(recursive: true);
      }
    },
    skip: Platform.isWindows,
  );

  test(
    'non-retryable failures retain parts; next process resumes with same id',
    () async {
      final tools = await fakeTools(r'''#!/bin/sh
base=$(dirname "$0")
while [ "$#" -gt 0 ]; do
  case "$1" in -o) shift; output="$1" ;; esac
  shift
done
output="${output%.*}.mp4"
if [ ! -f "$base/retry" ]; then
  printf 'partial-' > "$output.part"
  printf 'ERROR: Login required\n' >&2
  exit 1
fi
cat "$output.part" > "$output"
printf 'resumed' >> "$output"
printf 'FILE:%s\n' "$output"
''');
      final dir = await Directory.systemTemp.createTemp('vidora-restart-');
      final first = DesktopEngine(toolsDirectory: tools.path);
      final second = DesktopEngine(toolsDirectory: tools.path);
      try {
        await expectLater(
          first.download(
            sampleVideo(),
            sampleQuality,
            'mp4',
            dir.path,
            'persisted',
            (_) {},
          ),
          throwsA(
            isA<EngineException>().having(
              (e) => e.reason,
              'cause',
              Failure.loginRequired,
            ),
          ),
        );
        expect(dir.listSync().whereType<Directory>(), hasLength(1));
        await first.shutdown();
        await File(p.join(tools.path, 'retry')).writeAsString('yes');
        final output = await second.download(
          sampleVideo(),
          sampleQuality,
          'mp4',
          dir.path,
          'persisted',
          (_) {},
        );
        expect(await File(output).readAsString(), 'partial-resumed');
      } finally {
        await second.shutdown();
        await dir.delete(recursive: true);
        await tools.delete(recursive: true);
      }
    },
    skip: Platform.isWindows,
  );

  test(
    'pause stops a download and keeps its partial output for resume',
    () async {
      final tools = await fakeTools(r'''#!/bin/sh
base=$(dirname "$0")
while [ "$#" -gt 0 ]; do
  case "$1" in -o) shift; output="$1" ;; esac
  shift
done
output="${output%.*}.mp4"
if [ ! -f "$base/resume" ]; then
  printf 'paused-' > "$output.part"
  printf '%s\n' "$$" > "$base/ready.pids"
  sleep 60
else
  cat "$output.part" > "$output"
  printf 'resumed' >> "$output"
  printf 'FILE:%s\n' "$output"
fi
''');
      final dir = await Directory.systemTemp.createTemp('vidora-pause-');
      final engine = DesktopEngine(toolsDirectory: tools.path);
      try {
        final download = engine.download(
          sampleVideo(),
          sampleQuality,
          'mp4',
          dir.path,
          'pause',
          (_) {},
        );
        final completion = expectLater(
          download,
          throwsA(isA<EngineException>()),
        );
        await waitForPids(File(p.join(tools.path, 'ready.pids')));
        await engine.pause('pause');
        await completion;
        expect(dir.listSync().whereType<Directory>(), hasLength(1));
        await File(p.join(tools.path, 'resume')).writeAsString('yes');
        final output = await engine.download(
          sampleVideo(),
          sampleQuality,
          'mp4',
          dir.path,
          'pause',
          (_) {},
        );
        expect(await File(output).readAsString(), 'paused-resumed');
      } finally {
        await engine.shutdown();
        await dir.delete(recursive: true);
        await tools.delete(recursive: true);
      }
    },
    skip: Platform.isWindows,
  );

  test(
    'anti-bot retries impersonation only when supported and requested',
    () async {
      final tools = await fakeTools(r'''#!/bin/sh
base=$(dirname "$0")
impersonate=no
while [ "$#" -gt 0 ]; do
  case "$1" in
    --list-impersonate-targets) printf 'Chrome-133 Macos-15 curl_cffi\n'; exit 0 ;;
    --impersonate) impersonate=yes; shift ;;
    -o) shift; output="$1" ;;
  esac
  shift
done
printf '%s\n' "$impersonate" >> "$base/attempts"
if [ "$impersonate" = no ]; then
  printf 'ERROR: Confirm you are not a bot\n' >&2; exit 1
fi
output="${output%.*}.mp4"
printf 'fixture' > "$output"
printf 'FILE:%s\n' "$output"
''');
      final dir = await Directory.systemTemp.createTemp(
        'vidora-impersonation-',
      );
      final engine = DesktopEngine(toolsDirectory: tools.path);
      try {
        await engine.download(
          sampleVideo(),
          sampleQuality,
          'mp4',
          dir.path,
          'allowed',
          (_) {},
        );
        expect(await File(p.join(tools.path, 'attempts')).readAsLines(), [
          'no',
          'yes',
        ]);
        await expectLater(
          engine.download(
            sampleVideo(options: DownloadOptions(allowImpersonation: false)),
            sampleQuality,
            'mp4',
            dir.path,
            'disabled',
            (_) {},
          ),
          throwsA(isA<EngineException>()),
        );
        expect(await File(p.join(tools.path, 'attempts')).readAsLines(), [
          'no',
          'yes',
          'no',
        ]);
      } finally {
        await engine.shutdown();
        await dir.delete(recursive: true);
        await tools.delete(recursive: true);
      }
    },
    skip: Platform.isWindows,
  );
  test(
    'format fallback re-inspects and never lowers quality without opt-in',
    () async {
      final tools = await fakeTools(r'''#!/bin/sh
base=$(dirname "$0")
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dump-single-json)
      printf '%s\n' '{"title":"fixture","formats":[{"format_id":"lower","height":360,"ext":"mp4","vcodec":"h264","acodec":"aac"}]}'
      exit 0 ;;
    -f) shift; selector="$1" ;;
    -o) shift; output="$1" ;;
  esac
  shift
done
printf '%s\n' "$selector" >> "$base/selectors"
if [ "$selector" != lower ]; then
  printf 'ERROR: Requested format is not available\n' >&2; exit 1
fi
output="${output%.*}.mp4"
printf 'lower quality' > "$output"
printf 'FILE:%s\n' "$output"
''');
      final dir = await Directory.systemTemp.createTemp(
        'vidora-format-fallback-',
      );
      final engine = DesktopEngine(toolsDirectory: tools.path);
      try {
        await expectLater(
          engine.download(
            sampleVideo(),
            sampleQuality,
            'mp4',
            dir.path,
            'strict',
            (_) {},
          ),
          throwsA(
            isA<EngineException>().having(
              (e) => e.reason,
              'cause',
              Failure.formatUnavailable,
            ),
          ),
        );
        final heights = <int?>[];
        await engine.download(
          sampleVideo(options: DownloadOptions(allowFormatFallback: true)),
          sampleQuality,
          'mp4',
          dir.path,
          'fallback',
          (p) => heights.add(p.height),
        );
        expect(heights.last, 360);
        expect(await File(p.join(tools.path, 'selectors')).readAsLines(), [
          'video',
          'video',
          'lower',
        ]);
      } finally {
        await engine.shutdown();
        await dir.delete(recursive: true);
        await tools.delete(recursive: true);
      }
    },
    skip: Platform.isWindows,
  );

  test(
    'DRM stops immediately and cannot trigger network or format retries',
    () async {
      final tools = await fakeTools(r'''#!/bin/sh
base=$(dirname "$0")
printf 'attempt\n' >> "$base/attempts"
printf 'ERROR: Unable to download: DRM protected\n' >&2
exit 1
''');
      final dir = await Directory.systemTemp.createTemp('vidora-drm-');
      final engine = DesktopEngine(toolsDirectory: tools.path);
      try {
        await expectLater(
          engine.download(
            sampleVideo(options: DownloadOptions(allowFormatFallback: true)),
            sampleQuality,
            'mp4',
            dir.path,
            'drm',
            (_) {},
          ),
          throwsA(
            isA<EngineException>().having(
              (e) => e.reason,
              'cause',
              Failure.drm,
            ),
          ),
        );
        expect(await File(p.join(tools.path, 'attempts')).readAsLines(), [
          'attempt',
        ]);
      } finally {
        await engine.shutdown();
        await dir.delete(recursive: true);
        await tools.delete(recursive: true);
      }
    },
    skip: Platform.isWindows,
  );
}
