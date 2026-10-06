# Validation

## 0.1.10 — Linux x64 packages, 2026-10-06

- Kept the application version at `0.1.10+11`. Built the Linux x64 DEB and portable archive with the Aparat extractor included.
- Ubuntu 22.04 amd64 in Docker on the Apple Silicon host, with Flutter 3.41.2: `flutter analyze --no-pub` reported no issues; all 33 tests passed with the actual bundled download tools and a local H.264/AAC fixture. The separate public-network test remained skipped.
- The release build completed successfully after retrying a Dart file-copy `EINTR` error in the emulated build environment.
- Installed the DEB and checked its version, architecture, runtime dependencies and binary/plugin contents. The installed app rendered its interface in a visible 1280×720 window under Xvfb; its screenshot was inspected.
- The actual `DesktopEngine` using the installed app's tools inspected the user's Aparat URL `https://www.aparat.com/v/spy285j`, found 12 qualities and its thumbnail, and downloaded the complete 120.4-second video. FFprobe confirmed H.264 video and AAC audio.
- Checked the installed runtime binaries against the pinned SHA-256 manifest and compared the portable archive's app, runtime tools and plugin with the installed package. Both package checksums are recorded in `dist/SHA256SUMS.txt`. No native physical Linux machine was used for these checks.

## 0.1.10 — live service checks, 2026-10-06

- Reproduced the original Aparat failure with the bundled yt-dlp 2026.08.19: its retired embed-page parser could not extract the title. The latest stable upstream version was already bundled.
- Added a packaged extractor for Aparat's current public player API. Only the app's packaged plugin directory is enabled; Python bytecode writing is disabled so imports do not modify the signed app bundle.
- Four Python extractor regression tests passed. `flutter analyze --no-pub` reported no issues. All 33 Flutter tests passed; the separate public-network test remained skipped. Local fixture encoding used the developer's Homebrew FFmpeg for VP9/Opus; the download engine still used the actual packaged yt-dlp/FFmpeg tools.
- The user's Aparat URL `https://www.aparat.com/v/spy285j` passed inspection and a complete download through `DesktopEngine`: 120.4 seconds, H.264 video and AAC audio. Two other public Aparat videos (`wP8On`, `mhe5h12`) passed 10-second sample downloads and stream checks.
- Dailymotion `https://www.dailymotion.com/video/x5e9eog` passed inspection and a complete 242.4-second download through `DesktopEngine`, with H.264 video and AAC audio.
- YouTube `https://www.youtube.com/watch?v=aqz-KE-bpKQ` passed inspection through `DesktopEngine` with 37 video qualities and its thumbnail. A sample merge encountered HTTP 403; a later native attempt returned the service's sign-in/anti-bot requirement. Successful YouTube downloading is not claimed for this network/session.
- Vimeo `https://vimeo.com/1084537` required login; its public player URL returned HTTP 401. These restrictions are now classified as restricted access rather than a generic extraction error. No personal cookies or account credentials were used for these service checks.
- The outdated upstream Aparat fixture `8dflw` is now gone (the current API returns HTTP 410); it is not counted as a successful service test.
- Rebuilt and installed the 0.1.10 macOS DMG. Its native window/Quit smoke test passed (1080×768), and its interface rendered correctly. `DesktopEngine` using the installed app's tools found 12 qualities and the thumbnail for the user's Aparat link. Strict/deep signing verification still passed after extraction, with no Python bytecode added to the signed resources.
- Native UI automation could not deliver text/button actions reliably to the Flutter form, so an automated GUI inspection/download flow is not claimed. The full download and stream checks above ran through the actual app engine.
- The Windows 0.1.10 build kit includes the new extractor and updated packaging code. Linux 0.1.10 packages were subsequently rebuilt and checked as recorded above.

## 0.1.9 — macOS window correction, 2026-10-06

- Reproduced the reported missing window: the standalone runner's content was 1×0 points after attaching `FlutterViewController`. The earlier process/Quit check did not detect this.
- Restored the saved window frame after attaching the controller, matching `MainFlutterWindow` in the Xcode runner.
- Extended `--smoke-test-close` to fail for a hidden window or content smaller than 640×500. The original runner failed this check; the corrected runner passed with 1080×766 points and exited normally through Flutter cleanup.
- Inspected the corrected app with native accessibility and a screenshot on the user's Apple Silicon Mac: the video URL field, connection selector, cookie controls and download queue were visible.
- Rebuilt the DMG, verified its image checksums and strict/deep app signature, installed its app in `/Applications/Vidora.app`, and repeated both the native window/Quit check and visual inspection successfully. The corrected installer is also named `Vidora-macOS-arm64-0.1.9-fixed.dmg`.

