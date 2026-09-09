#!/usr/bin/env python3
"""Stage and verify a local app, then preserve the previous bundle before swapping."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid
import sys


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument('binary', type=Path)
    args = parser.parse_args()
    output_worker = args.binary.with_name("circlr-output-worker")
    if not output_worker.is_file():
        raise ValueError("Build circlr-output-worker beside the app binary before packaging")
    subprocess.run([sys.executable, str(root / 'scripts/build-agent-kit.py')], check=True)
    bundle_info = plistlib.loads((root / 'Resources/Info.plist').read_bytes())
    icon_name = bundle_info['CFBundleIconFile']
    if not isinstance(icon_name, str) or Path(icon_name).name != icon_name:
        raise ValueError('CFBundleIconFile must name a bundled icon')
    icon_name = icon_name if icon_name.endswith('.icns') else icon_name + '.icns'
    icon_source = root / 'Resources' / icon_name
    if not icon_source.is_file() or icon_source.stat().st_size < 8:
        raise ValueError('Run scripts/build-icon.py before packaging')
    catalog_source = root / 'Resources/Assets.car'
    if bundle_info.get('CFBundleIconName') != 'Circlr' or not catalog_source.is_file():
        raise ValueError('Run scripts/build-icon.py to compile the Circlr icon catalog')
    dist = root / 'dist'
    dist.mkdir(exist_ok=True)
    app = dist / '써클러.app'
    stage = Path(tempfile.mkdtemp(prefix='.circlr-stage-', suffix='.app', dir=dist))
    archive = None
    try:
        (stage / 'Contents/MacOS').mkdir(parents=True)
        (stage / 'Contents/Resources').mkdir()
        shutil.copy2(args.binary, stage / 'Contents/MacOS/circlr')
        shutil.copy2(output_worker, stage / 'Contents/MacOS/circlr-output-worker')
        shutil.copy2(root / 'Resources/Info.plist', stage / 'Contents/Info.plist')
        shutil.copy2(icon_source, stage / 'Contents/Resources' / icon_name)
        shutil.copy2(catalog_source, stage / 'Contents/Resources/Assets.car')
        kit_source = root / 'Resources/Codex'
        kit_target = stage / 'Contents/Resources/Codex'
        shutil.copytree(kit_source, kit_target, ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
        manifest = json.loads((kit_target / 'manifest.json').read_text())
        if manifest['version'] != bundle_info['CFBundleShortVersionString']:
            raise ValueError('Agent kit version differs from app')
        for name, sha in manifest['files'].items():
            if hashlib.sha256((kit_target / name).read_bytes()).hexdigest() != sha:
                raise ValueError('Bundled agent kit differs from source: ' + name)
        if (stage / 'Contents/Resources' / icon_name).read_bytes() != icon_source.read_bytes():
            raise ValueError('Bundled icon differs from source')
        if (stage / 'Contents/Resources/Assets.car').read_bytes() != catalog_source.read_bytes():
            raise ValueError('Bundled icon catalog differs from source')
        subprocess.run(['codesign', '--force', '--sign', '-', str(stage / 'Contents/MacOS/circlr-output-worker')], check=True)
        subprocess.run(['codesign', '--force', '--sign', '-', str(stage)], check=True)
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(stage)], check=True)
        if app.exists():
            info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
            version = str(info['CFBundleShortVersionString'])
            assert version and all(c.isascii() and (c.isalnum() or c in '.-') for c in version)
            archives = dist / 'archive'
            archives.mkdir(exist_ok=True)
            archive = archives / ('써클러-' + version + '.app')
            if archive.exists():
                archive = archives / ('써클러-' + version + '-' + str(uuid.uuid4())[:8] + '.app')
            app.rename(archive)
        try:
            stage.rename(app)
        except Exception:
            if archive is not None and not app.exists():
                archive.rename(app)
            raise
        print(app)
        if archive is not None:
            print('보관:', archive)
    finally:
        if stage.exists():
            shutil.rmtree(stage)


if __name__ == '__main__':
    main()
