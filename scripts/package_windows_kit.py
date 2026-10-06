"""Make a transferable Windows source kit, including all four Windows tools."""
import hashlib
import json
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    version = re.search(r'^version: ([^+\s]+)', (ROOT / 'pubspec.yaml').read_text(), re.M)[1]
    runtime = ROOT / 'runtime/windows'
    manifest = json.loads((runtime / 'manifest.json').read_text())
    for name in ('yt-dlp', 'ffmpeg', 'ffprobe', 'deno'):
        if hashlib.sha256((runtime / f'{name}.exe').read_bytes()).hexdigest() != manifest[name]['sha256']:
            raise RuntimeError(f'Runtime hash mismatch: {name}')
    sources = ['lib', 'assets', 'test', 'docs', 'windows', 'macos', 'linux', 'scripts', 'packaging',
               'runtime/windows', 'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml',
               'LICENSE', 'THIRD_PARTY_NOTICES.md', 'CHANGELOG.md', 'build_windows.cmd',
               'WINDOWS-BUILD.fa.md', '.metadata', *[p.name for p in ROOT.glob('README*.md')]]
    dest = ROOT / 'dist' / f'Vidora-Windows-BuildKit-x64-{version}.zip'
    dest.parent.mkdir(exist_ok=True)
    prefix = f'Vidora-Windows-BuildKit-{version}'
    with zipfile.ZipFile(dest, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for source in sources:
            path = ROOT / source
            paths = sorted(path.rglob('*')) if path.is_dir() else [path]
            for item in paths:
                if not item.is_file() or any(part in ('ephemeral', '__pycache__', '.DS_Store') for part in item.parts):
                    continue
                archive.write(item, f'{prefix}/{item.relative_to(ROOT).as_posix()}')
    with zipfile.ZipFile(dest) as archive:
        error = archive.testzip()
        if error:
            raise RuntimeError(f'Archive CRC mismatch: {error}')
    print(dest)


if __name__ == '__main__':
    main()
