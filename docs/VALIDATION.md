# Validation — 2026-10-05

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

Runtime binaries, local package outputs and test logs are excluded from Git. The source checkout retains dependency notices/manifests. Complete corresponding source for the bundled GPL FFmpeg is still required before public binary distribution.
