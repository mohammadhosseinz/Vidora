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

Output: `dist/Vidora-Setup-Windows-x64-0.1.10.exe` and `dist/Vidora-Windows-x64-0.1.10.zip`. The Windows build kit includes the engines; a fresh Git clone does not. Do not download unofficial replacement engines based on links supplied by end users.

The portable Windows build kit can be taken to another computer. Follow [the Persian Windows guide](../WINDOWS-BUILD.fa.md) and run `build_windows.cmd`. The script checks engine hashes, runs analysis/tests, finds the MSVC redistributable DLLs in Visual Studio and creates the installer with Inno Setup.

## macOS (build on macOS)

```sh
python3 scripts/prepare_runtime.py --platform macos --arch arm64 --ffmpeg-dir /path/to/static-ffmpeg/bin --ffmpeg-notices /path/to/notices
flutter pub get
bash scripts/package_unix.sh macos
```

Use `--arch x64` with Intel binaries for Intel Macs. Output: `dist/Vidora-macOS-arm64-0.1.10.dmg` for Apple Silicon. When only Apple Command Line Tools are available, `build_macos_cli.py` builds the current Swift plugins and a programmatic window runner. With full Xcode, the normal Flutter build is used. The script defaults to ad-hoc signing; public distribution needs Developer ID signing, notarization and native testing. The runner disables sandboxing to execute the packaged local engines.

```sh
CODESIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' bash scripts/package_unix.sh macos
xcrun notarytool submit dist/Vidora-macOS-arm64-0.1.10.dmg --keychain-profile YOUR_PROFILE --wait
xcrun stapler staple dist/Vidora-macOS-arm64-0.1.10.dmg
```

## Linux (build on Debian/Ubuntu)

```sh
python3 scripts/prepare_runtime.py --platform linux --arch x64 --ffmpeg-dir /path/to/static-ffmpeg/bin --ffmpeg-notices /path/to/notices
flutter pub get
bash scripts/package_unix.sh linux
sudo apt install ./dist/Vidora-Linux-amd64-0.1.10.deb
```

Use `--arch arm64` with ARM64 binaries when appropriate. The packaged x64 build requires glibc 2.35 or newer. Outputs: DEB and portable tar.gz under `dist/`. The x64 package targets Ubuntu 22.04 or newer and Debian 12 or newer. The Debian package declares GTK/system dependencies; yt-dlp includes its Python runtime; the media engines are bundled.

## Tests

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

To enable real local engine tests, use a developer-owned short H.264/AAC MP4 fixture with both video and audio. Fixture generation needs FFmpeg's `libvpx-vp9` and `libopus` encoders. If your packaged FFmpeg lacks these encoders, set `FIXTURE_FFMPEG` to a developer FFmpeg with them; inspection, downloads and remuxing still use the packaged tools:

```powershell
$env:LOCAL_VIDEO_TOOLS = (Resolve-Path runtime/windows).Path
$env:COOKIE_TEST_VIDEO = 'C:/path/to/fixture.mp4'
flutter test
```

On macOS/Linux, set the same variables for your native tools and fixture:

```sh
LOCAL_VIDEO_TOOLS=/absolute/path/to/tools COOKIE_TEST_VIDEO=/absolute/path/to/fixture.mp4 flutter test
```

These tests use a localhost HTTP fixture and standalone yt-dlp. This test server is not an application backend. A separate opt-in live-network smoke test uses `TEST_VIDEO_URL` and optionally `TEST_CONNECTION=direct`; it downloads the supplied video.

The Aparat extractor also has offline Python regression tests. Install the pinned yt-dlp Python package in your developer environment and run:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s test -p '*_plugin_test.py'
```

## Engine updates
Update the pinned yt-dlp/Deno versions through `scripts/prepare_runtime.py`, review their notices, verify digests, test inspection/download/merging/cancellation and replace the full engine set in each native package. Never update silently while jobs run. `--ignore-config`, disabled default plugin directories/remote components and safe argv-based process execution are deliberate. The app enables only `tools/plugins` when it is packaged. The reviewed Aparat extractor lives in `packaging/yt-dlp-plugins` and each packaging script copies it into the bundle. Python bytecode writing is disabled to preserve the signed app resources.

## Public release requirements
Supply the source/build information required by each FFmpeg build before publishing its binary packages. Include all dependency notices, sign installers as appropriate and run native macOS/Linux smoke tests. Local packages are not signed public releases. See `THIRD_PARTY_NOTICES.md` for the FFmpeg builds and source requirements.
