# Third-party licenses and runtime distribution

The repository's MIT LICENSE applies to Vidora's own source. Dependencies and bundled components retain their respective terms.

- Flutter/Dart and packages: package notices are included by Flutter in the compiled app.
- Noto Arabic and Chinese fonts: SIL Open Font License files are in `assets/fonts/`.
- yt-dlp standalone executable: upstream license and bundled Python/EJS/other dependency notices in `runtime/windows/licenses/`.
- Deno: MIT notice in `runtime/windows/licenses/`.
- Local FFmpeg/FFprobe 7.1 build: GPLv3, with build/readme/license notes under `runtime/windows/licenses/` and engine hashes in `runtime/windows/manifest.json`.

FFmpeg's GPL build requires appropriate complete corresponding source for FFmpeg and linked libraries when distributing binaries. The current runtime build notices/source pointers do not yet complete that public distribution requirement. Resolve it before publishing installers/portable archives to a public release. Runtime binaries and local archives are deliberately excluded from Git.

References:
- https://ffmpeg.org/legal.html
- https://github.com/yt-dlp/yt-dlp
- https://github.com/yt-dlp/yt-dlp/wiki/EJS
- https://github.com/denoland/deno

No browser cookies, payment secrets, app accounts or user media are distributed with this source.
