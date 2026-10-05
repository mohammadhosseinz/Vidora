# Build and package Vidora

## Requirements
Flutter 3.41.2 (Dart 3.11) was used locally. Install the native Flutter desktop toolchain for your build host. On Windows enable Developer Mode/symlink support and install Visual Studio C++ desktop build tools. Inno Setup 6.7+ creates the per-user installer. Python 3 is a **developer-only** dependency of runtime preparation scripts.

## Stage local engines
A complete runtime directory contains `yt-dlp`, `ffmpeg`, `ffprobe`, `deno` (with `.exe` on Windows), a manifest and license notices. `prepare_runtime.py` fetches pinned standalone yt-dlp/Deno releases and verifies upstream asset SHA256 digests. Supply reviewed standalone FFmpeg/FFprobe binaries and their license/source/build information yourself.

```powershell
python scripts/prepare_runtime.py --platform windows --arch x64 --ffmpeg-dir C:/path/to/ffmpeg/bin --ffmpeg-notices C:/path/to/notices
flutter pub get
$env:LOCAL_VIDEO_TOOLS = (Resolve-Path runtime/windows).Path
flutter run -d windows
./scripts/package_windows.ps1 -Iscc C:/path/to/ISCC.exe
```

Output: `dist/Vidora-Setup-Windows-x64-0.1.6.exe` and `dist/Vidora-Windows-x64-0.1.6.zip`. The local checkout already has the Windows engines; a fresh Git clone does not. Do not download unofficial replacement engines based on links supplied by end users.

## macOS (build on macOS)

```sh
python3 scripts/prepare_runtime.py --platform macos --arch arm64 --ffmpeg-dir /path/to/static-ffmpeg/bin --ffmpeg-notices /path/to/notices
flutter pub get
bash scripts/package_unix.sh macos
```

Use `--arch x64` with Intel binaries for Intel Macs. Output: `dist/Vidora-macOS.dmg`. Native macOS builds have not been validated here. The script defaults to ad-hoc signing; public distribution needs Developer ID signing, notarization and native testing. The runner disables sandboxing to execute the packaged local engines.

```sh
CODESIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' bash scripts/package_unix.sh macos
xcrun notarytool submit dist/Vidora-macOS.dmg --keychain-profile YOUR_PROFILE --wait
xcrun stapler staple dist/Vidora-macOS.dmg
```

## Linux (build on Debian/Ubuntu)

```sh
python3 scripts/prepare_runtime.py --platform linux --arch x64 --ffmpeg-dir /path/to/static-ffmpeg/bin --ffmpeg-notices /path/to/notices
flutter pub get
bash scripts/package_unix.sh linux
sudo apt install ./dist/Vidora-Linux-amd64.deb
```

Use `--arch arm64` with ARM64 binaries when appropriate. Outputs: DEB and portable tar.gz under `dist/`. Native Linux builds and target glibc compatibility have not been validated here. The Debian package declares GTK/system dependencies; Python and media engines are bundled.

## Tests

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

To enable real local engine tests on Windows, use any developer-owned short MP4 fixture:

```powershell
$env:LOCAL_VIDEO_TOOLS = (Resolve-Path runtime/windows).Path
$env:COOKIE_TEST_VIDEO = 'C:/path/to/fixture.mp4'
flutter test
```

These tests use a localhost HTTP fixture and standalone yt-dlp. This test server is not an application backend. A separate opt-in live-network smoke test uses `TEST_VIDEO_URL` and optionally `TEST_CONNECTION=direct`; it downloads the supplied video.

## Engine updates
Update the pinned yt-dlp/Deno versions through `scripts/prepare_runtime.py`, review their notices, verify digests, test inspection/download/merging/cancellation and replace the full engine set in each native package. Never update silently while jobs run. `--ignore-config`, disabled plugins/remote components and safe argv-based process execution are deliberate.

## Public release requirements
Supply complete corresponding source/build information for the bundled GPL FFmpeg and linked libraries before publishing its binary packages. Include all dependency notices, sign installers as appropriate and run native macOS/Linux smoke tests. The present local build is a prototype, not a completed public multi-platform release.
