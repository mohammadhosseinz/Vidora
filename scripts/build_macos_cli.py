"""Build the current Swift plugins with Apple's Command Line Tools (no NIB)."""
import json
import os
import platform
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    subprocess.run(args, cwd=ROOT, check=True)


def compile_runner_only(arch):
    app = ROOT / 'build/macos/Build/Products/Release/Vidora.app'
    frameworks = app / 'Contents/Frameworks'
    work = ROOT / 'work/package-build/macos-runner'
    work.mkdir(parents=True, exist_ok=True)
    registry = (ROOT / 'macos/Flutter/GeneratedPluginRegistrant.swift').read_text()
    (work / 'registry.swift').write_text(registry.replace('RegisterGeneratedPlugins', 'RegisterStandalonePlugins'))
    shutil.copy2(ROOT / 'macos/Runner/StandaloneMain.swift', work / 'main.swift')
    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    deployment = plistlib.loads((app / 'Contents/Info.plist').read_bytes())['LSMinimumSystemVersion']
    plugin_links = []
    for framework in frameworks.glob('*.framework'):
        if framework.stem != 'App':
            plugin_links.extend(['-framework', framework.stem])
    run('xcrun', 'swiftc', '-swift-version', '5', '-O', '-sdk', sdk,
        '-target', f'{arch}-apple-macos{deployment}', '-F', str(frameworks),
        '-framework', 'Cocoa', *plugin_links, '-Xlinker', '-rpath',
        '-Xlinker', '@executable_path/../Frameworks', str(work / 'registry.swift'),
        str(work / 'main.swift'), '-o', str(work / 'Vidora'))
    # Replace rather than overwrite a binary which may still be mapped by a running app.
    (work / 'Vidora').replace(app / 'Contents/MacOS/Vidora')


def main():
    flutter = os.environ.get('FLUTTER_BIN', 'flutter')
    arch = os.environ.get('MACOS_ARCH', platform.machine())
    if arch not in ('arm64', 'x86_64'):
        raise ValueError('MACOS_ARCH must be arm64 or x86_64')
    if '--runner-only' in sys.argv:
        compile_runner_only(arch)
        return
    version, build = re.search(r'^version: (\S+)\+(\d+)$',
                              (ROOT / 'pubspec.yaml').read_text(), re.M).groups()
    work = ROOT / 'work/package-build/macos-frameworks'
    run(flutter, 'pub', 'get', '--enforce-lockfile')
    for target in ('release_macos_bundle_flutter_assets', 'release_unpack_macos'):
        run(flutter, 'assemble', '-dTargetPlatform=darwin', '-dTargetFile=lib/main.dart',
            '-dBuildMode=release', f'-dDarwinArchs={arch}', '-dTreeShakeIcons=true',
            '-dTrackWidgetCreation=false', f'--output={work}', target)
    for symbols in work.glob('*.dSYM'):
        shutil.rmtree(symbols)
    app = ROOT / 'build/macos/Build/Products/Release/Vidora.app'
    if app.exists():
        shutil.rmtree(app)
    frameworks = app / 'Contents/Frameworks'
    resources = app / 'Contents/Resources'
    binary = app / 'Contents/MacOS/Vidora'
    frameworks.mkdir(parents=True)
    resources.mkdir(parents=True)
    binary.parent.mkdir(parents=True)
    for name in ('App.framework', 'FlutterMacOS.framework'):
        shutil.copytree(work / name, frameworks / name, symlinks=True)
    info = plistlib.loads((ROOT / 'macos/Runner/Info.plist').read_bytes())
    info.update(CFBundleDevelopmentRegion='en', CFBundleExecutable='Vidora',
                CFBundleIdentifier='com.example.localVideo', CFBundleName='Vidora',
                CFBundleShortVersionString=version, CFBundleVersion=build,
                LSMinimumSystemVersion='11.0' if arch == 'arm64' else '10.15',
                NSHumanReadableCopyright='Copyright © 2026 Zolfaghari',
                CFBundleIconFile='Vidora.icns', NSHighResolutionCapable=True)
    info.pop('NSMainNibFile', None)
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    icons = ROOT / 'work/package-build/Vidora.iconset'
    icons.mkdir(exist_ok=True)
    icon_path = ROOT / 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
    content = json.loads((icon_path / 'Contents.json').read_text())
    for item in content['images']:
        if 'filename' not in item:
            continue
        size = item['size'].split('x')[0]
        suffix = '@2x' if item['scale'] == '2x' else ''
        shutil.copy2(icon_path / item['filename'], icons / f'icon_{size}x{size}{suffix}.png')
    run('iconutil', '-c', 'icns', str(icons), '-o', str(resources / 'Vidora.icns'))
    plugins = json.loads((ROOT / '.flutter-plugins-dependencies').read_text())['plugins']['macos']
    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    deployment = info['LSMinimumSystemVersion']
    common = ['xcrun', 'swiftc', '-swift-version', '5', '-O', '-sdk', sdk,
              '-target', f'{arch}-apple-macos{deployment}', '-F', str(frameworks),
              '-framework', 'FlutterMacOS', '-framework', 'Cocoa',
              '-framework', 'UniformTypeIdentifiers']
    plugin_links = []
    for plugin in plugins:
        plugin_dir = Path(plugin['path']) / 'macos'
        swift = [str(path) for path in plugin_dir.rglob('*.swift')
                 if path.name != 'Package.swift' and 'Tests' not in path.parts]
        name = plugin['name']
        framework = frameworks / f'{name}.framework'
        modules = framework / 'Modules' / f'{name}.swiftmodule'
        modules.mkdir(parents=True)
        (framework / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier':f'org.flutter.plugin.{name.replace("_", "-")}',
            'CFBundleExecutable':name, 'CFBundleName':name,
            'CFBundlePackageType':'FMWK', 'CFBundleVersion':'1',
            'CFBundleShortVersionString':'1.0'}))
        run(*common, '-emit-library', '-emit-module', '-module-name', name,
            '-emit-module-path', str(modules / f'{arch}-apple-macos.swiftmodule'),
            '-Xlinker', '-install_name', '-Xlinker', f'@rpath/{name}.framework/{name}',
            *swift, '-o', str(framework / name))
        plugin_links.extend(['-framework', name])
        for privacy in plugin_dir.rglob('PrivacyInfo.xcprivacy'):
            dest = resources / f"{plugin['name']}.bundle"
            dest.mkdir(exist_ok=True)
            shutil.copy2(privacy, dest / privacy.name)
    registry = (ROOT / 'macos/Flutter/GeneratedPluginRegistrant.swift').read_text()
    registry = registry.replace('RegisterGeneratedPlugins', 'RegisterStandalonePlugins')
    (work / 'registry.swift').write_text(registry)
    # Top-level Swift entry points must be named main.swift.
    shutil.copy2(ROOT / 'macos/Runner/StandaloneMain.swift', work / 'main.swift')
    run(*common, *plugin_links, '-Xlinker', '-rpath',
        '-Xlinker', '@executable_path/../Frameworks',
        str(work / 'registry.swift'), str(work / 'main.swift'), '-o', str(binary))
    print(app)


if __name__ == '__main__':
    main()
