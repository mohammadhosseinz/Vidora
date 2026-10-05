#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
target="${1:?Usage: package_unix.sh macos|linux}"
case "$target" in macos|linux) ;; *) exit 2 ;; esac
for name in yt-dlp ffmpeg ffprobe deno; do
  test -x "runtime/$target/$name" || { echo "Missing executable runtime/$target/$name"; exit 1; }
done
flutter build "$target" --release
mkdir -p dist
if [ "$target" = macos ]; then
  app="build/macos/Build/Products/Release/Vidora.app"
  cp LICENSE THIRD_PARTY_NOTICES.md README*.md "$app/Contents/Resources/"
  mkdir -p "$app/Contents/MacOS/tools"
  cp -R runtime/macos/. "$app/Contents/MacOS/tools/"
  mkdir -p "$app/Contents/MacOS/tools/licenses"
  cp assets/fonts/*OFL.txt "$app/Contents/MacOS/tools/licenses/"
  # Sign nested binaries first; real distribution uses Developer ID and notarization.
  for name in yt-dlp ffmpeg ffprobe deno; do
    codesign --force --sign "${CODESIGN_IDENTITY:--}" --options runtime "$app/Contents/MacOS/tools/$name"
  done
  codesign --force --deep --sign "${CODESIGN_IDENTITY:--}" --options runtime "$app"
  stage="$(mktemp -d)"
  cp -R "$app" "$stage/"
  ln -s /Applications "$stage/Applications"
  hdiutil create -volname Vidora -srcfolder "$stage" -ov -format UDZO dist/Vidora-macOS.dmg
  rm -r "$stage"
else
  arch="$(uname -m)"
  bundle="build/linux/${arch/x86_64/x64}/release/bundle"
  if [ "$arch" = aarch64 ]; then bundle=build/linux/arm64/release/bundle; fi
  cp LICENSE THIRD_PARTY_NOTICES.md README*.md "$bundle/"
  mkdir -p "$bundle/tools"
  cp -R runtime/linux/. "$bundle/tools/"
  mkdir -p "$bundle/tools/licenses"
  cp assets/fonts/*OFL.txt "$bundle/tools/licenses/"
  cp assets/support.json "$bundle/support.json"
  tar -C "$bundle" -czf "dist/Vidora-Linux-$arch.tar.gz" .
  # Debian package includes Flutter's shared library, engines, and GTK dependencies.
  debarch="$(dpkg --print-architecture)"
  stage="$(mktemp -d)"
  mkdir -p "$stage/opt/local-video" "$stage/DEBIAN" "$stage/usr/share/applications"
  cp -R "$bundle/." "$stage/opt/local-video/"
  printf 'Package: local-video\nVersion: 0.1.7\nArchitecture: %s\nMaintainer: Vidora Developers\nDepends: libgtk-3-0, libstdc++6, libglib2.0-0, xdg-utils, procps\nDescription: Local Flutter video downloader\n' "$debarch" > "$stage/DEBIAN/control"
  printf '[Desktop Entry]\nType=Application\nName=Vidora\nIcon=vidora\nExec=/opt/local-video/local_video\nTerminal=false\nCategories=Network;AudioVideo;\n' > "$stage/usr/share/applications/local-video.desktop"
  mkdir -p "$stage/usr/share/icons/hicolor/256x256/apps"
  cp assets/brand/vidora-logo.png "$stage/usr/share/icons/hicolor/256x256/apps/vidora.png"
  dpkg-deb --build "$stage" "dist/Vidora-Linux-$debarch.deb"
  rm -r "$stage"
fi
