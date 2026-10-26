import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:file_selector/file_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'engine.dart';
import 'site_profiles.dart';
import 'diagnostics.dart';
import 'download_queue.dart';
import 'engine_health.dart';
import 'package:path_provider/path_provider.dart';
import 'strings.dart';
import 'support.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path/path.dart' as p;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setPreventClose(true);
  await windowManager.setTitle('Vidora');

  final initialLanguage = await LocalVideoApp.loadStoredLanguage();
  Directory? dataDirectory;
  try {
    dataDirectory = await getApplicationSupportDirectory();
  } catch (_) {}
  final store = dataDirectory == null
      ? null
      : QueueStore(File(p.join(dataDirectory.path, 'queue.json')));
  final diagnostics = Diagnostics(
    directory: dataDirectory == null
        ? null
        : Directory(p.join(dataDirectory.path, 'logs')),
  );
  final engine = DesktopEngine(
    toolsDirectory: Platform.environment['LOCAL_VIDEO_TOOLS'],
    diagnostics: diagnostics,
  );
  final theme = await LocalVideoApp.loadStoredTheme();
  runApp(
    LocalVideoApp(
      initialLanguage: initialLanguage,
      initialTheme: theme,
      engine: engine,
      queueStore: store,
      storageUnavailable: dataDirectory == null,
    ),
  );
}

class LocalVideoApp extends StatefulWidget {
  static const String languageKey = 'selected_language';
  static const List<String> supportedLanguageCodes = ['fa', 'ar', 'en', 'zh'];

  final DesktopEngine? engine;
  final String initialLanguage;
  final ThemeMode initialTheme;
  final QueueStore? queueStore;
  final bool storageUnavailable;

  const LocalVideoApp({
    super.key,
    this.engine,
    this.initialLanguage = 'en',
    this.initialTheme = ThemeMode.system,
    this.queueStore,
    this.storageUnavailable = false,
  });

  static Future<String> loadStoredLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(languageKey);
      if (saved != null && supportedLanguageCodes.contains(saved)) return saved;
    } catch (_) {
      /* An unreadable preference must not prevent startup. */
    }
    return 'en';
  }

  static Future<ThemeMode> loadStoredTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return ThemeMode.values.byName(prefs.getString('theme') ?? 'system');
    } catch (_) {
      return ThemeMode.system;
    }
  }

  @override
  State<LocalVideoApp> createState() => _AppState();
}

class _AppState extends State<LocalVideoApp> {
  late String language =
      LocalVideoApp.supportedLanguageCodes.contains(widget.initialLanguage)
      ? widget.initialLanguage
      : 'en';
  late ThemeMode theme = widget.initialTheme;
  Future<void> _settingsWrites = Future.value();

  void _savePreference(String key, String value) {
    // Serialize rapid changes so the last selected value wins on disk as well.
    _settingsWrites = _settingsWrites.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(key, value);
      } catch (_) {
        /* UI remains usable when settings cannot be written. */
      }
    });
  }

  void _onLanguageChanged(String nextLanguage) {
    setState(() => language = nextLanguage);
    _savePreference(LocalVideoApp.languageKey, nextLanguage);
  }

  void _toggleTheme() {
    final isDark =
        theme == ThemeMode.dark ||
        (theme == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    setState(() => theme = isDark ? ThemeMode.light : ThemeMode.dark);
    _savePreference('theme', theme.name);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: Locale(language),
    supportedLocales: const [
      Locale('fa'),
      Locale('ar'),
      Locale('en'),
      Locale('zh'),
    ],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      fontFamily: ['fa', 'ar'].contains(language)
          ? 'NotoArabic'
          : language == 'zh'
          ? 'NotoChinese'
          : null,
      fontFamilyFallback: const ['NotoArabic', 'NotoChinese'],
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff136f63)),
      useMaterial3: true,
    ),
    darkTheme: ThemeData(
      fontFamily: ['fa', 'ar'].contains(language)
          ? 'NotoArabic'
          : language == 'zh'
          ? 'NotoChinese'
          : null,
      fontFamilyFallback: const ['NotoArabic', 'NotoChinese'],
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff136f63),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    themeMode: theme,
    home: Home(
      engine: widget.engine,
      language: language,
      onLanguage: _onLanguageChanged,
      queueStore: widget.queueStore,
      storageUnavailable: widget.storageUnavailable,
      onTheme: _toggleTheme,
      flushSettings: () => _settingsWrites,
    ),
  );
}

