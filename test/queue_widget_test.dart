import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_video/cookies.dart';
import 'package:local_video/download_queue.dart';
import 'package:local_video/engine.dart';
import 'package:local_video/main.dart';
import 'package:local_video/site_profiles.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryStore extends QueueStore {
  final List<Job> seed;
  List<Job> last = [];
  MemoryStore(this.seed) : super(File('unused'));
  @override
  Future<List<Job>> load() async => seed;
  @override
  Future<void> save(List<Job> jobs) async {
    last = List.from(jobs);
  }
}

class QueueFixtureEngine extends DesktopEngine {
  final downloaded = <String>[];
  @override
  Future<Video> inspectWith(
    String url,
    ConnectionOptions selected,
    DownloadOptions settings, {
    String? cookieFile,
    CookieSession? session,
    String logId = 'inspection',
    bool impersonate = false,
  }) async {
    if (url.endsWith('/unsupported'))
      throw EngineException(Failure.unsupported);
    return Video(url, url.split('/').last, null, [
      Quality('fixture', 'mp4', 720, true),
    ], options: settings);
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
    downloaded.add(video.title);
    if (video.url.endsWith('/failed'))
      throw EngineException(Failure.loginRequired, logId: id);
    progress(Progress(1, 'fixture'));
    return '$folder/output.mp4';
  }
}

class QueueSelector extends FileSelectorPlatform {
  @override
  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) async => '/fixture';
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('batch keeps failed entries and continues downloading the rest', (
    tester,
  ) async {
    final original = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = QueueSelector();
    final store = MemoryStore([]);
    final engine = QueueFixtureEngine();
    try {
      await tester.pumpWidget(LocalVideoApp(engine: engine, queueStore: store));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'https://example.test/failed\nhttps://example.test/good\nhttps://example.test/unsupported\nhttps://example.test/last',
      );
      final add = find.widgetWithText(
        OutlinedButton,
        'Inspect and queue all links',
      );
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(engine.downloaded, ['failed', 'good', 'last']);
      expect(store.last.map((j) => j.state), [
        'failed',
        'done',
        'failed',
        'done',
      ]);
      expect(store.last.map((j) => j.id).toSet(), hasLength(4));
      expect(store.last[0].error, Failure.loginRequired);
      expect(store.last[2].error, Failure.unsupported);
      expect(tester.takeException(), isNull);
    } finally {
      FileSelectorPlatform.instance = original;
    }
  });

  testWidgets('restored queue waits for Resume and keeps the same job id', (
    tester,
  ) async {
    final q = Quality('fixture', 'mp4', 720, true);
    final restored =
        Job(
            Video('https://example.test/resumed', 'resumed', null, [q]),
            q,
            'mp4',
            '/fixture',
            id: 'restored',
          )
          ..restored = true
          ..state = 'paused'
          ..paused = true;
    final store = MemoryStore([restored]);
    final engine = QueueFixtureEngine();
    await tester.pumpWidget(LocalVideoApp(engine: engine, queueStore: store));
    await tester.pumpAndSettle();
    expect(engine.downloaded, isEmpty);
    final resume = find.widgetWithText(TextButton, 'Resume');
    await tester.scrollUntilVisible(
      resume,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(resume);
    await tester.pumpAndSettle();
    expect(engine.downloaded, ['resumed']);
    expect(store.last.single.id, 'restored');
    expect(store.last.single.state, 'done');
    expect(tester.takeException(), isNull);
  });
}
