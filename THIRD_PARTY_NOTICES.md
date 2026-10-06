# Third-party notices

The MIT license covers Vidora's own source. The tools, libraries and fonts below keep their own licenses.

- **Flutter, Dart and packages:** their notices are available from the application's Licenses screen.
- **Noto fonts:** SIL Open Font License. Copies are included in `assets/fonts` and the packaged tool notices.
- **yt-dlp:** upstream license and bundled dependency notices are included in each runtime's `licenses` folder. Source: https://github.com/yt-dlp/yt-dlp/tree/2026.08.19
- **Deno:** MIT license, included with each runtime. Source: https://github.com/denoland/deno/tree/v2.9.7
- **macOS FFmpeg/FFprobe 9.0.2:** built locally under LGPL 2.1 or later, using Apple system frameworks. The unmodified FFmpeg source archive, license and build instructions are included with the tools.
- **Linux FFmpeg/FFprobe:** BtbN LGPL build. The upstream license and build/source references are included with the tools. Build project: https://github.com/BtbN/FFmpeg-Builds
- **Windows FFmpeg/FFprobe:** Gyan essentials build under GPLv3. Its license, build information and source references are included with the tools. Build project: https://www.gyan.dev/ffmpeg/builds/

Each runtime's `manifest.json` records tool versions, source URLs and SHA256 hashes. Runtime executables and release archives are excluded from Git.

Before publishing packages containing FFmpeg, provide the corresponding source and build information required by the chosen build's license, including linked libraries. The macOS build includes its FFmpeg source; the Windows and Linux vendor builds need their complete corresponding source gathered before a public release. These packages are prepared for local use and have not been published.

FFmpeg license information: https://ffmpeg.org/legal.html
