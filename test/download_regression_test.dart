import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_video/engine.dart';
import 'package:path/path.dart' as p;

List<Quality> fixtureQualities({bool withAudio = true}) => parseQualities({
  'formats': [
    if (withAudio)
      {
        'format_id': 'audio',
        'vcodec': 'none',
        'acodec': 'opus',
        'filesize': 100,
      },
    {
      'format_id': 'h264',
      'vcodec': 'avc1.64001f',
      'acodec': 'aac',
      'height': 720,
      'ext': 'mp4',
      'filesize': 1024,
    },
    {
      'format_id': 'vp9',
      'vcodec': 'vp09.00.40.08',
      'acodec': 'none',
      'height': 1080,
      'ext': 'webm',
      'filesize': 2048,
    },
  ],
});

Future<Directory> fakeTools(String script) async {
  final dir = await Directory.systemTemp.createTemp('vidora-tools-test-');
  for (final name in ['yt-dlp', 'ffmpeg', 'ffprobe', 'deno']) {
    final file = File(p.join(dir.path, name));
    await file.writeAsString(name == 'yt-dlp' ? script : '#!/bin/sh\nexit 0\n');
    final chmod = await Process.run('chmod', ['700', file.path]);
    expect(chmod.exitCode, 0);
  }
  return dir;
}

Future<List<int>> waitForPids(File file) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    if (await file.exists()) {
      final contents = (await file.readAsString()).trim();
      if (contents.isNotEmpty)
        return contents.split(RegExp(r'\s+')).map(int.parse).toList();
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw TimeoutException('Process fixture did not start');
}

void main() {
  test('silent video keeps its own format and exact size', () {
    final silent = fixtureQualities(withAudio: false).first;
    expect(silent.audio, false);
    expect(silent.needsMerge, false);
    expect(silent.selector, 'vp9');
    expect(silent.bytes, 2048);
    expect(silent.approximate, false);
    expect(silent.containers, contains('webm'));
  });

  test('separate audio selection agrees with size and codec metadata', () {
    final split = fixtureQualities().first;
    expect(split.selector, 'vp9+audio');
    expect(split.needsMerge, true);
    expect(split.audioCodec, 'opus');
    expect(split.bytes, 2148);
    expect(split.containers, contains('webm'));
  });

  test('WebM excludes incompatible and unknown video or audio codecs', () {
    expect(
      Quality('native-webm', 'webm', 720, true).containers,
      contains('webm'),
    );
    expect(fixtureQualities().last.containers, isNot(contains('webm')));
    expect(
      Quality('unknown', 'mp4', 720, true).containers,
      isNot(contains('webm')),
    );
    expect(
      Quality(
        'vp9',
        'webm',
        720,
        true,
        videoCodec: 'vp9',
        audioCodec: 'aac',
      ).containers,
      isNot(contains('webm')),
    );
    expect(
      Quality(
        'vp9',
        'webm',
        720,
        true,
        videoCodec: 'vp9',
        audioCodec: 'opus',
      ).containers,
      contains('webm'),
    );
  });

  test('incompatible WebM is rejected before starting any process', () async {
    final engine = DesktopEngine(toolsDirectory: 'missing-tools');
    final q = fixtureQualities().last;
    await expectLater(
      engine.download(
        Video('https://example.test/video', 'video', null, [q]),
        q,
        'webm',
        '.',
        'incompatible',
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
  });

  test(
    'download uses the selected stream and preserves silent videos',
    () async {
      final tools = await fakeTools(r'''#!/bin/sh
tools=$(dirname "$0")
while [ "$#" -gt 0 ]; do
  case "$1" in
    -f) shift; printf '%s' "$1" > "$tools/selector" ;;
    -o) shift; output="$1" ;;
  esac
  shift
done
output="${output%.*}.mkv"
printf 'fixture' > "$output"
printf 'FILE:%s\n' "$output"
''');
      final destination = await Directory.systemTemp.createTemp(
        'vidora-output-test-',
      );
      final engine = DesktopEngine(toolsDirectory: tools.path);
      try {
        for (final withAudio in [false, true]) {
          final q = fixtureQualities(withAudio: withAudio).first;
          final output = await engine.download(
            Video('https://example.test/video', 'video', null, [q]),
            q,
            'mkv',
            destination.path,
            '$withAudio',
            (_) {},
          );
          expect(
            await File(p.join(tools.path, 'selector')).readAsString(),
            withAudio ? 'vp9+audio' : 'vp9',
          );
          expect(await File(output).readAsString(), 'fixture');
          expect(destination.listSync().whereType<Directory>(), isEmpty);
        }
      } finally {
        await engine.shutdown();
        await tools.delete(recursive: true);
        await destination.delete(recursive: true);
      }
    },
    skip: Platform.isWindows,
  );

  test(
    'cancel stops descendants that ignore TERM and releases output pipes',
    () async {
      final tools = await fakeTools(r'''#!/bin/sh
tools=$(dirname "$0")
trap '' TERM
/bin/sh "$tools/worker.sh" "$tools" &
printf '%s %s\n' "$$" "$!" > "$tools/parent.pids"
wait
''');
      await File(p.join(tools.path, 'worker.sh')).writeAsString(r'''
trap '' TERM
sleep 60 &
printf '%s %s\n' "$$" "$!" > "$1/child.pids"
wait
''');
      final destination = await Directory.systemTemp.createTemp(
        'vidora-cancel-test-',
      );
      final engine = DesktopEngine(toolsDirectory: tools.path);
      final q = Quality('video', 'mp4', 720, true);
      final pids = <int>{};
      final download = engine.download(
        Video('https://example.test/video', 'video', null, [q]),
        q,
        'mkv',
        destination.path,
        'cancel',
        (_) {},
      );
      final finished = expectLater(download, throwsA(isA<EngineException>()));
      try {
        pids.addAll(await waitForPids(File(p.join(tools.path, 'parent.pids'))));
        pids.addAll(await waitForPids(File(p.join(tools.path, 'child.pids'))));
        await engine.cancel('cancel').timeout(const Duration(seconds: 10));
        await finished.timeout(const Duration(seconds: 10));
        for (final pid in pids) {
          final process = await Process.run('ps', [
            '-p',
            '$pid',
            '-o',
            'stat=',
          ]);
          final state = (process.stdout as String).trim();
          expect(
            state.isEmpty || state.startsWith('Z'),
            true,
            reason: 'Process $pid is still running: $state',
          );
        }
        expect(destination.listSync().whereType<Directory>(), isEmpty);
      } finally {
        for (final pid in pids) {
          Process.killPid(pid, ProcessSignal.sigkill);
        }
        await finished.timeout(const Duration(seconds: 10));
        await engine.shutdown();
        await tools.delete(recursive: true);
        await destination.delete(recursive: true);
      }
    },
    skip: Platform.isWindows,
    timeout: const Timeout(Duration(seconds: 40)),
  );
}
