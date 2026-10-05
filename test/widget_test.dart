import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_video/main.dart';
import 'package:local_video/strings.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';

class FixtureSelector extends FileSelectorPlatform {
  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => XFile('fixture-cookies.txt');
}

void main() {
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