## 0.1.9 — 2026-10-06, packaging and copy

- Rewrote interface text and the four language guides. `flutter analyze` reported no issues. The default suite passed 29 tests with three opt-in tests skipped.
- Ubuntu 22.04 x64 in Docker on the Apple Silicon host: all 31 tests passed with the real bundled yt-dlp/FFmpeg tools and a local H.264/AAC fixture. Only the public-site smoke test was skipped. Tests covered silent video, DASH merging, WebM, cookies, cancellation and all four UI languages.
- Native Linux release compiled successfully. Its window rendered at 1280×720 under Xvfb; the screenshot was inspected. The DEB installed successfully and the installed app binary matched the release bundle. The installed window and bundled Deno were also exercised.
- Native macOS arm64 release compiled with Flutter 3.41.2 and Apple Command Line Tools. The bundled runtime cookie test passed all six tests. The app launched without a startup error; the native Quit smoke test exited normally through the Flutter cleanup handler.
- macOS signing verification and DMG checksums passed. The mounted DMG's yt-dlp and Deno ran successfully; FFmpeg links only Apple system libraries. Packages use ad-hoc signatures, without Developer ID or notarization. The macOS screenshot automation service was unavailable, so macOS visual inspection was not automated.
- Windows x64 kit: pinned upstream downloads and all executable hashes were checked, and the ZIP passed CRC checks. The kit includes source, runtime tools, a build command and Persian instructions. The 0.1.9 Windows EXE must be compiled and tested on Windows; it was not built on this Mac.
- Public video sites and JavaScript extraction were not tested. The packages have not been published.

## 2026-10-06 — download regression fixes on macOS arm64

- Flutter 3.41.2 / Dart 3.11.0: `flutter analyze --no-pub` reported no issues; formatting and `git diff --check` passed.
- `flutter test --no-pub`: 31 tests passed; the external-network smoke test was skipped. Local engine tests were enabled.
- Real local downloads used Python-installed yt-dlp 2026.07.04 and Homebrew FFmpeg. The temporary Deno placeholder was not used; JavaScript extraction and real source websites were not exercised.
- The original engine was run separately from the unmodified Git revision: explicit silent-stream metadata failed because of mandatory `+bestaudio`; H.264/AAC to WebM failed; cancellation left a TERM-resistant child/grandchild alive and the download future pending.
- Fixed-code tests verified silent MP4 output, local DASH audio/video merging and compatible WebM downloads, with FFprobe checking the resulting streams and no remaining download temp directories.
- Unix cancellation tests verified that TERM-resistant descendants stopped, inherited output pipes closed and temporary output directories were removed.
- UI tests verified exact/estimated/unknown size labels across Persian, Arabic, English and Chinese, and resetting a WebM selection when switching to incompatible quality.
- The regression checks above preceded native packaging; packaging results are recorded in the 0.1.9 section.

## 2026-10-05 — Windows x64

Checked from the new Vidora checkout on Windows x64 using Flutter 3.41.2 / Dart 3.11.0.

- Version 0.1.7: 22 automated tests passed; the separate live-network download smoke test was skipped.
- Real standalone yt-dlp was used with developer-owned local fixtures for cookie read/write and thumbnail inspection tests.
- English default, translated About/author/support invitation, support navigation and RTL/LTR directions were checked in all four languages.
- Both support cards displayed their exact currency/network/address, and each copy button copied its own address.
- Stock legacy configuration migration, custom configuration preservation and disabled support were checked.
- `flutter analyze --no-pub`: no issues.
- Native Windows release build and Inno installer compilation passed. The portable ZIP passed CRC checks, contained both exact receiving addresses and included MIT/dependency notices. Its app binary matched the build output. Logs remain in ignored `work/`.
- No real donation transaction or ownership verification was performed.
- Native macOS/Linux builds and the new GitHub Actions workflow have not been run here.

Runtime binaries, local package outputs and test logs are excluded from Git. The source checkout retains dependency notices/manifests. See `THIRD_PARTY_NOTICES.md` for the source requirements of each bundled FFmpeg build.
