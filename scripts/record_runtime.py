"""Record the hashes and versions of a reviewed runtime directory."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
root = Path(__file__).resolve().parents[1]
target = sys.argv[1]
directory = root / 'runtime' / target
ext = '.exe' if target=='windows' else ''
result = {'platform':target,'arch':'x64','sources':{
    'yt-dlp':'https://github.com/yt-dlp/yt-dlp/releases/tag/2026.08.19',
    'deno':'https://github.com/denoland/deno/releases/tag/v2.9.7',
    'ffmpeg':'https://www.gyan.dev/ffmpeg/builds/',
    'ffmpegSource':'https://github.com/FFmpeg/FFmpeg/commit/b08d7969c5'}}
for name in ['yt-dlp','ffmpeg','ffprobe','deno']:
    exe = directory / (name+ext)
    digest=hashlib.sha256(exe.read_bytes()).hexdigest()
    if name=='yt-dlp' and target=='windows' and digest!='66674953fe251b89f4d08c5f0e35e0728679bd67ab3d7d05c0562af101dd3e7a':
        raise RuntimeError('yt-dlp does not match upstream release digest')
    result[name]={'sha256':digest,'version':subprocess.check_output([str(exe),'--version' if name in ['yt-dlp','deno'] else '-version'],text=True).splitlines()[0]}
(directory/'manifest.json').write_text(json.dumps(result,indent=2),encoding='utf8')
print(json.dumps(result,indent=2))
