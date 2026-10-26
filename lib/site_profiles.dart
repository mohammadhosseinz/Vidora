enum ExtractorMode { automatic, upstream, generic }

class SiteProfile {
  final String id, name, preferredFormat;
  final List<String> domains;
  final String? referer, userAgent;
  final bool sessionHint, impersonation;
  const SiteProfile(
    this.id,
    this.name,
    this.domains, {
    this.referer,
    this.userAgent,
    this.preferredFormat = 'bv*+ba/b',
    this.sessionHint = false,
    this.impersonation = false,
  });

  static const generic = SiteProfile('generic', 'Other site', []);
  static const all = [
    SiteProfile('aparat', 'Aparat', [
      'aparat.com',
    ], referer: 'https://www.aparat.com/'),
    SiteProfile('youtube', 'YouTube', [
      'youtube.com',
      'youtu.be',
      'youtube-nocookie.com',
    ], sessionHint: true),
    SiteProfile(
      'instagram',
      'Instagram',
      ['instagram.com'],
      sessionHint: true,
      impersonation: true,
    ),
    SiteProfile(
      'twitter',
      'X / Twitter',
      ['x.com', 'twitter.com'],
      sessionHint: true,
      impersonation: true,
    ),
    SiteProfile(
      'tiktok',
      'TikTok',
      ['tiktok.com'],
      sessionHint: true,
      impersonation: true,
    ),
    SiteProfile(
      'facebook',
      'Facebook',
      ['facebook.com', 'fb.watch'],
      sessionHint: true,
      impersonation: true,
    ),
    SiteProfile(
      'vimeo',
      'Vimeo',
      ['vimeo.com'],
      sessionHint: true,
      impersonation: true,
    ),
  ];

  static SiteProfile forUrl(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return all.firstWhere(
      (profile) =>
          profile.domains.any((d) => host == d || host.endsWith('.$d')),
      orElse: () => generic,
    );
  }
}

/// Values belong to a single inspection/download, not mutable global settings.
class DownloadOptions {
  final Map<String, String> headers;
  final String userAgent, referer, format;
  final ExtractorMode extractor;
  final bool allowImpersonation, allowFormatFallback;
  DownloadOptions({
    Map<String, String> headers = const {},
    this.userAgent = '',
    this.referer = '',
    this.format = '',
    this.extractor = ExtractorMode.automatic,
    this.allowImpersonation = true,
    this.allowFormatFallback = false,
  }) : headers = Map.unmodifiable(headers);

  bool get hasSessionHeaders => headers.keys.any(
    (key) => RegExp(
      r'cookie|authorization|token|auth',
      caseSensitive: false,
    ).hasMatch(key),
  );

  static Map<String, String> parseHeaders(String source) {
    final result = <String, String>{};
    for (final line in source.split('\n')) {
      if (line.trim().isEmpty) continue;
      final colon = line.indexOf(':');
      if (colon <= 0) throw const FormatException('Invalid header');
      result[line.substring(0, colon).trim()] = line
          .substring(colon + 1)
          .trim();
    }
    return result;
  }

  void validate() {
    for (final value in [userAgent, referer, format, ...headers.values]) {
      if (value.length > 8192 || RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
        throw const FormatException('Invalid option');
      }
    }
    if (headers.length > 32 ||
        headers.keys.any(
          (key) => !RegExp(r"^[!#$%&'*+.^_`|~0-9a-zA-Z-]+$").hasMatch(key),
        ))
      throw const FormatException('Invalid header');
    if (referer.isNotEmpty) {
      final uri = Uri.tryParse(referer);
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw const FormatException('Invalid referer');
      }
    }
  }

  List<String> arguments(SiteProfile profile) {
    validate();
    final ua = userAgent.isEmpty ? profile.userAgent : userAgent;
    final ref = referer.isEmpty ? profile.referer : referer;
    return [
      if (ua != null && ua.isNotEmpty) ...['--user-agent', ua],
      if (ref != null && ref.isNotEmpty) ...['--referer', ref],
      for (final header in headers.entries) ...[
        '--add-headers',
        '${header.key}:${header.value}',
      ],
      if (extractor == ExtractorMode.generic) '--force-generic-extractor',
    ];
  }
}
