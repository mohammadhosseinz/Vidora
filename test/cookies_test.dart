import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_video/cookies.dart';
import 'package:local_video/engine.dart';

const header = '# Netscape HTTP Cookie File\n';
const youtube = '.youtube.com\tTRUE\t/\tTRUE\t0\tSESSION\ttest-session-value\n';
void main() {
  test(
    'standalone yt-dlp reads and writes a private cookie copy offline',
    () async {
      final session = CookieSession.parse(
        '$header$youtube',
        'https://www.youtube.com/',
      );
      final lease = await session.stage();
      final engine = DesktopEngine(
        toolsDirectory: Platform.environment['LOCAL_VIDEO_TOOLS'],
      );
      try {
        final result = await Process.run(
          engine.exe('yt-dlp'),
          [
            ...engine.common,
            ...lease.arguments,
            '--enable-file-urls',
            '--skip-download',
            '--dump-single-json',
            '--',
            File(
              Platform.environment['COOKIE_TEST_VIDEO']!,
            ).absolute.uri.toString(),
          ],
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
          runInShell: false,
        );
        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(
          (jsonDecode(result.stdout.toString()) as Map)['formats'],
          isNotEmpty,
        );
        final refreshed = await CookieSession.load(
          lease.path,
          'https://www.youtube.com/',
        );
        expect(refreshed.toString(), 'CookieSession(redacted)');
      } finally {
        await lease.dispose();
      }
      expect(await File(lease.path).exists(), false);
    },
    skip: Platform.environment['COOKIE_TEST_VIDEO'] == null,
  );
  test(
    'scope cookies to the selected site and support YouTube short links',
    () async {
      final session = CookieSession.parse(
        '$header$youtube.example.org\tTRUE\t/\tTRUE\t0\tOTHER\tother-site-value\n',
        'https://youtu.be/test',
      );
      final lease = await session.stage();
      try {
        final contents = await File(lease.path).readAsString();
        expect(contents, contains('test-session-value'));
        expect(contents, isNot(contains('other-site-value')));
        expect(session.toString(), isNot(contains('test-session-value')));
        expect(lease.arguments, ['--cookies', lease.path]);
      } finally {
        await lease.dispose();
      }
      expect(await File(lease.path).exists(), false);
    },
  );
  test('reject malformed, unrelated and expired cookie files', () {
    for (final contents in [
      'not cookies',
      '$header.youtube.com\tTRUE\t/\tTRUE\t0\tSESSION',
      '$header.youtube.com\tBAD\t/\tTRUE\t0\tSESSION\tvalue',
    ]) {
      expect(
        () => CookieSession.parse(contents, 'https://www.youtube.com/'),
        throwsA(isA<CookieException>()),
      );
    }
    for (final contents in [
      '$header.example.org\tTRUE\t/\tTRUE\t0\tSESSION\tvalue',
      '$header.youtube.com\tTRUE\t/\tTRUE\t1\tSESSION\tvalue',
    ]) {
      expect(
        () => CookieSession.parse(contents, 'https://www.youtube.com/'),
        throwsA(
          isA<CookieException>().having(
            (e) => e.reason,
            'reason',
            CookieFailure.noMatchingCookies,
          ),
        ),
      );
    }
  });
  test('HttpOnly and host cookies survive format normalization', () async {
    final session = CookieSession.parse(
      '$header#HttpOnly_youtube.com\tTRUE\t/\tTRUE\t0\tSID\tfixture\n'
          'www.youtube.com\tFALSE\t/\tTRUE\t0\tHOST\tfixture\n',
      'https://www.youtube.com/watch?v=test',
    );
    final lease = await session.stage();
    try {
      expect(
        await File(lease.path).readAsString(),
        contains('#HttpOnly_.youtube.com'),
      );
      expect(
        await File(lease.path).readAsString(),
        contains('www.youtube.com\tFALSE'),
      );
    } finally {
      await lease.dispose();
    }
  });
  test(
    'snapshot and staged writes never modify the original selected file',
    () async {
      final dir = await Directory.systemTemp.createTemp('cookie-fixture-');
      final source = File('${dir.path}/source.txt');
      try {
        await source.writeAsString('$header$youtube');
        final session = await CookieSession.load(
          source.path,
          'https://www.youtube.com/',
        );
        await source.writeAsString('changed after inspection');
        final lease = await session.stage();
        try {
          expect(
            await File(lease.path).readAsString(),
            contains('test-session-value'),
          );
          await File(lease.path).writeAsString('yt-dlp modifies its copy');
          expect(await source.readAsString(), 'changed after inspection');
        } finally {
          await lease.dispose();
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test('failed inspection cleans up the authentication copy', () async {
    final dir = await Directory.systemTemp.createTemp('cookie-fixture-');
    final source = File('${dir.path}/source.txt');
    final before = Directory.systemTemp
        .listSync()
        .whereType<Directory>()
        .where(
          (d) => d.path
              .split(Platform.pathSeparator)
              .last
              .startsWith('local-video-auth-'),
        )
        .map((d) => d.path)
        .toSet();
    try {
      await source.writeAsString('$header$youtube');
      final engine = DesktopEngine(toolsDirectory: 'missing-tools')
        ..cookieFile = source.path;
      await expectLater(
        engine.inspect('https://www.youtube.com/'),
        throwsA(isA<EngineException>()),
      );
      final after = Directory.systemTemp
          .listSync()
          .whereType<Directory>()
          .where(
            (d) => d.path
                .split(Platform.pathSeparator)
                .last
                .startsWith('local-video-auth-'),
          )
          .map((d) => d.path)
          .toSet();
      expect(after.difference(before), isEmpty);
      expect(await source.readAsString(), '$header$youtube');
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
