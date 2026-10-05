import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_video/engine.dart';
import 'package:local_video/strings.dart';

void main() {
  test(
    'real yt-dlp inspects fixture and downloads its thumbnail locally',
    () async {
      final tools = Platform.environment['LOCAL_VIDEO_TOOLS'];
      final fixture = Platform.environment['COOKIE_TEST_VIDEO'];
      if (tools == null || fixture == null) return;
      final bytes = await File(fixture).readAsBytes();
      final image = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final origin = 'http://127.0.0.1:${server.port}';
      server.listen((request) async {
        if (request.uri.path == '/video.mp4') {
          request.response.headers.contentType = ContentType('video', 'mp4');
          request.response.contentLength = bytes.length;
          if (request.method != 'HEAD') request.response.add(bytes);
        } else if (request.uri.path == '/preview.png') {
          request.response.headers.contentType = ContentType('image', 'png');
          request.response.add(image);
        } else {
          request.response.headers.contentType = ContentType.html;
          request.response.write(
            '<html><head><title>Local preview fixture</title><meta property="og:title" content="Local preview fixture"><meta property="og:image" content="$origin/preview.png"></head><body><video src="$origin/video.mp4"></video></body></html>',
          );
        }
        await request.response.close();
      });
      final engine = DesktopEngine(toolsDirectory: tools);
      engine.connection = const ConnectionOptions(mode: ConnectionMode.direct);
      try {
        final video = await engine.inspect('$origin/watch');
        expect(video.thumbnailBytes, image);
        expect(video.qualities, isNotEmpty);
      } finally {
        await engine.shutdown();
        await server.close(force: true);
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test('quality sizes include best audio, estimates and unknown totals', () {
    final qualities = parseQualities({
      'duration': 10,
      'formats': [
        {
          'format_id': 'audio',
          'vcodec': 'none',
          'acodec': 'opus',
          'filesize': 100,
        },
        {
          'format_id': 'combined',
          'vcodec': 'h264',
          'acodec': 'aac',
          'height': 360,
          'ext': 'mp4',
          'filesize': 1000,
        },
        {
          'format_id': 'separate',
          'vcodec': 'vp9',
          'acodec': 'none',
          'height': 720,
          'ext': 'webm',
          'filesize': 2000,
        },
        {
          'format_id': 'estimated',
          'vcodec': 'vp9',
          'acodec': 'none',
          'height': 1080,
          'ext': 'webm',
          'tbr': 800,
        },
        {
          'format_id': 'unknown',
          'vcodec': 'h264',
          'acodec': 'aac',
          'height': 240,
          'ext': 'mp4',
        },
      ],
    });
    Quality q(String id) => qualities.firstWhere((q) => q.id == id);
    expect(q('combined').bytes, 1000);
    expect(q('combined').approximate, false);
    expect(q('separate').bytes, 2100);
    expect(q('estimated').bytes, 1000100);
    expect(q('estimated').approximate, true);
    expect(q('unknown').bytes, isNull);
    expect(formatSize({'filesize': -1, 'filesize_approx': 120}, null), (
      bytes: 120,
      approximate: true,
    ));
    final noAudioSize = parseQualities({
      'formats': [
        {
          'format_id': 'v',
          'vcodec': 'h264',
          'acodec': 'none',
          'ext': 'mp4',
          'filesize': 1000,
        },
      ],
    });
    expect(noAudioSize.single.bytes, isNull);
  });
  test(
    'connection mode uses safe argument lists and preserves empty proxy',
    () {
      expect(const ConnectionOptions().arguments(), isEmpty);
      expect(const ConnectionOptions().attempts.map((a) => a.mode), [
        ConnectionMode.system,
        ConnectionMode.direct,
      ]);
      expect(
        const ConnectionOptions(
          mode: ConnectionMode.custom,
          proxy: 'http://127.0.0.1:1080',
        ).attempts.length,
        1,
      );
      expect(const ConnectionOptions(mode: ConnectionMode.direct).arguments(), [
        '--proxy',
        '',
      ]);
      expect(
        const ConnectionOptions(
          mode: ConnectionMode.custom,
          proxy: 'socks5://127.0.0.1:1080',
        ).arguments(),
        ['--proxy', 'socks5://127.0.0.1:1080'],
      );
      for (final proxy in [
        '--exec=bad',
        'file:///secret',
        'http://user:pass@localhost:8080',
        'http://localhost:8080/?secret=1',
      ]) {
        expect(
          () => ConnectionOptions(
            mode: ConnectionMode.custom,
            proxy: proxy,
          ).arguments(),
          throwsA(isA<EngineException>()),
        );
      }
    },
  );
  test('proxy, anti-bot and restricted failures have distinct messages', () {
    expect(classify('Unable to connect to proxy'), Failure.proxy);
    expect(classify("Sign in to confirm you’re not a bot"), Failure.bot);
    expect(classify('This video is unavailable'), Failure.restricted);
    expect(classify('Connection reset by peer'), Failure.network);
  });
  test('reject malformed and non-http URLs', () {
    for (final url in [
      '-o file',
      'file:///secret',
      'https://',
      'https://user:pass@site.test',
      'https://site.test\n--exec=bad',
    ]) {
      expect(() => validateLink(url), throwsA(isA<EngineException>()));
    }
    validateLink('https://example.com/watch?a=1&b=2');
  });
  test('safe portable filenames', () {
    expect(safeName('../CON:%bad|name'), '.._CON__bad_name');
    expect(safeName('NUL'), '_NUL');
    expect(safeName('CON.txt'), '_CON.txt');
    expect(safeName('video... '), 'video');
    expect(safeName('عنوان فیلم'), 'عنوان فیلم');
  });
  test('all user messages translated', () {
    for (final row in words.values) {
      expect(row.length, 4);
      expect(row.every((s) => s.isNotEmpty), true);
    }
  });
  test('missing packaged tools are reported', () async {
    final engine = DesktopEngine(toolsDirectory: 'missing-tools');
    await expectLater(
      engine.inspect('https://example.com/video'),
      throwsA(
        isA<EngineException>().having((e) => e.reason, 'reason', Failure.tools),
      ),
    );
  });
  test(
    'real inspect, download and FFmpeg remux',
    () async {
      final dir = await Directory.systemTemp.createTemp('local-video-test-');
      final engine = DesktopEngine(
        toolsDirectory: Platform.environment['LOCAL_VIDEO_TOOLS'],
      );
      if (Platform.environment['TEST_CONNECTION'] == 'direct') {
        engine.connection = const ConnectionOptions(
          mode: ConnectionMode.direct,
        );
      }
      try {
        final v = await engine.inspect(Platform.environment['TEST_VIDEO_URL']!);
        final output = await engine.download(
          v,
          v.qualities.last,
          'mkv',
          dir.path,
          'test',
          (p) {},
        );
        expect(await File(output).length(), greaterThan(1000));
        expect(dir.listSync().whereType<Directory>(), isEmpty);
        final probe = await Process.run(engine.exe('ffprobe'), [
          '-v',
          'error',
          '-show_entries',
          'stream=codec_type',
          '-of',
          'json',
          output,
        ]);
        expect(probe.exitCode, 0);
        expect(probe.stdout.toString(), contains('video'));
        final download = engine.download(
          v,
          v.qualities.last,
          'mkv',
          dir.path,
          'cancel',
          (p) {},
        );
        final cancelled = expectLater(
          download,
          throwsA(isA<EngineException>()),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await engine.cancel('cancel');
        await cancelled;
        expect(dir.listSync().whereType<Directory>(), isEmpty);
      } finally {
        await dir.delete(recursive: true);
      }
    },
    skip: Platform.environment['TEST_VIDEO_URL'] == null,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
