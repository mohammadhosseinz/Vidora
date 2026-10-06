import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_video/engine.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'real local silent download, DASH merge and compatible WebM',
    () async {
      final tools = Platform.environment['LOCAL_VIDEO_TOOLS']!;
      final source = Platform.environment['COOKIE_TEST_VIDEO']!;
      final dir = await Directory.systemTemp.createTemp(
        'vidora-local-download-',
      );
      final engine = DesktopEngine(toolsDirectory: tools);
      engine.connection = const ConnectionOptions(mode: ConnectionMode.direct);
      HttpServer? server;
      try {
        Future<void> ffmpeg(List<String> args) async {
          // Fixture encoding may use a developer FFmpeg with VP9/Opus encoders;
          // downloads and remuxing still use the packaged tools in the engine.
          final result = await Process.run(
            Platform.environment['FIXTURE_FFMPEG'] ?? engine.exe('ffmpeg'),
            ['-v', 'error', ...args],
            workingDirectory: dir.path,
          );
          expect(result.exitCode, 0, reason: result.stderr.toString());
        }

        await ffmpeg([
          '-i',
          source,
          '-an',
          '-c:v',
          'copy',
          p.join(dir.path, 'silent.mp4'),
        ]);
        await ffmpeg([
          '-i',
          source,
          '-c',
          'copy',
          '-f',
          'dash',
          p.join(dir.path, 'manifest.mpd'),
        ]);
        await ffmpeg([
          '-i',
          source,
          '-c:v',
          'libvpx-vp9',
          '-c:a',
          'libopus',
          p.join(dir.path, 'compatible.webm'),
        ]);
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final origin = 'http://127.0.0.1:${server.port}';
        server.listen((request) async {
          final file = File(p.join(dir.path, p.basename(request.uri.path)));
          if (await file.exists()) {
            request.response.contentLength = await file.length();
            request.response.headers.contentType =
                request.uri.path.endsWith('.mpd')
                ? ContentType('application', 'dash+xml')
                : request.uri.path.endsWith('.webm')
                ? ContentType('video', 'webm')
                : ContentType('video', 'mp4');
            if (request.method != 'HEAD')
              await request.response.addStream(file.openRead());
          } else {
            request.response.statusCode = HttpStatus.notFound;
          }
          await request.response.close();
        });
        Future<List<String>> streamTypes(String file) async {
          final result = await Process.run(engine.exe('ffprobe'), [
            '-v',
            'error',
            '-show_entries',
            'stream=codec_type',
            '-of',
            'json',
            file,
          ]);
          expect(result.exitCode, 0, reason: result.stderr.toString());
          final streams =
              (jsonDecode(result.stdout as String) as Map)['streams'] as List;
          return streams
              .map((stream) => stream['codec_type'] as String)
              .toList();
        }

        final silent = await engine.inspect('$origin/silent.mp4');
        // The generic extractor leaves codecs unknown. Supply known fixture
        // metadata to cover extractors that explicitly report acodec=none.
        final silentQuality = Quality(
          silent.qualities.first.id,
          'mp4',
          64,
          false,
          videoCodec: 'h264',
          audioCodec: 'none',
        );
        final silentOutput = await engine.download(
          silent,
          silentQuality,
          'mp4',
          dir.path,
          'silent',
          (_) {},
        );
        expect(await streamTypes(silentOutput), ['video']);
        await expectLater(
          engine.download(
            silent,
            silentQuality,
            'webm',
            dir.path,
            'invalid-webm',
            (_) {},
          ),
          throwsA(
            isA<EngineException>().having(
              (e) => e.reason,
              'reason',
              Failure.incompatibleFormat,
            ),
          ),
        );

        final dash = await engine.inspect('$origin/manifest.mpd');
        expect(dash.qualities.first.needsMerge, true);
        final merged = await engine.download(
          dash,
          dash.qualities.first,
          'mkv',
          dir.path,
          'merged',
          (_) {},
        );
        expect(await streamTypes(merged), containsAll(['video', 'audio']));

        final webm = await engine.inspect('$origin/compatible.webm');
        final webmQuality = webm.qualities.first;
        expect(webmQuality.containers, contains('webm'));
        final webmOutput = await engine.download(
          webm,
          webmQuality,
          'webm',
          dir.path,
          'webm',
          (_) {},
        );
        expect(await streamTypes(webmOutput), containsAll(['video', 'audio']));
        expect(dir.listSync().whereType<Directory>(), isEmpty);
      } finally {
        await engine.shutdown();
        await server?.close(force: true);
        await dir.delete(recursive: true);
      }
    },
    skip:
        Platform.environment['LOCAL_VIDEO_TOOLS'] == null ||
        Platform.environment['COOKIE_TEST_VIDEO'] == null,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