class Home extends StatefulWidget {
  final DesktopEngine? engine;
  final String language;
  final ValueChanged<String> onLanguage;
  final VoidCallback? onTheme;
  final QueueStore? queueStore;
  final bool storageUnavailable;
  final Future<void> Function()? flushSettings;
  const Home({
    super.key,
    required this.language,
    required this.onLanguage,
    this.engine,
    this.onTheme,
    this.queueStore,
    this.storageUnavailable = false,
    this.flushSettings,
  });
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WindowListener {
  late final engine =
      widget.engine ??
      DesktopEngine(toolsDirectory: Platform.environment['LOCAL_VIDEO_TOOLS']);
  final input = TextEditingController();
  Timer? previewTimer;
  SupportConfig supportConfig = SupportConfig();
  final proxyInput = TextEditingController();
  final userAgentInput = TextEditingController();
  final refererInput = TextEditingController();
  final headersInput = TextEditingController();
  final formatInput = TextEditingController();
  ExtractorMode extractorMode = ExtractorMode.automatic;
  bool allowImpersonation = true, allowFormatFallback = false;
  EngineHealth? health;
  bool checkingUpdate = false, updateFailed = false, persistenceFailed = false;
  bool queueReady = false;
  String? inspectionLogId;
  Timer? saveTimer;

  ConnectionMode connectionMode = ConnectionMode.automatic;
  String? cookiePath;
  final jobs = <Job>[];
  Video? video;
  Quality? quality;
  String format = 'mkv';
  String? folder;
  Failure? error;
  bool checking = false, working = false;
  bool closing = false;
  String t(String key) => tr(widget.language, key);
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    persistenceFailed = widget.storageUnavailable;
    unawaited(_restoreQueue());
    if (widget.engine != null && widget.queueStore != null)
      unawaited(_loadHealth());
    SupportConfig.load().then((config) {
      if (mounted) setState(() => supportConfig = config);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    previewTimer?.cancel();
    input.dispose();
    proxyInput.dispose();
    for (final controller in [
      userAgentInput,
      refererInput,
      headersInput,
      formatInput,
    ]) {
      controller.dispose();
    }
    saveTimer?.cancel();
    super.dispose();
  }

  @override
  Future<void> onWindowClose() async {
    if (closing) return;
    setState(() => closing = true);
    previewTimer?.cancel();
    for (final job in jobs.where(
      (j) => ['waiting', 'running', 'retrying', 'checking'].contains(j.state),
    )) {
      job.paused = true;
      if (job.state == 'waiting') job.state = 'paused';
    }
    await engine.shutdown();
    while (working || checking) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await _saveQueue();
    await widget.flushSettings?.call();
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  void linkChanged(String value) {
    previewTimer?.cancel();
    if (closing) return;
    setState(() {
      video = null;
      quality = null;
      error = null;
      inspectionLogId = null;
    });
    try {
      validateLink(value.trim());
    } catch (_) {
      return;
    }
    previewTimer = Timer(const Duration(milliseconds: 900), () {
      if (!checking) inspect();
    });
  }

  String sizeLabel(Quality q) {
    if (q.bytes == null) return t('unknownSize');
    final units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double size = q.bytes!.toDouble();
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${q.approximate ? t('approximately') : ''}${size.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  Future<void> inspect() async {
    if (checking || closing) return;
    previewTimer?.cancel();
    final inspectedLink = input.text.trim();
    setState(() {
      checking = true;
      error = null;
      inspectionLogId = null;
      video = null;
      quality = null;
    });
    try {
      engine.connection = ConnectionOptions(
        mode: connectionMode,
        proxy: proxyInput.text.trim(),
      );
      engine.cookieFile = cookiePath;
      engine.options = _currentOptions();
      final v = await engine.inspect(inspectedLink);
      if (mounted && input.text.trim() == inspectedLink)
        setState(() {
          video = v;
          quality = v.qualities.first;
          if (!quality!.containers.contains(format)) format = 'mkv';
        });
    } on EngineException catch (e) {
      if (mounted && input.text.trim() == inspectedLink)
        setState(() {
          error = e.reason;
          inspectionLogId = e.logId;
        });
    } on FormatException {
      if (mounted) setState(() => error = Failure.invalidOptions);
    } catch (_) {
      if (mounted && input.text.trim() == inspectedLink)
        setState(() => error = Failure.extraction);
    } finally {
      if (mounted) {
        setState(() => checking = false);
        if (input.text.trim() != inspectedLink) linkChanged(input.text);
      }
    }
  }

  DownloadOptions _currentOptions() => DownloadOptions(
    userAgent: userAgentInput.text.trim(),
    referer: refererInput.text.trim(),
    headers: DownloadOptions.parseHeaders(headersInput.text),
    format: formatInput.text.trim(),
    extractor: extractorMode,
    allowImpersonation: allowImpersonation,
    allowFormatFallback: allowFormatFallback,
  );

  Future<void> _restoreQueue() async {
    final stored = await widget.queueStore?.load() ?? <Job>[];
    if (!mounted) return;
    setState(() {
      jobs.addAll(stored);
      queueReady = true;
    });
  }

  Future<void> _saveQueue() async {
    saveTimer?.cancel();
    if (!queueReady) return;
    try {
      await widget.queueStore?.save(jobs);
    } catch (_) {
      if (mounted) setState(() => persistenceFailed = true);
    }
  }

  void _scheduleSave() {
    if (saveTimer?.isActive == true) return;
    saveTimer = Timer(
      const Duration(seconds: 2),
      () => unawaited(_saveQueue()),
    );
  }

  Future<void> _loadHealth() async {
    try {
      final status = EngineHealth(await engine.runtimeVersion());
      if (mounted) setState(() => health = status);
    } catch (_) {}
  }

  Future<void> _checkUpdate() async {
    setState(() {
      checkingUpdate = true;
      updateFailed = false;
    });
    try {
      final installed = health ?? EngineHealth(await engine.runtimeVersion());
      final status = await installed.checkLatest();
      if (mounted) setState(() => health = status);
    } catch (_) {
      if (mounted) setState(() => updateFailed = true);
    } finally {
      if (mounted) setState(() => checkingUpdate = false);
    }
  }

  Future<void> showLog(String id) async {
    final contents = await engine.diagnostics.read(id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('log')),
        content: SizedBox(
          width: 700,
          height: 400,
          child: SingleChildScrollView(
            child: SelectableText(
              contents.isEmpty ? t('noLog') : contents,
              textDirection: TextDirection.ltr,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: contents));
            },
            child: Text(t('copyLog')),
          ),
          TextButton(
            onPressed: () async {
              try {
                final location = await getSaveLocation(
                  suggestedName: 'vidora-$id.log',
                );
                if (location != null)
                  await XFile.fromData(
                    utf8.encode(contents),
                    mimeType: 'text/plain',
                    name: 'vidora-$id.log',
                  ).saveTo(location.path);
              } catch (_) {
                if (mounted)
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(t('storage'))));
              }
            },
            child: Text(t('exportLog')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t('close')),
          ),
        ],
      ),
    );
  }

  Future<void> addBatch() async {
    if (checking || closing || !queueReady) return;
    final links = input.text
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    if (links.isEmpty) return;
    final destination = folder ?? await getDirectoryPath();
    if (destination == null || !mounted) return;
    DownloadOptions settings;
    try {
      settings = _currentOptions();
      settings.validate();
    } catch (_) {
      setState(() => error = Failure.invalidOptions);
      return;
    }
    folder = destination;
    setState(() {
      checking = true;
      error = null;
    });
    final selectedConnection = ConnectionOptions(
      mode: connectionMode,
      proxy: proxyInput.text.trim(),
    );
    final selectedCookies = cookiePath;
    final batch = <Job>[];
    for (final link in links.take((1000 - jobs.length).clamp(0, 1000))) {
      final placeholder = Quality('pending', 'mp4', 0, true);
      final job = Job(
        Video(
          link,
          link,
          null,
          [placeholder],
          connection: selectedConnection,
          options: settings,
        ),
        placeholder,
        'mkv',
        destination,
      );
      job.state = 'checking';
      job.restored = true;
      batch.add(job);
    }
    setState(() => jobs.addAll(batch));
    await _saveQueue();
    for (final job in batch) {
      if (closing) {
        job.state = 'paused';
        continue;
      }
      if (job.cancelled || job.paused) {
        job.state = job.cancelled ? 'cancelled' : 'paused';
        continue;
      }
      try {
        final inspected = await engine.inspectWith(
          job.video.url,
          selectedConnection,
          settings,
          cookieFile: selectedCookies,
          logId: job.id,
        );
        job.video = inspected;
        job.quality = inspected.qualities.first;
        job.restored = false;
        job.state = job.cancelled
            ? 'cancelled'
            : job.paused || closing
            ? 'paused'
            : 'waiting';
      } on EngineException catch (e) {
        job.state = job.cancelled
            ? 'cancelled'
            : job.paused || closing
            ? 'paused'
            : 'failed';
        job.error = e.reason;
        engine.diagnostics.add(job.id, 'Inspection failed: ${e.reason.name}');
      } catch (_) {
        job.state = 'failed';
        job.error = Failure.extraction;
      }
      if (mounted) setState(() {});
      await engine.diagnostics.flush(job.id);
      await _saveQueue();
    }
    if (mounted)
      setState(() {
        for (final job in batch.where((j) => j.state == 'batchReady')) {
          job.state = 'waiting';
        }
        checking = false;
      });
    await _saveQueue();
    unawaited(pump());
  }

  Future<void> pump() async {
    if (working || closing) return;
    working = true;
    try {
      while (!closing && jobs.any((j) => j.state == 'waiting')) {
        final j = jobs.firstWhere((j) => j.state == 'waiting');
        setState(() => j.state = j.restored ? 'checking' : 'running');
        await _saveQueue();
        try {
          if (j.restored) {
            if (j.video.requiresSession && cookiePath == null)
              throw EngineException(Failure.cookiesRequired);
            final previous = j.video.options;
            final overrides = _currentOptions();
            final restoredOptions = DownloadOptions(
              headers: overrides.headers,
              userAgent: overrides.userAgent,
              referer: overrides.referer,
              format: previous.format,
              extractor: previous.extractor,
              allowImpersonation: previous.allowImpersonation,
              allowFormatFallback: previous.allowFormatFallback,
            );
            final refreshed = await engine.inspectWith(
              j.video.url,
              j.video.connection,
              restoredOptions,
              cookieFile: cookiePath,
              logId: j.id,
            );
            final matching = refreshed.qualities.where(
              (q) =>
                  q.id == j.quality.id &&
                  q.audioId == j.quality.audioId &&
                  q.containers.contains(j.format),
            );
            if (matching.isNotEmpty) {
              j.quality = matching.first;
            } else {
              final fallback = refreshed.qualities.where(
                (q) =>
                    (j.quality.id == 'pending' ||
                        q.height <= j.quality.height) &&
                    q.containers.contains(j.format),
              );
              if ((j.quality.id != 'pending' &&
                      !previous.allowFormatFallback) ||
                  fallback.isEmpty)
                throw EngineException(Failure.formatUnavailable);
              j.quality = fallback.first;
            }
            j.video = refreshed;
            j.restored = false;
          }
          if (j.paused || j.cancelled || closing)
            throw EngineException(Failure.extraction);
          await engine.download(j.video, j.quality, j.format, j.folder, j.id, (
            p,
          ) {
            if (mounted)
              setState(() {
                j.state = p.phase;
                j.progress = p.fraction;
                j.speed = p.speed;
                j.attempt = p.attempt;
                j.actualHeight = p.height;
                if (p.selectedQuality != null) j.quality = p.selectedQuality!;
              });
            _scheduleSave();
          });
          if (mounted)
            setState(() {
              j.state = 'done';
              j.progress = 1;
            });
        } on EngineException catch (e) {
          engine.diagnostics.add(j.id, 'Job failed: ${e.reason.name}');
          await engine.diagnostics.flush(j.id);
          if (mounted)
            setState(() {
              j.state = j.cancelled
                  ? 'cancelled'
                  : j.paused || closing
                  ? 'paused'
                  : 'failed';
              j.error = e.reason;
            });
        } catch (_) {
          if (mounted)
            setState(() {
              j.state = j.cancelled
                  ? 'cancelled'
                  : j.paused || closing
                  ? 'paused'
                  : 'failed';
              j.error = Failure.extraction;
            });
        }
        await _saveQueue();
      }
    } finally {
      working = false;
    }
  }

  Future<void> retry(Job j) async {
    if (j.state == 'failed' &&
        (cookiePath != null ||
            [
              Failure.loginRequired,
              Failure.cookiesRequired,
              Failure.invalidCookies,
              Failure.noMatchingCookies,
              Failure.expired,
              Failure.formatUnavailable,
            ].contains(j.error))) {
      j.restored = true;
    }
    engine.prepareRetry(j.id);
    setState(() {
      j.cancelled = false;
      j.paused = false;
      j.error = null;
      j.state = 'waiting';
    });
    await _saveQueue();
    unawaited(pump());
  }

  Future<void> pause(Job j) async {
    setState(() => j.paused = true);
    if (j.state == 'waiting') {
      setState(() => j.state = 'paused');
    } else {
      await engine.pause(j.id);
    }
    await _saveQueue();
  }

  Future<void> cancel(Job j) async {
    setState(() => j.cancelled = true);
    if (['waiting', 'paused', 'failed'].contains(j.state)) {
      setState(() => j.state = 'cancelled');
      await engine.discardPartial(j.folder, j.id);
    } else {
      await engine.cancel(j.id);
    }
    await _saveQueue();
  }

  Future<void> showAbout() async {
    final supportRequested = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('about')),
        scrollable: true,
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Image.asset(
                  'assets/brand/vidora-logo.png',
                  width: 88,
                  height: 88,
                ),
              ),
              const SizedBox(height: 16),
              Text(t('aboutBody')),
              const SizedBox(height: 16),
              Text(
                t('aboutAuthor'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Text(t('aboutSupport')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t('close')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.favorite_outline),
            label: Text(t('support')),
          ),
        ],
      ),
    );
    if (supportRequested == true && mounted) await showSupport();
  }

  Future<void> showSupport() async {
    bool launchFailed = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) => AlertDialog(
          title: Text(t('support')),
          scrollable: true,
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/brand/vidora-logo.png',
                  width: 88,
                  height: 88,
                ),
                const SizedBox(height: 16),
                Text(t('supportBody')),
                const SizedBox(height: 12),
                Text(t('supportPrivacy')),
                for (final wallet in supportConfig.wallets)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${wallet.currency} · ${wallet.network}',
                            textDirection: TextDirection.ltr,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            wallet.address,
                            textDirection: TextDirection.ltr,
                          ),
                          Text(t('walletNetworkHint')),
                          OutlinedButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: wallet.address),
                              );
                              if (dialogContext.mounted)
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  SnackBar(content: Text(t('addressCopied'))),
                                );
                            },
                            icon: const Icon(Icons.copy),
                            label: Text(t('copyAddress')),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                if (supportConfig.donationUrl == null &&
                    supportConfig.wallet == null)
                  Text(t('supportUnavailable')),
                if (supportConfig.donationUrl != null) ...[
                  Text(
                    supportConfig.donationUrl!.host,
                    textDirection: TextDirection.ltr,
                  ),
                  if (launchFailed) ...[
                    Text(t('supportError')),
                    SelectableText(
                      supportConfig.donationUrl.toString(),
                      textDirection: TextDirection.ltr,
                    ),
                  ],
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(t('close')),
            ),
            FilledButton.icon(
              onPressed: supportConfig.donationUrl == null
                  ? null
                  : () async {
                      try {
                        await openSupportPage(supportConfig.donationUrl!);
                      } catch (_) {
                        if (dialogContext.mounted)
                          updateDialog(() => launchFailed = true);
                      }
                    },
              icon: const Icon(Icons.favorite_outline),
              label: Text(t('supportOpen')),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> advancedSettings() {
    final profile = SiteProfile.forUrl(input.text.trim());
    return [
      if (profile.id != 'generic')
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            '${profile.name} · ${t(profile.sessionHint ? 'siteSessionHint' : 'siteReady')}',
          ),
        ),
      ExpansionTile(
        title: Text(t('advanced')),
        children: [
          TextField(
            controller: userAgentInput,
            enabled: !checking,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'User-Agent'),
          ),
          TextField(
            controller: refererInput,
            enabled: !checking,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'Referer'),
          ),
          TextField(
            controller: headersInput,
            enabled: !checking,
            textDirection: TextDirection.ltr,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: t('headers'),
              hintText: 'Header-Name: value',
            ),
          ),
          TextField(
            controller: formatInput,
            enabled: !checking,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: t('formatOverride'),
              hintText: profile.preferredFormat,
            ),
          ),
          DropdownButtonFormField<ExtractorMode>(
            initialValue: extractorMode,
            decoration: InputDecoration(labelText: t('extractor')),
            items: ExtractorMode.values
                .map(
                  (m) => DropdownMenuItem(
                    value: m,
                    child: Text(t('extractor_${m.name}')),
                  ),
                )
                .toList(),
            onChanged: checking
                ? null
                : (value) {
                    if (value != null) setState(() => extractorMode = value);
                  },
          ),
          SwitchListTile(
            title: Text(t('impersonation')),
            value: allowImpersonation,
            onChanged: checking
                ? null
                : (v) => setState(() => allowImpersonation = v),
          ),
          SwitchListTile(
            title: Text(t('formatFallback')),
            value: allowFormatFallback,
            onChanged: checking
                ? null
                : (v) => setState(() => allowFormatFallback = v),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(t('advancedHint')),
          ),
        ],
      ),
      ExpansionTile(
        title: Text(t('engineHealth')),
        children: [
          if (health != null)
            Text(
              'yt-dlp ${health!.version}${health!.latest == null ? '' : ' · ${t('latest')}: ${health!.latest}'}',
              textDirection: TextDirection.ltr,
            ),
          if (health?.outdatedAt(DateTime.now()) == true) Text(t('engineOld')),
          if (health?.latest != null && !health!.outdatedAt(DateTime.now()))
            Text(t('engineCurrent')),
          if (updateFailed) Text(t('updateFailed')),
          TextButton(
            onPressed: checkingUpdate ? null : _checkUpdate,
            child: Text(t('checkUpdate')),
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !working,
    child: Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/brand/vidora-logo.png', width: 36, height: 36),
            const SizedBox(width: 10),
            Text(t('app')),
          ],
        ),
        actions: [
          IconButton(
            onPressed: widget.onTheme,
            tooltip: t('theme'),
            icon: const Icon(Icons.brightness_6_outlined),
          ),
          IconButton(
            onPressed: showAbout,
            tooltip: t('about'),
            icon: const Icon(Icons.info_outline),
          ),
          IconButton(
            onPressed: showSupport,
            tooltip: t('support'),
            icon: const Icon(Icons.favorite_outline),
          ),
          DropdownButton<String>(
            key: const ValueKey('language-selector'),
            value: widget.language,
            items: languages.entries
                .map(
                  (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) widget.onLanguage(v);
            },
          ),
          const SizedBox(width: 24),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(t('privacy')),
              if (health?.outdatedAt(DateTime.now()) == true)
                Text(t('engineOld')),
              ExpansionTile(
                title: Text(t('connection')),
                subtitle: Text(t(connectionMode.name)),
                children: [
                  DropdownButtonFormField<ConnectionMode>(
                    initialValue: connectionMode,
                    items: ConnectionMode.values
                        .map(
                          (m) => DropdownMenuItem(
                            value: m,
                            child: Text(t(m.name)),
                          ),
                        )
                        .toList(),
                    onChanged: checking
                        ? null
                        : (m) {
                            if (m != null) setState(() => connectionMode = m);
                          },
                  ),
                  if ([
                    ConnectionMode.custom,
                    ConnectionMode.automatic,
                  ].contains(connectionMode))
                    TextField(
                      controller: proxyInput,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        labelText: t('proxyAddress'),
                        hintText: 'http://127.0.0.1:12334',
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(t('proxyHint')),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: input,
                onChanged: linkChanged,
                minLines: 3,
                maxLines: 5,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: t('link'),
                  border: const OutlineInputBorder(),
                ),
              ),
              ...advancedSettings(),
              ExpansionTile(
                title: Text(t('cookies')),
                subtitle: Text(
                  cookiePath == null ? t('noCookies') : p.basename(cookiePath!),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(t('cookiesHelp')),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: checking
                            ? null
                            : () async {
                                final file = await openFile(
                                  acceptedTypeGroups: [
                                    const XTypeGroup(
                                      label: 'Netscape cookies',
                                      extensions: ['txt'],
                                    ),
                                  ],
                                );
                                if (file != null && mounted)
                                  setState(() => cookiePath = file.path);
                              },
                        icon: const Icon(Icons.file_open),
                        label: Text(t('chooseCookies')),
                      ),
                      if (cookiePath != null)
                        TextButton(
                          onPressed: checking
                              ? null
                              : () => setState(() => cookiePath = null),
                          child: Text(t('clearCookies')),
                        ),
                    ],
                  ),
                  ExpansionTile(
                    title: Text(t('cookiesGuideTitle')),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Text(t('cookiesGuide')),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: checking ? null : inspect,
                icon: checking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: Text(t('inspect')),
              ),
              OutlinedButton.icon(
                onPressed: checking || !queueReady ? null : addBatch,
                icon: const Icon(Icons.playlist_add),
                label: Text(t('addBatch')),
              ),
              if (inspectionLogId != null)
                TextButton(
                  onPressed: () => showLog(inspectionLogId!),
                  child: Text(t('log')),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    t(error!.name),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (video != null) ...[
                const SizedBox(height: 20),
                Text(
                  video!.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: video!.thumbnailBytes != null
                        ? Image.memory(
                            video!.thumbnailBytes!,
                            height: 220,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Text(t('noPreview')),
                          )
                        : SizedBox(
                            height: 100,
                            child: Center(child: Text(t('noPreview'))),
                          ),
                  ),
                ),
                DropdownButtonFormField<Quality>(
                  key: ValueKey(video),
                  initialValue: quality,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: t('quality')),
                  items: video!.qualities
                      .map(
                        (q) => DropdownMenuItem(
                          value: q,
                          child: Text(
                            '${q.height > 0 ? '${q.height}p' : t('auto')} · ${q.ext} · ${q.id}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (q) => setState(() {
                    quality = q;
                    if (!q!.containers.contains(format)) format = 'mkv';
                  }),
                ),
                if (quality != null)
                  Text(
                    sizeLabel(quality!),
                    key: const ValueKey('download-size'),
                  ),
                Text(t('sizeHint')),
                if (quality?.needsMerge == true) Text(t('merge')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey((quality, format)),
                  initialValue: format,
                  decoration: InputDecoration(labelText: t('format')),
                  items: (quality?.containers ?? ['mkv', 'mp4'])
                      .map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text(s.toUpperCase()),
                        ),
                      )
                      .toList(),
                  onChanged: (s) => setState(() => format = s!),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final f = await getDirectoryPath();
                    if (f != null && mounted) setState(() => folder = f);
                  },
                  icon: const Icon(Icons.folder_open),
                  label: Text(folder ?? t('folder')),
                ),
                FilledButton.icon(
                  onPressed:
                      closing ||
                          !queueReady ||
                          folder == null ||
                          quality == null
                      ? null
                      : () {
                          setState(
                            () => jobs.add(
                              Job(video!, quality!, format, folder!),
                            ),
                          );
                          unawaited(_saveQueue().then((_) => pump()));
                        },
                  icon: const Icon(Icons.download),
                  label: Text(t('download')),
                ),
              ],
              const SizedBox(height: 28),
              Text(t('queue'), style: Theme.of(context).textTheme.titleLarge),
              if (persistenceFailed) Text(t('queueSaveFailed')),
              if (jobs.any(
                (j) =>
                    j.restored && j.state != 'done' && j.state != 'cancelled',
              ))
                Text(t('restoredHint')),
              if (jobs.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(t('empty')),
                ),
              ...jobs.map(
                (j) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(j.video.title),
                        Text(
                          '${t(j.state)} · ${j.actualHeight ?? j.quality.height}p · ${j.format} · ${t('attempt')} ${j.attempt}',
                        ),
                        if ([
                          'running',
                          'retrying',
                          'checking',
                        ].contains(j.state)) ...[
                          LinearProgressIndicator(value: j.progress),
                          Text(
                            '${(j.progress * 100).toStringAsFixed(1)}% · ${j.speed}',
                          ),
                        ],
                        if (j.state == 'failed' && j.error != null)
                          Text(t(j.error!.name)),
                        Wrap(
                          spacing: 8,
                          children: [
                            if ([
                              'waiting',
                              'running',
                              'retrying',
                              'checking',
                              'paused',
                              'failed',
                            ].contains(j.state))
                              TextButton(
                                onPressed: j.cancelled ? null : () => cancel(j),
                                child: Text(t('cancel')),
                              ),
                            if ([
                              'waiting',
                              'running',
                              'retrying',
                              'checking',
                            ].contains(j.state))
                              TextButton(
                                onPressed: j.paused ? null : () => pause(j),
                                child: Text(t('pause')),
                              ),
                            if ([
                              'failed',
                              'cancelled',
                              'paused',
                            ].contains(j.state))
                              TextButton(
                                onPressed: () => retry(j),
                                child: Text(
                                  t(j.state == 'paused' ? 'resume' : 'retry'),
                                ),
                              ),
                            TextButton(
                              onPressed: () => showLog(j.id),
                              child: Text(t('log')),
                            ),
                            if (j.state == 'done')
                              TextButton(
                                onPressed: () async {
                                  try {
                                    await engine.openFolder(j.folder);
                                  } catch (_) {
                                    if (mounted)
                                      setState(() => error = Failure.storage);
                                  }
                                },
                                child: Text(t('open')),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
