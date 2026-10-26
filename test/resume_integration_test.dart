import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_video/engine.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'bundled yt-dlp resumes partial bytes with HTTP Range after pause',
    () async {
      final tools = Platform.environment['LOCAL_VIDEO_TOOLS']!;
      final source = await File(
        Platform.environment['COOKIE_TEST_VIDEO']!,
      ).readAsBytes();
      // Trailing padding keeps this tiny valid MP4 slow enough to pause reliably.
      final bytes = [...source, ...List<int>.filled(4 * 1024 * 1024, 0)];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final ranges = <int>[];
      server.listen((request) async {
        try {
          final range = request.headers.value(HttpHeaders.rangeHeader);
          final start = range == null
              ? 0
              : int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)![1]!);
          ranges.add(start);
          if (start >= bytes.length) {
            request.response.statusCode =
                HttpStatus.requestedRangeNotSatisfiable;
            await request.response.close();
            return;
          }
          request.response.headers.contentType = ContentType('video', 'mp4');
          request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
          request.response.contentLength = bytes.length - start;
          if (range != null) {
            request.response.statusCode = HttpStatus.partialContent;
            request.response.headers.set(
              HttpHeaders.contentRangeHeader,
              'bytes $start-${bytes.length - 1}/${bytes.length}',
            );
          }
          if (request.method != 'HEAD') {
            for (var offset = start; offset < bytes.length; offset += 8192) {
              request.response.add(
                bytes.sublist(offset, (offset + 8192).clamp(0, bytes.length)),
              );
              await request.response.flush();
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
          }
          await request.response.close();
        } catch (_) {
          /* The inspection/pause deliberately closes the connection. */
        }
      });
      final directory = await Directory.systemTemp.createTemp(
        'vidora-real-resume-',
      );
      final engine = DesktopEngine(toolsDirectory: tools)
        ..connection = const ConnectionOptions(mode: ConnectionMode.direct);
      try {
        final video = await engine.inspect(
          'http://127.0.0.1:${server.port}/video.mp4',
        );
        Future<void>? paused;
        final first = engine.download(
          video,
          video.qualities.first,
          'mp4',
          directory.path,
          'resume',
          (progress) {
            if (progress.fraction > 0.4 &&
                progress.fraction < 0.9 &&
                paused == null)
              paused = engine.pause('resume');
          },
        );
        await expectLater(first, throwsA(isA<EngineException>()));
        expect(paused, isNotNull);
        await paused;
        final parts = Directory(p.join(directory.path, '.local-video-resume'))
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.part'))
            .toList();
        expect(parts, hasLength(1));
        expect(await parts.single.length(), greaterThan(0));
        final output = await engine.download(
          video,
          video.qualities.first,
          'mp4',
          directory.path,
          'resume',
          (_) {},
        );
        expect(ranges.where((start) => start > 0), isNotEmpty);
        final probe = await Process.run(engine.exe('ffprobe'), [
          '-v',
          'error',
          '-show_entries',
          'stream=codec_type',
          '-of',
          'json',
          output,
        ]);
        expect(probe.exitCode, 0, reason: '${probe.stderr}');
        final streams =
            (jsonDecode('${probe.stdout}') as Map)['streams'] as List;
        expect(
          streams.map((s) => s['codec_type']),
          containsAll(['video', 'audio']),
        );
        expect(directory.listSync().whereType<Directory>(), isEmpty);
      } finally {
        await engine.shutdown();
        await server.close(force: true);
        await directory.delete(recursive: true);
      }
    },
    skip:
        Platform.environment['LOCAL_VIDEO_TOOLS'] == null ||
        Platform.environment['COOKIE_TEST_VIDEO'] == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
