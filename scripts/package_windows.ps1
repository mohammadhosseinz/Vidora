param([string]$Iscc = 'ISCC.exe')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot
try {
  flutter build windows --release --no-pub
  if ($LASTEXITCODE -ne 0) { throw 'Flutter build failed' }
  $bundle = Join-Path $projectRoot 'build/windows/x64/runner/Release'
  foreach ($name in @('yt-dlp','ffmpeg','ffprobe','deno')) {
    if (!(Test-Path "runtime/windows/$name.exe")) { throw "Missing bundled $name" }
  }
  Copy-Item LICENSE,THIRD_PARTY_NOTICES.md,README*.md $bundle -Force
  New-Item -ItemType Directory -Force "$bundle/tools" | Out-Null
  Copy-Item assets/support.json "$bundle/support.json" -Force
  Copy-Item runtime/windows/* "$bundle/tools" -Recurse -Force
  Copy-Item assets/fonts/*OFL.txt "$bundle/tools/licenses" -Force
  # Flutter release must include MSVC runtime; no manual runtime installation.
  foreach ($dll in @('msvcp140.dll','vcruntime140.dll','vcruntime140_1.dll')) {
    Copy-Item (Join-Path $env:WINDIR "System32/$dll") $bundle -Force
  }
  New-Item -ItemType Directory -Force dist | Out-Null
  Compress-Archive -Path "$bundle/*" -DestinationPath dist/Vidora-Windows-x64-0.1.7.zip -Force
  & $Iscc packaging/windows.iss
  if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed' }
} finally { Pop-Location }
