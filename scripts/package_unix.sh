#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
target="${1:?Usage: package_unix.sh macos|linux}"
case "$target" in macos|linux) ;; *) exit 2 ;; esac
flutter_bin="${FLUTTER_BIN:-flutter}"
version="$(sed -n 's/^version: \([^+]*\).*/\1/p' pubspec.yaml)"
for name in yt-dlp ffmpeg ffprobe deno; do
  test -x "runtime/$target/$name" || { echo "Missing executable runtime/$target/$name"; exit 1; }
done
if [ "${2:-}" = --no-build ]; then
  echo "Packaging the existing release build"
elif [ "$target" = macos ] && ! xcodebuild -version >/dev/null 2>&1; then
  FLUTTER_BIN="$flutter_bin" python3 scripts/build_macos_cli.py
else
  "$flutter_bin" pub get --enforce-lockfile
  "$flutter_bin" build "$target" --release --no-pub
fi
mkdir -p dist
if [ "$target" = macos ]; then
  arch="${MACOS_ARCH:-$(uname -m)}"
  app="build/macos/Build/Products/Release/Vidora.app"
  cp LICENSE THIRD_PARTY_NOTICES.md README*.md "$app/Contents/Resources/"
  python3 - "$app/Contents/MacOS/tools" <<'PY'
import pathlib, shutil, sys
tools = pathlib.Path(sys.argv[1])
if tools.exists(): shutil.rmtree(tools)
PY
  mkdir -p "$app/Contents/MacOS/tools"
  cp runtime/macos/yt-dlp runtime/macos/ffmpeg runtime/macos/ffprobe runtime/macos/deno "$app/Contents/MacOS/tools/"
  mkdir -p "$app/Contents/Resources/tools/licenses"
  mkdir -p "$app/Contents/Resources/tools/plugins"
  cp -R packaging/yt-dlp-plugins/. "$app/Contents/Resources/tools/plugins/"
  # Keep Python source in Resources; MacOS/tools contains signed executables.
  ln -s ../../Resources/tools/plugins "$app/Contents/MacOS/tools/plugins"
  cp runtime/macos/manifest.json "$app/Contents/Resources/tools/"
  cp -R runtime/macos/licenses/. "$app/Contents/Resources/tools/licenses/"
  cp assets/fonts/*OFL.txt "$app/Contents/Resources/tools/licenses/"
  identity="${CODESIGN_IDENTITY:--}"
  signing_options=(--options runtime)
  # Ad-hoc signatures have no Team ID and cannot satisfy hardened library validation.
  if [ "$identity" = - ]; then signing_options=(--options 0); fi
  for name in yt-dlp ffmpeg ffprobe; do
    codesign --force --sign "$identity" "${signing_options[@]}" "$app/Contents/MacOS/tools/$name"
  done
  codesign --force --sign "$identity" "${signing_options[@]}" --entitlements packaging/deno.entitlements "$app/Contents/MacOS/tools/deno"
  for framework in "$app"/Contents/Frameworks/*.framework; do
    codesign --force --sign "$identity" "${signing_options[@]}" "$framework"
  done
  # Signing changes Mach-O hashes. Record the shipped binaries before sealing the app.
  python3 - "$app/Contents/MacOS/tools" "$app/Contents/Resources/tools/manifest.json" <<'PY'
import hashlib, json, pathlib, sys
tools = pathlib.Path(sys.argv[1])
path = pathlib.Path(sys.argv[2])
manifest = json.loads(path.read_text())
for name in ('yt-dlp', 'ffmpeg', 'ffprobe', 'deno'):
    manifest[name]['stagedSha256'] = manifest[name]['sha256']
    manifest[name]['sha256'] = hashlib.sha256((tools / name).read_bytes()).hexdigest()
path.write_text(json.dumps(manifest, indent=2))
PY
  codesign --force --sign "$identity" "${signing_options[@]}" --entitlements macos/Runner/Release.entitlements "$app"
  codesign --verify --deep --strict "$app"
  "$app/Contents/MacOS/tools/deno" eval 'if (1 + 1 !== 2) Deno.exit(1)'
  stage="$(mktemp -d)"
  trap 'rm -rf "$stage"' EXIT
  cp -R "$app" "$stage/"
  ln -s /Applications "$stage/Applications"
  hdiutil create -volname Vidora -srcfolder "$stage" -ov -format UDZO "dist/Vidora-macOS-$arch-$version.dmg"
else
  arch="$(uname -m)"
  bundle="build/linux/${arch/x86_64/x64}/release/bundle"
  if [ "$arch" = aarch64 ]; then bundle=build/linux/arm64/release/bundle; fi
  cp LICENSE THIRD_PARTY_NOTICES.md README*.md "$bundle/"
  mkdir -p "$bundle/tools"
  cp -R runtime/linux/. "$bundle/tools/"
  mkdir -p "$bundle/tools/plugins"
  cp -R packaging/yt-dlp-plugins/. "$bundle/tools/plugins/"
  mkdir -p "$bundle/tools/licenses"
  cp assets/fonts/*OFL.txt "$bundle/tools/licenses/"
  cp assets/support.json "$bundle/support.json"
  tar -C "$bundle" -czf "dist/Vidora-Linux-$arch-$version.tar.gz" .
  debarch="$(dpkg --print-architecture)"
  stage="$(mktemp -d)"
  trap 'rm -rf "$stage"' EXIT
  mkdir -p "$stage/opt/vidora" "$stage/DEBIAN" "$stage/usr/share/applications"
  # Hard links keep the temporary DEB tree small; packaging does not mutate it.
  cp -al "$bundle/." "$stage/opt/vidora/"
  printf 'Package: vidora\nVersion: %s\nArchitecture: %s\nMaintainer: Zolfaghari\nDepends: libc6 (>= 2.35), libgtk-3-0, libstdc++6 (>= 11), libglib2.0-0, libgl1, libegl1, xdg-utils, procps\nDescription: Download videos to your computer with Vidora\n' "$version" "$debarch" > "$stage/DEBIAN/control"
  printf '[Desktop Entry]\nType=Application\nName=Vidora\nIcon=vidora\nExec=/opt/vidora/local_video\nTerminal=false\nCategories=Network;AudioVideo;\n' > "$stage/usr/share/applications/vidora.desktop"
  mkdir -p "$stage/usr/share/icons/hicolor/256x256/apps"
  cp assets/brand/vidora-logo.png "$stage/usr/share/icons/hicolor/256x256/apps/vidora.png"
  dpkg-deb -Zzstd --build --root-owner-group "$stage" "dist/Vidora-Linux-$debarch-$version.deb"
fi
