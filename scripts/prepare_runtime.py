"""Developer-only tool: stage standalone engines; never invoked by the application."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import urllib.request
import zipfile
import io

ROOT = Path(__file__).resolve().parents[1]
def fetch(url):
    req = urllib.request.Request(url, headers={'User-Agent': 'LocalVideo-build'})
    with urllib.request.urlopen(req, timeout=120) as response:
        return response.read()

def asset(repo, version, name):
    release = json.loads(fetch(f'https://api.github.com/repos/{repo}/releases/tags/{version}'))
    item = next(a for a in release['assets'] if a['name'] == name)
    blob = fetch(item['browser_download_url'])
    digest = item.get('digest')
    if not digest or digest != 'sha256:' + hashlib.sha256(blob).hexdigest():
        raise RuntimeError(f'Missing or invalid upstream SHA256 for {name}')
    return blob, item['browser_download_url']

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--platform', choices=['windows','macos','linux'], required=True)
    parser.add_argument('--arch', choices=['x64','arm64'], default='x64')
    parser.add_argument('--yt-version', default='2026.08.19')
    parser.add_argument('--deno-version', default='v2.9.7')
    parser.add_argument('--ffmpeg-dir', type=Path, required=True,
                        help='Reviewed standalone FFmpeg/FFprobe binaries (no shared dependencies)')
    parser.add_argument('--ffmpeg-notices', type=Path, required=True,
                        help='Directory of licenses, build configuration, source links/source offer')
    args = parser.parse_args()
    dest = ROOT / 'runtime' / args.platform
    dest.mkdir(parents=True, exist_ok=True)
    ext = '.exe' if args.platform == 'windows' else ''
    yt = {'windows': 'yt-dlp.exe' if args.arch=='x64' else 'yt-dlp_arm64.exe',
          'macos':'yt-dlp_macos',
          'linux':'yt-dlp_linux' if args.arch=='x64' else 'yt-dlp_linux_aarch64'}[args.platform]
    deno_arch = 'x86_64' if args.arch=='x64' else 'aarch64'
    deno_os = {'windows':'pc-windows-msvc','macos':'apple-darwin','linux':'unknown-linux-gnu'}[args.platform]
    manifest = {'platform':args.platform,'arch':args.arch,'sources':{}}
    blob, url = asset('yt-dlp/yt-dlp', args.yt_version, yt)
    (dest / f'yt-dlp{ext}').write_bytes(blob)
    manifest['sources']['yt-dlp'] = url
    blob, url = asset('denoland/deno', args.deno_version, f'deno-{deno_arch}-{deno_os}.zip')
    with zipfile.ZipFile(io.BytesIO(blob)) as archive:
        (dest / f'deno{ext}').write_bytes(archive.read(f'deno{ext}'))
    manifest['sources']['deno'] = url
    for name in ['ffmpeg','ffprobe']:
        shutil.copy2(args.ffmpeg_dir / f'{name}{ext}', dest / f'{name}{ext}')
    shutil.copytree(args.ffmpeg_notices, dest / 'licenses', dirs_exist_ok=True)
    for repo, version, name in [('yt-dlp/yt-dlp', args.yt_version, 'LICENSE'),
                                ('yt-dlp/yt-dlp', args.yt_version, 'THIRD_PARTY_LICENSES.txt'),
                                ('denoland/deno', args.deno_version, 'LICENSE.md')]:
        (dest / 'licenses' / (repo.split('/')[-1]+'-'+name)).write_bytes(
            fetch(f'https://raw.githubusercontent.com/{repo}/{version}/{name}'))
    for name in ['yt-dlp','deno','ffmpeg','ffprobe']:
        executable = dest / f'{name}{ext}'
        if os.name!='nt': executable.chmod(0o755)
        output = subprocess.check_output([str(executable), '--version' if name in ['yt-dlp','deno'] else '-version'], text=True)
        manifest[name] = {'sha256':hashlib.sha256(executable.read_bytes()).hexdigest(),
                          'version':output.splitlines()[0]}
    (dest / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print(dest)

if __name__=='__main__': main()
