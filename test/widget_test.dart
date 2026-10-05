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
    'choose and disable optional cookies without reading the browser',
    (tester) async {
      final original = FileSelectorPlatform.instance;
      FileSelectorPlatform.instance = FixtureSelector();
      try {
        await tester.pumpWidget(const LocalVideoApp());
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
  testWidgets('Persian RTL and all four languages', (tester) async {
    await tester.pumpWidget(const LocalVideoApp());
    await tester.pumpAndSettle();
    expect(find.text('بررسی لینک'), findsOneWidget);
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
