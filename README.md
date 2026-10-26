# Vidora — ویدورا

<img src="assets/brand/vidora-logo.png" width="144" alt="Vidora logo">

Paste a video link, pick a quality and save it to your computer. Vidora supports Persian, Arabic, English and Chinese, with right-to-left layouts for Persian and Arabic.

[فارسی](README.fa.md) · [العربية](README.ar.md) · [中文](README.zh.md)

## Using Vidora

1. Paste a link and click **Inspect link**.
2. Choose a quality, file format and destination folder.
3. Start the download. You can queue more videos, pause, resume, cancel or retry a download. The queue is restored after restarting the app; click Resume to continue.

The app shows the title, thumbnail, available qualities and download size when the site provides it. Separate audio and video tracks are saved together in one file. WebM is available when the selected tracks support it.

Videos are saved on your device. There is no Vidora account or storage server. The app connects to the source site to inspect and download the video. Cookies are optional; choose a local cookies.txt file when a site needs your signed-in session. See the [cookie guide](docs/COOKIES.fa.md).

Some links may stop working after a site changes. Private videos, expired links, regional restrictions and DRM can also prevent a download. Cookies do not make every video downloadable.

## Download controls

Paste several links, one per line, and choose **Inspect and queue all links**. Each link is checked independently; a failed link does not stop the rest. Resume support depends on the source server and unchanged media streams. Cancel removes partial files; Pause and failed attempts keep them beside the destination in a hidden job folder.

Site profiles cover Aparat, YouTube, Instagram, X/Twitter, TikTok, Facebook and Vimeo. They supplement yt-dlp's extractors; other sites still use yt-dlp. Site hints describe possible session requirements, not guaranteed restrictions on a particular link.

**Advanced settings** accepts headers, User-Agent, Referer, a format selector and extractor behavior. Connection settings support a configured fallback proxy in automatic mode. Settings apply when the link is inspected and stay attached to that queue entry. A custom format selector overrides the quality dropdown. Equal/lower-quality fallback is optional and off by default.

Use **Log** on a queue entry or failed inspection to copy/export diagnostics. Logs remove URLs and sensitive header/session information; each log keeps up to roughly 1 MB of recent output, and up to 100 logs are retained. Queue files and logs stay in the operating system's application-support directory. Cookie contents and session headers are never written into the queue; re-select them after restarting when needed.

**Engine version and health** checks the installed version locally, warns after 90 days, and can compare it with the latest official yt-dlp release on request. Update by installing a newer Vidora package; the app does not replace signed bundled executables while running. Language and light/dark theme choices are remembered.

## Install or build

Source version **0.2.0**. Local packages are written to `dist/`:

- **macOS, Apple Silicon:** open the DMG and drag Vidora into Applications.
- **Linux, x64:** install the DEB on Ubuntu/Debian, or extract the portable archive.
- **Windows, x64:** the build kit includes the source and download tools. Build it on Windows to create the EXE installer and portable ZIP.

Complete app packages include the download tools. A fresh Git clone needs those tools staged separately; they are excluded from Git. The [build guide](docs/BUILD.md) covers prerequisites, packaging and tests. Test results are recorded in [validation notes](docs/VALIDATION.md).

Vidora is built with Flutter, yt-dlp, FFmpeg and Deno. Desktop builds use Flutter **3.41.2 / Dart 3.11**. Android is not available yet.

## About and support

Developed by **Zolfaghari**. If Vidora helps you, you can support future fixes and updates from the app's heart button or the [support page](docs/SUPPORT.md). Support is optional; all features are free.

## License

Vidora's source is under the [MIT license](LICENSE). Bundled tools and fonts keep their own licenses. See [third-party notices](THIRD_PARTY_NOTICES.md).
