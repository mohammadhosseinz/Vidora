import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

class SupportWallet {
  final String currency, network, address;
  const SupportWallet(this.currency, this.network, this.address);
  static SupportWallet? parse(dynamic source) {
    if (source is! Map) return null;
    final currency = source['currency'],
        network = source['network'],
        address = source['address'];
    if (currency is! String || network is! String || address is! String)
      return null;
    if (currency.trim().isEmpty ||
        network.trim().isEmpty ||
        currency.length > 32 ||
        network.length > 64 ||
        !RegExp(r'^[a-zA-Z0-9:_-]{14,160}$').hasMatch(address))
      return null;
    return SupportWallet(currency.trim(), network.trim(), address);
  }
}

/// Public donation link only. Never store payment credentials here.
class SupportConfig {
  final Uri? donationUrl;
  final List<SupportWallet> wallets;
  SupportWallet? get wallet => wallets.isEmpty ? null : wallets.first;
  SupportConfig({
    this.donationUrl,
    SupportWallet? wallet,
    List<SupportWallet>? wallets,
  }) : wallets = wallets ?? (wallet == null ? const [] : [wallet]);

  static SupportConfig parse(String source) {
    try {
      final data = jsonDecode(source) as Map<String, dynamic>;
      if (data['disabled'] == true) return SupportConfig();
      final entries = data['wallets'];
      final legacy = SupportWallet.parse(data['wallet']);
      final wallets = entries is List
          ? entries
                .take(8)
                .map(SupportWallet.parse)
                .whereType<SupportWallet>()
                .toList()
          : legacy == null
          ? <SupportWallet>[]
          : [legacy];
      final raw = data['donationUrl'];
      if (raw is! String || raw.trim().isEmpty)
        return SupportConfig(wallets: wallets);
      final uri = Uri.tryParse(raw.trim());
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          RegExp(r'[\x00-\x20]').hasMatch(raw.trim()))
        return SupportConfig(wallets: wallets);
      return SupportConfig(donationUrl: uri, wallets: wallets);
    } catch (_) {
      return SupportConfig();
    }
  }

  static SupportConfig resolveOverride(String source, SupportConfig bundled) {
    try {
      final data = jsonDecode(source) as Map<String, dynamic>;
      if (data['disabled'] == true) return SupportConfig();
      final wallet = data['wallet'];
      // Upgrade the empty template shipped in 0.1.4 to new bundled defaults.
      final emptyTemplate =
          data['donationUrl'] == '' &&
          wallet is Map &&
          ['currency', 'network', 'address'].every((key) => wallet[key] == '');
      if (emptyTemplate) return bundled;
      final parsed = parse(source);
      // Migrate the USDT-only default shipped in 0.1.5, preserving custom lists.
      final legacyDefault =
          !data.containsKey('wallets') &&
          parsed.donationUrl == null &&
          parsed.wallet?.currency == 'USDT' &&
          parsed.wallet?.network == 'BSC / BEP20' &&
          parsed.wallet?.address ==
              '0x9a350193884756c2ff75e58847d8eff5441c27bf';
      return legacyDefault ? bundled : parsed;
    } catch (_) {
      return SupportConfig();
    }
  }

  static Future<SupportConfig> load() async {
    final bundled = parse(await rootBundle.loadString('assets/support.json'));
    // Windows/Linux portable packages can be configured without rebuilding.
    // Signed macOS apps use bundled configuration to preserve the signature.
    if (!Platform.isMacOS) {
      final file = File(
        p.join(p.dirname(Platform.resolvedExecutable), 'support.json'),
      );
      try {
        if (await file.exists()) {
          if (await file.length() > 8192) return SupportConfig();
          final source = await file.readAsString();
          return resolveOverride(source, bundled);
        }
      } catch (_) {
        return SupportConfig();
      }
    }
    return bundled;
  }
}

Future<void> openSupportPage(Uri uri) async {
  if (SupportConfig.parse(
        jsonEncode({'donationUrl': uri.toString()}),
      ).donationUrl ==
      null)
    throw const FormatException('Invalid support URL');
  final executable = Platform.isWindows
      ? 'explorer.exe'
      : Platform.isMacOS
      ? 'open'
      : 'xdg-open';
  final process = await Process.start(executable, [
    uri.toString(),
  ], runInShell: false);
  // Drain output so Unix launchers can finish without pipe backpressure.
  process.stdout.drain<void>();
  process.stderr.drain<void>();
}
