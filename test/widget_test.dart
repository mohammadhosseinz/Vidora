import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_video/main.dart';
import 'package:local_video/strings.dart';
import 'package:local_video/engine.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';

class FixtureSelector extends FileSelectorPlatform {
  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => XFile('fixture-cookies.txt');
}

class FixtureEngine extends DesktopEngine {
  final qualities = [
    Quality(
      'vp9',
      'webm',
      1080,
      true,
      bytes: 2 * 1024 * 1024,
      videoCodec: 'vp9',
      audioCodec: 'opus',
    ),
    Quality(
      'h264',
      'mp4',
      720,
      true,
      bytes: 3 * 1024 * 1024,
      approximate: true,
      videoCodec: 'h264',
      audioCodec: 'aac',
    ),
    Quality('unknown', 'mp4', 360, true),
  ];

  @override
  Future<Video> inspect(String url) async =>
      Video(url, 'Fixture video', null, qualities);
}

Future<void> inspectFixture(WidgetTester tester, FixtureEngine engine) async {
  await tester.pumpWidget(LocalVideoApp(engine: engine));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'https://example.test/video');
  await tester.ensureVisible(find.text(tr('en', 'inspect')));
  await tester.tap(find.text(tr('en', 'inspect')));
  await tester.pumpAndSettle();
}

Future<void> chooseQuality(WidgetTester tester, String label) async {
  final field = find.byType(DropdownButtonFormField<Quality>);
  await tester.scrollUntilVisible(
    field,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('known, estimated and unknown sizes update in all languages', (
    tester,
  ) async {
    await inspectFixture(tester, FixtureEngine());
    for (final code in ['en', 'fa', 'ar', 'zh']) {
      final language = find.byKey(const ValueKey('language-selector'));
      await tester.tap(language);
      await tester.pumpAndSettle();
      await tester.tap(find.text(languages[code]!).last);
      await tester.pumpAndSettle();
      await chooseQuality(tester, '1080p · webm · vp9');
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('download-size'))).data,
        '2.0 MB',
      );
      await chooseQuality(tester, '720p · mp4 · h264');
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('download-size'))).data,
        '${tr(code, 'approximately')}3.0 MB',
      );
      await chooseQuality(tester, '360p · mp4 · unknown');
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('download-size'))).data,
        tr(code, 'unknownSize'),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('changing quality resets an incompatible WebM selection', (
    tester,
  ) async {
    await inspectFixture(tester, FixtureEngine());
    final field = find.byType(DropdownButtonFormField<String>);
    await tester.scrollUntilVisible(
      field,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text('WEBM').last);
    await tester.pumpAndSettle();
    await chooseQuality(tester, '720p · mp4 · h264');
    final dropdown = tester.widget<DropdownButton<String>>(
      find.descendant(of: field, matching: find.byType(DropdownButton<String>)),
    );
    expect(dropdown.value, 'mkv');
    expect(dropdown.items!.map((item) => item.value), ['mkv', 'mp4']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'About author, support invitation and support action in all four languages',
    (tester) async {
      await tester.pumpWidget(const LocalVideoApp());
      await tester.pumpAndSettle();
      for (final code in ['en', 'fa', 'ar', 'zh']) {
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(languages[code]!).last);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip(tr(code, 'about')));
        await tester.pumpAndSettle();
        expect(find.text(tr(code, 'aboutAuthor')), findsOneWidget);
        expect(find.text(tr(code, 'aboutSupport')), findsOneWidget);
        expect(
          Directionality.of(tester.element(find.text(tr(code, 'aboutBody')))),
          ['fa', 'ar'].contains(code) ? TextDirection.rtl : TextDirection.ltr,
        );
        await tester.tap(
          find.widgetWithText(FilledButton, tr(code, 'support')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text(tr(code, 'supportBody')), findsOneWidget);
        await tester.tap(find.text(tr(code, 'close')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets(
    'choose and disable optional cookies without reading the browser',
    (tester) async {
      final original = FileSelectorPlatform.instance;
      FileSelectorPlatform.instance = FixtureSelector();
      try {
        await tester.pumpWidget(const LocalVideoApp());
        await tester.pumpAndSettle();
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(languages['fa']!).last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('کوکی اختیاری مرورگر'));
        await tester.tap(find.text('کوکی اختیاری مرورگر'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('انتخاب فایل کوکی'));
        await tester.tap(find.text('انتخاب فایل کوکی'));
        await tester.pumpAndSettle();
        expect(find.text('fixture-cookies.txt'), findsOneWidget);
        await tester.ensureVisible(
          find.text('قطع استفاده از کوکی برای بررسی بعدی'),
        );
        await tester.tap(find.text('قطع استفاده از کوکی برای بررسی بعدی'));
        await tester.pumpAndSettle();
        expect(find.text('fixture-cookies.txt'), findsNothing);
        expect(find.text('بدون فایل کوکی'), findsOneWidget);
      } finally {
        FileSelectorPlatform.instance = original;
      }
    },
  );
  testWidgets('English default and correct direction for all four languages', (
    tester,
  ) async {
    await tester.pumpWidget(const LocalVideoApp());
    await tester.pumpAndSettle();
    expect(find.text(tr('en', 'inspect')), findsOneWidget);
    expect(
      Localizations.localeOf(tester.element(find.byType(Home))).languageCode,
      'en',
    );
    for (final code in ['en', 'ar', 'zh', 'fa']) {
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(languages[code]!).last);
      await tester.pumpAndSettle();
      expect(find.text(tr(code, 'inspect')), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.byType(TextField))),
        ['fa', 'ar'].contains(code) ? TextDirection.rtl : TextDirection.ltr,
      );
    }
  });
}
