# Changelog

## 0.1.10 — 2026-10-06

- Read Aparat's current public player API and offer its MP4 and HLS qualities after the site's embed-page change.
- Bundle the Aparat extractor on each platform and enable only the app's own plugin directory.
- Show login/password restrictions clearly, including Vimeo's login-required response.
- Verify full Aparat and Dailymotion downloads with the app engine, with audio and video checked by FFprobe.

## 0.1.9 — 2026-10-06

- Preserve the macOS window size when attaching Flutter so the app opens with a visible interface; check window dimensions in the native launch smoke test.
- Shorter, clearer interface text and guides in all four languages.
- Versioned macOS/Linux packages and a Windows build kit with bundled download tools.
- Windows packaging checks runtime hashes and includes the Visual Studio redistributable files.
- macOS packaging preserves the JIT entitlement needed by Deno and sends Quit through download cleanup.
- Stop the complete Unix download process tree, including descendants that ignore TERM, and prevent new work while closing.
- Download silent streams without requiring a nonexistent audio track; use the inspected audio format for both merging and size estimates.
- Offer WebM only for compatible streams and reset incompatible output choices when quality changes.
- Display known, estimated and unknown download sizes in all four interface languages.
- Add process cancellation, format compatibility, UI and local yt-dlp/FFmpeg download regression tests.

## 0.1.8
- Replace the cookie help's chat-specific warning with an expandable, translated guide for exporting Netscape cookies using Get cookies.txt LOCALLY.
- Add a public support page with network-specific address QR codes and a custom GitHub Sponsor link.
- Connect the app's support button to the public page and simplify support text across languages.
- Use Zolfaghari in non-Persian author credits.

## 0.1.7
- Default to English while retaining Persian, Arabic and Chinese, including RTL.
- Add a translated About dialog naming author Zolfaghari, with an optional support invitation and direct support action.
- Add Arabic and Chinese README files and language navigation across all four READMEs.

## 0.1.6
- Move the full project into the Vidora Git checkout with build/privacy/support documentation.
- Add independent USDT/BSC and TRX/TRON support cards and copy buttons.
- Migrate stock legacy support configuration while preserving custom lists and disabled state.

## 0.1.5
- Activate the owner-provided USDT/BSC receiving address.
- Validate wallet display/copy and configuration upgrades.

## 0.1.4
- Adopt Vidora branding/logo and add the optional support dialog.

## 0.1.3
- Automatically inspect pasted links, download thumbnails through the selected route and show quality size estimates including audio.

## 0.1.2
- Add optional site-scoped Netscape cookies and temporary authentication cleanup.

## 0.1.1
- Add system/direct/custom proxy modes and clearer network/anti-bot errors.

## 0.1.0
- Initial local desktop downloader with multilingual UI, download queue and FFmpeg merging.
