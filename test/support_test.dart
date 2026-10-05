import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_video/main.dart';
import 'package:local_video/support.dart';

void main() {
  test(
    'legacy USDT settings upgrade to both networks; explicit custom list is preserved',
    () {
      final bundled = SupportConfig(
        wallets: [
          const SupportWallet(
            'USDT',
            'BSC / BEP20',
            '0x9a350193884756c2ff75e58847d8eff5441c27bf',
          ),
          const SupportWallet(
            'TRX',
            'TRON (TRX only)',
            'TBiSUJuPZfLAJ9VHiQuGpNVPzsEYixgp13',
          ),
        ],
      );
      expect(
        SupportConfig.resolveOverride(
          '{"donationUrl":"","wallet":{"currency":"USDT","network":"BSC / BEP20","address":"0x9a350193884756c2ff75e58847d8eff5441c27bf"}}',
          bundled,
        ).wallets.length,
        2,
      );
      expect(
        SupportConfig.resolveOverride(
          '{"wallets":[{"currency":"TEST","network":"Fixture","address":"TESTADDRESS1234567890"}]}',
          bundled,
        ).wallets.single.currency,
        'TEST',
      );
      expect(
        SupportConfig.resolveOverride('{"disabled":true}', bundled).wallets,
        isEmpty,
      );
    },
  );
  test(
    'empty legacy settings upgrade while custom settings and disabled state survive',
    () {
      final bundled = SupportConfig(
        wallet: SupportWallet(
          'USDT',
          'BSC / BEP20',
          '0x9a350193884756c2ff75e58847d8eff5441c27bf',
        ),
      );
      expect(
        SupportConfig.resolveOverride(
          '{"donationUrl":"","wallet":{"currency":"","network":"","address":""}}',
          bundled,
        ).wallet?.address,
        bundled.wallet!.address,
      );
      expect(
        SupportConfig.resolveOverride(
          '{"donationUrl":"https://example.com/custom"}',
          bundled,
        ).donationUrl?.path,
        '/custom',
      );
      expect(
        SupportConfig.resolveOverride('{"disabled":true}', bundled).wallet,
        isNull,
      );
      expect(SupportConfig.resolveOverride('invalid', bundled).wallet, isNull);
    },
  );
  test('only safe public HTTPS donation links are accepted', () {
    expect(
      SupportConfig.parse(
        '{"donationUrl":"https://example.com/donate?creator=vidora"}',
      ).donationUrl?.host,
      'example.com',
    );
    for (final source in [
      '{}',
      'invalid',
      '{"donationUrl":"javascript:alert(1)"}',
      '{"donationUrl":"file:///secret"}',
      '{"donationUrl":"https://user:password@example.com"}',
      '{"donationUrl":"https://example.com bad"}',
    ]) {
      expect(SupportConfig.parse(source).donationUrl, isNull);
    }
  });
  test('wallet requires public address, currency and explicit network', () {
    final config = SupportConfig.parse(
      '{"wallet":{"currency":"TEST","network":"Fixture network","address":"TESTADDRESS1234567890"}}',
    );
    expect(config.wallet?.address, 'TESTADDRESS1234567890');
    expect(config.wallet?.network, 'Fixture network');
    expect(
      SupportConfig.parse(
        '{"wallet":{"currency":"TEST","address":"TESTADDRESS1234567890"}}',
      ).wallet,
      isNull,
    );
    expect(
      SupportConfig.parse(
        '{"wallet":{"currency":"TEST","network":"Fixture network","address":"word word word word"}}',
      ).wallet,
      isNull,
    );
  });
  testWidgets(
    'both donation networks display separate addresses and copy the selected one',
    (tester) async {
      await tester.pumpWidget(const LocalVideoApp());
      await tester.runAsync(() async {
        final config = await SupportConfig.load();
        expect(
          config.wallet?.address,
          '0x9a350193884756c2ff75e58847d8eff5441c27bf',
        );
      });
      await tester.pumpAndSettle();
      expect(find.text('ویدورا'), findsOneWidget);
      await tester.tap(find.byTooltip('حمایت از ویدورا'));
      await tester.pumpAndSettle();
      expect(find.text('لینک حمایت به‌زودی اضافه می‌شود.'), findsNothing);
      expect(find.text('USDT · BSC / BEP20'), findsOneWidget);
      expect(find.text('TRX · TRON (TRX only)'), findsOneWidget);
      const address = '0x9a350193884756c2ff75e58847d8eff5441c27bf';
      expect(find.text(address), findsOneWidget);
      String? copied;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData')
          copied = call.arguments['text'] as String;
        return null;
      });
      try {
        for (final expected in [
          address,
          'TBiSUJuPZfLAJ9VHiQuGpNVPzsEYixgp13',
        ]) {
          final card = find
              .ancestor(of: find.text(expected), matching: find.byType(Card))
              .first;
          final copy = find.descendant(
            of: card,
            matching: find.widgetWithText(OutlinedButton, 'کپی آدرس کیف پول'),
          );
          await tester.ensureVisible(copy);
          await tester.tap(copy);
          await tester.pumpAndSettle();
          expect(copied, expected);
        }
      } finally {
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      }

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'رفتن به صفحهٔ حمایت'),
      );
      expect(button.onPressed, isNull);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('بستن'));
      await tester.pumpAndSettle();
    },
  );
}
