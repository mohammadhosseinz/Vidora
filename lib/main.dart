import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:file_selector/file_selector.dart';
import 'engine.dart';
import 'strings.dart';
import 'support.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path/path.dart' as p;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setPreventClose(true);
  await windowManager.setTitle('Vidora');
  runApp(const LocalVideoApp());
}

class LocalVideoApp extends StatefulWidget {
  final DesktopEngine? engine;
  const LocalVideoApp({super.key, this.engine});
  @override
  State<LocalVideoApp> createState() => _AppState();
}

class _AppState extends State<LocalVideoApp> {
  String language = 'en';
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
    home: Home(
      engine: widget.engine,
      language: language,
      onLanguage: (v) => setState(() => language = v),
    ),
  );
}

class Job {
  final String id, folder, format;
  final Video video;
  final Quality quality;
  String state = 'waiting', speed = '';
  Failure? error;
  double progress = 0;
  bool cancelled = false;
  Job(this.video, this.quality, this.format, this.folder)
    : id = DateTime.now().microsecondsSinceEpoch.toString();
}

class Home extends StatefulWidget {
  final DesktopEngine? engine;
  final String language;
  final ValueChanged<String> onLanguage;
  const Home({
    super.key,
    required this.language,
    required this.onLanguage,
    this.engine,
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
    super.dispose();
  }

  @override
  Future<void> onWindowClose() async {
    if (closing) return;
    setState(() => closing = true);
    previewTimer?.cancel();
    for (final j
        in jobs
            .where((j) => ['waiting', 'running'].contains(j.state))
            .toList()) {
      await cancel(j);
    }
    // Download finally blocks remove temporary files before destroying the UI.
    while (working) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await engine.shutdown();
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
      video = null;
      quality = null;
    });
    try {
      engine.connection = ConnectionOptions(
        mode: connectionMode,
        proxy: proxyInput.text.trim(),
      );
      engine.cookieFile = cookiePath;
      final v = await engine.inspect(inspectedLink);
      if (mounted && input.text.trim() == inspectedLink)
        setState(() {
          video = v;
          quality = v.qualities.first;
          if (!quality!.containers.contains(format)) format = 'mkv';
        });
    } on EngineException catch (e) {
      if (mounted && input.text.trim() == inspectedLink)
        setState(() => error = e.reason);
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

  Future<void> pump() async {
    if (working || closing) return;
    working = true;
    while (!closing && jobs.any((j) => j.state == 'waiting')) {
      final j = jobs.firstWhere((j) => j.state == 'waiting');
      setState(() => j.state = 'running');
      try {
        await engine.download(j.video, j.quality, j.format, j.folder, j.id, (
          p,
        ) {
          if (mounted)
            setState(() {
              j.progress = p.fraction;
              j.speed = p.speed;
            });
        });
        if (mounted)
          setState(() {
            j.state = 'done';
            j.progress = 1;
          });
      } on EngineException catch (e) {
        if (mounted)
          setState(() {
            j.state = j.cancelled ? 'cancelled' : 'failed';
            j.error = e.reason;
          });
      } catch (_) {
        if (mounted)
          setState(() {
            j.state = j.cancelled ? 'cancelled' : 'failed';
            j.error = Failure.extraction;
          });
      }
    }
    working = false;
  }

  Future<void> cancel(Job j) async {
    setState(() => j.cancelled = true);
    if (j.state == 'waiting') {
      setState(() => j.state = 'cancelled');
      return;
    }
    await engine.cancel(j.id);
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
                  if (connectionMode == ConnectionMode.custom)
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
                  onPressed: closing || folder == null || quality == null
                      ? null
                      : () {
                          setState(
                            () => jobs.add(
                              Job(video!, quality!, format, folder!),
                            ),
                          );
                          unawaited(pump());
                        },
                  icon: const Icon(Icons.download),
                  label: Text(t('download')),
                ),
              ],
              const SizedBox(height: 28),
              Text(t('queue'), style: Theme.of(context).textTheme.titleLarge),
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
                          '${t(j.state)} · ${j.quality.height}p · ${j.format}',
                        ),
                        if (j.state == 'running') ...[
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
                            if (['waiting', 'running'].contains(j.state))
                              TextButton(
                                onPressed: j.cancelled ? null : () => cancel(j),
                                child: Text(t('cancel')),
                              ),
                            if (['failed', 'cancelled'].contains(j.state))
                              TextButton(
                                onPressed: () {
                                  setState(
                                    () => jobs.add(
                                      Job(
                                        j.video,
                                        j.quality,
                                        j.format,
                                        j.folder,
                                      ),
                                    ),
                                  );
                                  unawaited(pump());
                                },
                                child: Text(t('retry')),
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
