param([string]$Iscc = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot
try {
  if (!(Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Install Flutter 3.41.2 and add its bin folder to PATH. See WINDOWS-BUILD.fa.md.'
  }
  if (!$Iscc) {
    $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($command) { $Iscc = $command.Source }
    else {
      foreach ($directory in @(${env:ProgramFiles(x86)}, $env:ProgramFiles, $env:LOCALAPPDATA)) {
        if (!$directory) { continue }
        foreach ($relative in @('Inno Setup 6/ISCC.exe', 'Inno Setup 7/ISCC.exe', 'Programs/Inno Setup 6/ISCC.exe')) {
          $candidate = Join-Path $directory $relative
          if (Test-Path $candidate) { $Iscc = $candidate; break }
        }
        if ($Iscc) { break }
      }
    }
  }
  if (!$Iscc -or !(Test-Path $Iscc)) { throw 'Install Inno Setup, or pass -Iscc C:/path/to/ISCC.exe.' }
  $versionMatch = [regex]::Match((Get-Content pubspec.yaml -Raw), '(?m)^version: ([^+\s]+)\+\d+')
  if (!$versionMatch.Success) { throw 'Missing version in pubspec.yaml' }
  $version = $versionMatch.Groups[1].Value
  $manifest = Get-Content runtime/windows/manifest.json -Raw | ConvertFrom-Json
  foreach ($name in @('yt-dlp','ffmpeg','ffprobe','deno')) {
    $executable = "runtime/windows/$name.exe"
    if (!(Test-Path $executable)) { throw "Missing bundled $name. Use the complete Windows build kit." }
    if ((Get-FileHash $executable -Algorithm SHA256).Hash.ToLowerInvariant() -ne $manifest.$name.sha256) {
      throw "Checksum mismatch for $name"
    }
    & $executable $(if ($name -in @('yt-dlp','deno')) { '--version' } else { '-version' })
    if ($LASTEXITCODE -ne 0) { throw "$name cannot run on this computer" }
  }
  flutter pub get --enforce-lockfile
  if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed' }
  flutter analyze
  if ($LASTEXITCODE -ne 0) { throw 'Analysis failed' }
  flutter test
  if ($LASTEXITCODE -ne 0) { throw 'Tests failed' }
  flutter build windows --release --no-pub
  if ($LASTEXITCODE -ne 0) { throw 'Flutter build failed' }
  $bundle = Join-Path $projectRoot 'build/windows/x64/runner/Release'
  Copy-Item LICENSE,THIRD_PARTY_NOTICES.md,README*.md $bundle -Force
  New-Item -ItemType Directory -Force "$bundle/tools/licenses" | Out-Null
  Copy-Item assets/support.json "$bundle/support.json" -Force
  Copy-Item runtime/windows/* "$bundle/tools" -Recurse -Force
  New-Item -ItemType Directory -Force "$bundle/tools/plugins" | Out-Null
  Copy-Item packaging/yt-dlp-plugins/* "$bundle/tools/plugins" -Recurse -Force
  Copy-Item assets/fonts/*OFL.txt "$bundle/tools/licenses" -Force
  # Ship the redistributable DLLs from the installed Visual Studio toolchain.
  $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
  if (!(Test-Path $vswhere)) { throw 'Visual Studio C++ Desktop build tools are required.' }
  $vsPath = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  if (!$vsPath) { throw 'Visual Studio C++ Desktop build tools were not found.' }
  $redist = Get-ChildItem (Join-Path $vsPath 'VC/Redist/MSVC/*/x64/Microsoft.VC*.CRT') -Directory |
    Sort-Object FullName -Descending | Select-Object -First 1
  if (!$redist) { throw 'MSVC redistributable files were not found in Visual Studio.' }
  foreach ($dll in @('msvcp140.dll','vcruntime140.dll','vcruntime140_1.dll')) {
    Copy-Item (Join-Path $redist.FullName $dll) $bundle -Force
  }
  New-Item -ItemType Directory -Force dist | Out-Null
  Compress-Archive -Path "$bundle/*" -DestinationPath "dist/Vidora-Windows-x64-$version.zip" -Force
  & $Iscc "/DAppVersion=$version" packaging/windows.iss
  if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed' }
  Write-Host "Ready: dist/Vidora-Setup-Windows-x64-$version.exe"
} finally { Pop-Location }
