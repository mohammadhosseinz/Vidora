import 'dart:convert';
import 'dart:io';

class EngineHealth {
  final String version;
  final String? latest;
  const EngineHealth(this.version, {this.latest});

  static DateTime? releaseDate(String version) {
    final match = RegExp(r'^(\d{4})\.(\d{2})\.(\d{2})').firstMatch(version);
    return match == null
        ? null
        : DateTime.tryParse('${match[1]}-${match[2]}-${match[3]}');
  }

  bool outdatedAt(DateTime now) {
    final current = releaseDate(version);
    final newer = latest == null ? null : releaseDate(latest!);
    return (current != null && now.difference(current).inDays >= 90) ||
        (current != null && newer != null && newer.isAfter(current));
  }

  /// Explicit user action only. No video URLs or session data leave the app.
  Future<EngineHealth> checkLatest() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(
        Uri.https('api.github.com', '/repos/yt-dlp/yt-dlp/releases/latest'),
      );
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader, 'Vidora');
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != 200)
        throw const HttpException('Update check failed');
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 10))) {
        bytes.addAll(chunk);
        if (bytes.length > 1024 * 1024)
          throw const FormatException('Response too large');
      }
      final tag = (jsonDecode(utf8.decode(bytes)) as Map)['tag_name'] as String;
      if (releaseDate(tag) == null)
        throw const FormatException('Invalid release');
      return EngineHealth(version, latest: tag);
    } finally {
      client.close(force: true);
    }
  }
}
