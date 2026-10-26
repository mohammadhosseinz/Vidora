import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_video/main.dart';
import 'package:local_video/strings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'stored language restores, invalid or wrongly typed values use English',
    () async {
      expect(await LocalVideoApp.loadStoredLanguage(), 'en');
      SharedPreferences.setMockInitialValues({LocalVideoApp.languageKey: 'fa'});
      expect(await LocalVideoApp.loadStoredLanguage(), 'fa');
      SharedPreferences.setMockInitialValues({
        LocalVideoApp.languageKey: 'unsupported',
      });
      expect(await LocalVideoApp.loadStoredLanguage(), 'en');
      SharedPreferences.setMockInitialValues({LocalVideoApp.languageKey: 12});
      expect(await LocalVideoApp.loadStoredLanguage(), 'en');
    },
  );

  testWidgets('language and theme survive an app restart', (tester) async {
    await tester.pumpWidget(const LocalVideoApp());
    await tester.pumpAndSettle();
    for (final code in ['ar', 'en', 'fa']) {
      await tester.tap(find.byKey(const ValueKey('language-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(languages[code]!).last);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip(tr('fa', 'theme')));
    await tester.pumpAndSettle();
    expect(await LocalVideoApp.loadStoredLanguage(), 'fa');
    expect(await LocalVideoApp.loadStoredTheme(), ThemeMode.dark);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      LocalVideoApp(
        initialLanguage: await LocalVideoApp.loadStoredLanguage(),
        initialTheme: await LocalVideoApp.loadStoredTheme(),
      ),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(Home));
    expect(Localizations.localeOf(context).languageCode, 'fa');
    expect(Theme.of(context).brightness, Brightness.dark);
  });

  testWidgets(
    'unavailable preferences do not prevent startup or language changes',
    (tester) async {
      const channel = MethodChannel('plugins.flutter.io/shared_preferences');
      // Reset the singleton and then force the platform call to fail.
      SharedPreferences.resetStatic();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        _,
      ) async {
        throw PlatformException(code: 'unavailable');
      });
      try {
        expect(await LocalVideoApp.loadStoredLanguage(), 'en');
        await tester.pumpWidget(const LocalVideoApp());
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('language-selector')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(languages['fa']!).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
        SharedPreferences.setMockInitialValues({});
      }
    },
  );
}
